---
id: T03
parent: S02
milestone: M002
key_files:
  - ios/PrivateMoments/Views/MomentDetailView.swift
  - ios/PrivateMoments/Views/MomentCommentsSection.swift
  - ios/PrivateMomentsTests/MomentCommentUITests.swift
key_decisions:
  - Kept destructive comment selection and in-flight deletion state local to `MomentDetailView`, with rows only requesting deletion, so comments disappear only through the existing `TimelineStore.deleteComment` reload path.
duration: 
verification_result: passed
completed_at: 2026-04-29T19:53:02.771Z
blocker_discovered: false
---

# T03: Added confirmed private-comment deletion in Moment detail while keeping comments out of the timeline.

**Added confirmed private-comment deletion in Moment detail while keeping comments out of the timeline.**

## What Happened

Added a quiet per-comment destructive affordance in `MomentCommentsSection`: each row now has a red 40×40 hit-area trash button, accessible label/hint, and a lightweight spinner while that comment is deleting. Wired `MomentDetailView` to hold the selected comment for a centered SwiftUI alert confirmation, guard duplicate deletion while one mutation is in flight, safely no-op missing selections, and call `await store.deleteComment(comment)` without locally removing rows outside the store/reload path. Preserved the existing `TimelineStore` error path for mutation failures and did not add private body logging or any timeline badge/count/preview/search wiring. Added deterministic unit coverage for missing delete selection, selected-only confirmation, and duplicate-delete no-op behavior.

## Verification

Ran the PrivateMoments XCTest suite on the iPhone 16 simulator; it passed 16 tests with 0 failures, including new comment deletion policy tests. Ran static checks proving `TimelineRow.swift` and `TimelineView.swift` still have no `comment`/`Comment` matches and touched detail/comment views contain no `print`, `NSLog`, `os_log`, or `Logger` calls. Ran the required generic iOS build followed by the timeline non-clutter grep; it exited 0 with `** BUILD SUCCEEDED **`. LSP diagnostics were attempted on `MomentDetailView.swift` but SourceKit in this harness reported `No such module 'UIKit'`, while the real Xcode build succeeded.

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16'` | 0 | ✅ pass | 41100ms |
| 2 | `! rg -n "comment|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift` | 0 | ✅ pass | 0ms |
| 3 | `! rg -n "print|NSLog|os_log|Logger" ios/PrivateMoments/Views/MomentCommentsSection.swift ios/PrivateMoments/Views/MomentDetailView.swift` | 0 | ✅ pass | 0ms |
| 4 | `(cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build) && ! grep -R "comment\|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift` | 0 | ✅ pass | 5618ms |

## Deviations

Extended `ios/PrivateMomentsTests/MomentCommentUITests.swift` with focused deletion-selection policy tests so cancel/missing-selection/duplicate-delete behavior is covered deterministically alongside the UI implementation. Adapted the plan's `cd ios && ... && ! grep ... ios/...` verification to run from the repository root after the build subshell, because auto-mode requires commands to operate relative to the project working directory.

## Known Issues

None.

## Files Created/Modified

- `ios/PrivateMoments/Views/MomentDetailView.swift`
- `ios/PrivateMoments/Views/MomentCommentsSection.swift`
- `ios/PrivateMomentsTests/MomentCommentUITests.swift`
