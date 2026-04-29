import { readdir, stat, statfs } from "node:fs/promises";
import path from "node:path";

import type { DataPaths } from "./data-dir.js";

export interface ServerStorageStats {
  totalBytes: number;
  databaseBytes: number;
  mediaBytes: number;
  logsBytes: number;
  availableBytes: number;
}

export async function collectServerStorageStats(paths: DataPaths): Promise<ServerStorageStats> {
  const [totalBytes, databaseBytes, mediaBytes, logsBytes, availableBytes] = await Promise.all([
    directorySize(paths.dataDir),
    databaseSize(paths.databasePath),
    directorySize(paths.mediaDir),
    directorySize(paths.logsDir),
    availableDiskBytes(paths.dataDir),
  ]);

  return {
    totalBytes,
    databaseBytes,
    mediaBytes,
    logsBytes,
    availableBytes,
  };
}

async function databaseSize(databasePath: string): Promise<number> {
  const relatedFiles = [databasePath, `${databasePath}-wal`, `${databasePath}-shm`];
  const sizes = await Promise.all(relatedFiles.map(fileSize));
  return sizes.reduce((total, size) => total + size, 0);
}

async function availableDiskBytes(directory: string): Promise<number> {
  try {
    const stats = await statfs(directory);
    return stats.bavail * stats.bsize;
  } catch (error) {
    if (isNotFoundError(error)) {
      return 0;
    }

    throw error;
  }
}

async function directorySize(directory: string): Promise<number> {
  let total = 0;
  let entries;

  try {
    entries = await readdir(directory, {
      withFileTypes: true,
    });
  } catch (error) {
    if (isNotFoundError(error)) {
      return 0;
    }

    throw error;
  }

  for (const entry of entries) {
    const absolutePath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      total += await directorySize(absolutePath);
      continue;
    }

    if (entry.isFile()) {
      total += await fileSize(absolutePath);
    }
  }

  return total;
}

async function fileSize(filePath: string): Promise<number> {
  try {
    return (await stat(filePath)).size;
  } catch (error) {
    if (isNotFoundError(error)) {
      return 0;
    }

    throw error;
  }
}

function isNotFoundError(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "ENOENT"
  );
}
