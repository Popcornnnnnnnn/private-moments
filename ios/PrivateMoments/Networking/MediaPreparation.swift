@preconcurrency import AVFoundation
import CoreTransferable
import Foundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct PickedVideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let directory = try AppDirectories.draftMediaDirectory()
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = directory.appending(path: "\(UUID().uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedVideoFile(url: destination)
        }
    }
}

enum MediaPreparationError: LocalizedError {
    case videoTooLong
    case videoExportUnavailable
    case videoExportFailed
    case posterGenerationFailed
    case audioFileUnavailable

    var errorDescription: String? {
        switch self {
        case .videoTooLong:
            return "Choose a video up to 2 minutes."
        case .videoExportUnavailable:
            return "This video cannot be processed."
        case .videoExportFailed:
            return "Video processing failed."
        case .posterGenerationFailed:
            return "Could not create a video poster."
        case .audioFileUnavailable:
            return "Audio file is unavailable."
        }
    }
}

enum VideoMediaProcessor {
    static let maxDurationSeconds: Double = 120

    static func prepareVideo(from sourceURL: URL) async throws -> PreparedMomentMedia {
        let sourceAsset = AVURLAsset(url: sourceURL)
        let duration = try await sourceAsset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds.isFinite, durationSeconds <= maxDurationSeconds else {
            throw MediaPreparationError.videoTooLong
        }

        let directory = try AppDirectories.draftMediaDirectory()
        let mediaId = UUID().uuidString
        let outputURL = directory.appending(path: "\(mediaId).mp4")
        let posterURL = directory.appending(path: "\(mediaId)-poster.jpg")

        try? FileManager.default.removeItem(at: outputURL)
        try? FileManager.default.removeItem(at: posterURL)

        guard let exportSession = AVAssetExportSession(
            asset: sourceAsset,
            presetName: AVAssetExportPreset1280x720
        ) ?? AVAssetExportSession(asset: sourceAsset, presetName: AVAssetExportPresetHighestQuality) else {
            throw MediaPreparationError.videoExportUnavailable
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        try await export(exportSession)
        try generatePoster(from: outputURL, to: posterURL)

        return PreparedMomentMedia(
            id: mediaId,
            kind: "video",
            fileURL: outputURL,
            thumbnailURL: posterURL,
            mimeType: "video/mp4",
            durationSeconds: durationSeconds
        )
    }

    private static func export(_ session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: session.error ?? MediaPreparationError.videoExportFailed)
                default:
                    continuation.resume(throwing: MediaPreparationError.videoExportFailed)
                }
            }
        }
    }

    private static func generatePoster(from videoURL: URL, to posterURL: URL) throws {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        guard let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.78) else {
            throw MediaPreparationError.posterGenerationFailed
        }

        try jpegData.write(to: posterURL, options: [.atomic])
    }
}

enum AudioMediaInspector {
    static func preparedAudio(from url: URL) async throws -> PreparedMomentMedia {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MediaPreparationError.audioFileUnavailable
        }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)

        return PreparedMomentMedia(
            kind: "audio",
            fileURL: url,
            mimeType: "audio/mp4",
            durationSeconds: seconds.isFinite ? seconds : nil
        )
    }
}
