import SwiftUI

struct CheckInHeatmapView: View {
    let insight: CheckInHeatmapInsight
    let color: Color
    let language: AppResolvedLanguage
    let onOpenEntry: (CheckInEntry) -> Void

    @State private var selection: CheckInHeatmapSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if insight.hasData {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("24h distribution", language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    CheckInHourDistributionView(
                        buckets: insight.hourBuckets,
                        color: color,
                        selection: selection,
                        onSelect: selectHour
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("Weekday x time", language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    CheckInWeekdayHeatmapGrid(
                        buckets: insight.weekdayHourBuckets,
                        color: color,
                        selection: selection,
                        onSelect: selectWeekdayHour
                    )
                }

                if let selection {
                    CheckInHeatmapSelectionPanel(
                        selection: selection,
                        entries: insight.entries(for: selection),
                        language: language,
                        onOpenEntry: onOpenEntry
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                Text(L10n.t("No check-ins yet", language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .animation(.snappy(duration: 0.14), value: selection)
    }

    private func selectHour(_ hour: Int) {
        selection = CheckInHeatmapSelection(weekday: nil, hour: hour)
    }

    private func selectWeekdayHour(weekday: Int, hour: Int) {
        selection = CheckInHeatmapSelection(weekday: weekday, hour: hour)
    }
}

private struct CheckInHourDistributionView: View {
    let buckets: [CheckInHourBucket]
    let color: Color
    let selection: CheckInHeatmapSelection?
    let onSelect: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(buckets) { bucket in
                Button {
                    onSelect(bucket.hour)
                } label: {
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color.opacity(insightOpacity(for: bucket.intensity, isEmpty: bucket.count == 0)))
                            .frame(height: 18)
                            .overlay {
                                if isSelected(bucket) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .stroke(color, lineWidth: 1.6)
                                }
                            }

                        Text(String(format: "%02d", bucket.hour))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(isSelected(bucket) ? color : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: bucket))
            }
        }
    }

    private func isSelected(_ bucket: CheckInHourBucket) -> Bool {
        selection?.weekday == nil && selection?.hour == bucket.hour
    }

    private func accessibilityLabel(for bucket: CheckInHourBucket) -> String {
        "\(CheckInTimeInsightsBuilder.timeLabel(for: bucket.hour * 60)) \(bucket.count)"
    }
}

private struct CheckInWeekdayHeatmapGrid: View {
    let buckets: [CheckInWeekdayHourBucket]
    let color: Color
    let selection: CheckInHeatmapSelection?
    let onSelect: (Int, Int) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(1...7, id: \.self) { weekday in
                HStack(spacing: 3) {
                    Text(weekdayLabel(weekday))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)

                    CheckInWeekdayHeatmapRow(
                        weekday: weekday,
                        buckets: buckets.filter { $0.weekday == weekday },
                        color: color,
                        selection: selection,
                        weekdayLabel: weekdayLabel(weekday),
                        onSelect: onSelect
                    )
                }
            }
        }
    }
}

private struct CheckInWeekdayHeatmapRow: View {
    let weekday: Int
    let buckets: [CheckInWeekdayHourBucket]
    let color: Color
    let selection: CheckInHeatmapSelection?
    let weekdayLabel: String
    let onSelect: (Int, Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { hour in
                    let bucket = bucket(hour: hour)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color.opacity(insightOpacity(for: bucket.intensity, isEmpty: bucket.count == 0)))
                        .overlay {
                            if isSelected(hour: hour) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .stroke(color, lineWidth: 1.5)
                            }
                        }
                        .contentShape(Rectangle())
                        .accessibilityLabel("\(weekdayLabel) \(CheckInTimeInsightsBuilder.timeLabel(for: hour * 60)) \(bucket.count)")
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSelect(weekday, hour(at: value.location.x, width: proxy.size.width))
                    }
            )
        }
        .frame(height: 10)
    }

    private func bucket(hour: Int) -> CheckInWeekdayHourBucket {
        buckets.first { $0.hour == hour }
            ?? CheckInWeekdayHourBucket(weekday: weekday, hour: hour, count: 0, maxCount: 0)
    }

    private func isSelected(hour: Int) -> Bool {
        selection?.weekday == weekday && selection?.hour == hour
    }

    private func hour(at x: CGFloat, width: CGFloat) -> Int {
        let clamped = min(max(x, 0), max(width - 0.1, 0))
        let raw = Int((clamped / max(width, 1)) * 24)
        return min(max(raw, 0), 23)
    }
}

private struct CheckInHeatmapSelectionPanel: View {
    let selection: CheckInHeatmapSelection
    let entries: [CheckInEntry]
    let language: AppResolvedLanguage
    let onOpenEntry: (CheckInEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectionTitle)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text("\(entries.count) \(L10n.t("records", language))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if entries.isEmpty {
                Text(L10n.t("No records in this time bucket", language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.prefix(4))) { entry in
                        Button {
                            onOpenEntry(entry)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Self.historyFormatter.string(from: entry.occurredAt))
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    if entry.hasNote {
                                        Text(entry.note)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer(minLength: 8)

                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if entry.id != entries.prefix(4).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var selectionTitle: String {
        let hourRange = "\(CheckInTimeInsightsBuilder.timeLabel(for: selection.hour * 60))-\(CheckInTimeInsightsBuilder.timeLabel(for: selection.hour * 60 + 59))"
        if let weekday = selection.weekday {
            return "\(weekdayLabel(weekday)) · \(hourRange)"
        }

        return hourRange
    }

    private static let historyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private func weekdayLabel(_ weekday: Int) -> String {
    let symbols = Calendar.current.shortWeekdaySymbols
    guard symbols.indices.contains(weekday - 1) else {
        return "\(weekday)"
    }

    return symbols[weekday - 1]
}

private func insightOpacity(for intensity: Double, isEmpty: Bool) -> Double {
    if isEmpty {
        return 0.08
    }

    return 0.18 + min(max(intensity, 0), 1) * 0.72
}
