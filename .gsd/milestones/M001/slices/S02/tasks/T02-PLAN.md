---
estimated_steps: 28
estimated_files: 2
skills_used: []
---

# T02: Wrap UITextView as the shared plain-text editor

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

## Inputs

- `ios/PrivateMoments/Views/PlainTextListEditor.swift`
- `ios/PrivateMomentsListContinuationTests/PlainTextListContinuationTests.swift`
- `ios/project.yml`

## Expected Output

- `ios/PrivateMoments/Views/PlainTextListEditor.swift`

## Verification

cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMomentsListContinuationTests -destination 'platform=iOS Simulator,name=iPhone 16' test && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build

## Observability Impact

Maintains diagnostics through the helper test suite and compiler errors only; no runtime logging of private text should be introduced.
