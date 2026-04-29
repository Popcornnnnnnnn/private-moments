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

### R008 — A user can add and delete private plain-text comments on an existing moment from the iOS moment detail view, with comments displayed under that moment without changing the main timeline feed density.
- Class: functional
- Status: active
- Description: A user can add and delete private plain-text comments on an existing moment from the iOS moment detail view, with comments displayed under that moment without changing the main timeline feed density.
- Why it matters: The user wants lightweight follow-up thoughts attached to a moment while preserving the main timeline as a quiet feed.
- Source: M002 planning discussion 2026-04-30
- Primary owning slice: M002/S02
- Supporting slices: M002/S01,M002/S03
- Validation: A real-device UAT creates a comment, sees it in moment detail, deletes it, and confirms the main timeline row remains uncluttered.

### R010 — Private comments remain plain text and single-level: no replies, likes, mentions, Markdown rendering, public author identity, or social feedback features.
- Class: constraint
- Status: active
- Description: Private comments remain plain text and single-level: no replies, likes, mentions, Markdown rendering, public author identity, or social feedback features.
- Why it matters: Moments should stay a private expression space rather than becoming a social comment system or structured writing tool.
- Source: M002 planning discussion 2026-04-30
- Primary owning slice: M002/S02
- Supporting slices: M002/S01,M002/S03
- Validation: Implementation review confirms comments use plain strings, no nested thread model is exposed in iOS UI, and docs describe comments as private notes rather than social comments.

## Validated

### R004 — The timeline must keep feed browsing as the primary experience while offering lightweight month-only jump navigation from a low-frequency toolbar menu entry.
- Class: functional
- Status: validated
- Description: The timeline must keep feed browsing as the primary experience while offering lightweight month-only jump navigation from a low-frequency toolbar menu entry.
- Why it matters: As content grows, the user needs to return to a period of life without turning Moments into a database or management tool.
- Source: M001 discussion
- Primary owning slice: M001/S01
- Validation: Refined after user review: the toolbar calendar menu is month-only to avoid long nested day lists; exact date retrieval is deferred to future enhanced search. TimelineDateJumpModelsTests validate month grouping, month menu labels, filtered-item inputs, and count-free labels.

### R005 — Date navigation must only show existing months with moments, use life-feeling month labels, and avoid daily counts, daily submenus, or database-style date browsing.
- Class: constraint
- Status: validated
- Description: Date navigation must only show existing months with moments, use life-feeling month labels, and avoid daily counts, daily submenus, or database-style date browsing.
- Why it matters: The feature should support returning to lived time, not statistical archive management.
- Source: M001 discussion
- Primary owning slice: M001/S01
- Validation: Refined after user review: TimelineDateJumpBuilder no longer generates day groups for the calendar menu. Tests validate month-only groups, abbreviated menu labels, caller-filtered inputs, newest item month anchors, and count/statistics-free labels.

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

### R009 — Private comments sync through the Mac server using idempotent operation-log semantics so comments survive app reinstall and can converge across authorized devices.
- Class: functional
- Status: validated
- Description: Private comments sync through the Mac server using idempotent operation-log semantics so comments survive app reinstall and can converge across authorized devices.
- Why it matters: Comments are user data; keeping them local-only would create avoidable loss and future migration risk.
- Source: M002 planning discussion 2026-04-30
- Primary owning slice: M002/S01
- Supporting slices: M002/S02,M002/S03
- Validation: S01 validated the private comment sync contract: T02 added server Prisma schema/migration plus idempotent `create_comment` and `delete_comment` operations emitting `comment_created`/`comment_deleted`; T03 added iOS `local_comments`, payload builders, outbox plumbing, and strict server-change apply before cursor advancement. Verification: `npm run server:prisma:generate && npm run server:build`, scripted server comment sync smoke test, `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`, and iOS XCTest payload coverage passed.

## Traceability

| ID | Class | Status | Primary owner | Supporting | Proof |
|---|---|---|---|---|---|
| R001 | operational | active | none | none | A completed non-trivial change includes fresh verification output and either updated docs/fact sources or an explicit note that none were affected. |
| R002 | operational | active | none | none | High-risk changes have a milestone or slice context/plan before code changes and include success criteria plus verification evidence. |
| R003 | operational | active | none | none | Completion summaries name the verification class used and include the command or inspection evidence. |
| R004 | functional | validated | M001/S01 | none | Refined after user review: the toolbar calendar menu is month-only to avoid long nested day lists; exact date retrieval is deferred to future enhanced search. TimelineDateJumpModelsTests validate month grouping, month menu labels, filtered-item inputs, and count-free labels. |
| R005 | constraint | validated | M001/S01 | none | Refined after user review: TimelineDateJumpBuilder no longer generates day groups for the calendar menu. Tests validate month-only groups, abbreviated menu labels, caller-filtered inputs, newest item month anchors, and count/statistics-free labels. |
| R006 | functional | validated | M001/S02 | none | Validated by `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMomentsListContinuationTests -destination 'platform=iOS Simulator,name=iPhone 16' test` after creating an available iPhone 16 simulator: 14 XCTest cases passed, covering dash, bullet, numbered increment, empty-item exit, normal paragraph fallback, non-list fallback, invalid range fallback, max-int fallback, and emoji/Unicode UTF-16 safety. App integration also built with `xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`. Manual UAT script is recorded in S02-UAT for tactile cursor/save verification. |
| R007 | constraint | validated | M001/S02 | none | Validated by implementation boundaries and build evidence for S02: list continuation is implemented as plain string editing via `PlainTextListContinuation` and `PlainTextListEditor`; New Moment/Edit Moment bindings still pass plain `String` values into existing draft/save flows; no Markdown/rich-text rendering, schema, server, sync, storage, telemetry, or logging changes were introduced. `PrivateMomentsListContinuationTests` passed on iPhone 16 simulator and the app target built for generic iOS with code signing disabled. |
| R008 | functional | active | M002/S02 | M002/S01,M002/S03 | A real-device UAT creates a comment, sees it in moment detail, deletes it, and confirms the main timeline row remains uncluttered. |
| R009 | functional | validated | M002/S01 | M002/S02,M002/S03 | S01 validated the private comment sync contract: T02 added server Prisma schema/migration plus idempotent `create_comment` and `delete_comment` operations emitting `comment_created`/`comment_deleted`; T03 added iOS `local_comments`, payload builders, outbox plumbing, and strict server-change apply before cursor advancement. Verification: `npm run server:prisma:generate && npm run server:build`, scripted server comment sync smoke test, `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`, and iOS XCTest payload coverage passed. |
| R010 | constraint | active | M002/S02 | M002/S01,M002/S03 | Implementation review confirms comments use plain strings, no nested thread model is exposed in iOS UI, and docs describe comments as private notes rather than social comments. |

## Coverage Summary

- Active requirements: 5
- Mapped to slices: 5
- Validated: 5 (R004, R005, R006, R007, R009)
- Unmapped active requirements: 0
