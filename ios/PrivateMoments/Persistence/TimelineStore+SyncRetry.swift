import Foundation

private enum SyncRetryPolicy {
    static let delays: [UInt64] = [5, 20, 60, 120, 300]

    static func delay(for attempt: Int) -> UInt64 {
        delays[min(attempt, delays.count - 1)]
    }
}

extension TimelineStore {
    func scheduleSyncRetryIfNeeded() {
        do {
            try refreshPendingCounts()
        } catch {
            return
        }

        guard isAuthenticated else {
            cancelScheduledSyncRetry()
            return
        }

        guard pendingOperationCount > 0 || pendingUploadCount > 0 else {
            cancelScheduledSyncRetry()
            return
        }

        guard syncRetryTask == nil else {
            return
        }

        let delay = SyncRetryPolicy.delay(for: syncRetryAttempt)
        syncRetryAttempt += 1

        syncRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)

            guard !Task.isCancelled else {
                return
            }

            await self?.runScheduledSyncRetry()
        }
    }

    func cancelScheduledSyncRetry(resetAttempt: Bool = true) {
        syncRetryTask?.cancel()
        syncRetryTask = nil

        if resetAttempt {
            syncRetryAttempt = 0
        }
    }

    private func runScheduledSyncRetry() async {
        syncRetryTask = nil
        await syncPendingWorkIfNeeded(showErrors: false)
    }
}
