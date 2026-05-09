import Foundation
import SQLite3

extension LocalDatabase {
    func configure() throws {
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
    }

    func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS local_posts (
                id TEXT PRIMARY KEY,
                text TEXT NOT NULL,
                isFavorite INTEGER NOT NULL DEFAULT 0,
                isPinned INTEGER NOT NULL DEFAULT 0,
                pinnedAt TEXT,
                aiTagProcessedAt TEXT,
                tagsUserEditedAt TEXT,
                occurredAt TEXT NOT NULL,
                localCreatedAt TEXT NOT NULL,
                localUpdatedAt TEXT NOT NULL,
                localEditedAt TEXT,
                serverVersion INTEGER,
                syncStatus TEXT NOT NULL,
                deletedAt TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_local_posts_occurredAt ON local_posts(occurredAt);
            CREATE INDEX IF NOT EXISTS idx_local_posts_deletedAt ON local_posts(deletedAt);

            CREATE TABLE IF NOT EXISTS local_media (
                id TEXT PRIMARY KEY,
                postId TEXT NOT NULL REFERENCES local_posts(id) ON DELETE CASCADE,
                kind TEXT NOT NULL DEFAULT 'image',
                localCompressedPath TEXT NOT NULL,
                localOriginalStagingPath TEXT,
                localThumbnailPath TEXT,
                remoteCompressedPath TEXT,
                remoteOriginalPath TEXT,
                remoteThumbnailPath TEXT,
                originalPreserved INTEGER NOT NULL,
                uploadStatus TEXT NOT NULL,
                uploadError TEXT,
                mimeType TEXT,
                durationSeconds REAL,
                transcriptionText TEXT,
                transcriptionStatus TEXT NOT NULL DEFAULT 'not_requested',
                transcriptionError TEXT,
                transcriptionUpdatedAt TEXT,
                sortOrder INTEGER NOT NULL,
                checksum TEXT,
                createdAt TEXT NOT NULL,
                updatedAt TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_local_media_postId ON local_media(postId);

            CREATE TABLE IF NOT EXISTS local_comments (
                id TEXT PRIMARY KEY,
                postId TEXT NOT NULL REFERENCES local_posts(id) ON DELETE CASCADE,
                text TEXT NOT NULL,
                createdAt TEXT NOT NULL,
                updatedAt TEXT NOT NULL,
                serverVersion INTEGER,
                syncStatus TEXT NOT NULL DEFAULT 'synced',
                deletedAt TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_local_comments_postId ON local_comments(postId);
            CREATE INDEX IF NOT EXISTS idx_local_comments_deletedAt ON local_comments(deletedAt);

            CREATE TABLE IF NOT EXISTS local_ai_summaries (
                id TEXT PRIMARY KEY,
                postId TEXT NOT NULL REFERENCES local_posts(id) ON DELETE CASCADE,
                mediaId TEXT NOT NULL UNIQUE,
                status TEXT NOT NULL,
                format TEXT,
                language TEXT,
                overview TEXT,
                keyPointsJson TEXT NOT NULL DEFAULT '[]',
                sectionsJson TEXT NOT NULL DEFAULT '[]',
                summaryText TEXT,
                documentTitle TEXT,
                oneLiner TEXT,
                documentBlocksJson TEXT NOT NULL DEFAULT '[]',
                inputTranscriptLength INTEGER,
                inputDurationSeconds REAL,
                promptVersion TEXT NOT NULL,
                provider TEXT,
                model TEXT,
                errorCode TEXT,
                errorMessage TEXT,
                createdAt TEXT NOT NULL,
                updatedAt TEXT NOT NULL,
                deletedAt TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_local_ai_summaries_postId ON local_ai_summaries(postId);
            CREATE INDEX IF NOT EXISTS idx_local_ai_summaries_mediaId ON local_ai_summaries(mediaId);
            CREATE INDEX IF NOT EXISTS idx_local_ai_summaries_deletedAt ON local_ai_summaries(deletedAt);

            CREATE TABLE IF NOT EXISTS local_tags (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                name TEXT NOT NULL,
                normalizedName TEXT NOT NULL UNIQUE,
                colorHex TEXT,
                isDefault INTEGER NOT NULL DEFAULT 0,
                isArchived INTEGER NOT NULL DEFAULT 0,
                aiUsableAsPrimary INTEGER NOT NULL DEFAULT 0,
                createdAt TEXT NOT NULL,
                updatedAt TEXT NOT NULL,
                archivedAt TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_local_tags_type ON local_tags(type);
            CREATE INDEX IF NOT EXISTS idx_local_tags_isArchived ON local_tags(isArchived);

            CREATE TABLE IF NOT EXISTS local_tag_aliases (
                id TEXT PRIMARY KEY,
                tagId TEXT NOT NULL REFERENCES local_tags(id) ON DELETE CASCADE,
                alias TEXT NOT NULL,
                normalizedAlias TEXT NOT NULL UNIQUE,
                createdAt TEXT NOT NULL,
                deletedAt TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_local_tag_aliases_tagId ON local_tag_aliases(tagId);

            CREATE TABLE IF NOT EXISTS local_post_tags (
                id TEXT PRIMARY KEY,
                postId TEXT NOT NULL REFERENCES local_posts(id) ON DELETE CASCADE,
                tagId TEXT NOT NULL REFERENCES local_tags(id) ON DELETE CASCADE,
                role TEXT NOT NULL,
                source TEXT NOT NULL,
                confidence REAL,
                aiSummaryId TEXT,
                createdAt TEXT NOT NULL,
                updatedAt TEXT NOT NULL,
                deletedAt TEXT,
                UNIQUE(postId, tagId)
            );

            CREATE INDEX IF NOT EXISTS idx_local_post_tags_postId ON local_post_tags(postId);
            CREATE INDEX IF NOT EXISTS idx_local_post_tags_tagId ON local_post_tags(tagId);
            CREATE INDEX IF NOT EXISTS idx_local_post_tags_role ON local_post_tags(role);

            CREATE TABLE IF NOT EXISTS local_checkin_items (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                symbolName TEXT NOT NULL,
                colorHex TEXT NOT NULL,
                recordMode TEXT NOT NULL,
                timeVisualization TEXT NOT NULL DEFAULT 'none',
                activeWeekdays TEXT NOT NULL,
                sortOrder INTEGER NOT NULL,
                defaultShowInTimeline INTEGER NOT NULL DEFAULT 0,
                tagId TEXT REFERENCES local_tags(id) ON DELETE SET NULL,
                createdAt TEXT NOT NULL,
                updatedAt TEXT NOT NULL,
                archivedAt TEXT,
                deletedAt TEXT,
                syncStatus TEXT NOT NULL DEFAULT 'synced'
            );

            CREATE INDEX IF NOT EXISTS idx_local_checkin_items_sortOrder ON local_checkin_items(sortOrder);
            CREATE INDEX IF NOT EXISTS idx_local_checkin_items_deletedAt ON local_checkin_items(deletedAt);
            CREATE INDEX IF NOT EXISTS idx_local_checkin_items_archivedAt ON local_checkin_items(archivedAt);

            CREATE TABLE IF NOT EXISTS local_checkin_entries (
                id TEXT PRIMARY KEY,
                itemId TEXT NOT NULL REFERENCES local_checkin_items(id) ON DELETE CASCADE,
                occurredAt TEXT NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                showInTimeline INTEGER NOT NULL DEFAULT 0,
                createdAt TEXT NOT NULL,
                updatedAt TEXT NOT NULL,
                deletedAt TEXT,
                syncStatus TEXT NOT NULL DEFAULT 'synced'
            );

            CREATE INDEX IF NOT EXISTS idx_local_checkin_entries_itemId ON local_checkin_entries(itemId);
            CREATE INDEX IF NOT EXISTS idx_local_checkin_entries_occurredAt ON local_checkin_entries(occurredAt);
            CREATE INDEX IF NOT EXISTS idx_local_checkin_entries_deletedAt ON local_checkin_entries(deletedAt);

            CREATE TABLE IF NOT EXISTS local_checkin_media (
                id TEXT PRIMARY KEY,
                entryId TEXT NOT NULL REFERENCES local_checkin_entries(id) ON DELETE CASCADE,
                kind TEXT NOT NULL DEFAULT 'image',
                localCompressedPath TEXT NOT NULL,
                remoteCompressedPath TEXT,
                uploadStatus TEXT NOT NULL,
                uploadError TEXT,
                mimeType TEXT,
                sortOrder INTEGER NOT NULL,
                checksum TEXT,
                createdAt TEXT NOT NULL,
                updatedAt TEXT NOT NULL,
                deletedAt TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_local_checkin_media_entryId ON local_checkin_media(entryId);
            CREATE INDEX IF NOT EXISTS idx_local_checkin_media_uploadStatus ON local_checkin_media(uploadStatus);
            CREATE INDEX IF NOT EXISTS idx_local_checkin_media_deletedAt ON local_checkin_media(deletedAt);

            CREATE TABLE IF NOT EXISTS outbox_operations (
                id TEXT PRIMARY KEY,
                opId TEXT NOT NULL UNIQUE,
                type TEXT NOT NULL,
                entityType TEXT NOT NULL,
                entityId TEXT NOT NULL,
                payloadJson TEXT NOT NULL,
                status TEXT NOT NULL,
                attemptCount INTEGER NOT NULL,
                lastError TEXT,
                createdAt TEXT NOT NULL,
                updatedAt TEXT NOT NULL,
                sentAt TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_outbox_operations_entityId ON outbox_operations(entityId);
            CREATE INDEX IF NOT EXISTS idx_outbox_operations_status ON outbox_operations(status);
            """
        )

        try addColumnIfNeeded(table: "local_posts", column: "localEditedAt", definition: "TEXT")
        try addColumnIfNeeded(table: "local_posts", column: "isFavorite", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(table: "local_posts", column: "isPinned", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(table: "local_posts", column: "pinnedAt", definition: "TEXT")
        try addColumnIfNeeded(table: "local_posts", column: "aiTagProcessedAt", definition: "TEXT")
        try addColumnIfNeeded(table: "local_posts", column: "tagsUserEditedAt", definition: "TEXT")
        try addColumnIfNeeded(table: "local_media", column: "kind", definition: "TEXT NOT NULL DEFAULT 'image'")
        try addColumnIfNeeded(table: "local_media", column: "localThumbnailPath", definition: "TEXT")
        try addColumnIfNeeded(table: "local_media", column: "remoteThumbnailPath", definition: "TEXT")
        try addColumnIfNeeded(table: "local_media", column: "mimeType", definition: "TEXT")
        try addColumnIfNeeded(table: "local_media", column: "durationSeconds", definition: "REAL")
        try addColumnIfNeeded(table: "local_media", column: "transcriptionText", definition: "TEXT")
        try addColumnIfNeeded(table: "local_media", column: "transcriptionStatus", definition: "TEXT NOT NULL DEFAULT 'not_requested'")
        try addColumnIfNeeded(table: "local_media", column: "transcriptionError", definition: "TEXT")
        try addColumnIfNeeded(table: "local_media", column: "transcriptionUpdatedAt", definition: "TEXT")
        try addColumnIfNeeded(table: "local_media", column: "uploadError", definition: "TEXT")
        try addColumnIfNeeded(table: "local_media", column: "deletedAt", definition: "TEXT")
        try addColumnIfNeeded(table: "local_comments", column: "syncStatus", definition: "TEXT NOT NULL DEFAULT 'synced'")
        try addColumnIfNeeded(table: "local_ai_summaries", column: "documentTitle", definition: "TEXT")
        try addColumnIfNeeded(table: "local_ai_summaries", column: "oneLiner", definition: "TEXT")
        try addColumnIfNeeded(table: "local_ai_summaries", column: "documentBlocksJson", definition: "TEXT NOT NULL DEFAULT '[]'")
        try addColumnIfNeeded(table: "local_checkin_items", column: "timeVisualization", definition: "TEXT NOT NULL DEFAULT 'none'")
        try execute("CREATE INDEX IF NOT EXISTS idx_local_media_deletedAt ON local_media(deletedAt)")
        try seedDefaultTags()
    }

    func seedDefaultTags() throws {
        let now = Date()
        let tags: [(id: String, name: String, color: String)] = [
            ("tag-primary-diary", "日记", "#D7E3F4"),
            ("tag-primary-idea", "想法", "#E3DCF4"),
            ("tag-primary-learning", "学习整理", "#DDEBD8"),
            ("tag-primary-emotion", "情绪", "#F4DEE4"),
            ("tag-primary-casual", "碎碎念", "#E7E2DA"),
            ("tag-primary-review", "复盘", "#F0E4D4"),
        ]

        for tag in tags {
            let statement = try prepare(
                """
                INSERT INTO local_tags
                    (id, type, name, normalizedName, colorHex, isDefault, isArchived, aiUsableAsPrimary, createdAt, updatedAt, archivedAt)
                VALUES (?, 'primary', ?, ?, ?, 1, 0, 1, ?, ?, NULL)
                ON CONFLICT(id) DO UPDATE SET
                    type = 'primary',
                    name = excluded.name,
                    normalizedName = excluded.normalizedName,
                    isDefault = 1,
                    isArchived = 0,
                    aiUsableAsPrimary = 1,
                    updatedAt = excluded.updatedAt,
                    archivedAt = NULL
                """
            )
            defer {
                sqlite3_finalize(statement)
            }

            try bind(tag.id, to: 1, in: statement)
            try bind(tag.name, to: 2, in: statement)
            try bind(Self.normalizedTagName(tag.name), to: 3, in: statement)
            try bind(tag.color, to: 4, in: statement)
            try bind(now, to: 5, in: statement)
            try bind(now, to: 6, in: statement)
            try stepDone(statement)
        }
    }

    static func normalizedTagName(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }


    func addColumnIfNeeded(table: String, column: String, definition: String) throws {
        guard try !columnExists(table: table, column: column) else {
            return
        }

        try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }

    func columnExists(table: String, column: String) throws -> Bool {
        let statement = try prepare("PRAGMA table_info(\(table))")
        defer {
            sqlite3_finalize(statement)
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            if optionalText(statement, 1) == column {
                return true
            }
        }

        return false
    }

    func normalizeStoredMediaPaths() throws {
        var updates: [(id: String, compressedPath: String, originalStagingPath: String?, thumbnailPath: String?)] = []

        do {
            let statement = try prepare(
                """
                SELECT id, localCompressedPath, localOriginalStagingPath, localThumbnailPath
                FROM local_media
                """
            )
            defer {
                sqlite3_finalize(statement)
            }

            while true {
                let result = sqlite3_step(statement)

                if result == SQLITE_DONE {
                    break
                }

                guard result == SQLITE_ROW else {
                    throw LocalDatabaseError.sqlite(errorMessage)
                }

                let id = try text(statement, 0)
                let compressedPath = try text(statement, 1)
                let originalStagingPath = optionalText(statement, 2)
                let thumbnailPath = optionalText(statement, 3)
                let normalizedCompressedPath = try AppDirectories.storedPath(forLocalPath: compressedPath)
                let normalizedOriginalStagingPath = try storedLocalPath(originalStagingPath)
                let normalizedThumbnailPath = try storedLocalPath(thumbnailPath)

                if compressedPath != normalizedCompressedPath ||
                    originalStagingPath != normalizedOriginalStagingPath ||
                    thumbnailPath != normalizedThumbnailPath {
                    updates.append(
                        (
                            id: id,
                            compressedPath: normalizedCompressedPath,
                            originalStagingPath: normalizedOriginalStagingPath,
                            thumbnailPath: normalizedThumbnailPath
                        )
                    )
                }
            }
        }

        guard !updates.isEmpty else {
            return
        }

        try transaction {
            for update in updates {
                try updateStoredMediaPath(
                    mediaId: update.id,
                    compressedPath: update.compressedPath,
                    originalStagingPath: update.originalStagingPath,
                    thumbnailPath: update.thumbnailPath
                )
            }
        }
    }

    func updateStoredMediaPath(
        mediaId: String,
        compressedPath: String,
        originalStagingPath: String?,
        thumbnailPath: String?
    ) throws {
        let statement = try prepare(
            """
            UPDATE local_media
            SET localCompressedPath = ?,
                localOriginalStagingPath = ?,
                localThumbnailPath = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(compressedPath, to: 1, in: statement)
        try bind(originalStagingPath, to: 2, in: statement)
        try bind(thumbnailPath, to: 3, in: statement)
        try bind(mediaId, to: 4, in: statement)
        try stepDone(statement)
    }
}
