import Foundation

extension TimelineStore {
    func syncNow(
        showErrors: Bool = true,
        scheduleRetryOnFailure: Bool = true,
        userInitiated: Bool = true
    ) async {
        guard automaticSyncEnabled || userInitiated else {
            cancelScheduledSyncRetry()
            syncMessage = "Local-only"
            return
        }

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

            repeat {
                needsFollowUpSync = false
                try await runSyncPass(database: database, deviceId: deviceId, token: token)
                try await reload()
                try refreshPendingCounts()
            } while needsFollowUpSync

            if pendingOperationCount > 0 || pendingUploadCount > 0 {
                if automaticSyncEnabled {
                    syncMessage = "Retrying"
                    scheduleSyncRetryIfNeeded()
                } else {
                    syncMessage = "Waiting"
                    cancelScheduledSyncRetry()
                }
            } else {
                syncMessage = "Synced"
                cancelScheduledSyncRetry()
                Task {
                    await downloadMissingRemoteMediaIfNeeded(showErrors: false, userInitiated: userInitiated)
                }
            }
        } catch {
            handleSyncError(error, showErrors: showErrors)
            if scheduleRetryOnFailure && automaticSyncEnabled {
                scheduleSyncRetryIfNeeded()
            }
        }
    }

    func downloadMissingRemoteMediaIfNeeded(showErrors: Bool = false, userInitiated: Bool = true) async {
        guard !isDownloadingMedia else {
            return
        }

        guard automaticSyncEnabled || userInitiated else {
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

            try await withAvailableAPIClient(token: token) { client in
                try await downloadMissingMedia(client: client, database: database)
            }
            try await reload()
        } catch {
            if showErrors {
                errorMessage = error.localizedDescription
            }
        }
    }

    func syncPendingWorkIfNeeded(showErrors: Bool = false) async {
        guard automaticSyncEnabled else {
            cancelScheduledSyncRetry()
            syncMessage = "Local-only"
            return
        }

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
                await syncNow(showErrors: showErrors, userInitiated: false)
            } else if missingMediaDownloadCount > 0 {
                await downloadMissingRemoteMediaIfNeeded(showErrors: showErrors, userInitiated: false)
            } else {
                await syncNow(showErrors: showErrors, scheduleRetryOnFailure: false, userInitiated: false)
            }
        } catch {
            if showErrors {
                errorMessage = error.localizedDescription
            }
        }
    }

    func retryMediaUploadsNow(showErrors: Bool = true) async {
        do {
            guard let database else {
                throw StoreError.notReady
            }

            _ = try database.retryFailedMediaUploads()
            try await reload()
            try refreshPendingCounts()
            await syncNow(showErrors: showErrors, userInitiated: true)
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

            let localRecordCount = try database.localPostCount() + database.localCheckInRecordCount()
            let shouldRunRecoverySync = !AppSettings.didApplySyncRecoveryV1 || localRecordCount == 0

            if shouldRunRecoverySync {
                AppSettings.lastSyncCursor = 0
                lastSyncCursor = 0
                await syncNow(showErrors: true, userInitiated: false)
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
            await syncNow(showErrors: true, userInitiated: false)
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
        await syncNow(userInitiated: true)
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

    func runSyncPass(database: LocalDatabase, deviceId: String, token: String) async throws {
        let operations = try database.fetchPendingOperations()
        let hasNoLocalRecords = try database.localPostCount() == 0 && database.localCheckInRecordCount() == 0
        let requestedCursor = hasNoLocalRecords ? 0 : AppSettings.lastSyncCursor
        let request = SyncRequestBody(
            deviceId: deviceId,
            lastSyncCursor: requestedCursor,
            localChanges: try operations.map { try $0.syncLocalChange() }
        )
        let syncTimeout: TimeInterval = operations.isEmpty && requestedCursor > 0 ? 6 : 30

        let firstSync = try await withAvailableAPIClient(token: token) { client in
            try await client.sync(request, timeoutInterval: syncTimeout)
        }
        try apply(sync: firstSync, database: database)

        let pendingMedia = try database.fetchPendingMediaReadyForUpload()
        var didUploadSummarizableMedia = false
        for media in pendingMedia {
            do {
                let uploaded = try await withAvailableAPIClient(token: token) { client in
                    try await client.uploadMedia(media, variant: "compressed")
                }
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
                    let uploadedThumbnail = try await withAvailableAPIClient(token: token) { client in
                        try await client.uploadMedia(media, variant: "thumbnail")
                    }
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
            let followUpRequest = SyncRequestBody(
                    deviceId: deviceId,
                    lastSyncCursor: AppSettings.lastSyncCursor,
                    localChanges: try followUpOperations.map { try $0.syncLocalChange() }
                )
            let secondSync = try await withAvailableAPIClient(token: token) { client in
                try await client.sync(followUpRequest, timeoutInterval: 30)
            }
            try apply(sync: secondSync, database: database)
        }

        if didUploadSummarizableMedia {
            scheduleAISummaryFollowUpSync()
        }

        try await reload()
    }

    func scheduleAISummaryFollowUpSync() {
        guard automaticSyncEnabled else {
            aiSummaryFollowUpSyncTask?.cancel()
            aiSummaryFollowUpSyncTask = nil
            return
        }

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

                await self?.syncNow(showErrors: false, userInitiated: false)
            }
        }
    }
}
