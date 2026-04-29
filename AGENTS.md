# Agent Notes For Private Moments

## Scope

Work only inside `private-moments/`. The user explicitly asked not to work directly in the parent `07-github` root.

## Product Shape

Private Moments is a private, local-first personal timeline:

- iOS app is the primary capture and browsing surface.
- Mac runs the self-hosted server, SQLite archive, media storage, sync API, and Admin UI.
- Tailscale or a private VPN is the intended network boundary.
- Main timeline simplicity is a design constraint. Put low-frequency controls in toolbar menus, swipe actions, detail views, or settings rather than crowding the timeline.
- App-facing UI copy should stay primarily English unless the user explicitly requests localization.
- Timeline date/month context should stay light: use `MomentDateFormatter` for English human-friendly labels and a temporary floating month hint while scrolling.
- Timeline delete should use a centered alert, not a position-based `confirmationDialog`; keep trailing delete full-swipe disabled to avoid list jumps.

## Current Architecture

- `ios/PrivateMoments`: SwiftUI app named `Moments`.
- `server`: Node.js, TypeScript, Fastify, Prisma, SQLite, local file storage.
- `admin`: React + Vite Admin UI served by Fastify after build.
- `shared/openapi.yaml`: API contract.
- `shared/sync-protocol.md`: sync semantics.
- `docs/INTEGRATION-GUIDE.md`: API usage and route reference.
- `docs/OPERATOR-RUNBOOK.md`: setup, operations, iPhone install, troubleshooting.
- `docs/HANDOFF.md`: current working state and follow-up notes.

## Commands

Install and prepare:

```bash
npm install
cp server/.env.example server/.env
npm run server:prisma:generate
npm run server:prisma:migrate
npm run admin:build
```

Run server:

```bash
npm run server:dev
```

Build checks:

```bash
npm run server:typecheck
npm run admin:build
cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Install to real iPhone after iOS changes:

```bash
npm run ios:device
```

The paired phone is commonly named `wwz 的 iphone`; the real-device script can be overridden with `PRIVATE_MOMENTS_DEVICE_NAME`.

## Runtime Facts

- Development server port: `3210`.
- Bundle id: `com.popcornnnnnn.privatemoments`.
- App display name: `Moments`.
- Current schema version: `3`.
- Read the development password from `server/.env`; do not hard-code it into reusable docs or code.
- Get the current Mac Tailscale IP with `tailscale ip -4`.
- iOS Settings server URL may be `http://<mac-tailscale-ip>:3210` or a Tailscale Serve HTTPS URL.

Do not hard-code personal Tailscale values into reusable code unless the user asks for a personal-only shortcut. Prefer script/env overrides.

## Sync And Media Notes

- Sync endpoint: `POST /api/v1/sync`.
- Client operation types currently used: `create_post`, `update_post`, `update_post_favorite`, `delete_post`.
- `opId` is idempotent per device.
- `lastSyncCursor` must only advance after all returned server changes are applied.
- iOS has recovery logic via `didApplySyncRecoveryV1`; if local posts are empty, it requests cursor `0`.
- iOS must parse ISO8601 with fractional seconds; failing to parse and still advancing cursor caused data loss symptoms on 2026-04-29.
- Media upload is multipart via `POST /api/v1/media/upload`.
- iOS compresses display/upload images with max edge `1600px` and JPEG quality `0.72`; upload-time compression also covers old pending files.
- Failed sync or media upload work schedules delayed automatic retry: 5s, 20s, 60s, 120s, then 300s.
- Remote media cache recovery uses `POST /api/v1/media/batch-download`, defaulting to `thumbnail` variant as base64 JSON.
- Server thumbnails are generated with `sips`, max edge `800px`, with oversized thumbnails regenerated.
- `GET /api/v1/admin/status` returns admin counts plus storage diagnostics used by Settings > Storage. iOS hides the Mac Server section if this request fails.

## Code Organization

The project has already started splitting large files:

- `TimelineStore` is split across `TimelineStore+Session`, `+Mutations`, `+Sync`, `+SyncRetry`, `+ServerChanges`, `+Media`, and `+Payloads`.
- `LocalDatabase` is split across `+Schema`, `+Records`, `+Timeline`, `+Sync`, `+StorageStats`, and `+SQLite`.
- `TimelineView` is split into `TimelineView`, `TimelineRow`, `MomentDateFormatter`, `MediaGalleryView`, and `ZoomableLocalImage`.
- Storage diagnostics live in `ios/PrivateMoments/Models/StorageStats.swift`, `ios/PrivateMoments/Views/StorageSettingsView.swift`, and `server/src/storage/stats.ts`.

Before expanding large areas, prefer continuing these splits:

- `admin/src/App.tsx`
- `server/src/api/admin.ts`
- `server/src/api/sync.ts`
- `server/src/api/media.ts`
- `ios/PrivateMoments/Views/MomentDetailView.swift`

## Verification Habit

After server changes:

```bash
npm run server:build
curl -fsS http://127.0.0.1:3210/api/v1/health
```

After iOS changes, rebuild and install to the real iPhone when feasible:

```bash
npm run ios:device
```

For real-device data verification, copy the app Library container with `xcrun devicectl` and inspect:

```sql
SELECT COUNT(*) FROM local_posts;
SELECT COUNT(*) FROM local_posts WHERE deletedAt IS NULL;
SELECT COUNT(*) FROM local_media WHERE localCompressedPath <> '';
```

For image recovery, `missing_visible_media` should be `0`; see `docs/OPERATOR-RUNBOOK.md` for the full query.
