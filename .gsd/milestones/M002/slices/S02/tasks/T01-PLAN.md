---
estimated_steps: 6
estimated_files: 3
skills_used: []
---

# T01: Add comment UI helper tests and plain-text policy

Why: The slice needs executable proof for the comment UI boundary before wiring SwiftUI controls, especially whitespace-only rejection and plain-text/single-level constraints from R010.

Skills expected in task plan frontmatter: `test`, `verify-before-complete`.

Do: Create a small testable helper/policy in `MomentCommentsSection.swift` (for example `MomentCommentDraftPolicy`) that centralizes draft trimming and submit enablement without rendering or interpreting Markdown. Add `MomentCommentUITests.swift` with real XCTest assertions for whitespace-only rejection, trimming of leading/trailing whitespace, preservation of internal newlines/plain text, and no helper behavior that creates replies/rich-text semantics. Keep the helper independent of SQLite/network so the tests are deterministic.

Failure Modes (Q5): Dependency `XCTest/XcodeGen`; on error, fix project/test target wiring without changing app behavior; on unavailable simulator, record the simulator limitation and rely on generic build in later tasks; malformed draft inputs should produce disabled submit or trimmed plain text, never crashes.

Load Profile (Q6): Per-operation cost is trivial string trimming; 10x comment draft size is bounded by in-memory string operations and should not introduce shared resources.

Negative Tests (Q7): Empty string, whitespace/newline-only strings, strings with internal newlines/bullets, and strings containing Markdown-like characters should all remain plain strings with only submit eligibility affected.

## Inputs

- `ios/PrivateMoments/Views/MomentDetailView.swift`
- `ios/PrivateMoments/Models/TimelinePost.swift`
- `ios/PrivateMoments/Persistence/TimelineStore+Mutations.swift`
- `ios/project.yml`

## Expected Output

- `ios/PrivateMoments/Views/MomentCommentsSection.swift`
- `ios/PrivateMomentsTests/MomentCommentUITests.swift`

## Verification

cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16'

## Observability Impact

No runtime diagnostics are added in this task. The helper makes UI failure behavior inspectable in tests by separating draft validity from SwiftUI rendering.
