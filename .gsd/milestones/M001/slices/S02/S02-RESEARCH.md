# S02 Research — Plain-Text List Continuation

## Summary

S02 should implement list continuation at the text-input layer only. The feature boundary is already captured in project memory and decisions: Moments remains a private expression space, not a Markdown editor, and list support is limited to plain text continuation for `- `, `• `, and numbered prefixes.

The relevant UI surface is small:

- `ComposerView` uses a SwiftUI `TextEditor(text: $text)` for New Moment text.
- `EditMomentView` inside `MomentDetailView` uses a second SwiftUI `TextEditor(text: $text)` for Edit Moment text.
- Both flows persist ordinary `String` drafts and save trimmed plain text through existing `TimelineStore` create/update methods.
- `ios/project.yml` includes the whole `PrivateMoments` source directory, so a new Swift file under `ios/PrivateMoments/Views/` will be picked up after `xcodegen generate`.

SwiftUI `TextEditor` does not expose a clean, stable `Return` interception hook or selection control. For this slice, the smallest reliable seam is a shared `UIViewRepresentable` wrapper around `UITextView` that preserves a `Binding<String>` and intercepts newline insertion in `textView(_:shouldChangeTextIn:replacementText:)`.

## Recommendation

Add a shared plain-text editor component, likely `ios/PrivateMoments/Views/PlainTextListEditor.swift`, and replace both `TextEditor` instances with it:

```swift
PlainTextListEditor(text: $text)
    .frame(minHeight: 140)
```

and:

```swift
PlainTextListEditor(text: $text)
    .frame(minHeight: 160)
    .scrollContentBackground(.hidden) // only if the component exposes/needs equivalent styling
```

The component should:

1. Wrap `UITextView` via `UIViewRepresentable`.
2. Bind `uiView.text` back to SwiftUI state on every edit.
3. Intercept only `replacementText == "\n"`.
4. Determine the current line from the selected range.
5. If the current line matches a supported list prefix and contains non-empty item text, insert `\n` plus the next prefix:
   - `- item` → `\n- `
   - `• item` → `\n• `
   - `1. item` → `\n2. `
6. If the current line is an empty generated list item, replace the whole current list-marker line with a plain newline/paragraph exit so saved content does not retain a dangling `- `, `• `, or `2. `.
7. Return `false` only when it has manually applied an edit; otherwise return `true` to preserve native text behavior.

Keep all saved content as ordinary text. Do not add Markdown parsing, rich text attributes, preview rendering, link detection, headings, bold, quote behavior, or server/schema changes.

## Implementation Landscape

### Key Files

1. `ios/PrivateMoments/Views/ComposerView.swift` (lines 1-145)
   - New Moment screen.
   - Imports `PhotosUI`, `SwiftUI`, and `UIKit`.
   - Current editor seam is lines 19-21:

   ```swift
   TextEditor(text: $text)
       .frame(minHeight: 140)
   ```

   - Draft persistence already reacts to `text` changes at lines 91-93:

   ```swift
   .onChange(of: text) { _, value in
       ComposerDraftStore.save(text: value, occurredAt: occurredAt)
   }
   ```

   - Publishing passes the same plain `String` to the store at line 123.

2. `ios/PrivateMoments/Views/MomentDetailView.swift` (lines 136-242)
   - Contains `EditMomentView`.
   - Current editor seam is lines 241-243:

   ```swift
   TextEditor(text: $text)
       .frame(minHeight: 160)
       .scrollContentBackground(.hidden)
   ```

   - Draft persistence already reacts to `text` changes at lines 199-202.
   - Save snapshots the plain text string and passes it to `store.updatePost` at lines 383-390.

3. `ios/PrivateMoments/Persistence/TimelineStore+Mutations.swift` (lines 1-44, 141-195)
   - `createPost` trims leading/trailing whitespace/newlines and stores/syncs plain text.
   - `updatePost` also trims leading/trailing whitespace/newlines and stores/syncs plain text.
   - No server, database, sync, or API changes are needed for S02.

4. `ios/PrivateMoments/Views/ZoomableLocalImage.swift` (lines 1-90)
   - Existing local example of `UIViewRepresentable` structure and coordinator pattern.
   - Useful as style precedent, but do not copy image/scroll behavior.

5. `ios/project.yml` (lines 1-32)
   - XcodeGen target includes `sources: - PrivateMoments`.
   - A new source file under `ios/PrivateMoments/Views/` should be included by regeneration; no manual project file edit should be needed.

### Build Order

1. Create a small shared implementation file:
   - Suggested path: `ios/PrivateMoments/Views/PlainTextListEditor.swift`.
   - Suggested structure:
     - `struct PlainTextListEditor: UIViewRepresentable`
     - `final class Coordinator: NSObject, UITextViewDelegate`
     - a tiny pure helper, e.g. `PlainTextListContinuation`, for prefix detection and edit calculation.

2. Implement the list-rule helper before wiring UI.
   - Match only line-start prefixes:
     - dash: `^-\s`
     - bullet: `^•\s`
     - numbered: `^(\d+)\.\s`
   - Treat item text as `line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)`.
   - Continue only when item text is non-empty.
   - Exit only when the line is exactly/semantically an empty marker, e.g. `- `, `• `, `2. `, possibly with trailing spaces.
   - For numbered lists, parse the integer and increment by one; if parsing fails or overflows, fall back to normal newline.

3. Wire `UITextViewDelegate` interception.
   - In `shouldChangeTextIn`, if replacement is not `"\n"`, allow native editing.
   - Convert the `NSRange` selected range into a Swift string range carefully, or operate with `NSString` for line boundaries to avoid UTF-16 index mistakes.
   - After manual replacement, update both `textView.text` and the SwiftUI binding, then set `selectedRange` after the inserted prefix.

4. Replace `TextEditor` in `ComposerView` and `EditMomentView` with the shared component.
   - Preserve min heights.
   - Preserve visual fit inside `Form` and the custom edit card.
   - Match default body font and clear background where needed:
     - `textView.font = UIFont.preferredFont(forTextStyle: .body)`
     - `textView.adjustsFontForContentSizeCategory = true`
     - `textView.backgroundColor = .clear`
     - likely `textView.isScrollEnabled = true`

5. Keep persistence untouched.
   - Existing `onChange` handlers should continue saving drafts because the binding changes.
   - Existing create/update methods already store plain strings.

### Verification Approach

1. Generate and build iOS project:

```bash
cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

2. Manual simulator or real-device checks in New Moment:
   - Type `- item`, press Return → editor shows next line `- ` with cursor after the space.
   - Press Return immediately on that empty `- ` line → list exits and dangling marker is removed.
   - Type `• item`, press Return → editor shows next line `• `.
   - Type `1. item`, press Return → editor shows next line `2. `.
   - Save/publish and verify detail view displays the exact plain text, not rendered Markdown.

3. Repeat the same checks in Edit Moment.
   - Confirm edit draft autosave still updates while typing.
   - Confirm saving persists ordinary text through the existing update flow.

4. Regression checks:
   - Return in normal paragraph text inserts a normal newline.
   - Return in the middle of non-list text is unchanged.
   - Existing image picking/camera buttons remain unaffected.
   - Dynamic Type should remain acceptable because the wrapper should use preferred body font.

## Constraints

- Do not introduce Markdown rendering or rich text semantics.
- Do not change schema, sync API, server routes, or storage.
- Keep timeline display simple; `MomentDetailView` should continue using `Text(item.post.text)` as plain selectable text.
- The implementation should be shared between Composer and Edit to avoid behavior drift.

## Common Pitfalls

- Using SwiftUI `TextEditor.onChange` to post-process newlines can move the cursor unpredictably and may be unable to distinguish user Return from paste or programmatic text changes.
- `UITextViewDelegate` ranges are `NSRange`/UTF-16 based; careless Swift `String.Index` conversion can break with emoji or non-ASCII text.
- Empty-item exit should remove the generated marker, not leave a dangling `- `, `• `, or `2. ` in saved content.
- The edit screen currently uses `.scrollContentBackground(.hidden)` on `TextEditor`; a UIKit wrapper will need equivalent clear background/insets tuning rather than relying on that modifier.
- `TimelineStore` trims leading/trailing whitespace on final save. That is existing behavior and should not be changed for this slice.

## Open Risks

- Visual parity with SwiftUI `TextEditor` inside both a `Form` and a custom rounded edit card may need small UIKit inset/background tuning.
- There are no existing iOS test targets. If implementation extracts a pure helper, it can be manually checked now and unit-tested later if an iOS test target is added.
- If a minimal `UITextView` bridge grows beyond a small component plus helper, defer rather than restructuring Composer/Edit around a custom editor stack.

## Skills Discovered

- Installed prompt skills do not include a SwiftUI/UIKit text-input skill.
- `npx skills find "SwiftUI"` returned external SwiftUI skills, including `avdlee/swiftui-agent-skill@swiftui-expert-skill` and `twostraws/swiftui-agent-skill@swiftui-pro`; not installed.
- `npx skills find "UITextView"` returned no skills.
