# v0.1 收口与发布检查清单

本文档用于把当前项目从持续开发状态收口到一个可验证的 v0.1 内部候选版本。它不是功能路线图，而是发布门禁。

## 版本边界

v0.1 的目标是交付一个稳定的私有时间线闭环：

- iPhone 可以发布、浏览、搜索和管理个人 Moments。
- Mac server 可以保存 SQLite 数据、媒体文件、Admin UI 和同步 API。
- 文本、图片、语音、视频、评论、收藏、搜索筛选、AI media summary 都能在日常使用中形成闭环。
- Timeline 保持简洁，低频诊断和维护能力放在 Settings、Admin UI 或文档里。

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
```

通过标准：

- TypeScript typecheck 通过。
- Server build 通过。
- Admin build 通过。
- Health endpoint 返回成功。
- Admin UI 可以登录并查看 storage、sync、AI summary diagnostics。

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

每个候选版本至少手工验证一次：

- 发布纯文本 Moment。
- 发布图片 Moment。
- 发布语音 Moment，播放结束后回到初始播放状态。
- 发布视频 Moment，滑到视野中可静音自动播放。
- 发布带文本的图片、语音、视频 Moment。
- 主界面评论按钮能打开输入框，评论后滚动到最新评论位置。
- 长按评论能出现确认删除提示。
- 搜索支持模糊命中和媒体类型筛选。
- 按月份、收藏、评论、命中筛选可用。
- AI media summary 生成后显示 `Summary ready`，点击进入可阅读 Markdown-like summary。
- Settings > Storage & Diagnostics 可以看到 storage、sync 和 AI summary 状态。

## 开源前门禁

公开发布前必须完成：

- 仓库不包含 `server/.env`、真实数据库、媒体文件、设备日志、API key、私人 Tailscale IP。
- `.gitignore` 覆盖本地数据、构建产物、依赖目录和运行时缓存。
- `README.md` 能让新用户通过 `npm run setup:local` 完成本地安装。
- `docs/OPERATOR-RUNBOOK.md` 覆盖常见启动、安装、排查路径。
- `docs/OPEN-SOURCE-READINESS.md` 中没有 release-blocking 项。
- 明确 license。当前公开候选目录使用 `MIT`。
- 明确外部 AI provider 的隐私边界。
- 补齐最小数据安全闭环：backup、restore、export 的操作说明或脚本。当前公开候选目录已提供 `npm run backup:local`、`npm run restore:local` 和 `npm run export:local`。

## 当前结论

截至 2026-05-02，项目适合进入公开候选收口；尚不建议直接推到公开 GitHub 仓库。主要剩余风险是公开候选 Git history secret scan、release notes 和最后一次干净机器 setup/UAT。
