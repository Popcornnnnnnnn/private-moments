# Project State

Last updated: 2026-04-30

## What This Project Is

Moments is a private expression space with no audience. It is a personal timeline app that feels like posting to a feed, but everything belongs only to the user: no likes, no public audience, no pressure of being watched.

The product should preserve four north-star ideas:

- 表达，而不是记录 — writing can be partial, quick, and lightweight.
- 默认没有观众 — content is not created for other people to see.
- 时间是流动的 — browsing should feel like returning to a living timeline, not querying a database.
- 本地优先 — data belongs to the user and can sync without depending on a cloud platform.

The iOS app, named `Moments`, is the primary capture and browsing surface. A Mac runs the self-hosted server, SQLite archive, media storage, sync API, and Admin UI.

The intended network boundary is Tailscale or another private VPN. The project is not designed as a public cloud service.

## Current Architecture

- iOS app: SwiftUI, local SQLite, local media cache, drafts, outbox sync, comment persistence, and real-device install support.
- Mac server: Node.js, TypeScript, Fastify, Prisma, SQLite, local file storage, auth, sync, media, admin APIs, and static Admin UI hosting.
- Admin UI: React + Vite, built separately and served by Fastify.
- Shared contracts: OpenAPI route contract and sync protocol notes under `shared/`.
- XcodeGen specs: `ios/project.yml` is the canonical iOS spec for normal iOS work, and root `project.yml` mirrors it for automation that runs XcodeGen from the repository root.

## Current Product Surface

Implemented capabilities include:

- Local-first text, image, and text + image moments.
- Photo library and camera import.
- Manual occurred date/time.
- Composer and edit drafts.
- Plain-text list continuation in New Moment and Edit Moment for `- `, `• `, and numbered prefixes, including numbered auto-increment and empty-item exit.
- Offline outbox sync with delayed retry.
- Media upload, compression, thumbnail recovery, and local cache recovery.
- Timeline browsing with English human-friendly dates and temporary floating month hint.
- Search, filters, favorites, quiet toolbar-only month/day date jump, detail view, editing, image gallery, and soft delete.
- Private plain-text comments attached to moments, shown only in Moment detail with add/delete controls and existing sync-status visibility.
- Settings pages for connection, sync, advanced sync, and storage diagnostics.
- Mac Admin Overview and Posts management.
- Device binding via stable device keys to avoid duplicate physical-device registrations.

## Design Constraints

- The main iOS timeline must stay simple. Low-frequency controls belong in toolbar menus, swipe actions, detail views, or settings.
- Private comments are follow-up notes in Moment detail only; do not add comment badges, counts, previews, or search participation to the main timeline.
- Comments remain plain text and single-level: no replies, likes, mentions, avatars/public author identity, Markdown rendering, rich text controls, comment media, or edit/thread affordances.
- Content management features must help the user return to lived time, not turn Moments into an archive/database manager.
- Date navigation must stay derived from currently visible timeline items, so active search/filter state controls available month/day jump targets.
- Input assistance must reduce friction for lightweight expression, not turn Moments into a Markdown editor or writing tool.
- List continuation is plain string editing only; saved/rendered posts remain literal plain text with no Markdown/rich-text interpretation.
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

## Milestone Sequence

- [x] M001: Timeline Navigation and Lightweight Input — completed. Delivered quiet toolbar-only month/day timeline jumping from visible items plus shared plain-text list continuation in New Moment and Edit Moment. Automated XCTest/build verification passed; manual tactile UAT for menu/editor feel remains a follow-up.
- [x] M002: Private comments for moments — completed. Delivered private plain-text comments as first-class synced entities attached to moments, shown only in Moment detail with add/delete controls and sync-status visibility. S01 added server/iOS persistence plus idempotent `create_comment`/`delete_comment` sync; S02 added the detail-view UI while static checks kept the main timeline uncluttered; S03 updated durable docs and passed server build, iOS simulator tests, generic iOS build, static timeline non-clutter checks, and real-device install/launch proof. Manual real-device comment create/delete UAT and active schema-version-4 server SQLite aggregate proof remain follow-up validation for R008, which intentionally stays active.
