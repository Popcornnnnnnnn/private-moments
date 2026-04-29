---
id: M001
title: "Timeline Navigation and Lightweight Input"
status: complete
completed_at: 2026-04-29T18:15:17.139Z
key_decisions:
  - Kept date-jump grouping pure and caller-driven so TimelineView can pass filteredItems and avoid database/media coupling.
  - Kept date navigation inside the existing toolbar calendar menu, using month submenus with a direct Jump to Month action plus day buttons instead of adding a calendar/archive surface.
  - Kept list continuation as local plain-string editing with no Markdown/rich-text semantics, persistence/schema changes, server changes, sync changes, telemetry, or logging.
  - Reused one shared PlainTextListEditor component for both Composer and Edit Moment surfaces instead of forking per-screen behavior.
  - Maintained a root project.yml mirror for automation compatibility while preserving ios/project.yml as the documented iOS workflow spec.
key_files:
  - ios/PrivateMoments/Views/TimelineDateJumpModels.swift
  - ios/PrivateMoments/Views/MomentDateFormatter.swift
  - ios/PrivateMoments/Views/TimelineView.swift
  - ios/PrivateMomentsTests/TimelineDateJumpModelsTests.swift
  - ios/PrivateMoments/Views/PlainTextListEditor.swift
  - ios/PrivateMomentsListContinuationTests/PlainTextListContinuationTests.swift
  - ios/PrivateMoments/Views/ComposerView.swift
  - ios/PrivateMoments/Views/MomentDetailView.swift
  - ios/project.yml
  - project.yml
  - .gsd/PROJECT.md
lessons_learned:
  - Visible-only navigation helpers should receive already-filtered view models from the caller rather than querying persistence, because that preserves search/filter semantics and avoids archive/database feel.
  - UIKit text-editing polish is safer when the transformation is isolated in a pure NSRange/UTF-16 helper and tested against Unicode/cursor boundary cases before UI wiring.
  - Automation may invoke XcodeGen from the repository root even though the human workflow uses ios/project.yml; keep the root project.yml mirror synchronized or standardize automation.
  - Manual tactile UAT for nested menus and text cursor feel remains necessary for product acceptance, but it should be recorded honestly instead of claimed during auto-mode.
---

# M001: Timeline Navigation and Lightweight Input

**Moments now has quiet toolbar-only month/day timeline jumping plus shared plain-text list continuation in New Moment and Edit Moment, with saved content remaining literal plain text.**

## What Happened

M001 delivered two bounded polish capabilities without changing the app's product posture into an archive manager or writing editor. S01 extracted a pure date-jump model that groups only caller-provided visible timeline items, added count-free life-feeling day labels through MomentDateFormatter, and wired TimelineView's existing toolbar calendar menu to month anchors and first-visible day row IDs. The result preserves the feed as the primary surface: active filters/search determine available targets, empty dates are not selectable, and there is no new calendar tab or archive UI.

S02 delivered lightweight text-entry assistance by adding a pure NSRange/UTF-16 list-continuation helper and a shared UIKit-backed PlainTextListEditor. Composer and Edit Moment now use the same plain editor component, continuing dash, bullet, and numbered list prefixes on Return and exiting generated empty list items cleanly. The implementation deliberately stays inside the existing plain Binding<String> path, with no Markdown/rich-text rendering, no persistence/schema change, no sync/server change, and no text logging.

The milestone also hardened iOS verification paths. XcodeGen generation now works from both the documented ios/project.yml path and the repository root mirror used by automation, and an available iPhone 16 simulator destination was created during slice close-out so planned test commands could run unchanged. Manual tactile/device UAT remains a documented follow-up rather than an overclaimed result, but automated contract and build verification passed for the delivered code.

## Success Criteria Results

- ✅ Timeline remains visually quiet; date jump is available only through the toolbar calendar menu. Evidence: S01 summary records TimelineView keeping date jump in the existing toolbar calendar menu with no calendar/archive surface; code-change commits touch TimelineView and the date-jump model, not a new persistent navigation surface.
- ✅ User can jump to an existing month or a date with moments, and the feed scrolls to the first matching moment. Evidence: S01 summary records month anchor IDs plus day targets equal to first visible moment row IDs; fresh `xcodebuild -project ios/PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test` passed 5 TimelineDateJumpModelsTests with 0 failures.
- ✅ Date jump labels feel like time in life, not archive statistics: no daily moment counts and no empty-date selection. Evidence: TimelineDateJumpModelsTests passed 5/5, including visible-only grouping, empty input, and count/statistics-free label assertions.
- ✅ Composer and Edit Moment support plain-text list continuation without a large input architecture rewrite. Evidence: S02 summary records one shared PlainTextListEditor wired into ComposerView and MomentDetailView; fresh `xcodebuild -project ios/PrivateMoments.xcodeproj -scheme PrivateMomentsListContinuationTests -destination 'platform=iOS Simulator,name=iPhone 16' test` passed 14 tests with 0 failures.
- ✅ Saved and rendered content remains plain text; Markdown/rich-text rendering stays out of scope. Evidence: S02 summary confirms the editor preserves plain String binding/save paths and introduced no Markdown/rich-text rendering, schema, server, sync, storage, telemetry, or logging changes; fresh generic iOS app build succeeded with code signing disabled.

Fresh verification evidence from this completion turn:
- `git log` milestone-scoped commits show non-.gsd implementation files for S01/S02, including TimelineView, TimelineDateJumpModels, MomentDateFormatter, ComposerView, MomentDetailView, PlainTextListEditor, tests, and XcodeGen specs.
- `xcodegen generate --spec ios/project.yml && xcodebuild ... PrivateMomentsListContinuationTests ... test && xcodebuild ... PrivateMoments ... build` completed successfully; list tests executed 14 tests with 0 failures and the app build ended with `** BUILD SUCCEEDED **`.
- `xcodebuild -project ios/PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test` completed successfully; date-jump tests executed 5 tests with 0 failures and ended with `** TEST SUCCEEDED **`.

## Definition of Done Results

- ✅ Code-change verification: direct diff to main was empty because HEAD is already on main for close-out, so retry-on-main handling was used. Recent milestone-scoped commits with `GSD-Task: S01/T01`, `S01/T02`, `S02/T01`, `S02/T02`, and `S02/T03` show implementation files outside `.gsd/`, including iOS source, tests, and project specs.
- ✅ All slices complete: `gsd_milestone_status` reported milestone M001 active with S01 complete (2/2 tasks done) and S02 complete (3/3 tasks done).
- ✅ Slice summaries exist: `.gsd/milestones/M001/slices/S01/S01-SUMMARY.md` and `.gsd/milestones/M001/slices/S02/S02-SUMMARY.md` were read and both report `verification_result: passed`.
- ✅ Cross-slice integration: S01 provides visible-item-derived, toolbar-only date navigation; S02 independently preserves the same lightweight product boundary by staying plain-text/local-only and not adding writing/editor or management surfaces. Together they satisfy the milestone's quiet-polish vision without touching server/sync/storage behavior.
- ✅ Horizontal checklist: no Horizontal Checklist section was present in the roadmap. Existing UAT scripts exist for both slices, but manual/device UAT was explicitly not performed in auto-mode and remains a follow-up rather than a blocking automated verification failure.

## Requirement Outcomes

- R004: validated → validated — S01 delivered toolbar-only, month-first optional-day timeline jump from visible items; fresh date-jump XCTest command passed 5/5 and the app build passed.
- R005: validated → validated — S01 tests and summary prove existing-only months/dates, no empty-date targets, and count/statistics-free life-feeling labels.
- R006: validated → validated — S02 delivered plain-text list continuation for dash, bullet, and numbered prefixes with increment and empty-item exit; fresh list-continuation XCTest command passed 14/14.
- R007: validated → validated — S02 stayed in plain String editing/rendering with no Markdown/rich text, persistence, server, sync, storage, telemetry, or logging changes.

## Deviations

- Added/maintained a root-level `project.yml` mirror because automation runs XcodeGen from the repository root, while the documented iOS workflow uses `ios/project.yml`.
- Created a local iPhone 16 simulator destination during slice close-out so planned xcodebuild test commands could run unchanged.
- Manual/device UAT was documented but not performed in auto-mode; automated tests/builds provide contract and integration evidence, while tactile UX acceptance remains a follow-up.

## Follow-ups

- Run S01-UAT on simulator or the paired iPhone to confirm nested calendar menu ergonomics and scroll feel on real timeline data.
- Run S02-UAT on simulator or the paired iPhone to confirm live cursor placement, visual fit inside forms/cards, and saved plain-text display in both New Moment and Edit Moment.
- Keep root `project.yml` synchronized with `ios/project.yml` when future iOS targets/settings change, or update automation to always invoke XcodeGen with the iOS spec path.
