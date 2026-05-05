# S01: Maintenance Job And Mode Foundation

**Goal:** Implement the durable server-side foundation for archive, restore, export/import, and sync-health work.

**Demo:** Mac server can create, persist, list, and update maintenance jobs; only one maintenance job runs at a time; maintenance mode can block write-heavy APIs during restore/promote; Admin can fetch safe job state.

## Must-Haves

- Add a durable `maintenance_jobs` table.
- Add job types for:
  - `backup_create`
  - `backup_check`
  - `backup_restore`
  - `backup_promote`
  - `export_create`
  - `import_restore`
  - `sync_health_refresh`
- Add job statuses:
  - `queued`
  - `running`
  - `succeeded`
  - `failed`
  - `cancelled`
- Store:
  - job ID
  - type
  - status
  - stage
  - progress percentage
  - safe metadata JSON
  - artifact path
  - error code/message
  - created/started/finished timestamps
- Add a serial job runner so only one maintenance job executes at once.
- Add maintenance mode state that can block ordinary sync/media/AI writes during restore/promote.
- Add safe Admin API routes to list jobs, get job details, and get maintenance mode state.
- Do not store private content bodies in job metadata, logs, or Admin responses.

## Requirement Impact

- Owns R039.
- Supports R033, R034, R035, R036, R037, R038.

## Threat Surface

- **Data corruption:** restore/promote must not run while ordinary writes continue.
- **Lost job state:** long-running operations must survive browser refresh and remain inspectable after server restart.
- **Over-broad maintenance mode:** read-only Admin/status health checks should remain available where safe.
- **Privacy leakage:** job metadata must not contain post text, comments, transcript, summary body, or media content.
- **Deadlocks:** a failed job must clear in-memory execution state and leave maintenance mode in a known state.

## Planned Tasks

### T01 — Schema And Types

- Add Prisma `MaintenanceJob` model.
- Add migration.
- Add TypeScript job type/status/stage helpers.
- Add safe metadata validation helpers.

### T02 — Job Repository

- Implement create/list/get/update helpers.
- Normalize job state transitions.
- Ensure failed/succeeded terminal states include finished timestamp.
- Add safe serialization for Admin responses.

### T03 — Serial Runner

- Implement a process-local serial runner for v0.1.
- On server startup, mark stale `running` jobs as failed with restart-safe error metadata unless a job type later supports resume.
- Prevent starting a second job while one is active.
- Keep runner generic so S02/S05 can plug in actual backup/export jobs.

### T04 — Maintenance Mode Guard

- Add a server maintenance mode state that can be entered by restore/promote jobs.
- Block write-heavy routes while active:
  - sync push/pull mutations that can write server state
  - media upload
  - AI summary regenerate/delete/start operations
  - Admin destructive post cleanup
- Keep health/status/job read endpoints available.

### T05 — Admin API Surface

- Add Admin routes:
  - list maintenance jobs
  - get one maintenance job
  - get maintenance state
- Add OpenAPI updates if routes are externally documented.

## Verification

- `npm run server:prisma:generate`
- `npm run server:build`
- `npm run admin:build` if Admin API model changes require Admin compile updates.
- Prisma migration deploy against local dev database.
- HTTP smoke:
  - list jobs returns empty or existing safe rows.
  - creating a test/no-op job persists status transitions.
  - maintenance mode blocks a representative write route and leaves health/job reads available.
- `git diff --check`

## Files Likely Touched

- `server/prisma/schema.prisma`
- `server/prisma/migrations/*/migration.sql`
- `server/src/api/admin.ts`
- `server/src/api/sync.ts`
- `server/src/api/media.ts`
- `server/src/ai/*`
- `server/src/config/*`
- `shared/openapi.yaml`

## Done Criteria

- Durable maintenance jobs exist and are queryable.
- Job status transitions are persistent and safe for Admin display.
- Serial runner prevents concurrent maintenance jobs.
- Maintenance mode can safely protect restore/promote windows.
- No job metadata/log output includes private content bodies.
- S02 can implement restic backup/restore on top of this foundation without redesigning job state.
