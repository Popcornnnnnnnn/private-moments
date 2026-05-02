import Foundation

extension TimelineStore {
    func makeCreatePostPayload(text: String, occurredAt: Date) throws -> String {
        let payload: [String: String] = [
            "text": text,
            "occurredAt": ISO8601DateFormatter().string(from: occurredAt)
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    func makeDeletePostPayload(deletedAt: Date) throws -> String {
        let payload: [String: String] = [
            "deletedAt": ISO8601DateFormatter().string(from: deletedAt)
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    func makeUpdatePostPayload(
        text: String,
        occurredAt: Date,
        updatedAt: Date,
        media: [TimelineMedia]
    ) throws -> String {
        let payload: [String: Any] = [
            "text": text,
            "occurredAt": ISO8601DateFormatter().string(from: occurredAt),
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt),
            "media": media.map { item in
                [
                    "id": item.id,
                    "sortOrder": item.sortOrder
                ]
            }
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    func makeFavoritePayload(isFavorite: Bool, updatedAt: Date) throws -> String {
        let payload: [String: Any] = [
            "isFavorite": isFavorite,
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt)
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    func makeCreateCommentPayload(postId: String, text: String, createdAt: Date) throws -> String {
        let payload: [String: String] = [
            "postId": postId,
            "text": text,
            "createdAt": ISO8601DateFormatter().string(from: createdAt)
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    func makeDeleteCommentPayload(postId: String, deletedAt: Date) throws -> String {
        let payload: [String: String] = [
            "postId": postId,
            "deletedAt": ISO8601DateFormatter().string(from: deletedAt)
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    func makeUpdateMediaTranscriptionPayload(
        postId: String,
        transcriptionText: String,
        updatedAt: Date
    ) throws -> String {
        let payload: [String: String] = [
            "postId": postId,
            "transcriptionText": transcriptionText,
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt)
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }
}
