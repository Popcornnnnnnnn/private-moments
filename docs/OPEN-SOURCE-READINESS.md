# 开源前清理评估

评估日期：2026-05-02

当前结论：**已创建独立公开候选目录，但还不建议立即推到公开 GitHub 仓库。**

这个项目已经具备个人使用闭环，但开源发布需要额外关注隐私边界、安装路径、历史敏感信息和数据安全。

公开候选目录：

```text
private-moments-open-source/
```

私有开发目录：

```text
private-moments/
```

## 已具备的基础

- 根目录已设置 npm workspaces，server 和 admin 可以统一安装依赖。
- 新增 `npm run setup:local`，用于新机器初始化、生成 Prisma client、应用数据库迁移、构建 Admin UI 和 Server。
- `server/.env.example` 使用占位配置，没有包含真实 API key。
- `.gitignore` 已覆盖 `server/.env`、`server/data/`、`server/.venv/`、`server/dist/`、`admin/dist/`、`ios/build*`、`ios/PrivateMoments.xcodeproj/`、`node_modules/`、`.tmp/` 等运行时或生成内容。
- 文档已经覆盖产品定位、技术设计、操作 runbook、integration guide、design principles、workflow 和 handoff。
- AI media summary 的真实 provider credential 设计为只存在 Mac server 环境变量中。
- 公开候选目录已排除 `.git`、`.gsd/`、`server/.env`、`server/data/`、`server/.venv/`、`node_modules/` 和 build 产物。
- 公开候选目录已使用 `MIT` license。
- iOS 默认 bundle id 已换成 `dev.privatemoments.app`，且 XcodeGen 配置不再包含个人 Team ID。

## Release-blocking 项

### 1. License

状态：已处理。公开候选目录使用 `MIT`。

### 2. 最小数据安全闭环

项目保存的是私人 timeline、图片、音频、视频、评论和 AI summary。公开前至少需要给出明确的 backup/restore/export 路径。

状态：已补最小脚本，仍需要做一次恢复演练。

最低要求：

- 一条命令备份 SQLite 数据库和 `server/data/`：`npm run backup:local`。
- 一条文档化流程恢复到新机器：`npm run restore:local -- <archive> --yes`。
- 一条命令导出 JSON metadata：`npm run export:local`。
- 明确备份文件不会自动上传到第三方：已写入 README 和 runbook。
- 恢复后可以通过 health check 和 Admin UI 验证。

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
- 私有开发目录的 `.gsd/activity/` 历史执行日志中仍有个人 Tailscale 值的历史记录片段。公开发布使用当前独立候选目录，不复用私有开发目录的 Git history 或 `.gsd/`。

### 4. 外部 AI provider 隐私说明不足

AI media summary 会把本地转录后的文本发送给配置的外部 API。公开发布前需要在 README 或 SECURITY 文档中明确：

- 音频和视频文件本身是否发送给第三方。
- 转录文本是否发送给第三方。
- API key 存储在哪里。
- 用户如何完全关闭 AI summary。
- provider 超时、失败、重试时会记录哪些日志。

### 5. `.gsd` 是否公开

状态：公开候选目录暂不公开 `.gsd/`。

`.gsd/` 是私有开发目录的项目事实源，但可能包含内部过程、个人偏好和不适合公开的历史信息。公开前需要二选一：

- 保留 `.gsd/`：先做一次人工清理，只留下适合公开的项目事实。
- 不公开 `.gsd/`：把稳定事实沉淀到 `docs/`，并在公开仓库忽略或移除 `.gsd/`。

当前公开候选版本采用第一阶段策略：公开仓库优先以 `docs/` 作为人类读者入口，`.gsd/` 不进入公开快照。

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
- `docs/PUBLIC-RELEASE-TRACK.md`
- `CONTRIBUTING.md`

## 当前建议顺序

1. 先按 `docs/RELEASE-CHECKLIST.md` 收口公开候选版本。
2. 对公开候选目录初始化 Git，并做敏感信息扫描。
3. 做一次 backup/restore/export 演练。
4. 生成第一版 release notes。
5. 推到公开 GitHub 仓库前再跑一次全量检查。

## 当前验证记录

2026-05-02 已完成：

- `npm run setup:local -- --skip-build`：通过；Prisma schema engine 在干净 SQLite 上返回空错误时，setup 使用 SQLite migration fallback 完成初始化。
- `npm run verify:server`：通过。
- `npm run backup:local`：通过，生成本地 runtime archive。
- `npm run export:local`：通过，生成 JSON metadata export。
- `npm run restore:local -- <archive> --yes`：通过，恢复后 SQLite 有 9 张表。
- `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`：通过。
- `PORT=3211 npm run server:start` 后 `curl http://127.0.0.1:3211/api/v1/health`：通过，返回 `schemaVersion: 8`。
- 敏感模式扫描只命中 `.env.example` 的占位 API key 注释和 setup 脚本的本地 password 替换逻辑；未发现真实 API key、个人设备名、个人 bundle id、个人 Tailscale IP 或 `.gsd` 历史。
