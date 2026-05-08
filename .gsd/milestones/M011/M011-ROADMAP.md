# M011: Pinned Moments — Roadmap

## Goal

Add a quiet pinned-moments shortcut shelf above Timeline. Pinned moments default to a collapsed summary header, are hidden from the ordinary unfiltered Timeline list while the shelf is visible, keep their original time semantics everywhere else, and sync as lightweight post metadata.

## Slices

### S00 — Worktree And Data-Safety Boundary

**Status:** Design documented.

**Goal:** Keep pinned-moments design/build/package verification separate from the owner's active `main` version and live personal data.

**Outcome:** M011 work happens on branch `codex/pinned-moments-design` in `/Users/popcornnnnnn/.codex/worktrees/private-moments-pinned`. Server smoke tests must use isolated port/data. Real-device installs are blocked until a specific recovery checkpoint exists.

**Primary requirements:** R048.

### S01 — Pin Contract, Schema, And Sync

**Status:** Implemented.

**Goal:** Represent pin state as synced post metadata.

**Outcome:** Add `isPinned` / `pinnedAt` to server and iOS post tables, define `update_post_pin`, emit/apply `post_pin_updated`, include pin fields in post baseline payloads, preserve pin metadata in export/import, and keep cursor advancement strict.

**Primary requirements:** R002, R003, R052.

### S02 — iOS Local Model And Pinned Shelf

**Status:** Implemented.

**Goal:** Render pinned moments as a quiet shortcut shelf without duplicating full rows at the top of the unfiltered Timeline.

**Outcome:** `TimelinePost` carries pin metadata. Timeline derives `pinnedItems` only when no Timeline search/filter state is active, shows a top `Pinned · N` header when non-empty, defaults to collapsed, persists the one-to-three expanded/collapsed state locally, shows up to three title rows when expanded, and removes those pinned items from the ordinary unfiltered Timeline list while preserving them in search/filter, Calendar, Day Review, and review semantics.

**Primary requirements:** R003, R052.

### S03 — Pin And Unpin Actions

**Status:** Implemented.

**Goal:** Add low-frequency controls for pin state changes.

**Outcome:** Moment Detail has pin/unpin inside a top `More` menu; Timeline row context/long-press menu can pin/unpin without adding permanent row chrome. Pinned title rows and pinned sheet rows expose unpin through context actions, not visible destructive-looking buttons.

**Primary requirements:** R052.

### S04 — Title Derivation And Empty-State Handling

**Status:** Implemented.

**Goal:** Make collapsed rows and pinned sheet rows useful even when a moment has no explicit heading.

**Outcome:** Pinned titles use first H1/H2, first body line, ready summary title, or media/date fallback. Title rows may include a light occurred-date accessory but no body/media/comment/tag preview. Rows fit on small screens, do not overlap controls, and respect App Language for fallback labels.

**Primary requirements:** R052.

### S04.5 — More-Than-Three Pinned Sheet

**Status:** Implemented.

**Goal:** Keep the Timeline top surface compact when many moments are pinned.

**Outcome:** When more than three visible pinned moments exist and Timeline has no active filters, the `Pinned · N` header opens a bottom sheet with the complete pinned title list. The sheet owns an internal navigation stack, so selecting a row pushes full `MomentDetailView` inside the sheet and Back returns to the pinned list.

**Primary requirements:** R052.

### S05 — Verification And UAT

**Status:** Implementation validation in progress.

**Goal:** Prove the feature without putting live data at risk.

**Outcome:** Run server tests/build, admin build if contracts/docs require it, generic iOS build, focused iOS tests, isolated server sync smoke, `npm run verify:uat-gates`, and simulator UI/interaction validation for the pinned header, expansion preference, more-than-three sheet, sheet detail navigation, and context-menu pin/unpin flows. Real-device install happens only after Sync Health/outbox/recovery evidence. If real-device UAT is deferred, add an open UAT gate.

**Primary requirements:** R001, R002, R003, R048, R052.
