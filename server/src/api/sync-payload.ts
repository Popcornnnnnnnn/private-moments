import type { MediaOrderInput, SyncOperationInput, SyncRequestBody } from "./sync-types.js";

export const MAX_LOCAL_CHANGES = 100;

export type SyncRequestParseResult =
  | { ok: true; value: SyncRequestBody }
  | { ok: false; message: string };

export function parseSyncRequestBodyValue(
  body: unknown,
  maxLocalChanges = MAX_LOCAL_CHANGES,
): SyncRequestParseResult {
  if (!isRecord(body)) {
    return { ok: false, message: "Request body must be an object" };
  }

  const deviceId = getString(body, "deviceId");
  const lastSyncCursor = getNonNegativeInteger(body, "lastSyncCursor");
  const localChanges = body.localChanges;

  if (!deviceId || lastSyncCursor === null || !Array.isArray(localChanges)) {
    return { ok: false, message: "deviceId, lastSyncCursor, and localChanges are required" };
  }

  if (localChanges.length > maxLocalChanges) {
    return { ok: false, message: `localChanges cannot exceed ${maxLocalChanges} operations` };
  }

  const parsedChanges: SyncOperationInput[] = [];
  for (const [index, change] of localChanges.entries()) {
    const parsed = parseSyncOperation(change);
    if (!parsed) {
      return { ok: false, message: `localChanges[${index}] is invalid` };
    }

    parsedChanges.push(parsed);
  }

  return {
    ok: true,
    value: {
      deviceId,
      lastSyncCursor,
      localChanges: parsedChanges,
    },
  };
}

export function parseSyncOperation(value: unknown): SyncOperationInput | null {
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

export function getString(body: Record<string, unknown>, key: string): string | null {
  const value = body[key];
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function getStringAllowingEmpty(body: Record<string, unknown>, key: string): string | null {
  const value = body[key];
  return typeof value === "string" ? value : null;
}

export function getOptionalString(body: Record<string, unknown>, key: string): string | null {
  const value = body[key];
  if (value === null || value === undefined) {
    return null;
  }

  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

export function getNullableString(body: Record<string, unknown>, key: string): string | null {
  const value = body[key];
  if (value === null || value === undefined) {
    return null;
  }

  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

export function getDate(body: Record<string, unknown>, key: string): Date | null {
  const value = getString(body, key);
  if (!value) {
    return null;
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function getNullableDate(body: Record<string, unknown>, key: string): Date | null {
  if (body[key] === null || body[key] === undefined) {
    return null;
  }

  return getDate(body, key);
}

export function getBoolean(body: Record<string, unknown>, key: string): boolean | null {
  const value = body[key];
  return typeof value === "boolean" ? value : null;
}

export function getMediaOrder(body: Record<string, unknown>, key: string): MediaOrderInput[] | null {
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

export function getStringArray(
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

export function getIntegerArray(
  body: Record<string, unknown>,
  key: string,
  maxItems: number,
): number[] | null {
  const value = body[key];
  if (!Array.isArray(value) || value.length === 0 || value.length > maxItems) {
    return null;
  }

  const result: number[] = [];
  const seen = new Set<number>();
  for (const item of value) {
    if (typeof item !== "number" || !Number.isInteger(item)) {
      return null;
    }

    if (seen.has(item)) {
      continue;
    }

    seen.add(item);
    result.push(item);
  }

  return result;
}

export function getNonNegativeInteger(body: Record<string, unknown>, key: string): number | null {
  const value = body[key];
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    return null;
  }

  return value;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function parseJsonObject(value: string): Record<string, unknown> {
  const parsed = JSON.parse(value) as unknown;
  return isRecord(parsed) ? parsed : {};
}

export function parseJsonArray(value: string): unknown[] {
  const parsed = JSON.parse(value) as unknown;
  return Array.isArray(parsed) ? parsed : [];
}
