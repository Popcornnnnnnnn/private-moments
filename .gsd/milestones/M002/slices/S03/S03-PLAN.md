# S03: Comment flow validation and documentation

**Goal:** Validate the shipped private-comment flow end to end as far as the current environment allows, then update durable product/operator/integration documentation so future readers understand the feature, constraints, schema version, and UAT path.
**Demo:** A documented UAT path proves private comments create/delete and sync behavior, and operator/product docs explain the feature and constraints.

## Must-Haves

- A repeatable private-comments UAT/checklist exists in `docs/OPERATOR-RUNBOOK.md`, including iPhone UI steps plus local/server SQLite checks for comments and comment outbox state.
- Fresh validation evidence covers server build, iOS simulator tests/build, timeline non-clutter static check, and real-device install/UAT when feasible. If the real device is unavailable, the exact blocker is documented without claiming validation.
- `docs/PRD.md`, `docs/TECH-DESIGN.md`, `docs/INTEGRATION-GUIDE.md`, `shared/sync-protocol.md`, and `docs/HANDOFF.md` describe comments as shipped private plain-text detail-view notes, not social comments, and reflect schema version 4.
- R008 and R010 are updated only if current-session evidence supports validation; otherwise their remaining validation gap is recorded.

## Proof Level

- This slice proves: final-assembly

## Integration Closure

Consumes S01 server/sync/local persistence and S02 Moment detail UI. This slice introduces no new runtime wiring; it closes the milestone by exercising the real build/device/operator path and writing the durable docs and requirement evidence that make the feature usable and maintainable. After this slice, no known milestone work should remain unless real-device UAT is blocked, in which case the exact operational gap must be recorded in `docs/HANDOFF.md` and the slice summary.

## Verification

- Uses existing diagnostics rather than adding runtime signals: iOS `SyncBadge`/outbox status, `local_comments`, `outbox_operations`, server `comments` and `sync_operations`, `TimelineStore.errorMessage`, build/test output, and static timeline non-clutter checks. Verification and docs must avoid logging or copying private comment bodies or secrets.

## Tasks

- [x] **T01: Run and record private-comment validation evidence** `est:2h`
  Why: S03 must not close on documentation alone. It needs fresh proof that the S01 sync/data contract and S02 detail-view UI still compose, plus an honest record of whether real-device UAT was completed or blocked.

Files: `docs/OPERATOR-RUNBOOK.md`, `docs/HANDOFF.md`, `.gsd/REQUIREMENTS.md`

Do:
1. Load the `verify-before-complete` skill before making completion claims.
2. Run fresh regression checks from the repo root: `npm run server:build`; `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16'`; `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`; `! rg -n "comment|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift`.
3. Attempt real-device validation with `npm run ios:device` if the environment permits. On the iPhone, use the real app path: open an existing moment detail, add two private comments including multiline and Markdown-like literal text, delete one through the centered alert, confirm the parent moment remains visible, return to the main timeline and confirm no comment badge/count/dot/preview/search surface appears, then let sync clear pending state.
4. If device validation succeeds, collect non-secret durability evidence by copying the app Library container as described in the runbook and querying `local_comments` plus `outbox_operations`, then query the active dev server SQLite archive for `comments` and `sync_operations` comment rows. Do not include private comment body text in logs, docs, or summaries.
5. If device install, signing, trust, Tailscale/server reachability, simulator availability, or DB access fails, record the exact blocker and which checks still passed in `docs/HANDOFF.md`; do not mark R008/R010 validated from unavailable evidence.
6. If and only if the current-session evidence satisfies the requirement validation text, update `.gsd/REQUIREMENTS.md` through `gsd_requirement_update` for R008 and/or R010 rather than editing it manually.

Verify: `npm run server:build`; `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16'`; `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`; `! rg -n "comment|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift`; and, if feasible, `npm run ios:device` plus manual UAT/SQLite observations.

Done when: The executor has current-session evidence for each feasible verification path, has documented any unavailable real-device proof as a limitation, and has updated requirement status only where the evidence actually meets R008/R010 validation criteria.

Failure Modes:
| Dependency | On error | On timeout | On malformed response |
|------------|----------|------------|------------------------|
| Xcode/iPhone/server verification commands | Preserve the failing command, exit code, and last useful log lines in the task summary; do not proceed to validation claims based on stale output. | Stop that path, record timeout duration and likely blocker, and continue only with independent doc-safe checks. | Treat unexpected or partial command output as inconclusive and record it as a blocker rather than a pass. |
| Real-device UAT and copied SQLite/server archive | Document signing/trust/Tailscale/server/database blocker in `docs/HANDOFF.md`; keep requirements active if proof is missing. | Record the timeout phase and whether the app/server was reachable. | Do not infer pass from ambiguous DB rows; rerun or record as inconclusive. |

Load Profile:
- Shared resources: local build tools, iOS simulator/device, Mac dev server, SQLite archives.
- Per-operation cost: one server build, one simulator test run, one generic iOS build, optional install/UAT, and a few read-only SQLite aggregate queries.
- 10x breakpoint: Xcode build/device time and simulator availability, not app runtime throughput.

Negative Tests:
- Malformed inputs: UAT must include Markdown-like text such as `**bold**` or `- item` and confirm it stays literal plain text.
- Error paths: if sync or install fails, verify the failure is visible through pending/error state or command output without exposing comment text.
- Boundary conditions: delete exactly one selected comment and confirm the parent moment and remaining comments stay visible; timeline static check must remain empty.

Observability Impact:
- Signals added/changed: none; the task exercises existing `SyncBadge`, outbox status, SQLite tables, and command output diagnostics.
- How a future agent inspects this: `docs/OPERATOR-RUNBOOK.md`, `docs/HANDOFF.md`, local `local_comments`/`outbox_operations`, server `comments`/`sync_operations`, and build/test logs.
- Failure state exposed: failed/pending comment operations, install/build blockers, and explicit handoff limitations without private body logging.
  - Files: `docs/OPERATOR-RUNBOOK.md`, `docs/HANDOFF.md`, `.gsd/REQUIREMENTS.md`, `ios/PrivateMoments/Views/TimelineRow.swift`, `ios/PrivateMoments/Views/TimelineView.swift`
  - Verify: `npm run server:build`; `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16'`; `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`; `! rg -n "comment|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift`; optional `npm run ios:device` plus manual UAT and SQLite aggregate checks.

- [x] **T02: Update durable docs for shipped private comments** `est:1.5h`
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
  - Files: `docs/PRD.md`, `docs/TECH-DESIGN.md`, `docs/OPERATOR-RUNBOOK.md`, `docs/INTEGRATION-GUIDE.md`, `shared/sync-protocol.md`, `docs/HANDOFF.md`
  - Verify: `rg -n "schemaVersion\": 3|schemaVersion: 3|comment UI is not open|visible UI is not open|not open" docs/TECH-DESIGN.md docs/INTEGRATION-GUIDE.md docs/OPERATOR-RUNBOOK.md docs/PRD.md docs/HANDOFF.md shared/sync-protocol.md` returns no stale private-comment/schema-version hits; `rg -n "schemaVersion\": 4|SCHEMA_VERSION = 4|local_comments|outbox_operations|delete_comment|Private Comments" docs/TECH-DESIGN.md docs/INTEGRATION-GUIDE.md docs/OPERATOR-RUNBOOK.md shared/sync-protocol.md` shows expected anchors; `! rg -n "comment|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift`; rerun fresh build/test checks after final edits.

## Files Likely Touched

- docs/OPERATOR-RUNBOOK.md
- docs/HANDOFF.md
- .gsd/REQUIREMENTS.md
- ios/PrivateMoments/Views/TimelineRow.swift
- ios/PrivateMoments/Views/TimelineView.swift
- docs/PRD.md
- docs/TECH-DESIGN.md
- docs/INTEGRATION-GUIDE.md
- shared/sync-protocol.md
