import Foundation

extension TimelineStore {
    func createPost(text: String, imageData: [Data], occurredAt: Date) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !imageData.isEmpty else {
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let postId = UUID().uuidString
            let media = try persistImages(postId: postId, imageData: imageData, createdAt: now)
            let payload = try makeCreatePostPayload(text: trimmedText, occurredAt: occurredAt)

            let post = TimelinePost(
                id: postId,
                text: trimmedText,
                isFavorite: false,
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

            try database.insertPost(post, media: media, operation: operation)
            try await reload()
            try refreshPendingCounts()

            if isAuthenticated {
                Task {
                    await syncNow()
                }
            }

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

            if isAuthenticated {
                await syncNow()
            }
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

            if isAuthenticated {
                Task {
                    await syncNow()
                }
            }
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

            if isAuthenticated {
                Task {
                    await syncNow()
                }
            }

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createComment(postId: String, text: String) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return false
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let commentId = UUID().uuidString
            let payload = try makeCreateCommentPayload(postId: postId, text: trimmedText, createdAt: now)
            let comment = TimelineComment(
                id: commentId,
                postId: postId,
                text: trimmedText,
                createdAt: now,
                updatedAt: now,
                serverVersion: nil,
                syncStatus: "pending",
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

            if isAuthenticated {
                Task {
                    await syncNow()
                }
            }

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteComment(_ comment: TimelineComment) async {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            let now = Date()
            let payload = try makeDeleteCommentPayload(postId: comment.postId, deletedAt: now)
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
                createdAt: now,
                updatedAt: now,
                sentAt: nil
            )

            try database.softDeleteComment(commentId: comment.id, deletedAt: now, operation: operation)
            try await reload()
            try refreshPendingCounts()

            if isAuthenticated {
                Task {
                    await syncNow()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
