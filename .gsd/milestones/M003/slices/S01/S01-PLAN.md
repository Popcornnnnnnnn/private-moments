# S01: Contract Reset And Supersession

**Goal:** Establish M003 as the active Comments milestone and mark the old M002 detail-only comments direction as superseded/reference-only.
**Demo:** A future agent can read `.gsd` and understand the product, UI, sync, verification, and cleanup boundaries before writing code.

## Must-Haves

- M003 context states that old M002 detail-only private comments are superseded.
- `.gsd/DECISIONS.md` records the key product, UI, sync, search, verification, and cleanup choices.
- `.gsd/REQUIREMENTS.md` contains active requirements for timeline comments, sync/recovery, content constraints, search, and validation.
- `.gsd/PROJECT.md` and `.gsd/STATE.md` identify M003 as the next active planning direction.
- No code implementation starts in this slice.

## Requirement Impact

- Supports R001 by creating durable planning context.
- Satisfies R002 by creating milestone/slice planning before schema/sync/UI implementation.
- Defines R008 through R012 for downstream slices.

## Threat Surface

- Low runtime risk because this slice writes planning artifacts only.
- High process risk if it accidentally revives old M002 assumptions or leaves the active direction ambiguous.

## Verification

- Inspect `.gsd/milestones/M003/M003-CONTEXT.md`.
- Inspect `.gsd/milestones/M003/M003-ROADMAP.md`.
- Inspect `.gsd/DECISIONS.md`, `.gsd/REQUIREMENTS.md`, `.gsd/PROJECT.md`, and `.gsd/STATE.md`.
- Confirm old M002 remains superseded/reference-only rather than active implementation guidance.

## Files Likely Touched

- `.gsd/DECISIONS.md`
- `.gsd/PROJECT.md`
- `.gsd/REQUIREMENTS.md`
- `.gsd/STATE.md`
- `.gsd/milestones/M003/M003-CONTEXT.md`
- `.gsd/milestones/M003/M003-ROADMAP.md`
- `.gsd/milestones/M003/slices/S01/S01-PLAN.md`
