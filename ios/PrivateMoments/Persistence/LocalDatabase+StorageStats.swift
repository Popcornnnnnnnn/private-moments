import Foundation

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
}
