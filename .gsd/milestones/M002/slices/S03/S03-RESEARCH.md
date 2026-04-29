# S03 — Research

**Date:** 2026-04-30

## Summary

S03 is a targeted validation/documentation slice, not a new architecture slice. S01 already delivered the comment sync/data contract and marked R009 validated; S02 delivered the iOS Moment detail UI and advanced R008/R010. S03 should close the remaining active requirements by proving the full user path on a real iPhone when feasible, documenting any gap honestly, and updating stale human-facing docs so they describe comments as a shipped detail-view feature rather than contract-only groundwork.

The most important finding is doc drift: `docs/TECH-DESIGN.md` still says comment infrastructure exists but the visible UI is not open, and `docs/INTEGRATION-GUIDE.md` still shows `schemaVersion: 3` in an example while the server constant is now `SCHEMA_VERSION = 4`. The operator runbook has real-device install and database-copy sections, but no private-comment UAT path or SQL checks for `local_comments` / comment outbox state. S03 should prioritize these documentation corrections and a repeatable UAT checklist.

Skill guidance applied: `write-docs` says trunk docs must be written for a cold reader and avoid brittle file paths in long-lived prose; use behavior/module names in docs, not implementation line references. `verify-before-complete` says S03 cannot be claimed complete without fresh evidence after the final doc/code change; if real-device verification is not feasible, record the limitation instead of overclaiming.

## Recommendation

Build S03 as two thin tasks: first create/record the validation evidence, then update docs and requirement status from that evidence. Do not add new product scope, Admin comment management, search, exports, editing, replies, rich text, or timeline indicators.

Recommended validation flow:

1. Run server/iOS build regression checks after any doc-safe code checks or before UAT:
   - `npm run server:build`
   - `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`
   - optional focused simulator tests: `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16'`
2. Install/launch on the paired iPhone with `npm run ios:device` once the Mac server is reachable. The script auto-detects Tailscale DNS/IP/LAN and prints the server URL to enter in app Settings.
3. On iPhone, run UAT from `Moments` timeline → existing moment detail:
   - add two plain multiline comments and confirm oldest-first display;
   - include Markdown-like characters such as `**bold**` or `- item` and confirm they remain literal text;
   - delete one comment through the centered alert and confirm the parent moment remains visible;
   - return to main timeline and confirm there is no comment count/badge/dot/preview/search surface;
   - sync against the Mac server and confirm pending state clears when online.
4. Copy the iPhone Library container and inspect SQLite for durable local state. Add these checks to the runbook rather than relying only on visual inspection:
   ```sql
   SELECT COUNT(*) AS visible_comments FROM local_comments WHERE deletedAt IS NULL;
   SELECT COUNT(*) AS deleted_comments FROM local_comments WHERE deletedAt IS NOT NULL;
   SELECT COUNT(*) AS pending_comment_ops FROM outbox_operations WHERE entityType='comment' AND status='pending';
   SELECT COUNT(*) AS failed_comment_ops FROM outbox_operations WHERE entityType='comment' AND status='failed';
   ```
5. Inspect the Mac server archive if a local dev DB is used:
   ```sql
   SELECT COUNT(*) AS visible_comments FROM comments WHERE deleted_at IS NULL;
   SELECT COUNT(*) AS deleted_comments FROM comments WHERE deleted_at IS NOT NULL;
   SELECT type, rejected_at, rejection_reason FROM sync_operations WHERE entity_type='comment' ORDER BY received_at DESC LIMIT 10;
   ```
6. Preserve the existing static non-clutter proof for S03 completion evidence:
   - `! rg -n "comment|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift`

If real-device install or Tailscale connectivity fails, S03 should still update docs with the intended UAT path and record the blocker in the slice summary/known limitations; do not mark real-device behavior validated.

## Implementation Landscape

### Active Requirements Targeted

- **R008** — S03 should validate the real-device detail-view add/delete path and main timeline non-clutter. If UAT passes, update R008 validation text from active to validated.
- **R010** — S03 should validate/document plain-text single-level constraints. If UAT/static checks pass, update R010 validation text from active to validated.
- **R009** — Already validated by S01, but S03 should reuse its sync contract evidence and add end-to-end UI/device evidence rather than changing the contract.

### Key Files

- `docs/PRD.md` — Product/user-story doc. Add a concise private-comments user story under detail/viewing behavior or product goals: comments are private plain-text follow-up notes in Moment detail only; no social mechanics, no rich text, no timeline density.
- `docs/TECH-DESIGN.md` — Architecture doc. Update stale text that says comment UI is not open. Describe current state: comments are first-class synced entities, iOS has `local_comments`, Moment detail is the only user-facing surface, parent post deletion cascades/hides comments, schema version is 4.
- `docs/OPERATOR-RUNBOOK.md` — Best place for the S03 UAT procedure. Add a “Private comments UAT” section near real-device verification with iPhone steps, sync/server prerequisites, and SQL checks for local/server comment durability and outbox status.
- `docs/INTEGRATION-GUIDE.md` — Contract doc already has comment operation examples. Fix stale `schemaVersion: 3` example to 4 and consider adding that `delete_comment` payload should include `postId` when produced by iOS, even though the server currently derives `postId` from the existing comment for the server change.
- `docs/HANDOFF.md` — Update current state and next steps after S03: private comments shipped/verified if UAT passes, or list exact remaining verification gap if not.
- `shared/sync-protocol.md` — Already has a good Private Comments section. It says `delete_comment` payload only has `deletedAt`; S01 established iOS includes `postId` in both create/delete payloads for parent sync-status refresh. Consider adding an optional `postId` note if docs should reflect client behavior.
- `ios/PrivateMoments/Views/MomentCommentsSection.swift` — Current UI behavior: `Private Comments` section, empty state, `TextEditor`, `Add`, plain `Text` rendering, row `SyncBadge`, trash button with accessibility hint. No S03 code change expected unless UAT exposes a bug.
- `ios/PrivateMoments/Views/MomentDetailView.swift` — Current integration point: comments section appears below content/media; add calls `TimelineStore.createComment`; delete uses centered `alert("Delete this private comment?")` and `TimelineStore.deleteComment`.
- `ios/PrivateMoments/Views/TimelineRow.swift` and `ios/PrivateMoments/Views/TimelineView.swift` — Should remain untouched by comments; use static `rg` check as non-clutter proof.
- `ios/PrivateMoments/Persistence/LocalDatabase+Records.swift` — `fetchComments(postId:)` returns non-deleted comments `ORDER BY createdAt ASC`, which proves oldest-first source ordering for UI.
- `ios/PrivateMoments/Persistence/TimelineStore+Mutations.swift` — `createComment` trims text, inserts local comment + outbox operation, reloads, and kicks sync; `deleteComment` soft-deletes locally + queues `delete_comment`.
- `server/src/api/sync.ts` — Server rejects empty comment text, missing/deleted parent posts, duplicate comment ids, and emits `comment_created` / `comment_deleted` changes. No S03 code change expected unless validation finds a bug.
- `server/src/config/app-config.ts` — Source of truth for current server schema version: `SCHEMA_VERSION = 4`.
- `.gsd/REQUIREMENTS.md` — Update R008/R010 after S03 evidence using `gsd_requirement_update`, not by editing directly.

### Build Order

1. **Evidence design first:** write/confirm a UAT checklist before touching docs so docs reflect what was actually verified. Use the runbook as the durable home for the checklist.
2. **Run validation second:** server build, iOS build/test, real-device install/UAT when feasible, SQLite/server DB checks, static timeline non-clutter check.
3. **Docs third:** update PRD/TECH-DESIGN/OPERATOR-RUNBOOK/INTEGRATION-GUIDE/HANDOFF with the verified behavior and any limitations. Apply `write-docs` cold-reader rule: docs should tell a future operator/product reader what to do or what invariant to preserve, not retell S01/S02 implementation history.
4. **Requirement closure last:** only update R008/R010 to validated if evidence exists in the current session. Then complete S03 with `gsd_task_complete`/`gsd_slice_complete` as applicable.

### Verification Approach

Use fresh commands after the final file change before claiming completion:

```bash
npm run server:build
cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16'
cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build
! rg -n "comment|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift
```

Real-device verification command/path:

```bash
npm run ios:device
```

Then perform manual iPhone UAT and record what was observed. For local database evidence, use the existing runbook `xcrun devicectl device copy from ... --source Library` pattern and query the copied SQLite database for `local_comments` and comment outbox rows. For server archive evidence, query the active development SQLite database used by `DATABASE_URL` / `PRIVATE_MOMENTS_DATA_DIR`; do not hard-code personal paths into docs.

### Constraints

- Docs under `docs/` should be primarily Chinese, with command names/API fields/UI strings in English where clearer.
- App-facing UI copy remains English; S03 docs should not propose changing `Private Comments`, `Add`, or alert text unless UAT finds a bug.
- Main timeline simplicity is a hard constraint. Any S03 fix that adds timeline badges/counts/previews is out of scope and would violate R008/R010.
- No secrets in docs or verification logs. The password comes from `server/.env` but should never be copied into reusable docs or summaries.
- Real-device proof is expected when feasible. If blocked by signing, device trust, Tailscale reachability, or server startup, record the exact blocker rather than claiming the milestone is operationally validated.
- Long-lived docs should avoid brittle implementation paths/line numbers in prose. Runbook command snippets and SQL table names are acceptable because they are actionable operator material.

## Common Pitfalls

- **Overclaiming real-device validation** — S02 only has simulator/generic build/static proof. S03 must either produce fresh iPhone evidence or explicitly document the gap.
- **Leaving docs stale** — `TECH-DESIGN` currently says comment UI is not open and `INTEGRATION-GUIDE` has `schemaVersion: 3`; both should be corrected.
- **Forgetting parent-post cascade proof** — The server Prisma relation uses `onDelete: Cascade`, iOS `fetchTimelineItem` hides deleted posts, and comments fetch excludes deleted comments, but UAT/docs should explicitly state that deleting a parent moment hides its comments and no orphan comment UI appears.
- **Testing only visual UI** — add SQLite/server checks so S03 proves durability/sync, not only that a row appeared in SwiftUI.
- **Adding docs that sound social** — describe comments as private follow-up notes, not social comments, engagement, threads, or conversations.

## Open Risks

- Real-device UAT may be blocked by signing/trust, unavailable device, or Mac server reachability. The existing `npm run ios:device` script has useful failure messages for these cases.
- Full delayed/offline retry behavior is harder to prove manually in S03 without controlled network toggling. At minimum, verify pending comment outbox creation and successful sync; document any unexercised retry/reinstall recovery gaps.
- Server-side idempotent replay was already smoke-tested in S01, but there is no obvious committed test script in the repo. If S03 needs repeatable replay proof, an executor may need to add a small script or document the manual sync replay request.

## Skills Discovered

| Technology | Skill | Status |
|------------|-------|--------|
| Documentation | `write-docs` | installed; used for S03 doc approach |
| Verification | `verify-before-complete` | installed; used for S03 completion gate |
| SwiftUI | `avdlee/swiftui-agent-skill@swiftui-expert-skill` | available via `npx skills add`; not needed unless UAT exposes UI bugs |
| Fastify | `mcollina/skills@fastify-best-practices` | available via `npx skills add`; not needed unless server sync bugs are found |
