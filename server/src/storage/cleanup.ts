import { unlink } from "node:fs/promises";
import path from "node:path";

import type { PrismaClient } from "@prisma/client";

import type { FileLogger } from "../logging/file-logger.js";
import type { DataPaths } from "./data-dir.js";

const DELETED_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

export async function cleanupExpiredDeletedContent(
  prisma: PrismaClient,
  paths: DataPaths,
  fileLogger: FileLogger,
  now = new Date(),
): Promise<void> {
  const cutoff = new Date(now.getTime() - DELETED_RETENTION_MS);
  const expiredMedia = await prisma.media.findMany({
    where: {
      OR: [
        {
          deletedAt: {
            lt: cutoff,
          },
        },
        {
          post: {
            is: {
              deletedAt: {
                lt: cutoff,
              },
            },
          },
        },
      ],
    },
    select: {
      id: true,
      compressedPath: true,
      originalPath: true,
      thumbnailPath: true,
    },
  });

  for (const media of expiredMedia) {
    await removeMediaFiles(paths.dataDir, media, fileLogger);
  }

  const mediaDelete = expiredMedia.length
    ? await prisma.media.deleteMany({
        where: {
          id: {
            in: expiredMedia.map((media) => media.id),
          },
        },
      })
    : { count: 0 };

  const postDelete = await prisma.post.deleteMany({
    where: {
      deletedAt: {
        lt: cutoff,
      },
    },
  });

  if (mediaDelete.count > 0 || postDelete.count > 0) {
    await fileLogger.info("cleanup.expired_deleted_content", {
      cutoff: cutoff.toISOString(),
      postsDeleted: postDelete.count,
      mediaDeleted: mediaDelete.count,
    });
  }
}

async function removeMediaFiles(
  dataDir: string,
  media: {
    compressedPath: string | null;
    originalPath: string | null;
    thumbnailPath: string | null;
  },
  fileLogger: FileLogger,
): Promise<void> {
  for (const relativePath of [media.compressedPath, media.originalPath, media.thumbnailPath]) {
    if (!relativePath) {
      continue;
    }

    const absolutePath = path.join(dataDir, relativePath);
    if (!isPathInside(dataDir, absolutePath)) {
      await fileLogger.warn("cleanup.skipped_unsafe_path", {
        path: relativePath,
      });
      continue;
    }

    try {
      await unlink(absolutePath);
    } catch (error) {
      if (!isNotFoundError(error)) {
        await fileLogger.warn("cleanup.file_delete_failed", {
          path: relativePath,
          message: error instanceof Error ? error.message : "Unknown error",
        });
      }
    }
  }
}

function isPathInside(parent: string, child: string): boolean {
  const relative = path.relative(parent, child);
  return Boolean(relative) && !relative.startsWith("..") && !path.isAbsolute(relative);
}

function isNotFoundError(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "ENOENT"
  );
}
