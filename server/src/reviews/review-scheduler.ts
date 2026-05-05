import type { FileLogger } from "../logging/file-logger.js";
import { errorLogFields } from "../logging/error-fields.js";
import type { ReviewService } from "./review-service.js";

const REVIEW_SCHEDULER_INTERVAL_MS = 60 * 1000;
const SUNDAY = 0;
const SUNDAY_EVENING_HOUR = 21;

export class ReviewScheduler {
  private timer: NodeJS.Timeout | null = null;

  constructor(
    private readonly reviews: ReviewService,
    private readonly fileLogger: FileLogger,
  ) {}

  start(): void {
    if (this.timer) {
      return;
    }

    this.timer = setInterval(() => {
      void this.runTick();
    }, REVIEW_SCHEDULER_INTERVAL_MS);
    this.timer.unref();
    void this.runTick();
  }

  stop(): void {
    if (!this.timer) {
      return;
    }

    clearInterval(this.timer);
    this.timer = null;
  }

  private async tick(now = new Date()): Promise<void> {
    const settings = await this.reviews.getSettings();
    if (!settings.autoWeeklyEnabled || !isSundayEvening(now)) {
      return;
    }

    const localDate = localDateKey(now);
    if (settings.lastAutoWeeklyDate === localDate) {
      return;
    }

    await this.reviews.updateSettings({
      lastAutoWeeklyDate: localDate,
    });

    const review = await this.reviews.createRollingWeeklyReview("scheduled", now);
    await this.fileLogger.info("review.auto_weekly_triggered", {
      reviewId: review.id,
      status: review.status,
      localDate,
    });
  }

  private async runTick(now = new Date()): Promise<void> {
    try {
      await this.tick(now);
    } catch (error) {
      try {
        await this.fileLogger.error("review.scheduler_tick_failed", errorLogFields(error));
      } catch {
        // Avoid unhandled scheduler promises even if logging is unavailable.
      }
    }
  }
}

function isSundayEvening(date: Date): boolean {
  return date.getDay() === SUNDAY && date.getHours() >= SUNDAY_EVENING_HOUR;
}

function localDateKey(date: Date): string {
  const year = date.getFullYear();
  const month = `${date.getMonth() + 1}`.padStart(2, "0");
  const day = `${date.getDate()}`.padStart(2, "0");
  return `${year}-${month}-${day}`;
}
