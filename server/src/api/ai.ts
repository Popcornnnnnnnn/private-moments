import type { AiSummary, Device, Prisma, PrismaClient } from "@prisma/client";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";

import { AISummaryProviderError } from "../ai/media-summary.js";
import {
  generateAndSaveMediaSummary,
  serializeAISummary as serializeServiceAISummary,
} from "../ai/media-summary-service.js";
import { authenticateDevice, UnauthorizedError } from "../auth/request-auth.js";
import type { AppConfig } from "../config/app-config.js";
import type { FileLogger } from "../logging/file-logger.js";
import {
  blockWritesDuringMaintenance,
  type MaintenanceModeService,
} from "../maintenance/maintenance-mode.js";
import type { DataPaths } from "../storage/data-dir.js";
import { sendBadRequest, sendNotFound, sendUnauthorized } from "./http-errors.js";

interface AIRouteContext {
  config: AppConfig;
  paths: DataPaths;
  prisma: PrismaClient;
  fileLogger: FileLogger;
  maintenanceMode: MaintenanceModeService;
}

interface SummaryRequestBody {
  postId: string;
  mediaId: string;
  forceRegenerate: boolean;
  aiLanguage: "auto" | "zh" | "en";
}

export async function registerAIRoutes(
  app: FastifyInstance,
  context: AIRouteContext,
): Promise<void> {
  app.post("/api/v1/ai/media-summary", async (request, reply) => {
    const device = await authenticateOrReply(request, reply, context.prisma);
    if (!device) {
      return reply;
    }
    const maintenanceReply = blockWritesDuringMaintenance(reply, context.maintenanceMode);
    if (maintenanceReply) {
      return maintenanceReply;
    }

    const body = parseSummaryRequestBody(request.body, reply);
    if (!body) {
      return reply;
    }

    try {
      const summary = await generateAndSaveMediaSummary(context, {
        postId: body.postId,
        mediaId: body.mediaId,
        requestedByDeviceId: device.id,
        forceRegenerate: body.forceRegenerate,
        aiLanguage: body.aiLanguage,
      });

      return reply.send({
        summary: serializeServiceAISummary(summary),
      });
    } catch (error) {
      if (error instanceof AISummaryProviderError && error.code === "media_not_found") {
        return sendNotFound(reply, "Media not found");
      }

      if (error instanceof AISummaryProviderError && error.code === "unsupported_media") {
        return sendBadRequest(reply, "AI summaries are only available for audio or video media");
      }

      throw error;
    }
  });

  app.delete<{ Params: { summaryId: string } }>(
    "/api/v1/ai/media-summary/:summaryId",
    async (request, reply) => {
      const device = await authenticateOrReply(request, reply, context.prisma);
      if (!device) {
        return reply;
      }
      const maintenanceReply = blockWritesDuringMaintenance(reply, context.maintenanceMode);
      if (maintenanceReply) {
        return maintenanceReply;
      }

      const existing = await context.prisma.aiSummary.findUnique({
        where: {
          id: request.params.summaryId,
        },
      });

      if (!existing) {
        return sendNotFound(reply, "AI summary not found");
      }

      const deletedAt = existing.deletedAt ?? new Date();
      const summary = await context.prisma.$transaction(async (tx) => {
        const deleted = await tx.aiSummary.update({
          where: {
            id: existing.id,
          },
          data: {
            status: "deleted",
            deletedAt,
            errorCode: null,
            errorMessage: null,
            requestedByDeviceId: device.id,
          },
        });

        await emitAISummaryChange(tx, deleted, "ai_summary_deleted");
        return deleted;
      });

      await context.fileLogger.info("ai.summary_deleted", {
        summaryId: summary.id,
        postId: summary.postId,
        mediaId: summary.mediaId,
      });

      return reply.send({
        summary: serializeAISummary(summary),
      });
    },
  );
}

async function authenticateOrReply(
  request: FastifyRequest,
  reply: FastifyReply,
  prisma: PrismaClient,
): Promise<Device | null> {
  try {
    return await authenticateDevice(request, prisma);
  } catch (error) {
    if (error instanceof UnauthorizedError) {
      sendUnauthorized(reply, error.message);
      return null;
    }

    throw error;
  }
}

function parseSummaryRequestBody(
  body: unknown,
  reply: FastifyReply,
): SummaryRequestBody | null {
  if (!isRecord(body)) {
    sendBadRequest(reply, "Request body must be an object");
    return null;
  }

  const postId = getString(body, "postId");
  const mediaId = getString(body, "mediaId");
  if (!postId || !mediaId) {
    sendBadRequest(reply, "postId and mediaId are required");
    return null;
  }

  return {
    postId,
    mediaId,
    forceRegenerate: body.forceRegenerate === true,
    aiLanguage: parseAILanguage(getString(body, "aiLanguage")),
  };
}

function parseAILanguage(value: string | null): "auto" | "zh" | "en" {
  if (value === "zh" || value === "en") {
    return value;
  }

  return "auto";
}

async function emitAISummaryChange(
  tx: Prisma.TransactionClient,
  summary: AiSummary,
  changeType: "ai_summary_updated" | "ai_summary_deleted",
): Promise<void> {
  const change = await tx.serverChange.create({
    data: {
      entityType: "ai_summary",
      entityId: summary.id,
      changeType,
      payloadJson: JSON.stringify(serializeAISummary(summary)),
    },
  });

  await tx.post.update({
    where: {
      id: summary.postId,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

function serializeAISummary(summary: AiSummary): Record<string, unknown> {
  return {
    id: summary.id,
    postId: summary.postId,
    mediaId: summary.mediaId,
    status: summary.status,
    format: summary.format,
    language: summary.language,
    overview: summary.overview,
    keyPoints: parseJsonArray(summary.keyPointsJson),
    sections: parseJsonArray(summary.sectionsJson),
    summaryText: summary.summaryText,
    documentTitle: summary.documentTitle,
    oneLiner: summary.oneLiner,
    documentBlocks: parseJsonArray(summary.documentBlocksJson),
    inputTranscriptLength: summary.inputTranscriptLength,
    inputDurationSeconds: summary.inputDurationSeconds,
    promptVersion: summary.promptVersion,
    provider: summary.provider,
    model: summary.model,
    errorCode: summary.errorCode,
    errorMessage: summary.errorMessage,
    createdAt: summary.createdAt.toISOString(),
    updatedAt: summary.updatedAt.toISOString(),
    deletedAt: summary.deletedAt?.toISOString() ?? null,
  };
}

function parseJsonArray(value: string): unknown[] {
  try {
    const parsed = JSON.parse(value) as unknown;
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function getString(body: Record<string, unknown>, key: string): string | null {
  const value = body[key];
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
