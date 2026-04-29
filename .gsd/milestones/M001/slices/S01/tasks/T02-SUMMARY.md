---
id: T02
parent: S01
milestone: M001
key_files:
  - ios/PrivateMoments/Views/TimelineView.swift
key_decisions:
  - Kept day navigation inside nested month submenus under the existing toolbar calendar control, with a `Jump to Month` action to preserve top-level month navigation without introducing a new surface.
duration: 
verification_result: passed
completed_at: 2026-04-29T17:50:29.642Z
blocker_discovered: false
---

# T02: Wired the timeline toolbar calendar menu to month and day scroll targets derived from visible items.

**Wired the timeline toolbar calendar menu to month and day scroll targets derived from visible items.**

## What Happened

Replaced TimelineView's private month-only grouping with TimelineDateJumpBuilder.groups(from: filteredItems), preserving the visible-only search/filter boundary. Generalized the scroll request from a month-specific value to TimelineDateJumpRequest(targetID:), kept month anchors identified by their date-jump month IDs, and added `.id(item.id)` to each rendered TimelineRow so day menu buttons can scroll directly to the first visible row for that day. Updated the existing toolbar calendar menu only: months remain top-level entries as submenus, each submenu includes a quiet `Jump to Month` action plus count-free day labels, and the calendar control now exposes the accessibility label `Jump to date`. No new persistent calendar, archive view, logging, network, database, or media behavior was added.

## Verification

Ran the planned generic iOS build from the `ios/` directory; `xcodegen generate` created `ios/PrivateMoments.xcodeproj` and `xcodebuild build` reported `** BUILD SUCCEEDED **`. Also ran the slice-level XCTest flow on an available `iPhone 17` simulator because the plan's named `iPhone 16` simulator is not installed locally; `TimelineDateJumpModelsTests` executed 5 tests with 0 failures and `xcodebuild` reported `** TEST SUCCEEDED **`. Checked for stale month-only symbols and confirmed the only remaining `store.items` references in TimelineView are empty-state checks plus filteredItems derivation, not menu grouping.

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `cd ios && xcodegen generate && xcodebuild build -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO` | 0 | ✅ pass | 9300ms |
| 2 | `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO` | 0 | ✅ pass | 29800ms |

## Deviations

The exact slice-level iPhone 16 simulator test was not rerun because this host does not have an `iPhone 16` destination; the generic iOS build passed and the existing XCTest suite passed on an available `iPhone 17` simulator.

## Known Issues

Manual/device UAT was not performed in auto-mode; the SwiftUI wiring compiled and the pure date-jump model tests passed.

## Files Created/Modified

- `ios/PrivateMoments/Views/TimelineView.swift`
