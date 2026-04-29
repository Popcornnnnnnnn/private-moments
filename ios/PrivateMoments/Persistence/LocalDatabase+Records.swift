import Foundation
import SQLite3

extension LocalDatabase {
    func fetchPosts() throws -> [TimelinePost] {
        let statement = try prepare(
            """
            SELECT id, text, isFavorite, occurredAt, localCreatedAt, localUpdatedAt, localEditedAt, serverVersion, syncStatus, deletedAt
            FROM local_posts
            WHERE deletedAt IS NULL
            ORDER BY occurredAt DESC
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        var posts: [TimelinePost] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            posts.append(
                TimelinePost(
                    id: try text(statement, 0),
                    text: try text(statement, 1),
                    isFavorite: sqlite3_column_int(statement, 2) == 1,
                    occurredAt: try date(statement, 3),
                    localCreatedAt: try date(statement, 4),
                    localUpdatedAt: try date(statement, 5),
                    localEditedAt: try optionalDate(statement, 6),
                    serverVersion: optionalInt(statement, 7),
                    syncStatus: try text(statement, 8),
                    deletedAt: try optionalDate(statement, 9)
                )
            )
        }

        return posts
    }

    func fetchMedia(postId: String) throws -> [TimelineMedia] {
        let statement = try prepare(
            """
            SELECT id, postId, localCompressedPath, localOriginalStagingPath, remoteCompressedPath,
                   remoteOriginalPath, originalPreserved, uploadStatus, sortOrder, checksum, createdAt, updatedAt
            FROM local_media
            WHERE postId = ?
              AND deletedAt IS NULL
            ORDER BY sortOrder ASC
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(postId, to: 1, in: statement)
        var media: [TimelineMedia] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            media.append(try timelineMedia(statement))
        }

        return media
    }

    func insert(_ post: TimelinePost) throws {
        let statement = try prepare(
            """
            INSERT INTO local_posts
                (id, text, isFavorite, occurredAt, localCreatedAt, localUpdatedAt, localEditedAt, serverVersion, syncStatus, deletedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(post.id, to: 1, in: statement)
        try bind(post.text, to: 2, in: statement)
        try bind(post.isFavorite ? 1 : 0, to: 3, in: statement)
        try bind(post.occurredAt, to: 4, in: statement)
        try bind(post.localCreatedAt, to: 5, in: statement)
        try bind(post.localUpdatedAt, to: 6, in: statement)
        try bind(post.localEditedAt, to: 7, in: statement)
        try bind(post.serverVersion, to: 8, in: statement)
        try bind(post.syncStatus, to: 9, in: statement)
        try bind(post.deletedAt, to: 10, in: statement)
        try stepDone(statement)
    }

    func insert(_ media: TimelineMedia) throws {
        let statement = try prepare(
            """
            INSERT INTO local_media
                (id, postId, localCompressedPath, localOriginalStagingPath, remoteCompressedPath,
                 remoteOriginalPath, originalPreserved, uploadStatus, sortOrder, checksum, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(media.id, to: 1, in: statement)
        try bind(media.postId, to: 2, in: statement)
        try bind(AppDirectories.storedPath(forLocalPath: media.localCompressedPath), to: 3, in: statement)
        try bind(storedLocalPath(media.localOriginalStagingPath), to: 4, in: statement)
        try bind(media.remoteCompressedPath, to: 5, in: statement)
        try bind(media.remoteOriginalPath, to: 6, in: statement)
        try bind(media.originalPreserved ? 1 : 0, to: 7, in: statement)
        try bind(media.uploadStatus, to: 8, in: statement)
        try bind(media.sortOrder, to: 9, in: statement)
        try bind(media.checksum, to: 10, in: statement)
        try bind(media.createdAt, to: 11, in: statement)
        try bind(media.updatedAt, to: 12, in: statement)
        try stepDone(statement)
    }

    func insert(_ operation: OutboxOperation) throws {
        let statement = try prepare(
            """
            INSERT INTO outbox_operations
                (id, opId, type, entityType, entityId, payloadJson, status, attemptCount, lastError, createdAt, updatedAt, sentAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(operation.id, to: 1, in: statement)
        try bind(operation.opId, to: 2, in: statement)
        try bind(operation.type, to: 3, in: statement)
        try bind(operation.entityType, to: 4, in: statement)
        try bind(operation.entityId, to: 5, in: statement)
        try bind(operation.payloadJson, to: 6, in: statement)
        try bind(operation.status, to: 7, in: statement)
        try bind(operation.attemptCount, to: 8, in: statement)
        try bind(operation.lastError, to: 9, in: statement)
        try bind(operation.createdAt, to: 10, in: statement)
        try bind(operation.updatedAt, to: 11, in: statement)
        try bind(operation.sentAt, to: 12, in: statement)
        try stepDone(statement)
    }

    func fetchPost(id: String) throws -> TimelinePost? {
        let statement = try prepare(
            """
            SELECT id, text, isFavorite, occurredAt, localCreatedAt, localUpdatedAt, localEditedAt, serverVersion, syncStatus, deletedAt
            FROM local_posts
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(id, to: 1, in: statement)

        if sqlite3_step(statement) == SQLITE_ROW {
            return TimelinePost(
                id: try text(statement, 0),
                text: try text(statement, 1),
                isFavorite: sqlite3_column_int(statement, 2) == 1,
                occurredAt: try date(statement, 3),
                localCreatedAt: try date(statement, 4),
                localUpdatedAt: try date(statement, 5),
                localEditedAt: try optionalDate(statement, 6),
                serverVersion: optionalInt(statement, 7),
                syncStatus: try text(statement, 8),
                deletedAt: try optionalDate(statement, 9)
            )
        }

        return nil
    }

    func fetchMedia(id: String) throws -> TimelineMedia? {
        let statement = try prepare(
            """
            SELECT id, postId, localCompressedPath, localOriginalStagingPath, remoteCompressedPath,
                   remoteOriginalPath, originalPreserved, uploadStatus, sortOrder, checksum, createdAt, updatedAt
            FROM local_media
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(id, to: 1, in: statement)

        if sqlite3_step(statement) == SQLITE_ROW {
            return try timelineMedia(statement)
        }

        return nil
    }

    func fetchOperation(opId: String) throws -> OutboxOperation? {
        let statement = try prepare(
            """
            SELECT id, opId, type, entityType, entityId, payloadJson, status, attemptCount,
                   lastError, createdAt, updatedAt, sentAt
            FROM outbox_operations
            WHERE opId = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(opId, to: 1, in: statement)

        if sqlite3_step(statement) == SQLITE_ROW {
            return try outboxOperation(statement)
        }

        return nil
    }

    func updateOperationStatus(
        opId: String,
        status: String,
        lastError: String?,
        sentAt: Date?,
        updatedAt: Date = Date()
    ) throws {
        let statement = try prepare(
            """
            UPDATE outbox_operations
            SET status = ?,
                lastError = ?,
                updatedAt = ?,
                sentAt = ?
            WHERE opId = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(status, to: 1, in: statement)
        try bind(lastError, to: 2, in: statement)
        try bind(updatedAt, to: 3, in: statement)
        try bind(sentAt, to: 4, in: statement)
        try bind(opId, to: 5, in: statement)
        try stepDone(statement)
    }

    func supersedeFailedOperations(entityId: String, updatedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE outbox_operations
            SET status = 'superseded',
                updatedAt = ?
            WHERE entityId = ?
              AND status = 'failed'
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(updatedAt, to: 1, in: statement)
        try bind(entityId, to: 2, in: statement)
        try stepDone(statement)
    }

    func refreshPostSyncStatus(postId: String) throws {
        let pendingOps = try count(
            "SELECT COUNT(*) FROM outbox_operations WHERE entityId = ? AND status = 'pending'"
        ) { statement in
            try self.bind(postId, to: 1, in: statement)
        }
        let failedOps = try count(
            "SELECT COUNT(*) FROM outbox_operations WHERE entityId = ? AND status = 'failed'"
        ) { statement in
            try self.bind(postId, to: 1, in: statement)
        }
        let failedMedia = try count(
            "SELECT COUNT(*) FROM local_media WHERE postId = ? AND uploadStatus = 'failed' AND deletedAt IS NULL"
        ) { statement in
            try self.bind(postId, to: 1, in: statement)
        }
        let pendingMedia = try count(
            "SELECT COUNT(*) FROM local_media WHERE postId = ? AND uploadStatus = 'pending' AND deletedAt IS NULL"
        ) { statement in
            try self.bind(postId, to: 1, in: statement)
        }

        if pendingOps > 0 {
            try updatePostSyncStatus(postId: postId, status: "pending")
        } else if failedOps > 0 || failedMedia > 0 {
            try updatePostSyncStatus(postId: postId, status: "failed")
        } else if pendingMedia > 0 {
            try updatePostSyncStatus(postId: postId, status: "partial")
        } else {
            try updatePostSyncStatus(postId: postId, status: "synced")
        }
    }

    func updatePostSyncStatus(postId: String, status: String) throws {
        let statement = try prepare(
            """
            UPDATE local_posts
            SET syncStatus = ?,
                localUpdatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(status, to: 1, in: statement)
        try bind(Date(), to: 2, in: statement)
        try bind(postId, to: 3, in: statement)
        try stepDone(statement)
    }

    func softDeleteMedia(mediaId: String, deletedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE local_media
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

    func updateMediaSortOrder(mediaId: String, sortOrder: Int, updatedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE local_media
            SET sortOrder = ?,
                updatedAt = ?
            WHERE id = ?
              AND deletedAt IS NULL
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(sortOrder, to: 1, in: statement)
        try bind(updatedAt, to: 2, in: statement)
        try bind(mediaId, to: 3, in: statement)
        try stepDone(statement)
    }


    func timelineMedia(_ statement: OpaquePointer) throws -> TimelineMedia {
        TimelineMedia(
            id: try text(statement, 0),
            postId: try text(statement, 1),
            localCompressedPath: try localFilePath(statement, 2),
            localOriginalStagingPath: try optionalLocalFilePath(statement, 3),
            remoteCompressedPath: optionalText(statement, 4),
            remoteOriginalPath: optionalText(statement, 5),
            originalPreserved: sqlite3_column_int(statement, 6) == 1,
            uploadStatus: try text(statement, 7),
            sortOrder: Int(sqlite3_column_int64(statement, 8)),
            checksum: optionalText(statement, 9),
            createdAt: try date(statement, 10),
            updatedAt: try date(statement, 11)
        )
    }

    func localFilePath(_ statement: OpaquePointer, _ index: Int32) throws -> String {
        try AppDirectories.localFilePath(fromStoredPath: text(statement, index))
    }

    func optionalLocalFilePath(_ statement: OpaquePointer, _ index: Int32) throws -> String? {
        guard let path = optionalText(statement, index) else {
            return nil
        }

        return try AppDirectories.localFilePath(fromStoredPath: path)
    }

    func storedLocalPath(_ path: String?) throws -> String? {
        guard let path else {
            return nil
        }

        return try AppDirectories.storedPath(forLocalPath: path)
    }

    func outboxOperation(_ statement: OpaquePointer) throws -> OutboxOperation {
        OutboxOperation(
            id: try text(statement, 0),
            opId: try text(statement, 1),
            type: try text(statement, 2),
            entityType: try text(statement, 3),
            entityId: try text(statement, 4),
            payloadJson: try text(statement, 5),
            status: try text(statement, 6),
            attemptCount: Int(sqlite3_column_int64(statement, 7)),
            lastError: optionalText(statement, 8),
            createdAt: try date(statement, 9),
            updatedAt: try date(statement, 10),
            sentAt: try optionalDate(statement, 11)
        )
    }
}
