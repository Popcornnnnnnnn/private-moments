import Foundation
import SQLite3

extension LocalDatabase {
    func uploadCount(status: String) throws -> Int {
        try count(
            """
            SELECT COUNT(*)
            FROM local_media m
            JOIN local_posts p ON p.id = m.postId
            WHERE m.uploadStatus = ?
              AND m.deletedAt IS NULL
              AND p.deletedAt IS NULL
            """
        ) { statement in
            try self.bind(status, to: 1, in: statement)
        }
    }

    func downloadedAudioVideoCacheBytes() throws -> Int64 {
        try downloadedAudioVideoCachePaths().reduce(Int64(0)) { total, path in
            let localPath = (try? AppDirectories.localFilePath(fromStoredPath: path)) ?? path
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: localPath),
                  let size = attributes[.size] as? NSNumber else {
                return total
            }

            return total + size.int64Value
        }
    }

    func clearDownloadedAudioVideoCache() throws -> Int {
        let paths = try downloadedAudioVideoCachePaths()

        for path in paths {
            let localPath = (try? AppDirectories.localFilePath(fromStoredPath: path)) ?? path
            try? FileManager.default.removeItem(atPath: localPath)
        }

        guard !paths.isEmpty else {
            return 0
        }

        let statement = try prepare(
            """
            UPDATE local_media
            SET localCompressedPath = '',
                updatedAt = ?
            WHERE kind IN ('audio', 'video')
              AND remoteCompressedPath IS NOT NULL
              AND localCompressedPath <> ''
              AND uploadStatus = 'uploaded'
              AND deletedAt IS NULL
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        try bind(Date(), to: 1, in: statement)
        try stepDone(statement)
        return paths.count
    }

    private func downloadedAudioVideoCachePaths() throws -> [String] {
        let statement = try prepare(
            """
            SELECT localCompressedPath
            FROM local_media
            WHERE kind IN ('audio', 'video')
              AND remoteCompressedPath IS NOT NULL
              AND localCompressedPath <> ''
              AND uploadStatus = 'uploaded'
              AND deletedAt IS NULL
            """
        )
        defer {
            sqlite3_finalize(statement)
        }

        var paths: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            paths.append(try text(statement, 0))
        }

        return paths
    }
}
