# Private Moments 交接说明

Last reconciled: 2026-05-06

## 当前工作状态

- Mac server 已可构建和运行，覆盖 Fastify、Prisma、SQLite、file storage、auth、sync、media upload、media download、admin routes 和静态 Admin UI 托管。
- iOS app 名为 `Moments`，可通过 `npm run ios:device` 安装到已配对 iPhone。
- Admin UI 可通过 `npm run admin:build` 构建，并由 server 在 `/admin/` 提供访问。
- 项目工作流已写入 `docs/WORKFLOW.md`，agent 强制规则写入 `AGENTS.md`。
- `.gsd/` 是结构化事实源，记录当前项目事实、requirements、decisions 和 milestone state；`docs/` 是给人阅读的稳定文档层。
- 2026-05-02 开始 v0.1 收口和开源前清理评估：新增 `npm run setup:local`，默认不覆盖现有 `server/.env`，可选 `--with-ai` 和 `--with-ios`；新增 `docs/RELEASE-CHECKLIST.md`、`docs/OPEN-SOURCE-READINESS.md` 和 `SECURITY.md`；移除 iOS `Info.plist` 中的个人 Tailscale exception。当前结论是适合内部 RC 收口，但不建议立即公开发布。
- 2026-05-05 市场调研后，v0.1 方向调整为优先服务作者本人长期稳定自用，而不是马上做公开宣传或 App Store/TestFlight。新增 M009 `v0.1 Archive, Restore, And Sync Health`：Phase A 做 Mac Admin 管理的 restic backup/restore、每日定时备份、恢复到新目录、验证后强确认 promote preparation、durable maintenance jobs、maintenance mode，以及 Mac Admin + iOS Settings 的 Sync Health；Phase B 做迁移优先的 export/import，JSON manifest 是权威，Markdown 只是预览。
- 2026-05-05 M009 Phase A 代码主路径已落地：schema version 10 新增 `maintenance_jobs`，server 有 durable serial job runner、stale running job cleanup、maintenance mode guards；Admin 新增 `Archive` tab，可配置 restic repository、自动生成 `.private-moments-restic-key`、初始化 repository、手动备份、每日定时备份、snapshot list/check、staged restore 和 promote preparation；`/api/v1/admin/status.sync` 扩展了 Sync Health 计数和 timestamps；iOS Settings > Storage & Diagnostics 显示本机和 Mac 侧 Sync Health，并提供 `Sync Now`、`Pull Server Changes`、`Re-download Missing Media` 三个安全动作。
- 2026-05-05 下午断网后语音卡在 `partial` 的根因已定位并修复到 iOS 上传链路：文字 outbox 后来已同步到 Mac，但多条 audio media 仍停在本机 `pending/failed`，server 日志显示 `/api/v1/media/upload` 中途 `ERR_STREAM_PREMATURE_CLOSE`。修复后 iOS 上传 audio/video 不再把完整 multipart body 常驻内存，而是写临时 multipart 文件后用 file upload；本地上传队列优先处理 `pending` 再处理 `failed`，避免旧失败项挡住新语音；Settings > Storage & Diagnostics 新增 `Retry Uploads`，可把 failed media 重新排为 pending 并立即同步。Mac server 的 AI media summary job 也改为全局串行执行，避免断网恢复后多条音频补传同时启动多个本地 `mlx-whisper` 进程。
- 2026-05-06 修复 Settings > Sync 中 `Automatic Sync` 关闭后的状态反馈：按钮状态现在以 local-only/offline 优先于仍在收尾的 `isSyncing`，所以关闭开关后不再继续显示旋转 syncing 图标；关闭时也会清掉已排队的 follow-up sync 标记，避免旧触发在当前 sync pass 后追加一轮自动同步。
- 2026-05-05 为 iPhone 使用其他 VPN 时无法同时连接 Tailscale 的场景，已支持本机私有 HTTPS fallback endpoint：公开代码默认不内置个人域名，`npm run ios:device` / `npm run ios:simulator` 会从 ignored 的 `.env.local` 读取 `PRIVATE_MOMENTS_FALLBACK_SERVER_URL` 并写入 app bundle。运行时 Settings 中的 Server URL 仍是 primary；当 primary 出现网络级连接失败时，app 会自动尝试 bundled fallback。个人 Cloudflare Tunnel 配置不应提交到仓库；tunnel ingress 应只放行 iOS 同步所需 API，避免暴露完整 Admin UI。
- 2026-05-06 公网 fallback 同步事故定位到 Mac 侧 Cloudflare Tunnel 断连：iPhone 当天有 pending outbox/media，但 Tailscale 设备离线，fallback 域名返回 Cloudflare `530` / `1033`。本机 Clash Verge / Mihomo TUN fake-IP 曾让 `region*.v2.argotunnel.com`、`cloudflare.com`、`cftunnel.com` 和个人 fallback 域名进入错误路径；把这些域名设为 `DIRECT` 后又出现 Cloudflare edge `TLS handshake EOF`、QUIC timeout 和 connector 假活。有效修复是：Cloudflare Tunnel 相关域名和个人 fallback 域名保留在 `fake-ip-filter`，但路由到当前可用代理组，不走 `DIRECT`；cloudflared 固定 `protocol: http2` 并通过 LaunchAgent 重启。验证时 Cloudflare 控制面可见 active connector，公网 `/api/v1/health` 连续恢复 `200`，`/admin/` 仍按 tunnel ingress 返回 `404`。
- 2026-05-05 Promote 当前是 restart-safe preparation，不是 live DB hot swap：它验证 restored data directory，进入 maintenance mode，创建 `pre-promote` backup，然后写 `<dataDir>/archive/pending-promote.json`，里面包含要切换的 `PRIVATE_MOMENTS_DATA_DIR` 和 `DATABASE_URL`。真正切换需要停止 server、更新 env、再重启，避免 Prisma 持有 SQLite 连接时热替换数据库。
- 2026-05-05 M009 Phase B 代码主路径已落地：Admin `Archive` tab 增加 `Exports` 区域；server 新增 `export_create` / `import_restore` maintenance jobs；导出包包含 `manifest.json`、权威 `archive.json`、`preview.md`、`media/` 和 `.tar.gz` artifact；导入会在 `<dataDir>/archive/imports/<timestamp>-<label>/data` 新建 staged data directory，跑 Prisma migrations，导入 posts/media/comments/tags/aliases/post-tags/AI summaries，排除 user/device/sync operation/maintenance job runtime state，重建 server changes 并验证 missing media。
- 2026-05-03 开始入口优化：新增 `Save to Moments` iOS Share Extension、App Group import queue 和 `moments://import/<id>` 唤起路径。Extension 只接收 Share Sheet 内容并写入 App Group；主 App 打开现有 Composer 后消费 import，复用当前图片/视频/音频 preparation、draft、SQLite/outbox 和 sync pipeline。
- 2026-05-03 修复并硬化 Mac server media upload 故障路径：排查到旧 server 进程保留了多条未完成 media write fd，最新图片对应 post 已创建但 media upload 因 `ERR_STREAM_PREMATURE_CLOSE` 失败。已重启 LaunchAgent 清掉卡住连接，并把 `/api/v1/media/upload` 改成 temp-file 写入、完整接收后原子 rename、失败只删除 `.tmp`，同时新增 `media.upload_started` / `media.upload_received` / `media.upload_completed` / `media.upload_failed` 分阶段日志和 `client_premature_close` / `upload_timeout` 错误码。
- 2026-05-03 M006 Smart Tags 主实现已落地到 schema version 9：server/iOS 增加 `tags`、`tag_aliases`、`post_tags` / `local_*` 表，seed 默认主标签；iOS Composer 可选主标签，Timeline/Day Review/Detail 的标签显示跟随 `Show Tags in Timeline`，关闭后 Detail 不提供单条标签编辑；Settings > Tags 可管理词表、alias、archive/restore、topic merge 和主标签颜色；Timeline search/filter 支持标签和 alias；audio 首次 ready AI summary 可应用建议标签。
- 2026-05-03 M007 iOS localization 主路径已落地：Settings 增加本机 App Language（`System` / `English` / `简体中文`）和 AI Language（`Auto` / `Chinese` / `English`）；iOS 主 App 主要可见 UI、日期标签、搜索筛选、评论、Tags、Summary、Detail/Edit 跟随 App Language；默认主标签在中英文之间做显示层映射并支持双语搜索；AI Language 会传给 Mac summary pipeline，但不改变 App UI 语言。
- 2026-05-03 M007 自动化验证通过：`git diff --check`、本地化 key 覆盖检查（270/270）、`server:typecheck`、`server:build`、localhost health、generic iOS Debug build、iPhone 17 simulator tests 21/21 全部通过。重连 `wwz 的 iphone` 后，`npm run ios:device` 已 build/sign/install 成功；脚本启动阶段一度拿不到 pid，随后手动 `xcrun devicectl device process launch --device "wwz 的 iphone" --terminate-existing com.popcornnnnnn.privatemoments --timeout 30` 启动成功。
- 2026-05-04 New Moment composer 支持粘贴真实剪贴板图片：图片不会进入正文或 Markdown，而是追加到下方现有图片 media grid，继续遵守最多 9 张和单一媒体类型规则；普通文字粘贴保持原状，Edit Moment 暂不启用图片粘贴。验证已覆盖 generic iOS Debug build 和 iPhone 17 simulator tests 27/27。
- 2026-04-30 已实现 M003 Feed Comments 的首版代码路径：主时间线评论 UI、iOS local comments、server comments table、`create_comment` / `delete_comment` sync，以及 shared contract 文档。当前验证已覆盖 server build/migration、sync smoke、iOS tests、generic iOS build、Admin build、真机构建、真机安装和真机启动；用户已确认评论发送后的滚动反馈与长按删除反馈。
- 2026-04-30 已实现 M004 Audio and Video Moments 的首版主路径：iOS composer 支持相册视频导入、2 分钟限制、720p MP4 压缩和 poster；支持 AAC/M4A 语音录制、后台继续录制、暂停/继续/停止、发布前试听；timeline/detail 支持视频 poster 全屏播放和语音播放条；server/media/sync/SQLite 支持 `image`、`video`、`audio` typed media；Settings > Storage & Diagnostics 可清理可重新下载的完整语音/视频缓存；Admin 展示媒体类型、MIME、时长和 poster 诊断。
- 2026-04-30 已实现语音/视频本机转写首版；2026-05-01 已被新的 server-side AI summary 流程 supersede。iOS 不再链接 Speech framework、不再请求 speech recognition 权限、不再本地转写，也不再上传 `transcriptionText`。历史 `media.transcription_text` / `update_media_transcription` schema 和 sync 能力保留为兼容旧数据，但不是新发布路径。
- 2026-04-30 已实现 M005 AI Media Summaries 首版；2026-05-01 跟进后变为 server-side media summary：iOS 上传 audio/video 后，Mac server 在后台先用本地 `mlx-whisper` 转写，再把 transcript 发给外部 summary API，只保存 generated summary metadata、transcript hash/长度和错误码，不把 transcript 正文回传给 iOS。主时间线默认只有 ready summary 时显示 `Summary ready`；没有 ready summary 时不显示 Summary 占位。用户手动重新生成已有摘要时，入口可临时显示 `Regenerating`，失败后显示低调 `Summary failed`。Settings > Storage & Diagnostics 显示轻量 AI summary 诊断，底部 sheet 展示 AI summary，可复制、重新生成、删除，并在失败时显示原因和重试入口。新生成 summary 使用 `media-summary-v3` 的 `documentTitle`、`oneLiner` 和 `documentBlocks`，iOS 以 native Markdown-like 文档样式渲染；v3 对可识别的非空语音要求短标题，并在 provider 返回空/过长标题时由 server 从 `oneLiner` 做安全 fallback。2026-05-03 follow-up 允许新 audio 的首次 ready `documentTitle` 在无用户标题时写入 `post.text` 顶部 `##` 标题；正文摘要不写回，视频不写回。
- 2026-04-29 的真实 iPhone 验证结果：
  - `local_posts`: 8
  - visible local posts: 5
  - downloaded media cache entries: 9
  - missing visible media: 0

## 已实现的产品能力

- Local-first iOS timeline。
- 支持 text-only、image-only、text + image、audio-only、text + audio、video-only、text + video moments；空 moment 会被拒绝。
- 支持 photo library、camera import，以及在 New Moment 正文输入区粘贴真实图片后自动进入下方图片 media grid。
- 支持系统 Share Sheet 的 `Save to Moments` 入口：图片、视频、音频文件、URL 和文本先进入 App Group import queue，再由主 App Composer 接管发布。
- 支持从相册导入 2 分钟以内视频，并在发布前压缩和生成 poster。
- 支持在 composer 内录制最长 60 分钟语音，录制文件落盘为 M4A。
- 支持时间线视频滑入主要可视区域后静音自动播放，点击仍进入全屏播放。
- 支持全局 waveform voice bar 语音播放条，去掉重复 `Audio` 标题和整块灰色卡片；可点击播放/暂停、拖动 seek、右侧调倍速；语音播放完成后自动回到未播放状态，中途暂停仍保留续播进度。
- 支持语音/视频 server-side AI summary：发布后 Mac server 后台本地转写媒体文件，再调用外部 summary API 生成摘要，iOS 通过后续 sync 拿到 ready summary；新摘要在 sheet 内以标题、一句话总结、折叠详情、列表和 `AI suggested` callout 渲染。
- Timeline 默认只在有 ready AI summary 时显示 `Summary ready`；没有结果时不显示 transcript、Summary 占位或生成入口。手动重新生成已有摘要期间会显示轻量 `Regenerating`，失败后显示 `Summary failed` 并可点进 sheet 查看原因和重试。
- 支持手动设置 occurred date/time。
- 支持本地 composer drafts。
- Composer 和 Edit Moment 支持轻量 Markdown 富文本编辑：键盘 accessory 只保留 H1/H2，标题 marker 仅当前行露出；普通列表继续走 plain-text list continuation，不做 Markdown bullet 渲染；底层仍保存 Markdown source `String`。
- Moment Detail 对非空正文提供低干扰复制动作，复制 Markdown source。
- 支持 offline outbox sync。
- 支持 Settings 中的 `Automatic Sync` 本机开关。开启时维持启动/前台/发布/编辑/失败重试/AI follow-up 的自动同步；关闭时进入严格 local-only 模式，不自动连接 Mac、不自动上传媒体、不自动拉取 AI summary/tag/media 变更，直到用户显式点击 `Sync Now` 或重新打开自动同步。
- `pending`、`partial`、`failed`、`synced` 的 moment 都允许继续编辑。编辑以 iPhone 本地最新状态为准，后续通过 outbox 和 media upload queue 同步到 Mac。
- 失败的 pending sync work 在 `Automatic Sync` 开启时会自动延迟重试；关闭时只保留本地队列，不安排后台重试。
- Share Extension 继续作为截图、图片、音频、视频、网页 URL、微信文章 URL 或文本的统一入口。URL 类内容由主 App Composer 发布为普通 moment 正文，回看时从 URL 派生可点击 link-card；是否直接打开微信取决于微信/iOS 对原链接的处理。
- Post detail view。
- Full-screen image gallery，带接近原生体验的 pan 和 zoom。
- 支持编辑 text、occurred time、images 和 image ordering。
- 支持 favorite / unfavorite moments。
- 支持主时间线单用户私密 comments：右侧写评论入口、底部输入栏、发送后回到该 moment 底部让最新评论可见、最新两条预览、原位展开/收起、带按压/触觉反馈的长按删除确认、评论文本搜索。
- 支持 iPhone 本地 Timeline search 和 filters。搜索覆盖 post text、comments、已同步 AI summary generated metadata 和历史 transcript metadata，并做轻量宽松匹配；筛选可组合内容类型、收藏、评论、待同步、标签，以及有搜索词时的命中来源。
- 支持 Calendar Review：底部 Calendar tab 显示本地派生的月份网格、低饱和发布密度、最多两个媒体提示图标、媒体类型/收藏筛选；点击日期进入 Day Review，当天内容以日内时间轴展示，右上角 `Timeline` 可切回 Timeline 的可清除 day filter。Day Review 内点击某一条直接打开该 moment detail，返回仍在当天 Day Review，并记住该日期上次浏览到的位置；按 `Show Tags in Timeline` 显示主标签、全部统一小图缩略图、行内音频和视频类型/时长提示。
- 支持 Smart Tags：所有 moment 可手动添加主标签/主题标签；Timeline、Day Review 和 Moment Detail 的标签显示跟随 `Show Tags in Timeline`，关闭后 Detail 不再提供单条标签编辑入口；搜索可命中标签和 alias；Filter 可按主标签/主题标签组合筛选；Settings > Tags 管理 usage count、alias、archive/restore、batch Topic/Archived cleanup、archived tag 永久删除、topic merge、主标签颜色和批量 primary 改色；新 audio moment 可在首次 ready AI summary 后获得保守数量的 AI 建议标签。
- Timeline date 跟随 App Language 使用 human-friendly labels，滚动时显示临时 floating month indicator。
- 支持本机 App Language：`System`、`English`、`简体中文`；已有私人安装默认保持 English，新安装默认 System。App Language 不翻译用户内容、自定义标签或 AI summary 正文。
- 支持独立 AI Language：`Auto`、`Chinese`、`English`；该偏好用于后续 AI summary/title 生成，不同步到 Mac server。
- Timeline soft delete 使用居中的确认 alert。
- Settings 包含简化后的 connection、sync、advanced sync 和 storage diagnostics 页面；AI summary 进度和错误码放在 Storage & Diagnostics，不放进 Timeline。
- Mac Admin 包含 Overview 和 Posts management。
- Mac Admin `Archive` tab 支持 restic backup/restore/promote preparation、Sync Health job，以及 migration-first export/import package。
- Calendar `Reviews` 入口支持 AI Weekly Review：手动生成 rolling 7 days、默认关闭的周日晚上自动生成、结构化回顾阅读页、低权重 moment anchors、反馈、以及显式 publish-as-moment。
- 使用 `deviceKey` 绑定设备，避免同一物理设备重复注册。

## 2026-04-29 的重要修复

- iOS 现在能解析带 fractional seconds 的 server ISO8601 timestamp，例如 `2026-04-29T06:40:42.000Z`，避免 server changes 被跳过。
- iOS 加入一次性 cursor recovery：`didApplySyncRecoveryV1`。当 local post table 为空时，会把 cursor 重置为 `0`。
- Server 提供 `POST /api/v1/media/batch-download`。
- iOS 使用 batch thumbnail JSON 做 remote media cache recovery，因为真实 iPhone + Tailscale 场景下重复 binary media downloads 测试不稳定。
- iOS 在保存和上传 display copies 前压缩图片；upload-time compression 也覆盖旧 pending images。当前策略是 max edge `1600px`，JPEG quality `0.72`。
- 失败的 pending sync 或 media upload 会按 backoff 自动重试：5s、20s、60s、120s，然后 300s。iOS 上传队列优先处理 `pending` media，再重试 `failed` media；Settings > Storage & Diagnostics 的 `Retry Uploads` 可显式重新排队 failed media。
- iOS Settings 增加只读 Storage 页面，展示本机 storage、sync health，以及 `/api/v1/admin/status` 可达时的 Mac server storage。
- Server `/api/v1/admin/status` 返回 data directory、SQLite files、media files、logs 和 available disk 的 storage diagnostics。
- Server 用 `sips` 按需生成 800px thumbnail variants，并重新生成过大的旧 thumbnail files。
- Timeline delete confirmation 改为居中 alert，不再使用位置相关的 `confirmationDialog`；trailing swipe delete 关闭 full-swipe，并在短暂延迟后显示确认框，避免 row/list jump。
- Timeline dates 通过 `MomentDateFormatter` 使用英文 human-friendly labels；month context 改成滚动时短暂出现的 floating scroll hint，而不是常驻 section header。
- iOS 主实现已拆分：
  - `TimelineStore.swift` 拆为 session、mutation、sync、server-change、media 和 payload files。
  - `TimelineStore.swift` retry behavior 拆到 `TimelineStore+SyncRetry.swift`。
  - `LocalDatabase.swift` 拆为 schema、records、timeline、sync、storage stats 和 SQLite helper files。
  - `TimelineView.swift` 拆为 timeline、row/image、date formatting、gallery 和 zoomable image components。
- Storage diagnostics 拆到 `StorageStats.swift`、`StorageSettingsView.swift` 和 `server/src/storage/stats.ts`。

## 2026-04-30 的重要变更

- M003 supersedes 旧 M002 detail-only comments 方向；comments 聚集在主时间线，不在详情页管理。
- Server schema version 提升到 4，新增 `comments` table，并把 comment create/delete 建模为独立 local-first entity。
- Sync 新增 `create_comment`、`delete_comment`、`comment_created`、`comment_deleted`；父 post 缺失或已删除时拒绝 comment create。
- 删除 post 时会隐藏/软删除其 comments，但只广播 `post_deleted`，不为父删除额外广播逐条 comment deletes。
- iOS 新增 `local_comments`、comment outbox payload、本地 create/delete、server change 应用和 comment-aware search。
- Settings > Advanced Sync 只显示 outbox operation type/count，不显示评论正文。
- Server schema version 提升到 5，`media` 增加 `mime_type` 和 `duration_seconds`，`/api/v1/media/upload` 接受 `kind=image|video|audio` 与 `thumbnail` poster 变体。
- Server schema version 提升到 6，`media` 增加 `transcription_text`，sync 新增 `update_media_transcription` 和 `media_transcription_updated`，并把 media upload 的 `transcriptionText` 作为可选 metadata 保存。
- Server schema version 提升到 7，新增 `ai_summaries`；新增 `/api/v1/ai/media-summary` 和 `DELETE /api/v1/ai/media-summary/:summaryId`；sync server changes 新增 `ai_summary_updated` 和 `ai_summary_deleted`。
- iOS `local_media` 增加 `kind`、本地/远端 thumbnail path、`mimeType` 和 `durationSeconds`，旧图片默认迁移为 `image`。
- 修复 composer 图片草稿清理会误删已处理视频/语音草稿文件的问题；`ComposerDraftStore.saveImages([])` 现在只管理 `.image` 草稿文件，避免发布视频时报本地 `.mp4` 不存在。
- 修复最新 sync failures 的两个根因：
  - `/api/v1/media/upload` multipart `fields`/`parts` 限制过低，M004 新增的 `kind`、`mimeType`、duration、width/height 等字段会触发 `reach fields limit`，导致音频/视频/新图片上传返回 500；server 现在放宽到足够承载 typed media metadata。
  - 旧 server 曾把 `create_comment` / `delete_comment` 记录为 `Unsupported operation type`，这些失败会被 sync idempotency 永久重放；server 现在会在当前版本已支持该 operation/entity pair 时重新应用这类历史 rejection。
- 修复视频 poster thumbnail 上传污染主媒体 metadata 的问题：`thumbnail` 变体不再覆盖 video/audio/image 主记录的 MIME、duration、width 和 height。
- 音频播放完成时会清除该 media 的本地播放进度并复位播放条；时间线视频新增单例静音自动播放，只播放当前最靠近视口中心的视频，打开详情/全屏/发布页或开始语音播放时停止。
- iOS 本机语音/视频转写已停用；发布和媒体上传不再依赖 Speech framework。AI summary 失败不会标记 media/post sync 失败，也不会阻塞正常浏览。
- iOS 新增历史评论 no-op 清理：对已删除本地评论产生的 `Parent post not found` / `Comment not found` comment rejection，会把本地 outbox 和 comment 状态结清为 `synced`，避免旧的已删除评论一直显示 sync failed。
- 视频完整文件按播放下载，poster 通过 batch thumbnail recovery 自动回填；语音完整文件按播放下载并缓存。
- Settings > Storage & Diagnostics 的清理动作只删除已上传、可重新下载的完整 audio/video cache，不删除本地待上传文件、视频 poster 或 Mac 归档内容。
- AI summary provider 配置只在 Mac server `.env`：`AI_SUMMARY_PROVIDER`、`AI_SUMMARY_BASE_URL`、`AI_SUMMARY_API_KEY`、`AI_SUMMARY_MODEL`、`AI_TRANSCRIPTION_PROVIDER`、`AI_LOCAL_TRANSCRIPTION_*`、`AI_TRANSCRIPTION_MODEL` 和 `AI_SUMMARY_TIMEOUT_MS`。默认 `AI_TRANSCRIPTION_PROVIDER=local`，通过 `server/.venv` 中的 `mlx-whisper` 在 Mac 本地转写。正常日志只记录 summary/media/post id、provider/model、错误码和 transcript length，不记录 transcript 或 summary 正文。
- 本地 `server/.env` 已配置用户提供的 OpenAI-compatible provider：base URL 指向 localhost provider，model 为 `gpt-5.5`。`server/.env` 已确认被 git ignore，tracked files 中没有 API key。
- 2026-05-01 排查语音 summary 缺失时发现两点：当时 3210 上运行的是旧 server build，上传时没有触发新 job；当前 localhost OpenAI-compatible provider 对 `/audio/transcriptions` 返回 404。server 已补充 transcription 404/405 到 Chat Completions audio input 的 fallback，会把媒体临时转为 WAV 后直接生成结构化 summary；该路径不保存 transcript，因此 `inputTranscriptLength` 可为 `NULL`。随后发现该 provider 虽返回 200/JSON，但实际没有听到音频，生成了“无法访问音频”类内容；server 现在将这种结果判为 `audio_input_unusable` failed，而不是 ready。已把 6 条坏 ready summary 标记为 failed 并发出同步变更。
- 2026-05-01 后续采用 `1+1` 方案：Mac 本地 `mlx-whisper` 转写 + 外部 Chat Completions summary。已创建 ignored `server/.venv` 并安装 `mlx-whisper`，新增 `server/scripts/local-transcribe.py`，AI summary 状态拆成 `transcribing` 和 `summarizing`。一条 14.72s 已上传语音端到端 smoke test 成功：本地 transcript length 58，summary 状态 `ready`。随后用新流程重生成 6 条旧 `audio_input_unusable` failed summary，全部变为 `ready`；当前 `ai_summaries` 是 `ready=10, failed=0`，server change version 194。
- 2026-05-01 排查 Settings > Storage & Diagnostics 没有 AI Summaries、iPhone 上新语音 summary 不可见时，Mac server 侧确认 `/api/v1/admin/status` 已返回 `aiSummaries`，且 server DB 是 `ready=10, failed=0`、server change version 194。真实 iPhone container 侧仍是 `lastSyncCursor=173`、`local_ai_summaries ready=3 failed=7`、outbox pending 为 0。结论：summary job 和 admin status 正常，但 iOS 在没有本地 pending work 时没有拉取 remote-only `ai_summary_updated` changes，导致手机保留旧 failed/缺失状态。
- 2026-05-01 已修复 remote-only summary pull gap：app 回到前台、Settings > Storage & Diagnostics 刷新、Settings > Sync > Sync Now 都会在没有 outbox/upload/download work 时拉取 server changes；Storage & Diagnostics 显示 `This iPhone cursor`、`Mac change version` 和 behind count；`/api/v1/admin/status` 返回 `sync.latestServerChangeVersion`。安装并启动到配对 iPhone 后复制 container 验证：`lastSyncCursor=196`、`local_ai_summaries ready=10 failed=0`、outbox pending/failed `0`，server DB `MAX(server_changes.version)=196`。
- 2026-05-01 已实现 AI summary readability follow-up：server schema version 提升到 8，`ai_summaries` / `local_ai_summaries` 增加 `documentTitle`、`oneLiner`、`documentBlocksJson`；prompt version 当时改为 `media-summary-v2`。短中文 smoke test 返回 `language=zh`，长中文 smoke test 返回 `format=document`、7 个 block、包含 `ai_suggested`；真实 iPhone 安装启动后 container 检查确认 `local_ai_summaries` 新列存在，`lastSyncCursor=201` 与 server change version 201 对齐，outbox pending/failed 为 0。2026-05-03 AI title hardening 后，新生成 summary 当前使用 `media-summary-v3`。
- 2026-05-01 AI summary regenerate 反馈优化：Summary sheet 点击 `Regenerate` 后会立刻显示 regenerating 状态条，按钮变为 in-flight 并禁用重复点击；退出 sheet 不会取消任务，timeline 对应入口继续显示 `Regenerating`。服务端在重新生成开始和失败时保留旧摘要内容，只有新结果 ready 后才替换；失败时 timeline 显示 `Summary failed`，sheet 保留旧摘要并显示失败原因和重试入口。
- 2026-05-01 Timeline search/filter polish：新增轻量 fuzzy 本地搜索、AI summary 参与搜索、命中来源 badges、内容/月/收藏/评论/待同步/命中来源 AND 组合筛选、active chips 和非持久化筛选状态。AI summary job 现在记录 attempt/stage/elapsed timing，对瞬时失败做一次内存内 retry，Settings diagnostics 显示非 ready age 和 retry hint。
- 2026-05-01 search/filter hardening verification：已通过 `server:typecheck`、`server:build`、`admin:build`、generic iOS Debug build、`TimelineSearchTests` 4/4、`git diff --check`、3210 server restart/health、admin status diagnostics shape check，并已 `npm run ios:device` 安装和启动到 `wwz 的 iphone`。
- 2026-05-02 v0.1 收口新增本地 setup 主路径：`npm run setup:local` 会安装依赖、创建缺失的 `server/.env`、生成 Prisma client、通过 `server:prisma:deploy` 应用迁移、构建 Admin UI 和 Server；`--with-ai` 准备 `server/.venv` / `mlx-whisper`，`--with-ios` 生成 Xcode project。README、Runbook、release checklist、open-source readiness 和 security/privacy 说明已对齐；轻量敏感扫描发现 `.gsd/activity/` 历史日志仍含个人 Tailscale 片段，公开发布前需要清理或从干净快照发布。本轮验证已通过 setup help、setup skip-install/skip-build、Prisma deploy、`verify:server`、health、Info.plist lint、generic iOS Debug build、ignore-boundary check 和 `git diff --check`；`npm run ios:device` 已完成 build/sign，但 CoreDevice 未找到配对 iPhone，因此未完成安装。
- 2026-05-03 media upload 硬化已通过 `server:typecheck`、`server:build`、LaunchAgent restart、localhost/Tailscale health check、admin status 检查、无遗留 media `.tmp` 文件、无打开的 media write fd。真实 iPhone container 复制因设备当时处于 `offline/unavailable` 未完成；失败图片应由 iPhone 本地 queue 在下一次 foreground 或 Sync Now 时重试。
- 2026-05-03 真机 Sync Now 报 ATS secure connection：手机仍保存 `http://100.114.41.22:3210`，请求被 iOS ATS 拦在发出前，server `devices.last_seen_at` 未变化。已确认 Tailscale Serve HTTPS 配置存在，直连 Tailscale IP 的 HTTPS health check 成功；Debug app 的 ATS 配置已改为仅用 `NSAllowsArbitraryLoads` 作为 HTTP fallback，避免 `NSAllowsLocalNetworking` 对 Tailscale `100.x` 地址覆盖不稳定。随后 `npm run ios:device` 安装并启动到 `wwz 的 iphone`，server 收到该设备 sync，`server_changes` 推进到 `270`；手机 container 复查 `lastSyncCursor=270`、outbox pending/failed `0`、active media upload pending/failed `0`。之前失败的 `AE1196...` 图片和新分享测试 `C9B8...` 图片已上传完成；仅剩一条 2026-04-30 已删除 post 的旧 pending media 原始行，不属于活跃上传队列。
- 2026-05-03 通过 `$grill-me` 完成 Smart Tags 需求讨论并写入 `.gsd/milestones/M006/M006-CONTEXT.md`、`.gsd/milestones/M006/M006-ROADMAP.md`、`.gsd/milestones/M006/slices/S01/S01-PLAN.md` 和 R022-R027。M006 范围：所有 moment 支持手动标签；新语音 moment 在首次 summary ready 时自动生成主/副标签；视频/图片/文字不做 AI 自动标签；不做历史回填；timeline 最多显示主标签且可通过 `Show tags in Timeline` 隐藏；标签词汇表、aliases、archive/restore、搜索筛选、同步恢复和真机 UAT 都属于 milestone 范围。S01 下一步执行数据/schema/sync foundation。
- 2026-05-03 Smart Tags 自动化验证已完成：`server:typecheck`、`server:build`、`admin:build`、`git diff --check`、Prisma deploy、LaunchAgent restart、localhost health `schemaVersion: 9`、SQLite 默认标签 seed、authenticated admin status tag diagnostics、`xcodegen generate`、iOS simulator tests 17/17、generic iOS Debug build 全部通过。手机重新连接后，`npm run ios:device` 已完成 build/sign/install/launch 到 `wwz 的 iphone`；M006 真机 UAT 清单记录在 `.gsd/milestones/M006/M006-VALIDATION.md`。
- 2026-05-03 Smart Tags follow-up：Settings > Tags 的主标签颜色编辑已从裸 hex 输入改为低饱和预设色板；AI tag prompt 增强，空 `suggestedTags` 会触发一次 tag-only fallback call，并记录不含正文的 `ai.tags_processed` 置信度/跳过原因日志。排查用户最新两条语音时确认问题不在 iPhone 显示层，而是旧 prompt 返回了空标签；两条已 backfill 为 AI 标签并生成 server changes `309-322`。安装并启动到 `wwz 的 iphone` 后，server sync 与 iPhone container 复查均确认 `lastSyncCursor=322`，7 个 AI 标签已进入手机本地库。
- 2026-05-03 Edit Moment media follow-up：主标签色板改为 6 个低饱和默认色 + 一组更清晰的中高饱和预设色，并保留 `#RRGGBB` HEX 自定义输入。修复旧 bug：编辑语音 moment 时，audio 不再被传给图片缩略图网格解析；Edit Moment 现在按 media kind 渲染，图片保留可排序网格，audio/video 显示对应预览，并在非图片 media 存在时禁用 Add Photos/Use Camera 以保持 one-media-kind 语义。
- 2026-05-03 Appearance follow-up：Settings 新增 Appearance section，提供 `System / Light / Dark` 三段选择；偏好仅保存在本机 `UserDefaults`，通过 SwiftUI `preferredColorScheme` 即时生效，不进入 sync/schema，也不尝试修改 iOS 设备级深浅色模式。已通过模拟器测试、generic iOS build，并安装启动到 `wwz 的 iphone`。
- 2026-05-03 Appearance UI polish：Appearance section 从 Form 内嵌 segmented control 改为三条原生 Settings 风格选择行，使用 `System / Light / Dark` 图标和 checkmark 表示当前项，避免“小框嵌大框”的视觉层级。
- 2026-05-04 Calendar Day Review follow-up：Calendar 日期单击不再切 Timeline，也不再依赖长按 preview；单击会进入 Calendar 内的完整 `Day Review` 页面，右上角 `Timeline` 才是二级跳转到 Timeline day filter 的入口。Day Review 使用无卡片日内时间轴、日期/星期/数量/媒体构成 header、跟随 `Show Tags in Timeline` 的主标签显示、轻量 Markdown 标题渲染、统一小图网格、行内音频播放和视频类型/时长提示；内部 detail 跳转使用 `NavigationPath`，点击右箭头或内容可进入单条浏览并返回 Day Review。
- 2026-05-04 音频 UI follow-up：Timeline、Detail、Day Review 统一使用 waveform voice bar 取代旧 slider 播放条；支持点击播放/暂停、拖动 seek、右侧倍速 capsule menu，波形细分更密，播放按钮与波形区对齐，Detail 使用稍高密度，播放结束仍回到初始未播放状态。本轮已通过 tracked diff check、new-file whitespace check、generic iOS Debug build、`CalendarReviewModelsTests` 3/3，并已 build/sign/install 到连接的 iPhone；自动启动仅因手机锁屏被拒。
- 2026-05-04 UAT feedback fixes：Day Review 主标签现在跟随 `Show Tags in Timeline`，右箭头/内容点击进入单条详情的 bug 已用 `NavigationPath` 修复；waveform bar 改为更细密条形并让播放按钮/倍速按钮对齐波形区域。验证通过 `git diff --check`、generic iOS Debug build、`CalendarReviewModelsTests` 3/3，并已安装启动到 `wwz 的 iphone`。
- 2026-05-04 UAT follow-up：`Show Tags in Timeline` 关闭后 Moment Detail 不再显示 Tags section，也不再提供 Edit tags；音频播放在 App 内切 tab、进详情、开设置/发布/summary/gallery/video、或退出 Day Review/Detail 时自动暂停，但后台/锁屏继续播放；Day Review 通过 per-day visible moment id 记住上次滚动位置。验证已通过 `git diff --check`、手动 trailing whitespace 检查、generic iOS Debug build 和 `CalendarReviewModelsTests` 3/3；`npm run ios:device` 已 build/sign/install 到真机，最后 auto-launch 仅因设备锁屏被拒。
- 2026-05-04 Calendar Review density/statistics follow-up：Calendar 月份 heatmap 改为按可见月份最高发布日动态分级，并在日期格显示轻量数量；navigation bar 右上角新增 `Month Stats` sheet，展示当月总数、活跃天数、活跃日均、最多的一天、每日柱状节奏和内容组成。Calendar 月份筛选只影响月份网格和统计；点击日期进入完整 Day Review，Day Review 自带横向 chips，可按媒体、收藏、评论过滤，并使用 24 小时制时间列和轻量日内分隔。
- 2026-05-04 Calendar Review filter/statistics refinement：Day Review filters 改为多选 OR 逻辑，点已选 chip 取消，点 All 清空；Summary 不再是独立 Day Review filter，也不在 Month Stats 中统计，因为当前产品语义下 Audio 已覆盖 summary。Month Stats 去掉 Close 按钮，保留下滑关闭；每日柱状条和最多的一天可直接进入 Day Review，内容组成行可作为 Calendar 月份筛选快捷入口。
- 2026-05-04 Markdown editor follow-up：Composer 和 Edit Moment 的正文输入切到轻量 Markdown 富文本层；底层仍保存 Markdown source `String`，只支持 H1、H2。标题行在非当前行隐藏 `#` / `##`，光标进入时临时露出 marker；键盘 accessory toolbar 只提供 H1/H2。Timeline、Detail 和 Day Review 统一渲染 H1/H2，粘贴真实图片仍进入 New Moment 下方 media grid，不进入正文。
- 2026-05-04 Markdown editor IME follow-up：修复 H1/H2 后中文输入法候选词被打断的问题。`MarkdownTextEditor` 在 `UITextView.markedTextRange` 存在时不再重写 `textStorage` 或外部替换正文，候选词提交后再恢复样式；键盘上方格式工具从松散按钮改为紧凑 H1/H2 segmented control。
- 2026-05-04 Markdown list rollback / accessory / tag color follow-up：回滚 Composer/Edit 的无序列表富渲染，普通 `- ` / `• ` / numbered list 只保留既有 plain-text continuation，不再在编辑器、Timeline、Detail 或 Day Review 中显示 Markdown bullet；键盘 accessory 只保留 H1/H2，不再显示 Done/list。Settings > Tags 色板扩展为 6 个低饱和色 + 高饱和标准色，并在 Edit 模式支持批量选择 primary tags 后统一改色；HEX 自定义输入继续保留。验证已通过 `git diff --check`、iPhone 17 simulator tests 33/33、generic iOS Debug build，并已 `npm run ios:device` 安装启动到 `wwz 的 iphone`；移除 Done 后又通过 focused diff check、generic iOS build 和真机安装启动。
- 2026-05-04 Smart Tags primary repair：排查最新两条语音发现 AI primary 置信度已返回，但默认 primary tag canonical name 被颜色编辑同步写成英文且 `isDefault=false`，导致中文 primary 建议匹配失败。已修复 iOS 默认 tag payload、server 默认 tag ID 兜底、AI primary 中英文匹配和 primary-missing tag fallback；server DB 已修复默认标签并给两条语音补回 primary：短语音 `想法` + `Codex额度`，三分钟语音 `日记` + `APP开发/数据库/毕业论文`。server changes 推进到 `550`；Mac server 已重启，真机 build/install 成功，自动启动仅因手机锁屏被拒。
- 2026-05-05 M009 Archive/Sync Health Phase A verification：`git diff --check`、`npm run server:typecheck`、`npm run server:build`、`npm run admin:build`、generic iOS Debug build 均已通过；Homebrew `restic 0.18.0` 可用。严格隔离 Archive smoke 在 compiled server port `3330` 使用临时 data dir 和临时 restic repository 通过，覆盖 health/schemaVersion 10、repository configure/init、manual backup、snapshot count 1、repository check、restore succeeded、restore verification ok、`missingMediaFiles=0`、promote preparation succeeded 和 `archive/pending-promote.json` 创建。验证中修复了三处收口问题：Fastify 全局 error handler 保留 4xx status、`FileLogger` 自动创建 logs 目录、`setup-local.sh` 会在缺失 SQLite `file:` 数据库时先创建空文件再跑 Prisma deploy。fresh setup 验证已用 `DATABASE_URL="file:./m009-fresh-verify.db" npm run setup:local -- --skip-install --skip-build` 跑通 11 个 migrations 并确认 `maintenance_jobs` 可查询。早前一次 `npm run ios:device` 因 CoreDevice 报设备 unavailable 未完成安装；本轮重连后已重跑成功，见下一条。
- 2026-05-05 M009 Phase B export/import verification：严格隔离 HTTP smoke 在 compiled server port `3347` 使用临时 data dir 通过，覆盖 login、通过 `/api/v1/sync` 创建一条 post、通过 `/api/v1/media/upload` 上传一张图片、`export_create` job 成功并产生 `.tar.gz` artifact、`import_restore` job 成功导入到 staged data directory、导入 DB 检查 `posts=1`、`media=1`、`devices=0`、`server_changes=9`，导入后的 media 文件实际存在，`missingMediaFiles=0`。随后 `npm run ios:device` 已 build/sign/install/launch 到 `wwz 的 iphone`，脚本报告 server URL `http://100.114.41.22:3210`。
- 2026-05-03 Smart Tags duplicate-name follow-up：`local_tags.normalizedName` 是全局唯一，之前从 Add Primary/Topic 新建一个已存在但不在当前分组可见的 tag 时，会直接暴露 SQLite `UNIQUE constraint failed`。现在 Add Tag sheet 会提前检测 active/archived Primary 或 Topic 的同名项并显示内联说明；create/rename 写入前也会做本地词表冲突检查，避免底层约束错误冒到 UI。
- 2026-05-03 Smart Tags add-sheet follow-up：修复 SwiftUI sheet 旧状态问题。之前 Add Tag sheet 由 `isAddingTag` 和默认 `"topic"` 类型两个状态共同驱动，Add Primary Tag 可能展示旧的 Topic sheet，导致新增项进入 Topic Tags。现在 sheet 由携带 `primary/topic` 的 identifiable request 驱动，避免类型复用。
- 2026-05-03 Smart Tags archived-delete follow-up：Settings > Tags 的 archived 非 default tag 现在可以 `Delete Permanently`。删除会走 `delete_tag` sync operation，server 先发 assignment/alias 删除变更，再发 `tag_deleted`，并彻底释放 normalized name；适用于误把某个名称创建成 Topic 后想删除并重新创建成 Primary 的恢复场景。
- 2026-05-03 Smart Tags topic-count and batch-management follow-up：AI topic tag prompt 和服务端裁剪策略已改为短音频/短 transcript 优先 1 个 topic，只有额外建议高置信度且主题明显分离时保留多个；Settings > Tags 右上角 `Edit` 支持 Topic 批量 Archive/Merge，以及 Archived 批量 Restore/Delete。
- 2026-05-05 M010 AI Periodic Reviews implementation：新增 schema version 11，server `reviews` / `review_feedback` / `review_memory` / `review_settings`，`weekly-review-v1` generator，Review API routes，Mac Sunday-evening scheduler，Calendar Reviews UI，Weekly Review detail rendering，feedback controls，Settings 默认关闭的 auto-generate/publish toggles，以及显式 publish-as-moment。设计上 Review 是 generated artifact，不默认进入 Timeline；ordinary review sections 不做 per-claim evidence，只有 `Worth Revisiting` anchors 在 Review 内部打开 moment preview。
- 2026-05-06 AI token usage ledger follow-up：新增 schema version 12 `ai_usage_events`，对 media summary、weekly review 和 tag fallback provider calls 记录 privacy-safe token usage。记录字段只包含 feature、subject type/id、provider/model、promptVersion、status、duration、token usage、cached input token、字符估算和错误码；不保存 transcript、prompt、review input、summary body 或 provider response 正文。`/api/v1/admin/status.aiUsage` 聚合 Today、This week、This month、All time、本月按 feature breakdown 和 recent failures；iOS Settings > Storage & Diagnostics 增加 `AI Token Usage` 只读区。
- 2026-05-05 sustainability audit fix：Review generation 增加 35 天范围上限和 240 moments provider 输入上限；Review publish markdown 改为只生成 app 支持的 H1/H2 和普通列表，不再生成 H3；Review/Archive schedulers 捕获并记录 tick 失败，避免后台 promise 变成未处理异常；server 新增 Node test runner 脚本并把 focused Review tests 纳入 `verify:server`；runbook 增加 runtime truth check，要求 live health schema 与当前 `SCHEMA_VERSION` 对齐。

M003 验证证据记录在 `.gsd/milestones/M003/M003-VALIDATION.md`。M004 当前验证已覆盖 `server:typecheck`、`admin:build`、generic iOS Debug build、iOS simulator tests、真机构建安装和启动，以及 3210 server 重启后的 `schemaVersion: 5` health check；仍需要 real iPhone 音频/视频 UAT。2026-04-30 sync failure 修复已额外验证：server typecheck/build、隔离 SQLite server 上的 typed media multipart upload、隔离旧 `Unsupported operation type: create_comment` 幂等重放、真实 iPhone container SQLite 检查确认媒体失败已清掉且只剩旧已删除评论 no-op。2026-04-30 音频复位和视频静音自动播放已通过 generic iOS Debug build、iOS simulator tests，并成功安装和启动到 `wwz 的 iphone`；仍需要手动观察真机上的播放结束复位和滑动自动播放体验。2026-04-30 语音/视频转写已通过 `server:typecheck`、`server:build`、`server:prisma:migrate`、`admin:build`、iOS simulator tests、generic iOS Debug build、3210 server 重启后 `schemaVersion: 6` health check，以及 `npm run ios:device` 真机构建安装/启动。2026-04-30 M005 AI summary 首版已通过 server Prisma migrate/build/typecheck、Admin build、generic iOS Debug build、iOS simulator tests、3210 server 重启后 `schemaVersion: 7` health check、真实 iPhone build/install；真机启动被 iPhone 锁屏拒绝。配置本地 provider 后，server API smoke test 已对一条现有 video transcript 生成 `ready` summary，DB 中 summary length 为 171，日志检查未出现 transcript 或 summary 正文。2026-05-01 server-side media summary 跟进已通过 `server:typecheck`、`server:build`、`admin:build`、generic iOS Debug build、iOS simulator tests 13/13、`git diff --check`、3210 server health `schemaVersion: 7`，以及 `npm run ios:device` 真机构建和安装。2026-05-01 fallback 修复额外通过 `server:typecheck`、`server:build`、`git diff --check`、3210 health、最新一条和另外 4 条缺 summary record 的语音手动 backfill 到 ready，以及 `npm run ios:device` 真机构建安装并启动到 `wwz 的 iphone`。2026-05-01 provider unusable 修复已通过 `server:typecheck`、`server:build`、generic iOS Debug build、强制重新生成得到 `failed/audio_input_unusable`、6 条坏 summary failed 同步变更、3210 current build restart、`git diff --check` 和真机构建安装；启动被 iPhone 锁屏拒绝。2026-05-01 本地 `mlx-whisper` 转写 + 外部 summary 更新已通过 `server:typecheck`、`server:build`、generic iOS Debug build、真实 audio smoke test、6 条旧 failed summary 批量重生成、3210 current build restart、health check、`/api/v1/admin/status` AI diagnostics 检查、`git diff --check` 和 `npm run ios:device` 真机构建安装启动到 `wwz 的 iphone`。2026-05-01 remote-only summary pull 修复已通过 `server:typecheck`、`server:build`、`admin:build`、generic iOS Debug build、`npm run ios:device` 真机构建安装启动、3210 health、admin status diagnostics，以及真实 iPhone container 检查：`lastSyncCursor=196`、`local_ai_summaries ready=10 failed=0`、outbox pending/failed `0`。2026-05-01 AI summary readability follow-up 已通过 `server:typecheck`、`server:build`、`admin:build`、generic iOS Debug build、Prisma migrate deploy、短/长 provider smoke tests、3210 health `schemaVersion: 8`、`git diff --check`、`npm run ios:device` 真机构建安装启动，以及真实 iPhone container schema/cursor/outbox 检查。

## 仍然偏大的文件

这些文件后续成为活跃编辑目标时，优先继续拆分：

- `admin/src/App.tsx`
- `server/src/api/admin.ts`
- `server/src/api/sync.ts`
- `server/src/api/media.ts`
- `ios/PrivateMoments/Views/MomentDetailView.swift`

## 下一步合理工作

- 开始新工作前，先用 `docs/WORKFLOW.md` 判断走 quick track 还是 milestone track。
- 继续 feature work 时，不要把主 timeline 变复杂。
- 扩展 Posts management 前，先把 Admin UI 拆成更小的 React components。
- 新增 admin/sync/media 行为前，优先拆分 server API handlers。
- 为 sync cursor recovery、media batch download、automatic retry、storage diagnostics 和 duplicate device binding 增加 focused regression tests。
- 在真实 iPhone 上完成 M004 音频/视频 UAT：录音、暂停/继续/停止、试听、发布、后台播放、选择短视频、拒绝超长视频、全屏播放、sync/upload/recovery、Storage cache clear。
- 在真实 iPhone 上手动确认 Settings > Storage & Diagnostics 的 AI summary diagnostics 和 sync cursor comparison UI 渲染正常；API 和 container 数据验证已通过。
- 用一条 fresh clear-speech audio/video 验证新流程：发布后 iOS 不出现 transcript 或 Summary 占位；Mac 后台生成成功后，follow-up sync 让 timeline 出现 `Summary ready`；打开 bottom sheet 显示 v3 document summary，确认短标题、折叠详情、`AI suggested` 标识、Regenerate in-flight 反馈、退出 sheet 后 timeline `Regenerating` 状态、失败保留旧摘要语义、Delete 可用。对 fresh audio 额外确认：如果发布时没有手写 `#`/`##` 标题，AI title 自动插入为 timeline/detail 顶部标题，不显示 `Edited`，Regenerate 不覆盖已有标题；关闭 Settings > Feature Modules > `AI Title Auto-Insert` 后不再对未来音频自动插入。
- 在真实 iPhone 上完成 M006 Smart Tags UAT：手动主标签发布、timeline tag toggle、Detail 标签显示/单条标签编辑、topic alias search、topic merge/archive/restore、Storage diagnostics tags、以及新语音 moment -> summary ready -> AI tags sync。
- Share Extension 需要真实 iPhone UAT：Photos 多图分享、Safari URL/text 分享、Files/Voice Memos 音频分享、视频分享、主 App composer 唤起、发布成功、import queue 消费后清理，以及真实设备 provisioning 是否已启用 App Group。
- 当前下一步是人工 UAT Admin `Archive` tab 的真实本地服务流程。Phase B export/import 已实现并通过隔离 smoke，但 import 只创建 staged data directory；真正切换仍需走 promote/restart 安全流程。v0.1 公开发布暂时不是主线，以后再回到开源时仍需补 license、secret-history scan、`.gsd/` 公开策略和干净公开仓库。
- M010 下一步是人工 UAT Weekly Review 的质量：真实数据上生成一份最近 7 天 review，检查整体语气是否是冷静观察 + 适度鼓励，是否避免逐条 moment 过度解读，`Worth Revisiting` 是否足够低权重且能在 Review 内打开原 moment。
