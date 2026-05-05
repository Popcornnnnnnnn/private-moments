# S02: Restic Backup, Schedule, Restore, And Promote

**Goal:** Build the Admin-managed backup and restore loop on top of S01's maintenance job foundation.

**Demo:** From Mac Admin, the user can initialize a restic repository, run an immediate backup, see snapshots, schedule daily backup, restore a snapshot to a new directory, verify it, and promote it through strong confirmation.

## Must-Haves

- Detect whether `restic` is installed and report actionable setup instructions if missing.
- Initialize backup repository from Admin.
- Generate `.private-moments-restic-key` next to the repository path.
- Show clear UI copy: repo + key can restore; this is self-use recovery, not a separate encrypted vault against anyone who has both files.
- Support repository path selection/config by explicit user input, including iCloud Drive paths.
- Create controlled snapshots of current data rather than raw live zip.
- Exclude runtime dependencies and transient build/temp files.
- Run immediate backup.
- Configure daily fixed-time backup plus manual immediate backup.
- List snapshots.
- Run repository check.
- Restore selected snapshot into a new data directory.
- Verify restored archive.
- Promote verified restore with:
  - strong confirmation phrase
  - maintenance mode
  - pre-promote backup
  - `pending-promote.json` restart instructions for switching `PRIVATE_MOMENTS_DATA_DIR` and `DATABASE_URL`
  - rollback-aware pre-promote snapshot

## Requirement Impact

- Owns R034, R035.
- Supports R039.

## Threat Surface

- **Irrecoverable archive:** backup must include all durable content and enough configuration to restart on another Mac.
- **Self-lockout:** the user must not need to remember a password.
- **Accidental cloud assumption:** iCloud Drive is a user-selected folder, not app-managed cloud upload.
- **Partial restore:** restored directories must be verified before promote.
- **Destructive promote:** current data must be snapshotted before switching.
- **Path injection:** repository/data directory paths must be normalized and constrained enough for a local single-user admin tool.

## Planned Tasks

### T01 — Restic Service

- Add server-side restic wrapper.
- Detect binary and version.
- Generate/read repository key file.
- Initialize repository.
- Run backup/list/check/restore commands through maintenance jobs.

### T02 — Snapshot Source

- Build controlled snapshot source directory.
- Checkpoint/copy SQLite safely.
- Copy durable media/config metadata.
- Exclude dependencies, build outputs, temp files, and transient logs if not needed for recovery.
- Write backup manifest with app/schema/server version and source paths.

### T03 — Schedule

- Store backup schedule settings.
- Implement daily fixed-time trigger inside server process or launchd-backed helper, choosing the simpler robust path during implementation.
- Record next run and last run.
- Prevent schedule-triggered backup when another maintenance job is running.

### T04 — Restore And Verify

- Restore selected snapshot into a new directory.
- Verify database opens, schema version is supported, required directories exist, and media manifest references resolve.
- Mark restore job with candidate directory and verification result.

### T05 — Promote

- Require strong confirmation phrase.
- Enter maintenance mode.
- Run pre-promote backup.
- Write restart instructions instead of hot-swapping the active SQLite database while Prisma has an open connection.
- Preserve rollback information.

### T06 — Admin UI

- Add Backups section to `Archive & Export`.
- Show repo state, key semantics, schedule, snapshots, jobs, and restore candidates.
- Wire buttons for initialize, backup now, list/check, restore, verify, promote.

## Verification

- `npm run server:build`
- `npm run admin:build`
- Local restic repo init in a temp path.
- Backup current dev data.
- List/check snapshots.
- Restore snapshot to a temp/new data directory.
- Verify restored database/media manifest.
- Promote flow tested against a controlled temporary data directory where possible, not destructive production data.
- `git diff --check`

## Done Criteria

- Admin is the normal path for backup/restore.
- CLI/restic details remain transparent enough for debugging but are not required for routine use.
- Backup repository can live in a user-selected local or iCloud Drive path.
- User does not need to remember a restic password.
- Restore/promote is staged, verified, strongly confirmed, and rollback-aware.
