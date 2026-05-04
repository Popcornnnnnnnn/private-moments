# M006: Smart Tags — Roadmap

## Goal

Deliver a synced Smart Tags system that helps the user find and lightly organize moments without turning the timeline into a database. All moment types support manual tags. New audio moments can receive AI primary/topic tags once, after the existing audio summary pipeline produces a ready summary.

## Slices

### S01 — Tag Contract, Schema, And Sync Foundation

**Goal:** Lock the vocabulary, assignment, sync, and conflict model before UI or AI work starts.

**Outcome:** Server and iOS have durable tag vocabulary, aliases, post tag assignments, migrations, and sync semantics for create/update/archive/restore/assignment changes.

**Primary requirements:** R022, R026, R027.

**Implementation notes:**

- Add primary/topic tag vocabulary as first-class data.
- Seed default primary tags: `日记`, `想法`, `学习整理`, `情绪`, `碎碎念`, `复盘`.
- Keep tag vocabulary separate from post tag assignments.
- Add aliases with case-insensitive normalized matching.
- Support archived tags without deleting historical associations.
- Add deterministic conflict behavior: topic tags merge independently; primary tag is last-write-wins.
- Update `shared/openapi.yaml` and `shared/sync-protocol.md`.

### S02 — iOS Manual Tagging And Timeline Metadata

**Goal:** Add the core user-facing tagging affordances while preserving the quiet timeline.

**Outcome:** Composer can optionally choose one primary tag; Timeline can show a primary tag chip; Detail shows full tags read-only; Edit Moment can edit primary/topic tags.

**Primary requirements:** R022, R023, R027.

**Implementation notes:**

- Add a lightweight composer `Tag` control that chooses only one primary tag.
- Do not require a tag to publish.
- Do not expose topic tag editing in Composer.
- Add `Show tags in Timeline` as a display-only setting.
- Timeline metadata row ordering is: primary tag, favorite star, abnormal sync status.
- Remove `synced` from timeline; keep abnormal states visible.
- In tight space, tag display yields before favorite or abnormal sync status.
- Edit Moment marks tags as user-edited so future AI tag application is blocked for that moment.

### S03 — Local Search And Filter Integration

**Goal:** Make tags useful for retrieval without adding a new archive surface.

**Outcome:** Existing Timeline search/filter can match primary tags, topic tags, and aliases; filters separate primary tags and topics and compose with existing filters.

**Primary requirements:** R025, R027.

**Implementation notes:**

- Add `tag` as a search match source.
- Keep first-version search/filter local to iPhone.
- Keep tags inside the existing Filter menu.
- Show primary tags and topic tags in separate sections.
- Topic section should show popular/recent topics plus search across active topics.
- Multiple selected filters use AND semantics.
- Archived tags do not participate in ordinary search/filter.

### S04 — Settings Tag Management

**Goal:** Give the user enough vocabulary maintenance tools to keep dynamic topic tags clean.

**Outcome:** Settings can list tags with usage counts, customize primary colors, manage custom primary tags, and rename/merge/archive/restore topic tags.

**Primary requirements:** R022, R025, R027.

**Implementation notes:**

- Add `Settings > Tags`.
- Default primary tags are fixed: no rename/hide.
- Custom primary tags may be created through a deep path, renamed, hidden/archived, and color-customized.
- Topic tags can be renamed, merged into canonical tags, archived, and restored.
- Merging topic tags preserves the old name as an alias.
- Archived tags are visible in Settings and Edit Moment, not normal Timeline/Detail/Filter/Search.
- Mac Admin may show diagnostics later, but does not manage tags in this version.

### S05 — Audio AI Tag Generation

**Goal:** Extend the existing audio summary pipeline so new audio moments can receive trusted AI tags without a separate confirmation flow.

**Outcome:** First ready summary for a new audio moment can apply one primary tag and up to three topic tags, following user-intent and confidence rules.

**Primary requirements:** R023, R024, R026, R027.

**Implementation notes:**

- AI tagging is first-version audio-only.
- Video, image, and text-only moments do not receive AI tags.
- No historical audio backfill.
- No automatic tagging when opening old summaries.
- No `Regenerate tags` action in the first version.
- If the user selected a primary tag in Composer, AI may add topics but cannot change that primary tag.
- If the user later edits tags in Edit Moment, future AI tags are not auto-applied.
- AI must prefer existing topics/aliases before creating new topics.
- Apply at most three topic tags and fewer when confidence is low.
- Low-confidence primary tag should be left empty rather than forced to `碎碎念`.
- Store source/confidence metadata and privacy-safe diagnostics only.

### S06 — Verification, Documentation, And Real iPhone UAT

**Goal:** Prove the feature works across schema, sync, AI, UI, search/filter, and real-device async behavior.

**Outcome:** Builds/tests pass, shared contracts and docs are updated, and paired iPhone UAT verifies the new audio AI tag path plus manual tag retrieval flows.

**Primary requirements:** R001, R002, R003, R022, R023, R024, R025, R026, R027.

**Implementation notes:**

- Add focused migration and sync recovery checks.
- Add local search/filter tests for tag and alias matching.
- Add AI tag output validation tests for confidence, max topics, and user-edited lockout.
- Run server typecheck/build and admin build after server/admin changes.
- Run iOS build and focused tests after iOS changes.
- Install to real iPhone and verify new audio publish -> upload -> summary ready -> AI tags sync -> timeline chip/filter/search/edit.
- Inspect logs and diagnostics for no transcript/summary body leakage.

## Completion Bar

- Default primary tags exist and are seeded safely.
- Manual tags work for all moment types.
- New audio moments can receive AI tags only through first ready summary generation.
- Timeline shows optional primary tags and no longer shows `synced`.
- Filter and search can retrieve by primary tags, topic tags, and aliases.
- Settings can manage tag vocabulary without turning Admin into a content surface.
- Tag vocabulary and assignments sync and recover.
- Conflict handling is deterministic.
- Shared OpenAPI and sync protocol docs describe tag semantics.
- Real iPhone UAT proves the core end-to-end audio AI tag path.
- Known limitations are recorded: no historical backfill, no video/image/text AI tags, no regenerate-tags action, no server/Admin tag search in first version.
