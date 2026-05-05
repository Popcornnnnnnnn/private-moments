import test from "node:test";
import assert from "node:assert/strict";

import type { Review } from "@prisma/client";

import { ReviewService } from "./review-service.js";

function reviewFixture(overrides: Partial<Review> = {}): Review {
  const now = new Date("2026-05-06T00:00:00.000Z");
  return {
    id: "review-1",
    kind: "weekly",
    rangeMode: "rolling_7_days",
    rangeStart: new Date("2026-04-29T00:00:00.000Z"),
    rangeEnd: new Date("2026-05-06T00:00:00.000Z"),
    status: "ready",
    trigger: "manual",
    contentJson: "{}",
    inputDigestHash: null,
    promptVersion: "weekly-review-v1",
    provider: "test",
    model: "test-model",
    language: null,
    errorCode: null,
    errorMessage: null,
    generatedAt: now,
    regeneratedFromReviewId: null,
    publishedPostId: null,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    ...overrides,
  };
}

test("deleteReview is idempotent for already soft-deleted reviews", async () => {
  let stored = reviewFixture();
  const service = new ReviewService({
    config: { aiSummary: { provider: "test", model: "test-model" } },
    fileLogger: { info: async () => undefined },
    prisma: {
      review: {
        findUnique: async () => stored,
        update: async ({ data }: { data: Partial<Review> }) => {
          stored = { ...stored, ...data } as Review;
          return stored;
        },
      },
    },
  } as never);

  const first = await service.deleteReview(stored.id);
  const second = await service.deleteReview(stored.id);

  assert.ok(first?.deletedAt);
  assert.equal(second?.id, stored.id);
  assert.ok(second?.deletedAt);
});

test("generate returns the active generating review instead of creating another one", async () => {
  const active = reviewFixture({
    id: "active-review",
    status: "generating",
    updatedAt: new Date(),
  });
  const service = new ReviewService({
    config: { aiSummary: { provider: "test", model: "test-model" } },
    fileLogger: { warn: async () => undefined },
    prisma: {
      review: {
        findMany: async () => [],
        findFirst: async () => active,
        create: async () => {
          assert.fail("generate should not create a duplicate while another review is generating");
        },
      },
    },
  } as never);

  const review = await service.generate({
    kind: "weekly",
    rangeMode: "rolling_7_days",
    rangeStart: new Date("2026-04-29T00:00:00.000Z"),
    rangeEnd: new Date("2026-05-06T00:00:00.000Z"),
    trigger: "manual",
  });

  assert.equal(review.id, active.id);
  assert.equal(review.status, "generating");
});

test("generate marks stale generating reviews failed before allowing another active review", async () => {
  const stale = reviewFixture({
    id: "stale-review",
    status: "generating",
    updatedAt: new Date("2026-05-05T00:00:00.000Z"),
  });
  const active = reviewFixture({
    id: "active-review",
    status: "generating",
    updatedAt: new Date("2026-05-06T00:00:00.000Z"),
  });
  let staleUpdate: Partial<Review> | null = null;
  const service = new ReviewService({
    config: { aiSummary: { provider: "test", model: "test-model" } },
    fileLogger: { warn: async () => undefined },
    prisma: {
      review: {
        findMany: async () => [stale],
        update: async ({ data }: { data: Partial<Review> }) => {
          staleUpdate = data;
          return { ...stale, ...data } as Review;
        },
        findFirst: async () => active,
        create: async () => {
          assert.fail("generate should not create a duplicate while another fresh review is generating");
        },
      },
    },
  } as never);

  const review = await service.generate({
    kind: "weekly",
    rangeMode: "rolling_7_days",
    rangeStart: new Date("2026-04-29T00:00:00.000Z"),
    rangeEnd: new Date("2026-05-06T00:00:00.000Z"),
    trigger: "manual",
  });

  assert.equal(review.id, active.id);
  assert.equal(staleUpdate?.status, "failed");
  assert.equal(staleUpdate?.errorCode, "review_generation_timeout");
});
