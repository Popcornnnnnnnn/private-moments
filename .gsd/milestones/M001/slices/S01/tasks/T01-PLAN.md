---
estimated_steps: 24
estimated_files: 5
skills_used: []
---

# T01: Extract date jump grouping and label contract

Expected `skills_used` frontmatter: `test`, `verify-before-complete`.

Create the pure model contract that S01 depends on before touching the toolbar UI. Add an iOS unit-test target if needed, then implement a small tracked grouping helper that turns already-visible `TimelineItem` values into month groups and day groups. The helper must use one `Calendar` consistently for month/day boundaries, preserve newest-first ordering, expose month anchor IDs plus first-item day target IDs, and never include counts in labels. Add day jump label formatting to `MomentDateFormatter` so the view does not embed ad hoc formatter logic.

Steps:
1. Update `ios/project.yml` to include a `PrivateMomentsTests` unit-test target that depends on the `PrivateMoments` app target and is included in the shared `PrivateMoments` scheme test action.
2. Add `ios/PrivateMoments/Views/TimelineDateJumpModels.swift` with internal `TimelineDateJumpBuilder`, `TimelineDateJumpMonthGroup`, and `TimelineDateJumpDayGroup` (or similarly named) types; the builder should accept `[TimelineItem]`, `now`, and `calendar` and return visible-only groups.
3. Add `MomentDateFormatter.dayJumpTitle(for:now:calendar:)` using life-feeling labels such as `Today`, `Yesterday`, `Tomorrow`, weekday names for nearby days if desired, and month/day or month/day/year for older dates; no count/statistics strings.
4. Add `ios/PrivateMomentsTests/TimelineDateJumpModelsTests.swift` with fixture `TimelineItem` values proving month grouping, day target selection, filtered visible-only derivation, stable newest-first first-item IDs, and count-free day labels.

Must-haves:
- Grouping reads only the `[TimelineItem]` passed to it, so callers can pass `filteredItems` and satisfy R005.
- Every day group has a scroll target equal to the first visible `TimelineItem.id` for that calendar day.
- Test fixtures are inline in the tracked test file; do not depend on ignored app containers, `.gsd/`, local databases, or photos.
- Tests fail if labels include digits-only count suffixes or words like `moment`/`moments`.

Failure Modes:
| Dependency | On error | On timeout | On malformed response |
|------------|----------|------------|------------------------|
| XcodeGen/Xcode test target generation | Fix `ios/project.yml` so the generated project includes `PrivateMomentsTests` | Document local tool timeout and still run the generic iOS build if tests cannot launch | N/A — local build config only |

Load Profile:
- **Shared resources**: In-memory visible timeline items only.
- **Per-operation cost**: O(n log n) grouping/sorting over visible items; acceptable for current local timeline UI.
- **10x breakpoint**: Menu size and SwiftUI rendering become the first UX constraint, not the helper itself. Do not add database queries or media loading.

Negative Tests:
- **Malformed inputs**: Empty item arrays return no groups.
- **Boundary conditions**: Multiple moments on the same day select the newest visible item as that day target; items hidden by the caller are absent.
- **Label regressions**: Day labels contain date language only and no counts/statistics wording.

## Inputs

- `ios/project.yml`
- `ios/PrivateMoments/Views/MomentDateFormatter.swift`
- `ios/PrivateMoments/Models/TimelinePost.swift`

## Expected Output

- `ios/project.yml`
- `ios/PrivateMoments/Views/TimelineDateJumpModels.swift`
- `ios/PrivateMoments/Views/MomentDateFormatter.swift`
- `ios/PrivateMomentsTests/TimelineDateJumpModelsTests.swift`

## Verification

cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
