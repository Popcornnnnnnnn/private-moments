import { execFile } from "node:child_process";
import { createReadStream } from "node:fs";
import { mkdir, readFile, rm, stat } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";

import type { PrismaClient } from "@prisma/client";
import type { FastifyInstance, FastifyReply } from "fastify";

import { enqueueMediaSummaryJob } from "../ai/media-summary-service.js";
import { authenticateDevice, UnauthorizedError } from "../auth/request-auth.js";
import type { AppConfig } from "../config/app-config.js";
import type { FileLogger } from "../logging/file-logger.js";
import {
  blockWritesDuringMaintenance,
  type MaintenanceModeService,
} from "../maintenance/maintenance-mode.js";
import type { DataPaths } from "../storage/data-dir.js";
import { sendBadRequest, sendNotFound, sendUnauthorized } from "./http-errors.js";
import {
  extensionForMediaMimeType,
  isAllowedMediaUpload,
  parseMediaUploadFields,
  relativeMediaPath,
  type MediaUploadFields as UploadFields,
} from "./media-upload-fields.js";
import {
  contentTypeForMediaPath,
  mediaUploadErrorCode,
  parseMediaIds,
  parseMediaVariant,
  pathForMediaVariant,
  type MediaVariant,
} from "./media-helpers.js";
import {
  fileExists,
  isPathInside,
  parseContentLength,
  writeUploadedFile,
} from "./upload-helpers.js";

const execFileAsync = promisify(execFile);
const THUMBNAIL_MAX_EDGE = "800";
const THUMBNAIL_MAX_BYTES = 180_000;
const UPLOAD_STREAM_TIMEOUT_MS = 240_000;

interface MediaRouteContext {
  config: AppConfig;
  prisma: PrismaClient;
  paths: DataPaths;
  fileLogger: FileLogger;
  maintenanceMode: MaintenanceModeService;
}

export async function registerMediaRoutes(
  app: FastifyInstance,
  context: MediaRouteContext,
): Promise<void> {
  app.post<{ Body: { mediaIds?: unknown; variant?: unknown } }>(
    "/api/v1/media/batch-download",
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
        typeof request.body?.variant === "string" ? request.body.variant : "thumbnail",
      );
      if (mediaIds.length === 0) {
        return sendBadRequest(reply, "mediaIds must contain at least one id");
      }
      if (!variant) {
        return sendBadRequest(reply, "variant must be one of: compressed, original, thumbnail");
      }

      const downloadedMedia = [];
      for (const mediaId of mediaIds) {
        const media = await context.prisma.media.findUnique({
          where: {
            id: mediaId,
          },
        });
        if (!media || media.deletedAt) {
          continue;
        }

        const relativePath = await pathForVariantOrGeneratedThumbnail(context, media, variant);
        if (!relativePath) {
          continue;
        }

        const absolutePath = path.join(context.paths.dataDir, relativePath);
        if (!isPathInside(context.paths.dataDir, absolutePath) || !(await fileExists(absolutePath))) {
          continue;
        }

        const data = await readFile(absolutePath);
        downloadedMedia.push({
          id: media.id,
          variant,
          contentType: contentTypeForMediaPath(relativePath),
          fileName: path.basename(relativePath),
          base64: data.toString("base64"),
        });
      }

      await context.fileLogger.info("media.batch_download", {
        requestedCount: mediaIds.length,
        returnedCount: downloadedMedia.length,
        variant,
      });

      return reply.send({
        media: downloadedMedia,
      });
    },
  );

  app.get<{ Params: { mediaId: string } }>(
    "/api/v1/media/:mediaId",
    async (request, reply) => {
      try {
        await authenticateDevice(request, context.prisma);
      } catch (error) {
        if (error instanceof UnauthorizedError) {
          return sendUnauthorized(reply, error.message);
        }

        throw error;
      }

      const query = parseQuery(request.query);
      const variant = parseMediaVariant(query.variant ?? "compressed");
      if (!variant) {
        return sendBadRequest(reply, "variant must be one of: compressed, original, thumbnail");
      }

      const media = await context.prisma.media.findUnique({
        where: {
          id: request.params.mediaId,
        },
      });

      if (!media || media.deletedAt) {
        return sendNotFound(reply, "Media not found");
      }

      const relativePath = await pathForVariantOrGeneratedThumbnail(context, media, variant);
      if (!relativePath) {
        return sendNotFound(reply, "Requested media variant not found");
      }

      const absolutePath = path.join(context.paths.dataDir, relativePath);
      if (!isPathInside(context.paths.dataDir, absolutePath) || !(await fileExists(absolutePath))) {
        return sendNotFound(reply, "Media file not found");
      }

      const fileStats = await stat(absolutePath);
      await context.fileLogger.info("media.download", {
        mediaId: request.params.mediaId,
        variant,
        sizeBytes: fileStats.size,
      });

      reply.header("Content-Type", contentTypeForMediaPath(relativePath));
      reply.header("Content-Length", String(fileStats.size));
      reply.header("Connection", "close");
      if (variant === "thumbnail" || fileStats.size <= 1_000_000) {
        return reply.send(await readFile(absolutePath));
      }

      return reply.send(createReadStream(absolutePath));
    },
  );

  app.post("/api/v1/media/upload", async (request, reply) => {
    let deviceId: string;
    try {
      const device = await authenticateDevice(request, context.prisma);
      deviceId = device.id;
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

    if (!isAllowedMediaUpload(file.mimetype, fields.kind, fields.variant)) {
      file.file.resume();
      return sendBadRequest(reply, "Unsupported media upload type");
    }

    const post = await context.prisma.post.findUnique({
      where: {
        id: fields.postId,
      },
    });

    if (!post || post.deletedAt) {
      file.file.resume();
      return sendNotFound(reply, "Post not found");
    }

    const extension = extensionForMediaMimeType(file.mimetype, file.filename);
    const relativePath = relativeMediaPath(fields.variant, fields.mediaId, extension);
    const absolutePath = path.join(context.paths.dataDir, relativePath);

    const uploadStartedAt = Date.now();
    await context.fileLogger.info("media.upload_started", {
      mediaId: fields.mediaId,
      postId: fields.postId,
      kind: fields.kind,
      variant: fields.variant,
      mimeType: file.mimetype,
      expectedBytes: parseContentLength(request.headers["content-length"]),
    });

    let writeResult: { sizeBytes: number; checksum: string };
    try {
      writeResult = await writeUploadedFile(file, absolutePath, {
        timeoutMs: UPLOAD_STREAM_TIMEOUT_MS,
        timeoutMessage: "Media upload timed out",
      });
      await context.fileLogger.info("media.upload_received", {
        mediaId: fields.mediaId,
        postId: fields.postId,
        kind: fields.kind,
        variant: fields.variant,
        sizeBytes: writeResult.sizeBytes,
        elapsedMs: Date.now() - uploadStartedAt,
      });

      const media = await upsertMediaRecord(context.prisma, fields, relativePath, writeResult);
      await context.fileLogger.info("media.upload_completed", {
        mediaId: media.id,
        postId: media.postId,
        kind: media.kind,
        variant: fields.variant,
        status: media.status,
        sizeBytes: writeResult.sizeBytes,
        elapsedMs: Date.now() - uploadStartedAt,
      });

      if (fields.variant === "compressed" && (media.kind === "audio" || media.kind === "video")) {
        enqueueMediaSummaryJob(context, {
          postId: media.postId,
          mediaId: media.id,
          requestedByDeviceId: deviceId,
          aiLanguage: fields.aiLanguage,
        });
      }

      return reply.send({
        media: {
          id: media.id,
          postId: media.postId,
          variant: fields.variant,
          status: media.status,
          path: relativePath,
          sizeBytes: writeResult.sizeBytes,
          checksum: writeResult.checksum,
        },
      });
    } catch (error) {
      await context.fileLogger.warn("media.upload_failed", {
        mediaId: fields.mediaId,
        postId: fields.postId,
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

async function pathForVariantOrGeneratedThumbnail(
  context: MediaRouteContext,
  media: {
    id: string;
    kind: string;
    compressedPath: string | null;
    originalPath: string | null;
    thumbnailPath: string | null;
  },
  variant: MediaVariant,
): Promise<string | null> {
  if (variant === "thumbnail" && media.kind === "image" && media.compressedPath) {
    return generateThumbnailFromCompressed(context, media.id, media.compressedPath, media.thumbnailPath);
  }

  const existingPath = pathForMediaVariant(media, variant);
  if (existingPath) {
    return existingPath;
  }

  if (variant !== "thumbnail" || media.kind !== "image" || !media.compressedPath) {
    return null;
  }

  return generateThumbnailFromCompressed(context, media.id, media.compressedPath);
}

async function generateThumbnailFromCompressed(
  context: MediaRouteContext,
  mediaId: string,
  compressedPath: string,
  existingThumbnailPath: string | null = null,
): Promise<string | null> {
  const inputPath = path.join(context.paths.dataDir, compressedPath);
  if (!isPathInside(context.paths.dataDir, inputPath) || !(await fileExists(inputPath))) {
    return null;
  }

  const relativePath = existingThumbnailPath ?? relativeMediaPath("thumbnail", mediaId, ".jpg");
  const outputPath = path.join(context.paths.dataDir, relativePath);
  if (!isPathInside(context.paths.dataDir, outputPath)) {
    return null;
  }

  await mkdir(path.dirname(outputPath), { recursive: true });

  if (await fileExists(outputPath)) {
    const thumbnailStats = await stat(outputPath);
    if (thumbnailStats.size <= THUMBNAIL_MAX_BYTES) {
      return relativePath;
    }

    await rm(outputPath, { force: true });
  }

  if (!(await fileExists(outputPath))) {
    try {
      await execFileAsync("sips", [
        "-s",
        "format",
        "jpeg",
        "-s",
        "formatOptions",
        "75",
        "-Z",
        THUMBNAIL_MAX_EDGE,
        inputPath,
        "--out",
        outputPath,
      ]);
    } catch (error) {
      await rm(outputPath, { force: true });
      await context.fileLogger.warn("media.thumbnail_failed", {
        mediaId,
        message: error instanceof Error ? error.message : String(error),
      });
      return null;
    }
  }

  await context.prisma.media.update({
    where: {
      id: mediaId,
    },
    data: {
      thumbnailPath: relativePath,
    },
  });

  await context.fileLogger.info("media.thumbnail_ready", {
    mediaId,
    path: relativePath,
  });

  return relativePath;
}

async function upsertMediaRecord(
  prisma: PrismaClient,
  fields: UploadFields,
  relativePath: string,
  writeResult: { sizeBytes: number; checksum: string },
) {
  return prisma.$transaction(async (tx) => {
    const existing = await tx.media.findUnique({
      where: {
        id: fields.mediaId,
      },
    });

    const pathData = pathDataForVariant(fields.variant, relativePath, writeResult.sizeBytes);
    const status =
      fields.variant === "compressed" || existing?.compressedPath ? "uploaded" : "pending";

    const media = !existing
      ? await tx.media.create({
          data: {
            id: fields.mediaId,
            postId: fields.postId,
            kind: fields.kind,
            status,
            mimeType: fields.variant === "thumbnail" ? null : fields.mimeType,
            durationSeconds: fields.variant === "thumbnail" ? null : fields.durationSeconds,
            transcriptionText:
              fields.variant === "thumbnail" ? null : fields.transcriptionText,
            width: fields.variant === "thumbnail" ? null : fields.width,
            height: fields.variant === "thumbnail" ? null : fields.height,
            originalPreserved: fields.originalPreserved || fields.variant === "original",
            sortOrder: fields.sortOrder,
            checksum: writeResult.checksum,
            ...pathData,
          },
        })
      : await tx.media.update({
          where: {
            id: fields.mediaId,
          },
          data: {
            status,
            kind: fields.kind,
            mimeType:
              fields.variant === "thumbnail" ? existing.mimeType : fields.mimeType ?? existing.mimeType,
            durationSeconds:
              fields.variant === "thumbnail"
                ? existing.durationSeconds
                : fields.durationSeconds ?? existing.durationSeconds,
            transcriptionText:
              fields.variant === "thumbnail"
                ? existing.transcriptionText
                : fields.transcriptionText ?? existing.transcriptionText,
            width: fields.variant === "thumbnail" ? existing.width : fields.width ?? existing.width,
            height: fields.variant === "thumbnail" ? existing.height : fields.height ?? existing.height,
            originalPreserved:
              existing.originalPreserved || fields.originalPreserved || fields.variant === "original",
            sortOrder: fields.sortOrder,
            checksum: writeResult.checksum,
            ...pathData,
          },
        });

    const change = await tx.serverChange.create({
      data: {
        entityType: "media",
        entityId: media.id,
        changeType: "media_uploaded",
        payloadJson: JSON.stringify({
          id: media.id,
          postId: media.postId,
          kind: media.kind,
          status: media.status,
          variant: fields.variant,
          path: relativePath,
          mimeType: media.mimeType,
          durationSeconds: media.durationSeconds,
          transcriptionText: media.transcriptionText,
          width: media.width,
          height: media.height,
          originalPreserved: media.originalPreserved,
          sortOrder: media.sortOrder,
          checksum: media.checksum,
          compressedSizeBytes: media.compressedSizeBytes,
          originalSizeBytes: media.originalSizeBytes,
        }),
      },
    });

    await tx.post.update({
      where: {
        id: fields.postId,
      },
      data: {
        serverVersion: change.version,
      },
    });

    return media;
  });
}

function pathDataForVariant(
  variant: MediaVariant,
  relativePath: string,
  sizeBytes: number,
): Record<string, string | number> {
  if (variant === "compressed") {
    return {
      compressedPath: relativePath,
      compressedSizeBytes: sizeBytes,
    };
  }

  if (variant === "original") {
    return {
      originalPath: relativePath,
      originalSizeBytes: sizeBytes,
    };
  }

  return {
    thumbnailPath: relativePath,
  };
}

function parseUploadFields(
  fields: Parameters<typeof parseMediaUploadFields>[0],
  reply: FastifyReply,
): UploadFields | null {
  const parsed = parseMediaUploadFields(fields);
  if (!parsed.ok) {
    sendBadRequest(reply, parsed.message);
    return null;
  }

  return parsed.fields;
}
