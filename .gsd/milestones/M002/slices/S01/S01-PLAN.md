# S01: Comment data model and sync contract

**Goal:** Introduce the durable private comment data model and sync semantics across server, shared contract, and iOS persistence without changing visible UI yet.
**Demo:** A scripted sync/API check can create and delete a private comment using idempotent operations; iOS local database has a corresponding comment table and operation payload model ready for UI consumption.

## Must-Haves

- Prisma and iOS SQLite schemas include private comments with soft-delete support.
- Sync accepts idempotent create/delete comment operations and emits comment server changes.
- iOS can queue and apply comment operations/server changes locally.
- OpenAPI and sync protocol document new operation shapes.
- Server build/typecheck and iOS build/tests pass.

## Proof Level

- This slice proves: contract + integration

## Integration Closure

Server Prisma schema/migration, sync handler, shared docs/OpenAPI, and iOS local persistence compile together with tests or scripted sync verification.

## Verification

- Extend existing sync error surfaces with comment operation type context; no secrets in logs.

## Tasks

- [x] **T01: Map existing sync and persistence seams** `est:30m`
  Inspect current server sync handler, API models, iOS LocalDatabase schema, TimelineStore payload handling, and OpenAPI sync definitions. Produce a concise implementation map before editing.
  - Files: `server/src/api/sync.ts`, `shared/openapi.yaml`, `ios/PrivateMoments/Persistence/LocalDatabase+Schema.swift`, `ios/PrivateMoments/Persistence/TimelineStore+Payloads.swift`, `ios/PrivateMoments/Networking/APIModels.swift`
  - Verify: Produce notes in task summary; no code changes expected beyond optional comments if needed.

- [x] **T02: Add server comment schema and sync operations** `est:2h`
  Add server-side comment persistence and sync support: Prisma model/migration, create/delete comment operation validation/application, server change payloads, and shared OpenAPI/sync protocol updates.
  - Files: `server/prisma/schema.prisma`, `server/prisma/migrations/*/migration.sql`, `server/src/api/sync.ts`, `shared/openapi.yaml`, `shared/sync-protocol.md`
  - Verify: npm run server:prisma:generate && npm run server:build && scripted sync/API check or focused server test for idempotent create/delete comments.

- [x] **T03: Add iOS local comment sync plumbing** `est:2h`
  Add iOS local comment persistence and sync payload support without visible UI: SQLite schema migration, comment records, outbox operations, API models, TimelineStore apply/send logic.
  - Files: `ios/PrivateMoments/Persistence/LocalDatabase+Schema.swift`, `ios/PrivateMoments/Persistence/LocalDatabase+Records.swift`, `ios/PrivateMoments/Persistence/LocalDatabase+Sync.swift`, `ios/PrivateMoments/Persistence/TimelineStore+Payloads.swift`, `ios/PrivateMoments/Persistence/TimelineStore+ServerChanges.swift`, `ios/PrivateMoments/Networking/APIModels.swift`
  - Verify: cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build

- [x] **T04: Verify and close comment sync contract slice** `est:45m`
  Run slice-level integration checks, reconcile docs/contracts, and record S01 summary with remaining risks for UI slice.
  - Files: `docs/TECH-DESIGN.md`, `docs/INTEGRATION-GUIDE.md`, `.gsd/REQUIREMENTS.md`
  - Verify: npm run server:build && cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build

## Files Likely Touched

- server/src/api/sync.ts
- shared/openapi.yaml
- ios/PrivateMoments/Persistence/LocalDatabase+Schema.swift
- ios/PrivateMoments/Persistence/TimelineStore+Payloads.swift
- ios/PrivateMoments/Networking/APIModels.swift
- server/prisma/schema.prisma
- server/prisma/migrations/*/migration.sql
- shared/sync-protocol.md
- ios/PrivateMoments/Persistence/LocalDatabase+Records.swift
- ios/PrivateMoments/Persistence/LocalDatabase+Sync.swift
- ios/PrivateMoments/Persistence/TimelineStore+ServerChanges.swift
- docs/TECH-DESIGN.md
- docs/INTEGRATION-GUIDE.md
- .gsd/REQUIREMENTS.md
