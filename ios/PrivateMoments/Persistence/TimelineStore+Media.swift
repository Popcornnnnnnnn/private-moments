import Foundation
import UIKit

extension TimelineStore {
    func downloadMissingMedia(client: APIClient, database: LocalDatabase) async throws {
        let media = try database.fetchMediaNeedingDownload()
        let checkInMedia = try database.fetchCheckInMediaNeedingDownload()
        let queuedMedia = media.filter { item in
            if mediaDownloadsInFlight.contains(item.id) {
                return false
            }
            if item.isImage,
               !item.localCompressedPath.isEmpty,
               FileManager.default.fileExists(atPath: item.localCompressedPath) {
                return false
            }
            if item.isVideo,
               let thumbnailPath = item.localThumbnailPath,
               FileManager.default.fileExists(atPath: thumbnailPath) {
                return false
            }
            return true
        }
        let queuedCheckInMedia = checkInMedia.filter { item in
            if mediaDownloadsInFlight.contains(item.id) {
                return false
            }
            if item.hasLocalDisplayFile {
                return false
            }
            return true
        }

        if queuedMedia.isEmpty && queuedCheckInMedia.isEmpty {
            AppSettings.lastMediaDownloadError = nil
            return
        }

        AppSettings.lastMediaDownloadError = "Downloading \(queuedMedia.count + queuedCheckInMedia.count) media thumbnails"
        for item in queuedMedia {
            mediaDownloadsInFlight.insert(item.id)
        }
        for item in queuedCheckInMedia {
            mediaDownloadsInFlight.insert(item.id)
        }
        defer {
            for item in queuedMedia {
                mediaDownloadsInFlight.remove(item.id)
            }
            for item in queuedCheckInMedia {
                mediaDownloadsInFlight.remove(item.id)
            }
        }

        let payloads = queuedMedia.isEmpty
            ? []
            : try await client.downloadMediaBatch(mediaIds: queuedMedia.map(\.id), variant: "thumbnail")
        let checkInPayloads = queuedCheckInMedia.isEmpty
            ? []
            : try await client.downloadCheckInMediaBatch(mediaIds: queuedCheckInMedia.map(\.id), variant: "compressed")
        var payloadById: [String: DownloadedMediaPayload] = [:]
        for payload in payloads + checkInPayloads {
            payloadById[payload.id] = payload
        }

        var savedCount = 0
        for item in queuedMedia {
            guard let payload = payloadById[item.id],
                  let data = Data(base64Encoded: payload.base64) else {
                continue
            }

            let localURL = try localURLForDownloadedMedia(item, variant: "thumbnail")
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
            try data.write(to: localURL, options: [.atomic])
            try database.markMediaDownloaded(mediaId: item.id, localPath: localURL.path, isThumbnail: item.isVideo)
            savedCount += 1
        }
        for item in queuedCheckInMedia {
            guard let payload = payloadById[item.id],
                  let data = Data(base64Encoded: payload.base64) else {
                continue
            }

            let localURL = try localURLForDownloadedCheckInMedia(item)
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
            try data.write(to: localURL, options: [.atomic])
            try database.markCheckInMediaDownloaded(mediaId: item.id, localPath: localURL.path)
            savedCount += 1
        }

        if savedCount > 0 {
            try await reload()
        }
        AppSettings.lastMediaDownloadError = savedCount == queuedMedia.count + queuedCheckInMedia.count
            ? nil
            : "Downloaded \(savedCount)/\(queuedMedia.count + queuedCheckInMedia.count) media thumbnails"
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
            let localURL = try localURLForDownloadedMedia(item, variant: "thumbnail")
            let fileSize = try FileManager.default.attributesOfItem(atPath: downloadedURL.path)[.size] as? Int ?? 0
            AppSettings.lastMediaDownloadError = "Saving \(item.id) (\(fileSize) bytes)"

            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
            try FileManager.default.moveItem(at: downloadedURL, to: localURL)
            try database.markMediaDownloaded(mediaId: item.id, localPath: localURL.path, isThumbnail: item.isVideo)
            try await reload()

            if mediaDownloadsInFlight.count <= 1 {
                AppSettings.lastMediaDownloadError = nil
            }
        } catch {
            AppSettings.lastMediaDownloadError = "\(item.id): \(error.localizedDescription)"
        }
    }

    func localURLForDownloadedMedia(_ media: TimelineMedia, variant: String = "compressed") throws -> URL {
        let directory = try AppDirectories.mediaDirectory()
        let remotePath = variant == "thumbnail" ? media.remoteThumbnailPath : media.remoteCompressedPath
        let remoteExtension = remotePath.flatMap {
            URL(fileURLWithPath: $0).pathExtension.isEmpty ? nil : URL(fileURLWithPath: $0).pathExtension
        }
        let fallbackExtension = variant == "thumbnail" ? "jpg" : media.preferredFileExtension
        let fileExtension = remoteExtension ?? fallbackExtension

        let suffix = variant == "thumbnail" ? "-thumb" : ""
        return directory.appending(path: "\(media.id)\(suffix).\(fileExtension)")
    }

    func localURLForDownloadedCheckInMedia(_ media: CheckInMedia) throws -> URL {
        let directory = try AppDirectories.mediaDirectory()
        let remoteExtension = media.remoteCompressedPath.flatMap {
            URL(fileURLWithPath: $0).pathExtension.isEmpty ? nil : URL(fileURLWithPath: $0).pathExtension
        }
        return directory.appending(path: "\(media.id).\(remoteExtension ?? "jpg")")
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

    func persistPreparedMedia(
        postId: String,
        imageData: [Data],
        video: PreparedMomentMedia?,
        audio: PreparedMomentMedia?,
        createdAt: Date
    ) throws -> [TimelineMedia] {
        if let video {
            return [
                try Self.persistFileMedia(
                    postId: postId,
                    draft: video,
                    sortOrder: 0,
                    createdAt: createdAt
                )
            ]
        }

        if let audio {
            return [
                try Self.persistFileMedia(
                    postId: postId,
                    draft: audio,
                    sortOrder: 0,
                    createdAt: createdAt
                )
            ]
        }

        return try persistImages(postId: postId, imageData: imageData, createdAt: createdAt)
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
            kind: "image",
            localCompressedPath: fileURL.path,
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: "pending",
            mimeType: "image/jpeg",
            durationSeconds: nil,
            transcriptionText: nil,
            transcriptionStatus: "not_applicable",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: sortOrder,
            checksum: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    nonisolated static func persistFileMedia(
        postId: String,
        draft: PreparedMomentMedia,
        sortOrder: Int,
        createdAt: Date
    ) throws -> TimelineMedia {
        let directory = try AppDirectories.mediaDirectory()
        let mediaId = draft.id
        let fileExtension = draft.kind == "audio" ? "m4a" : "mp4"
        let fileURL = directory.appending(path: "\(mediaId).\(fileExtension)")
        let thumbnailURL = draft.thumbnailURL.map { _ in directory.appending(path: "\(mediaId)-thumb.jpg") }

        try replaceFile(at: draft.fileURL, withCopyAt: fileURL)
        if let sourceThumbnail = draft.thumbnailURL, let thumbnailURL {
            try replaceFile(at: sourceThumbnail, withCopyAt: thumbnailURL)
        }

        return TimelineMedia(
            id: mediaId,
            postId: postId,
            kind: draft.kind,
            localCompressedPath: fileURL.path,
            localOriginalStagingPath: nil,
            localThumbnailPath: thumbnailURL?.path,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: "pending",
            mimeType: draft.mimeType,
            durationSeconds: draft.durationSeconds,
            transcriptionText: nil,
            transcriptionStatus: "pending",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: sortOrder,
            checksum: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    nonisolated private static func replaceFile(at sourceURL: URL, withCopyAt destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    func localPlayableURL(for media: TimelineMedia) async throws -> URL {
        if media.hasLocalPlayableFile {
            return URL(fileURLWithPath: media.localCompressedPath)
        }

        guard automaticSyncEnabled else {
            throw StoreError.localOnlyModeEnabled
        }

        guard let database,
              let token = try KeychainStore.deviceToken() else {
            throw StoreError.notReady
        }

        let downloadedURL = try await withMediaDownloadTimeout(seconds: media.isVideo ? 180 : 120) {
            try await self.withAvailableAPIClient(token: token) { client in
                try await client.downloadMediaFile(mediaId: media.id, variant: "compressed")
            }
        }
        let localURL = try localURLForDownloadedMedia(media, variant: "compressed")

        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.moveItem(at: downloadedURL, to: localURL)
        try database.markMediaDownloaded(mediaId: media.id, localPath: localURL.path)
        try await reload()

        return localURL
    }
}

extension TimelineMedia {
    var preferredFileExtension: String {
        if isAudio {
            return "m4a"
        }

        if isVideo {
            return "mp4"
        }

        return "jpg"
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
