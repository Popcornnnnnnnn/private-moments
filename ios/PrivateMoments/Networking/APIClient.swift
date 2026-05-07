import Foundation
import UIKit

struct APIClient: Sendable {
    let baseURL: URL
    let token: String?

    func health() async throws -> HealthResponse {
        var request = URLRequest(url: endpoint("api/v1/health"))
        request.httpMethod = "GET"
        return try await send(request)
    }

    func login(password: String, deviceName: String, deviceKey: String?) async throws -> LoginResponse {
        var request = URLRequest(url: endpoint("api/v1/auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            LoginRequest(password: password, deviceName: deviceName, platform: "ios", deviceKey: deviceKey)
        )

        return try await send(request)
    }

    func sync(_ body: SyncRequestBody, timeoutInterval: TimeInterval? = nil) async throws -> SyncResponseBody {
        var request = try authorizedRequest(url: endpoint("api/v1/sync"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }

        return try await send(request)
    }

    func uploadMedia(_ media: TimelineMedia, variant: String = "compressed") async throws -> UploadedMedia {
        var request = try authorizedRequest(url: endpoint("api/v1/media/upload"))
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = try multipartBodyFile(for: media, variant: variant, boundary: boundary)
        defer {
            try? FileManager.default.removeItem(at: body.url)
        }

        request.httpMethod = "POST"
        request.timeoutInterval = uploadTimeout(for: media, bodyBytes: body.sizeBytes)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("\(body.sizeBytes)", forHTTPHeaderField: "Content-Length")
        request.setValue("close", forHTTPHeaderField: "Connection")

        let response: MediaUploadResponse = try await upload(request, fileURL: body.url)
        return response.media
    }

    func downloadMedia(mediaId: String, variant: String = "compressed") async throws -> Data {
        var components = URLComponents(url: endpoint("api/v1/media/\(mediaId)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "variant", value: variant)
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = try authorizedRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    func downloadMediaFile(mediaId: String, variant: String = "compressed") async throws -> URL {
        var components = URLComponents(url: endpoint("api/v1/media/\(mediaId)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "variant", value: variant)
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = try authorizedRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.timeoutInterval = 60

        let (fileURL, response) = try await URLSession.shared.download(for: request)
        let errorData = (try? Data(contentsOf: fileURL)) ?? Data()
        try validate(response: response, data: errorData)
        return fileURL
    }

    func downloadMediaBatch(mediaIds: [String], variant: String = "thumbnail") async throws -> [DownloadedMediaPayload] {
        var request = try authorizedRequest(url: endpoint("api/v1/media/batch-download"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try encoder.encode(MediaBatchDownloadRequest(mediaIds: mediaIds, variant: variant))

        let response: MediaBatchDownloadResponse = try await send(request)
        return response.media
    }

    func adminStatus(timeoutInterval: TimeInterval? = nil) async throws -> AdminStatusResponse {
        var request = try authorizedRequest(url: endpoint("api/v1/admin/status"))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        return try await send(request)
    }

    func adminMaintenanceState(timeoutInterval: TimeInterval? = nil) async throws -> AdminMaintenanceStateResponse {
        var request = try authorizedRequest(url: endpoint("api/v1/admin/maintenance/state"))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        return try await send(request)
    }

    func adminMaintenanceJobs(limit: Int = 5, timeoutInterval: TimeInterval? = nil) async throws -> [AdminMaintenanceJob] {
        var components = URLComponents(url: endpoint("api/v1/admin/maintenance/jobs"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = try authorizedRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        let response: AdminMaintenanceJobsResponse = try await send(request)
        return response.jobs
    }

    func adminArchiveRepository(timeoutInterval: TimeInterval? = nil) async throws -> AdminArchiveRepositoryState {
        var request = try authorizedRequest(url: endpoint("api/v1/admin/archive/repository"))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        let response: AdminArchiveRepositoryResponse = try await send(request)
        return response.repository
    }

    func adminArchiveSnapshots(timeoutInterval: TimeInterval? = nil) async throws -> [AdminArchiveSnapshot] {
        var request = try authorizedRequest(url: endpoint("api/v1/admin/archive/snapshots"))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        let response: AdminArchiveSnapshotsResponse = try await send(request)
        return response.snapshots
    }

    func requestMediaSummary(
        postId: String,
        mediaId: String,
        forceRegenerate: Bool,
        aiLanguage: AILanguageMode
    ) async throws -> AISummaryPayload {
        var request = try authorizedRequest(url: endpoint("api/v1/ai/media-summary"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            MediaSummaryRequest(
                postId: postId,
                mediaId: mediaId,
                forceRegenerate: forceRegenerate,
                aiLanguage: aiLanguage.requestValue
            )
        )

        let response: MediaSummaryResponse = try await send(request)
        return response.summary
    }

    func deleteMediaSummary(summaryId: String) async throws -> AISummaryPayload {
        var request = try authorizedRequest(url: endpoint("api/v1/ai/media-summary/\(summaryId)"))
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30

        let response: MediaSummaryResponse = try await send(request)
        return response.summary
    }

    func listReviews(kind: String = "weekly") async throws -> [ReviewPayload] {
        var components = URLComponents(url: endpoint("api/v1/reviews"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "kind", value: kind),
            URLQueryItem(name: "limit", value: "20")
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = try authorizedRequest(url: url)
        request.httpMethod = "GET"
        let response: ReviewListResponse = try await send(request)
        return response.reviews
    }

    func generateWeeklyReview(rangeStart: Date? = nil, rangeEnd: Date? = nil) async throws -> ReviewPayload {
        var request = try authorizedRequest(url: endpoint("api/v1/reviews/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            GenerateReviewRequest(
                kind: "weekly",
                rangeMode: "rolling_7_days",
                rangeStart: rangeStart,
                rangeEnd: rangeEnd
            )
        )

        let response: ReviewResponse = try await send(request)
        return response.review
    }

    func regenerateReview(reviewId: String) async throws -> ReviewPayload {
        var request = try authorizedRequest(url: endpoint("api/v1/reviews/\(reviewId)/regenerate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        let response: ReviewResponse = try await send(request)
        return response.review
    }

    func deleteReview(reviewId: String) async throws -> ReviewPayload {
        var request = try authorizedRequest(url: endpoint("api/v1/reviews/\(reviewId)"))
        request.httpMethod = "DELETE"
        let response: ReviewResponse = try await send(request)
        return response.review
    }

    func sendReviewFeedback(reviewId: String, type: String, note: String? = nil) async throws {
        var request = try authorizedRequest(url: endpoint("api/v1/reviews/\(reviewId)/feedback"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(ReviewFeedbackRequest(type: type, note: note))
        let _: ReviewFeedbackResponse = try await send(request)
    }

    func publishReviewAsMoment(reviewId: String) async throws -> ReviewPayload {
        var request = try authorizedRequest(url: endpoint("api/v1/reviews/\(reviewId)/publish"))
        request.httpMethod = "POST"
        let response: ReviewPublishResponse = try await send(request)
        return response.review
    }

    func reviewSettings() async throws -> ReviewSettingsPayload {
        var request = try authorizedRequest(url: endpoint("api/v1/reviews/settings"))
        request.httpMethod = "GET"
        let response: ReviewSettingsResponse = try await send(request)
        return response.settings
    }

    func updateReviewSettings(autoWeeklyEnabled: Bool, publishWeeklyToMoments: Bool) async throws -> ReviewSettingsPayload {
        var request = try authorizedRequest(url: endpoint("api/v1/reviews/settings"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            ReviewSettingsRequest(
                autoWeeklyEnabled: autoWeeklyEnabled,
                publishWeeklyToMoments: publishWeeklyToMoments
            )
        )
        let response: ReviewSettingsResponse = try await send(request)
        return response.settings
    }

    private func endpoint(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    private func authorizedRequest(url: URL) throws -> URLRequest {
        guard let token, !token.isEmpty else {
            throw APIError.missingToken
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func upload<T: Decodable>(_ request: URLRequest, fileURL: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpStatus(httpResponse.statusCode, body)
        }
    }

    private func multipartBodyFile(
        for media: TimelineMedia,
        variant: String,
        boundary: String
    ) throws -> (url: URL, sizeBytes: Int64) {
        let upload = try uploadFile(for: media, variant: variant)
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("private-moments-upload-\(UUID().uuidString).multipart")
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)

        do {
            let handle = try FileHandle(forWritingTo: bodyURL)
            defer {
                try? handle.close()
            }

            try writeMultipartField("mediaId", value: media.id, boundary: boundary, to: handle)
            try writeMultipartField("postId", value: media.postId, boundary: boundary, to: handle)
            try writeMultipartField("variant", value: variant, boundary: boundary, to: handle)
            try writeMultipartField("kind", value: media.kind, boundary: boundary, to: handle)
            try writeMultipartField("mimeType", value: upload.mimeType, boundary: boundary, to: handle)
            if let durationSeconds = media.durationSeconds {
                try writeMultipartField("durationSeconds", value: "\(durationSeconds)", boundary: boundary, to: handle)
            }
            try writeMultipartField("aiLanguage", value: AppSettings.aiLanguageMode.requestValue, boundary: boundary, to: handle)
            try writeMultipartField("originalPreserved", value: media.originalPreserved ? "true" : "false", boundary: boundary, to: handle)
            try writeMultipartField("sortOrder", value: "\(media.sortOrder)", boundary: boundary, to: handle)
            try writeMultipartFileHeader(
                "file",
                filename: upload.filename,
                mimeType: upload.mimeType,
                boundary: boundary,
                to: handle
            )
            try writeUploadFileData(from: upload.url, media: media, variant: variant, to: handle)
            try handle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))

            let size = try FileManager.default
                .attributesOfItem(atPath: bodyURL.path)[.size] as? NSNumber
            return (bodyURL, size?.int64Value ?? 0)
        } catch {
            try? FileManager.default.removeItem(at: bodyURL)
            throw error
        }
    }

    private func uploadFile(for media: TimelineMedia, variant: String) throws -> (url: URL, filename: String, mimeType: String) {
        if variant == "thumbnail" {
            guard let thumbnailPath = media.localThumbnailPath, !thumbnailPath.isEmpty else {
                throw APIError.missingUploadFile
            }

            return (URL(fileURLWithPath: thumbnailPath), "\(media.id)-thumb.jpg", "image/jpeg")
        }

        guard !media.localCompressedPath.isEmpty else {
            throw APIError.missingUploadFile
        }

        let fileExtension = URL(fileURLWithPath: media.localCompressedPath).pathExtension
        let ext = fileExtension.isEmpty ? media.preferredFileExtension : fileExtension
        return (
            URL(fileURLWithPath: media.localCompressedPath),
            "\(media.id).\(ext)",
            media.mimeType ?? defaultMimeType(for: media)
        )
    }

    private func uploadData(from fileURL: URL, media: TimelineMedia, variant: String) throws -> Data {
        let fileData = try Data(contentsOf: fileURL)
        guard media.isImage && variant == "compressed" else {
            return fileData
        }

        guard let image = UIImage(data: fileData),
              let compressedData = ImageCompression.uploadJPEGData(from: image) else {
            return fileData
        }

        return compressedData
    }

    private func writeMultipartField(
        _ name: String,
        value: String,
        boundary: String,
        to handle: FileHandle
    ) throws {
        try handle.write(contentsOf: Data("--\(boundary)\r\n".utf8))
        try handle.write(contentsOf: Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        try handle.write(contentsOf: Data("\(value)\r\n".utf8))
    }

    private func writeMultipartFileHeader(
        _ name: String,
        filename: String,
        mimeType: String,
        boundary: String,
        to handle: FileHandle
    ) throws {
        try handle.write(contentsOf: Data("--\(boundary)\r\n".utf8))
        try handle.write(contentsOf: Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        try handle.write(contentsOf: Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
    }

    private func writeUploadFileData(
        from fileURL: URL,
        media: TimelineMedia,
        variant: String,
        to handle: FileHandle
    ) throws {
        if media.isImage && variant == "compressed" {
            try handle.write(contentsOf: uploadData(from: fileURL, media: media, variant: variant))
            return
        }

        let input = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? input.close()
        }

        while true {
            let chunk = input.readData(ofLength: 1_048_576)
            guard !chunk.isEmpty else {
                break
            }
            try handle.write(contentsOf: chunk)
        }
    }

    private func uploadTimeout(for media: TimelineMedia, bodyBytes: Int64) -> TimeInterval {
        let megabytes = max(1.0, Double(bodyBytes) / 1_000_000.0)

        if media.isVideo {
            return min(900, max(240, 120 + megabytes * 30))
        }

        if media.isAudio {
            return min(300, max(120, 60 + megabytes * 30))
        }

        return min(180, max(60, 30 + megabytes * 20))
    }

    private func defaultMimeType(for media: TimelineMedia) -> String {
        if media.isVideo {
            return "video/mp4"
        }

        if media.isAudio {
            return "audio/mp4"
        }

        return "image/jpeg"
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        JSONDecoder()
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingToken
    case missingUploadFile
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid server response"
        case .missingToken:
            return "Missing device token"
        case .missingUploadFile:
            return "Missing media file"
        case .httpStatus(let status, let body):
            return "HTTP \(status): \(body)"
        }
    }
}

struct MediaBatchDownloadRequest: Encodable {
    let mediaIds: [String]
    let variant: String
}

struct MediaBatchDownloadResponse: Decodable {
    let media: [DownloadedMediaPayload]
}

struct DownloadedMediaPayload: Decodable {
    let id: String
    let variant: String
    let contentType: String
    let fileName: String
    let base64: String
}
