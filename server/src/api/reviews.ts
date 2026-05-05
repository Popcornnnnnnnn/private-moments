import type { PrismaClient, Review, ReviewSetting } from "@prisma/client";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";

import { authenticateDevice, UnauthorizedError } from "../auth/request-auth.js";
import {
  blockWritesDuringMaintenance,
  type MaintenanceModeService,
} from "../maintenance/maintenance-mode.js";
import { validateReviewRange } from "../reviews/review-limits.js";
import type { ReviewService } from "../reviews/review-service.js";
import { sendBadRequest, sendNotFound, sendUnauthorized } from "./http-errors.js";

interface ReviewsRouteContext {
  prisma: PrismaClient;
  reviews: ReviewService;
  maintenanceMode: MaintenanceModeService;
}

export async function registerReviewRoutes(
  app: FastifyInstance,
  context: ReviewsRouteContext,
): Promise<void> {
  app.get("/api/v1/reviews", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }

    const query = parseQuery(request.query);
    const reviews = await context.reviews.listReviews({
      kind: parseReviewKind(query.kind ?? null),
      limit: parseLimit(query.limit),
    });

    return reply.send({
      reviews: reviews.map(serializeReview),
    });
  });

  app.get<{ Params: { reviewId: string } }>("/api/v1/reviews/:reviewId", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }

    const review = await context.reviews.getReview(request.params.reviewId);
    if (!review) {
      return sendNotFound(reply, "Review not found");
    }

    return reply.send({
      review: serializeReview(review),
    });
  });

  app.post("/api/v1/reviews/generate", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }
    const maintenanceReply = blockWritesDuringMaintenance(reply, context.maintenanceMode);
    if (maintenanceReply) {
      return maintenanceReply;
    }

    const body = parseGenerateBody(request.body);
    if (!body.ok) {
      sendBadRequest(reply, body.message);
      return reply;
    }

    const review = await context.reviews.generate(body.input);
    return reply.send({
      review: serializeReview(review),
    });
  });

  app.post<{ Params: { reviewId: string } }>("/api/v1/reviews/:reviewId/regenerate", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }
    const maintenanceReply = blockWritesDuringMaintenance(reply, context.maintenanceMode);
    if (maintenanceReply) {
      return maintenanceReply;
    }

    const review = await context.reviews.regenerate(request.params.reviewId);
    if (!review) {
      return sendNotFound(reply, "Review not found");
    }

    return reply.send({
      review: serializeReview(review),
    });
  });

  app.post<{ Params: { reviewId: string } }>("/api/v1/reviews/:reviewId/feedback", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }
    const body = parseFeedbackBody(request.body, reply);
    if (!body) {
      return reply;
    }

    const review = await context.reviews.getReview(request.params.reviewId);
    if (!review) {
      return sendNotFound(reply, "Review not found");
    }

    await context.reviews.saveFeedback(review.id, body.type, body.note);
    return reply.send({
      ok: true,
    });
  });

  app.post<{ Params: { reviewId: string } }>("/api/v1/reviews/:reviewId/publish", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }
    const maintenanceReply = blockWritesDuringMaintenance(reply, context.maintenanceMode);
    if (maintenanceReply) {
      return maintenanceReply;
    }

    const result = await context.reviews.publishAsMoment(request.params.reviewId);
    if (!result) {
      return sendNotFound(reply, "Ready review not found");
    }

    return reply.send({
      review: serializeReview(result.review),
      postId: result.postId,
    });
  });

  app.get("/api/v1/reviews/settings", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }

    return reply.send({
      settings: serializeReviewSettings(await context.reviews.getSettings()),
    });
  });

  app.put("/api/v1/reviews/settings", async (request, reply) => {
    if (!(await authenticateOrReply(request, reply, context.prisma))) {
      return reply;
    }

    const body = parseSettingsBody(request.body, reply);
    if (!body) {
      return reply;
    }

    const settings = await context.reviews.updateSettings(body);
    return reply.send({
      settings: serializeReviewSettings(settings),
    });
  });
}

async function authenticateOrReply(
  request: FastifyRequest,
  reply: FastifyReply,
  prisma: PrismaClient,
): Promise<boolean> {
  try {
    await authenticateDevice(request, prisma);
    return true;
  } catch (error) {
    if (error instanceof UnauthorizedError) {
      sendUnauthorized(reply, error.message);
      return false;
    }

    throw error;
  }
}

function serializeReview(review: Review): Record<string, unknown> {
  return {
    id: review.id,
    kind: review.kind,
    rangeMode: review.rangeMode,
    rangeStart: review.rangeStart.toISOString(),
    rangeEnd: review.rangeEnd.toISOString(),
    status: review.status,
    trigger: review.trigger,
    content: parseJsonObject(review.contentJson),
    promptVersion: review.promptVersion,
    provider: review.provider,
    model: review.model,
    language: review.language,
    errorCode: review.errorCode,
    errorMessage: review.errorMessage,
    generatedAt: review.generatedAt?.toISOString() ?? null,
    regeneratedFromReviewId: review.regeneratedFromReviewId,
    publishedPostId: review.publishedPostId,
    createdAt: review.createdAt.toISOString(),
    updatedAt: review.updatedAt.toISOString(),
    deletedAt: review.deletedAt?.toISOString() ?? null,
  };
}

function serializeReviewSettings(settings: ReviewSetting): Record<string, unknown> {
  return {
    autoWeeklyEnabled: settings.autoWeeklyEnabled,
    publishWeeklyToMoments: settings.publishWeeklyToMoments,
    lastAutoWeeklyDate: settings.lastAutoWeeklyDate,
    updatedAt: settings.updatedAt.toISOString(),
  };
}

export function parseGenerateBody(body: unknown, now = new Date()): {
  ok: true;
  input: Parameters<ReviewService["generate"]>[0];
} | {
  ok: false;
  message: string;
} {
  if (!isRecord(body)) {
    return {
      ok: true,
      input: {
        kind: "weekly",
        rangeMode: "rolling_7_days",
        rangeStart: new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000),
        rangeEnd: now,
        trigger: "manual",
      },
    };
  }

  const kind = parseReviewKind(getString(body, "kind")) ?? "weekly";
  const rangeMode = parseReviewRangeMode(getString(body, "rangeMode")) ?? "rolling_7_days";
  const rangeEnd = parseDate(getString(body, "rangeEnd")) ?? now;
  const rangeStart = parseDate(getString(body, "rangeStart")) ?? new Date(rangeEnd.getTime() - 7 * 24 * 60 * 60 * 1000);
  const validationError = validateReviewRange(rangeStart, rangeEnd);

  if (validationError) {
    return {
      ok: false,
      message: validationError,
    };
  }

  return {
    ok: true,
    input: {
      kind,
      rangeMode,
      rangeStart,
      rangeEnd,
      trigger: "manual",
    },
  };
}

function parseFeedbackBody(body: unknown, reply: FastifyReply): { type: string; note: string | null } | null {
  if (!isRecord(body)) {
    sendBadRequest(reply, "Request body must be an object");
    return null;
  }

  const type = getString(body, "type");
  if (!type || !["useful", "too_much_inference", "too_dry", "missed_point", "hide_theme"].includes(type)) {
    sendBadRequest(reply, "Unsupported feedback type");
    return null;
  }

  return {
    type,
    note: getString(body, "note"),
  };
}

function parseSettingsBody(
  body: unknown,
  reply: FastifyReply,
): { autoWeeklyEnabled?: boolean; publishWeeklyToMoments?: boolean } | null {
  if (!isRecord(body)) {
    sendBadRequest(reply, "Request body must be an object");
    return null;
  }

  return {
    ...(typeof body.autoWeeklyEnabled === "boolean" ? { autoWeeklyEnabled: body.autoWeeklyEnabled } : {}),
    ...(typeof body.publishWeeklyToMoments === "boolean" ? { publishWeeklyToMoments: body.publishWeeklyToMoments } : {}),
  };
}

function parseReviewKind(value: string | null): "weekly" | "monthly" | "custom" | undefined {
  if (value === "weekly" || value === "monthly" || value === "custom") {
    return value;
  }

  return undefined;
}

function parseReviewRangeMode(value: string | null): "rolling_7_days" | "calendar_week" | "calendar_month" | "custom" | undefined {
  if (value === "rolling_7_days" || value === "calendar_week" || value === "calendar_month" || value === "custom") {
    return value;
  }

  return undefined;
}

function parseLimit(value: string | undefined): number | undefined {
  if (!value) {
    return undefined;
  }

  const parsed = Number(value);
  return Number.isInteger(parsed) ? parsed : undefined;
}

function parseDate(value: string | null): Date | null {
  if (!value) {
    return null;
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function parseQuery(query: unknown): Record<string, string | undefined> {
  if (!isRecord(query)) {
    return {};
  }

  const parsed: Record<string, string | undefined> = {};
  for (const [key, value] of Object.entries(query)) {
    parsed[key] = typeof value === "string" ? value : undefined;
  }
  return parsed;
}

function parseJsonObject(value: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(value) as unknown;
    return isRecord(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

function getString(record: Record<string, unknown>, key: string): string | null {
  const value = record[key];
  return typeof value === "string" ? value.trim() : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
