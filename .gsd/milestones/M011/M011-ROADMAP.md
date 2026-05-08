# M011: Pinned Moments — Roadmap

## Goal

Add a quiet pinned-moments shortcut shelf above Timeline. Pinned moments default to collapsed title rows, remain in their original chronological feed positions, and sync as lightweight post metadata.

## Slices

### S00 — Worktree And Data-Safety Boundary

**Status:** Design documented.

**Goal:** Keep pinned-moments design/build/package verification separate from the owner's active `main` version and live personal data.

**Outcome:** M011 work happens on branch `codex/pinned-moments-design` in `/Users/popcornnnnnn/.codex/worktrees/private-moments-pinned`. Server smoke tests must use isolated port/data. Real-device installs are blocked until a specific recovery checkpoint exists.

**Primary requirements:** R048.

### S01 — Pin Contract, Schema, And Sync

**Status:** Planned.

**Goal:** Represent pin state as synced post metadata.

**Outcome:** Add `isPinned` / `pinnedAt` to server and iOS post tables, define `update_post_pin`, emit/apply `post_pin_updated`, include pin fields in post baseline payloads, preserve pin metadata in export/import, and keep cursor advancement strict.

**Primary requirements:** R002, R003, R052.

### S02 — iOS Local Model And Pinned Shelf

**Status:** Planned.

**Goal:** Render pinned moments as a quiet shortcut shelf without disrupting Timeline chronology.

**Outcome:** `TimelinePost` carries pin metadata. Timeline derives `pinnedItems` after active filters, shows a top `Pinned` section when non-empty, defaults to collapsed title rows, persists collapsed/expanded state locally, and keeps originals in the normal feed.

**Primary requirements:** R003, R052.

### S03 — Pin And Unpin Actions

**Status:** Planned.

**Goal:** Add low-frequency controls for pin state changes.

**Outcome:** Moment Detail has a pin/unpin toolbar or menu action; Timeline row context/long-press menu can pin/unpin without adding permanent row chrome. Pinned title rows expose unpin through a swipe/context action, not a visible destructive-looking button.

**Primary requirements:** R052.

### S04 — Title Derivation And Empty-State Handling

**Status:** Planned.

**Goal:** Make collapsed rows useful even when a moment has no explicit heading.

**Outcome:** Pinned titles use first H1/H2, first body line, ready summary title, or media/date fallback. Title rows fit on small screens, do not overlap controls, and respect App Language for fallback labels.

**Primary requirements:** R052.

### S05 — Verification And UAT

**Status:** Planned.

**Goal:** Prove the feature without putting live data at risk.

**Outcome:** Run server tests/build, admin build if contracts/docs require it, generic iOS build, focused iOS tests, isolated server sync smoke, `npm run verify:uat-gates`, and real-device install only after Sync Health/outbox/recovery evidence. If real-device UAT is deferred, add an open UAT gate.

**Primary requirements:** R001, R002, R003, R048, R052.
