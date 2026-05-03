import Foundation
import SQLite3

extension LocalDatabase {
    func fetchPosts() throws -> [TimelinePost] {
        let statement = try prepare(
            """
            SELECT id, text, isFavorite, aiTagProcessedAt, tagsUserEditedAt, occurredAt,
                   localCreatedAt, localUpdatedAt, localEditedAt, serverVersion, syncStatus, deletedAt
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
                    aiTagProcessedAt: try optionalDate(statement, 3),
                    tagsUserEditedAt: try optionalDate(statement, 4),
                    occurredAt: try date(statement, 5),
                    localCreatedAt: try date(statement, 6),
                    localUpdatedAt: try date(statement, 7),
                    localEditedAt: try optionalDate(statement, 8),
                    serverVersion: optionalInt(statement, 9),
                    syncStatus: try text(statement, 10),
                    deletedAt: try optionalDate(statement, 11)
                )
            )
        }

        return posts
    }

    func fetchMedia(postId: String) throws -> [TimelineMedia] {
        let statement = try prepare(
            """
            SELECT id, postId, kind, localCompressedPath, localOriginalStagingPath, localThumbnailPath,
                   remoteCompressedPath, remoteOriginalPath, remoteThumbnailPath, originalPreserved,
                   uploadStatus, mimeType, durationSeconds, transcriptionText, transcriptionStatus,
                   transcriptionError, transcriptionUpdatedAt, sortOrder, checksum, createdAt, updatedAt
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

    func fetchComments(postId: String) throws -> [TimelineComment] {
        let statement = try prepare(
            """
            SELECT id, postId, text, createdAt, updatedAt, serverVersion, deletedAt
            FROM local_comments
            WHERE postId = ?
              AND deletedAt IS NULL
            ORDER BY createdAt ASC, id ASC
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(postId, to: 1, in: statement)
        var comments: [TimelineComment] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            comments.append(try timelineComment(statement))
        }

        return comments
    }

    func fetchAISummaries(postId: String) throws -> [TimelineAISummary] {
        let statement = try prepare(
            """
            SELECT id, postId, mediaId, status, format, language, overview, keyPointsJson,
                   sectionsJson, summaryText, inputTranscriptLength, inputDurationSeconds,
                   promptVersion, provider, model, errorCode, errorMessage, createdAt, updatedAt, deletedAt,
                   documentTitle, oneLiner, documentBlocksJson
            FROM local_ai_summaries
            WHERE postId = ?
              AND deletedAt IS NULL
            ORDER BY updatedAt DESC, id ASC
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(postId, to: 1, in: statement)
        var summaries: [TimelineAISummary] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            summaries.append(try timelineAISummary(statement))
        }

        return summaries
    }

    func fetchTags(type: String? = nil, includeArchived: Bool = false) throws -> [TimelineTag] {
        let sql: String
        if let type {
            sql = """
            SELECT id, type, name, normalizedName, colorHex, isDefault, isArchived, aiUsableAsPrimary, createdAt, updatedAt, archivedAt
            FROM local_tags
            WHERE type = ?
              AND (? = 1 OR isArchived = 0)
            ORDER BY isDefault DESC, name ASC
            """
            let statement = try prepare(sql)
            defer {
                sqlite3_finalize(statement)
            }

            try bind(type, to: 1, in: statement)
            try bind(includeArchived ? 1 : 0, to: 2, in: statement)
            return try collectTags(statement)
        }

        sql = """
        SELECT id, type, name, normalizedName, colorHex, isDefault, isArchived, aiUsableAsPrimary, createdAt, updatedAt, archivedAt
        FROM local_tags
        WHERE (? = 1 OR isArchived = 0)
        ORDER BY type ASC, isDefault DESC, name ASC
        """
        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        try bind(includeArchived ? 1 : 0, to: 1, in: statement)
        return try collectTags(statement)
    }

    func fetchTag(id: String) throws -> TimelineTag? {
        let statement = try prepare(
            """
            SELECT id, type, name, normalizedName, colorHex, isDefault, isArchived, aiUsableAsPrimary, createdAt, updatedAt, archivedAt
            FROM local_tags
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(id, to: 1, in: statement)
        if sqlite3_step(statement) == SQLITE_ROW {
            return try timelineTag(statement)
        }

        return nil
    }

    func fetchTag(normalizedName: String) throws -> TimelineTag? {
        let statement = try prepare(
            """
            SELECT id, type, name, normalizedName, colorHex, isDefault, isArchived, aiUsableAsPrimary, createdAt, updatedAt, archivedAt
            FROM local_tags
            WHERE normalizedName = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(normalizedName, to: 1, in: statement)
        if sqlite3_step(statement) == SQLITE_ROW {
            return try timelineTag(statement)
        }

        return nil
    }

    func fetchTagAliases(includeDeleted: Bool = false) throws -> [TimelineTagAlias] {
        let statement = try prepare(
            """
            SELECT id, tagId, alias, normalizedAlias, createdAt, deletedAt
            FROM local_tag_aliases
            WHERE (? = 1 OR deletedAt IS NULL)
            ORDER BY alias ASC
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(includeDeleted ? 1 : 0, to: 1, in: statement)
        var aliases: [TimelineTagAlias] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            aliases.append(try timelineTagAlias(statement))
        }

        return aliases
    }

    func fetchTagUsageCounts() throws -> [String: Int] {
        let statement = try prepare(
            """
            SELECT tagId, COUNT(*)
            FROM local_post_tags
            WHERE deletedAt IS NULL
            GROUP BY tagId
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        var counts: [String: Int] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            counts[try text(statement, 0)] = Int(sqlite3_column_int(statement, 1))
        }

        return counts
    }

    func fetchAssignedTags(postId: String) throws -> [TimelineAssignedTag] {
        let statement = try prepare(
            """
            SELECT pt.id, pt.postId, pt.tagId, pt.role, pt.source, pt.confidence, pt.aiSummaryId,
                   pt.createdAt, pt.updatedAt, pt.deletedAt,
                   t.id, t.type, t.name, t.normalizedName, t.colorHex, t.isDefault, t.isArchived,
                   t.aiUsableAsPrimary, t.createdAt, t.updatedAt, t.archivedAt
            FROM local_post_tags pt
            JOIN local_tags t ON t.id = pt.tagId
            WHERE pt.postId = ?
              AND pt.deletedAt IS NULL
              AND t.isArchived = 0
            ORDER BY CASE pt.role WHEN 'primary' THEN 0 ELSE 1 END, t.name ASC
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(postId, to: 1, in: statement)
        var tags: [TimelineAssignedTag] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            tags.append(try timelineAssignedTag(statement))
        }

        return tags
    }

    func upsertTag(_ tag: TimelineTag) throws {
        let statement = try prepare(
            """
            INSERT INTO local_tags
                (id, type, name, normalizedName, colorHex, isDefault, isArchived, aiUsableAsPrimary, createdAt, updatedAt, archivedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                type = excluded.type,
                name = excluded.name,
                normalizedName = excluded.normalizedName,
                colorHex = excluded.colorHex,
                isDefault = excluded.isDefault,
                isArchived = excluded.isArchived,
                aiUsableAsPrimary = excluded.aiUsableAsPrimary,
                createdAt = excluded.createdAt,
                updatedAt = excluded.updatedAt,
                archivedAt = excluded.archivedAt
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(tag.id, to: 1, in: statement)
        try bind(tag.type, to: 2, in: statement)
        try bind(tag.name, to: 3, in: statement)
        try bind(tag.normalizedName, to: 4, in: statement)
        try bind(tag.colorHex, to: 5, in: statement)
        try bind(tag.isDefault ? 1 : 0, to: 6, in: statement)
        try bind(tag.isArchived ? 1 : 0, to: 7, in: statement)
        try bind(tag.aiUsableAsPrimary ? 1 : 0, to: 8, in: statement)
        try bind(tag.createdAt, to: 9, in: statement)
        try bind(tag.updatedAt, to: 10, in: statement)
        try bind(tag.archivedAt, to: 11, in: statement)
        try stepDone(statement)
    }

    func upsertTagAlias(_ alias: TimelineTagAlias) throws {
        let statement = try prepare(
            """
            INSERT INTO local_tag_aliases
                (id, tagId, alias, normalizedAlias, createdAt, deletedAt)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                tagId = excluded.tagId,
                alias = excluded.alias,
                normalizedAlias = excluded.normalizedAlias,
                createdAt = excluded.createdAt,
                deletedAt = excluded.deletedAt
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(alias.id, to: 1, in: statement)
        try bind(alias.tagId, to: 2, in: statement)
        try bind(alias.alias, to: 3, in: statement)
        try bind(alias.normalizedAlias, to: 4, in: statement)
        try bind(alias.createdAt, to: 5, in: statement)
        try bind(alias.deletedAt, to: 6, in: statement)
        try stepDone(statement)
    }

    func upsertAssignedTag(_ assignedTag: TimelineAssignedTag) throws {
        try upsertTag(assignedTag.tag)

        let statement = try prepare(
            """
            INSERT INTO local_post_tags
                (id, postId, tagId, role, source, confidence, aiSummaryId, createdAt, updatedAt, deletedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(postId, tagId) DO UPDATE SET
                id = excluded.id,
                role = excluded.role,
                source = excluded.source,
                confidence = excluded.confidence,
                aiSummaryId = excluded.aiSummaryId,
                createdAt = excluded.createdAt,
                updatedAt = excluded.updatedAt,
                deletedAt = excluded.deletedAt
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(assignedTag.id, to: 1, in: statement)
        try bind(assignedTag.postId, to: 2, in: statement)
        try bind(assignedTag.tagId, to: 3, in: statement)
        try bind(assignedTag.role, to: 4, in: statement)
        try bind(assignedTag.source, to: 5, in: statement)
        try bind(assignedTag.confidence, to: 6, in: statement)
        try bind(assignedTag.aiSummaryId, to: 7, in: statement)
        try bind(assignedTag.createdAt, to: 8, in: statement)
        try bind(assignedTag.updatedAt, to: 9, in: statement)
        try bind(assignedTag.deletedAt, to: 10, in: statement)
        try stepDone(statement)
    }

    func insert(_ post: TimelinePost) throws {
        let statement = try prepare(
            """
            INSERT INTO local_posts
                (id, text, isFavorite, aiTagProcessedAt, tagsUserEditedAt, occurredAt,
                 localCreatedAt, localUpdatedAt, localEditedAt, serverVersion, syncStatus, deletedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(post.id, to: 1, in: statement)
        try bind(post.text, to: 2, in: statement)
        try bind(post.isFavorite ? 1 : 0, to: 3, in: statement)
        try bind(post.aiTagProcessedAt, to: 4, in: statement)
        try bind(post.tagsUserEditedAt, to: 5, in: statement)
        try bind(post.occurredAt, to: 6, in: statement)
        try bind(post.localCreatedAt, to: 7, in: statement)
        try bind(post.localUpdatedAt, to: 8, in: statement)
        try bind(post.localEditedAt, to: 9, in: statement)
        try bind(post.serverVersion, to: 10, in: statement)
        try bind(post.syncStatus, to: 11, in: statement)
        try bind(post.deletedAt, to: 12, in: statement)
        try stepDone(statement)
    }

    func insert(_ media: TimelineMedia) throws {
        let statement = try prepare(
            """
            INSERT INTO local_media
                (id, postId, kind, localCompressedPath, localOriginalStagingPath, localThumbnailPath,
                 remoteCompressedPath, remoteOriginalPath, remoteThumbnailPath, originalPreserved,
                 uploadStatus, mimeType, durationSeconds, transcriptionText, transcriptionStatus,
                 transcriptionError, transcriptionUpdatedAt, sortOrder, checksum, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(media.id, to: 1, in: statement)
        try bind(media.postId, to: 2, in: statement)
        try bind(media.kind, to: 3, in: statement)
        try bind(AppDirectories.storedPath(forLocalPath: media.localCompressedPath), to: 4, in: statement)
        try bind(storedLocalPath(media.localOriginalStagingPath), to: 5, in: statement)
        try bind(storedLocalPath(media.localThumbnailPath), to: 6, in: statement)
        try bind(media.remoteCompressedPath, to: 7, in: statement)
        try bind(media.remoteOriginalPath, to: 8, in: statement)
        try bind(media.remoteThumbnailPath, to: 9, in: statement)
        try bind(media.originalPreserved ? 1 : 0, to: 10, in: statement)
        try bind(media.uploadStatus, to: 11, in: statement)
        try bind(media.mimeType, to: 12, in: statement)
        try bind(media.durationSeconds, to: 13, in: statement)
        try bind(media.transcriptionText, to: 14, in: statement)
        try bind(media.transcriptionStatus, to: 15, in: statement)
        try bind(media.transcriptionError, to: 16, in: statement)
        try bind(media.transcriptionUpdatedAt, to: 17, in: statement)
        try bind(media.sortOrder, to: 18, in: statement)
        try bind(media.checksum, to: 19, in: statement)
        try bind(media.createdAt, to: 20, in: statement)
        try bind(media.updatedAt, to: 21, in: statement)
        try stepDone(statement)
    }

    func insert(_ comment: TimelineComment, syncStatus: String = "synced") throws {
        let statement = try prepare(
            """
            INSERT INTO local_comments
                (id, postId, text, createdAt, updatedAt, serverVersion, syncStatus, deletedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(comment.id, to: 1, in: statement)
        try bind(comment.postId, to: 2, in: statement)
        try bind(comment.text, to: 3, in: statement)
        try bind(comment.createdAt, to: 4, in: statement)
        try bind(comment.updatedAt, to: 5, in: statement)
        try bind(comment.serverVersion, to: 6, in: statement)
        try bind(syncStatus, to: 7, in: statement)
        try bind(comment.deletedAt, to: 8, in: statement)
        try stepDone(statement)
    }

    func upsertAISummary(_ summary: TimelineAISummary) throws {
        let statement = try prepare(
            """
            INSERT INTO local_ai_summaries
                (id, postId, mediaId, status, format, language, overview, keyPointsJson,
                 sectionsJson, summaryText, inputTranscriptLength, inputDurationSeconds,
                 promptVersion, provider, model, errorCode, errorMessage, createdAt, updatedAt, deletedAt,
                 documentTitle, oneLiner, documentBlocksJson)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(mediaId) DO UPDATE SET
                id = excluded.id,
                postId = excluded.postId,
                status = excluded.status,
                format = excluded.format,
                language = excluded.language,
                overview = excluded.overview,
                keyPointsJson = excluded.keyPointsJson,
                sectionsJson = excluded.sectionsJson,
                summaryText = excluded.summaryText,
                inputTranscriptLength = excluded.inputTranscriptLength,
                inputDurationSeconds = excluded.inputDurationSeconds,
                promptVersion = excluded.promptVersion,
                provider = excluded.provider,
                model = excluded.model,
                errorCode = excluded.errorCode,
                errorMessage = excluded.errorMessage,
                createdAt = excluded.createdAt,
                updatedAt = excluded.updatedAt,
                deletedAt = excluded.deletedAt,
                documentTitle = excluded.documentTitle,
                oneLiner = excluded.oneLiner,
                documentBlocksJson = excluded.documentBlocksJson
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(summary.id, to: 1, in: statement)
        try bind(summary.postId, to: 2, in: statement)
        try bind(summary.mediaId, to: 3, in: statement)
        try bind(summary.status, to: 4, in: statement)
        try bind(summary.format, to: 5, in: statement)
        try bind(summary.language, to: 6, in: statement)
        try bind(summary.overview, to: 7, in: statement)
        try bind(jsonString(summary.keyPoints), to: 8, in: statement)
        try bind(jsonString(summary.sections), to: 9, in: statement)
        try bind(summary.summaryText, to: 10, in: statement)
        try bind(summary.inputTranscriptLength, to: 11, in: statement)
        try bind(summary.inputDurationSeconds, to: 12, in: statement)
        try bind(summary.promptVersion, to: 13, in: statement)
        try bind(summary.provider, to: 14, in: statement)
        try bind(summary.model, to: 15, in: statement)
        try bind(summary.errorCode, to: 16, in: statement)
        try bind(summary.errorMessage, to: 17, in: statement)
        try bind(summary.createdAt, to: 18, in: statement)
        try bind(summary.updatedAt, to: 19, in: statement)
        try bind(summary.deletedAt, to: 20, in: statement)
        try bind(summary.documentTitle, to: 21, in: statement)
        try bind(summary.oneLiner, to: 22, in: statement)
        try bind(jsonString(summary.documentBlocks), to: 23, in: statement)
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
            SELECT id, text, isFavorite, aiTagProcessedAt, tagsUserEditedAt, occurredAt,
                   localCreatedAt, localUpdatedAt, localEditedAt, serverVersion, syncStatus, deletedAt
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
                aiTagProcessedAt: try optionalDate(statement, 3),
                tagsUserEditedAt: try optionalDate(statement, 4),
                occurredAt: try date(statement, 5),
                localCreatedAt: try date(statement, 6),
                localUpdatedAt: try date(statement, 7),
                localEditedAt: try optionalDate(statement, 8),
                serverVersion: optionalInt(statement, 9),
                syncStatus: try text(statement, 10),
                deletedAt: try optionalDate(statement, 11)
            )
        }

        return nil
    }

    func fetchMedia(id: String) throws -> TimelineMedia? {
        let statement = try prepare(
            """
            SELECT id, postId, kind, localCompressedPath, localOriginalStagingPath, localThumbnailPath,
                   remoteCompressedPath, remoteOriginalPath, remoteThumbnailPath, originalPreserved,
                   uploadStatus, mimeType, durationSeconds, transcriptionText, transcriptionStatus,
                   transcriptionError, transcriptionUpdatedAt, sortOrder, checksum, createdAt, updatedAt
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

    func fetchComment(id: String) throws -> TimelineComment? {
        let statement = try prepare(
            """
            SELECT id, postId, text, createdAt, updatedAt, serverVersion, deletedAt
            FROM local_comments
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(id, to: 1, in: statement)

        if sqlite3_step(statement) == SQLITE_ROW {
            return try timelineComment(statement)
        }

        return nil
    }

    func fetchAISummary(id: String) throws -> TimelineAISummary? {
        let statement = try prepare(
            """
            SELECT id, postId, mediaId, status, format, language, overview, keyPointsJson,
                   sectionsJson, summaryText, inputTranscriptLength, inputDurationSeconds,
                   promptVersion, provider, model, errorCode, errorMessage, createdAt, updatedAt, deletedAt,
                   documentTitle, oneLiner, documentBlocksJson
            FROM local_ai_summaries
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(id, to: 1, in: statement)

        if sqlite3_step(statement) == SQLITE_ROW {
            return try timelineAISummary(statement)
        }

        return nil
    }

    func fetchAISummary(mediaId: String) throws -> TimelineAISummary? {
        let statement = try prepare(
            """
            SELECT id, postId, mediaId, status, format, language, overview, keyPointsJson,
                   sectionsJson, summaryText, inputTranscriptLength, inputDurationSeconds,
                   promptVersion, provider, model, errorCode, errorMessage, createdAt, updatedAt, deletedAt,
                   documentTitle, oneLiner, documentBlocksJson
            FROM local_ai_summaries
            WHERE mediaId = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(mediaId, to: 1, in: statement)

        if sqlite3_step(statement) == SQLITE_ROW {
            return try timelineAISummary(statement)
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

    func fetchPendingCreateCommentOperation(commentId: String) throws -> OutboxOperation? {
        let statement = try prepare(
            """
            SELECT id, opId, type, entityType, entityId, payloadJson, status, attemptCount,
                   lastError, createdAt, updatedAt, sentAt
            FROM outbox_operations
            WHERE entityType = 'comment'
              AND entityId = ?
              AND type = 'create_comment'
              AND status = 'pending'
              AND sentAt IS NULL
            ORDER BY createdAt ASC
            LIMIT 1
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(commentId, to: 1, in: statement)

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

    func deleteOperation(id: String) throws {
        let statement = try prepare("DELETE FROM outbox_operations WHERE id = ?")
        defer {
            sqlite3_finalize(statement)
        }

        try bind(id, to: 1, in: statement)
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
            kind: try text(statement, 2),
            localCompressedPath: try localFilePath(statement, 3),
            localOriginalStagingPath: try optionalLocalFilePath(statement, 4),
            localThumbnailPath: try optionalLocalFilePath(statement, 5),
            remoteCompressedPath: optionalText(statement, 6),
            remoteOriginalPath: optionalText(statement, 7),
            remoteThumbnailPath: optionalText(statement, 8),
            originalPreserved: sqlite3_column_int(statement, 9) == 1,
            uploadStatus: try text(statement, 10),
            mimeType: optionalText(statement, 11),
            durationSeconds: optionalDouble(statement, 12),
            transcriptionText: optionalText(statement, 13),
            transcriptionStatus: optionalText(statement, 14) ?? "not_requested",
            transcriptionError: optionalText(statement, 15),
            transcriptionUpdatedAt: try optionalDate(statement, 16),
            sortOrder: Int(sqlite3_column_int64(statement, 17)),
            checksum: optionalText(statement, 18),
            createdAt: try date(statement, 19),
            updatedAt: try date(statement, 20)
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

    func timelineComment(_ statement: OpaquePointer) throws -> TimelineComment {
        TimelineComment(
            id: try text(statement, 0),
            postId: try text(statement, 1),
            text: try text(statement, 2),
            createdAt: try date(statement, 3),
            updatedAt: try date(statement, 4),
            serverVersion: optionalInt(statement, 5),
            deletedAt: try optionalDate(statement, 6)
        )
    }

    func timelineAISummary(_ statement: OpaquePointer) throws -> TimelineAISummary {
        TimelineAISummary(
            id: try text(statement, 0),
            postId: try text(statement, 1),
            mediaId: try text(statement, 2),
            status: try text(statement, 3),
            format: optionalText(statement, 4),
            language: optionalText(statement, 5),
            overview: optionalText(statement, 6),
            keyPoints: decodeJSONStringArray(optionalText(statement, 7)),
            sections: decodeSummarySections(optionalText(statement, 8)),
            summaryText: optionalText(statement, 9),
            documentTitle: optionalText(statement, 20),
            oneLiner: optionalText(statement, 21),
            documentBlocks: decodeSummaryBlocks(optionalText(statement, 22)),
            inputTranscriptLength: optionalInt(statement, 10),
            inputDurationSeconds: optionalDouble(statement, 11),
            promptVersion: optionalText(statement, 12) ?? "media-summary-v1",
            provider: optionalText(statement, 13),
            model: optionalText(statement, 14),
            errorCode: optionalText(statement, 15),
            errorMessage: optionalText(statement, 16),
            createdAt: try date(statement, 17),
            updatedAt: try date(statement, 18),
            deletedAt: try optionalDate(statement, 19)
        )
    }

    func timelineTag(_ statement: OpaquePointer, offset: Int = 0) throws -> TimelineTag {
        TimelineTag(
            id: try text(statement, Int32(offset)),
            type: try text(statement, Int32(offset + 1)),
            name: try text(statement, Int32(offset + 2)),
            normalizedName: try text(statement, Int32(offset + 3)),
            colorHex: optionalText(statement, Int32(offset + 4)),
            isDefault: sqlite3_column_int(statement, Int32(offset + 5)) == 1,
            isArchived: sqlite3_column_int(statement, Int32(offset + 6)) == 1,
            aiUsableAsPrimary: sqlite3_column_int(statement, Int32(offset + 7)) == 1,
            createdAt: try date(statement, Int32(offset + 8)),
            updatedAt: try date(statement, Int32(offset + 9)),
            archivedAt: try optionalDate(statement, Int32(offset + 10))
        )
    }

    func timelineTagAlias(_ statement: OpaquePointer, offset: Int = 0) throws -> TimelineTagAlias {
        TimelineTagAlias(
            id: try text(statement, Int32(offset)),
            tagId: try text(statement, Int32(offset + 1)),
            alias: try text(statement, Int32(offset + 2)),
            normalizedAlias: try text(statement, Int32(offset + 3)),
            createdAt: try date(statement, Int32(offset + 4)),
            deletedAt: try optionalDate(statement, Int32(offset + 5))
        )
    }

    func timelineAssignedTag(_ statement: OpaquePointer) throws -> TimelineAssignedTag {
        TimelineAssignedTag(
            id: try text(statement, 0),
            postId: try text(statement, 1),
            tagId: try text(statement, 2),
            role: try text(statement, 3),
            source: try text(statement, 4),
            confidence: optionalDouble(statement, 5),
            aiSummaryId: optionalText(statement, 6),
            createdAt: try date(statement, 7),
            updatedAt: try date(statement, 8),
            deletedAt: try optionalDate(statement, 9),
            tag: try timelineTag(statement, offset: 10)
        )
    }

    private func collectTags(_ statement: OpaquePointer) throws -> [TimelineTag] {
        var tags: [TimelineTag] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            tags.append(try timelineTag(statement))
        }

        return tags
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeJSONStringArray(_ value: String?) -> [String] {
        guard let value,
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return decoded
    }

    private func decodeSummarySections(_ value: String?) -> [TimelineAISummarySection] {
        guard let value,
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([TimelineAISummarySection].self, from: data) else {
            return []
        }

        return decoded
    }

    private func decodeSummaryBlocks(_ value: String?) -> [TimelineAISummaryBlock] {
        guard let value,
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([TimelineAISummaryBlock].self, from: data) else {
            return []
        }

        return decoded
    }
}
