# M002: Private comments for moments

**Gathered:** 2026-04-30
**Status:** Ready for planning

## Project Description

Add a small private-comment layer to Moments so the user can attach follow-up thoughts to an existing moment while keeping the app local-first, synced, quiet, and non-social.

Private comments are private plain-text, single-level notes attached to a moment. They are not social comments: no replies, likes, mentions, public author identity, rich text, Markdown rendering, media attachments, or comment search/export in this milestone. They should feel like a lightweight follow-up log for personal reflection, not a writing editor or management database.

## Why This Milestone

Moments is meant to be “一个没有观众的生活表达空间”: social-feed ease without social pressure, diary-level privacy without diary heaviness, and feed-like immersive browsing over a flowing personal timeline. A captured moment may later need a small appended thought, clarification, or after-feeling without rewriting the original moment.

This milestone solves that by adding private follow-up comments directly under the moment in detail view. It exists now because comments are user data and must be designed with local-first durability, sync semantics, schema migration, and recovery behavior from the beginning rather than being bolted on as local-only UI state later.

## User-Visible Outcome

### When this milestone is complete, the user can:

- Open an existing moment on a real iPhone, add a plain multiline private comment inline in Moment detail, and see it appear under that moment.
- Add multiple private comments and see them ordered oldest-first, like a natural follow-up log.
- Delete a private comment through a confirmation alert and have the deletion sync to the Mac server.
- Delete a parent moment without comment lifecycle friction; its comments cascade with the moment and do not remain visible as orphan UI.
- Continue browsing the main timeline without comment badges, counts, or other density changes.

### Entry point / environment

- Entry point: iOS app `Moments` → main timeline → `MomentDetailView` for an existing moment.
- Environment: mobile real-device flow backed by local dev / private Mac server on the Tailscale or private-network boundary.
- Live dependencies involved: iOS local SQLite database, iOS outbox sync, Mac Fastify server, Prisma/SQLite archive, `POST /api/v1/sync`; no third-party service dependency beyond the private network path.

## Completion Class

- Contract complete means: shared OpenAPI and sync protocol define comment operations/server changes; server tests or scripted sync checks prove idempotent `create_comment` and `delete_comment` operations; iOS code can encode, store, send, and apply comment payloads without advancing sync cursor before durable local persistence succeeds.
- Integration complete means: iOS Moment detail, local SQLite comment storage, outbox operations, server sync, Prisma/SQLite archive, and server-change application work together for create/delete and parent-moment cascade behavior.
- Operational complete means: the flow is verified on a real iPhone when feasible, including install/build evidence, local persistence, retry/idempotency behavior, and recovery-sensitive sync behavior. If real-device verification is not possible, the limitation must be explicitly documented rather than overclaimed.

## Final Integrated Acceptance

To call this milestone complete, we must prove:

- On a real iPhone, create a moment comment from Moment detail, sync it through the Mac server, and confirm it remains attached to that moment without adding timeline badges/counts or timeline clutter.
- Delete a private comment from Moment detail through a confirmation alert, sync the deletion, and confirm it is removed locally and on the server while the parent moment remains visible.
- Exercise idempotent sync by replaying or retrying comment create/delete operations and showing accepted/replayed operations do not duplicate comments or corrupt cursor state.
- Confirm parent moment deletion cascades/hides/deletes associated comments so no orphan comments appear in iOS UI.
- What cannot be simulated if this milestone is to be considered truly done: the tactile iPhone Moment detail flow, delayed/offline retry behavior, and app reinstall/recovery-sensitive persistence should be verified on the paired real device when feasible.

## Architectural Decisions

### Private comments product and data shape

**Decision:** Implement comments as private plain-text, single-level notes attached to a moment, synced like other local-first metadata; do not introduce replies, likes, mentions, media attachments, rich text, Markdown rendering, public author identity, or multi-user author presentation.

**Rationale:** This provides the follow-up-comment affordance the user wants while preserving Moments as a private expression space rather than adding social mechanics or turning the app into a writing editor.

**Alternatives Considered:**
- Social-style comments with replies/likes/mentions — not chosen because Moments has no audience and should not import social feedback mechanics.
- Rich text or Markdown comments — not chosen because comments should remain lightweight expression, consistent with prior plain-text decisions.
- Embedding comments into post text or post payloads — not chosen because comments need independent create/delete sync, idempotency, and local persistence.

---

### Moment detail is the only user-facing comment surface

**Decision:** The only user-facing comment UI in this milestone is iOS Moment detail. The main timeline remains uncluttered with no comment count, badge, dot, or preview. Admin UI comment management is out of scope unless strictly needed for diagnostics.

**Rationale:** Main timeline simplicity is a design constraint. Comments are low-frequency follow-up thoughts and belong under the moment, not in the feed. Keeping the surface to detail view protects the quiet browsing experience.

**Alternatives Considered:**
- Timeline comment hints or counts — not chosen because they increase feed density and make comments feel like social engagement metadata.
- Admin read-only comment views — not chosen for the first milestone because they add Mac UI/API surface beyond the core iOS personal flow.
- Action-menu-only hidden comments — not chosen because discoverability and quick follow-up would be too weak.

---

### Inline quick-note interaction

**Decision:** Adding a comment should feel like an inline quick note in Moment detail: a small plain-text input near the comments section, with comments shown under the moment.

**Rationale:** Inline input keeps comments lightweight and close to the moment. It avoids the ceremony of a separate writing sheet while still making follow-up thoughts easy to add.

**Alternatives Considered:**
- Dedicated compose sheet — not chosen because it makes comments feel more like a separate writing feature.
- Toolbar/action menu only — not chosen because it hides the feature and makes adding a follow-up thought take more taps.

---

### Comment ordering

**Decision:** Display multiple comments oldest-first in Moment detail.

**Rationale:** Oldest-first feels like a natural follow-up log attached to the moment: earlier reflections appear before later thoughts, preserving personal time flow.

**Alternatives Considered:**
- Newest-first — not chosen because it optimizes recency over diary-like continuity.
- Unspecified implementation order — not chosen because implicit ordering can surprise later and makes tests weaker.

---

### Comment deletion UX

**Decision:** Deleting a comment should use a confirmation alert before the comment is soft-deleted and synced.

**Rationale:** Comments are personal text. A small confirmation prevents accidental loss while staying consistent with the app’s cautious deletion posture.

**Alternatives Considered:**
- Immediate delete — not chosen because accidental taps/swipes could remove a thought with no recovery UI.
- Undo snackbar — not chosen for the first version because it adds more state and UI scope than needed.

---

### Parent moment deletion cascades comments

**Decision:** Comments require an existing non-deleted parent moment. When a parent moment is deleted, its comments cascade with that moment and must not appear as orphan comments in UI.

**Rationale:** Comments are subordinate follow-up notes, not independent records. Cascading avoids lifecycle blockers, orphan UI, and archive-management complexity.

**Alternatives Considered:**
- Keep archived comments after parent deletion — not chosen because it complicates restore/export semantics and creates invisible orphan data questions.
- Block post deletion when comments exist — not chosen because it adds friction and turns comments into lifecycle blockers.

## Error Handling Strategy

Comment operations should reuse the existing local-first sync error model:

- iOS queues `create_comment` and `delete_comment` as outbox operations with stable `opId`s and retries them through the existing delayed retry/backoff flow.
- Server validates comment operations strictly: `create_comment` requires `postId`, non-empty plain text, and a live parent post; `delete_comment` requires an existing comment whose parent post is not deleted.
- Replayed operations with the same `(deviceId, opId)` remain idempotent and do not duplicate comments.
- Malformed or rejected operations return explicit rejected-op reasons without leaking secrets.
- iOS must parse and apply `comment_created` / `comment_deleted` server changes durably before advancing `lastSyncCursor`, preserving the recovery safety learned from prior sync cursor issues.
- Unknown server changes may remain ignored where appropriate, but recognized comment changes should fail loudly if required fields or dates are invalid so cursor advancement is blocked until the problem is fixed.
- User-facing failures should follow existing sync behavior: the comment or parent moment can show pending/failed sync state; retry is automatic where the existing outbox retry machinery applies. Avoid adding noisy alerts for transient network failures.
- Deleting a comment uses a confirmation alert. Empty or whitespace-only comment input should be rejected/disabled in UI before queueing.

## Risks and Unknowns

- iOS local comment plumbing is not complete yet — without a `local_comments` table, records, payload helpers, and server-change handling, the already-started server contract cannot be safely consumed.
- Sync cursor safety is critical — if iOS fails to parse/apply a comment change but still advances `lastSyncCursor`, comments could appear lost after recovery.
- Parent post sync status may need adjustment — comment outbox operations use `entityId = commentId`, while current post status refresh logic is post-entity-oriented; the parent moment still needs accurate pending/failed feedback.
- Real-device verification may expose UI/timing issues that simulator or server smoke tests cannot catch, especially around delayed retry and detail-view state refresh.
- Scope creep risk is high because “comments” can imply social or management features; this milestone must stay detail-only, plain-text, synced create/delete.

## Existing Codebase / Prior Art

- `.gsd/milestones/M002/M002-ROADMAP.md` — existing milestone roadmap with S01 data/sync, S02 detail UI, and S03 validation/documentation slices.
- `.gsd/milestones/M002/slices/S01/S01-PLAN.md` — current slice plan for comment data model and sync contract.
- `.gsd/milestones/M002/slices/S01/tasks/T01-SUMMARY.md` — implementation map of server/iOS sync and persistence seams.
- `.gsd/milestones/M002/slices/S01/tasks/T02-SUMMARY.md` — records that server-side comment schema, sync operations, schema version bump, OpenAPI, and sync protocol changes have started.
- `server/prisma/schema.prisma` — now includes `Comment` as a first-class server entity related to `Post` and `Device` with soft-delete and `serverVersion`.
- `server/prisma/migrations/20260430190000_private_comments/migration.sql` — creates the server `comments` table and indexes.
- `server/src/api/sync.ts` — central sync handler; now includes server-side `create_comment` and `delete_comment` operation branches.
- `server/src/config/app-config.ts` — server schema version has been bumped for comment schema changes.
- `shared/openapi.yaml` — sync operation contract now includes comment operation/change semantics.
- `shared/sync-protocol.md` — sync semantics documentation now describes private comments.
- `ios/PrivateMoments/Views/MomentDetailView.swift` — target UI surface for displaying, adding, and deleting private comments.
- `ios/PrivateMoments/Persistence/LocalDatabase+Schema.swift` — iOS local SQLite migration surface that needs a `local_comments` table.
- `ios/PrivateMoments/Persistence/LocalDatabase+Records.swift` — local record/outbox helpers that need comment record support.
- `ios/PrivateMoments/Persistence/LocalDatabase+Sync.swift` — outbox/server-change application path and post sync status logic affected by comment operations.
- `ios/PrivateMoments/Persistence/TimelineStore+Payloads.swift` — payload encoding area for new comment operations.
- `ios/PrivateMoments/Persistence/TimelineStore+ServerChanges.swift` — must parse/apply `comment_created` and `comment_deleted` without unsafe cursor advancement.
- `ios/PrivateMoments/Networking/APIModels.swift` — generic sync models already carry JSON payloads and can carry comment operation payloads.
- `docs/TECH-DESIGN.md`, `docs/INTEGRATION-GUIDE.md`, `docs/OPERATOR-RUNBOOK.md`, `docs/HANDOFF.md` — human-facing docs that may need Chinese updates when behavior, schema, sync, or verification guidance changes.

## Relevant Requirements

- R001 — This milestone must close with change summary, verification evidence, known issues/next steps, and fact-source/human-facing doc updates where affected.
- R002 — This milestone affects schema migrations, sync semantics, and cross-device behavior, so milestone/slice planning is required before implementation.
- R003 — Verification must include server build/API checks, iOS build, and real-device verification when feasible because this crosses sync/storage/UI boundaries.
- R008 — Advances the requirement that a user can add and delete private plain-text comments on an existing moment from iOS Moment detail without changing main timeline feed density.
- R009 — Advances the requirement that private comments sync through the Mac server using idempotent operation-log semantics and converge across authorized devices.
- R010 — Enforces the constraint that private comments remain plain text and single-level with no replies, likes, mentions, Markdown rendering, public author identity, or social feedback features.

## Scope

### In Scope

- Server Prisma/SQLite schema for private comments.
- Server sync support for idempotent `create_comment` and `delete_comment` operations.
- Server-change payloads for `comment_created` and `comment_deleted`.
- Shared OpenAPI and sync protocol updates for comment operation/change shapes.
- iOS SQLite `local_comments` persistence with soft-delete support.
- iOS outbox payload support for comment create/delete.
- iOS server-change application for comment create/delete with cursor-safety preservation.
- iOS Moment detail UI for viewing comments, adding inline plain multiline comments, and deleting comments through a confirmation alert.
- Oldest-first comment ordering in Moment detail.
- Parent moment deletion cascade/hide behavior for comments.
- Build, sync/API, and real-device UAT evidence when feasible.
- Human-facing docs updates where behavior, operation, or integration contracts changed.

### Out of Scope / Non-Goals

- Replies/threading.
- Likes, mentions, public author display, or social feedback features.
- Rich text, Markdown rendering, headings, bold, quotes, link previews, or comment media attachments.
- Comment editing in the first version.
- Timeline comment count, badge, dot, preview, or any main-feed density change.
- Admin UI comment management, unless a minimal diagnostic is strictly necessary.
- Search enhancements, export workflows, or AI search over comments.
- Sharing workflows.
- Multi-user collaboration semantics beyond existing authorized-device sync.

## Technical Constraints

- Work only inside `private-moments/`.
- App-facing UI copy should stay primarily English unless explicitly requested otherwise.
- Human-facing docs under `docs/` should be primarily Chinese while preserving commands, API routes, field names, filenames, and UI copy in English where clearer.
- Main timeline simplicity is a hard design constraint; low-frequency controls belong in detail/settings/menus rather than the feed.
- Comments must stay local-first and durable; they cannot be UI-only transient state.
- Sync endpoint remains `POST /api/v1/sync`.
- `opId` remains idempotent per device.
- `lastSyncCursor` must advance only after all returned server changes are applied.
- iOS must parse ISO8601 values with and without fractional seconds.
- Server schema version is now `4` after comment schema introduction.
- Development server port remains `3210`.
- Do not hard-code personal Tailscale values into reusable code or docs.

## Integration Points

- iOS Moment detail UI — displays comments, inline add field, oldest-first ordering, and delete confirmation.
- iOS local SQLite — stores comments in a local table with soft-delete and parent `postId` linkage.
- iOS outbox — queues `create_comment` / `delete_comment` operations and participates in existing retry/backoff behavior.
- iOS server-change application — applies `comment_created` / `comment_deleted` before cursor advancement.
- Mac Fastify sync API — receives local comment operations through `POST /api/v1/sync`.
- Server Prisma/SQLite archive — persists comments, soft deletes, server versions, and parent post relation.
- Shared OpenAPI contract — documents sync operation enum and payload/change semantics.
- Shared sync protocol docs — documents idempotency, payloads, and comment lifecycle behavior.
- Operator/product docs — describe the feature, constraints, setup/verification implications, and known limitations.

## Testing Requirements

Testing should cover contract, integration, and operational behavior:

- Server build/typecheck must pass after schema and sync changes.
- Prisma client generation and migration deployment must be verified for the new `comments` table.
- A focused server sync smoke test or equivalent test must prove:
  - `create_comment` requires a live parent post and non-empty text.
  - replaying the same `opId` does not duplicate a comment.
  - `delete_comment` soft-deletes the comment and emits a server change.
  - rejected comment operations return clear reasons.
- iOS build must pass after local persistence and UI changes.
- iOS persistence/server-change tests or focused inspection must prove:
  - comments are stored durably under `postId`.
  - `comment_created` and `comment_deleted` apply correctly.
  - invalid recognized comment changes fail before `lastSyncCursor` advances.
  - parent moment deletion hides/cascades associated comments.
- Real-device UAT should prove:
  - add comment inline from Moment detail.
  - see comments ordered oldest-first.
  - delete comment through confirmation alert.
  - main timeline remains uncluttered.
  - sync/retry behavior works against the Mac server when feasible.

## Acceptance Criteria

- S01 acceptance: server, shared contract, and iOS local sync plumbing support private comments without visible UI; create/delete comment operations are idempotent and documented; iOS can persist/apply comment changes safely.
- S02 acceptance: iOS Moment detail includes a quiet comments section, inline quick-note add flow, oldest-first display, plain multiline validation, and confirmation-based comment delete; main timeline remains unchanged.
- S03 acceptance: final UAT and docs prove the full create/delete/sync/cascade path and record limitations, especially any real-device verification gaps.
- The implementation satisfies R008, R009, and R010 without introducing out-of-scope social, rich-text, Admin-management, or timeline-density features.

## Open Questions

- Whether comment edit should be added later — current thinking: explicitly out of scope for the first version to keep idempotency and UI simple.
- Whether Admin should ever show comments for diagnostics — current thinking: not in M002 unless future troubleshooting proves it is necessary.
- Whether comments should participate in future search/export — current thinking: defer until a broader search/export milestone can preserve the product’s “expression, not database” boundary.
- How much real-device verification is feasible during S03 — current thinking: real-device UAT is expected when feasible, and any inability must be documented rather than overclaimed.
