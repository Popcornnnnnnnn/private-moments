---
id: S01
parent: M001
milestone: M001
provides:
  - Timeline date jump target model/invariant: month targets and optional day targets are derived only from currently visible filtered timeline items.
  - Toolbar-only month/day date navigation that scrolls to existing month anchors or first visible moment row IDs.
  - Life-feeling date label policy for jump labels with no moment counts or archive statistics.
  - Root-level XcodeGen verification compatibility for automation.
requires:
  []
affects:
  - S02
key_files:
  - ios/project.yml
  - project.yml
  - ios/PrivateMoments/Views/TimelineDateJumpModels.swift
  - ios/PrivateMoments/Views/MomentDateFormatter.swift
  - ios/PrivateMomentsTests/TimelineDateJumpModelsTests.swift
  - ios/PrivateMoments/Views/TimelineView.swift
  - .gsd/PROJECT.md
key_decisions:
  - Kept date-jump grouping pure and caller-driven so TimelineView can pass filteredItems and avoid database/media coupling.
  - Kept date navigation inside the existing toolbar calendar menu, using month submenus with a direct Jump to Month action plus day buttons instead of adding a calendar/archive surface.
  - Added a root XcodeGen spec mirror to satisfy root-level automation while preserving ios/project.yml for the documented iOS workflow.
patterns_established:
  - Visible-only UI navigation models should accept already-filtered view items instead of querying broader persistence state.
  - Date labels for timeline navigation belong in MomentDateFormatter and must remain count/statistics-free.
  - SwiftUI scroll targets for mixed section/row navigation can use a neutral target ID request with section anchor IDs and row `.id(item.id)` values.
observability_surfaces:
  - None — this is local SwiftUI navigation state with no runtime service, logging, network, database, or persistence surface.
drill_down_paths:
  - .gsd/milestones/M001/slices/S01/tasks/T01-SUMMARY.md
  - .gsd/milestones/M001/slices/S01/tasks/T02-SUMMARY.md
duration: ""
verification_result: passed
completed_at: 2026-04-29T17:53:03.341Z
blocker_discovered: false
---

# S01: Lightweight Date Jump

**Quiet toolbar-only month/day timeline jumping shipped with visible-item-derived targets, count-free labels, tests, and root/iOS XcodeGen verification paths.**

## What Happened

S01 added a pure date-jump model and wired it into the SwiftUI timeline without adding any new persistent calendar or archive surface. The model lives in `TimelineDateJumpModels.swift` and groups only the `[TimelineItem]` values passed by the caller, preserving the privacy/product invariant that active search/filter state controls which months and days appear. It uses a caller-provided calendar and `now`, preserves newest-first ordering, exposes month anchor IDs, and gives each day a row target equal to the first visible moment for that day.

`MomentDateFormatter` now owns day jump labels so TimelineView does not embed ad hoc date formatting. Labels are life-feeling date language such as Today/Yesterday/weekday/month-day variants and test coverage rejects count/statistics wording. `TimelineView` now builds jump groups from `filteredItems`, keeps the existing toolbar calendar menu as the only entry point, presents months as nested menu entries with a `Jump to Month` action plus day buttons, and scrolls through a neutral target ID request. Existing month anchors remain valid and each rendered row has a stable `.id(item.id)` so day buttons can scroll directly to the first matching visible moment.

The initial auto-verification failed because it invoked `xcodegen generate` from the repository root while the existing project spec was only under `ios/project.yml`. To make the assembled slice robust under both documented and automated verification paths, this closure added a root `project.yml` mirror whose source and Info.plist paths are rooted at the repository. Root-level `xcodegen generate` now produces `PrivateMoments.xcodeproj`, while `ios/project.yml` remains available for the documented iOS workflow.

## Verification

Fresh slice-level verification was rerun after the root XcodeGen spec fix. `xcodegen generate && xcodebuild build -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO` completed with exit code 0 and `** BUILD SUCCEEDED **`. `xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO` completed with exit code 0 and `** TEST SUCCEEDED **`; `TimelineDateJumpModelsTests` executed 5 tests with 0 failures. The tests cover empty inputs, visible-only derivation from caller-provided items, month/day grouping, newest-first first-item target selection, and count/statistics-free date labels. Manual/device UAT was not performed in auto-mode.

## Requirements Advanced

None.

## Requirements Validated

- R004 — Root-level generic iOS build passed and TimelineView keeps date jump in the existing toolbar calendar menu with month/day scroll targets.
- R005 — TimelineDateJumpModelsTests passed 5/5, proving visible-only grouping, no empty groups/dates, stable day targets, and count-free labels.

## New Requirements Surfaced

None.

## Requirements Invalidated or Re-scoped

None.

## Operational Readiness

None.

## Deviations

Added a root-level `project.yml` mirror during slice closure because automated verification ran `xcodegen generate` from the repository root, while the task plan commands used `cd ios`. This does not change app behavior; it makes verification robust for both root and `ios/` execution contexts. The exact `iPhone 16` simulator destination was unavailable locally, so tests ran on an available `iPhone 17` simulator.

## Known Limitations

Manual/device UAT was not performed in auto-mode. Very large timelines could make the nested menu long; S01 intentionally avoids database-backed archive browsing and keeps the menu derived from visible items only.

## Follow-ups

Keep root `project.yml` synchronized with `ios/project.yml` when future iOS target settings change, or update automation to always invoke XcodeGen from `ios/`. Perform human/device UAT for nested menu feel when convenient.

## Files Created/Modified

- `ios/project.yml` — Defines the app and test targets for the documented iOS XcodeGen workflow.
- `project.yml` — Root-level XcodeGen spec mirror so root-run automation can generate and build PrivateMoments.xcodeproj.
- `ios/PrivateMoments/Views/TimelineDateJumpModels.swift` — Pure month/day date-jump grouping model over caller-provided visible TimelineItem values.
- `ios/PrivateMoments/Views/MomentDateFormatter.swift` — Adds count-free day jump label formatting.
- `ios/PrivateMomentsTests/TimelineDateJumpModelsTests.swift` — Unit tests for visible-only grouping, target selection, empty input, and label constraints.
- `ios/PrivateMoments/Views/TimelineView.swift` — Wires the toolbar calendar menu to visible-derived month/day jump targets and stable row IDs.
- `.gsd/PROJECT.md` — Refreshes current project state with completed S01 date-jump capability and root XcodeGen note.
