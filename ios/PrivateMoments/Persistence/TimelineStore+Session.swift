import Foundation
import UIKit

extension TimelineStore {
    func login(serverURLString: String, password: String) async -> Bool {
        do {
            let normalizedServerURL = try normalizeServerURL(serverURLString)
            let response = try await withAvailableAPIClient(token: nil, primaryServerURLString: serverURLString) { client in
                try await client.login(
                    password: password,
                    deviceName: UIDevice.current.name,
                    deviceKey: AppSettings.deviceKey(preferred: UIDevice.current.identifierForVendor?.uuidString)
                )
            }

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
            AppSettings.lastReachableServerURLString = nil
            loadSessionState()
            syncMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateServerURL(_ value: String) {
        do {
            let normalizedServerURL = try normalizeServerURL(value)
            AppSettings.lastReachableServerURLString = nil
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

    func withAvailableAPIClient<T>(
        token: String?,
        primaryServerURLString: String = AppSettings.serverURLString,
        preferLastReachable: Bool = true,
        operation: (APIClient) async throws -> T
    ) async throws -> T {
        let clients = try apiClientCandidates(
            token: token,
            primaryServerURLString: primaryServerURLString,
            preferLastReachable: preferLastReachable
        )
        var lastError: Error?

        for (index, client) in clients.enumerated() {
            do {
                let value = try await operation(client)
                AppSettings.rememberReachableServerURL(client.baseURL)
                return value
            } catch {
                lastError = error
                let hasFallback = index < clients.count - 1
                guard hasFallback, shouldTryFallback(after: error) else {
                    throw error
                }
            }
        }

        throw lastError ?? APIError.invalidURL
    }

    private func apiClientCandidates(
        token: String?,
        primaryServerURLString: String,
        preferLastReachable: Bool
    ) throws -> [APIClient] {
        var clients: [APIClient] = []
        for candidate in AppSettings.serverURLCandidateStrings(
            primary: primaryServerURLString,
            preferLastReachable: preferLastReachable
        ) {
            let url = try normalizeServerURL(candidate)
            clients.append(APIClient(baseURL: url, token: token))
        }

        guard !clients.isEmpty else {
            throw APIError.invalidURL
        }

        return clients
    }

    private func shouldTryFallback(after error: Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .invalidResponse:
                return true
            case .httpStatus:
                return apiError.shouldTryAlternateServerURL
            case .invalidURL, .missingToken, .missingUploadFile:
                return false
            }
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
            || nsError.domain == "kCFErrorDomainCFNetwork"
            || nsError.domain == NSPOSIXErrorDomain
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
