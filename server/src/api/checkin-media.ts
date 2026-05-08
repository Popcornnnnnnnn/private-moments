import { createReadStream } from "node:fs";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";

import type { PrismaClient } from "@prisma/client";
import type { FastifyInstance, FastifyReply } from "fastify";

import { authenticateDevice, UnauthorizedError } from "../auth/request-auth.js";
import type { FileLogger } from "../logging/file-logger.js";
import {
  blockWritesDuringMaintenance,
  type MaintenanceModeService,
} from "../maintenance/maintenance-mode.js";
import type { DataPaths } from "../storage/data-dir.js";
import {
  extensionForCheckInMediaMimeType,
  parseCheckInMediaUploadFields,
  relativeCheckInMediaPath,
  type CheckInMediaUploadFields as UploadFields,
} from "./checkin-media-helpers.js";
import { sendBadRequest, sendNotFound, sendUnauthorized } from "./http-errors.js";
import {
  contentTypeForMediaPath,
  mediaUploadErrorCode,
  parseMediaIds,
  parseMediaVariant,
} from "./media-helpers.js";
import {
  fileExists,
  isPathInside,
  parseContentLength,
  writeUploadedFile,
} from "./upload-helpers.js";

const UPLOAD_STREAM_TIMEOUT_MS = 120_000;

interface CheckInMediaRouteContext {
  prisma: PrismaClient;
  paths: DataPaths;
  fileLogger: FileLogger;
  maintenanceMode: MaintenanceModeService;
}

export async function registerCheckInMediaRoutes(
  app: FastifyInstance,
  context: CheckInMediaRouteContext,
): Promise<void> {
  app.post<{ Body: { mediaIds?: unknown; variant?: unknown } }>(
    "/api/v1/checkin-media/batch-download",
    async (request, reply) => {
      try {
        await authenticateDevice(request, context.prisma);
      } catch (error) {
        if (error instanceof UnauthorizedError) {
          return sendUnauthorized(reply, error.message);
        }

        throw error;
      }

      const mediaIds = parseMediaIds(request.body?.mediaIds);
      const variant = parseMediaVariant(
        typeof request.body?.variant === "string" ? request.body.variant : "compressed",
      );
      if (mediaIds.length === 0) {
        return sendBadRequest(reply, "mediaIds must contain at least one id");
      }
      if (variant !== "compressed") {
        return sendBadRequest(reply, "check-in media currently supports compressed image downloads only");
      }

      const downloadedMedia = [];
      for (const mediaId of mediaIds) {
        const media = await context.prisma.checkInMedia.findUnique({
          where: {
            id: mediaId,
          },
        });
        if (!media || media.deletedAt || !media.compressedPath) {
          continue;
        }

        const absolutePath = path.join(context.paths.dataDir, media.compressedPath);
        if (!isPathInside(context.paths.dataDir, absolutePath) || !(await fileExists(absolutePath))) {
          continue;
        }

        const data = await readFile(absolutePath);
        downloadedMedia.push({
          id: media.id,
          variant,
          contentType: contentTypeForMediaPath(media.compressedPath),
          fileName: path.basename(media.compressedPath),
          base64: data.toString("base64"),
        });
      }

      await context.fileLogger.info("checkin_media.batch_download", {
        requestedCount: mediaIds.length,
        returnedCount: downloadedMedia.length,
        variant,
      });

      return reply.send({
        media: downloadedMedia,
      });
    },
  );

  app.get<{ Params: { mediaId: string } }>("/api/v1/checkin-media/:mediaId", async (request, reply) => {
    try {
      await authenticateDevice(request, context.prisma);
    } catch (error) {
      if (error instanceof UnauthorizedError) {
        return sendUnauthorized(reply, error.message);
      }

      throw error;
    }

    const media = await context.prisma.checkInMedia.findUnique({
      where: {
        id: request.params.mediaId,
      },
    });

    if (!media || media.deletedAt || !media.compressedPath) {
      return sendNotFound(reply, "Check-in media not found");
    }

    const absolutePath = path.join(context.paths.dataDir, media.compressedPath);
    if (!isPathInside(context.paths.dataDir, absolutePath) || !(await fileExists(absolutePath))) {
      return sendNotFound(reply, "Check-in media file not found");
    }

    const fileStats = await stat(absolutePath);
    reply.header("Content-Type", contentTypeForMediaPath(media.compressedPath));
    reply.header("Content-Length", String(fileStats.size));
    reply.header("Connection", "close");
    if (fileStats.size <= 1_000_000) {
      return reply.send(await readFile(absolutePath));
    }

    return reply.send(createReadStream(absolutePath));
  });

  app.post("/api/v1/checkin-media/upload", async (request, reply) => {
    try {
      await authenticateDevice(request, context.prisma);
    } catch (error) {
      if (error instanceof UnauthorizedError) {
        return sendUnauthorized(reply, error.message);
      }

      throw error;
    }
    const maintenanceReply = blockWritesDuringMaintenance(reply, context.maintenanceMode);
    if (maintenanceReply) {
      return maintenanceReply;
    }

    const file = await request.file();
    if (!file) {
      return sendBadRequest(reply, "multipart file is required");
    }

    const fields = parseUploadFields(file.fields, reply);
    if (!fields) {
      file.file.resume();
      return reply;
    }

    if (!file.mimetype.startsWith("image/")) {
      file.file.resume();
      return sendBadRequest(reply, "Check-in media currently supports image uploads only");
    }

    const entry = await context.prisma.checkInEntry.findUnique({
      where: {
        id: fields.entryId,
      },
      include: {
        item: true,
      },
    });

    if (!entry || entry.deletedAt || entry.item.deletedAt) {
      file.file.resume();
      return sendNotFound(reply, "Check-in entry not found");
    }

    const existing = await context.prisma.checkInMedia.findUnique({
      where: {
        id: fields.mediaId,
      },
    });
    if (existing && existing.entryId !== fields.entryId) {
      file.file.resume();
      return sendBadRequest(reply, "mediaId belongs to another check-in entry");
    }

    const extension = extensionForCheckInMediaMimeType(file.mimetype, file.filename);
    const relativePath = relativeCheckInMediaPath(fields.mediaId, extension);
    const absolutePath = path.join(context.paths.dataDir, relativePath);
    const uploadStartedAt = Date.now();

    await context.fileLogger.info("checkin_media.upload_started", {
      mediaId: fields.mediaId,
      entryId: fields.entryId,
      kind: fields.kind,
      variant: fields.variant,
      mimeType: file.mimetype,
      expectedBytes: parseContentLength(request.headers["content-length"]),
    });

    try {
      const writeResult = await writeUploadedFile(file, absolutePath, {
        timeoutMs: UPLOAD_STREAM_TIMEOUT_MS,
        timeoutMessage: "Check-in media upload timed out",
      });
      const media = await upsertCheckInMediaRecord(context.prisma, fields, relativePath, writeResult);

      await context.fileLogger.info("checkin_media.upload_completed", {
        mediaId: media.id,
        entryId: media.entryId,
        kind: media.kind,
        variant: fields.variant,
        status: media.status,
        sizeBytes: writeResult.sizeBytes,
        elapsedMs: Date.now() - uploadStartedAt,
      });

      return reply.send({
        media: {
          id: media.id,
          entryId: media.entryId,
          variant: fields.variant,
          status: media.status,
          path: relativePath,
          sizeBytes: writeResult.sizeBytes,
          checksum: writeResult.checksum,
        },
      });
    } catch (error) {
      await context.fileLogger.warn("checkin_media.upload_failed", {
        mediaId: fields.mediaId,
        entryId: fields.entryId,
        kind: fields.kind,
        variant: fields.variant,
        errorCode: mediaUploadErrorCode(error),
        message: error instanceof Error ? error.message : String(error),
        elapsedMs: Date.now() - uploadStartedAt,
      });
      throw error;
    }
  });
}

async function upsertCheckInMediaRecord(
  prisma: PrismaClient,
  fields: UploadFields,
  relativePath: string,
  writeResult: { sizeBytes: number; checksum: string },
) {
  return prisma.$transaction(async (tx) => {
    const media = await tx.checkInMedia.upsert({
      where: {
        id: fields.mediaId,
      },
      create: {
        id: fields.mediaId,
        entryId: fields.entryId,
        kind: fields.kind,
        status: "uploaded",
        compressedPath: relativePath,
        compressedSizeBytes: writeResult.sizeBytes,
        mimeType: fields.mimeType,
        sortOrder: fields.sortOrder,
        checksum: writeResult.checksum,
      },
      update: {
        kind: fields.kind,
        status: "uploaded",
        compressedPath: relativePath,
        compressedSizeBytes: writeResult.sizeBytes,
        mimeType: fields.mimeType,
        sortOrder: fields.sortOrder,
        checksum: writeResult.checksum,
        deletedAt: null,
      },
    });

    const change = await tx.serverChange.create({
      data: {
        entityType: "checkin_media",
        entityId: media.id,
        changeType: "checkin_media_uploaded",
        payloadJson: JSON.stringify({
          id: media.id,
          entryId: media.entryId,
          kind: media.kind,
          status: media.status,
          variant: fields.variant,
          path: relativePath,
          mimeType: media.mimeType,
          sortOrder: media.sortOrder,
          checksum: media.checksum,
          compressedSizeBytes: media.compressedSizeBytes,
        }),
      },
    });

    await tx.checkInEntry.update({
      where: {
        id: fields.entryId,
      },
      data: {
        serverVersion: change.version,
      },
    });

    return media;
  });
}

function parseUploadFields(
  fields: Parameters<typeof parseCheckInMediaUploadFields>[0],
  reply: FastifyReply,
): UploadFields | null {
  const parsed = parseCheckInMediaUploadFields(fields);
  if (!parsed.ok) {
    sendBadRequest(reply, parsed.message);
    return null;
  }

  return parsed.fields;
}
