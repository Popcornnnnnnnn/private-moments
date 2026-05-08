import { randomUUID } from "node:crypto";

import type { Device, Prisma, PrismaClient } from "@prisma/client";
import type { FastifyInstance, FastifyReply } from "fastify";

import { authenticateDevice, UnauthorizedError } from "../auth/request-auth.js";
import { SCHEMA_VERSION, SERVER_VERSION } from "../config/app-config.js";
import type { FileLogger } from "../logging/file-logger.js";
import {
  blockWritesDuringMaintenance,
  type MaintenanceModeService,
} from "../maintenance/maintenance-mode.js";
import {
  cleanedTagName,
  canonicalDefaultPrimaryTagForId,
  emitPostTagChange,
  emitPostTagStateChange,
  emitTagAliasChange,
  emitTagChange,
  emitTagDeletedChange,
  isValidPostTagRole,
  isValidTagType,
  normalizeTagName,
  upsertPostTag,
} from "../tags/tagging.js";
import { sendBadRequest, sendForbidden, sendUnauthorized } from "./http-errors.js";
import { shouldReplayPreviouslyUnsupportedOperation } from "./sync-operations.js";

const MAX_LOCAL_CHANGES = 100;
const MAX_COMMENT_LENGTH = 500;
const MAX_TRANSCRIPTION_LENGTH = 100_000;
const MAX_TAG_ALIAS_LENGTH = 40;
const MAX_AI_TITLE_LENGTH = 40;

interface SyncRouteContext {
  prisma: PrismaClient;
  fileLogger: FileLogger;
  maintenanceMode: MaintenanceModeService;
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
    const maintenanceReply = blockWritesDuringMaintenance(reply, context.maintenanceMode);
    if (maintenanceReply) {
      return maintenanceReply;
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

  const shouldReplayUnsupportedRejection =
    existing?.rejectedAt && shouldReplayPreviouslyUnsupportedOperation(existing, operation);

  if (existing?.rejectedAt && !shouldReplayUnsupportedRejection) {
    return {
      accepted: false,
      reason: existing.rejectionReason ?? "Operation was previously rejected",
    };
  }

  try {
    await prisma.$transaction(async (tx) => {
      const syncOperation = existing
        ? await tx.syncOperation.update({
            where: {
              id: existing.id,
            },
            data: {
              type: operation.type,
              entityType: operation.entityType,
              entityId: operation.entityId,
              payloadJson: JSON.stringify(operation.payload),
              rejectedAt: null,
              rejectionReason: null,
            },
          })
        : await tx.syncOperation.create({
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
          rejectedAt: null,
          rejectionReason: null,
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

  if (operation.type === "insert_ai_title" && operation.entityType === "post") {
    await applyInsertAITitle(tx, device, operation);
    return;
  }

  if (operation.type === "update_post_favorite" && operation.entityType === "post") {
    await applyUpdatePostFavorite(tx, device, operation);
    return;
  }

  if (operation.type === "update_post_pin" && operation.entityType === "post") {
    await applyUpdatePostPin(tx, device, operation);
    return;
  }

  if (operation.type === "delete_post" && operation.entityType === "post") {
    await applyDeletePost(tx, device, operation);
    return;
  }

  if (operation.type === "update_media_transcription" && operation.entityType === "media") {
    await applyUpdateMediaTranscription(tx, device, operation);
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

  if (operation.type === "upsert_tag" && operation.entityType === "tag") {
    await applyUpsertTag(tx, operation);
    return;
  }

  if (operation.type === "archive_tag" && operation.entityType === "tag") {
    await applyArchiveTag(tx, operation);
    return;
  }

  if (operation.type === "restore_tag" && operation.entityType === "tag") {
    await applyRestoreTag(tx, operation);
    return;
  }

  if (operation.type === "delete_tag" && operation.entityType === "tag") {
    await applyDeleteTag(tx, operation);
    return;
  }

  if (operation.type === "merge_tag" && operation.entityType === "tag") {
    await applyMergeTag(tx, operation);
    return;
  }

  if (operation.type === "upsert_tag_alias" && operation.entityType === "tag_alias") {
    await applyUpsertTagAlias(tx, operation);
    return;
  }

  if (operation.type === "delete_tag_alias" && operation.entityType === "tag_alias") {
    await applyDeleteTagAlias(tx, operation);
    return;
  }

  if (operation.type === "set_post_tags" && operation.entityType === "post") {
    await applySetPostTags(tx, operation);
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
  const isPinned = getBoolean(operation.payload, "isPinned") ?? false;
  const pinnedAt = getNullableDate(operation.payload, "pinnedAt") ?? (isPinned ? operation.clientCreatedAt : null);
  const primaryTagId = getNullableString(operation.payload, "primaryTagId");

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
      isPinned,
      pinnedAt,
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
        isPinned,
        pinnedAt: pinnedAt?.toISOString() ?? null,
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

  if (primaryTagId) {
    const tag = await tx.tag.findUnique({
      where: {
        id: primaryTagId,
      },
    });
    if (!tag || tag.type !== "primary" || tag.isArchived) {
      throw new OperationRejectedError("create_post.payload.primaryTagId must reference an active primary tag");
    }

    await upsertPostTag(tx, {
      postId: operation.entityId,
      tagId: primaryTagId,
      role: "primary",
      source: "manual",
      confidence: null,
      aiSummaryId: null,
      now: operation.clientCreatedAt,
    });
  }
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
        isPinned: existingPost.isPinned,
        pinnedAt: existingPost.pinnedAt?.toISOString() ?? null,
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

async function applyInsertAITitle(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const summaryId = getString(operation.payload, "summaryId");
  const mediaId = getString(operation.payload, "mediaId");
  const insertedAt = getDate(operation.payload, "insertedAt") ?? operation.clientCreatedAt;

  if (!summaryId) {
    throw new OperationRejectedError("insert_ai_title.payload.summaryId is required");
  }

  if (!mediaId) {
    throw new OperationRejectedError("insert_ai_title.payload.mediaId is required");
  }

  const [post, summary] = await Promise.all([
    tx.post.findUnique({
      where: {
        id: operation.entityId,
      },
      include: {
        media: {
          where: {
            deletedAt: null,
          },
          orderBy: {
            sortOrder: "asc",
          },
          select: {
            id: true,
            sortOrder: true,
          },
        },
      },
    }),
    tx.aiSummary.findUnique({
      where: {
        id: summaryId,
      },
      include: {
        media: true,
      },
    }),
  ]);

  if (!post || post.deletedAt) {
    return;
  }

  if (
    !summary ||
    summary.deletedAt ||
    summary.status !== "ready" ||
    summary.postId !== post.id ||
    summary.mediaId !== mediaId ||
    summary.media.kind !== "audio" ||
    summary.media.deletedAt
  ) {
    return;
  }

  const title = cleanedAITitle(summary.documentTitle);
  if (!title || hasLeadingMarkdownTitle(post.text)) {
    return;
  }

  const text = insertAITitleIntoText(title, post.text);
  await tx.post.update({
    where: {
      id: post.id,
    },
    data: {
      text,
      clientUpdatedAt: insertedAt,
      updatedByDeviceId: device.id,
    },
  });

  const mediaOrder = post.media.map((media) => ({
    id: media.id,
    sortOrder: media.sortOrder,
  }));
  const change = await tx.serverChange.create({
    data: {
      entityType: "post",
      entityId: post.id,
      changeType: "post_updated",
      payloadJson: JSON.stringify({
        id: post.id,
        text,
        isFavorite: post.isFavorite,
        isPinned: post.isPinned,
        pinnedAt: post.pinnedAt?.toISOString() ?? null,
        occurredAt: post.occurredAt.toISOString(),
        updatedAt: insertedAt.toISOString(),
        updateSource: "ai_title",
        media: mediaOrder,
        deletedAt: null,
      }),
    },
  });

  await tx.post.update({
    where: {
      id: post.id,
    },
    data: {
      serverVersion: change.version,
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

async function applyUpdatePostPin(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const isPinned = getBoolean(operation.payload, "isPinned");
  const updatedAt = getDate(operation.payload, "updatedAt") ?? operation.clientCreatedAt;
  const pinnedAt = getNullableDate(operation.payload, "pinnedAt") ?? (isPinned ? updatedAt : null);

  if (isPinned === null) {
    throw new OperationRejectedError("update_post_pin.payload.isPinned must be a boolean");
  }

  if (isPinned && !pinnedAt) {
    throw new OperationRejectedError("update_post_pin.payload.pinnedAt must be an ISO date when isPinned is true");
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
      isPinned,
      pinnedAt: isPinned ? pinnedAt : null,
      clientUpdatedAt: updatedAt,
      updatedByDeviceId: device.id,
    },
  });

  const change = await tx.serverChange.create({
    data: {
      entityType: "post",
      entityId: operation.entityId,
      changeType: "post_pin_updated",
      payloadJson: JSON.stringify({
        id: operation.entityId,
        isPinned,
        pinnedAt: isPinned ? pinnedAt!.toISOString() : null,
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

  await tx.comment.updateMany({
    where: {
      postId: operation.entityId,
      deletedAt: null,
    },
    data: {
      deletedAt,
      clientUpdatedAt: operation.clientCreatedAt,
      updatedByDeviceId: device.id,
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

async function applyUpdateMediaTranscription(
  tx: Prisma.TransactionClient,
  device: Device,
  operation: SyncOperationInput,
): Promise<void> {
  const postId = getString(operation.payload, "postId");
  const transcriptionText = getStringAllowingEmpty(operation.payload, "transcriptionText");
  const updatedAt = getDate(operation.payload, "updatedAt") ?? operation.clientCreatedAt;

  if (!postId) {
    throw new OperationRejectedError("update_media_transcription.payload.postId is required");
  }

  if (transcriptionText === null) {
    throw new OperationRejectedError(
      "update_media_transcription.payload.transcriptionText is required",
    );
  }

  const trimmedText = transcriptionText.trim();
  if (trimmedText.length === 0) {
    throw new OperationRejectedError(
      "update_media_transcription.payload.transcriptionText cannot be empty",
    );
  }

  if (trimmedText.length > MAX_TRANSCRIPTION_LENGTH) {
    throw new OperationRejectedError(
      `update_media_transcription.payload.transcriptionText cannot exceed ${MAX_TRANSCRIPTION_LENGTH} characters`,
    );
  }

  const media = await tx.media.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!media || media.deletedAt || media.postId !== postId) {
    throw new OperationRejectedError("Media not found");
  }

  await tx.media.update({
    where: {
      id: operation.entityId,
    },
    data: {
      transcriptionText: trimmedText,
      updatedAt,
    },
  });

  const change = await tx.serverChange.create({
    data: {
      entityType: "media",
      entityId: operation.entityId,
      changeType: "media_transcription_updated",
      payloadJson: JSON.stringify({
        id: operation.entityId,
        postId,
        transcriptionText: trimmedText,
        updatedAt: updatedAt.toISOString(),
      }),
    },
  });

  await tx.post.update({
    where: {
      id: postId,
    },
    data: {
      serverVersion: change.version,
      updatedByDeviceId: device.id,
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

  const trimmedText = text.trim();
  if (trimmedText.length === 0) {
    throw new OperationRejectedError("create_comment.payload.text cannot be empty");
  }

  if (trimmedText.length > MAX_COMMENT_LENGTH) {
    throw new OperationRejectedError(
      `create_comment.payload.text cannot exceed ${MAX_COMMENT_LENGTH} characters`,
    );
  }

  const post = await tx.post.findUnique({
    where: {
      id: postId,
    },
  });

  if (!post || post.deletedAt) {
    throw new OperationRejectedError("Parent post not found");
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
      text: trimmedText,
      createdAt,
      updatedAt: createdAt,
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
        text: trimmedText,
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
  });

  if (!existingComment) {
    throw new OperationRejectedError("Comment not found");
  }

  if (existingComment.deletedAt) {
    return;
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

async function applyUpsertTag(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const type = getString(operation.payload, "type");
  const rawName = getString(operation.payload, "name");
  const colorHex = getOptionalString(operation.payload, "colorHex");
  const updatedAt = getDate(operation.payload, "updatedAt") ?? operation.clientCreatedAt;
  const isDefault = getBoolean(operation.payload, "isDefault") ?? false;
  const aiUsableAsPrimary = getBoolean(operation.payload, "aiUsableAsPrimary") ?? false;

  if (!type || !isValidTagType(type)) {
    throw new OperationRejectedError("upsert_tag.payload.type must be primary or topic");
  }

  const defaultPrimaryTag = canonicalDefaultPrimaryTagForId(operation.entityId);
  const name = defaultPrimaryTag ? defaultPrimaryTag.name : rawName ? cleanedTagName(rawName) : null;
  if (!name) {
    throw new OperationRejectedError("upsert_tag.payload.name is invalid");
  }

  const finalType = defaultPrimaryTag ? "primary" : type;
  const finalColorHex = defaultPrimaryTag ? colorHex ?? defaultPrimaryTag.colorHex : colorHex;
  const finalIsDefault = defaultPrimaryTag ? true : isDefault;
  const finalAiUsableAsPrimary = defaultPrimaryTag ? true : finalType === "primary" ? aiUsableAsPrimary : false;
  const normalizedName = normalizeTagName(name);
  const existingByName = await tx.tag.findUnique({
    where: {
      normalizedName,
    },
  });
  if (existingByName && existingByName.id !== operation.entityId) {
    throw new OperationRejectedError("Tag name already exists");
  }

  const tag = await tx.tag.upsert({
    where: {
      id: operation.entityId,
    },
    create: {
      id: operation.entityId,
      type: finalType,
      name,
      normalizedName,
      colorHex: finalColorHex,
      isDefault: finalIsDefault,
      isArchived: false,
      aiUsableAsPrimary: finalAiUsableAsPrimary,
      updatedAt,
    },
    update: {
      type: finalType,
      name,
      normalizedName,
      colorHex: finalColorHex,
      isDefault: finalIsDefault,
      isArchived: false,
      archivedAt: null,
      aiUsableAsPrimary: finalAiUsableAsPrimary,
    },
  });

  await emitTagChange(tx, tag);
}

async function applyArchiveTag(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const archivedAt = getDate(operation.payload, "archivedAt") ?? operation.clientCreatedAt;
  const tag = await tx.tag.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!tag) {
    throw new OperationRejectedError("Tag not found");
  }

  const updated = await tx.tag.update({
    where: {
      id: operation.entityId,
    },
    data: {
      isArchived: true,
      archivedAt,
    },
  });
  await emitTagChange(tx, updated);
}

async function applyRestoreTag(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const tag = await tx.tag.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!tag) {
    throw new OperationRejectedError("Tag not found");
  }

  const updated = await tx.tag.update({
    where: {
      id: operation.entityId,
    },
    data: {
      isArchived: false,
      archivedAt: null,
    },
  });
  await emitTagChange(tx, updated);
}

async function applyDeleteTag(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const deletedAt = getDate(operation.payload, "deletedAt") ?? operation.clientCreatedAt;
  const tag = await tx.tag.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!tag) {
    return;
  }

  if (tag.isDefault) {
    throw new OperationRejectedError("Default primary tags cannot be deleted");
  }

  if (!tag.isArchived) {
    throw new OperationRejectedError("Only archived tags can be deleted");
  }

  const activeAssignments = await tx.postTag.findMany({
    where: {
      tagId: tag.id,
      deletedAt: null,
    },
  });

  for (const assignment of activeAssignments) {
    const deleted = await tx.postTag.update({
      where: {
        id: assignment.id,
      },
      data: {
        updatedAt: deletedAt,
        deletedAt,
      },
    });
    await emitPostTagChange(tx, deleted, "post_tag_deleted");
  }

  const activeAliases = await tx.tagAlias.findMany({
    where: {
      tagId: tag.id,
      deletedAt: null,
    },
  });

  for (const alias of activeAliases) {
    const deletedAlias = await tx.tagAlias.update({
      where: {
        id: alias.id,
      },
      data: {
        deletedAt,
      },
    });
    await emitTagAliasChange(tx, deletedAlias, "tag_alias_deleted");
  }

  await tx.tag.delete({
    where: {
      id: tag.id,
    },
  });
  await emitTagDeletedChange(tx, tag, deletedAt);
}

async function applyMergeTag(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const targetTagId = getString(operation.payload, "targetTagId");
  const rawAlias = getOptionalString(operation.payload, "alias");
  const mergedAt = getDate(operation.payload, "mergedAt") ?? operation.clientCreatedAt;

  if (!targetTagId) {
    throw new OperationRejectedError("merge_tag.payload.targetTagId is required");
  }

  if (targetTagId === operation.entityId) {
    throw new OperationRejectedError("merge_tag target must be different from source");
  }

  const [sourceTag, targetTag] = await Promise.all([
    tx.tag.findUnique({ where: { id: operation.entityId } }),
    tx.tag.findUnique({ where: { id: targetTagId } }),
  ]);

  if (!sourceTag || sourceTag.type !== "topic") {
    throw new OperationRejectedError("merge_tag source must be an existing topic tag");
  }

  if (!targetTag || targetTag.type !== "topic" || targetTag.isArchived) {
    throw new OperationRejectedError("merge_tag target must be an active topic tag");
  }

  const sourceAssignments = await tx.postTag.findMany({
    where: {
      tagId: sourceTag.id,
      deletedAt: null,
    },
  });

  for (const sourceAssignment of sourceAssignments) {
    const existingTarget = await tx.postTag.findUnique({
      where: {
        postId_tagId: {
          postId: sourceAssignment.postId,
          tagId: targetTag.id,
        },
      },
    });

    if (existingTarget) {
      const revivedTarget = await tx.postTag.update({
        where: {
          id: existingTarget.id,
        },
        data: {
          role: "topic",
          source: existingTarget.deletedAt ? sourceAssignment.source : existingTarget.source,
          confidence: existingTarget.deletedAt ? sourceAssignment.confidence : existingTarget.confidence,
          aiSummaryId: existingTarget.deletedAt ? sourceAssignment.aiSummaryId : existingTarget.aiSummaryId,
          updatedAt: mergedAt,
          deletedAt: null,
        },
      });
      await emitPostTagChange(tx, revivedTarget, "post_tag_updated");

      const deletedSource = await tx.postTag.update({
        where: {
          id: sourceAssignment.id,
        },
        data: {
          updatedAt: mergedAt,
          deletedAt: mergedAt,
        },
      });
      await emitPostTagChange(tx, deletedSource, "post_tag_deleted");
      continue;
    }

    const moved = await tx.postTag.update({
      where: {
        id: sourceAssignment.id,
      },
      data: {
        tagId: targetTag.id,
        role: "topic",
        updatedAt: mergedAt,
      },
    });
    await emitPostTagChange(tx, moved, "post_tag_updated");
  }

  const aliasName = cleanedTagName(rawAlias ?? sourceTag.name);
  if (aliasName) {
    const normalizedAlias = normalizeTagName(aliasName);
    const existingAlias = await tx.tagAlias.findUnique({
      where: {
        normalizedAlias,
      },
    });
    const conflictingTag = await tx.tag.findUnique({
      where: {
        normalizedName: normalizedAlias,
      },
    });

    if (!conflictingTag || conflictingTag.id === targetTag.id || conflictingTag.id === sourceTag.id) {
      if (!existingAlias || existingAlias.tagId === targetTag.id) {
        const alias = await tx.tagAlias.upsert({
          where: {
            normalizedAlias,
          },
          create: {
            id: randomUUID(),
            tagId: targetTag.id,
            alias: aliasName,
            normalizedAlias,
            deletedAt: null,
          },
          update: {
            tagId: targetTag.id,
            alias: aliasName,
            deletedAt: null,
          },
        });
        await emitTagAliasChange(tx, alias, "tag_alias_updated");
      }
    }
  }

  const archived = await tx.tag.update({
    where: {
      id: sourceTag.id,
    },
    data: {
      isArchived: true,
      archivedAt: mergedAt,
      updatedAt: mergedAt,
    },
  });
  await emitTagChange(tx, archived);
}

async function applyUpsertTagAlias(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const tagId = getString(operation.payload, "tagId");
  const rawAlias = getString(operation.payload, "alias");

  if (!tagId) {
    throw new OperationRejectedError("upsert_tag_alias.payload.tagId is required");
  }

  const alias = rawAlias ? cleanedTagName(rawAlias) : null;
  if (!alias || alias.length > MAX_TAG_ALIAS_LENGTH) {
    throw new OperationRejectedError("upsert_tag_alias.payload.alias is invalid");
  }

  const tag = await tx.tag.findUnique({
    where: {
      id: tagId,
    },
  });
  if (!tag || tag.isArchived) {
    throw new OperationRejectedError("Tag not found");
  }

  const normalizedAlias = normalizeTagName(alias);
  const existingByAlias = await tx.tagAlias.findUnique({
    where: {
      normalizedAlias,
    },
  });
  if (existingByAlias && existingByAlias.id !== operation.entityId) {
    throw new OperationRejectedError("Tag alias already exists");
  }

  const existingTag = await tx.tag.findUnique({
    where: {
      normalizedName: normalizedAlias,
    },
  });
  if (existingTag && existingTag.id !== tagId) {
    throw new OperationRejectedError("Tag alias conflicts with another tag");
  }

  const saved = await tx.tagAlias.upsert({
    where: {
      id: operation.entityId,
    },
    create: {
      id: operation.entityId,
      tagId,
      alias,
      normalizedAlias,
      deletedAt: null,
    },
    update: {
      tagId,
      alias,
      normalizedAlias,
      deletedAt: null,
    },
  });

  await emitTagAliasChange(tx, saved, "tag_alias_updated");
}

async function applyDeleteTagAlias(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const deletedAt = getDate(operation.payload, "deletedAt") ?? operation.clientCreatedAt;
  const alias = await tx.tagAlias.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!alias) {
    throw new OperationRejectedError("Tag alias not found");
  }

  const deleted = await tx.tagAlias.update({
    where: {
      id: operation.entityId,
    },
    data: {
      deletedAt,
    },
  });

  await emitTagAliasChange(tx, deleted, "tag_alias_deleted");
}

async function applySetPostTags(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const updatedAt = getDate(operation.payload, "updatedAt") ?? operation.clientCreatedAt;
  const primaryTagId = getNullableString(operation.payload, "primaryTagId");
  const topicTagIds = getStringArray(operation.payload, "topicTagIds", 20);

  if (topicTagIds === null) {
    throw new OperationRejectedError("set_post_tags.payload.topicTagIds must be an array");
  }

  const post = await tx.post.findUnique({
    where: {
      id: operation.entityId,
    },
    include: {
      tags: {
        where: {
          deletedAt: null,
        },
      },
    },
  });
  if (!post || post.deletedAt) {
    throw new OperationRejectedError("Post not found");
  }

  const desiredTagIds = new Set(topicTagIds);
  if (primaryTagId) {
    desiredTagIds.add(primaryTagId);
  }

  const tags = desiredTagIds.size > 0
    ? await tx.tag.findMany({
        where: {
          id: {
            in: Array.from(desiredTagIds),
          },
          isArchived: false,
        },
      })
    : [];
  const tagsById = new Map(tags.map((tag) => [tag.id, tag]));

  if (primaryTagId) {
    const tag = tagsById.get(primaryTagId);
    if (!tag || tag.type !== "primary") {
      throw new OperationRejectedError("set_post_tags.payload.primaryTagId must reference an active primary tag");
    }
  }

  for (const topicTagId of topicTagIds) {
    const tag = tagsById.get(topicTagId);
    if (!tag || tag.type !== "topic") {
      throw new OperationRejectedError("set_post_tags.payload.topicTagIds must reference active topic tags");
    }
  }

  const desired = new Map<string, "primary" | "topic">();
  if (primaryTagId) {
    desired.set(primaryTagId, "primary");
  }
  for (const topicTagId of topicTagIds) {
    desired.set(topicTagId, "topic");
  }

  for (const existing of post.tags) {
    const desiredRole = desired.get(existing.tagId);
    if (desiredRole === existing.role) {
      if (existing.source !== "manual") {
        const updated = await tx.postTag.update({
          where: {
            id: existing.id,
          },
          data: {
            source: "manual",
            confidence: null,
            aiSummaryId: null,
            updatedAt,
          },
        });
        await emitPostTagChange(tx, updated, "post_tag_updated");
      }
      desired.delete(existing.tagId);
      continue;
    }

    const deleted = await tx.postTag.update({
      where: {
        id: existing.id,
      },
      data: {
        deletedAt: updatedAt,
        updatedAt,
      },
    });
    await emitPostTagChange(tx, deleted, "post_tag_deleted");
  }

  for (const [tagId, role] of desired) {
    if (!isValidPostTagRole(role)) {
      continue;
    }

    await upsertPostTag(tx, {
      postId: post.id,
      tagId,
      role,
      source: "manual",
      confidence: null,
      aiSummaryId: null,
      now: updatedAt,
    });
  }

  await tx.post.update({
    where: {
      id: post.id,
    },
    data: {
      tagsUserEditedAt: updatedAt,
      clientUpdatedAt: updatedAt,
    },
  });
  await emitPostTagStateChange(tx, post.id, {
    aiTagProcessedAt: post.aiTagProcessedAt,
    tagsUserEditedAt: updatedAt,
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

function getOptionalString(body: Record<string, unknown>, key: string): string | null {
  const value = body[key];
  if (value === null || value === undefined) {
    return null;
  }

  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function getNullableString(body: Record<string, unknown>, key: string): string | null {
  const value = body[key];
  if (value === null || value === undefined) {
    return null;
  }

  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function getDate(body: Record<string, unknown>, key: string): Date | null {
  const value = getString(body, key);
  if (!value) {
    return null;
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function getNullableDate(body: Record<string, unknown>, key: string): Date | null {
  if (body[key] === null || body[key] === undefined) {
    return null;
  }

  return getDate(body, key);
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

function getStringArray(
  body: Record<string, unknown>,
  key: string,
  maxItems: number,
): string[] | null {
  const value = body[key];
  if (!Array.isArray(value) || value.length > maxItems) {
    return null;
  }

  const result: string[] = [];
  const seen = new Set<string>();
  for (const item of value) {
    if (typeof item !== "string") {
      return null;
    }

    const trimmed = item.trim();
    if (!trimmed || seen.has(trimmed)) {
      continue;
    }

    seen.add(trimmed);
    result.push(trimmed);
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

function cleanedAITitle(value: string | null): string | null {
  if (!value) {
    return null;
  }

  const withoutMarker = value.replace(/^\s*#{1,6}\s*/u, "");
  const title = withoutMarker.replace(/\s+/gu, " ").trim();
  if (!title || Array.from(title).length > MAX_AI_TITLE_LENGTH) {
    return null;
  }

  return title;
}

function hasLeadingMarkdownTitle(text: string): boolean {
  const lines = text.split(/\r?\n/u);
  for (const line of lines) {
    if (line.trim().length === 0) {
      continue;
    }

    return markdownHeadingText(line) !== null;
  }

  return false;
}

function markdownHeadingText(line: string): string | null {
  let value: string | null = null;
  if (line.startsWith("## ")) {
    value = line.slice(3);
  } else if (line.startsWith("# ")) {
    value = line.slice(2);
  }

  if (value === null) {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function insertAITitleIntoText(title: string, text: string): string {
  const heading = `## ${title}`;
  if (text.trim().length === 0) {
    return heading;
  }

  return `${heading}\n\n${text}`;
}
