import { readdir, readFile, unlink } from "node:fs/promises";
import path from "node:path";

import type { Device, Media, Post, Prisma, PrismaClient } from "@prisma/client";
import type { FastifyInstance, FastifyReply } from "fastify";

import { authenticateDevice, UnauthorizedError } from "../auth/request-auth.js";
import { SCHEMA_VERSION, SERVER_VERSION } from "../config/app-config.js";
import type { FileLogger } from "../logging/file-logger.js";
import type { DataPaths } from "../storage/data-dir.js";
import { collectServerStorageStats } from "../storage/stats.js";
import { sendBadRequest, sendNotFound, sendUnauthorized } from "./http-errors.js";

const DEFAULT_LOG_LIMIT = 100;
const MAX_LOG_LIMIT = 500;
const DEFAULT_POST_LIMIT = 50;
const MAX_POST_LIMIT = 100;
const MAX_SEARCH_LIMIT = 100;

type DeletedFilter = "active" | "deleted" | "all";

type AdminPost = Post & {
  createdByDevice: Device | null;
  updatedByDevice: Device | null;
  media: Media[];
};

interface AdminRouteContext {
  prisma: PrismaClient;
  paths: DataPaths;
  fileLogger: FileLogger;
}

interface TimelineCursor {
  occurredAt: string;
  id: string;
}

export async function registerAdminRoutes(
  app: FastifyInstance,
  context: AdminRouteContext,
): Promise<void> {
  app.get("/api/v1/admin/posts", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const query = parseQuery(request.query);
    const deleted = parseDeletedFilter(query.deleted);
    if (!deleted) {
      return sendBadRequest(reply, "deleted must be one of: active, deleted, all");
    }

    const q = query.q?.trim();
    const limit = parsePostLimit(query.limit, q ? MAX_SEARCH_LIMIT : MAX_POST_LIMIT);
    if (limit === null) {
      return sendBadRequest(reply, "limit must be an integer between 1 and 100");
    }

    const cursor = q ? null : parseCursor(query.cursor);
    if (!q && query.cursor && !cursor) {
      return sendBadRequest(reply, "cursor is invalid");
    }

    const where = postWhere({
      deleted,
      deviceId: query.deviceId,
      q,
      cursor,
    });

    const posts = await context.prisma.post.findMany({
      where,
      orderBy: [
        {
          occurredAt: "desc",
        },
        {
          id: "desc",
        },
      ],
      take: q ? Math.min(limit, MAX_SEARCH_LIMIT) : limit,
      include: adminPostInclude,
    });

    return reply.send({
      posts: posts.map(serializeAdminPost),
      nextCursor: !q && posts.length === limit ? encodeCursor(posts[posts.length - 1]!) : null,
      searchLimited: Boolean(q),
    });
  });

  app.get<{ Params: { postId: string } }>(
    "/api/v1/admin/posts/:postId",
    async (request, reply) => {
      const authenticated = await authenticateOrReply(request, reply, context.prisma);
      if (!authenticated) {
        return reply;
      }

      const post = await context.prisma.post.findUnique({
        where: {
          id: request.params.postId,
        },
        include: adminPostInclude,
      });

      if (!post) {
        return sendNotFound(reply, "Post not found");
      }

      return reply.send({
        post: serializeAdminPost(post),
      });
    },
  );

  app.delete<{ Params: { postId: string } }>(
    "/api/v1/admin/posts/:postId",
    async (request, reply) => {
      const adminDevice = await authenticateOrReply(request, reply, context.prisma);
      if (!adminDevice) {
        return reply;
      }

      const existing = await context.prisma.post.findUnique({
        where: {
          id: request.params.postId,
        },
      });

      if (!existing) {
        return sendNotFound(reply, "Post not found");
      }

      if (!existing.deletedAt) {
        await softDeletePost(context.prisma, request.params.postId, adminDevice.id);
        await context.fileLogger.info("admin.post_soft_deleted", {
          postId: request.params.postId,
          adminDeviceId: adminDevice.id,
        });
      }

      const post = await context.prisma.post.findUnique({
        where: {
          id: request.params.postId,
        },
        include: adminPostInclude,
      });

      return reply.send({
        post: post ? serializeAdminPost(post) : null,
      });
    },
  );

  app.get<{ Params: { deviceId: string } }>(
    "/api/v1/admin/devices/:deviceId/clean-posts/preview",
    async (request, reply) => {
      const authenticated = await authenticateOrReply(request, reply, context.prisma);
      if (!authenticated) {
        return reply;
      }

      const device = await context.prisma.device.findUnique({
        where: {
          id: request.params.deviceId,
        },
      });

      if (!device) {
        return sendNotFound(reply, "Device not found");
      }

      const candidateCount = await context.prisma.post.count({
        where: {
          createdByDeviceId: device.id,
        },
      });

      return reply.send({
        device: serializeDevice(device),
        candidateCount,
      });
    },
  );

  app.post<{ Params: { deviceId: string }; Body: unknown }>(
    "/api/v1/admin/devices/:deviceId/clean-posts",
    async (request, reply) => {
      const adminDevice = await authenticateOrReply(request, reply, context.prisma);
      if (!adminDevice) {
        return reply;
      }

      const body = parseBody(request.body);
      const confirmDeviceName = body.confirmDeviceName?.trim();

      const device = await context.prisma.device.findUnique({
        where: {
          id: request.params.deviceId,
        },
      });

      if (!device) {
        return sendNotFound(reply, "Device not found");
      }

      if (confirmDeviceName !== device.name) {
        return sendBadRequest(reply, "confirmDeviceName must match the device name");
      }

      const posts = await context.prisma.post.findMany({
        where: {
          createdByDeviceId: device.id,
        },
        include: {
          media: true,
        },
      });

      const deletedAt = new Date();
      const postIds = posts.map((post) => post.id);
      const mediaPaths = uniqueMediaPaths(posts.flatMap((post) => post.media));

      if (postIds.length > 0) {
        await context.prisma.$transaction(async (tx) => {
          for (const post of posts) {
            await tx.serverChange.create({
              data: {
                entityType: "post",
                entityId: post.id,
                changeType: "post_deleted",
                payloadJson: JSON.stringify({
                  id: post.id,
                  deletedAt: deletedAt.toISOString(),
                  cleanup: true,
                }),
              },
            });
          }

          await tx.post.deleteMany({
            where: {
              id: {
                in: postIds,
              },
            },
          });
        });
      }

      const mediaCleanup = await deleteMediaFiles(context.paths.dataDir, mediaPaths);
      await context.fileLogger.warn("admin.device_posts_cleaned", {
        deviceId: device.id,
        deviceName: device.name,
        adminDeviceId: adminDevice.id,
        postCount: postIds.length,
        deletedMediaFiles: mediaCleanup.deleted,
        failedMediaFiles: mediaCleanup.failed,
      });

      return reply.send({
        device: serializeDevice(device),
        deletedPosts: postIds.length,
        deletedMediaFiles: mediaCleanup.deleted,
        failedMediaFiles: mediaCleanup.failed,
      });
    },
  );

  app.get("/api/v1/admin/status", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const [
      activeDevices,
      revokedDevices,
      posts,
      deletedPosts,
      media,
      storage,
      aiSummaries,
      serverChangeVersion,
    ] =
      await Promise.all([
        context.prisma.device.count({
          where: {
            revokedAt: null,
          },
        }),
        context.prisma.device.count({
          where: {
            revokedAt: {
              not: null,
            },
          },
        }),
        context.prisma.post.count({
          where: {
            deletedAt: null,
          },
        }),
        context.prisma.post.count({
          where: {
            deletedAt: {
              not: null,
            },
          },
        }),
        context.prisma.media.count(),
        collectServerStorageStats(context.paths),
        collectAISummaryDiagnostics(context.prisma),
        latestServerChangeVersion(context.prisma),
      ]);

    return reply.send({
      serverVersion: SERVER_VERSION,
      schemaVersion: SCHEMA_VERSION,
      dataDir: context.paths.dataDir,
      uptimeSeconds: Math.round(process.uptime()),
      counts: {
        activeDevices,
        revokedDevices,
        posts,
        deletedPosts,
        media,
      },
      storage,
      aiSummaries,
      sync: {
        latestServerChangeVersion: serverChangeVersion,
      },
    });
  });

  app.get("/api/v1/admin/logs", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const query = parseQuery(request.query);
    const limit = parseLimit(query.limit);
    if (limit === null) {
      return sendBadRequest(reply, "limit must be an integer between 1 and 500");
    }

    return reply.send({
      logs: await readRecentLogs(context.paths.logsDir, limit),
    });
  });
}

async function collectAISummaryDiagnostics(prisma: PrismaClient): Promise<Record<string, unknown>> {
  const [total, transcribing, summarizing, ready, failed, deleted, recent] = await Promise.all([
    prisma.aiSummary.count(),
    prisma.aiSummary.count({ where: { status: "transcribing", deletedAt: null } }),
    prisma.aiSummary.count({ where: { status: "summarizing", deletedAt: null } }),
    prisma.aiSummary.count({ where: { status: "ready", deletedAt: null } }),
    prisma.aiSummary.count({ where: { status: "failed", deletedAt: null } }),
    prisma.aiSummary.count({ where: { deletedAt: { not: null } } }),
    prisma.aiSummary.findMany({
      where: {
        deletedAt: null,
        status: {
          in: ["transcribing", "summarizing", "failed"],
        },
      },
      orderBy: {
        updatedAt: "desc",
      },
      take: 5,
      select: {
        id: true,
        mediaId: true,
        status: true,
        errorCode: true,
        inputTranscriptLength: true,
        inputDurationSeconds: true,
        updatedAt: true,
      },
    }),
  ]);

  return {
    total,
    transcribing,
    summarizing,
    ready,
    failed,
    deleted,
    recent: recent.map((summary) => ({
      id: summary.id,
      mediaId: summary.mediaId,
      status: summary.status,
      errorCode: summary.errorCode,
      inputTranscriptLength: summary.inputTranscriptLength,
      inputDurationSeconds: summary.inputDurationSeconds,
      ageSeconds: Math.max(0, Math.round((Date.now() - summary.updatedAt.getTime()) / 1_000)),
      retryHint: aiSummaryRetryHint(summary.status),
      updatedAt: summary.updatedAt.toISOString(),
    })),
  };
}

function aiSummaryRetryHint(status: string): string {
  if (status === "failed") {
    return "Open the summary on iPhone and tap Regenerate.";
  }

  if (status === "transcribing") {
    return "If this stays here, check local transcription and server logs.";
  }

  if (status === "summarizing") {
    return "If this stays here, check AI provider timeout and server logs.";
  }

  return "No action needed.";
}

async function latestServerChangeVersion(prisma: PrismaClient): Promise<number> {
  const result = await prisma.serverChange.aggregate({
    _max: {
      version: true,
    },
  });

  return result._max.version ?? 0;
}

async function authenticateOrReply(
  request: Parameters<typeof authenticateDevice>[0],
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

const adminPostInclude = {
  createdByDevice: true,
  updatedByDevice: true,
  media: {
    orderBy: {
      sortOrder: "asc",
    },
  },
} satisfies Prisma.PostInclude;

function postWhere({
  cursor,
  deleted,
  deviceId,
  q,
}: {
  cursor: TimelineCursor | null;
  deleted: DeletedFilter;
  deviceId: string | undefined;
  q: string | undefined;
}): Prisma.PostWhereInput {
  const where: Prisma.PostWhereInput = {};

  if (deleted === "active") {
    where.deletedAt = null;
  } else if (deleted === "deleted") {
    where.deletedAt = {
      not: null,
    };
  }

  if (deviceId) {
    where.createdByDeviceId = deviceId;
  }

  if (q) {
    where.OR = [
      {
        text: {
          contains: q,
        },
      },
      {
        media: {
          some: {
            deletedAt: null,
            transcriptionText: {
              contains: q,
            },
          },
        },
      },
      {
        comments: {
          some: {
            deletedAt: null,
            text: {
              contains: q,
            },
          },
        },
      },
    ];
  }

  if (cursor) {
    where.OR = [
      {
        occurredAt: {
          lt: new Date(cursor.occurredAt),
        },
      },
      {
        occurredAt: new Date(cursor.occurredAt),
        id: {
          lt: cursor.id,
        },
      },
    ];
  }

  return where;
}

function serializeAdminPost(post: AdminPost): Record<string, unknown> {
  const activeMedia = post.media.filter((media) => !media.deletedAt);

  return {
    id: post.id,
    text: post.text,
    isFavorite: post.isFavorite,
    occurredAt: post.occurredAt.toISOString(),
    createdAt: post.createdAt.toISOString(),
    updatedAt: post.updatedAt.toISOString(),
    deletedAt: post.deletedAt?.toISOString() ?? null,
    clientCreatedAt: post.clientCreatedAt?.toISOString() ?? null,
    clientUpdatedAt: post.clientUpdatedAt?.toISOString() ?? null,
    serverVersion: post.serverVersion,
    createdByDevice: post.createdByDevice ? serializeDevice(post.createdByDevice) : null,
    updatedByDevice: post.updatedByDevice ? serializeDevice(post.updatedByDevice) : null,
    mediaCount: activeMedia.length,
    totalMediaCount: post.media.length,
    media: post.media.map((media) => ({
      id: media.id,
      kind: media.kind,
      status: media.status,
      sortOrder: media.sortOrder,
      originalPreserved: media.originalPreserved,
      width: media.width,
      height: media.height,
      mimeType: media.mimeType,
      durationSeconds: media.durationSeconds,
      transcriptionText: media.transcriptionText,
      compressedSizeBytes: media.compressedSizeBytes,
      originalSizeBytes: media.originalSizeBytes,
      checksum: media.checksum,
      deletedAt: media.deletedAt?.toISOString() ?? null,
      compressedUrl:
        media.compressedPath && !media.deletedAt
          ? `/api/v1/media/${media.id}?variant=compressed`
          : null,
      originalUrl:
        media.originalPath && !media.deletedAt
          ? `/api/v1/media/${media.id}?variant=original`
          : null,
      thumbnailUrl:
        media.thumbnailPath && !media.deletedAt
          ? `/api/v1/media/${media.id}?variant=thumbnail`
          : null,
    })),
  };
}

function serializeDevice(device: Device): Record<string, unknown> {
  return {
    id: device.id,
    name: device.name,
    platform: device.platform,
    lastSeenAt: device.lastSeenAt?.toISOString() ?? null,
    revokedAt: device.revokedAt?.toISOString() ?? null,
    createdAt: device.createdAt.toISOString(),
  };
}

async function softDeletePost(
  prisma: PrismaClient,
  postId: string,
  adminDeviceId: string,
): Promise<void> {
  const deletedAt = new Date();

  await prisma.$transaction(async (tx) => {
    await tx.post.update({
      where: {
        id: postId,
      },
      data: {
        deletedAt,
        updatedByDeviceId: adminDeviceId,
      },
    });

    await tx.media.updateMany({
      where: {
        postId,
        deletedAt: null,
      },
      data: {
        deletedAt,
        status: "deleted",
      },
    });

    await tx.comment.updateMany({
      where: {
        postId,
        deletedAt: null,
      },
      data: {
        deletedAt,
        updatedByDeviceId: adminDeviceId,
      },
    });

    const change = await tx.serverChange.create({
      data: {
        entityType: "post",
        entityId: postId,
        changeType: "post_deleted",
        payloadJson: JSON.stringify({
          id: postId,
          deletedAt: deletedAt.toISOString(),
        }),
      },
    });

    await tx.post.update({
      where: {
        id: postId,
      },
      data: {
        serverVersion: change.version,
      },
    });
  });
}

function uniqueMediaPaths(media: Media[]): string[] {
  return [
    ...new Set(
      media.flatMap((item) =>
        [item.compressedPath, item.originalPath, item.thumbnailPath].filter(isString),
      ),
    ),
  ];
}

async function deleteMediaFiles(
  dataDir: string,
  relativePaths: string[],
): Promise<{ deleted: number; failed: number }> {
  let deleted = 0;
  let failed = 0;

  for (const relativePath of relativePaths) {
    const absolutePath = path.join(dataDir, relativePath);
    if (!isPathInside(dataDir, absolutePath)) {
      failed += 1;
      continue;
    }

    try {
      await unlink(absolutePath);
      deleted += 1;
    } catch (error) {
      if (isNotFoundError(error)) {
        continue;
      }

      failed += 1;
    }
  }

  return {
    deleted,
    failed,
  };
}

function isPathInside(parent: string, child: string): boolean {
  const relative = path.relative(parent, child);
  return Boolean(relative) && !relative.startsWith("..") && !path.isAbsolute(relative);
}

async function readRecentLogs(logsDir: string, limit: number): Promise<unknown[]> {
  const files = (await readdir(logsDir))
    .filter((file) => file.endsWith(".jsonl"))
    .sort()
    .reverse();

  const logs: unknown[] = [];
  for (const file of files) {
    const content = await readFile(path.join(logsDir, file), "utf8");
    const lines = content.trim().split("\n").filter(Boolean).reverse();

    for (const line of lines) {
      logs.push(parseLogLine(line));
      if (logs.length >= limit) {
        return logs;
      }
    }
  }

  return logs;
}

function parseLogLine(line: string): unknown {
  try {
    return JSON.parse(line) as unknown;
  } catch {
    return {
      raw: line,
    };
  }
}

function parseQuery(query: unknown): Record<string, string | undefined> {
  if (typeof query !== "object" || query === null || Array.isArray(query)) {
    return {};
  }

  const parsed: Record<string, string | undefined> = {};
  for (const [key, value] of Object.entries(query)) {
    parsed[key] = typeof value === "string" ? value : undefined;
  }

  return parsed;
}

function parseBody(body: unknown): Record<string, string | undefined> {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return {};
  }

  const parsed: Record<string, string | undefined> = {};
  for (const [key, value] of Object.entries(body)) {
    parsed[key] = typeof value === "string" ? value : undefined;
  }

  return parsed;
}

function parseLimit(value: string | undefined): number | null {
  if (!value) {
    return DEFAULT_LOG_LIMIT;
  }

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > MAX_LOG_LIMIT) {
    return null;
  }

  return parsed;
}

function parsePostLimit(value: string | undefined, max: number): number | null {
  if (!value) {
    return DEFAULT_POST_LIMIT;
  }

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > max) {
    return null;
  }

  return parsed;
}

function parseDeletedFilter(value: string | undefined): DeletedFilter | null {
  if (!value) {
    return "active";
  }

  if (value === "active" || value === "deleted" || value === "all") {
    return value;
  }

  return null;
}

function parseCursor(value: string | undefined): TimelineCursor | null {
  if (!value) {
    return null;
  }

  try {
    const parsed = JSON.parse(Buffer.from(value, "base64url").toString("utf8")) as {
      occurredAt?: unknown;
      id?: unknown;
    };

    if (typeof parsed.occurredAt !== "string" || typeof parsed.id !== "string") {
      return null;
    }

    if (Number.isNaN(new Date(parsed.occurredAt).getTime())) {
      return null;
    }

    return {
      occurredAt: parsed.occurredAt,
      id: parsed.id,
    };
  } catch {
    return null;
  }
}

function encodeCursor(post: Post): string {
  const cursor: TimelineCursor = {
    occurredAt: post.occurredAt.toISOString(),
    id: post.id,
  };

  return Buffer.from(JSON.stringify(cursor), "utf8").toString("base64url");
}

function isString(value: string | null): value is string {
  return typeof value === "string" && value.length > 0;
}

function isNotFoundError(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "ENOENT"
  );
}
