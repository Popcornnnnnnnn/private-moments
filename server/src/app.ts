import fastify, { type FastifyInstance } from "fastify";
import type { PrismaClient } from "@prisma/client";
import multipart from "@fastify/multipart";

import { registerAdminRoutes } from "./api/admin.js";
import { registerAIRoutes } from "./api/ai.js";
import { registerAuthRoutes } from "./api/auth.js";
import { registerDeviceRoutes } from "./api/devices.js";
import { registerHealthRoutes } from "./api/health.js";
import { registerMediaRoutes } from "./api/media.js";
import { registerPostRoutes } from "./api/posts.js";
import { registerSyncRoutes } from "./api/sync.js";
import { registerStaticAdmin } from "./admin/static-admin.js";
import type { AppConfig } from "./config/app-config.js";
import type { FileLogger } from "./logging/file-logger.js";
import type { DataPaths } from "./storage/data-dir.js";

export interface AppContext {
  config: AppConfig;
  paths: DataPaths;
  fileLogger: FileLogger;
  prisma: PrismaClient;
}

export async function buildApp(context: AppContext): Promise<FastifyInstance> {
  const app = fastify({
    logger: {
      level: context.config.logLevel,
    },
  });

  app.setErrorHandler(async (error, request, reply) => {
    const message = error instanceof Error ? error.message : "Unknown error";

    request.log.error({ err: error }, "request failed");
    await context.fileLogger.error("request.failed", {
      method: request.method,
      url: request.url,
      message,
    });

    return reply.status(500).send({
      error: "internal_server_error",
      message: "Internal server error",
    });
  });

  await app.register(multipart, {
    limits: {
      files: 1,
      fields: 12,
      parts: 14,
      fileSize: 50 * 1024 * 1024,
    },
  });

  await registerHealthRoutes(app, {
    config: context.config,
    paths: context.paths,
  });
  await registerAdminRoutes(app, {
    prisma: context.prisma,
    paths: context.paths,
    fileLogger: context.fileLogger,
  });
  await registerAuthRoutes(app, {
    prisma: context.prisma,
    fileLogger: context.fileLogger,
  });
  await registerDeviceRoutes(app, {
    prisma: context.prisma,
    fileLogger: context.fileLogger,
  });
  await registerPostRoutes(app, {
    prisma: context.prisma,
  });
  await registerMediaRoutes(app, {
    config: context.config,
    prisma: context.prisma,
    paths: context.paths,
    fileLogger: context.fileLogger,
  });
  await registerAIRoutes(app, {
    config: context.config,
    paths: context.paths,
    prisma: context.prisma,
    fileLogger: context.fileLogger,
  });
  await registerSyncRoutes(app, {
    prisma: context.prisma,
    fileLogger: context.fileLogger,
  });
  await registerStaticAdmin(app);

  app.addHook("onClose", async () => {
    await context.prisma.$disconnect();
  });

  return app;
}
