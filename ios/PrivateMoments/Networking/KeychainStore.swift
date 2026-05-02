import Foundation
import Security

enum KeychainStore {
    private static let service = "PrivateMoments"
    private static let account = "deviceToken"
    private static let simulatorFallbackKey = "simulator.deviceToken"
    private static let missingEntitlementStatus: OSStatus = -34018

    static func deviceToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            if shouldUseSimulatorFallback(for: status) {
                return UserDefaults.standard.string(forKey: simulatorFallbackKey)
            }

            throw KeychainError.status(status)
        }

        guard let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func saveDeviceToken(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if shouldUseSimulatorFallback(for: updateStatus) {
            UserDefaults.standard.set(token, forKey: simulatorFallbackKey)
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.status(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            if shouldUseSimulatorFallback(for: addStatus) {
                UserDefaults.standard.set(token, forKey: simulatorFallbackKey)
                return
            }

            throw KeychainError.status(addStatus)
        }
    }

    static func clearDeviceToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: simulatorFallbackKey)

        if status != errSecSuccess && status != errSecItemNotFound {
            if shouldUseSimulatorFallback(for: status) {
                return
            }

            throw KeychainError.status(status)
        }
    }

    private static func shouldUseSimulatorFallback(for status: OSStatus) -> Bool {
        #if targetEnvironment(simulator)
        return status == missingEntitlementStatus
        #else
        return false
        #endif
    }
}

enum KeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status):
            return "Keychain error \(status)"
        }
    }
}
