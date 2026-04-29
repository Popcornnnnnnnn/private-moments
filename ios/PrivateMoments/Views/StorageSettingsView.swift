import SwiftUI

struct StorageSummaryLink: View {
    @EnvironmentObject private var store: TimelineStore
    @State private var localStats: LocalStorageStats?
    @State private var serverStats: ServerStorageStats?

    var body: some View {
        NavigationLink {
            StorageDetailsView()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Storage")
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 3)
        }
        .task {
            await refresh()
        }
    }

    private var summary: String {
        guard let localStats else {
            return "Checking storage"
        }

        let local = "iPhone \(StorageByteFormatter.string(from: localStats.totalBytes))"
        guard let serverStats else {
            return local
        }

        return "\(local), Mac \(StorageByteFormatter.string(from: serverStats.totalBytes))"
    }

    private func refresh() async {
        localStats = try? LocalStorageStatsLoader.load(database: store.database)
        serverStats = await loadServerStats()
    }

    private func loadServerStats() async -> ServerStorageStats? {
        guard store.isAuthenticated,
              let token = try? KeychainStore.deviceToken() else {
            return nil
        }

        do {
            let client = APIClient(baseURL: try store.normalizeServerURL(store.serverURLString), token: token)
            return try await client.adminStatus().storage
        } catch {
            return nil
        }
    }
}

struct StorageDetailsView: View {
    @EnvironmentObject private var store: TimelineStore
    @State private var localStats: LocalStorageStats?
    @State private var serverStatus: AdminStatusResponse?
    @State private var isRefreshing = false

    var body: some View {
        Form {
            if let localStats {
                iPhoneSection(localStats)
                syncHealthSection(localStats)
            } else {
                Section("This iPhone") {
                    ProgressView("Loading")
                }
            }

            if let serverStatus {
                macServerSection(serverStatus)
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isRefreshing {
                    ProgressView()
                } else {
                    Button {
                        Task {
                            await refresh()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh storage")
                }
            }
        }
        .task {
            await refresh()
        }
    }

    private func iPhoneSection(_ stats: LocalStorageStats) -> some View {
        Section("This iPhone") {
            LabeledContent("Total", value: StorageByteFormatter.string(from: stats.totalBytes))
            LabeledContent("Database", value: StorageByteFormatter.string(from: stats.databaseBytes))
            LabeledContent("Image cache", value: StorageByteFormatter.string(from: stats.mediaBytes))
        }
    }

    private func syncHealthSection(_ stats: LocalStorageStats) -> some View {
        Section("Sync Health") {
            LabeledContent("Status", value: syncStatusText(for: stats))
            LabeledContent("Pending changes", value: "\(stats.pendingChanges)")
            LabeledContent("Pending uploads", value: "\(stats.pendingUploads)")
            LabeledContent("Failed uploads", value: "\(stats.failedUploads)")
        }
    }

    private func macServerSection(_ status: AdminStatusResponse) -> some View {
        Section("Mac Server") {
            LabeledContent("Total", value: StorageByteFormatter.string(from: status.storage.totalBytes))

            if let databaseBytes = status.storage.databaseBytes {
                LabeledContent("Database", value: StorageByteFormatter.string(from: databaseBytes))
            }

            if let mediaBytes = status.storage.mediaBytes {
                LabeledContent("Media files", value: StorageByteFormatter.string(from: mediaBytes))
            }

            if let logsBytes = status.storage.logsBytes {
                LabeledContent("Logs", value: StorageByteFormatter.string(from: logsBytes))
            }

            if let availableBytes = status.storage.availableBytes {
                LabeledContent("Available disk", value: StorageByteFormatter.string(from: availableBytes))
            }

            LabeledContent("Posts", value: "\(status.counts.posts)")
            LabeledContent("Media", value: "\(status.counts.media)")
        }
    }

    private func syncStatusText(for stats: LocalStorageStats) -> String {
        if stats.pendingChanges == 0 && stats.pendingUploads == 0 && stats.failedUploads == 0 {
            return "All synced"
        }

        if stats.failedUploads > 0 {
            return "\(stats.failedUploads) failed uploads"
        }

        if stats.pendingUploads > 0 {
            return "\(stats.pendingUploads) pending uploads"
        }

        return "\(stats.pendingChanges) pending changes"
    }

    private func refresh() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        localStats = try? LocalStorageStatsLoader.load(database: store.database)
        serverStatus = await loadServerStatus()
    }

    private func loadServerStatus() async -> AdminStatusResponse? {
        guard store.isAuthenticated,
              let token = try? KeychainStore.deviceToken() else {
            return nil
        }

        do {
            let client = APIClient(baseURL: try store.normalizeServerURL(store.serverURLString), token: token)
            return try await client.adminStatus()
        } catch {
            return nil
        }
    }
}
