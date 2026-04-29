---
id: T02
parent: S02
milestone: M002
key_files:
  - ios/PrivateMoments/Views/MomentDetailView.swift
  - ios/PrivateMoments/Views/MomentCommentsSection.swift
  - ios/PrivateMomentsTests/MomentCommentUITests.swift
key_decisions:
  - Used local MomentDetailView state for comment draft/submitting coordination so failure recovery remains visible and isolated from timeline rendering.
  - Used plain TextEditor/Text rendering plus existing SyncBadge for comment rows, avoiding Markdown/rich/social semantics and avoiding private comment body logs.
duration: 
verification_result: passed
completed_at: 2026-04-29T19:50:06.877Z
blocker_discovered: false
---

# T02: Rendered private comments in Moment detail with retry-safe plain-text submission.

**Rendered private comments in Moment detail with retry-safe plain-text submission.**

## What Happened

Composed `MomentCommentsSection` under the existing detail text/media content in `MomentDetailView`, passing `item.comments` through in local-storage order and routing add submissions to `TimelineStore.createComment(postId:text:)`. Built the section as plain SwiftUI text/editor UI with a quiet empty state, no reply/social/rich-text affordances, no timeline badge/count/preview/search changes, and lightweight `SyncBadge` row status for existing observability. Kept draft/submitting state local to the detail view, disabled duplicate or whitespace-only submits, cleared the draft only after a successful store return, and preserved the visible draft when the store returns `false` or surfaces an error through `store.errorMessage`. Added a deterministic policy test proving drafts clear only on successful submission.

## Verification

Ran LSP diagnostics on the edited Swift files with no diagnostics. Ran the slice XCTest command on the iPhone 16 simulator; it passed 13 tests with 0 failures, including the new draft-preservation test. Ran the required generic iOS build after changes; it exited 0 with `** BUILD SUCCEEDED **`. Ran static timeline non-clutter and no-private-body-logging checks; timeline files had no `comment`/`Comment` matches and touched view files had no `print`, `NSLog`, `os_log`, or `Logger` calls.

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `lsp diagnostics ios/PrivateMoments/Views/MomentDetailView.swift ios/PrivateMoments/Views/MomentCommentsSection.swift ios/PrivateMomentsTests/MomentCommentUITests.swift` | 0 | ✅ pass | 0ms |
| 2 | `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16'` | 0 | ✅ pass | 39500ms |
| 3 | `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build` | 0 | ✅ pass | 14500ms |
| 4 | `grep -R "comment\|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift || true` | 0 | ✅ pass | 0ms |
| 5 | `grep -R "print\|NSLog\|os_log\|Logger" ios/PrivateMoments/Views/MomentCommentsSection.swift ios/PrivateMoments/Views/MomentDetailView.swift || true` | 0 | ✅ pass | 0ms |

## Deviations

Extended `ios/PrivateMomentsTests/MomentCommentUITests.swift` with a focused draft-success/failure policy assertion even though the task expected output listed only the two view files; this directly verifies the specified failed-create draft preservation rule.

## Known Issues

Comment deletion remains for T03 as planned. Real-device UAT remains deferred to S03 as planned.

## Files Created/Modified

- `ios/PrivateMoments/Views/MomentDetailView.swift`
- `ios/PrivateMoments/Views/MomentCommentsSection.swift`
- `ios/PrivateMomentsTests/MomentCommentUITests.swift`
