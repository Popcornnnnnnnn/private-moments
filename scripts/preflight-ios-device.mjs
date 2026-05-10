#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = parseArgs(process.argv.slice(2));
const cloudflareEndpoint = process.env.PRIVATE_MOMENTS_FALLBACK_SERVER_URL ?? readRootEnvLocal("PRIVATE_MOMENTS_FALLBACK_SERVER_URL");
const serverUrl = args["server-url"] ?? process.env.PRIVATE_MOMENTS_DEVICE_SERVER_URL ?? cloudflareEndpoint ?? "http://127.0.0.1:3210";
const deviceName = args.device ?? process.env.PRIVATE_MOMENTS_DEVICE_NAME ?? "Your iPhone";
const strict = process.env.PRIVATE_MOMENTS_PREFLIGHT_STRICT === "1" || args.strict === "1";

const checks = [];

const health = await checkHealth(serverUrl);
const expectedSchemaVersion = readExpectedSchemaVersion();
if (health.ok && expectedSchemaVersion !== null && health.value.schemaVersion < expectedSchemaVersion) {
  checks.push(fail(
    "schema",
    `server schema ${health.value.schemaVersion} is older than expected ${expectedSchemaVersion}`,
  ));
} else if (health.ok) {
  checks.push(pass(
    "schema",
    expectedSchemaVersion === null
      ? `server schema ${health.value.schemaVersion}`
      : `server schema ${health.value.schemaVersion} matches expected ${expectedSchemaVersion}`,
  ));
}

checks.push(health.ok
  ? pass("server", `${serverUrl} is reachable`)
  : fail("server", `${serverUrl} is not reachable: ${health.error}`));

checks.push(...checkLocalArchiveDatabase());
checks.push(checkDeviceListing(deviceName));

const failures = checks.filter((check) => check.level === "fail");
const warnings = checks.filter((check) => check.level === "warn");

for (const check of checks) {
  const label = check.level === "pass" ? "PASS" : check.level === "warn" ? "WARN" : "FAIL";
  console.log(`[${label}] ${check.name}: ${check.message}`);
}

if (warnings.length > 0) {
  console.log(`[INFO] ${warnings.length} warning(s). Set PRIVATE_MOMENTS_PREFLIGHT_STRICT=1 to fail on warnings.`);
}

if (failures.length > 0 || (strict && warnings.length > 0)) {
  process.exit(1);
}

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (!value.startsWith("--")) {
      continue;
    }

    const key = value.slice(2);
    const next = values[index + 1];
    if (next && !next.startsWith("--")) {
      parsed[key] = next;
      index += 1;
    } else {
      parsed[key] = "1";
    }
  }
  return parsed;
}

async function checkHealth(baseUrl) {
  try {
    const response = await fetch(`${baseUrl.replace(/\/$/, "")}/api/v1/health`, {
      signal: AbortSignal.timeout(5_000),
    });
    if (!response.ok) {
      return { ok: false, error: `HTTP ${response.status}` };
    }

    const value = await response.json();
    return { ok: true, value };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : String(error) };
  }
}

function readExpectedSchemaVersion() {
  const appConfigPath = path.join(rootDir, "server", "src", "config", "app-config.ts");
  if (!existsSync(appConfigPath)) {
    return null;
  }

  const match = readFileSync(appConfigPath, "utf8").match(/SCHEMA_VERSION\s*=\s*(\d+)/);
  return match ? Number(match[1]) : null;
}

function checkLocalArchiveDatabase() {
  const databasePath = liveDatabasePath();
  if (!databasePath) {
    return [warn("database", "DATABASE_URL was not found in server/.env; skipped local archive queue checks")];
  }

  if (!existsSync(databasePath)) {
    return [warn("database", `database file not found at ${databasePath}`)];
  }

  if (!commandExists("sqlite3")) {
    return [warn("database", "sqlite3 is not available; skipped local archive queue checks")];
  }

  const runningJobs = queryInt(databasePath, "SELECT COUNT(*) FROM maintenance_jobs WHERE status = 'running';");
  const rejectedOps = queryInt(databasePath, "SELECT COUNT(*) FROM sync_operations WHERE rejected_at IS NOT NULL;");
  const pendingOps = queryInt(databasePath, "SELECT COUNT(*) FROM sync_operations WHERE applied_at IS NULL AND rejected_at IS NULL;");
  const mediaNotUploaded = queryInt(databasePath, "SELECT COUNT(*) FROM media WHERE deleted_at IS NULL AND status NOT IN ('uploaded', 'deleted');");
  const checkInMediaNotUploaded = queryInt(databasePath, "SELECT COUNT(*) FROM checkin_media WHERE deleted_at IS NULL AND status NOT IN ('uploaded', 'deleted');");
  const latestBackup = queryText(databasePath, "SELECT COALESCE(status || ':' || created_at, '') FROM maintenance_jobs WHERE type = 'backup_create' ORDER BY created_at DESC LIMIT 1;");

  const results = [
    runningJobs > 0
      ? warn("maintenance", `${runningJobs} maintenance job(s) are still running`)
      : pass("maintenance", "no running maintenance job"),
    pendingOps > 0
      ? warn("server sync queue", `${pendingOps} unapplied server sync operation(s)`)
      : pass("server sync queue", "no unapplied server sync operations"),
    rejectedOps > 0
      ? warn("server rejected ops", `${rejectedOps} historical rejected operation(s); inspect only if iPhone still has pending work`)
      : pass("server rejected ops", "no rejected operations"),
    mediaNotUploaded + checkInMediaNotUploaded > 0
      ? warn("server media", `${mediaNotUploaded} media and ${checkInMediaNotUploaded} check-in media item(s) not uploaded`)
      : pass("server media", "all active server media rows are uploaded or deleted"),
  ];

  if (latestBackup) {
    results.push(pass("last backup", latestBackup));
  } else {
    results.push(warn("last backup", "no backup_create job found in the local archive database"));
  }

  return results;
}

function liveDatabasePath() {
  const envPath = path.join(rootDir, "server", ".env");
  if (!existsSync(envPath)) {
    return null;
  }

  const env = readFileSync(envPath, "utf8");
  const match = env.match(/^DATABASE_URL=(.+)$/m);
  if (!match) {
    return null;
  }

  let value = match[1].trim().replace(/^["']|["']$/g, "");
  if (!value.startsWith("file:")) {
    return null;
  }

  value = value.slice("file:".length);
  return path.isAbsolute(value) ? value : path.resolve(rootDir, "server", value);
}

function readRootEnvLocal(key) {
  const envLocalPath = path.join(rootDir, ".env.local");
  if (!existsSync(envLocalPath)) {
    return null;
  }

  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = readFileSync(envLocalPath, "utf8").match(new RegExp(`^${escapedKey}=(.+)$`, "m"));
  return match ? match[1].trim().replace(/^["']|["']$/g, "") : null;
}

function queryInt(databasePath, sql) {
  const value = queryText(databasePath, sql);
  return Number.parseInt(value, 10) || 0;
}

function queryText(databasePath, sql) {
  const result = spawnSync("sqlite3", [databasePath, sql], {
    cwd: rootDir,
    encoding: "utf8",
    timeout: 10_000,
  });
  return result.status === 0 ? result.stdout.trim() : "";
}

function checkDeviceListing(name) {
  if (!commandExists("xcrun")) {
    return warn("device", "xcrun is not available; skipped paired iPhone visibility check");
  }

  const result = spawnSync("xcrun", ["devicectl", "list", "devices"], {
    cwd: rootDir,
    encoding: "utf8",
    timeout: 15_000,
  });
  if (result.status !== 0) {
    return warn("device", "devicectl device list failed; keep the iPhone unlocked and trusted before install");
  }

  const line = result.stdout
    .split("\n")
    .map((item) => item.trim())
    .find((item) => item.includes(name));

  if (!line) {
    return warn("device", `${name} was not found in devicectl output`);
  }

  return pass("device", line);
}

function commandExists(command) {
  return spawnSync("sh", ["-lc", `command -v ${shellEscape(command)} >/dev/null 2>&1`], {
    stdio: "ignore",
  }).status === 0;
}

function shellEscape(value) {
  return `'${value.replaceAll("'", "'\\''")}'`;
}

function pass(name, message) {
  return { level: "pass", name, message };
}

function warn(name, message) {
  return { level: "warn", name, message };
}

function fail(name, message) {
  return { level: "fail", name, message };
}
