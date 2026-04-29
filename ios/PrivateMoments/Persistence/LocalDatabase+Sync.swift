import Foundation
import SQLite3

extension LocalDatabase {
    func pendingOperationCount() throws -> Int {
        try count("SELECT COUNT(*) FROM outbox_operations WHERE status IN ('pending', 'failed')")
    }

    func pendingUploadCount() throws -> Int {
        try count(
            """
            SELECT COUNT(*)
            FROM local_media m
            JOIN local_posts p ON p.id = m.postId
            WHERE m.uploadStatus IN ('pending', 'failed')
              AND m.deletedAt IS NULL
              AND p.deletedAt IS NULL
            """
        )
    }

    func missingMediaDownloadCount() throws -> Int {
        try count(
            """
            SELECT COUNT(*)
            FROM local_media m
            JOIN local_posts p ON p.id = m.postId
            WHERE m.uploadStatus = 'uploaded'
              AND m.remoteCompressedPath IS NOT NULL
              AND m.localCompressedPath = ''
              AND m.deletedAt IS NULL
              AND p.deletedAt IS NULL
            """
        )
    }

    func localPostCount() throws -> Int {
        try count("SELECT COUNT(*) FROM local_posts")
    }

    func fetchPendingOperations(limit: Int = 100) throws -> [OutboxOperation] {
        let statement = try prepare(
            """
            SELECT id, opId, type, entityType, entityId, payloadJson, status, attemptCount,
                   lastError, createdAt, updatedAt, sentAt
            FROM outbox_operations
            WHERE status IN ('pending', 'failed')
            ORDER BY createdAt ASC
            LIMIT ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(limit, to: 1, in: statement)
        var operations: [OutboxOperation] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            operations.append(try outboxOperation(statement))
        }

        return operations
    }

    func fetchPendingMediaReadyForUpload() throws -> [TimelineMedia] {
        let statement = try prepare(
            """
            SELECT m.id, m.postId, m.localCompressedPath, m.localOriginalStagingPath, m.remoteCompressedPath,
                   m.remoteOriginalPath, m.originalPreserved, m.uploadStatus, m.sortOrder, m.checksum,
                   m.createdAt, m.updatedAt
            FROM local_media m
            JOIN local_posts p ON p.id = m.postId
            WHERE m.uploadStatus IN ('pending', 'failed')
              AND m.deletedAt IS NULL
              AND p.deletedAt IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM outbox_operations o
                  WHERE o.entityId = m.postId
                    AND o.status IN ('pending', 'failed')
              )
            ORDER BY m.createdAt ASC, m.sortOrder ASC
            LIMIT 50
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        var media: [TimelineMedia] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            media.append(try timelineMedia(statement))
        }

        return media
    }

    func fetchMediaNeedingDownload(limit: Int = 50) throws -> [TimelineMedia] {
        let statement = try prepare(
            """
            SELECT m.id, m.postId, m.localCompressedPath, m.localOriginalStagingPath, m.remoteCompressedPath,
                   m.remoteOriginalPath, m.originalPreserved, m.uploadStatus, m.sortOrder, m.checksum,
                   m.createdAt, m.updatedAt
            FROM local_media m
            JOIN local_posts p ON p.id = m.postId
            WHERE m.uploadStatus = 'uploaded'
              AND m.remoteCompressedPath IS NOT NULL
              AND m.localCompressedPath = ''
              AND m.deletedAt IS NULL
              AND p.deletedAt IS NULL
            ORDER BY m.updatedAt DESC, m.sortOrder ASC
            LIMIT ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(limit, to: 1, in: statement)
        var media: [TimelineMedia] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            media.append(try timelineMedia(statement))
        }

        return media
    }

    func markOperationsAccepted(_ opIds: [String]) throws {
        let now = Date()

        try transaction {
            for opId in opIds {
                guard let operation = try fetchOperation(opId: opId) else {
                    continue
                }

                try updateOperationStatus(opId: opId, status: "synced", lastError: nil, sentAt: now)

                if operation.entityType == "post" {
                    try refreshPostSyncStatus(postId: operation.entityId)
                } else if operation.entityType == "comment",
                          let postId = try operationCommentPostId(operation) {
                    try refreshPostSyncStatus(postId: postId)
                }
            }
        }
    }

    func markOperationsRejected(_ rejections: [(opId: String, reason: String)]) throws {
        let now = Date()

        try transaction {
            for rejection in rejections {
                guard let operation = try fetchOperation(opId: rejection.opId) else {
                    continue
                }

                try updateOperationStatus(
                    opId: rejection.opId,
                    status: "failed",
                    lastError: rejection.reason,
                    sentAt: nil,
                    updatedAt: now
                )

                if operation.entityType == "post" {
                    try updatePostSyncStatus(postId: operation.entityId, status: "failed")
                } else if operation.entityType == "comment",
                          let postId = try operationCommentPostId(operation) {
                    try updatePostSyncStatus(postId: postId, status: "failed")
                }
            }
        }
    }

    func markMediaUploaded(mediaId: String, remotePath: String, checksum: String?) throws {
        let statement = try prepare(
            """
            UPDATE local_media
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

        if let media = try fetchMedia(id: mediaId) {
            try refreshPostSyncStatus(postId: media.postId)
        }
    }

    func markMediaUploadFailed(mediaId: String, error: String) throws {
        let statement = try prepare(
            """
            UPDATE local_media
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

        if let media = try fetchMedia(id: mediaId) {
            try refreshPostSyncStatus(postId: media.postId)
        }
    }

    func markMediaDownloaded(mediaId: String, localPath: String) throws {
        let statement = try prepare(
            """
            UPDATE local_media
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

    func operationCommentPostId(_ operation: OutboxOperation) throws -> String? {
        guard let data = operation.payloadJson.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return object["postId"] as? String
    }

    func applyPostCreated(
        id: String,
        text: String,
        isFavorite: Bool,
        occurredAt: Date,
        serverVersion: Int
    ) throws {
        let now = Date()
        let existing = try fetchPost(id: id)

        if existing == nil {
            let statement = try prepare(
                """
                INSERT INTO local_posts
                    (id, text, isFavorite, occurredAt, localCreatedAt, localUpdatedAt, localEditedAt, serverVersion, syncStatus, deletedAt)
                VALUES (?, ?, ?, ?, ?, ?, NULL, ?, 'synced', NULL)
                """
            )
            defer {
                sqlite3_finalize(statement)
            }

            try bind(id, to: 1, in: statement)
            try bind(text, to: 2, in: statement)
            try bind(isFavorite ? 1 : 0, to: 3, in: statement)
            try bind(occurredAt, to: 4, in: statement)
            try bind(now, to: 5, in: statement)
            try bind(now, to: 6, in: statement)
            try bind(serverVersion, to: 7, in: statement)
            try stepDone(statement)
            return
        }

        let statement = try prepare(
            """
            UPDATE local_posts
            SET text = ?,
                isFavorite = ?,
                occurredAt = ?,
                serverVersion = ?,
                syncStatus = CASE
                    WHEN syncStatus = 'failed' THEN 'failed'
                    ELSE 'synced'
                END,
                deletedAt = NULL,
                localUpdatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(text, to: 1, in: statement)
        try bind(isFavorite ? 1 : 0, to: 2, in: statement)
        try bind(occurredAt, to: 3, in: statement)
        try bind(serverVersion, to: 4, in: statement)
        try bind(now, to: 5, in: statement)
        try bind(id, to: 6, in: statement)
        try stepDone(statement)
        try refreshPostSyncStatus(postId: id)
    }

    func applyPostDeleted(id: String, deletedAt: Date, serverVersion: Int) throws {
        let statement = try prepare(
            """
            UPDATE local_posts
            SET deletedAt = ?,
                serverVersion = ?,
                syncStatus = 'synced',
                localUpdatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(deletedAt, to: 1, in: statement)
        try bind(serverVersion, to: 2, in: statement)
        try bind(Date(), to: 3, in: statement)
        try bind(id, to: 4, in: statement)
        try stepDone(statement)
    }

    func applyPostUpdated(
        id: String,
        text: String,
        isFavorite: Bool?,
        occurredAt: Date,
        editedAt: Date,
        mediaOrder: [(id: String, sortOrder: Int)],
        serverVersion: Int
    ) throws {
        guard try fetchPost(id: id) != nil else {
            return
        }

        try transaction {
            let statement = try prepare(
                isFavorite == nil
                    ? """
                    UPDATE local_posts
                    SET text = ?,
                        occurredAt = ?,
                        localEditedAt = ?,
                        serverVersion = ?,
                        localUpdatedAt = ?
                    WHERE id = ?
                    """
                    : """
                    UPDATE local_posts
                    SET text = ?,
                        isFavorite = ?,
                        occurredAt = ?,
                        localEditedAt = ?,
                        serverVersion = ?,
                        localUpdatedAt = ?
                    WHERE id = ?
                    """
            )
            defer {
                sqlite3_finalize(statement)
            }

            let now = Date()
            try bind(text, to: 1, in: statement)
            if let isFavorite {
                try bind(isFavorite ? 1 : 0, to: 2, in: statement)
                try bind(occurredAt, to: 3, in: statement)
                try bind(editedAt, to: 4, in: statement)
                try bind(serverVersion, to: 5, in: statement)
                try bind(now, to: 6, in: statement)
                try bind(id, to: 7, in: statement)
            } else {
                try bind(occurredAt, to: 2, in: statement)
                try bind(editedAt, to: 3, in: statement)
                try bind(serverVersion, to: 4, in: statement)
                try bind(now, to: 5, in: statement)
                try bind(id, to: 6, in: statement)
            }
            try stepDone(statement)

            for media in mediaOrder {
                try updateMediaSortOrder(mediaId: media.id, sortOrder: media.sortOrder, updatedAt: now)
            }

            try refreshPostSyncStatus(postId: id)
        }
    }

    func applyPostFavoriteUpdated(
        id: String,
        isFavorite: Bool,
        updatedAt: Date,
        serverVersion: Int
    ) throws {
        guard try fetchPost(id: id) != nil else {
            return
        }

        let statement = try prepare(
            """
            UPDATE local_posts
            SET isFavorite = ?,
                localUpdatedAt = ?,
                serverVersion = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(isFavorite ? 1 : 0, to: 1, in: statement)
        try bind(updatedAt, to: 2, in: statement)
        try bind(serverVersion, to: 3, in: statement)
        try bind(id, to: 4, in: statement)
        try stepDone(statement)
        try refreshPostSyncStatus(postId: id)
    }

    func applyMediaDeleted(mediaId: String, postId: String, deletedAt: Date) throws {
        guard try fetchPost(id: postId) != nil else {
            return
        }

        try softDeleteMedia(mediaId: mediaId, deletedAt: deletedAt)
        try refreshPostSyncStatus(postId: postId)
    }

    func applyMediaUploaded(
        mediaId: String,
        postId: String,
        remotePath: String,
        originalPreserved: Bool,
        sortOrder: Int,
        checksum: String?
    ) throws {
        guard try fetchPost(id: postId) != nil else {
            return
        }

        if try fetchMedia(id: mediaId) == nil {
            let now = Date()
            let statement = try prepare(
                """
                INSERT INTO local_media
                    (id, postId, localCompressedPath, localOriginalStagingPath, remoteCompressedPath,
                     remoteOriginalPath, originalPreserved, uploadStatus, sortOrder, checksum, createdAt, updatedAt)
                VALUES (?, ?, '', NULL, ?, NULL, ?, 'uploaded', ?, ?, ?, ?)
                """
            )
            defer {
                sqlite3_finalize(statement)
            }

            try bind(mediaId, to: 1, in: statement)
            try bind(postId, to: 2, in: statement)
            try bind(remotePath, to: 3, in: statement)
            try bind(originalPreserved ? 1 : 0, to: 4, in: statement)
            try bind(sortOrder, to: 5, in: statement)
            try bind(checksum, to: 6, in: statement)
            try bind(now, to: 7, in: statement)
            try bind(now, to: 8, in: statement)
            try stepDone(statement)
            return
        }

        let statement = try prepare(
            """
            UPDATE local_media
            SET remoteCompressedPath = ?,
                originalPreserved = ?,
                uploadStatus = 'uploaded',
                uploadError = NULL,
                sortOrder = ?,
                checksum = ?,
                updatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(remotePath, to: 1, in: statement)
        try bind(originalPreserved ? 1 : 0, to: 2, in: statement)
        try bind(sortOrder, to: 3, in: statement)
        try bind(checksum, to: 4, in: statement)
        try bind(Date(), to: 5, in: statement)
        try bind(mediaId, to: 6, in: statement)
        try stepDone(statement)
        try refreshPostSyncStatus(postId: postId)
    }

    func applyCommentCreated(
        id: String,
        postId: String,
        text: String,
        createdAt: Date,
        updatedAt: Date,
        serverVersion: Int
    ) throws {
        guard try fetchPost(id: postId) != nil else {
            return
        }

        if try fetchComment(id: id) == nil {
            let comment = TimelineComment(
                id: id,
                postId: postId,
                text: text,
                createdAt: createdAt,
                updatedAt: updatedAt,
                serverVersion: serverVersion,
                syncStatus: "synced",
                deletedAt: nil
            )
            try insert(comment)
            try refreshPostSyncStatus(postId: postId)
            return
        }

        let statement = try prepare(
            """
            UPDATE local_comments
            SET postId = ?,
                text = ?,
                createdAt = ?,
                updatedAt = ?,
                serverVersion = ?,
                syncStatus = CASE
                    WHEN syncStatus = 'failed' THEN 'failed'
                    ELSE 'synced'
                END,
                deletedAt = NULL
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(postId, to: 1, in: statement)
        try bind(text, to: 2, in: statement)
        try bind(createdAt, to: 3, in: statement)
        try bind(updatedAt, to: 4, in: statement)
        try bind(serverVersion, to: 5, in: statement)
        try bind(id, to: 6, in: statement)
        try stepDone(statement)
        try refreshPostSyncStatus(postId: postId)
    }

    func applyCommentDeleted(id: String, postId: String, deletedAt: Date, serverVersion: Int) throws {
        guard try fetchPost(id: postId) != nil else {
            return
        }

        let statement = try prepare(
            """
            UPDATE local_comments
            SET deletedAt = ?,
                serverVersion = ?,
                syncStatus = 'synced',
                updatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(deletedAt, to: 1, in: statement)
        try bind(serverVersion, to: 2, in: statement)
        try bind(deletedAt, to: 3, in: statement)
        try bind(id, to: 4, in: statement)
        try stepDone(statement)
        try refreshPostSyncStatus(postId: postId)
    }
}
