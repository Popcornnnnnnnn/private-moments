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
                isPinned: change.payload["isPinned"]?.boolValue ?? false,
                pinnedAt: change.payload["pinnedAt"]?.stringValue.flatMap(Self.parseServerDate),
                aiTagProcessedAt: change.payload["aiTagProcessedAt"]?.stringValue.flatMap(Self.parseServerDate),
                tagsUserEditedAt: change.payload["tagsUserEditedAt"]?.stringValue.flatMap(Self.parseServerDate),
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
            let isUserEdit = change.payload["updateSource"]?.stringValue != "ai_title"
            try database.applyPostUpdated(
                id: id,
                text: text,
                isFavorite: change.payload["isFavorite"]?.boolValue,
                isPinned: change.payload["isPinned"]?.boolValue,
                pinnedAt: change.payload["pinnedAt"]?.stringValue.flatMap(Self.parseServerDate),
                occurredAt: occurredAt,
                editedAt: editedAt,
                isUserEdit: isUserEdit,
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

        case "post_pin_updated":
            guard let id = change.payload["id"]?.stringValue,
                  let isPinned = change.payload["isPinned"]?.boolValue else {
                return
            }

            let pinnedAtValue = change.payload["pinnedAt"]?.stringValue
            let updatedAtValue = change.payload["updatedAt"]?.stringValue
            let pinnedAt = pinnedAtValue.flatMap(Self.parseServerDate)
            let updatedAt = updatedAtValue.flatMap(Self.parseServerDate) ?? Date()
            try database.applyPostPinUpdated(
                id: id,
                isPinned: isPinned,
                pinnedAt: pinnedAt,
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
            try insertAITitleIfNeeded(for: summary, database: database)

        case "ai_summary_deleted":
            let summary = try parseAISummaryPayload(change.payload, changeType: "ai_summary_deleted")
            try database.applyAISummaryDeleted(summary, serverVersion: change.version)

        case "tag_updated":
            let tag = try parseTagPayload(change.payload, changeType: "tag_updated")
            try database.applyTagUpdated(tag)

        case "tag_deleted":
            guard let id = change.payload["id"]?.stringValue else {
                throw StoreError.invalidServerChange("tag_deleted is missing id")
            }
            try database.applyTagDeleted(id: id)

        case "tag_alias_updated":
            let alias = try parseTagAliasPayload(change.payload, changeType: "tag_alias_updated")
            try database.applyTagAliasUpdated(alias)

        case "tag_alias_deleted":
            let alias = try parseTagAliasPayload(change.payload, changeType: "tag_alias_deleted")
            try database.applyTagAliasDeleted(alias)

        case "post_tag_updated":
            guard let assignedTag = try parseAssignedTagPayload(
                change.payload,
                changeType: "post_tag_updated",
                database: database
            ) else {
                throw StoreError.invalidServerChange("post_tag_updated references a missing local tag")
            }
            try database.applyPostTagUpdated(assignedTag, serverVersion: change.version)

        case "post_tag_deleted":
            if let assignedTag = try parseAssignedTagPayload(
                change.payload,
                changeType: "post_tag_deleted",
                database: database,
                allowMissingTag: true
            ) {
                try database.applyPostTagDeleted(assignedTag, serverVersion: change.version)
            }

        case "post_tag_state_updated":
            guard let postId = change.payload["postId"]?.stringValue else {
                throw StoreError.invalidServerChange("post_tag_state_updated is missing postId")
            }

            try database.applyPostTagStateUpdated(
                postId: postId,
                aiTagProcessedAt: change.payload["aiTagProcessedAt"]?.stringValue.flatMap(Self.parseServerDate),
                tagsUserEditedAt: change.payload["tagsUserEditedAt"]?.stringValue.flatMap(Self.parseServerDate),
                serverVersion: change.version
            )

        case "checkin_item_updated":
            let item = try parseCheckInItemPayload(change.payload, changeType: "checkin_item_updated")
            try database.applyCheckInItemUpdated(item)

        case "checkin_item_deleted":
            guard let id = change.payload["id"]?.stringValue,
                  let deletedAtValue = change.payload["deletedAt"]?.stringValue,
                  let deletedAt = Self.parseServerDate(deletedAtValue) else {
                throw StoreError.invalidServerChange("checkin_item_deleted is missing required fields")
            }
            try database.applyCheckInItemDeleted(id: id, deletedAt: deletedAt)

        case "checkin_entry_updated":
            let entry = try parseCheckInEntryPayload(change.payload, changeType: "checkin_entry_updated")
            try database.applyCheckInEntryUpdated(entry)

        case "checkin_entry_deleted":
            guard let id = change.payload["id"]?.stringValue,
                  let deletedAtValue = change.payload["deletedAt"]?.stringValue,
                  let deletedAt = Self.parseServerDate(deletedAtValue) else {
                throw StoreError.invalidServerChange("checkin_entry_deleted is missing required fields")
            }
            try database.applyCheckInEntryDeleted(id: id, deletedAt: deletedAt)

        case "checkin_media_uploaded":
            guard let id = change.payload["id"]?.stringValue,
                  let entryId = change.payload["entryId"]?.stringValue,
                  let kind = change.payload["kind"]?.stringValue,
                  let variant = change.payload["variant"]?.stringValue,
                  let path = change.payload["path"]?.stringValue else {
                throw StoreError.invalidServerChange("checkin_media_uploaded is missing required fields")
            }
            try database.applyCheckInMediaUploaded(
                mediaId: id,
                entryId: entryId,
                kind: kind,
                variant: variant,
                remotePath: path,
                sortOrder: change.payload["sortOrder"]?.intValue ?? 0,
                checksum: change.payload["checksum"]?.stringValue,
                mimeType: change.payload["mimeType"]?.stringValue
            )

        case "checkin_media_deleted":
            guard let id = change.payload["id"]?.stringValue,
                  let deletedAtValue = change.payload["deletedAt"]?.stringValue,
                  let deletedAt = Self.parseServerDate(deletedAtValue) else {
                throw StoreError.invalidServerChange("checkin_media_deleted is missing required fields")
            }
            try database.applyCheckInMediaDeleted(id: id, deletedAt: deletedAt)

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

    private func parseTagPayload(
        _ payload: [String: JSONValue],
        changeType: String
    ) throws -> TimelineTag {
        guard let id = payload["id"]?.stringValue,
              let type = payload["type"]?.stringValue,
              let name = payload["name"]?.stringValue,
              let normalizedName = payload["normalizedName"]?.stringValue,
              let isDefault = payload["isDefault"]?.boolValue,
              let isArchived = payload["isArchived"]?.boolValue,
              let aiUsableAsPrimary = payload["aiUsableAsPrimary"]?.boolValue,
              let createdAtValue = payload["createdAt"]?.stringValue,
              let updatedAtValue = payload["updatedAt"]?.stringValue else {
            throw StoreError.invalidServerChange("\(changeType) is missing required fields")
        }

        guard let createdAt = Self.parseServerDate(createdAtValue),
              let updatedAt = Self.parseServerDate(updatedAtValue) else {
            throw StoreError.invalidServerChange("\(changeType) has invalid timestamps")
        }

        return TimelineTag(
            id: id,
            type: type,
            name: name,
            normalizedName: normalizedName,
            colorHex: payload["colorHex"]?.stringValue,
            isDefault: isDefault,
            isArchived: isArchived,
            aiUsableAsPrimary: aiUsableAsPrimary,
            createdAt: createdAt,
            updatedAt: updatedAt,
            archivedAt: payload["archivedAt"]?.stringValue.flatMap(Self.parseServerDate)
        )
    }

    private func parseCheckInItemPayload(
        _ payload: [String: JSONValue],
        changeType: String
    ) throws -> CheckInItem {
        guard let id = payload["id"]?.stringValue,
              let name = payload["name"]?.stringValue,
              let symbolName = payload["symbolName"]?.stringValue,
              let colorHex = payload["colorHex"]?.stringValue,
              let recordModeValue = payload["recordMode"]?.stringValue,
              let recordMode = CheckInRecordMode(rawValue: recordModeValue),
              let sortOrder = payload["sortOrder"]?.intValue,
              let defaultShowInTimeline = payload["defaultShowInTimeline"]?.boolValue,
              let createdAtValue = payload["createdAt"]?.stringValue,
              let updatedAtValue = payload["updatedAt"]?.stringValue,
              let createdAt = Self.parseServerDate(createdAtValue),
              let updatedAt = Self.parseServerDate(updatedAtValue) else {
            throw StoreError.invalidServerChange("\(changeType) is missing required fields")
        }

        let activeWeekdays = parseIntegerArray(payload["activeWeekdays"]).filter { (1...7).contains($0) }
        return CheckInItem(
            id: id,
            name: name,
            symbolName: symbolName,
            colorHex: colorHex,
            recordMode: recordMode,
            activeWeekdays: activeWeekdays.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : activeWeekdays,
            sortOrder: sortOrder,
            defaultShowInTimeline: defaultShowInTimeline,
            tagId: payload["tagId"]?.stringValue,
            createdAt: createdAt,
            updatedAt: updatedAt,
            archivedAt: payload["archivedAt"]?.stringValue.flatMap(Self.parseServerDate),
            deletedAt: payload["deletedAt"]?.stringValue.flatMap(Self.parseServerDate),
            syncStatus: "synced"
        )
    }

    private func parseCheckInEntryPayload(
        _ payload: [String: JSONValue],
        changeType: String
    ) throws -> CheckInEntry {
        guard let id = payload["id"]?.stringValue,
              let itemId = payload["itemId"]?.stringValue,
              let occurredAtValue = payload["occurredAt"]?.stringValue,
              let occurredAt = Self.parseServerDate(occurredAtValue),
              let showInTimeline = payload["showInTimeline"]?.boolValue,
              let createdAtValue = payload["createdAt"]?.stringValue,
              let updatedAtValue = payload["updatedAt"]?.stringValue,
              let createdAt = Self.parseServerDate(createdAtValue),
              let updatedAt = Self.parseServerDate(updatedAtValue) else {
            throw StoreError.invalidServerChange("\(changeType) is missing required fields")
        }

        return CheckInEntry(
            id: id,
            itemId: itemId,
            occurredAt: occurredAt,
            note: payload["note"]?.stringValue ?? "",
            showInTimeline: showInTimeline,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: payload["deletedAt"]?.stringValue.flatMap(Self.parseServerDate),
            syncStatus: "synced"
        )
    }

    private func parseTagAliasPayload(
        _ payload: [String: JSONValue],
        changeType: String
    ) throws -> TimelineTagAlias {
        guard let id = payload["id"]?.stringValue,
              let tagId = payload["tagId"]?.stringValue,
              let alias = payload["alias"]?.stringValue,
              let normalizedAlias = payload["normalizedAlias"]?.stringValue,
              let createdAtValue = payload["createdAt"]?.stringValue else {
            throw StoreError.invalidServerChange("\(changeType) is missing required fields")
        }

        guard let createdAt = Self.parseServerDate(createdAtValue) else {
            throw StoreError.invalidServerChange("\(changeType) has invalid createdAt")
        }

        return TimelineTagAlias(
            id: id,
            tagId: tagId,
            alias: alias,
            normalizedAlias: normalizedAlias,
            createdAt: createdAt,
            deletedAt: payload["deletedAt"]?.stringValue.flatMap(Self.parseServerDate)
        )
    }

    private func parseAssignedTagPayload(
        _ payload: [String: JSONValue],
        changeType: String,
        database: LocalDatabase,
        allowMissingTag: Bool = false
    ) throws -> TimelineAssignedTag? {
        guard let id = payload["id"]?.stringValue,
              let postId = payload["postId"]?.stringValue,
              let tagId = payload["tagId"]?.stringValue,
              let role = payload["role"]?.stringValue,
              let source = payload["source"]?.stringValue,
              let createdAtValue = payload["createdAt"]?.stringValue,
              let updatedAtValue = payload["updatedAt"]?.stringValue else {
            throw StoreError.invalidServerChange("\(changeType) is missing required fields")
        }

        guard let createdAt = Self.parseServerDate(createdAtValue),
              let updatedAt = Self.parseServerDate(updatedAtValue) else {
            throw StoreError.invalidServerChange("\(changeType) has invalid timestamps")
        }

        guard let tag = try database.fetchTag(id: tagId) else {
            if allowMissingTag {
                return nil
            }
            throw StoreError.invalidServerChange("\(changeType) references a missing local tag")
        }

        return TimelineAssignedTag(
            id: id,
            postId: postId,
            tagId: tagId,
            role: role,
            source: source,
            confidence: payload["confidence"]?.doubleValue,
            aiSummaryId: payload["aiSummaryId"]?.stringValue,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: payload["deletedAt"]?.stringValue.flatMap(Self.parseServerDate),
            tag: tag
        )
    }

    private func parseStringArray(_ value: JSONValue?) -> [String] {
        value?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    private func parseIntegerArray(_ value: JSONValue?) -> [Int] {
        value?.arrayValue?.compactMap(\.intValue) ?? []
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
