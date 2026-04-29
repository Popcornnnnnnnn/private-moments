import path from "node:path";
import { homedir } from "node:os";

export const SERVER_VERSION = "0.1.0";
export const SCHEMA_VERSION = 3;

export interface AppConfig {
  host: string;
  port: number;
  logLevel: string;
  dataDir: string;
  databaseUrl: string;
  initialPassword?: string;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const dataDir = path.resolve(
    env.PRIVATE_MOMENTS_DATA_DIR ??
      path.join(homedir(), "Library", "Application Support", "PrivateMoments"),
  );

  return {
    host: env.HOST ?? "127.0.0.1",
    port: parsePort(env.PORT),
    logLevel: env.LOG_LEVEL ?? "info",
    dataDir,
    databaseUrl: env.DATABASE_URL ?? `file:${path.join(dataDir, "app.sqlite")}`,
    initialPassword: env.PRIVATE_MOMENTS_INITIAL_PASSWORD,
  };
}

function parsePort(value: string | undefined): number {
  if (!value) {
    return 3210;
  }

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65535) {
    throw new Error(`Invalid PORT value: ${value}`);
  }

  return parsed;
}
