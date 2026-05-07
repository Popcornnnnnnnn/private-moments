# Admin 迁移计划

Last updated: 2026-05-07

## 目标

Mac Admin 后续不再作为日常后台中心。iOS app 是主要使用界面；日常设置、监控、诊断和安全修复动作优先进入 iOS Settings / Diagnostics。

Mac Admin 只保留必须依赖 Mac 本地文件系统、server 进程、Archive repository 或恢复 artifact 的低频运维能力。它应该像“本地恢复控制台”，而不是内容管理后台。

## Admin 最小保留信息

以下信息保留在 Mac Admin：

| 类别 | 保留内容 | 原因 |
|---|---|---|
| Archive 与恢复 | restic repository path、key file path 状态、restic availability/version、repository initialized 状态、自动备份 schedule、snapshot list、restore/check/promote/export/import jobs | 这些能力依赖 Mac 文件路径、restic、staged data directory 和 artifact，iPhone 不适合作为主执行端 |
| Promote 与 artifact | `pending-promote.json` 位置、staged restore data directory、export/import artifact path、pre-promote backup 状态 | promote 当前是 restart-safe preparation，需要 operator 在 Mac 上停止 server、更新 env、重启 |
| Server runtime truth | server version、schema version、data directory、database path、media/logs directory、uptime、available disk | 排障时必须知道当前 Mac 进程实际读写哪里 |
| Maintenance jobs | 当前 maintenance mode、running job、job status/progress、最近失败 job 的 error code/message | 长任务需要浏览器刷新后仍可见，并且不能只靠 iPhone 表示 Mac 端恢复状态 |
| Server logs | privacy-safe recent logs、error code、job/media/sync stage metadata | 日常状态不看日志；真正排障需要 Mac 端日志 |
| Device emergency | active/revoked devices、revoke device、按设备清理测试 posts 的危险操作 | 设备 token 和测试数据清理是低频恢复/排错操作；必须保留强确认 |

以下信息不应长期依赖 Mac Admin：

- 普通内容浏览、阅读、筛选和回看：迁移或保留在 iOS Timeline / Calendar / Search。
- 日常 Sync Health：以 iOS Settings > Storage & Diagnostics 为主；Admin 只保留 Mac 侧只读摘要和日志入口。
- Tags、AI Language、Feature Modules、Weekly Review settings：继续放在 iOS Settings。
- AI token usage 的日常查看：iOS Settings 为主；Admin 只作为 server status 的只读来源。
- 媒体播放、语音/视频内容消费：不进入 Admin。

## 迁移顺序

### Step 1: Admin 入口降级为 Mac 运维面

当前 checkpoint 已把 Mac Admin 默认入口切到 `Archive`，并把 tab 顺序调整为 `Archive / Overview / Posts`。这不会删除旧能力，但会让默认使用路径先落到最需要 Mac 的恢复和迁移能力上。

### Step 2: Overview 收缩

下一步把 Overview 收缩成三块：

1. Runtime：server/schema/data dir/disk/logs。
2. Jobs：maintenance mode、running/recent failed jobs。
3. Emergency devices：active/revoked devices、revoke、clean test posts。

普通 post count、media count、AI usage、tag diagnostics 等日常读数继续由 iOS Settings 展示；Admin 只在排障时读 `/api/v1/admin/status` 的 Mac 侧证据。

### Step 3: Posts 降为 Debug/Emergency

`Posts` 不再作为长期内容管理入口。后续可以改成 hidden/debug-only 或只保留：

- 按 ID 定位少量 post。
- 查看 media path/status/checksum 等恢复证据。
- 清理明确测试设备产生的数据。

不增加 Admin 内编辑、播放、批量内容整理或日常搜索体验。

### Step 4: iOS 补齐迁移项

如果收缩 Admin 时发现某个日常动作还只能在 Mac Admin 里完成，优先补到 iOS Settings / Diagnostics。候选包括：

- 更清晰的 Mac reachability/runtime 摘要。
- Archive 最近备份时间的只读状态。
- 最近 failed maintenance job 的只读提示。
- Sync Health 与 AI diagnostics 的更短路径。

触发备份、restore、promote、export/import 仍留在 Mac Admin，避免 iPhone 误操作 Mac 本地恢复流程。

## 当前边界

本轮只做低风险方向切换和文档化，不删除任何现有 Admin 功能，不改变 API、SQLite schema、sync 语义或 Archive job 行为。后续真正删除或隐藏 `Posts`、重构 Overview 时，应作为单独 checkpoint 处理，并至少验证 `npm run admin:build` 和 Admin smoke。
