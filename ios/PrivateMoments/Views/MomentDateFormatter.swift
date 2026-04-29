import Foundation

enum MomentDateFormatter {
    static func timelineLabel(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            let delta = date.timeIntervalSince(now)
            if delta <= 0 {
                let elapsed = abs(delta)
                if elapsed < 60 {
                    return "Just now"
                }
                if elapsed < 60 * 60 {
                    return "\(max(Int(elapsed / 60), 1)) min ago"
                }
            } else if delta < 60 * 60 {
                return "In \(max(Int(delta / 60), 1)) min"
            }

            return "Today \(clockTime(for: date, calendar: calendar))"
        }

        if calendar.isDateInYesterday(date) {
            return "Yesterday \(clockTime(for: date, calendar: calendar))"
        }

        if calendar.isDateInTomorrow(date) {
            return "Tomorrow \(clockTime(for: date, calendar: calendar))"
        }

        let dayDelta = daysBetween(date, and: now, calendar: calendar)
        if dayDelta > 0 && dayDelta <= 6 {
            return "\(dayDelta) days ago"
        }
        if dayDelta < 0 && dayDelta >= -6 {
            return "In \(-dayDelta) days"
        }

        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let currentYear = calendar.component(.year, from: now)
        let year = components.year ?? currentYear

        if year == currentYear {
            return "\(shortMonthDay(for: date, calendar: calendar)) \(clockTime(for: date, calendar: calendar))"
        }

        return fullDate(for: date, calendar: calendar)
    }

    static func monthTitle(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private static func daysBetween(_ date: Date, and now: Date, calendar: Calendar) -> Int {
        let dateStart = calendar.startOfDay(for: date)
        let nowStart = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: dateStart, to: nowStart).day ?? 0
    }

    private static func clockTime(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private static func shortMonthDay(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d,"
        return formatter.string(from: date)
    }

    private static func fullDate(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
