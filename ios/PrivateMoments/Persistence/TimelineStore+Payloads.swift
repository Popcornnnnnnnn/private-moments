import Foundation

extension TimelineStore {
    func makeCreatePostPayload(text: String, occurredAt: Date, primaryTagId: String? = nil) throws -> String {
        var payload: [String: Any] = [
            "text": text,
            "occurredAt": ISO8601DateFormatter().string(from: occurredAt)
        ]
        if let primaryTagId {
            payload["primaryTagId"] = primaryTagId
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    func makeSetPostTagsPayload(primaryTagId: String?, topicTagIds: [String], updatedAt: Date) throws -> String {
        let payload: [String: Any] = [
            "primaryTagId": primaryTagId ?? NSNull(),
            "topicTagIds": topicTagIds,
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt)
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    func makeUpsertTagPayload(
        type: String,
        name: String,
        colorHex: String?,
        isDefault: Bool = false,
        aiUsableAsPrimary: Bool,
        updatedAt: Date
    ) throws -> String {
        let payload: [String: Any] = [
            "type": type,
            "name": name,
            "colorHex": colorHex ?? NSNull(),
            "isDefault": isDefault,
            "aiUsableAsPrimary": aiUsableAsPrimary,
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt)
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    func makeArchiveTagPayload(archivedAt: Date) throws -> String {
        let payload: [String: String] = [
            "archivedAt": ISO8601DateFormatter().string(from: archivedAt)
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    func makeRestoreTagPayload(restoredAt: Date) throws -> String {
        let payload: [String: String] = [
            "restoredAt": ISO8601DateFormatter().string(from: restoredAt)
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    func makeDeleteTagPayload(deletedAt: Date) throws -> String {
        let payload: [String: String] = [
            "deletedAt": ISO8601DateFormatter().string(from: deletedAt)
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    func makeUpsertTagAliasPayload(tagId: String, alias: String) throws -> String {
        let payload: [String: String] = [
            "tagId": tagId,
            "alias": alias
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    func makeDeleteTagAliasPayload(deletedAt: Date) throws -> String {
        let payload: [String: String] = [
            "deletedAt": ISO8601DateFormatter().string(from: deletedAt)
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    func makeMergeTagPayload(targetTagId: String, alias: String, mergedAt: Date) throws -> String {
        let payload: [String: String] = [
            "targetTagId": targetTagId,
            "alias": alias,
            "mergedAt": ISO8601DateFormatter().string(from: mergedAt)
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

    func makeInsertAITitlePayload(summaryId: String, mediaId: String, insertedAt: Date) throws -> String {
        let payload: [String: String] = [
            "summaryId": summaryId,
            "mediaId": mediaId,
            "insertedAt": ISO8601DateFormatter().string(from: insertedAt)
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

    func makePinPayload(isPinned: Bool, pinnedAt: Date?, updatedAt: Date) throws -> String {
        let payload: [String: Any] = [
            "isPinned": isPinned,
            "pinnedAt": pinnedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
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

    func makeUpsertCheckInItemPayload(_ item: CheckInItem) throws -> String {
        let payload: [String: Any] = [
            "name": item.name,
            "symbolName": item.symbolName,
            "colorHex": item.colorHex,
            "recordMode": item.recordMode.rawValue,
            "timeVisualization": item.timeVisualization.rawValue,
            "dayStartHour": CheckInDayBoundary.normalizedHour(item.dayStartHour),
            "activeWeekdays": item.activeWeekdays,
            "sortOrder": item.sortOrder,
            "defaultShowInTimeline": item.defaultShowInTimeline,
            "tagId": item.tagId ?? NSNull(),
            "createdAt": ISO8601DateFormatter().string(from: item.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: item.updatedAt),
            "archivedAt": item.archivedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            "deletedAt": item.deletedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    func makeUpsertCheckInEntryPayload(_ entry: CheckInEntry) throws -> String {
        let payload: [String: Any] = [
            "itemId": entry.itemId,
            "occurredAt": ISO8601DateFormatter().string(from: entry.occurredAt),
            "note": entry.note,
            "showInTimeline": entry.showInTimeline,
            "createdAt": ISO8601DateFormatter().string(from: entry.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: entry.updatedAt),
            "deletedAt": entry.deletedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }

    func makeDeleteCheckInPayload(deletedAt: Date) throws -> String {
        let payload: [String: String] = [
            "deletedAt": ISO8601DateFormatter().string(from: deletedAt)
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(decoding: data, as: UTF8.self)
    }
}
