# Private Moments Handoff

Last reconciled: 2026-04-29

## Current Working State

- Mac server builds and runs with Fastify, Prisma, SQLite, file storage, auth, sync, media upload, media download, admin routes, and static Admin UI hosting.
- iOS app builds as `Moments` and installs on the paired iPhone with `npm run ios:device`.
- Admin UI builds with `npm run admin:build` and is served at `/admin/`.
- Project workflow is now documented in `docs/WORKFLOW.md` and enforced for agents through `AGENTS.md`.
- `.gsd/` is the structured source for current project facts, requirements, decisions, and milestone state; `docs/` remains the stable human-facing documentation set.
- Real iPhone verification on 2026-04-29 showed:
  - `local_posts`: 8
  - visible local posts: 5
  - downloaded media cache entries: 9
  - missing visible media: 0

## Implemented Product Surface

- Local-first iOS timeline.
- Text-only, image-only, and text + image posts; empty posts are rejected.
- Photo library and camera import.
- Manual occurred date/time.
- Local composer drafts.
- Offline outbox sync.
- Delayed automatic retry for failed pending sync work.
- Post detail view.
- Full-screen image gallery with native-feeling pan and zoom.
- Edit text, occurred time, images, and image ordering.
- Favorite/unfavorite moments.
- Search, filters, and month jump.
- English human-friendly timeline dates and a temporary floating month indicator while scrolling.
- Soft delete with centered confirmation on the timeline.
- Settings with simplified connection, sync, advanced sync, and storage diagnostics pages.
- Mac Admin Overview and Posts management.
- Device binding via `deviceKey` to avoid duplicate physical-device registrations.

## Important Fixes From 2026-04-29

- iOS now parses server ISO8601 timestamps with fractional seconds, so server changes like `2026-04-29T06:40:42.000Z` no longer get skipped.
- iOS includes one-time cursor recovery (`didApplySyncRecoveryV1`) and resets cursor to `0` when the local post table is empty.
- Server exposes `POST /api/v1/media/batch-download`.
- iOS uses batch thumbnail JSON for remote media cache recovery because repeated binary media downloads over Tailscale/iOS were unreliable in testing.
- iOS compresses images before storing/uploading display copies, and upload-time compression also helps old pending images. Current policy is max edge `1600px` with JPEG quality `0.72`.
- Failed pending sync or media upload work schedules delayed retry with backoff: 5s, 20s, 60s, 120s, then 300s.
- iOS Settings includes a read-only Storage page showing local iPhone storage, sync health, and Mac server storage when `/api/v1/admin/status` is reachable.
- Server `/api/v1/admin/status` includes storage diagnostics for the data directory, SQLite files, media files, logs, and available disk.
- Server generates 800px thumbnail variants on demand and regenerates oversized thumbnail files.
- Timeline delete confirmation now uses a centered alert instead of a position-based confirmation dialog; trailing swipe delete disables full-swipe and waits briefly before showing the alert to avoid row/list jumps.
- Timeline dates now use English human-friendly labels through `MomentDateFormatter`; month context appears as a temporary floating scroll hint instead of a persistent section header.
- The iOS main implementation was split:
  - `TimelineStore.swift` into session, mutation, sync, server-change, media, and payload files.
  - `TimelineStore.swift` retry behavior into `TimelineStore+SyncRetry.swift`.
  - `LocalDatabase.swift` into schema, records, timeline, sync, storage stats, and SQLite helper files.
  - `TimelineView.swift` into timeline, row/image, date formatting, gallery, and zoomable image components.
  - Storage diagnostics into `StorageStats.swift`, `StorageSettingsView.swift`, and `server/src/storage/stats.ts`.

## Known Large Files

These files are still worth splitting when they become active edit targets:

- `admin/src/App.tsx`
- `server/src/api/admin.ts`
- `server/src/api/sync.ts`
- `server/src/api/media.ts`
- `ios/PrivateMoments/Views/MomentDetailView.swift`

## Next Sensible Work

- Use `docs/WORKFLOW.md` to choose quick track vs milestone track before starting new work.
- Continue feature work without adding visible clutter to the main timeline.
- Split Admin UI into smaller React components before expanding Posts management.
- Split server API handlers when adding new admin/sync/media behavior.
- Add focused regression tests around sync cursor recovery, media batch download, automatic retry, storage diagnostics, and duplicate device binding.
- Add backup/export after core feature polish; backup is intentionally not the next blocking item.
