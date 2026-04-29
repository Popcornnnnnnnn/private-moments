# S02 — Research

**Date:** 2026-04-30

## Summary

S02 is a targeted SwiftUI implementation slice. S01 already delivered the durable comment model, outbox payloads, local SQLite storage, oldest-first database fetch, and `TimelineStore.createComment(postId:text:)` / `TimelineStore.deleteComment(_:)` methods. The remaining work is to expose those seams in `MomentDetailView` as a quiet private-comments section without changing `TimelineRow` or any timeline filtering/search behavior.

This slice owns R008 and R010. R008 is delivered by adding an inline multiline comment input, rendering `item.comments` under the moment, and deleting comments through a confirmation alert. R010 is protected by using plain `String` text, single-level rows, no reply/edit/like/mention UI, and no Markdown/rich text rendering. Existing project memories and decisions reinforce that comments should feel like private expression notes, not social comments or a writing/management surface.

## Recommendation

Implement comments directly in `ios/PrivateMoments/Views/MomentDetailView.swift`, but consider extracting small private subviews in the same file or a new `MomentCommentsSection.swift` if the file grows too much. Use the existing `PlainTextListEditor` for a multiline plain-text input only if the list-continuation behavior is acceptable as plain text assistance; it does not render Markdown and matches the existing plain-string input boundary. The add button should be disabled for whitespace-only text and should clear the draft only after `store.createComment(postId:text:)` returns `true`.

Render `item.comments` directly; `LocalDatabase.fetchComments(postId:)` already filters `deletedAt IS NULL` and orders by `createdAt ASC`, so the UI receives oldest-first visible comments. Delete should use an `alert` or centered confirmation pattern rather than swipe-only deletion, consistent with the project’s cautious deletion posture. Do not modify `TimelineRow.swift` / `TimelineView.swift` for badges, counts, previews, search participation, or density changes.

## Implementation Landscape

### Key Files

- `ios/PrivateMoments/Views/MomentDetailView.swift` — Primary S02 surface. Currently renders header, post text, media grid, favorite/edit/delete toolbar, edit sheet, gallery, and moment delete confirmation. Needs a comments section below media/text with inline input, comment list, delete action, local state for draft text/submission/deletion confirmation, and accessibility labels.
- `ios/PrivateMoments/Models/TimelinePost.swift` — Defines `TimelineComment` and `TimelineItem.comments`. No model change expected for S02 unless a small computed helper is added elsewhere.
- `ios/PrivateMoments/Persistence/TimelineStore+Mutations.swift` — Already provides `createComment(postId:text:) async -> Bool` and `deleteComment(_:) async`. These trim whitespace, create outbox operations (`create_comment` / `delete_comment`), reload items, refresh pending counts, and trigger sync when authenticated. UI should call these rather than writing database/outbox code.
- `ios/PrivateMoments/Persistence/LocalDatabase+Records.swift` — `fetchComments(postId:)` already returns only non-deleted comments ordered `createdAt ASC`. This satisfies oldest-first display if the UI uses `item.comments` as-is.
- `ios/PrivateMoments/Persistence/LocalDatabase+Timeline.swift` — `fetchTimelineItem` only returns live posts, and timeline items include comments. `softDeletePost` hides the parent moment from detail/timeline; comments do not appear as orphan UI because comments are only fetched under visible posts. No S02 change expected unless tests expose a stricter local cascade requirement.
- `ios/PrivateMoments/Views/PlainTextListEditor.swift` — Existing multiline plain-text UIKit-backed editor. It includes plain-string list continuation for bullets/numbered lists but no Markdown rendering. Suitable for comment input if the planner accepts this consistency with composer/edit input; otherwise use SwiftUI `TextEditor` for an even simpler comment field.
- `ios/PrivateMoments/Views/TimelineRow.swift` and `ios/PrivateMoments/Views/TimelineView.swift` — Important non-change files. They should remain free of comment badges/counts/previews, and timeline search should continue searching post text only.
- `ios/PrivateMomentsTests/CommentSyncPayloadTests.swift` — Existing comment payload tests. S02 may add focused unit coverage only for extracted pure helpers (for example trimmed draft enablement/date formatting), but full UI behavior is not currently covered by SwiftUI UI tests.
- `ios/project.yml` — Test scheme currently runs `PrivateMomentsTests`; XcodeGen must be run from `ios/`.

### Natural Seams

- **UI composition seam:** Add a comments section below existing content in `MomentDetailView` without touching sync/database code. If the implementation becomes large, extract `MomentCommentsSection`, `MomentCommentRow`, and/or `CommentComposer` to keep `MomentDetailView.swift` from growing further.
- **Mutation seam:** The UI only calls `TimelineStore.createComment` and `TimelineStore.deleteComment`; it should not duplicate payload construction or outbox logic.
- **Timeline non-surface seam:** Leave timeline row/list/search/filter code unchanged except for compilation fallout, preserving R008’s no-clutter requirement.

### Build Order

1. Build the comments section UI against in-memory `item.comments`: title/empty state, oldest-first rows, timestamp/sync badge if desired, and delete affordance with adequate hit area.
2. Wire inline input state to `store.createComment(postId:text:)`: trim for enablement, disable while submitting, clear only on success, preserve text on failure so retry/edit is possible.
3. Wire comment delete confirmation to `store.deleteComment(_:)`: keep a `pendingCommentDelete: TimelineComment?` and present a centered alert/confirmation before mutation.
4. Rebuild iOS and inspect any warnings/errors. If helper extraction was added, include focused tests; otherwise defer behavioral proof to S03 real-device UAT.

### Verification Approach

- Compile/build: `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`.
- Optional existing tests after UI compiles: `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16'` if an available simulator exists; otherwise record the simulator limitation and rely on generic build plus later real-device UAT.
- Static/product review checks:
  - `TimelineRow.swift` remains without comment count/badge/preview.
  - `TimelineView.filteredItems` remains post-text-only and does not search comments unless a future milestone explicitly changes search.
  - Comment input disables whitespace-only submit.
  - Delete path has a confirmation alert before calling `deleteComment`.
  - UI renders `item.comments` in provided order (`createdAt ASC` from DB), not reversed.
- Real-device UAT is best left for S03/final validation but should cover: open moment detail, add two comments, confirm oldest-first order, delete one through confirmation, return to timeline and confirm no timeline clutter, sync against Mac server.

## Constraints

- App-facing UI copy should stay English.
- Human-facing docs are not expected in S02 unless UI behavior or verification instructions are documented early; S03 owns validation/docs.
- Comments must remain plain text and single-level: no reply controls, likes, mentions, public author identity, Markdown rendering, comment media, editing, or timeline indicators.
- `MomentDetailView.swift` is already listed as a large file; prefer private subviews/extraction if the comment UI adds substantial code.
- `lastSyncCursor` safety and idempotent sync are already implemented in S01; do not rework sync semantics in this UI slice.
- XcodeGen must run from `ios/`, not the repository root.

## Common Pitfalls

- **Clearing failed drafts** — Only clear the comment input after `createComment` returns `true`; otherwise a transient DB/sync error could lose typed private text.
- **Accidental timeline clutter** — Do not add comment counts, dots, badges, preview text, or comment search to `TimelineRow`/`TimelineView`.
- **Hidden social semantics** — Avoid labels like “reply”, “thread”, “author”, “like”, “mention”, or avatar-like UI. Use private-note language such as “Comments” / “Add private comment”.
- **Delete without confirmation** — Comments are personal text; deletion should be explicitly confirmed before soft-delete/outbox queueing.

## Skills Discovered

| Technology | Skill | Status |
|------------|-------|--------|
| SwiftUI | `avdlee/swiftui-agent-skill@swiftui-expert-skill` (`npx skills add avdlee/swiftui-agent-skill@swiftui-expert-skill`) | available, not installed |
| SwiftUI | `twostraws/swiftui-agent-skill@swiftui-pro` (`npx skills add twostraws/swiftui-agent-skill@swiftui-pro`) | available, not installed |
| UI polish | Installed `make-interfaces-feel-better` skill | used for quiet surface/hit-area guidance |
