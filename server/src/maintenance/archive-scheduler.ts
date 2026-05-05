import type { FileLogger } from "../logging/file-logger.js";
import { errorLogFields } from "../logging/error-fields.js";
import { MaintenanceJobAlreadyRunningError } from "./maintenance-jobs.js";
import type { MaintenanceJobService } from "./maintenance-jobs.js";
import type { ResticService } from "./restic-service.js";

const SCHEDULER_INTERVAL_MS = 60 * 1000;

export class ArchiveScheduler {
  private timer: NodeJS.Timeout | null = null;
  private lastTriggeredNextRunAt: string | null = null;

  constructor(
    private readonly maintenanceJobs: MaintenanceJobService,
    private readonly restic: ResticService,
    private readonly fileLogger: FileLogger,
  ) {}

  start(): void {
    if (this.timer) {
      return;
    }

    this.timer = setInterval(() => {
      void this.runTick();
    }, SCHEDULER_INTERVAL_MS);
    this.timer.unref();
    void this.runTick();
  }

  stop(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  private async tick(): Promise<void> {
    const state = await this.restic.getRepositoryState();
    const nextRunAt = state.schedule.nextRunAt;
    if (!state.schedule.enabled || !nextRunAt) {
      return;
    }

    if (this.lastTriggeredNextRunAt === nextRunAt || new Date(nextRunAt) > new Date()) {
      return;
    }

    this.lastTriggeredNextRunAt = nextRunAt;

    if (await this.maintenanceJobs.getRunningJob()) {
      await this.fileLogger.warn("archive.schedule_skipped_job_running", {
        nextRunAt,
      });
      return;
    }

    const created = await this.maintenanceJobs.createJob({
      type: "backup_create",
      stage: "queued",
      metadata: {
        source: "schedule",
      },
    });

    try {
      await this.maintenanceJobs.startJob(created.id, async () => {
        await this.maintenanceJobs.updateJob(created.id, {
          stage: "scheduled_backup",
          progress: 10,
        });
        const metadata = await this.restic.createBackup(created.id, "schedule");
        await this.maintenanceJobs.updateJob(created.id, {
          stage: "backup_written",
          progress: 90,
          metadata,
        });
      });
    } catch (error) {
      if (error instanceof MaintenanceJobAlreadyRunningError) {
        await this.fileLogger.warn("archive.schedule_skipped_job_running", {
          nextRunAt,
        });
        return;
      }

      this.lastTriggeredNextRunAt = null;
      throw error;
    }
  }

  private async runTick(): Promise<void> {
    try {
      await this.tick();
    } catch (error) {
      try {
        await this.fileLogger.error("archive.schedule_tick_failed", errorLogFields(error));
      } catch {
        // Avoid unhandled scheduler promises even if logging is unavailable.
      }
    }
  }
}
