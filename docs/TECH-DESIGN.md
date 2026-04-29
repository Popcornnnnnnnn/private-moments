# Private Moments Technical Design

## 1. 架构概览

Private Moments 采用 iOS 原生 App + Mac 自托管服务端的本地优先架构。

```text
iPhone App
  Swift + SwiftUI
  SQLite3 local database
  local drafts
  local timeline cache
  outbox sync queue
  media compression
        |
        | Tailscale / private VPN
        | HTTPS or HTTP over private network
        v
Mac Server
  Node.js + TypeScript
  Fastify API
  Prisma + SQLite
  local file storage
  launchd login service
        |
        v
Mac Admin UI
  React + Vite
  served by Fastify
```

Mac 是最终归档源，iPhone 是本地优先缓存和待同步队列。iPhone 离线时可以完整创建内容和浏览已有本地内容；Mac 可达后再通过 sync endpoint 对账。

## 2. Monorepo 结构

项目放在 `private-moments/` 子目录，不直接在上层 `07-github` 根目录工作。

建议结构：

```text
private-moments/
  ios/
    PrivateMoments.xcodeproj
    PrivateMoments/
  server/
    package.json
    src/
      api/
      auth/
      config/
      db/
      media/
      sync/
      admin/
      logging/
    prisma/
      schema.prisma
      migrations/
  admin/
    package.json
    src/
  shared/
    openapi.yaml
    sync-protocol.md
  docs/
    PRD.md
    TECH-DESIGN.md
    INTEGRATION-GUIDE.md
    OPERATOR-RUNBOOK.md
    HANDOFF.md
    DESIGN-PRINCIPLES.md
```

当前仓库已经包含 `ios/`、`server/`、`admin/`、`shared/` 的 MVP 骨架和可编译实现。

当前实现已经覆盖第一版本地构建：iOS 本地优先发布文字和图片、手动选择发生时间、草稿保存、离线 outbox、自动延迟重试、图片上传压缩与远端图片缓存、设置页存储诊断、英文人性化时间标签、滚动月份浮层提示、时间线搜索、收藏、筛选、月份跳转、详情页、编辑、软删除同步，以及 Mac 后台状态页和 Posts 运维管理。

当前 comment 基础设施已经具备 contract 层能力：Mac server 有 private comments 表和 `create_comment` / `delete_comment` sync operations，iOS 本地 SQLite 有 `local_comments` 表、outbox payload builders 和 server change apply 逻辑。可见 UI 入口尚未开放；评论仍是后续详情页功能的底层数据能力。

当前 UI 设计原则是保持主时间线安静：筛选、月份跳转、收藏和管理能力应尽量藏在 toolbar menu、滑动操作或详情页里，避免把主界面做成后台管理界面。详细原则见 `docs/DESIGN-PRINCIPLES.md`。

iOS 主要模块已经按职责拆分。`TimelineStore` 按 session、mutations、sync、server changes、media、payloads 和 sync retry 拆分；`LocalDatabase` 按 schema、records、timeline、sync、storage stats 和 SQLite helper 拆分；`TimelineView` 拆出 `TimelineRow`、`MomentDateFormatter`、`MediaGalleryView` 和 `ZoomableLocalImage`。设置页存储诊断拆在 `StorageStats.swift` 和 `StorageSettingsView.swift`。后续继续加功能时优先扩展这些小文件，不再把同步、数据库或主界面逻辑塞回单一大文件。

## 2.1 时间线交互决策

时间线 UI 保持英文体系和低干扰原则。`MomentDateFormatter` 负责把 `occurredAt` 转换为 `Just now`、`2 min ago`、`Today 2:40 PM`、`Yesterday 2:40 PM`、`Apr 29, 2:40 PM` 这类更接近日常阅读的标签。月份标题不再作为列表里的常驻结构块，而是通过滚动时短暂出现的 `FloatingMonthIndicator` 提供方向感；停止滚动后自动淡出。

时间线删除使用右侧 swipe action 打开居中的系统 `alert`。右滑删除不允许 full swipe，并在点击 Delete 后延迟约 180ms 展示确认框，让系统 swipe 行先收回，避免列表跳动。这里不要使用位置相关的 `confirmationDialog`，因为它会表现得像从某个列表行冒出的气泡，删除确认语义不够清楚。

## 2.2 详情与编辑决策

详情页是单条动态的管理入口。时间线点击动态进入详情页，详情页负责查看完整内容、图片浏览、编辑入口和删除入口。图片浏览器只负责查看，不承担删除操作。

编辑采用直接覆盖模型：保存后原动态只显示最新文字、发生时间和图片列表，不提供可见历史版本。编辑页支持修改文字、发生时间、新增图片、删除图片和 9 张以内图片的长按拖拽重排。保存时，编辑页里的最终图片列表就是新状态；服务端软删除移除的图片，保留新增图片等待上传，重排后的 `sortOrder` 作为权威顺序。

iOS 继续本地优先：编辑先写入本地 SQLite 和 outbox，网络可达后自动同步到 Mac。同步中或部分同步的动态暂不允许编辑，避免多个本地操作和媒体上传互相打架；已同步或失败的动态允许编辑。新增图片上传失败时，动态显示 `partial`。

收藏是独立的轻量元数据操作，不进入编辑页。iOS 本地更新 `isFavorite` 并写入 `update_post_favorite` outbox operation；Mac 接收后更新 `posts.is_favorite`，写入 `post_favorite_updated` server change，再由其他设备同步。

编辑草稿按 `postId` 保存在本机文件目录中。打开编辑页时如果有草稿，先询问继续编辑草稿或丢弃草稿。保存成功或用户主动丢弃后清除草稿。

## 2.3 Mac Admin Posts 管理决策

Mac Admin 的 Posts 功能定位为运维管理台，不替代 iPhone 的内容编辑入口。第一版采用 `Overview / Posts` 顶部 tab：Overview 保持服务、设备、日志和存储概览；Posts 负责内容查看、排查和清理测试数据。

Posts 页面采用列表 + 右侧详情抽屉。列表用于快速扫描文字摘要、发生时间、图片数、创建设备、更新设备、删除状态和基础同步状态；详情抽屉用于查看完整正文、图片网格、媒体状态、大小、checksum、`serverVersion`、创建/更新设备和删除时间。图片在详情抽屉内显示缩略图，点击后以全屏 lightbox 查看压缩展示图。

列表默认只显示未删除 posts，可切换查看软删除 posts。普通列表沿用 cursor 分页，默认 50 条，支持 `Load more`。文本搜索用于定位少量记录，第一版限制最多 100 条，不做搜索分页。筛选能力包括创建设备、删除状态和文本搜索。

后台单条删除只放在详情抽屉内，必须二次确认。单条删除采用软删除：服务端设置 `Post.deletedAt`，将该 post 下未删除媒体标记为 deleted，并写入 `post_deleted` server change；iPhone 下次同步后隐藏本地缓存。第一版不做软删除恢复。

设备行提供 `Clean posts` 危险操作，用于永久清理某设备创建的测试数据。该操作只匹配 `createdByDeviceId`，不匹配仅被该设备更新过的 posts。执行前必须展示候选数量和设备名，并要求输入设备名确认。执行后不自动撤销设备。

永久清理会删除匹配 posts 的数据库记录和媒体文件，Posts 管理里不再显示这些记录。为保持 iPhone 与 Mac 一致，服务端在删除数据库记录前为每个 post 写入最小 `post_deleted` server change；下次 iPhone 同步时隐藏本地缓存。后台日志记录清理操作的设备、数量和操作者。

设备绑定使用 `deviceKey` 防止重复注册。同一用户、同一平台、同一 `deviceKey` 只能对应一条 `Device`：iOS 使用 `UIDevice.identifierForVendor`，Mac Admin 浏览器使用本地 `localStorage` UUID。重复登录会更新原设备的 token、名称和 lastSeenAt，而不是插入新设备。为了兼容旧客户端，如果带 `deviceKey` 的登录找不到完全匹配记录，服务端会优先复用同名、同平台、未绑定 `deviceKey` 的旧设备记录。

## 2.4 Settings Storage 诊断决策

iOS Settings 的 Storage 功能是诊断入口，不是清理入口。主 Settings 只显示一行摘要，例如 `iPhone 120 MB, Mac 430 MB`；详情页使用系统 Form 风格展示更细的只读信息。

本机统计由 iOS 直接扫描本地文件和 SQLite 状态：

- 总占用。
- SQLite 数据库、`-wal`、`-shm`。
- 图片缓存目录。
- 待同步操作数。
- 待上传图片数。
- 失败上传数。

Mac server 统计通过 `GET /api/v1/admin/status` 获取。服务端的 `server/src/storage/stats.ts` 统计数据目录总量、SQLite 相关文件、media 目录、logs 目录和数据目录所在卷的可用空间。iOS 已登录且请求成功时显示 Mac Server 区域；如果 Mac 不在线、token 不可用或请求失败，详情页隐藏 Mac Server 区域，不弹错误。

第一版 Storage 不提供清理、删除、重建缓存或迁移操作，避免 Settings 主界面变成后台管理台。后续如果加空间管理，危险操作必须进入二级确认或独立页面。

## 3. 技术栈

### iOS App

- Swift。
- SwiftUI。
- 系统 SQLite3。当前先用轻量自写访问层减少外部依赖，后续如果本地查询复杂度上升，可以再替换为 GRDB。
- 本地文件目录保存压缩图和待上传原图副本。
- 使用系统相册/相机能力。
- 本地 outbox 队列驱动同步。
- 失败同步或上传任务使用 5s、20s、60s、120s、300s 的延迟自动重试。
- 发布草稿保存文字、发生时间和已选择图片。
- 远端同步来的压缩图会下载到本地缓存后展示。
- Settings > Storage 展示本机存储和同步健康状态，Mac 在线时额外展示服务端存储状态。

### Mac Server

- Node.js。
- TypeScript。
- Fastify。
- Prisma。
- SQLite。
- 本地文件存储。
- launchd 登录后自动启动。
- `/api/v1/admin/status` 返回服务状态、计数和存储诊断。

### Mac Admin UI

- React。
- Vite。
- 构建后由 Fastify 静态托管。

### Shared Contract

- `shared/openapi.yaml` 描述 API 字段、认证和响应结构。
- `shared/sync-protocol.md` 描述同步协议语义、幂等、冲突和 cursor 规则。

## 4. Mac 数据目录

默认数据目录：

```text
~/Library/Application Support/PrivateMoments/
  manifest.json
  app.sqlite
  media/
    compressed/
    originals/
    thumbnails/
    temp/
  exports/
  logs/
```

### manifest.json

`manifest.json` 用于记录数据目录版本，支持未来迁移和备份校验。

草案：

```json
{
  "app": "PrivateMoments",
  "dataVersion": 1,
  "schemaVersion": 1,
  "createdAt": "2026-04-28T00:00:00.000Z",
  "mediaLayoutVersion": 1
}
```

## 5. 服务端数据模型

服务端使用 Prisma + SQLite。图片二进制文件不存入 SQLite，数据库只保存元数据和文件路径。

### User

MVP 只有单用户，但保留用户表有利于认证和未来扩展。

字段草案：

```text
user
  id
  passwordHash
  createdAt
  updatedAt
```

### Device

记录已授权设备和撤销状态。

```text
device
  id
  userId
  name
  deviceKey
  tokenHash
  platform
  lastSeenAt
  revokedAt
  createdAt
  updatedAt
```

`device token` 明文只在登录时返回给 iOS。服务端保存 `tokenHash`。

`deviceKey` 用于复用同一个物理设备或同一个浏览器安装，避免重复登录时产生大量同名设备。iOS 使用 `UIDevice.identifierForVendor` 派生稳定 key；Mac Admin 浏览器使用 `localStorage` UUID。

### Post

```text
post
  id
  text
  isFavorite
  occurredAt
  createdAt
  updatedAt
  deletedAt
  clientCreatedAt
  clientUpdatedAt
  serverVersion
  createdByDeviceId
  updatedByDeviceId
```

说明：

- `occurredAt` 是用户可手动修改的发生时间，用于时间线和月份归档。
- `isFavorite` 是收藏状态，独立于编辑流同步。
- `createdAt`/`updatedAt` 是服务端记录时间。
- `deletedAt` 为软删除时间。
- `serverVersion` 用于增量同步。

### Media

```text
media
  id
  postId
  kind
  status
  compressedPath
  originalPath
  thumbnailPath
  originalPreserved
  width
  height
  compressedSizeBytes
  originalSizeBytes
  checksum
  sortOrder
  createdAt
  updatedAt
  deletedAt
```

`kind` MVP 只支持 `image`。

`status` 可选：

```text
pending
uploaded
failed
deleted
```

### Comment

Private comments 是附着在 post 下的单层 plain-text note。当前服务端 schema 和 sync contract 已支持，iOS 也有本地表和同步 plumbing；可见 UI 入口尚未开放。

```text
comment
  id
  postId
  text
  createdAt
  updatedAt
  deletedAt
  clientCreatedAt
  clientUpdatedAt
  serverVersion
  createdByDeviceId
  updatedByDeviceId
```

说明：

- `postId` 指向所属 post。
- `text` 是普通字符串，不渲染 Markdown，不支持 replies、likes、mentions 或 public author identity。
- `deletedAt` 为软删除时间。
- `serverVersion` 用于增量同步。

### SyncOperation

服务端记录设备提交过的操作，用于幂等和排查。

```text
sync_operation
  id
  opId
  deviceId
  type
  entityType
  entityId
  payloadJson
  receivedAt
  appliedAt
  rejectedAt
  rejectionReason
```

`opId` 由客户端生成，同一设备内唯一。服务端对 `(deviceId, opId)` 建唯一索引，避免重复创建。

### ServerChange

服务端变更日志，用于 sync cursor 拉取增量。

```text
server_change
  version
  entityType
  entityId
  changeType
  payloadJson
  createdAt
```

`version` 是单调递增的服务端序号。客户端的 `syncCursor` 指向最后已处理的 `version`。

## 6. iOS 本地数据模型

iOS 使用 SQLite，模型与服务端接近，但增加本地状态字段。

### local_post

```text
local_post
  id
  text
  isFavorite
  occurredAt
  localCreatedAt
  localUpdatedAt
  serverVersion
  syncStatus
  deletedAt
```

`syncStatus` 可选：

```text
draft
pending
partial
synced
failed
deleted_pending
```

### local_media

```text
local_media
  id
  postId
  localCompressedPath
  localOriginalStagingPath
  remoteCompressedPath
  remoteOriginalPath
  originalPreserved
  uploadStatus
  sortOrder
  checksum
  createdAt
  updatedAt
```

### local_comment

```text
local_comment
  id
  postId
  text
  createdAt
  updatedAt
  serverVersion
  syncStatus
  deletedAt
```

`local_comment` 是 iOS 端 private comments 的本地缓存和待同步状态来源。comment outbox operation 的 `entityId` 是 comment id；payload 中保留 `postId`，用于本地把 comment 同步状态映射回所属 moment。

### outbox_operation

```text
outbox_operation
  id
  opId
  type
  entityType
  entityId
  payloadJson
  status
  attemptCount
  lastError
  createdAt
  updatedAt
  sentAt
```

`outbox_operation` 是本地优先架构的核心。UI 更新不等待网络成功，所有用户操作先写本地，再进入 outbox。

### sync_state

```text
sync_state
  key
  value
```

关键值：

```text
deviceId
lastSyncCursor
lastSuccessfulSyncAt
```

## 7. API 设计

所有 API 使用 `/api/v1` 前缀。响应中应包含 `serverVersion` 和 `schemaVersion`，至少在认证、健康检查和同步响应中提供。

### 认证

iOS API 使用 Bearer device token：

```http
Authorization: Bearer <device-token>
```

登录后返回长期 token。token 长期有效，可在后台撤销。高风险操作需要重新验证密码。

### Core Endpoints

```text
GET    /api/v1/health
POST   /api/v1/auth/login
GET    /api/v1/devices
DELETE /api/v1/devices/:deviceId
POST   /api/v1/sync
POST   /api/v1/media/upload
POST   /api/v1/media/batch-download
GET    /api/v1/media/:mediaId
GET    /api/v1/timeline
GET    /api/v1/posts/:postId
GET    /api/v1/search?q=...
GET    /api/v1/admin/status
GET    /api/v1/admin/logs
GET    /api/v1/admin/posts
GET    /api/v1/admin/posts/:postId
DELETE /api/v1/admin/posts/:postId
GET    /api/v1/admin/devices/:deviceId/clean-posts/preview
POST   /api/v1/admin/devices/:deviceId/clean-posts
```

说明：

- `/api/v1/timeline` 和 `/api/v1/posts/:postId` 主要用于读取和调试。
- 离线创建、删除和未来编辑通过 `/api/v1/sync` 处理。
- 图片文件通过 `/api/v1/media/upload` 上传，避免把大文件塞进 sync JSON。
- iOS 拉取远端图片优先使用 `/api/v1/media/batch-download` 获取缩略图 JSON，避免真机/Tailscale 场景下多次二进制下载超时。
- Mac Admin 路由复用 Bearer device token，普通内容发布仍然只在 iOS 端进行。
- `/api/v1/admin/status` 同时给 Mac Admin 和 iOS Settings Storage 使用；storage 字段包含 `totalBytes`、`databaseBytes`、`mediaBytes`、`logsBytes`、`availableBytes`。

## 8. Sync Endpoint

`sync endpoint` 本质上是一个 HTTP API，但语义是设备与服务器对账，而不是对单一资源做 CRUD。

### 请求草案

```json
{
  "deviceId": "device-uuid",
  "lastSyncCursor": 120,
  "localChanges": [
    {
      "opId": "op-uuid-1",
      "type": "create_post",
      "entityType": "post",
      "entityId": "post-uuid",
      "clientCreatedAt": "2026-04-28T10:00:00.000Z",
      "payload": {
        "text": "去了咖啡店",
        "occurredAt": "2026-04-28T09:30:00.000Z",
        "mediaIds": ["media-uuid-1"]
      }
    },
    {
      "opId": "op-uuid-2",
      "type": "delete_post",
      "entityType": "post",
      "entityId": "post-uuid",
      "clientCreatedAt": "2026-04-28T11:00:00.000Z",
      "payload": {
        "deletedAt": "2026-04-28T11:00:00.000Z"
      }
    }
  ]
}
```

### 响应草案

```json
{
  "serverVersion": "0.1.0",
  "schemaVersion": 1,
  "acceptedOps": ["op-uuid-1", "op-uuid-2"],
  "rejectedOps": [],
  "serverChanges": [
    {
      "version": 121,
      "entityType": "post",
      "entityId": "post-uuid",
      "changeType": "post_created",
      "payload": {
        "id": "post-uuid",
        "text": "去了咖啡店",
        "occurredAt": "2026-04-28T09:30:00.000Z",
        "deletedAt": null
      }
    }
  ],
  "nextSyncCursor": 121
}
```

### 同步规则

- 客户端先写本地数据库，再写 outbox。
- App 打开后自动触发同步。
- 切到后台或锁屏后尽量继续传完当前同步任务。
- 每个操作必须有 `opId`。
- 服务端使用 `(deviceId, opId)` 保证幂等。
- `syncCursor` 表示客户端已处理到的服务端 `server_change.version`。
- 同步时客户端上传本地变化，同时拉取 `lastSyncCursor` 之后的服务端变化。
- 多设备冲突使用最后写入胜出。
- 服务端保留操作日志用于排查。
- iOS 只在成功应用全部 `serverChanges` 后推进本地 cursor。
- iOS 兼容带毫秒和不带毫秒的 ISO8601 时间；解析失败会让本轮同步失败，而不是静默跳过变更后推进 cursor。
- `didApplySyncRecoveryV1` 用于 2026-04-29 的一次性恢复：如果本地为空或旧 cursor 可能已经错误推进，启动后会把 cursor 重置为 0 从服务端完整拉取。

## 9. 图片上传流程

图片文件不直接放进 `/api/v1/sync`。

推荐流程：

1. iOS 生成 `postId` 和 `mediaId`。
2. iOS 生成压缩展示图，并移除 EXIF/GPS。
3. 如果用户选择保留原图，iOS 保留原图待上传副本。
4. iOS 本地创建 post 和 media 记录。
5. iOS 创建 `create_post` outbox operation。
6. 同步时先通过 `/api/v1/media/upload` 上传图片文件。
7. 图片可以逐张成功或失败。
8. iOS 通过 `/api/v1/sync` 同步帖子和图片元数据。
9. 服务端记录部分同步状态。
10. 失败图片保留在本地队列中自动重试。

iOS 在保存展示图和上传文件前都会压缩图片。当前压缩展示策略是最大边 `1600px`、JPEG 质量 `0.72`，并移除 EXIF/GPS 等隐私元数据。上传时再次走压缩路径，因此旧版本遗留的 pending 大图也会在下一次上传前被压缩。

图片上传逐张执行；任意图片失败不会阻塞本地时间线展示。失败后本地状态保持可重试，并由 sync retry 调度器按 5s、20s、60s、120s、300s 间隔自动重试。

远端图片回填：

1. iOS 应用 `media_uploaded` 或远端 post 变更后，找出本地缺失的已上传图片。
2. iOS 调用 `POST /api/v1/media/batch-download`，默认请求 `thumbnail` variant。
3. 服务端用 macOS `sips` 按需生成最大边 800px 的 JPEG 缩略图，并把过大的旧缩略图重新压缩到目标范围。
4. 服务端返回 base64 JSON：`id`、`variant`、`contentType`、`fileName`、`base64`。
5. iOS 写入本地 media cache，并更新 `localCompressedPath`。

保留 `GET /api/v1/media/:mediaId?variant=...` 作为单文件下载和 Admin 图片预览入口。iOS 主同步路径优先使用批量 JSON 下载，因为 2026-04-29 真机验证发现多次独立二进制下载在 Tailscale/iOS 组合下更容易超时。

### 部分同步

如果文字和部分图片已同步，但还有图片失败，帖子状态为 `partial`。UI 可展示本地完整内容，设置页显示失败明细。

## 10. 删除和清理

MVP 支持删除，不支持完整回收站 UI。

删除流程：

1. 用户在 iOS 删除 post。
2. iOS 设置本地 `deletedAt`。
3. iOS 创建 `delete_post` outbox operation。
4. 同步成功后服务端设置 `post.deletedAt` 和相关 `media.deletedAt`。
5. 服务端 30 天后永久删除数据库记录和图片文件。

清理任务可由 Mac 服务端定时执行，也可在服务启动时执行一次。

当前实现会在服务启动时执行一次清理，并在服务运行中每 6 小时清理一次 30 天前软删除的帖子和媒体文件。删除文件时只允许删除数据目录内部的相对路径，避免误删数据目录外文件。

## 11. Mac 后台

后台 UI 由 React + Vite 实现，构建后作为静态资源由 Fastify 托管。

MVP 页面：

- Overview：服务状态、版本、schemaVersion。
- Devices：设备列表、撤销设备。
- Storage：数据目录、数据库大小、媒体大小。
- Sync：同步状态和失败概览。
- Logs：文件日志。
- Posts：内容运维列表、筛选、详情抽屉、图片预览、软删除和按设备清理测试数据。

后续页面：

- Trash：回收站和恢复。
- Backup：导出 zip 备份。
- Search：独立搜索增强；当前 Posts 页已有文本搜索。

## 12. 日志

服务端写文件日志到：

```text
~/Library/Application Support/PrivateMoments/logs/
```

MVP 不强制日志轮转，但日志格式应结构化，便于后台展示和排查。

建议字段：

```json
{
  "time": "2026-04-28T10:00:00.000Z",
  "level": "info",
  "event": "sync.completed",
  "deviceId": "device-uuid",
  "acceptedOps": 3,
  "failedUploads": 1
}
```

## 13. launchd 自启动

Mac 服务端第一版使用 `launchd` 登录自启动。

设计要求：

- 服务进程读取固定数据目录。
- 配置文件可放在数据目录或 `server/config`。
- stdout/stderr 可由 launchd 接管。
- 应用自身仍写文件日志。
- 后续可增加菜单栏 App 包装启动状态。

## 14. OpenAPI 与同步协议文档

`shared/openapi.yaml` 描述：

- `/api/v1/health`
- `/api/v1/auth/login`
- `/api/v1/devices`
- `/api/v1/sync`
- `/api/v1/media/upload`
- `/api/v1/media/batch-download`
- `/api/v1/timeline`
- `/api/v1/search`
- `/api/v1/admin/status`
- `/api/v1/admin/logs`
- `/api/v1/admin/posts`
- Admin status 的 storage diagnostics 字段。
- Bearer token 认证。
- 通用错误响应。

`shared/sync-protocol.md` 描述：

- `syncCursor` 语义。
- `opId` 幂等。
- outbox 处理顺序。
- 图片上传与帖子同步顺序。
- 图片压缩、逐张上传和失败重试。
- 多设备最后写入胜出。
- 删除和软删除。
- 部分同步状态。

## 15. 安全

MVP 安全边界：

- Tailscale 或私有 VPN。
- 单用户密码登录。
- Bearer device token。
- 服务端保存 token hash。
- 设备可撤销。
- 高风险操作重新验证密码。
- Mac 文件权限。

不做：

- 端到端加密。
- 应用级本地数据库加密。
- 多用户权限。
- OAuth。
- 2FA。

## 16. 性能和可靠性

### iOS

- 时间线本地优先渲染。
- 本地 SQLite 保存全部文本元数据。
- 已下载图片缓存保存在本地。
- 旧图片按需下载。
- 同步不阻塞主 UI。
- 图片压缩在后台任务中执行。
- 失败同步和上传自动延迟重试。
- Settings > Storage 可快速查看本地占用和同步健康状态。

### Mac

- SQLite 对单用户场景足够。
- 图片文件存磁盘，数据库只存路径和元数据。
- `server_change.version` 支持增量同步。
- sync endpoint 支持批量操作和重试。
- `/api/v1/admin/status` 暴露服务端数据目录存储诊断，供 Admin 和 iOS Settings 使用。

## 17. 未来阶段

第二阶段：

- 回收站 UI。
- 应用内一键 zip 备份导出。
- 更完整的 storage cleanup。
- 多设备冲突提示。
- 原图保留策略和空间管理。

第三阶段：

- iCloud Drive 备份包输出。
- 多设备体验增强。
- 原生后台传输优化。
- 菜单栏 Mac App。
- 开源安装文档完善。

## 18. 已确认架构决策

- iOS 原生 App 是主入口。
- Mac 是服务器和后台。
- 使用 Tailscale 或私有 VPN，不公网暴露。
- Mac 是权威归档源。
- iPhone 是本地优先缓存 + 待同步队列。
- 单用户，但数据结构支持多设备。
- 多设备冲突使用最后写入胜出 + 操作日志。
- 时间线本地优先渲染 + 后台增量同步。
- iPhone 缓存全部元数据 + 已下载图片缓存。
- 文本搜索在 iPhone 本地和 Mac 后台都支持。
- MVP 做发布、同步、详情、编辑、收藏、筛选、删除和 Mac Admin Posts 运维。
- 回收站 UI、备份导出、多设备冲突提示后置。
