import Foundation

enum SyncDoctorStatus: Equatable {
    case allClear
    case needsAttention
    case blocked

    var titleKey: String {
        switch self {
        case .allClear:
            return "All clear"
        case .needsAttention:
            return "Needs attention"
        case .blocked:
            return "Blocked"
        }
    }
}

enum SyncDoctorAction: Equatable {
    case syncNow
    case pullServerChanges
    case retryUploads
    case redownloadMissingMedia

    var titleKey: String {
        switch self {
        case .syncNow:
            return "Sync Now"
        case .pullServerChanges:
            return "Pull Server Changes"
        case .retryUploads:
            return "Retry Uploads"
        case .redownloadMissingMedia:
            return "Re-download Missing Media"
        }
    }
}

struct SyncDoctorFinding: Equatable, Identifiable {
    let id: String
    let status: SyncDoctorStatus
    let titleKey: String
    let detailKey: String
    let value: String?
    let action: SyncDoctorAction?
}

struct SyncDoctorDiagnosis: Equatable {
    let status: SyncDoctorStatus
    let titleKey: String
    let detailKey: String
    let findings: [SyncDoctorFinding]

    var recommendedAction: SyncDoctorAction? {
        findings.first?.action
    }

    static func resolve(
        stats: LocalStorageStats,
        serverStatus: AdminStatusResponse?,
        lastSyncCursor: Int,
        isAuthenticated: Bool,
        automaticSyncEnabled: Bool
    ) -> SyncDoctorDiagnosis {
        resolve(
            stats: stats,
            serverReachable: serverStatus != nil,
            sync: serverStatus?.sync,
            lastSyncCursor: lastSyncCursor,
            isAuthenticated: isAuthenticated,
            automaticSyncEnabled: automaticSyncEnabled
        )
    }

    static func resolve(
        stats: LocalStorageStats,
        serverReachable: Bool,
        sync: AdminSyncDiagnostics?,
        lastSyncCursor: Int,
        isAuthenticated: Bool,
        automaticSyncEnabled: Bool
    ) -> SyncDoctorDiagnosis {
        var findings: [SyncDoctorFinding] = []

        if !isAuthenticated {
            findings.append(
                SyncDoctorFinding(
                    id: "not-authenticated",
                    status: .blocked,
                    titleKey: "Log in to sync",
                    detailKey: "Open Settings and log in to your Mac server.",
                    value: nil,
                    action: nil
                )
            )
        }

        if isAuthenticated && automaticSyncEnabled && !serverReachable {
            findings.append(
                SyncDoctorFinding(
                    id: "mac-unavailable",
                    status: .blocked,
                    titleKey: "Mac server unavailable",
                    detailKey: "Tap Sync Now to retry. If it still fails, check the Mac server, Tailscale, or fallback endpoint.",
                    value: nil,
                    action: .syncNow
                )
            )
        }

        if stats.failedUploads > 0 {
            findings.append(
                SyncDoctorFinding(
                    id: "failed-uploads",
                    status: .needsAttention,
                    titleKey: "Uploads need retry",
                    detailKey: "Failed media uploads are waiting on this iPhone.",
                    value: "\(stats.failedUploads)",
                    action: .retryUploads
                )
            )
        }

        if stats.pendingChanges > 0 || stats.pendingUploads > 0 {
            findings.append(
                SyncDoctorFinding(
                    id: "pending-work",
                    status: .needsAttention,
                    titleKey: "Sync work is waiting",
                    detailKey: "This iPhone has local changes or media uploads waiting to sync.",
                    value: "\(stats.pendingChanges + stats.pendingUploads)",
                    action: .syncNow
                )
            )
        }

        if let sync, sync.latestServerChangeVersion > lastSyncCursor {
            findings.append(
                SyncDoctorFinding(
                    id: "remote-behind",
                    status: .needsAttention,
                    titleKey: "This iPhone is behind",
                    detailKey: "Your Mac has newer changes than this iPhone.",
                    value: "\(sync.latestServerChangeVersion - lastSyncCursor)",
                    action: .pullServerChanges
                )
            )
        }

        if stats.missingMediaDownloads > 0 {
            findings.append(
                SyncDoctorFinding(
                    id: "missing-media",
                    status: .needsAttention,
                    titleKey: "Media needs re-download",
                    detailKey: "Some uploaded media is missing locally and can be downloaded again.",
                    value: "\(stats.missingMediaDownloads)",
                    action: .redownloadMissingMedia
                )
            )
        }

        if let rejectedOperations = sync?.rejectedOperations, rejectedOperations > 0 {
            findings.append(
                SyncDoctorFinding(
                    id: "rejected-operations",
                    status: .blocked,
                    titleKey: "Server rejected sync work",
                    detailKey: "Check Sync Health and Mac logs before retrying rejected sync work.",
                    value: "\(rejectedOperations)",
                    action: nil
                )
            )
        }

        if let failedMediaUploads = sync?.failedMediaUploads, failedMediaUploads > 0 {
            findings.append(
                SyncDoctorFinding(
                    id: "server-failed-media",
                    status: .needsAttention,
                    titleKey: "Mac media uploads need inspection",
                    detailKey: "The Mac reports failed media uploads. Check Sync Health and Mac logs before retrying.",
                    value: "\(failedMediaUploads)",
                    action: nil
                )
            )
        }

        if let aiNonReady = sync?.aiNonReady, aiNonReady > 0 {
            findings.append(
                SyncDoctorFinding(
                    id: "ai-not-ready",
                    status: .needsAttention,
                    titleKey: "AI summaries still running",
                    detailKey: "AI summaries are still processing on the Mac. This does not block sync.",
                    value: "\(aiNonReady)",
                    action: nil
                )
            )
        }

        if isAuthenticated && !automaticSyncEnabled {
            findings.append(
                SyncDoctorFinding(
                    id: "local-only",
                    status: .needsAttention,
                    titleKey: "Local-only mode",
                    detailKey: "Automatic Sync is off. New work stays on this iPhone until you tap Sync Now or turn it back on.",
                    value: nil,
                    action: hasPendingWork(stats) ? .syncNow : nil
                )
            )
        }

        guard let primaryFinding = findings.first else {
            return SyncDoctorDiagnosis(
                status: .allClear,
                titleKey: "All clear",
                detailKey: "No sync problems found.",
                findings: []
            )
        }

        return SyncDoctorDiagnosis(
            status: primaryFinding.status,
            titleKey: primaryFinding.titleKey,
            detailKey: primaryFinding.detailKey,
            findings: findings
        )
    }

    private static func hasPendingWork(_ stats: LocalStorageStats) -> Bool {
        stats.pendingChanges > 0 || stats.pendingUploads > 0 || stats.failedUploads > 0
    }
}
