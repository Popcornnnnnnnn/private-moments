# M003: Feed Comments

**Gathered:** 2026-04-30
**Status:** Implemented; user-confirmed; sync failure cleanup added
**Supersedes:** the previous M002 detail-only private comments direction. The current worktree intentionally keeps old M002 removed from the active milestone tree. Reuse old data/sync ideas only after checking them against this context.

## Project Description

Add single-user `Comments` to the iOS main timeline. The interaction should feel closer to WeChat Moments than to a detail-only note feature: each moment has a quiet comment action, comments can be created directly from the timeline through a bottom input bar, and existing comments live under the moment in the feed.

This is not a public or multi-user social system. There is no second author, no family sharing, no replies, no likes, no mentions, no public author identity, and no comment media. Comments are private user content attached to a moment and synced through the existing local-first Mac server architecture.

## Why This Milestone

The user wants a comment interaction pattern, not merely a hidden note field. The main timeline should support quick follow-up expression in place, while still preserving Moments as a private expression space rather than a social network.

This touches schema migrations, SQLite, sync semantics, search, recovery, and real-device keyboard/gesture behavior. It must be planned as a full milestone before implementation.

## User-Visible Outcome

### When this milestone is complete, the user can:

- Tap a comment icon under a moment in the main timeline.
- See a bottom comment input bar, focused with the keyboard, showing a short target summary such as `Commenting on: ...` or `Photo moment · 3 photos`.
- Write plain multiline text and send with a `Send` button; Return inserts a newline.
- Send a comment, then see the input close and the timeline move to the bottom of that moment so the newest comment is visible.
- See new comments appear immediately in the moment's timeline comment area, without waiting for sync.
- See the latest two comments under each moment by default, shown oldest-to-newest within that preview.
- Tap `View all N comments` to expand the full comment list in place, then `Show less` to collapse back to the latest two.
- Long-press any comment in the timeline, see pressed feedback and haptic confirmation, then confirm `Delete comment?` to delete it.
- Search moment text and comment text together; comment search matches keep the result explainable by surfacing matching comments first and lightly emphasizing matching rows.

### Entry Point / Environment

- Entry point: iOS `Moments` app main timeline.
- Existing moment detail stays available for current detail/edit/delete/media flows, but comments are not managed from detail in this milestone.
- Environment: local-first iOS app with Mac Fastify/Prisma/SQLite server over Tailscale or private network.

## Completion Class

- Contract complete means: server/iOS/shared sync contracts define independent comment entities, `create_comment` and `delete_comment`, parent post constraints, soft delete behavior, and cursor-safe server-change handling.
- Integration complete means: the main timeline comment UI, bottom input bar, local SQLite, outbox ordering, search, deletion, parent cascade, and server sync work together.
- Operational complete means: migrations and recovery-sensitive paths have current-session evidence, and the WeChat-like main timeline flow has real iPhone UAT when feasible.

## Final Integrated Acceptance

To call this milestone complete, prove:

- A real iPhone can create a timeline comment from the main feed, keep the keyboard/input target stable, and immediately show the new comment under the correct moment.
- The timeline displays a comment icon on every moment, real comment counts for moments with comments, latest-two previews, `View all N comments`, and `Show less`.
- Long-press deletion removes a comment locally immediately, asks `Delete comment?`, syncs deletion when needed, and does not delete the parent moment.
- Search applies existing filters first, then matches moment text or comment text; comment matches are visible and lightly emphasized in results.
- Comment create/delete sync through the Mac server without duplicate comments, cursor loss, orphan comments, or parent/post ordering bugs.
- Server migration, iOS schema migration, and restore/recovery or equivalent SQLite inspection are verified.
- Comment operations appear in sync diagnostics/outbox counts without exposing comment body text.

## Scope

### In Scope

- Server `Comment` entity/table with soft delete and parent `Post` relation.
- iOS `local_comments` table and local timeline model support.
- `create_comment` and `delete_comment` sync operations; no `update_comment`.
- Strict server rejection for missing or deleted parent posts.
- Cursor-safe iOS application of `comment_created` and `comment_deleted`; missing parent on comment apply fails and blocks cursor advancement.
- Parent moment deletion cascades/hides local comments; server emits `post_deleted` only, not per-comment delete changes.
- Local short-circuit when an unsynced newly created comment is deleted before it reaches the server.
- Timeline action row containing only the comment button/count.
- Timeline comment section with light secondary background, latest-two preview, full multiline text, relative English time, expand/collapse, and long-press delete.
- Bottom timeline comment input bar with target summary, multiline text, 500-character limit, draft discard confirmation, and send-success closure followed by scroll-to-moment-bottom feedback.
- Search over comments after existing filters, including matching-comment prioritization and row-level light emphasis.
- Advanced Sync/outbox diagnostics for comment operation types and counts, without comment text.
- OpenAPI and sync protocol updates.
- Real iPhone UAT and migration/recovery verification.

### Out of Scope / Non-Goals

- Multi-user or family author identity.
- Public comments, likes, reactions, mentions, replies, nested threads, or `replyToCommentId`.
- Comment editing.
- Comment text selection/copy in the first version; long press is reserved for delete.
- Comment media attachments, Markdown rendering, rich text, headings, link previews, or automatic cleanup of Markdown-like text.
- Admin UI comment display or management.
- Storage/media diagnostics for comments.
- Changing moment timeline sort order based on comment activity.
- Per-comment `synced`, `pending`, or `failed` status badges.
- Managing comments from Moment detail.

## Architectural Decisions

### Main timeline owns comments

**Decision:** Comments are read, created, expanded, collapsed, and deleted in the main timeline. Moment detail remains for existing moment detail/edit/media behavior and does not manage comments.

**Rationale:** The desired interaction is WeChat Moments-like: fast in-feed commenting without navigating into a detail-only note surface.

### Single-user comments, not social authors

**Decision:** Comments have no visible author name, device name, replies, likes, or author permissions in the first version. All comments are the user's comments and may be long-pressed for delete.

**Rationale:** The product remains a private expression space. The social-like part is the interaction pattern, not a networked audience model.

### Timeline density is controlled but not hidden

**Decision:** Every moment has a quiet comment action. Moments with comments show real counts and a comment area. Default preview shows the latest two comments, displayed oldest-to-newest; full lists expand in place.

**Rationale:** This gives comments enough presence to feel useful while preventing every long thread from permanently expanding the feed.

### Plain text only

**Decision:** Comments are plain multiline text, maximum 500 characters, with Markdown-like input shown literally. Return inserts newline; `Send` sends.

**Rationale:** The feature should support quick expression without turning comments into a second editor or media pipeline.

### Independent local-first comment entities

**Decision:** Comments are independent entities in server and iOS SQLite, synced with `create_comment` and `delete_comment` operations.

**Rationale:** Independent entities preserve local-first durability, idempotency, soft delete, and recovery semantics better than embedding comment arrays in post payloads.

## Error Handling Strategy

- Empty or whitespace-only comments disable `Send`.
- Text over 500 characters shows a lightweight limit hint and disables `Send`; it is not truncated.
- Switching comment targets with a non-empty draft asks `Discard draft?`.
- Closing the input bar with a non-empty draft asks `Discard draft?`; closing an empty draft is immediate.
- Keyboard dismissal keeps the input bar and draft.
- Comment target does not change on scroll; only tapping another comment button changes the target.
- Server rejects comment creation for missing or deleted posts.
- iOS fails comment server-change application if the parent post is missing, and must not advance `lastSyncCursor`.
- Deleting an unsynced local comment cancels the pending create when possible; deleting an already-sent/synced comment queues `delete_comment`.
- Comment sync failure is visible only through global sync/outbox diagnostics, not per-comment badges.

## Risks And Unknowns

- Existing `TimelineView` currently has whole-row tap-to-detail behavior; comment buttons, comments, and expand/collapse controls must not accidentally trigger detail navigation.
- SwiftUI `List`, bottom input bar, keyboard avoidance, and automatic scroll-to-target need real-device validation.
- Search result explainability needs careful preview selection when comment matches are not among the latest two comments.
- Local-first ordering requires create-post operations to precede comments for unsynced parent moments.
- The current worktree contains staged deletion/removal of the old M002 detail-only comments work; future implementation must not accidentally restore old UI assumptions.

## Existing Codebase / Prior Art

- `ios/PrivateMoments/Views/TimelineView.swift` owns timeline filtering, search, list rows, detail navigation, delete alert, and toolbar state.
- `ios/PrivateMoments/Views/TimelineRow.swift` currently renders date/status, post text, and media; it has no action row or comment section yet.
- `ios/PrivateMoments/Views/MomentDetailView.swift` remains the existing detail/edit/media surface.
- `ios/PrivateMoments/Persistence/TimelineStore+Mutations.swift`, `+Payloads.swift`, `+ServerChanges.swift`, and `LocalDatabase+*` are the iOS sync/persistence seams.
- `server/src/api/sync.ts`, `server/prisma/schema.prisma`, and `shared/sync-protocol.md` are the server/shared sync contract seams.
- Old M002 work may contain useful server/iOS data-sync patterns, but its detail-only UI/product assumptions are superseded.

## 2026-04-30 Sync Failure Follow-Up

- Real iPhone outbox inspection found old `create_comment` / `delete_comment` operations failed with `Unsupported operation type` from a previous server version.
- Server sync idempotency now replays previously unsupported comment operations when the current implementation supports the operation/entity pair, instead of permanently returning the historical rejection.
- iOS local sync now settles deleted-comment no-ops: `create_comment` rejected as `Parent post not found` can be marked synced when the local comment or parent post has already been deleted, and `delete_comment` rejected as `Comment not found` can be marked synced when the local comment is already gone/deleted.
- Verification: isolated temp SQLite server replayed an old rejected `create_comment` op and returned `acceptedOps: 1`, `rejectedOps: 0`; iOS simulator tests and generic iOS Debug build passed. Real-device reinstall of the iOS cleanup patch is pending because `wwz 的 iphone` was `unavailable` in CoreDevice.

## Relevant Requirements

- R001 — Closure loop with summary, verification, known issues, and fact/doc updates.
- R002 — High-risk work needs milestone/slice planning before implementation.
- R003 — Verification depth must cover server, iOS, sync, storage/recovery, and real-device behavior when feasible.
- R008 — Main timeline comments UI.
- R009 — Local-first comment sync and recovery.
- R010 — Comment content and interaction boundaries.
- R011 — Comment-aware search behavior.
- R012 — Migration, diagnostics, and real-device UAT evidence.

## Slice Roadmap

- S01: Supersede old M002 and define the feed-comments contract.
- S02: Implement independent comment persistence and sync.
- S03: Implement timeline comment UI, input bar, search, and deletion.
- S04: Run migration/recovery/device validation and update docs.

## Open Questions

- Whether the old M002 server/iOS sync code should be selectively recovered during S02 or rewritten against this new milestone.
- Whether the current staged deletion state should be committed as a cleanup before S02 starts.
