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

    var database: LocalDatabase?
    var needsFollowUpSync = false
    var isDownloadingMedia = false
    var mediaDownloadsInFlight = Set<String>()
    var aiSummaryFollowUpSyncTask: Task<Void, Never>?
    var syncRetryTask: Task<Void, Never>?
    var syncRetryAttempt = 0

    func bootstrap() async {
        do {
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
}
