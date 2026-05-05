import { mkdir, readFile, writeFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import path from "node:path";

import type { DataPaths } from "../storage/data-dir.js";

export interface ArchiveConfig {
  repositoryPath: string | null;
  keyFilePath: string | null;
  schedule: {
    enabled: boolean;
    timeOfDay: string;
    lastRunAt: string | null;
    nextRunAt: string | null;
  };
  updatedAt: string | null;
}

interface ArchiveConfigFile {
  repositoryPath?: unknown;
  keyFilePath?: unknown;
  schedule?: {
    enabled?: unknown;
    timeOfDay?: unknown;
    lastRunAt?: unknown;
  };
  updatedAt?: unknown;
}

export class ArchiveConfigService {
  constructor(private readonly paths: DataPaths) {}

  async read(): Promise<ArchiveConfig> {
    const file = await this.readFile();
    return normalizeConfig(file);
  }

  async configureRepository(repositoryPath: string): Promise<ArchiveConfig> {
    const current = await this.read();
    const normalizedRepository = path.resolve(repositoryPath);
    const next: ArchiveConfig = {
      ...current,
      repositoryPath: normalizedRepository,
      keyFilePath: path.join(normalizedRepository, ".private-moments-restic-key"),
      updatedAt: new Date().toISOString(),
    };
    await this.write(next);
    return next;
  }

  async updateSchedule(input: { enabled: boolean; timeOfDay: string }): Promise<ArchiveConfig> {
    const current = await this.read();
    const next: ArchiveConfig = {
      ...current,
      schedule: {
        enabled: input.enabled,
        timeOfDay: input.timeOfDay,
        lastRunAt: current.schedule.lastRunAt,
        nextRunAt: computeNextRun(input.enabled, input.timeOfDay, new Date()),
      },
      updatedAt: new Date().toISOString(),
    };
    await this.write(next);
    return next;
  }

  async markScheduleRun(at: Date): Promise<ArchiveConfig> {
    const current = await this.read();
    const next: ArchiveConfig = {
      ...current,
      schedule: {
        ...current.schedule,
        lastRunAt: at.toISOString(),
        nextRunAt: computeNextRun(current.schedule.enabled, current.schedule.timeOfDay, at),
      },
      updatedAt: new Date().toISOString(),
    };
    await this.write(next);
    return next;
  }

  async ensureKeyFile(): Promise<string> {
    const config = await this.read();
    if (!config.repositoryPath || !config.keyFilePath) {
      throw new Error("Backup repository is not configured");
    }

    await mkdir(config.repositoryPath, { recursive: true });

    try {
      const existing = await readFile(config.keyFilePath, "utf8");
      if (existing.trim().length >= 24) {
        return config.keyFilePath;
      }
    } catch (error) {
      if (!isNotFoundError(error)) {
        throw error;
      }
    }

    const key = randomUUID() + randomUUID();
    await writeFile(config.keyFilePath, `${key}\n`, { encoding: "utf8", mode: 0o600 });
    return config.keyFilePath;
  }

  private async readFile(): Promise<ArchiveConfigFile> {
    try {
      return JSON.parse(await readFile(this.configPath(), "utf8")) as ArchiveConfigFile;
    } catch (error) {
      if (isNotFoundError(error)) {
        return {};
      }

      throw error;
    }
  }

  private async write(config: ArchiveConfig): Promise<void> {
    await mkdir(this.paths.archiveDir, { recursive: true });
    await writeFile(this.configPath(), `${JSON.stringify(config, null, 2)}\n`, "utf8");
  }

  private configPath(): string {
    return path.join(this.paths.archiveDir, "archive-config.json");
  }
}

export function computeNextRun(enabled: boolean, timeOfDay: string, now: Date): string | null {
  if (!enabled) {
    return null;
  }

  const match = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(timeOfDay);
  if (!match) {
    return null;
  }

  const next = new Date(now);
  next.setHours(Number(match[1]), Number(match[2]), 0, 0);
  if (next <= now) {
    next.setDate(next.getDate() + 1);
  }

  return next.toISOString();
}

export function isValidScheduleTime(value: string): boolean {
  return /^([01]\d|2[0-3]):([0-5]\d)$/.test(value);
}

function normalizeConfig(file: ArchiveConfigFile): ArchiveConfig {
  const schedule = file.schedule && typeof file.schedule === "object" ? file.schedule : {};
  const enabled = typeof schedule.enabled === "boolean" ? schedule.enabled : false;
  const timeOfDay = typeof schedule.timeOfDay === "string" && isValidScheduleTime(schedule.timeOfDay)
    ? schedule.timeOfDay
    : "03:30";
  const lastRunAt = typeof schedule.lastRunAt === "string" ? schedule.lastRunAt : null;

  return {
    repositoryPath: typeof file.repositoryPath === "string" ? path.resolve(file.repositoryPath) : null,
    keyFilePath: typeof file.keyFilePath === "string" ? path.resolve(file.keyFilePath) : null,
    schedule: {
      enabled,
      timeOfDay,
      lastRunAt,
      nextRunAt: computeNextRun(enabled, timeOfDay, new Date()),
    },
    updatedAt: typeof file.updatedAt === "string" ? file.updatedAt : null,
  };
}

function isNotFoundError(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "ENOENT"
  );
}
