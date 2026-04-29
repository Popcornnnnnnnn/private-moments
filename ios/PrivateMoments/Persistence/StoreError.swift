import Foundation

enum StoreError: LocalizedError {
    case notReady
    case notAuthenticated
    case invalidServerChange(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Local database is not ready"
        case .notAuthenticated:
            return "Log in to the Mac server first"
        case .invalidServerChange(let message):
            return "Invalid server change: \(message)"
        }
    }
}
