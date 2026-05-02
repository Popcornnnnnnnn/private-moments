# Private Moments 运维手册

这份 runbook 覆盖 Mac server、Admin UI 和 iOS test app 的本地运行、验证和排障。

## 环境要求

- 安装 Xcode 的 macOS。
- Node.js `>=22`。
- `npm`。
- `xcodegen`，用于重新生成 `ios/PrivateMoments.xcodeproj`。只运行 Mac server 时不是必需项。
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
| `PRIVATE_MOMENTS_DEVICE_NAME` | unset | `devicectl` 使用的真实 iPhone 名称。真机安装时必须显式设置。 |
| `PRIVATE_MOMENTS_BUNDLE_ID` | `dev.privatemoments.app` | iOS app bundle id override。 |
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

## 本地开发启动

推荐一键初始化：

```bash
npm run setup:local
```

这个脚本会：

- 保留已有的 `server/.env`，只在缺失时从 `server/.env.example` 创建。
- 生成 Prisma client。
- 使用 `server:prisma:deploy` 应用已有数据库迁移。
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
PRIVATE_MOMENTS_DEVICE_NAME="Your iPhone" npm run ios:device
```

真实设备脚本会：

1. 检查候选 server URLs。
2. 如果可用，用 `xcodegen` 重新生成 Xcode project。
3. 构建 Debug iPhoneOS app。
4. 使用 `xcrun devicectl` 安装。
5. 启动 `dev.privatemoments.app`。

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

响应应包含 `counts`，以及 `storage.totalBytes`、`storage.databaseBytes`、`storage.mediaBytes`、`storage.logsBytes`、`storage.availableBytes`、`sync.latestServerChangeVersion` 和 `aiSummaries`。`aiSummaries` 只暴露计数、状态、错误码、duration、transcript length、卡住时长和排查提示，不暴露 transcript 或 summary 正文。

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

## Backup / Restore / Export

完整本地备份：

```bash
npm run backup:local
```

默认输出到 `backups/private-moments-backup-<timestamp>.tgz`。备份包含本地 runtime data，例如 SQLite 数据库和媒体目录；不包含 `server/.env`。

恢复备份：

```bash
npm run restore:local -- backups/private-moments-backup-YYYYMMDDTHHMMSSZ.tgz --yes
```

恢复前，脚本会把现有 `server/data` 或旧 `server/prisma/dev.db` 移到带时间戳的旁路目录/文件，再解压备份。恢复后运行：

```bash
npm run server:prisma:deploy
npm run server:dev
```

导出可读 JSON metadata：

```bash
npm run export:local
```

`export:local` 会导出 `posts.json`、`comments.json`、`media.json` 和 `ai_summaries.json`，用于人工检查或迁移规划。它不包含媒体文件；完整恢复请用 `backup:local`。

## 真实 iPhone 数据验证

复制 app 的 Library container：

```bash
rm -rf .tmp/device-app-library-check
mkdir -p .tmp/device-app-library-check
xcrun devicectl device copy from \
  --device "Your iPhone" \
  --domain-type appDataContainer \
  --domain-identifier dev.privatemoments.app \
  --source Library \
  --destination .tmp/device-app-library-check \
  --timeout 60
```

检查 sync state：

```bash
plutil -p .tmp/device-app-library-check/Preferences/dev.privatemoments.app.plist
sqlite3 '.tmp/device-app-library-check/Application Support/PrivateMoments/private-moments.sqlite' \
  'SELECT COUNT(*) FROM local_posts WHERE deletedAt IS NULL;'
sqlite3 '.tmp/device-app-library-check/Application Support/PrivateMoments/private-moments.sqlite' \
  'SELECT COUNT(*) FROM local_comments WHERE deletedAt IS NULL;'
```

如果怀疑 iPhone 没拉到 Mac 上已经生成的 server changes，先在 iPhone 打开 Settings > Storage & Diagnostics 并点右上角 refresh。这个页面会先尝试一次安静 sync pull，然后显示 `This iPhone cursor`、`Mac change version` 和落后数量。也可以复制 container 后手动比较两端 cursor：

```bash
plutil -p .tmp/device-app-library-check/Preferences/dev.privatemoments.app.plist | grep lastSyncCursor
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

## Troubleshooting

### Login Fails With App Transport Security

使用 HTTPS Tailscale Serve，或者在本地开发 build 中依赖 `NSAllowsArbitraryLoads` 和 `NSAllowsLocalNetworking`。公开版不内置个人 Tailscale exception；干净的 production build 后续应该收紧 ATS 配置。

### Duplicate Devices

重复登录应该复用 `deviceKey`。如果历史上已经产生 duplicate rows，可以谨慎使用 Mac Admin 的 device cleanup。不要撤销当前活跃 iPhone token，除非你准备重新登录。

### Sync Shows Empty Timeline After Login

检查 app preferences 里的 `lastSyncCursor`。iOS recovery 会在本地数据库为空或一次性 recovery flag 尚未应用时，把 cursor 重置为 `0`。sync 完成后，`lastSyncCursor` 应该匹配 server 最新的 `server_changes.version`。

### Images Do Not Load

检查 server logs 里的 `media.batch_download`。iOS 现在用 batch thumbnail JSON 做 remote cache recovery。手机数据库中 `missing_visible_media` 应为 `0`。

### Uploads Stay Pending

iOS 会逐个上传 media，并在上传前压缩图片。如果大文件上传失败或 Tailscale 连接中断，item 会留在本地 queue，并由 sync retry 调度器按 backoff 延迟重试。先看 Settings > Storage & Diagnostics > Sync Health 里的 pending 或 failed counts，再检查 server logs 里的 `media.upload` 和 sync errors。

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

先确认目标 audio/video media 的完整文件已经在 Mac server 上可读。新流程不依赖 `media.transcription_text`；server 会先在 Mac 本地转写媒体文件，并把内部 transcript 继续交给 summary provider。ready 记录通常应该有非空 `input_transcript_length`。

如果是 provider 配置问题，检查 Mac server 的 `AI_SUMMARY_API_KEY`、`AI_SUMMARY_BASE_URL`、`AI_SUMMARY_MODEL` 和本地转写相关 env，修改后重启 server。可以用 `POST /api/v1/ai/media-summary` 对已上传的 audio/video media 重新生成；真机新发布媒体会在上传完成后自动排队生成。

如果是 provider/network 失败，检查 server logs 中的 `ai.summary_failed`，只看 `summaryId`、`mediaId`、`provider`、`model`、`inputTranscriptLength` 和 `errorCode`。正常日志不应包含 transcript 或 summary body。

删除 summary 只会软删除 generated metadata，不会删除 post、media、legacy transcript metadata 或 comments。重新生成会覆盖同一个 media 当前 summary record。

新生成的 `media-summary-v2` ready 记录应有 `document_title` / `one_liner` 或非空 `document_blocks_json`。如果旧 summary 没有这些字段但仍有 `overview` / `key_points_json` / `sections_json`，iOS 会走 legacy 渲染；只有重新生成后才会变成 v2 document blocks。

### Storage Mac Server Section Is Missing

Settings > Storage & Diagnostics 总是显示本机 iPhone usage。只有在 app 已登录且 `/api/v1/admin/status` 成功时，Mac Server section 才会出现。如果 Mac section 被隐藏，检查 server URL、token state 和 Tailscale reachability。

AI Summaries subsection 也来自 `/api/v1/admin/status.aiSummaries`。如果 Mac Server section 出现但 AI Summaries 不出现，先确认已安装包含 Storage & Diagnostics 更新的 iOS build，再用 curl 检查 admin status 响应是否包含 `aiSummaries`。

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
