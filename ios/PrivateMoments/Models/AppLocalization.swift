import Foundation
import SwiftUI

enum AppResolvedLanguage: String, Equatable {
    case english
    case simplifiedChinese
}

enum AppLanguageMode: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String {
        rawValue
    }

    var resolvedLanguage: AppResolvedLanguage {
        switch self {
        case .system:
            return Self.systemResolvedLanguage
        case .english:
            return .english
        case .simplifiedChinese:
            return .simplifiedChinese
        }
    }

    func title(language: AppResolvedLanguage) -> String {
        switch self {
        case .system:
            return L10n.t("System", language)
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        }
    }

    var systemImageName: String {
        switch self {
        case .system:
            return "globe"
        case .english:
            return "character.book.closed"
        case .simplifiedChinese:
            return "character.book.closed.zh"
        }
    }

    private static var systemResolvedLanguage: AppResolvedLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }
}

enum AILanguageMode: String, CaseIterable, Identifiable {
    case auto
    case chinese
    case english

    var id: String {
        rawValue
    }

    func title(language: AppResolvedLanguage) -> String {
        switch self {
        case .auto:
            return L10n.t("Auto", language)
        case .chinese:
            return L10n.t("Chinese", language)
        case .english:
            return L10n.t("English", language)
        }
    }

    func subtitle(language: AppResolvedLanguage) -> String {
        switch self {
        case .auto:
            return L10n.t("Follow the audio language", language)
        case .chinese:
            return L10n.t("Always summarize in Chinese", language)
        case .english:
            return L10n.t("Always summarize in English", language)
        }
    }

    var requestValue: String {
        switch self {
        case .auto:
            return "auto"
        case .chinese:
            return "zh"
        case .english:
            return "en"
        }
    }
}

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppResolvedLanguage = AppLanguageMode.system.resolvedLanguage
}

extension EnvironmentValues {
    var appLanguage: AppResolvedLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}

enum L10n {
    static func t(_ key: String, _ language: AppResolvedLanguage) -> String {
        guard language == .simplifiedChinese else {
            return key
        }

        return simplifiedChinese[key] ?? key
    }

    static func tagName(_ tag: TimelineTag, language: AppResolvedLanguage) -> String {
        guard tag.isDefaultPrimaryTag else {
            return tag.name
        }

        return DefaultPrimaryTagLocalization.displayName(for: tag.name, language: language)
    }

    static func defaultPrimaryTagSearchNames(for tag: TimelineTag) -> [String] {
        guard tag.isDefaultPrimaryTag else {
            return [tag.name]
        }

        return DefaultPrimaryTagLocalization.searchNames(for: tag.name)
    }

    private static let simplifiedChinese: [String: String] = [
        "24h distribution": "24 小时分布",
        "Add": "添加",
        "Add alias": "添加别名",
        "Add from Library": "从相册添加",
        "Add Photos": "添加照片",
        "Add Video": "添加视频",
        "Add Primary Tag": "添加主标签",
        "Add Topic Tag": "添加主题标签",
        "Advanced": "高级",
        "Advanced Sync": "高级同步",
        "AI Language": "AI 语言",
        "AI & Tags": "AI 与标签",
        "AI not ready": "AI 未完成",
        "AI Title Auto-Insert": "AI 标题自动嵌入",
        "AI assignments": "AI 分配",
        "AI suggested": "AI 建议",
        "Alias": "别名",
        "Aliases": "别名",
        "Active": "开启",
        "Active days": "活跃天数",
        "Afternoon": "下午",
        "All": "全部",
        "All clear": "全部正常",
        "All icons": "全部图标",
        "Any": "全部",
        "Appearance": "外观",
        "Archive": "归档",
        "Archive repository": "归档仓库",
        "Archived": "已归档",
        "Attributes": "属性",
        "Audio and video": "音频和视频",
        "Automatic Sync": "自动同步",
        "Automatic Sync is off. New work stays on this iPhone until you tap Sync Now or turn it back on.": "自动同步已关闭。新内容会留在这台 iPhone 上，直到你点击立即同步或重新打开自动同步。",
        "Auto-generate Weekly Review": "自动生成每周回顾",
        "Auto": "自动",
        "Available disk": "可用磁盘",
        "Backup": "备份",
        "Backup actions stay in Mac Admin.": "备份操作仍在 Mac Admin 中执行。",
        "Backup check": "备份检查",
        "Backup Status": "备份状态",
        "Blocked": "已阻塞",
        "Calendar": "日历",
        "Cancel": "取消",
        "Category": "类别",
        "Chinese": "中文",
        "Choose a preset or enter a valid SF Symbol name.": "选择预设图标，或输入有效的 SF Symbol 名称。",
        "Choose": "选择",
        "Clear": "清除",
        "Clear Audio and Video Cache": "清除音频和视频缓存",
        "Clear Filters": "清除筛选",
        "Clear Month Filter": "清除月份筛选",
        "Close": "关闭",
        "Comment text": "评论内容",
        "Commented": "有评论",
        "Comments": "评论",
        "Completed": "已完成",
        "Connection": "连接",
        "Content": "内容",
        "Continue Editing Draft": "继续编辑草稿",
        "Copied": "已复制",
        "Copy": "复制",
        "Copy text": "复制正文",
        "Configured": "已配置",
        "Created": "创建时间",
        "Custom HEX color": "自定义 HEX 颜色",
        "Custom icon": "自定义图标",
        "Dark": "深色",
        "Database": "数据库",
        "Date": "日期",
        "Daily": "日常",
        "Day Review": "当天回看",
        "Daily rhythm": "每日节奏",
        "Delete": "删除",
        "Delete Permanently": "永久删除",
        "Delete comment?": "删除评论？",
        "Delete Review": "删除回顾",
        "Delete review?": "删除这篇回顾？",
        "Delete summary?": "删除摘要？",
        "Delete this moment?": "删除这条 moment？",
        "Deleting review": "正在删除回顾",
        "Device": "设备",
        "Device ID": "设备 ID",
        "Diagnostics": "诊断",
        "Discard": "丢弃",
        "Discard Draft": "丢弃草稿",
        "Discard draft?": "丢弃草稿？",
        "Done": "完成",
        "Downloaded Media Cache": "已下载媒体缓存",
        "Edit Moment": "编辑 Moment",
        "Edit Tags": "编辑标签",
        "English": "英文",
        "Enter a valid SF Symbol name.": "请输入有效的 SF Symbol 名称。",
        "Error": "错误",
        "Evening": "晚上",
        "Export": "导出",
        "Failed": "失败",
        "Favorite": "收藏",
        "Favorites": "收藏",
        "Feature Modules": "功能模块",
        "Feedback": "反馈",
        "Filter moments": "筛选 moments",
        "Finished": "完成时间",
        "Food": "饮食",
        "More media": "更多媒介",
        "No check-ins for this item": "这个项目还没有打卡",
        "Photo": "照片",
        "Remove photo": "移除照片",
        "Filter calendar": "筛选日历",
        "Follow the audio language": "跟随音频主体语言",
        "Future date": "未来日期",
        "Generate Last 7 Days": "生成最近 7 天",
        "Generating review": "正在生成回顾",
        "Gentle Suggestions": "温和建议",
        "Hide this theme": "隐藏这个主题",
        "Host": "主机",
        "Image unavailable": "图片不可用",
        "Import": "导入",
        "Importing shared item": "正在导入分享内容",
        "Idle": "空闲",
        "Initialized": "已初始化",
        "Invalid HEX": "HEX 无效",
        "Invalid icon": "无效图标",
        "Jump to Month": "跳到该月",
        "Jump to date": "跳转日期",
        "Key file": "密钥文件",
        "Late Night": "深夜",
        "Latest backup job": "最近备份任务",
        "Latest snapshot": "最近快照",
        "Light": "浅色",
        "Linked": "已连接",
        "Local-only": "仅本地",
        "Local-only mode keeps new work on this iPhone until you tap Sync Now or turn automatic sync back on.": "仅本地模式会把新内容保留在这台 iPhone 上，直到你点击立即同步或重新打开自动同步。",
        "Log In": "登录",
        "Log In First": "先登录",
        "Log Out": "退出登录",
        "Logging In": "正在登录",
        "Login": "登录",
        "Last backup": "最近备份",
        "Last rejected sync": "最近拒绝同步",
        "Last snapshot": "最近快照",
        "Last successful sync": "最近成功同步",
        "Mac Server": "Mac 服务器",
        "Mac Operations": "Mac 运维",
        "Mac change version": "Mac 变更版本",
        "Mac reachability": "Mac 可达性",
        "Maintenance": "维护模式",
        "Manual assignments": "手动分配",
        "Match Source": "命中来源",
        "Media": "媒体",
        "Media files": "媒体文件",
        "Media unavailable": "媒体不可用",
        "Merge": "合并",
        "Merge Into": "合并到",
        "Merge Selected...": "合并所选...",
        "Merge and Archive This Tag": "合并并归档此标签",
        "Moment": "Moment",
        "Moments": "Moments",
        "Month Stats": "月度统计",
        "Morning": "上午",
        "Movement": "运动",
        "Mind": "精神",
        "Name": "名称",
        "Needs Sync": "需要同步",
        "Needs attention": "需要处理",
        "Missing media": "缺失媒体",
        "Missed the point": "没有抓住重点",
        "New Moment": "新 Moment",
        "New Tag": "新标签",
        "Next backup": "下次备份",
        "No": "否",
        "No aliases": "没有别名",
        "No backup job yet": "还没有备份任务",
        "No matching icons": "没有匹配的图标",
        "No check-ins yet": "还没有 check-ins",
        "No records in this time bucket": "这个时间段还没有记录",
        "No snapshot yet": "还没有快照",
        "No time visualization": "未开启时间可视化",
        "No pending operations": "没有待处理操作",
        "No repair action available": "没有可用的修复动作",
        "No sync problems found.": "没有发现同步问题。",
        "No tags": "没有标签",
        "No moments on this day": "这一天没有 moments",
        "No moments yet": "还没有 moments",
        "Not configured": "未配置",
        "No weekly reviews yet": "还没有每周回顾",
        "No target topic tags": "没有可合并的主题标签",
        "No topic tags yet": "还没有主题标签",
        "None": "无",
        "Not initialized": "未初始化",
        "Not logged in": "未登录",
        "OK": "好",
        "Off": "关闭",
        "Only the available photo slots were added.": "只添加了剩余可用数量的照片。",
        "Open day review": "打开当天回看",
        "Open loops": "开放循环",
        "Open moment preview": "打开 moment 预览",
        "Open moment detail": "打开 moment 详情",
        "Open Settings and log in to your Mac server.": "打开设置并登录你的 Mac 服务器。",
        "Operation counts do not include private text bodies.": "操作计数不包含私人正文内容。",
        "Organization": "组织",
        "Outbox": "发件箱",
        "Password": "密码",
        "Pending changes": "待同步变更",
        "Pending uploads": "待上传",
        "Paths": "路径",
        "Progress": "进展",
        "Queued": "排队中",
        "Progress and Open Loops": "进展与开放循环",
        "Publish as Moment": "发布为 Moment",
        "Publish Weekly Review": "发布每周回顾",
        "Recent Records": "最近记录",
        "Pull Server Changes": "拉取服务器变更",
        "Posts": "内容",
        "Primary": "主标签",
        "Primary Tag": "主标签",
        "Primary Tags": "主标签",
        "Previous month": "上个月",
        "Processing video": "正在处理视频",
        "Promote": "切换准备",
        "Publish": "发布",
        "Publishing": "正在发布",
        "Ready": "已完成",
        "Reason": "原因",
        "Rebuild From Server": "从服务器重建",
        "Rebuilding": "正在重建",
        "Reachable": "可连接",
        "Re-download Missing Media": "重新下载缺失媒体",
        "Refresh diagnostics": "刷新诊断",
        "Recent Reviews": "最近回顾",
        "Recent failed job": "最近失败任务",
        "Recovery files": "恢复文件",
        "Regenerate": "重新生成",
        "Regenerating": "正在重新生成",
        "Regenerating review": "正在重新生成回顾",
        "Review deleted": "回顾已删除",
        "Review failed": "回顾生成失败",
        "Reviews": "回顾",
        "Rhythm": "节奏",
        "records": "条记录",
        "Remove audio or video before adding photos.": "请先移除音频或视频，再添加照片。",
        "Remove favorite": "取消收藏",
        "Repository": "仓库",
        "Repository path": "仓库路径",
        "Restore": "恢复",
        "Restore Selected": "恢复所选",
        "Restic": "Restic",
        "Retry Uploads": "重试上传",
        "Running": "运行中",
        "Running job": "运行中任务",
        "Save": "保存",
        "Save Changes": "保存更改",
        "Save Server": "保存服务器",
        "Search": "搜索",
        "Search icons": "搜索图标",
        "Search match sources": "搜索命中来源",
        "Send": "发送",
        "Server": "服务器",
        "Server & Device": "服务器与设备",
        "Server failed media": "服务器失败媒体",
        "Server pending ops": "服务器待处理操作",
        "Server rejected ops": "服务器拒绝操作",
        "Server rejected sync work": "服务器拒绝了同步工作",
        "Server URL": "服务器 URL",
        "Selected icon": "当前图标",
        "Schema": "Schema",
        "Schedule": "计划",
        "Settings": "设置",
        "Share": "分享",
        "Short note": "简短说明",
        "Show Tags in Timeline": "在时间线显示标签",
        "Show This Month": "显示本月",
        "SF Symbol name": "SF Symbol 名称",
        "Snapshot": "快照",
        "Started": "开始时间",
        "Status": "状态",
        "Storage": "存储",
        "Storage & Diagnostics": "存储与诊断",
        "State Response": "状态回应",
        "Summary": "摘要",
        "Summary failed": "摘要失败",
        "Summary ready": "摘要已完成",
        "Summary regenerating": "摘要正在重新生成",
        "Summary update failed": "摘要更新失败",
        "Succeeded": "成功",
        "Sync": "同步",
        "Sync Doctor": "同步医生",
        "Sync Health": "同步健康",
        "Sync Now": "立即同步",
        "Synced": "已同步",
        "Syncing": "同步中",
        "System": "跟随系统",
        "Tag": "标签",
        "Tag already exists": "标签已存在",
        "Tag color": "标签颜色",
        "Tags": "标签",
        "This iPhone": "这台 iPhone",
        "This iPhone has local changes or media uploads waiting to sync.": "这台 iPhone 有本地变更或媒体上传等待同步。",
        "This iPhone is behind": "这台 iPhone 落后于 Mac",
        "Timeline": "时间线",
        "Themes": "主题",
        "Too dry": "太干",
        "Too much inference": "推断太多",
        "Topic": "主题",
        "Topic Tags": "主题标签",
        "Topics": "主题",
        "Total": "总计",
        "Transcribing": "转录中",
        "Type": "类型",
        "Use Camera": "使用相机",
        "Usage": "使用次数",
        "Waiting": "等待",
        "Work & Home": "工作与家庭",
        "You can add up to 9 photos.": "最多可以添加 9 张照片。",
        "Always summarize in Chinese": "始终用中文总结",
        "Always summarize in English": "始终用英文总结",
        "AI Summaries": "AI 摘要",
        "AI summaries still running": "AI 摘要仍在处理",
        "AI summaries are still processing on the Mac. This does not block sync.": "AI 摘要仍在 Mac 上处理。这不会阻塞同步。",
        "AI Token Usage": "AI Token 用量",
        "AI tags": "AI 标签",
        "AI decides": "由 AI 决定",
        "Add comment": "添加评论",
        "All Moments": "全部 Moments",
        "All time": "总累计",
        "All synced": "全部已同步",
        "Any Match": "任意命中",
        "Apply": "应用",
        "Apply Color": "应用颜色",
        "Archive Selected": "归档所选",
        "Audio": "音频",
        "Audio moment": "音频 moment",
        "Avg/active day": "活跃日均",
        "Busiest day": "最多的一天",
        "Cancel comment": "取消评论",
        "Cached input": "缓存输入",
        "Check-ins rhythm": "Check-ins 节奏",
        "Checking": "检查中",
        "Checking storage": "正在检查存储",
        "Change Color Selected...": "修改所选颜色...",
        "Clear downloaded media cache?": "清除已下载媒体缓存？",
        "Clear filters": "清除筛选",
        "Close video": "关闭视频",
        "Color": "颜色",
        "Comment": "评论",
        "Commenting on:": "评论：",
        "Comments can be up to": "评论最多",
        "Continue editing draft?": "继续编辑草稿？",
        "Delete Selected": "删除所选",
        "Delete Tag Permanently?": "永久删除标签？",
        "Delete Tags Permanently?": "永久删除标签？",
        "Delete moment": "删除 moment",
        "Details": "详情",
        "Discard edit draft?": "丢弃编辑草稿？",
        "Downloaded full audio and video files will be removed from this iPhone. They can be downloaded again from your Mac when played.": "已下载的完整音频和视频会从这台 iPhone 移除。之后播放时可以再从 Mac 下载。",
        "Duration": "时长",
        "Edit moment": "编辑 moment",
        "Edit tags": "编辑标签",
        "Edited": "已编辑",
        "Estimated requests": "估算请求",
        "Failed requests": "失败请求",
        "Editing is available after this moment finishes syncing.": "这条 moment 完成同步后可以编辑。",
        "Failed uploads": "上传失败",
        "Key Points": "要点",
        "Language": "语言",
        "Linked to": "已连接到",
        "Loading": "加载中",
        "Log in to sync": "登录以同步",
        "Logs": "日志",
        "Long press to delete comment": "长按删除评论",
        "Mac server unavailable": "Mac 服务器不可用",
        "Matched comment": "命中评论",
        "Matched summary": "命中摘要",
        "Matched tag": "命中标签",
        "Matched text": "命中正文",
        "Matched transcript": "命中文稿",
        "Media summaries": "媒体摘要",
        "Mac media uploads need inspection": "Mac 媒体上传需要检查",
        "Mac Storage": "Mac 存储",
        "Merge Selected Into": "合并所选到",
        "Moment unavailable": "Moment 不可用",
        "More": "更多",
        "Move image left": "向左移动图片",
        "Move image right": "向右移动图片",
        "New moment": "新 moment",
        "New topic": "新主题",
        "No matching moments": "没有匹配的 moments",
        "No moments": "没有 moments",
        "No results": "没有结果",
        "Open image": "打开图片",
        "Open video": "打开视频",
        "Photo access denied": "没有照片访问权限",
        "Photo moment": "照片 moment",
        "Pin moment": "置顶 moment",
        "Pinned": "置顶",
        "Post Text": "正文",
        "Regenerating summary...": "正在重新生成摘要...",
        "Recommended": "建议",
        "Remote changes": "远端变更",
        "Remove": "移除",
        "Remove audio": "移除音频",
        "Remove image": "移除图片",
        "Remove video": "移除视频",
        "Requests": "请求数",
        "Restore it from the Archived section instead of creating a duplicate.": "请从已归档区域恢复它，而不是创建重复标签。",
        "Save failed": "保存失败",
        "Save image to Photos": "保存图片到照片",
        "Saved to Photos": "已保存到照片",
        "Selected topic tags will be archived and kept as aliases of the target.": "所选主题标签会被归档，并作为目标标签的别名保留。",
        "Selected Primary Tags": "已选主标签",
        "Share image": "分享图片",
        "Show less": "收起",
        "See Sync Health for raw metrics": "查看 Sync Health 原始指标",
        "Signals": "信号",
        "Stuck for": "卡住",
        "Summarizing": "总结中",
        "Summarizing...": "正在总结...",
        "Summary unavailable": "摘要不可用",
        "Sync Doctor only uses existing Sync Health signals. Repair actions run only when tapped.": "Sync Doctor 只使用现有 Sync Health 信号。修复动作只会在你点击后执行。",
        "Tag names are shared across": "标签名称在以下类型中共享：",
        "Tap Sync Now to retry. If it still fails, check the Mac server or configured remote access URL.": "点击立即同步重试。如果仍然失败，请检查 Mac 服务器或已配置的远程访问 URL。",
        "Text": "文本",
        "Time Heatmap": "时间热力图",
        "Time Insights": "时间洞察",
        "Time Line": "时间折线",
        "Time visualization": "时间可视化",
        "The current summary will update when the new result is ready.": "新结果完成后，当前摘要会自动更新。",
        "The Mac reports failed media uploads. Check Sync Health and Mac logs before retrying.": "Mac 报告有失败的媒体上传。重试前请查看 Sync Health 和 Mac 日志。",
        "The previous summary is still available. Try regenerating again when the Mac is reachable.": "之前的摘要仍可查看。Mac 可连接时可以再试一次。",
        "There is an unsaved edit draft for this moment.": "这条 moment 有一份未保存的编辑草稿。",
        "This can take a moment.": "这可能需要一点时间。",
        "This iPhone cursor": "这台 iPhone 游标",
        "This month": "本月",
        "This week": "本周",
        "Today": "今天",
        "Choose Time Line or Time Heatmap in Manage to show insights here.": "在 Manage 中选择时间折线或时间热力图后，这里会显示洞察。",
        "Daily reset": "每日重置",
        "This removes": "这会移除",
        "This removes only the generated AI summary.": "这只会移除生成的 AI 摘要。",
        "This removes the moment from your timeline and syncs the deletion to your Mac.": "这会从时间线删除该 moment，并把删除同步到 Mac。",
        "This updates only the color of selected primary tags.": "这里只会更新所选主标签的颜色。",
        "Topics appear after AI summaries create them.": "主题标签会在 AI 摘要生成后出现。",
        "Transcribing media...": "正在转录媒体...",
        "Transcript": "文稿",
        "Try again after sync finishes.": "同步完成后再试一次。",
        "Try regenerating again when the Mac is reachable.": "Mac 可连接时可以再重新生成。",
        "Unavailable": "不可用",
        "Uncertainty": "不确定性",
        "Unpin moment": "取消置顶 moment",
        "Updated": "更新于",
        "Uptime": "运行时间",
        "Useful": "有用",
        "Use this only when this iPhone looks out of date. Normal sync is enough for daily use.": "只有当这台 iPhone 看起来明显落后时才使用。日常使用普通同步就够了。",
        "Video": "视频",
        "Video moment": "视频 moment",
        "Video unavailable": "视频不可用",
        "Version": "版本",
        "Check Sync Health and Mac logs before retrying rejected sync work.": "重试被拒绝的同步工作前，请先查看 Sync Health 和 Mac 日志。",
        "Failed media uploads are waiting on this iPhone.": "这台 iPhone 上有失败的媒体上传等待处理。",
        "Media needs re-download": "媒体需要重新下载",
        "Some uploaded media is missing locally and can be downloaded again.": "部分已上传媒体在本机缺失，可以重新下载。",
        "Sync work is waiting": "同步工作正在等待",
        "Uploads need retry": "上传需要重试",
        "Your Mac has newer changes than this iPhone.": "Mac 上有比这台 iPhone 更新的变更。",
        "Weekday x time": "星期 x 时间",
        "Weekly Review": "每周回顾",
        "Yes": "是",
        "What did it miss?": "它漏掉了什么？",
        "Worth Revisiting": "值得回看",
        "View all": "查看全部",
        "View in Timeline": "在时间线查看",
        "With Photos": "含照片",
        "already exists as a": "已经是",
        "and": "和",
        "1 moment": "1 条 moment",
        "archived tags from Tags, aliases, and moments. Their names will be available again.": "个已归档标签，以及相关别名和 moment 关联。这些名称之后可以重新使用。",
        "behind": "条落后",
        "characters.": "个字符。",
        "chars": "字符",
        "comments": "条评论",
        "failed uploads": "个上传失败",
        "filter": "筛选",
        "requests": "次请求",
        "from Tags, aliases, and moments. The name will be available again for a new Primary or Topic Tag.": "从标签、别名和 moments 中移除。这个名称之后可以重新用于新的主标签或主题标签。",
        "audio": "段音频",
        "image": "张图片",
        "is already in": "已经存在于",
        "is archived under": "已归档于",
        "Media moment": "媒体 moment",
        "moments": "条 moments",
        "Next month": "下个月",
        "of": "/",
        "Open day in Timeline. Long press for preview.": "打开这一天的时间线。长按可预览。",
        "pending changes": "个待同步变更",
        "pending uploads": "个待上传",
        "photo": "张照片",
        "Photos": "照片",
        "photos": "张照片",
        "text": "条文本",
        "texts": "条文本",
        "this moment": "这条 moment",
        "video": "个视频",
        "videos": "个视频",
    ]
}

enum DefaultPrimaryTagLocalization {
    private static let englishByChineseName: [String: String] = [
        "日记": "Diary",
        "想法": "Thoughts",
        "学习整理": "Study",
        "情绪": "Mood",
        "碎碎念": "Random",
        "复盘": "Review",
    ]

    static func displayName(for storedName: String, language: AppResolvedLanguage) -> String {
        guard language == .english else {
            return chineseName(for: storedName) ?? storedName
        }

        return englishName(for: storedName) ?? storedName
    }

    static func searchNames(for storedName: String) -> [String] {
        var names = [storedName]
        if let chinese = chineseName(for: storedName), !names.contains(chinese) {
            names.append(chinese)
        }
        if let english = englishName(for: storedName), !names.contains(english) {
            names.append(english)
        }
        return names
    }

    private static func englishName(for storedName: String) -> String? {
        if let english = englishByChineseName[storedName] {
            return english
        }

        return englishByChineseName.first { $0.value.caseInsensitiveCompare(storedName) == .orderedSame }?.value
    }

    private static func chineseName(for storedName: String) -> String? {
        if englishByChineseName[storedName] != nil {
            return storedName
        }

        return englishByChineseName.first { $0.value.caseInsensitiveCompare(storedName) == .orderedSame }?.key
    }
}
