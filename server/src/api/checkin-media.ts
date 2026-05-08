import { createHash, randomUUID } from "node:crypto";
import { createReadStream, createWriteStream } from "node:fs";
import { access, mkdir, readFile, rename, rm, stat } from "node:fs/promises";
import { Transform } from "node:stream";
import { pipeline } from "node:stream/promises";
import path from "node:path";

import type { PrismaClient } from "@prisma/client";
import type { FastifyInstance, FastifyReply } from "fastify";
import type { MultipartFields, MultipartFile, MultipartValue } from "@fastify/multipart";

import { authenticateDevice, UnauthorizedError } from "../auth/request-auth.js";
import type { FileLogger } from "../logging/file-logger.js";
import {
  blockWritesDuringMaintenance,
  type MaintenanceModeService,
} from "../maintenance/maintenance-mode.js";
import type { DataPaths } from "../storage/data-dir.js";
import { sendBadRequest, sendNotFound, sendUnauthorized } from "./http-errors.js";
import {
  contentTypeForMediaPath,
  mediaUploadErrorCode,
  parseMediaIds,
  parseMediaVariant,
  type MediaVariant,
} from "./media-helpers.js";

const UPLOAD_STREAM_TIMEOUT_MS = 120_000;

interface CheckInMediaRouteContext {
  prisma: PrismaClient;
  paths: DataPaths;
  fileLogger: FileLogger;
  maintenanceMode: MaintenanceModeService;
}

interface UploadFields {
  mediaId: string;
  entryId: string;
  variant: MediaVariant;
  kind: "image";
  mimeType: string | null;
  sortOrder: number;
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

    const extension = extensionForMimeType(file.mimetype, file.filename);
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
      const writeResult = await writeUploadedFile(file, absolutePath);
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

function parseUploadFields(fields: MultipartFields, reply: FastifyReply): UploadFields | null {
  const mediaId = getMultipartString(fields, "mediaId");
  const entryId = getMultipartString(fields, "entryId");
  const variant = getMultipartString(fields, "variant");
  const kind = getMultipartString(fields, "kind") ?? "image";
  const mimeType = getMultipartString(fields, "mimeType");
  const sortOrder = getMultipartInteger(fields, "sortOrder") ?? 0;

  if (!mediaId || !entryId || !variant) {
    sendBadRequest(reply, "mediaId, entryId, and variant are required");
    return null;
  }

  if (parseMediaVariant(variant) !== "compressed") {
    sendBadRequest(reply, "check-in media currently supports compressed image uploads only");
    return null;
  }

  if (kind !== "image") {
    sendBadRequest(reply, "check-in media currently supports image uploads only");
    return null;
  }

  return {
    mediaId,
    entryId,
    variant: "compressed",
    kind,
    mimeType,
    sortOrder,
  };
}

function getMultipartString(fields: MultipartFields, key: string): string | null {
  const field = firstField(fields[key]);
  if (!field || field.type !== "field" || typeof field.value !== "string") {
    return null;
  }

  const trimmed = field.value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function getMultipartInteger(fields: MultipartFields, key: string): number | null {
  const value = getMultipartString(fields, key);
  if (value === null) {
    return null;
  }

  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : null;
}

function firstField(field: MultipartFields[string]): MultipartValue | MultipartFile | undefined {
  return Array.isArray(field) ? field[0] : field;
}

async function writeUploadedFile(
  file: MultipartFile,
  absolutePath: string,
): Promise<{ sizeBytes: number; checksum: string }> {
  const tracker = createUploadHashTracker();
  const tempPath = tempUploadPath(absolutePath);
  const controller = new AbortController();
  const timeout = setTimeout(() => {
    controller.abort(new Error("Check-in media upload timed out"));
  }, UPLOAD_STREAM_TIMEOUT_MS);
  timeout.unref();

  let output: ReturnType<typeof createWriteStream> | null = null;
  try {
    await mkdir(path.dirname(absolutePath), { recursive: true });
    output = createWriteStream(tempPath, { flags: "wx" });
    await pipeline(file.file, tracker.stream, output, { signal: controller.signal });
    await rename(tempPath, absolutePath);
  } catch (error) {
    file.file.destroy();
    output?.destroy();
    await rm(tempPath, { force: true });
    throw error;
  } finally {
    clearTimeout(timeout);
  }

  return tracker.result();
}

function createUploadHashTracker(): {
  stream: Transform;
  result: () => { sizeBytes: number; checksum: string };
} {
  const hash = createHash("sha256");
  let sizeBytes = 0;

  const stream = new Transform({
    transform(chunk: Buffer, _encoding, callback) {
      sizeBytes += chunk.length;
      hash.update(chunk);
      callback(null, chunk);
    },
  });

  return {
    stream,
    result: () => ({
      sizeBytes,
      checksum: hash.digest("hex"),
    }),
  };
}

function tempUploadPath(absolutePath: string): string {
  const directory = path.dirname(absolutePath);
  const extension = path.extname(absolutePath) || ".upload";
  const baseName = path.basename(absolutePath, extension);
  return path.join(directory, `.${baseName}.${process.pid}.${Date.now()}.${randomUUID()}.tmp`);
}

function parseContentLength(value: string | string[] | undefined): number | null {
  const rawValue = Array.isArray(value) ? value[0] : value;
  if (!rawValue) {
    return null;
  }

  const parsed = Number(rawValue);
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : null;
}

function relativeCheckInMediaPath(mediaId: string, extension: string): string {
  return path.join("media", "checkins", "compressed", `${mediaId}${extension}`);
}

function extensionForMimeType(mimetype: string, filename: string): string {
  if (mimetype === "image/jpeg") {
    return ".jpg";
  }

  if (mimetype === "image/png") {
    return ".png";
  }

  if (mimetype === "image/heic") {
    return ".heic";
  }

  if (mimetype === "image/webp") {
    return ".webp";
  }

  const extension = path.extname(filename).toLowerCase();
  return extension.length > 0 && extension.length <= 10 ? extension : ".jpg";
}

async function fileExists(absolutePath: string): Promise<boolean> {
  try {
    await access(absolutePath);
    return true;
  } catch {
    return false;
  }
}

function isPathInside(parent: string, child: string): boolean {
  const relative = path.relative(parent, child);
  return Boolean(relative) && !relative.startsWith("..") && !path.isAbsolute(relative);
}
