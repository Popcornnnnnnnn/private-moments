import test from "node:test";
import assert from "node:assert/strict";

import {
  MAX_REVIEW_INPUT_MOMENTS,
  MAX_REVIEW_RANGE_DAYS,
  ReviewInputLimitError,
  assertReviewMomentCount,
  validateReviewRange,
} from "./review-limits.js";

test("validateReviewRange accepts normal weekly ranges", () => {
  const start = new Date("2026-05-01T00:00:00.000Z");
  const end = new Date("2026-05-08T00:00:00.000Z");

  assert.equal(validateReviewRange(start, end), null);
});

test("validateReviewRange rejects reversed ranges", () => {
  const start = new Date("2026-05-08T00:00:00.000Z");
  const end = new Date("2026-05-01T00:00:00.000Z");

  assert.equal(validateReviewRange(start, end), "rangeStart must be before rangeEnd");
});

test("validateReviewRange rejects ranges over the review budget", () => {
  const start = new Date("2026-01-01T00:00:00.000Z");
  const end = new Date(start.getTime() + (MAX_REVIEW_RANGE_DAYS + 1) * 24 * 60 * 60 * 1000);

  assert.equal(validateReviewRange(start, end), `Review range must be ${MAX_REVIEW_RANGE_DAYS} days or less`);
});

test("assertReviewMomentCount rejects oversized packs before provider calls", () => {
  assert.throws(
    () => assertReviewMomentCount(MAX_REVIEW_INPUT_MOMENTS + 1),
    ReviewInputLimitError,
  );
});
