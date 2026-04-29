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

### R004 — The timeline must keep feed browsing as the primary experience while offering lightweight month-first, optional-day jump navigation from a low-frequency toolbar menu entry.
- Class: functional
- Status: active
- Description: The timeline must keep feed browsing as the primary experience while offering lightweight month-first, optional-day jump navigation from a low-frequency toolbar menu entry.
- Why it matters: As content grows, the user needs to return to a period of life without turning Moments into a database or management tool.
- Source: M001 discussion
- Primary owning slice: M001/S01
- Validation: User can open the toolbar calendar menu, choose an existing month or a date within that month, and the timeline scrolls to the first matching moment without adding a persistent calendar/archive UI.

### R005 — Date navigation must only show existing months and dates with moments, use life-feeling labels such as month names and weekday context, and avoid daily counts or database-style primary date strings.
- Class: constraint
- Status: active
- Description: Date navigation must only show existing months and dates with moments, use life-feeling labels such as month names and weekday context, and avoid daily counts or database-style primary date strings.
- Why it matters: The feature should support returning to lived time, not statistical archive management.
- Source: M001 discussion
- Primary owning slice: M001/S01
- Validation: Date jump menu displays entries such as month titles and day labels without moment counts, and there is no empty-date selection path.

### R006 — Composer and edit text input may support plain-text list continuation for `- `, `• `, and numbered list prefixes, including numbered auto-increment and empty-item exit.
- Class: functional
- Status: active
- Description: Composer and edit text input may support plain-text list continuation for `- `, `• `, and numbered list prefixes, including numbered auto-increment and empty-item exit.
- Why it matters: This preserves lightweight expression while removing common friction when writing a few short lines.
- Source: M001 discussion
- Primary owning slice: M001/S02
- Validation: In both New Moment and Edit Moment, pressing Return after `- item`, `• item`, or `1. item` continues the list; pressing Return on an empty generated list item exits the list.

## Traceability

| ID | Class | Status | Primary owner | Supporting | Proof |
|---|---|---|---|---|---|
| R001 | operational | active | none | none | A completed non-trivial change includes fresh verification output and either updated docs/fact sources or an explicit note that none were affected. |
| R002 | operational | active | none | none | High-risk changes have a milestone or slice context/plan before code changes and include success criteria plus verification evidence. |
| R003 | operational | active | none | none | Completion summaries name the verification class used and include the command or inspection evidence. |
| R004 | functional | active | M001/S01 | none | User can open the toolbar calendar menu, choose an existing month or a date within that month, and the timeline scrolls to the first matching moment without adding a persistent calendar/archive UI. |
| R005 | constraint | active | M001/S01 | none | Date jump menu displays entries such as month titles and day labels without moment counts, and there is no empty-date selection path. |
| R006 | functional | active | M001/S02 | none | In both New Moment and Edit Moment, pressing Return after `- item`, `• item`, or `1. item` continues the list; pressing Return on an empty generated list item exits the list. |

## Coverage Summary

- Active requirements: 6
- Mapped to slices: 6
- Validated: 0
- Unmapped active requirements: 0
