# Private Moments 运维手册

这份 runbook 覆盖 Mac server、Admin UI 和 iOS test app 的本地运行、验证和排障。

## 环境要求

- 安装 Xcode 的 macOS。
- Node.js `>=22`。
- `npm`。
- `xcodegen`，用于重新生成 `ios/PrivateMoments.xcodeproj`。只运行 Mac server 时不是必需项。
- Tailscale，用于真实 iPhone 访问 simulator localhost 之外的 Mac server。
- 已配对的 iPhone 需要解锁，并信任当前 Mac，才能通过命令行安装。
- `restic`，用于 Mac Admin 的 Archive backup/restore 功能。可通过 `brew install restic` 安装。

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
| `AI_SUMMARY_PROVIDER` | `openai` | AI summary provider label。当前实现使用 OpenAI-compatible Chat Completions API。 |
| `AI_SUMMARY_BASE_URL` | `https://api.openai.com/v1` | 外部 AI provider base URL。 |
| `AI_SUMMARY_API_KEY` | unset | 外部 AI API key。只放在 Mac server 环境里，不写入 iOS 或文档。 |
| `AI_SUMMARY_MODEL` | `gpt-4o-mini` | AI summary model。 |
| `AI_TRANSCRIPTION_PROVIDER` | `local` | 语音/视频转写 provider。默认用 Mac 本地 `mlx-whisper`，只把生成后的 transcript 交给 summary API。 |
| `AI_TRANSCRIPTION_MODEL` | `gpt-4o-mini-transcribe` | OpenAI-compatible transcription model。仅在 `AI_TRANSCRIPTION_PROVIDER=openai` 时使用。 |
| `AI_LOCAL_TRANSCRIPTION_PYTHON` | `./.venv/bin/python` | 本地转写 Python 路径，相对 `server/` 运行目录。 |
| `AI_LOCAL_TRANSCRIPTION_SCRIPT` | `./scripts/local-transcribe.py` | 本地转写脚本路径。 |
| `AI_LOCAL_TRANSCRIPTION_MODEL` | `mlx-community/whisper-turbo` | `mlx-whisper` 模型。 |
| `AI_LOCAL_TRANSCRIPTION_TIMEOUT_MS` | `600000` | 本地转写超时。长语音可调大。 |
| `AI_SUMMARY_TIMEOUT_MS` | `60000` | AI summary provider request timeout。 |

## Runtime Truth Check

每次 server schema、API route 或 Admin UI 改完后，不只看 build 成功，还要确认 3210 上的实际进程已经加载当前 build：

```bash
npm run server:prisma:deploy
npm run server:build
launchctl kickstart -k "gui/$(id -u)/${PRIVATE_MOMENTS_LAUNCHD_LABEL:-com.private-moments.server}"
curl -fsS http://127.0.0.1:3210/api/v1/health
```

`/api/v1/health` 的 `schemaVersion` 必须和 `server/src/config/app-config.ts` 中的 `SCHEMA_VERSION` 一致。若 build 通过但 health 仍返回旧 schema，说明 LaunchAgent 或当前 server 进程仍在运行旧代码，先重启服务再继续验证。

## Worktree 开发和数据安全

`main` 工作目录只作为固定版本的集成线。功能开发、测试、构建、打包和真实设备 UAT 默认在独立 worktree 中完成。

创建功能 worktree：

```bash
git worktree list
mkdir -p ../private-moments-worktrees
git worktree add -b codex/<topic> ../private-moments-worktrees/<topic> main
```

在 Codex App 中，一个 thread 固定使用一个 worktree。不要在同一个工作目录中反复切换 `main` 和功能分支。功能完成后，先在功能 worktree 中提交 checkpoint 并完成对应验证，再回到 `main` 工作目录合并。

合并后清理：

```bash
git worktree remove ../private-moments-worktrees/<topic>
git branch -d codex/<topic>
git worktree list
```

### Worktree server 数据隔离

Worktree 隔离的是代码目录，不自动隔离 runtime data。临时功能分支启动 server 时，默认使用独立端口和独立 data directory，不要直接写当前 live archive：

```bash
mkdir -p server/data-worktree
PORT=3310 \
PRIVATE_MOMENTS_DATA_DIR="$PWD/server/data-worktree" \
DATABASE_URL="file:$PWD/server/data-worktree/app.sqlite" \
npm run server:dev
```

如果需要对临时 data directory 初始化 schema，先在同一组环境变量下运行 Prisma deploy 或 `setup:local`。不要删除或重建已有真实 SQLite 文件来解决迁移问题。

只有在准备最终集成验证时，才允许让当前代码指向 live data。这样做前必须确认：

- 当前分支就是准备合入 `main` 的版本。
- 已经有可恢复的 archive backup、export artifact，或其他等价恢复点。
- 没有另一个 3210 server 进程仍在运行旧代码。
- `/api/v1/health` 返回的 schemaVersion 与当前代码一致。

### Worktree iOS 安装数据安全

真实 iPhone 上的 `Moments` 使用固定 bundle id。无论 app 是从 `main` 还是 feature worktree 打包安装，只要 bundle id 不变，iOS 都会继续使用同一个 app container。这是保留用户数据的基础，但也意味着临时分支的代码会直接运行在现有本地数据上。

从 feature worktree 安装到真实 iPhone 前，必须确认：

- 分支基于当前 `main`，不是旧分支或旧 schema 回退。
- 没有改变 bundle id、App Group id、local database 文件位置或 media cache 路径。
- 没有删除 app、清空 app container、重置 SQLite、清空 outbox 或清理 media cache 的调试代码。
- Sync Health 没有显示必须保留的未同步 outbox、local-only draft 或 media upload 队列；如果有，先完成 Sync Now，或复制 app container 后再安装。
- 涉及 SQLite、sync cursor、outbox、media recovery、backup/restore、auth 或真实设备恢复的变更，已经按 milestone/slice planning 准备验证和恢复方案。

如果需要验证高风险 iOS 变更，优先在 simulator 或隔离数据上做第一轮。真实 iPhone 安装前，先创建 Mac archive backup。注意 Mac archive backup 只保护已经同步到 Mac archive 的数据；如果 iPhone 可能还有未同步本地数据，必须用 `xcrun devicectl` copy app container，保留安装前的本地数据库和媒体 cache 证据。

## Archive / Backup / Restore

Archive 功能用于自用灾难恢复，入口在 Mac Admin 的 `Archive` tab。日常备份/恢复不需要直接运行 restic 命令，但 Mac 上必须安装 restic：

```bash
brew install restic
restic version
```

### 备份仓库和 key 文件

在 Admin `Archive > Backup Repository` 中填写 repository path。它可以是普通本机目录，也可以是用户自己明确选择的 iCloud Drive 目录，例如：

```text
/Users/<you>/Library/Mobile Documents/com~apple~CloudDocs/PrivateMomentsBackup
```

保存路径后，项目会在 repository 目录旁边创建或复用：

```text
.private-moments-restic-key
```

这个 key 文件就是 restic repository 的密码来源。用户不需要记一个额外的备份密码，但要理解安全语义：谁同时拿到 repository 内容和 `.private-moments-restic-key`，谁就可以恢复这个 archive。这是面向本人长期使用的恢复工具，不是额外的加密保险箱。

### 初始化和备份

常规流程：

1. 打开 `http://127.0.0.1:3210/admin/` 并登录。
2. 进入 `Archive` tab。
3. 填写 `Repository path`，点 `Save path`。
4. 点 `Initialize` 初始化 restic repository。
5. 点 `Backup now` 立即创建快照。
6. 在 `Snapshots` 和 `Recent Jobs` 区域确认结果。

手动备份会创建一个受控 snapshot source，而不是直接 zip 当前运行中的目录。当前 snapshot 包含：

- `app.sqlite`
- `manifest.json`
- `media/`
- `backup-manifest.json`

运行时依赖和临时文件，例如 `node_modules`、`.venv`、build output、media temp 文件，不作为恢复数据源。

### 每日定时备份

在 `Daily Backup` 中打开 `Enable daily backup` 并设置时间。server 进程每分钟检查一次 schedule；到点时如果没有其他 maintenance job 正在运行，就创建 `backup_create` job。如果当时已有 job 在跑，本次 scheduled backup 会跳过并写安全日志。

### Snapshot check

点 `Check repository` 会运行 restic repository check，并把结果记录为 `backup_check` maintenance job。建议在首次设置、换 repository 位置、或者怀疑 iCloud Drive 同步不完整时运行一次。

### Restore 到新目录

在 `Snapshots` 中选择某个 snapshot 点 `Restore`。restore job 会把 snapshot 恢复到：

```text
<dataDir>/archive/restores/<timestamp>-<snapshot>
```

恢复完成后，job metadata 和 `artifactPath` 会显示恢复出的数据目录。server 会自动做基本验证：

- `app.sqlite` 存在且可读。
- `manifest.json` 存在。
- `media/` 目录存在。
- 未删除 media 的文件引用仍在恢复目录内，且文件存在。

验证通过时，job stage 会进入 `completed`，metadata 里的 `verification.ok` 为 `true`，`missingMediaFiles` 应为 `0`。

### Promote preparation

当前 v0.1 不在运行中直接替换 live SQLite database。原因是 server 的 Prisma 连接已经打开，热替换数据目录风险比收益大。

Promote 的正确流程是：

1. 先完成 restore，并确认 Recent Jobs 里的 restore `artifactPath`。
2. 在 `Promote Restore` 填入 `Restored data directory`。
3. 在 `Confirmation` 中输入：

```text
PROMOTE <restored-folder-name>
```

4. 点 `Prepare promote`。

Promote preparation 会：

- 进入 maintenance mode，暂停普通 sync/media/AI/admin destructive writes。
- 重新验证 restored data directory。
- 为当前数据创建一份 `pre-promote` backup。
- 写入：

```text
<dataDir>/archive/pending-promote.json
```

这个文件包含恢复目录、当前目录、pre-promote backup metadata，以及需要切换的 env：

```text
PRIVATE_MOMENTS_DATA_DIR=<restored-data-dir>
DATABASE_URL=file:<restored-data-dir>/app.sqlite
```

真正切换时，停止 server，按 `pending-promote.json` 更新 `server/.env` 或 launchd 环境，再重新启动 server。不要在 server 仍运行时手动替换当前 `app.sqlite` 或整个 data directory。

### Maintenance jobs

Archive 操作会写入 `maintenance_jobs`，Admin `Recent Jobs` 显示最近 job。可通过 API 排查：

```bash
curl -fsS http://127.0.0.1:3210/api/v1/admin/maintenance/jobs \
  -H "Authorization: Bearer $TOKEN"
```

job metadata 只允许保存路径、状态、计数、错误码等安全信息；不要把 post 正文、comment、transcript、summary 正文或媒体内容写进 job metadata 或日志。

### Export / Import 迁移包

Export/import 是迁移和恢复辅助路径，不替代 restic backup。入口同样在 Mac Admin 的 `Archive` tab。

Export 会生成：

- `manifest.json`：包格式、schema/server 版本、导出范围和计数。
- `archive.json`：权威迁移数据，包含 posts、media metadata、comments、tags、tag aliases、post tag assignments 和 AI summaries。
- `media/`：导出范围内引用到的媒体文件。
- `preview.md`：仅供快速阅读预览，不作为导入依据。
- `private-moments-export-<timestamp>.tar.gz`：可移动的导出包。

在 `Exports` 区域点击 `Create export` 时，如果 `From` / `To` 留空就是全量导出；填写日期则按 occurred date 做半开区间导出。导出完成后，在 `Recent Jobs` 查看 `export_create` job 的 `artifactPath`，它就是 `.tar.gz` 包路径。

Import 只会导入到新的 staged data directory：

```text
<dataDir>/archive/imports/<timestamp>-<label>/data
```

导入不会覆盖当前 archive，也不会恢复旧的 device token、session、sync operations 或 maintenance jobs。导入会保留内容 ID、时间戳、tag/AI generated metadata，并重建新的 `server_changes`，方便后续作为一个干净 archive 被新设备同步。导入完成后，`import_restore` job 的 `artifactPath` 是 staged data directory；如果要切换使用，后续仍走 `Promote Restore` 的强确认流程。

## 本地开发启动

推荐一键初始化：

```bash
npm run setup:local
```

这个脚本会：

- 保留已有的 `server/.env`，只在缺失时从 `server/.env.example` 创建。
- 生成 Prisma client。
- 如果 `DATABASE_URL` 指向 SQLite `file:` 且数据库文件还不存在，先创建一个空 SQLite 文件，再使用 `server:prisma:deploy` 应用已有数据库迁移。
- 构建 Admin UI 和 Server。
- 不自动覆盖真实密码、真实数据或媒体文件。

可选参数：

```bash
npm run setup:local -- --with-ai
npm run setup:local -- --with-ios
```

`--with-ai` 会创建或复用 `server/.venv` 并安装 `mlx-whisper`，用于 Mac 本地转写。`--with-ios` 会要求本机已安装 `xcodegen` 并重新生成 Xcode project。

手动初始化 fallback：

```bash
npm install
cp server/.env.example server/.env
npm run server:prisma:generate
npm run server:prisma:deploy
npm run admin:build
npm run server:build
npm run server:dev
```

如果是全新的 SQLite 文件，当前 Prisma SQLite engine 在某些机器上会要求文件先存在。推荐优先用 `npm run setup:local`，它会自动处理这个步骤。手动 fallback 时，如果 `server/.env` 仍使用默认 `DATABASE_URL="file:./dev.db"`，可在 deploy 前执行：

```bash
sqlite3 server/prisma/dev.db 'PRAGMA user_version=0;'
```

如果 `DATABASE_URL` 是绝对路径，例如 `file:/path/to/app.sqlite`，则在对应路径创建空 SQLite 文件即可；不要对已有真实数据库执行删除或重建。

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

### Share Extension

iOS app 内嵌 `Save to Moments` Share Extension。安装到 iPhone 后，可以在 Photos、Files、Voice Memos、Safari 或其他支持系统 Share Sheet 的 App 中选择 `Save to Moments`。

当前 Share Extension 使用 App Group：

```text
group.com.popcornnnnnn.privatemoments
```

真实设备签名时，主 App bundle id `com.popcornnnnnn.privatemoments` 和 extension bundle id `com.popcornnnnnn.privatemoments.share` 都需要在 Apple Developer 账号中启用同一个 App Group capability。若设备构建或安装时报 provisioning / entitlement 相关错误，先在 Apple Developer Portal 或 Xcode Signing & Capabilities 中确认 App Group 已注册并分配给这两个 identifiers。

验证路径：

1. 安装 App 到 iPhone。
2. 打开 Photos，选择 1-9 张图片，点 Share。
3. 选择 `Save to Moments`，可补一段文字。
4. 完成后主 App 应打开 New Moment composer，图片和文字进入草稿。
5. 发布后走原有本地保存、sync/upload 和后续 AI summary 流程。

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

如果启用了 Tailscale Serve，可以优先使用 HTTPS 入口，避免 iOS App Transport Security 对明文 HTTP 的限制：

```bash
tailscale serve status
curl -fsS --resolve <tailscale-host>:443:<tailscale-ip> https://<tailscale-host>/api/v1/health
```

真实 iPhone 的 Server URL 可以填 `https://<tailscale-host>`；如果继续使用 `http://<tailscale-ip>:3210`，Debug app 的 `NSAppTransportSecurity` 当前通过 `NSAllowsArbitraryLoads` 允许开发期明文 HTTP。

### Private fallback endpoint

公开项目默认只记录 Tailscale/private VPN 路径。个人本机如果还有一个额外 HTTPS endpoint，例如 Cloudflare Tunnel，可以通过 ignored 的 `.env.local` 注入到本机 iOS build 里作为 fallback；不要把个人域名、tunnel id 或 DNS 目标提交到仓库。

```bash
PRIVATE_MOMENTS_FALLBACK_SERVER_URL=https://your-private-fallback.example
```

`npm run ios:device` 和 `npm run ios:simulator` 会读取 `.env.local`，并把 `PRIVATE_MOMENTS_FALLBACK_SERVER_URL` 写入 app bundle 的 `PrivateMomentsFallbackServerURL`。运行时仍以 Settings 中的 Server URL 为 primary；当 primary 出现网络级连接失败时，app 会自动尝试 bundled fallback。HTTP 401/403/404 等认证或服务端错误不会触发 fallback。

如果使用 Cloudflare Tunnel，建议只放行 iOS 同步所需 API，避免把完整 Mac Admin UI 暴露到公网：

```text
/api/v1/health
/api/v1/auth/login
/api/v1/sync
/api/v1/media/*
/api/v1/ai/media-summary
/api/v1/admin/status
```

如果 fallback 域名返回 Cloudflare `530` / `error code: 1033`，通常表示 tunnel connector 没有连上 Cloudflare edge，iOS 端会表现为所有公网 fallback 同步失败。先在 Mac 上确认：

```bash
curl -i https://your-private-fallback.example/api/v1/health
tail -n 80 ~/Library/Logs/cloudflared-blog.err.log
dig +short region1.v2.argotunnel.com A
```

健康状态应看到 `/api/v1/health` 返回 `200`，`cloudflared` 日志出现 `Registered tunnel connection`，`region*.v2.argotunnel.com` 解析为真实 Cloudflare edge IP。如果本机使用 Clash Verge / Mihomo 的 TUN + fake-IP，`region*.v2.argotunnel.com`、`cloudflare.com`、fallback 域名或 `cftunnel.com` 解析到 `198.18.x.x` 会让 tunnel 断开。把 Cloudflare Tunnel 相关域名和个人 fallback 域名加入 `fake-ip-filter` 并设置直连规则后，reload Clash 配置、刷新 DNS cache，再重启 cloudflared LaunchAgent。

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

响应应包含 `counts`，以及 `storage.totalBytes`、`storage.databaseBytes`、`storage.mediaBytes`、`storage.logsBytes`、`storage.availableBytes`、`sync.latestServerChangeVersion`、`aiSummaries` 和 `aiUsage`。`aiSummaries` 只暴露计数、状态、错误码、duration、transcript length、卡住时长和排查提示，不暴露 transcript 或 summary 正文。`aiUsage` 只暴露 token/request/error 聚合，不暴露 prompt、transcript、review input 或 summary/review 正文。

Sync Health 还应包含 server-side `pendingOperations`、`rejectedOperations`、`failedMediaUploads`、`aiNonReady`、`lastServerChangeAt`、`lastSyncOperationAt`、`lastSuccessfulSyncAt` 和 `lastRejectedSyncAt`。iOS Settings > Storage & Diagnostics 会把这些 Mac 侧计数和本机 cursor、outbox、pending upload、failed upload、missing media download 状态合并展示，并提供安全动作：`Sync Now`、`Pull Server Changes`、`Retry Uploads`、`Re-download Missing Media`。

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
sqlite3 '.tmp/device-app-library-check/Application Support/PrivateMoments/private-moments.sqlite' \
  'SELECT COUNT(*) FROM local_comments WHERE deletedAt IS NULL;'
```

如果怀疑 iPhone 没拉到 Mac 上已经生成的 server changes，先在 iPhone 打开 Settings > Storage & Diagnostics 并点右上角 refresh。这个页面会先尝试一次安静 sync pull，然后显示 `This iPhone cursor`、`Mac change version` 和落后数量。也可以复制 container 后手动比较两端 cursor：

```bash
plutil -p .tmp/device-app-library-check/Preferences/com.popcornnnnnn.privatemoments.plist | grep lastSyncCursor
sqlite3 server/prisma/dev.db 'SELECT MAX(version) FROM server_changes;'
```

开发时如果 `DATABASE_URL` 或 `PRIVATE_MOMENTS_DATA_DIR` 指向其他 SQLite 文件，第二条命令要改成对应 server database path。健康状态下，iPhone `lastSyncCursor` 应追上 server `MAX(server_changes.version)` 或 `/api/v1/admin/status.sync.latestServerChangeVersion`；如果明显落后，先在 app 里运行 Settings > Storage & Diagnostics refresh 或 Settings > Sync > Sync Now，再重新复制 container 检查。

Media recovery 常用检查：

```sql
SELECT COUNT(*) AS missing_visible_media
FROM local_media m
JOIN local_posts p ON p.id = m.postId
WHERE m.uploadStatus='uploaded'
  AND (
    (m.kind='image' AND m.remoteCompressedPath IS NOT NULL AND m.localCompressedPath = '')
    OR (m.kind='video' AND m.remoteThumbnailPath IS NOT NULL AND (m.localThumbnailPath IS NULL OR m.localThumbnailPath = ''))
  )
  AND m.deletedAt IS NULL
  AND p.deletedAt IS NULL;
```

Cache recovery 健康状态下，`missing_visible_media` 应为 `0`。语音和视频完整文件默认按播放需求下载，不纳入这个缺失缩略图/poster 检查。

Legacy audio/video transcription metadata 常用检查：

```sql
SELECT id, kind, transcriptionStatus, length(transcriptionText) AS transcript_length, transcriptionError
FROM local_media
WHERE kind IN ('audio', 'video')
ORDER BY updatedAt DESC
LIMIT 10;
```

这些字段只用于旧客户端和历史数据兼容。新 iOS 发布语音/视频时不再运行本机 Speech transcription，不再上传 `transcriptionText`，也不会把 transcript 作为 timeline 或 bottom sheet 的可见回退内容。排查旧数据时不要把完整私人转写正文贴进日志或聊天，只记录长度、状态和 media id。

AI summary 常用检查：

```sql
SELECT id, media_id, status, document_title, one_liner, json_array_length(document_blocks_json) AS block_count,
       provider, model, input_transcript_length, error_code, deleted_at
FROM ai_summaries
ORDER BY updated_at DESC
LIMIT 10;
```

本机 iPhone container 侧：

```sql
SELECT id, mediaId, status, documentTitle, oneLiner, provider, model,
       inputTranscriptLength, errorCode, deletedAt
FROM local_ai_summaries
ORDER BY updatedAt DESC
LIMIT 10;
```

排查时只记录 id、状态、document block 数量、provider/model、错误码和 transcript length。不要复制私人 transcript 正文或 AI summary 正文。

Smart Tags 常用检查：

```sql
SELECT id, type, name, is_default, is_archived, ai_usable_as_primary
FROM tags
ORDER BY type, is_default DESC, name;

SELECT tag_id, COUNT(*) AS active_assignments
FROM post_tags
WHERE deleted_at IS NULL
GROUP BY tag_id
ORDER BY active_assignments DESC;

SELECT source, COUNT(*)
FROM post_tags
WHERE deleted_at IS NULL
GROUP BY source;

SELECT p.id AS post_id, m.id AS media_id, s.status,
       p.ai_tag_processed_at,
       COUNT(pt.id) AS active_tags
FROM posts p
JOIN media m ON m.post_id = p.id
LEFT JOIN ai_summaries s ON s.media_id = m.id AND s.deleted_at IS NULL
LEFT JOIN post_tags pt ON pt.post_id = p.id AND pt.deleted_at IS NULL
WHERE m.kind = 'audio' AND p.deleted_at IS NULL
GROUP BY p.id, m.id, s.status, p.ai_tag_processed_at
ORDER BY p.created_at DESC
LIMIT 10;
```

本机 iPhone container 侧：

```sql
SELECT id, type, name, isDefault, isArchived, aiUsableAsPrimary
FROM local_tags
ORDER BY type, isDefault DESC, name;

SELECT tagId, COUNT(*) AS active_assignments
FROM local_post_tags
WHERE deletedAt IS NULL
GROUP BY tagId
ORDER BY active_assignments DESC;

SELECT COUNT(*) FROM local_tag_aliases WHERE deletedAt IS NULL;
```

默认主标签应至少有 6 条：`日记`、`想法`、`学习整理`、`情绪`、`碎碎念`、`复盘`，并保持 `is_default=1`、`ai_usable_as_primary=1`。AI 自动标签只应出现在新 audio moment 的首次 ready summary 之后；video/image/text 没有 AI 自动标签。短音频/短 transcript 通常只应有 1 个 topic，只有多主题且高置信度时才保留多个。排查时只记录 tag id/name/type/count/source、AI 建议置信度数组、`primarySkippedReason` 和 skipped reason，不复制 post 正文、comment、transcript 或 summary 正文。server 正常日志里的 `ai.tags_processed` 可用于区分 `primary_no_suggestion`、`primary_low_confidence`、`primary_no_matching_tag`、`no_suggestions`、`low_confidence`、`user_edited`、`already_processed`、`force_regenerate`、`non_audio_media` 和已应用标签等路径。Settings > Tags 的 `Edit` 可批量 Archive/Merge Topic，也可批量 Restore/Delete Archived tags。

## Troubleshooting

### Login Fails With App Transport Security

优先检查 Settings 里的 Server URL。如果是 `http://<tailscale-ip>:3210`，ATS 报错通常说明请求在 iOS 侧被拦截，尚未到达 Mac server；此时 server logs 和 `devices.last_seen_at` 通常不会变化。

推荐使用 Tailscale Serve HTTPS：

```bash
tailscale serve status
```

然后把 iOS Server URL 改为输出里的 `https://<tailscale-host>`。当前 Debug app 也通过 `NSAllowsArbitraryLoads` 允许开发期 HTTP fallback；不要同时依赖 `NSAllowsLocalNetworking` 来覆盖 Tailscale `100.x` 地址，因为它不一定被 ATS 判定为 local networking。

### Duplicate Devices

重复登录应该复用 `deviceKey`。如果历史上已经产生 duplicate rows，可以谨慎使用 Mac Admin 的 device cleanup。不要撤销当前活跃 iPhone token，除非你准备重新登录。

### Sync Shows Empty Timeline After Login

检查 app preferences 里的 `lastSyncCursor`。iOS recovery 会在本地数据库为空或一次性 recovery flag 尚未应用时，把 cursor 重置为 `0`。sync 完成后，`lastSyncCursor` 应该匹配 server 最新的 `server_changes.version`。

### Images Do Not Load

检查 server logs 里的 `media.batch_download`。iOS 现在用 batch thumbnail JSON 做 remote cache recovery。手机数据库中 `missing_visible_media` 应为 `0`。

### Uploads Stay Pending

iOS 会逐个上传 media，并在上传前压缩图片。如果大文件上传失败或 Tailscale 连接中断，item 会留在本地 queue，并由 sync retry 调度器按 backoff 延迟重试。上传队列优先处理 `pending`，再处理 `failed`，避免一个旧失败项挡住新语音。iOS 上传 audio/video 时会先写临时 multipart 文件，再用 file upload 交给 `URLSession`，避免把完整音视频 body 常驻内存。

先看 Settings > Storage & Diagnostics > Sync Health 里的 pending 或 failed counts。`Retry Uploads` 会把本机 failed media 重新排为 pending，并立即触发一次同步；`Sync Now` 也会处理当前 pending/failed media。然后检查 server logs 里的分阶段上传日志：

- `media.upload_started`: server 已收到 multipart request，并记录 `mediaId`、`postId`、`kind`、`variant` 和预期 body size。
- `media.upload_received`: server 已完整写入临时文件，并完成 size/checksum 统计。
- `media.upload_completed`: server 已把临时文件原子 rename 到最终 media path，并写入 SQLite media record。
- `media.upload_failed`: 上传中断或超时。常见 `errorCode` 是 `client_premature_close` 或 `upload_timeout`。

Server 会先写入同目录隐藏 `.tmp` 文件，只有完整收完后才原子 rename 成最终 media 文件；失败时只删除 `.tmp`，不把半截文件当成已上传内容。如果日志里反复出现 `client_premature_close`，通常是 iPhone/Tailscale 连接中断或旧 server 进程卡着上传流。可以重启 Mac server，打开 iPhone app，或在 Settings > Storage & Diagnostics 使用 `Retry Uploads` 让本地 queue 重新上传。

### Comments Do Not Appear After Sync

评论通过 `create_comment` / `delete_comment` 走 `/api/v1/sync`，不走 media upload。先检查 Settings > Advanced Sync 的 Outbox operation counts；这里只应该显示 operation type/count，不显示评论正文。再检查 server `sync_operation` 是否有 rejected `create_comment`，常见原因是父 post 不存在或已删除。iOS 应用远端 comment change 时如果缺父 post，会保留原 cursor 并让本轮 sync 失败，避免静默丢评论。

### Audio Or Video Summary Is Missing

新 iOS 客户端不会生成可见转写结果。语音/视频完整文件上传到 Mac 后，server 会在后台先用 Mac 本地 `mlx-whisper` 生成内部 transcript，再把 transcript 交给 summary provider。iOS 只同步 generated AI summary metadata；没有 ready summary 时，主时间线不显示 `Summary` 入口、transcript 回退、处理中状态或失败状态。需要排查进度时，在 iPhone 打开 Settings > Storage & Diagnostics > AI Summaries，看是否停在 `Transcribing`、`Summarizing` 或进入 `Failed`。

首次配置本地转写：

```bash
cd server
python3 -m venv .venv
.venv/bin/pip install mlx-whisper
```

排查顺序：

- 确认 audio/video 的 `variant=compressed` 媒体已经上传成功，server `media.compressed_path` 指向的文件存在。
- 检查 server `ai_summaries` 表；失败时看 `status`、`error_code`、`provider`、`model`、`input_transcript_length`，不要复制 transcript 或 summary 正文。
- 检查 server logs 中的 `ai.summary_started`、`ai.summary_attempt_started`、`ai.summary_stage`、`ai.summary_retry_scheduled`、`ai.summary_ready`、`ai.summary_stage_failed`、`ai.summary_failed` 或 `ai.summary_job_failed`。正常日志只应包含 id、provider/model、阶段、耗时、错误码和长度 metadata。
- 如果 `status` 是 `transcribing` 且长时间不变，优先检查 `.venv/bin/python`、`server/scripts/local-transcribe.py`、`mlx-whisper` 安装和 `AI_LOCAL_TRANSCRIPTION_TIMEOUT_MS`。
- 如果 `error_code` 是 `media_file_missing`，先修复媒体上传/存储路径；如果是 `empty_transcript`、`local_transcription_timeout`、`local_transcription_failed` 或 `local_transcription_invalid_output`，优先检查本地转写环境、模型下载和源文件可读性；如果是 `provider_*`、`invalid_json` 或 `invalid_output`，再检查 summary model/base URL/API key。
- iOS 上传 audio/video 后会安排几次延迟 follow-up sync；如果 server 已有 ready summary 但手机没显示，手动触发一次 sync 并检查 `local_ai_summaries` 是否收到了 `ready` 记录。
- Server 端生成的 `ai_summary_updated` 可能发生在 iPhone 已经没有 pending outbox/media work 之后。如果 server `ai_summaries.status='ready'`、server 最新 `server_changes.version` 高于 iPhone `lastSyncCursor`，但 iPhone 仍显示旧 failed 或没有 `Summary ready`，优先判断为客户端没有拉取 remote-only changes，而不是 summary job 失败。当前 iOS 会在 app 回到前台、Storage & Diagnostics 刷新和手动 Sync Now 时拉取这种 remote-only changes。

### AI Summary Is Missing Or Failed

AI summary 没有单独列表页。timeline 只在 ready summary 存在时显示 `Summary ready`；底部 sheet 只显示 ready AI summary。没有 ready summary、处理中、失败或 provider 未配置时，主时间线保持静默，不显示 transcript、`Needs transcript`、`No speech detected` 或 `Summary failed`。

新 audio moment 还有一个可选的标题写回：Settings > Feature Modules > `AI Title Auto-Insert` 默认打开。若首次 ready summary 有有效 `documentTitle`，且该 audio/post 是开启功能之后新建、当前正文没有行首 `# ` 或 `## ` 标题，iOS 会把 `## <title>` 插入正文顶部，并通过 `insert_ai_title` 同步到 Mac。这个过程只写标题，不写 summary 正文；如果没有出现标题，优先检查该开关、summary 是否 ready、音频是否是旧内容、`document_title` 是否为空/超过 40 字符、正文是否已有标题，以及 outbox 是否存在失败的 `insert_ai_title`。`media-summary-v3` 会要求可识别非空音频有短标题，并在 server 侧从 `one_liner` 做 fallback；如果 `document_title` 仍为空，通常表示该音频被判定为内容为空、无法识别、静音或噪音。

先确认目标 audio/video media 的完整文件已经在 Mac server 上可读。新流程不依赖 `media.transcription_text`；server 会先在 Mac 本地转写媒体文件，并把内部 transcript 继续交给 summary provider。ready 记录通常应该有非空 `input_transcript_length`。

如果是 provider 配置问题，检查 Mac server 的 `AI_SUMMARY_API_KEY`、`AI_SUMMARY_BASE_URL`、`AI_SUMMARY_MODEL` 和本地转写相关 env，修改后重启 server。可以用 `POST /api/v1/ai/media-summary` 对已上传的 audio/video media 重新生成；真机新发布媒体会在上传完成后自动排队生成。

如果是 provider/network 失败，检查 server logs 中的 `ai.summary_failed`，只看 `summaryId`、`mediaId`、`provider`、`model`、`inputTranscriptLength` 和 `errorCode`。正常日志不应包含 transcript 或 summary body。

删除 summary 只会软删除 generated metadata，不会删除 post、media、legacy transcript metadata 或 comments。重新生成会覆盖同一个 media 当前 summary record。

新生成的 `media-summary-v3` ready 记录应有 `document_title` / `one_liner` 或非空 `document_blocks_json`。如果旧 summary 没有这些字段但仍有 `overview` / `key_points_json` / `sections_json`，iOS 会走 legacy 渲染；只有重新生成后才会变成 v3 document blocks。

### Storage Mac Server Section Is Missing

Settings > Storage & Diagnostics 总是显示本机 iPhone usage。只有在 app 已登录且 `/api/v1/admin/status` 成功时，Mac Server section 才会出现。如果 Mac section 被隐藏，检查 server URL、token state 和 Tailscale reachability。

AI Summaries subsection 来自 `/api/v1/admin/status.aiSummaries`，AI Token Usage subsection 来自 `/api/v1/admin/status.aiUsage`，Tags subsection 来自 `/api/v1/admin/status.tags`。如果 Mac Server section 出现但这些 subsection 不出现，先确认已安装包含 Storage & Diagnostics 更新的 iOS build，再用 curl 检查 admin status 响应是否包含对应字段。

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
