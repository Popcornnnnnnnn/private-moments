import path from "node:path";
import { homedir } from "node:os";

export const SERVER_VERSION = "0.1.0";
export const SCHEMA_VERSION = 17;

export interface AppConfig {
  host: string;
  port: number;
  logLevel: string;
  dataDir: string;
  databaseUrl: string;
  initialPassword?: string;
  aiSummary: AISummaryConfig;
}

export interface AISummaryConfig {
  provider: string;
  baseUrl: string;
  apiKey?: string;
  model: string;
  transcriptionProvider: string;
  transcriptionModel: string;
  localTranscriptionPythonPath: string;
  localTranscriptionScriptPath: string;
  localTranscriptionModel: string;
  localTranscriptionTimeoutMs: number;
  timeoutMs: number;
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
    aiSummary: {
      provider: env.AI_SUMMARY_PROVIDER ?? "openai",
      baseUrl: trimTrailingSlash(env.AI_SUMMARY_BASE_URL ?? "https://api.openai.com/v1"),
      apiKey: env.AI_SUMMARY_API_KEY,
      model: env.AI_SUMMARY_MODEL ?? "gpt-4o-mini",
      transcriptionProvider: env.AI_TRANSCRIPTION_PROVIDER ?? "local",
      transcriptionModel: env.AI_TRANSCRIPTION_MODEL ?? "gpt-4o-mini-transcribe",
      localTranscriptionPythonPath: path.resolve(
        env.AI_LOCAL_TRANSCRIPTION_PYTHON ?? path.join(process.cwd(), ".venv/bin/python"),
      ),
      localTranscriptionScriptPath: path.resolve(
        env.AI_LOCAL_TRANSCRIPTION_SCRIPT ?? path.join(process.cwd(), "scripts/local-transcribe.py"),
      ),
      localTranscriptionModel: env.AI_LOCAL_TRANSCRIPTION_MODEL ?? "mlx-community/whisper-turbo",
      localTranscriptionTimeoutMs: parsePositiveInteger(env.AI_LOCAL_TRANSCRIPTION_TIMEOUT_MS, 600_000),
      timeoutMs: parsePositiveInteger(env.AI_SUMMARY_TIMEOUT_MS, 60_000),
    },
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

function parsePositiveInteger(value: string | undefined, fallback: number): number {
  if (!value) {
    return fallback;
  }

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) {
    throw new Error(`Invalid positive integer value: ${value}`);
  }

  return parsed;
}

function trimTrailingSlash(value: string): string {
  return value.endsWith("/") ? value.slice(0, -1) : value;
}
