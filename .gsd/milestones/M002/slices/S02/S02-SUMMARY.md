---
id: S02
parent: M002
milestone: M002
provides:
  - iOS Moment detail can view, add, and confirm-delete private plain-text comments using S01 store/sync seams while keeping the main timeline uncluttered.
  - Reusable tested policy helpers for comment draft submission and deletion confirmation state.
requires:
  - slice: S01
    provides: `TimelineItem.comments`, `TimelineComment`, `TimelineStore.createComment(postId:text:)`, `TimelineStore.deleteComment(_:)`, local comment storage, and sync/outbox plumbing.
affects:
  - S03
key_files:
  - ios/PrivateMoments/Views/MomentCommentsSection.swift
  - ios/PrivateMoments/Views/MomentDetailView.swift
  - ios/PrivateMomentsTests/MomentCommentUITests.swift
  - .gsd/PROJECT.md
key_decisions:
  - Kept `MomentCommentDraftPolicy` independent of SwiftUI, SQLite, and network so UI boundary rules are deterministic and unit-testable.
  - Kept draft/submitting/delete-selection state local to `MomentDetailView`, with `MomentCommentsSection` as a plain rendering/request component, so failure recovery remains visible and comments disappear only through store reload paths.
  - Used plain `TextEditor`/`Text` rendering plus existing `SyncBadge` rather than Markdown, rich-text, or social metadata surfaces.
patterns_established:
  - Use Foundation-only policy helpers for UI boundary behavior that needs deterministic tests.
  - Keep mutation coordination state local to the entrypoint view and route persistence changes through `TimelineStore` rather than optimistically mutating row collections.
  - Prove timeline non-clutter with static checks against `TimelineRow.swift` and `TimelineView.swift` whenever detail-only features are added.
observability_surfaces:
  - Existing visible `SyncBadge(status:)` on comment rows for pending/synced state where available.
  - Existing `TimelineStore.errorMessage` path for mutation failures.
  - No private comment body logging; static no-logging check covers touched detail/comment views.
drill_down_paths:
  - .gsd/milestones/M002/slices/S02/tasks/T01-SUMMARY.md
  - .gsd/milestones/M002/slices/S02/tasks/T02-SUMMARY.md
  - .gsd/milestones/M002/slices/S02/tasks/T03-SUMMARY.md
duration: ""
verification_result: passed
completed_at: 2026-04-29T19:54:52.641Z
blocker_discovered: false
---

# S02: Private comments in Moment detail

**Moment detail now shows private plain-text comments with retry-safe add and confirmed delete controls, while the main timeline remains untouched.**

## What Happened

S02 consumed the S01 comment model/store contract and wired it into the actual iOS Moment detail entrypoint. The slice added `MomentCommentDraftPolicy` as a deterministic, Foundation-only policy for trimming drafts, rejecting whitespace-only submissions, preserving internal newlines and Markdown-like characters as literal text, and coordinating draft clearing only after successful creation. `MomentDetailView` now composes `MomentCommentsSection` below the existing moment content/media, renders `item.comments` in the supplied local-storage order, routes add operations through `TimelineStore.createComment(postId:text:)`, and preserves the typed draft when creation fails so retry remains recoverable. The comment section stays quiet and private: it uses plain `Text`/`TextEditor`, a simple empty state, existing `SyncBadge` row status, and no reply/social/rich-text affordances. Deletion was added as a per-comment destructive row action with a centered confirmation alert in `MomentDetailView`; selected-comment and in-flight delete state are local to the detail view, duplicate deletes no-op, missing selections no-op safely, and rows are not removed outside the existing `TimelineStore.deleteComment` reload path. Static checks confirmed `TimelineRow.swift` and `TimelineView.swift` still have no comment display/search surface, preserving the uncluttered timeline constraint.

## Verification

Fresh slice-level verification ran after the last file change in this completion unit. `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16'` exited 0 with `** TEST SUCCEEDED **` and 16 tests / 0 failures, including 10 `MomentCommentUITests` covering whitespace rejection, trim behavior, plain-text preservation, draft success/failure clearing, selected-only delete, missing-selection no-op, and duplicate-delete no-op. `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build` exited 0 with `** BUILD SUCCEEDED **`. Static non-clutter proof passed: `! rg -n "comment|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift` exited 0. Privacy logging proof passed: `! rg -n "print|NSLog|os_log|Logger" ios/PrivateMoments/Views/MomentCommentsSection.swift ios/PrivateMoments/Views/MomentDetailView.swift` exited 0.

## Requirements Advanced

- R008 — Moment detail now displays `item.comments`, supports non-empty plain-text create through `TimelineStore.createComment`, supports confirmed delete through `TimelineStore.deleteComment`, preserves drafts on failed create, and static checks prove no timeline badges/counts/previews/search were added.
- R010 — Implementation uses plain strings and plain SwiftUI text/editor controls only; tests preserve Markdown-like characters as literal text and static/no-UI review found no replies, likes, mentions, rich text, media, edit/thread, or public identity affordances.

## Requirements Validated

None.

## New Requirements Surfaced

- None.

## Requirements Invalidated or Re-scoped

None.

## Operational Readiness

None.

## Deviations

Extended the planned XCTest coverage beyond draft policy into deterministic delete-selection policy tests, covering missing selection, selected-only confirmation, and duplicate-delete no-op behavior. This stayed within the slice goal and improved proof for destructive behavior. No timeline UI files required edits for comment display/search, as intended.

## Known Limitations

Full real-device add/delete plus server sync convergence UAT is intentionally deferred to S03. S02 proves the iOS detail-view runtime path, simulator unit tests, generic iOS build, static timeline non-clutter, and no private-body logging checks; it does not close the milestone-level documentation or cross-boundary UAT requirement.

## Follow-ups

S03 should run the documented real-device UAT path against the Mac server, verify comment create/delete sync behavior end-to-end, and update product/operator/integration documentation in Chinese-facing docs while preserving English app UI copy.

## Files Created/Modified

- `ios/PrivateMoments/Views/MomentCommentsSection.swift` — Added private comment section rendering, draft policy, plain-text add UI, row sync status, and delete affordance callbacks.
- `ios/PrivateMoments/Views/MomentDetailView.swift` — Composed the comments section below moment content/media and coordinated add/delete state plus centered delete confirmation.
- `ios/PrivateMomentsTests/MomentCommentUITests.swift` — Added deterministic XCTest coverage for draft trimming/submission/plain-text behavior and deletion selection policy.
- `.gsd/PROJECT.md` — Refreshed project state to include private comments in the current product surface and design constraints.
