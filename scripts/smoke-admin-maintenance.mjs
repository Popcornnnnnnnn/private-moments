#!/usr/bin/env node
const args = new Map();
for (let index = 2; index < process.argv.length; index += 1) {
  const current = process.argv[index];
  const next = process.argv[index + 1];
  if (current.startsWith("--")) {
    args.set(current.slice(2), next?.startsWith("--") ? "true" : next ?? "true");
    if (next && !next.startsWith("--")) {
      index += 1;
    }
  }
}

const baseUrl = trimTrailingSlash(
  args.get("server-url") ?? process.env.PRIVATE_MOMENTS_SMOKE_SERVER_URL ?? "http://127.0.0.1:3210",
);
const password = process.env.PRIVATE_MOMENTS_SMOKE_PASSWORD;
const deviceKey = args.get("device-key") ?? "private-moments-admin-smoke";

await getJson("/api/v1/health");
console.log(`health ok: ${baseUrl}`);

if (!password) {
  console.log("authenticated smoke skipped: set PRIVATE_MOMENTS_SMOKE_PASSWORD to check admin/review/archive APIs");
  process.exit(0);
}

const login = await postJson("/api/v1/auth/login", {
  password,
  deviceName: "Admin Smoke",
  platform: "mac",
  deviceKey,
});
const authHeaders = {
  Authorization: `Bearer ${login.deviceToken}`,
};

const status = await getJson("/api/v1/admin/status", authHeaders);
expectObject(status.sync, "admin status sync");
expectObject(status.aiUsage, "admin status aiUsage");

const maintenance = await getJson("/api/v1/admin/maintenance/state", authHeaders);
expectObject(maintenance.maintenance, "maintenance state");

const jobs = await getJson("/api/v1/admin/maintenance/jobs?limit=5", authHeaders);
expectArray(jobs.jobs, "maintenance jobs");

const repository = await getJson("/api/v1/admin/archive/repository", authHeaders);
expectObject(repository.repository, "archive repository");

const reviewSettings = await getJson("/api/v1/reviews/settings", authHeaders);
expectObject(reviewSettings.settings, "review settings");

const reviews = await getJson("/api/v1/reviews", authHeaders);
expectArray(reviews.reviews, "reviews list");

console.log("authenticated admin/review/archive smoke ok");

async function getJson(route, headers = {}) {
  return requestJson(route, {
    method: "GET",
    headers,
  });
}

async function postJson(route, body, headers = {}) {
  return requestJson(route, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

async function requestJson(route, init) {
  const response = await fetch(`${baseUrl}${route}`, init);
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`${init.method} ${route} failed: ${response.status} ${text}`);
  }

  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`${init.method} ${route} did not return JSON: ${text.slice(0, 120)}`);
  }
}

function expectObject(value, label) {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${label} missing or invalid`);
  }
}

function expectArray(value, label) {
  if (!Array.isArray(value)) {
    throw new Error(`${label} missing or invalid`);
  }
}

function trimTrailingSlash(value) {
  return value.endsWith("/") ? value.slice(0, -1) : value;
}
