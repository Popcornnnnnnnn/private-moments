---
estimated_steps: 6
estimated_files: 2
skills_used: []
---

# T02: Render and submit private comments in Moment detail

Why: This task delivers the main R008 user-facing path: opening a moment detail shows comments under the moment and allows adding a private plain-text comment without touching timeline feed density.

Skills expected in task plan frontmatter: `make-interfaces-feel-better`, `verify-before-complete`.

Do: Compose the comments section below the existing moment text/media in `MomentDetailView`. Render `item.comments` directly in the supplied order (oldest-first from `LocalDatabase.fetchComments(postId:)`), with a quiet empty state and no nested/reply/social UI. Add an inline multiline plain-text draft field (use `TextEditor` or the existing plain text editor only if it does not imply rich text), disable submit while whitespace-only or submitting, call `await store.createComment(postId:item.post.id,text:draft)`, clear the draft only when the result is `true`, and preserve the draft on failure. Keep app-facing copy English and avoid adding comment count/badge/preview/search to `TimelineRow.swift` or `TimelineView.swift`.

Failure Modes (Q5): Dependency `TimelineStore.createComment`; on error/false return, leave the draft intact and let existing `store.errorMessage` carry the failure; no timeout handling is needed beyond disabling duplicate submit while awaiting; malformed/whitespace input must not call the store.

Load Profile (Q6): Shared resources are SwiftUI state and existing local database/outbox via store; per add is one store mutation and reload; 10x comments may make the detail section longer but should not affect timeline rendering.

Negative Tests (Q7): Whitespace-only submit disabled, empty comment list renders an empty state, failed create preserves typed text, and Markdown-like text displays as plain text rather than rich rendering.

## Inputs

- `ios/PrivateMoments/Views/MomentDetailView.swift`
- `ios/PrivateMoments/Views/MomentCommentsSection.swift`
- `ios/PrivateMoments/Models/TimelinePost.swift`
- `ios/PrivateMoments/Persistence/TimelineStore+Mutations.swift`

## Expected Output

- `ios/PrivateMoments/Views/MomentDetailView.swift`
- `ios/PrivateMoments/Views/MomentCommentsSection.swift`

## Verification

cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build

## Observability Impact

The add path should expose failure through existing store error presentation and preserve the visible draft for retry. Do not add logs containing comment body text.
