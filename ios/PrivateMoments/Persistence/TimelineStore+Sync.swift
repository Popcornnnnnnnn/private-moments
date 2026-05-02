import Foundation

extension TimelineStore {
    func syncNow(showErrors: Bool = true, scheduleRetryOnFailure: Bool = true) async {
        if isSyncing {
            needsFollowUpSync = true
            return
        }

        cancelScheduledSyncRetry(resetAttempt: false)

        do {
            guard let database else {
                throw StoreError.notReady
            }
            guard let deviceId = AppSettings.deviceId,
                  let token = try KeychainStore.deviceToken() else {
                throw StoreError.notAuthenticated
            }

            isSyncing = true
            syncMessage = "Syncing"
            defer {
                isSyncing = false
            }

            let client = APIClient(baseURL: try normalizeServerURL(AppSettings.serverURLString), token: token)

            repeat {
                needsFollowUpSync = false
                try await runSyncPass(database: database, client: client, deviceId: deviceId)
                try await reload()
                try refreshPendingCounts()
            } while needsFollowUpSync

            if pendingOperationCount > 0 || pendingUploadCount > 0 {
                syncMessage = "Retrying"
                scheduleSyncRetryIfNeeded()
            } else {
                syncMessage = "Synced"
                cancelScheduledSyncRetry()
                Task {
                    await downloadMissingRemoteMediaIfNeeded(showErrors: false)
                }
            }
        } catch {
            handleSyncError(error, showErrors: showErrors)
            if scheduleRetryOnFailure {
                scheduleSyncRetryIfNeeded()
            }
        }
    }

    func downloadMissingRemoteMediaIfNeeded(showErrors: Bool = false) async {
        guard !isDownloadingMedia else {
            return
        }

        do {
            guard isAuthenticated,
                  let database,
                  let token = try KeychainStore.deviceToken() else {
                return
            }

            let missingMediaDownloadCount = try database.missingMediaDownloadCount()
            guard missingMediaDownloadCount > 0 else {
                AppSettings.lastMediaDownloadError = nil
                return
            }

            isDownloadingMedia = true
            defer {
                isDownloadingMedia = false
            }

            let client = APIClient(baseURL: try normalizeServerURL(AppSettings.serverURLString), token: token)
            try await downloadMissingMedia(client: client, database: database)
            try await reload()
        } catch {
            if showErrors {
                errorMessage = error.localizedDescription
            }
        }
    }

    func syncPendingWorkIfNeeded(showErrors: Bool = false) async {
        do {
            guard let database else {
                return
            }

            try refreshPendingCounts()
            let missingMediaDownloadCount = try database.missingMediaDownloadCount()
            guard isAuthenticated else {
                return
            }

            if pendingOperationCount > 0 || pendingUploadCount > 0 {
                await syncNow(showErrors: showErrors)
            } else if missingMediaDownloadCount > 0 {
                await downloadMissingRemoteMediaIfNeeded(showErrors: showErrors)
            } else {
                await syncNow(showErrors: showErrors, scheduleRetryOnFailure: false)
            }
        } catch {
            if showErrors {
                errorMessage = error.localizedDescription
            }
        }
    }

    func syncAfterBootstrap() async {
        do {
            guard let database else {
                return
            }

            let localPostCount = try database.localPostCount()
            let shouldRunRecoverySync = !AppSettings.didApplySyncRecoveryV1 || localPostCount == 0

            if shouldRunRecoverySync {
                AppSettings.lastSyncCursor = 0
                lastSyncCursor = 0
                await syncNow(showErrors: true)
                if AppSettings.lastSyncCursor > 0 {
                    AppSettings.didApplySyncRecoveryV1 = true
                }
                return
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        if items.isEmpty {
            AppSettings.lastSyncCursor = 0
            lastSyncCursor = 0
            await syncNow(showErrors: true)
            return
        }

        await syncPendingWorkIfNeeded()
    }

    func resyncFromServer() async {
        guard isAuthenticated else {
            errorMessage = StoreError.notAuthenticated.localizedDescription
            return
        }

        AppSettings.lastSyncCursor = 0
        lastSyncCursor = 0
        syncMessage = "Resyncing"
        await syncNow()
    }

    func apply(sync response: SyncResponseBody, database: LocalDatabase) throws {
        try database.markOperationsAccepted(response.acceptedOps)
        try database.markOperationsRejected(
            response.rejectedOps.map { (opId: $0.opId, reason: $0.reason) }
        )

        for change in response.serverChanges.sorted(by: { $0.version < $1.version }) {
            try apply(change: change, database: database)
        }

        AppSettings.lastSyncCursor = response.nextSyncCursor
        lastSyncCursor = response.nextSyncCursor

        if response.serverChanges.count >= 500 {
            needsFollowUpSync = true
        }
    }

    func runSyncPass(database: LocalDatabase, client: APIClient, deviceId: String) async throws {
        let operations = try database.fetchPendingOperations()
        let requestedCursor = try database.localPostCount() == 0 ? 0 : AppSettings.lastSyncCursor
        let request = SyncRequestBody(
            deviceId: deviceId,
            lastSyncCursor: requestedCursor,
            localChanges: try operations.map { try $0.syncLocalChange() }
        )

        let firstSync = try await client.sync(request)
        try apply(sync: firstSync, database: database)

        let pendingMedia = try database.fetchPendingMediaReadyForUpload()
        var didUploadSummarizableMedia = false
        for media in pendingMedia {
            do {
                let uploaded = try await client.uploadMedia(media, variant: "compressed")
                try database.markMediaUploaded(
                    mediaId: media.id,
                    variant: uploaded.variant,
                    remotePath: uploaded.path,
                    checksum: uploaded.checksum
                )
                if uploaded.variant == "compressed" && (media.isAudio || media.isVideo) {
                    didUploadSummarizableMedia = true
                }

                if media.isVideo, media.localThumbnailPath != nil {
                    let uploadedThumbnail = try await client.uploadMedia(media, variant: "thumbnail")
                    try database.markMediaUploaded(
                        mediaId: media.id,
                        variant: uploadedThumbnail.variant,
                        remotePath: uploadedThumbnail.path,
                        checksum: uploadedThumbnail.checksum
                    )
                }
            } catch {
                try database.markMediaUploadFailed(mediaId: media.id, error: error.localizedDescription)
            }
        }

        if !pendingMedia.isEmpty {
            let followUpOperations = try database.fetchPendingOperations()
            let secondSync = try await client.sync(
                SyncRequestBody(
                    deviceId: deviceId,
                    lastSyncCursor: AppSettings.lastSyncCursor,
                    localChanges: try followUpOperations.map { try $0.syncLocalChange() }
                )
            )
            try apply(sync: secondSync, database: database)
        }

        if didUploadSummarizableMedia {
            scheduleAISummaryFollowUpSync()
        }

        try await reload()
    }

    func scheduleAISummaryFollowUpSync() {
        aiSummaryFollowUpSyncTask?.cancel()
        aiSummaryFollowUpSyncTask = Task { [weak self] in
            for seconds in [8.0, 20.0, 45.0, 90.0] {
                do {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                } catch {
                    return
                }

                guard !Task.isCancelled else {
                    return
                }

                await self?.syncNow(showErrors: false)
            }
        }
    }
}
