---
id: T02
parent: S01
milestone: M002
key_files:
  - server/prisma/schema.prisma
  - server/prisma/migrations/20260430190000_private_comments/migration.sql
  - server/src/api/sync.ts
  - server/src/config/app-config.ts
  - shared/openapi.yaml
  - shared/sync-protocol.md
key_decisions:
  - Added comments as first-class server entities in a new `comments` table with soft-delete and `serverVersion`.
  - Added `create_comment` and `delete_comment` as local sync operations for `entityType: "comment"`.
  - Emitted `comment_created` and `comment_deleted` server changes with `postId` included so iOS can apply changes and refresh the parent moment without needing a prior comment lookup.
  - Bumped `SCHEMA_VERSION` from 3 to 4 because server archive schema changed.
duration: 
verification_result: passed
completed_at: 2026-04-29T19:23:08.698Z
blocker_discovered: false
---

# T02: Added server-side private comment schema, sync operations, shared contract docs, and smoke-tested idempotent create/delete comment sync.

**Added server-side private comment schema, sync operations, shared contract docs, and smoke-tested idempotent create/delete comment sync.**

## What Happened

Implemented the server-side private comment sync contract. Prisma now has a `Comment` model mapped to `comments`, related to `Post` and optionally to creating/updating devices, with indexes on `postId`, `deletedAt`, and `serverVersion`. A hand-written migration creates the table and indexes. The sync handler now routes `create_comment` and `delete_comment` for `entityType: "comment"`. `create_comment` validates `postId`, non-empty text, and a live parent post before creating the comment and emitting `comment_created`. `delete_comment` validates the comment and its parent post, soft-deletes the comment, and emits `comment_deleted`. Both changes update the comment `serverVersion`. Shared sync protocol docs now describe private comment payloads and server changes, and OpenAPI sync operation enums include comment operations while removing the misleading current `upsert_media` local operation enum entry. Server schema version is now 4.

## Verification

Ran Prisma client generation, TypeScript server build, whitespace diff check, and an in-process Fastify sync smoke test against a temporary SQLite database. The smoke test logged in a test device, synced a post plus comment creation, replayed the same comment op idempotently, and synced comment deletion.

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `git diff --check` | 0 | ✅ pass | 0ms |
| 2 | `npm run server:prisma:generate && npm run server:build` | 0 | ✅ pass — Prisma Client generated; `tsc -p tsconfig.json` completed. | 7600ms |
| 3 | `tmpdir=$(mktemp -d); DATABASE_URL=file:$tmpdir/app.sqlite PRIVATE_MOMENTS_DATA_DIR=$tmpdir/data npx prisma migrate deploy --schema server/prisma/schema.prisma && npx tsx <comment-sync-smoke-test>` | 0 | ✅ pass — comment sync smoke test passed; acceptedCreateOps=2, replayAcceptedOps=1, deleteAcceptedOps=1, finalCursor=3. | 3200ms |

## Deviations

None. The task stayed within server/shared contract scope; iOS local plumbing is intentionally deferred to T03.

## Known Issues

No blocker. iOS does not yet understand or apply `comment_created` / `comment_deleted`; that is the planned scope of S01/T03. OpenAPI still keeps sync payloads broadly typed with `additionalProperties` instead of full discriminated operation schemas; it now documents comment payload semantics inline, but a future contract cleanup could make each operation payload explicit.

## Files Created/Modified

- `server/prisma/schema.prisma`
- `server/prisma/migrations/20260430190000_private_comments/migration.sql`
- `server/src/api/sync.ts`
- `server/src/config/app-config.ts`
- `shared/openapi.yaml`
- `shared/sync-protocol.md`
