# S04: Validation And Documentation

**Goal:** Prove the full Comments feature and update stable docs.
**Demo:** Current-session evidence shows the feature builds, syncs, migrates/recovers, and works on the real iPhone timeline; Chinese docs explain the behavior and operation boundaries.

## Must-Haves

- Server build and Prisma generation pass.
- iOS build passes.
- Server sync smoke checks cover create, duplicate replay, delete, missing/deleted parent rejection, and parent delete cascade behavior.
- iOS local SQLite migration creates `local_comments` safely.
- Recovery or equivalent SQLite inspection proves comments survive sync/reload paths and missing-parent apply does not advance cursor.
- Real iPhone UAT covers main timeline comment flow: comment button, bottom input bar, send-success scroll-to-moment-bottom feedback, send, latest-two preview, expand/collapse, search hit display, long-press delete, and parent moment delete cascade.
- Advanced Sync/outbox diagnostics show comment operation types/counts without comment body text.
- `docs/PRD.md`, `docs/TECH-DESIGN.md`, `docs/OPERATOR-RUNBOOK.md`, `docs/INTEGRATION-GUIDE.md`, `docs/DESIGN-PRINCIPLES.md`, and `docs/HANDOFF.md` are updated if behavior/contracts changed.

## Requirement Impact

- Owns R012.
- Supports R001 and R003.

## Threat Surface

- Privacy risk: verification notes must not log private comment body text or secrets.
- Overclaim risk: if real-device, signing, Tailscale, server, or DB access fails, record the blocker and keep missing proof explicit.

## Verification

- `npm run server:prisma:generate`
- `npm run server:build`
- `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- `npm run ios:device` when feasible.
- Read-only SQLite aggregate checks for `local_comments`, `outbox_operations`, server `comments`, and `sync_operations`, without selecting comment text.
- HTTP health check if the dev server is running: `curl -fsS http://127.0.0.1:3210/api/v1/health`

## Files Likely Touched

- `.gsd/REQUIREMENTS.md`
- `docs/PRD.md`
- `docs/TECH-DESIGN.md`
- `docs/OPERATOR-RUNBOOK.md`
- `docs/INTEGRATION-GUIDE.md`
- `docs/DESIGN-PRINCIPLES.md`
- `docs/HANDOFF.md`
