import { createHash, randomUUID } from "node:crypto";
import { createWriteStream } from "node:fs";
import { access, mkdir, rename, rm } from "node:fs/promises";
import path from "node:path";
import { Transform } from "node:stream";
import { pipeline } from "node:stream/promises";

import type { MultipartFields, MultipartFile, MultipartValue } from "@fastify/multipart";

export async function fileExists(absolutePath: string): Promise<boolean> {
  try {
    await access(absolutePath);
    return true;
  } catch {
    return false;
  }
}

export function isPathInside(parent: string, child: string): boolean {
  const relative = path.relative(parent, child);
  return Boolean(relative) && !relative.startsWith("..") && !path.isAbsolute(relative);
}

export async function writeUploadedFile(
  file: MultipartFile,
  absolutePath: string,
  options: { timeoutMs: number; timeoutMessage: string },
): Promise<{ sizeBytes: number; checksum: string }> {
  const tracker = createUploadHashTracker();
  const tempPath = tempUploadPath(absolutePath);
  const controller = new AbortController();
  const timeout = setTimeout(() => {
    controller.abort(new Error(options.timeoutMessage));
  }, options.timeoutMs);
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

export function createUploadHashTracker(): {
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

export function tempUploadPath(absolutePath: string): string {
  const directory = path.dirname(absolutePath);
  const extension = path.extname(absolutePath) || ".upload";
  const baseName = path.basename(absolutePath, extension);
  return path.join(directory, `.${baseName}.${process.pid}.${Date.now()}.${randomUUID()}.tmp`);
}

export function parseContentLength(value: string | string[] | undefined): number | null {
  const rawValue = Array.isArray(value) ? value[0] : value;
  if (!rawValue) {
    return null;
  }

  const parsed = Number(rawValue);
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : null;
}

export function getMultipartString(fields: MultipartFields, key: string): string | null {
  const field = firstMultipartField(fields[key]);
  if (!field || field.type !== "field" || typeof field.value !== "string") {
    return null;
  }

  const trimmed = field.value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function getMultipartInteger(fields: MultipartFields, key: string): number | null {
  const value = getMultipartString(fields, key);
  if (value === null) {
    return null;
  }

  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : null;
}

export function firstMultipartField(
  field: MultipartFields[string],
): MultipartValue | MultipartFile | undefined {
  return Array.isArray(field) ? field[0] : field;
}
