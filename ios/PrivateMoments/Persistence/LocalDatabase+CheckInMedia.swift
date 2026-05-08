import Foundation
import SQLite3

extension LocalDatabase {
    func fetchCheckInMedia(includeDeleted: Bool = false) throws -> [CheckInMedia] {
        let statement = try prepare(
            """
            SELECT id, entryId, kind, localCompressedPath, remoteCompressedPath, uploadStatus,
                   uploadError, mimeType, sortOrder, checksum, createdAt, updatedAt, deletedAt
            FROM local_checkin_media
            WHERE (? = 1 OR deletedAt IS NULL)
            ORDER BY sortOrder ASC, createdAt ASC
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(includeDeleted ? 1 : 0, to: 1, in: statement)

        var media = [CheckInMedia]()
        while sqlite3_step(statement) == SQLITE_ROW {
            media.append(try checkInMedia(statement))
        }
        return media
    }

    func fetchCheckInMedia(entryId: String, includeDeleted: Bool = false) throws -> [CheckInMedia] {
        let statement = try prepare(
            """
            SELECT id, entryId, kind, localCompressedPath, remoteCompressedPath, uploadStatus,
                   uploadError, mimeType, sortOrder, checksum, createdAt, updatedAt, deletedAt
            FROM local_checkin_media
            WHERE entryId = ?
              AND (? = 1 OR deletedAt IS NULL)
            ORDER BY sortOrder ASC, createdAt ASC
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(entryId, to: 1, in: statement)
        try bind(includeDeleted ? 1 : 0, to: 2, in: statement)

        var media = [CheckInMedia]()
        while sqlite3_step(statement) == SQLITE_ROW {
            media.append(try checkInMedia(statement))
        }
        return media
    }

    func fetchCheckInMedia(id: String) throws -> CheckInMedia? {
        let statement = try prepare(
            """
            SELECT id, entryId, kind, localCompressedPath, remoteCompressedPath, uploadStatus,
                   uploadError, mimeType, sortOrder, checksum, createdAt, updatedAt, deletedAt
            FROM local_checkin_media
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(id, to: 1, in: statement)
        if sqlite3_step(statement) == SQLITE_ROW {
            return try checkInMedia(statement)
        }
        return nil
    }

    func upsertCheckInEntry(_ entry: CheckInEntry, media: CheckInMedia?, operation: OutboxOperation?) throws {
        try transaction {
            try upsertCheckInEntryOnly(entry)
            if let media {
                try upsertCheckInMediaOnly(media)
            }
            if let operation {
                try insert(operation)
            }
        }
    }

    func insertCheckInMedia(_ media: CheckInMedia) throws {
        try upsertCheckInMediaOnly(media)
    }

    func replaceCheckInMedia(entryId: String, media: CheckInMedia?, deleteOperations: [OutboxOperation]) throws {
        let deletedAt = Date()
        try transaction {
            try softDeleteCheckInMediaForEntry(entryId: entryId, deletedAt: deletedAt)
            for operation in deleteOperations {
                try insert(operation)
            }
            if let media {
                try upsertCheckInMediaOnly(media)
            }
        }
    }

    func softDeleteCheckInMedia(mediaId: String, deletedAt: Date, operation: OutboxOperation?) throws {
        try transaction {
            try softDeleteCheckInMediaOnly(mediaId: mediaId, deletedAt: deletedAt)
            if let operation {
                try insert(operation)
            }
        }
    }

    func softDeleteCheckInMediaForEntry(entryId: String, deletedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE local_checkin_media
            SET deletedAt = ?,
                uploadStatus = 'deleted',
                uploadError = NULL,
                updatedAt = ?
            WHERE entryId = ?
              AND deletedAt IS NULL
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(deletedAt, to: 1, in: statement)
        try bind(deletedAt, to: 2, in: statement)
        try bind(entryId, to: 3, in: statement)
        try stepDone(statement)
    }

    func applyCheckInMediaUploaded(
        mediaId: String,
        entryId: String,
        kind: String,
        variant: String,
        remotePath: String,
        sortOrder: Int,
        checksum: String?,
        mimeType: String?
    ) throws {
        guard try fetchCheckInEntry(id: entryId) != nil else {
            return
        }

        let now = Date()
        if try fetchCheckInMedia(id: mediaId) == nil {
            try upsertCheckInMediaOnly(
                CheckInMedia(
                    id: mediaId,
                    entryId: entryId,
                    kind: kind,
                    localCompressedPath: "",
                    remoteCompressedPath: variant == "compressed" ? remotePath : nil,
                    uploadStatus: "uploaded",
                    uploadError: nil,
                    mimeType: mimeType,
                    sortOrder: sortOrder,
                    checksum: checksum,
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil
                )
            )
            return
        }

        let statement = try prepare(
            """
            UPDATE local_checkin_media
            SET kind = ?,
                remoteCompressedPath = COALESCE(?, remoteCompressedPath),
                uploadStatus = 'uploaded',
                uploadError = NULL,
                mimeType = COALESCE(?, mimeType),
                sortOrder = ?,
                checksum = ?,
                updatedAt = ?,
                deletedAt = NULL
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(kind, to: 1, in: statement)
        try bind(variant == "compressed" ? remotePath : nil, to: 2, in: statement)
        try bind(mimeType, to: 3, in: statement)
        try bind(sortOrder, to: 4, in: statement)
        try bind(checksum, to: 5, in: statement)
        try bind(now, to: 6, in: statement)
        try bind(mediaId, to: 7, in: statement)
        try stepDone(statement)
    }

    func applyCheckInMediaDeleted(id: String, deletedAt: Date) throws {
        try softDeleteCheckInMediaOnly(mediaId: id, deletedAt: deletedAt)
    }

    func pendingCheckInMediaUploadCount() throws -> Int {
        try count(
            """
            SELECT COUNT(*)
            FROM local_checkin_media m
            JOIN local_checkin_entries e ON e.id = m.entryId
            JOIN local_checkin_items i ON i.id = e.itemId
            WHERE m.uploadStatus IN ('pending', 'failed')
              AND m.deletedAt IS NULL
              AND e.deletedAt IS NULL
              AND i.deletedAt IS NULL
            """
        )
    }

    func fetchPendingCheckInMediaReadyForUpload(limit: Int = 50) throws -> [CheckInMedia] {
        let statement = try prepare(
            """
            SELECT m.id, m.entryId, m.kind, m.localCompressedPath, m.remoteCompressedPath,
                   m.uploadStatus, m.uploadError, m.mimeType, m.sortOrder, m.checksum,
                   m.createdAt, m.updatedAt, m.deletedAt
            FROM local_checkin_media m
            JOIN local_checkin_entries e ON e.id = m.entryId
            JOIN local_checkin_items i ON i.id = e.itemId
            WHERE m.uploadStatus IN ('pending', 'failed')
              AND m.deletedAt IS NULL
              AND e.deletedAt IS NULL
              AND i.deletedAt IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM outbox_operations o
                  WHERE o.entityId = m.entryId
                    AND o.status IN ('pending', 'failed')
              )
            ORDER BY
              CASE WHEN m.uploadStatus = 'pending' THEN 0 ELSE 1 END,
              m.createdAt ASC,
              m.sortOrder ASC
            LIMIT ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(limit, to: 1, in: statement)

        var media = [CheckInMedia]()
        while sqlite3_step(statement) == SQLITE_ROW {
            media.append(try checkInMedia(statement))
        }
        return media
    }

    func fetchCheckInMediaNeedingDownload(limit: Int = 50) throws -> [CheckInMedia] {
        let statement = try prepare(
            """
            SELECT m.id, m.entryId, m.kind, m.localCompressedPath, m.remoteCompressedPath,
                   m.uploadStatus, m.uploadError, m.mimeType, m.sortOrder, m.checksum,
                   m.createdAt, m.updatedAt, m.deletedAt
            FROM local_checkin_media m
            JOIN local_checkin_entries e ON e.id = m.entryId
            JOIN local_checkin_items i ON i.id = e.itemId
            WHERE m.uploadStatus = 'uploaded'
              AND m.kind = 'image'
              AND m.remoteCompressedPath IS NOT NULL
              AND m.localCompressedPath = ''
              AND m.deletedAt IS NULL
              AND e.deletedAt IS NULL
              AND i.deletedAt IS NULL
            ORDER BY m.updatedAt DESC, m.sortOrder ASC
            LIMIT ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(limit, to: 1, in: statement)

        var media = [CheckInMedia]()
        while sqlite3_step(statement) == SQLITE_ROW {
            media.append(try checkInMedia(statement))
        }
        return media
    }

    func markCheckInMediaUploaded(mediaId: String, remotePath: String, checksum: String?) throws {
        let statement = try prepare(
            """
            UPDATE local_checkin_media
            SET remoteCompressedPath = ?,
                uploadStatus = 'uploaded',
                uploadError = NULL,
                checksum = ?,
                updatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(remotePath, to: 1, in: statement)
        try bind(checksum, to: 2, in: statement)
        try bind(Date(), to: 3, in: statement)
        try bind(mediaId, to: 4, in: statement)
        try stepDone(statement)
    }

    func markCheckInMediaUploadFailed(mediaId: String, error: String) throws {
        let statement = try prepare(
            """
            UPDATE local_checkin_media
            SET uploadStatus = 'failed',
                uploadError = ?,
                updatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(error, to: 1, in: statement)
        try bind(Date(), to: 2, in: statement)
        try bind(mediaId, to: 3, in: statement)
        try stepDone(statement)
    }

    func markCheckInMediaDownloaded(mediaId: String, localPath: String) throws {
        let statement = try prepare(
            """
            UPDATE local_checkin_media
            SET localCompressedPath = ?,
                updatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(AppDirectories.storedPath(forLocalPath: localPath), to: 1, in: statement)
        try bind(Date(), to: 2, in: statement)
        try bind(mediaId, to: 3, in: statement)
        try stepDone(statement)
    }

    func retryFailedCheckInMediaUploads() throws -> Int {
        let statement = try prepare(
            """
            UPDATE local_checkin_media
            SET uploadStatus = 'pending',
                uploadError = NULL,
                updatedAt = ?
            WHERE uploadStatus = 'failed'
              AND deletedAt IS NULL
              AND EXISTS (
                SELECT 1
                FROM local_checkin_entries e
                JOIN local_checkin_items i ON i.id = e.itemId
                WHERE e.id = local_checkin_media.entryId
                  AND e.deletedAt IS NULL
                  AND i.deletedAt IS NULL
              )
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(Date(), to: 1, in: statement)
        try stepDone(statement)
        return Int(sqlite3_changes(handle))
    }

    func upsertCheckInMediaOnly(_ media: CheckInMedia) throws {
        let statement = try prepare(
            """
            INSERT INTO local_checkin_media
                (id, entryId, kind, localCompressedPath, remoteCompressedPath, uploadStatus,
                 uploadError, mimeType, sortOrder, checksum, createdAt, updatedAt, deletedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                entryId = excluded.entryId,
                kind = excluded.kind,
                localCompressedPath = excluded.localCompressedPath,
                remoteCompressedPath = excluded.remoteCompressedPath,
                uploadStatus = excluded.uploadStatus,
                uploadError = excluded.uploadError,
                mimeType = excluded.mimeType,
                sortOrder = excluded.sortOrder,
                checksum = excluded.checksum,
                updatedAt = excluded.updatedAt,
                deletedAt = excluded.deletedAt
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(media.id, to: 1, in: statement)
        try bind(media.entryId, to: 2, in: statement)
        try bind(media.kind, to: 3, in: statement)
        try bind(AppDirectories.storedPath(forLocalPath: media.localCompressedPath), to: 4, in: statement)
        try bind(media.remoteCompressedPath, to: 5, in: statement)
        try bind(media.uploadStatus, to: 6, in: statement)
        try bind(media.uploadError, to: 7, in: statement)
        try bind(media.mimeType, to: 8, in: statement)
        try bind(media.sortOrder, to: 9, in: statement)
        try bind(media.checksum, to: 10, in: statement)
        try bind(media.createdAt, to: 11, in: statement)
        try bind(media.updatedAt, to: 12, in: statement)
        try bind(media.deletedAt, to: 13, in: statement)
        try stepDone(statement)
    }

    private func softDeleteCheckInMediaOnly(mediaId: String, deletedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE local_checkin_media
            SET deletedAt = ?,
                uploadStatus = 'deleted',
                uploadError = NULL,
                updatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(deletedAt, to: 1, in: statement)
        try bind(deletedAt, to: 2, in: statement)
        try bind(mediaId, to: 3, in: statement)
        try stepDone(statement)
    }

    func checkInMedia(_ statement: OpaquePointer) throws -> CheckInMedia {
        CheckInMedia(
            id: try text(statement, 0),
            entryId: try text(statement, 1),
            kind: try text(statement, 2),
            localCompressedPath: try localFilePath(statement, 3),
            remoteCompressedPath: optionalText(statement, 4),
            uploadStatus: try text(statement, 5),
            uploadError: optionalText(statement, 6),
            mimeType: optionalText(statement, 7),
            sortOrder: Int(sqlite3_column_int64(statement, 8)),
            checksum: optionalText(statement, 9),
            createdAt: try date(statement, 10),
            updatedAt: try date(statement, 11),
            deletedAt: try optionalDate(statement, 12)
        )
    }
}
