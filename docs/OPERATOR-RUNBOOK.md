# Private Moments 运维手册

这份 runbook 覆盖 Mac server、Admin UI 和 iOS test app 的本地运行、验证和排障。

## 环境要求

- 安装 Xcode 的 macOS。
- Node.js `>=22`。
- `npm`。
- `xcodegen`，用于重新生成 `ios/PrivateMoments.xcodeproj`。
- Tailscale，用于真实 iPhone 访问 simulator localhost 之外的 Mac server。
- 已配对的 iPhone 需要解锁，并信任当前 Mac，才能通过命令行安装。

## 环境变量

| Variable | Default | Purpose |
|---|---|---|
| `HOST` | `127.0.0.1` | Server bind address。真实 iPhone 通过 LAN/Tailscale 访问时使用 `0.0.0.0`。 |
| `PORT` | `3210` | Server port。 |
| `LOG_LEVEL` | `info` | Fastify log level。 |
| `PRIVATE_MOMENTS_INITIAL_PASSWORD` | unset | 数据库没有 user 时，用于创建第一个本地用户。 |
| `PRIVATE_MOMENTS_DATA_DIR` | `~/Library/Application Support/PrivateMoments` | Runtime data directory。开发时常用 `./server/data`。 |
| `DATABASE_URL` | `file:<dataDir>/app.sqlite` | Prisma SQLite database URL。`server/.env.example` 里的 `file:./dev.db` 是相对 `server/prisma/schema.prisma`。 |
| `PRIVATE_MOMENTS_SERVER_URL` | `http://127.0.0.1:3210` | Simulator script server URL。 |
| `PRIVATE_MOMENTS_SIM_NAME` | `Private Moments iPhone 13 Pro` | Simulator display name。 |
| `PRIVATE_MOMENTS_DEVICE_TYPE` | `com.apple.CoreSimulator.SimDeviceType.iPhone-13-Pro` | Simulator device type。 |
| `PRIVATE_MOMENTS_DEVICE_NAME` | `wwz 的 iphone` | `devicectl` 使用的真实 iPhone 名称。 |
| `PRIVATE_MOMENTS_DEVICE_SERVER_URL` | auto-detected | 真实设备 server URL override。 |
| `PRIVATE_MOMENTS_LAUNCHD_LABEL` | `com.private-moments.server` | launchd label。 |

## 本地开发启动

```bash
npm install
cp server/.env.example server/.env
npm run server:prisma:generate
npm run server:prisma:migrate
npm run admin:build
npm run server:dev
```

第一次启动前，需要在 `server/.env` 里设置真实的 `PRIVATE_MOMENTS_INITIAL_PASSWORD`。Agent 应使用安全 secret 收集机制处理这个值，不要在聊天或文档中要求用户粘贴密码。

真实 iPhone 测试时，让 server 可以从 Tailscale 访问：

```text
HOST=0.0.0.0
PRIVATE_MOMENTS_DATA_DIR="./data"
```

## 构建和安装 iOS

Simulator：

```bash
npm run ios:simulator
```

真实 iPhone：

```bash
npm run ios:device
```

真实设备脚本会：

1. 检查候选 server URLs。
2. 如果可用，用 `xcodegen` 重新生成 Xcode project。
3. 构建 Debug iPhoneOS app。
4. 使用 `xcrun devicectl` 安装。
5. 启动 `com.popcornnnnnn.privatemoments`。

如果 iPhone 阻止未信任开发者 app，在手机上信任开发者：

```text
Settings > General > VPN & Device Management > Developer App
```

## Mac Admin

执行 `npm run admin:build` 后，server 会提供：

```text
http://127.0.0.1:3210/admin/
```

Admin 使用和 iOS login 相同的 password。Admin 会注册为 web device，并使用同一套 Bearer token flow。

## launchd Service

安装：

```bash
server/scripts/install-launchd.sh
```

卸载：

```bash
server/scripts/uninstall-launchd.sh
```

生产数据默认放在：

```text
~/Library/Application Support/PrivateMoments
```

launchd stdout/stderr logs：

```text
~/Library/Logs/private-moments.out.log
~/Library/Logs/private-moments.err.log
```

Application logs：

```text
<dataDir>/logs/app-YYYY-MM-DD.jsonl
```

## Smoke Checks

Server health：

```bash
curl -fsS http://127.0.0.1:3210/api/v1/health
```

从 Mac 检查 Tailscale reachability：

```bash
tailscale ip -4
curl -fsS http://<tailscale-ip>:3210/api/v1/health
```

Admin build 和 server typecheck：

```bash
npm run admin:build
npm run server:typecheck
```

Admin storage diagnostics。登录后把 device token 设置到 `TOKEN`：

```bash
curl -fsS http://127.0.0.1:3210/api/v1/admin/status \
  -H "Authorization: Bearer $TOKEN"
```

响应应包含 `counts`，以及 `storage.totalBytes`、`storage.databaseBytes`、`storage.mediaBytes`、`storage.logsBytes` 和 `storage.availableBytes`。

iOS 无签名编译检查：

```bash
cd ios
xcodegen generate
xcodebuild -project PrivateMoments.xcodeproj \
  -scheme PrivateMoments \
  -destination generic/platform=iOS \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 真实 iPhone 数据验证

复制 app 的 Library container：

```bash
rm -rf .tmp/device-app-library-check
mkdir -p .tmp/device-app-library-check
xcrun devicectl device copy from \
  --device "wwz 的 iphone" \
  --domain-type appDataContainer \
  --domain-identifier com.popcornnnnnn.privatemoments \
  --source Library \
  --destination .tmp/device-app-library-check \
  --timeout 60
```

检查 sync state：

```bash
plutil -p .tmp/device-app-library-check/Preferences/com.popcornnnnnn.privatemoments.plist
sqlite3 '.tmp/device-app-library-check/Application Support/PrivateMoments/private-moments.sqlite' \
  'SELECT COUNT(*) FROM local_posts WHERE deletedAt IS NULL;'
```

Media recovery 常用检查：

```sql
SELECT COUNT(*) AS missing_visible_media
FROM local_media m
JOIN local_posts p ON p.id = m.postId
WHERE m.uploadStatus='uploaded'
  AND m.remoteCompressedPath IS NOT NULL
  AND m.localCompressedPath = ''
  AND m.deletedAt IS NULL
  AND p.deletedAt IS NULL;
```

Cache recovery 健康状态下，`missing_visible_media` 应为 `0`。

## Private Comments UAT

Private Comments 是 Moment detail 里的私密 follow-up notes。UAT 目标是证明 create/delete、同步状态和持久化都工作，同时确认主 timeline 没有变成评论流。记录证据时只记录 aggregate counts、状态和命令结果；不要把密码、device token、server URL 中的 secret、或私密评论正文粘贴到日志、issue、handoff 或聊天里。

### 前置条件

- Mac server 已启动，并且真实 iPhone 能通过 Tailscale、Tailscale Serve HTTPS 或 LAN URL 访问。
- iPhone 已安装当前 Debug app，并在 Settings 中登录同一 Mac server。
- 如果需要验证 server SQLite，先确认 active server 使用的 database 已应用 schema version 4 migration；`GET /api/v1/health` 或 Admin Overview 应显示 `schemaVersion: 4`。
- UAT 文本可以包含多行和 Markdown-like 字符，例如 `# heading`、`**bold**`、`- item`，但预期是 plain text literal，不应渲染为 Markdown。

### iPhone UI 步骤

1. 打开 Moments，选择一条已同步或可同步的 Moment。
2. 进入 Moment detail，找到 `Private Comments` 区域。
3. 点击 `Add`，创建第一条 private comment。
4. 再创建第二条 private comment，建议使用多行和 Markdown-like literal 文本。
5. 确认两条 comment 只出现在 Moment detail；返回主 timeline，确认没有 comment badge、count、dot、preview 或搜索入口。
6. 删除其中一条 comment。
7. 确认 parent moment 仍可见，剩余 comment 仍在 detail 中可见，被删除 comment 不再可见。
8. 等待 `SyncBadge` / outbox 状态从 pending 或 syncing 清空；如果 Mac 暂不可达，应记录为 blocked 或 pending，而不是把它写成 passed。

### 本机 timeline non-clutter 静态检查

```bash
! rg -n "comment|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift
```

该检查应无命中，用来防止 Private Comments 在主 timeline 行或主 timeline view 中引入 badge/count/preview/search surface。

### 复制 iPhone app Library container

```bash
rm -rf .tmp/device-app-library-check
mkdir -p .tmp/device-app-library-check
xcrun devicectl device copy from \
  --device "wwz 的 iphone" \
  --domain-type appDataContainer \
  --domain-identifier com.popcornnnnnn.privatemoments \
  --source Library \
  --destination .tmp/device-app-library-check \
  --timeout 60
```

如果 install、launch、手动 UI、container copy 或 DB inspection 被阻塞，在 handoff 中记录：阻塞步骤、错误摘要、是否已完成前置检查、以及哪些证据仍未获得。不要补写推断性结论。

### iPhone SQLite aggregate checks

只查询计数和状态，不查询 `text` 字段：

```bash
sqlite3 '.tmp/device-app-library-check/Application Support/PrivateMoments/private-moments.sqlite' <<'SQL'
SELECT COUNT(*) AS local_comments_total FROM local_comments;
SELECT COUNT(*) AS local_comments_visible FROM local_comments WHERE deletedAt IS NULL;
SELECT syncStatus, COUNT(*) AS count FROM local_comments GROUP BY syncStatus ORDER BY syncStatus;
SELECT type, status, COUNT(*) AS count
FROM outbox_operations
WHERE type IN ('create_comment', 'delete_comment')
GROUP BY type, status
ORDER BY type, status;
SQL
```

健康结果取决于本次 UAT 创建和删除的数量，但至少应能看到 `local_comments` 中有对应 aggregate 变化；最终已同步时 comment outbox 不应长期停留在 pending/failed。若仍 pending，应同时记录当前 server reachability 和 Settings > Sync 状态。

### Server SQLite aggregate checks

先确认正在查询的是 active server database；开发环境常见位置取决于 `PRIVATE_MOMENTS_DATA_DIR` / `DATABASE_URL`。只查询 aggregate，不输出 comment body：

```bash
sqlite3 '<active-server-app.sqlite>' <<'SQL'
SELECT COUNT(*) AS comments_total FROM comments;
SELECT COUNT(*) AS comments_visible FROM comments WHERE deleted_at IS NULL;
SELECT type, COUNT(*) AS count
FROM sync_operations
WHERE type IN ('create_comment', 'delete_comment')
GROUP BY type
ORDER BY type;
SELECT rejected_at IS NOT NULL AS rejected, COUNT(*) AS count
FROM sync_operations
WHERE type IN ('create_comment', 'delete_comment')
GROUP BY rejected
ORDER BY rejected;
SQL
```

健康结果应显示 comment create/delete operations 已进入 `sync_operations`，没有意外 rejected rows；`comments_visible` 应反映删除后一条仍可见、被删 comment 不可见。若 active database 没有 `comments` 表，先处理 schema version 4 migration 或 server data-dir mismatch，再重跑 UAT。

## Troubleshooting

### Login Fails With App Transport Security

使用 HTTPS Tailscale Serve，或者使用当前 `ios/PrivateMoments/Info.plist` 里的 `NSAppTransportSecurity` exceptions 覆盖的 IP/host。开发 app 当前允许 arbitrary loads 和 local networking，但干净的 production build 后续应该收紧。

### Duplicate Devices

重复登录应该复用 `deviceKey`。如果历史上已经产生 duplicate rows，可以谨慎使用 Mac Admin 的 device cleanup。不要撤销当前活跃 iPhone token，除非你准备重新登录。

### Sync Shows Empty Timeline After Login

检查 app preferences 里的 `lastSyncCursor`。iOS recovery 会在本地数据库为空或一次性 recovery flag 尚未应用时，把 cursor 重置为 `0`。sync 完成后，`lastSyncCursor` 应该匹配 server 最新的 `server_changes.version`。

### Images Do Not Load

检查 server logs 里的 `media.batch_download`。iOS 现在用 batch thumbnail JSON 做 remote cache recovery。手机数据库中 `missing_visible_media` 应为 `0`。

### Uploads Stay Pending

iOS 会逐个上传 media，并在上传前压缩图片。如果大文件上传失败或 Tailscale 连接中断，item 会留在本地 queue，并由 sync retry 调度器按 backoff 延迟重试。先看 Settings > Storage > Sync Health 里的 pending 或 failed counts，再检查 server logs 里的 `media.upload` 和 sync errors。

### Storage Mac Server Section Is Missing

Settings > Storage 总是显示本机 iPhone usage。只有在 app 已登录且 `/api/v1/admin/status` 成功时，Mac Server section 才会出现。如果 Mac section 被隐藏，检查 server URL、token state 和 Tailscale reachability。

### Build Fails With Signing/Profile Errors

打开 Xcode：

```text
Xcode > Settings > Accounts
Target PrivateMoments > Signing & Capabilities
```

选择 personal team，保持 automatic signing，解锁 iPhone，然后重新运行：

```bash
npm run ios:device
```
