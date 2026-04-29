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
                localCompressedPath TEXT NOT NULL,
                localOriginalStagingPath TEXT,
                remoteCompressedPath TEXT,
                remoteOriginalPath TEXT,
                originalPreserved INTEGER NOT NULL,
                uploadStatus TEXT NOT NULL,
                uploadError TEXT,
                sortOrder INTEGER NOT NULL,
                checksum TEXT,
                createdAt TEXT NOT NULL,
                updatedAt TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_local_media_postId ON local_media(postId);

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
        try addColumnIfNeeded(table: "local_media", column: "uploadError", definition: "TEXT")
        try addColumnIfNeeded(table: "local_media", column: "deletedAt", definition: "TEXT")
        try execute("CREATE INDEX IF NOT EXISTS idx_local_media_deletedAt ON local_media(deletedAt)")
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
        var updates: [(id: String, compressedPath: String, originalStagingPath: String?)] = []

        do {
            let statement = try prepare(
                """
                SELECT id, localCompressedPath, localOriginalStagingPath
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
                let normalizedCompressedPath = try AppDirectories.storedPath(forLocalPath: compressedPath)
                let normalizedOriginalStagingPath = try storedLocalPath(originalStagingPath)

                if compressedPath != normalizedCompressedPath || originalStagingPath != normalizedOriginalStagingPath {
                    updates.append(
                        (
                            id: id,
                            compressedPath: normalizedCompressedPath,
                            originalStagingPath: normalizedOriginalStagingPath
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
                    originalStagingPath: update.originalStagingPath
                )
            }
        }
    }

    func updateStoredMediaPath(
        mediaId: String,
        compressedPath: String,
        originalStagingPath: String?
    ) throws {
        let statement = try prepare(
            """
            UPDATE local_media
            SET localCompressedPath = ?,
                localOriginalStagingPath = ?
            WHERE id = ?
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(compressedPath, to: 1, in: statement)
        try bind(originalStagingPath, to: 2, in: statement)
        try bind(mediaId, to: 3, in: statement)
        try stepDone(statement)
    }
}
