import Foundation

struct TimelineDateJumpMonthGroup: Identifiable {
    let id: String
    let title: String
    let menuTitle: String
    let monthStart: Date
    let anchorItemID: TimelineItem.ID
    let items: [TimelineItem]
}

enum TimelineDateJumpBuilder {
    static func groups(
        from items: [TimelineItem],
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

                return TimelineDateJumpMonthGroup(
                    id: monthID(for: monthStart, calendar: calendar),
                    title: MomentDateFormatter.monthTitle(for: monthStart, calendar: calendar),
                    menuTitle: MomentDateFormatter.monthMenuTitle(for: monthStart, calendar: calendar),
                    monthStart: monthStart,
                    anchorItemID: anchorItem.id,
                    items: monthItems
                )
            }
            .sorted { lhs, rhs in
                lhs.monthStart > rhs.monthStart
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
}
