# Private Moments 交接说明

Last reconciled: 2026-04-30

## 当前工作状态

- Mac server 已可构建和运行，覆盖 Fastify、Prisma、SQLite、file storage、auth、sync、media upload、media download、admin routes 和静态 Admin UI 托管。
- iOS app 名为 `Moments`，可通过 `npm run ios:device` 安装到已配对 iPhone。
- Admin UI 可通过 `npm run admin:build` 构建，并由 server 在 `/admin/` 提供访问。
- 项目工作流已写入 `docs/WORKFLOW.md`，agent 强制规则写入 `AGENTS.md`。
- `.gsd/` 是结构化事实源，记录当前项目事实、requirements、decisions 和 milestone state；`docs/` 是给人阅读的稳定文档层。
- 2026-04-29 的真实 iPhone 验证结果：
  - `local_posts`: 8
  - visible local posts: 5
  - downloaded media cache entries: 9
  - missing visible media: 0

## 已实现的产品能力

- Local-first iOS timeline。
- 支持 text-only、image-only、text + image posts；空 post 会被拒绝。
- 支持 photo library 和 camera import。
- 支持手动设置 occurred date/time。
- 支持本地 composer drafts。
- 支持 offline outbox sync。
- 失败的 pending sync work 会自动延迟重试。
- Post detail view。
- Full-screen image gallery，带接近原生体验的 pan 和 zoom。
- 支持编辑 text、occurred time、images 和 image ordering。
- 支持 favorite / unfavorite moments。
- 支持 search、filters 和 month jump。
- Timeline date 使用英文 human-friendly labels，滚动时显示临时 floating month indicator。
- Timeline soft delete 使用居中的确认 alert。
- Settings 包含简化后的 connection、sync、advanced sync 和 storage diagnostics 页面。
- Mac Admin 包含 Overview 和 Posts management。
- 使用 `deviceKey` 绑定设备，避免同一物理设备重复注册。

## 2026-04-29 的重要修复

- iOS 现在能解析带 fractional seconds 的 server ISO8601 timestamp，例如 `2026-04-29T06:40:42.000Z`，避免 server changes 被跳过。
- iOS 加入一次性 cursor recovery：`didApplySyncRecoveryV1`。当 local post table 为空时，会把 cursor 重置为 `0`。
- Server 提供 `POST /api/v1/media/batch-download`。
- iOS 使用 batch thumbnail JSON 做 remote media cache recovery，因为真实 iPhone + Tailscale 场景下重复 binary media downloads 测试不稳定。
- iOS 在保存和上传 display copies 前压缩图片；upload-time compression 也覆盖旧 pending images。当前策略是 max edge `1600px`，JPEG quality `0.72`。
- 失败的 pending sync 或 media upload 会按 backoff 自动重试：5s、20s、60s、120s，然后 300s。
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
- core feature polish 后再做 backup/export；backup 目前不是下一个阻塞项。
