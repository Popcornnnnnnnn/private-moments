import Combine
import Foundation

@MainActor
final class TimelineStore: ObservableObject {
    @Published var items: [TimelineItem] = []
    @Published var checkInItems: [CheckInItem] = []
    @Published var checkInEntries: [CheckInEntry] = []
    @Published var checkInMedia: [CheckInMedia] = []
    @Published var isReady = false
    @Published var errorMessage: String?
    @Published var syncMessage: String?
    @Published var isSyncing = false
    @Published var isAuthenticated = false
    @Published var serverURLString = AppSettings.serverURLString
    @Published var deviceId: String?
    @Published var lastSyncCursor = 0
    @Published var pendingOperationCount = 0
    @Published var pendingUploadCount = 0
    @Published var aiSummaryRequestsInFlight = Set<String>()
    @Published var tags: [TimelineTag] = []
    @Published var tagAliases: [TimelineTagAlias] = []
    @Published var tagUsageCounts: [String: Int] = [:]
    @Published var showTagsInTimeline = AppSettings.showTagsInTimeline
    @Published var aiTitleAutoInsertEnabled = AppSettings.aiTitleAutoInsertEnabled
    @Published var appAppearanceMode = AppSettings.appAppearanceMode
    @Published var appLanguageMode = AppSettings.appLanguageMode
    @Published var aiLanguageMode = AppSettings.aiLanguageMode
    @Published var automaticSyncEnabled = AppSettings.automaticSyncEnabled
    @Published var weeklyReviews: [ReviewPayload] = []
    @Published var isLoadingReviews = false
    @Published var reviewGenerationInFlightId: String?
    @Published var reviewMutationIds = Set<String>()
    @Published var autoWeeklyReviewEnabled = AppSettings.autoWeeklyReviewEnabled
    @Published var publishWeeklyReviewToMoments = AppSettings.publishWeeklyReviewToMoments

    var database: LocalDatabase?
    var needsFollowUpSync = false
    var isDownloadingMedia = false
    var mediaDownloadsInFlight = Set<String>()
    var aiSummaryFollowUpSyncTask: Task<Void, Never>?
    var syncRetryTask: Task<Void, Never>?
    var syncRetryAttempt = 0

    func bootstrap() async {
        do {
            let launchArguments = ProcessInfo.processInfo.arguments
            let shouldSeedDemoData = launchArguments.contains("--private-moments-demo-data")
            let shouldResetDemoData = launchArguments.contains("--private-moments-demo-data-reset")

            if shouldSeedDemoData {
                AppSettings.showTagsInTimeline = true
                AppSettings.automaticSyncEnabled = false
                AppSettings.appAppearanceMode = .light
                AppSettings.appLanguageMode = .english
                showTagsInTimeline = AppSettings.showTagsInTimeline
                automaticSyncEnabled = AppSettings.automaticSyncEnabled
                appAppearanceMode = AppSettings.appAppearanceMode
                appLanguageMode = AppSettings.appLanguageMode
            }

            AppSettings.ensureAITitleAutoInsertCutoff()
            database = try LocalDatabase.open()
            loadSessionState()
            if shouldSeedDemoData {
                try database?.seedDemoDataIfNeeded(reset: shouldResetDemoData)
            } else if launchArguments.contains("--private-moments-checkins-mock") {
                try database?.seedCheckInMockDataIfNeeded()
            }
            try await reload()
            try refreshPendingCounts()
            isReady = true

            if isAuthenticated && automaticSyncEnabled {
                Task {
                    await syncAfterBootstrap()
                }
            }

            if isAuthenticated {
                Task {
                    await refreshReviewSettings()
                    await refreshReviews()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() async throws {
        guard let database else {
            return
        }

        items = try database.fetchTimelineItems()
        checkInItems = try database.fetchCheckInItems(includeArchived: true)
        checkInEntries = try database.fetchCheckInEntries()
        checkInMedia = try database.fetchCheckInMedia()
        tags = try database.fetchTags(includeArchived: true)
        tagAliases = try database.fetchTagAliases()
        tagUsageCounts = try database.fetchTagUsageCounts()
    }

    func clearError() {
        errorMessage = nil
    }

    func item(id: String) -> TimelineItem? {
        items.first { $0.id == id }
    }

    func checkInItem(id: String) -> CheckInItem? {
        checkInItems.first { $0.id == id }
    }

    func checkInEntry(id: String) -> CheckInEntry? {
        checkInEntries.first { $0.id == id }
    }

    var checkInFeedEntries: [CheckInFeedEntry] {
        let itemById = Dictionary(uniqueKeysWithValues: checkInItems.map { ($0.id, $0) })
        let tagById = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        let mediaByEntryId = Dictionary(grouping: checkInMedia.filter { $0.deletedAt == nil }, by: \.entryId)
        return checkInEntries.compactMap { entry in
            guard let item = itemById[entry.itemId],
                  entry.deletedAt == nil,
                  item.deletedAt == nil else {
                return nil
            }

            return CheckInFeedEntry(
                entry: entry,
                item: item,
                tag: item.tagId.flatMap { tagById[$0] },
                media: mediaByEntryId[entry.id] ?? []
            )
        }
    }

    var timelineFeedItems: [MomentFeedItem] {
        let moments = items
            .filter { $0.post.deletedAt == nil }
            .map(MomentFeedItem.moment)
        let checkIns = checkInFeedEntries
            .filter { $0.entry.showInTimeline }
            .map(MomentFeedItem.checkIn)

        return (moments + checkIns).sorted { lhs, rhs in
            if lhs.occurredAt == rhs.occurredAt {
                return lhs.sortKey > rhs.sortKey
            }

            return lhs.occurredAt > rhs.occurredAt
        }
    }

    func canEdit(_ item: TimelineItem) -> Bool {
        item.post.deletedAt == nil
    }

    func refreshPendingCounts() throws {
        guard let database else {
            pendingOperationCount = 0
            pendingUploadCount = 0
            return
        }

        pendingOperationCount = try database.pendingOperationCount()
        pendingUploadCount = try database.pendingUploadCount()
    }

    func pendingOperationTypeCounts() -> [OutboxOperationTypeCount] {
        guard let database else {
            return []
        }

        return (try? database.pendingOperationTypeCounts()) ?? []
    }

    var activePrimaryTags: [TimelineTag] {
        tags.filter { $0.type == "primary" && !$0.isArchived }
    }

    var activeTopicTags: [TimelineTag] {
        tags.filter { $0.type == "topic" && !$0.isArchived }
    }

    var aliasesByTagId: [String: [TimelineTagAlias]] {
        Dictionary(grouping: tagAliases.filter { $0.deletedAt == nil }, by: \.tagId)
    }

    func setShowTagsInTimeline(_ value: Bool) {
        AppSettings.showTagsInTimeline = value
        showTagsInTimeline = value
    }

    func setAITitleAutoInsertEnabled(_ value: Bool) {
        AppSettings.aiTitleAutoInsertEnabled = value
        aiTitleAutoInsertEnabled = value
    }

    func setAppAppearanceMode(_ mode: AppAppearanceMode) {
        AppSettings.appAppearanceMode = mode
        appAppearanceMode = mode
    }

    var resolvedAppLanguage: AppResolvedLanguage {
        appLanguageMode.resolvedLanguage
    }

    func setAppLanguageMode(_ mode: AppLanguageMode) {
        AppSettings.appLanguageMode = mode
        appLanguageMode = mode
    }

    func setAILanguageMode(_ mode: AILanguageMode) {
        AppSettings.aiLanguageMode = mode
        aiLanguageMode = mode
    }

    func setAutomaticSyncEnabled(_ value: Bool) {
        AppSettings.automaticSyncEnabled = value
        automaticSyncEnabled = value

        if value {
            Task {
                await syncPendingWorkIfNeeded(showErrors: false)
            }
        } else {
            needsFollowUpSync = false
            cancelScheduledSyncRetry()
            aiSummaryFollowUpSyncTask?.cancel()
            aiSummaryFollowUpSyncTask = nil
            syncMessage = "Local-only"
        }
    }

    func refreshReviews() async {
        guard isAuthenticated else {
            weeklyReviews = []
            return
        }

        isLoadingReviews = true
        defer {
            isLoadingReviews = false
        }

        do {
            let token = try KeychainStore.deviceToken()
            let reviews = try await withAvailableAPIClient(token: token) { client in
                try await client.listReviews(kind: "weekly")
            }
            weeklyReviews = reviews
        } catch {
            handleSyncError(error, showErrors: false)
        }
    }

    func generateWeeklyReview() async {
        guard !isReviewGenerationInFlight else {
            return
        }

        reviewGenerationInFlightId = "manual-generate"
        syncMessage = "Generating review"
        defer {
            reviewGenerationInFlightId = nil
        }

        await runReviewMutation { client in
            try await client.generateWeeklyReview()
        }
    }

    func regenerateReview(_ review: ReviewPayload) async {
        guard !isReviewGenerationInFlight else {
            return
        }

        reviewGenerationInFlightId = review.id
        syncMessage = "Regenerating review"
        defer {
            reviewGenerationInFlightId = nil
        }

        await runReviewMutation { client in
            try await client.regenerateReview(reviewId: review.id)
        }
    }

    func deleteReview(_ review: ReviewPayload) async {
        guard !isReviewGenerationInFlight, !isReviewMutationInFlight(review) else {
            return
        }

        reviewMutationIds.insert(review.id)
        syncMessage = "Deleting review"
        defer {
            reviewMutationIds.remove(review.id)
        }

        guard isAuthenticated else {
            errorMessage = "Log in first"
            return
        }

        do {
            let token = try KeychainStore.deviceToken()
            _ = try await withAvailableAPIClient(token: token) { client in
                try await client.deleteReview(reviewId: review.id)
            }
            weeklyReviews.removeAll { $0.id == review.id }
            syncMessage = "Review deleted"
            await refreshReviews()
        } catch {
            handleSyncError(error, showErrors: true)
        }
    }

    func deleteReviews(at offsets: IndexSet) async {
        let reviews = offsets.compactMap { index in
            weeklyReviews.indices.contains(index) ? weeklyReviews[index] : nil
        }
        for review in reviews {
            await deleteReview(review)
        }
    }

    func isReviewMutationInFlight(_ review: ReviewPayload) -> Bool {
        review.status == "generating" || reviewMutationIds.contains(review.id)
    }

    var isReviewGenerationInFlight: Bool {
        reviewGenerationInFlightId != nil || weeklyReviews.contains { $0.status == "generating" }
    }

    func publishReviewAsMoment(_ review: ReviewPayload) async {
        guard !isReviewGenerationInFlight else {
            return
        }

        await runReviewMutation { client in
            try await client.publishReviewAsMoment(reviewId: review.id)
        }
        await syncNow()
    }

    func sendReviewFeedback(review: ReviewPayload, type: String, note: String? = nil) async {
        guard isAuthenticated else {
            return
        }

        do {
            let token = try KeychainStore.deviceToken()
            try await withAvailableAPIClient(token: token) { client in
                try await client.sendReviewFeedback(reviewId: review.id, type: type, note: note)
            }
            syncMessage = "Feedback saved"
        } catch {
            handleSyncError(error, showErrors: true)
        }
    }

    func refreshReviewSettings() async {
        guard isAuthenticated else {
            return
        }

        do {
            let token = try KeychainStore.deviceToken()
            let settings = try await withAvailableAPIClient(token: token) { client in
                try await client.reviewSettings()
            }
            AppSettings.autoWeeklyReviewEnabled = settings.autoWeeklyEnabled
            AppSettings.publishWeeklyReviewToMoments = settings.publishWeeklyToMoments
            autoWeeklyReviewEnabled = settings.autoWeeklyEnabled
            publishWeeklyReviewToMoments = settings.publishWeeklyToMoments
        } catch {
            handleSyncError(error, showErrors: false)
        }
    }

    func setAutoWeeklyReviewEnabled(_ value: Bool) {
        AppSettings.autoWeeklyReviewEnabled = value
        autoWeeklyReviewEnabled = value
        Task {
            await pushReviewSettings()
        }
    }

    func setPublishWeeklyReviewToMoments(_ value: Bool) {
        AppSettings.publishWeeklyReviewToMoments = value
        publishWeeklyReviewToMoments = value
        Task {
            await pushReviewSettings()
        }
    }

    private func runReviewMutation(_ operation: (APIClient) async throws -> ReviewPayload) async {
        guard isAuthenticated else {
            errorMessage = "Log in first"
            return
        }

        isLoadingReviews = true
        defer {
            isLoadingReviews = false
        }

        do {
            let token = try KeychainStore.deviceToken()
            let review = try await withAvailableAPIClient(token: token, operation: operation)
            weeklyReviews.removeAll { $0.id == review.id }
            weeklyReviews.insert(review, at: 0)
            await refreshReviews()
        } catch {
            handleSyncError(error, showErrors: true)
        }
    }

    private func pushReviewSettings() async {
        guard isAuthenticated else {
            return
        }

        do {
            let token = try KeychainStore.deviceToken()
            let settings = try await withAvailableAPIClient(token: token) { client in
                try await client.updateReviewSettings(
                    autoWeeklyEnabled: autoWeeklyReviewEnabled,
                    publishWeeklyToMoments: publishWeeklyReviewToMoments
                )
            }
            AppSettings.autoWeeklyReviewEnabled = settings.autoWeeklyEnabled
            AppSettings.publishWeeklyReviewToMoments = settings.publishWeeklyToMoments
            autoWeeklyReviewEnabled = settings.autoWeeklyEnabled
            publishWeeklyReviewToMoments = settings.publishWeeklyToMoments
        } catch {
            handleSyncError(error, showErrors: true)
        }
    }
}
