import path from "node:path";

import type { MultipartFields } from "@fastify/multipart";

import { parseMediaVariant } from "./media-helpers.js";
import { getMultipartInteger, getMultipartString } from "./upload-helpers.js";

export interface CheckInMediaUploadFields {
  mediaId: string;
  entryId: string;
  variant: "compressed";
  kind: "image";
  mimeType: string | null;
  sortOrder: number;
}

export type CheckInMediaUploadFieldsResult =
  | { ok: true; fields: CheckInMediaUploadFields }
  | { ok: false; message: string };

export function parseCheckInMediaUploadFields(
  fields: MultipartFields,
): CheckInMediaUploadFieldsResult {
  const mediaId = getMultipartString(fields, "mediaId");
  const entryId = getMultipartString(fields, "entryId");
  const variant = getMultipartString(fields, "variant");
  const kind = getMultipartString(fields, "kind") ?? "image";
  const mimeType = getMultipartString(fields, "mimeType");
  const sortOrder = getMultipartInteger(fields, "sortOrder") ?? 0;

  if (!mediaId || !entryId || !variant) {
    return { ok: false, message: "mediaId, entryId, and variant are required" };
  }

  if (parseMediaVariant(variant) !== "compressed") {
    return {
      ok: false,
      message: "check-in media currently supports compressed image uploads only",
    };
  }

  if (kind !== "image") {
    return { ok: false, message: "check-in media currently supports image uploads only" };
  }

  return {
    ok: true,
    fields: {
      mediaId,
      entryId,
      variant: "compressed",
      kind,
      mimeType,
      sortOrder,
    },
  };
}

export function relativeCheckInMediaPath(mediaId: string, extension: string): string {
  return path.join("media", "checkins", "compressed", `${mediaId}${extension}`);
}

export function extensionForCheckInMediaMimeType(mimetype: string, filename: string): string {
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
