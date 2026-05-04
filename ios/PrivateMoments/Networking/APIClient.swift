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

    func sync(_ body: SyncRequestBody) async throws -> SyncResponseBody {
        var request = try authorizedRequest(url: endpoint("api/v1/sync"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        return try await send(request)
    }

    func uploadMedia(_ media: TimelineMedia, variant: String = "compressed") async throws -> UploadedMedia {
        var request = try authorizedRequest(url: endpoint("api/v1/media/upload"))
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = try multipartBody(for: media, variant: variant, boundary: boundary)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")

        let response: MediaUploadResponse = try await upload(request, body: body)
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

    func adminStatus() async throws -> AdminStatusResponse {
        var request = try authorizedRequest(url: endpoint("api/v1/admin/status"))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return try await send(request)
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

    private func upload<T: Decodable>(_ request: URLRequest, body: Data) async throws -> T {
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
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

    private func multipartBody(for media: TimelineMedia, variant: String, boundary: String) throws -> Data {
        let upload = try uploadFile(for: media, variant: variant)
        let fileData = try uploadData(from: upload.url, media: media, variant: variant)
        var body = Data()

        body.appendMultipartField("mediaId", value: media.id, boundary: boundary)
        body.appendMultipartField("postId", value: media.postId, boundary: boundary)
        body.appendMultipartField("variant", value: variant, boundary: boundary)
        body.appendMultipartField("kind", value: media.kind, boundary: boundary)
        body.appendMultipartField("mimeType", value: upload.mimeType, boundary: boundary)
        if let durationSeconds = media.durationSeconds {
            body.appendMultipartField("durationSeconds", value: "\(durationSeconds)", boundary: boundary)
        }
        body.appendMultipartField("aiLanguage", value: AppSettings.aiLanguageMode.requestValue, boundary: boundary)
        body.appendMultipartField("originalPreserved", value: media.originalPreserved ? "true" : "false", boundary: boundary)
        body.appendMultipartField("sortOrder", value: "\(media.sortOrder)", boundary: boundary)
        body.appendMultipartFile(
            "file",
            filename: upload.filename,
            mimeType: upload.mimeType,
            data: fileData,
            boundary: boundary
        )
        body.appendString("--\(boundary)--\r\n")
        return body
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

private extension Data {
    mutating func appendMultipartField(_ name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendMultipartFile(
        _ name: String,
        filename: String,
        mimeType: String,
        data: Data,
        boundary: String
    ) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }

    mutating func appendString(_ value: String) {
        append(Data(value.utf8))
    }
}
