---
estimated_steps: 1
estimated_files: 5
skills_used: []
---

# T02: Add server comment schema and sync operations

Add server-side comment persistence and sync support: Prisma model/migration, create/delete comment operation validation/application, server change payloads, and shared OpenAPI/sync protocol updates.

## Inputs

- `T01 implementation map`
- `server/src/api/sync.ts`
- `server/src/api/http-errors.ts`

## Expected Output

- `Prisma comment model and migration`
- `Sync handler support for comment operations`
- `Updated shared API/sync docs`
- `Server verification output`

## Verification

npm run server:prisma:generate && npm run server:build && scripted sync/API check or focused server test for idempotent create/delete comments.

## Observability Impact

Include operation type and entity id in non-secret sync rejection/error context where existing patterns allow.
