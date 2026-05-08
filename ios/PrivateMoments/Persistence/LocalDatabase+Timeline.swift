import Foundation
import SQLite3

extension LocalDatabase {
    func fetchTimelineItems() throws -> [TimelineItem] {
        let posts = try fetchPosts()

        return try posts.map { post in
            TimelineItem(
                post: post,
                media: try fetchMedia(postId: post.id),
                comments: try fetchComments(postId: post.id),
                aiSummaries: try fetchAISummaries(postId: post.id),
                tags: try fetchAssignedTags(postId: post.id)
            )
        }
    }

    func fetchTimelineItem(postId: String) throws -> TimelineItem? {
        guard let post = try fetchPost(id: postId), post.deletedAt == nil else {
            return nil
        }

        return TimelineItem(
            post: post,
            media: try fetchMedia(postId: post.id),
            comments: try fetchComments(postId: post.id),
            aiSummaries: try fetchAISummaries(postId: post.id),
            tags: try fetchAssignedTags(postId: post.id)
        )
    }

    func insertPost(_ post: TimelinePost, media: [TimelineMedia], operation: OutboxOperation, primaryTagId: String? = nil) throws {
        try transaction {
            try insert(post)

            for item in media {
                try insert(item)
            }

            if let primaryTagId,
               let tag = try fetchTag(id: primaryTagId) {
                try upsertAssignedTag(
                    TimelineAssignedTag(
                        id: UUID().uuidString,
                        postId: post.id,
                        tagId: primaryTagId,
                        role: "primary",
                        source: "manual",
                        confidence: nil,
                        aiSummaryId: nil,
                        createdAt: post.localCreatedAt,
                        updatedAt: post.localCreatedAt,
                        deletedAt: nil,
                        tag: tag
                    )
                )
            }

            try insert(operation)
        }
    }

    func softDeletePost(postId: String, deletedAt: Date, operation: OutboxOperation) throws {
        try transaction {
            let statement = try prepare(
                """
                UPDATE local_posts
                SET deletedAt = ?,
                    syncStatus = 'pending',
                    localUpdatedAt = ?
                WHERE id = ?
                """
            )
            defer {
                sqlite3_finalize(statement)
            }

            try bind(deletedAt, to: 1, in: statement)
            try bind(deletedAt, to: 2, in: statement)
            try bind(postId, to: 3, in: statement)
            try stepDone(statement)
            try softDeleteComments(postId: postId, deletedAt: deletedAt)
            try insert(operation)
        }
    }

    func updateFavorite(postId: String, isFavorite: Bool, updatedAt: Date, operation: OutboxOperation) throws {
        try transaction {
            let statement = try prepare(
                """
                UPDATE local_posts
                SET isFavorite = ?,
                    syncStatus = 'pending',
                    localUpdatedAt = ?
                WHERE id = ?
                """
            )
            defer {
                sqlite3_finalize(statement)
            }

            try bind(isFavorite ? 1 : 0, to: 1, in: statement)
            try bind(updatedAt, to: 2, in: statement)
            try bind(postId, to: 3, in: statement)
            try stepDone(statement)
            try insert(operation)
        }
    }

    func updatePinned(
        postId: String,
        isPinned: Bool,
        pinnedAt: Date?,
        updatedAt: Date,
        operation: OutboxOperation
    ) throws {
        try transaction {
            let statement = try prepare(
                """
                UPDATE local_posts
                SET isPinned = ?,
                    pinnedAt = ?,
                    syncStatus = 'pending',
                    localUpdatedAt = ?
                WHERE id = ?
                  AND deletedAt IS NULL
                """
            )
            defer {
                sqlite3_finalize(statement)
            }

            try bind(isPinned ? 1 : 0, to: 1, in: statement)
            try bind(isPinned ? pinnedAt : nil, to: 2, in: statement)
            try bind(updatedAt, to: 3, in: statement)
            try bind(postId, to: 4, in: statement)
            try stepDone(statement)

            guard sqlite3_changes(handle) > 0 else {
                return
            }

            try insert(operation)
        }
    }

    func updatePost(
        postId: String,
        text: String,
        occurredAt: Date,
        localEditedAt: Date,
        finalMedia: [TimelineMedia],
        operation: OutboxOperation
    ) throws {
        try transaction {
            let existingMedia = try fetchMedia(postId: postId)
            let finalMediaIds = Set(finalMedia.map(\.id))

            let statement = try prepare(
                """
                UPDATE local_posts
                SET text = ?,
                    occurredAt = ?,
                    localUpdatedAt = ?,
                    localEditedAt = ?,
                    syncStatus = 'pending'
                WHERE id = ?
                """
            )
            defer {
                sqlite3_finalize(statement)
            }

            try bind(text, to: 1, in: statement)
            try bind(occurredAt, to: 2, in: statement)
            try bind(localEditedAt, to: 3, in: statement)
            try bind(localEditedAt, to: 4, in: statement)
            try bind(postId, to: 5, in: statement)
            try stepDone(statement)

            try supersedeFailedOperations(entityId: postId, updatedAt: localEditedAt)

            for media in existingMedia where !finalMediaIds.contains(media.id) {
                try softDeleteMedia(mediaId: media.id, deletedAt: localEditedAt)
            }

            let existingMediaIds = Set(existingMedia.map(\.id))
            for media in finalMedia {
                if existingMediaIds.contains(media.id) {
                    try updateMediaSortOrder(mediaId: media.id, sortOrder: media.sortOrder, updatedAt: localEditedAt)
                } else {
                    try insert(media)
                }
            }

            try insert(operation)
        }
    }

    func insertAITitle(
        postId: String,
        text: String,
        updatedAt: Date,
        operation: OutboxOperation
    ) throws {
        try transaction {
            let statement = try prepare(
                """
                UPDATE local_posts
                SET text = ?,
                    localUpdatedAt = ?,
                    syncStatus = 'pending'
                WHERE id = ?
                  AND deletedAt IS NULL
                """
            )
            defer {
                sqlite3_finalize(statement)
            }

            try bind(text, to: 1, in: statement)
            try bind(updatedAt, to: 2, in: statement)
            try bind(postId, to: 3, in: statement)
            try stepDone(statement)

            guard sqlite3_changes(handle) > 0 else {
                return
            }

            try insert(operation)
        }
    }

    func insertComment(_ comment: TimelineComment, operation: OutboxOperation) throws {
        try transaction {
            try insert(comment, syncStatus: "pending")
            try insert(operation)
        }
    }

    func softDeleteComment(comment: TimelineComment, deletedAt: Date, operation: OutboxOperation) throws {
        try transaction {
            if let pendingCreate = try fetchPendingCreateCommentOperation(commentId: comment.id) {
                try deleteOperation(id: pendingCreate.id)
                try softDeleteCommentOnly(commentId: comment.id, deletedAt: deletedAt)
                return
            }

            try softDeleteCommentOnly(commentId: comment.id, deletedAt: deletedAt)
            try insert(operation)
        }
    }

    func softDeleteCommentOnly(commentId: String, deletedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE local_comments
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
        try bind(commentId, to: 3, in: statement)
        try stepDone(statement)
    }

    func softDeleteComments(postId: String, deletedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE local_comments
            SET deletedAt = ?,
                updatedAt = ?,
                syncStatus = 'pending'
            WHERE postId = ?
              AND deletedAt IS NULL
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(deletedAt, to: 1, in: statement)
        try bind(deletedAt, to: 2, in: statement)
        try bind(postId, to: 3, in: statement)
        try stepDone(statement)
    }

    func setPostTags(
        postId: String,
        primaryTagId: String?,
        topicTagIds: [String],
        updatedAt: Date,
        operation: OutboxOperation
    ) throws {
        try transaction {
            let existing = try fetchAssignedTags(postId: postId)
            let desiredTagIds = Set(([primaryTagId].compactMap { $0 }) + topicTagIds)

            for assignedTag in existing where !desiredTagIds.contains(assignedTag.tagId) {
                let statement = try prepare(
                    """
                    UPDATE local_post_tags
                    SET deletedAt = ?,
                        updatedAt = ?
                    WHERE id = ?
                    """
                )
                defer {
                    sqlite3_finalize(statement)
                }

                try bind(updatedAt, to: 1, in: statement)
                try bind(updatedAt, to: 2, in: statement)
                try bind(assignedTag.id, to: 3, in: statement)
                try stepDone(statement)
            }

            if let primaryTagId,
               let tag = try fetchTag(id: primaryTagId) {
                try upsertAssignedTag(
                    TimelineAssignedTag(
                        id: existing.first { $0.tagId == primaryTagId }?.id ?? UUID().uuidString,
                        postId: postId,
                        tagId: primaryTagId,
                        role: "primary",
                        source: "manual",
                        confidence: nil,
                        aiSummaryId: nil,
                        createdAt: existing.first { $0.tagId == primaryTagId }?.createdAt ?? updatedAt,
                        updatedAt: updatedAt,
                        deletedAt: nil,
                        tag: tag
                    )
                )
            }

            for topicTagId in topicTagIds {
                guard let tag = try fetchTag(id: topicTagId) else {
                    continue
                }

                try upsertAssignedTag(
                    TimelineAssignedTag(
                        id: existing.first { $0.tagId == topicTagId }?.id ?? UUID().uuidString,
                        postId: postId,
                        tagId: topicTagId,
                        role: "topic",
                        source: "manual",
                        confidence: nil,
                        aiSummaryId: nil,
                        createdAt: existing.first { $0.tagId == topicTagId }?.createdAt ?? updatedAt,
                        updatedAt: updatedAt,
                        deletedAt: nil,
                        tag: tag
                    )
                )
            }

            let postStatement = try prepare(
                """
                UPDATE local_posts
                SET tagsUserEditedAt = ?,
                    localUpdatedAt = ?,
                    syncStatus = 'pending'
                WHERE id = ?
                """
            )
            defer {
                sqlite3_finalize(postStatement)
            }

            try bind(updatedAt, to: 1, in: postStatement)
            try bind(updatedAt, to: 2, in: postStatement)
            try bind(postId, to: 3, in: postStatement)
            try stepDone(postStatement)

            try insert(operation)
        }
    }
}
