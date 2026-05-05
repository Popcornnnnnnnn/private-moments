import Foundation

enum StoreError: LocalizedError {
    case notReady
    case notAuthenticated
    case localOnlyModeEnabled
    case invalidServerChange(String)
    case commentTargetUnavailable

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Local database is not ready"
        case .notAuthenticated:
            return "Log in to the Mac server first"
        case .localOnlyModeEnabled:
            return "Automatic Sync is off. Turn it on or use Sync Now before requesting Mac server features."
        case .invalidServerChange(let message):
            return "Invalid server change: \(message)"
        case .commentTargetUnavailable:
            return "This moment is no longer available."
        }
    }
}
