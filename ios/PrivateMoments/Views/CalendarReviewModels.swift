import Foundation

struct CalendarTimelineRoute: Equatable {
    let dayStart: Date
    let targetItemID: TimelineItem.ID?
}

enum CalendarReviewMediaFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case photos
    case audio
    case video

    var id: String {
        rawValue
    }

    func title(language: AppResolvedLanguage) -> String {
        switch self {
        case .all:
            return L10n.t("All Moments", language)
        case .text:
            return L10n.t("Text", language)
        case .photos:
            return L10n.t("Photos", language)
        case .audio:
            return L10n.t("Audio", language)
        case .video:
            return L10n.t("Video", language)
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "rectangle.stack"
        case .text:
            return "text.alignleft"
        case .photos:
            return "photo.on.rectangle"
        case .audio:
            return "waveform"
        case .video:
            return "video"
        }
    }

    func includes(_ item: TimelineItem) -> Bool {
        switch self {
        case .all:
            return true
        case .text:
            return item.media.isEmpty && !item.post.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .photos:
            return item.media.contains { $0.isImage }
        case .audio:
            return item.media.contains { $0.isAudio }
        case .video:
            return item.media.contains { $0.isVideo }
        }
    }
}

enum CalendarReviewDensityLevel: Int {
    case none = 0
    case light = 1
    case medium = 2
    case strong = 3
    case intense = 4
    case peak = 5

    static func level(for count: Int, maxCount: Int = 0) -> CalendarReviewDensityLevel {
        guard maxCount > 4 else {
            return fixedLevel(for: count)
        }

        guard count > 0 else {
            return .none
        }

        let ratio = Double(count) / Double(maxCount)
        if ratio >= 0.80 {
            return .peak
        }

        if ratio >= 0.60 {
            return .intense
        }

        if ratio >= 0.40 {
            return .strong
        }

        if ratio >= 0.20 {
            return .medium
        }

        return .light
    }

    private static func fixedLevel(for count: Int) -> CalendarReviewDensityLevel {
        if count >= 4 {
            return .strong
        }

        if count >= 2 {
            return .medium
        }

        if count == 1 {
            return .light
        }

        return .none
    }
}

enum CalendarDayReviewFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case photos
    case audio
    case video
    case favorites
    case comments

    var id: String {
        rawValue
    }

    func title(language: AppResolvedLanguage) -> String {
        switch self {
        case .all:
            return L10n.t("All", language)
        case .photos:
            return L10n.t("Photos", language)
        case .audio:
            return L10n.t("Audio", language)
        case .video:
            return L10n.t("Video", language)
        case .favorites:
            return L10n.t("Favorites", language)
        case .comments:
            return L10n.t("Comments", language)
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "rectangle.stack"
        case .photos:
            return "photo.on.rectangle"
        case .audio:
            return "waveform"
        case .video:
            return "video"
        case .favorites:
            return "star"
        case .comments:
            return "text.bubble"
        }
    }

    func includes(_ item: TimelineItem) -> Bool {
        switch self {
        case .all:
            return true
        case .photos:
            return item.media.contains { $0.isImage }
        case .audio:
            return item.media.contains { $0.isAudio }
        case .video:
            return item.media.contains { $0.isVideo }
        case .favorites:
            return item.post.isFavorite
        case .comments:
            return item.comments.contains { $0.deletedAt == nil }
        }
    }

    func includes(_ item: MomentFeedItem) -> Bool {
        switch item {
        case .moment(let moment):
            return includes(moment)
        case .checkIn(let checkIn):
            switch self {
            case .all:
                return true
            case .photos:
                return checkIn.media.contains { $0.isImage }
            case .audio, .video, .favorites, .comments:
                return false
            }
        }
    }
}

struct CalendarDayReviewFilterSelection: Equatable {
    private(set) var activeFilters: Set<CalendarDayReviewFilter> = []

    var isAllSelected: Bool {
        activeFilters.isEmpty
    }

    mutating func toggle(_ filter: CalendarDayReviewFilter) {
        if filter == .all {
            activeFilters.removeAll()
            return
        }

        if activeFilters.contains(filter) {
            activeFilters.remove(filter)
        } else {
            activeFilters.insert(filter)
        }
    }

    func isSelected(_ filter: CalendarDayReviewFilter) -> Bool {
        filter == .all ? activeFilters.isEmpty : activeFilters.contains(filter)
    }

    func includes(_ item: TimelineItem) -> Bool {
        activeFilters.isEmpty || activeFilters.contains { $0.includes(item) }
    }

    func includes(_ item: MomentFeedItem) -> Bool {
        activeFilters.isEmpty || activeFilters.contains { $0.includes(item) }
    }

    var emptyStateSystemImage: String {
        activeFilters.first?.systemImage ?? "line.3.horizontal.decrease.circle"
    }
}

enum CalendarReviewMediaHint: String, CaseIterable {
    case image
    case audio
    case video

    var systemImage: String {
        switch self {
        case .image:
            return "photo"
        case .audio:
            return "waveform"
        case .video:
            return "play.rectangle"
        }
    }

    func accessibilityTitle(language: AppResolvedLanguage) -> String {
        switch self {
        case .image:
            return L10n.t("Photos", language)
        case .audio:
            return L10n.t("Audio", language)
        case .video:
            return L10n.t("Video", language)
        }
    }
}

struct CalendarReviewWeekday: Identifiable {
    let id: Int
    let title: String
}

struct CalendarReviewDay: Identifiable {
    let id: String
    let date: Date
    let dayStart: Date
    let isInDisplayedMonth: Bool
    let isToday: Bool
    let isFuture: Bool
    let items: [TimelineItem]
    let checkIns: [CheckInFeedEntry]
    let mediaHints: [CalendarReviewMediaHint]
    let densityLevel: CalendarReviewDensityLevel

    var activityCount: Int {
        items.count + checkIns.count
    }

    var containsFavorite: Bool {
        items.contains { $0.post.isFavorite }
    }

    var isSelectable: Bool {
        !isFuture && activityCount > 0
    }

    var targetItemID: String? {
        items.first?.id
    }
}

struct CalendarReviewMonth {
    let id: String
    let title: String
    let monthStart: Date
    let weekdays: [CalendarReviewWeekday]
    let days: [CalendarReviewDay]

    var containsMoments: Bool {
        days.contains { $0.activityCount > 0 }
    }

    var stats: CalendarReviewMonthStats {
        CalendarReviewMonthStats(days: days)
    }
}

struct CalendarReviewDailyCount: Identifiable, Equatable {
    let id: String
    let date: Date
    let dayStart: Date
    let count: Int
    let isFuture: Bool
}

struct CalendarReviewMonthStats: Equatable {
    let totalMoments: Int
    let totalCheckIns: Int
    let totalActivity: Int
    let activeDays: Int
    let totalDays: Int
    let maxDayCount: Int
    let textOnlyMoments: Int
    let imageCount: Int
    let audioCount: Int
    let videoCount: Int
    let favoriteMoments: Int
    let commentedMoments: Int
    let dailyCounts: [CalendarReviewDailyCount]

    var averagePerActiveDay: Double {
        guard activeDays > 0 else {
            return 0
        }

        return Double(totalActivity) / Double(activeDays)
    }

    var busiestDay: CalendarReviewDailyCount? {
        dailyCounts
            .filter { !$0.isFuture && $0.count > 0 }
            .max { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.dayStart < rhs.dayStart
                }

                return lhs.count < rhs.count
            }
    }

    init(days: [CalendarReviewDay]) {
        let displayedDays = days.filter(\.isInDisplayedMonth)
        let reviewableDays = displayedDays.filter { !$0.isFuture }
        let reviewableItems = reviewableDays.flatMap(\.items)
        let reviewableCheckIns = reviewableDays.flatMap(\.checkIns)
        let media = reviewableItems.flatMap(\.media)
        let checkInMedia = reviewableCheckIns.flatMap(\.media)

        totalMoments = reviewableItems.count
        totalCheckIns = reviewableCheckIns.count
        totalActivity = totalMoments + totalCheckIns
        activeDays = reviewableDays.filter { $0.activityCount > 0 }.count
        totalDays = reviewableDays.count
        maxDayCount = reviewableDays.map(\.activityCount).max() ?? 0
        textOnlyMoments = reviewableItems.filter { item in
            item.media.isEmpty && !item.post.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        imageCount = media.filter(\.isImage).count + checkInMedia.filter(\.isImage).count
        audioCount = media.filter(\.isAudio).count
        videoCount = media.filter(\.isVideo).count
        favoriteMoments = reviewableItems.filter { $0.post.isFavorite }.count
        commentedMoments = reviewableItems.filter { item in
            item.comments.contains { $0.deletedAt == nil }
        }.count
        dailyCounts = displayedDays.map { day in
            CalendarReviewDailyCount(
                id: day.id,
                date: day.date,
                dayStart: day.dayStart,
                count: day.activityCount,
                isFuture: day.isFuture
            )
        }
    }
}

enum CalendarReviewBuilder {
    static func month(
        containing date: Date,
        items: [TimelineItem],
        checkIns: [CheckInFeedEntry] = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        language: AppResolvedLanguage = .english,
        mediaFilter: CalendarReviewMediaFilter = .all,
        favoritesOnly: Bool = false,
        commentsOnly: Bool = false
    ) -> CalendarReviewMonth {
        let monthStart = monthStart(for: date, calendar: calendar)
        let filteredItems = visibleItems(
            from: items,
            mediaFilter: mediaFilter,
            favoritesOnly: favoritesOnly,
            commentsOnly: commentsOnly
        )
        let visibleCheckIns = hasMomentOnlyFilters(
            mediaFilter: mediaFilter,
            favoritesOnly: favoritesOnly,
            commentsOnly: commentsOnly
        ) ? [] : checkIns.filter { !$0.isDeleted }
        let groupedItems = Dictionary(grouping: filteredItems) { item in
            calendar.startOfDay(for: item.post.occurredAt)
        }
        let groupedCheckIns = Dictionary(grouping: visibleCheckIns) { item in
            calendar.startOfDay(for: item.occurredAt)
        }
        let days = monthDays(
            for: monthStart,
            groupedItems: groupedItems,
            groupedCheckIns: groupedCheckIns,
            now: now,
            calendar: calendar
        )

        return CalendarReviewMonth(
            id: monthID(for: monthStart, calendar: calendar),
            title: MomentDateFormatter.monthTitle(for: monthStart, calendar: calendar, language: language),
            monthStart: monthStart,
            weekdays: weekdays(calendar: calendar),
            days: days
        )
    }

    static func monthStart(for date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.era, .year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func addMonths(_ value: Int, to date: Date, calendar: Calendar = .current) -> Date {
        let monthStart = monthStart(for: date, calendar: calendar)
        return calendar.date(byAdding: .month, value: value, to: monthStart) ?? monthStart
    }

    static func dayID(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        let era = components.era ?? 1
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "calendar-day-%04d-%04d-%02d-%02d", era, year, month, day)
    }

    private static func visibleItems(
        from items: [TimelineItem],
        mediaFilter: CalendarReviewMediaFilter,
        favoritesOnly: Bool,
        commentsOnly: Bool
    ) -> [TimelineItem] {
        items
            .filter { $0.post.deletedAt == nil }
            .filter { mediaFilter.includes($0) }
            .filter { !favoritesOnly || $0.post.isFavorite }
            .filter { !commentsOnly || $0.comments.contains { $0.deletedAt == nil } }
            .sorted { lhs, rhs in
                if lhs.post.occurredAt == rhs.post.occurredAt {
                    return lhs.id > rhs.id
                }

                return lhs.post.occurredAt > rhs.post.occurredAt
            }
    }

    private static func hasMomentOnlyFilters(
        mediaFilter: CalendarReviewMediaFilter,
        favoritesOnly: Bool,
        commentsOnly: Bool
    ) -> Bool {
        mediaFilter != .all || favoritesOnly || commentsOnly
    }

    private static func monthDays(
        for monthStart: Date,
        groupedItems: [Date: [TimelineItem]],
        groupedCheckIns: [Date: [CheckInFeedEntry]],
        now: Date,
        calendar: Calendar
    ) -> [CalendarReviewDay] {
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingDayCount = (firstWeekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDayCount, to: monthStart) ?? monthStart
        let currentMonth = calendar.component(.month, from: monthStart)
        let nowStart = calendar.startOfDay(for: now)
        let rawDays = (0..<42).compactMap { offset -> (
            id: String,
            date: Date,
            dayStart: Date,
            isInDisplayedMonth: Bool,
            isToday: Bool,
            isFuture: Bool,
            items: [TimelineItem],
            checkIns: [CheckInFeedEntry],
            mediaHints: [CalendarReviewMediaHint]
        )? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }

            let dayStart = calendar.startOfDay(for: date)
            let items = groupedItems[dayStart] ?? []
            let checkIns = groupedCheckIns[dayStart] ?? []
            return (
                id: dayID(for: dayStart, calendar: calendar),
                date: date,
                dayStart: dayStart,
                isInDisplayedMonth: calendar.component(.month, from: date) == currentMonth,
                isToday: calendar.isDate(dayStart, inSameDayAs: nowStart),
                isFuture: dayStart > nowStart,
                items: items,
                checkIns: checkIns,
                mediaHints: mediaHints(for: items, checkIns: checkIns)
            )
        }

        let maxDisplayedCount = rawDays
            .filter { $0.isInDisplayedMonth && !$0.isFuture }
            .map { $0.items.count + $0.checkIns.count }
            .max() ?? 0

        return rawDays.map { day in
            CalendarReviewDay(
                id: day.id,
                date: day.date,
                dayStart: day.dayStart,
                isInDisplayedMonth: day.isInDisplayedMonth,
                isToday: day.isToday,
                isFuture: day.isFuture,
                items: day.items,
                checkIns: day.checkIns,
                mediaHints: day.mediaHints,
                densityLevel: CalendarReviewDensityLevel.level(
                    for: day.items.count + day.checkIns.count,
                    maxCount: day.isInDisplayedMonth && !day.isFuture ? maxDisplayedCount : day.items.count + day.checkIns.count
                )
            )
        }
    }

    private static func weekdays(calendar: Calendar) -> [CalendarReviewWeekday] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? formatter.shortStandaloneWeekdaySymbols ?? []

        return (0..<7).map { offset in
            let symbolIndex = (calendar.firstWeekday - 1 + offset) % 7
            let title = symbols.indices.contains(symbolIndex) ? symbols[symbolIndex] : ""
            return CalendarReviewWeekday(id: symbolIndex, title: title)
        }
    }

    private static func mediaHints(for items: [TimelineItem], checkIns: [CheckInFeedEntry]) -> [CalendarReviewMediaHint] {
        CalendarReviewMediaHint.allCases
            .filter { hint in
                switch hint {
                case .image:
                    return items.contains { $0.media.contains { $0.isImage } }
                        || checkIns.contains { $0.media.contains { $0.isImage } }
                case .audio:
                    return items.contains { $0.media.contains { $0.isAudio } }
                case .video:
                    return items.contains { $0.media.contains { $0.isVideo } }
                }
            }
            .prefix(2)
            .map { $0 }
    }

    private static func monthID(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.era, .year, .month], from: date)
        let era = components.era ?? 1
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "calendar-month-%04d-%04d-%02d", era, year, month)
    }
}
