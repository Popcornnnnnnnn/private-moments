# Private Moments PRD

## 0. 项目宗旨

Moments 是一个没有观众的生活表达空间。

它是一个个人时间线应用，体验类似发朋友圈，但所有内容默认只属于你自己。没有公开点赞、多人评论或被观看的压力；评论能力只作为单用户、私密的补充表达，仍然不引入真实观众。写一句话，放几张照片，录一段语音，放一段短视频，补一句评论，记录当下，然后继续生活。

你可以像刷 feed 一样回看过去，而不是像查数据库一样翻记录。

现有工具往往走向两个极端：要么太社交，总是在被看；要么太沉重，像在写日记。Moments 试图在中间找到一种更自然的方式：像社交一样轻松表达，像日记一样完全私密，像信息流一样可以沉浸浏览。

核心理念：

- **表达，而不是记录**：不需要写完整，只需要说一句。
- **默认没有观众**：内容不是为了被别人看到。
- **时间是流动的**：不是列表，而是一段持续的生活轨迹。
- **本地优先**：数据属于你自己，可同步但不依赖云端。

## 1. 产品概述

Private Moments 是一个单用户、私密、自托管的生活记录产品。它的核心体验类似私人版朋友圈：用户可以在 iPhone 上随手发布文字、图片、语音或短视频，内容先稳定保存在本机，即使离线也不丢；当 iPhone 通过用户配置的 Server URL 连回 Mac 后，内容自动同步到 Mac 服务端作为长期归档源。这个 URL 可以来自 LAN、Tailscale/private VPN、Cloudflare Tunnel 或其他受保护 HTTPS endpoint。

第一版不做公开社交、不做好友关系、不做多人账号体系。产品重点是低摩擦记录、可靠离线保存、私有归档和可控备份。

## 2. 目标用户

第一目标用户是项目作者本人：

- 使用 iPhone 作为主要记录入口。
- 使用自己的 Mac 作为服务器和后台管理端。
- 希望内容不依赖第三方社交平台。
- 希望外出时也能通过自己配置的受保护 Server URL 连回 Mac。
- 后续可能开源给其他个人自托管用户。

## 3. 产品目标

- 在 iPhone 上快速发布文字、图片、语音和短视频。
- 支持从系统 Share Sheet 把照片、视频、音频、网页链接或文本发送到 Moments，并继续在发布页补充文字、调整图片顺序或修改发生时间。
- 支持通过 Share Sheet 保存截图、照片和微信/网页文章链接；文章类内容以轻量链接卡片回看，点击时尽量打开原始链接或对应 App。
- 支持离线创建内容，本地可靠保存。
- 网络恢复且 Mac 可达后，可自动同步到 Mac；用户也可以在 Settings 里关闭 `Automatic Sync`，把 iPhone 临时变成严格本地模式，只在手动 `Sync Now` 时联网。
- Mac 作为最终归档源，保存数据库和媒体文件。
- Mac Admin 支持 restic-backed Archive backup/restore，包含手动备份、每日定时备份、snapshot check、恢复到新目录和 promote preparation。
- 支持时间线、月份归档和文本搜索；搜索覆盖动态正文、评论，并兼容历史语音/视频转写 metadata。
- 支持独立 `Check-ins` 入口，用于每天运动、吃饭、按时起床、健康饮食等重复生活活动；Today 左侧 icon 一键打卡，单条记录可决定是否显示到 Timeline，部分 item 可打开只读时间趋势或可探索的时间热力图。
- 支持在主时间线下直接创建、展开、折叠、搜索和删除单用户私密评论。
- 支持置顶少量重要 moments，在无筛选时间线顶部以默认折叠的 `Pinned · N` 入口快速回到原动态；置顶项仍保留在原时间线位置，并用轻量 pin 图标提示状态，它们的原发生时间仍用于 Calendar、Day Review、搜索/筛选和 review。
- 支持 Mac server 对已上传语音/视频自动生成 AI 摘要，辅助回看较长语音备忘录或视频记录。
- 支持 AI 每周回顾：用户可在 Calendar 的 Reviews 入口手动生成最近 7 天的 Weekly Review；也可在 Settings 中打开默认关闭的每周日晚上自动生成。Weekly Review 默认不通知、不发布到 Timeline，只作为可回看的 generated review artifact。
- 支持收藏、筛选、月份快速跳转和完整图片查看。
- 支持编辑文字、发生时间、图片新增/删除和拖拽重排。
- 支持在 pending/partial/failed/synced 状态下继续编辑 moment；本机最新状态优先，后续同步负责与 Mac 对齐。
- 支持在详情页快速复制正文 Markdown 源文本。
- 支持删除，并采用软删除 + 30 天后永久清理。
- Mac 后台提供运维管理能力，包括设备、服务状态、存储、同步状态和日志。
- iOS 设置页提供只读空间诊断，显示本机缓存、同步健康状态、安全修复动作，以及 Mac 在线时的服务端存储概览。
- 数据目录清晰，便于 Time Machine 或其他外部工具备份。

## 3.1 设计原则

主时间线必须保持简洁、低干扰。新增筛选、跳转、整理和管理能力时，优先放进 toolbar menu、滑动操作、详情页或设置页；不要为了加功能把主界面堆满控件。详细原则见 `docs/DESIGN-PRINCIPLES.md`。

内容管理能力必须服务于“回到某段生活”，而不是把 Moments 变成 archive/database。输入能力必须服务于“顺手表达”，而不是把 Moments 变成 Markdown editor 或写作工具。

## 4. 非目标项

MVP 不包含：

- 好友关系、关注、多人发布或公开社交。
- 多人评论、可见作者身份、回复楼层、点赞、提及、评论媒体或互动通知。
- Live Photo、RAW 文件处理、视频 OCR、公开分享或多人互动。
- 推送通知、每日提醒、纪念日提醒。
- 打卡提醒、连续打卡、遗漏统计、完成率、目标 KPI 或任务系统。
- 复杂标签、心情系统、OCR、AI 搜图、AI 自动评论、AI 人格或自动评测。
- 可见历史版本、复杂冲突 UI 或跨设备编辑合并工具。
- 完整回收站 UI。
- 应用内一键 zip 备份导出；v0.1 采用 Mac Admin + restic snapshot 作为恢复主路径。
- 端到端加密或应用级数据加密。
- App Store/TestFlight 分发。
- 多用户权限系统。

## 5. 平台与使用方式

### iOS

iOS App 是主入口，使用 Swift + SwiftUI 开发。用户通过 iPhone 发布、浏览、搜索、归档查看和删除内容。

第一版通过 Xcode 直接安装到自己的 iPhone，不考虑 App Store 分发。

### Mac

Mac 是服务端和后台管理端。服务端登录后自动启动，提供 API、同步、文件存储和后台 Web UI。

Mac 通过用户配置的 Server URL 被 iPhone 访问；如果使用公网 tunnel，该 endpoint 应只暴露 iOS 同步所需 API，不开放完整 Admin UI。

## 6. 核心用户故事

### 发布内容

作为用户，我希望在 iPhone 上发布一条包含文字、图片、语音或短视频的日常表达，这样我可以像发朋友圈一样轻松保存生活片段，但不需要面对任何观众。

验收标准：

- 可以输入文字。
- 可以从相册多选图片。
- 可以直接拍照。
- 可以从相册选择短视频。
- 可以在发布页录制一段语音。
- 每条动态最多 9 张图片。
- 每条动态只允许一种媒体类型：最多 9 张图片，或 1 段视频，或 1 段语音。
- 发布时默认使用当前时间。
- 可以手动修改日期时间。
- 发布成功后内容立即出现在本地时间线。
- 正文保存为 Markdown source `String`，但发布页和详情编辑页提供轻量富文本编辑体验：只支持 H1 和 H2；标题行在光标进入时临时显示 `#` / `##`。
- 键盘上方只提供紧凑的 H1、H2 输入辅助；按钮切换当前行格式，且中文等输入法组词期间不能被 Markdown 渲染打断。
- Timeline、Detail 和 Day Review 统一渲染行首 `# ` 和 `## `；普通 `- ` / `• ` / numbered list 只做 plain-text continuation，不做 Markdown bullet 渲染。Timeline 标题尺寸更克制。
- 粘贴真实剪贴板图片时进入下方 media grid，不解析 Markdown 图片语法；不支持 bold、quote 或 link preview。
- 后续可以重新讨论更强 Markdown 编辑，但必须先明确支持语法、输入控件、阅读渲染和 IME 稳定性边界；在决策前不把 Moments 扩展成完整写作工具。

### 从其他 App 保存到 Moments

作为用户，我希望在 Photos、Files、Voice Memos、Safari 或其他 App 里通过系统分享菜单选择 `Save to Moments`，这样我不需要先打开 Moments 再重新选择内容。

验收标准：

- Share Sheet 中出现 `Save to Moments` extension。
- 支持最多 9 张图片，导入后进入现有发布页，并可继续补文字、修改发生时间和调整图片顺序。
- 支持 1 段视频，导入后由主 App 继续复用现有视频压缩、poster 生成、发布和同步逻辑。
- 支持 1 个音频文件，导入后由主 App 继续复用现有语音发布、播放、同步和 AI summary 生成逻辑。
- 支持网页 URL、纯文本和用户在 share extension 内补充的文字，进入发布页后作为 plain text 草稿。
- Share Extension 只负责接收系统分享内容、复制到 App Group import queue 和唤起主 App；不直接写主 SQLite、不压缩视频、不执行同步、不调用 Mac server。
- 如果用户不完成发布，内容仍然停留在主 App 发布页草稿流程，不应产生已发布 moment。

### 离线记录

作为用户，我希望没网或 Mac 不在线时也能发布，这样记录不会被网络状态打断。

验收标准：

- 离线时可以创建文字、图片、语音或短视频内容。
- 内容保存在 iPhone 本地数据库和文件目录中。
- App 重启后内容仍可见。
- 内容标记为待同步状态。

### 自动同步

作为用户，我希望 iPhone 连回 Mac 后自动同步，这样我不需要手动维护上传流程。

验收标准：

- App 打开后自动尝试同步。
- 切到后台或锁屏后尽量继续传完当前任务。
- 文字/帖子可以先同步。
- 图片逐张上传；语音、视频和视频 poster 作为 media 上传，失败后自动重试。
- 帖子可显示部分同步状态。
- 每条内容显示小状态：待同步、部分同步、已同步、失败。
- 设置中提供同步详情页，显示队列、失败原因和重试入口。
- 设置中提供 Storage 诊断页，显示本机缓存、待同步/失败数量，并在 Mac 在线时显示服务端存储占用。

### 时间线与归档

作为用户，我希望按时间回看记录，这样可以像刷 feed 一样回到某段生活，而不是像查数据库一样翻记录。

验收标准：

- 首页支持时间线浏览，按发生时间倒序。
- 底部主入口为 `Timeline` 和 `Calendar`；Settings 仍是低频 toolbar 设置入口。
- 时间标签跟随 App Language，并保持生活化表达：英文使用 `Just now`、`2 min ago`、`Yesterday 2:40 PM`，中文使用 `刚刚`、`2分钟前`、`昨天 14:40` 等。
- 月份信息作为滚动时短暂出现的浮层提示，不作为常驻的大块结构标题。
- 支持搜索、筛选、收藏筛选、图片筛选、待同步筛选。
- Calendar 默认显示当前月份，可以通过左右箭头或横向滑动切换连续月份；空月份显示普通空日历格，不显示统计说明。
- Calendar 用低饱和动态热力色表达每天 moment 数量密度；忙碌月份按当月最高发布日做相对分级，避免 10-20+ 条的日期全部看起来一样。日期格可以显示轻量数量标签，并最多显示两个媒体类型小图标。
- Calendar 可独立按媒体类型、收藏和评论筛选，不继承 Timeline 的搜索/筛选状态；筛选影响月份网格、可点击状态和月度统计，不把 Day Review 变成筛选后的残缺一天。
- Calendar navigation bar 右上角提供轻量 `Month Stats` 入口，展示当月总数、活跃天数、活跃日均、最多的一天、每日柱状节奏和媒体/收藏/评论组成；它是回看辅助，不是主时间线 dashboard。Month Stats 通过下滑关闭，不需要单独 `Close` 按钮；每日柱状条和最多的一天可直接进入对应 Day Review，内容组成行可作为回到 Calendar 的轻筛选入口。
- 点击有内容的日期会进入 Calendar 内的完整 `Day Review`，展示日期、星期、当天 moment 总数、媒体构成和无卡片日内时间轴。Day Review 会记住每个日期上次浏览到的 moment，行内可跟随 `Show Tags in Timeline` 显示主标签，正文支持轻量 `#` / `##` 渲染，图片统一显示小缩略图网格，音频可行内播放并显示轻量 summary 状态，视频只显示类型/时长提示。右上角 `Timeline` 是二级入口，点击后才切回 Timeline 并显示可清除的 day filter chip。
- Day Review 内部可用轻量横向 chips 多选过滤当天内容：Photos、Audio、Video、Favorites、Comments 是 OR 关系，点已选 chip 可取消，点 All 清空筛选。Summary 不作为独立筛选项；时间列使用 24 小时制，并用很轻的 Morning/Afternoon/Evening/Late Night 分隔让一天更有节奏。当天 check-ins 会先以紧凑 rhythm strip 呈现一眼可扫的发生顺序，再进入完整混合时间轴。
- Timeline 不再保留并行的 toolbar 日期跳转菜单；日期回看统一从 Calendar 进入。
- 新功能入口必须保持克制，不破坏主时间线的简洁感。

### 打卡

作为用户，我希望有一个和 Timeline、Calendar 并列的 `Check-ins` 界面，用来快速记录吃饭、运动、起床、健康饮食等重复生活活动，这样这类高频小事可以形成独立回看线索，而不必每次都作为普通 moment 写进主时间线。

验收标准：

- 底部主入口为 `Timeline`、`Calendar`、`Check-ins`；默认启动界面仍然是 `Timeline`。
- `Check-ins` 默认显示 `Today`；可以在同一界面切到 `History`，查看最近一周、一个月和按 item 的概况。
- 点击 Today 中某个 check-in item 左侧 icon 会立即打卡，不弹出必填表单；已经完成的一天一次 item，左侧 icon 打开今日 entry。
- Today row 中间 item 区域打开只读 item insights/trends 页；右侧独立入口添加 note、发生时间、照片和 `Show in Timeline` 开关。默认打卡可以什么内容都没有。
- 新建 item 时可以选择一天一次或一天多次，设置名称、通过精选选择器或高级输入设置 SF Symbol 图标、HEX 或预设高对比度颜色、活跃星期、默认是否显示到 Timeline，以及可选 `Time visualization`。一天一次 item 还可以设置 `Daily reset`，默认 00:00；睡觉这类跨午夜语义可以设为 12:00，避免凌晨和当晚记录被自然日挤在一起。
- `Time visualization` 默认 `None`。`Time Line` 只用于一天一次且发生时间相对稳定的 item，展示最近 30 个 item day 的发生时间，缺失日期断线，跨午夜按连续晚间区间处理，并支持点按/拖动查看真实发生日期时间。`Time Heatmap` 用 1 小时 bucket 展示最近 30 天发生时间分布，支持一天多次记录，也支持选择 bucket 查看对应记录并进入 entry detail。
- 每条 check-in entry 的 `Show in Timeline` 与 entry 是否存在相互独立；即使不显示到 Timeline，仍然进入 Check-ins History、Calendar heatmap、Day Review 和 Month Stats。
- Timeline 只显示 `Show in Timeline` 打开的 check-in entry，并使用紧凑 check-in row，不提供 favorite、pin 或 comments。
- Calendar heatmap、Day Review 和 Month Stats 把 check-ins 作为生活 activity 计入，并区分普通 moments 和 check-ins；带照片的 check-ins 也计入 Photos 相关过滤和回看。
- Check-ins History 支持按 item 过滤，例如只看 `Meal` 的历史记录。
- Check-ins 可以关联一个 secondary tag，但默认不使用任何 tag；入口应隐藏、低频，不走 AI 自动打 tag。
- Check-ins 不做语音转写、AI summary、OCR、提醒、streak、遗漏统计、预设模板或 Mac Admin 管理；当前媒体只启用拍照/图片，audio/video 入口可以预留但不启用。
- 进入 entry detail 后可以修改 note、照片、发生时间、Timeline 显示开关，或取消打卡。

### 置顶动态

作为用户，我希望可以置顶几条重要 moments，这样我能从时间线顶部快速回到它们，但平时不会让主时间线变成一个管理面板。

验收标准：

- 时间线顶部只在没有搜索、日期、Tag、Favorite、评论、内容类型、待同步等筛选时显示 `Pinned` 区域。
- `Pinned` 默认折叠，只显示一个 `Pinned · N` 汇总行。
- 当置顶数量为 1-3 条时，点击汇总行可展开/收起最多 3 条单行标题；展开/收起状态保存在本机，不参与同步。
- 当置顶数量超过 3 条时，点击汇总行打开底部 sheet，sheet 内显示完整置顶标题列表。
- 置顶 moment 的标题优先使用正文里的 `#` / `##` 标题；没有标题时使用第一条正文、AI summary title 或媒体/日期 fallback。
- 置顶标题行显示标题和很轻的发生日期辅助信息，不显示正文、媒体、评论、Tag 或完整预览。
- 点击置顶标题打开原 moment detail；从置顶 sheet 进入时，detail 在 sheet 内部 navigation stack 中打开，并保留完整详情能力。
- 已置顶 moment 仍按原发生时间保留在普通 Timeline；Calendar、Day Review、搜索、筛选和 Weekly Review 不因为置顶而改变发生时间或统计。
- 当已置顶 moment 作为普通 Timeline row 出现时，该 row 显示轻量 pin 图标，提示它已经被置顶。
- Pin / Unpin 入口放在 Moment Detail 的 `More` 菜单、Timeline row 长按菜单和置顶 sheet 行 context menu，不在每条时间线 row 常驻增加按钮，也不占用现有 Favorite 左滑操作。
- Pin 状态应该随同步恢复，离线、pending、failed、partial 或 synced moment 都可以本地 pin/unpin，后续在 Mac 可达时同步。
- Pin 和 Favorite 相互独立；pin/unpin 不改变 favorite，favorite/unfavorite 不改变 pin。
- 删除 moment 后它直接从 Pinned 区域消失，不需要额外取消置顶操作。
- 第一个版本不支持自定义置顶标题、手动拖拽排序、Pinned-only 筛选、置顶评论、置顶 review、Calendar/Day Review/Weekly Review 置顶入口或 Admin 侧管理。

### 评论动态

作为用户，我希望能像微信朋友圈一样在主时间线点评论按钮，然后在底部输入框给某条动态补一句话，这样后续想法也能自然留在同一段生活下面，而不需要进入内部详情页。

验收标准：

- 每条动态在主时间线都有轻量评论按钮。
- 点评论按钮后，底部出现输入框并聚焦键盘，输入框显示当前评论目标摘要。
- 评论是 plain text 多行文本，最多 500 字符；Return 换行，`Send` 发送。
- 新评论本地立即显示在对应动态下，不等待同步完成。
- 发送成功后收起输入框，并把主时间线带到该 moment 底部，让最新评论可见。
- 默认只预览最新两条评论，并按旧到新显示；可在原位 `View all N comments` 和 `Show less`。
- 长按某条评论后显示居中确认提示 `Delete comment?`，确认后只删除评论，不删除动态。
- 评论不显示作者、点赞、回复、媒体、Markdown 渲染、编辑入口或每条评论的同步状态。
- 搜索在现有筛选之后同时匹配动态正文和评论文本；命中评论时应让匹配评论在预览中可见。

### 搜索

作为用户，我希望能搜索文字内容，这样我可以快速找到过去的记录。

验收标准：

- iPhone 本地搜索已同步的文本元数据。
- 历史语音/视频转写 metadata 如果存在，可以作为兼容文本元数据参与搜索；新发布语音/视频不依赖 iOS 本机转写。
- 已同步的 AI summary generated metadata 参与 iPhone 本地搜索，但 summary 正文仍不直接展开在 timeline row 内。
- iPhone 本地搜索支持轻量宽松匹配：大小写、空格和标点不敏感，多关键词 AND，英文轻量 typo 容错，中文按子串匹配；不做拼音、OCR 或语义搜索。
- Timeline 可组合筛选内容类型、收藏、评论、待同步、标签；有搜索词时可再按命中来源筛选，并显示 active filter chips 和 `Clear`。Calendar 日期点击先进入 Day Review；只有在 Day Review 内点击 `Timeline` 后，才会在 Timeline 添加一个可清除的 day filter chip。
- 搜索和筛选状态不跨 App 重启持久化。
- 离线时可搜索本地已有文本。
- Mac 后台也提供服务端搜索；当前模糊搜索和命中来源筛选只在 iPhone 本地 Timeline 生效。
- MVP 不做图片 OCR、视频 OCR、AI 搜图或模糊语义搜索。

### 标签

作为用户，我希望给 moment 添加少量稳定标签和可增长的主题标签，这样后续可以用很低成本找回某类生活记录。

验收标准：

- 所有 moment 类型都支持手动标签：纯文字、图片、视频、语音。
- 主标签用于表达类型，默认预设为 `日记`、`想法`、`学习整理`、`情绪`、`碎碎念`、`复盘`。
- 副标签/主题标签用于具体内容，例如 `大语言模型`、`面试`、`康复训练`，可以动态新增。
- Composer 只提供可选主标签，不要求发布时必须选择标签；主题标签通过详情页的单条标签编辑入口（仅在标签显示开启时）和 Settings 中维护。
- 主时间线、Day Review 和 Moment Detail 最多只显示一个主标签或完整标签信息，并可通过 Settings > Feature Modules > `Show Tags in Timeline` 隐藏；隐藏后 Detail 不再显示 Tags 或提供单条标签编辑，标签数据、搜索、筛选、Settings 管理和 AI 自动标签继续工作。
- Settings > Feature Modules 还提供 `AI Title Auto-Insert`，默认打开；关闭后只影响未来新语音 summary 的标题写回，不移除已插入标题。
- 主时间线不再显示成功态 `synced` badge；只保留需要注意的异常同步状态。
- Timeline search 可以命中主标签、主题标签和 alias，并把命中来源显示为 tag。
- Filter 菜单可以按主标签和主题标签筛选，并和内容类型、收藏、评论、待同步等条件组合。
- Settings > Tags 可以查看标签 usage count、新增自定义标签、重命名/归档/恢复 topic、批量归档/合并 Topic、批量恢复/永久删除 Archived、管理 alias，并用预设色板或 HEX 输入自定义主标签颜色；Edit 模式支持批量选择 primary tags 后统一改色。默认主标签不可重命名、归档或删除。
- 新语音 moment 在首次 AI summary ready 时可以自动获得一个主标签和保守数量的主题标签；短音频优先只生成一个主题标签，只有明显多主题时才保留多个。视频、图片、文字不做 AI 自动标签，历史语音不回填，summary regenerate 不重新打标签。
- 默认主标签在 App Language 为英文时显示为 `Diary`、`Thoughts`、`Study`、`Mood`、`Random`、`Review`，在中文时显示为原中文名；这是显示层本地化，不创建新的 synced tag。默认主标签搜索/筛选可同时匹配中英文名称。

### 语言偏好

作为用户，我希望可以在英文和中文界面之间切换，同时不影响我自己的内容和 AI 生成内容语言，这样这个 App 可以适配不同语言习惯。

验收标准：

- Settings 提供 App Language：`System`、`English`、`简体中文`。
- 新安装默认跟随系统；已有私人安装默认保持 English，避免现有使用体验突然变化。
- App Language 存在本机 `UserDefaults`，立即生效，不同步到 Mac server。
- App Language 影响 iOS 主 App 的按钮、菜单、设置、搜索/筛选、标签显示、评论 UI、弹窗、时间标签和 Calendar 日期文案。
- App Language 不翻译用户正文、评论、自定义标签、主题标签、alias、历史内容或 AI summary 正文。
- Settings 提供独立的 AI Language：`Auto`、`Chinese`、`English`。默认 `Auto` 跟随语音/视频输入的主导语言，中文语音里夹杂英文术语时仍应生成中文 summary/title。
- AI Language 只影响新生成或重新生成的 AI summary/title，不改变 App UI 语言，也不作为跨设备同步偏好。

### AI 摘要

作为用户，我希望较长语音备忘录或视频记录在同步到 Mac 后能生成一份清晰摘要，这样我回看时可以先读结构化重点，再决定是否重新听完整内容。

验收标准：

- 主时间线默认只在 ready summary 存在时显示 `Summary ready`，没有结果时不显示占位；手动重新生成期间，该入口可临时显示 `Regenerating`，失败后显示低调的 `Summary failed`。
- 点击 `Summary ready` 打开底部 sheet；summary 内容不直接展开在 timeline row 内。
- 新摘要以结构化 document blocks 渲染：可包含标题、一句话总结、一级/二级标题、段落、项目列表、编号列表和 `AI suggested` callout。
- 详细内容默认折叠，用户可以在 sheet 内展开阅读；折叠状态不需要跨次打开持久化。
- 摘要语言默认跟随原语音/视频的主导语言，专有名词和英文术语保持原样；用户也可以通过 Settings > AI Language 强制新生成/重新生成 summary 使用中文或英文。
- AI 推断出的后续建议必须明确标记为 `AI suggested`，不能混入客观事实。
- 重新生成成功后才覆盖当前 generated summary；旧 summary 兼容显示，但不会批量自动重生成。
- 点击 `Regenerate` 后应立即显示正在重新生成的反馈，禁用重复点击；退出 sheet 后 timeline 仍显示轻量 `Regenerating` 状态。新结果完成前保留当前摘要可读，失败时不清空旧摘要，并在 sheet 中显示失败原因和重试入口。
- AI summary generated metadata 参与 iPhone 本地搜索；搜索还覆盖原始动态正文、评论文本和历史 transcript metadata。
- 对新语音 moment，AI summary 应为可识别的非空语音生成不超过 40 个字符的 `documentTitle`；如果 provider 返回空/过长标题，server 可从 `oneLiner` 派生安全短标题。若首次 ready summary 有有效标题，且当前正文第一条非空行不是 `# ` 或 `## ` 标题，iOS 可以把它作为 `## 标题` 插入正文顶部。只插入标题，不插入 summary 正文；summary regenerate 不覆盖已有标题；视频、图片、文字和历史语音不自动写回标题。

### 查看和编辑动态

作为用户，我希望能点进一条动态查看详情，并在发错内容时直接修改，这样私人记录可以长期保持准确。

验收标准：

- 时间线点动态进入详情页。
- 详情页支持查看完整文字、发生时间、图片/语音/视频和同步状态。
- 详情页支持完整图片浏览、语音播放和视频全屏播放。
- 详情页支持删除整条动态，并需要二次确认。
- 时间线左滑删除保留，但也需要二次确认。
- 详情页右上角进入编辑页。
- 编辑页支持修改文字、发生时间、新增/删除/替换媒体；图片支持长按拖拽重排。
- 保存时以编辑页最终文本和媒体列表作为新状态。
- 可以只有文字，也可以只有一种媒体，但不允许文字和媒体都为空。
- 编辑直接覆盖原动态，不做可见历史版本。
- 编辑本地先保存，随后通过同步队列上传到 Mac。
- 同步中或部分同步的动态暂不允许编辑；已同步或失败的动态允许编辑。
- 单张图片删除采用软删除，并由服务端 30 天后清理文件。
- 新增图片上传失败时，动态显示为部分同步。
- 编辑草稿按动态保存；再次打开时询问继续编辑草稿或丢弃草稿。
- 保存成功或用户主动丢弃时清除编辑草稿。
- 详情页弱显示 iPhone 本地最后编辑时间。

### 删除

作为用户，我希望可以删除不想保留的内容，这样记录可控。

验收标准：

- MVP 支持删除内容。
- 删除采用软删除。
- 删除操作可离线记录，并在联网后同步到 Mac。
- Mac 端保留软删除记录 30 天。
- 30 天后服务端清理数据库记录和相关图片文件。
- MVP 不要求实现完整回收站 UI。

### 设备认证

作为用户，我希望只有授权设备能访问我的服务，这样即使在 Tailscale 内网中也能防误访问。

验收标准：

- 单用户密码登录。
- iOS 登录后获得长期 device token。
- API 使用 `Authorization: Bearer <device-token>`。
- 设备 token 长期有效，可手动撤销。
- 高风险操作需要重新输入密码。
- Mac 后台可查看设备列表和撤销设备。

### Mac 后台管理

作为用户，我希望 Mac 后台显示服务状态和同步状态，这样我可以确认系统是否正常工作。

验收标准：

- 显示服务状态。
- 显示存储占用。
- 显示设备列表和撤销入口。
- 显示同步状态。
- 显示文件日志。
- 提供后台服务运维入口。
- MVP 不作为主要发布入口。

### Mac Archive 备份与恢复

作为用户，我希望 Mac 后台能管理备份和恢复，这样长期使用时不需要靠手动复制数据库或记一串复杂命令来保护 archive。

验收标准：

- Admin 有 `Archive` 入口。
- 可以填写本机目录或 iCloud Drive 目录作为 restic repository path。
- 项目自动创建 `.private-moments-restic-key`，用户不需要记额外备份密码。
- UI 明确说明：repository + key file 可以恢复 archive，这不是额外的加密保险箱。
- 可以手动 `Backup now`。
- 可以开启每日固定时间备份。
- 可以列出 snapshots。
- 可以运行 repository check。
- iOS Settings > Storage & Diagnostics > Diagnostics 可只读查看 `Backup Status`：repository configured/initialized、restic availability、latest backup job、latest snapshot、schedule、repository path 和 key file path。
- Restore 必须恢复到新目录，不能直接覆盖当前数据。
- Restore job 会验证数据库、manifest 和 media 文件引用。
- Promote preparation 要求强确认，进入 maintenance mode，创建 pre-promote backup，并写出 restart instructions。
- 当前 v0.1 不做 live SQLite hot swap；operator 按 `pending-promote.json` 停止 server、切换 env、重启 server。

### Sync Health 诊断

作为用户，我希望在 iPhone 和 Mac 后台能看懂同步为什么卡住，这样可以区分是 Mac 不在线、认证问题、cursor 落后、outbox 没发完、media 上传失败、media 回填缺失，还是 AI summary pipeline 没完成。

验收标准：

- Mac Admin Overview 显示 Sync Health。
- iOS Settings > Storage & Diagnostics 显示 Sync Health。
- iOS 显示本机 pending changes、pending uploads、failed uploads、missing media、当前 cursor。
- Mac 在线时，iOS 显示 Mac latest server change version、pending/rejected server ops、failed media uploads、AI not ready 和 last sync timestamps。
- 提供安全动作：`Sync Now`、`Pull Server Changes`、`Re-download Missing Media`。
- 默认 UI 不提供 reset cursor、清空数据库或破坏性重建。

### Mac Posts 运维管理

作为用户，我希望在 Mac 后台查看和清理动态数据，这样我可以区分真机/模拟器数据、检查图片是否同步成功，并清理测试数据。

验收标准：

- 后台采用 `Overview / Posts` 顶部 tab。
- Posts 页提供列表 + 右侧详情抽屉。
- 列表显示文字摘要、发生时间、媒体数量、创建设备、更新设备、删除状态和基础同步状态。
- 详情抽屉显示完整文字、发生时间、创建/更新时间、创建设备、更新设备、serverVersion、媒体状态、媒体大小和 checksum。
- 详情抽屉显示图片缩略图网格。
- 点击缩略图可以全屏查看大图。
- 默认只显示未删除动态，可切换查看软删除动态。
- 支持按创建设备筛选。
- 支持按删除状态筛选。
- 支持文本搜索，覆盖动态正文、评论文本，并兼容历史语音/视频转写 metadata。
- 普通列表默认 50 条，支持 `Load more`。
- 搜索结果最多返回 100 条，第一版不做搜索分页。
- 单条删除入口只放在详情抽屉内，必须二次确认。
- 单条删除采用软删除，并通过同步事件让 iPhone 下次同步后隐藏该动态。
- 设备列表提供 `Clean posts` 危险操作，用于永久清理该设备创建的测试动态。
- `Clean posts` 必须显示候选数量和设备名，并要求输入设备名确认。
- `Clean posts` 只清理该设备创建的动态，不清理该设备仅更新过的动态。
- `Clean posts` 不自动撤销设备。
- 永久清理后，动态从 Posts 管理里彻底消失；服务端只保留让 iPhone 同步隐藏所需的最小删除事件和日志。
- 第一版不支持在 Mac 后台编辑动态正文、发生时间或图片顺序。
- 第一版不支持恢复软删除动态。

## 7. 媒体策略

- 支持文字 + 图片、文字 + 语音、文字 + 视频，以及纯图片、纯语音、纯视频动态。
- 评论保持纯文字，不支持评论媒体。
- 每条动态只允许一种媒体类型：最多 9 张图片，或 1 段视频，或 1 段语音。
- 图片发布页支持相册多选 + 直接拍照。
- 视频从相册选择，最长 2 分钟，发布前由 iOS 压缩为 720p H.264 MP4 并生成 poster。
- 语音在发布页内录制为 AAC/M4A，最长 60 分钟，支持暂停、继续、停止、切到其他 App 后继续后台录制，以及发布前试听。
- 时间线里的视频在滑入主要可视区域后静音自动播放；同一时间只自动播放一条视频，点击视频仍进入全屏播放。
- 语音支持中途暂停和下次续播；完整播放结束后回到未播放的初始状态，不保留末尾进度。
- iOS 不再对语音和视频做本机 speech transcription，也不上传 `transcriptionText`。语音/视频上传到 Mac 后，server 在后台用 Mac 本地 `mlx-whisper` 转写，再调用外部 summary provider 生成 AI summary；transcript 只作为服务端内部输入和长度/hash metadata，不作为 timeline 正文或 sheet 回退内容。
- 图片上传后生成压缩展示图。
- 用户可选择是否保留原图。
- 压缩展示图默认移除 EXIF/GPS 等隐私元数据。
- 选择保留原图时，原图保留完整元数据。
- iPhone 本地保存压缩展示图 + 原图待上传副本。
- 原图上传成功后，iPhone 本地原图副本可按空间策略清理。
- Mac 长期保存压缩图、视频 MP4、视频 poster、语音 M4A，以及用户选择保留的原图。

## 8. 本地缓存策略

- iPhone 缓存全部文本元数据。
- iPhone 缓存已下载的展示图/缩略图和视频 poster。
- 旧图片可按需从 Mac 下载；远端语音/视频的完整文件在播放时按需下载并缓存。
- 时间线优先从本地渲染。
- App 打开后在后台进行增量同步。
- Settings > Storage & Diagnostics 可清理可重新下载的完整语音/视频缓存；不删除本地待上传文件或 Mac 归档内容。

## 9. 草稿策略

- iPhone 支持本地草稿自动保存。
- 草稿不上传 Mac。
- 用户发布后，内容才进入同步队列。

## 10. 备份策略

MVP 采用单一数据目录，方便 Time Machine、外部硬盘、Syncthing 或其他工具备份。

默认目录：

```text
~/Library/Application Support/PrivateMoments
```

当前备份主路径是 Mac Admin 的 restic-backed Archive：可以把 repository path 放在用户明确选择的本机目录或 iCloud Drive 目录中，但不要让 SQLite 数据库直接运行在 iCloud Drive 中。迁移辅助路径是 Mac Admin 的 migration-first export/import package：JSON manifest/metadata 是权威，Markdown 只是预览，import 只写入新的 staged data directory。

## 11. 安全策略

MVP 不做应用级加密，不做端到端加密。

第一版依赖：

- 用户自选的受保护 Server URL 作为真实设备同步路径。
- LAN、Tailscale/private VPN、Cloudflare Tunnel 或其他 HTTPS endpoint 都只是可选网络层。
- 单用户密码登录。
- 长期 device token。
- 设备撤销。
- Mac 文件权限。

后续可考虑：

- 加密 zip 备份。
- 高风险操作重新验证。
- 更细粒度审计日志。

## 12. 开源定位

项目后续定位为个人自托管产品，而不是通用开发脚手架。

文档优先解释：

- 如何在 Mac 上安装和启动服务。
- 如何配置 launchd。
- 如何配置一个可从 iPhone 访问的 Server URL；LAN、Tailscale/private VPN、Cloudflare Tunnel 或其他受保护 HTTPS endpoint 都只是可选网络层。
- 如何用 Xcode 安装 iOS App。
- 如何备份和迁移数据目录。

## 13. MVP 范围

MVP 必须包含：

- iOS 原生 App 基础发布流程。
- 文字 + 图片、文字 + 语音、文字 + 视频，以及纯图片、纯语音、纯视频。
- 图片相册多选 + 直接拍照。
- 相册短视频导入、压缩和 poster。
- 发布页语音录制、试听和播放。
- 主时间线单用户私密评论。
- 本地 SQLite 存储。
- 本地自动草稿。
- 离线发布队列。
- App 重启后本地内容仍可见。
- Mac 服务端 API。
- 受保护 remote endpoint 下同步。
- 文字/帖子先同步，图片、语音、视频和视频 poster 逐项同步。
- Mac server 侧语音/视频 AI summary：完整媒体上传后，server 本地转写并调用外部 summary provider，结果作为 generated metadata 保存并同步回 iOS。
- Smart Tags：所有 moment 可手动打主标签/主题标签；新语音 moment 可在首次 AI summary ready 后自动应用保守数量的 AI 建议标签；标签参与 iPhone 本地搜索/筛选，并可在 Settings > Tags 单条或批量管理。
- 主时间线默认只在 ready summary 存在时显示 `Summary ready`；没有 ready summary 时不显示 Summary 占位或 transcript 回退。用户手动重新生成已有摘要时，timeline 可显示轻量 `Regenerating` / `Summary failed` 状态；底部弹层保留旧摘要直到新结果成功替换。
- 删除和软删除同步。
- Mac SQLite + 本地文件存储。
- Mac 后台管理页基础状态。
- 设备 token 鉴权。
- 数据目录和 manifest。
- 文件日志和后台日志。
- 详情页查看与编辑。
- 收藏、筛选和月份快速跳转。
- Mac Admin Posts 运维管理。

MVP 暂缓：

- 回收站 UI。
- 一键备份导出。
- iOS 多设备冲突 UI。
- 通知。
- 更复杂的心情分析或 AI persona 评价。
- App Store 分发。

## 13.1 AI Periodic Reviews

AI Periodic Reviews 是一层私密回看 artifact，不是普通 moment。第一版实现 `Weekly Review`，但底层按通用 `Review` 建模，后续可以扩展到月度回顾或自定义时间段。

Weekly Review 的定位：

- 以回看为主，辅以少量反思。
- 语气是冷静观察 + 适度鼓励。
- 手动生成时总结触发时刻往前 rolling 7 days。
- 自动生成默认关闭；开启后由 Mac server 在每周日晚上生成过去 7 天，不通知、不自动发布。
- 输入包括文本 moment、评论、ready audio/video AI summary、标签、收藏、媒体类型和发生时间。
- 图片第一版只作为媒体类型和回看信号，不做视觉理解。
- AI 不为每条判断绑定 evidence；只在 `Worth Revisiting` 中提供低权重 moment anchors，帮助用户在当前 Review 界面内回到原始 moment。新生成内容必须避免没有输入支撑的完成度、效率、情绪、健康或意图判断，且 anchors 必须只引用本次输入中真实存在的 moment。
- 用户可以对 review 提供反馈，例如 useful、too much inference、too dry、missed the point、hide this theme。
- 发布到 moment 是显式动作或未来可控开关，默认不发生。

## 14. 核心验收标准

MVP 的端到端成功标准：

1. iPhone 在离线状态下创建一条包含文字和媒体的动态。
2. App 重启后，这条动态仍然可以在本地时间线看到。
3. iPhone 通过配置的 Server URL 重新连上 Mac 后，App 自动同步。
4. Mac 成功保存帖子、评论、媒体元数据和媒体文件。
5. Mac 后台能看到同步成功、存储占用和设备状态。
6. iPhone 上这条内容从待同步或部分同步状态变为已同步。
7. 对包含清晰语音的 audio/video moment，完整媒体上传后 Mac server 可以生成 AI summary；生成前 iOS 不显示 Summary 占位或 transcript 回退，生成后 iOS 显示 `Summary ready`。
8. 用户点击 `Summary ready` 后，底部弹层显示 AI 摘要，并可复制、重新生成和删除 summary；重新生成过程中退出 sheet 不会取消任务，timeline 显示轻量状态，成功后替换旧摘要，失败时旧摘要仍保留且可查看失败原因。除新语音首次 ready summary 可插入一个 `##` 标题外，原 post/media/legacy transcript metadata/comments 不被 AI summary 修改。
9. 用户可以给任意 moment 手动添加主标签和主题标签，并通过搜索、筛选、Settings > Tags 单条或批量管理这些标签；对新的清晰语音 moment，首次 ready AI summary 可以同步回保守数量的 AI 建议标签。
