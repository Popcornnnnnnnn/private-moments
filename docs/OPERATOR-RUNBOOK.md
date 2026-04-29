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
