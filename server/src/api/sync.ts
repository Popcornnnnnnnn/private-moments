import type { Device, Prisma, PrismaClient } from "@prisma/client";
import type { FastifyInstance, FastifyReply } from "fastify";

import { authenticateDevice, UnauthorizedError } from "../auth/request-auth.js";
import { SCHEMA_VERSION, SERVER_VERSION } from "../config/app-config.js";
import type { FileLogger } from "../logging/file-logger.js";
import { sendBadRequest, sendForbidden, sendUnauthorized } from "./http-errors.js";

const MAX_LOCAL_CHANGES = 100;

interface SyncRouteContext {
  prisma: PrismaClient;
  fileLogger: FileLogger;
}

interface SyncRequestBody {
  deviceId: string;
  lastSyncCursor: number;
  localChanges: SyncOperationInput[];
}

interface SyncOperationInput {
  opId: string;
  type: string;
  entityType: string;
  entityId: string;
  clientCreatedAt: Date;
  payload: Record<string, unknown>;
}

interface RejectedOperation {
  opId: string;
  reason: string;
}

interface MediaOrderInput {
  id: string;
  sortOrder: number;
}

class OperationRejectedError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OperationRejectedError";
  }
}

export async function registerSyncRoutes(
  app: FastifyInstance,
  context: SyncRouteContext,
): Promise<void> {
  app.post("/api/v1/sync", async (request, reply) => {
    let device: Device;
    try {
      device = await authenticateDevice(request, context.prisma);
    } catch (error) {
      if (error instanceof UnauthorizedError) {
        return sendUnauthorized(reply, error.message);
      }

      throw error;
    }

    const body = parseSyncRequestBody(request.body, reply);
    if (!body) {
      return reply;
    }

    if (body.deviceId !== device.id) {
      return sendForbidden(reply, "Request deviceId does not match bearer token");
    }

    const acceptedOps: string[] = [];
    const rejectedOps: RejectedOperation[] = [];

    for (const operation of body.localChanges) {
      const result = await applyOrReplayOperation(context.prisma, device, operation);
      if (result.accepted) {
        acceptedOps.push(operation.opId);
      } else {
        rejectedOps.push({
          opId: operation.opId,
          reason: result.reason,
        });
      }
    }

    const serverChanges = await context.prisma.serverChange.findMany({
      where: {
        version: {
          gt: body.lastSyncCursor,
        },
      },
      orderBy: {
        version: "asc",
      },
      take: 500,
    });

    const nextSyncCursor =
      serverChanges.length > 0
        ? serverChanges[serverChanges.length - 1]!.version
        : body.lastSyncCursor;

    await context.fileLogger.info("sync.completed", {
      deviceId: device.id,
      acceptedOps: acceptedOps.length,
      rejectedOps: rejectedOps.length,
      nextSyncCursor,
    });

    return reply.send({
      serverVersion: SERVER_VERSION,
      schemaVersion: SCHEMA_VERSION,
      acceptedOps,
      rejectedOps,
      serverChanges: serverChanges.map((change) => ({
        version: change.version,
        entityType: change.entityType,
        entityId: change.entityId,
        changeType: change.changeType,
        payload: parseJsonObject(change.payloadJson),
        createdAt: change.createdAt,
      })),
      nextSyncCursor,
    });
  });
}

async function applyOrReplayOperation(
  prisma: PrismaClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<{ accepted: true } | { accepted: false; reason: string }> {
  const existing = await prisma.syncOperation.findUnique({
    where: {
      deviceId_opId: {
        deviceId: device.id,
        opId: operation.opId,
      },
    },
  });

  if (existing?.appliedAt) {
    return { accepted: true };
  }

  if (existing?.rejectedAt) {
    return {
      accepted: false,
      reason: existing.rejectionReason ?? "Operation was previously rejected",
    };
  }

  try {
    await prisma.$transaction(async (tx) => {
      const syncOperation = await tx.syncOperation.create({
        data: {
          opId: operation.opId,
          deviceId: device.id,
          type: operation.type,
          entityType: operation.entityType,
          entityId: operation.entityId,
          payloadJson: JSON.stringify(operation.payload),
        },
      });

      await applyOperation(tx, device, operation);

      await tx.syncOperation.update({
        where: {
          id: syncOperation.id,
        },
        data: {
          appliedAt: new Date(),
        },
      });
    });

    return { accepted: true };
  } catch (error) {
    if (!(error instanceof OperationRejectedError)) {
      throw error;
    }

    await markOperationRejected(prisma, device, operation, error.message);

    return {
      accepted: false,
      reason: error.message,
    };
  }
}

async function applyOperation(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  if (operation.type === "create_post" && operation.entityType === "post") {
    await applyCreatePost(tx, device, operation);
    return;
  }

  if (operation.type === "update_post" && operation.entityType === "post") {
    await applyUpdatePost(tx, device, operation);
    return;
  }

  if (operation.type === "update_post_favorite" && operation.entityType === "post") {
    await applyUpdatePostFavorite(tx, device, operation);
    return;
  }

  if (operation.type === "delete_post" && operation.entityType === "post") {
    await applyDeletePost(tx, device, operation);
    return;
  }

  if (operation.type === "create_comment" && operation.entityType === "comment") {
    await applyCreateComment(tx, device, operation);
    return;
  }

  if (operation.type === "delete_comment" && operation.entityType === "comment") {
    await applyDeleteComment(tx, device, operation);
    return;
  }

  throw new OperationRejectedError(`Unsupported operation type: ${operation.type}`);
}

async function applyCreatePost(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const text = getStringAllowingEmpty(operation.payload, "text");
  const occurredAt = getDate(operation.payload, "occurredAt");
  const isFavorite = getBoolean(operation.payload, "isFavorite") ?? false;

  if (text === null) {
    throw new OperationRejectedError("create_post.payload.text is required");
  }

  if (!occurredAt) {
    throw new OperationRejectedError("create_post.payload.occurredAt must be an ISO date");
  }

  const existingPost = await tx.post.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (existingPost) {
    throw new OperationRejectedError("Post already exists");
  }

  await tx.post.create({
    data: {
      id: operation.entityId,
      text,
      isFavorite,
      occurredAt,
      clientCreatedAt: operation.clientCreatedAt,
      clientUpdatedAt: operation.clientCreatedAt,
      createdByDeviceId: device.id,
      updatedByDeviceId: device.id,
    },
  });

  const change = await tx.serverChange.create({
    data: {
      entityType: "post",
      entityId: operation.entityId,
      changeType: "post_created",
      payloadJson: JSON.stringify({
        id: operation.entityId,
        text,
        isFavorite,
        occurredAt: occurredAt.toISOString(),
        deletedAt: null,
      }),
    },
  });

  await tx.post.update({
    where: {
      id: operation.entityId,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

async function applyUpdatePost(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const text = getStringAllowingEmpty(operation.payload, "text");
  const occurredAt = getDate(operation.payload, "occurredAt");
  const updatedAt = getDate(operation.payload, "updatedAt") ?? operation.clientCreatedAt;
  const mediaOrder = getMediaOrder(operation.payload, "media");

  if (text === null) {
    throw new OperationRejectedError("update_post.payload.text is required");
  }

  if (!occurredAt) {
    throw new OperationRejectedError("update_post.payload.occurredAt must be an ISO date");
  }

  if (!mediaOrder) {
    throw new OperationRejectedError("update_post.payload.media must be an array");
  }

  const mediaIds = new Set(mediaOrder.map((media) => media.id));
  if (mediaIds.size !== mediaOrder.length) {
    throw new OperationRejectedError("update_post.payload.media contains duplicate media ids");
  }

  if (text.trim().length === 0 && mediaOrder.length === 0) {
    throw new OperationRejectedError("update_post cannot leave a post empty");
  }

  const existingPost = await tx.post.findUnique({
    where: {
      id: operation.entityId,
    },
    include: {
      media: {
        where: {
          deletedAt: null,
        },
      },
    },
  });

  if (!existingPost || existingPost.deletedAt) {
    throw new OperationRejectedError("Post not found");
  }

  const existingMediaIds = new Set(existingPost.media.map((media) => media.id));
  const mediaFromOtherPosts = await tx.media.findMany({
    where: {
      id: {
        in: Array.from(mediaIds),
      },
      postId: {
        not: operation.entityId,
      },
    },
    select: {
      id: true,
    },
  });

  if (mediaFromOtherPosts.length > 0) {
    throw new OperationRejectedError("update_post.payload.media contains media from another post");
  }

  const removedMedia = existingPost.media.filter((media) => !mediaIds.has(media.id));
  const deletedAt = updatedAt;

  await tx.post.update({
    where: {
      id: operation.entityId,
    },
    data: {
      text,
      occurredAt,
      clientUpdatedAt: updatedAt,
      updatedByDeviceId: device.id,
    },
  });

  for (const media of mediaOrder) {
    if (!existingMediaIds.has(media.id)) {
      continue;
    }

    await tx.media.update({
      where: {
        id: media.id,
      },
      data: {
        sortOrder: media.sortOrder,
      },
    });
  }

  if (removedMedia.length > 0) {
    await tx.media.updateMany({
      where: {
        id: {
          in: removedMedia.map((media) => media.id),
        },
      },
      data: {
        deletedAt,
        status: "deleted",
      },
    });
  }

  let latestVersion = 0;
  const postChange = await tx.serverChange.create({
    data: {
      entityType: "post",
      entityId: operation.entityId,
      changeType: "post_updated",
      payloadJson: JSON.stringify({
        id: operation.entityId,
        text,
        isFavorite: existingPost.isFavorite,
        occurredAt: occurredAt.toISOString(),
        updatedAt: updatedAt.toISOString(),
        media: mediaOrder,
        deletedAt: null,
      }),
    },
  });
  latestVersion = postChange.version;

  for (const media of removedMedia) {
    const mediaChange = await tx.serverChange.create({
      data: {
        entityType: "media",
        entityId: media.id,
        changeType: "media_deleted",
        payloadJson: JSON.stringify({
          id: media.id,
          postId: operation.entityId,
          deletedAt: deletedAt.toISOString(),
        }),
      },
    });
    latestVersion = mediaChange.version;
  }

  await tx.post.update({
    where: {
      id: operation.entityId,
    },
    data: {
      serverVersion: latestVersion,
    },
  });
}

async function applyUpdatePostFavorite(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const isFavorite = getBoolean(operation.payload, "isFavorite");
  const updatedAt = getDate(operation.payload, "updatedAt") ?? operation.clientCreatedAt;

  if (isFavorite === null) {
    throw new OperationRejectedError("update_post_favorite.payload.isFavorite must be a boolean");
  }

  const existingPost = await tx.post.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!existingPost || existingPost.deletedAt) {
    throw new OperationRejectedError("Post not found");
  }

  await tx.post.update({
    where: {
      id: operation.entityId,
    },
    data: {
      isFavorite,
      clientUpdatedAt: updatedAt,
      updatedByDeviceId: device.id,
    },
  });

  const change = await tx.serverChange.create({
    data: {
      entityType: "post",
      entityId: operation.entityId,
      changeType: "post_favorite_updated",
      payloadJson: JSON.stringify({
        id: operation.entityId,
        isFavorite,
        updatedAt: updatedAt.toISOString(),
      }),
    },
  });

  await tx.post.update({
    where: {
      id: operation.entityId,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

async function applyDeletePost(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const deletedAt = getDate(operation.payload, "deletedAt") ?? operation.clientCreatedAt;

  const existingPost = await tx.post.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!existingPost) {
    throw new OperationRejectedError("Post not found");
  }

  await tx.post.update({
    where: {
      id: operation.entityId,
    },
    data: {
      deletedAt,
      clientUpdatedAt: operation.clientCreatedAt,
      updatedByDeviceId: device.id,
    },
  });

  await tx.media.updateMany({
    where: {
      postId: operation.entityId,
      deletedAt: null,
    },
    data: {
      deletedAt,
      status: "deleted",
    },
  });

  const change = await tx.serverChange.create({
    data: {
      entityType: "post",
      entityId: operation.entityId,
      changeType: "post_deleted",
      payloadJson: JSON.stringify({
        id: operation.entityId,
        deletedAt: deletedAt.toISOString(),
      }),
    },
  });

  await tx.post.update({
    where: {
      id: operation.entityId,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

async function applyCreateComment(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const postId = getString(operation.payload, "postId");
  const text = getStringAllowingEmpty(operation.payload, "text");
  const createdAt = getDate(operation.payload, "createdAt") ?? operation.clientCreatedAt;

  if (!postId) {
    throw new OperationRejectedError("create_comment.payload.postId is required");
  }

  if (text === null) {
    throw new OperationRejectedError("create_comment.payload.text is required");
  }

  if (text.trim().length === 0) {
    throw new OperationRejectedError("create_comment.payload.text cannot be empty");
  }

  const existingPost = await tx.post.findUnique({
    where: {
      id: postId,
    },
  });

  if (!existingPost || existingPost.deletedAt) {
    throw new OperationRejectedError("Post not found");
  }

  const existingComment = await tx.comment.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (existingComment) {
    throw new OperationRejectedError("Comment already exists");
  }

  await tx.comment.create({
    data: {
      id: operation.entityId,
      postId,
      text: text.trim(),
      clientCreatedAt: createdAt,
      clientUpdatedAt: createdAt,
      createdByDeviceId: device.id,
      updatedByDeviceId: device.id,
    },
  });

  const change = await tx.serverChange.create({
    data: {
      entityType: "comment",
      entityId: operation.entityId,
      changeType: "comment_created",
      payloadJson: JSON.stringify({
        id: operation.entityId,
        postId,
        text: text.trim(),
        createdAt: createdAt.toISOString(),
        updatedAt: createdAt.toISOString(),
        deletedAt: null,
      }),
    },
  });

  await tx.comment.update({
    where: {
      id: operation.entityId,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

async function applyDeleteComment(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const deletedAt = getDate(operation.payload, "deletedAt") ?? operation.clientCreatedAt;

  const existingComment = await tx.comment.findUnique({
    where: {
      id: operation.entityId,
    },
    include: {
      post: true,
    },
  });

  if (!existingComment || existingComment.post.deletedAt) {
    throw new OperationRejectedError("Comment not found");
  }

  await tx.comment.update({
    where: {
      id: operation.entityId,
    },
    data: {
      deletedAt,
      clientUpdatedAt: deletedAt,
      updatedByDeviceId: device.id,
    },
  });

  const change = await tx.serverChange.create({
    data: {
      entityType: "comment",
      entityId: operation.entityId,
      changeType: "comment_deleted",
      payloadJson: JSON.stringify({
        id: operation.entityId,
        postId: existingComment.postId,
        deletedAt: deletedAt.toISOString(),
      }),
    },
  });

  await tx.comment.update({
    where: {
      id: operation.entityId,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

async function markOperationRejected(
  prisma: PrismaClient,
  device: Device,
  operation: SyncOperationInput,
  reason: string,
): Promise<void> {
  await prisma.syncOperation.upsert({
    where: {
      deviceId_opId: {
        deviceId: device.id,
        opId: operation.opId,
      },
    },
    create: {
      opId: operation.opId,
      deviceId: device.id,
      type: operation.type,
      entityType: operation.entityType,
      entityId: operation.entityId,
      payloadJson: JSON.stringify(operation.payload),
      rejectedAt: new Date(),
      rejectionReason: reason,
    },
    update: {
      rejectedAt: new Date(),
      rejectionReason: reason,
    },
  });
}

function parseSyncRequestBody(
  body: unknown,
  reply: FastifyReply,
): SyncRequestBody | null {
  if (!isRecord(body)) {
    sendBadRequest(reply, "Request body must be an object");
    return null;
  }

  const deviceId = getString(body, "deviceId");
  const lastSyncCursor = getNonNegativeInteger(body, "lastSyncCursor");
  const localChanges = body.localChanges;

  if (!deviceId || lastSyncCursor === null || !Array.isArray(localChanges)) {
    sendBadRequest(reply, "deviceId, lastSyncCursor, and localChanges are required");
    return null;
  }

  if (localChanges.length > MAX_LOCAL_CHANGES) {
    sendBadRequest(reply, `localChanges cannot exceed ${MAX_LOCAL_CHANGES} operations`);
    return null;
  }

  const parsedChanges: SyncOperationInput[] = [];
  for (const [index, change] of localChanges.entries()) {
    const parsed = parseSyncOperation(change);
    if (!parsed) {
      sendBadRequest(reply, `localChanges[${index}] is invalid`);
      return null;
    }

    parsedChanges.push(parsed);
  }

  return {
    deviceId,
    lastSyncCursor,
    localChanges: parsedChanges,
  };
}

function parseSyncOperation(value: unknown): SyncOperationInput | null {
  if (!isRecord(value)) {
    return null;
  }

  const opId = getString(value, "opId");
  const type = getString(value, "type");
  const entityType = getString(value, "entityType");
  const entityId = getString(value, "entityId");
  const clientCreatedAt = getDate(value, "clientCreatedAt");
  const payload = value.payload;

  if (!opId || !type || !entityType || !entityId || !clientCreatedAt || !isRecord(payload)) {
    return null;
  }

  return {
    opId,
    type,
    entityType,
    entityId,
    clientCreatedAt,
    payload,
  };
}

function getString(body: Record<string, unknown>, key: string): string | null {
  const value = body[key];
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function getStringAllowingEmpty(body: Record<string, unknown>, key: string): string | null {
  const value = body[key];
  return typeof value === "string" ? value : null;
}

function getDate(body: Record<string, unknown>, key: string): Date | null {
  const value = getString(body, key);
  if (!value) {
    return null;
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function getBoolean(body: Record<string, unknown>, key: string): boolean | null {
  const value = body[key];
  return typeof value === "boolean" ? value : null;
}

function getMediaOrder(body: Record<string, unknown>, key: string): MediaOrderInput[] | null {
  const value = body[key];
  if (!Array.isArray(value)) {
    return null;
  }

  const result: MediaOrderInput[] = [];
  for (const item of value) {
    if (!isRecord(item)) {
      return null;
    }

    const id = getString(item, "id");
    const sortOrder = getNonNegativeInteger(item, "sortOrder");
    if (!id || sortOrder === null) {
      return null;
    }

    result.push({ id, sortOrder });
  }

  return result;
}

function getNonNegativeInteger(body: Record<string, unknown>, key: string): number | null {
  const value = body[key];
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    return null;
  }

  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseJsonObject(value: string): Record<string, unknown> {
  const parsed = JSON.parse(value) as unknown;
  return isRecord(parsed) ? parsed : {};
}
