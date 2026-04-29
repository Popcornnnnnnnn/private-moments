# S01: Lightweight Date Jump

**Goal:** Add quiet, toolbar-only date navigation to the SwiftUI timeline: month targets remain selectable, days with visible moments are available under each month, and every selection scrolls to the first matching visible moment.
**Demo:** From the timeline toolbar calendar menu, the user can choose an existing month or a date with moments and the feed jumps to that point.

## Must-Haves

- ## Must-Haves
- R004: Date jump stays in the existing timeline toolbar calendar menu; no persistent calendar/archive surface is added.
- R004: Selecting a month scrolls to the first visible moment in that month; selecting a day scrolls to the first visible moment on that day.
- R005: Month and day choices are derived only from currently visible `filteredItems`, so search/filter state controls the menu contents.
- R005: Labels are life-feeling date labels only; no moment counts, archive statistics, or empty-date selection path appears.
- ## Threat Surface
- **Abuse**: Low. This is local SwiftUI navigation state only; there is no auth, network, persistence, parameter replay, or privilege boundary.
- **Data exposure**: Low but relevant to local privacy: the menu exposes dates for currently visible moments. It must not bypass the active filter/search and reveal dates hidden from the visible timeline.
- **Input trust**: Search text and filter state are trusted only as UI selectors. Date targets must be computed from already-rendered `TimelineItem` values, not from a broader database query.
- ## Requirement Impact
- **Requirements touched**: R004, R005.
- **Re-verify**: Toolbar-only entry point, month/day scroll behavior, visible-data derivation under search/filter, no counts or empty days in labels.
- **Decisions revisited**: D006 remains the controlling UX decision; do not broaden to a calendar tab, archive view, or count-heavy menu.
- ## Verification
- `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO`
- If the named simulator is unavailable, run `cd ios && xcodegen generate && xcodebuild build -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO` and document the simulator availability blocker.
- Manual/device UAT after implementation: with moments across at least two months and multiple days in one month, open the toolbar calendar menu, confirm month entries are top-level, day entries are nested/within each month, selecting month/day scrolls to the first matching visible item, labels contain no counts, and search/filter narrows available dates.

## Proof Level

- This slice proves: contract + UI integration. Pure grouping/label tests prove the visible-data/no-count boundary, and the iOS build proves the SwiftUI wiring compiles through the real app target.

## Integration Closure

Consumes existing `TimelineView.filteredItems`, month anchors, `ScrollViewReader`, `TimelineItem.id`, and `MomentDateFormatter.monthTitle`. Introduces a reusable date jump grouping model plus real toolbar menu wiring. After this slice, S01 is usable end-to-end in the app; remaining milestone work is independent S02 text input behavior.

## Verification

- No new logging or runtime diagnostics are required. The inspectable state for future agents is intentionally the in-memory date jump model derived from `filteredItems`; tests in `ios/PrivateMomentsTests/TimelineDateJumpModelsTests.swift` should make empty-date/count regressions obvious.

## Tasks

- [x] **T01: Extract date jump grouping and label contract** `est:1h`
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
  - Files: `ios/project.yml`, `ios/PrivateMoments/Views/TimelineDateJumpModels.swift`, `ios/PrivateMoments/Views/MomentDateFormatter.swift`, `ios/PrivateMomentsTests/TimelineDateJumpModelsTests.swift`, `ios/PrivateMoments/Models/TimelinePost.swift`
  - Verify: cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO

- [ ] **T02: Wire toolbar month/day menu to timeline scrolling** `est:1h`
  Expected `skills_used` frontmatter: `accessibility`, `test`, `verify-before-complete`.

Connect the date jump model to the real `TimelineView` toolbar. Keep the existing quiet calendar toolbar surface, but generalize the jump request from month-only to a target ID that can point either at an existing month anchor or at a visible row ID. Add stable row IDs to rendered `TimelineRow` values so day jumps have real `ScrollViewReader` targets.

Steps:
1. In `ios/PrivateMoments/Views/TimelineView.swift`, replace the private month-only grouping implementation with the helper from `TimelineDateJumpModels.swift`, passing `filteredItems` so menu contents respect search/filter state.
2. Replace `TimelineMonthJump`/`monthJumpRequest` with a neutral date jump request containing `targetID`; month buttons target the existing month anchor ID and day buttons target `TimelineDateJumpDayGroup.firstItemID`.
3. Add `.id(item.id)` to the rendered row or a stable wrapper around `TimelineRow` so `proxy.scrollTo(day.firstItemID, anchor: .top)` can find day targets.
4. Update the toolbar `Menu`: preserve top-level month navigation, add day choices inside each month (nested `Menu` with a direct `Jump to Month` button is acceptable), disable when no groups exist, and update the accessibility label to `Jump to date`.
5. Keep labels quiet: no counts, no archive/statistics wording, and no empty-date picker.

Must-haves:
- The only date navigation entry remains the toolbar calendar menu; do not add a tab, sheet, persistent date picker, or archive list.
- Month selection still scrolls to the month anchor and preserves floating month hint behavior.
- Day selection scrolls to the first visible moment for that day using a rendered row ID.
- Menu choices come from `filteredItems`, not `store.items`.
- Existing delete, favorite, search, filter, refresh, detail, and gallery interactions remain wired.

Failure Modes:
| Dependency | On error | On timeout | On malformed response |
|------------|----------|------------|------------------------|
| `ScrollViewReader` target lookup | Ensure month anchors keep `.id(group.id)` and rows add `.id(item.id)` before assigning jump requests | N/A — local UI animation only | N/A |
| SwiftUI nested `Menu` behavior | If nested menus compile but feel awkward on device, use a month submenu containing `Jump to Month` plus day buttons; do not introduce a new surface | N/A | N/A |

Load Profile:
- **Shared resources**: SwiftUI list/menu rendering over visible items.
- **Per-operation cost**: One grouping pass whenever view state changes; no network, DB, media, or sync work.
- **10x breakpoint**: Very large visible timelines could make the menu long. Keep groups derived from visible filtered items and avoid loading extra data.

Negative Tests:
- **Boundary conditions**: Empty `groupedItems` disables the calendar menu; search/filter hiding a day removes it from the menu.
- **Error paths**: Jump requests with missing targets should not crash; in normal flow, targets must exist because they come from rendered groups/items.
- **UI regressions**: Month entries remain available after adding day entries, and labels contain no counts.
  - Files: `ios/PrivateMoments/Views/TimelineView.swift`, `ios/PrivateMoments/Views/TimelineDateJumpModels.swift`, `ios/PrivateMoments/Views/MomentDateFormatter.swift`, `ios/PrivateMomentsTests/TimelineDateJumpModelsTests.swift`
  - Verify: cd ios && xcodegen generate && xcodebuild build -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO

## Files Likely Touched

- ios/project.yml
- ios/PrivateMoments/Views/TimelineDateJumpModels.swift
- ios/PrivateMoments/Views/MomentDateFormatter.swift
- ios/PrivateMomentsTests/TimelineDateJumpModelsTests.swift
- ios/PrivateMoments/Models/TimelinePost.swift
- ios/PrivateMoments/Views/TimelineView.swift
