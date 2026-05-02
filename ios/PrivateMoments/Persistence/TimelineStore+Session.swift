import Foundation
import UIKit

extension TimelineStore {
    func login(serverURLString: String, password: String) async -> Bool {
        do {
            let normalizedServerURL = try normalizeServerURL(serverURLString)
            let client = APIClient(baseURL: normalizedServerURL, token: nil)
            let response = try await client.login(
                password: password,
                deviceName: UIDevice.current.name,
                deviceKey: AppSettings.deviceKey(preferred: UIDevice.current.identifierForVendor?.uuidString)
            )

            AppSettings.serverURLString = normalizedServerURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            AppSettings.deviceId = response.deviceId
            AppSettings.lastSyncCursor = 0
            try KeychainStore.saveDeviceToken(response.deviceToken)

            loadSessionState()
            syncMessage = "Logged in"
            await syncNow()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func logout() {
        do {
            cancelScheduledSyncRetry()
            try KeychainStore.clearDeviceToken()
            AppSettings.clearSession()
            loadSessionState()
            syncMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateServerURL(_ value: String) {
        do {
            let normalizedServerURL = try normalizeServerURL(value)
            AppSettings.serverURLString = normalizedServerURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            loadSessionState()
            syncMessage = "Server updated"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSessionState() {
        serverURLString = AppSettings.serverURLString
        deviceId = AppSettings.deviceId
        lastSyncCursor = AppSettings.lastSyncCursor
        isAuthenticated = AppSettings.deviceId != nil && (try? KeychainStore.deviceToken()) != nil
    }

    func normalizeServerURL(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            throw APIError.invalidURL
        }

        return url
    }

    func handleSyncError(_ error: Error, showErrors: Bool) {
        if case APIError.httpStatus(let status, _) = error, status == 401 {
            try? KeychainStore.clearDeviceToken()
            loadSessionState()
            syncMessage = "Log in again"

            if showErrors {
                errorMessage = "Session expired. Log in again."
            }
            return
        }

        if showErrors {
            errorMessage = error.localizedDescription
        }
    }
}
