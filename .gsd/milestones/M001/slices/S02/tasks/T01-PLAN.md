---
estimated_steps: 28
estimated_files: 3
skills_used: []
---

# T01: Extract list-continuation rules with XCTest coverage

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

## Inputs

- `ios/project.yml`
- `ios/PrivateMoments/Views/ComposerView.swift`
- `ios/PrivateMoments/Views/MomentDetailView.swift`

## Expected Output

- `ios/PrivateMoments/Views/PlainTextListEditor.swift`
- `ios/PrivateMomentsListContinuationTests/PlainTextListContinuationTests.swift`
- `ios/project.yml`

## Verification

cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMomentsListContinuationTests -destination 'platform=iOS Simulator,name=iPhone 16' test

## Observability Impact

Adds deterministic XCTest diagnostics for every supported list-continuation rule and important negative case. No runtime text logging is allowed because moment content is private.
