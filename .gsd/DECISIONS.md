# Decisions Register

<!-- Append-only. Never edit or remove existing rows.
     To reverse a decision, add a new row that supersedes it.
     Read this file at the start of any planning or research phase. -->

| # | When | Scope | Decision | Choice | Rationale | Revisable? | Made By |
|---|------|-------|----------|--------|-----------|------------|---------|
| D001 | workflow alignment discussion 2026-04-30 | workflow | Persistent project workflow and documentation source of truth | .gsd is the structured source for current facts, requirements, decisions, and milestone state; docs remains the stable human-facing documentation set. | The project will continue to evolve across iOS, server, admin, sync, and storage; separating structured execution facts from stable operator/product docs reduces drift. | Yes | human |
| D002 | workflow alignment discussion 2026-04-30 | workflow | Work planning mode | Use lightweight continuous maintenance by default, with milestone/slice planning required for high-risk domains. | Small UI and documentation changes should stay fast, while sync, schema migration, storage, backup, security, and cross-device work need explicit boundaries and evidence. | Yes | human |
| D003 | workflow alignment discussion 2026-04-30 | documentation | Documentation responsibilities | Keep docs single-purpose: PRD for product intent, technical design for system design, runbook for operations, integration guide for API use, handoff for current state, workflow for process. | Single-purpose documents reduce repeated content and make stale sections easier to detect. | Yes | human |
