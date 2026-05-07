export type MediaVariant = "compressed" | "original" | "thumbnail";
export type MediaKind = "image" | "video" | "audio";

export const MEDIA_VARIANTS = new Set(["compressed", "original", "thumbnail"]);
export const MEDIA_KINDS = new Set(["image", "video", "audio"]);

export function parseMediaVariant(value: string): MediaVariant | null {
  return MEDIA_VARIANTS.has(value) ? (value as MediaVariant) : null;
}

export function parseMediaIds(value: unknown, limit = 20): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const seen = new Set<string>();
  const mediaIds: string[] = [];
  for (const item of value) {
    if (typeof item !== "string") {
      continue;
    }

    const mediaId = item.trim();
    if (!mediaId || seen.has(mediaId)) {
      continue;
    }

    seen.add(mediaId);
    mediaIds.push(mediaId);

    if (mediaIds.length >= limit) {
      break;
    }
  }

  return mediaIds;
}

export function pathForMediaVariant(
  media: {
    compressedPath: string | null;
    originalPath: string | null;
    thumbnailPath: string | null;
  },
  variant: MediaVariant,
): string | null {
  if (variant === "compressed") {
    return media.compressedPath;
  }

  if (variant === "original") {
    return media.originalPath;
  }

  return media.thumbnailPath;
}

export function contentTypeForMediaPath(relativePath: string): string {
  const extension = relativePath.split(".").pop()?.toLowerCase();
  if (extension === "jpg" || extension === "jpeg") {
    return "image/jpeg";
  }

  if (extension === "png") {
    return "image/png";
  }

  if (extension === "heic") {
    return "image/heic";
  }

  if (extension === "webp") {
    return "image/webp";
  }

  if (extension === "mp4") {
    return "video/mp4";
  }

  if (extension === "mov") {
    return "video/quicktime";
  }

  if (extension === "m4a") {
    return "audio/mp4";
  }

  if (extension === "aac") {
    return "audio/aac";
  }

  return "application/octet-stream";
}

export function mediaUploadErrorCode(error: unknown): string {
  if (error instanceof Error && error.name === "AbortError") {
    return "upload_timeout";
  }

  if (error instanceof Error && /premature close/i.test(error.message)) {
    return "client_premature_close";
  }

  if (typeof error === "object" && error !== null && "code" in error) {
    const code = (error as { code?: unknown }).code;
    if (typeof code === "string" && code.length > 0) {
      return code.toLowerCase();
    }
  }

  return "upload_failed";
}
