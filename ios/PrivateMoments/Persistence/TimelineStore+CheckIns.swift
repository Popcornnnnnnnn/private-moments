import Foundation
import UIKit

extension TimelineStore {
    func createCheckInItem(
        name: String,
        symbolName: String,
        colorHex: String,
        recordMode: CheckInRecordMode,
        timeVisualization: CheckInTimeVisualization,
        dayStartHour: Int = 0,
        activeWeekdays: [Int],
        defaultShowInTimeline: Bool,
        tagId: String?
    ) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Check-in name is required."
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let item = CheckInItem(
                id: UUID().uuidString,
                name: trimmedName,
                symbolName: normalizedCheckInSymbol(symbolName),
                colorHex: normalizedCheckInColor(colorHex),
                recordMode: recordMode,
                timeVisualization: normalizedTimeVisualization(timeVisualization, recordMode: recordMode),
                dayStartHour: normalizedDayStartHour(recordMode == .oncePerDay ? dayStartHour : 0),
                activeWeekdays: normalizedWeekdays(activeWeekdays),
                sortOrder: try database.nextCheckInSortOrder(),
                defaultShowInTimeline: defaultShowInTimeline,
                tagId: tagId,
                createdAt: now,
                updatedAt: now,
                archivedAt: nil,
                deletedAt: nil,
                syncStatus: "pending"
            )
            let operation = try makeCheckInOperation(
                type: "upsert_checkin_item",
                entityType: "checkin_item",
                entityId: item.id,
                payloadJson: makeUpsertCheckInItemPayload(item)
            )

            try database.upsertCheckInItem(item, operation: operation)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateCheckInItem(_ item: CheckInItem) async -> Bool {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            var updated = item
            updated.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !updated.name.isEmpty else {
                errorMessage = "Check-in name is required."
                return false
            }

            updated.symbolName = normalizedCheckInSymbol(updated.symbolName)
            updated.colorHex = normalizedCheckInColor(updated.colorHex)
            updated.timeVisualization = normalizedTimeVisualization(
                updated.timeVisualization,
                recordMode: updated.recordMode
            )
            updated.dayStartHour = normalizedDayStartHour(updated.recordMode == .oncePerDay ? updated.dayStartHour : 0)
            updated.activeWeekdays = normalizedWeekdays(updated.activeWeekdays)
            updated.updatedAt = Date()
            updated.syncStatus = "pending"

            let operation = try makeCheckInOperation(
                type: "upsert_checkin_item",
                entityType: "checkin_item",
                entityId: updated.id,
                payloadJson: makeUpsertCheckInItemPayload(updated)
            )
            try database.upsertCheckInItem(updated, operation: operation)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func archiveCheckInItem(_ item: CheckInItem) async {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            var updated = item
            let now = Date()
            updated.archivedAt = now
            updated.updatedAt = now
            updated.syncStatus = "pending"
            let operation = try makeCheckInOperation(
                type: "upsert_checkin_item",
                entityType: "checkin_item",
                entityId: item.id,
                payloadJson: makeUpsertCheckInItemPayload(updated)
            )
            try database.archiveCheckInItem(itemId: item.id, archivedAt: now, operation: operation)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCheckInItem(_ item: CheckInItem) async {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let operation = try makeCheckInOperation(
                type: "delete_checkin_item",
                entityType: "checkin_item",
                entityId: item.id,
                payloadJson: makeDeleteCheckInPayload(deletedAt: now)
            )
            try database.softDeleteCheckInItem(itemId: item.id, deletedAt: now, operation: operation)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recordCheckIn(
        item: CheckInItem,
        note: String = "",
        occurredAt: Date = Date(),
        showInTimeline: Bool? = nil,
        imageData: Data? = nil
    ) async -> CheckInEntry? {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            if item.recordMode == .oncePerDay,
               try database.hasCheckInEntry(itemId: item.id, on: occurredAt, dayStartHour: item.dayStartHour) {
                errorMessage = "Already checked in for this day."
                return nil
            }

            let now = Date()
            let entry = CheckInEntry(
                id: UUID().uuidString,
                itemId: item.id,
                occurredAt: occurredAt,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                showInTimeline: showInTimeline ?? item.defaultShowInTimeline,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                syncStatus: "pending"
            )
            let media = try imageData.flatMap { data in
                try Self.persistCheckInImage(
                    entryId: entry.id,
                    mediaId: UUID().uuidString,
                    data: data,
                    sortOrder: 0,
                    createdAt: now
                )
            }
            let operation = try makeCheckInOperation(
                type: "upsert_checkin_entry",
                entityType: "checkin_entry",
                entityId: entry.id,
                payloadJson: makeUpsertCheckInEntryPayload(entry)
            )
            if let media {
                try database.upsertCheckInEntry(entry, media: media, operation: operation)
            } else {
                try database.upsertCheckInEntry(entry, operation: operation)
            }
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return entry
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateCheckInEntry(_ entry: CheckInEntry) async -> Bool {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            guard let item = checkInItem(id: entry.itemId) else {
                errorMessage = "Check-in item not found."
                return false
            }

            if item.recordMode == .oncePerDay,
               try database.hasCheckInEntry(
                itemId: item.id,
                on: entry.occurredAt,
                excluding: entry.id,
                dayStartHour: item.dayStartHour
               ) {
                errorMessage = "Already checked in for that day."
                return false
            }

            var updated = entry
            updated.note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.updatedAt = Date()
            updated.syncStatus = "pending"

            let operation = try makeCheckInOperation(
                type: "upsert_checkin_entry",
                entityType: "checkin_entry",
                entityId: updated.id,
                payloadJson: makeUpsertCheckInEntryPayload(updated)
            )
            try database.upsertCheckInEntry(updated, operation: operation)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func replaceCheckInEntryImage(entry: CheckInEntry, imageData: Data?) async -> Bool {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let existingMedia = try database.fetchCheckInMedia(entryId: entry.id)
            let deleteOperations = try existingMedia
                .filter { $0.uploadStatus == "uploaded" && $0.remoteCompressedPath != nil }
                .map { media in
                    try makeCheckInOperation(
                        type: "delete_checkin_media",
                        entityType: "checkin_media",
                        entityId: media.id,
                        payloadJson: makeDeleteCheckInPayload(deletedAt: now)
                    )
                }
            let media = try imageData.flatMap { data in
                try Self.persistCheckInImage(
                    entryId: entry.id,
                    mediaId: UUID().uuidString,
                    data: data,
                    sortOrder: 0,
                    createdAt: now
                )
            }

            try database.replaceCheckInMedia(
                entryId: entry.id,
                media: media,
                deleteOperations: deleteOperations
            )
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteCheckInEntry(_ entry: CheckInEntry) async {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let operation = try makeCheckInOperation(
                type: "delete_checkin_entry",
                entityType: "checkin_entry",
                entityId: entry.id,
                payloadJson: makeDeleteCheckInPayload(deletedAt: now)
            )
            try database.softDeleteCheckInEntry(entryId: entry.id, deletedAt: now, operation: operation)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func entries(for item: CheckInItem, on date: Date, calendar: Calendar = .current) -> [CheckInEntry] {
        checkInEntries
            .filter { entry in
                entry.itemId == item.id
                    && entry.deletedAt == nil
                    && CheckInDayBoundary.isSameItemDay(
                        entry.occurredAt,
                        date,
                        dayStartHour: item.dayStartHour,
                        calendar: calendar
                    )
            }
            .sorted { lhs, rhs in
                if lhs.occurredAt == rhs.occurredAt {
                    return lhs.id > rhs.id
                }

                return lhs.occurredAt > rhs.occurredAt
            }
    }

    private func makeCheckInOperation(
        type: String,
        entityType: String,
        entityId: String,
        payloadJson: String
    ) throws -> OutboxOperation {
        let now = Date()
        return OutboxOperation(
            id: UUID().uuidString,
            opId: UUID().uuidString,
            type: type,
            entityType: entityType,
            entityId: entityId,
            payloadJson: payloadJson,
            status: "pending",
            attemptCount: 0,
            lastError: nil,
            createdAt: now,
            updatedAt: now,
            sentAt: nil
        )
    }

    private func normalizedCheckInSymbol(_ value: String) -> String {
        CheckInSymbolValidator.normalized(value)
    }

    private func normalizedCheckInColor(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil {
            return trimmed.uppercased()
        }

        return "#61B88D"
    }

    private func normalizedTimeVisualization(
        _ value: CheckInTimeVisualization,
        recordMode: CheckInRecordMode
    ) -> CheckInTimeVisualization {
        if recordMode == .multiplePerDay, value == .timeLine {
            return .timeHeatmap
        }

        return value
    }

    private func normalizedDayStartHour(_ value: Int) -> Int {
        CheckInDayBoundary.normalizedHour(value)
    }

    private func normalizedWeekdays(_ value: [Int]) -> [Int] {
        let weekdays = value.filter { (1...7).contains($0) }
        return weekdays.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : Array(Set(weekdays)).sorted()
    }

    nonisolated static func persistCheckInImage(
        entryId: String,
        mediaId: String,
        data: Data,
        sortOrder: Int,
        createdAt: Date
    ) throws -> CheckInMedia? {
        guard let image = UIImage(data: data), let jpegData = ImageCompression.uploadJPEGData(from: image) else {
            return nil
        }

        let directory = try AppDirectories.mediaDirectory()
        let fileURL = directory.appending(path: "\(mediaId).jpg")
        try jpegData.write(to: fileURL, options: [.atomic])

        return CheckInMedia(
            id: mediaId,
            entryId: entryId,
            kind: "image",
            localCompressedPath: fileURL.path,
            remoteCompressedPath: nil,
            uploadStatus: "pending",
            uploadError: nil,
            mimeType: "image/jpeg",
            sortOrder: sortOrder,
            checksum: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }
}
