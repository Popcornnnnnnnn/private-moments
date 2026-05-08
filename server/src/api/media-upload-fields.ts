import path from "node:path";

import type { MultipartFields } from "@fastify/multipart";

import {
  MEDIA_KINDS,
  MEDIA_VARIANTS,
  type MediaKind,
  type MediaVariant,
} from "./media-helpers.js";
import { getMultipartInteger, getMultipartString } from "./upload-helpers.js";

const MAX_TRANSCRIPTION_LENGTH = 100_000;

export interface MediaUploadFields {
  mediaId: string;
  postId: string;
  variant: MediaVariant;
  kind: MediaKind;
  mimeType: string | null;
  durationSeconds: number | null;
  transcriptionText: string | null;
  width: number | null;
  height: number | null;
  originalPreserved: boolean;
  sortOrder: number;
  aiLanguage: "auto" | "zh" | "en";
}

export type MediaUploadFieldsResult =
  | { ok: true; fields: MediaUploadFields }
  | { ok: false; message: string };

export function parseMediaUploadFields(fields: MultipartFields): MediaUploadFieldsResult {
  const mediaId = getMultipartString(fields, "mediaId");
  const postId = getMultipartString(fields, "postId");
  const variant = getMultipartString(fields, "variant");
  const kind = getMultipartString(fields, "kind") ?? "image";
  const mimeType = getMultipartString(fields, "mimeType");
  const durationSeconds = getMultipartFloat(fields, "durationSeconds");
  const transcriptionText = getMultipartString(fields, "transcriptionText");
  const width = getMultipartInteger(fields, "width");
  const height = getMultipartInteger(fields, "height");
  const originalPreserved = getMultipartBoolean(fields, "originalPreserved") ?? false;
  const sortOrder = getMultipartInteger(fields, "sortOrder") ?? 0;
  const aiLanguage = parseAILanguage(getMultipartString(fields, "aiLanguage"));

  if (!mediaId || !postId || !variant) {
    return { ok: false, message: "mediaId, postId, and variant are required" };
  }

  if (!MEDIA_VARIANTS.has(variant)) {
    return { ok: false, message: "variant must be one of: compressed, original, thumbnail" };
  }

  if (!MEDIA_KINDS.has(kind)) {
    return { ok: false, message: "kind must be one of: image, video, audio" };
  }

  if (durationSeconds !== null && (durationSeconds < 0 || durationSeconds > 24 * 60 * 60)) {
    return { ok: false, message: "durationSeconds is invalid" };
  }

  if (transcriptionText !== null && transcriptionText.length > MAX_TRANSCRIPTION_LENGTH) {
    return {
      ok: false,
      message: `transcriptionText cannot exceed ${MAX_TRANSCRIPTION_LENGTH} characters`,
    };
  }

  return {
    ok: true,
    fields: {
      mediaId,
      postId,
      variant: variant as MediaVariant,
      kind: kind as MediaKind,
      mimeType,
      durationSeconds,
      transcriptionText,
      width,
      height,
      originalPreserved,
      sortOrder,
      aiLanguage,
    },
  };
}

export function parseAILanguage(value: string | null): "auto" | "zh" | "en" {
  if (value === "zh" || value === "en") {
    return value;
  }

  return "auto";
}

export function getMultipartBoolean(fields: MultipartFields, key: string): boolean | null {
  const value = getMultipartString(fields, key);
  if (value === null) {
    return null;
  }

  if (value === "true") {
    return true;
  }

  if (value === "false") {
    return false;
  }

  return null;
}

export function getMultipartFloat(fields: MultipartFields, key: string): number | null {
  const value = getMultipartString(fields, key);
  if (value === null) {
    return null;
  }

  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

export function relativeMediaPath(
  variant: MediaVariant,
  mediaId: string,
  extension: string,
): string {
  const dir = variant === "original" ? "originals" : variant === "thumbnail" ? "thumbnails" : "compressed";
  return path.join("media", dir, `${mediaId}${extension}`);
}

export function extensionForMediaMimeType(mimetype: string, filename: string): string {
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

  if (mimetype === "video/mp4") {
    return ".mp4";
  }

  if (mimetype === "video/quicktime") {
    return ".mov";
  }

  if (mimetype === "audio/mp4" || mimetype === "audio/x-m4a") {
    return ".m4a";
  }

  if (mimetype === "audio/aac") {
    return ".aac";
  }

  const extension = path.extname(filename).toLowerCase();
  return extension.length > 0 && extension.length <= 10 ? extension : ".bin";
}

export function isAllowedMediaUpload(
  mimetype: string,
  kind: MediaKind,
  variant: MediaVariant,
): boolean {
  if (variant === "thumbnail") {
    return mimetype.startsWith("image/");
  }

  if (kind === "image") {
    return mimetype.startsWith("image/");
  }

  if (kind === "video") {
    return mimetype.startsWith("video/") || mimetype === "application/octet-stream";
  }

  return mimetype.startsWith("audio/") || mimetype === "application/octet-stream";
}
