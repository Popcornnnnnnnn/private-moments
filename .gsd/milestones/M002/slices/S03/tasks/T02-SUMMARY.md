---
id: T02
parent: S03
milestone: M002
key_files:
  - docs/PRD.md
  - docs/TECH-DESIGN.md
  - docs/OPERATOR-RUNBOOK.md
  - docs/INTEGRATION-GUIDE.md
  - shared/sync-protocol.md
  - docs/HANDOFF.md
  - .gsd/REQUIREMENTS.md
key_decisions:
  - Marked R010 validated after docs, implementation boundaries, and fresh iOS tests satisfied its validation contract; left R008 active because manual real-device UAT remains required.
duration: 
verification_result: passed
completed_at: 2026-04-29T20:05:15.949Z
blocker_discovered: false
---

# T02: Updated durable product, architecture, operator, integration, and sync docs for shipped Private Comments.

**Updated durable product, architecture, operator, integration, and sync docs for shipped Private Comments.**

## What Happened

Loaded project memory plus the write-docs and verify-before-complete skills, then verified source truth from `server/src/config/app-config.ts` (`SCHEMA_VERSION = 4`) and T01’s evidence before editing. Updated `docs/PRD.md` to describe shipped detail-only private plain-text follow-up notes and explicitly exclude replies, likes, mentions, Markdown rendering, rich text, public author identity, and timeline clutter. Updated `docs/TECH-DESIGN.md` to remove stale unopened-comment-UI language, describe shipped first-class comment entities, `local_comments`, server `comments`, `delete_comment` / `create_comment`, parent-deletion visibility constraints, schema version 4, and existing diagnostic surfaces that avoid copying comment bodies. Updated `docs/OPERATOR-RUNBOOK.md` with a concrete Private Comments UAT path covering prerequisites, iPhone UI steps, no-timeline-clutter checks, copied Library container inspection, local/server SQLite aggregate queries, blocked-check recording, and privacy rules against logging secrets or private comment bodies. Updated `docs/INTEGRATION-GUIDE.md` so examples use `schemaVersion: 4` and the `delete_comment` guidance explains that iOS includes `postId` for parent sync-status refresh while the server derives the authoritative parent from the existing comment row. Updated `shared/sync-protocol.md` to align the `delete_comment` payload note with optional client `postId` without adding edits/replies/new scopes. Updated `docs/HANDOFF.md` with final S03 state, continued real-device UAT limitation, and next work. After the docs and fresh tests, updated R010 to `validated`; R008 remains active because it still requires manual real-device UAT.

## Verification

Verified stale schema/private-comment wording is gone, required schema/comment anchors are present, and timeline files still have no comment surface. Ran fresh `npm run server:build` after edits. Ran fresh iOS simulator tests on iPhone 16; 16 XCTest cases passed, including comment payload, plain-text literal, delete-selection, and no-rich-text/no-reply policy coverage. Observability impact was verified by checking the docs now describe existing UI/outbox/local SQLite/server SQLite/build-test diagnostic surfaces and explicitly forbid copying comment bodies or secrets into logs.

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `! rg -n "schemaVersion\": 3|schemaVersion: 3|comment UI is not open|visible UI is not open|not open" docs/TECH-DESIGN.md docs/INTEGRATION-GUIDE.md docs/OPERATOR-RUNBOOK.md docs/PRD.md docs/HANDOFF.md shared/sync-protocol.md` | 0 | ✅ pass | 100ms |
| 2 | `rg -n "schemaVersion\": 4|SCHEMA_VERSION = 4|local_comments|outbox_operations|delete_comment|Private Comments" docs/TECH-DESIGN.md docs/INTEGRATION-GUIDE.md docs/OPERATOR-RUNBOOK.md shared/sync-protocol.md server/src/config/app-config.ts` | 0 | ✅ pass | 100ms |
| 3 | `! rg -n "comment|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift` | 0 | ✅ pass | 100ms |
| 4 | `npm run server:build` | 0 | ✅ pass | 37200ms |
| 5 | `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16'` | 0 | ✅ pass | 34200ms |

## Deviations

No plan-invalidating deviations. I included `server/src/config/app-config.ts` in the positive anchor check to prove `SCHEMA_VERSION = 4` against source truth, and updated R010 because T02 completed the remaining docs portion of its validation contract.

## Known Issues

Manual real-device Private Comments UAT is still not executable in autonomous auto-mode, so R008 remains active. T01 also found the copied device DB had no comment rows/outbox comment ops and the checked local server SQLite archives lacked a `comments` table; future UAT must confirm the active schema-version-4 database before server aggregate proof.

## Files Created/Modified

- `docs/PRD.md`
- `docs/TECH-DESIGN.md`
- `docs/OPERATOR-RUNBOOK.md`
- `docs/INTEGRATION-GUIDE.md`
- `shared/sync-protocol.md`
- `docs/HANDOFF.md`
- `.gsd/REQUIREMENTS.md`
