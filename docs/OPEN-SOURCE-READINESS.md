# 开源前清理评估

评估日期：2026-05-02

当前结论：**不建议立即公开发布；适合先作为 v0.1 内部候选版本继续收口。**

这个项目已经具备个人使用闭环，但开源发布需要额外关注隐私边界、安装路径、历史敏感信息和数据安全。

## 已具备的基础

- 根目录已设置 npm workspaces，server 和 admin 可以统一安装依赖。
- 新增 `npm run setup:local`，用于新机器初始化、生成 Prisma client、应用数据库迁移、构建 Admin UI 和 Server。
- `server/.env.example` 使用占位配置，没有包含真实 API key。
- `.gitignore` 已覆盖 `server/.env`、`server/data/`、`server/.venv/`、`server/dist/`、`admin/dist/`、`ios/build*`、`ios/PrivateMoments.xcodeproj/`、`node_modules/`、`.tmp/` 等运行时或生成内容。
- 文档已经覆盖产品定位、技术设计、操作 runbook、integration guide、design principles、workflow 和 handoff。
- AI media summary 的真实 provider credential 设计为只存在 Mac server 环境变量中。

## Release-blocking 项

### 1. License 未明确

公开仓库需要先选择 license。建议优先在以下两种里选择：

- `MIT`：最开放，适合让别人自由 fork 和修改。
- `AGPL-3.0`：如果你希望别人把改过的网络服务公开使用时也必须开源改动，可以考虑这个。

当前建议：如果目标是展示项目、让别人参考和自用，选择 `MIT` 更简单。

### 2. 最小数据安全闭环已经有主路径，仍需最终发布级验证

项目保存的是私人 timeline、图片、音频、视频、评论和 AI summary。公开前至少需要给出明确的 backup/restore/export 路径。

当前进展：

- M009 Phase A 已加入 Mac Admin 管理的 restic backup/restore：repository config、项目管理 `.private-moments-restic-key`、manual backup、daily schedule、snapshot list/check、staged restore 和 promote preparation。
- M009 Phase B 已加入 Mac Admin 管理的 export/import：全量或日期范围导出、JSON manifest/metadata 权威包、Markdown preview、media payload、导入到 staged data directory，并排除 auth/session/device runtime state。
- `docs/OPERATOR-RUNBOOK.md` 已说明 repository + key file 的恢复语义，iCloud Drive 只是用户选择的文件夹，不是 app-managed cloud upload。
- 当前 promote 是 restart-safe preparation：写 `archive/pending-promote.json`，operator 停止 server、切换 env、重启。

公开前仍需要：

- 用干净数据目录演练 import/restore 后 health check、Admin UI 和 iOS sync recovery。
- 明确公开版中 `.gsd/`、历史日志和示例数据的处理策略。

### 3. 历史敏感信息扫描尚未作为发布门禁

当前 `.gitignore` 覆盖了常见运行时文件，但公开发布前不能只看工作区，还要扫描 Git history。

建议门禁：

```bash
git log --all --stat -- server/.env server/data
git grep -n "PRIVATE_MOMENTS_INITIAL_PASSWORD\\|AI_SUMMARY_API_KEY\\|sk-" $(git rev-list --all)
```

如果发现真实 secret，不能只删除当前文件，需要轮换 secret，并考虑重写历史或新建干净公开仓库。

本次轻量扫描结果：

- 当前 iOS `Info.plist` 中的个人 Tailscale exception 已移除，开发期仍依赖 `NSAllowsArbitraryLoads` 和 `NSAllowsLocalNetworking`。
- `server/.env.example` 只包含 AI API key 占位示例。
- `scripts/setup-local.sh` 只包含写入本地 password 的脚本逻辑，不包含真实 password。
- `.gsd/activity/` 历史执行日志中仍有个人 Tailscale 值的历史记录片段。公开发布前必须决定是否清理 `.gsd/`、重写历史，或从干净快照创建公开仓库。

### 4. 外部 AI provider 隐私说明不足

AI media summary 会把本地转录后的文本发送给配置的外部 API。公开发布前需要在 README 或 SECURITY 文档中明确：

- 音频和视频文件本身是否发送给第三方。
- 转录文本是否发送给第三方。
- API key 存储在哪里。
- 用户如何完全关闭 AI summary。
- provider 超时、失败、重试时会记录哪些日志。

### 5. `.gsd` 是否公开需要决策

`.gsd/` 是当前项目事实源，但可能包含内部过程、个人偏好和不适合公开的历史信息。公开前需要二选一：

- 保留 `.gsd/`：先做一次人工清理，只留下适合公开的项目事实。
- 不公开 `.gsd/`：把稳定事实沉淀到 `docs/`，并在公开仓库忽略或移除 `.gsd/`。

当前建议：公开仓库优先以 `docs/` 作为人类读者入口，`.gsd/` 是否保留延后到发布前单独审计。

## 建议保留为私有的内容

- `server/.env`
- `server/data/`
- `server/.venv/`
- `server/prisma/dev.db`
- 任何真实媒体文件、缩略图、录音、视频。
- iPhone 设备 container dump。
- 本机 Tailscale IP、Tailnet 名称、个人设备名。
- 外部 AI provider API key、base URL、日志里的请求内容。

## 开源发布材料建议

最小公开包应包含：

- `README.md`：项目是什么、适合谁、如何本地启动、如何配置 iOS。
- `LICENSE`：明确复用边界。
- `SECURITY.md`：隐私、安全、AI provider 和 secret 处理说明。
- `docs/PRD.md`
- `docs/TECH-DESIGN.md`
- `docs/OPERATOR-RUNBOOK.md`
- `docs/INTEGRATION-GUIDE.md`
- `docs/DESIGN-PRINCIPLES.md`
- `docs/RELEASE-CHECKLIST.md`

## 当前建议顺序

1. 先按 `docs/RELEASE-CHECKLIST.md` 收口 v0.1 内部候选版本。
2. 完成 backup/restore/export/import 的最终发布级验证。
3. 选择 license，并补 `SECURITY.md`。
4. 对当前工作区和 Git history 做敏感信息扫描。
5. 决定 `.gsd/` 是否公开。
6. 从当前私有仓库切一个干净 release 分支，或者新建公开仓库导入干净快照。
