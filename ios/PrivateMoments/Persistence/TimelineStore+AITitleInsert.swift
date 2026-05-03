import Foundation
import os

private let aiTitleInsertLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "PrivateMoments",
    category: "AITitleInsert"
)

extension TimelineStore {
    func insertAITitleIfNeeded(for summary: TimelineAISummary, database: LocalDatabase) throws {
        guard AppSettings.aiTitleAutoInsertEnabled else {
            logAITitleInsertSkip(summary: summary, reason: "disabled", titleLength: 0)
            return
        }

        let cutoff = AppSettings.aiTitleAutoInsertCutoff
        guard summary.createdAt >= cutoff else {
            logAITitleInsertSkip(summary: summary, reason: "historical_summary", titleLength: 0)
            return
        }

        guard summary.isReady else {
            logAITitleInsertSkip(summary: summary, reason: "summary_not_ready", titleLength: 0)
            return
        }

        guard let title = MomentTextMarkdown.normalizedAITitle(summary.documentTitle) else {
            logAITitleInsertSkip(summary: summary, reason: "invalid_title", titleLength: summary.documentTitle?.count ?? 0)
            return
        }

        guard let media = try database.fetchMedia(id: summary.mediaId) else {
            logAITitleInsertSkip(summary: summary, reason: "missing_media", titleLength: title.count)
            return
        }

        guard media.isAudio else {
            logAITitleInsertSkip(summary: summary, reason: "non_audio_media", titleLength: title.count)
            return
        }

        guard media.createdAt >= cutoff else {
            logAITitleInsertSkip(summary: summary, reason: "historical_media", titleLength: title.count)
            return
        }

        guard let post = try database.fetchPost(id: summary.postId), post.deletedAt == nil else {
            logAITitleInsertSkip(summary: summary, reason: "missing_post", titleLength: title.count)
            return
        }

        guard !MomentTextMarkdown.hasLeadingTitle(post.text) else {
            logAITitleInsertSkip(summary: summary, reason: "existing_title", titleLength: title.count)
            return
        }

        let now = Date()
        let nextText = MomentTextMarkdown.insertingAITitle(title, into: post.text)
        let operation = OutboxOperation(
            id: UUID().uuidString,
            opId: UUID().uuidString,
            type: "insert_ai_title",
            entityType: "post",
            entityId: post.id,
            payloadJson: try makeInsertAITitlePayload(
                summaryId: summary.id,
                mediaId: summary.mediaId,
                insertedAt: now
            ),
            status: "pending",
            attemptCount: 0,
            lastError: nil,
            createdAt: now,
            updatedAt: now,
            sentAt: nil
        )

        try database.insertAITitle(
            postId: post.id,
            text: nextText,
            updatedAt: now,
            operation: operation
        )
        needsFollowUpSync = true

        aiTitleInsertLogger.info(
            "ai_title_insert applied postId=\(post.id, privacy: .public) mediaId=\(summary.mediaId, privacy: .public) summaryId=\(summary.id, privacy: .public) titleLength=\(title.count, privacy: .public)"
        )
    }

    private func logAITitleInsertSkip(summary: TimelineAISummary, reason: String, titleLength: Int) {
        aiTitleInsertLogger.info(
            "ai_title_insert skipped reason=\(reason, privacy: .public) postId=\(summary.postId, privacy: .public) mediaId=\(summary.mediaId, privacy: .public) summaryId=\(summary.id, privacy: .public) titleLength=\(titleLength, privacy: .public)"
        )
    }
}
