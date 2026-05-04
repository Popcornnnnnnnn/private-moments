# S02: Comment Data And Sync

**Goal:** Implement independent local-first comment entities and sync semantics.
**Demo:** A comment can be created and deleted through local operations, synced through the Mac server, replayed idempotently, and restored through server changes without cursor loss.

## Must-Haves

- Server `comments` table with parent `posts` relation, soft delete, server version, and device-source fields useful for debugging.
- Server accepts `create_comment` and `delete_comment` through `POST /api/v1/sync`.
- Server rejects missing/deleted parent posts for `create_comment`.
- Server emits `comment_created` and `comment_deleted` for direct comment operations.
- Server does not emit per-comment delete changes when a parent post is deleted; `post_deleted` is enough.
- iOS has `local_comments` with soft delete and parent `postId`.
- iOS queues `create_comment` and `delete_comment`; deleting an unsynced newly created comment short-circuits the pending create when possible.
- iOS ensures unsynced parent post create happens before comment create.
- iOS applies recognized comment server changes strictly; missing parent means fail and do not advance `lastSyncCursor`.
- Comment operations contribute to global outbox/sync diagnostics without exposing comment bodies.

## Requirement Impact

- Owns R009.
- Supports R012.

## Threat Surface

- Data loss risk: cursor advancement must not skip failed comment apply.
- Ordering risk: comments for unsynced parent moments must not reach the server before the parent exists.
- Privacy risk: diagnostics must not print or display comment body text.

## Verification

- `npm run server:prisma:generate`
- `npm run server:build`
- Server sync smoke coverage for create, replay, delete, rejected missing/deleted parent, and parent delete cascade behavior.
- `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- Focused iOS persistence/payload/server-change tests or SQLite inspection proving local comments, cursor-safe apply, and short-circuit delete.

## Files Likely Touched

- `server/prisma/schema.prisma`
- `server/prisma/migrations/*/migration.sql`
- `server/src/api/sync.ts`
- `server/src/config/app-config.ts`
- `shared/openapi.yaml`
- `shared/sync-protocol.md`
- `ios/PrivateMoments/Models/TimelinePost.swift`
- `ios/PrivateMoments/Persistence/LocalDatabase+Schema.swift`
- `ios/PrivateMoments/Persistence/LocalDatabase+Records.swift`
- `ios/PrivateMoments/Persistence/LocalDatabase+Sync.swift`
- `ios/PrivateMoments/Persistence/LocalDatabase+Timeline.swift`
- `ios/PrivateMoments/Persistence/TimelineStore+Mutations.swift`
- `ios/PrivateMoments/Persistence/TimelineStore+Payloads.swift`
- `ios/PrivateMoments/Persistence/TimelineStore+ServerChanges.swift`
