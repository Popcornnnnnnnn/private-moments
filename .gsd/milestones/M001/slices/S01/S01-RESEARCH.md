# S01 Research — Lightweight Date Jump

## Summary

S01 should extend the existing toolbar calendar menu in `TimelineView` rather than adding a new surface. The current implementation already groups filtered, visible timeline data by month, renders invisible section anchors, and scrolls with `ScrollViewReader` through `TimelineMonthJump`.

The missing piece for R004/R005 is day-level navigation nested under month entries: days should be derived only from the same visible `filteredItems`, should not display counts, and should scroll to the first visible matching moment. This can be implemented as local helper structs/functions in `TimelineView.swift`, with any reusable date label formatting added to `MomentDateFormatter.swift`.

## Recommendation

Build a month-first menu with optional day submenu using the existing calendar toolbar item:

- Keep the toolbar calendar `Menu` in `ios/PrivateMoments/Views/TimelineView.swift`.
- Replace or extend `TimelineMonthGroup` so each month contains derived `TimelineDayGroup` values.
- Keep month entries selectable and make them scroll to the first moment in that month.
- Add day entries under each month, showing only dates that have visible moments.
- Give every row a stable scroll ID, probably the existing `TimelineItem.id`, and scroll day selections to the first item in that day.
- Avoid counts and archive-style labels. Labels should be date/life-feeling only, e.g. `Today`, `Yesterday`, `April 29`, or `April 29, 2025` depending on formatter choice.

Suggested shape:

```swift
private struct TimelineMonthGroup: Identifiable {
    let id: String
    let title: String
    let items: [TimelineItem]
    let days: [TimelineDayGroup]
}

private struct TimelineDayGroup: Identifiable {
    let id: String
    let title: String
    let firstItemID: String
    let items: [TimelineItem]
}

private struct TimelineDateJump: Equatable {
    let requestID = UUID()
    let targetID: String
}
```

A single jump request type is cleaner than separate month/day request state. Month requests use the month anchor ID; day requests use the first item ID.

## Implementation Landscape

### Key Files

- `ios/PrivateMoments/Views/TimelineView.swift`
  - Lines 11 and 97-105: current `monthJumpRequest` state and `ScrollViewReader` jump handling. This is the primary seam for generalizing from month-only to date-target jump.
  - Lines 35-76: `List` renders `groupedItems`, month anchors, and `TimelineRow` values. Add `.id(item.id)` to row content or a stable wrapper so day jump can target a concrete first moment.
  - Lines 126-136: existing toolbar calendar `Menu` lists `groupedItems` by month. Replace this with month-first menu entries plus nested day entries.
  - Lines 184-211: `groupedItems` currently derives month groups from `filteredItems`, sorts rows by `occurredAt DESC`, and creates `MomentDateFormatter.monthTitle` labels. Extend this grouping to derive day groups from each month’s already sorted items.
  - Lines 281-302: `monthAnchor(for:)` creates invisible month scroll anchors and emits floating month preferences. Keep this for month scrolling and floating month hint.
  - Lines 415-453: private helper types (`TimelineMonthGroup`, `MonthAnchorValue`, `TimelineMonthJump`) are already colocated. Add day group/jump helper types here.

- `ios/PrivateMoments/Views/MomentDateFormatter.swift`
  - Lines 3-47: `timelineLabel(for:)` contains life-feeling relative language for rows.
  - Lines 49-55: `monthTitle(for:)` is already the month label source. Add a `dayJumpTitle(for:now:calendar:)` or similarly named method here rather than embedding `DateFormatter` logic in the view.
  - Existing helpers `shortMonthDay`, `fullDate`, and `daysBetween` are private; day jump labels can reuse the same style internally without exposing low-level formatters.

- `ios/PrivateMoments/Models/TimelinePost.swift`
  - Lines 3-13: `TimelinePost.occurredAt` is the only date field needed for month/day grouping.
  - Lines 25-31: `TimelineItem.id` delegates to `post.id`, suitable as a stable row scroll target.

- `ios/PrivateMoments/Persistence/LocalDatabase+Records.swift`
  - Lines 5-14: `fetchPosts()` excludes `deletedAt` and orders by `occurredAt DESC`. The UI receives visible timeline order; no query/API change is needed.

- `ios/PrivateMoments/Persistence/LocalDatabase+Timeline.swift`
  - Lines 5-10: `fetchTimelineItems()` maps each post to media. No change needed.

### Build Order

1. Add day label formatting to `MomentDateFormatter.swift`.
   - Prefer labels that feel like browsing life moments, not archive records.
   - Avoid count text in formatter output.

2. Generalize the jump state in `TimelineView.swift`.
   - Rename `monthJumpRequest` to a more neutral date/jump request, or keep month state and add day state if minimizing diff.
   - Recommended: one request with `targetID`, where month target IDs are month anchors and day target IDs are `TimelineItem.id`.

3. Add stable row scroll IDs.
   - In the `ForEach(group.items)` row chain, attach `.id(item.id)` to the row or a wrapper around it.
   - Keep existing `monthAnchor(for:)` IDs unchanged so floating month behavior and month jump keep working.

4. Extend grouping.
   - Continue deriving from `filteredItems`, not `store.items`, so the menu only lists currently visible months/dates.
   - Use `Calendar.current` or an injected local `Calendar` consistently for day boundaries.
   - Month IDs may remain `yyyy-MM`; day IDs can be `yyyy-MM-dd`, but day scroll target should be `firstItemID` to avoid needing additional invisible day anchors.

5. Update the calendar menu.
   - Month-first structure: each month should remain visible as a top-level entry.
   - If a SwiftUI `Menu` inside a `Menu` is acceptable on target iOS, use nested day submenu under each month. If nested menus feel poor on device, use a month `Menu` label containing a direct `Jump to Month` button plus day buttons.
   - Disable the toolbar calendar menu when `groupedItems.isEmpty`, as today.

6. Add/adjust accessibility labels.
   - Keep toolbar label `Jump to month` or update to `Jump to date`.
   - Day entries should announce their date label only; do not announce counts.

### Verification Approach

- Build verification for iOS changes:

```bash
cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

- Manual/UI verification on simulator or real device:
  - Create or use moments across at least two months and multiple days in one month.
  - Open the existing toolbar calendar menu.
  - Confirm top-level month entries come only from visible timeline data.
  - Confirm day entries appear only for days that have visible moments.
  - Confirm selecting a month scrolls to the first visible moment in that month.
  - Confirm selecting a day scrolls to the first visible moment on that day.
  - Confirm no labels include counts or archive/statistics wording.
  - With search/filter active, confirm the menu reflects `filteredItems` rather than all stored moments.

## Constraints

- Main timeline must remain feed-first; do not add a calendar/archive tab or always-visible date picker.
- Date navigation should stay inside the existing toolbar calendar menu.
- The feature must use existing visible data only: no empty months/days and no all-history index if the current filter/search hides items.
- Labels must avoid counts and management language.
- No server, sync protocol, schema, or SQLite migration should be needed.

## Common Pitfalls

- Grouping by string-only `DateFormatter` with default timezone/calendar could drift from `Calendar.current` day boundaries. Use a single `Calendar` for day grouping and label generation.
- `ScrollViewReader.scrollTo` requires the target ID to exist in the rendered list. Month anchors already exist; day targets need explicit row IDs or day anchors.
- Nested SwiftUI `Menu` behavior can vary by platform/version and should be tested on device if possible.
- If the menu is derived from `store.items` instead of `filteredItems`, date jump will show dates the current timeline view does not show, violating the visible-data requirement.

## Open Risks

- Exact nested-menu interaction quality on iPhone needs device verification. If it feels awkward, keep the month-first menu but present each month as a submenu containing `This Month` plus day buttons.
- There are no dedicated Swift tests for formatter/grouping helpers today. If planner wants stronger coverage, extracting pure grouping helpers would make unit tests easier, but that is likely more ceremony than S01 needs.

## Skills Discovered

No installed SwiftUI-specific skill was available in the prompt. `npx skills find "SwiftUI"` found external candidates such as `avdlee/swiftui-agent-skill@swiftui-expert-skill`, `twostraws/swiftui-agent-skill@swiftui-pro`, and `affaan-m/everything-claude-code@swiftui-patterns`; none were installed or required for this research.