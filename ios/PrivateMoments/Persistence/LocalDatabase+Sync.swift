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
              AND (
                  (m.kind = 'image' AND m.remoteCompressedPath IS NOT NULL AND m.localCompressedPath = '')
                  OR (m.kind = 'video' AND m.remoteThumbnailPath IS NOT NULL AND (m.localThumbnailPath IS NULL OR m.localThumbnailPath = ''))
              )
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

    func pendingOperationTypeCounts() throws -> [OutboxOperationTypeCount] {
        let statement = try prepare(
            """
            SELECT type, status, COUNT(*)
            FROM outbox_operations
            WHERE status IN ('pending', 'failed')
            GROUP BY type, status
            ORDER BY type ASC, status ASC
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        var counts: [OutboxOperationTypeCount] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            counts.append(
                OutboxOperationTypeCount(
                    type: try text(statement, 0),
                    status: try text(statement, 1),
                    count: Int(sqlite3_column_int64(statement, 2))
                )
            )
        }

        return counts
    }

    func fetchPendingMediaReadyForUpload() throws -> [TimelineMedia] {
        let statement = try prepare(
            """
            SELECT m.id, m.postId, m.kind, m.localCompressedPath, m.localOriginalStagingPath, m.localThumbnailPath,
                   m.remoteCompressedPath, m.remoteOriginalPath, m.remoteThumbnailPath, m.originalPreserved,
                   m.uploadStatus, m.mimeType, m.durationSeconds, m.transcriptionText, m.transcriptionStatus,
                   m.transcriptionError, m.transcriptionUpdatedAt, m.sortOrder, m.checksum, m.createdAt, m.updatedAt
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
            ORDER BY
              CASE WHEN m.uploadStatus = 'pending' THEN 0 ELSE 1 END,
              m.createdAt ASC,
              m.sortOrder ASC
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
            SELECT m.id, m.postId, m.kind, m.localCompressedPath, m.localOriginalStagingPath, m.localThumbnailPath,
                   m.remoteCompressedPath, m.remoteOriginalPath, m.remoteThumbnailPath, m.originalPreserved,
                   m.uploadStatus, m.mimeType, m.durationSeconds, m.transcriptionText, m.transcriptionStatus,
                   m.transcriptionError, m.transcriptionUpdatedAt, m.sortOrder, m.checksum, m.createdAt, m.updatedAt
            FROM local_media m
            JOIN local_posts p ON p.id = m.postId
            WHERE m.uploadStatus = 'uploaded'
              AND (
                  (m.kind = 'image' AND m.remoteCompressedPath IS NOT NULL AND m.localCompressedPath = '')
                  OR (m.kind = 'video' AND m.remoteThumbnailPath IS NOT NULL AND (m.localThumbnailPath IS NULL OR m.localThumbnailPath = ''))
              )
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

    func fetchMediaPendingTranscription(limit: Int = 5) throws -> [TimelineMedia] {
        let statement = try prepare(
            """
            SELECT m.id, m.postId, m.kind, m.localCompressedPath, m.localOriginalStagingPath, m.localThumbnailPath,
                   m.remoteCompressedPath, m.remoteOriginalPath, m.remoteThumbnailPath, m.originalPreserved,
                   m.uploadStatus, m.mimeType, m.durationSeconds, m.transcriptionText, m.transcriptionStatus,
                   m.transcriptionError, m.transcriptionUpdatedAt, m.sortOrder, m.checksum, m.createdAt, m.updatedAt
            FROM local_media m
            JOIN local_posts p ON p.id = m.postId
            WHERE m.kind IN ('audio', 'video')
              AND (
                m.transcriptionStatus IN ('not_requested', 'pending', 'transcribing')
                OR (
                  m.transcriptionStatus = 'failed'
                  AND m.transcriptionError LIKE 'No speech%'
                )
              )
              AND m.transcriptionText IS NULL
              AND m.localCompressedPath <> ''
              AND m.deletedAt IS NULL
              AND p.deletedAt IS NULL
            ORDER BY m.createdAt ASC
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

                if try shouldSettleRejectedCommentOperation(operation, reason: rejection.reason) {
                    try updateOperationStatus(
                        opId: rejection.opId,
                        status: "synced",
                        lastError: nil,
                        sentAt: now,
                        updatedAt: now
                    )
                    try markCommentSyncStatus(commentId: operation.entityId, status: "synced")
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
                }
            }
        }
    }

    func shouldSettleRejectedCommentOperation(_ operation: OutboxOperation, reason: String) throws -> Bool {
        guard operation.entityType == "comment" else {
            return false
        }

        if operation.type == "delete_comment", reason == "Comment not found" {
            guard let comment = try fetchComment(id: operation.entityId) else {
                return true
            }

            return comment.deletedAt != nil
        }

        if operation.type == "create_comment", reason == "Parent post not found" {
            guard let comment = try fetchComment(id: operation.entityId) else {
                return true
            }

            if comment.deletedAt != nil {
                return true
            }

            return try fetchPost(id: comment.postId)?.deletedAt != nil
        }

        return false
    }

    func markCommentSyncStatus(commentId: String, status: String) throws {
        let statement = try prepare(
            """
            UPDATE local_comments
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
        try bind(commentId, to: 3, in: statement)
        try stepDone(statement)
    }

    func markMediaUploaded(mediaId: String, variant: String, remotePath: String, checksum: String?) throws {
        let statement = try prepare(uploadedMediaSQL(for: variant))
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

    private func uploadedMediaSQL(for variant: String) -> String {
        switch variant {
        case "thumbnail":
            return """
            UPDATE local_media
            SET remoteThumbnailPath = ?,
                uploadStatus = 'uploaded',
                uploadError = NULL,
                checksum = ?,
                updatedAt = ?
            WHERE id = ?
            """

        case "original":
            return """
            UPDATE local_media
            SET remoteOriginalPath = ?,
                uploadStatus = 'uploaded',
                uploadError = NULL,
                checksum = ?,
                updatedAt = ?
            WHERE id = ?
            """

        default:
            return """
            UPDATE local_media
            SET remoteCompressedPath = ?,
                uploadStatus = 'uploaded',
                uploadError = NULL,
                checksum = ?,
                updatedAt = ?
            WHERE id = ?
            """
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

    func markMediaDownloaded(mediaId: String, localPath: String, isThumbnail: Bool = false) throws {
        let column = isThumbnail ? "localThumbnailPath" : "localCompressedPath"
        let statement = try prepare(
            """
            UPDATE local_media
            SET \(column) = ?,
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

    func applyPostCreated(
        id: String,
        text: String,
        isFavorite: Bool,
        isPinned: Bool,
        pinnedAt: Date?,
        aiTagProcessedAt: Date?,
        tagsUserEditedAt: Date?,
        occurredAt: Date,
        serverVersion: Int
    ) throws {
        let now = Date()
        let existing = try fetchPost(id: id)

        if existing == nil {
            let statement = try prepare(
                """
                INSERT INTO local_posts
                    (id, text, isFavorite, isPinned, pinnedAt, aiTagProcessedAt, tagsUserEditedAt, occurredAt,
                     localCreatedAt, localUpdatedAt, localEditedAt, serverVersion, syncStatus, deletedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, 'synced', NULL)
                """
            )
            defer {
                sqlite3_finalize(statement)
            }

            try bind(id, to: 1, in: statement)
            try bind(text, to: 2, in: statement)
            try bind(isFavorite ? 1 : 0, to: 3, in: statement)
            try bind(isPinned ? 1 : 0, to: 4, in: statement)
            try bind(isPinned ? pinnedAt : nil, to: 5, in: statement)
            try bind(aiTagProcessedAt, to: 6, in: statement)
            try bind(tagsUserEditedAt, to: 7, in: statement)
            try bind(occurredAt, to: 8, in: statement)
            try bind(now, to: 9, in: statement)
            try bind(now, to: 10, in: statement)
            try bind(serverVersion, to: 11, in: statement)
            try stepDone(statement)
            return
        }

        let statement = try prepare(
            """
            UPDATE local_posts
            SET text = ?,
                isFavorite = ?,
                isPinned = ?,
                pinnedAt = ?,
                aiTagProcessedAt = ?,
                tagsUserEditedAt = ?,
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
        try bind(isPinned ? 1 : 0, to: 3, in: statement)
        try bind(isPinned ? pinnedAt : nil, to: 4, in: statement)
        try bind(aiTagProcessedAt, to: 5, in: statement)
        try bind(tagsUserEditedAt, to: 6, in: statement)
        try bind(occurredAt, to: 7, in: statement)
        try bind(serverVersion, to: 8, in: statement)
        try bind(now, to: 9, in: statement)
        try bind(id, to: 10, in: statement)
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
        try softDeleteComments(postId: id, deletedAt: deletedAt)
    }

    func applyPostUpdated(
        id: String,
        text: String,
        isFavorite: Bool?,
        isPinned: Bool?,
        pinnedAt: Date?,
        occurredAt: Date,
        editedAt: Date,
        isUserEdit: Bool = true,
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
                        isPinned = COALESCE(?, isPinned),
                        pinnedAt = CASE WHEN ? = 1 THEN ? ELSE pinnedAt END,
                        occurredAt = ?,
                        localEditedAt = CASE WHEN ? = 1 THEN ? ELSE localEditedAt END,
                        serverVersion = ?,
                        localUpdatedAt = ?
                    WHERE id = ?
                    """
                    : """
                    UPDATE local_posts
                    SET text = ?,
                        isFavorite = ?,
                        isPinned = COALESCE(?, isPinned),
                        pinnedAt = CASE WHEN ? = 1 THEN ? ELSE pinnedAt END,
                        occurredAt = ?,
                        localEditedAt = CASE WHEN ? = 1 THEN ? ELSE localEditedAt END,
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
            let shouldUpdatePin = isPinned != nil
            if let isFavorite {
                try bind(isFavorite ? 1 : 0, to: 2, in: statement)
                try bind(isPinned.map { $0 ? 1 : 0 }, to: 3, in: statement)
                try bind(shouldUpdatePin ? 1 : 0, to: 4, in: statement)
                try bind(isPinned == true ? pinnedAt : nil, to: 5, in: statement)
                try bind(occurredAt, to: 6, in: statement)
                try bind(isUserEdit ? 1 : 0, to: 7, in: statement)
                try bind(editedAt, to: 8, in: statement)
                try bind(serverVersion, to: 9, in: statement)
                try bind(now, to: 10, in: statement)
                try bind(id, to: 11, in: statement)
            } else {
                try bind(isPinned.map { $0 ? 1 : 0 }, to: 2, in: statement)
                try bind(shouldUpdatePin ? 1 : 0, to: 3, in: statement)
                try bind(isPinned == true ? pinnedAt : nil, to: 4, in: statement)
                try bind(occurredAt, to: 5, in: statement)
                try bind(isUserEdit ? 1 : 0, to: 6, in: statement)
                try bind(editedAt, to: 7, in: statement)
                try bind(serverVersion, to: 8, in: statement)
                try bind(now, to: 9, in: statement)
                try bind(id, to: 10, in: statement)
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

    func applyPostPinUpdated(
        id: String,
        isPinned: Bool,
        pinnedAt: Date?,
        updatedAt: Date,
        serverVersion: Int
    ) throws {
        guard try fetchPost(id: id) != nil else {
            return
        }

        let statement = try prepare(
            """
            UPDATE local_posts
            SET isPinned = ?,
                pinnedAt = ?,
                localUpdatedAt = ?,
                serverVersion = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(isPinned ? 1 : 0, to: 1, in: statement)
        try bind(isPinned ? pinnedAt : nil, to: 2, in: statement)
        try bind(updatedAt, to: 3, in: statement)
        try bind(serverVersion, to: 4, in: statement)
        try bind(id, to: 5, in: statement)
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

    func applyCommentCreated(
        id: String,
        postId: String,
        text: String,
        createdAt: Date,
        updatedAt: Date,
        serverVersion: Int
    ) throws {
        guard let post = try fetchPost(id: postId), post.deletedAt == nil else {
            throw StoreError.invalidServerChange("comment_created references a missing parent post")
        }

        if try fetchComment(id: id) == nil {
            try insert(
                TimelineComment(
                    id: id,
                    postId: postId,
                    text: text,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    serverVersion: serverVersion,
                    deletedAt: nil
                )
            )
            return
        }

        let statement = try prepare(
            """
            UPDATE local_comments
            SET text = ?,
                postId = ?,
                createdAt = ?,
                updatedAt = ?,
                serverVersion = ?,
                syncStatus = 'synced',
                deletedAt = NULL
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(text, to: 1, in: statement)
        try bind(postId, to: 2, in: statement)
        try bind(createdAt, to: 3, in: statement)
        try bind(updatedAt, to: 4, in: statement)
        try bind(serverVersion, to: 5, in: statement)
        try bind(id, to: 6, in: statement)
        try stepDone(statement)
    }

    func applyCommentDeleted(id: String, postId: String, deletedAt: Date, serverVersion: Int) throws {
        guard let post = try fetchPost(id: postId), post.deletedAt == nil else {
            throw StoreError.invalidServerChange("comment_deleted references a missing parent post")
        }

        guard try fetchComment(id: id) != nil else {
            throw StoreError.invalidServerChange("comment_deleted references a missing local comment")
        }

        let statement = try prepare(
            """
            UPDATE local_comments
            SET deletedAt = ?,
                updatedAt = ?,
                serverVersion = ?,
                syncStatus = 'synced'
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(deletedAt, to: 1, in: statement)
        try bind(deletedAt, to: 2, in: statement)
        try bind(serverVersion, to: 3, in: statement)
        try bind(id, to: 4, in: statement)
        try stepDone(statement)
    }

    func applyMediaUploaded(
        mediaId: String,
        postId: String,
        kind: String,
        variant: String,
        remotePath: String,
        originalPreserved: Bool,
        sortOrder: Int,
        checksum: String?,
        mimeType: String?,
        durationSeconds: Double?,
        transcriptionText: String?
    ) throws {
        guard try fetchPost(id: postId) != nil else {
            return
        }

        let remoteCompressedPath = variant == "compressed" ? remotePath : nil
        let remoteOriginalPath = variant == "original" ? remotePath : nil
        let remoteThumbnailPath = variant == "thumbnail" ? remotePath : nil

        if try fetchMedia(id: mediaId) == nil {
            let now = Date()
            let statement = try prepare(
                """
                INSERT INTO local_media
                    (id, postId, kind, localCompressedPath, localOriginalStagingPath, localThumbnailPath,
                     remoteCompressedPath, remoteOriginalPath, remoteThumbnailPath, originalPreserved,
                     uploadStatus, mimeType, durationSeconds, transcriptionText, transcriptionStatus,
                     transcriptionError, transcriptionUpdatedAt, sortOrder, checksum, createdAt, updatedAt)
                VALUES (?, ?, ?, '', NULL, NULL, ?, ?, ?, ?, 'uploaded', ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?)
                """
            )
            defer {
                sqlite3_finalize(statement)
            }

            try bind(mediaId, to: 1, in: statement)
            try bind(postId, to: 2, in: statement)
            try bind(kind, to: 3, in: statement)
            try bind(remoteCompressedPath, to: 4, in: statement)
            try bind(remoteOriginalPath, to: 5, in: statement)
            try bind(remoteThumbnailPath, to: 6, in: statement)
            try bind(originalPreserved ? 1 : 0, to: 7, in: statement)
            try bind(mimeType, to: 8, in: statement)
            try bind(durationSeconds, to: 9, in: statement)
            try bind(transcriptionText, to: 10, in: statement)
            try bind(transcriptionText == nil ? "not_requested" : "transcribed", to: 11, in: statement)
            try bind(transcriptionText == nil ? nil : now, to: 12, in: statement)
            try bind(sortOrder, to: 13, in: statement)
            try bind(checksum, to: 14, in: statement)
            try bind(now, to: 15, in: statement)
            try bind(now, to: 16, in: statement)
            try stepDone(statement)
            return
        }

        let statement = try prepare(
            """
            UPDATE local_media
            SET kind = ?,
                remoteCompressedPath = COALESCE(?, remoteCompressedPath),
                remoteOriginalPath = COALESCE(?, remoteOriginalPath),
                remoteThumbnailPath = COALESCE(?, remoteThumbnailPath),
                originalPreserved = ?,
                uploadStatus = 'uploaded',
                uploadError = NULL,
                mimeType = COALESCE(?, mimeType),
                durationSeconds = COALESCE(?, durationSeconds),
                transcriptionText = COALESCE(?, transcriptionText),
                transcriptionStatus = CASE WHEN ? IS NULL THEN transcriptionStatus ELSE 'transcribed' END,
                transcriptionError = CASE WHEN ? IS NULL THEN transcriptionError ELSE NULL END,
                transcriptionUpdatedAt = COALESCE(?, transcriptionUpdatedAt),
                sortOrder = ?,
                checksum = ?,
                updatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(kind, to: 1, in: statement)
        try bind(remoteCompressedPath, to: 2, in: statement)
        try bind(remoteOriginalPath, to: 3, in: statement)
        try bind(remoteThumbnailPath, to: 4, in: statement)
        try bind(originalPreserved ? 1 : 0, to: 5, in: statement)
        try bind(mimeType, to: 6, in: statement)
        try bind(durationSeconds, to: 7, in: statement)
        let now = Date()
        try bind(transcriptionText, to: 8, in: statement)
        try bind(transcriptionText, to: 9, in: statement)
        try bind(transcriptionText, to: 10, in: statement)
        try bind(transcriptionText == nil ? nil : now, to: 11, in: statement)
        try bind(sortOrder, to: 12, in: statement)
        try bind(checksum, to: 13, in: statement)
        try bind(now, to: 14, in: statement)
        try bind(mediaId, to: 15, in: statement)
        try stepDone(statement)
        try refreshPostSyncStatus(postId: postId)
    }

    func updateMediaTranscriptionStatus(
        mediaId: String,
        status: String,
        error: String?,
        updatedAt: Date
    ) throws {
        let statement = try prepare(
            """
            UPDATE local_media
            SET transcriptionStatus = ?,
                transcriptionError = ?,
                transcriptionUpdatedAt = ?,
                updatedAt = ?
            WHERE id = ?
              AND deletedAt IS NULL
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(status, to: 1, in: statement)
        try bind(error, to: 2, in: statement)
        try bind(updatedAt, to: 3, in: statement)
        try bind(updatedAt, to: 4, in: statement)
        try bind(mediaId, to: 5, in: statement)
        try stepDone(statement)
    }

    func updateMediaTranscription(
        mediaId: String,
        transcriptionText: String,
        updatedAt: Date,
        operation: OutboxOperation?
    ) throws {
        try transaction {
            let statement = try prepare(
                """
                UPDATE local_media
                SET transcriptionText = ?,
                    transcriptionStatus = 'transcribed',
                    transcriptionError = NULL,
                    transcriptionUpdatedAt = ?,
                    updatedAt = ?
                WHERE id = ?
                  AND deletedAt IS NULL
                """
            )
            defer {
                sqlite3_finalize(statement)
            }

            try bind(transcriptionText, to: 1, in: statement)
            try bind(updatedAt, to: 2, in: statement)
            try bind(updatedAt, to: 3, in: statement)
            try bind(mediaId, to: 4, in: statement)
            try stepDone(statement)

            if let operation {
                try insert(operation)
                if let media = try fetchMedia(id: mediaId) {
                    try refreshPostSyncStatus(postId: media.postId)
                }
            }
        }
    }

    func applyMediaTranscriptionUpdated(
        mediaId: String,
        postId: String,
        transcriptionText: String?,
        serverVersion: Int
    ) throws {
        guard try fetchPost(id: postId) != nil else {
            return
        }

        let now = Date()
        let statement = try prepare(
            """
            UPDATE local_media
            SET transcriptionText = ?,
                transcriptionStatus = ?,
                transcriptionError = NULL,
                transcriptionUpdatedAt = ?,
                updatedAt = ?
            WHERE id = ?
              AND postId = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(transcriptionText, to: 1, in: statement)
        try bind(transcriptionText == nil ? "not_requested" : "transcribed", to: 2, in: statement)
        try bind(now, to: 3, in: statement)
        try bind(now, to: 4, in: statement)
        try bind(mediaId, to: 5, in: statement)
        try bind(postId, to: 6, in: statement)
        try stepDone(statement)

        let postStatement = try prepare(
            """
            UPDATE local_posts
            SET serverVersion = ?,
                localUpdatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(postStatement)
        }

        try bind(serverVersion, to: 1, in: postStatement)
        try bind(now, to: 2, in: postStatement)
        try bind(postId, to: 3, in: postStatement)
        try stepDone(postStatement)
        try refreshPostSyncStatus(postId: postId)
    }

    func applyAISummaryUpdated(_ summary: TimelineAISummary, serverVersion: Int) throws {
        guard try fetchPost(id: summary.postId) != nil else {
            throw StoreError.invalidServerChange("ai_summary_updated references a missing parent post")
        }

        guard try fetchMedia(id: summary.mediaId) != nil else {
            throw StoreError.invalidServerChange("ai_summary_updated references missing media")
        }

        try transaction {
            try upsertAISummary(summary)
            try updatePostServerVersion(postId: summary.postId, serverVersion: serverVersion)
        }
    }

    func applyAISummaryDeleted(_ summary: TimelineAISummary, serverVersion: Int) throws {
        guard try fetchPost(id: summary.postId) != nil else {
            throw StoreError.invalidServerChange("ai_summary_deleted references a missing parent post")
        }

        let deletedSummary = TimelineAISummary(
            id: summary.id,
            postId: summary.postId,
            mediaId: summary.mediaId,
            status: "deleted",
            format: summary.format,
            language: summary.language,
            overview: summary.overview,
            keyPoints: summary.keyPoints,
            sections: summary.sections,
            summaryText: summary.summaryText,
            inputTranscriptLength: summary.inputTranscriptLength,
            inputDurationSeconds: summary.inputDurationSeconds,
            promptVersion: summary.promptVersion,
            provider: summary.provider,
            model: summary.model,
            errorCode: summary.errorCode,
            errorMessage: summary.errorMessage,
            createdAt: summary.createdAt,
            updatedAt: summary.updatedAt,
            deletedAt: summary.deletedAt ?? Date()
        )

        try transaction {
            try upsertAISummary(deletedSummary)
            try updatePostServerVersion(postId: summary.postId, serverVersion: serverVersion)
        }
    }

    func applyTagUpdated(_ tag: TimelineTag) throws {
        try upsertTag(tag)
    }

    func applyTagAliasUpdated(_ alias: TimelineTagAlias) throws {
        try upsertTagAlias(alias)
    }

    func applyTagAliasDeleted(_ alias: TimelineTagAlias) throws {
        guard try fetchTag(id: alias.tagId) != nil else {
            return
        }

        try upsertTagAlias(alias)
    }

    func applyPostTagUpdated(_ assignedTag: TimelineAssignedTag, serverVersion: Int) throws {
        guard try fetchPost(id: assignedTag.postId) != nil else {
            return
        }

        try transaction {
            try upsertAssignedTag(assignedTag)
            try updatePostServerVersion(postId: assignedTag.postId, serverVersion: serverVersion)
        }
    }

    func applyPostTagDeleted(_ assignedTag: TimelineAssignedTag, serverVersion: Int) throws {
        guard try fetchPost(id: assignedTag.postId) != nil else {
            return
        }

        try transaction {
            try upsertAssignedTag(assignedTag)
            try updatePostServerVersion(postId: assignedTag.postId, serverVersion: serverVersion)
        }
    }

    func applyPostTagStateUpdated(
        postId: String,
        aiTagProcessedAt: Date?,
        tagsUserEditedAt: Date?,
        serverVersion: Int
    ) throws {
        guard try fetchPost(id: postId) != nil else {
            return
        }

        let statement = try prepare(
            """
            UPDATE local_posts
            SET aiTagProcessedAt = ?,
                tagsUserEditedAt = ?,
                serverVersion = ?,
                localUpdatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(aiTagProcessedAt, to: 1, in: statement)
        try bind(tagsUserEditedAt, to: 2, in: statement)
        try bind(serverVersion, to: 3, in: statement)
        try bind(Date(), to: 4, in: statement)
        try bind(postId, to: 5, in: statement)
        try stepDone(statement)
    }

    private func updatePostServerVersion(postId: String, serverVersion: Int) throws {
        let statement = try prepare(
            """
            UPDATE local_posts
            SET serverVersion = ?,
                localUpdatedAt = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(serverVersion, to: 1, in: statement)
        try bind(Date(), to: 2, in: statement)
        try bind(postId, to: 3, in: statement)
        try stepDone(statement)
    }
}
