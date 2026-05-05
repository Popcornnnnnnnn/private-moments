import type { Device, PrismaClient } from "@prisma/client";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";

import { authenticateDevice, UnauthorizedError } from "../auth/request-auth.js";
import type { ExportImportService } from "../maintenance/export-import-service.js";
import type { MaintenanceModeService } from "../maintenance/maintenance-mode.js";
import {
  MaintenanceJobAlreadyRunningError,
  type MaintenanceJobService,
  parseMaintenanceJobStatus,
  parseMaintenanceJobType,
  serializeMaintenanceJob,
} from "../maintenance/maintenance-jobs.js";
import type { ResticService } from "../maintenance/restic-service.js";
import { sendBadRequest, sendConflict, sendNotFound, sendUnauthorized } from "./http-errors.js";

interface AdminMaintenanceRouteContext {
  prisma: PrismaClient;
  exportImport: ExportImportService;
  maintenanceJobs: MaintenanceJobService;
  maintenanceMode: MaintenanceModeService;
  restic: ResticService;
}

export async function registerAdminMaintenanceRoutes(
  app: FastifyInstance,
  context: AdminMaintenanceRouteContext,
): Promise<void> {
  app.get("/api/v1/admin/maintenance/state", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    return reply.send({
      maintenance: context.maintenanceMode.snapshot(),
      runningJob: await serializeOptionalJob(context.maintenanceJobs.getRunningJob()),
    });
  });

  app.get("/api/v1/admin/maintenance/jobs", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const query = parseQuery(request.query);
    const limit = parseLimit(query.limit);
    if (limit === null) {
      return sendBadRequest(reply, "limit must be an integer between 1 and 100");
    }

    const type = parseMaintenanceJobType(query.type);
    if (query.type && !type) {
      return sendBadRequest(reply, "type is invalid");
    }

    const status = parseMaintenanceJobStatus(query.status);
    if (query.status && !status) {
      return sendBadRequest(reply, "status is invalid");
    }

    const jobs = await context.maintenanceJobs.listJobs({
      limit,
      type,
      status,
    });

    return reply.send({
      jobs: jobs.map(serializeMaintenanceJob),
    });
  });

  app.get<{ Params: { jobId: string } }>(
    "/api/v1/admin/maintenance/jobs/:jobId",
    async (request, reply) => {
      const authenticated = await authenticateOrReply(request, reply, context.prisma);
      if (!authenticated) {
        return reply;
      }

      const job = await context.maintenanceJobs.getJob(request.params.jobId);
      if (!job) {
        return sendNotFound(reply, "Maintenance job not found");
      }

      return reply.send({
        job: serializeMaintenanceJob(job),
      });
    },
  );

  app.post("/api/v1/admin/maintenance/jobs/sync-health-refresh", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const job = await context.maintenanceJobs.createJob({
      type: "sync_health_refresh",
      stage: "queued",
      metadata: {
        source: "admin",
      },
    });

    try {
      const { job: completedJob } = await context.maintenanceJobs.runJob(job.id, async () => {
        const snapshot = await collectSafeSyncHealthSnapshot(context.prisma);
        await context.maintenanceJobs.updateJob(job.id, {
          stage: "collecting",
          progress: 50,
          metadata: snapshot,
        });
      });

      return reply.send({
        job: serializeMaintenanceJob(completedJob),
      });
    } catch (error) {
      if (error instanceof MaintenanceJobAlreadyRunningError) {
        return sendConflict(reply, error.message);
      }

      throw error;
    }
  });

  app.get("/api/v1/admin/archive/repository", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    return reply.send({
      repository: await context.restic.getRepositoryState(),
    });
  });

  app.post("/api/v1/admin/archive/repository", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const body = parseBody(request.body);
    if (!body.repositoryPath) {
      return sendBadRequest(reply, "repositoryPath is required");
    }

    return reply.send({
      repository: await context.restic.configureRepository(body.repositoryPath),
    });
  });

  app.post("/api/v1/admin/archive/repository/init", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    try {
      return reply.send({
        repository: await context.restic.initializeRepository(),
      });
    } catch (error) {
      return sendArchiveActionError(reply, error);
    }
  });

  app.get("/api/v1/admin/archive/snapshots", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    try {
      return reply.send({
        snapshots: await context.restic.listSnapshots(),
      });
    } catch (error) {
      return sendArchiveActionError(reply, error);
    }
  });

  app.post("/api/v1/admin/archive/schedule", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const body = parseBody(request.body);
    if (body.enabled !== "true" && body.enabled !== "false") {
      return sendBadRequest(reply, "enabled is required");
    }
    if (!body.timeOfDay) {
      return sendBadRequest(reply, "timeOfDay is required");
    }

    return reply.send({
      repository: await context.restic.updateSchedule({
        enabled: body.enabled === "true",
        timeOfDay: body.timeOfDay,
      }),
    });
  });

  app.post("/api/v1/admin/archive/jobs/backup", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const created = await context.maintenanceJobs.createJob({
      type: "backup_create",
      stage: "queued",
      metadata: {
        source: "manual",
      },
    });

    try {
      const job = await context.maintenanceJobs.startJob(created.id, async () => {
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "creating_snapshot",
          progress: 10,
        });
        const metadata = await context.restic.createBackup(created.id, "manual");
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "backup_written",
          progress: 90,
          metadata,
        });
      });

      return reply.status(202).send({
        job: serializeMaintenanceJob(job),
      });
    } catch (error) {
      if (error instanceof MaintenanceJobAlreadyRunningError) {
        return sendConflict(reply, error.message);
      }
      throw error;
    }
  });

  app.post("/api/v1/admin/archive/jobs/check", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const created = await context.maintenanceJobs.createJob({
      type: "backup_check",
      stage: "queued",
      metadata: {},
    });

    try {
      const job = await context.maintenanceJobs.startJob(created.id, async () => {
        const metadata = await context.restic.checkRepository();
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "checked",
          progress: 90,
          metadata,
        });
      });

      return reply.status(202).send({
        job: serializeMaintenanceJob(job),
      });
    } catch (error) {
      if (error instanceof MaintenanceJobAlreadyRunningError) {
        return sendConflict(reply, error.message);
      }
      throw error;
    }
  });

  app.post("/api/v1/admin/archive/jobs/restore", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const body = parseBody(request.body);
    if (!body.snapshotId) {
      return sendBadRequest(reply, "snapshotId is required");
    }
    const snapshotId = body.snapshotId;
    const restoreName = body.restoreName;

    const created = await context.maintenanceJobs.createJob({
      type: "backup_restore",
      stage: "queued",
      metadata: {
        snapshotId,
      },
    });

    try {
      const job = await context.maintenanceJobs.startJob(created.id, async () => {
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "restoring",
          progress: 10,
        });
        const metadata = await context.restic.restoreSnapshot(snapshotId, restoreName);
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "verified",
          progress: 90,
          metadata,
          artifactPath: typeof metadata.restorePath === "string" ? metadata.restorePath : null,
        });
      });

      return reply.status(202).send({
        job: serializeMaintenanceJob(job),
      });
    } catch (error) {
      if (error instanceof MaintenanceJobAlreadyRunningError) {
        return sendConflict(reply, error.message);
      }
      throw error;
    }
  });

  app.post("/api/v1/admin/archive/jobs/promote", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const body = parseBody(request.body);
    if (!body.restoredDataDir || !body.confirmation) {
      return sendBadRequest(reply, "restoredDataDir and confirmation are required");
    }
    const restoredDataDir = body.restoredDataDir;
    const confirmation = body.confirmation;

    const created = await context.maintenanceJobs.createJob({
      type: "backup_promote",
      stage: "queued",
      metadata: {
        restoredDataDir,
      },
    });

    try {
      const job = await context.maintenanceJobs.startJob(created.id, async () => {
        context.maintenanceMode.enter(created.id, "Promoting restored archive");
        try {
          await context.maintenanceJobs.updateJob(created.id, {
            stage: "pre_promote_backup",
            progress: 10,
          });
          const metadata = await context.restic.promoteRestore(
            created.id,
            restoredDataDir,
            confirmation,
          );
          await context.maintenanceJobs.updateJob(created.id, {
            stage: "pending_restart",
            progress: 90,
            metadata,
            artifactPath: typeof metadata.pendingPromotePath === "string"
              ? metadata.pendingPromotePath
              : null,
          });
        } finally {
          context.maintenanceMode.exit(created.id);
        }
      });

      return reply.status(202).send({
        job: serializeMaintenanceJob(job),
      });
    } catch (error) {
      context.maintenanceMode.exit(created.id);
      if (error instanceof MaintenanceJobAlreadyRunningError) {
        return sendConflict(reply, error.message);
      }
      throw error;
    }
  });

  app.post("/api/v1/admin/archive/jobs/export", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const body = parseBody(request.body);
    const created = await context.maintenanceJobs.createJob({
      type: "export_create",
      stage: "queued",
      metadata: {
        mode: body.from || body.to ? "date_range" : "all",
        from: body.from ?? null,
        to: body.to ?? null,
      },
    });

    try {
      const job = await context.maintenanceJobs.startJob(created.id, async () => {
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "exporting",
          progress: 10,
        });
        const metadata = await context.exportImport.createExport({
          from: body.from,
          to: body.to,
        });
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "exported",
          progress: 90,
          metadata,
          artifactPath: typeof metadata.packagePath === "string" ? metadata.packagePath : null,
        });
      });

      return reply.status(202).send({
        job: serializeMaintenanceJob(job),
      });
    } catch (error) {
      if (error instanceof MaintenanceJobAlreadyRunningError) {
        return sendConflict(reply, error.message);
      }
      throw error;
    }
  });

  app.post("/api/v1/admin/archive/jobs/import", async (request, reply) => {
    const authenticated = await authenticateOrReply(request, reply, context.prisma);
    if (!authenticated) {
      return reply;
    }

    const body = parseBody(request.body);
    if (!body.packagePath) {
      return sendBadRequest(reply, "packagePath is required");
    }

    const created = await context.maintenanceJobs.createJob({
      type: "import_restore",
      stage: "queued",
      metadata: {
        packagePath: body.packagePath,
      },
    });

    try {
      const job = await context.maintenanceJobs.startJob(created.id, async () => {
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "importing",
          progress: 10,
        });
        const metadata = await context.exportImport.importPackage({
          packagePath: body.packagePath!,
          importName: body.importName,
        });
        await context.maintenanceJobs.updateJob(created.id, {
          stage: "imported",
          progress: 90,
          metadata,
          artifactPath: typeof metadata.importPath === "string" ? metadata.importPath : null,
        });
      });

      return reply.status(202).send({
        job: serializeMaintenanceJob(job),
      });
    } catch (error) {
      if (error instanceof MaintenanceJobAlreadyRunningError) {
        return sendConflict(reply, error.message);
      }
      throw error;
    }
  });
}

async function collectSafeSyncHealthSnapshot(
  prisma: PrismaClient,
): Promise<Record<string, unknown>> {
  const [
    serverChange,
    pendingOperations,
    rejectedOperations,
    failedMediaUploads,
    aiNonReady,
    lastServerChange,
    lastOperation,
  ] =
    await Promise.all([
      prisma.serverChange.aggregate({
        _max: {
          version: true,
        },
      }),
      prisma.syncOperation.count({
        where: {
          appliedAt: null,
          rejectedAt: null,
        },
      }),
      prisma.syncOperation.count({
        where: {
          rejectedAt: {
            not: null,
          },
        },
      }),
      prisma.media.count({
        where: {
          status: "failed",
          deletedAt: null,
        },
      }),
      prisma.aiSummary.count({
        where: {
          deletedAt: null,
          status: {
            in: ["transcribing", "summarizing", "failed"],
          },
        },
      }),
      prisma.serverChange.findFirst({
        orderBy: {
          createdAt: "desc",
        },
        select: {
          createdAt: true,
        },
      }),
      prisma.syncOperation.findFirst({
        orderBy: {
          receivedAt: "desc",
        },
        select: {
          receivedAt: true,
          appliedAt: true,
          rejectedAt: true,
        },
      }),
    ]);

  return {
    latestServerChangeVersion: serverChange._max.version ?? 0,
    pendingOperations,
    rejectedOperations,
    failedMediaUploads,
    aiNonReady,
    lastServerChangeAt: lastServerChange?.createdAt.toISOString() ?? null,
    lastSyncOperationAt: lastOperation?.receivedAt.toISOString() ?? null,
    lastSuccessfulSyncAt: lastOperation?.appliedAt?.toISOString() ?? null,
    lastRejectedSyncAt: lastOperation?.rejectedAt?.toISOString() ?? null,
  };
}

async function serializeOptionalJob(
  jobPromise: Promise<Awaited<ReturnType<MaintenanceJobService["getRunningJob"]>>>,
): Promise<Record<string, unknown> | null> {
  const job = await jobPromise;
  return job ? serializeMaintenanceJob(job) : null;
}

async function authenticateOrReply(
  request: FastifyRequest,
  reply: FastifyReply,
  prisma: PrismaClient,
): Promise<Device | null> {
  try {
    return await authenticateDevice(request, prisma);
  } catch (error) {
    if (error instanceof UnauthorizedError) {
      sendUnauthorized(reply, error.message);
      return null;
    }

    throw error;
  }
}

function parseQuery(query: unknown): Record<string, string | undefined> {
  if (typeof query !== "object" || query === null || Array.isArray(query)) {
    return {};
  }

  const parsed: Record<string, string | undefined> = {};
  for (const [key, value] of Object.entries(query)) {
    parsed[key] = typeof value === "string" ? value : undefined;
  }

  return parsed;
}

function parseBody(body: unknown): Record<string, string | undefined> {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return {};
  }

  const parsed: Record<string, string | undefined> = {};
  for (const [key, value] of Object.entries(body)) {
    if (typeof value === "string") {
      parsed[key] = value;
    } else if (typeof value === "boolean") {
      parsed[key] = value ? "true" : "false";
    }
  }

  return parsed;
}

function parseLimit(value: string | undefined): number | null {
  if (!value) {
    return 25;
  }

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 100) {
    return null;
  }

  return parsed;
}

function sendArchiveActionError(reply: FastifyReply, error: unknown): FastifyReply {
  if (error instanceof Error) {
    return sendBadRequest(reply, error.message);
  }

  return sendBadRequest(reply, "Archive operation failed");
}
