---
phase: complete
phase_name: Milestone Learnings Extraction
project: private-moments
generated: 2026-04-29T18:15:30Z
counts:
  decisions: 5
  lessons: 4
  patterns: 5
  surprises: 3
missing_artifacts:
  - Manual/device UAT evidence was not produced in auto-mode; S01-UAT.md and S02-UAT.md remain scripts for future human/device checks.
---

# M001 Learnings: Timeline Navigation and Lightweight Input

### Decisions

- Keep date navigation in the existing toolbar calendar menu, with month submenus, direct Jump to Month actions, and day buttons rather than adding a calendar/archive surface.
  Source: S01-SUMMARY.md/Key decisions
- Keep date-jump grouping pure and caller-driven so TimelineView passes filteredItems and the model never queries broader persistence/media state.
  Source: S01-SUMMARY.md/Key decisions
- Keep list continuation as local plain-string editing with no Markdown/rich-text semantics, persistence/schema changes, server changes, sync changes, telemetry, or logging.
  Source: S02-SUMMARY.md/Key decisions
- Reuse one shared PlainTextListEditor component for both Composer and Edit Moment instead of forking per-screen behavior.
  Source: S02-SUMMARY.md/Key decisions
- Maintain a root project.yml mirror to satisfy root-level automation while preserving ios/project.yml for the documented iOS workflow.
  Source: S01-SUMMARY.md/Deviations

### Lessons

- Auto verification may run XcodeGen from the repository root even when the human workflow says `cd ios`; either keep the root spec mirror synchronized or standardize automation around `xcodegen generate --spec ios/project.yml`.
  Source: S01-SUMMARY.md/Deviations
- Simulator-name verification failures can be environmental rather than code failures; if the device type and runtime exist, create the missing simulator and rerun the planned xcodebuild destination unchanged.
  Source: S02-SUMMARY.md/Deviations
- Manual tactile UAT is still needed for nested menu ergonomics, scroll feel, editor cursor behavior, and saved plain-text display; automated tests/builds prove contracts and integration but not final touch feel.
  Source: M001-VALIDATION.md/Verification Class Compliance
- Moment text is private, so diagnostics for text-entry behavior should be deterministic tests and build output rather than runtime logging or telemetry of typed content.
  Source: S02-SUMMARY.md/Observability/diagnostics

### Patterns

- Visible-only UI navigation models should accept already-filtered view items from the caller instead of querying persistence, preserving search/filter semantics and avoiding database/archive coupling.
  Source: S01-SUMMARY.md/Patterns established
- Date labels for timeline navigation belong in MomentDateFormatter and must remain count/statistics-free.
  Source: S01-SUMMARY.md/Patterns established
- SwiftUI scroll targets for mixed section/row navigation can use a neutral target ID request with section anchor IDs and row `.id(item.id)` values.
  Source: S01-SUMMARY.md/Patterns established
- For UIKit text-editing helpers, isolate string/range transformation in a pure NSRange/UTF-16 helper and test Unicode boundaries before wiring UI.
  Source: S02-SUMMARY.md/Patterns established
- For lightweight input polish, share one plain editor component across Composer/Edit surfaces and preserve the existing plain Binding<String> save/draft path.
  Source: S02-SUMMARY.md/Patterns established

### Surprises

- The exact iPhone 16 simulator destination was initially unavailable locally, despite being the planned verification destination.
  Source: S02-SUMMARY.md/Deviations
- Root-level automation expected an XcodeGen spec at the repository root even though the documented iOS workflow used ios/project.yml.
  Source: S01-SUMMARY.md/Deviations
- Milestone validation returned needs-attention because manual/device UAT and consumer-side assessment artifacts were missing, even though automated contract/build evidence covered the core implementation.
  Source: M001-VALIDATION.md/Verdict Rationale
