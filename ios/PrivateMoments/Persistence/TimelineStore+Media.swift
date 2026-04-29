import Foundation
import UIKit

extension TimelineStore {
    func downloadMissingMedia(client: APIClient, database: LocalDatabase) async throws {
        let media = try database.fetchMediaNeedingDownload()
        let queuedMedia = media.filter { item in
            if mediaDownloadsInFlight.contains(item.id) {
                return false
            }
            if !item.localCompressedPath.isEmpty,
               FileManager.default.fileExists(atPath: item.localCompressedPath) {
                return false
            }
            return true
        }

        if queuedMedia.isEmpty {
            AppSettings.lastMediaDownloadError = nil
            return
        }

        AppSettings.lastMediaDownloadError = "Downloading \(queuedMedia.count) media thumbnails"
        for item in queuedMedia {
            mediaDownloadsInFlight.insert(item.id)
        }
        defer {
            for item in queuedMedia {
                mediaDownloadsInFlight.remove(item.id)
            }
        }

        let payloads = try await client.downloadMediaBatch(mediaIds: queuedMedia.map(\.id))
        var payloadById: [String: DownloadedMediaPayload] = [:]
        for payload in payloads {
            payloadById[payload.id] = payload
        }

        var savedCount = 0
        for item in queuedMedia {
            guard let payload = payloadById[item.id],
                  let data = Data(base64Encoded: payload.base64) else {
                continue
            }

            let localURL = try localURLForDownloadedMedia(item)
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
            try data.write(to: localURL, options: [.atomic])
            try database.markMediaDownloaded(mediaId: item.id, localPath: localURL.path)
            savedCount += 1
        }

        if savedCount > 0 {
            try await reload()
        }
        AppSettings.lastMediaDownloadError = savedCount == queuedMedia.count
            ? nil
            : "Downloaded \(savedCount)/\(queuedMedia.count) media thumbnails"
    }

    func downloadMediaItem(_ item: TimelineMedia, client: APIClient, database: LocalDatabase) async {
        defer {
            mediaDownloadsInFlight.remove(item.id)
        }

        do {
            AppSettings.lastMediaDownloadError = "Downloading \(item.id)"
            let downloadedURL = try await withMediaDownloadTimeout(seconds: 60) {
                try await client.downloadMediaFile(mediaId: item.id, variant: "thumbnail")
            }
            let localURL = try localURLForDownloadedMedia(item)
            let fileSize = try FileManager.default.attributesOfItem(atPath: downloadedURL.path)[.size] as? Int ?? 0
            AppSettings.lastMediaDownloadError = "Saving \(item.id) (\(fileSize) bytes)"

            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
            try FileManager.default.moveItem(at: downloadedURL, to: localURL)
            try database.markMediaDownloaded(mediaId: item.id, localPath: localURL.path)
            try await reload()

            if mediaDownloadsInFlight.count <= 1 {
                AppSettings.lastMediaDownloadError = nil
            }
        } catch {
            AppSettings.lastMediaDownloadError = "\(item.id): \(error.localizedDescription)"
        }
    }

    func localURLForDownloadedMedia(_ media: TimelineMedia) throws -> URL {
        let directory = try AppDirectories.mediaDirectory()
        let remoteExtension = media.remoteCompressedPath.flatMap {
            URL(fileURLWithPath: $0).pathExtension.isEmpty ? nil : URL(fileURLWithPath: $0).pathExtension
        }
        let fileExtension = remoteExtension ?? "jpg"

        return directory.appending(path: "\(media.id).\(fileExtension)")
    }

    func persistImages(postId: String, imageData: [Data], createdAt: Date) throws -> [TimelineMedia] {
        return try imageData.prefix(9).enumerated().compactMap { index, data in
            try Self.persistImage(
                postId: postId,
                mediaId: UUID().uuidString,
                data: data,
                sortOrder: index,
                createdAt: createdAt
            )
        }
    }

    nonisolated static func materializeEditedMedia(
        postId: String,
        mediaItems: [MomentEditMediaItem],
        updatedAt: Date
    ) async throws -> [TimelineMedia] {
        try await Task.detached(priority: .userInitiated) {
            try mediaItems.prefix(9).enumerated().compactMap { index, item in
                switch item.source {
                case .existing(var media):
                    media.sortOrder = index
                    media.updatedAt = updatedAt
                    return media

                case .new(let data):
                    return try Self.persistImage(
                        postId: postId,
                        mediaId: item.id,
                        data: data,
                        sortOrder: index,
                        createdAt: updatedAt
                    )
                }
            }
        }.value
    }

    nonisolated static func persistImage(
        postId: String,
        mediaId: String,
        data: Data,
        sortOrder: Int,
        createdAt: Date
    ) throws -> TimelineMedia? {
        guard let image = UIImage(data: data), let jpegData = ImageCompression.uploadJPEGData(from: image) else {
            return nil
        }

        let directory = try AppDirectories.mediaDirectory()
        let fileURL = directory.appending(path: "\(mediaId).jpg")
        try jpegData.write(to: fileURL, options: [.atomic])

        return TimelineMedia(
            id: mediaId,
            postId: postId,
            localCompressedPath: fileURL.path,
            localOriginalStagingPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            originalPreserved: false,
            uploadStatus: "pending",
            sortOrder: sortOrder,
            checksum: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}

private enum MediaDownloadError: LocalizedError {
    case timedOut(seconds: UInt64)

    var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "Media download timed out after \(seconds) seconds"
        }
    }
}

private func withMediaDownloadTimeout<T: Sendable>(
    seconds: UInt64,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw MediaDownloadError.timedOut(seconds: seconds)
        }

        guard let result = try await group.next() else {
            throw MediaDownloadError.timedOut(seconds: seconds)
        }

        group.cancelAll()
        return result
    }
}
