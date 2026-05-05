# M009 Validation

## Scope

Validation for M009 Phase A and Phase B: Admin-managed backup/restore, daily backup scheduling support, staged restore/promote preparation, durable maintenance jobs, maintenance mode, Mac Admin Sync Health, iOS Settings Sync Health, fresh local setup behavior, and migration-first export/import packages.

## 2026-05-05 Evidence

- `npm run server:typecheck` passed.
- `npm run server:build` passed.
- `npm run admin:build` passed.
- Generic iOS Debug build passed with `xcodegen generate` and `xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`.
- `git diff --check` passed after final documentation updates.
- `npm run server:prisma:generate` passed.
- Existing SQLite deploy path passed with `DATABASE_URL=file:./dev.db npm run server:prisma:deploy`.
- Fresh SQLite setup path passed with `DATABASE_URL="file:./m009-fresh-verify.db" npm run setup:local -- --skip-install --skip-build`; the script created the empty SQLite file, applied all 11 migrations through `20260505120000_maintenance_jobs`, and `SELECT COUNT(*) FROM maintenance_jobs;` returned `0`.
- Isolated Archive smoke passed on compiled server port `3330` using a temporary data directory and temporary restic repository. Verified health, schema version `10`, repository configuration/init, one manual snapshot, restore status `succeeded`, restore verification `ok`, `missingMediaFiles=0`, promote status `succeeded`, and `archive/pending-promote.json` creation.
- Isolated Export/Import smoke passed on compiled server port `3347` using a temporary data directory. Verified login, one post created through `/api/v1/sync`, one image uploaded through `/api/v1/media/upload`, `export_create` job succeeded with a `.tar.gz` package artifact, `import_restore` job succeeded into a staged data directory, imported DB counts showed `posts=1`, `media=1`, `devices=0`, `server_changes=9`, the imported media file existed on disk, and `missingMediaFiles=0`.
- `restic 0.18.0` is available at `/opt/homebrew/bin/restic`.
- Real-device install passed with `npm run ios:device`: iPhoneOS build succeeded, the app installed on `wwz 的 iphone`, and `com.popcornnnnnn.privatemoments` launched. The script reported server URL `http://100.114.41.22:3210`.

## Fixes From Validation

- Fastify global error handling now preserves expected 4xx `statusCode` values instead of wrapping malformed client requests as 500.
- `FileLogger.write` now creates the log directory before append so fresh or restored data directories do not fail when logs are absent.
- `scripts/setup-local.sh` now pre-creates missing SQLite `file:` databases before Prisma deploy. This works around the observed Prisma SQLite behavior where migrate deploy can fail against a missing fresh database file.

## Remaining Closure

- Rerun the final command bundle after any further code or documentation edits: `npm run server:typecheck`, `npm run server:build`, `npm run admin:build`, `git diff --check`, and the export/import smoke if Phase B code changes again.
- Manual UAT should still exercise the Admin `Archive` tab on the normal local server: create a backup, create an export package, import it into a staged directory, and inspect recent jobs.
- Import currently stages a new data directory. Switching runtime to that imported archive remains an explicit promote/restart operation rather than an automatic live database swap.
