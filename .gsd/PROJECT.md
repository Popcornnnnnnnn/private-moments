# Project State

Last updated: 2026-04-30

## What This Project Is

Private Moments is a private, local-first personal timeline. The iOS app, named `Moments`, is the primary capture and browsing surface. A Mac runs the self-hosted server, SQLite archive, media storage, sync API, and Admin UI.

The intended network boundary is Tailscale or another private VPN. The project is not designed as a public cloud service.

## Current Architecture

- iOS app: SwiftUI, local SQLite, local media cache, drafts, outbox sync, and real-device install support.
- Mac server: Node.js, TypeScript, Fastify, Prisma, SQLite, local file storage, auth, sync, media, admin APIs, and static Admin UI hosting.
- Admin UI: React + Vite, built separately and served by Fastify.
- Shared contracts: OpenAPI route contract and sync protocol notes under `shared/`.

## Current Product Surface

Implemented capabilities include:

- Local-first text, image, and text + image moments.
- Photo library and camera import.
- Manual occurred date/time.
- Composer and edit drafts.
- Offline outbox sync with delayed retry.
- Media upload, compression, thumbnail recovery, and local cache recovery.
- Timeline browsing with English human-friendly dates and temporary floating month hint.
- Search, filters, favorites, month jump, detail view, editing, image gallery, and soft delete.
- Settings pages for connection, sync, advanced sync, and storage diagnostics.
- Mac Admin Overview and Posts management.
- Device binding via stable device keys to avoid duplicate physical-device registrations.

## Design Constraints

- The main iOS timeline must stay simple. Low-frequency controls belong in toolbar menus, swipe actions, detail views, or settings.
- App-facing UI copy should remain primarily English unless explicitly requested otherwise.
- Sync cursor advancement is data-sensitive: the client must only advance after all returned server changes are applied.
- Media recovery should prefer robust batch thumbnail recovery for iOS/Tailscale reliability.
- Personal Tailscale values and secrets must not be hard-coded into reusable code or docs.

## Documentation System

`.gsd/` is the structured source for current project facts, requirements, decisions, and milestone state. `docs/` is the stable human-facing documentation set.

Current documentation responsibilities:

- `docs/PRD.md`: product intent, user stories, goals, and non-goals.
- `docs/TECH-DESIGN.md`: architecture, data flow, system design, and long-lived technical constraints.
- `docs/OPERATOR-RUNBOOK.md`: setup, operation, verification, troubleshooting, and real-device checks.
- `docs/INTEGRATION-GUIDE.md`: API route usage and integration reference.
- `docs/HANDOFF.md`: current working state, recent important fixes, and next sensible work.
- `docs/DESIGN-PRINCIPLES.md`: UI and product design principles.
- `docs/WORKFLOW.md`: how work is planned, verified, closed, and documented.

## Current Workflow Policy

Use lightweight continuous maintenance by default. Upgrade work to milestone/slice planning when it touches high-risk areas: sync semantics, schema migrations, media storage or recovery, backup or restore, auth/security boundaries, or cross-device behavior.

Every non-trivial change must close with a short summary, fresh verification evidence, known issues or next steps, and updates to affected `.gsd` or `docs/` files.
