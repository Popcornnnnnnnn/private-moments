#!/usr/bin/env node
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

import {
  commandExists,
  commandOutput,
  expectedSchemaVersion,
  getJson,
  liveDataDir,
  liveDatabasePath,
  makeReporter,
  parseArgs,
  readDotEnv,
  rootDir,
  shellEscape,
  sqliteValue,
  trimTrailingSlash,
} from "./lib/doctor-common.mjs";

const args = parseArgs();
const strict = args.strict === "1" || process.env.PRIVATE_MOMENTS_DOCTOR_STRICT === "1";
const label = args.label ?? process.env.PRIVATE_MOMENTS_LAUNCHD_LABEL ?? "com.private-moments.server";
const localUrl = trimTrailingSlash(args["server-url"] ?? "http://127.0.0.1:3210");
const expectedRoot = path.resolve(args.root ?? rootDir);
const reporter = makeReporter({ strict });

const env = readDotEnv();
const databasePath = liveDatabasePath();
const dataDir = liveDataDir();

checkEnvPaths();
await checkHealth(`${localUrl}/api/v1/health`);
checkLaunchAgent();
checkLiveProcess();
checkGeneratedPaths();
checkSqlite();
await checkNetworkEntrypoints();

reporter.printAndExit();

function checkEnvPaths() {
  if (!databasePath) {
    reporter.fail("env database", "server/.env DATABASE_URL is missing or is not a file: URL");
  } else if (!isInside(databasePath, expectedRoot)) {
    reporter.fail("env database", "DATABASE_URL points outside the current checkout", databasePath);
  } else {
    reporter.pass("env database", "DATABASE_URL points inside the current checkout", databasePath);
  }

  if (!dataDir) {
    reporter.fail("env data dir", "PRIVATE_MOMENTS_DATA_DIR is missing");
  } else if (!isInside(dataDir, expectedRoot)) {
    reporter.fail("env data dir", "PRIVATE_MOMENTS_DATA_DIR points outside the current checkout", dataDir);
  } else {
    reporter.pass("env data dir", "PRIVATE_MOMENTS_DATA_DIR points inside the current checkout", dataDir);
  }

  if (env.AI_LOCAL_TRANSCRIPTION_PYTHON && !isInside(path.resolve(env.AI_LOCAL_TRANSCRIPTION_PYTHON), expectedRoot)) {
    reporter.warn("AI python", "AI_LOCAL_TRANSCRIPTION_PYTHON points outside the current checkout", env.AI_LOCAL_TRANSCRIPTION_PYTHON);
  }
}

async function checkHealth(url) {
  try {
    const health = await getJson(url);
    const schemaVersion = expectedSchemaVersion();
    if (schemaVersion !== null && health.schemaVersion !== schemaVersion) {
      reporter.fail("health schema", `health schema ${health.schemaVersion} does not match expected ${schemaVersion}`);
    } else {
      reporter.pass("health schema", `health schema is ${health.schemaVersion}`);
    }

    for (const [name, value] of [
      ["health data dir", health.dataDir],
      ["health database", health.databasePath],
      ["health media dir", health.mediaDir],
    ]) {
      if (!value) {
        reporter.fail(name, "health response omitted runtime path");
      } else if (!isInside(path.resolve(value), expectedRoot)) {
        reporter.fail(name, "health runtime path points outside the current checkout", value);
      } else {
        reporter.pass(name, "health runtime path points inside the current checkout", value);
      }
    }
  } catch (error) {
    reporter.fail("health", `local health check failed: ${messageOf(error)}`);
  }
}

function checkLaunchAgent() {
  if (!commandExists("launchctl")) {
    reporter.warn("launchctl", "launchctl unavailable; skipped LaunchAgent checks");
    return;
  }

  const result = commandOutput("launchctl", ["print", `gui/${process.getuid()}/${label}`]);
  if (!result.ok) {
    reporter.fail("LaunchAgent", `${label} is not loaded`, result.stderr.trim());
    return;
  }

  const output = `${result.stdout}\n${result.stderr}`;
  const workingDirectory = matchLine(output, /working directory = (.+)/);
  const state = matchLine(output, /state = (.+)/);
  if (state === "running") {
    reporter.pass("LaunchAgent state", `${label} is running`);
  } else {
    reporter.fail("LaunchAgent state", `${label} state is ${state || "unknown"}`);
  }

  if (!workingDirectory) {
    reporter.fail("LaunchAgent cwd", "working directory missing from launchctl output");
  } else if (path.resolve(workingDirectory) !== path.join(expectedRoot, "server")) {
    reporter.fail("LaunchAgent cwd", "working directory does not match current server directory", workingDirectory);
  } else {
    reporter.pass("LaunchAgent cwd", "working directory matches current server directory", workingDirectory);
  }

  const plistPath = path.join(process.env.HOME ?? "", "Library", "LaunchAgents", `${label}.plist`);
  if (existsSync(plistPath)) {
    const plist = readFileSync(plistPath, "utf8");
    if (plist.includes("/07-github/private-moments") || plist.includes("/.Trash/07-github/private-moments")) {
      reporter.fail("LaunchAgent plist", "plist still contains the old checkout path", plistPath);
    } else {
      reporter.pass("LaunchAgent plist", "plist has no old checkout path", plistPath);
    }
  }
}

function checkLiveProcess() {
  if (!commandExists("lsof")) {
    reporter.warn("process fd", "lsof unavailable; skipped live process fd checks");
    return;
  }

  const pidResult = commandOutput("sh", ["-lc", "lsof -tiTCP:3210 -sTCP:LISTEN | head -n1"]);
  const pid = pidResult.stdout.trim();
  if (!pid) {
    reporter.fail("listener", "no process is listening on TCP 3210");
    return;
  }

  const lsof = commandOutput("lsof", ["-a", "-p", pid]);
  const output = `${lsof.stdout}\n${lsof.stderr}`;
  const cwdLine = output.split("\n").find((line) => /\bcwd\b/.test(line));
  if (cwdLine?.includes(path.join(expectedRoot, "server"))) {
    reporter.pass("process cwd", "listener process cwd is the current server directory", `pid ${pid}`);
  } else {
    reporter.fail("process cwd", "listener process cwd is not the current server directory", cwdLine ?? `pid ${pid}`);
  }

  if (output.includes("/.Trash/") || output.includes("/07-github/private-moments")) {
    reporter.fail("process old fd", "listener process still has old checkout or Trash file descriptors");
  } else {
    reporter.pass("process old fd", "listener process has no old checkout or Trash file descriptors");
  }

  if (databasePath && output.includes(databasePath)) {
    reporter.pass("process database fd", "listener process has the current SQLite database open", databasePath);
  } else {
    reporter.warn("process database fd", "current SQLite database fd not visible yet; this may be normal before first DB request");
  }
}

function checkGeneratedPaths() {
  const scanTargets = [
    path.join(rootDir, "node_modules", ".prisma", "client"),
    path.join(rootDir, "server", ".venv", "bin"),
    path.join(rootDir, "server", ".venv", "pyvenv.cfg"),
  ].filter((target) => existsSync(target));

  if (scanTargets.length === 0) {
    reporter.warn("generated path scan", "no generated Prisma or venv paths found to scan");
    return;
  }

  const command = `rg -n ${shellEscape("07-github/private-moments|MacLocal/Projects/07-github/private-moments|.Trash/07-github/private-moments")} ${scanTargets.map(shellEscape).join(" ")}`;
  const result = commandOutput("sh", ["-lc", command], { timeoutMs: 15_000 });
  if (result.status === 0) {
    reporter.fail("generated path scan", "generated files still contain old checkout paths", result.stdout.trim().split("\n").slice(0, 5).join(" | "));
  } else {
    reporter.pass("generated path scan", "generated Prisma client and Python venv contain no old checkout paths");
  }
}

function checkSqlite() {
  if (!databasePath || !existsSync(databasePath)) {
    reporter.fail("sqlite", "live database path does not exist", databasePath ?? "missing");
    return;
  }

  const quickCheck = sqliteValue(databasePath, "PRAGMA quick_check;");
  if (quickCheck === "ok") {
    reporter.pass("sqlite quick_check", "live database integrity check passed");
  } else {
    reporter.fail("sqlite quick_check", "live database integrity check failed", quickCheck);
  }

  const writable = commandOutput("sqlite3", [databasePath, "PRAGMA user_version;"]);
  if (writable.ok) {
    reporter.pass("sqlite readable", "sqlite3 can read the live database");
  } else {
    reporter.fail("sqlite readable", "sqlite3 cannot read the live database", writable.stderr.trim());
  }
}

async function checkNetworkEntrypoints() {
  const tailscaleIp = commandOutput("sh", ["-lc", "tailscale ip -4 2>/dev/null | head -n1"]).stdout.trim();
  if (tailscaleIp) {
    await checkOptionalHealth(`http://${tailscaleIp}:3210/api/v1/health`, "Tailscale IP health");
  } else {
    reporter.warn("Tailscale IP health", "tailscale ip -4 did not return an address");
  }

  const cloudflareUrl = process.env.PRIVATE_MOMENTS_FALLBACK_SERVER_URL ?? readRootEnvLocalCloudflareEndpoint();
  if (cloudflareUrl) {
    await checkOptionalHealth(`${trimTrailingSlash(cloudflareUrl)}/api/v1/health`, "Cloudflare endpoint health");
  }

  const serveHostname = args["tailscale-serve-hostname"];
  if (serveHostname && tailscaleIp) {
    const result = commandOutput("curl", [
      "-fsS",
      "--resolve",
      `${serveHostname}:443:${tailscaleIp}`,
      `https://${serveHostname}/api/v1/health`,
    ], { timeoutMs: 10_000 });
    if (result.ok && result.stdout.includes(expectedRoot)) {
      reporter.pass("Tailscale Serve health", "Tailscale Serve hostname reaches the current checkout when resolved to the Tailscale IP");
    } else if (result.ok) {
      reporter.fail("Tailscale Serve health", "Tailscale Serve hostname responded but did not report the current checkout", result.stdout.slice(0, 240));
    } else {
      reporter.warn("Tailscale Serve health", "Tailscale Serve hostname check failed", result.stderr.trim());
    }
  }
}

async function checkOptionalHealth(url, name) {
  try {
    const health = await getJson(url);
    if (health.dataDir && isInside(path.resolve(health.dataDir), expectedRoot)) {
      reporter.pass(name, "health endpoint reports current checkout data dir", url);
    } else {
      reporter.fail(name, "health endpoint reports a data dir outside the current checkout", `${url} -> ${health.dataDir}`);
    }
  } catch (error) {
    reporter.warn(name, messageOf(error), url);
  }
}

function readRootEnvLocalCloudflareEndpoint() {
  const envLocal = readDotEnv(path.join(rootDir, ".env.local"));
  return envLocal.PRIVATE_MOMENTS_FALLBACK_SERVER_URL;
}

function isInside(child, parent) {
  const relative = path.relative(parent, child);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function matchLine(value, pattern) {
  return value.match(pattern)?.[1]?.trim() ?? "";
}

function messageOf(error) {
  return error instanceof Error ? error.message : String(error);
}
