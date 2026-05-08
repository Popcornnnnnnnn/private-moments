import Foundation

extension TimelineStore {
    func createPost(
        text: String,
        imageData: [Data],
        video: PreparedMomentMedia? = nil,
        audio: PreparedMomentMedia? = nil,
        occurredAt: Date,
        primaryTagId: String? = nil
    ) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !imageData.isEmpty || video != nil || audio != nil else {
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let postId = UUID().uuidString
            let media = try persistPreparedMedia(
                postId: postId,
                imageData: imageData,
                video: video,
                audio: audio,
                createdAt: now
            )
            let payload = try makeCreatePostPayload(text: trimmedText, occurredAt: occurredAt, primaryTagId: primaryTagId)

            let post = TimelinePost(
                id: postId,
                text: trimmedText,
                isFavorite: false,
                isPinned: false,
                pinnedAt: nil,
                aiTagProcessedAt: nil,
                tagsUserEditedAt: nil,
                occurredAt: occurredAt,
                localCreatedAt: now,
                localUpdatedAt: now,
                localEditedAt: nil,
                serverVersion: nil,
                syncStatus: "pending",
                deletedAt: nil
            )
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "create_post",
                entityType: "post",
                entityId: postId,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.insertPost(post, media: media, operation: operation, primaryTagId: primaryTagId)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deletePost(_ item: TimelineItem) async {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let payload = try makeDeletePostPayload(deletedAt: now)
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "delete_post",
                entityType: "post",
                entityId: item.post.id,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.softDeletePost(postId: item.post.id, deletedAt: now, operation: operation)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFavorite(_ item: TimelineItem) async {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let nextValue = !item.post.isFavorite
            let payload = try makeFavoritePayload(isFavorite: nextValue, updatedAt: now)
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "update_post_favorite",
                entityType: "post",
                entityId: item.post.id,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.updateFavorite(
                postId: item.post.id,
                isFavorite: nextValue,
                updatedAt: now,
                operation: operation
            )
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePinned(_ item: TimelineItem) async {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let nextValue = !item.post.isPinned
            let pinnedAt = nextValue ? now : nil
            let payload = try makePinPayload(isPinned: nextValue, pinnedAt: pinnedAt, updatedAt: now)
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "update_post_pin",
                entityType: "post",
                entityId: item.post.id,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.updatePinned(
                postId: item.post.id,
                isPinned: nextValue,
                pinnedAt: pinnedAt,
                updatedAt: now,
                operation: operation
            )
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePost(
        item: TimelineItem,
        text: String,
        occurredAt: Date,
        mediaItems: [MomentEditMediaItem]
    ) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !mediaItems.isEmpty else {
            errorMessage = "Add text or at least one image before saving."
            return false
        }

        guard canEdit(item) else {
            errorMessage = "Wait until this moment finishes syncing before editing."
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let media = try await Self.materializeEditedMedia(postId: item.post.id, mediaItems: mediaItems, updatedAt: now)
            let payload = try makeUpdatePostPayload(
                text: trimmedText,
                occurredAt: occurredAt,
                updatedAt: now,
                media: media
            )
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "update_post",
                entityType: "post",
                entityId: item.post.id,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.updatePost(
                postId: item.post.id,
                text: trimmedText,
                occurredAt: occurredAt,
                localEditedAt: now,
                finalMedia: media,
                operation: operation
            )
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createComment(postId: String, text: String) async -> TimelineComment? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        guard trimmedText.count <= 500 else {
            errorMessage = "Comments can be up to 500 characters."
            return nil
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            guard let post = try database.fetchPost(id: postId), post.deletedAt == nil else {
                throw StoreError.commentTargetUnavailable
            }

            let now = Date()
            let commentId = UUID().uuidString
            let payload = try makeCreateCommentPayload(postId: post.id, text: trimmedText, createdAt: now)
            let comment = TimelineComment(
                id: commentId,
                postId: post.id,
                text: trimmedText,
                createdAt: now,
                updatedAt: now,
                serverVersion: nil,
                deletedAt: nil
            )
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "create_comment",
                entityType: "comment",
                entityId: commentId,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.insertComment(comment, operation: operation)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()

            return comment
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteComment(_ comment: TimelineComment) async {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            let deletedAt = Date()
            let payload = try makeDeleteCommentPayload(postId: comment.postId, deletedAt: deletedAt)
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "delete_comment",
                entityType: "comment",
                entityId: comment.id,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: deletedAt,
                updatedAt: deletedAt,
                sentAt: nil
            )

            try database.softDeleteComment(comment: comment, deletedAt: deletedAt, operation: operation)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTags(item: TimelineItem, primaryTagId: String?, topicTagIds: [String]) async -> Bool {
        guard canEdit(item) else {
            errorMessage = "Wait until this moment finishes syncing before editing tags."
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let payload = try makeSetPostTagsPayload(
                primaryTagId: primaryTagId,
                topicTagIds: topicTagIds,
                updatedAt: now
            )
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "set_post_tags",
                entityType: "post",
                entityId: item.post.id,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.setPostTags(
                postId: item.post.id,
                primaryTagId: primaryTagId,
                topicTagIds: topicTagIds,
                updatedAt: now,
                operation: operation
            )
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createTag(type: String, name: String, colorHex: String? = nil) async -> TimelineTag? {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty, cleanedName.count <= 40 else {
            errorMessage = "Tags can be up to 40 characters."
            return nil
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let normalizedName = LocalDatabase.normalizedTagName(cleanedName)
            if let existingTag = try database.fetchTag(normalizedName: normalizedName) {
                errorMessage = duplicateTagMessage(existingTag, requestedType: type)
                return nil
            }

            let tag = TimelineTag(
                id: UUID().uuidString,
                type: type,
                name: cleanedName,
                normalizedName: normalizedName,
                colorHex: colorHex,
                isDefault: false,
                isArchived: false,
                aiUsableAsPrimary: false,
                createdAt: now,
                updatedAt: now,
                archivedAt: nil
            )
            let payload = try makeUpsertTagPayload(
                type: type,
                name: cleanedName,
                colorHex: colorHex,
                aiUsableAsPrimary: false,
                updatedAt: now
            )
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "upsert_tag",
                entityType: "tag",
                entityId: tag.id,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.saveTag(tag, operation: operation)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()

            return tag
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateTag(_ tag: TimelineTag, name: String, colorHex: String? = nil) async -> Bool {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty, cleanedName.count <= 40 else {
            errorMessage = "Tags can be up to 40 characters."
            return false
        }

        if tag.isDefaultPrimaryTag && cleanedName != tag.name {
            errorMessage = "Default primary tags cannot be renamed."
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let normalizedName = LocalDatabase.normalizedTagName(cleanedName)
            if let existingTag = try database.fetchTag(normalizedName: normalizedName),
               existingTag.id != tag.id {
                errorMessage = duplicateTagMessage(existingTag, requestedType: tag.type)
                return false
            }

            var updatedTag = tag
            updatedTag.name = cleanedName
            updatedTag.normalizedName = normalizedName
            updatedTag.colorHex = updatedTag.type == "primary" ? colorHex : nil
            updatedTag.updatedAt = now

            let payload = try makeUpsertTagPayload(
                type: updatedTag.type,
                name: updatedTag.name,
                colorHex: updatedTag.colorHex,
                isDefault: updatedTag.isDefaultPrimaryTag,
                aiUsableAsPrimary: updatedTag.aiUsableAsPrimary,
                updatedAt: now
            )
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "upsert_tag",
                entityType: "tag",
                entityId: updatedTag.id,
                payloadJson: payload,
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.saveTag(updatedTag, operation: operation)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func archiveTag(_ tag: TimelineTag) async -> Bool {
        if tag.isDefaultPrimaryTag {
            errorMessage = "Default primary tags cannot be archived."
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "archive_tag",
                entityType: "tag",
                entityId: tag.id,
                payloadJson: try makeArchiveTagPayload(archivedAt: now),
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.archiveTag(tag, archivedAt: now, operation: operation)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restoreTag(_ tag: TimelineTag) async -> Bool {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "restore_tag",
                entityType: "tag",
                entityId: tag.id,
                payloadJson: try makeRestoreTagPayload(restoredAt: now),
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.restoreTag(tag, restoredAt: now, operation: operation)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteTag(_ tag: TimelineTag) async -> Bool {
        guard tag.isArchived else {
            errorMessage = "Archive tags before deleting them permanently."
            return false
        }

        if tag.isDefaultPrimaryTag {
            errorMessage = "Default primary tags cannot be deleted."
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "delete_tag",
                entityType: "tag",
                entityId: tag.id,
                payloadJson: try makeDeleteTagPayload(deletedAt: now),
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.deleteArchivedTag(tag, operation: operation)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createTagAlias(tag: TimelineTag, alias: String) async -> Bool {
        let cleanedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedAlias.isEmpty, cleanedAlias.count <= 40 else {
            errorMessage = "Aliases can be up to 40 characters."
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let tagAlias = TimelineTagAlias(
                id: UUID().uuidString,
                tagId: tag.id,
                alias: cleanedAlias,
                normalizedAlias: LocalDatabase.normalizedTagName(cleanedAlias),
                createdAt: now,
                deletedAt: nil
            )
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "upsert_tag_alias",
                entityType: "tag_alias",
                entityId: tagAlias.id,
                payloadJson: try makeUpsertTagAliasPayload(tagId: tag.id, alias: cleanedAlias),
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.saveTagAlias(tagAlias, operation: operation)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteTagAlias(_ alias: TimelineTagAlias) async -> Bool {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "delete_tag_alias",
                entityType: "tag_alias",
                entityId: alias.id,
                payloadJson: try makeDeleteTagAliasPayload(deletedAt: now),
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.softDeleteTagAlias(alias, deletedAt: now, operation: operation)
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func mergeTopicTag(_ sourceTag: TimelineTag, into targetTag: TimelineTag) async -> Bool {
        guard sourceTag.type == "topic", targetTag.type == "topic", sourceTag.id != targetTag.id else {
            errorMessage = "Choose two different topic tags to merge."
            return false
        }

        guard !targetTag.isArchived else {
            errorMessage = "Merge into an active topic tag."
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let aliasId = UUID().uuidString
            let operation = OutboxOperation(
                id: UUID().uuidString,
                opId: UUID().uuidString,
                type: "merge_tag",
                entityType: "tag",
                entityId: sourceTag.id,
                payloadJson: try makeMergeTagPayload(targetTagId: targetTag.id, alias: sourceTag.name, mergedAt: now),
                status: "pending",
                attemptCount: 0,
                lastError: nil,
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.mergeTopicTag(
                sourceTag: sourceTag,
                targetTag: targetTag,
                aliasName: sourceTag.name,
                aliasId: aliasId,
                mergedAt: now,
                operation: operation
            )
            try await reload()
            try refreshPendingCounts()
            syncSoonIfAuthenticated()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func syncSoonIfAuthenticated() {
        if isAuthenticated && automaticSyncEnabled {
            Task {
                await syncNow(userInitiated: false)
            }
        }
    }
}

private func duplicateTagMessage(_ tag: TimelineTag, requestedType: String) -> String {
    let existingType = tag.type == "primary" ? "Primary Tag" : "Topic Tag"
    let requestedTypeTitle = requestedType == "primary" ? "Primary Tag" : "Topic Tag"
    let archivedPrefix = tag.isArchived ? "archived " : ""

    if tag.type == requestedType {
        return "A \(archivedPrefix)\(existingType.lowercased()) named \"\(tag.name)\" already exists."
    }

    return "A \(archivedPrefix)\(existingType.lowercased()) named \"\(tag.name)\" already exists. Tag names are shared across \(requestedTypeTitle)s and \(existingType)s."
}
