---
estimated_steps: 27
estimated_files: 4
skills_used: []
---

# T02: Wire toolbar month/day menu to timeline scrolling

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

## Inputs

- `ios/PrivateMoments/Views/TimelineView.swift`
- `ios/PrivateMoments/Views/TimelineDateJumpModels.swift`
- `ios/PrivateMoments/Views/MomentDateFormatter.swift`
- `ios/PrivateMomentsTests/TimelineDateJumpModelsTests.swift`

## Expected Output

- `ios/PrivateMoments/Views/TimelineView.swift`
- `ios/PrivateMoments/Views/TimelineDateJumpModels.swift`

## Verification

cd ios && xcodegen generate && xcodebuild build -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO
