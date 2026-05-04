import Combine
import Foundation

@MainActor
final class TimelineStore: ObservableObject {
    @Published var items: [TimelineItem] = []
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

    var database: LocalDatabase?
    var needsFollowUpSync = false
    var isDownloadingMedia = false
    var mediaDownloadsInFlight = Set<String>()
    var aiSummaryFollowUpSyncTask: Task<Void, Never>?
    var syncRetryTask: Task<Void, Never>?
    var syncRetryAttempt = 0

    func bootstrap() async {
        do {
            AppSettings.ensureAITitleAutoInsertCutoff()
            database = try LocalDatabase.open()
            loadSessionState()
            try await reload()
            try refreshPendingCounts()
            isReady = true

            if isAuthenticated {
                Task {
                    await syncAfterBootstrap()
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

    func canEdit(_ item: TimelineItem) -> Bool {
        item.post.syncStatus == "synced" || item.post.syncStatus == "failed"
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
}
