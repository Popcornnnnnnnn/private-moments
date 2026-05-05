import SwiftUI

struct StorageSummaryLink: View {
    @Environment(\.appLanguage) private var appLanguage
    @EnvironmentObject private var store: TimelineStore
    @State private var localStats: LocalStorageStats?
    @State private var serverStats: ServerStorageStats?

    var body: some View {
        NavigationLink {
            StorageDetailsView()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("Storage", appLanguage))
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
            return L10n.t("Checking storage", appLanguage)
        }

        let local = "iPhone \(StorageByteFormatter.string(from: localStats.totalBytes))"
        guard let serverStats else {
            return local
        }

        return "\(local), Mac \(StorageByteFormatter.string(from: serverStats.totalBytes))"
    }

    private func refresh() async {
        localStats = try? LocalStorageStatsLoader.load(database: store.database)
        serverStats = store.automaticSyncEnabled ? await loadServerStats() : nil
    }

    private func loadServerStats() async -> ServerStorageStats? {
        guard store.isAuthenticated,
              let token = try? KeychainStore.deviceToken() else {
            return nil
        }

        do {
            return try await store.withAvailableAPIClient(token: token) { client in
                try await client.adminStatus().storage
            }
        } catch {
            return nil
        }
    }
}

struct StorageDetailsView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage
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
                Section(L10n.t("This iPhone", appLanguage)) {
                    ProgressView(L10n.t("Loading", appLanguage))
                }
            }

            if let serverStatus {
                macServerSection(serverStatus)
                if let aiSummaries = serverStatus.aiSummaries {
                    aiSummarySection(aiSummaries)
                }
                if let tags = serverStatus.tags {
                    tagSection(tags)
                }
            }
        }
        .navigationTitle(L10n.t("Storage & Diagnostics", appLanguage))
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
                    .accessibilityLabel(L10n.t("Refresh diagnostics", appLanguage))
                }
            }
        }
        .task {
            await refresh()
        }
        .alert(L10n.t("Clear downloaded media cache?", appLanguage), isPresented: $confirmClearCache) {
            Button(L10n.t("Cancel", appLanguage), role: .cancel) {}
            Button(L10n.t("Clear", appLanguage), role: .destructive) {
                Task {
                    await clearDownloadedCache()
                }
            }
        } message: {
            Text(L10n.t("Downloaded full audio and video files will be removed from this iPhone. They can be downloaded again from your Mac when played.", appLanguage))
        }
    }

    private func iPhoneSection(_ stats: LocalStorageStats) -> some View {
        Section(L10n.t("This iPhone", appLanguage)) {
            LabeledContent(L10n.t("Total", appLanguage), value: StorageByteFormatter.string(from: stats.totalBytes))
            LabeledContent(L10n.t("Database", appLanguage), value: StorageByteFormatter.string(from: stats.databaseBytes))
            LabeledContent(L10n.t("Media files", appLanguage), value: StorageByteFormatter.string(from: stats.mediaBytes))
        }
    }

    private func mediaCacheSection(_ stats: LocalStorageStats) -> some View {
        Section(L10n.t("Downloaded Media Cache", appLanguage)) {
            LabeledContent(L10n.t("Audio and video", appLanguage), value: StorageByteFormatter.string(from: stats.audioVideoCacheBytes))

            Button(role: .destructive) {
                confirmClearCache = true
            } label: {
                if isClearingCache {
                    ProgressView()
                } else {
                    Text(L10n.t("Clear Audio and Video Cache", appLanguage))
                }
            }
            .disabled(stats.audioVideoCacheBytes == 0 || isClearingCache)
        }
    }

    private func syncHealthSection(_ stats: LocalStorageStats, serverStatus: AdminStatusResponse?) -> some View {
        Section(L10n.t("Sync Health", appLanguage)) {
            LabeledContent(L10n.t("Status", appLanguage), value: syncStatusText(for: stats))
            LabeledContent(L10n.t("Pending changes", appLanguage), value: "\(stats.pendingChanges)")
            LabeledContent(L10n.t("Pending uploads", appLanguage), value: "\(stats.pendingUploads)")
            LabeledContent(L10n.t("Failed uploads", appLanguage), value: "\(stats.failedUploads)")
            LabeledContent(L10n.t("This iPhone cursor", appLanguage), value: "\(AppSettings.lastSyncCursor)")

            if !store.automaticSyncEnabled {
                LabeledContent(L10n.t("Automatic Sync", appLanguage), value: L10n.t("Off", appLanguage))
            }

            if let serverVersion = serverStatus?.sync?.latestServerChangeVersion {
                LabeledContent(L10n.t("Mac change version", appLanguage), value: "\(serverVersion)")

                let changesBehind = max(0, serverVersion - AppSettings.lastSyncCursor)
                if changesBehind > 0 {
                    LabeledContent(L10n.t("Remote changes", appLanguage), value: "\(changesBehind) \(L10n.t("behind", appLanguage))")
                }
            }

            if let sync = serverStatus?.sync {
                LabeledContent(L10n.t("Mac reachability", appLanguage), value: L10n.t("Reachable", appLanguage))
                LabeledContent(L10n.t("Server pending ops", appLanguage), value: "\(sync.pendingOperations ?? 0)")
                LabeledContent(L10n.t("Server rejected ops", appLanguage), value: "\(sync.rejectedOperations ?? 0)")
                LabeledContent(L10n.t("Server failed media", appLanguage), value: "\(sync.failedMediaUploads ?? 0)")
                LabeledContent(L10n.t("AI not ready", appLanguage), value: "\(sync.aiNonReady ?? 0)")

                if let lastSuccessfulSyncAt = sync.lastSuccessfulSyncAt {
                    LabeledContent(L10n.t("Last successful sync", appLanguage), value: shortTimestamp(lastSuccessfulSyncAt))
                }
                if let lastRejectedSyncAt = sync.lastRejectedSyncAt {
                    LabeledContent(L10n.t("Last rejected sync", appLanguage), value: shortTimestamp(lastRejectedSyncAt))
                }
            } else if store.automaticSyncEnabled {
                LabeledContent(L10n.t("Mac reachability", appLanguage), value: L10n.t("Unavailable", appLanguage))
            } else {
                LabeledContent(L10n.t("Mac reachability", appLanguage), value: L10n.t("Local-only", appLanguage))
            }

            if stats.missingMediaDownloads > 0 {
                LabeledContent(L10n.t("Missing media", appLanguage), value: "\(stats.missingMediaDownloads)")
            }

            Button {
                Task {
                    await syncNowFromDiagnostics()
                }
            } label: {
                Text(L10n.t(store.isSyncing ? "Syncing" : "Sync Now", appLanguage))
            }
            .disabled(!store.isAuthenticated || store.isSyncing)

            Button {
                Task {
                    await pullServerChanges()
                }
            } label: {
                Text(L10n.t("Pull Server Changes", appLanguage))
            }
            .disabled(!store.isAuthenticated || store.isSyncing)

            Button {
                Task {
                    await retryMediaUploads()
                }
            } label: {
                Text(L10n.t("Retry Uploads", appLanguage))
            }
            .disabled(!store.isAuthenticated || !store.automaticSyncEnabled || store.isSyncing || (stats.pendingUploads + stats.failedUploads) == 0)

            Button {
                Task {
                    await retryMediaDownloads()
                }
            } label: {
                Text(L10n.t("Re-download Missing Media", appLanguage))
            }
            .disabled(!store.isAuthenticated || !store.automaticSyncEnabled || stats.missingMediaDownloads == 0)
        }
    }

    private func macServerSection(_ status: AdminStatusResponse) -> some View {
        Section(L10n.t("Mac Server", appLanguage)) {
            LabeledContent(L10n.t("Total", appLanguage), value: StorageByteFormatter.string(from: status.storage.totalBytes))

            if let databaseBytes = status.storage.databaseBytes {
                LabeledContent(L10n.t("Database", appLanguage), value: StorageByteFormatter.string(from: databaseBytes))
            }

            if let mediaBytes = status.storage.mediaBytes {
                LabeledContent(L10n.t("Media files", appLanguage), value: StorageByteFormatter.string(from: mediaBytes))
            }

            if let logsBytes = status.storage.logsBytes {
                LabeledContent(L10n.t("Logs", appLanguage), value: StorageByteFormatter.string(from: logsBytes))
            }

            if let availableBytes = status.storage.availableBytes {
                LabeledContent(L10n.t("Available disk", appLanguage), value: StorageByteFormatter.string(from: availableBytes))
            }

            LabeledContent(L10n.t("Posts", appLanguage), value: "\(status.counts.posts)")
            LabeledContent(L10n.t("Media", appLanguage), value: "\(status.counts.media)")
        }
    }

    private func aiSummarySection(_ diagnostics: AdminAISummaryDiagnostics) -> some View {
        Section(L10n.t("AI Summaries", appLanguage)) {
            LabeledContent(L10n.t("Ready", appLanguage), value: "\(diagnostics.ready)")
            LabeledContent(L10n.t("Transcribing", appLanguage), value: "\(diagnostics.transcribing)")
            LabeledContent(L10n.t("Summarizing", appLanguage), value: "\(diagnostics.summarizing)")
            LabeledContent(L10n.t("Failed", appLanguage), value: "\(diagnostics.failed)")

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

    private func tagSection(_ diagnostics: AdminTagDiagnostics) -> some View {
        Section(L10n.t("Tags", appLanguage)) {
            LabeledContent(L10n.t("Primary", appLanguage), value: "\(diagnostics.primary)")
            LabeledContent(L10n.t("Topics", appLanguage), value: "\(diagnostics.topics)")
            LabeledContent(L10n.t("AI assignments", appLanguage), value: "\(diagnostics.aiAssignments)")
            LabeledContent(L10n.t("Manual assignments", appLanguage), value: "\(diagnostics.manualAssignments)")

            if diagnostics.archived > 0 {
                LabeledContent(L10n.t("Archived", appLanguage), value: "\(diagnostics.archived)")
            }
        }
    }

    private func syncStatusText(for stats: LocalStorageStats) -> String {
        if stats.pendingChanges == 0 && stats.pendingUploads == 0 && stats.failedUploads == 0 {
            return L10n.t("All synced", appLanguage)
        }

        if stats.failedUploads > 0 {
            return "\(stats.failedUploads) \(L10n.t("failed uploads", appLanguage))"
        }

        if stats.pendingUploads > 0 {
            return "\(stats.pendingUploads) \(L10n.t("pending uploads", appLanguage))"
        }

        return "\(stats.pendingChanges) \(L10n.t("pending changes", appLanguage))"
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
        var parts = ["\(L10n.t("Updated", appLanguage)) \(shortTimestamp(item.updatedAt))"]

        if let inputTranscriptLength = item.inputTranscriptLength {
            parts.append("\(L10n.t("Transcript", appLanguage)) \(inputTranscriptLength) \(L10n.t("chars", appLanguage))")
        }

        if let inputDurationSeconds = item.inputDurationSeconds {
            parts.append("\(L10n.t("Duration", appLanguage)) \(durationText(inputDurationSeconds))")
        }

        if let ageSeconds = item.ageSeconds {
            parts.append("\(L10n.t("Stuck for", appLanguage)) \(durationText(Double(ageSeconds)))")
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

        if store.isAuthenticated && store.automaticSyncEnabled {
            await store.syncPendingWorkIfNeeded(showErrors: false)
        }

        localStats = try? LocalStorageStatsLoader.load(database: store.database)
        serverStatus = store.automaticSyncEnabled ? await loadServerStatus() : nil
    }

    private func syncNowFromDiagnostics() async {
        await store.syncNow(showErrors: true)
        await refresh()
    }

    private func pullServerChanges() async {
        await store.syncNow(showErrors: true, scheduleRetryOnFailure: false)
        await refresh()
    }

    private func retryMediaUploads() async {
        await store.retryMediaUploadsNow(showErrors: true)
        await refresh()
    }

    private func retryMediaDownloads() async {
        await store.downloadMissingRemoteMediaIfNeeded(showErrors: true)
        await refresh()
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
            return try await store.withAvailableAPIClient(token: token) { client in
                try await client.adminStatus()
            }
        } catch {
            return nil
        }
    }
}
