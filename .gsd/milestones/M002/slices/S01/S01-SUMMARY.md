---
id: S01
parent: M002
milestone: M002
provides:
  - Server-side comment persistence and idempotent create/delete sync operations.
  - Shared OpenAPI/sync protocol documentation for comment operations and server changes.
  - iOS local comment persistence, outbox payloads, and server-change application ready for UI consumption.
requires:
  []
affects:
  []
key_files:
  - server/src/api/sync.ts
  - server/prisma/schema.prisma
  - server/prisma/migrations/20260430190000_private_comments/migration.sql
  - shared/openapi.yaml
  - shared/sync-protocol.md
  - ios/PrivateMoments/Models/TimelinePost.swift
  - ios/PrivateMoments/Persistence/LocalDatabase+Schema.swift
  - ios/PrivateMoments/Persistence/LocalDatabase+Records.swift
  - ios/PrivateMoments/Persistence/LocalDatabase+Sync.swift
  - ios/PrivateMoments/Persistence/TimelineStore+Payloads.swift
  - ios/PrivateMoments/Persistence/TimelineStore+ServerChanges.swift
  - docs/TECH-DESIGN.md
  - docs/INTEGRATION-GUIDE.md
  - .gsd/REQUIREMENTS.md
key_decisions:
  - Represent comments as a first-class synced entity with `entityType: "comment"`, not embedded post payload data.
  - Use separate idempotent operations for `create_comment` and `delete_comment`; do not add comment updates in the first contract slice.
  - Include parent `postId` in iOS comment payloads so comment outbox status can refresh the parent moment.
  - Keep comment diagnostics operation/change-type focused and avoid logging private comment text.
patterns_established:
  - Private comments are first-class synced entities, not embedded post payloads.
  - Comment outbox operations carry parent `postId` in payload for local post-status propagation even when `entityId` is the comment id.
observability_surfaces:
  - Server operation rejections preserve operation type context such as `create_comment.payload.text is required`.
  - iOS invalid server-change errors name `comment_created`/`comment_deleted` and invalid fields without interpolating private comment text.
  - Outbox `lastError` continues to persist rejected-operation reasons for sync diagnostics.
drill_down_paths:
  - .gsd/milestones/M002/slices/S01/tasks/T01-SUMMARY.md
  - .gsd/milestones/M002/slices/S01/tasks/T02-SUMMARY.md
  - .gsd/milestones/M002/slices/S01/tasks/T03-SUMMARY.md
  - .gsd/milestones/M002/slices/S01/tasks/T04-SUMMARY.md
duration: ""
verification_result: passed
completed_at: 2026-04-29T19:41:40.467Z
blocker_discovered: false
---

# S01: Comment data model and sync contract

**Established the private comment data model and idempotent sync contract across server, shared docs, and iOS local persistence.**

## What Happened

S01 introduced the durable private comment data model and sync contract across server, shared API docs, and iOS local persistence without changing visible UI. The server now persists comments as first-class soft-deleted entities, accepts idempotent `create_comment` and `delete_comment` operations, and emits `comment_created`/`comment_deleted` server changes. The shared sync protocol/OpenAPI contract documents those operation shapes. iOS now has a `local_comments` table, `TimelineComment`, payload builders, outbox plumbing, server-change apply logic, and focused payload tests. Human-facing docs and R009 were updated to reflect that the contract layer is validated while UI/UAT remains for later slices.

## Verification

Verified server build, server scripted sync smoke test in T02, iOS generic build, iOS payload tests, docs sync, and R009 requirement validation. Final S01 verification command passed: `npm run server:build && cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`.

## Requirements Advanced

- R008 — S01 supplies the persistence/sync foundation needed by the S02 detail-view UI.
- R010 — S01 keeps comments plain text and single-level at the data/contract layer; no Markdown, replies, social metadata, or public identity fields were added.

## Requirements Validated

- R009 — Server schema/migration and sync smoke test validated idempotent create/delete comment operations and server changes; iOS build/tests validated local comment schema, payloads, and server-change apply plumbing with cursor advancement still gated by successful local apply.

## New Requirements Surfaced

None.

## Requirements Invalidated or Re-scoped

None.

## Operational Readiness

None.

## Deviations

None.

## Known Limitations

No visible iOS comment UI yet. iOS comment local plumbing is compile/test covered, but a full real-device create/delete comment UAT waits for S02 UI. Comment update/edit was intentionally out of scope for S01.

## Follow-ups

Build S02 visible iOS detail-view comment UI, then run real-device comment create/delete UAT. S03 should verify cross-device/reinstall convergence after UI exists.

## Files Created/Modified

- `server/prisma/schema.prisma` — Added private comment server model.
- `server/prisma/migrations/20260430190000_private_comments/migration.sql` — Added SQLite comments table migration.
- `server/src/api/sync.ts` — Added create/delete comment sync operations and comment server changes.
- `shared/openapi.yaml` — Documented comment sync operation/server-change shapes.
- `shared/sync-protocol.md` — Documented private comment sync semantics.
- `ios/PrivateMoments/Models/TimelinePost.swift` — Added TimelineComment and comment collection on TimelineItem.
- `ios/PrivateMoments/Persistence/LocalDatabase+Schema.swift` — Added local_comments table and indexes.
- `ios/PrivateMoments/Persistence/LocalDatabase+Records.swift` — Added comment record fetch/insert helpers and parent post sync-status mapping.
- `ios/PrivateMoments/Persistence/LocalDatabase+Sync.swift` — Added comment server-change apply helpers and comment outbox status propagation.
- `ios/PrivateMoments/Persistence/LocalDatabase+Timeline.swift` — Loaded comments with timeline items and added local create/delete transactions.
- `ios/PrivateMoments/Persistence/TimelineStore+Payloads.swift` — Added create/delete comment payload builders.
- `ios/PrivateMoments/Persistence/TimelineStore+ServerChanges.swift` — Parsed comment_created/comment_deleted server changes with content-safe error messages.
- `ios/PrivateMoments/Persistence/TimelineStore+Mutations.swift` — Added non-UI create/delete comment store methods for future UI.
- `ios/PrivateMomentsTests/CommentSyncPayloadTests.swift` — Added focused payload tests for comment sync operations.
- `docs/TECH-DESIGN.md` — Recorded private comment contract-layer architecture.
- `docs/INTEGRATION-GUIDE.md` — Recorded comment sync operation examples and behavior.
- `.gsd/REQUIREMENTS.md` — Marked R009 validated for the S01 sync-contract layer.
