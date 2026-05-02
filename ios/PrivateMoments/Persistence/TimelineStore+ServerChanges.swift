import Foundation

extension TimelineStore {
    func apply(change: ServerChange, database: LocalDatabase) throws {
        switch change.changeType {
        case "post_created":
            guard let id = change.payload["id"]?.stringValue,
                  let text = change.payload["text"]?.stringValue,
                  let occurredAtValue = change.payload["occurredAt"]?.stringValue else {
                throw StoreError.invalidServerChange("post_created is missing required fields")
            }

            guard let occurredAt = Self.parseServerDate(occurredAtValue) else {
                throw StoreError.invalidServerChange("post_created has an invalid occurredAt: \(occurredAtValue)")
            }

            try database.applyPostCreated(
                id: id,
                text: text,
                isFavorite: change.payload["isFavorite"]?.boolValue ?? false,
                occurredAt: occurredAt,
                serverVersion: change.version
            )

        case "post_updated":
            guard let id = change.payload["id"]?.stringValue,
                  let text = change.payload["text"]?.stringValue,
                  let occurredAtValue = change.payload["occurredAt"]?.stringValue else {
                throw StoreError.invalidServerChange("post_updated is missing required fields")
            }

            guard let occurredAt = Self.parseServerDate(occurredAtValue) else {
                throw StoreError.invalidServerChange("post_updated has an invalid occurredAt: \(occurredAtValue)")
            }

            let editedAtValue = change.payload["updatedAt"]?.stringValue
            let editedAt = editedAtValue.flatMap(Self.parseServerDate) ?? Date()
            let mediaOrder = parseMediaOrder(change.payload["media"])
            try database.applyPostUpdated(
                id: id,
                text: text,
                isFavorite: change.payload["isFavorite"]?.boolValue,
                occurredAt: occurredAt,
                editedAt: editedAt,
                mediaOrder: mediaOrder,
                serverVersion: change.version
            )

        case "post_favorite_updated":
            guard let id = change.payload["id"]?.stringValue,
                  let isFavorite = change.payload["isFavorite"]?.boolValue else {
                return
            }

            let updatedAtValue = change.payload["updatedAt"]?.stringValue
            let updatedAt = updatedAtValue.flatMap(Self.parseServerDate) ?? Date()
            try database.applyPostFavoriteUpdated(
                id: id,
                isFavorite: isFavorite,
                updatedAt: updatedAt,
                serverVersion: change.version
            )

        case "post_deleted":
            guard let id = change.payload["id"]?.stringValue,
                  let deletedAtValue = change.payload["deletedAt"]?.stringValue else {
                throw StoreError.invalidServerChange("post_deleted is missing required fields")
            }

            guard let deletedAt = Self.parseServerDate(deletedAtValue) else {
                throw StoreError.invalidServerChange("post_deleted has an invalid deletedAt: \(deletedAtValue)")
            }

            try database.applyPostDeleted(id: id, deletedAt: deletedAt, serverVersion: change.version)

        case "media_uploaded":
            guard let mediaId = change.payload["id"]?.stringValue,
                  let postId = change.payload["postId"]?.stringValue,
                  let remotePath = change.payload["path"]?.stringValue else {
                return
            }

            try database.applyMediaUploaded(
                mediaId: mediaId,
                postId: postId,
                kind: change.payload["kind"]?.stringValue ?? "image",
                variant: change.payload["variant"]?.stringValue ?? "compressed",
                remotePath: remotePath,
                originalPreserved: change.payload["originalPreserved"]?.boolValue ?? false,
                sortOrder: change.payload["sortOrder"]?.intValue ?? 0,
                checksum: change.payload["checksum"]?.stringValue,
                mimeType: change.payload["mimeType"]?.stringValue,
                durationSeconds: change.payload["durationSeconds"]?.doubleValue,
                transcriptionText: change.payload["transcriptionText"]?.stringValue
            )

        case "media_transcription_updated":
            guard let mediaId = change.payload["id"]?.stringValue,
                  let postId = change.payload["postId"]?.stringValue else {
                throw StoreError.invalidServerChange("media_transcription_updated is missing required fields")
            }

            try database.applyMediaTranscriptionUpdated(
                mediaId: mediaId,
                postId: postId,
                transcriptionText: change.payload["transcriptionText"]?.stringValue,
                serverVersion: change.version
            )

        case "media_deleted":
            guard let mediaId = change.payload["id"]?.stringValue,
                  let postId = change.payload["postId"]?.stringValue,
                  let deletedAtValue = change.payload["deletedAt"]?.stringValue else {
                throw StoreError.invalidServerChange("media_deleted is missing required fields")
            }

            guard let deletedAt = Self.parseServerDate(deletedAtValue) else {
                throw StoreError.invalidServerChange("media_deleted has an invalid deletedAt: \(deletedAtValue)")
            }

            try database.applyMediaDeleted(mediaId: mediaId, postId: postId, deletedAt: deletedAt)

        case "comment_created":
            guard let id = change.payload["id"]?.stringValue,
                  let postId = change.payload["postId"]?.stringValue,
                  let text = change.payload["text"]?.stringValue,
                  let createdAtValue = change.payload["createdAt"]?.stringValue else {
                throw StoreError.invalidServerChange("comment_created is missing required fields")
            }

            guard let createdAt = Self.parseServerDate(createdAtValue) else {
                throw StoreError.invalidServerChange("comment_created has an invalid createdAt: \(createdAtValue)")
            }

            let updatedAtValue = change.payload["updatedAt"]?.stringValue
            let updatedAt = updatedAtValue.flatMap(Self.parseServerDate) ?? createdAt
            try database.applyCommentCreated(
                id: id,
                postId: postId,
                text: text,
                createdAt: createdAt,
                updatedAt: updatedAt,
                serverVersion: change.version
            )

        case "comment_deleted":
            guard let id = change.payload["id"]?.stringValue,
                  let postId = change.payload["postId"]?.stringValue,
                  let deletedAtValue = change.payload["deletedAt"]?.stringValue else {
                throw StoreError.invalidServerChange("comment_deleted is missing required fields")
            }

            guard let deletedAt = Self.parseServerDate(deletedAtValue) else {
                throw StoreError.invalidServerChange("comment_deleted has an invalid deletedAt: \(deletedAtValue)")
            }

            try database.applyCommentDeleted(
                id: id,
                postId: postId,
                deletedAt: deletedAt,
                serverVersion: change.version
            )

        case "ai_summary_updated":
            let summary = try parseAISummaryPayload(change.payload, changeType: "ai_summary_updated")
            try database.applyAISummaryUpdated(summary, serverVersion: change.version)

        case "ai_summary_deleted":
            let summary = try parseAISummaryPayload(change.payload, changeType: "ai_summary_deleted")
            try database.applyAISummaryDeleted(summary, serverVersion: change.version)

        default:
            return
        }
    }

    private func parseMediaOrder(_ value: JSONValue?) -> [(id: String, sortOrder: Int)] {
        value?.arrayValue?.compactMap { item in
            guard let object = item.objectValue,
                  let id = object["id"]?.stringValue,
                  let sortOrder = object["sortOrder"]?.intValue else {
                return nil
            }

            return (id: id, sortOrder: sortOrder)
        } ?? []
    }

    private func parseAISummaryPayload(
        _ payload: [String: JSONValue],
        changeType: String
    ) throws -> TimelineAISummary {
        guard let id = payload["id"]?.stringValue,
              let postId = payload["postId"]?.stringValue,
              let mediaId = payload["mediaId"]?.stringValue,
              let status = payload["status"]?.stringValue,
              let promptVersion = payload["promptVersion"]?.stringValue,
              let createdAtValue = payload["createdAt"]?.stringValue,
              let updatedAtValue = payload["updatedAt"]?.stringValue else {
            throw StoreError.invalidServerChange("\(changeType) is missing required fields")
        }

        guard let createdAt = Self.parseServerDate(createdAtValue),
              let updatedAt = Self.parseServerDate(updatedAtValue) else {
            throw StoreError.invalidServerChange("\(changeType) has invalid timestamps")
        }

        let deletedAt = payload["deletedAt"]?.stringValue.flatMap(Self.parseServerDate)
        return TimelineAISummary(
            id: id,
            postId: postId,
            mediaId: mediaId,
            status: status,
            format: payload["format"]?.stringValue,
            language: payload["language"]?.stringValue,
            overview: payload["overview"]?.stringValue,
            keyPoints: parseStringArray(payload["keyPoints"]),
            sections: parseSummarySections(payload["sections"]),
            summaryText: payload["summaryText"]?.stringValue,
            documentTitle: payload["documentTitle"]?.stringValue,
            oneLiner: payload["oneLiner"]?.stringValue,
            documentBlocks: parseSummaryBlocks(payload["documentBlocks"]),
            inputTranscriptLength: payload["inputTranscriptLength"]?.intValue,
            inputDurationSeconds: payload["inputDurationSeconds"]?.doubleValue,
            promptVersion: promptVersion,
            provider: payload["provider"]?.stringValue,
            model: payload["model"]?.stringValue,
            errorCode: payload["errorCode"]?.stringValue,
            errorMessage: payload["errorMessage"]?.stringValue,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    private func parseStringArray(_ value: JSONValue?) -> [String] {
        value?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    private func parseSummarySections(_ value: JSONValue?) -> [TimelineAISummarySection] {
        value?.arrayValue?.compactMap { item in
            guard let object = item.objectValue,
                  let heading = object["heading"]?.stringValue else {
                return nil
            }

            return TimelineAISummarySection(
                heading: heading,
                bullets: parseStringArray(object["bullets"])
            )
        } ?? []
    }

    private func parseSummaryBlocks(_ value: JSONValue?) -> [TimelineAISummaryBlock] {
        value?.arrayValue?.compactMap { item in
            guard let object = item.objectValue,
                  let kind = object["kind"]?.stringValue else {
                return nil
            }

            return TimelineAISummaryBlock(
                kind: kind,
                level: object["level"]?.intValue ?? 0,
                text: object["text"]?.stringValue ?? "",
                items: parseStringArray(object["items"])
            )
        } ?? []
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
