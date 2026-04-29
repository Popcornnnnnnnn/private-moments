# Private Moments Workflow

This document explains how to keep Private Moments maintainable over time. It is for the future maintainer or agent who opens the project cold and needs to decide how to plan, verify, and document work.

After reading this, the maintainer should be able to choose the right work track, know which facts must be updated, and close a change without losing context.

## Source Of Truth

Private Moments uses two documentation layers:

1. `.gsd/` is the structured source for project facts, requirements, decisions, and milestone state.
2. `docs/` is the stable human-facing documentation set.

Use `.gsd/` for current operational truth that changes as the project evolves. Use `docs/` for explanations a person should be able to read later: product intent, architecture, operations, API usage, handoff, design principles, and this workflow.

## Work Tracks

Use lightweight continuous maintenance by default. Upgrade to milestone/slice planning when the risk category requires it.

### Quick Track

Use the quick track for low-risk work such as:

- Small UI copy or layout tweaks.
- Documentation corrections.
- Minor refactors inside an already-understood module.
- Small bug fixes that do not change data semantics.
- Build or script cleanup that does not affect runtime behavior.

Quick-track work still needs verification and closure. It just does not need a full milestone plan.

### Milestone Track

Use milestone/slice planning before implementation when work can affect:

- Sync semantics or sync cursor behavior.
- SQLite schema migrations or data model compatibility.
- Media storage, upload, thumbnail generation, cache recovery, or cleanup.
- Backup, restore, export, migration, or data retention.
- Authentication, device tokens, device revocation, or security boundaries.
- Cross-device behavior or conflict handling.
- Real-device install, launch, or recovery behavior.

Size is not the trigger. Risk is. A one-hour sync cursor fix can require milestone planning; a larger visual polish pass may stay quick-track.

## End-Of-Work Closure

Every non-trivial change must end with a minimum closure loop:

1. State what changed.
2. Provide fresh verification evidence.
3. Name known issues, limitations, or next steps.
4. Update affected fact-source files.
5. Update affected human-facing docs.

If no durable docs changed, say why. If verification could not be completed, say exactly what is missing and why.

## Verification Levels

Choose verification based on impact:

- Server changes: run the relevant server build or typecheck, then verify health or affected HTTP behavior.
- Admin UI changes: run the Admin build and verify affected UI behavior in a browser when behavior changed.
- iOS changes: at minimum build the iOS project. Install to a real device when the change affects runtime behavior that simulator/build cannot prove.
- Sync, media recovery, storage diagnostics, or cross-device behavior: prefer real-device install and, when relevant, inspect the app container or local database.
- Documentation-only changes: verify links, commands, and file names against the repository.

Do not claim completion without fresh evidence from the current work session.

## Documentation Responsibilities

Keep each long-lived document single-purpose:

- `PRD`: product purpose, user stories, goals, non-goals, and acceptance-level product behavior.
- `Technical Design`: architecture, data flow, module responsibilities, sync semantics, storage design, and system constraints.
- `Operator Runbook`: installation, running, troubleshooting, environment variables, smoke checks, launchd, real-device verification, and recovery procedures.
- `Integration Guide`: API usage, route examples, sync payloads, media routes, and admin route contracts.
- `Handoff`: current state, important recent fixes, known large files, and next sensible work. This is the human-readable “start here tomorrow” entry point.
- `Design Principles`: UI/product principles that should guide future features.
- `Workflow`: this process document.

Avoid duplicating the same procedural detail across multiple docs. Link to the owning doc instead.

## GSD Fact Sources

Use these files for structured project memory:

- `.gsd/PROJECT.md`: what the project is right now. Do not turn it into history.
- `.gsd/REQUIREMENTS.md`: durable requirements and validation status. Record medium-grain requirements that constrain architecture, data, security, sync, operations, or product behavior.
- `.gsd/DECISIONS.md`: append-only decision register. Record decisions a future maintainer would ask “why” about.
- `.gsd/milestones/`: milestone, slice, task plans, summaries, and validation evidence for high-risk work.

Decision logs should stay low-noise. Record long-lived and non-obvious tradeoffs, not every helper function or small UI implementation detail.

## When To Update What

Update `.gsd/PROJECT.md` when the current shape of the project changes.

Update `.gsd/REQUIREMENTS.md` when a durable requirement appears, changes status, is validated, is deferred, or is explicitly descoped.

Update `.gsd/DECISIONS.md` when a choice affects future architecture, data semantics, sync behavior, security, storage policy, user experience principles, or workflow rules.

Update `docs/HANDOFF.md` when the next session would otherwise miss important current state, recent fixes, known risks, or next steps.

Update `docs/OPERATOR-RUNBOOK.md` when setup, runtime, verification, deployment, backup, recovery, or troubleshooting behavior changes.

Update `docs/TECH-DESIGN.md` when architecture, module boundaries, data flow, persistence, sync semantics, storage, or API design changes.

Update `docs/PRD.md` when product goals, non-goals, user stories, or acceptance expectations change.

## Reader-Test Before Finishing Documentation

Before finishing a documentation change, read it as if you were opening the project tomorrow with no session context. The document should tell that reader what to do next, what not to do, and where the authoritative detail lives.
