import Foundation

enum MomentDateFormatter {
    static func timelineLabel(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        language: AppResolvedLanguage = .english
    ) -> String {
        if language == .simplifiedChinese {
            return chineseTimelineLabel(for: date, now: now, calendar: calendar)
        }

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

    static func monthTitle(
        for date: Date,
        calendar: Calendar = .current,
        language: AppResolvedLanguage = .english
    ) -> String {
        if language == .simplifiedChinese {
            return chineseMonthTitle(for: date, calendar: calendar)
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    static func dayJumpTitle(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        language: AppResolvedLanguage = .english
    ) -> String {
        if language == .simplifiedChinese {
            return chineseDayJumpTitle(for: date, now: now, calendar: calendar)
        }

        let dayDelta = daysBetween(date, and: now, calendar: calendar)
        if dayDelta == 0 {
            return "Today"
        }

        if dayDelta == 1 {
            return "Yesterday"
        }

        if dayDelta == -1 {
            return "Tomorrow"
        }

        if abs(dayDelta) <= 6 {
            return weekdayTitle(for: date, calendar: calendar)
        }

        let currentYear = calendar.component(.year, from: now)
        let year = calendar.component(.year, from: date)
        if year == currentYear {
            return dayJumpMonthDay(for: date, calendar: calendar)
        }

        return fullDate(for: date, calendar: calendar)
    }

    static func commentRelativeTitle(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        language: AppResolvedLanguage = .english
    ) -> String {
        if language == .simplifiedChinese {
            return chineseCommentRelativeTitle(for: date, now: now, calendar: calendar)
        }

        let elapsed = now.timeIntervalSince(date)

        if elapsed >= 0 {
            if elapsed < 60 {
                return "Just now"
            }

            if elapsed < 60 * 60 {
                return "\(max(Int(elapsed / 60), 1))m ago"
            }

            if elapsed < 24 * 60 * 60, calendar.isDate(date, inSameDayAs: now) {
                return "\(max(Int(elapsed / 3600), 1))h ago"
            }
        }

        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        let currentYear = calendar.component(.year, from: now)
        let year = calendar.component(.year, from: date)
        if year == currentYear {
            return dayJumpMonthDay(for: date, calendar: calendar)
        }

        return fullDate(for: date, calendar: calendar)
    }

    private static func chineseTimelineLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) {
            let delta = date.timeIntervalSince(now)
            if delta <= 0 {
                let elapsed = abs(delta)
                if elapsed < 60 {
                    return "刚刚"
                }
                if elapsed < 60 * 60 {
                    return "\(max(Int(elapsed / 60), 1))分钟前"
                }
            } else if delta < 60 * 60 {
                return "\(max(Int(delta / 60), 1))分钟后"
            }

            return "今天 \(chineseClockTime(for: date, calendar: calendar))"
        }

        if calendar.isDateInYesterday(date) {
            return "昨天 \(chineseClockTime(for: date, calendar: calendar))"
        }

        if calendar.isDateInTomorrow(date) {
            return "明天 \(chineseClockTime(for: date, calendar: calendar))"
        }

        let dayDelta = daysBetween(date, and: now, calendar: calendar)
        if dayDelta > 0 && dayDelta <= 6 {
            return "\(dayDelta)天前"
        }
        if dayDelta < 0 && dayDelta >= -6 {
            return "\(-dayDelta)天后"
        }

        let currentYear = calendar.component(.year, from: now)
        let year = calendar.component(.year, from: date)
        if year == currentYear {
            return "\(chineseMonthDay(for: date, calendar: calendar)) \(chineseClockTime(for: date, calendar: calendar))"
        }

        return chineseFullDate(for: date, calendar: calendar)
    }

    private static func chineseDayJumpTitle(for date: Date, now: Date, calendar: Calendar) -> String {
        let dayDelta = daysBetween(date, and: now, calendar: calendar)
        if dayDelta == 0 {
            return "今天"
        }

        if dayDelta == 1 {
            return "昨天"
        }

        if dayDelta == -1 {
            return "明天"
        }

        if abs(dayDelta) <= 6 {
            return chineseWeekdayTitle(for: date, calendar: calendar)
        }

        let currentYear = calendar.component(.year, from: now)
        let year = calendar.component(.year, from: date)
        if year == currentYear {
            return "\(chineseMonthDay(for: date, calendar: calendar)) \(chineseWeekdayTitle(for: date, calendar: calendar))"
        }

        return chineseFullDate(for: date, calendar: calendar)
    }

    private static func chineseCommentRelativeTitle(for date: Date, now: Date, calendar: Calendar) -> String {
        let elapsed = now.timeIntervalSince(date)

        if elapsed >= 0 {
            if elapsed < 60 {
                return "刚刚"
            }

            if elapsed < 60 * 60 {
                return "\(max(Int(elapsed / 60), 1))分钟前"
            }

            if elapsed < 24 * 60 * 60, calendar.isDate(date, inSameDayAs: now) {
                return "\(max(Int(elapsed / 3600), 1))小时前"
            }
        }

        if calendar.isDateInYesterday(date) {
            return "昨天"
        }

        let currentYear = calendar.component(.year, from: now)
        let year = calendar.component(.year, from: date)
        if year == currentYear {
            return chineseMonthDay(for: date, calendar: calendar)
        }

        return chineseFullDate(for: date, calendar: calendar)
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

    private static func dayJumpMonthDay(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private static func weekdayTitle(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private static func fullDate(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private static func chineseClockTime(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func chineseMonthDay(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private static func chineseMonthTitle(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }

    private static func chineseWeekdayTitle(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private static func chineseFullDate(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }
}
