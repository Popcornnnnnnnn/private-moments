# M009: v0.1 Archive, Restore, And Sync Health — Roadmap

## Goal

Deliver a personal v0.1 reliability layer for long-term self-use: safe backups, verifiable restores, operational sync health, and export/import migration packages.

## Slices

### S01 — Maintenance Job And Mode Foundation

**Status:** Implemented in Phase A.

**Goal:** Add the durable server-side foundation needed for backup/restore/export/import jobs.

**Outcome:** Server has a `maintenance_jobs` model, serial job runner, maintenance mode state, and safe job status APIs that Admin can consume.

**Primary requirements:** R039.

**Implementation notes:**

- Add Prisma migration for `maintenance_jobs`.
- Represent backup, restore, check, export, import, promote, and sync-health jobs.
- Store status, progress, stage, safe metadata, artifact path, error code/message, started/finished timestamps.
- Run maintenance jobs serially.
- Add maintenance mode guard that can block sync/media/AI writes during restore/promote.
- Keep private bodies out of logs and job records.

### S02 — Restic Backup, Schedule, Restore, And Promote

**Status:** Implemented in Phase A.

**Goal:** Build Admin-managed backup/restore using restic without making the user manage a password.

**Outcome:** Admin can initialize repository settings, run immediate backups, configure daily backups, list/check snapshots, restore to a new directory, verify, and promote with strong confirmation.

**Primary requirements:** R034, R035, R039.

**Implementation notes:**

- Use restic for deduplicated snapshots.
- Generate/store `.private-moments-restic-key` next to the repository.
- Treat iCloud Drive as a user-selected repository path, not an automatic cloud upload.
- Create backup snapshots from a controlled server snapshot, not a raw live zip.
- Include SQLite, media, generated metadata, and required server configuration needed for recovery.
- Exclude runtime/build dependencies such as `node_modules`, `.venv`, build outputs, and transient temp files.
- Restore into a new directory.
- Verify restored archive before promote.
- Promote only with maintenance mode, pre-promote backup, and strong confirmation.

### S03 — Mac Admin Archive & Export Page

**Status:** Implemented across Phase A and Phase B.

**Goal:** Make backup/restore usable from Mac Admin instead of raw CLI.

**Outcome:** Admin has one `Archive & Export` page with `Backups` and `Exports` sections. Backups cover restic archive operations; Exports cover migration-first package creation and import.

**Primary requirements:** R034, R035, R038, R039.

**Implementation notes:**

- Add route/tab in Admin.
- Show backup repository path, key-file semantics, schedule state, last run, next run, recent jobs, and recent snapshots.
- Allow manual backup, schedule edit, snapshot check, restore, verify, and promote.
- Use strong copy for security semantics: repo + key file can restore; this is not a separate encrypted vault.
- Do not add one-click destructive overwrite.

### S04 — Sync Health In Mac Admin And iOS Settings

**Status:** Implemented in Phase A.

**Goal:** Explain sync failures and stale data with concrete categories and safe repair actions.

**Outcome:** Mac Admin and iOS Settings show comparable Sync Health sections that distinguish reachability, auth, cursor lag, outbox, uploads, missing media, AI summary state, and last success.

**Primary requirements:** R036, R037, R039.

**Implementation notes:**

- Extend Admin status or add a focused sync health endpoint.
- iOS Settings adds a `Sync Health` entry separate from `Storage & Diagnostics`.
- Admin shows server-side and aggregate state.
- iOS shows local phone state and compares against Mac when reachable.
- Safe repair actions may include Sync Now, retry uploads, pull server changes, and re-download missing media.
- No reset cursor/clear database/destructive repair in default v0.1 UI.

### S05 — Export/Import Migration Package

**Status:** Implemented in Phase B.

**Goal:** Deliver migration-first export/import after backup/restore is stable.

**Outcome:** Admin can create all/date-range export packages and import a package into a new/empty data directory, preserving archive identity while reinitializing runtime auth/device/sync state.

**Primary requirements:** R038, R039.

**Implementation notes:**

- JSON manifest/metadata is authoritative.
- Markdown is preview only.
- Include media files, comments, AI summaries/title metadata, tags, archived tags, soft-deleted state, and all non-permanently-cleaned archive state.
- Exclude auth token/session/device runtime state.
- Import only into new/empty data directory.
- Preserve post/comment/media/tag/summary IDs and timestamps where possible.
- Reinitialize sync/outbox/device state.
- Do not re-run AI.
- Reuse restore/promote verification path for imported archives.

### S06 — Verification, Docs, And v0.1 Closure

**Status:** Phase A and Phase B verification in progress.

**Goal:** Prove data recovery paths and document operational use.

**Outcome:** Release checklist, runbook, technical design, integration docs, and handoff reflect the new reliability layer; verification evidence covers backup/restore/sync health/export/import.

**Primary requirements:** R001, R002, R003, R033, R034, R035, R036, R037, R038, R039.

**Implementation notes:**

- Server/admin build after server/admin changes.
- Prisma migration checks.
- Restic availability and repo init checks.
- Backup/create/list/check smoke.
- Restore-to-new-directory and verify smoke.
- Promote dry-run or controlled test data verification.
- Admin UI browser/HTTP checks.
- iOS generic build and real-device install when feasible.
- Human-facing docs stay Chinese and explain the repo + key-file security semantics.

## Completion Bar

- Phase A gives a real disaster-recovery loop: backup, list, check, restore, verify, promote.
- Phase A gives a real diagnostic loop: Mac Admin and iOS Settings can explain why sync is stale or failing.
- Phase B gives a migration loop: export package can be imported into a new archive without relying on raw DB copies.
- No private transcript, summary, post, comment, or media body leaks into normal logs/job records.
- Dangerous actions require strong confirmation and never silently overwrite the current archive.
