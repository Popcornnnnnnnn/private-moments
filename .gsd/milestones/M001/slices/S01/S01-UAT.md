# S01: Lightweight Date Jump — UAT

**Milestone:** M001
**Written:** 2026-04-29T17:53:03.343Z

# S01: Lightweight Date Jump — UAT

**Milestone:** M001
**Written:** 2026-04-30

## UAT Type

- UAT mode: mixed
- Why this mode is sufficient: Unit tests and builds prove the model contract and SwiftUI compile-time wiring; human/device UAT is still the right final check for scroll feel and nested menu ergonomics because toolbar menu interaction is visual/tactile.

## Preconditions

- Install or run the iOS app with a local timeline containing visible moments across at least two months.
- Include at least one month with moments on two different days.
- Ensure the timeline is not empty and can be scrolled.
- Optional for filter checks: have searchable text that hides at least one month or day when the search field is active.

## Smoke Test

Open the timeline toolbar calendar control. It should be labeled as date jump navigation, show existing months only, and keep all date navigation inside this toolbar menu rather than opening a persistent calendar/archive screen.

## Test Cases

### 1. Jump to an existing month

1. Open Moments to the main timeline.
2. Tap the toolbar calendar/date jump menu.
3. Choose a month that is not currently at the top of the timeline.
4. Tap `Jump to Month` for that month.
5. **Expected:** The feed scrolls to the first visible moment in that month. The floating month hint behavior remains consistent with normal timeline scrolling. No new tab, sheet, archive list, or persistent calendar appears.

### 2. Jump to a day within a month

1. Open the toolbar calendar/date jump menu.
2. Open a month submenu that contains multiple day choices.
3. Choose one day label.
4. **Expected:** The feed scrolls to the first visible moment for that calendar day. If multiple visible moments exist on that day, the target is the newest visible one in the current timeline ordering.

### 3. Labels stay life-feeling and count-free

1. Open the toolbar calendar/date jump menu.
2. Inspect month labels and day labels.
3. **Expected:** Labels use month/day date language such as month titles, Today, Yesterday, weekday, or month/day/year style labels. They do not include moment counts, words like `moment` or `moments`, archive statistics, or empty-date placeholders.

### 4. Search/filter limits available dates

1. Apply a search or filter that hides some timeline moments.
2. Open the toolbar calendar/date jump menu again.
3. **Expected:** Only months and days represented by the currently visible filtered timeline items appear. Dates hidden by the search/filter do not remain selectable.

## Edge Cases

### Empty visible timeline

1. Apply a search/filter that produces no visible moments, or test with an empty local timeline.
2. Look at the toolbar calendar/date jump control.
3. **Expected:** The date jump menu is disabled or offers no selectable date targets. There is no empty-date picker and no crash.

### Missing target resilience

1. Open a date jump menu, then change filter/search state before using an older mental target if possible.
2. **Expected:** Normal UI flow derives targets from currently rendered groups, so selections should resolve. If a target no longer exists due to state change, the app should not crash.

## Failure Signals

- `xcodegen generate` cannot find a project spec from the verification working directory.
- Xcode build fails for the `PrivateMoments` scheme.
- The toolbar calendar opens a persistent calendar/archive screen instead of a menu.
- Month/day labels show counts or statistics.
- Search/filter-hidden dates still appear in the menu.
- Day selection does nothing, jumps to the wrong month/day, or crashes.

## Not Proven By This UAT

- Long-timeline menu ergonomics at very large scale.
- Real-device tactile feel of nested SwiftUI menus in every iOS version.
- S02 plain-text list continuation behavior, which is independent milestone work.

## Notes for Tester

The available simulator on the build host was `iPhone 17`; the originally planned `iPhone 16` simulator was not installed. The important product gut check is whether the menu feels quiet and like returning to a period of life rather than managing an archive.
