import fastify, { type FastifyInstance } from "fastify";
import type { PrismaClient } from "@prisma/client";
import multipart from "@fastify/multipart";

import { registerAdminMaintenanceRoutes } from "./api/admin-maintenance.js";
import { registerAdminRoutes } from "./api/admin.js";
import { registerAIRoutes } from "./api/ai.js";
import { registerAuthRoutes } from "./api/auth.js";
import { registerCheckInMediaRoutes } from "./api/checkin-media.js";
import { registerDeviceRoutes } from "./api/devices.js";
import { registerHealthRoutes } from "./api/health.js";
import { registerMediaRoutes } from "./api/media.js";
import { registerPostRoutes } from "./api/posts.js";
import { registerReviewRoutes } from "./api/reviews.js";
import { registerSyncRoutes } from "./api/sync.js";
import { registerStaticAdmin } from "./admin/static-admin.js";
import type { AppConfig } from "./config/app-config.js";
import type { FileLogger } from "./logging/file-logger.js";
import type { ExportImportService } from "./maintenance/export-import-service.js";
import type { MaintenanceJobService } from "./maintenance/maintenance-jobs.js";
import type { MaintenanceModeService } from "./maintenance/maintenance-mode.js";
import type { ResticService } from "./maintenance/restic-service.js";
import type { ReviewService } from "./reviews/review-service.js";
import type { DataPaths } from "./storage/data-dir.js";

export interface AppContext {
  config: AppConfig;
  paths: DataPaths;
  fileLogger: FileLogger;
  exportImport: ExportImportService;
  maintenanceJobs: MaintenanceJobService;
  maintenanceMode: MaintenanceModeService;
  restic: ResticService;
  reviews: ReviewService;
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
    const statusCode = errorStatusCode(error);

    request.log[statusCode >= 500 ? "error" : "warn"]({ err: error }, "request failed");
    await context.fileLogger[statusCode >= 500 ? "error" : "warn"]("request.failed", {
      method: request.method,
      url: request.url,
      message,
    });

    if (statusCode >= 400 && statusCode < 500) {
      return reply.status(statusCode).send({
        error: statusCode === 401 ? "unauthorized" : "bad_request",
        message,
      });
    }

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
    maintenanceMode: context.maintenanceMode,
  });
  await registerAdminMaintenanceRoutes(app, {
    prisma: context.prisma,
    exportImport: context.exportImport,
    maintenanceJobs: context.maintenanceJobs,
    maintenanceMode: context.maintenanceMode,
    restic: context.restic,
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
    maintenanceMode: context.maintenanceMode,
  });
  await registerCheckInMediaRoutes(app, {
    prisma: context.prisma,
    paths: context.paths,
    fileLogger: context.fileLogger,
    maintenanceMode: context.maintenanceMode,
  });
  await registerAIRoutes(app, {
    config: context.config,
    paths: context.paths,
    prisma: context.prisma,
    fileLogger: context.fileLogger,
    maintenanceMode: context.maintenanceMode,
  });
  await registerReviewRoutes(app, {
    prisma: context.prisma,
    reviews: context.reviews,
    maintenanceMode: context.maintenanceMode,
  });
  await registerSyncRoutes(app, {
    prisma: context.prisma,
    fileLogger: context.fileLogger,
    maintenanceMode: context.maintenanceMode,
  });
  await registerStaticAdmin(app);

  app.addHook("onClose", async () => {
    await context.prisma.$disconnect();
  });

  return app;
}

function errorStatusCode(error: unknown): number {
  if (
    typeof error === "object" &&
    error !== null &&
    "statusCode" in error &&
    typeof error.statusCode === "number"
  ) {
    return error.statusCode;
  }

  return 500;
}
