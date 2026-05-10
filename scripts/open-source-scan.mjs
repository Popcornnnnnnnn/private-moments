#!/usr/bin/env node
import { existsSync } from "node:fs";
import path from "node:path";

import { commandExists, commandOutput, makeReporter, parseArgs, rootDir } from "./lib/doctor-common.mjs";

const args = parseArgs();
const strict = args.strict === "1" || process.env.PRIVATE_MOMENTS_RELEASE_STRICT === "1";
const reporter = makeReporter({ strict });

checkLicense();
checkTrackedSecrets();
checkIgnoredRuntimeFiles();
checkPublicDocs();
checkGsdPolicy();

reporter.printAndExit();

function checkLicense() {
  const licensePath = path.join(rootDir, "LICENSE");
  if (existsSync(licensePath)) {
    reporter.pass("license", "LICENSE file exists");
  } else {
    reporter.warn("license", "LICENSE file is missing; choose MIT/AGPL/etc before public release");
  }
}

function checkTrackedSecrets() {
  if (!commandExists("git")) {
    reporter.warn("tracked secret scan", "git unavailable; skipped tracked file scan");
    return;
  }

  const secretResult = commandOutput("sh", [
    "-lc",
    `git grep -n -E ${shellQuote("sk-[A-Za-z0-9_-]{20,}")} -- ':!server/.env.example' ':!docs/OPEN-SOURCE-READINESS.md'`,
  ], { timeoutMs: 15_000 });
  if (secretResult.status === 0) {
    reporter.warn("tracked API key scan", "tracked files contain API-key-looking strings", firstLines(secretResult.stdout));
  } else {
    reporter.pass("tracked API key scan", "no API-key-looking strings found in tracked source files");
  }

  const personalResult = commandOutput("sh", [
    "-lc",
    `git grep -n -E ${shellQuote("100\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}|moments\\.popcornnn\\.xyz|wwz 的 iphone")} -- ':!docs/OPEN-SOURCE-READINESS.md' ':!docs/OPERATOR-RUNBOOK.md' ':!AGENTS.md' ':!scripts/open-source-scan.mjs'`,
  ], { timeoutMs: 15_000 });
  if (personalResult.status === 0) {
    reporter.warn("tracked personal config scan", "tracked files still contain personal deployment details", firstLines(personalResult.stdout));
  } else {
    reporter.pass("tracked personal config scan", "no personal Tailscale/domain/device details found outside allowed docs");
  }
}

function checkIgnoredRuntimeFiles() {
  const runtimePaths = [
    "server/.env",
    "server/data",
    "server/.venv",
    ".env.local",
    ".tmp",
    "node_modules",
    "admin/dist",
    "server/dist",
  ];

  const missing = [];
  for (const runtimePath of runtimePaths) {
    const result = commandOutput("git", ["check-ignore", "-q", runtimePath], { timeoutMs: 10_000 });
    if (!result.ok) {
      missing.push(runtimePath);
    }
  }

  if (missing.length === 0) {
    reporter.pass("ignored runtime files", "core runtime/private paths are ignored by git");
  } else {
    reporter.warn("ignored runtime files", "one or more runtime/private paths may not be ignored", missing.join(", "));
  }
}

function checkPublicDocs() {
  const docs = [
    "README.md",
    "SECURITY.md",
    "docs/PRD.md",
    "docs/TECH-DESIGN.md",
    "docs/OPERATOR-RUNBOOK.md",
    "docs/RELEASE-CHECKLIST.md",
    "docs/OPEN-SOURCE-READINESS.md",
  ];
  const missing = docs.filter((item) => !existsSync(path.join(rootDir, item)));
  if (missing.length === 0) {
    reporter.pass("public docs", "minimum public documentation set exists");
  } else {
    reporter.warn("public docs", "minimum public documentation set is incomplete", missing.join(", "));
  }
}

function checkGsdPolicy() {
  const readinessPath = path.join(rootDir, "docs", "OPEN-SOURCE-READINESS.md");
  if (!existsSync(readinessPath)) {
    reporter.warn(".gsd release policy", "OPEN-SOURCE-READINESS.md missing");
    return;
  }

  const result = commandOutput("rg", ["-n", "\\.gsd", readinessPath], { timeoutMs: 10_000 });
  if (result.ok) {
    reporter.pass(".gsd release policy", "open-source readiness doc records the .gsd public/private decision point");
  } else {
    reporter.warn(".gsd release policy", "document whether .gsd is cleaned, omitted, or published before release");
  }
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function firstLines(value) {
  return value.trim().split("\n").slice(0, 8).join(" | ");
}
