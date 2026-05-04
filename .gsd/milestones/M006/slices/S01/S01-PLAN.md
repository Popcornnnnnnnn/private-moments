# S01: Tag Contract, Schema, And Sync Foundation

**Goal:** Implement the durable tag vocabulary, alias, assignment, migration, and sync foundation for Smart Tags.

**Demo:** A tag vocabulary can be seeded, synced, archived/restored, and used to assign primary/topic tags to posts without touching Timeline UI or AI generation yet.

## Must-Haves

- Server has first-class tag vocabulary storage:
  - `tags`
  - `tag_aliases`
  - `post_tags`
- iOS has matching local storage:
  - `local_tags`
  - `local_tag_aliases`
  - `local_post_tags`
- Default primary tags are seeded exactly once:
  - `日记`
  - `想法`
  - `学习整理`
  - `情绪`
  - `碎碎念`
  - `复盘`
- Tags have stable IDs, `type`, canonical name, normalized name, archive state, timestamps, and source fields needed for sync.
- Primary tags and topic tags are distinct vocabulary types.
- Tag names are globally unique across active and archived tags.
- Aliases are case-insensitive and belong to one canonical tag.
- Archived tags are retained and restorable rather than hard-deleted.
- Post tag assignments reference tag IDs, not label strings.
- Post tag assignments record role, source, confidence, optional `aiSummaryId`, timestamps, and soft delete state.
- Post-level metadata can express:
  - `aiTagProcessedAt`
  - `tagsUserEditedAt`
- Sync supports tag vocabulary and post tag assignment changes.
- Topic assignments merge independently.
- Primary assignment is single-select and last-write-wins.
- Applying a tag server change must fail cursor advancement if the parent post/tag cannot be resolved.
- OpenAPI and sync protocol docs describe the new tag entities and changes.

## Requirement Impact

- Owns R022.
- Owns R026.
- Supports R027.

## Threat Surface

- **Data loss:** Cursor advancement must not skip tag changes that cannot be applied.
- **Drift:** Seeded default primary tags must be idempotent and stable across devices/server migrations.
- **Duplicate vocabulary:** Normalized names and aliases must prevent duplicate active/archived labels.
- **Conflict ambiguity:** Topic tags can merge, but primary tag must stay single-select.
- **Privacy:** Tag sync diagnostics must not leak post text, comments, transcripts, or summary bodies.
- **Forward compatibility:** S05 AI tags must be able to use the same vocabulary/assignment model without schema redesign.

## Planned Tasks

### T01 — Server Schema And Seed Migration

- Add Prisma models for tags, aliases, and post tag assignments.
- Add schema version bump through normal migration path.
- Seed the six default primary tags idempotently.
- Enforce enough uniqueness to avoid duplicate canonical names and aliases.
- Preserve archived tags for restore rather than hard delete.

### T02 — iOS Local Schema And Records

- Add local SQLite tables for tags, aliases, and post tag assignments.
- Add migration path without disturbing existing posts/media/comments/summaries.
- Add Swift record models and SQLite mappers.
- Add helpers for default primary tag fetch, assignment fetch, and active/archived vocabulary lookup.

### T03 — Sync Operations And Server Changes

- Add sync operation payloads for tag vocabulary and assignment mutation.
- Add server changes for vocabulary, alias, and post tag assignment updates/deletes.
- Ensure server idempotency for repeated tag operations.
- Ensure iOS apply logic is cursor-safe when a referenced post/tag is missing.
- Keep body-bearing content out of tag diagnostics.

### T04 — Conflict Rules And Recovery Checks

- Implement topic assignment merge behavior.
- Implement primary tag last-write-wins behavior.
- Ensure user-edited/AI-processed post-level tag state survives sync/recovery.
- Add focused tests or SQLite inspection scripts for reinstall-equivalent recovery.

### T05 — Shared Contract Documentation

- Update `shared/openapi.yaml` for any tag APIs/payloads added in S01.
- Update `shared/sync-protocol.md` with tag operation and server-change semantics.
- Update affected `.gsd` docs if implementation changes the planned contract.

## Verification

- `npm run server:prisma:generate`
- `npm run server:build`
- Server migration/sync checks for:
  - default primary seed idempotency
  - create/update/archive/restore tag vocabulary
  - alias uniqueness and case-insensitive matching
  - assign/remove topic tag
  - assign competing primary tags with last-write-wins
  - missing parent post/tag no-cursor-advance behavior
- iOS generic build:
  - `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- Focused iOS persistence tests or SQLite inspection for:
  - local schema migration
  - default primary availability
  - tag/alias/assignment fetch
  - archived tag retention
  - post-level `aiTagProcessedAt` / `tagsUserEditedAt`
- `git diff --check`

## Files Likely Touched

- `server/prisma/schema.prisma`
- `server/prisma/migrations/*/migration.sql`
- `server/src/api/sync.ts`
- `server/src/config/app-config.ts`
- `shared/openapi.yaml`
- `shared/sync-protocol.md`
- `ios/PrivateMoments/Models/TimelinePost.swift`
- `ios/PrivateMoments/Networking/APIModels.swift`
- `ios/PrivateMoments/Persistence/LocalDatabase+Schema.swift`
- `ios/PrivateMoments/Persistence/LocalDatabase+Records.swift`
- `ios/PrivateMoments/Persistence/LocalDatabase+Sync.swift`
- `ios/PrivateMoments/Persistence/LocalDatabase+Timeline.swift`
- `ios/PrivateMoments/Persistence/TimelineStore+Payloads.swift`
- `ios/PrivateMoments/Persistence/TimelineStore+ServerChanges.swift`

## Done Criteria

- Server and iOS can represent tags, aliases, and post assignments without UI-specific shortcuts.
- Default primary tags are available after migration/seed.
- Tag vocabulary and assignments are syncable and recoverable.
- Conflict rules are implemented or explicitly encoded in the sync contract.
- Shared docs reflect the implemented contract.
- S02 can build UI on top of local tag reads/writes without changing schema fundamentals.
