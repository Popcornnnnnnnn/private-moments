---
id: T01
parent: S01
milestone: M002
key_files:
  - server/src/api/sync.ts
  - server/prisma/schema.prisma
  - ios/PrivateMoments/Persistence/LocalDatabase+Schema.swift
  - ios/PrivateMoments/Persistence/LocalDatabase+Records.swift
  - ios/PrivateMoments/Persistence/LocalDatabase+Sync.swift
  - ios/PrivateMoments/Persistence/TimelineStore+Payloads.swift
  - ios/PrivateMoments/Persistence/TimelineStore+ServerChanges.swift
  - ios/PrivateMoments/Networking/APIModels.swift
  - shared/openapi.yaml
  - shared/sync-protocol.md
key_decisions:
  - Represent comments as a first-class synced entity with `entityType: "comment"`, not as embedded post payload data.
  - Use separate idempotent operations for `create_comment` and `delete_comment`; avoid comment updates in the first version unless later requested.
  - Keep iOS sync cursor advancement guarded by existing `apply(sync:)` behavior: apply all server changes first, then write `lastSyncCursor` only after success.
duration: 
verification_result: passed
completed_at: 2026-04-29T19:20:12.673Z
blocker_discovered: false
---

# T01: Mapped the server, iOS persistence, payload, and contract seams for adding private comment sync safely.

**Mapped the server, iOS persistence, payload, and contract seams for adding private comment sync safely.**

## What Happened

Mapped the existing local-first sync implementation before editing. Server sync is centralized in `server/src/api/sync.ts`: local changes are parsed, deduplicated by `(deviceId, opId)`, applied in a Prisma transaction, and emitted as `ServerChange` rows. Existing operations are direct branches in `applyOperation`, with payload validation helpers and explicit `OperationRejectedError` reasons. iOS outbox operations are generic JSON payload rows, converted to `SyncLocalChange` in `APIModels.swift`, so comment operation payloads can reuse that path. Local persistence is hand-written SQLite migration and record code; comments should add a `local_comments` table and record helpers rather than expanding `TimelinePost`. Server changes are applied in `TimelineStore+ServerChanges.swift`; existing unknown changes are ignored, but new comment changes should be parsed strictly so malformed comment payloads fail before cursor advancement. `TimelineStore+Sync.swift` already applies accepted/rejected ops and all server changes before writing `AppSettings.lastSyncCursor`, which is the boundary to preserve for comment recovery safety. `refreshPostSyncStatus` currently counts outbox rows by `entityId = postId`, so comment operations with `entityId = commentId` will need either a post-aware status refresh path or a payload/postId join so the parent moment can show pending/failed state accurately.

## Verification

Verified by reading the planned seam files and running a focused repository search for sync/schema/payload touchpoints. No source code was changed.

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `read .gsd/milestones/M002/slices/S01/tasks/T01-PLAN.md; read server/src/api/sync.ts; read ios/PrivateMoments/Persistence/LocalDatabase+Schema.swift; read ios/PrivateMoments/Persistence/LocalDatabase+Records.swift; read ios/PrivateMoments/Persistence/LocalDatabase+Sync.swift; read ios/PrivateMoments/Persistence/TimelineStore+Payloads.swift; read ios/PrivateMoments/Persistence/TimelineStore+ServerChanges.swift; read ios/PrivateMoments/Persistence/TimelineStore+Sync.swift; read ios/PrivateMoments/Networking/APIModels.swift; read shared/openapi.yaml; read server/prisma/schema.prisma` | 0 | ✅ pass | 0ms |
| 2 | `rg -n "SyncRequest|SyncResponse|ServerChange|localChanges|create_post|delete_post|media_uploaded|schemaVersion|SCHEMA_VERSION|insertPost|softDeletePost|refreshPostSyncStatus" shared/openapi.yaml server/src ios/PrivateMoments -g '!PrivateMoments.xcodeproj/**'` | 0 | ✅ pass | 0ms |

## Deviations

None. This task was intentionally read-only and produced an implementation map for S01/T02-T03.

## Known Issues

`shared/openapi.yaml` sync operation enum is already slightly stale relative to implementation: it includes `upsert_media` but current server sync supports post create/update/favorite/delete and media changes are server-originated. S01/T02 should reconcile this while adding comment operation shapes. `.gsd/KNOWLEDGE.md` does not exist yet, so there was no knowledge file to read.

## Files Created/Modified

- `server/src/api/sync.ts`
- `server/prisma/schema.prisma`
- `ios/PrivateMoments/Persistence/LocalDatabase+Schema.swift`
- `ios/PrivateMoments/Persistence/LocalDatabase+Records.swift`
- `ios/PrivateMoments/Persistence/LocalDatabase+Sync.swift`
- `ios/PrivateMoments/Persistence/TimelineStore+Payloads.swift`
- `ios/PrivateMoments/Persistence/TimelineStore+ServerChanges.swift`
- `ios/PrivateMoments/Networking/APIModels.swift`
- `shared/openapi.yaml`
- `shared/sync-protocol.md`
