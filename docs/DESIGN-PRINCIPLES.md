# Private Moments Design Principles

## Product North Star

Moments 是一个没有观众的生活表达空间。它应该像社交一样轻松表达，像日记一样完全私密，像信息流一样可以沉浸浏览，但不把用户推向被观看、被评价、被管理或被迫写完整的压力里。

后续功能优先保护这些原则：

- **表达，而不是记录**：输入要降低表达摩擦，不鼓励复杂结构化写作。
- **默认没有观众**：不要引入公开点赞、多人评论、公开展示、社交反馈或类似压力。
- **时间是流动的**：回看体验应像回到一段生活轨迹，而不是查数据库。
- **本地优先**：数据属于用户自己，同步是能力，不是云端依赖。

## Keep the Main Timeline Quiet

当前使用体验的核心优势是界面简洁、低干扰、记录入口清楚。后续新增功能时，应优先保护这个体验。

设计约束：

- 主时间线只展示阅读和判断当前动态所必需的信息。
- 低频功能优先放进 toolbar menu、滑动操作、详情页或设置页，不常驻占用主界面。
- 新增状态标记必须克制，只在有明确价值时显示，例如已收藏动态的小星标。
- 筛选、跳转、管理类能力应服务于“快速找回内容”，不能把时间线变成后台管理界面。
- Storage 默认是诊断信息入口，只展示本地和 Mac server 的空间/同步健康状态；清理、删除、重建缓存等危险或低频操作必须后置到二级确认或后续版本，不能让 Settings 主界面变重。
- Appearance 是本机偏好，不属于同步数据。提供 `System / Light / Dark` 这种清晰、低频的 Settings 控制即可，不应占用主时间线常驻入口。
- 时间和月份提示应服务于方向感，并保持 App UI 的英文体系。优先使用 `Just now`、`2 min ago`、`Yesterday 2:40 PM` 这类人类表达；月份信息适合作为滚动时短暂出现的浮层提示，而不是常驻的大块结构标题。
- 如果一个功能让首屏变复杂，默认重新设计入口，而不是继续堆控件。

## Pinned Moments Without Timeline Clutter

置顶是少量重要 moment 的快捷入口，不是把时间线顶部改造成公告栏、任务列表或收藏夹页面。

设计约束：

- Pinned 区域只在有置顶内容时出现，并且默认折叠。
- 折叠状态只显示标题，不显示正文、图片网格、comments、summary 正文、tag 列表或管理按钮。
- 置顶不改变 moment 的发生时间，也不把原 moment 从正常时间线、Calendar 或 Day Review 中移走。
- Pin / Unpin 是低频操作，入口优先放在 Detail、context menu、swipe/menu 等位置，不给普通 timeline row 常驻增加 pin 按钮。
- 置顶标题优先来自已有正文标题或内容 fallback。第一版不要新增“置顶标题”编辑字段，避免把一个快捷入口变成第二套写作/整理系统。
- 如果以后需要排序，先评估是否真的超过少量置顶；默认用 `pinnedAt` 排序，不急着做拖拽管理。
- 当前筛选/搜索启用时，Pinned 应只显示同样匹配筛选的 pinned moments，避免顶部出现和当前上下文无关的内容。

## Check-ins Without Habit Pressure

Check-ins 是生活纹理，不是 KPI habit tracker。它可以帮助用户回看起床、睡觉、喝咖啡、吃饭、运动等时间节奏，但不能把主体验变成任务系统。

设计约束：

- Today row 的日常动作保持轻量：左侧 icon 一键打卡或打开今日 entry，中间区域进入只读 insights，右侧才是补 note、时间、照片和 Timeline 显示的低频入口。
- Time insights 只在 item 详情页展示，不在 Today row 放 mini chart，避免破坏打卡速度。
- `Time Line` 只用于一天一次且时间相对稳定的 item；一天多次或时间分散的 item 使用 `Time Heatmap` 或 `None`。
- 图表解释只展示事实分布，不生成 AI 评价、提醒、连续天数、完成率或目标压力。
- Calendar 继续承担日期回看，不因为 check-in insights 变成统计面板。

## iOS-First Operations

Mac Admin 是低频运维工具，不是长期的日常使用中心。后续新增设置、监控、诊断和安全修复动作时，默认先判断能否放在 iOS Settings 或 iOS 内的专用诊断页里。

设计约束：

- iPhone 是主要使用设备；同步健康、AI 使用量、标签管理、语言、外观、本机存储和安全 repair action 应优先在 iOS 端可见。
- Mac Admin 保留给必须依赖 Mac 文件系统或服务权限的低频动作，例如 backup repository、staged restore、promote preparation、export/import artifact 和 server logs。
- 不要因为已有 Admin UI 就把新监控默认塞到后台。只有当该能力需要 Mac 本地路径、restic、server process、文件系统 artifact 或比手机端更强的运维上下文时，才优先进入 Mac Admin。
- 如果某个能力短期先放进 Mac Admin，技术设计和 handoff 里要记录它是否应迁移到 iOS，以及迁移前不能依赖 Admin 作为唯一入口。

## Private Feed Comments

评论是主时间线的受控例外：它借用朋友圈式交互，但仍然是单用户、私密、无观众的补充表达。

设计约束：

- 评论必须聚集在主时间线，不新增内部评论管理界面。
- 入口放在该 moment 操作行右侧，使用轻量写评论图标，不复用与 `Summary` 相近的 text/bubble 图形；没有评论时不显示空状态文案。
- 默认只展示最新两条评论，长评论和多评论通过原位展开控制处理。
- 评论输入使用底部输入栏，并清楚标识当前目标，防止发错动态。
- 评论发送成功后应收起输入栏，并把时间线带到该 moment 的底部，让最新评论在主时间线里可见。
- 删除评论通过长按评论行触发居中确认框；长按期间要有按压高亮，触发时要有轻量触觉反馈，不要把删除塞进详情页或隐藏菜单。
- 评论不显示作者、点赞、回复、媒体、Markdown 渲染或每条评论同步标识。
- Advanced Sync 等诊断界面只能显示 operation type/count，不显示评论正文。

## Audio And Video In Timeline

音频和视频应该增加 feed 的沉浸感，但不能把主时间线变成复杂播放器。

设计约束：

- 视频卡片可以像社交 feed 一样在滑入主要可视区域后静音自动播放。
- 自动播放只允许一条视频处于播放状态，优先选择最接近视口中心的视频。
- 自动播放必须静音；需要声音时，用户点击进入全屏视频播放。
- 滑走视频、打开详情、打开发布页、进入图片/视频全屏或开始播放语音时，应停止时间线自动播放。
- 语音播放条保持轻量；中途暂停可保留进度，完整播放结束后回到未播放初始状态。
- 语音/视频转写不再是 iOS 本地可见流程。新发布媒体由 Mac server 在后台用本地 `mlx-whisper` 生成内部 transcript，再调用外部 summary API 生成 AI summary。transcript 只作为服务端内部输入和质量调试 metadata，不成为 timeline 正文或 sheet fallback。
- AI summary 是后台生成的安静工具，不是时间线里的新内容类型。主时间线只在已有 ready summary 时显示 `Summary ready`；没有结果、失败或处理中时不显示占位。底部弹层只显示已生成的 AI 摘要。不写入评论，不把摘要正文替换进原动态，也不让 AI 像公开观众一样主动评价用户内容。唯一例外是新语音动态可以把首次 ready summary 的标题写成正文顶部 `##` 标题，前提是用户还没有写过标题。
- Summary sheet 可以比 timeline 更有信息密度，但仍应是阅读工具而不是编辑器。新摘要用 native document blocks 渲染为标题、一句话总结、折叠详情、列表和 `AI suggested` callout；不要把 arbitrary Markdown 当作源格式，也不要把推断建议伪装成事实。

## Smart Tags Without Tag Wall

标签的目标是降低未来找回内容的成本，不是要求用户每次发布都做分类。

设计约束：

- 主标签保持少量稳定，用于表达类型；主题标签才承载具体内容。
- Composer 只允许可选选择一个主标签，不把主题标签编辑放进发布主路径。
- 主时间线和 Day Review 最多显示一个主标签；Moment Detail 只在标签显示开启时展示完整标签和单条编辑入口。Detail 标签 badge 必须完整展示标签名，允许换行，不用省略号；normal read mode 不显示 `Manual` / `AI` 来源文字。`Show Tags in Timeline` 关闭后，标签系统仍然正常参与搜索、筛选、Settings 管理、AI 自动标签和同步，但阅读界面不再露出标签操作。
- 主题标签不在时间线常驻展示，避免每条 moment 变成一排 chips。
- 标签管理属于 Settings > Tags，不属于 Mac Admin 内容管理台，也不应该成为主时间线的常驻面板。
- 默认主标签不可重命名、归档或删除；自定义标签可以通过 archive 隐藏，archived 标签可以永久删除以释放误建的名称；主题标签额外支持 alias 和 merge，用于清理 AI 或手动产生的词汇漂移。Topic 与 Archived 清理可以批量执行，但入口留在 Settings > Tags 的编辑模式里，不进入主时间线。
- 主标签颜色选择以预设色板为主，默认保留少量低饱和颜色，同时提供更醒目的高饱和标准色；也保留 HEX 自定义输入，给需要精确颜色的用户使用。批量管理只允许统一修改 primary tag 颜色，不做批量重命名。
- AI 标签只跟随 audio summary 的首次 ready 结果安静应用，不弹确认窗口，不新增 `Tagging...` 状态，也不在 summary regenerate 时反复覆盖用户整理过的标签。短音频的 topic tag 要克制，默认偏向一个具体主题，只有明显多主题且高置信度时才保留多个。AI topic 应优先复用已有 active topic/alias，避免把同一个概念拆成多个近义标签。

编辑媒体时也要尊重 media kind。图片可以使用可排序缩略图网格；语音和视频应显示为对应的播放/预览控件，不能落入图片缩略图占位，也不能在不确认的情况下和图片混合。

## Time Navigation Without Database Feel

内容变多以后，Moments 需要更好的时间导航，但导航目标是“回到某段生活”，不是管理 archive。

设计约束：

- 主体验继续以 timeline/feed 为主。
- Calendar 可以作为 Timeline 的底部 review tab，但不承担发布、编辑或归档管理。它可以提供轻量 Month Stats 辅助回看，但不能压过“回到某一天”的主体验。
- Timeline 不保留并行的 toolbar 日期跳转入口；日期回看统一从 Calendar 进入。
- Calendar 月份连续可浏览，空月份显示普通空日历格，避免把空状态做成 onboarding 或发布提示。
- 点击有内容的日期先进入 Day Review；`Timeline` 作为 Day Review 内的二级动作，用可清除 day filter chip 表达日期上下文。
- 日期格可以显示轻量数量标签；动态 heatmap、数量和少量媒体图标共同触发记忆，但视觉上仍应低饱和、安静，不能做成 KPI 面板。
- 日期文案偏生活感，例如 `April 2026`、`Today`、`昨天`；Day Review 使用 24 小时制和轻分隔表达一天内部节奏，不使用厚重卡片或大块灰底。

## Lightweight Input, Not Markdown Editor

输入体验可以帮助用户顺手表达，但不能把 Moments 变成写作工具。

2026-05-08 后续方向：更强 Markdown 编辑可以进入下一轮产品设计，但不能默认等同于完整 Markdown 编辑器。实现前必须明确哪一小组语法确实降低表达摩擦，以及它们如何在 Composer、Edit、Timeline、Detail 和 Day Review 中保持一致。

设计约束：

- 保存格式保持 Markdown source `String`，不引入富文本数据库模型。
- Composer/Edit 可以提供很轻的 Typora/Obsidian-like Markdown 编辑层，只支持行首 `# ` 和 `## `。标题行持续显示为标题字号，光标进入标题行时临时露出 `#` / `##`。
- 键盘上方可以提供紧凑的 H1、H2 输入辅助；这些按钮只切换当前行前缀，不变成完整编辑器工具栏，也不额外放低价值的完成按钮。
- Markdown 编辑渲染必须尊重 iOS 输入法 marked text。中文、日文、韩文等输入法正在组词时，不要重写 `UITextView.textStorage` 或替换正文，否则会打断候选词并留下拼音/字母。
- Timeline/Detail/Day Review 对保存文本做同一组有限渲染：行首 `# ` / `## ` 显示为标题；Timeline 标题尺寸比 Detail/Edit 更克制。
- 评论不进入标题渲染。
- 可以支持轻量列表延续：`- `、`• `、`1. `。
- Numbered list 可以自动递增：`1. ` 回车后生成 `2. `。
- 空列表项再次回车退出列表。
- 不支持 bold、quote、link preview、Markdown 图片内嵌或完整 Markdown 预览区。真实剪贴板图片仍进入下方 media grid，Markdown 图片语法保持正文文本。
- 如果未来扩展 Markdown，默认仍保持：评论纯文本、媒体继续走 media grid、保存层仍是 Markdown source `String`、不引入富文本数据库模型、不牺牲中文输入法 marked text 稳定性、不让 Timeline 变成长文排版页面。
