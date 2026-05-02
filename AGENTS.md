# Agent Notes For Private Moments

## Scope

Work only inside `private-moments-open-source/`. This directory is the sanitized public-release track. Do not modify the owner's private development directory `private-moments/` unless explicitly asked.

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
- `docs/WORKFLOW.md`: project workflow, documentation ownership, verification levels, and closure rules.

## Persistent Workflow

Use `docs/` as the stable human-facing documentation set and public source of truth. The owner's private `.gsd/` execution history is intentionally not part of this public-release snapshot. If a local `.gsd/` workspace is created for planning, keep it untracked.

Human-facing documentation under `docs/` should be primarily Chinese. Keep command names, API routes, field names, filenames, code symbols, and established app UI copy in English where that is clearer or source-of-truth. `AGENTS.md` may stay English-first because it primarily serves agents and tooling.

Work defaults to lightweight continuous maintenance. Upgrade to milestone/slice planning before implementation when a change can affect sync semantics, SQLite schema migrations, media storage or recovery, backup or restore, auth/security boundaries, cross-device behavior, or real-device recovery.

Every non-trivial change must close with:

- A concise change summary.
- Fresh verification evidence from the current session.
- Known issues, limitations, or next steps.
- Updates to affected human-facing docs when usage, operation, architecture, or product behavior changed.

Keep docs single-purpose:

- `docs/PRD.md`: product intent, user stories, goals, and non-goals.
- `docs/TECH-DESIGN.md`: architecture, data flow, system design, and long-lived technical constraints.
- `docs/OPERATOR-RUNBOOK.md`: setup, operation, verification, troubleshooting, and real-device checks.
- `docs/INTEGRATION-GUIDE.md`: API route usage and integration reference.
- `docs/HANDOFF.md`: current working state, recent important fixes, known risks, and next sensible work.
- `docs/DESIGN-PRINCIPLES.md`: UI and product design principles.
- `docs/WORKFLOW.md`: how work is planned, verified, closed, and documented.

## Commands

Install and prepare:

```bash
npm run setup:local
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

Install to a real iPhone after iOS changes:

```bash
PRIVATE_MOMENTS_DEVICE_NAME="Your iPhone" npm run ios:device
```

The real-device script requires `PRIVATE_MOMENTS_DEVICE_NAME`. The bundle id can be overridden with `PRIVATE_MOMENTS_BUNDLE_ID`.

## Runtime Facts

- Development server port: `3210`.
- Default public bundle id: `dev.privatemoments.app`.
- App display name: `Moments`.
- Current schema version: `8`.
- Read the development password from `server/.env`; do not hard-code it into reusable docs or code.
- Get the current Mac Tailscale IP with `tailscale ip -4`.
- iOS Settings server URL may be `http://<mac-tailscale-ip>:3210` or a Tailscale Serve HTTPS URL.

Do not hard-code personal Tailscale values into reusable code unless the user asks for a personal-only shortcut. Prefer script/env overrides.

## Sync And Media Notes

- Sync endpoint: `POST /api/v1/sync`.
- Client operation types currently used: `create_post`, `update_post`, `update_post_favorite`, `delete_post`, `create_comment`, `delete_comment`, `update_media_transcription`.
- `opId` is idempotent per device.
- `lastSyncCursor` must only advance after all returned server changes are applied.
- iOS has recovery logic via `didApplySyncRecoveryV1`; if local posts are empty, it requests cursor `0`.
- iOS must parse ISO8601 with fractional seconds; failing to parse and still advancing cursor caused data loss symptoms on 2026-04-29.
- Comments are independent local-first entities via `create_comment` / `delete_comment`; comment rows do not show per-comment sync badges.
- Media upload is multipart via `POST /api/v1/media/upload`; media `kind` supports `image`, `video`, and `audio`, with `thumbnail` used for video posters.
- iOS compresses display/upload images with max edge `1600px` and JPEG quality `0.72`; upload-time compression also covers old pending files.
- iOS prepares videos as 720p H.264 MP4 with poster thumbnails, records audio as AAC/M4A, and stores audio/video duration metadata.
- New iOS clients do not run Speech framework transcription, request speech permission, upload `transcriptionText`, or show transcript fallback/status in the timeline. `update_media_transcription` remains only for old-client compatibility and historical metadata.
- AI media summaries are generated metadata for uploaded audio/video media. The Mac server runs local `mlx-whisper` transcription first, then sends the transcript to the configured external summary API. iOS calls the Mac server only; external AI provider credentials live in server env vars. Summary changes sync through `ai_summary_updated` and `ai_summary_deleted` server changes, not through client outbox operations.
- New AI summaries use prompt version `media-summary-v2` and a native document block model (`documentTitle`, `oneLiner`, `documentBlocks`) rendered by iOS as Markdown-like headings, paragraphs, lists, and `AI suggested` callouts. Legacy `overview`/`keyPoints`/`sections` remain for compatibility; old summaries are not batch-regenerated.
- AI summary processing statuses are `transcribing`, `summarizing`, `ready`, `failed`, and `deleted`. Timeline only shows `Summary ready` for ready summaries; progress/failure diagnostics belong in Settings > Storage & Diagnostics.
- Normal AI summary logs must not contain private transcript or summary bodies; record IDs, provider/model, status, error codes, and input lengths only.
- Failed sync or media upload work schedules delayed automatic retry: 5s, 20s, 60s, 120s, then 300s.
- Remote media cache recovery uses `POST /api/v1/media/batch-download`, defaulting to `thumbnail` variant as base64 JSON for image thumbnails and video posters. Full audio/video files download on play.
- Server thumbnails are generated with `sips`, max edge `800px`, with oversized thumbnails regenerated.
- `GET /api/v1/admin/status` returns admin counts plus storage, `sync.latestServerChangeVersion`, and `aiSummaries` diagnostics used by Settings > Storage & Diagnostics. iOS hides the Mac Server section if this request fails.
- Server-originated AI summary changes can be ready on Mac while a quiet iPhone has an older `lastSyncCursor`. If summaries look stale, compare iPhone `lastSyncCursor` with server `MAX(server_changes.version)` or admin status `sync.latestServerChangeVersion`; app foreground, Storage & Diagnostics refresh, and Settings > Sync > Sync Now should pull remote-only changes.

## Code Organization

The project has already started splitting large files:

- `TimelineStore` is split across `TimelineStore+Session`, `+Mutations`, `+Sync`, `+SyncRetry`, `+ServerChanges`, `+Media`, legacy `+Transcription`, and `+Payloads`.
- `LocalDatabase` is split across `+Schema`, `+Records`, `+Timeline`, `+Sync`, `+StorageStats`, and `+SQLite`.
- `TimelineView` is split into `TimelineView`, `TimelineRow`, `TimelineCommentsSection`, `TimelineCommentInputBar`, `MomentDateFormatter`, `MediaGalleryView`, and `ZoomableLocalImage`.
- Audio/video support lives in `PreparedMomentMedia`, `MediaPreparation`, `AudioRecorderController`, and `MediaPlaybackCenter`. Server-side AI summary support lives under `server/src/ai/` plus `server/scripts/local-transcribe.py`.
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
SELECT COUNT(*) FROM local_comments WHERE deletedAt IS NULL;
SELECT kind, transcriptionStatus, COUNT(*) FROM local_media WHERE kind IN ('audio', 'video') GROUP BY kind, transcriptionStatus;
```

For image recovery, `missing_visible_media` should be `0`; see `docs/OPERATOR-RUNBOOK.md` for the full query.
