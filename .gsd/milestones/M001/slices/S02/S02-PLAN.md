# S02: Plain-Text List Continuation

**Goal:** Add shared plain-text list continuation to the iOS New Moment and Edit Moment text inputs while keeping saved/rendered content as ordinary plain text.
**Demo:** When feasible, typing a bullet or numbered list in New Moment or Edit Moment continues the list on Return and exits on an empty list item.

## Must-Haves

- ## Must-Haves
- New Moment and Edit Moment use one shared list-continuation input path for `- `, `• `, and numbered prefixes.
- Pressing Return after a non-empty dash, bullet, or numbered item inserts the next plain-text list prefix; numbered items auto-increment.
- Pressing Return on an empty generated list item exits the list and removes the dangling marker.
- Normal paragraph Return behavior remains native and unchanged.
- Saved posts remain plain text; no Markdown/rich-text rendering, headings, bold, quotes, link previews, schema changes, server changes, or sync changes are introduced.
- ## Threat Surface
- **Abuse**: User-entered text is transformed locally before existing draft/save paths consume it. Main abuse risk is unexpected transformation or cursor movement causing accidental content changes; there is no privilege or network boundary change.
- **Data exposure**: Moment text is personal/private data already handled by the app. This slice must not add logging, telemetry, previews, external services, or new persistence locations for typed text.
- **Input trust**: Text typed/pasted into UIKit `UITextView` is untrusted user input that later reaches the existing local database and sync queue as plain text. Unicode/emoji and malformed numbered prefixes must not corrupt the string or crash range handling.
- ## Requirement Impact
- **Requirements touched**: R006, R007.
- **Re-verify**: New Moment list continuation, Edit Moment list continuation, empty-item exit, numbered increment, plain paragraph newlines, and plain-text timeline/detail rendering.
- **Decisions revisited**: D007 remains in force; do not expand scope into Markdown or rich text. D005 remains in force; keep this as lightweight expression assistance, not a writing-editor feature.
- ## Proof Level
- This slice proves: integration.
- Real runtime required: yes, via iOS generic build and shared UIKit wrapper compilation.
- Human/UAT required: yes for final tactile cursor/list behavior in New Moment and Edit Moment on simulator or device because UIKit text selection behavior is difficult to fully prove with the current project test harness.
- ## Verification
- `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMomentsListContinuationTests -destination 'platform=iOS Simulator,name=iPhone 16' test` runs XCTest assertions for dash, bullet, numbered increment, empty-item exit, normal newline fallback, emoji/Unicode range safety, and non-list behavior.
- `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build` proves the app target still compiles with the shared editor wired into both screens.
- Manual UAT on simulator or real device: in both New Moment and Edit Moment, type `- item`, `• item`, and `1. item`, press Return to see continuation, press Return on an empty generated item to exit, then save/publish and confirm detail/timeline text remains literal plain text.
- ## Observability / Diagnostics
- Runtime signals: No logs or telemetry should be added because typed moment text is private; diagnostics are through deterministic helper tests and visible editor state only.
- Inspection surfaces: XCTest file `ios/PrivateMomentsListContinuationTests/PlainTextListContinuationTests.swift`, app build output, and manual UI state in New Moment/Edit Moment.
- Failure visibility: Test failures identify the list rule or boundary case; build failures identify SwiftUI/UIKit integration issues; manual UAT catches cursor/selection regressions.
- Redaction constraints: Do not print, log, or persist typed private text outside existing draft/save paths.
- ## Integration Closure
- Upstream surfaces consumed: `ios/PrivateMoments/Views/ComposerView.swift`, `ios/PrivateMoments/Views/MomentDetailView.swift`, `ios/PrivateMoments/Persistence/TimelineStore+Mutations.swift`, and `ios/project.yml`.
- New wiring introduced in this slice: a shared `PlainTextListEditor`/list-continuation helper under `ios/PrivateMoments/Views/`, an iOS XCTest target in `ios/project.yml`, and replacements for both existing SwiftUI `TextEditor` seams.
- What remains before the milestone is truly usable end-to-end: nothing beyond the planned manual UAT after tests/build pass.

## Proof Level

- This slice proves: integration; XCTest plus app build, with manual UAT for cursor behavior

## Integration Closure

The slice consumes the existing Composer/Edit draft and save flows, introduces a shared `PlainTextListEditor` UIKit bridge, and wires it into both text-input surfaces without changing persistence, sync, server, schema, or plain-text rendering.

## Verification

- No runtime logging should be added because moment text is private. Diagnostics are provided by deterministic XCTest coverage in `ios/PrivateMomentsListContinuationTests/PlainTextListContinuationTests.swift`, compiler/build output, and manual UI state in New Moment/Edit Moment.

## Tasks

- [x] **T01: Extract list-continuation rules with XCTest coverage** `est:1h 15m`
  Executor skills: `tdd`, `test`, `verify-before-complete`.

Why: R006 depends on precise list rules, and the riskiest part is transforming text around a UIKit selection without corrupting Unicode or expanding into Markdown semantics. This task establishes a small pure helper and an iOS XCTest target before UI wiring, so later work has executable proof for continuation, exit, and fallback behavior.

Do:
1. Add a test target to `ios/project.yml` named `PrivateMomentsListContinuationTests` that can import the app module with `@testable import PrivateMoments`.
2. Create `ios/PrivateMoments/Views/PlainTextListEditor.swift` with a pure helper type, e.g. `PlainTextListContinuation`, whose public/internal testable API accepts a plain `String`, an `NSRange` selection/replacement context, and returns either no custom edit or a replacement text plus cursor position.
3. Match only line-start plain-text prefixes: `- `, `• `, and `N. ` where `N` is a base-10 integer; continue only when item text after the prefix is non-empty after trimming spaces.
4. For empty generated marker lines such as `- `, `• `, or `2. ` with optional trailing spaces, return an edit that removes the marker and leaves a normal paragraph break/list exit; do not leave dangling marker text.
5. Add `ios/PrivateMomentsListContinuationTests/PlainTextListContinuationTests.swift` covering dash continuation, bullet continuation, numbered increment, empty dash/bullet/numbered exit, normal paragraph newline fallback, middle-of-non-list fallback, and emoji/Unicode text around the selection.

Must-haves:
- Helper operates safely with `NSRange`/UTF-16 selection inputs from `UITextView`.
- Helper has no Markdown rendering, attributed text, schema, server, sync, or persistence behavior.
- Test target and tests are tracked under `ios/` and do not depend on `.gsd/` or other ignored planning artifacts.

Failure Modes:
| Dependency | On error | On timeout | On malformed response |
|------------|----------|------------|------------------------|
| XcodeGen/project generation | Fix `ios/project.yml` target/scheme wiring before implementing UI integration | N/A for local generation | Treat invalid YAML/project settings as a planning blocker and correct them in this task |
| XCTest simulator destination | If `iPhone 16` is unavailable, use an available iOS simulator from `xcrun simctl list devices available` and document the command used | If simulator boot/test hangs, fall back to build-for-testing plus app build and note manual test gap | N/A |

Load Profile:
- **Shared resources**: Local text buffer only; no database, network, or files at runtime.
- **Per-operation cost**: One current-line lookup and small string replacement per Return keypress.
- **10x breakpoint**: Very long individual lines could make string scanning noticeable; keep helper limited to the current line, not the full document beyond line-boundary discovery.

Negative Tests:
- **Malformed inputs**: Empty string, cursor at start/end, invalid or out-of-bounds `NSRange`, lines without prefixes, and numbered prefixes that cannot safely increment.
- **Error paths**: Invalid range should return no custom edit rather than crash.
- **Boundary conditions**: Emoji/non-ASCII before the cursor, empty marker with trailing spaces, multi-digit numbered prefix, and Return in normal text.

Verify:
- `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMomentsListContinuationTests -destination 'platform=iOS Simulator,name=iPhone 16' test`

Done when: The helper and test target exist, all list-rule tests pass, and the app has not yet changed user-facing editor wiring beyond adding the shared helper file.
  - Files: `ios/PrivateMoments/Views/PlainTextListEditor.swift`, `ios/PrivateMomentsListContinuationTests/PlainTextListContinuationTests.swift`, `ios/project.yml`
  - Verify: cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMomentsListContinuationTests -destination 'platform=iOS Simulator,name=iPhone 16' test

- [ ] **T02: Wrap UITextView as the shared plain-text editor** `est:1h`
  Executor skills: `test`, `verify-before-complete`.

Why: SwiftUI `TextEditor` does not provide reliable Return interception or cursor control. This task turns the tested helper into a reusable `UIViewRepresentable` that preserves `Binding<String>`, Dynamic Type, clear background styling, and native text behavior outside list-continuation cases.

Do:
1. In `ios/PrivateMoments/Views/PlainTextListEditor.swift`, add `struct PlainTextListEditor: UIViewRepresentable` wrapping `UITextView` with a `Coordinator: NSObject, UITextViewDelegate`.
2. Configure the text view for plain text only: preferred body font, Dynamic Type adjustment, clear background, reasonable text container insets, scroll enabled, selectable/editable, no attributed rendering feature, and no link/Markdown preview work.
3. In `textView(_:shouldChangeTextIn:replacementText:)`, intercept only `replacementText == "\n"`; call the helper from T01; manually apply custom edits by updating `textView.text`, the SwiftUI binding, and `selectedRange`, returning `false` only for handled list edits.
4. Allow native editing for all non-Return edits and for Return cases the helper declines; keep `textViewDidChange` syncing the binding for normal typing/paste/deletion.
5. Avoid feedback loops in `updateUIView` by only assigning `uiView.text` when it differs from the binding.

Must-haves:
- The wrapper remains a plain text input component; it must not add rendering, preview, parsing, persistence, or network behavior.
- Binding updates continue on every edit so existing Composer/Edit draft autosave can observe changes once wired.
- Cursor is placed after the inserted prefix for continuation and at the correct paragraph exit position for empty-item exit.

Failure Modes:
| Dependency | On error | On timeout | On malformed response |
|------------|----------|------------|------------------------|
| UIKit delegate callbacks | If callbacks do not fire, verify `textView.delegate = context.coordinator` in `makeUIView` and no SwiftUI wrapper replacement drops the delegate | N/A | Invalid `NSRange` from delegate should be declined by helper rather than crashing |

Load Profile:
- **Shared resources**: UIKit text view state and SwiftUI binding.
- **Per-operation cost**: Constant-to-current-line string work per Return; normal typing uses native path.
- **10x breakpoint**: Reassigning whole text on every `updateUIView` could cause cursor jumps; avoid by checking text equality before assignment.

Negative Tests:
- **Malformed inputs**: Delegate receives invalid ranges or replacement text other than newline.
- **Error paths**: Helper returns nil/no edit; delegate must return true and preserve native behavior.
- **Boundary conditions**: Unicode text and multi-line strings already covered by helper tests; manually reason through cursor placement after custom replacement.

Verify:
- `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMomentsListContinuationTests -destination 'platform=iOS Simulator,name=iPhone 16' test`
- `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Done when: `PlainTextListEditor` compiles, helper tests still pass, and the app target builds with the shared wrapper available for both editor surfaces.
  - Files: `ios/PrivateMoments/Views/PlainTextListEditor.swift`, `ios/PrivateMomentsListContinuationTests/PlainTextListContinuationTests.swift`
  - Verify: cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMomentsListContinuationTests -destination 'platform=iOS Simulator,name=iPhone 16' test && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build

- [ ] **T03: Wire shared editor into New Moment and Edit Moment** `est:45m`
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
  - Files: `ios/PrivateMoments/Views/ComposerView.swift`, `ios/PrivateMoments/Views/MomentDetailView.swift`, `ios/PrivateMoments/Views/PlainTextListEditor.swift`, `ios/PrivateMomentsListContinuationTests/PlainTextListContinuationTests.swift`
  - Verify: cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMomentsListContinuationTests -destination 'platform=iOS Simulator,name=iPhone 16' test && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build

## Files Likely Touched

- ios/PrivateMoments/Views/PlainTextListEditor.swift
- ios/PrivateMomentsListContinuationTests/PlainTextListContinuationTests.swift
- ios/project.yml
- ios/PrivateMoments/Views/ComposerView.swift
- ios/PrivateMoments/Views/MomentDetailView.swift
