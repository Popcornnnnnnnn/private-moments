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
    @State private var isClearingCache = false
    @State private var confirmClearCache = false

    var body: some View {
        Form {
            if let localStats {
                iPhoneSection(localStats)
                mediaCacheSection(localStats)
                syncHealthSection(localStats, serverStatus: serverStatus)
            } else {
                Section("This iPhone") {
                    ProgressView("Loading")
                }
            }

            if let serverStatus {
                macServerSection(serverStatus)
                if let aiSummaries = serverStatus.aiSummaries {
                    aiSummarySection(aiSummaries)
                }
            }
        }
        .navigationTitle("Storage & Diagnostics")
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
                    .accessibilityLabel("Refresh diagnostics")
                }
            }
        }
        .task {
            await refresh()
        }
        .alert("Clear downloaded media cache?", isPresented: $confirmClearCache) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task {
                    await clearDownloadedCache()
                }
            }
        } message: {
            Text("Downloaded full audio and video files will be removed from this iPhone. They can be downloaded again from your Mac when played.")
        }
    }

    private func iPhoneSection(_ stats: LocalStorageStats) -> some View {
        Section("This iPhone") {
            LabeledContent("Total", value: StorageByteFormatter.string(from: stats.totalBytes))
            LabeledContent("Database", value: StorageByteFormatter.string(from: stats.databaseBytes))
            LabeledContent("Media files", value: StorageByteFormatter.string(from: stats.mediaBytes))
        }
    }

    private func mediaCacheSection(_ stats: LocalStorageStats) -> some View {
        Section("Downloaded Media Cache") {
            LabeledContent("Audio and video", value: StorageByteFormatter.string(from: stats.audioVideoCacheBytes))

            Button(role: .destructive) {
                confirmClearCache = true
            } label: {
                if isClearingCache {
                    ProgressView()
                } else {
                    Text("Clear Audio and Video Cache")
                }
            }
            .disabled(stats.audioVideoCacheBytes == 0 || isClearingCache)
        }
    }

    private func syncHealthSection(_ stats: LocalStorageStats, serverStatus: AdminStatusResponse?) -> some View {
        Section("Sync Health") {
            LabeledContent("Status", value: syncStatusText(for: stats))
            LabeledContent("Pending changes", value: "\(stats.pendingChanges)")
            LabeledContent("Pending uploads", value: "\(stats.pendingUploads)")
            LabeledContent("Failed uploads", value: "\(stats.failedUploads)")
            LabeledContent("This iPhone cursor", value: "\(AppSettings.lastSyncCursor)")

            if let serverVersion = serverStatus?.sync?.latestServerChangeVersion {
                LabeledContent("Mac change version", value: "\(serverVersion)")

                let changesBehind = max(0, serverVersion - AppSettings.lastSyncCursor)
                if changesBehind > 0 {
                    LabeledContent("Remote changes", value: "\(changesBehind) behind")
                }
            }
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

    private func aiSummarySection(_ diagnostics: AdminAISummaryDiagnostics) -> some View {
        Section("AI Summaries") {
            LabeledContent("Ready", value: "\(diagnostics.ready)")
            LabeledContent("Transcribing", value: "\(diagnostics.transcribing)")
            LabeledContent("Summarizing", value: "\(diagnostics.summarizing)")
            LabeledContent("Failed", value: "\(diagnostics.failed)")

            ForEach(diagnostics.recent.prefix(5)) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusText(for: item))
                        .font(.subheadline)
                    Text(diagnosticDetail(for: item))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.vertical, 2)
            }
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

    private func statusText(for item: AdminAISummaryDiagnosticItem) -> String {
        if let errorCode = item.errorCode, !errorCode.isEmpty {
            return "\(item.status) / \(errorCode)"
        }

        return item.status
    }

    private func shortTimestamp(_ value: String) -> String {
        value.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
    }

    private func diagnosticDetail(for item: AdminAISummaryDiagnosticItem) -> String {
        var parts = ["Updated \(shortTimestamp(item.updatedAt))"]

        if let inputTranscriptLength = item.inputTranscriptLength {
            parts.append("Transcript \(inputTranscriptLength) chars")
        }

        if let inputDurationSeconds = item.inputDurationSeconds {
            parts.append("Duration \(durationText(inputDurationSeconds))")
        }

        if let ageSeconds = item.ageSeconds {
            parts.append("Stuck for \(durationText(Double(ageSeconds)))")
        }

        if let retryHint = item.retryHint, !retryHint.isEmpty {
            parts.append(retryHint)
        }

        return parts.joined(separator: " · ")
    }

    private func durationText(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }

        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return "\(minutes)m \(remainingSeconds)s"
    }

    private func refresh() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        if store.isAuthenticated {
            await store.syncPendingWorkIfNeeded(showErrors: false)
        }

        localStats = try? LocalStorageStatsLoader.load(database: store.database)
        serverStatus = await loadServerStatus()
    }

    private func clearDownloadedCache() async {
        guard !isClearingCache else {
            return
        }

        isClearingCache = true
        defer {
            isClearingCache = false
        }

        do {
            _ = try store.database?.clearDownloadedAudioVideoCache()
            try await store.reload()
            localStats = try LocalStorageStatsLoader.load(database: store.database)
        } catch {
            store.errorMessage = error.localizedDescription
        }
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
