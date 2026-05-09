import XCTest
@testable import PrivateMoments

final class SyncDoctorDiagnosisTests: XCTestCase {
    func testAllClearWhenServerIsReachableAndCursorIsCurrent() {
        let diagnosis = diagnose(
            stats: Self.makeStats(),
            sync: Self.makeSync(latestServerChangeVersion: 42),
            lastSyncCursor: 42
        )

        XCTAssertEqual(diagnosis.status, .allClear)
        XCTAssertEqual(diagnosis.recommendedAction, nil)
        XCTAssertTrue(diagnosis.findings.isEmpty)
    }

    func testUnauthenticatedBlocksRepairActions() {
        let diagnosis = diagnose(
            stats: Self.makeStats(pendingChanges: 2, pendingUploads: 1),
            serverReachable: false,
            isAuthenticated: false
        )

        XCTAssertEqual(diagnosis.status, .blocked)
        XCTAssertEqual(diagnosis.titleKey, "Log in to sync")
        XCTAssertEqual(diagnosis.recommendedAction, nil)
    }

    func testMacUnavailableRecommendsSyncNowRetry() {
        let diagnosis = diagnose(serverReachable: false)

        XCTAssertEqual(diagnosis.status, .blocked)
        XCTAssertEqual(diagnosis.titleKey, "Mac server unavailable")
        XCTAssertEqual(diagnosis.recommendedAction, .syncNow)
    }

    func testAutomaticSyncOffWithPendingWorkRecommendsExplicitSyncNow() {
        let diagnosis = diagnose(
            stats: Self.makeStats(pendingChanges: 1),
            automaticSyncEnabled: false
        )

        XCTAssertEqual(diagnosis.status, .needsAttention)
        XCTAssertEqual(diagnosis.titleKey, "Sync work is waiting")
        XCTAssertEqual(diagnosis.recommendedAction, .syncNow)
        XCTAssertTrue(diagnosis.findings.contains { $0.id == "local-only" })
    }

    func testFailedUploadsOutrankPendingUploads() {
        let diagnosis = diagnose(
            stats: Self.makeStats(pendingUploads: 3, failedUploads: 2)
        )

        XCTAssertEqual(diagnosis.titleKey, "Uploads need retry")
        XCTAssertEqual(diagnosis.recommendedAction, .retryUploads)
    }

    func testRemoteChangesBehindRecommendsPullServerChanges() {
        let diagnosis = diagnose(
            sync: Self.makeSync(latestServerChangeVersion: 50),
            lastSyncCursor: 44
        )

        XCTAssertEqual(diagnosis.titleKey, "This iPhone is behind")
        XCTAssertEqual(diagnosis.recommendedAction, .pullServerChanges)
    }

    func testMissingMediaRecommendsRedownload() {
        let diagnosis = diagnose(
            stats: Self.makeStats(missingMediaDownloads: 4)
        )

        XCTAssertEqual(diagnosis.titleKey, "Media needs re-download")
        XCTAssertEqual(diagnosis.recommendedAction, .redownloadMissingMedia)
    }

    func testHistoricalRejectedOperationsDoNotBlockWhenSyncIsHealthy() {
        let diagnosis = diagnose(
            sync: Self.makeSync(
                latestServerChangeVersion: 10,
                rejectedOperations: 2,
                lastSuccessfulSyncAt: "2026-05-08T10:05:00.000Z",
                lastRejectedSyncAt: "2026-05-08T10:00:00.000Z"
            ),
            lastSyncCursor: 10
        )

        XCTAssertEqual(diagnosis.status, .allClear)
        XCTAssertEqual(diagnosis.recommendedAction, nil)
        XCTAssertTrue(diagnosis.findings.isEmpty)
    }

    func testCurrentRejectedOperationsRequireManualInspectionWhenPendingWorkRemains() {
        let diagnosis = diagnose(
            stats: Self.makeStats(pendingChanges: 1),
            sync: Self.makeSync(
                latestServerChangeVersion: 10,
                rejectedOperations: 2,
                lastSuccessfulSyncAt: "2026-05-08T10:00:00.000Z",
                lastRejectedSyncAt: "2026-05-08T10:05:00.000Z"
            ),
            lastSyncCursor: 10
        )

        XCTAssertEqual(diagnosis.status, .blocked)
        XCTAssertEqual(diagnosis.titleKey, "Server rejected sync work")
        XCTAssertEqual(diagnosis.recommendedAction, nil)
    }

    func testHistoricalRejectedOperationsDoNotOutrankNewPendingWork() {
        let diagnosis = diagnose(
            stats: Self.makeStats(pendingChanges: 1),
            sync: Self.makeSync(
                latestServerChangeVersion: 10,
                rejectedOperations: 2
            ),
            lastSyncCursor: 10
        )

        XCTAssertEqual(diagnosis.status, .needsAttention)
        XCTAssertEqual(diagnosis.titleKey, "Sync work is waiting")
        XCTAssertEqual(diagnosis.recommendedAction, .syncNow)
    }

    private func diagnose(
        stats: LocalStorageStats = SyncDoctorDiagnosisTests.makeStats(),
        serverReachable: Bool = true,
        sync: AdminSyncDiagnostics? = SyncDoctorDiagnosisTests.makeSync(latestServerChangeVersion: 0),
        lastSyncCursor: Int = 0,
        isAuthenticated: Bool = true,
        automaticSyncEnabled: Bool = true
    ) -> SyncDoctorDiagnosis {
        SyncDoctorDiagnosis.resolve(
            stats: stats,
            serverReachable: serverReachable,
            sync: sync,
            lastSyncCursor: lastSyncCursor,
            isAuthenticated: isAuthenticated,
            automaticSyncEnabled: automaticSyncEnabled
        )
    }

    private static func makeStats(
        pendingChanges: Int = 0,
        pendingUploads: Int = 0,
        failedUploads: Int = 0,
        missingMediaDownloads: Int = 0
    ) -> LocalStorageStats {
        LocalStorageStats(
            totalBytes: 0,
            databaseBytes: 0,
            mediaBytes: 0,
            audioVideoCacheBytes: 0,
            pendingChanges: pendingChanges,
            pendingUploads: pendingUploads,
            failedUploads: failedUploads,
            missingMediaDownloads: missingMediaDownloads,
            checkIns: LocalCheckInStats(activeItems: 0, entries: 0, pendingChanges: 0, failedChanges: 0)
        )
    }

    private static func makeSync(
        latestServerChangeVersion: Int,
        rejectedOperations: Int = 0,
        aiNonReady: Int = 0,
        lastSuccessfulSyncAt: String? = nil,
        lastRejectedSyncAt: String? = nil
    ) -> AdminSyncDiagnostics {
        AdminSyncDiagnostics(
            latestServerChangeVersion: latestServerChangeVersion,
            pendingOperations: 0,
            rejectedOperations: rejectedOperations,
            failedMediaUploads: 0,
            aiNonReady: aiNonReady,
            lastServerChangeAt: nil,
            lastSyncOperationAt: nil,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt,
            lastRejectedSyncAt: lastRejectedSyncAt
        )
    }
}
