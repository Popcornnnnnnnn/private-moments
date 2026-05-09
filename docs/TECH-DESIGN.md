# Private Moments Technical Design

## 1. 架构概览

Private Moments 采用 iOS 原生 App + Mac 自托管服务端的本地优先架构。

```text
  iPhone App
  Swift + SwiftUI
  Share Extension
  SQLite3 local database
  local drafts
  local timeline cache
  outbox sync queue
  media compression
        |
        | Tailscale / private VPN
        | HTTPS or HTTP over private network
        v
Mac Server
  Node.js + TypeScript
  Fastify API
  Prisma + SQLite
  local file storage
  launchd login service
        |
        v
Mac Admin UI
  React + Vite
  served by Fastify
```

Mac 是最终归档源，iPhone 是本地优先缓存和待同步队列。iPhone 离线时可以完整创建内容和浏览已有本地内容；Mac 可达后再通过 sync endpoint 对账。

## 2. Monorepo 结构

项目放在 `private-moments/` 子目录，不直接在上层 `07-github` 根目录工作。

建议结构：

```text
private-moments/
  ios/
    PrivateMoments.xcodeproj
    PrivateMoments/
  server/
    package.json
    src/
      api/
      auth/
      config/
      db/
      media/
      sync/
      admin/
      logging/
    prisma/
      schema.prisma
      migrations/
  admin/
    package.json
    src/
  shared/
    openapi.yaml
    sync-protocol.md
  docs/
    PRD.md
    TECH-DESIGN.md
    INTEGRATION-GUIDE.md
    OPERATOR-RUNBOOK.md
    HANDOFF.md
    DESIGN-PRINCIPLES.md
```

当前仓库已经包含 `ios/`、`server/`、`admin/`、`shared/` 的 MVP 骨架和可编译实现。

当前实现已经覆盖第一版本地构建：iOS 本地优先发布文字、图片、语音和短视频，系统 Share Sheet 导入入口，主时间线单用户私密评论，独立 Check-ins 生活活动记录，check-in 照片附件，手动选择发生时间、草稿保存、离线 outbox、自动延迟重试、图片上传压缩、视频压缩与 poster、音频录制与播放、server-side 语音/视频 AI summary、远端媒体缓存、设置页存储诊断、App Language-aware 人性化时间标签、滚动月份浮层提示、时间线搜索、收藏、筛选、Calendar Review、详情页、编辑、软删除同步、iOS 本机语言偏好，以及 Mac 本地 Archive/恢复运维面。

iOS 还提供本机 `Automatic Sync` 开关。打开时沿用启动、前台、发布/编辑、失败重试和 AI follow-up 的自动同步路径；关闭时进入严格 local-only 模式：发布、编辑、评论、标签和媒体草稿仍写入本地 SQLite/outbox，但不会自动连接 Mac server、上传媒体、拉取远端 AI summary/tag/media 变更或执行后台 retry。Settings 里的显式 `Sync Now` 仍是用户主动联网动作；Settings 根页的同步转圈只表示这类用户主动动作，不表示后台空闲检查。

v0.1 owner reliability layer 增加 Mac Admin `Archive` 和 Sync Health。Archive 使用 restic 作为底层 deduplicated snapshot 工具，server 通过 durable `maintenance_jobs` 记录备份、检查、恢复和 promote preparation；Sync Health 和 Mac operations read-only 摘要在 iOS Settings 中展示，Mac Admin 保留 Archive、runtime truth、maintenance jobs、logs 和 device emergency。

当前 UI 设计原则是保持主时间线安静：筛选、Calendar 回看、收藏和管理能力应尽量藏在 toolbar menu、底部 review tab、滑动操作或详情页里，避免把主界面做成后台管理界面。详细原则见 `docs/DESIGN-PRINCIPLES.md`。

iOS 主要模块已经按职责拆分。`TimelineStore` 按 session、mutations、sync、server changes、media、check-ins、payloads 和 sync retry 拆分；`LocalDatabase` 按 schema、records、timeline、sync、storage stats、check-ins/check-in media 和 SQLite helper 拆分；`TimelineView` 拆出 `TimelineRow`、`MomentDateFormatter`、`MediaGalleryView` 和 `ZoomableLocalImage`。设置页存储诊断拆在 `StorageStats.swift` 和 `StorageSettingsView.swift`。后续继续加功能时优先扩展这些小文件，不再把同步、数据库或主界面逻辑塞回单一大文件。

## 2.1 时间线交互决策

时间线 UI 保持低干扰原则。`MomentDateFormatter` 负责把 `occurredAt` 转换为跟随 App Language 的生活化标签：英文如 `Just now`、`2 min ago`、`Today 2:40 PM`、`Yesterday 2:40 PM`、`Apr 29, 2:40 PM`，中文如 `刚刚`、`2分钟前`、`今天 14:40`、`昨天 14:40`。月份标题不再作为列表里的常驻结构块，而是通过滚动时短暂出现的 `FloatingMonthIndicator` 提供方向感；停止滚动后自动淡出。

时间线删除使用右侧 swipe action 打开居中的系统 `alert`。右滑删除不允许 full swipe，并在点击 Delete 后延迟约 180ms 展示确认框，让系统 swipe 行先收回，避免列表跳动。这里不要使用位置相关的 `confirmationDialog`，因为它会表现得像从某个列表行冒出的气泡，删除确认语义不够清楚。

### 2.1.1 主时间线评论决策

评论由主时间线直接承载，不走单独内部评论界面。每条动态下有轻量写评论入口，使用 `square.and.pencil` 小胶囊以区别于 `Summary` 的文本/AI 状态入口；有评论时显示真实数量和评论预览。默认预览最新两条评论，但预览内部按旧到新排列，避免阅读顺序倒置；`View all N comments` 和 `Show less` 在原位展开/折叠完整评论列表。

评论输入使用底部输入栏。点击某条动态的评论按钮后，输入栏显示 `Commenting on: ...` 或 `Photo moment · N photos` 等目标摘要并聚焦键盘。Return 插入换行，`Send` 发送；发送成功后收起输入栏，展开该动态评论区，并把时间线滚到该 moment 的底部，让最新评论可见。切换目标或关闭非空草稿时需要确认丢弃。

评论内容是 plain multiline text，最大 500 字符。第一版不支持评论作者、回复、点赞、媒体、Markdown/rich text 渲染、编辑或复制选择。长按评论行触发 `Delete comment?` 居中确认框；确认后只删除评论，不删除父动态。评论行不显示 `synced`、`pending` 或 `failed` 等逐条同步标识。

搜索先应用既有筛选，再匹配动态正文或评论文本。命中评论时，时间线仍显示父动态，但评论预览优先展示最多两条匹配评论并轻量强调命中行；评论数量始终是真实未删除评论总数，不变成搜索命中数。历史转写 metadata 可继续作为旧数据兼容存在，但新发布的语音/视频不再在 iOS 本地生成 transcript，也不把 transcript 作为可见内容入口。

### 2.1.2 Calendar Review 决策

Calendar 是 Timeline 的底部 tab 同级 review 模式，用于看过去某段时间的发布密度和快速回到某一天。Settings 不再作为底部 tab，而是保留在 Timeline/Calendar 的 toolbar 设置入口里。Calendar 不提供 Compose、新建、编辑或归档管理功能。

Calendar v1 完全由 iPhone 本地 Timeline 数据派生，不增加 SQLite schema、sync operation、server calendar API 或 Mac 统计缓存。它默认显示当前月份，支持左右箭头、横向滑动和 `Today` 返回当前月；月份网格固定为 42 个日期格，包含空月份和相邻月份日期。Weekday 顺序跟随 `Calendar.current.firstWeekday`，month/day 文案跟随 App Language。

日期格用低饱和 heatmap 表达本地 moment 数量。低频月份保持固定阈值，忙碌月份按当前可见月份的最高发布日做相对分级，支持 `light`、`medium`、`strong`、`intense`、`peak` 等层次，避免 4+ 后全部同色。日期格可以显示轻量数量标签，并最多显示两个媒体提示图标，作为记忆触发而不是内容列表。未来日期淡出且不可点击；今天只用轻量描边，不做任务 App 式强调。

Calendar 有自己的轻量月份筛选：All/Text/Photos/Audio/Video、Favorites 和 Comments。筛选只影响 Calendar 的 heatmap、媒体提示、日期是否可点和 Month Stats，不继承也不改变 Timeline 的搜索/筛选状态。Calendar navigation bar 的 `topBarTrailing` toolbar 放置 Month Stats 和 Settings 等低频入口；Month Stats sheet 由本地 month model 派生，展示总数、活跃天数、活跃日均、最多的一天、每日柱状节奏和内容组成，不展示单独 Summary 数量。Sheet 不放 Close 按钮，依赖系统下滑关闭；最多的一天和每日柱状条可直接进入对应 Day Review，内容组成行可把 Calendar 月份筛选切到对应类型。点击有内容的日期会在 Calendar navigation stack 内 push 一个完整 `Day Review` 页面，并使用未被月份筛选裁剪的当天数据；Day Review 右上角 `Timeline` 才是切回 Timeline 并应用临时 day filter chip 的二级动作。清除 chip 后 Timeline 恢复完整列表。普通 Timeline/Calendar tab 切换应保留 Timeline 原滚动状态。

Day Review 不使用 grouped `List` 或 sheet 的灰色大块背景，而是用 ScrollView + 无卡片日内时间轴表达“这一天发生了什么”。顶部显示日期、星期、当天 moment 总数和媒体构成；每条记录左侧是 24 小时制时间点，右侧是内容预览。Day Review 自带轻量横向 chips，多选 Photos、Audio、Video、Favorites、Comments 时按 OR 关系显示内容，点已选 chip 可取消，点 All 清空筛选；Summary 不作为独立筛选项。日内记录用 Morning/Afternoon/Evening/Late Night 等轻分隔增加一天内部的节奏。记录在 `Show Tags in Timeline` 打开时只显示主标签，并对正文中的 `#` / `##` 标题做轻量 Markdown 渲染，正文缺失时回退到 AI 标题或媒体 fallback。图片 moment 在 Day Review 里全部显示为统一小缩略图，单张图片也不放大；视频只显示类型/时长提示，不播放、不自动播放，也不显示 poster；音频可行内播放并显示 ready/summarizing/failed summary 入口。点击非音频控件区域会 push 到 `MomentDetailView`，返回时保持在同一天 Day Review；Day Review 用本地 `UserDefaults` 按日期保存当前可见 moment id，返回 App 或重建该日期页面时恢复上次浏览位置。日期格点击反馈沿用 app 的轻量手感：`0.985` 左右的按压缩放、浅 tint、无阴影，并在确认进入 Day Review 时触发一次 selection feedback。旧 Timeline toolbar `Jump to date` 日历图标在 Calendar 落地后移除，避免两个日期入口并存。

### 2.1.3 Pinned Moments 设计

Pinned Moments 是时间线顶部的快捷回看层，不是新的内容类型。它只增加主 Timeline 顶部的可达性：置顶 moment 仍保留在普通主列表的原时间位置，并用轻量 pin 图标提示状态；它不改变 `occurredAt`、Calendar/Day Review 统计、Review 输入范围、搜索/筛选结果或原 moment 身份。

数据模型：

- server `posts` 增加 `is_pinned` 和 nullable `pinned_at`。
- iOS `local_posts` 增加 `isPinned` 和 nullable `pinnedAt`。
- 同步使用独立 `update_post_pin` operation，payload 包含 `isPinned`、nullable `pinnedAt` 和 `updatedAt`。
- server 接收后更新 post metadata，发出 `post_pin_updated` server change。
- `post_created` 和 `post_updated` payload 应包含 pin 字段，用于新客户端 baseline/recovery。
- export/import、Archive restore 和 staged promote 必须保留 pin metadata。

排序和冲突：

- Pinned 区域按 `pinnedAt DESC` 排序，时间相同时用 `occurredAt DESC` 和 id 做稳定兜底。
- 多设备或多次操作采用当前 sync 的 last-write-wins 语义，以 server 接收顺序为准。
- 删除 post 后，它自然从 Pinned 区域消失；`post_deleted` 已足够，不需要额外 unpin change。

Timeline UI：

- Pinned 只出现在主 Timeline，并且只在没有 active search/filter state 时出现；搜索、日期、Tag、Favorite、评论、内容类型、待同步或 match-source 筛选都会隐藏 Pinned。
- Timeline 顶部默认只显示 `Pinned · N` 汇总 header。
- 已置顶 items 保留在普通 Timeline list 的原时间位置；Pinned header/sheet 只是额外快捷入口，不搬移动态。
- 当置顶 items 作为普通 Timeline row 显示时，row 顶部 metadata 区显示一个低权重 `pin.fill` 图标，和 Favorite / sync badge 一样作为状态提示，不增加文字或新操作按钮。
- 当 pinned 数量为 1-3 条时，点击 header 展开/收起最多 3 条标题行。展开/收起状态只保存在本机 `UserDefaults`，不进入 sync。
- 当 pinned 数量超过 3 条时，点击 header 打开底部 sheet，显示完整 pinned 标题列表。
- 标题行只显示标题和轻量发生日期辅助信息；不显示正文、media grid、comments、AI summary、tag wall 或 sync success badge。
- Pinned sheet 使用内部 `NavigationStack`。点击 pinned 行在 sheet 内 push 正常 `MomentDetailView`，Back 返回 pinned 列表；sheet 内 detail 保留编辑、删除、favorite、tag、pin/unpin 等完整行为。
- Pin / Unpin 入口放在 Moment Detail 顶部 `More` 菜单、Timeline row context menu 和 pinned sheet row context menu。不要给每条普通 row 新增常驻 pin 按钮，也不要占用现有 Favorite swipe action。
- Calendar、Day Review 和 Weekly Review 不新增 pinned 入口或 pin 标记。

标题生成计划：

1. 正文第一条非空 `# ` 或 `## ` 标题，去掉 marker。
2. 正文第一条非空普通行，单行截断。
3. ready audio/video AI summary 的 `documentTitle`。
4. `Photo moment` / `Audio moment` / `Video moment` 之类媒体 fallback，必要时加发生日期。

第一版不新增自定义置顶标题、手动拖拽排序、Pinned-only Timeline filter 或 Admin pin management。自定义标题会新增用户编辑字段，拖拽排序会新增排序冲突语义；两者都留到需要时再单独设计。

Pin 与 Favorite 保持独立。Pending、failed、partial 和 synced 本地 moment 都允许 pin/unpin，操作写入 outbox 后按普通同步流程发送。多设备冲突以 server 接收顺序为准，last server-accepted wins。删除 post 后 Pinned 表面直接不再显示它，不额外生成 unpin operation。

### 2.1.4 Check-ins 设计

Check-ins 是第三个底部 tab，和 Timeline、Calendar 并列；默认启动 tab 仍然是 Timeline。它记录重复生活活动，例如吃饭、运动、起床和健康饮食，但不把这些活动伪装成普通 moment。

数据模型分两层：

- `checkin_items` / `local_checkin_items` 定义活动：名称、SF Symbol `symbolName`、颜色、`oncePerDay` 或 `multiplePerDay`、活跃星期、手动排序、默认 `showInTimeline`、可选 tag、archive/delete 状态和 sync 状态。
- `checkin_entries` / `local_checkin_entries` 定义一次打卡：item id、发生时间、可选 note、entry-level `showInTimeline`、soft delete 状态和 sync 状态。

Check-in 图标没有单独的 server/database icon 表。同步协议只保存 SF Symbol 名称字符串；iOS 编辑器提供本地精选图标 catalog、类别筛选、搜索、预览和高级 `SF Symbol name` 输入，并在保存前用系统 symbol lookup 校验。只有未来需要跨平台可管理 icon library 时，才重新考虑 icon catalog 表。

一次一天 item 使用本地日期做去重，编辑 entry 时间时也要重新校验同一天是否已有 entry。一天多次 item 不做时间冲突 UI，因为用户不需要在同一时间连续打卡；按发生时间自然排序即可。Item 还同步一个 `timeVisualization` 配置，取值为 `none`、`timeLine` 或 `timeHeatmap`，旧 item 默认 `none`。`timeLine` 只允许 `oncePerDay` item 使用；`multiplePerDay` item 只能用 `none` 或 `timeHeatmap`。

Check-ins UI 的默认路径必须是 one tap。`Today` row 左侧 icon 负责一键打卡；已经完成的一天一次 item，左侧 icon 打开今日 entry。中间 item 区域打开只读 item insights/trends 页，右侧低权重入口打开单独表单，允许填写 note、发生时间、照片和 `Show in Timeline`。Entry detail 支持修改 note、发生时间、Timeline 显示开关，或取消打卡。`Manage` 负责 item 创建、编辑、archive/delete；item row 整行都是编辑入口，并提供按压/hover 式反馈，避免只有图标像可点击。创建 item 可以稍复杂，但日常打卡不能被表单拖慢。

Item insights 是只读回看页，不进入 Manage。`timeLine` 使用最近 30 天回看窗口，但绘图区从窗口内第一条有效记录所在日期开始延伸到今天；缺失日期为空点并断线，只有 today 一条记录时点位于左端。发生时间是 Y 轴，Y 轴根据真实最早/最晚时间自动外扩；当晚间/凌晨时间跨午夜时，图表会把凌晨点展开到连续晚间区间。`timeHeatmap` 展示最近 30 天所有非删除 entry 的发生时间，使用 1 小时 bucket，同时显示 `24h distribution` 和 `weekday x hour`，支持一天多次记录。第一版不做聚类、AI 解读、提醒、目标或连续天数。

Timeline 使用混合 feed：普通 `TimelineItem` 加上 `showInTimeline=true` 的 `CheckInFeedEntry`。Check-in row 由 item 图标/颜色和 item 名称表达身份，可显示 note 和可选 tag，但不提供 comments、favorite、pin、AI summary、transcription、OCR 或 AI auto-tagging。关闭某条 entry 的 `Show in Timeline` 只影响 Timeline 和 Timeline search/filter；entry 仍保留在 Check-ins、Calendar 和 sync 数据中。

Calendar 使用 check-ins 作为 activity signal。Heatmap、每日 activity count、Day Review 和 Month Stats 都纳入非删除 check-in entries，并在 Month Stats 中区分 `Moments` 和 `Check-ins`。Day Review 显示当天所有 check-ins，包括隐藏于 Timeline 的 entry。真正统计型信息仍以 Calendar Month Stats 为主；Check-ins History 只显示最近周/月和 item 概况，避免把 Check-ins 变成 KPI dashboard。

Sync 使用四个独立 operation：

- `upsert_checkin_item`
- `delete_checkin_item`
- `upsert_checkin_entry`
- `delete_checkin_entry`

这些 operation 的 `entityType` 分别是 `checkin_item` 和 `checkin_entry`。Server changes 对应 `checkin_item_updated/deleted` 和 `checkin_entry_updated/deleted`。删除 item 会 soft-delete 其 entries；客户端应用 item delete 时本地级联即可。

Check-in 照片使用独立的 `checkin_media` / `local_checkin_media` 父对象，不复用 ordinary post media。当前只启用 still image，来源是相册 `Add Photos` 或相机 `Use Camera`；上传和恢复走 `/api/v1/checkin-media/upload`、`/api/v1/checkin-media/batch-download` 和 `GET /api/v1/checkin-media/:mediaId`。照片会出现在 Check-ins History、Calendar Day Review、Month Stats 和 Photos filter 中，即使对应 entry 不发布到 Timeline。

v1 明确不做 reminders、streak、missed count、completion rate、preset templates、Mac Admin management、separate export、AI tags、OCR、transcription 或 AI summary。Optional tag 默认 none，并且是 item-level secondary metadata；AI、语音和普通 composer 流程不应自动给 check-ins 打 tag。Audio/video check-in media 只保留入口和数据边界，尚未启用；后续扩展必须继续使用 check-in-owned media，而不是把 check-ins 写成 ordinary posts。

## 2.2 详情与编辑决策

详情页是单条动态的管理入口。时间线点击动态进入详情页，详情页负责查看完整内容、图片/视频/语音浏览播放、编辑入口和删除入口。图片浏览器只负责查看，不承担删除操作；视频使用全屏播放；语音使用全局复用的 waveform voice bar。

媒体模型支持 `image`、`video`、`audio` 三种 `kind`。每条动态只允许一种媒体类型：图片最多 9 张，视频 1 段，语音 1 段。视频从相册导入后在 iOS 端压缩为 720p H.264 MP4，并生成 JPEG poster 写入 `thumbnail` variant；时间线里由单例 muted autoplay center 选择当前最靠近视口中心的视频静音自动播放，滑走、打开详情/全屏/发布页时停止，点击视频仍进入全屏播放。语音通过 AVAudioRecorder 写入 AAC/M4A，主 App 声明 `audio` background mode，录音 session 使用 `playAndRecord` + `spokenAudio`，因此用户从发布页开始录音后可以切到其他 App，回到 Moments 后再停止并生成语音草稿。本地播放进度按 media id 存在 UserDefaults；中途暂停或切走会保存进度，完整播放结束会清除该 media 的进度并让播放条回到初始未播放状态。音频播放在 App 仍 active 的界面切换中自动暂停，例如切换 Timeline/Calendar、进入详情、打开 Settings/Composer/Summary/gallery/video 或退出 Day Review/Detail；进入后台或锁屏不暂停，继续依赖 `audio` background mode 和 `.playback` session。语音条是全局复用的 waveform voice bar：用 deterministic pseudo-waveform 表达可拖动进度，点击播放/暂停，横向拖动 seek，右侧轻量 `1x/1.5x/2x` capsule menu 调倍速；Timeline 和 Day Review 使用紧凑密度，Detail 稍高。语音条不显示重复的 `Audio` 标题，也不使用突兀的整块灰色卡片；正文语境由 moment text 或 comments 承担。iOS 不再使用 Speech framework 做本地转写，也不再上传 `transcriptionText`；语音/视频摘要由 Mac server 在媒体上传后先本地转写，再调用外部 summary API 处理。评论仍然是纯文字，不复用媒体模型。

编辑采用直接覆盖模型：保存后原动态只显示最新文字、发生时间和图片列表，不提供可见历史版本。编辑页支持修改文字、发生时间、新增图片、删除图片和 9 张以内图片的长按拖拽重排。保存时，编辑页里的最终图片列表就是新状态；服务端软删除移除的图片，保留新增图片等待上传，重排后的 `sortOrder` 作为权威顺序。

编辑入口不再等待 moment 完全 synced。`pending`、`partial`、`failed` 和 `synced` 的 moment 都可以编辑正文、时间、媒体顺序和标签；本地最新状态是用户看到的权威状态。同步层通过 outbox operations 和 media upload queue 在 Mac 可达时收敛到最终版本。详情页的正文复制动作复制 `post.text` 的 Markdown source，避免引入另一套富文本导出模型。

Share Extension 仍保持 thin extension 边界：截图、图片、音频、视频、网页 URL、微信文章 URL 或文本分享只会被 staged 到 App Group inbox，主 App Composer 负责最终编辑和发布。文章/URL 类内容不新增服务端抓取链路；iOS 从正文中的 URL 派生轻量 link-card 样式，点击时交给系统打开原 URL，是否回到微信由 iOS/微信的 Universal Link 或 URL 处理能力决定。

iOS New Moment composer 和 Edit Moment 的正文输入使用轻量 Markdown 富文本层，但底层仍保存 `post.text` 为 Markdown source `String`。编辑器只支持行首 H1 和 H2：非当前标题行隐藏 `#` / `##`，光标进入标题行时临时露出 marker；普通 `- ` 或 `• ` 列表只保留既有 plain-text list continuation，不做 Markdown bullet 渲染。键盘上方 accessory toolbar 只放紧凑 H1/H2 segmented control，并只切换当前行前缀；不额外放 `Done` 按钮。编辑器基于 `UITextView` 的 attributed styling 必须避开输入法 marked text：当中文等输入法正在组词时，不重写 `textStorage` 或替换正文，待候选词提交后再恢复 Markdown 样式刷新。Timeline、Detail 和 Day Review 复用 `MomentTextMarkdown` / `MomentTextView` 做同一组 H1/H2 展示渲染，Timeline 标题字号低于 Detail/Edit。

发布页会拦截真实剪贴板图片粘贴。粘贴到正文区域的图片不会写入 `post.text`，也不会解析 Markdown 图片语法，而是追加到现有 image draft media grid，并复用相册/相机图片的草稿保存、预览、最多 9 张、单一媒体类型、发布压缩、SQLite/outbox 和 sync 路径。普通文字粘贴继续由系统文本编辑器处理并可被 Markdown 渲染层识别；Edit Moment 第一版不启用图片粘贴，避免扩大编辑媒体替换语义。

iOS 继续本地优先：编辑先写入本地 SQLite 和 outbox，网络可达后自动同步到 Mac。同步中或部分同步的动态暂不允许编辑，避免多个本地操作和媒体上传互相打架；已同步或失败的动态允许编辑。新增图片上传失败时，动态显示 `partial`。

收藏是独立的轻量元数据操作，不进入编辑页。iOS 本地更新 `isFavorite` 并写入 `update_post_favorite` outbox operation；Mac 接收后更新 `posts.is_favorite`，写入 `post_favorite_updated` server change，再由其他设备同步。

编辑草稿按 `postId` 保存在本机文件目录中。打开编辑页时如果有草稿，先询问继续编辑草稿或丢弃草稿。保存成功或用户主动丢弃后清除草稿。

### 2.2.1 Share Extension 与导入队列

系统分享入口以真正的 iOS Share Extension 形式存在，显示名为 `Save to Moments`，随主 App 安装和卸载。它不是单独 App，也不直接承担完整发布流程。

Share Extension 的职责保持很窄：

- 从 Share Sheet 接收最多 9 张图片、1 段视频、1 个音频文件、URL 或纯文本。
- 允许用户在 extension 内补一句 plain text note。
- 把文件复制到 App Group 容器的 `ShareImports/<importId>/files/`，并把 `import.json` 作为 metadata 写入同一个 import 目录。
- 通过 `moments://import/<importId>` 唤起主 App。

主 App 负责真正的导入消费。`RootView` 监听 share import notification 并打开现有 `ComposerView`；`ComposerView` 从 App Group import queue 读取最早的 pending import，把文本合并到 composer 草稿，把图片读为现有 image draft，把视频交给 `VideoMediaProcessor.prepareVideo`，把音频复制到 draft media 目录并交给 `AudioMediaInspector`。消费成功后删除 import 目录。

这个边界避免了三套入口各自实现发布逻辑：相册 picker、相机、录音、Share Extension 进入的内容最终都复用同一个 composer、media preparation、SQLite/outbox 和 sync pipeline。Share Extension 不写主 App SQLite，也不调用 server，不做视频压缩或 AI summary。

### 2.2.2 AI Summary 决策

AI summary 是语音/视频之上的 server-side 生成 metadata，不是评论者或公开反馈。主时间线只在 audio/video media 已经有 ready summary 时显示 `Summary ready`；没有 ready summary、仍在处理、失败或 provider 未配置时，不在时间线显示 Summary 占位、transcript 或失败文案。

iOS 点击 `Summary ready` 入口后打开底部 sheet，只显示 ready AI 摘要内容。生成路径由 Mac server 持有：完整 audio/video 上传到 `/api/v1/media/upload` 后，server 在后台优先使用 Mac 本地 `mlx-whisper` 把媒体文件转成内部 transcript，再把 transcript 交给外部 Chat Completions API 生成结构化 summary。iOS 不保存外部 AI API key，不直接访问外部 provider，也不展示 transcript fallback。生成结果保存为 `ai_summaries` / `local_ai_summaries`，可以复制、重新生成或删除；删除只隐藏/软删除 generated metadata，不影响 media 或 comments，也不会把 summary 正文写入 post。

唯一的 post-text 写回例外是新 audio 的 AI title auto-insert。iOS 在收到首次 ready audio summary 后，如果 `documentTitle` 有效、长度不超过 40 个字符、media 和 summary 都晚于本机 feature cutoff、当前 post 第一条非空行不是 `# ` 或 `## `，就把 `## <documentTitle>` 插入 `post.text` 顶部，并写入 `insert_ai_title` outbox operation。这个 operation payload 只包含 `summaryId`、`mediaId` 和 `insertedAt`，不包含标题正文；server 重新从自己的 ready summary 取 `documentTitle`，验证 audio/media/post 关系后发出带 `updateSource: "ai_title"` 的 `post_updated`。iOS 应用这类 `post_updated` 时不更新 `localEditedAt`，因此详情页不显示用户 `Edited` 标记。Settings > Feature Modules > `AI Title Auto-Insert` 只控制未来自动插入，不删除已经写入的标题。

摘要输出采用结构化 JSON。`media-summary-v4` 的主要渲染字段是 `documentTitle`、`oneLiner` 和 `documentBlocks`，iOS 用 native SwiftUI 渲染成标题、一句话总结、折叠详情、列表和 `AI suggested` callout；`overview`、`keyPoints`、`sections` 只作为旧客户端兼容字段保留。v4 继承 v3 的短标题要求：可识别的非空语音/转录摘要应返回 40 个字符以内的 `documentTitle`；如果 provider 仍返回空标题或过长标题，server 会从 `oneLiner` 派生一个安全短标题，只有内容为空、无法识别、静音或噪音场景才保留 null。v4 还会把 active topic tag 词表和 alias 传给 summary/tag prompt，要求优先复用已有 canonical topic；server 落库前也会按 exact/alias/明显包含关系复用旧 topic，避免 `HTTPS 中间人攻击` 与 `中间人攻击` 这类近义窄化标签继续分裂。服务端记录 `promptVersion`、provider、summary model、本地 transcription provider/model、输入 transcript hash/长度、duration、错误码和 timestamps；处理状态区分 `transcribing` 和 `summarizing`，便于在设置页排查卡住环节。日志只记录 id、状态、provider/model、错误码和输入长度，不记录 transcript 正文、summary 正文或 audio body。已同步 AI summary generated metadata 参与 iPhone 本地搜索，但不会直接展开在 timeline row 内。

### 2.2.3 Smart Tags 决策

Smart Tags 是 moment 的一层轻量组织 metadata，不是公开话题系统。数据模型分成稳定主标签和动态主题标签：

- 主标签描述表达类型，默认固定为 `日记`、`想法`、`学习整理`、`情绪`、`碎碎念`、`复盘`。
- 主题标签描述具体内容，例如 `大语言模型`、`面试`、`康复训练`，支持动态新增和 alias。
- 标签词表和 moment 关联分离：`tags` / `tag_aliases` / `post_tags` 在 server 侧持久化，iOS 对应 `local_tags` / `local_tag_aliases` / `local_post_tags`。
- 关联记录保存 `role`、`source`、`confidence`、`aiSummaryId`，使 AI 标签和手动标签都能作为普通标签同步和恢复。
- iOS 应用 `post_tag_updated` 时优先按 assignment `id` 更新本地 `local_post_tags`。服务端 `merge_tag` 可能把同一个 assignment 从 source topic 移到 target topic，如果本地已有目标 topic 关联，iOS 先清理冲突行再写入服务端指定的 assignment，避免 SQLite 唯一约束错误阻断 cursor。
- `Post.aiTagProcessedAt` 记录首次 AI 标签处理；`Post.tagsUserEditedAt` 记录用户完整编辑过标签，用于阻止后续 AI 自动覆盖。

UI 边界：

- Composer 只提供一个可选主标签 picker；用户不选时正常发布。
- Timeline 和 Day Review 只在 `Show Tags in Timeline` 打开时显示主标签 chip，不显示主题标签；Moment Detail 的 Tags section 和单条标签编辑入口也跟随同一个开关。成功态 `synced` badge 从 timeline 移除，只保留异常同步状态。
- Detail 在 `Show Tags in Timeline` 打开时只读显示完整标签，并提供单条标签编辑入口；tag badge 不做省略号截断，长标签在可用宽度内换行，normal read mode 不显示 `Manual` / `AI` 来源信息。关闭后 Detail 不露出标签展示或编辑操作。
- Settings > Tags 管理词表：usage count、自定义主标签、主题标签新增/重命名/归档/恢复、Topic 批量归档/合并、Archived 批量恢复/永久删除、alias、topic merge，以及主标签颜色；颜色选择以预设调色盘为主，保留 6 个低饱和默认色，也提供一组更清晰的高饱和标准色，并预留 HEX 自定义输入。Edit 模式支持批量选择多个 primary tag 并统一修改颜色，但不批量修改名称。
- Settings 顶层只保留 `Appearance` 入口；二级页提供 `System`、`Light`、`Dark` 本机外观偏好，通过 SwiftUI `preferredColorScheme` 即时覆盖 Moments App 外观；该偏好不进入 sync，也不尝试修改 iOS 设备级系统外观。
- Settings 顶层只保留 `Language` 入口；二级页提供 App Language 和 AI Language。App Language 是本机 UI 偏好；AI Language 只影响之后生成或重新生成的 summary/title。
- Mac Admin 只展示诊断，不作为标签内容管理入口。

AI 边界：

- 只有新 audio moment 在首次 ready AI summary 时自动应用标签。
- AI 输出在 `media-summary-v4` 结构化结果里带 `suggestedTags`，包含一个可选默认主标签和最多三个 topic 建议；短音频或短 transcript 会被保守裁剪为优先 1 个 topic，只有额外 topic 是高置信度且代表明显不同主题时才保留多个。生成时会把 active topic tag/alias 词表作为组织上下文传给 provider，provider 应优先返回已有 canonical topic name；server 应用标签时也会先匹配现有 topic、alias 和明显的包含关系，再决定是否创建新 topic。如果主 summary 输出缺少 primary 或完全没有标签，server 会再走一次聚焦的 tag-only provider call，并记录安全的置信度/跳过原因日志。
- 如果用户在 Composer 选择了主标签，AI 不改变主标签，但仍可追加 topic。
- 如果用户在单条标签编辑器中编辑过完整标签，server 不再自动应用该 moment 的未来 AI 标签。
- Summary regenerate 不重新生成或覆盖标签；历史 audio 不做回填；video/image/text 不做 AI 自动标签。

### 2.2.4 语言偏好与本地化边界

iOS 第一版语言系统使用 App 内本地化层，而不是把语言作为 server-side profile 同步。`AppLocalization.swift` 定义 `AppLanguageMode`、`AILanguageMode`、`appLanguage` SwiftUI environment 和 `L10n.t(...)` 字典。`AppSettings` 把 App Language 和 AI Language 存在本机 `UserDefaults`；已有私人安装在没有显式语言偏好时默认 English，新安装默认 System。Settings 顶层的 `Language` row 只显示当前偏好摘要，具体选项进入二级页。

App Language 只影响 iOS 主 App 的 user-visible chrome：Timeline、Calendar、Composer、Detail/Edit、Settings、Tags、Summary sheet、Search/Filter、评论 UI、弹窗和时间/日期标签。它不翻译用户正文、评论、自定义标签、主题标签、alias、历史内容、AI summary 正文、API 字段或 server/admin 文案。新增 iOS 可见文案应走 `L10n.t(...)`，避免中文模式出现新的英文漏项。

默认主标签是一组 synced tag identity，而不是两套语言 tag。server 以默认 tag ID 为准保护 canonical 中文名称、`isDefault` 和 `aiUsableAsPrimary`；iOS 也把这些固定 ID 视为默认主标签，即使旧本地数据曾经同步错过 `isDefault`。iOS 在显示层把默认主标签映射为英文 `Diary`、`Thoughts`、`Study`、`Mood`、`Random`、`Review` 或中文 `日记`、`想法`、`学习整理`、`情绪`、`碎碎念`、`复盘`；usage count、assignment、archive/delete rules、AI assignment 和 sync identity 都仍绑定到原 tag ID。Timeline search/filter 对这些默认主标签额外加入中英文 search names；自定义主标签、topic tags 和 aliases 不自动翻译。

AI Language 与 App Language 分离。iOS 在 `/api/v1/media/upload` 和 `/api/v1/ai/media-summary` 请求中传 `aiLanguage=auto|zh|en`；Mac server 将其作为 prompt 指令，用于新生成或重新生成的 summary/title。`Auto` 跟随 transcript/audio 的主导语言；`zh` 或 `en` 只影响 generated content，不改变 iOS UI，也不作为跨设备 synced preference。

### 2.2.5 AI Periodic Reviews 决策

AI Periodic Reviews 是通用回看系统。第一版是 `Weekly Review`，但 schema、API 和服务层不命名为 `weekly_reviews`，而是使用 `reviews.kind`、`rangeMode`、`rangeStart` 和 `rangeEnd`，为后续 monthly/custom review 复用同一基础。

Weekly Review 放在 Calendar 的 `Reviews` 入口下，而不是 Timeline。它是 generated review artifact，不默认成为 moment；用户只能通过显式 `Publish as Moment` 把 ready review 转成一条普通 server post。Settings > Feature Modules 提供 `Auto-generate Weekly Review` 和 `Publish Weekly Review`，两个默认关闭。自动生成由 Mac server 在本地时间每周日 21:00 后触发，生成 rolling 7 days，不通知、不自动发布。

Review 输入由 server 构建：

- 时间范围内未删除的 post text。
- 未删除 comments。
- ready 且未删除的 audio/video AI summary generated metadata。
- tags、favorite、media kind、occurredAt。
- 每日/时段节奏统计。

为了避免长范围自定义回顾把过多私密内容一次性送到外部 provider，server 对 Review generation 设置输入预算：生成范围最多 35 天，provider 输入最多 240 条 moments。超过范围的 API 请求直接返回 400；超过 moment 数量预算的生成会保存为 failed review，错误码为 `review_input_too_large`。

图片第一版只作为 image moment/media kind 信号，不做 OCR 或 vision analysis。普通日志和 review memory 不记录 post body、comment body、transcript body 或 summary body。

Review prompt 强制 whole-period reading：主题、关键词、状态回应、进展和节奏不绑定 per-claim evidence。只有 `notableMoments` / `Worth Revisiting` 可以携带 moment IDs 作为低权重 review anchors。iOS 点击 anchor 时在当前 Review 界面内打开 moment preview/detail sheet，不跳 Timeline，也不设置 Timeline day filter。

Review feedback 写入 `review_feedback`，并用粗粒度 counters 更新 `review_memory`。第一版 memory 只保存反馈偏好和最近反馈上下文，不保存私人内容正文。

## 2.3 Mac Admin 迁移与最小运维面

Mac Admin 定位为低频 Mac 本地运维台，不替代 iPhone 的内容编辑、回看、设置或日常诊断入口。当前顶层 tab 只保留 `Archive / Overview`：`Archive` 负责 restic backup/restore、promote preparation、export/import 和 repository 状态；`Overview` 只保留 runtime truth、maintenance jobs、server logs 和 device emergency。

后续设置、监控、诊断和安全修复动作默认优先迁移到 iOS Settings / Diagnostics。Mac Admin 保留为低频 Mac 本地运维面：Archive backup/restore、staged promote、export/import artifact、server logs、文件系统权限、LaunchAgent/进程状态和必须靠 Mac 文件路径完成的恢复操作。短期如果某个能力只能先放在 Admin，需要在 `docs/HANDOFF.md` 标明它是否属于后续迁移到 iOS 的候选。Admin 最小保留信息和迁移顺序记录在 `docs/ADMIN-MIGRATION.md`。

Posts 不再作为 Mac Admin 顶层内容管理页面。底层 Admin posts API 和旧 React 组件短期保留一个 checkpoint，作为紧急排障余量；后续确认不需要浏览器侧内容证据后，再单独删除或改成 hidden/debug-only。若保留 debug 能力，只允许按 ID 定位少量 post、查看 media path/status/checksum 等恢复证据、或清理明确测试设备产生的数据；不增加 Admin 内编辑、播放、批量内容整理或日常搜索体验。

历史 Posts 页面采用列表 + 右侧详情抽屉。列表用于快速扫描文字摘要、发生时间、媒体数量、创建设备、更新设备、删除状态和基础同步状态；详情抽屉用于查看完整正文、图片网格或媒体诊断、媒体状态、大小、checksum、`serverVersion`、创建/更新设备和删除时间。图片在详情抽屉内显示缩略图，点击后以全屏 lightbox 查看压缩展示图；语音/视频不在 Admin 内播放。该页面不再从顶层导航进入。

后台单条删除只放在详情抽屉内，必须二次确认。单条删除采用软删除：服务端设置 `Post.deletedAt`，将该 post 下未删除媒体和 comments 标记为 deleted，并写入 `post_deleted` server change；iPhone 下次同步后隐藏本地缓存。第一版不做软删除恢复。

设备行提供 `Clean posts` 危险操作，用于永久清理某设备创建的测试数据。该操作只匹配 `createdByDeviceId`，不匹配仅被该设备更新过的 posts。执行前必须展示候选数量和设备名，并要求输入设备名确认。执行后不自动撤销设备。

永久清理会删除匹配 posts 的数据库记录和媒体文件，Posts 管理里不再显示这些记录。为保持 iPhone 与 Mac 一致，服务端在删除数据库记录前为每个 post 写入最小 `post_deleted` server change；下次 iPhone 同步时隐藏本地缓存。后台日志记录清理操作的设备、数量和操作者。

设备绑定使用 `deviceKey` 防止重复注册。同一用户、同一平台、同一 `deviceKey` 只能对应一条 `Device`：iOS 使用 `UIDevice.identifierForVendor`，Mac Admin 浏览器使用本地 `localStorage` UUID。重复登录会更新原设备的 token、名称和 lastSeenAt，而不是插入新设备。为了兼容旧客户端，如果带 `deviceKey` 的登录找不到完全匹配记录，服务端会优先复用同名、同平台、未绑定 `deviceKey` 的旧设备记录。

## 2.4 Settings Storage 诊断决策

iOS Settings 的 Storage & Diagnostics 功能按语义拆成两个入口。主 Settings 的 `Storage & Diagnostics` section 下显示 `Storage` 和 `Diagnostics` 两行摘要：`Storage` 负责本机占用、可清理媒体缓存和 Mac 存储总量，`Diagnostics` 负责同步健康、Mac runtime、Mac operations、AI summary/token usage 和 tags 诊断。清理动作仍只限于清理可重新从 Mac 下载的完整语音/视频缓存。

本机统计由 iOS 直接扫描本地文件和 SQLite 状态：

- 总占用。
- SQLite 数据库、`-wal`、`-shm`。
- 媒体缓存目录。
- 可重新下载的完整语音/视频缓存大小。
- 待同步操作数。
- 待上传 media 数。
- 失败上传数。

Mac server 统计通过 `GET /api/v1/admin/status` 获取。服务端的 `server/src/storage/stats.ts` 统计数据目录总量、SQLite 相关文件、media 目录、logs 目录和数据目录所在卷的可用空间；同一个响应还返回 runtime、sync、`aiSummaries`、`aiUsage` 和 tags 轻量诊断。iOS 已登录且请求成功时，`Storage` 模块显示 `Mac Storage`，`Diagnostics` 模块显示 Mac Server runtime、AI summary 诊断和 AI token usage；如果 Mac 不在线、token 不可用或请求失败，入口只保留 Mac reachability 摘要，不弹错误。

iOS Settings > Storage & Diagnostics 的 `Diagnostics` 模块还会只读请求 maintenance state、最近 maintenance jobs、Archive repository 和 snapshots，用于展示 Mac Operations：maintenance mode、running job、最近失败 job、repository configured、restic availability/version、last backup/snapshot 和 next backup。该区域不触发 sync，也不提供 backup、restore、promote、export/import 等 Mac 本地恢复动作。

Storage 不提供删除归档内容、重建数据库或迁移操作，避免 Settings 主界面变成后台管理台。当前清理动作只删除已上传且可重新下载的本机完整语音/视频文件；不会删除视频 poster、本地待上传媒体或 Mac 归档内容。

## 3. 技术栈

### iOS App

- Swift。
- SwiftUI。
- 系统 SQLite3。当前先用轻量自写访问层减少外部依赖，后续如果本地查询复杂度上升，可以再替换为 GRDB。
- 本地文件目录保存压缩图、待上传原图副本、视频、视频 poster 和语音文件。
- 使用系统相册/相机能力。
- 使用 Share Extension + App Group import queue 接收外部 App 分享来的图片、视频、音频、URL 和文本；主 App 再转换为现有 composer draft。
- 本地 outbox 队列驱动同步。
- 失败同步或上传任务使用 5s、20s、60s、120s、300s 的延迟自动重试。
- 发布草稿保存文字、发生时间和已准备媒体。
- 远端同步来的压缩图和视频 poster 会下载到本地缓存后展示；完整语音/视频按播放需求下载。
- Settings > Storage & Diagnostics 分为 `Storage` 与 `Diagnostics` 两个入口：前者展示本机/Mac storage 与可清理媒体缓存，后者展示同步健康状态、AI summary 诊断、AI token usage、安全修复动作和只读 Mac Operations；Mac 在线时额外展示服务端 runtime、maintenance 和 Archive 状态。后续日常设置和监控默认继续放到 iOS Settings，而不是扩展为日常使用的 Mac Admin。

### Mac Server

- Node.js。
- TypeScript。
- Fastify。
- Prisma。
- SQLite。
- 本地文件存储。
- launchd 登录后自动启动。
- `/api/v1/admin/status` 返回服务状态、计数、存储诊断、Sync Health、AI summary 诊断和 AI token usage。

### Mac Admin UI

- React。
- Vite。
- 构建后由 Fastify 静态托管。

### Shared Contract

- `shared/openapi.yaml` 描述 API 字段、认证和响应结构。
- `shared/sync-protocol.md` 描述同步协议语义、幂等、冲突和 cursor 规则。

## 4. Mac 数据目录

默认数据目录：

```text
~/Library/Application Support/PrivateMoments/
  manifest.json
  app.sqlite
  media/
    compressed/
    originals/
    thumbnails/
    temp/
  exports/
  archive/
    archive-config.json
    staging/
    restores/
    restic-cache/
    pending-promote.json
  logs/
```

### manifest.json

`manifest.json` 用于记录数据目录版本，支持未来迁移和备份校验。

草案：

```json
{
  "app": "PrivateMoments",
  "dataVersion": 1,
  "schemaVersion": 16,
  "createdAt": "2026-04-28T00:00:00.000Z",
  "mediaLayoutVersion": 1
}
```

## 5. 服务端数据模型

服务端使用 Prisma + SQLite。媒体二进制文件不存入 SQLite，数据库只保存元数据和文件路径。

### User

MVP 只有单用户，但保留用户表有利于认证和未来扩展。

字段草案：

```text
user
  id
  passwordHash
  createdAt
  updatedAt
```

### Device

记录已授权设备和撤销状态。

```text
device
  id
  userId
  name
  deviceKey
  tokenHash
  platform
  lastSeenAt
  revokedAt
  createdAt
  updatedAt
```

`device token` 明文只在登录时返回给 iOS。服务端保存 `tokenHash`。

`deviceKey` 用于复用同一个物理设备或同一个浏览器安装，避免重复登录时产生大量同名设备。iOS 使用 `UIDevice.identifierForVendor` 派生稳定 key；Mac Admin 浏览器使用 `localStorage` UUID。

### Post

```text
post
  id
  text
  isFavorite
  occurredAt
  createdAt
  updatedAt
  deletedAt
  clientCreatedAt
  clientUpdatedAt
  serverVersion
  createdByDeviceId
  updatedByDeviceId
```

说明：

- `occurredAt` 是用户可手动修改的发生时间，用于时间线和月份归档。
- `isFavorite` 是收藏状态，独立于编辑流同步。
- `createdAt`/`updatedAt` 是服务端记录时间。
- `deletedAt` 为软删除时间。
- `serverVersion` 用于增量同步。

### Comment

```text
comment
  id
  postId
  text
  createdAt
  updatedAt
  deletedAt
  clientCreatedAt
  clientUpdatedAt
  serverVersion
  createdByDeviceId
  updatedByDeviceId
```

评论是独立 local-first entity，但生命周期从属于 `post`。服务端拒绝给不存在或已删除 post 创建评论。删除父 post 时，服务端软删除其下未删除评论，但只发出 `post_deleted` server change，不额外发逐条 `comment_deleted`。

### Media

```text
media
  id
  postId
  kind
  status
  compressedPath
  originalPath
  thumbnailPath
  originalPreserved
  mimeType
  durationSeconds
  transcriptionText
  width
  height
  compressedSizeBytes
  originalSizeBytes
  checksum
  sortOrder
  createdAt
  updatedAt
  deletedAt
```

`kind` 支持 `image`、`video` 和 `audio`。`transcriptionText` 是 schema version 6 的历史兼容字段；新 iOS 不再本机转写，也不再通过 upload metadata 写入该字段。

`status` 可选：

```text
pending
uploaded
failed
deleted
```

### AISummary

AI 摘要是 media 的 generated metadata。每个 media 第一版最多一个当前 summary record，通过 `mediaId` 唯一约束定位。

```text
ai_summaries
  id
  postId
  mediaId
  status
  format
  language
  overview
  keyPointsJson
  sectionsJson
  summaryText
  documentTitle
  oneLiner
  documentBlocksJson
  inputTranscriptHash
  inputTranscriptLength
  inputDurationSeconds
  promptVersion
  provider
  model
  errorCode
  errorMessage
  requestedByDeviceId
  createdAt
  updatedAt
  deletedAt
```

`status` 可选：

```text
transcribing
summarizing
ready
failed
deleted
```

服务端通过 `ai_summary_updated` 和 `ai_summary_deleted` server changes 同步结果。失败状态只影响 summary record，不改变 post/media/comment 的同步状态。AI media summary job 全局串行执行，避免断网恢复或批量补传后同时启动多个本地 `mlx-whisper` 进程。`/api/v1/admin/status` 暴露轻量 AI summary diagnostics，Settings > Storage & Diagnostics 可查看 `transcribing`、`summarizing`、`ready`、`failed` 计数和非 ready 项的错误码，不暴露 transcript 或 summary 正文。

### AIUsageEvent

`ai_usage_events` 是 privacy-safe 的 AI 使用计量账本。它记录每次外部 AI provider 调用的 feature、subject、provider/model、promptVersion、请求状态、duration、token usage 和本地估算值；不记录 prompt、transcript、summary body、review input JSON 或 provider request/response 正文。provider 返回 usage 时优先使用真实 `inputTokens`、`outputTokens`、`totalTokens` 和 `cachedInputTokens`；没有 usage 时只用字符数估算，并在 Admin/iOS 诊断里计入 estimated requests。

```text
ai_usage_events
  id
  feature
  subjectType
  subjectId
  provider
  model
  promptVersion
  status
  inputChars
  outputChars
  inputTokens
  outputTokens
  totalTokens
  cachedInputTokens
  estimatedInputTokens
  estimatedOutputTokens
  estimatedTotalTokens
  durationMs
  errorCode
  createdAt
```

### SyncOperation

服务端记录设备提交过的操作，用于幂等和排查。

```text
sync_operation
  id
  opId
  deviceId
  type
  entityType
  entityId
  payloadJson
  receivedAt
  appliedAt
  rejectedAt
  rejectionReason
```

`opId` 由客户端生成，同一设备内唯一。服务端对 `(deviceId, opId)` 建唯一索引，避免重复创建。

### ServerChange

服务端变更日志，用于 sync cursor 拉取增量。

```text
server_change
  version
  entityType
  entityId
  changeType
  payloadJson
  createdAt
```

`version` 是单调递增的服务端序号。客户端的 `syncCursor` 指向最后已处理的 `version`。

### MaintenanceJob

维护任务用于 backup、restore、check、promote preparation、export、import 和 Sync Health refresh。它是浏览器刷新安全的状态记录，不是私人内容日志。

```text
maintenance_job
  id
  type
  status
  stage
  progress
  metadataJson
  artifactPath
  errorCode
  errorMessage
  createdAt
  startedAt
  finishedAt
```

`type` 当前包括：

```text
backup_create
backup_check
backup_restore
backup_promote
export_create
import_restore
sync_health_refresh
```

`status` 当前包括：

```text
queued
running
succeeded
failed
cancelled
```

server 启动时会把遗留 `running` jobs 标记为 `failed/server_restarted`，避免旧状态永久卡住。v0.1 使用 process-local serial runner，保证同一时间只执行一个 maintenance job。job metadata 只保存路径、计数、状态和错误码等安全信息，不保存 post/comment/transcript/summary 正文或媒体内容。

### Maintenance Mode

Maintenance mode 是 server 进程内状态，由 restore/promote preparation 进入和退出。它用于暂停 write-heavy routes，避免恢复/切换准备期间继续写入 archive：

- `/api/v1/sync`
- `/api/v1/media/upload`
- `/api/v1/ai/media-summary`
- `/api/v1/ai/media-summary/:summaryId`
- Admin soft delete / clean posts 等 destructive write

Health、Admin status、maintenance job list/detail 和 archive read state 保持可读。

## 5.1 Archive Backup/Restore Design

Archive backup/restore 面向自用灾难恢复，由 Mac server/Admin UI 管理，CLI/restic 只作为调试底层。

### Repository Config

Admin `Archive` tab 通过 `/api/v1/admin/archive/repository` 保存 repository path。server 在数据目录内保存：

```text
archive/archive-config.json
```

repository path 可以是本机目录，也可以是用户明确选择的 iCloud Drive 目录。server 不做云上传集成，只把 iCloud Drive 当作普通文件夹。

项目会在 repository path 下创建或复用：

```text
.private-moments-restic-key
```

这个文件作为 restic password file。用户不需要记额外密码，但谁同时拥有 repository 和 key 文件，谁就可以恢复 archive。

### Backup Source

`backup_create` job 会先构造受控 snapshot source：

```text
archive/staging/<job>/snapshot/
  app.sqlite
  manifest.json
  media/
  backup-manifest.json
```

SQLite 优先通过 `sqlite3 .backup` 生成一致副本，失败时才退回文件复制。snapshot 写入 restic 后，staging 目录会被清理。备份不包含依赖目录、build output、Python venv、运行时 temp 文件或普通日志。

### Restore

`backup_restore` job 使用 restic 把指定 snapshot 恢复到：

```text
archive/restores/<timestamp>-<snapshot>[-label]/
```

server 会扫描恢复结果中的 data directory，并验证：

- `app.sqlite` 存在且 SQLite 可读。
- `manifest.json` 存在。
- `media/` 存在。
- 未删除 media 的 `compressed_path` / `original_path` / `thumbnail_path` 都仍位于恢复目录内并且文件存在。

验证结果写入 job metadata，恢复目录写入 `artifactPath`。

### Promote Preparation

当前 v0.1 不在运行中直接替换 live SQLite database。`backup_promote` 是 promote preparation：

1. 校验确认短语必须是 `PROMOTE <restored-folder-name>`。
2. 进入 maintenance mode。
3. 再次验证 restored data directory。
4. 创建 `pre-promote` backup。
5. 写入 `archive/pending-promote.json`。
6. 退出 maintenance mode。

`pending-promote.json` 包含恢复目录、当前目录、pre-promote backup metadata，以及应写入环境的：

```text
PRIVATE_MOMENTS_DATA_DIR=<restored-data-dir>
DATABASE_URL=file:<restored-data-dir>/app.sqlite
```

Operator 需要停止 server，按该文件切换 env，再重启 server。这样避免在 Prisma 持有 SQLite 连接时热替换数据库。

## 5.2 Export/Import Design

Export/import 是迁移和恢复辅助路径，不替代 restic backup。它同样由 Mac Admin 的 `Archive` tab 管理，并通过 `maintenance_jobs` 运行。

`export_create` job 支持全量或 occurred date range。导出目录写入：

```text
exports/private-moments-export-<timestamp>/
  manifest.json
  archive.json
  preview.md
  media/
```

`manifest.json` 记录包类型、包版本、server/schema version、导出范围和计数。`archive.json` 是权威迁移数据，包含 posts、media metadata、comments、tags、tag aliases、post tag assignments 和 AI summaries。`preview.md` 只用于快速阅读，不作为 import source of truth。导出完成后 server 用 tar 生成：

```text
exports/private-moments-export-<timestamp>.tar.gz
```

`import_restore` job 只导入到新的 staged data directory：

```text
archive/imports/<timestamp>-<label>/data
```

导入流程会先创建新 data dir 和 SQLite DB，跑 Prisma migrations，再导入内容数据。导入会保留 post/comment/media/tag/summary IDs 和 timestamps，恢复 generated AI/tag metadata，复制媒体 payload，并重建 `server_changes`，让新设备可以从 cursor `0` 拉取内容。导入明确排除 users、devices、sync operations 和 maintenance jobs，因此不会带回旧 token、session、device cursor 或旧维护任务。

导入后会验证：

- imported database 可读。
- `devices` 为空。
- `server_changes` 已重建。
- 未删除 media 引用的文件存在且仍位于 staged data dir 内。

如果要把 imported archive 变成当前运行 archive，仍然走 promote/restart 安全流程，而不是 import job 自动替换 live database。

## 6. iOS 本地数据模型

iOS 使用 SQLite，模型与服务端接近，但增加本地状态字段。

### local_post

```text
local_post
  id
  text
  isFavorite
  occurredAt
  localCreatedAt
  localUpdatedAt
  serverVersion
  syncStatus
  deletedAt
```

`syncStatus` 可选：

```text
draft
pending
partial
synced
failed
deleted_pending
```

### local_media

```text
local_media
  id
  postId
  kind
  localCompressedPath
  localOriginalStagingPath
  localThumbnailPath
  remoteCompressedPath
  remoteOriginalPath
  remoteThumbnailPath
  originalPreserved
  uploadStatus
  mimeType
  durationSeconds
  transcriptionText
  transcriptionStatus
  transcriptionError
  transcriptionUpdatedAt
  sortOrder
  checksum
  createdAt
  updatedAt
```

### local_comment

```text
local_comment
  id
  postId
  text
  localCreatedAt
  localUpdatedAt
  serverVersion
  syncStatus
  deletedAt
```

本地评论随 timeline item 一起读取，只在主时间线展示。`syncStatus` 是 iOS 本地兼容字段，用于支持曾经安装过旧评论 schema 的设备，不作为每条评论的 UI 标识展示。删除未同步的本地新评论时，iOS 会取消对应 pending `create_comment` operation，并只做本地软删除；已提交或已同步评论删除时写入 `delete_comment` outbox operation。

### local_ai_summaries

```text
local_ai_summaries
  id
  postId
  mediaId
  status
  format
  language
  overview
  keyPointsJson
  sectionsJson
  summaryText
  documentTitle
  oneLiner
  documentBlocksJson
  inputTranscriptLength
  inputDurationSeconds
  promptVersion
  provider
  model
  errorCode
  errorMessage
  createdAt
  updatedAt
  deletedAt
```

本地 AI summary 随 timeline item 一起读取。`ready` 状态在 timeline 只显示 `Summary ready`，点开 bottom sheet 才显示完整摘要；没有 ready summary 时不显示 Summary 入口，也不回退显示 transcript。新 summary 优先用 `documentTitle`、`oneLiner` 和 `documentBlocksJson` 渲染；老 summary 继续用 `overview`、`keyPointsJson` 和 `sectionsJson` 兼容显示。新 audio 的 `documentTitle` 可以按上面的 `insert_ai_title` 规则写成 post 顶部标题；summary 正文不写回。`transcribing`、`summarizing`、`failed` 和 `deleted` 状态都不会阻塞普通 sync、media upload、评论或标题插入失败/跳过。

### outbox_operation

```text
outbox_operation
  id
  opId
  type
  entityType
  entityId
  payloadJson
  status
  attemptCount
  lastError
  createdAt
  updatedAt
  sentAt
```

`outbox_operation` 是本地优先架构的核心。UI 更新不等待网络成功，所有用户操作先写本地，再进入 outbox。

### sync_state

```text
sync_state
  key
  value
```

关键值：

```text
deviceId
lastSyncCursor
lastSuccessfulSyncAt
```

## 7. API 设计

所有 API 使用 `/api/v1` 前缀。响应中应包含 `serverVersion` 和 `schemaVersion`，至少在认证、健康检查和同步响应中提供。

### 认证

iOS API 使用 Bearer device token：

```http
Authorization: Bearer <device-token>
```

登录后返回长期 token。token 长期有效，可在后台撤销。高风险操作需要重新验证密码。

### Core Endpoints

```text
GET    /api/v1/health
POST   /api/v1/auth/login
GET    /api/v1/devices
DELETE /api/v1/devices/:deviceId
POST   /api/v1/sync
POST   /api/v1/ai/media-summary
DELETE /api/v1/ai/media-summary/:summaryId
POST   /api/v1/media/upload
POST   /api/v1/media/batch-download
GET    /api/v1/media/:mediaId
GET    /api/v1/timeline
GET    /api/v1/posts/:postId
GET    /api/v1/search?q=...
GET    /api/v1/admin/status
GET    /api/v1/admin/logs
GET    /api/v1/admin/posts
GET    /api/v1/admin/posts/:postId
DELETE /api/v1/admin/posts/:postId
GET    /api/v1/admin/devices/:deviceId/clean-posts/preview
POST   /api/v1/admin/devices/:deviceId/clean-posts
GET    /api/v1/admin/maintenance/state
GET    /api/v1/admin/maintenance/jobs
GET    /api/v1/admin/maintenance/jobs/:jobId
POST   /api/v1/admin/maintenance/jobs/sync-health-refresh
GET    /api/v1/admin/archive/repository
POST   /api/v1/admin/archive/repository
POST   /api/v1/admin/archive/repository/init
POST   /api/v1/admin/archive/schedule
GET    /api/v1/admin/archive/snapshots
POST   /api/v1/admin/archive/jobs/backup
POST   /api/v1/admin/archive/jobs/check
POST   /api/v1/admin/archive/jobs/restore
POST   /api/v1/admin/archive/jobs/promote
POST   /api/v1/admin/archive/jobs/export
POST   /api/v1/admin/archive/jobs/import
```

说明：

- `/api/v1/timeline` 和 `/api/v1/posts/:postId` 主要用于读取和调试。
- 离线创建、删除和未来编辑通过 `/api/v1/sync` 处理。
- 图片、语音和视频文件通过 `/api/v1/media/upload` 上传，避免把大文件塞进 sync JSON；新 iOS 不随 multipart metadata 带 `transcriptionText`。
- AI 摘要由 Mac server 在完整 audio/video 上传后后台触发：先用本地 `mlx-whisper` 转写，再调用外部 summary provider；`/api/v1/ai/media-summary` 仍可用于 regenerate。iOS 只拿到 summary metadata 和轻量错误状态。新摘要使用 `media-summary-v4` document block 模型：`documentTitle`、`oneLiner`、`documentBlocks` 是主要渲染字段，旧 `overview`、`keyPoints`、`sections` 保留作兼容；v4 会把 active topic tag/alias 词表作为上下文，用于优先复用现有 AI topic tag。
- iOS 拉取远端图片缩略图和视频 poster 时优先使用 `/api/v1/media/batch-download` 获取 base64 JSON，避免真机/Tailscale 场景下多次二进制下载超时。
- Mac Admin 路由复用 Bearer device token，普通内容发布仍然只在 iOS 端进行。
- `/api/v1/admin/status` 同时给 Mac Admin 和 iOS Settings > Storage & Diagnostics 使用；storage 字段包含 `totalBytes`、`databaseBytes`、`mediaBytes`、`logsBytes`、`availableBytes`，`sync.latestServerChangeVersion` 用于和 iPhone `lastSyncCursor` 对比，`sync.pendingOperations`、`sync.rejectedOperations`、`sync.failedMediaUploads`、`sync.aiNonReady` 和 last-sync timestamps 用于 Sync Health 和 iOS Sync Doctor，`aiSummaries` 字段包含 summary 状态计数和非 ready 项的安全错误 metadata，`aiUsage` 字段包含 Today、This week、This month、All time 的 AI token usage、请求数、失败数、cached input token 和本月按 feature 聚合，`tags` 字段包含安全的标签计数和 AI/manual assignment 计数。诊断页的 `Sync Now` / `Pull Server Changes` 是显式恢复动作，不应被后台 `isSyncing` 禁用；后台同步进行中时再次点击会排 follow-up sync。Sync Doctor 不新增 server contract，只把现有本机和 Mac-side Sync Health 信号分类成安全恢复建议。Mac-side `sync.rejectedOperations` 是原始历史计数，Sync Doctor 只有在本机仍有 pending outbox 且最新 rejected timestamp 晚于最近 successful sync 时，才将其解释为当前 `Blocked`；否则该计数只保留在 Sync Health 原始指标中。

## 8. Sync Endpoint

`sync endpoint` 本质上是一个 HTTP API，但语义是设备与服务器对账，而不是对单一资源做 CRUD。

### 请求草案

```json
{
  "deviceId": "device-uuid",
  "lastSyncCursor": 120,
  "localChanges": [
    {
      "opId": "op-uuid-1",
      "type": "create_post",
      "entityType": "post",
      "entityId": "post-uuid",
      "clientCreatedAt": "2026-04-28T10:00:00.000Z",
      "payload": {
        "text": "去了咖啡店",
        "occurredAt": "2026-04-28T09:30:00.000Z",
        "mediaIds": ["media-uuid-1"]
      }
    },
    {
      "opId": "op-uuid-2",
      "type": "delete_post",
      "entityType": "post",
      "entityId": "post-uuid",
      "clientCreatedAt": "2026-04-28T11:00:00.000Z",
      "payload": {
        "deletedAt": "2026-04-28T11:00:00.000Z"
      }
    }
  ]
}
```

### 响应草案

```json
{
  "serverVersion": "0.1.0",
  "schemaVersion": 16,
  "acceptedOps": ["op-uuid-1", "op-uuid-2"],
  "rejectedOps": [],
  "serverChanges": [
    {
      "version": 121,
      "entityType": "post",
      "entityId": "post-uuid",
      "changeType": "post_created",
      "payload": {
        "id": "post-uuid",
        "text": "去了咖啡店",
        "occurredAt": "2026-04-28T09:30:00.000Z",
        "deletedAt": null
      }
    }
  ],
  "nextSyncCursor": 121
}
```

### 同步规则

- 客户端先写本地数据库，再写 outbox。
- App 打开后自动触发同步。
- 切到后台或锁屏后尽量继续传完当前同步任务。
- 每个操作必须有 `opId`。
- 服务端使用 `(deviceId, opId)` 保证幂等。
- `syncCursor` 表示客户端已处理到的服务端 `server_change.version`。
- 同步时客户端上传本地变化，同时拉取 `lastSyncCursor` 之后的服务端变化。
- 多设备冲突使用最后写入胜出。
- 服务端保留操作日志用于排查。
- iOS 只在成功应用全部 `serverChanges` 后推进本地 cursor。
- iOS 兼容带毫秒和不带毫秒的 ISO8601 时间；解析失败会让本轮同步失败，而不是静默跳过变更后推进 cursor。
- `didApplySyncRecoveryV1` 用于 2026-04-29 的一次性恢复：如果本地为空或旧 cursor 可能已经错误推进，启动后会把 cursor 重置为 0 从服务端完整拉取。
- 评论通过 `create_comment` 和 `delete_comment` 同步，对应 server changes 是 `comment_created` 和 `comment_deleted`。iOS 应用评论变更时如果找不到父 post，必须让本轮同步失败，不能推进 cursor。
- `update_media_transcription` / `media_transcription_updated` 保留为旧客户端兼容同步；新 iOS 不再创建本地转写 operation。
- AI 摘要通过独立 endpoint 生成，但结果仍通过 server changes 恢复和多设备同步；对应 server changes 是 `ai_summary_updated` 和 `ai_summary_deleted`。iOS 应用 AI summary 变更时如果找不到父 post 或 media，必须让本轮同步失败，不能推进 cursor。
- 标签通过 `upsert_tag`、`archive_tag`、`restore_tag`、`delete_tag`、`merge_tag`、`upsert_tag_alias`、`delete_tag_alias` 和 `set_post_tags` 同步；对应 server changes 是 `tag_updated/deleted`、`tag_alias_updated/deleted`、`post_tag_updated/deleted` 和 `post_tag_state_updated`。`delete_tag` 只允许 archived 且非 default 的 tag，用于释放错误词表项的 normalized name；server 会先发 assignment/alias 删除变更，再发 `tag_deleted`。`merge_tag` 下发的 `post_tag_updated` 可能保留原 assignment `id` 但改变 `tagId`，iOS 必须按 `id` 更新本地关联并处理 `(postId, tagId)` 冲突。iOS 应用 post tag assignment 时如果缺少本地 tag，应让本轮同步失败，不能推进 cursor。

## 9. 媒体上传与回填流程

媒体文件不直接放进 `/api/v1/sync`。

推荐流程：

1. iOS 生成 `postId` 和 `mediaId`。
2. iOS 生成压缩展示图，并移除 EXIF/GPS。
3. 如果用户选择保留原图，iOS 保留原图待上传副本。
4. iOS 本地创建 post 和 media 记录。
5. iOS 创建 `create_post` outbox operation。
6. 同步时先通过 `/api/v1/media/upload` 上传媒体文件；视频额外上传 poster 作为 `thumbnail` variant。
7. 完整 audio/video 上传成功后，Mac server 异步启动 AI summary job。
8. iOS 安排数次延迟 follow-up sync，用于拉取稍后生成的 `ai_summary_updated`。如果没有本地 pending work，app 回到前台、手动 `Sync Now` 或 `Pull Server Changes` 仍会拉取这种 server-originated metadata。空闲 `/sync` 检查使用短 timeout 以便私有主地址不可达时快速尝试 fallback；恢复/本地变更同步保留更长 timeout。Storage & Diagnostics refresh 只做只读状态检查和 cursor 对比，避免进入诊断页就启动隐藏同步。
9. 媒体可以逐项成功或失败。
10. iOS 通过 `/api/v1/sync` 同步帖子、媒体元数据和 AI summary metadata。
11. 服务端记录部分同步状态。
12. 失败媒体保留在本地队列中自动重试。

iOS 在保存展示图和上传文件前都会压缩图片。当前压缩展示策略是最大边 `1600px`、JPEG 质量 `0.72`，并移除 EXIF/GPS 等隐私元数据。上传时再次走压缩路径，因此旧版本遗留的 pending 大图也会在下一次上传前被压缩。

媒体上传逐项执行；任意媒体失败不会阻塞本地时间线展示。失败后本地状态保持可重试，并由 sync retry 调度器按 5s、20s、60s、120s、300s 间隔自动重试。iOS 端上传队列优先处理新鲜 `pending` media，再处理旧 `failed` retry，避免一个早期超时音频挡住后面的语音。audio/video 上传会先写入临时 multipart 文件，再用 file-backed upload 发送，降低断网恢复和较大媒体上传时的内存压力。Settings > Storage & Diagnostics 提供 `Retry Uploads`，用于把 failed media 重新排为 pending 并立即触发同步。

远端媒体回填：

1. iOS 应用 `media_uploaded` 或远端 post 变更后，找出本地缺失的已上传图片缩略图或视频 poster。
2. iOS 调用 `POST /api/v1/media/batch-download`，默认请求 `thumbnail` variant。
3. 服务端用 macOS `sips` 按需生成最大边 800px 的 JPEG 缩略图，并把过大的旧缩略图重新压缩到目标范围。
4. 服务端返回 base64 JSON：`id`、`variant`、`contentType`、`fileName`、`base64`。
5. iOS 写入本地 media cache：图片缩略图更新 `localCompressedPath`，视频 poster 更新 `localThumbnailPath`。

语音和视频完整文件默认不自动回填；点击播放时通过 `GET /api/v1/media/:mediaId?variant=compressed` 按需下载，成功后保存在本机缓存。历史转写文本属于 legacy metadata；新 summary 结果通过 sync 回填，不依赖完整媒体文件下载。Settings > Storage & Diagnostics 的清理动作只清理这类可重新下载的完整语音/视频缓存。

保留 `GET /api/v1/media/:mediaId?variant=...` 作为单文件下载、完整音视频按需播放下载和 Admin 图片预览入口。iOS 主同步路径优先使用批量 JSON 下载缩略图/poster，因为 2026-04-29 真机验证发现多次独立二进制下载在 Tailscale/iOS 组合下更容易超时。

### 部分同步

如果文字和部分媒体已同步，但还有媒体上传失败，帖子状态为 `partial`。UI 可展示本地完整内容，设置页显示失败明细。

## 10. 删除和清理

MVP 支持删除，不支持完整回收站 UI。

删除流程：

1. 用户在 iOS 删除 post。
2. iOS 设置本地 `deletedAt`。
3. iOS 同时隐藏/软删除该 post 下本地评论。
4. iOS 创建 `delete_post` outbox operation。
5. 同步成功后服务端设置 `post.deletedAt`、相关 `media.deletedAt` 和该 post 下未删除 comments 的 `deletedAt`。
6. 服务端 30 天后永久删除数据库记录和相关媒体文件。

清理任务可由 Mac 服务端定时执行，也可在服务启动时执行一次。

当前实现会在服务启动时执行一次清理，并在服务运行中每 6 小时清理一次 30 天前软删除的帖子和媒体文件。删除文件时只允许删除数据目录内部的相对路径，避免误删数据目录外文件。

## 11. Mac 后台

后台 UI 由 React + Vite 实现，构建后作为静态资源由 Fastify 托管。

MVP 页面：

- Overview：服务状态、版本、schemaVersion。
- Devices：设备列表、撤销设备。
- Storage：数据目录、数据库大小、媒体大小。
- Sync：同步状态和失败概览。
- Logs：文件日志。
- Posts：内容运维列表、筛选、详情抽屉、图片预览、语音/视频转写查看、软删除和按设备清理测试数据。
- Archive：restic repository 配置、key 文件说明、manual backup、daily schedule、snapshot list/check、staged restore、promote preparation 和 recent maintenance jobs。
- Sync Health：最新 server change version、pending/rejected sync operations、failed media uploads、AI non-ready count 和 last sync timestamps。

后续页面：

- Trash：回收站和恢复。
- Search：独立搜索增强；当前 Posts 页已有文本搜索。

## 12. 日志

服务端写文件日志到：

```text
~/Library/Application Support/PrivateMoments/logs/
```

MVP 不强制日志轮转，但日志格式应结构化，便于后台展示和排查。

建议字段：

```json
{
  "time": "2026-04-28T10:00:00.000Z",
  "level": "info",
  "event": "sync.completed",
  "deviceId": "device-uuid",
  "acceptedOps": 3,
  "failedUploads": 1
}
```

## 13. launchd 自启动

Mac 服务端第一版使用 `launchd` 登录自启动。

设计要求：

- 服务进程读取固定数据目录。
- 配置文件可放在数据目录或 `server/config`。
- stdout/stderr 可由 launchd 接管。
- 应用自身仍写文件日志。
- 后续可增加菜单栏 App 包装启动状态。

## 14. OpenAPI 与同步协议文档

`shared/openapi.yaml` 描述：

- `/api/v1/health`
- `/api/v1/auth/login`
- `/api/v1/devices`
- `/api/v1/sync`
- `/api/v1/ai/media-summary`
- `/api/v1/media/upload`
- `/api/v1/media/batch-download`
- `/api/v1/timeline`
- `/api/v1/search`
- `/api/v1/admin/status`
- `/api/v1/admin/logs`
- `/api/v1/admin/posts`
- Admin status 的 storage diagnostics 字段。
- Media schema 的 audio/video `transcriptionText` 字段。
- AI summary request/response schema 和 `ai_summary_updated` / `ai_summary_deleted` 同步语义。
- Bearer token 认证。
- 通用错误响应。

`shared/sync-protocol.md` 描述：

- `syncCursor` 语义。
- `opId` 幂等。
- outbox 处理顺序。
- 媒体上传与帖子同步顺序。
- 图片压缩、逐项上传和失败重试。
- 旧客户端语音/视频转写 metadata 的 `update_media_transcription` 兼容同步。
- 多设备最后写入胜出。
- 删除和软删除。
- 部分同步状态。

## 15. 安全

MVP 安全边界：

- Tailscale 或私有 VPN。
- 单用户密码登录。
- Bearer device token。
- 服务端保存 token hash。
- 设备可撤销。
- 高风险操作重新验证密码。
- 外部 AI API key 只放在 Mac server 环境变量中，不进入 iOS、本地文档示例或日志。
- Mac 文件权限。

不做：

- 端到端加密。
- 应用级本地数据库加密。
- 多用户权限。
- OAuth。
- 2FA。

## 16. 性能和可靠性

### iOS

- 时间线本地优先渲染。
- 本地 SQLite 保存全部文本元数据。
- 已下载图片缩略图、视频 poster 和完整语音/视频缓存保存在本地。
- 旧图片和远端完整语音/视频按需下载。
- 同步不阻塞主 UI。
- 图片压缩在后台任务中执行。
- 失败同步和上传自动延迟重试。
- Settings > Storage & Diagnostics 可快速查看本地占用、同步健康状态、AI summary 诊断和 AI token usage。

### Mac

- SQLite 对单用户场景足够。
- 媒体文件存磁盘，数据库只存路径和元数据。
- `server_change.version` 支持增量同步。
- sync endpoint 支持批量操作和重试。
- `/api/v1/admin/status` 暴露服务端数据目录存储诊断、AI summary 诊断和 AI token usage，供 Admin 和 iOS Settings 使用。
- AI summary provider 失败只写入 `ai_summaries.status = failed`，不影响 post/media/comment sync，也不把私人 transcript 或 summary 正文写入正常日志。

## 17. 未来阶段

第二阶段：

- 回收站 UI。
- 应用内一键 zip 备份导出。
- 更完整的 storage cleanup。
- 多设备冲突提示。
- 原图保留策略和空间管理。

第三阶段：

- iCloud Drive 备份包输出。
- 多设备体验增强。
- 原生后台传输优化。
- 菜单栏 Mac App。
- 开源安装文档完善。

## 18. 已确认架构决策

- iOS 原生 App 是主入口。
- Mac 是服务器和后台。
- 使用 Tailscale 或私有 VPN，不公网暴露。
- Mac 是权威归档源。
- iPhone 是本地优先缓存 + 待同步队列。
- 单用户，但数据结构支持多设备。
- 多设备冲突使用最后写入胜出 + 操作日志。
- 时间线本地优先渲染 + 后台增量同步。
- iPhone 缓存全部元数据、已下载图片缩略图、视频 poster 和按需下载的完整语音/视频缓存。
- 文本搜索在 iPhone 本地和 Mac 后台都支持，覆盖动态正文、评论和语音/视频转写文本。
- MVP 做发布、同步、详情、编辑、评论、音视频、转写、收藏、筛选、删除和 Mac Admin Posts 运维。
- 第一版 AI 只做用户手动触发的 audio/video summary；不做自动人格、评论、评测、archive-wide analysis 或语义搜索。
- 回收站 UI、备份导出、多设备冲突提示后置。
