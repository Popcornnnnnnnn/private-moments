import XCTest
@testable import PrivateMoments

final class SettingsSyncButtonStateTests: XCTestCase {
    func testLocalOnlyStateOverridesActiveSync() {
        let state = SyncButtonState.resolve(
            isAuthenticated: true,
            isSyncing: true,
            automaticSyncEnabled: false,
            hasPendingSyncWork: true
        )

        XCTAssertEqual(state, .localOnly)
    }

    func testSyncingStateOnlyAppliesWhenAutomaticSyncIsOn() {
        let state = SyncButtonState.resolve(
            isAuthenticated: true,
            isSyncing: true,
            automaticSyncEnabled: true,
            hasPendingSyncWork: false
        )

        XCTAssertEqual(state, .syncing)
    }
}
