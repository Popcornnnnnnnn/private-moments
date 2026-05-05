import Foundation

struct LocalStorageStats: Equatable {
    let totalBytes: Int64
    let databaseBytes: Int64
    let mediaBytes: Int64
    let audioVideoCacheBytes: Int64
    let pendingChanges: Int
    let pendingUploads: Int
    let failedUploads: Int
    let missingMediaDownloads: Int
}

enum StorageByteFormatter {
    static func string(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesActualByteCount = false
        return formatter.string(fromByteCount: bytes)
    }
}

enum LocalStorageStatsLoader {
    static func load(database: LocalDatabase?) throws -> LocalStorageStats {
        let databaseBytes = try databaseFileBytes()
        let mediaBytes = try directoryBytes(AppDirectories.mediaDirectory())

        return LocalStorageStats(
            totalBytes: databaseBytes + mediaBytes,
            databaseBytes: databaseBytes,
            mediaBytes: mediaBytes,
            audioVideoCacheBytes: try database?.downloadedAudioVideoCacheBytes() ?? 0,
            pendingChanges: try database?.pendingOperationCount() ?? 0,
            pendingUploads: try database?.uploadCount(status: "pending") ?? 0,
            failedUploads: try database?.uploadCount(status: "failed") ?? 0,
            missingMediaDownloads: try database?.missingMediaDownloadCount() ?? 0
        )
    }

    private static func databaseFileBytes() throws -> Int64 {
        let databaseURL = try AppDirectories.databaseURL()
        return [
            databaseURL,
            URL(fileURLWithPath: "\(databaseURL.path)-wal"),
            URL(fileURLWithPath: "\(databaseURL.path)-shm")
        ].reduce(Int64(0)) { total, url in
            total + fileBytes(url)
        }
    }

    private static func directoryBytes(_ directory: URL) throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ) else {
            return 0
        }

        var total = Int64(0)
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else {
                continue
            }

            total += Int64(values.fileSize ?? 0)
        }

        return total
    }

    private static func fileBytes(_ url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }

        return size.int64Value
    }
}
