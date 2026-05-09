import Foundation

enum CheckInDayBoundary {
    static func normalizedHour(_ value: Int) -> Int {
        min(max(value, 0), 23)
    }

    static func dayStart(
        containing date: Date,
        dayStartHour: Int,
        calendar: Calendar = .current
    ) -> Date {
        let hour = normalizedHour(dayStartHour)
        guard hour > 0,
              let shiftedDate = calendar.date(byAdding: .hour, value: -hour, to: date) else {
            return calendar.startOfDay(for: date)
        }

        let shiftedDayStart = calendar.startOfDay(for: shiftedDate)
        return calendar.date(byAdding: .hour, value: hour, to: shiftedDayStart) ?? shiftedDayStart
    }

    static func dayStart(
        forDisplayDay day: Date,
        dayStartHour: Int,
        calendar: Calendar = .current
    ) -> Date {
        let hour = normalizedHour(dayStartHour)
        let naturalStart = calendar.startOfDay(for: day)
        guard hour > 0 else {
            return naturalStart
        }

        return calendar.date(byAdding: .hour, value: hour, to: naturalStart) ?? naturalStart
    }

    static func dayRange(
        containing date: Date,
        dayStartHour: Int,
        calendar: Calendar = .current
    ) -> Range<Date> {
        let start = dayStart(containing: date, dayStartHour: dayStartHour, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return start..<end
    }

    static func isSameItemDay(
        _ lhs: Date,
        _ rhs: Date,
        dayStartHour: Int,
        calendar: Calendar = .current
    ) -> Bool {
        dayStart(containing: lhs, dayStartHour: dayStartHour, calendar: calendar) ==
            dayStart(containing: rhs, dayStartHour: dayStartHour, calendar: calendar)
    }
}
