import Foundation

struct HealthResponse: Decodable {
    let ok: Bool
    let serverVersion: String
    let schemaVersion: Int
    let dataDir: String
}

struct LoginRequest: Encodable {
    let password: String
    let deviceName: String
    let platform: String
    let deviceKey: String?
}

struct LoginResponse: Decodable {
    let deviceId: String
    let deviceToken: String
    let serverVersion: String
    let schemaVersion: Int
}

struct SyncRequestBody: Encodable {
    let deviceId: String
    let lastSyncCursor: Int
    let localChanges: [SyncLocalChange]
}

struct SyncLocalChange: Encodable {
    let opId: String
    let type: String
    let entityType: String
    let entityId: String
    let clientCreatedAt: Date
    let payload: [String: JSONValue]
}

struct SyncResponseBody: Decodable {
    let serverVersion: String
    let schemaVersion: Int
    let acceptedOps: [String]
    let rejectedOps: [RejectedSyncOperation]
    let serverChanges: [ServerChange]
    let nextSyncCursor: Int
}

struct RejectedSyncOperation: Decodable {
    let opId: String
    let reason: String
}

struct ServerChange: Decodable {
    let version: Int
    let entityType: String
    let entityId: String
    let changeType: String
    let payload: [String: JSONValue]
    let createdAt: String
}

struct MediaUploadResponse: Decodable {
    let media: UploadedMedia
}

struct UploadedMedia: Decodable {
    let id: String
    let postId: String
    let variant: String
    let status: String
    let path: String
    let sizeBytes: Int
    let checksum: String
}

struct AdminStatusResponse: Decodable {
    let counts: AdminStatusCounts
    let storage: ServerStorageStats
    let aiSummaries: AdminAISummaryDiagnostics?
    let sync: AdminSyncDiagnostics?
}

struct AdminStatusCounts: Decodable, Equatable {
    let activeDevices: Int
    let revokedDevices: Int
    let posts: Int
    let deletedPosts: Int
    let media: Int
}

struct MediaSummaryRequest: Encodable {
    let postId: String
    let mediaId: String
    let forceRegenerate: Bool
}

struct MediaSummaryResponse: Decodable {
    let summary: AISummaryPayload
}

struct AISummaryPayload: Decodable {
    let id: String
    let postId: String
    let mediaId: String
    let status: String
    let format: String?
    let language: String?
    let overview: String?
    let keyPoints: [String]
    let sections: [TimelineAISummarySection]
    let summaryText: String?
    let documentTitle: String?
    let oneLiner: String?
    let documentBlocks: [TimelineAISummaryBlock]?
    let inputTranscriptLength: Int?
    let inputDurationSeconds: Double?
    let promptVersion: String
    let provider: String?
    let model: String?
    let errorCode: String?
    let errorMessage: String?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    func timelineSummary() -> TimelineAISummary {
        TimelineAISummary(
            id: id,
            postId: postId,
            mediaId: mediaId,
            status: status,
            format: format,
            language: language,
            overview: overview,
            keyPoints: keyPoints,
            sections: sections,
            summaryText: summaryText,
            documentTitle: documentTitle,
            oneLiner: oneLiner,
            documentBlocks: documentBlocks ?? [],
            inputTranscriptLength: inputTranscriptLength,
            inputDurationSeconds: inputDurationSeconds,
            promptVersion: promptVersion,
            provider: provider,
            model: model,
            errorCode: errorCode,
            errorMessage: errorMessage,
            createdAt: Self.parseServerDate(createdAt) ?? Date(),
            updatedAt: Self.parseServerDate(updatedAt) ?? Date(),
            deletedAt: deletedAt.flatMap(Self.parseServerDate)
        )
    }

    private static func parseServerDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

struct ServerStorageStats: Decodable, Equatable {
    let totalBytes: Int64
    let databaseBytes: Int64?
    let mediaBytes: Int64?
    let logsBytes: Int64?
    let availableBytes: Int64?
}

struct AdminAISummaryDiagnostics: Decodable, Equatable {
    let total: Int
    let transcribing: Int
    let summarizing: Int
    let ready: Int
    let failed: Int
    let deleted: Int
    let recent: [AdminAISummaryDiagnosticItem]
}

struct AdminAISummaryDiagnosticItem: Decodable, Equatable, Identifiable {
    let id: String
    let mediaId: String
    let status: String
    let errorCode: String?
    let inputTranscriptLength: Int?
    let inputDurationSeconds: Double?
    let ageSeconds: Int?
    let retryHint: String?
    let updatedAt: String
}

struct AdminSyncDiagnostics: Decodable, Equatable {
    let latestServerChangeVersion: Int
}

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }

        return nil
    }

    var intValue: Int? {
        if case .number(let value) = self {
            return Int(value)
        }

        return nil
    }

    var doubleValue: Double? {
        if case .number(let value) = self {
            return value
        }

        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }

        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self {
            return value
        }

        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        }

        return nil
    }
}

extension OutboxOperation {
    func syncLocalChange() throws -> SyncLocalChange {
        let data = Data(payloadJson.utf8)
        let payload = try JSONDecoder().decode([String: JSONValue].self, from: data)

        return SyncLocalChange(
            opId: opId,
            type: type,
            entityType: entityType,
            entityId: entityId,
            clientCreatedAt: createdAt,
            payload: payload
        )
    }
}
