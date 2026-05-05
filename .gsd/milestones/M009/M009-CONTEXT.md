# M009: v0.1 Archive, Restore, And Sync Health

**Gathered:** 2026-05-05
**Status:** Phase A and Phase B implemented; closure verification in progress
**Depends on:** Current Mac server data directory, SQLite/Prisma schema, media storage layout, Admin UI, iOS Settings, existing Storage & Diagnostics, sync cursor/outbox/media retry logic, server AI summary diagnostics, and v0.1 release checklist.

## Project Description

M009 closes the project toward a personal v0.1 candidate for long-term self-use.

The product direction after market research is no longer public promotion first. The current priority is making the app trustworthy for the project owner as a private, durable, daily-use archive. Public/open-source polish remains useful later, but it is not the driver for this milestone.

This milestone focuses on two reliability pillars:

- **Archive reliability:** the Mac can create, verify, restore, and promote backups of the full Private Moments archive without relying on raw manual CLI work.
- **Operational clarity:** the iPhone and Mac can explain sync health well enough to tell whether an issue is server reachability, auth, cursor lag, local outbox, media upload, missing media recovery, or AI summary pipeline state.

## Root Decision

v0.1 is scoped to the current self-use architecture:

- iPhone remains the primary capture and browsing surface.
- Mac server remains the authoritative archive source.
- iOS standalone mode, App Store/TestFlight distribution, and public marketing are out of scope for this milestone.
- Mac server and Admin UI should absorb the backup/export/restore workflow so routine long-term use does not depend on remembering raw terminal commands.

## User-Visible Outcome

With Phase A complete, the user can:

- Open Mac Admin and see an `Archive & Export` page.
- Initialize or inspect a backup repository.
- Configure a daily backup schedule and run an immediate backup.
- See backup job progress and history.
- List and check restic snapshots through Admin.
- Restore a snapshot into a new data directory.
- Verify the restored archive before switching runtime configuration.
- Prepare promotion of a verified restore through a strong-confirm flow. Current v0.1 implementation writes restart instructions instead of hot-swapping the live SQLite database in-process.
- See a Sync Health page in Mac Admin and iOS Settings with the same high-level health categories.
- Use safe repair actions such as `Sync Now`, retry uploads, pull server changes, and re-download missing media where appropriate.

With Phase B complete, the user can:

- Create an export package from Mac Admin.
- Choose all data or a date range.
- Treat JSON manifest/metadata as the authoritative migration format.
- Use Markdown only as a human-readable preview.
- Import an export package into a new staged data directory.
- Verify that imported content preserves archive identity before promote/restart.

## Product Boundaries

### In Scope For M009

- Admin-managed backup/restore based on restic-style encrypted, deduplicated snapshots.
- Project-managed restic password/key so the user does not need to remember a backup password.
- Backup repository can be placed in iCloud Drive or a local path, but cloud sync is a user-chosen filesystem location, not an app-managed cloud upload.
- Durable maintenance job tracking in the server database.
- Maintenance mode for restore/promote.
- Admin `Archive & Export` page with `Backups` and `Exports` sections.
- Admin and iOS `Sync Health` surfaces.
- Export/import package designed for migration/recovery, not primarily for reading.

### Out Of Scope For M009

- iOS standalone mode.
- App Store/TestFlight distribution.
- Public marketing, launch page, or user acquisition.
- Cloud provider integrations beyond choosing a filesystem path such as iCloud Drive.
- End-to-end encrypted cloud backup product semantics.
- User-managed backup passwords.
- Multi-user restore/merge semantics.
- Importing an export package into a non-empty existing archive.
- Syncing backup/export settings to iOS.
- One-tap destructive restore that overwrites current data without staging and verification.

## Backup And Restore Decisions

Backup and restore are disaster-recovery features, not human reading features.

Rules:

- Backups are managed by Mac server/Admin UI, with CLI only as a fallback/debug path.
- Backups use restic underneath for deduplicated snapshots and repository integrity checks.
- The user does not manage a backup password. The project automatically creates and stores a fixed restic key next to the backup repository as `.private-moments-restic-key`.
- Admin UI must show the security implication: anyone with both the restic repository and key file can restore it. This is a self-use reliability feature, not a separate encrypted vault against local/iCloud account compromise.
- Backup repository default should be local, while initialization recommends iCloud Drive as an explicit user-selected option.
- Backups should be safe snapshots, not raw zip of a live SQLite/media directory.
- Restore always writes into a new data directory first.
- Restore must be verified before promote.
- Promote requires strong confirmation, creates a pre-promote snapshot of current data, enters maintenance mode, writes restart instructions for switching `PRIVATE_MOMENTS_DATA_DIR` / `DATABASE_URL`, and preserves rollback information. Runtime database replacement is intentionally not performed while Prisma has an open SQLite connection.

## Export And Import Decisions

Export/import is a migration package feature, not the primary disaster-recovery path.

Rules:

- Export is managed by Mac Admin, with CLI only as fallback/debug path.
- Export supports all data and date-range export in v0.1.
- Export's authoritative artifact is JSON manifest/metadata plus media files.
- Markdown output is an optional preview for manual inspection, not the source of truth.
- Export includes comments, AI summaries, titles, tag assignments, archived tags, soft-deleted moments/comments, and all not-yet-permanently-cleaned archive state.
- Export excludes auth tokens, sessions, device tokens, and current runtime device state.
- Import from export is implemented in Phase B.
- Import only targets a new/empty data directory.
- Import preserves original archive identity such as post/comment/media/tag/summary IDs and timestamps where possible.
- Import reinitializes sync/outbox/device state so old device/session/cursor state does not pollute the restored environment.
- Import restores generated metadata and does not re-run AI.

## Sync Health Decisions

Sync Health should explain the current system state rather than clutter the Timeline.

Rules:

- Mac Admin and iOS Settings both show Sync Health.
- The two surfaces use shared categories where possible:
  - server reachable
  - authenticated
  - iPhone cursor vs Mac latest change version
  - pending/failed outbox operations
  - failed media uploads
  - missing downloadable media
  - AI summary pipeline status
  - last successful sync
- Safe repair actions are allowed when they are idempotent and low-risk:
  - sync now
  - retry uploads
  - pull server changes
  - re-download missing media
- Dangerous actions such as reset cursor, clear database, or destructive rebuild are not default v0.1 actions.
- Timeline remains quiet.

## Technical Shape

The server should own a durable maintenance job model:

- `maintenance_jobs` table records job type, status, progress, stage, error code/message, timestamps, artifact paths, and safe metadata.
- Backup, restore, check, export, import, and health refresh jobs should be representable by the same model.
- Maintenance jobs run serially.
- Restore/promote enters maintenance mode and blocks ordinary sync/media/AI writes.
- Normal logs and Admin job details must not include post body, comment body, transcript body, summary body, or raw media content.

## Phase Plan

### Phase A — Backup/Restore + Sync Health

Phase A delivers the immediate self-use stability base:

- Admin-managed backup repository setup.
- Manual backup.
- Daily scheduled backup.
- Restic snapshot list/check.
- Restore to new directory.
- Verify restored directory.
- Strong-confirm promote.
- Durable maintenance jobs.
- Maintenance mode.
- Mac Admin Sync Health.
- iOS Settings Sync Health.

### Phase B — Export/Import

Phase B delivers migration/recovery packages:

- Export all/date-range package.
- Manifest/metadata schema.
- Media copy/verification.
- Markdown preview generation.
- Import into new/empty data directory.
- Import verification.
- Promote imported archive through the same restore/promote safety path.

## Completion Bar

M009 is complete when:

- Admin can run, inspect, check, restore, verify, and prepare promotion of backup snapshots without raw CLI as the normal path.
- Scheduled daily backup can run unattended.
- Backup repository can live in a user-selected local or iCloud Drive path.
- Restore/promote never directly overwrites current data without staging, verification, pre-promote snapshot, maintenance mode, and strong confirmation. The current v0.1 promote step writes `pending-promote.json` restart instructions rather than changing the live database under an open process.
- Admin and iOS Settings can explain sync health using concrete categories and safe next actions.
- Export package format is migration-first and importable into a clean directory.
- Export/import preserves archive identity and generated metadata while excluding auth/session/device runtime state.
- Verification includes server/admin build, migration checks, restic backup/restore smoke, Admin browser or HTTP checks, iOS build, and real-device install/inspection when feasible.
