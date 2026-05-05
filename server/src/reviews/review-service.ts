import { randomUUID } from "node:crypto";

import type { Prisma, PrismaClient, Review, ReviewSetting } from "@prisma/client";

import {
  generateReview,
  REVIEW_PROMPT_VERSION,
  reviewInputDigest,
  type ReviewInputPack,
  type ReviewKind,
  type ReviewOutput,
  type ReviewRangeMode,
  type ReviewTrigger,
} from "../ai/review-generation.js";
import { recordAIUsageEvent } from "../ai/usage-ledger.js";
import type { AppConfig } from "../config/app-config.js";
import type { FileLogger } from "../logging/file-logger.js";
import { assertReviewMomentCount, MAX_REVIEW_INPUT_MOMENTS } from "./review-limits.js";
import { reviewToMarkdown } from "./review-markdown.js";

const DEFAULT_SETTINGS_ID = "default";
const REVIEW_MEMORY_SCOPE = "periodic_review";
const REVIEW_MEMORY_FEEDBACK_KEY = "feedback_preferences";
const REVIEW_GENERATION_STALE_MS = 15 * 60 * 1000;
let inFlightReviewGeneration: Promise<Review | null> | null = null;

type ReviewPost = Prisma.PostGetPayload<{
  include: {
    comments: true;
    media: {
      include: {
        aiSummaries: true;
      };
    };
    tags: {
      include: {
        tag: true;
      };
    };
  };
}>;

export interface ReviewServiceContext {
  config: AppConfig;
  prisma: PrismaClient;
  fileLogger: FileLogger;
}

export interface GenerateReviewInput {
  kind: ReviewKind;
  rangeMode: ReviewRangeMode;
  rangeStart: Date;
  rangeEnd: Date;
  trigger: ReviewTrigger;
  regeneratedFromReviewId?: string | null;
}

export class ReviewService {
  constructor(private readonly context: ReviewServiceContext) {}

  async listReviews(options: { kind?: ReviewKind; limit?: number } = {}): Promise<Review[]> {
    return this.context.prisma.review.findMany({
      where: {
        deletedAt: null,
        ...(options.kind ? { kind: options.kind } : {}),
      },
      orderBy: {
        createdAt: "desc",
      },
      take: clampLimit(options.limit ?? 20, 1, 100),
    });
  }

  async getReview(id: string): Promise<Review | null> {
    return this.context.prisma.review.findFirst({
      where: {
        id,
        deletedAt: null,
      },
    });
  }

  async generate(input: GenerateReviewInput): Promise<Review> {
    const existing = await this.activeGeneratingReview();
    if (existing) {
      return existing;
    }

    if (inFlightReviewGeneration) {
      const active = await this.activeGeneratingReview();
      if (active) {
        return active;
      }

      const generated = await inFlightReviewGeneration;
      if (generated) {
        return generated;
      }
    }

    const task = this.generateUnlocked(input);
    inFlightReviewGeneration = task;
    try {
      return await task;
    } finally {
      if (inFlightReviewGeneration === task) {
        inFlightReviewGeneration = null;
      }
    }
  }

  private async generateUnlocked(input: GenerateReviewInput): Promise<Review> {
    const reviewId = randomUUID();
    const created = await this.context.prisma.review.create({
      data: {
        id: reviewId,
        kind: input.kind,
        rangeMode: input.rangeMode,
        rangeStart: input.rangeStart,
        rangeEnd: input.rangeEnd,
        status: "generating",
        trigger: input.trigger,
        contentJson: "{}",
        promptVersion: REVIEW_PROMPT_VERSION,
        provider: this.context.config.aiSummary.provider,
        model: this.context.config.aiSummary.model,
        regeneratedFromReviewId: input.regeneratedFromReviewId ?? null,
      },
    });

    try {
      const inputPack = await this.buildInputPack(input);
      const digest = reviewInputDigest(inputPack);
      const output = await generateReview(this.context.config.aiSummary, inputPack, {
        feature: "weekly_review",
        subjectType: "review",
        subjectId: created.id,
        promptVersion: REVIEW_PROMPT_VERSION,
        recorder: (event) => recordAIUsageEvent(this.context.prisma, event),
      });
      const ready = await this.context.prisma.review.update({
        where: {
          id: created.id,
        },
        data: {
          status: "ready",
          contentJson: JSON.stringify(output),
          inputDigestHash: digest,
          language: inferReviewLanguage(output),
          generatedAt: new Date(),
          errorCode: null,
          errorMessage: null,
        },
      });

      await this.context.fileLogger.info("review.ready", {
        reviewId: ready.id,
        kind: ready.kind,
        rangeMode: ready.rangeMode,
        trigger: ready.trigger,
        momentCount: inputPack.totals.moments,
        commentCount: inputPack.totals.comments,
      });
      return ready;
    } catch (error) {
      const failed = await this.context.prisma.review.update({
        where: {
          id: created.id,
        },
        data: {
          status: "failed",
          errorCode: reviewErrorCode(error),
          errorMessage: error instanceof Error ? error.message : "Unknown review generation error",
        },
      });

      await this.context.fileLogger.warn("review.failed", {
        reviewId: failed.id,
        kind: failed.kind,
        trigger: failed.trigger,
        errorCode: failed.errorCode,
      });
      return failed;
    }
  }

  async createRollingWeeklyReview(trigger: ReviewTrigger, now = new Date()): Promise<Review> {
    return this.generate({
      kind: "weekly",
      rangeMode: "rolling_7_days",
      rangeStart: new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000),
      rangeEnd: now,
      trigger,
    });
  }

  async regenerate(reviewId: string): Promise<Review | null> {
    const existing = await this.getReview(reviewId);
    if (!existing) {
      return null;
    }

    const generating = await this.activeGeneratingReview();
    if (generating) {
      return generating;
    }

    return this.generate({
      kind: parseReviewKind(existing.kind),
      rangeMode: parseReviewRangeMode(existing.rangeMode),
      rangeStart: existing.rangeStart,
      rangeEnd: existing.rangeEnd,
      trigger: "regenerate",
      regeneratedFromReviewId: existing.id,
    });
  }

  private async activeGeneratingReview(now = new Date()): Promise<Review | null> {
    const staleCutoff = new Date(now.getTime() - REVIEW_GENERATION_STALE_MS);
    const staleReviews = await this.context.prisma.review.findMany({
      where: {
        status: "generating",
        deletedAt: null,
        updatedAt: {
          lt: staleCutoff,
        },
      },
      orderBy: {
        updatedAt: "asc",
      },
      take: 20,
    });

    for (const stale of staleReviews) {
      await this.context.prisma.review.update({
        where: {
          id: stale.id,
        },
        data: {
          status: "failed",
          errorCode: "review_generation_timeout",
          errorMessage: "Review generation timed out. Please regenerate.",
        },
      });
      await this.context.fileLogger.warn("review.generation_timed_out", {
        reviewId: stale.id,
        kind: stale.kind,
        trigger: stale.trigger,
        updatedAt: stale.updatedAt.toISOString(),
      });
    }

    return this.context.prisma.review.findFirst({
      where: {
        status: "generating",
        deletedAt: null,
      },
      orderBy: {
        updatedAt: "desc",
      },
    });
  }

  async deleteReview(reviewId: string): Promise<Review | null> {
    const review = await this.context.prisma.review.findUnique({
      where: {
        id: reviewId,
      },
    });
    if (!review) {
      return null;
    }

    if (review.deletedAt) {
      return review;
    }

    const deleted = await this.context.prisma.review.update({
      where: {
        id: review.id,
      },
      data: {
        deletedAt: new Date(),
      },
    });

    await this.context.fileLogger.info("review.deleted", {
      reviewId: deleted.id,
      kind: deleted.kind,
      status: deleted.status,
    });
    return deleted;
  }

  async saveFeedback(reviewId: string, type: string, note: string | null): Promise<void> {
    await this.context.prisma.reviewFeedback.create({
      data: {
        reviewId,
        type,
        note,
        metadataJson: "{}",
      },
    });

    const current = await this.context.prisma.reviewMemory.findUnique({
      where: {
        scope_key: {
          scope: REVIEW_MEMORY_SCOPE,
          key: REVIEW_MEMORY_FEEDBACK_KEY,
        },
      },
    });
    const value = parseJsonObject(current?.valueJson);
    const counts = isRecord(value.counts) ? value.counts : {};
    const existingCount = typeof counts[type] === "number" ? counts[type] : 0;
    const nextValue = {
      ...value,
      counts: {
        ...counts,
        [type]: existingCount + 1,
      },
      lastFeedback: {
        type,
        note,
        reviewId,
        at: new Date().toISOString(),
      },
    };

    await this.context.prisma.reviewMemory.upsert({
      where: {
        scope_key: {
          scope: REVIEW_MEMORY_SCOPE,
          key: REVIEW_MEMORY_FEEDBACK_KEY,
        },
      },
      create: {
        scope: REVIEW_MEMORY_SCOPE,
        key: REVIEW_MEMORY_FEEDBACK_KEY,
        valueJson: JSON.stringify(nextValue),
      },
      update: {
        valueJson: JSON.stringify(nextValue),
      },
    });
  }

  async getSettings(): Promise<ReviewSetting> {
    return this.context.prisma.reviewSetting.upsert({
      where: {
        id: DEFAULT_SETTINGS_ID,
      },
      create: {
        id: DEFAULT_SETTINGS_ID,
      },
      update: {},
    });
  }

  async updateSettings(input: {
    autoWeeklyEnabled?: boolean;
    publishWeeklyToMoments?: boolean;
    lastAutoWeeklyDate?: string | null;
  }): Promise<ReviewSetting> {
    await this.getSettings();
    return this.context.prisma.reviewSetting.update({
      where: {
        id: DEFAULT_SETTINGS_ID,
      },
      data: {
        ...(input.autoWeeklyEnabled !== undefined ? { autoWeeklyEnabled: input.autoWeeklyEnabled } : {}),
        ...(input.publishWeeklyToMoments !== undefined ? { publishWeeklyToMoments: input.publishWeeklyToMoments } : {}),
        ...(input.lastAutoWeeklyDate !== undefined ? { lastAutoWeeklyDate: input.lastAutoWeeklyDate } : {}),
      },
    });
  }

  async publishAsMoment(reviewId: string): Promise<{ review: Review; postId: string } | null> {
    const review = await this.getReview(reviewId);
    if (!review || review.status !== "ready") {
      return null;
    }

    if (review.publishedPostId) {
      return {
        review,
        postId: review.publishedPostId,
      };
    }

    const content = parseReviewContent(review.contentJson);
    const postId = `review-${review.id}`;
    const text = reviewToMarkdown(content, review);
    const occurredAt = review.rangeEnd;

    const updated = await this.context.prisma.$transaction(async (tx) => {
      const post = await tx.post.create({
        data: {
          id: postId,
          text,
          isFavorite: false,
          occurredAt,
          clientCreatedAt: new Date(),
          clientUpdatedAt: new Date(),
        },
      });
      const change = await tx.serverChange.create({
        data: {
          entityType: "post",
          entityId: post.id,
          changeType: "post_created",
          payloadJson: JSON.stringify({
            id: post.id,
            text: post.text,
            isFavorite: post.isFavorite,
            occurredAt: post.occurredAt.toISOString(),
            deletedAt: null,
          }),
        },
      });
      await tx.post.update({
        where: {
          id: post.id,
        },
        data: {
          serverVersion: change.version,
        },
      });
      return tx.review.update({
        where: {
          id: review.id,
        },
        data: {
          publishedPostId: post.id,
        },
      });
    });

    await this.context.fileLogger.info("review.published_as_moment", {
      reviewId: review.id,
      postId,
    });

    return {
      review: updated,
      postId,
    };
  }

  private async buildInputPack(input: GenerateReviewInput): Promise<ReviewInputPack> {
    const [posts, memories] = await Promise.all([
      this.context.prisma.post.findMany({
        where: {
          deletedAt: null,
          occurredAt: {
            gte: input.rangeStart,
            lt: input.rangeEnd,
          },
        },
        include: {
          comments: {
            where: {
              deletedAt: null,
            },
            orderBy: {
              createdAt: "asc",
            },
          },
          media: {
            where: {
              deletedAt: null,
            },
            include: {
              aiSummaries: {
                where: {
                  status: "ready",
                  deletedAt: null,
                },
              },
            },
            orderBy: {
              sortOrder: "asc",
            },
          },
          tags: {
            where: {
              deletedAt: null,
            },
            include: {
              tag: true,
            },
          },
        },
        orderBy: {
          occurredAt: "asc",
        },
        take: MAX_REVIEW_INPUT_MOMENTS + 1,
      }),
      this.context.prisma.reviewMemory.findMany({
        where: {
          scope: REVIEW_MEMORY_SCOPE,
        },
        orderBy: {
          updatedAt: "desc",
        },
        take: 20,
      }),
    ]);
    assertReviewMomentCount(posts.length);

    return {
      kind: input.kind,
      rangeMode: input.rangeMode,
      rangeStart: input.rangeStart.toISOString(),
      rangeEnd: input.rangeEnd.toISOString(),
      generatedAt: new Date().toISOString(),
      totals: summarizeTotals(posts),
      rhythm: summarizeRhythm(posts),
      moments: posts.map((post) => ({
        id: post.id,
        occurredAt: post.occurredAt.toISOString(),
        text: clampText(post.text, 4000),
        mediaKinds: unique(post.media.map((media) => media.kind)),
        comments: post.comments.map((comment) => clampText(comment.text, 1000)),
        tags: post.tags
          .filter((assignment) => !assignment.tag.isArchived)
          .map((assignment) => assignment.tag.name),
        favorite: post.isFavorite,
        aiSummaries: post.media.flatMap((media) =>
          media.aiSummaries.map((summary) => ({
            mediaId: media.id,
            kind: media.kind,
            documentTitle: summary.documentTitle,
            oneLiner: summary.oneLiner,
            summaryText: summary.summaryText ? clampText(summary.summaryText, 4000) : null,
            documentBlocks: parseJsonArray(summary.documentBlocksJson),
          })),
        ),
      })),
      reviewMemory: memories.map((memory) => ({
        key: memory.key,
        value: parseJsonObject(memory.valueJson),
      })),
    };
  }
}

function summarizeTotals(posts: ReviewPost[]): ReviewInputPack["totals"] {
  return {
    moments: posts.length,
    textMoments: posts.filter((post) => post.text.trim().length > 0).length,
    imageMoments: posts.filter((post) => post.media.some((media) => media.kind === "image")).length,
    audioMoments: posts.filter((post) => post.media.some((media) => media.kind === "audio")).length,
    videoMoments: posts.filter((post) => post.media.some((media) => media.kind === "video")).length,
    comments: posts.reduce((count, post) => count + post.comments.length, 0),
    favorites: posts.filter((post) => post.isFavorite).length,
  };
}

function summarizeRhythm(posts: ReviewPost[]): ReviewInputPack["rhythm"] {
  const byDay = new Map<string, number>();
  const byHourBucket = new Map<string, number>([
    ["morning", 0],
    ["afternoon", 0],
    ["evening", 0],
    ["late_night", 0],
  ]);

  for (const post of posts) {
    const date = post.occurredAt.toISOString().slice(0, 10);
    byDay.set(date, (byDay.get(date) ?? 0) + 1);
    const hour = post.occurredAt.getHours();
    const bucket = hour >= 5 && hour < 12
      ? "morning"
      : hour >= 12 && hour < 18
        ? "afternoon"
        : hour >= 18 && hour < 23
          ? "evening"
          : "late_night";
    byHourBucket.set(bucket, (byHourBucket.get(bucket) ?? 0) + 1);
  }

  return {
    byDay: [...byDay.entries()].map(([date, count]) => ({ date, count })),
    byHourBucket: [...byHourBucket.entries()].map(([bucket, count]) => ({ bucket, count })),
  };
}

function parseReviewContent(value: string): ReviewOutput {
  const parsed = parseJsonObject(value);
  return {
    title: typeof parsed.title === "string" ? parsed.title : "Weekly Review",
    oneLiner: typeof parsed.oneLiner === "string" ? parsed.oneLiner : "",
    keywords: Array.isArray(parsed.keywords) ? parsed.keywords as ReviewOutput["keywords"] : [],
    themes: Array.isArray(parsed.themes) ? parsed.themes as ReviewOutput["themes"] : [],
    emotionalReflection: isRecord(parsed.emotionalReflection)
      ? parsed.emotionalReflection as ReviewOutput["emotionalReflection"]
      : { tone: "mixed", body: "" },
    progressAndOpenLoops: isRecord(parsed.progressAndOpenLoops)
      ? parsed.progressAndOpenLoops as ReviewOutput["progressAndOpenLoops"]
      : { progress: [], openLoops: [] },
    rhythm: isRecord(parsed.rhythm)
      ? parsed.rhythm as ReviewOutput["rhythm"]
      : { body: "", observations: [] },
    notableMoments: Array.isArray(parsed.notableMoments) ? parsed.notableMoments as ReviewOutput["notableMoments"] : [],
    gentleSuggestions: Array.isArray(parsed.gentleSuggestions) ? parsed.gentleSuggestions as string[] : [],
    uncertainty: Array.isArray(parsed.uncertainty) ? parsed.uncertainty as string[] : [],
  };
}

function inferReviewLanguage(output: ReviewOutput): string {
  const text = `${output.title}\n${output.oneLiner}\n${output.emotionalReflection.body}`;
  const cjk = [...text].filter((character) => /[\u3400-\u9fff]/u.test(character)).length;
  const latin = [...text].filter((character) => /[a-z]/iu.test(character)).length;
  if (cjk >= 8 && cjk >= latin) {
    return "zh";
  }

  if (latin >= 16) {
    return "en";
  }

  return "mixed";
}

function parseReviewKind(value: string): ReviewKind {
  return value === "monthly" || value === "custom" ? value : "weekly";
}

function parseReviewRangeMode(value: string): ReviewRangeMode {
  if (value === "calendar_week" || value === "calendar_month" || value === "custom") {
    return value;
  }

  return "rolling_7_days";
}

function reviewErrorCode(error: unknown): string {
  if (error instanceof Error && "code" in error && typeof error.code === "string") {
    return error.code;
  }

  return "review_generation_failed";
}

function parseJsonObject(value: string | undefined): Record<string, unknown> {
  if (!value) {
    return {};
  }

  try {
    const parsed = JSON.parse(value) as unknown;
    return isRecord(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

function parseJsonArray(value: string): unknown[] {
  try {
    const parsed = JSON.parse(value) as unknown;
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function clampText(value: string, maxLength: number): string {
  const trimmed = value.trim();
  return trimmed.length > maxLength ? `${trimmed.slice(0, maxLength)}...` : trimmed;
}

function unique(values: string[]): string[] {
  return [...new Set(values)];
}

function clampLimit(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
