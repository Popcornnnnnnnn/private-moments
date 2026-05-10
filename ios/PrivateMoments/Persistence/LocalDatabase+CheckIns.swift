import Foundation
import SQLite3

extension LocalDatabase {
    func fetchCheckInItems(includeArchived: Bool = true, includeDeleted: Bool = false) throws -> [CheckInItem] {
        let statement = try prepare(
            """
            SELECT id, name, symbolName, colorHex, recordMode, timeVisualization, dayStartHour,
                   activeWeekdays, sortOrder,
                   defaultShowInTimeline, tagId, createdAt, updatedAt, archivedAt, deletedAt, syncStatus
            FROM local_checkin_items
            WHERE (? = 1 OR deletedAt IS NULL)
              AND (? = 1 OR archivedAt IS NULL)
            ORDER BY sortOrder ASC, name ASC
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(includeDeleted ? 1 : 0, to: 1, in: statement)
        try bind(includeArchived ? 1 : 0, to: 2, in: statement)

        var items = [CheckInItem]()
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(try checkInItem(statement))
        }
        return items
    }

    func fetchCheckInItem(id: String) throws -> CheckInItem? {
        let statement = try prepare(
            """
            SELECT id, name, symbolName, colorHex, recordMode, timeVisualization, dayStartHour,
                   activeWeekdays, sortOrder,
                   defaultShowInTimeline, tagId, createdAt, updatedAt, archivedAt, deletedAt, syncStatus
            FROM local_checkin_items
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(id, to: 1, in: statement)
        if sqlite3_step(statement) == SQLITE_ROW {
            return try checkInItem(statement)
        }
        return nil
    }

    func fetchCheckInEntries(includeDeleted: Bool = false) throws -> [CheckInEntry] {
        let statement = try prepare(
            """
            SELECT id, itemId, occurredAt, note, showInTimeline, createdAt, updatedAt, deletedAt, syncStatus
            FROM local_checkin_entries
            WHERE (? = 1 OR deletedAt IS NULL)
            ORDER BY occurredAt DESC, id DESC
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(includeDeleted ? 1 : 0, to: 1, in: statement)

        var entries = [CheckInEntry]()
        while sqlite3_step(statement) == SQLITE_ROW {
            entries.append(try checkInEntry(statement))
        }
        return entries
    }

    func fetchCheckInEntry(id: String) throws -> CheckInEntry? {
        let statement = try prepare(
            """
            SELECT id, itemId, occurredAt, note, showInTimeline, createdAt, updatedAt, deletedAt, syncStatus
            FROM local_checkin_entries
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(id, to: 1, in: statement)
        if sqlite3_step(statement) == SQLITE_ROW {
            return try checkInEntry(statement)
        }
        return nil
    }

    func nextCheckInSortOrder() throws -> Int {
        try count("SELECT COALESCE(MAX(sortOrder), -1) + 1 FROM local_checkin_items")
    }

    func localCheckInRecordCount() throws -> Int {
        try count(
            """
            SELECT
                (SELECT COUNT(*) FROM local_checkin_items) +
                (SELECT COUNT(*) FROM local_checkin_entries) +
                (SELECT COUNT(*) FROM local_checkin_media)
            """
        )
    }

    func checkInDiagnosticsStats() throws -> LocalCheckInStats {
        let activeItems = try count(
            """
            SELECT COUNT(*)
            FROM local_checkin_items
            WHERE deletedAt IS NULL
              AND archivedAt IS NULL
            """
        )
        let entries = try count(
            """
            SELECT COUNT(*)
            FROM local_checkin_entries
            WHERE deletedAt IS NULL
            """
        )
        let pendingChanges = try count(
            """
            SELECT
                (SELECT COUNT(*) FROM local_checkin_items WHERE syncStatus = 'pending') +
                (SELECT COUNT(*) FROM local_checkin_entries WHERE syncStatus = 'pending') +
                (SELECT COUNT(*) FROM local_checkin_media WHERE uploadStatus = 'pending' AND deletedAt IS NULL)
            """
        )
        let failedChanges = try count(
            """
            SELECT
                (SELECT COUNT(*) FROM local_checkin_items WHERE syncStatus = 'failed') +
                (SELECT COUNT(*) FROM local_checkin_entries WHERE syncStatus = 'failed') +
                (SELECT COUNT(*) FROM local_checkin_media WHERE uploadStatus = 'failed' AND deletedAt IS NULL)
            """
        )

        return LocalCheckInStats(
            activeItems: activeItems,
            entries: entries,
            pendingChanges: pendingChanges,
            failedChanges: failedChanges
        )
    }

    func upsertCheckInItem(_ item: CheckInItem, operation: OutboxOperation?) throws {
        try transaction {
            try upsertCheckInItemOnly(item)
            if let operation {
                try insert(operation)
            }
        }
    }

    func upsertCheckInEntry(_ entry: CheckInEntry, operation: OutboxOperation?) throws {
        try transaction {
            try upsertCheckInEntryOnly(entry)
            if let operation {
                try insert(operation)
            }
        }
    }

    func softDeleteCheckInItem(itemId: String, deletedAt: Date, operation: OutboxOperation?) throws {
        try transaction {
            let itemStatement = try prepare(
                """
                UPDATE local_checkin_items
                SET deletedAt = ?,
                    updatedAt = ?,
                    syncStatus = 'pending'
                WHERE id = ?
                """
            )
            defer {
                sqlite3_finalize(itemStatement)
            }

            try bind(deletedAt, to: 1, in: itemStatement)
            try bind(deletedAt, to: 2, in: itemStatement)
            try bind(itemId, to: 3, in: itemStatement)
            try stepDone(itemStatement)

            let entryStatement = try prepare(
                """
                UPDATE local_checkin_entries
                SET deletedAt = ?,
                    updatedAt = ?,
                    syncStatus = 'pending'
                WHERE itemId = ?
                  AND deletedAt IS NULL
                """
            )
            defer {
                sqlite3_finalize(entryStatement)
            }

            try bind(deletedAt, to: 1, in: entryStatement)
            try bind(deletedAt, to: 2, in: entryStatement)
            try bind(itemId, to: 3, in: entryStatement)
            try stepDone(entryStatement)

            let mediaStatement = try prepare(
                """
                UPDATE local_checkin_media
                SET deletedAt = ?,
                    updatedAt = ?,
                    uploadStatus = 'deleted',
                    uploadError = NULL
                WHERE entryId IN (
                    SELECT id
                    FROM local_checkin_entries
                    WHERE itemId = ?
                )
                  AND deletedAt IS NULL
                """
            )
            defer {
                sqlite3_finalize(mediaStatement)
            }

            try bind(deletedAt, to: 1, in: mediaStatement)
            try bind(deletedAt, to: 2, in: mediaStatement)
            try bind(itemId, to: 3, in: mediaStatement)
            try stepDone(mediaStatement)

            if let operation {
                try insert(operation)
            }
        }
    }

    func archiveCheckInItem(itemId: String, archivedAt: Date, operation: OutboxOperation?) throws {
        try transaction {
            let statement = try prepare(
                """
                UPDATE local_checkin_items
                SET archivedAt = ?,
                    updatedAt = ?,
                    syncStatus = 'pending'
                WHERE id = ?
                  AND deletedAt IS NULL
                """
            )
            defer {
                sqlite3_finalize(statement)
            }

            try bind(archivedAt, to: 1, in: statement)
            try bind(archivedAt, to: 2, in: statement)
            try bind(itemId, to: 3, in: statement)
            try stepDone(statement)

            if let operation {
                try insert(operation)
            }
        }
    }

    func softDeleteCheckInEntry(entryId: String, deletedAt: Date, operation: OutboxOperation?) throws {
        try transaction {
            let statement = try prepare(
                """
                UPDATE local_checkin_entries
                SET deletedAt = ?,
                    updatedAt = ?,
                    syncStatus = 'pending'
                WHERE id = ?
                """
            )
            defer {
                sqlite3_finalize(statement)
            }

            try bind(deletedAt, to: 1, in: statement)
            try bind(deletedAt, to: 2, in: statement)
            try bind(entryId, to: 3, in: statement)
            try stepDone(statement)

            try softDeleteCheckInMediaForEntry(entryId: entryId, deletedAt: deletedAt)

            if let operation {
                try insert(operation)
            }
        }
    }

    func hasCheckInEntry(
        itemId: String,
        on date: Date,
        excluding entryId: String? = nil,
        dayStartHour: Int = 0,
        calendar: Calendar = .current
    ) throws -> Bool {
        let dayRange = CheckInDayBoundary.dayRange(
            containing: date,
            dayStartHour: dayStartHour,
            calendar: calendar
        )
        let statement = try prepare(
            """
            SELECT COUNT(*)
            FROM local_checkin_entries
            WHERE itemId = ?
              AND occurredAt >= ?
              AND occurredAt < ?
              AND deletedAt IS NULL
              AND (? IS NULL OR id != ?)
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(itemId, to: 1, in: statement)
        try bind(dayRange.lowerBound, to: 2, in: statement)
        try bind(dayRange.upperBound, to: 3, in: statement)
        try bind(entryId, to: 4, in: statement)
        try bind(entryId, to: 5, in: statement)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return false
        }

        return sqlite3_column_int(statement, 0) > 0
    }

    func applyCheckInItemUpdated(_ item: CheckInItem) throws {
        var synced = item
        synced.syncStatus = "synced"
        try upsertCheckInItemOnly(synced)
    }

    func applyCheckInItemDeleted(id: String, deletedAt: Date) throws {
        try softDeleteCheckInItem(itemId: id, deletedAt: deletedAt, operation: nil)
        try markCheckInItemSyncStatus(itemId: id, status: "synced")
    }

    func applyCheckInEntryUpdated(_ entry: CheckInEntry) throws {
        var synced = entry
        synced.syncStatus = "synced"
        try upsertCheckInEntryOnly(synced)
    }

    func applyCheckInEntryDeleted(id: String, deletedAt: Date) throws {
        try softDeleteCheckInEntry(entryId: id, deletedAt: deletedAt, operation: nil)
        try markCheckInEntrySyncStatus(entryId: id, status: "synced")
    }

    func markCheckInItemSyncStatus(itemId: String, status: String) throws {
        let statement = try prepare(
            """
            UPDATE local_checkin_items
            SET syncStatus = ?,
                updatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(status, to: 1, in: statement)
        try bind(Date(), to: 2, in: statement)
        try bind(itemId, to: 3, in: statement)
        try stepDone(statement)
    }

    func markCheckInEntrySyncStatus(entryId: String, status: String) throws {
        let statement = try prepare(
            """
            UPDATE local_checkin_entries
            SET syncStatus = ?,
                updatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(status, to: 1, in: statement)
        try bind(Date(), to: 2, in: statement)
        try bind(entryId, to: 3, in: statement)
        try stepDone(statement)
    }

    func seedCheckInMockDataIfNeeded(now: Date = Date(), calendar: Calendar = .current) throws {
        guard try fetchCheckInItems(includeArchived: true, includeDeleted: true).isEmpty else {
            return
        }

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let weekdays = [1, 2, 3, 4, 5, 6, 7]
        let items = [
            CheckInItem(
                id: "mock-checkin-morning",
                name: "Wake up",
                symbolName: "sun.max",
                colorHex: "#F4C95D",
                recordMode: .oncePerDay,
                timeVisualization: .none,
                dayStartHour: 0,
                activeWeekdays: weekdays,
                sortOrder: 0,
                defaultShowInTimeline: true,
                tagId: nil,
                createdAt: yesterday,
                updatedAt: yesterday,
                archivedAt: nil,
                deletedAt: nil,
                syncStatus: "synced"
            ),
            CheckInItem(
                id: "mock-checkin-workout",
                name: "Workout",
                symbolName: "figure.run",
                colorHex: "#61B88D",
                recordMode: .oncePerDay,
                timeVisualization: .none,
                dayStartHour: 0,
                activeWeekdays: [2, 3, 4, 5, 6],
                sortOrder: 1,
                defaultShowInTimeline: true,
                tagId: nil,
                createdAt: yesterday,
                updatedAt: yesterday,
                archivedAt: nil,
                deletedAt: nil,
                syncStatus: "synced"
            ),
            CheckInItem(
                id: "mock-checkin-meal",
                name: "Meal",
                symbolName: "fork.knife",
                colorHex: "#D98E73",
                recordMode: .multiplePerDay,
                timeVisualization: .none,
                dayStartHour: 0,
                activeWeekdays: weekdays,
                sortOrder: 2,
                defaultShowInTimeline: false,
                tagId: nil,
                createdAt: yesterday,
                updatedAt: yesterday,
                archivedAt: nil,
                deletedAt: nil,
                syncStatus: "synced"
            ),
        ]

        let entries = [
            CheckInEntry(
                id: "mock-checkin-entry-wake-today",
                itemId: "mock-checkin-morning",
                occurredAt: calendar.date(byAdding: .hour, value: 7, to: today) ?? now,
                note: "",
                showInTimeline: true,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                syncStatus: "synced"
            ),
            CheckInEntry(
                id: "mock-checkin-entry-workout-yesterday",
                itemId: "mock-checkin-workout",
                occurredAt: calendar.date(byAdding: .hour, value: 18, to: yesterday) ?? yesterday,
                note: "Evening run",
                showInTimeline: true,
                createdAt: yesterday,
                updatedAt: yesterday,
                deletedAt: nil,
                syncStatus: "synced"
            ),
            CheckInEntry(
                id: "mock-checkin-entry-meal-hidden",
                itemId: "mock-checkin-meal",
                occurredAt: calendar.date(byAdding: .hour, value: 12, to: today) ?? now,
                note: "Lunch",
                showInTimeline: false,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                syncStatus: "synced"
            ),
        ]

        let mockMedia = try makeMockCheckInMedia(
            entryId: "mock-checkin-entry-meal-hidden",
            createdAt: now
        )

        try transaction {
            for item in items {
                try upsertCheckInItemOnly(item)
            }
            for entry in entries {
                try upsertCheckInEntryOnly(entry)
            }
            if let mockMedia {
                try upsertCheckInMediaOnly(mockMedia)
            }
        }
    }

    private func makeMockCheckInMedia(entryId: String, createdAt: Date) throws -> CheckInMedia? {
        let base64PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        guard let data = Data(base64Encoded: base64PNG) else {
            return nil
        }

        let mediaId = "mock-checkin-media-meal-photo"
        let fileURL = try AppDirectories.mediaDirectory().appending(path: "\(mediaId).png")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try data.write(to: fileURL, options: [.atomic])
        }

        return CheckInMedia(
            id: mediaId,
            entryId: entryId,
            kind: "image",
            localCompressedPath: fileURL.path,
            remoteCompressedPath: nil,
            uploadStatus: "uploaded",
            uploadError: nil,
            mimeType: "image/png",
            sortOrder: 0,
            checksum: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }

    func upsertCheckInItemOnly(_ item: CheckInItem) throws {
        let statement = try prepare(
            """
            INSERT INTO local_checkin_items
                (id, name, symbolName, colorHex, recordMode, timeVisualization, dayStartHour,
                 activeWeekdays, sortOrder,
                 defaultShowInTimeline, tagId, createdAt, updatedAt, archivedAt, deletedAt, syncStatus)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                symbolName = excluded.symbolName,
                colorHex = excluded.colorHex,
                recordMode = excluded.recordMode,
                timeVisualization = excluded.timeVisualization,
                dayStartHour = excluded.dayStartHour,
                activeWeekdays = excluded.activeWeekdays,
                sortOrder = excluded.sortOrder,
                defaultShowInTimeline = excluded.defaultShowInTimeline,
                tagId = excluded.tagId,
                updatedAt = excluded.updatedAt,
                archivedAt = excluded.archivedAt,
                deletedAt = excluded.deletedAt,
                syncStatus = excluded.syncStatus
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(item.id, to: 1, in: statement)
        try bind(item.name, to: 2, in: statement)
        try bind(item.symbolName, to: 3, in: statement)
        try bind(item.colorHex, to: 4, in: statement)
        try bind(item.recordMode.rawValue, to: 5, in: statement)
        try bind(item.timeVisualization.rawValue, to: 6, in: statement)
        try bind(CheckInDayBoundary.normalizedHour(item.dayStartHour), to: 7, in: statement)
        try bind(Self.weekdayStorageString(item.activeWeekdays), to: 8, in: statement)
        try bind(item.sortOrder, to: 9, in: statement)
        try bind(item.defaultShowInTimeline ? 1 : 0, to: 10, in: statement)
        try bind(item.tagId, to: 11, in: statement)
        try bind(item.createdAt, to: 12, in: statement)
        try bind(item.updatedAt, to: 13, in: statement)
        try bind(item.archivedAt, to: 14, in: statement)
        try bind(item.deletedAt, to: 15, in: statement)
        try bind(item.syncStatus, to: 16, in: statement)
        try stepDone(statement)
    }

    func upsertCheckInEntryOnly(_ entry: CheckInEntry) throws {
        let statement = try prepare(
            """
            INSERT INTO local_checkin_entries
                (id, itemId, occurredAt, note, showInTimeline, createdAt, updatedAt, deletedAt, syncStatus)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                itemId = excluded.itemId,
                occurredAt = excluded.occurredAt,
                note = excluded.note,
                showInTimeline = excluded.showInTimeline,
                updatedAt = excluded.updatedAt,
                deletedAt = excluded.deletedAt,
                syncStatus = excluded.syncStatus
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(entry.id, to: 1, in: statement)
        try bind(entry.itemId, to: 2, in: statement)
        try bind(entry.occurredAt, to: 3, in: statement)
        try bind(entry.note, to: 4, in: statement)
        try bind(entry.showInTimeline ? 1 : 0, to: 5, in: statement)
        try bind(entry.createdAt, to: 6, in: statement)
        try bind(entry.updatedAt, to: 7, in: statement)
        try bind(entry.deletedAt, to: 8, in: statement)
        try bind(entry.syncStatus, to: 9, in: statement)
        try stepDone(statement)
    }

    private func checkInItem(_ statement: OpaquePointer) throws -> CheckInItem {
        CheckInItem(
            id: try text(statement, 0),
            name: try text(statement, 1),
            symbolName: try text(statement, 2),
            colorHex: try text(statement, 3),
            recordMode: CheckInRecordMode(rawValue: try text(statement, 4)) ?? .oncePerDay,
            timeVisualization: CheckInTimeVisualization(rawValue: try text(statement, 5)) ?? .none,
            dayStartHour: CheckInDayBoundary.normalizedHour(optionalInt(statement, 6) ?? 0),
            activeWeekdays: Self.weekdays(from: try text(statement, 7)),
            sortOrder: optionalInt(statement, 8) ?? 0,
            defaultShowInTimeline: sqlite3_column_int(statement, 9) == 1,
            tagId: optionalText(statement, 10),
            createdAt: try date(statement, 11),
            updatedAt: try date(statement, 12),
            archivedAt: try optionalDate(statement, 13),
            deletedAt: try optionalDate(statement, 14),
            syncStatus: try text(statement, 15)
        )
    }

    private func checkInEntry(_ statement: OpaquePointer) throws -> CheckInEntry {
        CheckInEntry(
            id: try text(statement, 0),
            itemId: try text(statement, 1),
            occurredAt: try date(statement, 2),
            note: try text(statement, 3),
            showInTimeline: sqlite3_column_int(statement, 4) == 1,
            createdAt: try date(statement, 5),
            updatedAt: try date(statement, 6),
            deletedAt: try optionalDate(statement, 7),
            syncStatus: try text(statement, 8)
        )
    }

    private static func weekdayStorageString(_ weekdays: [Int]) -> String {
        weekdays
            .filter { (1...7).contains($0) }
            .uniqued()
            .sorted()
            .map(String.init)
            .joined(separator: ",")
    }

    private static func weekdays(from value: String) -> [Int] {
        let parsed = value
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { (1...7).contains($0) }
            .uniqued()
            .sorted()
        return parsed.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : parsed
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
