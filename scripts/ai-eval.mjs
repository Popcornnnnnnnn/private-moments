#!/usr/bin/env node
import { existsSync } from "node:fs";

import {
  commandOutput,
  liveDatabasePath,
  makeReporter,
  parseArgs,
  sqliteInt,
} from "./lib/doctor-common.mjs";

const args = parseArgs();
const strict = args.strict === "1" || process.env.PRIVATE_MOMENTS_DOCTOR_STRICT === "1";
const reporter = makeReporter({ strict });
const databasePath = liveDatabasePath();
const limit = Number.parseInt(args.limit ?? "20", 10);

if (!databasePath || !existsSync(databasePath)) {
  reporter.fail("AI eval database", "live SQLite database not found", databasePath ?? "DATABASE_URL missing");
  reporter.printAndExit();
}

evaluateMediaSummaries();
evaluateReviews();
evaluateUsageLedger();

reporter.printAndExit();

function evaluateMediaSummaries() {
  const readyCount = sqliteInt(databasePath, "SELECT COUNT(*) FROM ai_summaries WHERE deleted_at IS NULL AND status = 'ready';");
  const failedCount = sqliteInt(databasePath, "SELECT COUNT(*) FROM ai_summaries WHERE deleted_at IS NULL AND status = 'failed';");
  const badTitleCount = sqliteInt(
    databasePath,
    "SELECT COUNT(*) FROM ai_summaries WHERE deleted_at IS NULL AND status = 'ready' AND (COALESCE(document_title, '') = '' OR length(document_title) > 40);",
  );
  const oldPromptCount = sqliteInt(
    databasePath,
    "SELECT COUNT(*) FROM ai_summaries WHERE deleted_at IS NULL AND status = 'ready' AND COALESCE(prompt_version, '') <> 'media-summary-v4';",
  );
  const emptyBodyCount = sqliteInt(
    databasePath,
    "SELECT COUNT(*) FROM ai_summaries WHERE deleted_at IS NULL AND status = 'ready' AND COALESCE(summary_text, '') = '' AND COALESCE(one_liner, '') = '' AND COALESCE(document_blocks_json, '[]') = '[]';",
  );

  if (readyCount > 0) {
    reporter.pass("AI summaries", `${readyCount} ready summary row(s), ${failedCount} failed row(s)`);
  } else {
    reporter.warn("AI summaries", "no ready summary rows found");
  }

  if (badTitleCount > 0) {
    reporter.warn("AI summary titles", `${badTitleCount} ready summary title(s) are blank or over 40 characters`);
  } else {
    reporter.pass("AI summary titles", "ready summary titles are present and within 40 characters");
  }

  if (oldPromptCount > 0) {
    reporter.warn("AI summary prompt version", `${oldPromptCount} ready summary row(s) use legacy prompt versions`);
  } else {
    reporter.pass("AI summary prompt version", "all ready summaries use media-summary-v4");
  }

  if (emptyBodyCount > 0) {
    reporter.warn("AI summary body", `${emptyBodyCount} ready summary row(s) have no one-liner, summary text, or document blocks`);
  } else {
    reporter.pass("AI summary body", "ready summaries have visible body content");
  }

  const recent = queryJson(
    `SELECT id, document_title, one_liner, prompt_version
       FROM ai_summaries
      WHERE deleted_at IS NULL
      ORDER BY updated_at DESC
      LIMIT ${safeLimit(limit)};`,
  );
  const overlongOneLiners = recent.filter((row) => (row.one_liner ?? "").length > 240);
  if (overlongOneLiners.length > 0) {
    reporter.warn("AI summary one-liners", `${overlongOneLiners.length} recent one-liner(s) are over 240 characters`);
  } else {
    reporter.pass("AI summary one-liners", "recent one-liners stay compact");
  }
}

function evaluateReviews() {
  const readyReviews = queryJson(
    `SELECT id, prompt_version, content_json
       FROM reviews
      WHERE deleted_at IS NULL AND status = 'ready'
      ORDER BY updated_at DESC
      LIMIT ${safeLimit(limit)};`,
  );

  if (readyReviews.length === 0) {
    reporter.warn("Weekly Review eval", "no ready reviews found");
    return;
  }

  let invalidContent = 0;
  let invalidAnchors = 0;
  let legacyPrompt = 0;
  for (const review of readyReviews) {
    if (review.prompt_version !== "weekly-review-v2") {
      legacyPrompt += 1;
    }

    let content;
    try {
      content = JSON.parse(review.content_json || "{}");
    } catch {
      invalidContent += 1;
      continue;
    }

    const momentIds = collectMomentIds(content.notableMoments ?? []);
    for (const momentId of momentIds) {
      const exists = sqliteInt(databasePath, `SELECT COUNT(*) FROM posts WHERE id = ${sqlString(momentId)} AND deleted_at IS NULL;`);
      if (exists === 0) {
        invalidAnchors += 1;
      }
    }
  }

  reporter.pass("Weekly Review eval", `${readyReviews.length} ready review row(s) inspected`);
  if (legacyPrompt > 0) {
    reporter.warn("Weekly Review prompt version", `${legacyPrompt} ready review row(s) use legacy prompt versions`);
  } else {
    reporter.pass("Weekly Review prompt version", "ready reviews use weekly-review-v2");
  }

  if (invalidContent > 0) {
    reporter.warn("Weekly Review content JSON", `${invalidContent} ready review row(s) have invalid content JSON`);
  } else {
    reporter.pass("Weekly Review content JSON", "ready review content JSON parses");
  }

  if (invalidAnchors > 0) {
    reporter.warn("Weekly Review anchors", `${invalidAnchors} Worth Revisiting anchor(s) point to missing/deleted posts`);
  } else {
    reporter.pass("Weekly Review anchors", "Worth Revisiting anchors point to existing active posts");
  }
}

function evaluateUsageLedger() {
  const totalUsage = sqliteInt(databasePath, "SELECT COUNT(*) FROM ai_usage_events;");
  const unsafeTextHits = sqliteInt(
    databasePath,
    "SELECT COUNT(*) FROM ai_usage_events WHERE COALESCE(error_code, '') LIKE '%transcript%' OR COALESCE(error_code, '') LIKE '%summary%';",
  );
  if (totalUsage > 0) {
    reporter.pass("AI usage ledger", `${totalUsage} privacy-safe usage event row(s)`);
  } else {
    reporter.warn("AI usage ledger", "no AI usage event rows found");
  }

  if (unsafeTextHits > 0) {
    reporter.warn("AI usage error codes", `${unsafeTextHits} usage row(s) have suspicious text-like error_code values`);
  } else {
    reporter.pass("AI usage error codes", "usage error codes do not look like transcript/summary bodies");
  }
}

function queryJson(sql) {
  const result = commandOutput("sqlite3", ["-json", databasePath, sql], { timeoutMs: 10_000 });
  if (!result.ok || !result.stdout.trim()) {
    return [];
  }

  try {
    return JSON.parse(result.stdout);
  } catch {
    return [];
  }
}

function collectMomentIds(items) {
  const ids = [];
  for (const item of Array.isArray(items) ? items : []) {
    if (Array.isArray(item?.momentIds)) {
      ids.push(...item.momentIds.filter((value) => typeof value === "string"));
    }
  }
  return [...new Set(ids)];
}

function safeLimit(value) {
  if (!Number.isInteger(value) || value < 1) {
    return 20;
  }
  return Math.min(value, 100);
}

function sqlString(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}
