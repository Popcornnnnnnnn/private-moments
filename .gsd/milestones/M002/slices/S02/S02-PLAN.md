# S02: Private comments in Moment detail

**Goal:** Expose the S01 private-comment persistence/sync seams in the iOS Moment detail view so a user can view, add, and delete plain-text comments attached to one moment while the main timeline remains uncluttered.
**Demo:** On iPhone, opening a moment detail shows a private comments section where the user can add and delete plain-text comments; the main timeline stays uncluttered.

## Must-Haves

- ## Must-Haves
- R008: `MomentDetailView` shows a private comments section under the moment content/media, renders `item.comments` in the order supplied by local storage, supports adding a non-empty plain-text comment through `TimelineStore.createComment(postId:text:)`, supports deleting an existing comment through `TimelineStore.deleteComment(_:)`, and does not add comment badges/counts/previews/search to the main timeline.
- R010: The visible comment UI remains plain text and single-level only: no replies, likes, mentions, avatars/public author identity, Markdown rendering, rich text controls, comment media, or edit/thread affordances.
- Failed comment creation must preserve the typed draft; the draft clears only after `createComment` returns `true`.
- Comment deletion must require an explicit confirmation alert before calling the store mutation.
- ## Threat Surface
- **Abuse**: Comment text is user-controlled and eventually syncs through the existing outbox/API path; the UI must reject whitespace-only submissions and avoid adding new operation types or parameter-tampering surfaces.
- **Data exposure**: Comment text is private personal data. Do not log, expose in diagnostics, add timeline previews, or include it in accessibility labels beyond the visible row text already on screen.
- **Input trust**: Treat the draft as untrusted plain text that reaches SQLite and sync payloads via `TimelineStore.createComment`; do not interpret it as Markdown/HTML or attach social metadata.
- ## Requirement Impact
- **Requirements touched**: R008, R010.
- **Re-verify**: Moment detail add/delete behavior, whitespace draft handling, delete confirmation, oldest-first rendering from `item.comments`, and timeline non-clutter (`TimelineRow.swift` / `TimelineView.swift` unchanged for comment display/search).
- **Decisions revisited**: D009 remains in force; no new structural decision is needed unless execution discovers a reason to add social/rich/comment-edit concepts, which should be treated as out of scope.
- ## Verification
- Add focused XCTest file `ios/PrivateMomentsTests/MomentCommentUITests.swift` covering comment draft trimming/submittability and plain-text preservation rules used by the UI.
- Run `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16'` when that simulator is available; if simulator availability blocks tests, record the limitation and still run the generic build below.
- Run `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`.
- Static proof: `grep -R "comment\|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift` should show no new comment count/badge/preview/search UI; if existing unrelated matches appear, document them and verify no timeline comment surface was added.
- ## Observability / Diagnostics
- Runtime signals: Uses existing visible `SyncBadge(status:)`/pending sync status surfaces for comments where included, and existing `TimelineStore.errorMessage` for mutation failures; no private comment text should be logged.
- Inspection surfaces: Moment detail UI shows whether comments are present and whether submit/delete controls are enabled; existing local database/outbox tables remain the backend diagnostic surface from S01.
- Failure visibility: Add operation preserves the draft on failure so the user/agent can retry; pending comment rows can show lightweight sync status without exposing text in logs.
- Redaction constraints: Never add diagnostics that print private comment body text.
- ## Integration Closure
- Upstream surfaces consumed: `TimelineItem.comments` and `TimelineComment` from `ios/PrivateMoments/Models/TimelinePost.swift`; `TimelineStore.createComment(postId:text:)` and `TimelineStore.deleteComment(_:)` from `ios/PrivateMoments/Persistence/TimelineStore+Mutations.swift`; existing detail composition in `ios/PrivateMoments/Views/MomentDetailView.swift`.
- New wiring introduced in this slice: `MomentDetailView` composes a comments section that reads `item.comments`, writes through store mutation methods, and presents a delete confirmation.
- What remains before the milestone is truly usable end-to-end: S03 real-device/cross-boundary UAT and docs update after the UI exists.

## Proof Level

- This slice proves: integration: this slice proves the iOS detail-view runtime path is wired to the previously validated local/sync comment store seams. A generic iOS build is required; simulator XCTest should run when an available iPhone simulator exists; real-device full UAT is deferred to S03 but the UI should be ready for it.

## Integration Closure

Consumes the S01 comment model/store contract and wires it into the actual Moment detail entrypoint. Does not alter the timeline feed/search surfaces. Leaves final real-device sync/UAT documentation to S03.

## Verification

- The UI should make failure recoverable rather than opaque: failed creates preserve draft text, mutation failures continue to surface through the existing store error path, and pending/synced status can be visible via lightweight row status without logging private comment bodies.

## Tasks

- [x] **T01: Add comment UI helper tests and plain-text policy** `est:45m`
  Why: The slice needs executable proof for the comment UI boundary before wiring SwiftUI controls, especially whitespace-only rejection and plain-text/single-level constraints from R010.

Skills expected in task plan frontmatter: `test`, `verify-before-complete`.

Do: Create a small testable helper/policy in `MomentCommentsSection.swift` (for example `MomentCommentDraftPolicy`) that centralizes draft trimming and submit enablement without rendering or interpreting Markdown. Add `MomentCommentUITests.swift` with real XCTest assertions for whitespace-only rejection, trimming of leading/trailing whitespace, preservation of internal newlines/plain text, and no helper behavior that creates replies/rich-text semantics. Keep the helper independent of SQLite/network so the tests are deterministic.

Failure Modes (Q5): Dependency `XCTest/XcodeGen`; on error, fix project/test target wiring without changing app behavior; on unavailable simulator, record the simulator limitation and rely on generic build in later tasks; malformed draft inputs should produce disabled submit or trimmed plain text, never crashes.

Load Profile (Q6): Per-operation cost is trivial string trimming; 10x comment draft size is bounded by in-memory string operations and should not introduce shared resources.

Negative Tests (Q7): Empty string, whitespace/newline-only strings, strings with internal newlines/bullets, and strings containing Markdown-like characters should all remain plain strings with only submit eligibility affected.
  - Files: `ios/PrivateMoments/Views/MomentCommentsSection.swift`, `ios/PrivateMomentsTests/MomentCommentUITests.swift`, `ios/project.yml`
  - Verify: cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16'

- [x] **T02: Render and submit private comments in Moment detail** `est:1h`
  Why: This task delivers the main R008 user-facing path: opening a moment detail shows comments under the moment and allows adding a private plain-text comment without touching timeline feed density.

Skills expected in task plan frontmatter: `make-interfaces-feel-better`, `verify-before-complete`.

Do: Compose the comments section below the existing moment text/media in `MomentDetailView`. Render `item.comments` directly in the supplied order (oldest-first from `LocalDatabase.fetchComments(postId:)`), with a quiet empty state and no nested/reply/social UI. Add an inline multiline plain-text draft field (use `TextEditor` or the existing plain text editor only if it does not imply rich text), disable submit while whitespace-only or submitting, call `await store.createComment(postId:item.post.id,text:draft)`, clear the draft only when the result is `true`, and preserve the draft on failure. Keep app-facing copy English and avoid adding comment count/badge/preview/search to `TimelineRow.swift` or `TimelineView.swift`.

Failure Modes (Q5): Dependency `TimelineStore.createComment`; on error/false return, leave the draft intact and let existing `store.errorMessage` carry the failure; no timeout handling is needed beyond disabling duplicate submit while awaiting; malformed/whitespace input must not call the store.

Load Profile (Q6): Shared resources are SwiftUI state and existing local database/outbox via store; per add is one store mutation and reload; 10x comments may make the detail section longer but should not affect timeline rendering.

Negative Tests (Q7): Whitespace-only submit disabled, empty comment list renders an empty state, failed create preserves typed text, and Markdown-like text displays as plain text rather than rich rendering.
  - Files: `ios/PrivateMoments/Views/MomentDetailView.swift`, `ios/PrivateMoments/Views/MomentCommentsSection.swift`
  - Verify: cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build

- [ ] **T03: Add confirmed comment deletion and final timeline non-clutter proof** `est:45m`
  Why: This closes the destructive half of R008 and proves R010/R008 constraints that comments remain detail-only, single-level, and not timeline clutter.

Skills expected in task plan frontmatter: `make-interfaces-feel-better`, `verify-before-complete`.

Do: Add a delete affordance on each comment row with adequate hit area and a centered SwiftUI `alert` confirmation before calling `await store.deleteComment(comment)`. Keep any deleting state local enough to avoid duplicate taps but do not remove comments outside the store/reload path. Include accessible labels that describe the action without inventing social metadata. Run final static checks that `TimelineRow.swift` and `TimelineView.swift` have not gained comment badges/counts/previews or comment search participation.

Failure Modes (Q5): Dependency `TimelineStore.deleteComment`; on error, rely on existing store error handling and do not dismiss/unwind the whole detail view; no timeout handling is needed beyond avoiding duplicate delete actions; malformed state such as a missing selected comment should cancel safely.

Load Profile (Q6): Per delete is one store mutation and reload; shared resources are existing outbox/local database; a long comment list should not add timeline cost because no timeline row/search wiring is introduced.

Negative Tests (Q7): Canceling confirmation must not call delete, confirming deletes only the selected comment, missing selection must be a no-op, and timeline files must not include new comment display/search code.
  - Files: `ios/PrivateMoments/Views/MomentDetailView.swift`, `ios/PrivateMoments/Views/MomentCommentsSection.swift`, `ios/PrivateMoments/Views/TimelineRow.swift`, `ios/PrivateMoments/Views/TimelineView.swift`
  - Verify: cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build && ! grep -R "comment\|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift

## Files Likely Touched

- ios/PrivateMoments/Views/MomentCommentsSection.swift
- ios/PrivateMomentsTests/MomentCommentUITests.swift
- ios/project.yml
- ios/PrivateMoments/Views/MomentDetailView.swift
- ios/PrivateMoments/Views/TimelineRow.swift
- ios/PrivateMoments/Views/TimelineView.swift
