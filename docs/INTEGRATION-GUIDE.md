# Private Moments 集成指南

这份指南面向需要连接 Mac server 的开发者或未来 agent：包括 client、admin tool、diagnostic script 等。

## Server Base URL

本地 Mac 开发：

```text
http://127.0.0.1:3210
```

真实 iPhone 通过 Tailscale 测试时，通常使用：

```text
http://<mac-tailscale-ip>:3210
https://<mac-tailscale-serve-name>
```

iOS app 在 Settings 中保存 server URL。真实设备安装脚本会自动探测可访问的 Tailscale Serve hostname、Tailscale IP 或 LAN IP；也可以通过 `PRIVATE_MOMENTS_DEVICE_SERVER_URL` override。

## Authentication

Login 会用单用户 password 换取长期 device token。

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

Authenticated requests 使用：

```http
Authorization: Bearer <device-token>
```

`deviceKey` 用于避免重复 device rows。同一物理设备或同一 browser installation 重复 login 时，应复用同一个 `deviceKey`。

## Endpoint Quick Reference

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/v1/health` | Health、schema version、data directory。 |
| `POST` | `/api/v1/auth/login` | Password login，并签发或重新绑定 device token。 |
| `GET` | `/api/v1/devices` | 列出 authorized devices。 |
| `DELETE` | `/api/v1/devices/:deviceId` | 撤销 device token。 |
| `POST` | `/api/v1/sync` | 推送 local operations，并拉取 server changes。 |
| `POST` | `/api/v1/media/upload` | 用 multipart form data 上传单张 image file。 |
| `POST` | `/api/v1/media/batch-download` | 以 base64 JSON 下载多个 media variants。 |
| `GET` | `/api/v1/media/:mediaId?variant=thumbnail` | 下载单个 media file。 |
| `GET` | `/api/v1/timeline` | 读取 server timeline，用于 diagnostics。 |
| `GET` | `/api/v1/posts/:postId` | 读取单个 post。 |
| `GET` | `/api/v1/search?q=...` | 搜索 server archive text。 |
| `GET` | `/api/v1/admin/status` | Admin dashboard status 和 storage diagnostics。 |
| `GET` | `/api/v1/admin/logs?limit=100` | Admin dashboard logs。 |
| `GET` | `/api/v1/admin/posts` | Admin post list，支持 filters。 |
| `GET` | `/api/v1/admin/posts/:postId` | Admin post detail。 |
| `DELETE` | `/api/v1/admin/posts/:postId` | 从 Admin soft delete 单个 post。 |
| `GET` | `/api/v1/admin/devices/:deviceId/clean-posts/preview` | 预览某个 device 创建的 posts 永久清理候选。 |
| `POST` | `/api/v1/admin/devices/:deviceId/clean-posts` | 永久清理某个 device 创建的测试 posts。 |

## Sync

`POST /api/v1/sync` 是 device/server reconciliation endpoint，不是针对单个 resource 的 CRUD endpoint。

Request shape：

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

当前支持的 client operation types：

- `create_post`
- `update_post`
- `update_post_favorite`
- `delete_post`
- `create_comment`
- `delete_comment`

Comment operations：

```json
{
  "opId": "comment-op-uuid",
  "type": "create_comment",
  "entityType": "comment",
  "entityId": "comment-uuid",
  "clientCreatedAt": "2026-04-30T12:00:00.000Z",
  "payload": {
    "postId": "post-uuid",
    "text": "补一句自己的想法",
    "createdAt": "2026-04-30T12:00:00.000Z"
  }
}
```

```json
{
  "opId": "comment-delete-op-uuid",
  "type": "delete_comment",
  "entityType": "comment",
  "entityId": "comment-uuid",
  "clientCreatedAt": "2026-04-30T12:10:00.000Z",
  "payload": {
    "postId": "post-uuid",
    "deletedAt": "2026-04-30T12:10:00.000Z"
  }
}
```

Server 会为 comment 操作写入 `comment_created` / `comment_deleted` server changes。iOS 只在本地成功应用这些 server changes 后推进 cursor；comment change 解析错误会带 `comment_created` 或 `comment_deleted` 上下文，但不把评论正文写入错误信息。

重要规则：

- `opId` 必须在同一 device 内唯一。Server 使用 `(deviceId, opId)` 保证 idempotency。
- `syncCursor` 表示 client 已经应用的最大 `server_changes.version`。
- Client 只能在成功应用所有返回的 `serverChanges` 后，持久化 `nextSyncCursor`。
- iOS 接受带 fractional seconds 和不带 fractional seconds 的 ISO8601 timestamps。
- 如果 local database 为空，iOS 会请求 cursor `0`，从 Mac archive 恢复数据。

## Media Upload

用 multipart form data 上传单张 image：

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

Server 会把文件存到 configured data directory，只把 relative file paths 和 metadata 写入 SQLite。

## Media Batch Download

iOS 使用 batch download 做 remote image cache recovery：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/media/batch-download \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "mediaIds": ["media-uuid-1", "media-uuid-2"],
    "variant": "thumbnail"
  }'
```

Response：

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

Server 使用 `sips` 按需生成 thumbnail variants。当前 thumbnail policy 是 max edge `800px`；如果已有 thumbnail 超过 server threshold，会重新生成。

## Admin Status And Storage Diagnostics

`GET /api/v1/admin/status` 使用和其他 admin routes 相同的 Bearer token auth。iOS Settings storage page 登录后会调用这个 endpoint；如果 Mac server offline 或请求失败，iOS UI 会隐藏 Mac Server storage section，而不是弹 error alert。

```bash
curl -X GET http://127.0.0.1:3210/api/v1/admin/status \
  -H "Authorization: Bearer $TOKEN"
```

Response shape：

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

`databaseBytes` 包含 SQLite database 以及 `-wal`、`-shm` sidecar files。`totalBytes` 是整个 configured data directory。`availableBytes` 是 data directory 所在 volume 的可用空间。

## Admin Posts Filters

`GET /api/v1/admin/posts` 支持：

| Query | Values | Notes |
|---|---|---|
| `deleted` | `active`, `deleted`, `all` | UI 默认显示 active。 |
| `deviceId` | device UUID | 按 `createdByDeviceId` 过滤。 |
| `q` | text | 搜索 post text。Search 最多返回 100 rows，不使用 cursor pagination。 |
| `limit` | `1..100` | 默认 list limit 是 50。 |
| `cursor` | encoded cursor | 用于非 search list pagination。 |

`POST /api/v1/admin/devices/:deviceId/clean-posts` 需要：

```json
{
  "confirmDeviceName": "Device display name"
}
```

它会永久删除该 device 创建的 posts，并写入最小化的 `post_deleted` server changes，让 iOS caches 在下次 sync 时隐藏这些 posts。
