import SwiftUI

struct CheckInItemInsightsView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage

    let item: CheckInItem

    @State private var detailRoute: CheckInEntryDetailRoute?

    private var entries: [CheckInEntry] {
        store.checkInEntries
            .filter { $0.itemId == item.id && $0.deletedAt == nil }
            .sorted { lhs, rhs in
                if lhs.occurredAt == rhs.occurredAt {
                    return lhs.id > rhs.id
                }

                return lhs.occurredAt > rhs.occurredAt
            }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CheckInInsightsHeader(item: item, entryCount: entries.count, language: appLanguage)
                }

                Section(L10n.t("Time Insights", appLanguage)) {
                    switch item.timeVisualization {
                    case .none:
                        CheckInNoInsightsView(language: appLanguage)
                    case .timeLine:
                        if item.recordMode == .oncePerDay {
                            CheckInTimeLineView(
                                insight: CheckInTimeInsightsBuilder.lineInsight(item: item, entries: entries),
                                color: itemColor,
                                language: appLanguage
                            )
                        } else {
                            CheckInNoInsightsView(language: appLanguage)
                        }
                    case .timeHeatmap:
                        CheckInHeatmapView(
                            insight: CheckInTimeInsightsBuilder.heatmapInsight(item: item, entries: entries),
                            color: itemColor,
                            language: appLanguage
                        )
                    }
                }

                Section(L10n.t("Recent Records", appLanguage)) {
                    if entries.isEmpty {
                        Text(L10n.t("No check-ins yet", appLanguage))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(entries.prefix(30))) { entry in
                            Button {
                                detailRoute = CheckInEntryDetailRoute(entryId: entry.id)
                            } label: {
                                CheckInInsightsEntryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("Done", appLanguage)) {
                        dismiss()
                    }
                }
            }
            .sheet(item: $detailRoute) { route in
                CheckInEntryDetailView(entryId: route.entryId)
            }
        }
    }

    private var itemColor: Color {
        Color(hex: item.colorHex) ?? .accentColor
    }
}

private struct CheckInInsightsHeader: View {
    let item: CheckInItem
    let entryCount: Int
    let language: AppResolvedLanguage

    private var itemColor: Color {
        Color(hex: item.colorHex) ?? .accentColor
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(itemColor)
                .frame(width: 40, height: 40)
                .background(itemColor.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.headline)
                Text("\(entryCount) \(L10n.t("records", language))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

private struct CheckInNoInsightsView: View {
    let language: AppResolvedLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.t("No time visualization", language), systemImage: "chart.xyaxis.line")
                .font(.subheadline.weight(.semibold))
            Text(L10n.t("Choose Time Line or Time Heatmap in Manage to show insights here.", language))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct CheckInTimeLineView: View {
    let insight: CheckInTimeLineInsight
    let color: Color
    let language: AppResolvedLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if insight.hasData {
                HStack(alignment: .top, spacing: 8) {
                    CheckInTimeLineYAxis(insight: insight)
                        .frame(width: 44, height: 156)

                    CheckInTimeLineCanvas(insight: insight, color: color, language: language)
                        .frame(height: 156)
                }

                HStack(spacing: 8) {
                    Spacer()
                        .frame(width: 44)
                    HStack {
                        Text(xAxisStartLabel)
                        Spacer()
                        if insight.points.count > 1 {
                            Text(L10n.t("Today", language))
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Text(L10n.t("No check-ins yet", language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var xAxisStartLabel: String {
        guard let firstDay = insight.points.first?.day else {
            return ""
        }

        if Calendar.current.isDateInToday(firstDay) {
            return L10n.t("Today", language)
        }

        return Self.dayFormatter.string(from: firstDay)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()
}

private struct CheckInTimeLineYAxis: View {
    let insight: CheckInTimeLineInsight

    private var middleMinute: Int {
        (insight.lowerMinute + insight.upperMinute) / 2
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(CheckInTimeInsightsBuilder.timeLabel(for: insight.upperMinute))
            Spacer(minLength: 0)
            Text(CheckInTimeInsightsBuilder.timeLabel(for: middleMinute))
            Spacer(minLength: 0)
            Text(CheckInTimeInsightsBuilder.timeLabel(for: insight.lowerMinute))
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
    }
}

private struct CheckInTimeLineCanvas: View {
    let insight: CheckInTimeLineInsight
    let color: Color
    let language: AppResolvedLanguage

    @State private var selectedIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let layout = CheckInTimeLineChartLayout(insight: insight, size: proxy.size)

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawGrid(context: context, layout: layout)
                    drawSelectionGuide(context: context, layout: layout)
                    drawSeries(context: context, layout: layout)
                }

                if let selected = selectedPlotPoint(in: layout) {
                    CheckInTimeLineTooltip(point: selected.point, language: language)
                        .position(tooltipPosition(for: selected.position, in: proxy.size))
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectedIndex = layout.nearestDataPointIndex(toX: value.location.x)
                    }
            )
            .animation(.snappy(duration: 0.12), value: selectedIndex)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("Time Line", language))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard
            let selectedIndex,
            insight.points.indices.contains(selectedIndex),
            let minute = insight.points[selectedIndex].minuteOfDay
        else {
            return ""
        }

        return CheckInTimeInsightsBuilder.timeLabel(for: minute)
    }

    private func selectedPlotPoint(in layout: CheckInTimeLineChartLayout) -> CheckInTimeLinePlotPoint? {
        guard let selectedIndex else {
            return nil
        }

        return layout.plotPoints.first { $0.index == selectedIndex && $0.point.plottedMinute != nil }
    }

    private func tooltipPosition(for point: CGPoint, in size: CGSize) -> CGPoint {
        let width = max(size.width, 1)
        let x = min(max(point.x, 58), max(width - 58, 58))
        let y = max(point.y - 26, 18)
        return CGPoint(x: x, y: y)
    }

    private func drawGrid(context: GraphicsContext, layout: CheckInTimeLineChartLayout) {
        for ratio in [CGFloat(0), 0.5, 1] {
            let y = layout.yInset + layout.plotHeight * ratio
            var gridLine = Path()
            gridLine.move(to: CGPoint(x: layout.xInset, y: y))
            gridLine.addLine(to: CGPoint(x: layout.xInset + layout.plotWidth, y: y))
            context.stroke(
                gridLine,
                with: .color(.secondary.opacity(0.15)),
                style: StrokeStyle(lineWidth: 1, lineCap: .round)
            )
        }
    }

    private func drawSelectionGuide(context: GraphicsContext, layout: CheckInTimeLineChartLayout) {
        guard let selected = selectedPlotPoint(in: layout) else {
            return
        }

        var guide = Path()
        guide.move(to: CGPoint(x: selected.position.x, y: layout.yInset))
        guide.addLine(to: CGPoint(x: selected.position.x, y: layout.yInset + layout.plotHeight))
        context.stroke(
            guide,
            with: .color(.secondary.opacity(0.35)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
        )
    }

    private func drawSeries(context: GraphicsContext, layout: CheckInTimeLineChartLayout) {
        var previous: CGPoint?

        for plotPoint in layout.plotPoints {
            let isSelected = plotPoint.index == selectedIndex

            guard plotPoint.point.plottedMinute != nil else {
                previous = nil
                context.stroke(
                    Path(ellipseIn: CGRect(x: plotPoint.position.x - 2, y: plotPoint.position.y - 2, width: 4, height: 4)),
                    with: .color(.secondary.opacity(0.35)),
                    lineWidth: 1
                )
                continue
            }

            if let previous {
                var segment = Path()
                segment.move(to: previous)
                segment.addLine(to: plotPoint.position)
                context.stroke(segment, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }

            if isSelected {
                context.fill(
                    Path(ellipseIn: CGRect(x: plotPoint.position.x - 6, y: plotPoint.position.y - 6, width: 12, height: 12)),
                    with: .color(color.opacity(0.18))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: plotPoint.position.x - 4.5, y: plotPoint.position.y - 4.5, width: 9, height: 9)),
                    with: .color(color)
                )
                context.stroke(
                    Path(ellipseIn: CGRect(x: plotPoint.position.x - 4.5, y: plotPoint.position.y - 4.5, width: 9, height: 9)),
                    with: .color(.white.opacity(0.85)),
                    lineWidth: 1.5
                )
            } else {
                context.fill(
                    Path(ellipseIn: CGRect(x: plotPoint.position.x - 3.5, y: plotPoint.position.y - 3.5, width: 7, height: 7)),
                    with: .color(color)
                )
            }

            previous = plotPoint.position
        }
    }
}

struct CheckInTimeLinePlotPoint: Equatable {
    let index: Int
    let point: CheckInTimeLinePoint
    let position: CGPoint
}

struct CheckInTimeLineChartLayout {
    let insight: CheckInTimeLineInsight
    let size: CGSize

    let xInset: CGFloat = 6
    let yInset: CGFloat = 8

    var width: CGFloat {
        max(size.width, 1)
    }

    var height: CGFloat {
        max(size.height, 1)
    }

    var plotWidth: CGFloat {
        max(width - xInset * 2, 1)
    }

    var plotHeight: CGFloat {
        max(height - yInset * 2, 1)
    }

    var plotPoints: [CheckInTimeLinePlotPoint] {
        insight.points.indices.map { index in
            CheckInTimeLinePlotPoint(
                index: index,
                point: insight.points[index],
                position: position(for: index)
            )
        }
    }

    func nearestDataPointIndex(toX x: CGFloat) -> Int? {
        plotPoints
            .filter { $0.point.plottedMinute != nil }
            .min { lhs, rhs in
                abs(lhs.position.x - x) < abs(rhs.position.x - x)
            }?
            .index
    }

    private func position(for index: Int) -> CGPoint {
        let count = max(insight.points.count - 1, 1)
        let x = xInset + plotWidth * CGFloat(index) / CGFloat(count)
        guard let plottedMinute = insight.points[index].plottedMinute else {
            return CGPoint(x: x, y: yInset + plotHeight)
        }

        let range = max(insight.upperMinute - insight.lowerMinute, 1)
        let ratio = CGFloat(plottedMinute - insight.lowerMinute) / CGFloat(range)
        return CGPoint(x: x, y: yInset + plotHeight - ratio * plotHeight)
    }
}

private struct CheckInTimeLineTooltip: View {
    let point: CheckInTimeLinePoint
    let language: AppResolvedLanguage

    var body: some View {
        VStack(spacing: 1) {
            Text(dayLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(timeLabel)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.secondary.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    private var dayLabel: String {
        if Calendar.current.isDateInToday(point.day) {
            return L10n.t("Today", language)
        }

        return Self.dayFormatter.string(from: point.day)
    }

    private var timeLabel: String {
        guard let minute = point.minuteOfDay else {
            return ""
        }

        return CheckInTimeInsightsBuilder.timeLabel(for: minute)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()
}

private struct CheckInHeatmapView: View {
    let insight: CheckInHeatmapInsight
    let color: Color
    let language: AppResolvedLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if insight.hasData {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("24h distribution", language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    CheckInHourDistributionView(buckets: insight.hourBuckets, color: color)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("Weekday x time", language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    CheckInWeekdayHeatmapGrid(buckets: insight.weekdayHourBuckets, color: color)
                }
            } else {
                Text(L10n.t("No check-ins yet", language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct CheckInHourDistributionView: View {
    let buckets: [CheckInHourBucket]
    let color: Color

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(buckets) { bucket in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color.opacity(insightOpacity(for: bucket.intensity, isEmpty: bucket.count == 0)))
                        .frame(height: 18)
                    Text(String(format: "%02d", bucket.hour))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("\(bucket.hour):00 \(bucket.count)")
            }
        }
    }
}

private struct CheckInWeekdayHeatmapGrid: View {
    let buckets: [CheckInWeekdayHourBucket]
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ForEach(1...7, id: \.self) { weekday in
                HStack(spacing: 3) {
                    Text(weekdayLabel(weekday))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)

                    ForEach(0..<24, id: \.self) { hour in
                        let bucket = bucket(weekday: weekday, hour: hour)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(color.opacity(insightOpacity(for: bucket.intensity, isEmpty: bucket.count == 0)))
                            .frame(height: 10)
                            .accessibilityLabel("\(weekdayLabel(weekday)) \(hour):00 \(bucket.count)")
                    }
                }
            }
        }
    }

    private func bucket(weekday: Int, hour: Int) -> CheckInWeekdayHourBucket {
        buckets.first { $0.weekday == weekday && $0.hour == hour }
            ?? CheckInWeekdayHourBucket(weekday: weekday, hour: hour, count: 0, maxCount: 0)
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        guard symbols.indices.contains(weekday - 1) else {
            return "\(weekday)"
        }

        return symbols[weekday - 1]
    }
}

private struct CheckInInsightsEntryRow: View {
    let entry: CheckInEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.historyFormatter.string(from: entry.occurredAt))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if entry.hasNote {
                    Text(entry.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private static let historyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private func insightOpacity(for intensity: Double, isEmpty: Bool) -> Double {
    if isEmpty {
        return 0.08
    }

    return 0.18 + min(max(intensity, 0), 1) * 0.72
}
