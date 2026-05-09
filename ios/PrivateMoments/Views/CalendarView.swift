import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var store: TimelineStore
    @EnvironmentObject private var playbackCenter: MediaPlaybackCenter
    @Environment(\.appLanguage) private var appLanguage

    let onSelectDay: (CalendarTimelineRoute) -> Void
    let onOpenSettings: () -> Void

    @State private var visibleMonth = CalendarReviewBuilder.monthStart(for: Date())
    @State private var mediaFilter: CalendarReviewMediaFilter = .all
    @State private var favoritesOnly = false
    @State private var commentsOnly = false
    @State private var navigationPath = NavigationPath()
    @State private var daySelectionFeedbackToken = 0
    @State private var showMonthStats = false
    @State private var now = Date()

    private var calendar: Calendar {
        .current
    }

    private var month: CalendarReviewMonth {
        CalendarReviewBuilder.month(
            containing: visibleMonth,
            items: store.items,
            checkIns: store.checkInFeedEntries,
            now: now,
            calendar: calendar,
            language: appLanguage,
            mediaFilter: mediaFilter,
            favoritesOnly: favoritesOnly,
            commentsOnly: commentsOnly
        )
    }

    private var isViewingCurrentMonth: Bool {
        calendar.isDate(visibleMonth, equalTo: Date(), toGranularity: .month)
    }

    private var hasActiveFilters: Bool {
        mediaFilter != .all || favoritesOnly || commentsOnly
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if !store.isReady {
                    ProgressView()
                } else {
                    VStack(spacing: 14) {
                        CalendarMonthHeader(
                            title: month.title,
                            showToday: !isViewingCurrentMonth,
                            onPrevious: { moveMonth(-1) },
                            onNext: { moveMonth(1) },
                            onToday: { jumpToToday() }
                        )

                        CalendarMonthGrid(
                            month: month,
                            calendar: calendar,
                            onSelectDay: selectDay
                        )

                        if store.items.isEmpty && store.checkInEntries.isEmpty {
                            Text(L10n.t("No moments yet", appLanguage))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .gesture(monthSwipeGesture)
                }
            }
            .navigationTitle(L10n.t("Calendar", appLanguage))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        navigationPath.append(CalendarReviewsRoute())
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .accessibilityLabel(L10n.t("Reviews", appLanguage))

                    Menu {
                        Section(L10n.t("Content", appLanguage)) {
                            ForEach(CalendarReviewMediaFilter.allCases) { filter in
                                Button {
                                    mediaFilter = filter
                                } label: {
                                    Label(
                                        filter.title(language: appLanguage),
                                        systemImage: mediaFilter == filter ? "checkmark" : filter.systemImage
                                    )
                                }
                            }
                        }

                        Section(L10n.t("Attributes", appLanguage)) {
                            Button {
                                favoritesOnly.toggle()
                            } label: {
                                Label(L10n.t("Favorites", appLanguage), systemImage: favoritesOnly ? "checkmark" : "star")
                            }

                            Button {
                                commentsOnly.toggle()
                            } label: {
                                Label(L10n.t("Comments", appLanguage), systemImage: commentsOnly ? "checkmark" : "text.bubble")
                            }
                        }

                        if hasActiveFilters {
                            Section {
                                Button(L10n.t("Clear Filters", appLanguage), role: .destructive) {
                                    mediaFilter = .all
                                    favoritesOnly = false
                                    commentsOnly = false
                                }
                            }
                        }
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(L10n.t("Filter calendar", appLanguage))

                    Button {
                        playbackCenter.pause()
                        onOpenSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(L10n.t("Settings", appLanguage))

                    Button {
                        showMonthStats = true
                    } label: {
                        Image(systemName: "chart.bar.xaxis")
                    }
                    .accessibilityLabel(L10n.t("Month Stats", appLanguage))
                }
            }
            .navigationDestination(for: CalendarDayRoute.self) { route in
                if let day = day(for: route) {
                    CalendarDayReviewView(
                        day: day,
                        calendar: calendar,
                        onOpenTimeline: { route in
                            playbackCenter.pause()
                            navigationPath = NavigationPath()
                            onSelectDay(route)
                        },
                        onOpenMoment: { postId in
                            playbackCenter.pause()
                            navigationPath.append(postId)
                        }
                    )
                } else {
                    ContentUnavailableView(L10n.t("No moments", appLanguage), systemImage: "calendar")
                }
            }
            .navigationDestination(for: CalendarReviewsRoute.self) { _ in
                WeeklyReviewListView()
            }
            .navigationDestination(for: TimelineItem.ID.self) { postId in
                MomentDetailView(postId: postId)
            }
            .sheet(isPresented: $showMonthStats) {
                CalendarMonthStatsSheet(
                    month: month,
                    calendar: calendar,
                    onOpenDay: openDayFromStats,
                    onSelectFocus: applyMonthStatsFocus
                )
            }
            .sensoryFeedback(.selection, trigger: daySelectionFeedbackToken)
            .onAppear {
                visibleMonth = CalendarReviewBuilder.monthStart(for: visibleMonth, calendar: calendar)
                now = Date()
            }
        }
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) >= 54 else {
                    return
                }

                if value.translation.width < 0 {
                    moveMonth(1)
                } else {
                    moveMonth(-1)
                }
            }
    }

    private func moveMonth(_ offset: Int) {
        withAnimation(.easeInOut(duration: 0.22)) {
            visibleMonth = CalendarReviewBuilder.addMonths(offset, to: visibleMonth, calendar: calendar)
        }
    }

    private func jumpToToday() {
        now = Date()
        withAnimation(.easeInOut(duration: 0.22)) {
            visibleMonth = CalendarReviewBuilder.monthStart(for: now, calendar: calendar)
        }
    }

    private func selectDay(_ day: CalendarReviewDay) {
        guard day.isSelectable else {
            return
        }

        playbackCenter.pause()
        daySelectionFeedbackToken += 1
        navigationPath.append(CalendarDayRoute(dayStart: day.dayStart))
    }

    private func openDayFromStats(_ dayStart: Date) {
        playbackCenter.pause()
        showMonthStats = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            navigationPath.append(CalendarDayRoute(dayStart: dayStart))
        }
    }

    private func applyMonthStatsFocus(_ focus: CalendarMonthStatsFocus) {
        showMonthStats = false
        switch focus {
        case .text:
            mediaFilter = .text
            favoritesOnly = false
            commentsOnly = false
        case .photos:
            mediaFilter = .photos
            favoritesOnly = false
            commentsOnly = false
        case .audio:
            mediaFilter = .audio
            favoritesOnly = false
            commentsOnly = false
        case .video:
            mediaFilter = .video
            favoritesOnly = false
            commentsOnly = false
        case .favorites:
            mediaFilter = .all
            favoritesOnly = true
            commentsOnly = false
        case .comments:
            mediaFilter = .all
            favoritesOnly = false
            commentsOnly = true
        }
    }

    private func day(for route: CalendarDayRoute) -> CalendarReviewDay? {
        CalendarReviewBuilder.month(
            containing: route.dayStart,
            items: store.items,
            checkIns: store.checkInFeedEntries,
            now: now,
            calendar: calendar,
            language: appLanguage
        )
        .days
        .first { calendar.isDate($0.dayStart, inSameDayAs: route.dayStart) }
    }
}

private struct CalendarDayRoute: Hashable {
    let dayStart: Date
}

private struct CalendarReviewsRoute: Hashable {}

private struct CalendarMonthHeader: View {
    @Environment(\.appLanguage) private var appLanguage

    let title: String
    let showToday: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Previous month", appLanguage))

            VStack(spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .fontDesign(.rounded)

                Button(L10n.t("Today", appLanguage), action: onToday)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
                    .opacity(showToday ? 1 : 0)
                    .disabled(!showToday)
                    .accessibilityHidden(!showToday)
            }
            .frame(maxWidth: .infinity)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Next month", appLanguage))
        }
    }
}

private struct CalendarMonthGrid: View {
    let month: CalendarReviewMonth
    let calendar: Calendar
    let onSelectDay: (CalendarReviewDay) -> Void

    @State private var gridWidth: CGFloat = 0

    private let gridSpacing: CGFloat = 6
    private let weekdayHeight: CGFloat = 18

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: gridSpacing) {
                ForEach(month.weekdays) { weekday in
                    Text(weekday.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: dayCellSide, height: weekdayHeight)
                }
            }

            VStack(spacing: gridSpacing) {
                ForEach(0..<6, id: \.self) { rowIndex in
                    HStack(spacing: gridSpacing) {
                        ForEach(0..<7, id: \.self) { columnIndex in
                            let dayIndex = rowIndex * 7 + columnIndex
                            if dayIndex < month.days.count {
                                let day = month.days[dayIndex]
                                Button {
                                    if day.isSelectable {
                                        onSelectDay(day)
                                    }
                                } label: {
                                    CalendarDayCell(day: day, calendar: calendar, side: dayCellSide)
                                }
                                .buttonStyle(CalendarDayButtonStyle(isEnabled: day.isSelectable))
                                .disabled(!day.isSelectable)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: CalendarGridWidthPreferenceKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(CalendarGridWidthPreferenceKey.self) { width in
            if width > 0, abs(gridWidth - width) > 0.5 {
                gridWidth = width
            }
        }
    }

    private var dayCellSide: CGFloat {
        guard gridWidth > 0 else {
            return 44
        }

        return max(0, (gridWidth - gridSpacing * 6) / 7)
    }
}

private struct CalendarGridWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

private struct CalendarDayButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                if configuration.isPressed && isEnabled {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.10 : 0.07))
                }
            }
            .scaleEffect(configuration.isPressed && isEnabled ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct CalendarDayCell: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.colorScheme) private var colorScheme

    let day: CalendarReviewDay
    let calendar: Calendar
    let side: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dayNumber)
                .font(.subheadline.weight(day.isToday ? .bold : .medium))
                .fontDesign(.rounded)
                .foregroundStyle(day.isInDisplayedMonth ? Color.primary : Color.secondary)

            Spacer(minLength: 0)

            if !day.mediaHints.isEmpty || day.activityCount > 0 {
                HStack(spacing: 4) {
                    if !day.mediaHints.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(day.mediaHints, id: \.rawValue) { hint in
                                Image(systemName: hint.systemImage)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    if day.activityCount > 0 {
                        Text("\(day.activityCount)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.primary.opacity(0.72))
                            .minimumScaleFactor(0.72)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(6)
        .frame(width: side, height: side, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(dayBackground)
        }
        .overlay {
            if day.isToday {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 1.2)
            }
        }
        .opacity(dayOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(day.isSelectable ? [.isButton] : [])
        .accessibilityHint(accessibilityHint)
    }

    private var dayNumber: String {
        String(calendar.component(.day, from: day.date))
    }

    private var dayBackground: Color {
        switch day.densityLevel {
        case .none:
            return Color.secondary.opacity(colorScheme == .dark ? 0.10 : 0.055)
        case .light:
            return heatColor.opacity(colorScheme == .dark ? 0.16 : 0.12)
        case .medium:
            return heatColor.opacity(colorScheme == .dark ? 0.28 : 0.22)
        case .strong:
            return heatColor.opacity(colorScheme == .dark ? 0.40 : 0.32)
        case .intense:
            return heatColor.opacity(colorScheme == .dark ? 0.55 : 0.44)
        case .peak:
            return heatColor.opacity(colorScheme == .dark ? 0.72 : 0.58)
        }
    }

    private var heatColor: Color {
        Color(red: 0.28, green: 0.58, blue: 0.47)
    }

    private var dayOpacity: Double {
        if day.isFuture {
            return 0.30
        }

        return day.isInDisplayedMonth ? 1 : 0.46
    }

    private var accessibilityLabel: String {
        var parts = [fullDateTitle, momentCountTitle]

        if !day.mediaHints.isEmpty {
            parts.append(day.mediaHints.map { $0.accessibilityTitle(language: appLanguage) }.joined(separator: ", "))
        }

        if day.containsFavorite {
            parts.append(L10n.t("Favorites", appLanguage))
        }

        if day.isToday {
            parts.append(L10n.t("Today", appLanguage))
        }

        if day.isFuture {
            parts.append(L10n.t("Future date", appLanguage))
        }

        return parts.joined(separator: ", ")
    }

    private var accessibilityHint: String {
        if day.isFuture {
            return L10n.t("Unavailable", appLanguage)
        }

        if day.isSelectable {
            return L10n.t("Open day review", appLanguage)
        }

        return L10n.t("No moments on this day", appLanguage)
    }

    private var fullDateTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.dateStyle = .full
        return formatter.string(from: day.date)
    }

    private var momentCountTitle: String {
        if day.activityCount == 0 {
            return L10n.t("No moments", appLanguage)
        }

        if day.activityCount == 1 {
            return L10n.t("1 item", appLanguage)
        }

        return "\(day.activityCount) \(L10n.t("items", appLanguage))"
    }
}

private enum CalendarMonthStatsFocus: String, CaseIterable, Identifiable {
    case text
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
        case .text:
            return L10n.t("Text", language)
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
        case .text:
            return "text.alignleft"
        case .photos:
            return "photo"
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
}

private struct CalendarMonthStatsSheet: View {
    @Environment(\.appLanguage) private var appLanguage

    let month: CalendarReviewMonth
    let calendar: Calendar
    let onOpenDay: (Date) -> Void
    let onSelectFocus: (CalendarMonthStatsFocus) -> Void

    private var stats: CalendarReviewMonthStats {
        month.stats
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    CalendarMonthStatsOverview(
                        month: month,
                        stats: stats,
                        calendar: calendar,
                        onOpenDay: onOpenDay
                    )
                    CalendarMonthDailyBars(
                        stats: stats,
                        calendar: calendar,
                        onOpenDay: onOpenDay
                    )
                    CalendarMonthStatsGrid(
                        stats: stats,
                        onSelectFocus: onSelectFocus
                    )
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .navigationTitle(L10n.t("Month Stats", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CalendarMonthStatsOverview: View {
    @Environment(\.appLanguage) private var appLanguage

    let month: CalendarReviewMonth
    let stats: CalendarReviewMonthStats
    let calendar: Calendar
    let onOpenDay: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(month.title)
                .font(.title2.weight(.semibold))
                .fontDesign(.rounded)

            HStack(spacing: 10) {
                CalendarMonthStatPill(
                    title: L10n.t("Total", appLanguage),
                    value: "\(stats.totalActivity)"
                )
                CalendarMonthStatPill(
                    title: L10n.t("Active days", appLanguage),
                    value: "\(stats.activeDays)"
                )
                CalendarMonthStatPill(
                    title: L10n.t("Avg/active day", appLanguage),
                    value: averageTitle
                )
            }

            HStack(spacing: 8) {
                Label("\(stats.totalMoments) \(L10n.t("moments", appLanguage))", systemImage: "rectangle.stack")
                Label("\(stats.totalCheckIns) \(L10n.t("check-ins", appLanguage))", systemImage: "checkmark.circle")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            if let busiestDay = stats.busiestDay {
                Button {
                    onOpenDay(busiestDay.dayStart)
                } label: {
                    HStack(spacing: 6) {
                        Text("\(L10n.t("Busiest day", appLanguage)): \(dayTitle(for: busiestDay.date)) · \(busiestDay.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var averageTitle: String {
        String(format: "%.1f", stats.averagePerActiveDay)
    }

    private func dayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }
}

private struct CalendarMonthStatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: 58)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CalendarMonthDailyBars: View {
    @Environment(\.appLanguage) private var appLanguage

    let stats: CalendarReviewMonthStats
    let calendar: Calendar
    let onOpenDay: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("Daily rhythm", appLanguage))
                .font(.headline.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(stats.dailyCounts) { day in
                        Button {
                            onOpenDay(day.dayStart)
                        } label: {
                            VStack(spacing: 5) {
                                Capsule()
                                    .fill(barColor(for: day))
                                    .frame(width: 7, height: barHeight(for: day))

                                Text(dayLabel(for: day.date))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(day.isFuture || day.count == 0)
                        .opacity(day.isFuture ? 0.30 : 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(dayLabel(for: day.date)), \(day.count)")
                    }
                }
                .frame(minHeight: 116, alignment: .bottom)
                .padding(.horizontal, 2)
            }
        }
    }

    private func barHeight(for day: CalendarReviewDailyCount) -> CGFloat {
        guard stats.maxDayCount > 0, day.count > 0 else {
            return 4
        }

        let ratio = CGFloat(day.count) / CGFloat(stats.maxDayCount)
        return max(8, 90 * ratio)
    }

    private func barColor(for day: CalendarReviewDailyCount) -> Color {
        guard day.count > 0 else {
            return Color.secondary.opacity(0.14)
        }

        return Color(red: 0.28, green: 0.58, blue: 0.47).opacity(day.count == stats.maxDayCount ? 0.88 : 0.58)
    }

    private func dayLabel(for date: Date) -> String {
        "\(calendar.component(.day, from: date))"
    }
}

private struct CalendarMonthStatsGrid: View {
    @Environment(\.appLanguage) private var appLanguage

    let stats: CalendarReviewMonthStats
    let onSelectFocus: (CalendarMonthStatsFocus) -> Void

    private var rows: [(CalendarMonthStatsFocus, Int)] {
        [
            (.text, stats.textOnlyMoments),
            (.photos, stats.imageCount),
            (.audio, stats.audioCount),
            (.video, stats.videoCount),
            (.favorites, stats.favoriteMoments),
            (.comments, stats.commentedMoments),
        ]
    }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(rows, id: \.0) { row in
                Button {
                    onSelectFocus(row.0)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: row.0.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        Text(row.0.title(language: appLanguage))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Text("\(row.1)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(row.1 == 0)
                .opacity(row.1 == 0 ? 0.45 : 1)
            }
        }
    }
}

private struct CalendarDayReviewView: View {
    @EnvironmentObject private var store: TimelineStore
    @EnvironmentObject private var playbackCenter: MediaPlaybackCenter
    @Environment(\.appLanguage) private var appLanguage

    let day: CalendarReviewDay
    let calendar: Calendar
    let onOpenTimeline: (CalendarTimelineRoute) -> Void
    let onOpenMoment: (TimelineItem.ID) -> Void

    @State private var summaryRoute: CalendarSummaryRoute?
    @State private var checkInDetailRoute: CheckInEntryDetailRoute?
    @State private var scrollTargetItemID: String?
    @State private var filterSelection = CalendarDayReviewFilterSelection()

    init(
        day: CalendarReviewDay,
        calendar: Calendar,
        onOpenTimeline: @escaping (CalendarTimelineRoute) -> Void,
        onOpenMoment: @escaping (TimelineItem.ID) -> Void
    ) {
        self.day = day
        self.calendar = calendar
        self.onOpenTimeline = onOpenTimeline
        self.onOpenMoment = onOpenMoment
        _scrollTargetItemID = State(initialValue: DayReviewScrollMemory.restoredItemID(for: day, calendar: calendar))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                CalendarDayReviewHeader(day: day, calendar: calendar)
                    .padding(.bottom, day.activityCount == 0 ? 18 : 12)

                CalendarDayCheckInRhythmStrip(
                    checkIns: day.checkInRhythmItems,
                    calendar: calendar,
                    onOpen: { checkIn in
                        playbackCenter.pause()
                        checkInDetailRoute = CheckInEntryDetailRoute(entryId: checkIn.id)
                    }
                )
                .padding(.bottom, day.checkInRhythmItems.isEmpty ? 0 : 18)

                if day.activityCount == 0 {
                    ContentUnavailableView(L10n.t("No moments", appLanguage), systemImage: "calendar")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                } else if filteredItems.isEmpty {
                    CalendarDayReviewFilterBar(selection: $filterSelection, filters: availableFilters)
                        .padding(.bottom, 18)

                    ContentUnavailableView(L10n.t("No matching moments", appLanguage), systemImage: filterSelection.emptyStateSystemImage)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 22)
                } else {
                    CalendarDayReviewFilterBar(selection: $filterSelection, filters: availableFilters)
                        .padding(.bottom, 18)

                    ForEach(sections) { section in
                        CalendarDayReviewPeriodHeader(title: section.period.title(language: appLanguage))

                        ForEach(section.items) { item in
                            switch item {
                            case .moment(let moment):
                                CalendarDayReviewItemRow(
                                    item: moment,
                                    calendar: calendar,
                                    isLast: item.rawItemID == lastFilteredItemID,
                                    onOpenMoment: {
                                        playbackCenter.pause()
                                        onOpenMoment(moment.id)
                                    },
                                    onOpenSummary: { media in
                                        playbackCenter.pause()
                                        summaryRoute = CalendarSummaryRoute(mediaId: media.id)
                                    }
                                )
                                .id(moment.id)

                            case .checkIn(let checkIn):
                                CalendarDayReviewCheckInRow(
                                    checkIn: checkIn,
                                    calendar: calendar,
                                    isLast: item.rawItemID == lastFilteredItemID,
                                    onOpen: {
                                        playbackCenter.pause()
                                        checkInDetailRoute = CheckInEntryDetailRoute(entryId: checkIn.id)
                                    }
                                )
                                .id(checkIn.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .scrollPosition(id: $scrollTargetItemID, anchor: .top)
        .navigationTitle(L10n.t("Day Review", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L10n.t("Timeline", appLanguage)) {
                    playbackCenter.pause()
                    onOpenTimeline(CalendarTimelineRoute(dayStart: day.dayStart, targetItemID: day.targetItemID))
                }
            }
        }
        .sheet(item: $summaryRoute) { route in
            if let media = media(for: route) {
                AISummarySheet(
                    media: media,
                    summary: aiSummary(for: media),
                    onRegenerate: {
                        await store.requestAISummary(for: media, forceRegenerate: true)
                    },
                    onDelete: {
                        if let summary = aiSummary(for: media) {
                            Task {
                                await store.deleteAISummary(summary)
                            }
                        }
                    }
                )
            } else {
                ContentUnavailableView(L10n.t("Summary unavailable", appLanguage), systemImage: "sparkles")
            }
        }
        .sheet(item: $checkInDetailRoute) { route in
            CheckInEntryDetailView(entryId: route.entryId)
        }
        .onChange(of: scrollTargetItemID) { _, itemID in
            guard let itemID else {
                return
            }

            DayReviewScrollMemory.save(itemID, for: day.dayStart, calendar: calendar)
        }
        .onDisappear {
            playbackCenter.pauseForInterfaceChange()
        }
    }

    private func media(for route: CalendarSummaryRoute) -> TimelineMedia? {
        store.items
            .flatMap(\.media)
            .first { $0.id == route.mediaId }
    }

    private func aiSummary(for media: TimelineMedia) -> TimelineAISummary? {
        store.items
            .flatMap(\.aiSummaries)
            .first { $0.mediaId == media.id && $0.deletedAt == nil }
    }

    private var availableFilters: [CalendarDayReviewFilter] {
        CalendarDayReviewFilter.allCases.filter { filter in
            filter == .all || dayFeedItems.contains { filter.includes($0) }
        }
    }

    private var dayFeedItems: [MomentFeedItem] {
        let moments = day.items.map(MomentFeedItem.moment)
        let checkIns = day.checkIns.map(MomentFeedItem.checkIn)
        return (moments + checkIns).sorted { lhs, rhs in
            if lhs.occurredAt == rhs.occurredAt {
                return lhs.sortKey > rhs.sortKey
            }

            return lhs.occurredAt > rhs.occurredAt
        }
    }

    private var filteredItems: [MomentFeedItem] {
        dayFeedItems.filter { filterSelection.includes($0) }
    }

    private var sections: [CalendarDayReviewSection] {
        CalendarDayPeriod.allCases.reversed().compactMap { period in
            let items = filteredItems.filter { item in
                CalendarDayPeriod.period(for: item.occurredAt, calendar: calendar) == period
            }

            guard !items.isEmpty else {
                return nil
            }

            return CalendarDayReviewSection(period: period, items: items)
        }
    }

    private var lastFilteredItemID: String? {
        filteredItems.last?.rawItemID
    }
}

private struct CalendarDayReviewSection: Identifiable {
    let period: CalendarDayPeriod
    let items: [MomentFeedItem]

    var id: String {
        period.rawValue
    }
}

private enum CalendarDayPeriod: String, CaseIterable {
    case lateNight
    case morning
    case afternoon
    case evening

    static func period(for date: Date, calendar: Calendar) -> CalendarDayPeriod {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 6..<12:
            return .morning
        case 12..<18:
            return .afternoon
        case 18..<24:
            return .evening
        default:
            return .lateNight
        }
    }

    func title(language: AppResolvedLanguage) -> String {
        switch self {
        case .lateNight:
            return L10n.t("Late Night", language)
        case .morning:
            return L10n.t("Morning", language)
        case .afternoon:
            return L10n.t("Afternoon", language)
        case .evening:
            return L10n.t("Evening", language)
        }
    }
}

private struct CalendarDayReviewFilterBar: View {
    @Environment(\.appLanguage) private var appLanguage

    @Binding var selection: CalendarDayReviewFilterSelection
    let filters: [CalendarDayReviewFilter]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters) { filter in
                    Button {
                        selection.toggle(filter)
                    } label: {
                        Label(filter.title(language: appLanguage), systemImage: filter.systemImage)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(backgroundColor(for: filter), in: Capsule())
                            .foregroundStyle(foregroundColor(for: filter))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func backgroundColor(for filter: CalendarDayReviewFilter) -> Color {
        if selection.isSelected(filter) {
            return Color.accentColor.opacity(0.16)
        }

        return Color.secondary.opacity(0.08)
    }

    private func foregroundColor(for filter: CalendarDayReviewFilter) -> Color {
        selection.isSelected(filter) ? .accentColor : .secondary
    }
}

private struct CalendarDayReviewPeriodHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 1)
        }
        .padding(.top, 2)
        .padding(.bottom, 10)
    }
}

private struct CalendarSummaryRoute: Identifiable {
    let mediaId: String

    var id: String {
        mediaId
    }
}

private enum DayReviewScrollMemory {
    static func restoredItemID(for day: CalendarReviewDay, calendar: Calendar) -> String? {
        guard let itemID = UserDefaults.standard.string(forKey: key(for: day.dayStart, calendar: calendar)),
              day.items.contains(where: { $0.id == itemID }) || day.checkIns.contains(where: { $0.id == itemID }) else {
            return nil
        }

        return itemID
    }

    static func save(_ itemID: String, for dayStart: Date, calendar: Calendar) {
        UserDefaults.standard.set(itemID, forKey: key(for: dayStart, calendar: calendar))
    }

    private static func key(for dayStart: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: dayStart)
        if let year = components.year, let month = components.month, let day = components.day {
            return String(format: "dayReview.scroll.%04d-%02d-%02d", year, month, day)
        }

        return "dayReview.scroll.\(Int(dayStart.timeIntervalSince1970))"
    }
}

private struct CalendarDayReviewHeader: View {
    @Environment(\.appLanguage) private var appLanguage

    let day: CalendarReviewDay
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dayTitle)
                .font(.title.weight(.semibold))
                .fontDesign(.rounded)

            Text(weekdayTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(momentCountTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.78))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.secondary.opacity(0.08), in: Capsule())

                if !mediaCompositionTitle.isEmpty {
                    Text(mediaCompositionTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dayTitle: String {
        MomentDateFormatter.dayJumpTitle(for: day.dayStart, calendar: calendar, language: appLanguage)
    }

    private var weekdayTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: day.dayStart)
    }

    private var momentCountTitle: String {
        if day.activityCount == 1 {
            return L10n.t("1 item", appLanguage)
        }

        return "\(day.activityCount) \(L10n.t("items", appLanguage))"
    }

    private var mediaCompositionTitle: String {
        let media = day.items.flatMap(\.media)
        let checkInMedia = day.checkIns.flatMap(\.media)
        let textCount = day.items.filter { item in
            item.media.isEmpty && !item.post.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        let imageCount = media.filter(\.isImage).count + checkInMedia.filter(\.isImage).count
        let audioCount = media.filter(\.isAudio).count
        let videoCount = media.filter(\.isVideo).count
        let checkInCount = day.checkIns.count
        let parts = [
            compositionPart(count: textCount, singular: "text", plural: "texts"),
            compositionPart(count: imageCount, singular: "photo", plural: "photos"),
            compositionPart(count: audioCount, singular: "audio", plural: "audio"),
            compositionPart(count: videoCount, singular: "video", plural: "videos"),
            compositionPart(count: checkInCount, singular: "check-in", plural: "check-ins"),
        ].compactMap { $0 }

        return parts.joined(separator: " · ")
    }

    private func compositionPart(count: Int, singular: String, plural: String) -> String? {
        guard count > 0 else {
            return nil
        }

        let noun = count == 1 ? singular : plural
        return "\(count) \(L10n.t(noun, appLanguage))"
    }
}

private struct CalendarDayReviewItemRow: View {
    @Environment(\.appLanguage) private var appLanguage
    @EnvironmentObject private var store: TimelineStore

    let item: TimelineItem
    let calendar: Calendar
    let isLast: Bool
    let onOpenMoment: () -> Void
    let onOpenSummary: (TimelineMedia) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeTitle)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .allowsTightening(true)
                .frame(width: 42, alignment: .trailing)
                .padding(.top, 2)

            VStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)

                Rectangle()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 1)
                    .opacity(isLast ? 0 : 1)
            }
            .frame(width: 8)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    if store.showTagsInTimeline, let primaryTag = item.primaryTag {
                        TimelineTagChip(tag: primaryTag.tag, compact: true)
                    }

                    Spacer(minLength: 0)

                    Button(action: onOpenMoment) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Open moment detail", appLanguage))
                }

                Button(action: onOpenMoment) {
                    if hasPostText {
                        MomentTextView(text: item.post.text, style: .preview)
                            .lineLimit(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(fallbackTitle)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)

                if !previewImageMedia.isEmpty {
                    Button(action: onOpenMoment) {
                        LazyVGrid(columns: imageGridColumns, alignment: .leading, spacing: 6) {
                            ForEach(previewImageMedia) { imageMedia in
                                TimelineImage(media: imageMedia, style: .grid)
                                    .frame(width: 58, height: 58)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }

                if let audio = item.media.first(where: \.isAudio) {
                    TimelineAudioCard(media: audio, style: .compact)

                    if let state = aiSummaryControlState(for: audio) {
                        TimelineAISummaryControl(
                            media: audio,
                            state: state,
                            onOpenSummary: onOpenSummary
                        )
                    }
                }

                if let video = item.media.first(where: \.isVideo) {
                    Button(action: onOpenMoment) {
                        CalendarDayReviewVideoHint(media: video)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, isLast ? 0 : 18)
        }
        .accessibilityElement(children: .contain)
    }

    private var hasPostText: Bool {
        !item.post.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var previewImageMedia: [TimelineMedia] {
        item.media.filter(\.isImage)
    }

    private var imageGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 58, maximum: 72), spacing: 6)
        ]
    }

    private var dotColor: Color {
        if item.media.contains(where: { $0.isAudio }) {
            return Color.accentColor.opacity(0.72)
        }

        if item.media.contains(where: { $0.isImage || $0.isVideo }) {
            return Color.secondary.opacity(0.46)
        }

        return Color.secondary.opacity(0.34)
    }

    private var timeTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: item.post.occurredAt)
    }

    private var fallbackTitle: String {
        if let summaryTitle = item.aiSummaries
            .filter(\.isReady)
            .compactMap({ $0.documentTitle ?? $0.oneLiner })
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !summaryTitle.isEmpty {
            return summaryTitle
        }

        if item.media.count == 1 {
            if item.media.first?.isAudio == true {
                return L10n.t("Audio moment", appLanguage)
            }
            if item.media.first?.isVideo == true {
                return L10n.t("Video moment", appLanguage)
            }
            return L10n.t("Photo moment", appLanguage)
        }

        if item.media.count > 1 {
            return L10n.t("Media moment", appLanguage)
        }

        return L10n.t("Moment", appLanguage)
    }

    private func aiSummaryControlState(for media: TimelineMedia) -> TimelineAISummaryControlState? {
        let summary = aiSummary(for: media)

        if store.aiSummaryRequestsInFlight.contains(media.id) {
            return .regenerating
        }

        if summary?.isSummarizing == true {
            return .summarizing
        }

        if summary?.isFailed == true {
            return .failed
        }

        if summary?.isReady == true || summary?.hasDisplayContent == true {
            return .ready
        }

        return nil
    }

    private func aiSummary(for media: TimelineMedia) -> TimelineAISummary? {
        item.aiSummaries.first { $0.mediaId == media.id && $0.deletedAt == nil }
    }

    private var accessibilityLabel: String {
        var parts = [timeTitle]

        if store.showTagsInTimeline, let primaryTag = item.primaryTag {
            parts.append(L10n.tagName(primaryTag.tag, language: appLanguage))
        }

        if hasPostText {
            parts.append(MomentTextMarkdown.searchableText(item.post.text))
        } else {
            parts.append(fallbackTitle)
        }

        if !previewImageMedia.isEmpty {
            parts.append(L10n.t("Photos", appLanguage))
        }

        return parts.joined(separator: ", ")
    }
}

private struct CalendarDayReviewCheckInRow: View {
    let checkIn: CheckInFeedEntry
    let calendar: Calendar
    let isLast: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeTitle)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .allowsTightening(true)
                .frame(width: 42, alignment: .trailing)
                .padding(.top, 2)

            VStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)

                Rectangle()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 1)
                    .opacity(isLast ? 0 : 1)
            }
            .frame(width: 8)

            CheckInTimelineRow(
                checkIn: checkIn,
                showsDate: false,
                showTagsInTimeline: false,
                onOpenDetail: onOpen
            )
            .padding(.bottom, isLast ? 0 : 18)
        }
    }

    private var dotColor: Color {
        Color(hex: checkIn.item.colorHex) ?? Color.accentColor
    }

    private var timeTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: checkIn.occurredAt)
    }
}

private struct CalendarDayReviewVideoHint: View {
    @Environment(\.appLanguage) private var appLanguage

    let media: TimelineMedia

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "video")
                .font(.caption.weight(.semibold))

            Text(L10n.t("Video", appLanguage))
                .font(.caption.weight(.semibold))

            Spacer(minLength: 0)

            if let duration = media.durationSeconds {
                Text(mediaDurationLabel(duration))
                    .font(.caption.monospacedDigit())
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
