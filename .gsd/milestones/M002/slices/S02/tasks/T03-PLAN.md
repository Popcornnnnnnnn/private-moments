---
estimated_steps: 6
estimated_files: 4
skills_used: []
---

# T03: Add confirmed comment deletion and final timeline non-clutter proof

Why: This closes the destructive half of R008 and proves R010/R008 constraints that comments remain detail-only, single-level, and not timeline clutter.

Skills expected in task plan frontmatter: `make-interfaces-feel-better`, `verify-before-complete`.

Do: Add a delete affordance on each comment row with adequate hit area and a centered SwiftUI `alert` confirmation before calling `await store.deleteComment(comment)`. Keep any deleting state local enough to avoid duplicate taps but do not remove comments outside the store/reload path. Include accessible labels that describe the action without inventing social metadata. Run final static checks that `TimelineRow.swift` and `TimelineView.swift` have not gained comment badges/counts/previews or comment search participation.

Failure Modes (Q5): Dependency `TimelineStore.deleteComment`; on error, rely on existing store error handling and do not dismiss/unwind the whole detail view; no timeout handling is needed beyond avoiding duplicate delete actions; malformed state such as a missing selected comment should cancel safely.

Load Profile (Q6): Per delete is one store mutation and reload; shared resources are existing outbox/local database; a long comment list should not add timeline cost because no timeline row/search wiring is introduced.

Negative Tests (Q7): Canceling confirmation must not call delete, confirming deletes only the selected comment, missing selection must be a no-op, and timeline files must not include new comment display/search code.

## Inputs

- `ios/PrivateMoments/Views/MomentDetailView.swift`
- `ios/PrivateMoments/Views/MomentCommentsSection.swift`
- `ios/PrivateMoments/Views/TimelineRow.swift`
- `ios/PrivateMoments/Views/TimelineView.swift`

## Expected Output

- `ios/PrivateMoments/Views/MomentDetailView.swift`
- `ios/PrivateMoments/Views/MomentCommentsSection.swift`

## Verification

cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build && ! grep -R "comment\|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift

## Observability Impact

Deletion remains diagnosable through existing store/outbox status and visible row disappearance after reload. Do not add logs or timeline previews containing private comment text.
