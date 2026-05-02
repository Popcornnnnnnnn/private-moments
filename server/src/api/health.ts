import type { FastifyInstance } from "fastify";

import type { AppConfig } from "../config/app-config.js";
import { SCHEMA_VERSION, SERVER_VERSION } from "../config/app-config.js";
import type { DataPaths } from "../storage/data-dir.js";

export interface HealthRouteContext {
  config: AppConfig;
  paths: DataPaths;
}

export async function registerHealthRoutes(
  app: FastifyInstance,
  context: HealthRouteContext,
): Promise<void> {
  app.get("/api/v1/health", async () => {
    return {
      ok: true,
      serverVersion: SERVER_VERSION,
      schemaVersion: SCHEMA_VERSION,
      dataDir: context.paths.dataDir,
      databasePath: context.paths.databasePath,
      mediaDir: context.paths.mediaDir,
      uptimeSeconds: Math.round(process.uptime()),
      timestamp: new Date().toISOString(),
    };
  });
}

