import Foundation
import SQLite3

extension LocalDatabase {
    func saveTag(_ tag: TimelineTag, operation: OutboxOperation) throws {
        try transaction {
            try upsertTag(tag)
            try insert(operation)
        }
    }

    func saveTagAlias(_ alias: TimelineTagAlias, operation: OutboxOperation) throws {
        try transaction {
            try upsertTagAlias(alias)
            try insert(operation)
        }
    }

    func softDeleteTagAlias(_ alias: TimelineTagAlias, deletedAt: Date, operation: OutboxOperation) throws {
        var deletedAlias = alias
        deletedAlias.deletedAt = deletedAt

        try transaction {
            try upsertTagAlias(deletedAlias)
            try insert(operation)
        }
    }

    func archiveTag(_ tag: TimelineTag, archivedAt: Date, operation: OutboxOperation) throws {
        var archivedTag = tag
        archivedTag.isArchived = true
        archivedTag.archivedAt = archivedAt
        archivedTag.updatedAt = archivedAt

        try transaction {
            try upsertTag(archivedTag)
            try insert(operation)
        }
    }

    func restoreTag(_ tag: TimelineTag, restoredAt: Date, operation: OutboxOperation) throws {
        var restoredTag = tag
        restoredTag.isArchived = false
        restoredTag.archivedAt = nil
        restoredTag.updatedAt = restoredAt

        try transaction {
            try upsertTag(restoredTag)
            try insert(operation)
        }
    }

    func deleteArchivedTag(_ tag: TimelineTag, operation: OutboxOperation) throws {
        try transaction {
            try deleteTagRows(tagId: tag.id)
            try insert(operation)
        }
    }

    func applyTagDeleted(id: String) throws {
        try transaction {
            try deleteTagRows(tagId: id)
        }
    }

    func mergeTopicTag(
        sourceTag: TimelineTag,
        targetTag: TimelineTag,
        aliasName: String,
        aliasId: String,
        mergedAt: Date,
        operation: OutboxOperation
    ) throws {
        try transaction {
            let sourceAssignments = try activeAssignments(tagId: sourceTag.id)

            for assignment in sourceAssignments {
                if let existingTarget = try postTagRow(postId: assignment.postId, tagId: targetTag.id) {
                    let targetStatement = try prepare(
                        """
                        UPDATE local_post_tags
                        SET role = 'topic',
                            source = ?,
                            confidence = ?,
                            aiSummaryId = ?,
                            updatedAt = ?,
                            deletedAt = NULL
                        WHERE id = ?
                        """
                    )
                    defer {
                        sqlite3_finalize(targetStatement)
                    }

                    try bind(existingTarget.deletedAt == nil ? existingTarget.source : assignment.source, to: 1, in: targetStatement)
                    try bind(existingTarget.deletedAt == nil ? existingTarget.confidence : assignment.confidence, to: 2, in: targetStatement)
                    try bind(existingTarget.deletedAt == nil ? existingTarget.aiSummaryId : assignment.aiSummaryId, to: 3, in: targetStatement)
                    try bind(mergedAt, to: 4, in: targetStatement)
                    try bind(existingTarget.id, to: 5, in: targetStatement)
                    try stepDone(targetStatement)

                    let deleteSourceStatement = try prepare(
                        """
                        UPDATE local_post_tags
                        SET updatedAt = ?,
                            deletedAt = ?
                        WHERE id = ?
                        """
                    )
                    defer {
                        sqlite3_finalize(deleteSourceStatement)
                    }

                    try bind(mergedAt, to: 1, in: deleteSourceStatement)
                    try bind(mergedAt, to: 2, in: deleteSourceStatement)
                    try bind(assignment.id, to: 3, in: deleteSourceStatement)
                    try stepDone(deleteSourceStatement)
                    continue
                }

                let moveStatement = try prepare(
                    """
                    UPDATE local_post_tags
                    SET tagId = ?,
                        role = 'topic',
                        updatedAt = ?
                    WHERE id = ?
                    """
                )
                defer {
                    sqlite3_finalize(moveStatement)
                }

                try bind(targetTag.id, to: 1, in: moveStatement)
                try bind(mergedAt, to: 2, in: moveStatement)
                try bind(assignment.id, to: 3, in: moveStatement)
                try stepDone(moveStatement)
            }

            if !aliasName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try upsertTagAlias(
                    TimelineTagAlias(
                        id: aliasId,
                        tagId: targetTag.id,
                        alias: aliasName,
                        normalizedAlias: Self.normalizedTagName(aliasName),
                        createdAt: mergedAt,
                        deletedAt: nil
                    )
                )
            }

            var archivedSource = sourceTag
            archivedSource.isArchived = true
            archivedSource.archivedAt = mergedAt
            archivedSource.updatedAt = mergedAt
            try upsertTag(archivedSource)

            try insert(operation)
        }
    }

    private struct LocalPostTagRow {
        var id: String
        var postId: String
        var source: String
        var confidence: Double?
        var aiSummaryId: String?
        var deletedAt: Date?
    }

    private func activeAssignments(tagId: String) throws -> [LocalPostTagRow] {
        let statement = try prepare(
            """
            SELECT id, postId, source, confidence, aiSummaryId, deletedAt
            FROM local_post_tags
            WHERE tagId = ?
              AND deletedAt IS NULL
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(tagId, to: 1, in: statement)
        var rows: [LocalPostTagRow] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(
                LocalPostTagRow(
                    id: try text(statement, 0),
                    postId: try text(statement, 1),
                    source: try text(statement, 2),
                    confidence: optionalDouble(statement, 3),
                    aiSummaryId: optionalText(statement, 4),
                    deletedAt: try optionalDate(statement, 5)
                )
            )
        }

        return rows
    }

    private func postTagRow(postId: String, tagId: String) throws -> LocalPostTagRow? {
        let statement = try prepare(
            """
            SELECT id, postId, source, confidence, aiSummaryId, deletedAt
            FROM local_post_tags
            WHERE postId = ?
              AND tagId = ?
            LIMIT 1
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(postId, to: 1, in: statement)
        try bind(tagId, to: 2, in: statement)

        if sqlite3_step(statement) == SQLITE_ROW {
            return LocalPostTagRow(
                id: try text(statement, 0),
                postId: try text(statement, 1),
                source: try text(statement, 2),
                confidence: optionalDouble(statement, 3),
                aiSummaryId: optionalText(statement, 4),
                deletedAt: try optionalDate(statement, 5)
            )
        }

        return nil
    }

    private func deleteTagRows(tagId: String) throws {
        let deleteAssignments = try prepare("DELETE FROM local_post_tags WHERE tagId = ?")
        defer {
            sqlite3_finalize(deleteAssignments)
        }
        try bind(tagId, to: 1, in: deleteAssignments)
        try stepDone(deleteAssignments)

        let deleteAliases = try prepare("DELETE FROM local_tag_aliases WHERE tagId = ?")
        defer {
            sqlite3_finalize(deleteAliases)
        }
        try bind(tagId, to: 1, in: deleteAliases)
        try stepDone(deleteAliases)

        let deleteTag = try prepare("DELETE FROM local_tags WHERE id = ?")
        defer {
            sqlite3_finalize(deleteTag)
        }
        try bind(tagId, to: 1, in: deleteTag)
        try stepDone(deleteTag)
    }
}
