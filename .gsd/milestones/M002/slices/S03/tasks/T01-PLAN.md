---
estimated_steps: 28
estimated_files: 5
skills_used: []
---

# T01: Run and record private-comment validation evidence

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

## Inputs

- `docs/OPERATOR-RUNBOOK.md`
- `docs/HANDOFF.md`
- `.gsd/REQUIREMENTS.md`
- `ios/PrivateMoments/Views/MomentCommentsSection.swift`
- `ios/PrivateMoments/Views/MomentDetailView.swift`
- `ios/PrivateMoments/Views/TimelineRow.swift`
- `ios/PrivateMoments/Views/TimelineView.swift`
- `server/src/config/app-config.ts`

## Expected Output

- `docs/HANDOFF.md`
- `.gsd/REQUIREMENTS.md`

## Verification

`npm run server:build`; `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16'`; `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`; `! rg -n "comment|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift`; optional `npm run ios:device` plus manual UAT and SQLite aggregate checks.

## Observability Impact

Exercises existing runtime diagnostics and state surfaces only: `SyncBadge`, `TimelineStore.errorMessage`, `local_comments`, `outbox_operations`, server `comments`, server `sync_operations`, and command output. No private comment text or secrets should be written to docs or summaries.
