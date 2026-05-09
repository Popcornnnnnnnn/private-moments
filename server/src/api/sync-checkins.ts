import type { CheckInEntry, CheckInItem, CheckInMedia, Prisma } from "@prisma/client";

import {
  getBoolean,
  getDate,
  getIntegerArray,
  getNonNegativeInteger,
  getNullableDate,
  getNullableString,
  getString,
  getStringAllowingEmpty,
  parseJsonArray,
} from "./sync-payload.js";
import { OperationRejectedError, type SyncOperationInput } from "./sync-types.js";

const MAX_CHECKIN_NAME_LENGTH = 80;
const MAX_CHECKIN_NOTE_LENGTH = 2_000;
const CHECKIN_TIME_VISUALIZATIONS = new Set(["none", "timeLine", "timeHeatmap"]);

export async function applyCheckInOperation(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<boolean> {
  if (operation.type === "upsert_checkin_item" && operation.entityType === "checkin_item") {
    await applyUpsertCheckInItem(tx, operation);
    return true;
  }

  if (operation.type === "delete_checkin_item" && operation.entityType === "checkin_item") {
    await applyDeleteCheckInItem(tx, operation);
    return true;
  }

  if (operation.type === "upsert_checkin_entry" && operation.entityType === "checkin_entry") {
    await applyUpsertCheckInEntry(tx, operation);
    return true;
  }

  if (operation.type === "delete_checkin_entry" && operation.entityType === "checkin_entry") {
    await applyDeleteCheckInEntry(tx, operation);
    return true;
  }

  if (operation.type === "delete_checkin_media" && operation.entityType === "checkin_media") {
    await applyDeleteCheckInMedia(tx, operation);
    return true;
  }

  return false;
}

async function applyUpsertCheckInItem(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const name = getString(operation.payload, "name");
  const symbolName = getString(operation.payload, "symbolName") ?? "checkmark.circle";
  const colorHex = getString(operation.payload, "colorHex") ?? "#61B88D";
  const recordMode = getString(operation.payload, "recordMode");
  const timeVisualization = getString(operation.payload, "timeVisualization") ?? "none";
  const activeWeekdays = getIntegerArray(operation.payload, "activeWeekdays", 7);
  const sortOrder = getNonNegativeInteger(operation.payload, "sortOrder") ?? 0;
  const defaultShowInTimeline = getBoolean(operation.payload, "defaultShowInTimeline");
  const tagId = getNullableString(operation.payload, "tagId");
  const createdAt = getDate(operation.payload, "createdAt") ?? operation.clientCreatedAt;
  const updatedAt = getDate(operation.payload, "updatedAt") ?? operation.clientCreatedAt;
  const archivedAt = getNullableDate(operation.payload, "archivedAt");
  const deletedAt = getNullableDate(operation.payload, "deletedAt");

  if (!name || name.length > MAX_CHECKIN_NAME_LENGTH) {
    throw new OperationRejectedError("upsert_checkin_item.payload.name is invalid");
  }

  if (recordMode !== "oncePerDay" && recordMode !== "multiplePerDay") {
    throw new OperationRejectedError("upsert_checkin_item.payload.recordMode is invalid");
  }

  if (!CHECKIN_TIME_VISUALIZATIONS.has(timeVisualization)) {
    throw new OperationRejectedError("upsert_checkin_item.payload.timeVisualization is invalid");
  }

  if (recordMode === "multiplePerDay" && timeVisualization === "timeLine") {
    throw new OperationRejectedError("upsert_checkin_item.payload.timeVisualization is incompatible with multiplePerDay");
  }

  if (!activeWeekdays || activeWeekdays.some((weekday) => weekday < 1 || weekday > 7)) {
    throw new OperationRejectedError("upsert_checkin_item.payload.activeWeekdays is invalid");
  }

  if (defaultShowInTimeline === null) {
    throw new OperationRejectedError("upsert_checkin_item.payload.defaultShowInTimeline must be a boolean");
  }

  if (tagId) {
    const tag = await tx.tag.findUnique({
      where: {
        id: tagId,
      },
    });
    if (!tag || tag.isArchived) {
      throw new OperationRejectedError("upsert_checkin_item.payload.tagId must reference an active tag");
    }
  }

  const item = await tx.checkInItem.upsert({
    where: {
      id: operation.entityId,
    },
    create: {
      id: operation.entityId,
      name,
      symbolName,
      colorHex,
      recordMode,
      timeVisualization,
      activeWeekdaysJson: JSON.stringify(activeWeekdays),
      sortOrder,
      defaultShowInTimeline,
      tagId,
      createdAt,
      updatedAt,
      archivedAt,
      deletedAt,
    },
    update: {
      name,
      symbolName,
      colorHex,
      recordMode,
      timeVisualization,
      activeWeekdaysJson: JSON.stringify(activeWeekdays),
      sortOrder,
      defaultShowInTimeline,
      tagId,
      updatedAt,
      archivedAt,
      deletedAt,
    },
  });

  await emitCheckInItemChange(tx, item, "checkin_item_updated");
}

async function applyDeleteCheckInItem(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const deletedAt = getDate(operation.payload, "deletedAt") ?? operation.clientCreatedAt;
  const existing = await tx.checkInItem.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!existing) {
    throw new OperationRejectedError("Check-in item not found");
  }

  const item = await tx.checkInItem.update({
    where: {
      id: operation.entityId,
    },
    data: {
      deletedAt,
      updatedAt: deletedAt,
    },
  });

  const itemEntryIds = await tx.checkInEntry.findMany({
    where: {
      itemId: item.id,
    },
    select: {
      id: true,
    },
  });

  await tx.checkInEntry.updateMany({
    where: {
      itemId: item.id,
      deletedAt: null,
    },
    data: {
      deletedAt,
      updatedAt: deletedAt,
    },
  });

  await tx.checkInMedia.updateMany({
    where: {
      entryId: {
        in: itemEntryIds.map((entry) => entry.id),
      },
      deletedAt: null,
    },
    data: {
      deletedAt,
      status: "deleted",
      updatedAt: deletedAt,
    },
  });

  await emitCheckInItemChange(tx, item, "checkin_item_deleted");
}

async function applyUpsertCheckInEntry(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const itemId = getString(operation.payload, "itemId");
  const occurredAt = getDate(operation.payload, "occurredAt");
  const note = getStringAllowingEmpty(operation.payload, "note") ?? "";
  const showInTimeline = getBoolean(operation.payload, "showInTimeline");
  const createdAt = getDate(operation.payload, "createdAt") ?? operation.clientCreatedAt;
  const updatedAt = getDate(operation.payload, "updatedAt") ?? operation.clientCreatedAt;
  const deletedAt = getNullableDate(operation.payload, "deletedAt");

  if (!itemId) {
    throw new OperationRejectedError("upsert_checkin_entry.payload.itemId is required");
  }

  if (!occurredAt) {
    throw new OperationRejectedError("upsert_checkin_entry.payload.occurredAt must be an ISO date");
  }

  if (note.length > MAX_CHECKIN_NOTE_LENGTH) {
    throw new OperationRejectedError(
      `upsert_checkin_entry.payload.note cannot exceed ${MAX_CHECKIN_NOTE_LENGTH} characters`,
    );
  }

  if (showInTimeline === null) {
    throw new OperationRejectedError("upsert_checkin_entry.payload.showInTimeline must be a boolean");
  }

  const item = await tx.checkInItem.findUnique({
    where: {
      id: itemId,
    },
  });
  if (!item || item.deletedAt) {
    throw new OperationRejectedError("Check-in item not found");
  }

  const entry = await tx.checkInEntry.upsert({
    where: {
      id: operation.entityId,
    },
    create: {
      id: operation.entityId,
      itemId,
      occurredAt,
      note: note.trim(),
      showInTimeline,
      clientCreatedAt: createdAt,
      clientUpdatedAt: updatedAt,
      createdAt,
      updatedAt,
      deletedAt,
    },
    update: {
      itemId,
      occurredAt,
      note: note.trim(),
      showInTimeline,
      clientUpdatedAt: updatedAt,
      updatedAt,
      deletedAt,
    },
  });

  await emitCheckInEntryChange(tx, entry, "checkin_entry_updated");
}

async function applyDeleteCheckInEntry(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const deletedAt = getDate(operation.payload, "deletedAt") ?? operation.clientCreatedAt;
  const existing = await tx.checkInEntry.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!existing) {
    throw new OperationRejectedError("Check-in entry not found");
  }

  if (existing.deletedAt) {
    return;
  }

  const entry = await tx.checkInEntry.update({
    where: {
      id: operation.entityId,
    },
    data: {
      deletedAt,
      clientUpdatedAt: deletedAt,
      updatedAt: deletedAt,
    },
  });

  await tx.checkInMedia.updateMany({
    where: {
      entryId: entry.id,
      deletedAt: null,
    },
    data: {
      deletedAt,
      status: "deleted",
      updatedAt: deletedAt,
    },
  });

  await emitCheckInEntryChange(tx, entry, "checkin_entry_deleted");
}

async function applyDeleteCheckInMedia(
  tx: Prisma.TransactionClient,
  operation: SyncOperationInput,
): Promise<void> {
  const deletedAt = getDate(operation.payload, "deletedAt") ?? operation.clientCreatedAt;
  const existing = await tx.checkInMedia.findUnique({
    where: {
      id: operation.entityId,
    },
  });

  if (!existing) {
    throw new OperationRejectedError("Check-in media not found");
  }

  if (existing.deletedAt) {
    return;
  }

  const media = await tx.checkInMedia.update({
    where: {
      id: operation.entityId,
    },
    data: {
      deletedAt,
      status: "deleted",
      updatedAt: deletedAt,
    },
  });

  await emitCheckInMediaDeletedChange(tx, media, deletedAt);
}

async function emitCheckInItemChange(
  tx: Prisma.TransactionClient,
  item: CheckInItem,
  changeType: "checkin_item_updated" | "checkin_item_deleted",
): Promise<void> {
  const payload =
    changeType === "checkin_item_deleted"
      ? {
          id: item.id,
          deletedAt: (item.deletedAt ?? new Date()).toISOString(),
        }
      : {
          id: item.id,
          name: item.name,
          symbolName: item.symbolName,
          colorHex: item.colorHex,
          recordMode: item.recordMode,
          timeVisualization: item.timeVisualization,
          activeWeekdays: parseJsonArray(item.activeWeekdaysJson),
          sortOrder: item.sortOrder,
          defaultShowInTimeline: item.defaultShowInTimeline,
          tagId: item.tagId,
          createdAt: item.createdAt.toISOString(),
          updatedAt: item.updatedAt.toISOString(),
          archivedAt: item.archivedAt?.toISOString() ?? null,
          deletedAt: item.deletedAt?.toISOString() ?? null,
        };

  const change = await tx.serverChange.create({
    data: {
      entityType: "checkin_item",
      entityId: item.id,
      changeType,
      payloadJson: JSON.stringify(payload),
    },
  });

  await tx.checkInItem.update({
    where: {
      id: item.id,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

async function emitCheckInEntryChange(
  tx: Prisma.TransactionClient,
  entry: CheckInEntry,
  changeType: "checkin_entry_updated" | "checkin_entry_deleted",
): Promise<void> {
  const payload =
    changeType === "checkin_entry_deleted"
      ? {
          id: entry.id,
          itemId: entry.itemId,
          deletedAt: (entry.deletedAt ?? new Date()).toISOString(),
        }
      : {
          id: entry.id,
          itemId: entry.itemId,
          occurredAt: entry.occurredAt.toISOString(),
          note: entry.note,
          showInTimeline: entry.showInTimeline,
          createdAt: entry.createdAt.toISOString(),
          updatedAt: entry.updatedAt.toISOString(),
          deletedAt: entry.deletedAt?.toISOString() ?? null,
        };

  const change = await tx.serverChange.create({
    data: {
      entityType: "checkin_entry",
      entityId: entry.id,
      changeType,
      payloadJson: JSON.stringify(payload),
    },
  });

  await tx.checkInEntry.update({
    where: {
      id: entry.id,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

async function emitCheckInMediaDeletedChange(
  tx: Prisma.TransactionClient,
  media: CheckInMedia,
  deletedAt: Date,
): Promise<void> {
  const change = await tx.serverChange.create({
    data: {
      entityType: "checkin_media",
      entityId: media.id,
      changeType: "checkin_media_deleted",
      payloadJson: JSON.stringify({
        id: media.id,
        entryId: media.entryId,
        deletedAt: deletedAt.toISOString(),
      }),
    },
  });

  await tx.checkInEntry.update({
    where: {
      id: media.entryId,
    },
    data: {
      serverVersion: change.version,
    },
  });
}
