import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

import { SCHEMA_VERSION } from "../config/app-config.js";

export interface DataPaths {
  dataDir: string;
  manifestPath: string;
  databasePath: string;
  mediaDir: string;
  compressedDir: string;
  originalsDir: string;
  thumbnailsDir: string;
  tempDir: string;
  exportsDir: string;
  archiveDir: string;
  archiveStagingDir: string;
  archiveRestoresDir: string;
  archiveImportsDir: string;
  logsDir: string;
}

export interface Manifest {
  app: "PrivateMoments";
  dataVersion: number;
  schemaVersion: number;
  createdAt: string;
  mediaLayoutVersion: number;
}

export async function ensureDataDir(dataDir: string): Promise<DataPaths> {
  const paths = resolveDataPaths(dataDir);

  await Promise.all([
    mkdir(paths.compressedDir, { recursive: true }),
    mkdir(paths.originalsDir, { recursive: true }),
    mkdir(paths.thumbnailsDir, { recursive: true }),
    mkdir(paths.tempDir, { recursive: true }),
    mkdir(paths.exportsDir, { recursive: true }),
    mkdir(paths.archiveStagingDir, { recursive: true }),
    mkdir(paths.archiveRestoresDir, { recursive: true }),
    mkdir(paths.archiveImportsDir, { recursive: true }),
    mkdir(paths.logsDir, { recursive: true }),
  ]);

  await ensureManifest(paths.manifestPath);

  return paths;
}

export function resolveDataPaths(dataDir: string): DataPaths {
  const mediaDir = path.join(dataDir, "media");
  const archiveDir = path.join(dataDir, "archive");

  return {
    dataDir,
    manifestPath: path.join(dataDir, "manifest.json"),
    databasePath: path.join(dataDir, "app.sqlite"),
    mediaDir,
    compressedDir: path.join(mediaDir, "compressed"),
    originalsDir: path.join(mediaDir, "originals"),
    thumbnailsDir: path.join(mediaDir, "thumbnails"),
    tempDir: path.join(mediaDir, "temp"),
    exportsDir: path.join(dataDir, "exports"),
    archiveDir,
    archiveStagingDir: path.join(archiveDir, "staging"),
    archiveRestoresDir: path.join(archiveDir, "restores"),
    archiveImportsDir: path.join(archiveDir, "imports"),
    logsDir: path.join(dataDir, "logs"),
  };
}

async function ensureManifest(manifestPath: string): Promise<void> {
  try {
    await readFile(manifestPath, "utf8");
    return;
  } catch (error) {
    if (!isNotFoundError(error)) {
      throw error;
    }
  }

  const manifest: Manifest = {
    app: "PrivateMoments",
    dataVersion: 1,
    schemaVersion: SCHEMA_VERSION,
    createdAt: new Date().toISOString(),
    mediaLayoutVersion: 1,
  };

  await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
}

function isNotFoundError(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "ENOENT"
  );
}
