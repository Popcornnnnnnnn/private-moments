# Requirements

This file is the explicit capability and coverage contract for the project.

## Active

### R001 — Non-trivial work must end with a minimum closure loop: change summary, verification evidence, known issues or next steps, and updates to affected fact-source or human-facing docs.
- Class: operational
- Status: active
- Description: Non-trivial work must end with a minimum closure loop: change summary, verification evidence, known issues or next steps, and updates to affected fact-source or human-facing docs.
- Why it matters: This project spans iOS, server, admin, local storage, and real-device behavior; losing end-of-work context makes future maintenance risky.
- Source: workflow alignment discussion 2026-04-30
- Validation: A completed non-trivial change includes fresh verification output and either updated docs/fact sources or an explicit note that none were affected.

### R002 — High-risk work must use milestone/slice planning before implementation when it can affect sync semantics, schema migrations, media storage or recovery, backup or restore, auth/security boundaries, or cross-device behavior.
- Class: operational
- Status: active
- Description: High-risk work must use milestone/slice planning before implementation when it can affect sync semantics, schema migrations, media storage or recovery, backup or restore, auth/security boundaries, or cross-device behavior.
- Why it matters: These areas can corrupt data, hide records, break recovery, or weaken the private network boundary even when changes are small.
- Source: workflow alignment discussion 2026-04-30
- Validation: High-risk changes have a milestone or slice context/plan before code changes and include success criteria plus verification evidence.

### R003 — Verification depth must be proportional to change impact: server/admin changes require build and HTTP or browser checks; iOS changes require build; sync, media, storage, and real-device behavior require device install or device data inspection when feasible.
- Class: operational
- Status: active
- Description: Verification depth must be proportional to change impact: server/admin changes require build and HTTP or browser checks; iOS changes require build; sync, media, storage, and real-device behavior require device install or device data inspection when feasible.
- Why it matters: A single fixed verification rule is either too weak for data-risk changes or too heavy for low-risk maintenance.
- Source: workflow alignment discussion 2026-04-30
- Validation: Completion summaries name the verification class used and include the command or inspection evidence.

## Validated

### R004 — The timeline must keep feed browsing as the primary experience while offering lightweight month-first, optional-day jump navigation from a low-frequency toolbar menu entry.
- Class: functional
- Status: validated
- Description: The timeline must keep feed browsing as the primary experience while offering lightweight month-first, optional-day jump navigation from a low-frequency toolbar menu entry.
- Why it matters: As content grows, the user needs to return to a period of life without turning Moments into a database or management tool.
- Source: M001 discussion
- Primary owning slice: M001/S01
- Validation: S01 completed: root-level and iOS XcodeGen specs generate successfully; generic iOS build passed; TimelineDateJumpModelsTests passed 5/5 on iPhone 17 simulator. Toolbar-only date jump menu remains the only date navigation entry, with month targets and day row targets wired through TimelineView.

### R005 — Date navigation must only show existing months and dates with moments, use life-feeling labels such as month names and weekday context, and avoid daily counts or database-style primary date strings.
- Class: constraint
- Status: validated
- Description: Date navigation must only show existing months and dates with moments, use life-feeling labels such as month names and weekday context, and avoid daily counts or database-style primary date strings.
- Why it matters: The feature should support returning to lived time, not statistical archive management.
- Source: M001 discussion
- Primary owning slice: M001/S01
- Validation: S01 completed: TimelineDateJumpBuilder tests passed 5/5 and prove groups are derived only from caller-provided visible items, omit empty dates, select first visible day targets, and enforce count/statistics-free labels. TimelineView passes filteredItems into the builder.

### R006 — Composer and edit text input may support plain-text list continuation for `- `, `• `, and numbered list prefixes, including numbered auto-increment and empty-item exit.
- Class: functional
- Status: validated
- Description: Composer and edit text input may support plain-text list continuation for `- `, `• `, and numbered list prefixes, including numbered auto-increment and empty-item exit.
- Why it matters: This preserves lightweight expression while removing common friction when writing a few short lines.
- Source: M001 discussion
- Primary owning slice: M001/S02
- Validation: Validated by `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMomentsListContinuationTests -destination 'platform=iOS Simulator,name=iPhone 16' test` after creating an available iPhone 16 simulator: 14 XCTest cases passed, covering dash, bullet, numbered increment, empty-item exit, normal paragraph fallback, non-list fallback, invalid range fallback, max-int fallback, and emoji/Unicode UTF-16 safety. App integration also built with `xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`. Manual UAT script is recorded in S02-UAT for tactile cursor/save verification.

### R007 — Moments must not introduce Markdown rendering, rich-text formatting, headings, bold, quotes, or link previews as part of the list continuation work.
- Class: constraint
- Status: validated
- Description: Moments must not introduce Markdown rendering, rich-text formatting, headings, bold, quotes, or link previews as part of the list continuation work.
- Why it matters: The app should remain an expression space rather than becoming a Markdown editor or writing tool.
- Source: M001 discussion
- Primary owning slice: M001/S02
- Validation: Validated by implementation boundaries and build evidence for S02: list continuation is implemented as plain string editing via `PlainTextListContinuation` and `PlainTextListEditor`; New Moment/Edit Moment bindings still pass plain `String` values into existing draft/save flows; no Markdown/rich-text rendering, schema, server, sync, storage, telemetry, or logging changes were introduced. `PrivateMomentsListContinuationTests` passed on iPhone 16 simulator and the app target built for generic iOS with code signing disabled.

## Traceability

| ID | Class | Status | Primary owner | Supporting | Proof |
|---|---|---|---|---|---|
| R001 | operational | active | none | none | A completed non-trivial change includes fresh verification output and either updated docs/fact sources or an explicit note that none were affected. |
| R002 | operational | active | none | none | High-risk changes have a milestone or slice context/plan before code changes and include success criteria plus verification evidence. |
| R003 | operational | active | none | none | Completion summaries name the verification class used and include the command or inspection evidence. |
| R004 | functional | validated | M001/S01 | none | S01 completed: root-level and iOS XcodeGen specs generate successfully; generic iOS build passed; TimelineDateJumpModelsTests passed 5/5 on iPhone 17 simulator. Toolbar-only date jump menu remains the only date navigation entry, with month targets and day row targets wired through TimelineView. |
| R005 | constraint | validated | M001/S01 | none | S01 completed: TimelineDateJumpBuilder tests passed 5/5 and prove groups are derived only from caller-provided visible items, omit empty dates, select first visible day targets, and enforce count/statistics-free labels. TimelineView passes filteredItems into the builder. |
| R006 | functional | validated | M001/S02 | none | Validated by `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMomentsListContinuationTests -destination 'platform=iOS Simulator,name=iPhone 16' test` after creating an available iPhone 16 simulator: 14 XCTest cases passed, covering dash, bullet, numbered increment, empty-item exit, normal paragraph fallback, non-list fallback, invalid range fallback, max-int fallback, and emoji/Unicode UTF-16 safety. App integration also built with `xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`. Manual UAT script is recorded in S02-UAT for tactile cursor/save verification. |
| R007 | constraint | validated | M001/S02 | none | Validated by implementation boundaries and build evidence for S02: list continuation is implemented as plain string editing via `PlainTextListContinuation` and `PlainTextListEditor`; New Moment/Edit Moment bindings still pass plain `String` values into existing draft/save flows; no Markdown/rich-text rendering, schema, server, sync, storage, telemetry, or logging changes were introduced. `PrivateMomentsListContinuationTests` passed on iPhone 16 simulator and the app target built for generic iOS with code signing disabled. |

## Coverage Summary

- Active requirements: 3
- Mapped to slices: 3
- Validated: 4 (R004, R005, R006, R007)
- Unmapped active requirements: 0
