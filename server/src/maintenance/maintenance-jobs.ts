import type { MaintenanceJob, PrismaClient } from "@prisma/client";

import type { FileLogger } from "../logging/file-logger.js";

export const MAINTENANCE_JOB_TYPES = [
  "backup_create",
  "backup_check",
  "backup_restore",
  "backup_promote",
  "export_create",
  "import_restore",
  "sync_health_refresh",
] as const;

export const MAINTENANCE_JOB_STATUSES = [
  "queued",
  "running",
  "succeeded",
  "failed",
  "cancelled",
] as const;

export type MaintenanceJobType = (typeof MAINTENANCE_JOB_TYPES)[number];
export type MaintenanceJobStatus = (typeof MAINTENANCE_JOB_STATUSES)[number];

export interface CreateMaintenanceJobInput {
  type: MaintenanceJobType;
  stage?: string | null;
  metadata?: Record<string, unknown>;
  artifactPath?: string | null;
}

export interface UpdateMaintenanceJobInput {
  status?: MaintenanceJobStatus;
  stage?: string | null;
  progress?: number;
  metadata?: Record<string, unknown>;
  artifactPath?: string | null;
  errorCode?: string | null;
  errorMessage?: string | null;
  startedAt?: Date | null;
  finishedAt?: Date | null;
}

export interface ListMaintenanceJobsOptions {
  limit?: number;
  type?: MaintenanceJobType;
  status?: MaintenanceJobStatus;
}

export class MaintenanceJobAlreadyRunningError extends Error {
  constructor(message = "A maintenance job is already running") {
    super(message);
    this.name = "MaintenanceJobAlreadyRunningError";
  }
}

export class MaintenanceJobService {
  private activeJobId: string | null = null;

  constructor(
    private readonly prisma: PrismaClient,
    private readonly fileLogger: FileLogger,
  ) {}

  async markStaleRunningJobsFailed(): Promise<number> {
    const now = new Date();
    const result = await this.prisma.maintenanceJob.updateMany({
      where: {
        status: "running",
      },
      data: {
        status: "failed",
        errorCode: "server_restarted",
        errorMessage: "Server restarted while this maintenance job was running.",
        finishedAt: now,
      },
    });

    if (result.count > 0) {
      await this.fileLogger.warn("maintenance.stale_jobs_failed", {
        count: result.count,
      });
    }

    return result.count;
  }

  async createJob(input: CreateMaintenanceJobInput): Promise<MaintenanceJob> {
    return this.prisma.maintenanceJob.create({
      data: {
        type: input.type,
        status: "queued",
        stage: input.stage ?? null,
        progress: 0,
        metadataJson: stringifySafeMetadata(input.metadata ?? {}),
        artifactPath: input.artifactPath ?? null,
      },
    });
  }

  async listJobs(options: ListMaintenanceJobsOptions = {}): Promise<MaintenanceJob[]> {
    return this.prisma.maintenanceJob.findMany({
      where: {
        ...(options.type ? { type: options.type } : {}),
        ...(options.status ? { status: options.status } : {}),
      },
      orderBy: {
        createdAt: "desc",
      },
      take: clampLimit(options.limit ?? 25, 1, 100),
    });
  }

  async getJob(id: string): Promise<MaintenanceJob | null> {
    return this.prisma.maintenanceJob.findUnique({
      where: {
        id,
      },
    });
  }

  async getRunningJob(): Promise<MaintenanceJob | null> {
    return this.prisma.maintenanceJob.findFirst({
      where: {
        status: "running",
      },
      orderBy: {
        startedAt: "desc",
      },
    });
  }

  async updateJob(id: string, input: UpdateMaintenanceJobInput): Promise<MaintenanceJob> {
    return this.prisma.maintenanceJob.update({
      where: {
        id,
      },
      data: {
        ...(input.status ? { status: input.status } : {}),
        ...(input.stage !== undefined ? { stage: input.stage } : {}),
        ...(input.progress !== undefined ? { progress: clampLimit(input.progress, 0, 100) } : {}),
        ...(input.metadata !== undefined ? { metadataJson: stringifySafeMetadata(input.metadata) } : {}),
        ...(input.artifactPath !== undefined ? { artifactPath: input.artifactPath } : {}),
        ...(input.errorCode !== undefined ? { errorCode: input.errorCode } : {}),
        ...(input.errorMessage !== undefined ? { errorMessage: input.errorMessage } : {}),
        ...(input.startedAt !== undefined ? { startedAt: input.startedAt } : {}),
        ...(input.finishedAt !== undefined ? { finishedAt: input.finishedAt } : {}),
      },
    });
  }

  async runJob<T>(
    jobId: string,
    handler: (job: MaintenanceJob) => Promise<T>,
  ): Promise<{ job: MaintenanceJob; result: T }> {
    if (this.activeJobId && this.activeJobId !== jobId) {
      throw new MaintenanceJobAlreadyRunningError();
    }

    const runningJob = await this.getRunningJob();
    if (runningJob && runningJob.id !== jobId) {
      throw new MaintenanceJobAlreadyRunningError();
    }

    this.activeJobId = jobId;
    let job = await this.updateJob(jobId, {
      status: "running",
      startedAt: new Date(),
      stage: "starting",
      progress: 1,
      errorCode: null,
      errorMessage: null,
    });

    try {
      const result = await handler(job);
      job = await this.updateJob(jobId, {
        status: "succeeded",
        stage: "completed",
        progress: 100,
        finishedAt: new Date(),
      });
      return { job, result };
    } catch (error) {
      job = await this.updateJob(jobId, {
        status: "failed",
        errorCode: maintenanceErrorCode(error),
        errorMessage: error instanceof Error ? error.message : "Unknown maintenance job error",
        finishedAt: new Date(),
      });
      throw error;
    } finally {
      if (this.activeJobId === jobId) {
        this.activeJobId = null;
      }
    }
  }

  async startJob<T>(
    jobId: string,
    handler: (job: MaintenanceJob) => Promise<T>,
  ): Promise<MaintenanceJob> {
    if (this.activeJobId && this.activeJobId !== jobId) {
      throw new MaintenanceJobAlreadyRunningError();
    }

    const runningJob = await this.getRunningJob();
    if (runningJob && runningJob.id !== jobId) {
      throw new MaintenanceJobAlreadyRunningError();
    }

    const job = await this.updateJob(jobId, {
      status: "running",
      startedAt: new Date(),
      stage: "starting",
      progress: 1,
      errorCode: null,
      errorMessage: null,
    });

    this.activeJobId = jobId;
    void this.runStartedJob(job, handler);
    return job;
  }

  private async runStartedJob<T>(
    initialJob: MaintenanceJob,
    handler: (job: MaintenanceJob) => Promise<T>,
  ): Promise<void> {
    try {
      await handler(initialJob);
      await this.updateJob(initialJob.id, {
        status: "succeeded",
        stage: "completed",
        progress: 100,
        finishedAt: new Date(),
      });
    } catch (error) {
      await this.updateJob(initialJob.id, {
        status: "failed",
        errorCode: maintenanceErrorCode(error),
        errorMessage: error instanceof Error ? error.message : "Unknown maintenance job error",
        finishedAt: new Date(),
      });
    } finally {
      if (this.activeJobId === initialJob.id) {
        this.activeJobId = null;
      }
    }
  }
}

export function parseMaintenanceJobType(value: string | undefined): MaintenanceJobType | undefined {
  if (!value) {
    return undefined;
  }

  return MAINTENANCE_JOB_TYPES.includes(value as MaintenanceJobType)
    ? (value as MaintenanceJobType)
    : undefined;
}

export function parseMaintenanceJobStatus(
  value: string | undefined,
): MaintenanceJobStatus | undefined {
  if (!value) {
    return undefined;
  }

  return MAINTENANCE_JOB_STATUSES.includes(value as MaintenanceJobStatus)
    ? (value as MaintenanceJobStatus)
    : undefined;
}

export function serializeMaintenanceJob(job: MaintenanceJob): Record<string, unknown> {
  return {
    id: job.id,
    type: job.type,
    status: job.status,
    stage: job.stage,
    progress: job.progress,
    metadata: parseMetadata(job.metadataJson),
    artifactPath: job.artifactPath,
    errorCode: job.errorCode,
    errorMessage: job.errorMessage,
    createdAt: job.createdAt.toISOString(),
    startedAt: job.startedAt?.toISOString() ?? null,
    finishedAt: job.finishedAt?.toISOString() ?? null,
  };
}

function stringifySafeMetadata(metadata: Record<string, unknown>): string {
  const json = JSON.stringify(metadata);
  if (json.length > 20_000) {
    throw new Error("Maintenance job metadata is too large");
  }

  return json;
}

function parseMetadata(value: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(value) as unknown;
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
  } catch {
    // Fall through to safe empty metadata.
  }

  return {};
}

function maintenanceErrorCode(error: unknown): string {
  if (error instanceof MaintenanceJobAlreadyRunningError) {
    return "job_already_running";
  }

  return "job_failed";
}

function clampLimit(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) {
    return min;
  }

  return Math.min(max, Math.max(min, Math.round(value)));
}
