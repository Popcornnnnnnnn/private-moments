import Foundation
import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum AppSettings {
    private enum Keys {
        static let serverURLString = "serverURLString"
        static let deviceId = "deviceId"
        static let deviceKey = "deviceKey"
        static let lastSyncCursor = "lastSyncCursor"
        static let didApplySyncRecoveryV1 = "didApplySyncRecoveryV1"
        static let lastMediaDownloadError = "lastMediaDownloadError"
        static let showTagsInTimeline = "showTagsInTimeline"
        static let aiTitleAutoInsertEnabled = "aiTitleAutoInsertEnabled"
        static let aiTitleAutoInsertCutoff = "aiTitleAutoInsertCutoff"
        static let appAppearanceMode = "appAppearanceMode"
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

    static var showTagsInTimeline: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.showTagsInTimeline) == nil {
                return true
            }

            return UserDefaults.standard.bool(forKey: Keys.showTagsInTimeline)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.showTagsInTimeline)
        }
    }

    static var aiTitleAutoInsertEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.aiTitleAutoInsertEnabled) == nil {
                return true
            }

            return UserDefaults.standard.bool(forKey: Keys.aiTitleAutoInsertEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.aiTitleAutoInsertEnabled)
        }
    }

    static var aiTitleAutoInsertCutoff: Date {
        let storedValue = UserDefaults.standard.double(forKey: Keys.aiTitleAutoInsertCutoff)
        if storedValue > 0 {
            return Date(timeIntervalSince1970: storedValue)
        }

        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Keys.aiTitleAutoInsertCutoff)
        return now
    }

    static func ensureAITitleAutoInsertCutoff() {
        _ = aiTitleAutoInsertCutoff
    }

    static var appAppearanceMode: AppAppearanceMode {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: Keys.appAppearanceMode),
                  let mode = AppAppearanceMode(rawValue: rawValue) else {
                return .system
            }

            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.appAppearanceMode)
        }
    }

    static func clearSession() {
        UserDefaults.standard.removeObject(forKey: Keys.deviceId)
        UserDefaults.standard.removeObject(forKey: Keys.lastSyncCursor)
    }
}
