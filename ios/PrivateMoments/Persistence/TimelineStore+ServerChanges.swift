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
                remotePath: remotePath,
                originalPreserved: change.payload["originalPreserved"]?.boolValue ?? false,
                sortOrder: change.payload["sortOrder"]?.intValue ?? 0,
                checksum: change.payload["checksum"]?.stringValue
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
                  let createdAtValue = change.payload["createdAt"]?.stringValue,
                  let updatedAtValue = change.payload["updatedAt"]?.stringValue else {
                throw StoreError.invalidServerChange("comment_created is missing required fields")
            }

            guard let createdAt = Self.parseServerDate(createdAtValue) else {
                throw StoreError.invalidServerChange("comment_created has an invalid createdAt")
            }

            guard let updatedAt = Self.parseServerDate(updatedAtValue) else {
                throw StoreError.invalidServerChange("comment_created has an invalid updatedAt")
            }

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
                throw StoreError.invalidServerChange("comment_deleted has an invalid deletedAt")
            }

            try database.applyCommentDeleted(id: id, postId: postId, deletedAt: deletedAt, serverVersion: change.version)

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

    private static func parseServerDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
