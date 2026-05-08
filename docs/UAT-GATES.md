# v0.1 UAT 门禁

本文档记录 v0.1 内部候选版本前必须人工确认的真实使用路径。它和自动化测试不同：自动化验证负责防止代码退化，UAT 负责确认真实 iPhone、Mac server、网络和个人数据路径在日常使用里成立。

运行状态检查：

```bash
npm run verify:uat-gates
npm run verify:release-gates
```

`verify:uat-gates` 只汇总当前 open gate；`verify:release-gates` 会在仍有 open gate 时失败，用于 release candidate 前的硬门禁。

## 当前 Gate

| Gate | Status | Area | Required Evidence |
|---|---|---|---|
| UAT-M004-AUDIO-VIDEO | closed | Audio and Video Moments | 真实 iPhone 上录音、暂停/继续/停止、试听、发布、后台播放、短视频导入、超长视频拒绝、全屏播放、sync/upload/recovery、Storage cache clear 均通过。 |
| UAT-M005-AI-SUMMARY | closed | AI Media Summaries | fresh clear-speech audio/video 发布后，iOS 不显示 transcript/占位；Mac 生成 ready summary 后，timeline 显示 `Summary ready`，sheet 显示 v4 document summary，Regenerate/Delete/failed 保留旧摘要语义均可用。 |
| UAT-M005-AI-TITLE | closed | AI Title Auto-Insert | fresh audio 无用户标题时首次 ready summary 写入 `##` 短标题，不显示 `Edited`；已有 `#`/`##` 或关闭 `AI Title Auto-Insert` 时不写入；Regenerate 不覆盖已有标题。 |
| UAT-M006-SMART-TAGS | closed | Smart Tags | 手动主标签发布、timeline tag toggle、Detail 标签显示/单条编辑、topic alias search、topic merge/archive/restore/delete、Storage diagnostics tags、新语音 summary ready 后 AI tags sync 均通过，并确认 AI topic 优先复用已有 topic/alias 而不是创建近义重复标签。 |
| UAT-M007-LANGUAGE | closed | App Language | `System` / `English` / `简体中文` 切换后，主 App 主要 UI、日期、筛选、Settings、Tags、Summary、Detail/Edit 可读且不翻译用户内容。 |
| UAT-M008-CALENDAR | closed | Calendar Review | 真实 iPhone 上 Calendar month grid、Day Review、Month Stats、Day Review filters、Timeline day filter handoff、返回位置记忆、音频/视频提示体验成立。 |
| UAT-M009-ARCHIVE | closed | Archive / Restore / Export / Import | 真实本地服务上通过 Mac Admin 创建 backup、list/check snapshot、staged restore、promote preparation、export package、import staged data directory；确认真正切换仍走 `pending-promote.json` restart 流程。 |
| UAT-M009-SYNC-HEALTH | closed | Sync Health | iOS Settings 和 Mac Admin 能区分 server unreachable、auth failure、cursor lag、pending outbox、failed media upload、missing media、AI non-ready，并且安全动作可恢复常见状态。 |
| UAT-M010-WEEKLY-REVIEW | closed | Weekly Review | 真实最近 7 天数据生成 Review，语气是冷静观察 + 适度鼓励，不逐条过度解读；`Worth Revisiting` 低权重 anchors 能在 Review 内打开原 moment。 |
| UAT-SHARE-EXTENSION | closed | Save to Moments | Photos 多图、Safari URL/text、Files/Voice Memos 音频、视频分享都能打开主 App Composer，发布成功后 import queue 被清理；真实 provisioning/App Group 正常。 |
| UAT-M011-PINNED-MOMENTS | open | Pinned Moments | 合并/真机安装前先完成 Sync Health/outbox/recovery checkpoint；真实 iPhone 上确认 Detail `More` pin/unpin、Timeline 长按 pin/unpin、`Pinned · N` 默认折叠、1-3 条展开、超过 3 条 sheet、sheet 内 detail navigation、搜索/筛选隐藏 Pinned 且仍能找到原 moment。 |

## 验收记录

- 2026-05-07：用户确认当前 10 个 UAT gate 先全部验收通过。本次收口只记录人工验收状态，不引入功能代码变更；后续如果发现回归或新增范围，应重新打开对应 gate 或新增 gate。
- 2026-05-08：M011 Pinned Moments 已在功能 worktree 通过自动化、隔离 server smoke 和模拟器 UI/交互验证；因为本轮明确不安装真机，新增 `UAT-M011-PINNED-MOMENTS` 作为后续真实设备验收门禁。

## 关闭 Gate 的规则

关闭 gate 时必须同时更新：

- 本文档对应行的 `Status`，把 `open` 改为 `closed`。
- `docs/HANDOFF.md` 的当前工作状态或下一步。
- 对应 `.gsd/STATE.md` / `.gsd/REQUIREMENTS.md` 的验证记录。
- 最终回复里的当前会话验证证据。

不能只因为 build 或 simulator test 通过就关闭真实设备 gate。真实 iPhone UAT 可以由用户确认，也可以由 agent 在完成安装前数据安全检查后执行并记录证据。
