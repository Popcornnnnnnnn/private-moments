# v0.1 收口与发布检查清单

本文档用于把当前项目从持续开发状态收口到一个可验证的 v0.1 内部候选版本。它不是功能路线图，而是发布门禁。

## 版本边界

v0.1 的目标是交付一个稳定的私有时间线闭环：

- iPhone 可以发布、浏览、搜索和管理个人 Moments。
- Mac server 可以保存 SQLite 数据、媒体文件、Admin UI 和同步 API。
- 文本、图片、语音、视频、评论、收藏、搜索筛选、AI media summary 都能在日常使用中形成闭环。
- Share Sheet import、Smart Tags、AI 音频标题写回和 Settings 诊断/管理入口不破坏主时间线简洁性。
- Timeline 保持简洁，低频诊断和维护能力放在 Settings、Admin UI 或文档里。
- Mac Admin 可以管理个人 archive 的 backup/restore，Sync Health 可以解释 Mac/iPhone 同步是否健康。
- Mac Admin 可以创建 migration-first export package，并把 export package 导入到 staged data directory。

v0.1 收口后，只接受以下类型变更：

- 阻塞真实使用的 bug。
- 数据安全、同步安全、媒体恢复相关修复。
- 安装、配置、文档、发布材料清理。
- 不改变产品语义的小范围体验修补。

## 本地启动门禁

新用户或新机器优先使用：

```bash
npm run setup:local
```

可选能力：

```bash
npm run setup:local -- --with-ai
npm run setup:local -- --with-ios
```

通过标准：

- `server/.env` 存在，且真实使用前已替换 `PRIVATE_MOMENTS_INITIAL_PASSWORD`。
- `npm install` 成功。
- Prisma client 生成成功。
- 数据库迁移通过 `server:prisma:deploy` 应用成功。
- `admin:build` 成功。
- `server:build` 成功。

## Server/Admin 验证门禁

```bash
npm run verify:server
npm run server:dev
curl -fsS http://127.0.0.1:3210/api/v1/health
npm run doctor:runtime
PRIVATE_MOMENTS_SMOKE_PASSWORD="<read-from-server-env>" npm run doctor:sync
```

通过标准：

- TypeScript typecheck 通过。
- Server build 通过。
- Admin build 通过。
- Health endpoint 返回成功。
- Admin UI 可以登录并查看 storage、sync、AI summary diagnostics。
- Runtime doctor 不再发现旧目录、旧 LaunchAgent cwd、旧 SQLite 路径或旧虚拟环境 shebang。
- Sync doctor 没有 pending/rejected sync、media、AI summary 或 maintenance job 的阻塞项。

## iOS 验证门禁

```bash
cd ios
xcodegen generate
xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

真实设备验证：

```bash
npm run ios:device
```

通过标准：

- App 可以安装到配对 iPhone。
- Server URL 和 password 配置后可以完成登录和同步。
- 前台、后台再回前台、手动 Sync Now 都不会造成 timeline 丢失或重复。

## 产品 UAT 清单

每个候选版本至少手工验证一次。权威 gate 状态记录在 `docs/UAT-GATES.md`；release candidate 前必须运行：

```bash
npm run verify:release-gates
```

以下是人工验证范围摘要：

- 发布纯文本 Moment。
- 发布图片 Moment。
- 发布语音 Moment，播放结束后回到初始播放状态。
- 发布视频 Moment，滑到视野中可静音自动播放。
- 发布带文本的图片、语音、视频 Moment。
- 从 Photos / Files / Safari 等系统 Share Sheet 使用 `Save to Moments` 导入内容，确认主 App Composer 打开、可编辑并成功发布。
- 主界面评论按钮能打开输入框，评论后滚动到最新评论位置。
- 长按评论能出现确认删除提示。
- 搜索支持模糊命中和媒体类型筛选。
- 按月份、收藏、评论、命中筛选可用。
- AI media summary 生成后显示 `Summary ready`，点击进入可阅读 Markdown-like summary。
- 新语音未手写标题时，AI ready 后可把短标题写入正文顶部；已有 `#` / `##` 标题或关闭 `AI Title Auto-Insert` 时不自动写入。
- 手动主标签、主题标签筛选、Settings > Tags 的 archive/restore/delete/merge/alias/color 管理可用；新语音的 AI 建议标签能在 summary ready 后同步出现。
- Settings > Storage & Diagnostics 可以看到 storage、sync 和 AI summary 状态。
- Mac Admin 的 Archive & Export / Backups 区域可以创建、列出、校验、恢复并 promote 备份快照。
- Mac Admin 和 iOS Settings 的 Sync Health 可以区分 server reachability、auth、cursor lag、outbox、media upload、missing media 和 AI summary pipeline 状态。

如果某一项暂时只能由用户肉眼确认，关闭 gate 时必须把用户确认写进 `docs/UAT-GATES.md`、`docs/HANDOFF.md` 和 `.gsd` 验证记录。

## 数据恢复门禁

M009 Phase A 完成后，v0.1 内部候选版本还必须满足：

- Admin 可初始化 backup repository；repository 可选本机目录或用户明确选择的 iCloud Drive 路径。
- 底层 backup 使用 restic deduplicated snapshots；项目自动管理 `.private-moments-restic-key`，用户不需要记备份密码。
- Admin 清楚说明：谁同时拿到 repository 和 key 文件，就可以恢复 archive；这不是额外的加密保险箱。
- 支持立即备份和每日固定时间定时备份。
- 支持 snapshot list/check。
- Restore 必须恢复到新数据目录，不能直接覆盖当前数据。
- Promote preparation 前必须验证恢复目录、进入 maintenance mode、创建 pre-promote snapshot，并要求强确认。
- 当前 v0.1 promote 不做 live SQLite hot swap；通过 `archive/pending-promote.json` 输出 `PRIVATE_MOMENTS_DATA_DIR` 和 `DATABASE_URL` restart instructions，operator 停止 server、切换 env、重启 server。
- 普通 sync/media/AI 写入在 restore/promote 期间被暂停。

- Export 支持全量和日期范围。
- Export package 以 JSON manifest/metadata 为权威，Markdown 只是预览。
- Export 包含 media、comments、tags、AI summary/title metadata、archived/soft-deleted 未永久清理状态。
- Export 不包含 auth token、session、device runtime state。
- Import 只导入到新/空数据目录，并保留 archive IDs/timestamps/generated metadata；导入后重新初始化 sync/outbox/device 状态。

自动化演练入口：

```bash
npm run doctor:archive
```

通过标准：

- live SQLite 的临时副本 `quick_check` 通过。
- report 中 posts/media/check-ins/server changes 统计符合当前 archive 预期。
- 未删除 media 引用的文件存在。
- restic 可用，archive config 可读。
- 没有遗留的 `archive/pending-promote.json` 挡住下一次 restore/promote 演练。

## AI 质量门禁

```bash
npm run doctor:ai
```

通过标准：

- 新 ready summary 使用当前 prompt version，标题不超过当前约束。
- Weekly Review 使用当前 prompt version，anchors 指向仍存在的 active posts。
- `ai_usage_events` 有可用的 feature/model/status/token 记账，不包含私密正文。
- 历史旧 summary/review 可以作为 warning 记录，但不能掩盖新生成路径的回归。

## 开源前门禁

公开发布前必须完成：

- 仓库不包含 `server/.env`、真实数据库、媒体文件、设备日志、API key、私人 Tailscale IP。
- `.gitignore` 覆盖本地数据、构建产物、依赖目录和运行时缓存。
- `README.md` 能让新用户通过 `npm run setup:local` 完成本地安装。
- `docs/OPERATOR-RUNBOOK.md` 覆盖常见启动、安装、排查路径。
- `docs/OPEN-SOURCE-READINESS.md` 中没有未解释的 release-blocking 项，剩余风险有明确处理路径。
- 明确 license。
- 明确外部 AI provider 的隐私边界。
- 补齐最小数据安全闭环：backup、restore、promote preparation、export/import 的操作说明或脚本。

当前工作区扫描入口：

```bash
npm run doctor:release
```

`doctor:release` 只覆盖当前 checkout，不替代 Git history secret scan。公开发布前仍需要对历史提交、release 分支和最终公开快照单独审计。

## 当前结论

截至 2026-05-10，GitHub `main` 已更新为当前 public source snapshot，并保留旧 GitHub `main` 到远端备份分支 `backup/github-main-before-local-refresh-20260510`。项目仍优先服务作者本人长期稳定自用；公开源码不等同于 stable release。正式 tag/Release 前仍需重新运行 `npm run verify:release-gates`、`npm run doctor:release`、必要的 `doctor:*`，并完成 Git history secret scan、`.gsd` 公开策略和 release-grade archive 演练。
