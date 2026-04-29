# Private Moments Sync Protocol

This document defines the business rules for syncing iOS local changes with the Mac server.

## Goals

- iOS can create content offline.
- The UI renders from local SQLite first.
- Sync is retryable and idempotent.
- Mac is the authoritative archive.
- The data model supports multiple devices for one user.

## Terms

- `deviceId`: Stable ID for an authorized device.
- `deviceToken`: Long-lived secret used by a device to call the API.
- `opId`: Client-generated operation ID, unique per device.
- `syncCursor`: Last server change version processed by the client.
- `serverVersion`: Monotonic integer assigned by the Mac server to each accepted change.
- `outbox`: Local iOS table containing pending operations.
- `serverChanges`: Ordered server-side change log used for incremental pull sync.

## Core Flow

1. iOS writes user changes to local SQLite first.
2. iOS appends an operation to `outbox_operation`.
3. When the Mac server is reachable, iOS sends pending metadata operations to `POST /api/v1/sync`.
4. The server applies accepted operations transactionally.
5. iOS uploads media files for posts that now exist on the server.
6. iOS calls `POST /api/v1/sync` again with no local changes to pull media upload changes.
7. The server returns new server changes after the client's `syncCursor`.
8. iOS applies server changes locally and advances `lastSyncCursor`.
9. iOS downloads missing remote media thumbnails through `POST /api/v1/media/batch-download`.

## MVP Operations

The MVP server currently supports these operation types:

- `create_post`: create a text post with `occurredAt`.
- `update_post`: replace post text, `occurredAt`, media order, and removed media set.
- `update_post_favorite`: update only a post's favorite state.
- `delete_post`: soft delete an existing post.
- `media_uploaded`: server-originated change emitted after `/api/v1/media/upload`.
- `media_deleted`: server-originated change emitted when a media item is removed from a post.

Future operation types:

- `upsert_media`
- media status reconciliation

## Idempotency

Each local operation must include an `opId`. The server stores `(deviceId, opId)` in `sync_operation` with a unique constraint.

If the same operation is received again:

- The server must not apply it twice.
- The server should return it as accepted if the previous application succeeded.
- The server should return the previous rejection if it was rejected.

## Conflict Policy

MVP uses last write wins plus operation logs.

If two devices update the same entity, the operation received later by the server wins. The server keeps `sync_operation` rows for debugging and future recovery.

## Deletion

Deletes are soft deletes.

- iOS sets `deletedAt` locally and appends `delete_post`.
- The server sets `deletedAt` on the post and related media.
- The server permanently deletes records and files after 30 days.

## Partial Media Sync

Post metadata and media files may sync separately.

- A post can be accepted before every image upload succeeds.
- Failed image uploads remain retryable.
- The iOS UI can show the local image while remote upload is pending.
- Sync status may be `pending`, `partial`, `synced`, or `failed`.
- iOS uploads media one file at a time and compresses images before upload so large original photos do not keep breaking the request.
- Failed sync or upload work schedules delayed retry with backoff: 5s, 20s, 60s, 120s, then 300s.
- Remote media cache recovery uses thumbnail batch download first; single binary media download remains available for direct preview and diagnostics.

## Remote Media Cache Recovery

`POST /api/v1/media/batch-download` accepts:

```json
{
  "mediaIds": ["media-id-1", "media-id-2"],
  "variant": "thumbnail"
}
```

The response returns base64 JSON payloads keyed by media id. iOS writes each payload to the local media cache and updates `local_media.localCompressedPath`.

Server behavior:

- `thumbnail` is the default variant for iOS recovery.
- Thumbnails are generated on demand with max edge `800px`.
- Oversized existing thumbnails are regenerated.
- Missing or deleted media ids are skipped instead of failing the entire batch.

## Editing

Editing is represented as a direct overwrite, not a visible version history.

`update_post` payload:

```json
{
  "text": "latest text",
  "occurredAt": "2026-04-29T12:00:00Z",
  "updatedAt": "2026-04-29T12:05:00Z",
  "media": [
    { "id": "existing-or-new-media-id", "sortOrder": 0 }
  ],
  "removedMediaIds": ["media-id-to-soft-delete"]
}
```

The server updates the post, soft-deletes removed media, updates `sortOrder` for existing media, and emits server changes for the updated post and removed media. Newly added media records are created later by the existing media upload endpoint.

If two devices edit the same post offline, the last operation applied by the server wins.

## Favorites

Favorite state is synced as metadata on the post, but it uses a separate lightweight operation so starring a moment does not require entering the edit flow.

`update_post_favorite` payload:

```json
{
  "isFavorite": true,
  "updatedAt": "2026-04-29T12:06:00Z"
}
```

The server updates `Post.isFavorite`, emits `post_favorite_updated`, and assigns a new `serverVersion`. Clients should keep the time line visually quiet: favorites are a small marker and filter target, not a prominent content block.

## Cursor Rules

`syncCursor` refers to the largest `server_change.version` the client has applied.

The server response includes `nextSyncCursor`, which should only be stored locally after iOS successfully applies all returned `serverChanges`.

If the iOS local post table is empty, the client should request cursor `0` even if UserDefaults has an older nonzero cursor. This supports archive recovery after reinstall, failed migration, or the 2026-04-29 cursor recovery bug.

iOS must reject invalid server changes instead of silently skipping them and advancing cursor. Timestamp parsing must handle both fractional and non-fractional ISO8601 strings.
