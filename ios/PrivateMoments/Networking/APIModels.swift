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
}

struct AdminStatusCounts: Decodable, Equatable {
    let activeDevices: Int
    let revokedDevices: Int
    let posts: Int
    let deletedPosts: Int
    let media: Int
}

struct ServerStorageStats: Decodable, Equatable {
    let totalBytes: Int64
    let databaseBytes: Int64?
    let mediaBytes: Int64?
    let logsBytes: Int64?
    let availableBytes: Int64?
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
