import Foundation

extension TimelineStore {
    func aiSummary(id: String) -> TimelineAISummary? {
        for item in items {
            if let summary = item.aiSummaries.first(where: { $0.id == id }) {
                return summary
            }
        }

        return nil
    }

    func requestAISummary(for media: TimelineMedia, forceRegenerate: Bool = false) async {
        aiSummaryRequestsInFlight.insert(media.id)
        defer {
            aiSummaryRequestsInFlight.remove(media.id)
        }

        do {
            guard let database else {
                throw StoreError.notReady
            }
            guard isAuthenticated,
                  let token = try KeychainStore.deviceToken() else {
                throw StoreError.notAuthenticated
            }

            let client = APIClient(baseURL: try normalizeServerURL(AppSettings.serverURLString), token: token)
            let payload = try await client.requestMediaSummary(
                postId: media.postId,
                mediaId: media.id,
                forceRegenerate: forceRegenerate,
                aiLanguage: aiLanguageMode
            )
            try database.upsertAISummary(payload.timelineSummary())
            try await reload()
        } catch {
            await markAISummaryRequestFailed(media: media, error: error)
        }
    }

    func deleteAISummary(_ summary: TimelineAISummary) async {
        do {
            guard let database else {
                throw StoreError.notReady
            }
            guard isAuthenticated,
                  let token = try KeychainStore.deviceToken() else {
                throw StoreError.notAuthenticated
            }

            let client = APIClient(baseURL: try normalizeServerURL(AppSettings.serverURLString), token: token)
            let payload = try await client.deleteMediaSummary(summaryId: summary.id)
            try database.upsertAISummary(payload.timelineSummary())
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markAISummaryRequestFailed(media: TimelineMedia, error: Error) async {
        do {
            guard let database else {
                return
            }

            let now = Date()
            let existing = try database.fetchAISummary(mediaId: media.id)
            let failed = TimelineAISummary(
                id: existing?.id ?? "local-\(media.id)",
                postId: media.postId,
                mediaId: media.id,
                status: "failed",
                format: existing?.format,
                language: existing?.language,
                overview: existing?.overview,
                keyPoints: existing?.keyPoints ?? [],
                sections: existing?.sections ?? [],
                summaryText: existing?.summaryText,
                documentTitle: existing?.documentTitle,
                oneLiner: existing?.oneLiner,
                documentBlocks: existing?.documentBlocks ?? [],
                inputTranscriptLength: existing?.inputTranscriptLength,
                inputDurationSeconds: media.durationSeconds,
                promptVersion: existing?.promptVersion ?? "media-summary-v1",
                provider: existing?.provider,
                model: existing?.model,
                errorCode: "request_failed",
                errorMessage: error.localizedDescription,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now,
                deletedAt: nil
            )

            try database.upsertAISummary(failed)
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
