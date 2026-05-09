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
                HStack {
                    Text(CheckInTimeInsightsBuilder.timeLabel(for: insight.upperMinute))
                    Spacer()
                    Text(CheckInTimeInsightsBuilder.timeLabel(for: insight.lowerMinute))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

                CheckInTimeLineCanvas(insight: insight, color: color)
                    .frame(height: 150)

                HStack {
                    Text("30d")
                    Spacer()
                    Text(L10n.t("Today", language))
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
}

private struct CheckInTimeLineCanvas: View {
    let insight: CheckInTimeLineInsight
    let color: Color

    var body: some View {
        Canvas { context, size in
            let width = max(size.width, 1)
            let height = max(size.height, 1)
            let count = max(insight.points.count - 1, 1)
            let range = max(insight.upperMinute - insight.lowerMinute, 1)
            var previous: CGPoint?

            for (index, point) in insight.points.enumerated() {
                let x = width * Double(index) / Double(count)
                guard let plottedMinute = point.plottedMinute else {
                    previous = nil
                    let y = height - 2
                    context.stroke(
                        Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)),
                        with: .color(.secondary.opacity(0.35)),
                        lineWidth: 1
                    )
                    continue
                }

                let ratio = Double(plottedMinute - insight.lowerMinute) / Double(range)
                let y = height - ratio * height
                let current = CGPoint(x: x, y: y)
                if let previous {
                    var segment = Path()
                    segment.move(to: previous)
                    segment.addLine(to: current)
                    context.stroke(segment, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }

                context.fill(
                    Path(ellipseIn: CGRect(x: x - 3.5, y: y - 3.5, width: 7, height: 7)),
                    with: .color(color)
                )
                previous = current
            }
        }
        .accessibilityHidden(true)
    }
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
