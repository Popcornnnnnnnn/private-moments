---
estimated_steps: 30
estimated_files: 4
skills_used: []
---

# T03: Wire shared editor into New Moment and Edit Moment

Executor skills: `test`, `verify-before-complete`.

Why: The slice demo is only true when both New Moment and Edit Moment use the shared editor path. This task replaces the two `TextEditor` seams while preserving layout, draft autosave, save/update flows, and plain-text rendering boundaries.

Do:
1. In `ios/PrivateMoments/Views/ComposerView.swift`, replace `TextEditor(text: $text).frame(minHeight: 140)` with `PlainTextListEditor(text: $text).frame(minHeight: 140)` and preserve existing `.onChange` draft save behavior unchanged.
2. In `ios/PrivateMoments/Views/MomentDetailView.swift`, replace the edit screen `TextEditor(text: $text)` with `PlainTextListEditor(text: $text).frame(minHeight: 160)`; remove `.scrollContentBackground(.hidden)` if it no longer applies, relying on the wrapper's clear background instead.
3. Confirm no changes are made to `TimelineStore+Mutations`, API contracts, database schema, sync payloads, or `Text(item.post.text)` rendering.
4. Run the planned XCTest and app build commands. If simulator tests cannot run due to destination availability, use an available simulator and record the exact substitute command in the completion summary.
5. Perform or document manual UAT for both surfaces: dash, bullet, numbered continuation, empty-item exit, normal paragraph newline, save/publish, and detail/timeline plain literal rendering.

Must-haves:
- Both New Moment and Edit Moment share the same `PlainTextListEditor` component.
- Existing draft autosave and create/update save calls continue receiving plain `String` values.
- R007 is preserved: no Markdown/rich text formatting, headings, bold, quote behavior, link previews, server/schema/sync/storage changes.

Failure Modes:
| Dependency | On error | On timeout | On malformed response |
|------------|----------|------------|------------------------|
| Existing draft/save flows | If drafts stop updating, verify binding changes from `PlainTextListEditor` trigger existing `.onChange` handlers | N/A | N/A |
| Visual fit inside Form/edit card | If background/insets look wrong, tune only `PlainTextListEditor` UIKit styling; do not fork behavior per screen unless absolutely necessary | N/A | N/A |

Load Profile:
- **Shared resources**: SwiftUI view state and local draft persistence already present in the app.
- **Per-operation cost**: Same text binding/save observation behavior as existing editor plus small Return-only helper work.
- **10x breakpoint**: Frequent binding changes should not add new disk writes beyond existing draft autosave behavior; avoid extra timers/logs/persistence.

Negative Tests:
- **Malformed inputs**: Pasted multi-line text should not be post-processed as if Return was pressed unless UIKit reports an actual newline replacement path that the helper safely declines or handles.
- **Error paths**: App build should fail fast on unsupported modifiers/imports; fix by keeping wrapper API minimal.
- **Boundary conditions**: Empty editor, normal paragraphs, Unicode/emoji text, and numbered list increment from multi-digit numbers.

Verify:
- `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMomentsListContinuationTests -destination 'platform=iOS Simulator,name=iPhone 16' test`
- `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- Manual UAT on simulator or real device for New Moment and Edit Moment list behavior and plain-text display.

Done when: Both user-facing editors use the shared component, tests and app build pass, and the only user-visible change is plain-text list continuation/exit behavior.

## Inputs

- `ios/PrivateMoments/Views/ComposerView.swift`
- `ios/PrivateMoments/Views/MomentDetailView.swift`
- `ios/PrivateMoments/Views/PlainTextListEditor.swift`
- `ios/PrivateMomentsListContinuationTests/PlainTextListContinuationTests.swift`
- `ios/project.yml`

## Expected Output

- `ios/PrivateMoments/Views/ComposerView.swift`
- `ios/PrivateMoments/Views/MomentDetailView.swift`

## Verification

cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMomentsListContinuationTests -destination 'platform=iOS Simulator,name=iPhone 16' test && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build

## Observability Impact

Keeps failure diagnosis limited to UI-visible state, XCTest results, and build output. Do not add text logging or telemetry because moment content is private.
