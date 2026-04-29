# Private Moments Integration Guide

This guide is for a developer or future agent that needs to connect a client, admin tool, or diagnostic script to the Mac server.

## Server Base URL

Local Mac development:

```text
http://127.0.0.1:3210
```

Real iPhone testing over Tailscale normally uses either:

```text
http://<mac-tailscale-ip>:3210
https://<mac-tailscale-serve-name>
```

The iOS app stores the server URL in Settings. The real-device install script auto-detects a reachable Tailscale Serve hostname, Tailscale IP, or LAN IP unless `PRIVATE_MOMENTS_DEVICE_SERVER_URL` is set.

## Authentication

Login exchanges the single-user password for a long-lived device token.

```bash
curl -X POST http://127.0.0.1:3210/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{
    "password": "your-password",
    "deviceName": "Dev iPhone",
    "platform": "ios",
    "deviceKey": "stable-device-key"
  }'
```

Authenticated requests use:

```http
Authorization: Bearer <device-token>
```

`deviceKey` prevents duplicate device rows. Repeated login from the same physical device or browser installation should reuse the same `deviceKey`.

## Endpoint Quick Reference

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/v1/health` | Health, schema version, data directory. |
| `POST` | `/api/v1/auth/login` | Password login and device token issue/rebind. |
| `GET` | `/api/v1/devices` | List authorized devices. |
| `DELETE` | `/api/v1/devices/:deviceId` | Revoke a device token. |
| `POST` | `/api/v1/sync` | Push local operations and pull server changes. |
| `POST` | `/api/v1/media/upload` | Upload one image file with multipart form data. |
| `POST` | `/api/v1/media/batch-download` | Download multiple media variants as base64 JSON. |
| `GET` | `/api/v1/media/:mediaId?variant=thumbnail` | Download one media file. |
| `GET` | `/api/v1/timeline` | Read server timeline for diagnostics. |
| `GET` | `/api/v1/posts/:postId` | Read one post. |
| `GET` | `/api/v1/search?q=...` | Search server archive text. |
| `GET` | `/api/v1/admin/status` | Admin dashboard status and storage diagnostics. |
| `GET` | `/api/v1/admin/logs?limit=100` | Admin dashboard logs. |
| `GET` | `/api/v1/admin/posts` | Admin post list with filters. |
| `GET` | `/api/v1/admin/posts/:postId` | Admin post detail. |
| `DELETE` | `/api/v1/admin/posts/:postId` | Soft delete one post from Admin. |
| `GET` | `/api/v1/admin/devices/:deviceId/clean-posts/preview` | Preview permanent cleanup for one device's created posts. |
| `POST` | `/api/v1/admin/devices/:deviceId/clean-posts` | Permanently clean test posts created by one device. |

## Sync

`POST /api/v1/sync` is an endpoint for device/server reconciliation, not a CRUD endpoint for one resource.

Request shape:

```json
{
  "deviceId": "device-uuid",
  "lastSyncCursor": 0,
  "localChanges": [
    {
      "opId": "op-uuid",
      "type": "create_post",
      "entityType": "post",
      "entityId": "post-uuid",
      "clientCreatedAt": "2026-04-29T12:00:00.000Z",
      "payload": {
        "text": "记录一条动态",
        "occurredAt": "2026-04-29T11:58:00.000Z"
      }
    }
  ]
}
```

Supported client operation types:

- `create_post`
- `update_post`
- `update_post_favorite`
- `delete_post`

Important rules:

- `opId` must be unique per device. The server uses `(deviceId, opId)` for idempotency.
- `syncCursor` is the largest `server_changes.version` the client has applied.
- The client should only persist `nextSyncCursor` after applying all returned `serverChanges`.
- iOS accepts ISO8601 timestamps with and without fractional seconds.
- If the local database is empty, iOS requests cursor `0` to restore from the Mac archive.

## Media Upload

Upload one image with multipart form data:

```bash
curl -X POST http://127.0.0.1:3210/api/v1/media/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F mediaId=media-uuid \
  -F postId=post-uuid \
  -F variant=compressed \
  -F originalPreserved=false \
  -F sortOrder=0 \
  -F file=@image.jpg
```

The server stores files under the configured data directory and writes only relative file paths and metadata to SQLite.

## Media Batch Download

iOS uses batch download for remote image cache recovery:

```bash
curl -X POST http://127.0.0.1:3210/api/v1/media/batch-download \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "mediaIds": ["media-uuid-1", "media-uuid-2"],
    "variant": "thumbnail"
  }'
```

Response:

```json
{
  "media": [
    {
      "id": "media-uuid-1",
      "variant": "thumbnail",
      "contentType": "image/jpeg",
      "fileName": "media-uuid-1.jpg",
      "base64": "..."
    }
  ]
}
```

The server generates thumbnail variants on demand with `sips`. Current thumbnail policy is max edge `800px`; large existing thumbnails are regenerated when they exceed the server threshold.

## Admin Status And Storage Diagnostics

`GET /api/v1/admin/status` uses the same Bearer token auth as other admin routes. The iOS Settings storage page calls this endpoint when logged in; if the Mac server is offline or the request fails, the iOS UI hides the Mac Server storage section instead of showing an error alert.

```bash
curl -X GET http://127.0.0.1:3210/api/v1/admin/status \
  -H "Authorization: Bearer $TOKEN"
```

Response shape:

```json
{
  "serverVersion": "0.1.0",
  "schemaVersion": 3,
  "dataDir": "/path/to/PrivateMoments",
  "uptimeSeconds": 123,
  "counts": {
    "activeDevices": 1,
    "revokedDevices": 0,
    "posts": 8,
    "deletedPosts": 6,
    "media": 19
  },
  "storage": {
    "totalBytes": 29480943,
    "databaseBytes": 163840,
    "mediaBytes": 29268634,
    "logsBytes": 42996,
    "availableBytes": 143418429440
  }
}
```

`databaseBytes` includes the SQLite database plus `-wal` and `-shm` sidecar files. `totalBytes` is the whole configured data directory. `availableBytes` is the free space available to the data directory volume.

## Admin Posts Filters

`GET /api/v1/admin/posts` supports:

| Query | Values | Notes |
|---|---|---|
| `deleted` | `active`, `deleted`, `all` | Defaults to active in the UI. |
| `deviceId` | device UUID | Filters by `createdByDeviceId`. |
| `q` | text | Searches post text. Search returns up to 100 rows and does not use cursor pagination. |
| `limit` | `1..100` | Default list limit is 50. |
| `cursor` | encoded cursor | Used for non-search list pagination. |

`POST /api/v1/admin/devices/:deviceId/clean-posts` requires:

```json
{
  "confirmDeviceName": "Device display name"
}
```

It permanently removes posts created by that device and writes minimal `post_deleted` server changes so iOS caches can hide those posts on the next sync.
