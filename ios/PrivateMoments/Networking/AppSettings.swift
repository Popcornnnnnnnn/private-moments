import Foundation

enum AppSettings {
    private enum Keys {
        static let serverURLString = "serverURLString"
        static let deviceId = "deviceId"
        static let deviceKey = "deviceKey"
        static let lastSyncCursor = "lastSyncCursor"
        static let didApplySyncRecoveryV1 = "didApplySyncRecoveryV1"
        static let lastMediaDownloadError = "lastMediaDownloadError"
    }

    static var serverURLString: String {
        get {
            UserDefaults.standard.string(forKey: Keys.serverURLString) ?? "http://127.0.0.1:3210"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.serverURLString)
        }
    }

    static var deviceId: String? {
        get {
            UserDefaults.standard.string(forKey: Keys.deviceId)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.deviceId)
        }
    }

    static func deviceKey(preferred: String?) -> String {
        if let existing = UserDefaults.standard.string(forKey: Keys.deviceKey), !existing.isEmpty {
            return existing
        }

        let preferredKey = preferred?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key: String
        if let preferredKey, !preferredKey.isEmpty {
            key = preferredKey
        } else {
            key = UUID().uuidString
        }

        UserDefaults.standard.set(key, forKey: Keys.deviceKey)
        return key
    }

    static var lastSyncCursor: Int {
        get {
            UserDefaults.standard.integer(forKey: Keys.lastSyncCursor)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.lastSyncCursor)
        }
    }

    static var didApplySyncRecoveryV1: Bool {
        get {
            UserDefaults.standard.bool(forKey: Keys.didApplySyncRecoveryV1)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.didApplySyncRecoveryV1)
        }
    }

    static var lastMediaDownloadError: String? {
        get {
            UserDefaults.standard.string(forKey: Keys.lastMediaDownloadError)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.lastMediaDownloadError)
        }
    }

    static func clearSession() {
        UserDefaults.standard.removeObject(forKey: Keys.deviceId)
        UserDefaults.standard.removeObject(forKey: Keys.lastSyncCursor)
    }
}
