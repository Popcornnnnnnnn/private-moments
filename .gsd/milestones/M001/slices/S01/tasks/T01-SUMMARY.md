---
id: T01
parent: S01
milestone: M001
key_files:
  - ios/project.yml
  - ios/PrivateMoments/Views/TimelineDateJumpModels.swift
  - ios/PrivateMoments/Views/MomentDateFormatter.swift
  - ios/PrivateMomentsTests/TimelineDateJumpModelsTests.swift
key_decisions:
  - Kept the date-jump helper pure and caller-driven so future UI work can pass `filteredItems` without adding database/media dependencies.
  - Used injected `now` and `calendar` in `dayJumpTitle` instead of wall-clock calendar helpers so tests and future date-jump menus are deterministic.
  - Changed the app target executable product name to `$(TARGET_NAME)` while relying on `CFBundleDisplayName` for the user-facing Moments name so hosted XCTest bundles can resolve the app executable.
duration: 
verification_result: mixed
completed_at: 2026-04-29T17:47:45.156Z
blocker_discovered: false
---

# T01: Added a tested pure date-jump grouping model and count-free day labels for timeline navigation.

**Added a tested pure date-jump grouping model and count-free day labels for timeline navigation.**

## What Happened

Added the `PrivateMomentsTests` XCTest target to `ios/project.yml`, included it in the shared `PrivateMoments` scheme test action, and adjusted the app target product name so XcodeGen's generated test host resolves to the actual app executable while the visible app name remains supplied by Info.plist. Implemented `TimelineDateJumpBuilder` with month and day group models that group only the passed visible `TimelineItem` values, use the caller-provided calendar for month/day boundaries, preserve newest-first ordering, expose month anchor item IDs, and set each day target to the newest visible item on that day. Added `MomentDateFormatter.dayJumpTitle(for:now:calendar:)` using injected `now`/`calendar` semantics for stable Today/Yesterday/Tomorrow/weekday/date labels. Added inline XCTest fixtures covering empty input, visible-only derivation, month/day grouping, newest-first target selection, and count/statistics-free labels.

## Verification

Ran the planned XcodeGen + XCTest command first; it could not execute because this machine has no `iPhone 16` simulator destination. Per the task failure-mode guidance, reran the full XcodeGen + XCTest flow against an installed `iPhone 17, OS=26.3.1` simulator. The available-simulator run passed: `TimelineDateJumpModelsTests` executed 5 tests with 0 failures and `xcodebuild` reported `** TEST SUCCEEDED **`.

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO` | 70 | ❌ fail | 62700ms |
| 2 | `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' CODE_SIGNING_ALLOWED=NO` | 0 | ✅ pass | 33200ms |

## Deviations

The exact planned `iPhone 16` simulator destination is not installed locally, so verification was rerun on the available `iPhone 17, OS=26.3.1` simulator after confirming the destination failure.

## Known Issues

No product issues found. Local simulator inventory lacks the planned `iPhone 16` destination.

## Files Created/Modified

- `ios/project.yml`
- `ios/PrivateMoments/Views/TimelineDateJumpModels.swift`
- `ios/PrivateMoments/Views/MomentDateFormatter.swift`
- `ios/PrivateMomentsTests/TimelineDateJumpModelsTests.swift`
