#!/usr/bin/env node
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

import {
  commandExists,
  commandOutput,
  liveDataDir,
  liveDatabasePath,
  makeReporter,
  parseArgs,
  rootDir,
  sqliteInt,
  sqliteValue,
} from "./lib/doctor-common.mjs";

const args = parseArgs();
const strict = args.strict === "1" || process.env.PRIVATE_MOMENTS_DOCTOR_STRICT === "1";
const reporter = makeReporter({ strict });
const databasePath = liveDatabasePath();
const dataDir = liveDataDir();
const timestamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..+/, "Z");
const drillDir = path.resolve(args["out-dir"] ?? path.join(rootDir, ".tmp", "archive-drills", timestamp));

mkdirSync(drillDir, { recursive: true });

checkInputs();
const copiedDatabase = copyAndVerifyDatabase();
const mediaReport = checkMediaFiles();
const archiveConfig = checkArchiveConfig();
writeReport({ copiedDatabase, mediaReport, archiveConfig });

reporter.printAndExit();

function checkInputs() {
  if (!databasePath || !existsSync(databasePath)) {
    reporter.fail("live database", "live database is missing", databasePath ?? "DATABASE_URL missing");
  } else {
    reporter.pass("live database", "live database exists", databasePath);
  }

  if (!dataDir || !existsSync(dataDir)) {
    reporter.fail("data dir", "data directory is missing", dataDir ?? "PRIVATE_MOMENTS_DATA_DIR missing");
  } else {
    reporter.pass("data dir", "data directory exists", dataDir);
  }
}

function copyAndVerifyDatabase() {
  if (!databasePath || !existsSync(databasePath)) {
    return null;
  }

  const target = path.join(drillDir, "app.sqlite");
  copyFileSync(databasePath, target);
  const quickCheck = sqliteValue(target, "PRAGMA quick_check;");
  const counts = {
    posts: sqliteInt(target, "SELECT COUNT(*) FROM posts;"),
    media: sqliteInt(target, "SELECT COUNT(*) FROM media;"),
    checkInEntries: sqliteInt(target, "SELECT COUNT(*) FROM checkin_entries;"),
    serverChanges: sqliteInt(target, "SELECT COALESCE(MAX(version), 0) FROM server_changes;"),
  };

  if (quickCheck === "ok") {
    reporter.pass("database copy", "copied SQLite database passes quick_check", target);
  } else {
    reporter.fail("database copy", "copied SQLite database failed quick_check", quickCheck);
  }

  reporter.pass(
    "database copy counts",
    `posts=${counts.posts}, media=${counts.media}, checkIns=${counts.checkInEntries}, latestChange=${counts.serverChanges}`,
  );
  return { path: target, quickCheck, counts };
}

function checkMediaFiles() {
  if (!databasePath || !dataDir || !existsSync(databasePath)) {
    return null;
  }

  const rows = sqliteValue(
    databasePath,
    [
      "SELECT COALESCE(compressed_path, '') FROM media WHERE deleted_at IS NULL AND COALESCE(compressed_path, '') <> '';",
      "SELECT COALESCE(original_path, '') FROM media WHERE deleted_at IS NULL AND COALESCE(original_path, '') <> '';",
      "SELECT COALESCE(thumbnail_path, '') FROM media WHERE deleted_at IS NULL AND COALESCE(thumbnail_path, '') <> '';",
      "SELECT COALESCE(compressed_path, '') FROM checkin_media WHERE deleted_at IS NULL AND COALESCE(compressed_path, '') <> '';",
    ].join("\n"),
  )
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);

  const uniquePaths = [...new Set(rows)];
  const missing = [];
  for (const storedPath of uniquePaths) {
    const absolute = path.isAbsolute(storedPath) ? storedPath : path.join(dataDir, storedPath);
    if (!existsSync(absolute)) {
      missing.push(storedPath);
    }
  }

  if (missing.length === 0) {
    reporter.pass("media files", `${uniquePaths.length} referenced media file path(s) exist`);
  } else {
    reporter.warn("media files", `${missing.length} referenced media file path(s) are missing`, missing.slice(0, 5).join(", "));
  }

  return { referenced: uniquePaths.length, missing };
}

function checkArchiveConfig() {
  if (!dataDir) {
    return null;
  }

  const archiveConfigPath = path.join(dataDir, "archive", "archive-config.json");
  if (!existsSync(archiveConfigPath)) {
    reporter.warn("archive config", "archive-config.json is missing; configure Archive before relying on scheduled backups");
    return null;
  }

  const config = JSON.parse(readFileSync(archiveConfigPath, "utf8"));
  if (config.repositoryPath) {
    reporter.pass("archive repository path", config.repositoryPath);
  } else {
    reporter.warn("archive repository path", "repositoryPath is not configured");
  }

  if (config.keyFilePath) {
    reporter.pass("archive key path", config.keyFilePath);
  } else {
    reporter.warn("archive key path", "keyFilePath is not configured");
  }

  if (commandExists("restic")) {
    const restic = commandOutput("restic", ["version"]);
    reporter.pass("restic", restic.stdout.trim() || "restic is installed");
  } else {
    reporter.warn("restic", "restic is not on PATH; Archive backup/restore execution will be unavailable");
  }

  const pendingPromotePath = path.join(dataDir, "archive", "pending-promote.json");
  if (existsSync(pendingPromotePath)) {
    reporter.warn("pending promote", "pending-promote.json exists; finish or clear promote before treating the archive as normal", pendingPromotePath);
  } else {
    reporter.pass("pending promote", "no pending promote artifact");
  }

  return config;
}

function writeReport(report) {
  const reportPath = path.join(drillDir, "report.json");
  writeFileSync(reportPath, `${JSON.stringify({
    generatedAt: new Date().toISOString(),
    rootDir,
    dataDir,
    databasePath,
    ...report,
  }, null, 2)}\n`);
  reporter.pass("drill report", "archive drill report written", reportPath);
}
