import Foundation

enum CheckInRecordMode: String, CaseIterable, Codable, Identifiable {
    case oncePerDay
    case multiplePerDay

    var id: String {
        rawValue
    }

    func title(language: AppResolvedLanguage = .english) -> String {
        switch self {
        case .oncePerDay:
            return L10n.t("Once per day", language)
        case .multiplePerDay:
            return L10n.t("Multiple per day", language)
        }
    }

    var systemImage: String {
        switch self {
        case .oncePerDay:
            return "checkmark.circle"
        case .multiplePerDay:
            return "plus.circle"
        }
    }
}

enum CheckInTimeVisualization: String, CaseIterable, Codable, Identifiable {
    case none
    case timeLine
    case timeHeatmap

    var id: String {
        rawValue
    }

    func title(language: AppResolvedLanguage = .english) -> String {
        switch self {
        case .none:
            return L10n.t("None", language)
        case .timeLine:
            return L10n.t("Time Line", language)
        case .timeHeatmap:
            return L10n.t("Time Heatmap", language)
        }
    }

    var systemImage: String {
        switch self {
        case .none:
            return "minus.circle"
        case .timeLine:
            return "chart.xyaxis.line"
        case .timeHeatmap:
            return "square.grid.3x3"
        }
    }
}

struct CheckInItem: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var symbolName: String
    var colorHex: String
    var recordMode: CheckInRecordMode
    var timeVisualization: CheckInTimeVisualization
    var dayStartHour: Int
    var activeWeekdays: [Int]
    var sortOrder: Int
    var defaultShowInTimeline: Bool
    var tagId: String?
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var deletedAt: Date?
    var syncStatus: String

    var isArchived: Bool {
        archivedAt != nil
    }

    func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        let itemDayStart = CheckInDayBoundary.dayStart(
            containing: date,
            dayStartHour: dayStartHour,
            calendar: calendar
        )
        return activeWeekdays.contains(calendar.component(.weekday, from: itemDayStart))
    }
}

struct CheckInEntry: Identifiable, Codable, Equatable {
    var id: String
    var itemId: String
    var occurredAt: Date
    var note: String
    var showInTimeline: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: String

    var hasNote: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct CheckInMedia: Identifiable, Codable, Equatable {
    var id: String
    var entryId: String
    var kind: String
    var localCompressedPath: String
    var remoteCompressedPath: String?
    var uploadStatus: String
    var uploadError: String?
    var mimeType: String?
    var sortOrder: Int
    var checksum: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var isImage: Bool {
        kind == "image"
    }

    var hasLocalDisplayFile: Bool {
        !localCompressedPath.isEmpty && FileManager.default.fileExists(atPath: localCompressedPath)
    }
}

struct CheckInFeedEntry: Identifiable {
    let entry: CheckInEntry
    let item: CheckInItem
    let tag: TimelineTag?
    let media: [CheckInMedia]

    var id: String {
        entry.id
    }

    var occurredAt: Date {
        entry.occurredAt
    }

    var syncStatus: String {
        if entry.syncStatus != "synced" {
            return entry.syncStatus
        }

        if item.syncStatus != "synced" {
            return item.syncStatus
        }

        if media.contains(where: { $0.uploadStatus == "failed" }) {
            return "failed"
        }

        if media.contains(where: { $0.uploadStatus == "pending" }) {
            return "partial"
        }

        return "synced"
    }

    var isDeleted: Bool {
        entry.deletedAt != nil || item.deletedAt != nil
    }
}

enum MomentFeedItem: Identifiable {
    case moment(TimelineItem)
    case checkIn(CheckInFeedEntry)

    var id: String {
        switch self {
        case .moment(let item):
            return "moment-\(item.id)"
        case .checkIn(let checkIn):
            return "checkin-\(checkIn.id)"
        }
    }

    var rawItemID: String {
        switch self {
        case .moment(let item):
            return item.id
        case .checkIn(let checkIn):
            return checkIn.id
        }
    }

    var occurredAt: Date {
        switch self {
        case .moment(let item):
            return item.post.occurredAt
        case .checkIn(let checkIn):
            return checkIn.occurredAt
        }
    }

    var isMoment: Bool {
        if case .moment = self {
            return true
        }

        return false
    }

    var isCheckIn: Bool {
        if case .checkIn = self {
            return true
        }

        return false
    }

    var moment: TimelineItem? {
        if case .moment(let item) = self {
            return item
        }

        return nil
    }

    var checkIn: CheckInFeedEntry? {
        if case .checkIn(let item) = self {
            return item
        }

        return nil
    }

    var media: [TimelineMedia] {
        moment?.media ?? []
    }

    var comments: [TimelineComment] {
        moment?.comments ?? []
    }

    var primaryTagId: String? {
        switch self {
        case .moment(let item):
            return item.primaryTag?.tagId
        case .checkIn(let item):
            return item.tag?.id
        }
    }

    var topicTagIds: Set<String> {
        Set(moment?.topicTags.map(\.tagId) ?? [])
    }

    var syncStatus: String {
        switch self {
        case .moment(let item):
            return item.post.syncStatus
        case .checkIn(let item):
            return item.syncStatus
        }
    }

    var sortKey: String {
        switch self {
        case .moment(let item):
            return item.id
        case .checkIn(let item):
            return item.id
        }
    }
}
