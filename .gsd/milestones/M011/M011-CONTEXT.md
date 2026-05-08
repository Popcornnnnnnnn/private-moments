# M011: Pinned Moments

**Gathered:** 2026-05-08
**Status:** Design checkpoint; implementation not started
**Worktree:** `/Users/popcornnnnnn/.codex/worktrees/private-moments-pinned`
**Branch:** `codex/pinned-moments-design`
**Depends on:** Timeline, Detail, local SQLite schema, server Prisma schema, sync operations, Calendar/Day Review, tags/search/filter, and worktree/data-safety requirement R048.

## Project Description

M011 adds a small pinned-moments surface for moments the user wants to keep immediately reachable. It must behave like a quiet shortcut shelf, not a second timeline, task board, archive dashboard, or content-management mode.

Pinned moments appear above the normal chronological Timeline only when Timeline has no active search/filter state. The pinned area defaults to a single collapsed summary header such as `Pinned · 3`; pinned title rows are revealed only after the user opens the header. The original moments remain in their normal chronological positions so Calendar, Day Review, search, filters, review inputs, counts, and lived-time browsing stay truthful.

## Root Decision

Pinned moments are an access layer over existing moments:

- Pinning does not change `occurredAt`.
- Pinning does not remove the moment from the normal Timeline.
- Pinning does not create a new post, comment, tag, review, or AI artifact.
- Pinning is synced metadata on `Post`, similar in weight to favorite but with a stronger layout effect.
- The pinned Timeline surface defaults to a collapsed summary header and never shows body/media/comment previews.

## User-Visible Outcome

The user can:

- Pin several moments from low-frequency controls.
- See a compact `Pinned` section at the top of Timeline when at least one visible moment is pinned.
- Keep the pinned section collapsed by default, showing only a `Pinned · N` summary header.
- Tap the header to show up to three title rows when there are one to three pinned moments.
- Tap the header to open a bottom sheet list when there are more than three pinned moments.
- Tap a pinned title to open that moment detail; sheet entries open detail inside the sheet navigation stack.
- Unpin from the same low-frequency surfaces used to pin, plus pinned sheet row context menus.

## Product Boundaries

### In Scope

- `isPinned` and `pinnedAt` metadata on posts.
- `update_post_pin` local operation and `post_pin_updated` server change.
- iOS local migration and Timeline model support.
- Pinned compact section above Timeline.
- Default collapsed summary header above Timeline, with expanded/collapsed state persisted locally as a device UI preference for the one-to-three pinned case.
- Title derivation from existing moment content, without adding a second editable title field.
- Pin/unpin from Moment Detail `More` menu, Timeline long-press/context controls, and pinned sheet row context controls.
- Search/filter behavior that hides the pinned surface whenever Timeline has any active search/filter state.
- Bottom sheet list for more than three pinned moments.

### Out Of Scope

- Manual drag reordering of pinned moments.
- Separate pin title editing.
- Admin UI pin management.
- Pinned-only Timeline tab or filter.
- Pinning comments, reviews, tags, media items, or Calendar dates.
- Hiding the original chronological occurrence.
- Pinned entry points in Calendar, Day Review, or Weekly Review.
- Pinned full preview rows in the Timeline top surface.
- Notification/reminder behavior.
- Public/open-source screenshots or marketing work.

## Title Derivation

The collapsed pinned row title should be derived in this order:

1. First non-empty `# ` or `## ` heading in `post.text`, rendered without the Markdown marker.
2. First non-empty body line, trimmed and single-line truncated.
3. Ready audio/video AI summary `documentTitle`, when available.
4. Media fallback such as `Photo moment`, `Audio moment`, or `Video moment`, paired with the human-friendly occurred date when needed.

Pinned title rows may show a light occurred-date accessory for disambiguation. They should not show body previews, media thumbnails, comments, tags, or sync-success badges.

M011 should not add a user-editable pin title in the first implementation. If title editing becomes necessary, it should be a later slice because it adds another user-authored field and export/import/sync surface.

## Technical Shape

- Server schema: add `Post.isPinned` and nullable `Post.pinnedAt`, mapped to `is_pinned` and `pinned_at`.
- iOS schema: add `local_posts.isPinned` and nullable `local_posts.pinnedAt`; bump local/server schema version from 12 to 13 during implementation.
- Sync operation: `update_post_pin` with payload `{ "isPinned": true|false, "pinnedAt": "ISO8601|null" }`.
- Server change: `post_pin_updated` with post id, pin state, `pinnedAt`, and `updatedAt`.
- Existing `post_created` and `post_updated` payloads should include pin fields for baseline recovery.
- Ordering: pinned shelf sorts by `pinnedAt DESC`, tie-breaking by `occurredAt DESC`, then id.
- Conflict policy: last server-accepted pin operation wins.
- Pending, failed, partially synced, and synced local moments can all be pinned/unpinned; the operation joins the outbox and syncs later.
- Pin and favorite are independent; pin/unpin never toggles favorite, and favorite/unfavorite never toggles pin.
- Delete behavior: deleted moments disappear from pinned shelf; unpin does not need a separate emitted change when `post_deleted` is applied.
- Export/import and Archive should preserve pin metadata with posts.

## UI Shape

- Pinned appears only on the main Timeline and only when Timeline has no active search, date, tag, favorite, commented, content-type, needs-sync, or match-source filter.
- When one to three pinned moments exist, the collapsed header shows `Pinned · N`; tapping the header expands or collapses up to three title rows. That expanded/collapsed state is a local UI preference and does not sync.
- When more than three pinned moments exist, the Timeline shows only the `Pinned · N` header. Tapping it opens a bottom sheet with a full pinned title list.
- The pinned sheet uses an internal navigation stack. Selecting a pinned row pushes the normal `MomentDetailView` inside the sheet, with full detail behavior including edit, delete, favorite, tag edit, and pin/unpin.
- Pinned sheet rows support unpin through long-press/context menu. They do not show a permanent unpin button.
- Moment Detail should expose pin/unpin inside a top `More` menu, not as another always-visible toolbar icon.
- Timeline ordinary rows expose pin/unpin through long-press/context menu, not through the existing favorite swipe action and not through a permanent row button.

## Runtime And Worktree Safety

This design was created in a dedicated feature worktree so the user's active `main` working copy and live development version stay untouched.

Implementation and verification must keep the same isolation:

- Do not run feature server code against the live `3210` data directory by default.
- Use a separate port such as `3211` and a worktree-local data directory for server/API smoke tests.
- Generic iOS builds with `CODE_SIGNING_ALLOWED=NO` are safe and should be the first iOS verification gate.
- Do not run `npm run ios:device` from this feature worktree until there is a deliberate real-device checkpoint with Sync Health/outbox review and an iPhone app-container or equivalent recovery point.
- Installing from the feature worktree uses the same bundle id and app container as the daily `Moments` app, so worktree isolation alone is not data isolation.

## Completion Bar

Implementation is complete only when:

- Server Prisma migration, generate, typecheck/build, and focused sync tests pass.
- iOS schema migration, local model, Timeline rendering, Detail action, and focused tests pass.
- Generic iOS Debug build passes.
- Isolated server smoke proves pin/unpin sync round trip without touching live data.
- Simulator validation covers the Timeline pinned header, one-to-three-row expansion preference, more-than-three bottom sheet, sheet-internal detail navigation, and pin/unpin interaction logic.
- Worktree-specific verification evidence records the exact port/data directory used.
- Real-device install/UAT is either completed with recovery evidence or explicitly left as an open UAT gate.
