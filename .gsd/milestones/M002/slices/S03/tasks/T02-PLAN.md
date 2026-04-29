---
estimated_steps: 26
estimated_files: 6
skills_used: []
---

# T02: Update durable docs for shipped private comments

Why: S01 and S02 changed product behavior and contracts, but long-lived docs still have drift: `docs/TECH-DESIGN.md` describes comment UI as not open, and `docs/INTEGRATION-GUIDE.md` contains a stale `schemaVersion: 3` example. S03 must leave cold-reader docs accurate and operational.

Files: `docs/PRD.md`, `docs/TECH-DESIGN.md`, `docs/OPERATOR-RUNBOOK.md`, `docs/INTEGRATION-GUIDE.md`, `shared/sync-protocol.md`, `docs/HANDOFF.md`

Do:
1. Load the `write-docs` and `verify-before-complete` skills before editing and final claims. Keep human-facing docs primarily Chinese; preserve English command names, API fields, filenames, SQL identifiers, and app UI strings such as `Private Comments` and `Add`.
2. Update `docs/PRD.md` to state the shipped product behavior: private plain-text follow-up notes live only in Moment detail; the main timeline remains quiet; no replies, likes, mentions, public author identity, Markdown rendering, or rich-text/social mechanics.
3. Update `docs/TECH-DESIGN.md` to remove stale “comment UI not open” language and describe the current architecture: first-class synced comment entities, iOS `local_comments`, Moment detail as the only user-facing surface, parent moment deletion hiding/cascading comment visibility, existing diagnostics, and schema version 4.
4. Update `docs/OPERATOR-RUNBOOK.md` with a concrete “Private comments UAT” section: server/device prerequisites, iPhone UI steps, no-timeline-clutter check, pending/synced observation, `xcrun devicectl` copy pattern reference, local SQLite aggregate queries for `local_comments`/`outbox_operations`, and server SQLite aggregate queries for `comments`/`sync_operations`. The runbook must tell operators not to paste secrets or private comment bodies into logs.
5. Update `docs/INTEGRATION-GUIDE.md` so all examples use schema version 4 and the `delete_comment` guidance reflects current client behavior: iOS includes `postId` for parent sync-status refresh, while the server derives parent information from the existing comment for emitted deletion changes.
6. Update `shared/sync-protocol.md` only if needed to align the protocol note with optional client `postId` in `delete_comment` payloads; do not invent new operation types or scope such as edits/replies.
7. Update `docs/HANDOFF.md` with the final S03 state: what was verified, whether real-device UAT passed or remains blocked, any requirement status changes, and the next sensible work.
8. Run doc/static checks after edits, then rerun at least the relevant build/static verification from T01 before claiming completion.

Verify: `rg -n "schemaVersion\": 3|schemaVersion: 3|comment UI is not open|visible UI is not open|not open" docs/TECH-DESIGN.md docs/INTEGRATION-GUIDE.md docs/OPERATOR-RUNBOOK.md docs/PRD.md docs/HANDOFF.md shared/sync-protocol.md` should return no stale private-comment/schema-version hits; `rg -n "schemaVersion\": 4|SCHEMA_VERSION = 4|local_comments|outbox_operations|delete_comment|Private Comments" docs/TECH-DESIGN.md docs/INTEGRATION-GUIDE.md docs/OPERATOR-RUNBOOK.md shared/sync-protocol.md` should show the expected anchors; `! rg -n "comment|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift`; and the final evidence bundle should include fresh `npm run server:build` plus iOS simulator test or generic build output.

Done when: Product, architecture, operator, integration, sync-protocol, and handoff docs accurately describe shipped private comments and their constraints; stale schema/UI text is gone; UAT and SQL checks are documented; and final verification evidence is fresh after the last edit.

Failure Modes:
| Dependency | On error | On timeout | On malformed response |
|------------|----------|------------|------------------------|
| Prior T01 validation evidence | Write docs to distinguish passed, blocked, and not-run checks; do not convert missing evidence into validated language. | Preserve the timeout as a limitation in `docs/HANDOFF.md`. | Treat ambiguous evidence as inconclusive and use cautious wording. |
| Doc references to API/schema state | Verify against `server/src/config/app-config.ts` and existing shared contract files before changing examples. | N/A | If contract examples conflict, prefer source-of-truth code and note the doc alignment change. |

Load Profile:
- Shared resources: human-facing docs and shared protocol examples.
- Per-operation cost: documentation edits plus static `rg` checks and build/test reruns.
- 10x breakpoint: doc drift and duplicated wording, not runtime throughput.

Negative Tests:
- Malformed inputs: docs must explicitly preserve Markdown-like text as literal plain text rather than describing Markdown rendering.
- Error paths: runbook must describe what to record when real-device install/sync/DB inspection is blocked.
- Boundary conditions: docs must state that comments stay out of timeline badges/counts/previews/search and that parent moment deletion must not leave orphan visible comments.

## Inputs

- `docs/PRD.md`
- `docs/TECH-DESIGN.md`
- `docs/OPERATOR-RUNBOOK.md`
- `docs/INTEGRATION-GUIDE.md`
- `shared/sync-protocol.md`
- `docs/HANDOFF.md`
- `server/src/config/app-config.ts`

## Expected Output

- `docs/PRD.md`
- `docs/TECH-DESIGN.md`
- `docs/OPERATOR-RUNBOOK.md`
- `docs/INTEGRATION-GUIDE.md`
- `shared/sync-protocol.md`
- `docs/HANDOFF.md`

## Verification

`rg -n "schemaVersion\": 3|schemaVersion: 3|comment UI is not open|visible UI is not open|not open" docs/TECH-DESIGN.md docs/INTEGRATION-GUIDE.md docs/OPERATOR-RUNBOOK.md docs/PRD.md docs/HANDOFF.md shared/sync-protocol.md` returns no stale private-comment/schema-version hits; `rg -n "schemaVersion\": 4|SCHEMA_VERSION = 4|local_comments|outbox_operations|delete_comment|Private Comments" docs/TECH-DESIGN.md docs/INTEGRATION-GUIDE.md docs/OPERATOR-RUNBOOK.md shared/sync-protocol.md` shows expected anchors; `! rg -n "comment|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift`; rerun fresh build/test checks after final edits.

## Observability Impact

Documents how future agents/operators inspect comment sync and persistence failures through existing UI state, local SQLite tables, server SQLite tables, and command output. Adds no new runtime telemetry.
