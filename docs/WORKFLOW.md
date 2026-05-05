# Private Moments 工作流

这份文档说明如何长期维护 Private Moments。它面向未来打开项目的维护者：需要判断一项工作该怎么计划、怎么验证、结束时要更新哪些事实和文档。

读完以后，维护者应该能判断一项工作走 quick track 还是 milestone track，并能在不丢上下文的情况下收尾。

## 文档语言

`docs/` 目录下的稳定文档以中文为主，因为它们主要给项目维护者阅读。

以下内容可以保留英文：

- 命令、环境变量、文件名、路径和代码符号。
- API route、字段名、错误码和协议术语。
- App 内既定英文 UI 文案。
- 无法自然翻译或翻译后更难理解的技术名词。

`.gsd/` 和 `AGENTS.md` 可以偏英文，因为它们主要服务 agent、工具和结构化执行流程。

## 事实源分层

Private Moments 使用两层文档：

1. `.gsd/` 是结构化事实源，记录当前项目事实、需求、决策和 milestone 状态。
2. `docs/` 是稳定的人类可读文档，解释产品、架构、操作方式、API、交接状态、设计原则和工作流。

`.gsd/` 用来保存会随项目演进而变化的执行事实。`docs/` 用来保存人以后能直接阅读和行动的说明。

## 工作轨道

默认使用轻量连续维护。只有当风险类别需要时，才升级为 milestone/slice planning。

## 分支和 Worktree 纪律

`main` 是固定版本的集成线。它用于保存已经合并、可继续验证和可继续发版的项目状态，不作为日常功能开发目录使用。

每个功能分支只承载一个边界清楚的迭代。具体开发、测试、构建、打包和真实设备安装，默认都在该功能分支对应的独立 Git worktree 中完成。不要在 `main` 工作目录里来回切换功能分支，也不要让多个 Codex thread 共享同一个工作目录做不同分支的开发。

推荐约束：

- 一个 Codex thread 固定对应一个 worktree。
- 功能开发前，从 `main` 创建或移交到独立 worktree。
- 功能 worktree 内可以提交 checkpoint、运行 server/admin/iOS build、做真实设备安装和 UAT。
- `main` worktree 只做最终合并、合并后验证、release candidate 检查和稳定服务重启。
- 功能合并并确认不再继续开发后，删除对应 worktree 和已合并分支。

Worktree 是代码工作目录隔离，不是数据隔离。数据一致性由 runtime 配置、iOS bundle/container 行为和迁移兼容性保证：

- Feature worktree 启动 Mac server 时，默认使用独立端口和独立 data directory，避免临时分支写入当前 live archive。
- 只有在明确做最终集成验证、且已经确认当前分支就是准备合入的版本时，才允许让 worktree 指向 live data。
- 从 feature worktree 安装到真实 iPhone 会更新同一个 `Moments` app bundle，并继续使用同一个 app container。安装前必须确认分支基于当前 `main`，不会降级本地 SQLite/schema、删除 app container、清空 outbox、改变 bundle id/app group，或执行破坏性迁移。
- Mac archive backup 只保护已经同步到 Mac archive 的数据。若 iPhone 可能有未同步 outbox、draft、local media cache 或 local-only 数据，真实设备安装前必须先同步确认，或复制 iPhone app container 作为安装前恢复点。
- 任何涉及 SQLite schema、sync、media storage/recovery、backup/restore、auth/security 或真实设备恢复的 worktree 安装，都必须升级到 milestone/slice planning，并在安装前准备可恢复证据，例如 Mac archive backup、export/import artifact，或 iPhone app container copy。

### Quick Track

低风险工作走 quick track，例如：

- 小的 UI 文案或布局调整。
- 文档修正。
- 在已理解模块里的轻量重构。
- 不改变数据语义的小 bug fix。
- 不影响运行时行为的构建或脚本清理。

Quick track 仍然需要验证和收尾，只是不需要完整 milestone plan。

### Milestone Track

当工作可能影响下面任一领域时，实施前必须进入 milestone/slice planning：

- sync 语义或 sync cursor 行为。
- SQLite schema migration 或数据模型兼容性。
- media 存储、上传、thumbnail 生成、cache recovery 或清理。
- backup、restore、export、migration 或数据保留策略。
- auth、device token、设备撤销或安全边界。
- 跨设备行为或冲突处理。
- 真实设备安装、启动或恢复行为。

触发条件不是工作量，而是风险类别。一个一小时的 sync cursor 修复也可能需要 milestone；一个更大的视觉 polish 反而可以留在 quick track。

## 收尾闭环

每次非平凡变更都必须有最小收尾闭环：

1. 说明改了什么。
2. 给出当前会话里的新鲜验证证据。
3. 说明已知问题、限制或下一步。
4. 更新受影响的 `.gsd` 事实源。
5. 更新受影响的人类可读文档。
6. 在功能或修复达到已验证 checkpoint 后立刻做一次 git commit，即使人工 UAT 还没完成。不要把多个已完成功能、多个 slice 或多个 milestone 的改动长期堆在未提交工作树里；commit message 要清楚说明 checkpoint 范围，剩余 UAT 写进验证记录和最终回复。

如果没有 durable docs 需要更新，要说明原因。如果验证无法完成，要说明缺少什么、为什么缺少。

## 验证分级

按影响面选择验证深度：

- Server 变更：运行相关 server build 或 typecheck，然后验证 health endpoint 或受影响 HTTP 行为。
- Admin UI 变更：运行 Admin build；如果行为变化，还要用浏览器验证受影响 UI。
- iOS 变更：至少 build iOS project。影响真实运行行为且模拟器/build 无法证明时，安装到真实设备验证。
- Sync、media recovery、storage diagnostics 或 cross-device behavior：优先真实设备安装；必要时检查 app container 或本地数据库。
- 纯文档变更：验证链接、命令和文件名是否与仓库一致。

没有当前会话里的新鲜验证证据，不要声称工作完成。

## 文档职责

每份长期文档保持单一职责：

- `PRD`：产品目的、用户故事、目标、非目标和验收层面的产品行为。
- `Technical Design`：架构、数据流、模块职责、sync 语义、存储设计和系统约束。
- `Operator Runbook`：安装、运行、排障、环境变量、smoke checks、launchd、真实设备验证和恢复流程。
- `Integration Guide`：API 用法、route 示例、sync payload、media route 和 admin route contract。
- `Handoff`：当前状态、重要修复、已知大文件和下一步。它是“下次接手先看这里”的入口。
- `Design Principles`：未来功能需要遵守的 UI / 产品设计原则。
- `Workflow`：本工作流文档。

避免把同一段操作细节复制到多个文档里。稳定信息只放在它所属的文档，其他地方链接过去。

## GSD 事实源

`.gsd/` 里的文件用于结构化项目记忆：

- `.gsd/PROJECT.md`：项目现在是什么。不要把它写成历史记录。
- `.gsd/REQUIREMENTS.md`：长期需求和验证状态。只记录会约束架构、数据、安全、sync、运维或产品行为的中等粒度需求。
- `.gsd/DECISIONS.md`：追加式决策登记。记录未来维护者会问“为什么这样做”的决定。
- `.gsd/milestones/`：高风险工作的 milestone、slice、task plan、summary 和验证证据。

Decision log 要保持低噪音。记录长期影响和非显然取舍，不记录每个 helper function 或小 UI 实现细节。

## 什么时候更新什么

当项目当前形态发生变化时，更新 `.gsd/PROJECT.md`。

当出现新的长期需求、需求状态变化、需求被验证、延期或明确排除时，更新 `.gsd/REQUIREMENTS.md`。

当选择会影响未来架构、数据语义、sync 行为、安全、存储策略、用户体验原则或工作流规则时，更新 `.gsd/DECISIONS.md`。

当下一次会话如果不读会漏掉重要当前状态、已完成修复、已知风险或下一步时，更新 `docs/HANDOFF.md`。

当 setup、runtime、verification、deployment、backup、recovery 或 troubleshooting 行为变化时，更新 `docs/OPERATOR-RUNBOOK.md`。

当架构、模块边界、数据流、持久化、sync 语义、存储或 API 设计变化时，更新 `docs/TECH-DESIGN.md`。

当产品目标、非目标、用户故事或验收预期变化时，更新 `docs/PRD.md`。

## 文档完成前的冷读检查

完成文档变更前，把它当作第一次打开项目的人来读一遍。文档应该能告诉读者下一步做什么、不要做什么，以及权威细节在哪里。
