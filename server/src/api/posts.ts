import type { Media, Post, PrismaClient } from "@prisma/client";
import type { FastifyInstance, FastifyReply } from "fastify";

import { authenticateDevice, UnauthorizedError } from "../auth/request-auth.js";
import { sendBadRequest, sendNotFound, sendUnauthorized } from "./http-errors.js";

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 100;

type PostWithMedia = Post & {
  media: Media[];
};

interface PostRouteContext {
  prisma: PrismaClient;
}

interface TimelineCursor {
  occurredAt: string;
  id: string;
}

export async function registerPostRoutes(
  app: FastifyInstance,
  context: PostRouteContext,
): Promise<void> {
  app.get("/api/v1/timeline", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const query = parseQuery(request.query);
    const limit = parseLimit(query.limit);
    if (limit === null) {
      return sendBadRequest(reply, "limit must be an integer between 1 and 100");
    }

    const cursor = parseCursor(query.cursor);
    if (query.cursor && !cursor) {
      return sendBadRequest(reply, "cursor is invalid");
    }

    const posts = await context.prisma.post.findMany({
      where: {
        deletedAt: null,
        ...(cursor
          ? {
              OR: [
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
              ],
            }
          : {}),
      },
      orderBy: [
        {
          occurredAt: "desc",
        },
        {
          id: "desc",
        },
      ],
      take: limit,
      include: {
        media: {
          where: {
            deletedAt: null,
          },
          orderBy: {
            sortOrder: "asc",
          },
        },
      },
    });

    return reply.send({
      posts: posts.map(serializePost),
      nextCursor: posts.length === limit ? encodeCursor(posts[posts.length - 1]!) : null,
    });
  });

  app.get<{ Params: { postId: string } }>(
    "/api/v1/posts/:postId",
    async (request, reply) => {
      const authenticated = await authenticateOrReply(request, reply, context.prisma);
      if (!authenticated) {
        return reply;
      }

      const post = await context.prisma.post.findUnique({
        where: {
          id: request.params.postId,
        },
        include: {
          media: {
            orderBy: {
              sortOrder: "asc",
            },
          },
        },
      });

      if (!post) {
        return sendNotFound(reply, "Post not found");
      }

      return reply.send({
        post: serializePost(post),
      });
    },
  );

  app.get("/api/v1/search", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const query = parseQuery(request.query);
    const q = query.q?.trim();
    if (!q) {
      return sendBadRequest(reply, "q is required");
    }

    const limit = parseLimit(query.limit);
    if (limit === null) {
      return sendBadRequest(reply, "limit must be an integer between 1 and 100");
    }

    const posts = await context.prisma.post.findMany({
      where: {
        deletedAt: null,
        OR: [
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
        ],
      },
      orderBy: [
        {
          occurredAt: "desc",
        },
        {
          id: "desc",
        },
      ],
      take: limit,
      include: {
        media: {
          where: {
            deletedAt: null,
          },
          orderBy: {
            sortOrder: "asc",
          },
        },
      },
    });

    return reply.send({
      posts: posts.map(serializePost),
    });
  });
}

function serializePost(post: PostWithMedia): Record<string, unknown> {
  return {
    id: post.id,
    text: post.text,
    isFavorite: post.isFavorite,
    isPinned: post.isPinned,
    pinnedAt: post.pinnedAt?.toISOString() ?? null,
    occurredAt: post.occurredAt.toISOString(),
    createdAt: post.createdAt.toISOString(),
    updatedAt: post.updatedAt.toISOString(),
    deletedAt: post.deletedAt?.toISOString() ?? null,
    serverVersion: post.serverVersion,
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
      compressedUrl: media.compressedPath
        ? `/api/v1/media/${media.id}?variant=compressed`
        : null,
      originalUrl: media.originalPath
        ? `/api/v1/media/${media.id}?variant=original`
        : null,
      thumbnailUrl: media.thumbnailPath
        ? `/api/v1/media/${media.id}?variant=thumbnail`
        : null,
    })),
  };
}

async function authenticateOrReply(
  request: Parameters<typeof authenticateDevice>[0],
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

function parseLimit(value: string | undefined): number | null {
  if (!value) {
    return DEFAULT_LIMIT;
  }

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > MAX_LIMIT) {
    return null;
  }

  return parsed;
}

function encodeCursor(post: Post): string {
  const cursor: TimelineCursor = {
    occurredAt: post.occurredAt.toISOString(),
    id: post.id,
  };

  return Buffer.from(JSON.stringify(cursor), "utf8").toString("base64url");
}

function parseCursor(value: string | undefined): TimelineCursor | null {
  if (!value) {
    return null;
  }

  try {
    const parsed = JSON.parse(Buffer.from(value, "base64url").toString("utf8")) as unknown;
    if (!isRecord(parsed)) {
      return null;
    }

    const occurredAt = typeof parsed.occurredAt === "string" ? parsed.occurredAt : null;
    const id = typeof parsed.id === "string" ? parsed.id : null;
    if (!occurredAt || !id || Number.isNaN(new Date(occurredAt).getTime())) {
      return null;
    }

    return {
      occurredAt,
      id,
    };
  } catch {
    return null;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
