import Foundation

struct CheckInTimeLinePoint: Identifiable, Equatable {
    let day: Date
    let entry: CheckInEntry?
    let minuteOfDay: Int?
    let plottedMinute: Int?

    var id: Date {
        day
    }
}

struct CheckInTimeLineInsight: Equatable {
    let points: [CheckInTimeLinePoint]
    let lowerMinute: Int
    let upperMinute: Int
    let usesOvernightExpansion: Bool

    var hasData: Bool {
        points.contains { $0.plottedMinute != nil }
    }
}

struct CheckInHourBucket: Identifiable, Equatable {
    let hour: Int
    let count: Int
    let maxCount: Int

    var id: Int {
        hour
    }

    var intensity: Double {
        guard maxCount > 0 else {
            return 0
        }

        return Double(count) / Double(maxCount)
    }
}

struct CheckInWeekdayHourBucket: Identifiable, Equatable {
    let weekday: Int
    let hour: Int
    let count: Int
    let maxCount: Int

    var id: String {
        "\(weekday)-\(hour)"
    }

    var intensity: Double {
        guard maxCount > 0 else {
            return 0
        }

        return Double(count) / Double(maxCount)
    }
}

struct CheckInHeatmapInsight: Equatable {
    let hourBuckets: [CheckInHourBucket]
    let weekdayHourBuckets: [CheckInWeekdayHourBucket]
    let entries: [CheckInEntry]
    let maxCount: Int
    let totalEntries: Int

    var hasData: Bool {
        totalEntries > 0
    }

    func entries(for selection: CheckInHeatmapSelection, calendar: Calendar = .current) -> [CheckInEntry] {
        entries.filter { entry in
            let hour = calendar.component(.hour, from: entry.occurredAt)
            guard hour == selection.hour else {
                return false
            }

            if let weekday = selection.weekday {
                return calendar.component(.weekday, from: entry.occurredAt) == weekday
            }

            return true
        }
    }
}

struct CheckInHeatmapSelection: Identifiable, Equatable {
    let weekday: Int?
    let hour: Int

    var id: String {
        if let weekday {
            return "\(weekday)-\(hour)"
        }

        return "hour-\(hour)"
    }
}

enum CheckInTimeInsightsBuilder {
    static let defaultDayCount = 30

    static func lineInsight(
        item: CheckInItem,
        entries: [CheckInEntry],
        now: Date = Date(),
        calendar: Calendar = .current,
        dayCount: Int = defaultDayCount
    ) -> CheckInTimeLineInsight {
        let windowDays = insightDays(
            endingAt: now,
            dayStartHour: item.dayStartHour,
            calendar: calendar,
            dayCount: dayCount
        )
        let range = insightRange(
            endingAt: now,
            dayStartHour: item.dayStartHour,
            calendar: calendar,
            dayCount: dayCount
        )
        let entriesByDay = Dictionary(
            grouping: activeEntries(for: item, entries: entries, in: range)
        ) { entry in
            CheckInDayBoundary.dayStart(
                containing: entry.occurredAt,
                dayStartHour: item.dayStartHour,
                calendar: calendar
            )
        }
        let firstEntryByDay: [Date: CheckInEntry] = Dictionary(uniqueKeysWithValues: entriesByDay.compactMap { day, dayEntries in
            guard let first = dayEntries.sorted(by: { lhs, rhs in
                if lhs.occurredAt == rhs.occurredAt {
                    return lhs.id < rhs.id
                }

                return lhs.occurredAt < rhs.occurredAt
            }).first else {
                return nil
            }

            return (day, first)
        })
        let days: [Date]
        if let firstDataDay = firstEntryByDay.keys.min(),
           let firstIndex = windowDays.firstIndex(of: firstDataDay) {
            days = Array(windowDays[firstIndex...])
        } else {
            days = []
        }

        let rawMinutes = days.compactMap { day -> Int? in
            guard let entry = firstEntryByDay[day] else {
                return nil
            }

            return minuteOfDay(for: entry.occurredAt, calendar: calendar)
        }
        let usesOvernightExpansion = shouldUseOvernightExpansion(minutes: rawMinutes)
        let plottedByDay = Dictionary(uniqueKeysWithValues: days.compactMap { day -> (Date, Int)? in
            guard let entry = firstEntryByDay[day] else {
                return nil
            }

            let minute = minuteOfDay(for: entry.occurredAt, calendar: calendar)
            return (day, usesOvernightExpansion && minute < 720 ? minute + 1_440 : minute)
        })

        let plottedMinutes = days.compactMap { plottedByDay[$0] }
        let bounds = minuteBounds(for: plottedMinutes)
        let points = days.map { day in
            let entry = firstEntryByDay[day]
            let minute = entry.map { minuteOfDay(for: $0.occurredAt, calendar: calendar) }
            return CheckInTimeLinePoint(
                day: day,
                entry: entry,
                minuteOfDay: minute,
                plottedMinute: plottedByDay[day]
            )
        }

        return CheckInTimeLineInsight(
            points: points,
            lowerMinute: bounds.lower,
            upperMinute: bounds.upper,
            usesOvernightExpansion: usesOvernightExpansion
        )
    }

    static func heatmapInsight(
        item: CheckInItem,
        entries: [CheckInEntry],
        now: Date = Date(),
        calendar: Calendar = .current,
        dayCount: Int = defaultDayCount
    ) -> CheckInHeatmapInsight {
        let range = insightRange(endingAt: now, dayStartHour: 0, calendar: calendar, dayCount: dayCount)
        let scopedEntries = activeEntries(for: item, entries: entries, in: range)
        var hourCounts = Array(repeating: 0, count: 24)
        var weekdayHourCounts = [String: Int]()

        for entry in scopedEntries {
            let hour = calendar.component(.hour, from: entry.occurredAt)
            let weekday = calendar.component(.weekday, from: entry.occurredAt)
            hourCounts[hour] += 1
            weekdayHourCounts["\(weekday)-\(hour)", default: 0] += 1
        }

        let maxCount = max(hourCounts.max() ?? 0, weekdayHourCounts.values.max() ?? 0)
        let hourBuckets = (0..<24).map { hour in
            CheckInHourBucket(hour: hour, count: hourCounts[hour], maxCount: maxCount)
        }
        let weekdayHourBuckets = (1...7).flatMap { weekday in
            (0..<24).map { hour in
                CheckInWeekdayHourBucket(
                    weekday: weekday,
                    hour: hour,
                    count: weekdayHourCounts["\(weekday)-\(hour)", default: 0],
                    maxCount: maxCount
                )
            }
        }

        return CheckInHeatmapInsight(
            hourBuckets: hourBuckets,
            weekdayHourBuckets: weekdayHourBuckets,
            entries: scopedEntries.sorted { lhs, rhs in
                if lhs.occurredAt == rhs.occurredAt {
                    return lhs.id > rhs.id
                }

                return lhs.occurredAt > rhs.occurredAt
            },
            maxCount: maxCount,
            totalEntries: scopedEntries.count
        )
    }

    static func timeLabel(for minute: Int) -> String {
        let normalized = ((minute % 1_440) + 1_440) % 1_440
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }

    private static func activeEntries(
        for item: CheckInItem,
        entries: [CheckInEntry],
        in range: Range<Date>
    ) -> [CheckInEntry] {
        entries.filter { entry in
            entry.itemId == item.id
                && entry.deletedAt == nil
                && range.contains(entry.occurredAt)
        }
    }

    private static func insightDays(
        endingAt now: Date,
        dayStartHour: Int,
        calendar: Calendar,
        dayCount: Int
    ) -> [Date] {
        let count = max(dayCount, 1)
        let endDay = CheckInDayBoundary.dayStart(
            containing: now,
            dayStartHour: dayStartHour,
            calendar: calendar
        )
        let startDay = calendar.date(byAdding: .day, value: -(count - 1), to: endDay) ?? endDay
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startDay)
        }
    }

    private static func insightRange(
        endingAt now: Date,
        dayStartHour: Int,
        calendar: Calendar,
        dayCount: Int
    ) -> Range<Date> {
        let days = insightDays(
            endingAt: now,
            dayStartHour: dayStartHour,
            calendar: calendar,
            dayCount: dayCount
        )
        let start = days.first ?? CheckInDayBoundary.dayStart(
            containing: now,
            dayStartHour: dayStartHour,
            calendar: calendar
        )
        let endDay = days.last ?? start
        let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? now
        return start..<end
    }

    private static func minuteOfDay(for date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    private static func shouldUseOvernightExpansion(minutes: [Int]) -> Bool {
        guard minutes.count >= 2 else {
            return false
        }

        let rawSpan = (minutes.max() ?? 0) - (minutes.min() ?? 0)
        let shifted = minutes.map { minute in
            minute < 720 ? minute + 1_440 : minute
        }
        let shiftedSpan = (shifted.max() ?? 0) - (shifted.min() ?? 0)
        return shiftedSpan < rawSpan
    }

    private static func minuteBounds(for minutes: [Int]) -> (lower: Int, upper: Int) {
        guard let minMinute = minutes.min(), let maxMinute = minutes.max() else {
            return (0, 1_440)
        }

        var lower = (minMinute / 60) * 60 - 60
        var upper = ((maxMinute + 59) / 60) * 60 + 60
        if upper - lower < 120 {
            lower -= 60
            upper += 60
        }

        return (lower, upper)
    }
}
