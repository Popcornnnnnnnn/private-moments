# 公开版迭代说明

这个目录是 Private Moments 的公开版迭代轨道，和所有者的私有开发目录分离。

## 目录边界

- 私有开发目录：`private-moments/`
- 公开候选目录：`private-moments-open-source/`

公开候选目录来自一次干净快照，排除了：

- Git history。
- `.gsd/` 执行历史和本地 agent runtime。
- `server/.env`。
- SQLite 数据库。
- `server/data/` 媒体和日志。
- `server/.venv/`。
- `node_modules/`。
- Admin/server/iOS build 产物。
- 个人 Tailscale exception 和个人设备名默认值。

## 公开版当前目标

公开版先走 v1.0-public 收口，而不是继续混入私有开发节奏。

当前目标：

- 新用户可以通过 `npm run setup:local` 跑起 Mac server 和 Admin UI。
- iOS project 可以由 `ios/project.yml` 生成，不依赖个人 Team ID。
- 默认 bundle id 是 `dev.privatemoments.app`，发布者可以用 `PRIVATE_MOMENTS_BUNDLE_ID` 或 XcodeGen 配置自行替换。
- 文档明确说明本地数据、AI provider、secret、backup/restore 的边界。
- 公开仓库不包含任何私人数据库、媒体、设备日志、API key 或个人网络值。
- 最小数据安全命令已提供：`backup:local`、`restore:local`、`export:local`。

## 后续公开版优先级

1. 跑完整 secret scan，包括当前工作区和新公开 repo history。
2. 做一次 backup/restore/export 恢复演练。
3. 补 GitHub 发布材料：issue templates、PR template、release notes。
4. 收紧 production ATS/network 指南。
5. 决定是否提供 Docker 或 launchd 的更简化安装路径。

## 与私有开发目录同步

公开版需要吸收私有开发目录的新能力时，建议使用人工 cherry-pick 或干净快照同步，不要共享 `.git`、`.gsd`、`.env` 或 runtime data。
