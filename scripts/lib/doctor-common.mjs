import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

export function parseArgs(values = process.argv.slice(2)) {
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

export function readDotEnv(filePath = path.join(rootDir, "server", ".env")) {
  if (!existsSync(filePath)) {
    return {};
  }

  const env = {};
  for (const line of readFileSync(filePath, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }

    const match = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match) {
      continue;
    }

    env[match[1]] = stripQuotes(match[2].trim());
  }
  return env;
}

export function liveDatabasePath() {
  const env = readDotEnv();
  const databaseUrl = env.DATABASE_URL;
  if (!databaseUrl?.startsWith("file:")) {
    return null;
  }

  const rawPath = databaseUrl.slice("file:".length);
  return path.isAbsolute(rawPath) ? rawPath : path.resolve(rootDir, "server", rawPath);
}

export function liveDataDir() {
  const env = readDotEnv();
  if (env.PRIVATE_MOMENTS_DATA_DIR) {
    return path.isAbsolute(env.PRIVATE_MOMENTS_DATA_DIR)
      ? env.PRIVATE_MOMENTS_DATA_DIR
      : path.resolve(rootDir, "server", env.PRIVATE_MOMENTS_DATA_DIR);
  }

  const databasePath = liveDatabasePath();
  return databasePath ? path.dirname(databasePath) : null;
}

export function expectedSchemaVersion() {
  const configPath = path.join(rootDir, "server", "src", "config", "app-config.ts");
  if (!existsSync(configPath)) {
    return null;
  }

  const match = readFileSync(configPath, "utf8").match(/SCHEMA_VERSION\s*=\s*(\d+)/);
  return match ? Number(match[1]) : null;
}

export async function getJson(url, init = {}) {
  const response = await fetch(url, {
    signal: AbortSignal.timeout(Number(init.timeoutMs ?? 5_000)),
    ...init,
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`${url} returned HTTP ${response.status}: ${text.slice(0, 240)}`);
  }

  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`${url} did not return JSON: ${text.slice(0, 240)}`);
  }
}

export async function postJson(url, body, headers = {}) {
  return getJson(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

export function sqliteValue(databasePath, sql) {
  const result = spawnSync("sqlite3", [databasePath, sql], {
    cwd: rootDir,
    encoding: "utf8",
    timeout: 10_000,
  });
  if (result.status !== 0) {
    return "";
  }
  return result.stdout.trim();
}

export function sqliteInt(databasePath, sql) {
  return Number.parseInt(sqliteValue(databasePath, sql), 10) || 0;
}

export function commandOutput(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: rootDir,
    encoding: "utf8",
    timeout: options.timeoutMs ?? 10_000,
    ...options,
  });
  return {
    ok: result.status === 0,
    status: result.status,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  };
}

export function commandExists(command) {
  return spawnSync("sh", ["-lc", `command -v ${shellEscape(command)} >/dev/null 2>&1`], {
    stdio: "ignore",
  }).status === 0;
}

export function makeReporter({ strict = false } = {}) {
  const checks = [];

  return {
    pass(name, message, evidence) {
      checks.push({ level: "pass", name, message, evidence });
    },
    warn(name, message, evidence) {
      checks.push({ level: "warn", name, message, evidence });
    },
    fail(name, message, evidence) {
      checks.push({ level: "fail", name, message, evidence });
    },
    printAndExit() {
      for (const check of checks) {
        const label = check.level === "pass" ? "PASS" : check.level === "warn" ? "WARN" : "FAIL";
        console.log(`[${label}] ${check.name}: ${check.message}`);
        if (check.evidence) {
          console.log(`       ${check.evidence}`);
        }
      }

      const failures = checks.filter((check) => check.level === "fail").length;
      const warnings = checks.filter((check) => check.level === "warn").length;
      console.log(`[SUMMARY] ${checks.length} checks, ${failures} failure(s), ${warnings} warning(s)`);
      if (failures > 0 || (strict && warnings > 0)) {
        process.exit(1);
      }
    },
    checks,
  };
}

export function shellEscape(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

export function stripQuotes(value) {
  return value.replace(/^["']|["']$/g, "");
}

export function trimTrailingSlash(value) {
  return value.endsWith("/") ? value.slice(0, -1) : value;
}
