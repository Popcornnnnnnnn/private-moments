# 开源前清理评估

评估日期：2026-05-10

当前结论：**源码仓库已经可以作为 public source snapshot 维护；仍应把它标成源码自托管候选，而不是面向普通用户的一键稳定发行版。**

这个项目已经具备个人使用闭环，但开源发布需要额外关注隐私边界、安装路径、历史敏感信息和数据安全。

## 已具备的基础

- 根目录已设置 npm workspaces，server 和 admin 可以统一安装依赖。
- `LICENSE` 已选择 MIT。
- 新增 `npm run setup:local`，用于新机器初始化、生成 Prisma client、应用数据库迁移、构建 Admin UI 和 Server。
- `server/.env.example` 使用占位配置，没有包含真实 API key。
- 新增 `docs/NETWORKING.md` 和 `.env.local.example`：公开默认只要求用户配置 `Server URL`，LAN、Tailscale/private VPN、Cloudflare Tunnel 或其他受保护 HTTPS endpoint 都只是可选网络层；个人 device name、Apple Team ID、bundle id、App Group 和 fallback URL 通过 ignored 本地配置覆盖。
- iOS 公开默认 identifiers 已迁移到 `ios/Config/Public.xcconfig`，本地 override 由 ignored 的 `ios/Config/Local.xcconfig` 承载。
- `.gitignore` 已覆盖 `server/.env`、`server/data/`、`server/.venv/`、`server/dist/`、`admin/dist/`、`ios/build*`、`ios/PrivateMoments.xcodeproj/`、`node_modules/`、`.tmp/` 等运行时或生成内容。
- 文档已经覆盖产品定位、技术设计、操作 runbook、integration guide、design principles、workflow 和 handoff。
- README 通过可重复 simulator demo fixture 维护 6 张公开截图：Timeline、Detail、Calendar、Check-ins、Settings 和 Tags。
- AI media summary 的真实 provider credential 设计为只存在 Mac server 环境变量中。
- 2026-05-10 已将当前本地整理后的仓库推到 `Popcornnnnnnnn/private-moments` 的 GitHub `main`；推送前把旧 GitHub `main` 保留为远端备份分支 `backup/github-main-before-local-refresh-20260510`。

## 剩余发布风险

### 1. Git history 敏感信息扫描仍需要发布级复核

当前 checkout 的轻量扫描已经进入 `npm run doctor:release`，但它不扫描 Git history。公开仓库已经存在后，后续 stable release 仍需要对最终公开分支和 tag 做完整 history secret scan；如果发现真实 secret，应轮换 secret，并考虑重写历史或重新发布干净快照。

### 2. 最小数据安全闭环已经有主路径，仍需最终发布级演练

项目保存的是私人 timeline、图片、音频、视频、评论和 AI summary。公开前至少需要给出明确的 backup/restore/export 路径。

当前进展：

- M009 Phase A 已加入 Mac Admin 管理的 restic backup/restore：repository config、项目管理 `.private-moments-restic-key`、manual backup、daily schedule、snapshot list/check、staged restore 和 promote preparation。
- M009 Phase B 已加入 Mac Admin 管理的 export/import：全量或日期范围导出、JSON manifest/metadata 权威包、Markdown preview、media payload、导入到 staged data directory，并排除 auth/session/device runtime state。
- `docs/OPERATOR-RUNBOOK.md` 已说明 repository + key file 的恢复语义，iCloud Drive 只是用户选择的文件夹，不是 app-managed cloud upload。
- 当前 promote 是 restart-safe preparation：写 `archive/pending-promote.json`，operator 停止 server、切换 env、重启。

公开前仍需要：

- 用干净数据目录演练 import/restore 后 health check、Admin UI 和 iOS sync recovery。
- 明确公开版中 `.gsd/`、历史日志和示例数据的处理策略。
- 运行 `npm run doctor:archive`，保留本轮 archive drill report 作为当前 checkout 的数据恢复演练证据。

建议 history scan 门禁：

```bash
git log --all --stat -- server/.env server/data
git grep -n "PRIVATE_MOMENTS_INITIAL_PASSWORD\\|AI_SUMMARY_API_KEY\\|sk-" $(git rev-list --all)
```

本次轻量扫描结果：

- 当前 iOS `Info.plist` 中的个人 Tailscale exception 已移除，开发期仍依赖 `NSAllowsArbitraryLoads` 和 `NSAllowsLocalNetworking`。
- `server/.env.example` 只包含 AI API key 占位示例。
- `scripts/setup-local.sh` 只包含写入本地 password 的脚本逻辑，不包含真实 password。
- `.gsd/milestones/` 历史文档中仍有个人设备名片段；`doctor:release` 会把它作为 warning 报出。若要发布 stable release/tag，应先清理或决定 `.gsd/` 的公开策略。
- 2026-05-10 起，当前 checkout 可用 `npm run doctor:release` 做重复扫描；它会检查 license、tracked API key 形态、个人配置片段、ignore 边界、公开 docs 和 `.gsd` release policy。它不扫描 Git history。

### 3. 外部 AI provider 隐私说明仍需更面向外部用户

AI media summary 会把本地转录后的文本发送给配置的外部 API。公开发布前需要在 README 或 SECURITY 文档中明确：

- 音频和视频文件本身是否发送给第三方。
- 转录文本是否发送给第三方。
- API key 存储在哪里。
- 用户如何完全关闭 AI summary。
- provider 超时、失败、重试时会记录哪些日志。

### 4. `.gsd` 是否公开需要稳定策略

`.gsd/` 是当前项目事实源，但可能包含内部过程、个人偏好和不适合公开的历史信息。公开前需要二选一：

- 保留 `.gsd/`：先做一次人工清理，只留下适合公开的项目事实。
- 不公开 `.gsd/`：把稳定事实沉淀到 `docs/`，并在公开仓库忽略或移除 `.gsd/`。

当前建议：公开仓库优先以 `docs/` 作为人类读者入口，`.gsd/` 默认不随公开快照发布；如果后续决定保留 `.gsd/`，必须先清理 `.gsd/milestones` 中的历史设备名、bundle id、个人 endpoint 和旧 UAT 记录。

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

1. 保持 GitHub `main` 作为 public source snapshot，README 和 docs 只承诺源码自托管路径。
2. 完成 backup/restore/export/import 的最终发布级验证。
3. 对公开分支和未来 tag 做 Git history secret scan。
4. 决定 `.gsd/` 的稳定公开策略，至少清理当前 `doctor:release` 报出的个人设备名 warning。
5. 再决定是否发布 v1.0/stable tag、GitHub Release 或面向普通用户的安装包。
