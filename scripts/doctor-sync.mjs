#!/usr/bin/env node
import { existsSync } from "node:fs";

import {
  getJson,
  liveDatabasePath,
  makeReporter,
  parseArgs,
  postJson,
  sqliteInt,
  sqliteValue,
  trimTrailingSlash,
} from "./lib/doctor-common.mjs";

const args = parseArgs();
const strict = args.strict === "1" || process.env.PRIVATE_MOMENTS_DOCTOR_STRICT === "1";
const baseUrl = trimTrailingSlash(args["server-url"] ?? "http://127.0.0.1:3210");
const password = args.password ?? process.env.PRIVATE_MOMENTS_SMOKE_PASSWORD;
const reporter = makeReporter({ strict });
const databasePath = liveDatabasePath();

await checkHealth();
checkLocalDatabaseSignals();
await checkAdminSignals();

reporter.printAndExit();

async function checkHealth() {
  try {
    const health = await getJson(`${baseUrl}/api/v1/health`);
    reporter.pass("Mac server", `reachable with schema ${health.schemaVersion}`, baseUrl);
  } catch (error) {
    reporter.fail("Mac server", `unreachable: ${messageOf(error)}`, baseUrl);
  }
}

function checkLocalDatabaseSignals() {
  if (!databasePath || !existsSync(databasePath)) {
    reporter.fail("local database", "live SQLite database not found", databasePath ?? "missing");
    return;
  }

  const latestServerChange = sqliteInt(databasePath, "SELECT COALESCE(MAX(version), 0) FROM server_changes;");
  const recentRejected = sqliteInt(databasePath, "SELECT COUNT(*) FROM sync_operations WHERE rejected_at IS NOT NULL AND rejected_at >= datetime('now', '-24 hours');");
  const pendingServerOps = sqliteInt(databasePath, "SELECT COUNT(*) FROM sync_operations WHERE applied_at IS NULL AND rejected_at IS NULL;");
  const uploadedMedia = sqliteInt(databasePath, "SELECT COUNT(*) FROM media WHERE deleted_at IS NULL AND status = 'uploaded';");
  const blockedMedia = sqliteInt(databasePath, "SELECT COUNT(*) FROM media WHERE deleted_at IS NULL AND status NOT IN ('uploaded', 'deleted');");
  const blockedCheckInMedia = sqliteInt(databasePath, "SELECT COUNT(*) FROM checkin_media WHERE deleted_at IS NULL AND status NOT IN ('uploaded', 'deleted');");
  const activeDevices = sqliteInt(databasePath, "SELECT COUNT(*) FROM devices WHERE revoked_at IS NULL;");
  const nonReadySummaries = sqliteInt(databasePath, "SELECT COUNT(*) FROM ai_summaries WHERE deleted_at IS NULL AND status NOT IN ('ready', 'deleted');");
  const failedSummaries = sqliteInt(databasePath, "SELECT COUNT(*) FROM ai_summaries WHERE deleted_at IS NULL AND status = 'failed';");
  const runningJobs = sqliteInt(databasePath, "SELECT COUNT(*) FROM maintenance_jobs WHERE status = 'running';");
  const recentSync = sqliteValue(databasePath, "SELECT COALESCE(MAX(applied_at), '') FROM sync_operations WHERE applied_at IS NOT NULL;");

  reporter.pass("server cursor", `latest server change version is ${latestServerChange}`);
  reporter.pass("active devices", `${activeDevices} active device row(s)`);
  reporter.pass("uploaded media", `${uploadedMedia} active media row(s) are uploaded`);

  if (pendingServerOps > 0) {
    reporter.warn("server operation queue", `${pendingServerOps} operation(s) are still unapplied`);
  } else {
    reporter.pass("server operation queue", "no unapplied sync operation rows");
  }

  if (recentRejected > 0) {
    reporter.warn("recent rejections", `${recentRejected} rejected operation(s) in the last 24 hours`, "Check iOS Sync Doctor if the phone still shows pending work.");
  } else {
    reporter.pass("recent rejections", "no rejected sync operations in the last 24 hours");
  }

  if (blockedMedia + blockedCheckInMedia > 0) {
    reporter.warn(
      "server media upload state",
      `${blockedMedia} ordinary media and ${blockedCheckInMedia} check-in media row(s) are not uploaded`,
      "Use iOS Retry Uploads if the corresponding phone still has local pending media.",
    );
  } else {
    reporter.pass("server media upload state", "all active server media rows are uploaded or deleted");
  }

  if (nonReadySummaries > 0 || failedSummaries > 0) {
    reporter.warn("AI summary queue", `${nonReadySummaries} non-ready summary row(s), including ${failedSummaries} failed`);
  } else {
    reporter.pass("AI summary queue", "no active non-ready summary rows");
  }

  if (runningJobs > 0) {
    reporter.warn("maintenance jobs", `${runningJobs} maintenance job(s) are running`);
  } else {
    reporter.pass("maintenance jobs", "no running maintenance jobs");
  }

  if (recentSync) {
    reporter.pass("recent applied sync", recentSync);
  } else {
    reporter.warn("recent applied sync", "no applied sync operation timestamp found");
  }
}

async function checkAdminSignals() {
  if (!password) {
    reporter.warn("admin status", "authenticated checks skipped; set PRIVATE_MOMENTS_SMOKE_PASSWORD to compare Admin status");
    return;
  }

  try {
    const login = await postJson(`${baseUrl}/api/v1/auth/login`, {
      password,
      deviceName: "Sync Doctor",
      platform: "mac",
      deviceKey: "private-moments-sync-doctor",
    });
    const headers = { Authorization: `Bearer ${login.deviceToken}` };
    const status = await getJson(`${baseUrl}/api/v1/admin/status`, { headers });
    const sync = status.sync ?? {};
    const latestServerChangeVersion = sync.latestServerChangeVersion ?? sync.latestServerChange ?? null;
    if (latestServerChangeVersion !== null) {
      reporter.pass("admin sync cursor", `admin status latest server change version is ${latestServerChangeVersion}`);
    } else {
      reporter.warn("admin sync cursor", "admin status did not expose latest server change version");
    }

    if (status.aiSummaries) {
      reporter.pass("admin AI diagnostics", "admin status exposes AI summary diagnostics");
    }
    if (status.storage) {
      reporter.pass("admin storage diagnostics", "admin status exposes storage diagnostics");
    }
  } catch (error) {
    reporter.warn("admin status", `authenticated admin status check failed: ${messageOf(error)}`);
  }
}

function messageOf(error) {
  return error instanceof Error ? error.message : String(error);
}
