---
id: M002
title: "Private comments for moments"
status: complete
completed_at: 2026-04-29T20:10:33.025Z
key_decisions:
  - Represent private comments as first-class synced entities with `entityType: "comment"` rather than embedding them in post payloads.
  - Use separate idempotent `create_comment` and `delete_comment` operations for the first comment contract; defer edit/update semantics.
  - Include parent `postId` in iOS comment outbox payloads so parent moment sync status can be refreshed even when the operation entity is the comment.
  - Keep comment UI detail-only with plain `TextEditor`/`Text`, existing `SyncBadge`, and no timeline badges/counts/previews/search participation.
  - Keep draft submission and delete-selection policies Foundation-only and deterministic for unit testing.
  - Do not validate R008 from install/launch automation alone when the requirement explicitly needs manual iPhone gestures and populated aggregate evidence.
key_files:
  - server/src/api/sync.ts
  - server/prisma/schema.prisma
  - server/prisma/migrations/20260430190000_private_comments/migration.sql
  - shared/openapi.yaml
  - shared/sync-protocol.md
  - ios/PrivateMoments/Models/TimelinePost.swift
  - ios/PrivateMoments/Persistence/LocalDatabase+Schema.swift
  - ios/PrivateMoments/Persistence/LocalDatabase+Records.swift
  - ios/PrivateMoments/Persistence/LocalDatabase+Sync.swift
  - ios/PrivateMoments/Persistence/LocalDatabase+Timeline.swift
  - ios/PrivateMoments/Persistence/TimelineStore+Payloads.swift
  - ios/PrivateMoments/Persistence/TimelineStore+ServerChanges.swift
  - ios/PrivateMoments/Persistence/TimelineStore+Mutations.swift
  - ios/PrivateMoments/Views/MomentCommentsSection.swift
  - ios/PrivateMoments/Views/MomentDetailView.swift
  - ios/PrivateMomentsTests/CommentSyncPayloadTests.swift
  - ios/PrivateMomentsTests/MomentCommentUITests.swift
  - docs/PRD.md
  - docs/TECH-DESIGN.md
  - docs/OPERATOR-RUNBOOK.md
  - docs/INTEGRATION-GUIDE.md
  - docs/HANDOFF.md
lessons_learned:
  - First-class comment entities made idempotent sync, soft deletion, and future recovery clearer than embedding comments inside post payloads.
  - Detail-only UI features should be guarded by static timeline checks so feed density constraints remain mechanically verifiable.
  - Private-data UAT should use aggregate SQLite counts/statuses only and never log comment bodies.
  - Autonomous install/launch proof is useful real-device evidence, but it must not be substituted for manual tactile UAT when a requirement demands real iPhone gestures.
---

# M002: Private comments for moments

**Delivered private, synced, plain-text comments attached to moments in iOS Moment detail, with server/iOS sync plumbing, documentation, and automated plus real-device install verification while leaving manual iPhone create/delete UAT as an explicit follow-up.**

## What Happened

M002 added a small private-comment layer without changing the quiet main timeline. S01 established comments as first-class synced entities: the server gained a Prisma/SQLite comments model and migration, idempotent `create_comment` and `delete_comment` sync operations, `comment_created`/`comment_deleted` server changes, and shared OpenAPI/sync-protocol documentation. iOS gained `TimelineComment`, a `local_comments` table, comment payload builders, outbox plumbing, server-change application, and local create/delete transactions that preserve cursor safety by applying server changes before cursor advancement.

S02 consumed that contract in the user-facing iOS surface. Moment detail now renders private comments below the moment, provides a plain-text draft field, routes add/delete mutations through `TimelineStore`, preserves failed drafts for retry, and uses a centered confirmation alert for destructive deletion. The timeline remained intentionally untouched: static checks verified `TimelineRow.swift` and `TimelineView.swift` have no comment display/search/count/badge surface. UI behavior that must stay deterministic was factored into Foundation-only policy helpers and covered by XCTest.

S03 closed validation and documentation. It refreshed product, architecture, operator, integration, handoff, and sync-protocol docs to describe Private Comments as private, single-level, plain-text notes shown only in Moment detail. It added a repeatable operator UAT path with iPhone UI steps, local/server aggregate SQLite checks, static timeline checks, blocked-check handling, and privacy guidance to avoid logging comment bodies. Automated validation passed for server build, iOS simulator tests, generic iOS build, and static non-clutter checks. Real-device automation proved build/sign/install/launch on the paired iPhone, but autonomous auto-mode could not perform tactile iPhone add/delete gestures or produce populated aggregate DB evidence; that limitation is recorded as the remaining R008 validation follow-up rather than overclaimed.

## Success Criteria Results

- ✅ Private comments exist as durable, synced, plain-text data attached to moments. Evidence: S01 added server `comments` persistence, schema migration, idempotent sync operations, iOS `local_comments`, payloads, outbox plumbing, and server-change application; S01 verification passed server build, scripted sync smoke test, iOS build, and payload tests.
- ✅ The only user-facing comment UI is in Moment detail, not as timeline clutter. Evidence: S02 added `MomentCommentsSection` inside `MomentDetailView`; S02/S03 static checks `! rg -n "comment|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift` exited 0.
- ✅ Comment create/delete is retryable and idempotent through existing sync machinery. Evidence: S01 implemented separate `create_comment`/`delete_comment` operations, idempotent server operation handling, iOS outbox payload builders, and parent `postId` status propagation; S02 routed UI mutations through `TimelineStore` rather than direct row mutation.
- ✅ No social mechanics or rich text are introduced. Evidence: R010 is validated; S02 tests preserve Markdown-like text literally and implementation/docs exclude replies, likes, mentions, Markdown rendering, public identity, rich text, media, and thread affordances.
- ✅ Verification evidence covers server, iOS, and real-device behavior. Evidence: S03 passed `npm run server:build`, iOS simulator XCTest with 16 tests / 0 failures, generic iOS build, static timeline checks, and `npm run ios:device` build/sign/install/launch proof on `wwz 的 iphone`. Manual iPhone create/delete UAT remains a follow-up for R008 and is not claimed as complete validation.

## Definition of Done Results

- ✅ All roadmap slices are checked complete: S01, S02, and S03 are `[x]` in `.gsd/milestones/M002/M002-ROADMAP.md`.
- ✅ GSD DB state confirms all slices complete: `gsd_milestone_status(M002)` returned S01/S02/S03 status `complete` with all tasks done.
- ✅ Slice summaries exist: `.gsd/milestones/M002/slices/S01/S01-SUMMARY.md`, `S02-SUMMARY.md`, and `S03-SUMMARY.md` were found on disk.
- ✅ Code-change verification passed despite current branch being `main` with an empty self-diff: milestone-scoped commits touching `.gsd/milestones/M002` also touched non-`.gsd/` implementation/docs files including `server/src/api/sync.ts`, `server/prisma/schema.prisma`, `ios/PrivateMoments/Persistence/*`, `ios/PrivateMoments/Views/MomentCommentsSection.swift`, `ios/PrivateMoments/Views/MomentDetailView.swift`, `ios/PrivateMomentsTests/*`, `shared/openapi.yaml`, `shared/sync-protocol.md`, and `docs/*`.
- ✅ Cross-slice integration is coherent: S01 provided persistence/sync seams, S02 consumed them in Moment detail UI, and S03 documented/validated the assembled server/iOS/operator paths.
- ✅ No Horizontal Checklist was present in the roadmap.

## Requirement Outcomes

- R008 remains `active`. It was advanced by S01 persistence/sync work, S02 detail-view add/delete UI, and S03 docs/static/build/install evidence, but it was not marked validated because its acceptance criterion requires manual real-device UAT of comment creation/deletion and timeline non-clutter; autonomous auto-mode could not perform tactile iPhone gestures or produce populated aggregate DB evidence.
- R009 is `validated`. S01 validated private comment sync through idempotent operation-log semantics via server schema/migration, `create_comment`/`delete_comment`, server changes, iOS local persistence/outbox/server-change application, server build, scripted sync smoke test, iOS generic build, and payload XCTest coverage.
- R010 is `validated`. S03 validated the constraint through implementation boundaries, iOS XCTest coverage, static timeline non-clutter checks, and durable PRD/TECH-DESIGN/OPERATOR-RUNBOOK/INTEGRATION-GUIDE/sync-protocol documentation proving comments remain private, plain-text, single-level, and non-social.

## Deviations

Manual real-device Private Comments create/delete UAT could not be performed by autonomous auto-mode. The milestone closed with implementation, sync-contract, documentation, automated server/iOS verification, static timeline proof, and real-device install/launch evidence, while leaving R008 active for human validation rather than overclaiming it.

## Follow-ups

- Complete R008 manual UAT on the real iPhone: open Moment detail, add two private comments including multiline and Markdown-like literal text, delete one via centered alert, verify the parent moment and remaining comment stay visible, verify the main timeline remains uncluttered, let sync clear pending state, and record only aggregate `local_comments`/`outbox_operations` plus server `comments`/`sync_operations` counts.
- During that UAT, confirm the active schema-version-4 server SQLite database path because checked local archives during S03 did not expose a `comments` table.
- Consider a future recovery/reinstall validation pass after manual UAT data exists.
