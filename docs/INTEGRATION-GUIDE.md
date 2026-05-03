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
| `POST` | `/api/v1/ai/media-summary` | 为一个已上传的 audio/video media 文件生成或重新生成 AI summary。 |
| `DELETE` | `/api/v1/ai/media-summary/:summaryId` | 软删除一条 generated AI summary。 |
| `POST` | `/api/v1/media/upload` | 用 multipart form data 上传 image/audio/video media file。 |
| `POST` | `/api/v1/media/batch-download` | 以 base64 JSON 下载多个 media variants。 |
| `GET` | `/api/v1/media/:mediaId?variant=thumbnail` | 下载单个 media file。 |
| `GET` | `/api/v1/timeline` | 读取 server timeline，用于 diagnostics。 |
| `GET` | `/api/v1/posts/:postId` | 读取单个 post。 |
| `GET` | `/api/v1/search?q=...` | 搜索 server archive text、comments，并兼容搜索历史 audio/video transcription metadata。 |
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
- `insert_ai_title`
- `update_post_favorite`
- `delete_post`
- `create_comment`
- `delete_comment`
- `update_media_transcription`
- `upsert_tag`
- `archive_tag`
- `restore_tag`
- `delete_tag`
- `merge_tag`
- `upsert_tag_alias`
- `delete_tag_alias`
- `set_post_tags`

Comment operations 使用同一个 sync endpoint。`create_comment` 的 `entityType` 是 `comment`，`entityId` 是 comment id，payload 至少包含父 `postId` 和 `text`：

```json
{
  "opId": "op-comment-create",
  "type": "create_comment",
  "entityType": "comment",
  "entityId": "comment-uuid",
  "clientCreatedAt": "2026-04-30T12:00:00.000Z",
  "payload": {
    "postId": "post-uuid",
    "text": "补一句后来的想法",
    "createdAt": "2026-04-30T12:00:00.000Z"
  }
}
```

`delete_comment` payload 只需要删除时间：

```json
{
  "opId": "op-comment-delete",
  "type": "delete_comment",
  "entityType": "comment",
  "entityId": "comment-uuid",
  "clientCreatedAt": "2026-04-30T12:05:00.000Z",
  "payload": {
    "deletedAt": "2026-04-30T12:05:00.000Z"
  }
}
```

`update_media_transcription` 是 schema version 6 留下的兼容 operation，用于旧客户端把本机转写文本同步为 media metadata。新 iOS 发布路径已经停用本机转写，不再发送这个 operation，也不再通过 upload metadata 发送 `transcriptionText`。

```json
{
  "opId": "op-media-transcription",
  "type": "update_media_transcription",
  "entityType": "media",
  "entityId": "media-uuid",
  "clientCreatedAt": "2026-04-30T12:10:00.000Z",
  "payload": {
    "postId": "post-uuid",
    "transcriptionText": "本机转写出来的语音内容",
    "updatedAt": "2026-04-30T12:10:00.000Z"
  }
}
```

重要规则：

- `opId` 必须在同一 device 内唯一。Server 使用 `(deviceId, opId)` 保证 idempotency。
- `syncCursor` 表示 client 已经应用的最大 `server_changes.version`。
- Client 只能在成功应用所有返回的 `serverChanges` 后，持久化 `nextSyncCursor`。
- iOS 接受带 fractional seconds 和不带 fractional seconds 的 ISO8601 timestamps。
- 如果 local database 为空，iOS 会请求 cursor `0`，从 Mac archive 恢复数据。
- Server 会拒绝给不存在或已删除 post 创建 comment。
- 删除 post 会级联软删除 comments，但 server 只发 `post_deleted`；不会为父删除生成每条 `comment_deleted`。
- Client 应用 `comment_created` 或 `comment_deleted` 时如果找不到父 post，应让本轮 sync 失败并保留原 cursor。
- `update_media_transcription` 只作为旧客户端兼容路径更新 audio/video media 的文本 metadata；server 会发出 `media_transcription_updated` server change。
- AI summary 由独立 endpoint 触发，但同步恢复仍走 server changes：`ai_summary_updated` 和 `ai_summary_deleted`。Client 应用这些变更时如果找不到父 post 或 media，应让本轮 sync 失败并保留原 cursor。
- Smart Tags 作为一等 metadata 同步：词表 changes 是 `tag_updated` 和 `tag_alias_updated/deleted`，post 关联 changes 是 `post_tag_updated/deleted` 和 `post_tag_state_updated`。Client 应用 post tag assignment 时如果本地缺少对应 tag，应让本轮 sync 失败并保留原 cursor。

## Smart Tags Sync

Tag vocabulary 和 post assignments 分开同步。

`create_post` 可以在 payload 中带可选 `primaryTagId`：

```json
{
  "text": "今天学了一点 LLM",
  "occurredAt": "2026-05-03T12:00:00.000Z",
  "primaryTagId": "tag-primary-learning"
}
```

`set_post_tags` 用于替换一条 moment 的完整标签集合：

```json
{
  "opId": "op-set-post-tags",
  "type": "set_post_tags",
  "entityType": "post",
  "entityId": "post-uuid",
  "clientCreatedAt": "2026-05-03T12:05:00.000Z",
  "payload": {
    "primaryTagId": "tag-primary-learning",
    "topicTagIds": ["topic-llm", "topic-reinforcement-learning"],
    "updatedAt": "2026-05-03T12:05:00.000Z"
  }
}
```

词表操作：

- `upsert_tag`：`entityType: "tag"`，payload `{type, name, colorHex, isDefault, aiUsableAsPrimary, updatedAt}`。
- `archive_tag`：payload `{archivedAt}`，隐藏标签但保留历史。
- `restore_tag`：恢复 archived tag。
- `delete_tag`：payload `{deletedAt}`，仅用于 archived 且非 default 的 tag。server 会先广播活跃 assignment 的 `post_tag_deleted` 和活跃 alias 的 `tag_alias_deleted`，再广播 `tag_deleted`，并释放该 tag 的 normalized name。
- `upsert_tag_alias`：`entityType: "tag_alias"`，payload `{tagId, alias}`。
- `delete_tag_alias`：payload `{deletedAt}`。
- `merge_tag`：`entityType: "tag"`，`entityId` 是 source topic tag，payload `{targetTagId, alias, mergedAt}`；server 会把 source 的活跃关联移动到 target、保留 source name 为 target alias，并 archive source tag。

默认主标签由 server/iOS seed：`日记`、`想法`、`学习整理`、`情绪`、`碎碎念`、`复盘`。默认主标签不可重命名或归档；自定义主标签和 topic tag 通过 Settings > Tags 管理。AI 自动标签只在新 audio moment 的首次 ready summary 中应用一次。

## AI Media Summary

AI summary 的 provider credentials 只配置在 Mac server。iOS 不直接访问外部 AI provider，也不再本机转写 audio/video。完整 audio/video 上传成功后，Mac server 会在后台先用本地 `mlx-whisper` 转成内部 transcript，再把 transcript 交给外部 Chat Completions API 生成结构化 summary。iOS 通过正常 sync 接收 `ai_summary_updated`，只有 ready summary 才会出现在主时间线。

Request：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/ai/media-summary \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "postId": "post-uuid",
    "mediaId": "media-uuid",
    "forceRegenerate": false
  }'
```

Response：

```json
{
  "summary": {
    "id": "summary-uuid",
    "postId": "post-uuid",
    "mediaId": "media-uuid",
    "status": "ready",
    "format": "document",
    "language": "zh",
    "documentTitle": "面试复盘",
    "oneLiner": "这段语音主要复盘了一次面试后的感受、系统设计回答问题，以及下一次准备的重点。",
    "documentBlocks": [
      {
        "kind": "heading",
        "level": 1,
        "text": "一句话总结",
        "items": []
      },
      {
        "kind": "paragraph",
        "level": 0,
        "text": "说话者认为这次面试整体可复盘的重点在系统设计表达顺序，而不是单个知识点遗漏。",
        "items": []
      },
      {
        "kind": "heading",
        "level": 1,
        "text": "主要内容",
        "items": []
      },
      {
        "kind": "bullets",
        "level": 0,
        "text": "",
        "items": ["先讲约束再讲方案会更清楚", "需要把权衡和边界条件说得更主动"]
      },
      {
        "kind": "ai_suggested",
        "level": 0,
        "text": "下一次准备时可以先写一个 3 分钟系统设计开场模板。",
        "items": []
      }
    ],
    "overview": "这段语音主要复盘了一次面试后的感受、系统设计回答问题，以及下一次准备的重点。",
    "keyPoints": ["先讲约束再讲方案会更清楚", "需要把权衡和边界条件说得更主动"],
    "sections": [],
    "summaryText": "# 面试复盘\n\n这段语音主要复盘了一次面试后的感受、系统设计回答问题，以及下一次准备的重点。",
    "inputTranscriptLength": 320,
    "inputDurationSeconds": 86,
    "promptVersion": "media-summary-v3",
    "provider": "openai",
    "model": "gpt-5.5",
    "errorCode": null,
    "errorMessage": null,
    "createdAt": "2026-04-30T12:20:00.000Z",
    "updatedAt": "2026-04-30T12:20:10.000Z",
    "deletedAt": null
  }
}
```

常见轻量失败：

- `media_file_missing`：Mac server 上找不到该媒体文件。
- `empty_transcript`：本地转写没有返回可用文本。
- `local_transcription_timeout` / `local_transcription_failed` / `local_transcription_invalid_output`：Mac 本地转写超时、执行失败或输出无效。
- `not_configured`：server 缺少外部 AI API key 或配置。
- `provider_request_failed` / `provider_http_*` / `provider_timeout` / `invalid_output`：外部 summary provider 或结构化输出校验失败。

重新生成时设置 `forceRegenerate: true`。删除 summary 只删除 generated metadata：

```bash
curl -X DELETE http://127.0.0.1:3210/api/v1/ai/media-summary/summary-uuid \
  -H "Authorization: Bearer $TOKEN"
```

AI summary generated metadata 会进入 iPhone 本地 Timeline search；当前 server `/api/v1/search` 仍只搜索 post text、comments 和历史 media transcription metadata。`media-summary-v3` 的主内容是 `documentTitle`、`oneLiner` 和 `documentBlocks`；`overview`、`keyPoints`、`sections` 和 `summaryText` 继续保留，主要用于 copy 文本和旧客户端兼容。v3 要求可识别非空音频/转录生成 40 字符以内短标题，server 会在 provider 返回空/过长标题时从 `oneLiner` 派生 fallback。排查时只记录 id、状态、provider/model、错误码和 transcript length；不要复制私人 transcript 或 summary 正文。`AI_TRANSCRIPTION_PROVIDER=local` 是默认路径，本地转写模型和超时可通过 `AI_LOCAL_TRANSCRIPTION_MODEL` / `AI_LOCAL_TRANSCRIPTION_TIMEOUT_MS` 覆盖。`/api/v1/admin/status` 的 `aiSummaries` 字段提供 `transcribing`、`summarizing`、`ready`、`failed` 计数和非 ready 项，供 iOS Settings > Storage & Diagnostics 显示；recent diagnostics 还包含卡住时长和 retry hint。

新 audio 的 AI 标题写回通过 `insert_ai_title` 同步，不使用普通 `update_post`。payload 只包含 `{summaryId, mediaId, insertedAt}`；server 从自己的 ready audio summary 读取 `documentTitle`，验证 post/media/summary 关系和当前 post 没有行首 `# ` / `## ` 标题后，才发出 `post_updated`，并带 `updateSource: "ai_title"`。客户端应用该 change 时不应把它当作用户手动编辑。

`ai_summary_updated` 是 server-originated change。客户端即使没有本地 outbox operation，也需要通过正常 sync pull 到这些变更；如果 Mac 上 summary 已经 ready 但 iPhone 仍不可见，先比较 iPhone `lastSyncCursor` 和 server `server_changes.version`。

## Media Upload

用 multipart form data 上传 media file；下面是 image 的最小示例：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/media/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F mediaId=media-uuid \
  -F postId=post-uuid \
  -F variant=compressed \
  -F kind=image \
  -F mimeType=image/jpeg \
  -F originalPreserved=false \
  -F sortOrder=0 \
  -F file=@image.jpg
```

Server 会把文件存到 configured data directory，只把 relative file paths 和 metadata 写入 SQLite。`kind` 支持 `image`、`video`、`audio`；视频 poster 用同一 endpoint 上传为 `variant=thumbnail`，完整音频/视频用 `variant=compressed`。音频/视频可附带 `durationSeconds`。新 iOS 不再附带 `transcriptionText`；完整 audio/video 上传后 server 会异步启动 AI summary job。Admin 和 iOS timeline 会显示轻量时长。

## Media Batch Download

iOS 使用 batch download 做 remote image thumbnail 和 video poster cache recovery：

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

Server 使用 `sips` 按需生成 image thumbnail variants。视频 poster 由 iOS 上传为 `thumbnail` variant。当前 image thumbnail policy 是 max edge `800px`；如果已有 thumbnail 超过 server threshold，会重新生成。

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
  "schemaVersion": 9,
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
  },
  "sync": {
    "latestServerChangeVersion": 194
  },
  "aiSummaries": {
    "total": 10,
    "transcribing": 0,
    "summarizing": 0,
    "ready": 4,
    "failed": 6,
    "deleted": 0,
    "recent": [
      {
        "id": "summary-uuid",
        "mediaId": "media-uuid",
        "status": "failed",
        "errorCode": "local_transcription_failed",
        "inputTranscriptLength": null,
        "inputDurationSeconds": 42.5,
        "updatedAt": "2026-05-01T10:20:30.000Z"
      }
    ]
  },
  "tags": {
    "total": 18,
    "primary": 6,
    "topics": 12,
    "archived": 1,
    "aiAssignments": 4,
    "manualAssignments": 9
  }
}
```

`databaseBytes` 包含 SQLite database 以及 `-wal`、`-shm` sidecar files。`totalBytes` 是整个 configured data directory。`availableBytes` 是 data directory 所在 volume 的可用空间。`sync.latestServerChangeVersion` 是 Mac server 已写入的最大 `server_changes.version`，可和 iPhone `lastSyncCursor` 比较。`aiSummaries.recent` 只返回非 ready 项的状态、错误码、duration 和 transcript length，不返回 transcript 或 summary 正文。`tags` 只返回安全计数，不返回 post text、comment text、transcript 或 summary 正文。

## Admin Posts Filters

`GET /api/v1/admin/posts` 支持：

| Query | Values | Notes |
|---|---|---|
| `deleted` | `active`, `deleted`, `all` | UI 默认显示 active。 |
| `deviceId` | device UUID | 按 `createdByDeviceId` 过滤。 |
| `q` | text | 搜索 post text、comment text，并兼容搜索历史 media transcription text。Search 最多返回 100 rows，不使用 cursor pagination。 |
| `limit` | `1..100` | 默认 list limit 是 50。 |
| `cursor` | encoded cursor | 用于非 search list pagination。 |

`POST /api/v1/admin/devices/:deviceId/clean-posts` 需要：

```json
{
  "confirmDeviceName": "Device display name"
}
```

它会永久删除该 device 创建的 posts，并写入最小化的 `post_deleted` server changes，让 iOS caches 在下次 sync 时隐藏这些 posts。
