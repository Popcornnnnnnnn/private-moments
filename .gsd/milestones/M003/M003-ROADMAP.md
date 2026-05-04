# M003: Feed Comments — Roadmap

## Goal

Deliver single-user, local-first Comments in the iOS main timeline with WeChat Moments-like interaction, durable sync, comment-aware search, and real-device verification.

## Slices

### S01 — Contract Reset And Supersession

**Goal:** Turn the discussion into a durable contract and explicitly supersede the old M002 detail-only comments direction.

**Outcome:** Future agents know that M003 is the active Comments plan, old M002 is reference-only, and implementation must not restore detail-only comment assumptions.

**Primary requirements:** R001, R002, R008, R009, R010, R011, R012.

### S02 — Comment Data And Sync

**Goal:** Add independent comment persistence and sync support on server and iOS.

**Outcome:** Comments can be created/deleted locally, queued through outbox, accepted idempotently by the server, applied from server changes cursor-safely, and recovered after migration/reinstall-equivalent flows.

**Primary requirements:** R009, R012.

### S03 — Timeline Comment Interaction

**Goal:** Build the main-timeline comment action row, comment preview/expand UI, bottom input bar, long-press deletion, and comment-aware search behavior.

**Outcome:** The user can create, read, expand, collapse, delete, and search comments from the main timeline without using Moment detail.

**Primary requirements:** R008, R010, R011.

### S04 — Validation And Documentation

**Goal:** Prove the full feature on current tools and update stable human-facing docs.

**Outcome:** Server/iOS builds, sync checks, migration/recovery evidence, real iPhone UAT, diagnostics review, and Chinese docs updates are recorded.

**Primary requirements:** R001, R003, R012.

## Completion Bar

- Server schema/migration and sync build pass.
- iOS schema, local persistence, outbox, and server-change handling build and are covered by focused tests or inspection.
- Main timeline comment UI compiles and works on a real iPhone when feasible.
- Comment search behavior is verified.
- `shared/openapi.yaml`, `shared/sync-protocol.md`, and affected Chinese docs are updated.
- Known limitations are recorded, especially any unavailable real-device or recovery proof.
