import Foundation

struct TimelineDateJumpMonthGroup: Identifiable {
    let id: String
    let title: String
    let monthStart: Date
    let anchorItemID: TimelineItem.ID
    let days: [TimelineDateJumpDayGroup]
    let items: [TimelineItem]
}

struct TimelineDateJumpDayGroup: Identifiable {
    let id: String
    let title: String
    let dayStart: Date
    let targetItemID: TimelineItem.ID
    let items: [TimelineItem]
}

enum TimelineDateJumpBuilder {
    static func groups(
        from items: [TimelineItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TimelineDateJumpMonthGroup] {
        let sortedItems = items.sorted { lhs, rhs in
            if lhs.post.occurredAt == rhs.post.occurredAt {
                return lhs.id > rhs.id
            }

            return lhs.post.occurredAt > rhs.post.occurredAt
        }

        let groupedByMonth = Dictionary(grouping: sortedItems) { item in
            monthStart(for: item.post.occurredAt, calendar: calendar)
        }

        return groupedByMonth
            .compactMap { monthStart, monthItems -> TimelineDateJumpMonthGroup? in
                guard let anchorItem = monthItems.first else {
                    return nil
                }

                let days = dayGroups(from: monthItems, now: now, calendar: calendar)
                return TimelineDateJumpMonthGroup(
                    id: monthID(for: monthStart, calendar: calendar),
                    title: MomentDateFormatter.monthTitle(for: monthStart, calendar: calendar),
                    monthStart: monthStart,
                    anchorItemID: anchorItem.id,
                    days: days,
                    items: monthItems
                )
            }
            .sorted { lhs, rhs in
                lhs.monthStart > rhs.monthStart
            }
    }

    private static func dayGroups(
        from items: [TimelineItem],
        now: Date,
        calendar: Calendar
    ) -> [TimelineDateJumpDayGroup] {
        let groupedByDay = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.post.occurredAt)
        }

        return groupedByDay
            .compactMap { dayStart, dayItems -> TimelineDateJumpDayGroup? in
                guard let targetItem = dayItems.first else {
                    return nil
                }

                return TimelineDateJumpDayGroup(
                    id: dayID(for: dayStart, calendar: calendar),
                    title: MomentDateFormatter.dayJumpTitle(for: dayStart, now: now, calendar: calendar),
                    dayStart: dayStart,
                    targetItemID: targetItem.id,
                    items: dayItems
                )
            }
            .sorted { lhs, rhs in
                lhs.dayStart > rhs.dayStart
            }
    }

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.era, .year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private static func monthID(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.era, .year, .month], from: date)
        let era = components.era ?? 1
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "date-jump-month-%04d-%04d-%02d", era, year, month)
    }

    private static func dayID(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        let era = components.era ?? 1
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "date-jump-day-%04d-%04d-%02d-%02d", era, year, month, day)
    }
}
