# M002: Private comments for moments

**Vision:** Add a small private-comment layer to Moments so the user can attach follow-up thoughts to an existing moment while keeping the app local-first, synced, quiet, and non-social.

## Success Criteria

- Private comments exist as durable, synced, plain-text data attached to moments.
- The only user-facing comment UI is in Moment detail, not as timeline clutter.
- Comment create/delete is retryable and idempotent through existing sync machinery.
- No social mechanics or rich text are introduced.
- Verification evidence covers server, iOS, and real-device behavior.

## Slices

- [x] **S01: S01** `risk:high` `depends:[]`
  > After this: A scripted sync/API check can create and delete a private comment using idempotent operations; iOS local database has a corresponding comment table and operation payload model ready for UI consumption.

- [x] **S02: S02** `risk:medium` `depends:[]`
  > After this: On iPhone, opening a moment detail shows a private comments section where the user can add and delete plain-text comments; the main timeline stays uncluttered.

- [ ] **S03: S03** `risk:medium` `depends:[]`
  > After this: A documented UAT path proves private comments create/delete and sync behavior, and operator/product docs explain the feature and constraints.

## Boundary Map

### In scope
- Server Prisma/SQLite schema for private comments.
- Sync protocol and OpenAPI updates for comment create/delete changes.
- iOS local SQLite storage, outbox operations, server-change application, and retry semantics for comments.
- iOS Moment detail UI for viewing, adding, and deleting private comments.
- Real-device install and basic cross-boundary verification.

### Out of scope
- Replies/threading, likes, mentions, public author display, rich text, Markdown rendering, AI search, or search enhancements.
- Admin UI comment management unless needed for diagnostics.
- Media attachments on comments.
- Sharing/export workflows.
