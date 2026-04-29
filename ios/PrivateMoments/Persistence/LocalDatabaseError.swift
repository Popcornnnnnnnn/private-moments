import Foundation

enum LocalDatabaseError: LocalizedError {
    case sqlite(String)
    case missingColumn(Int)
    case invalidDate(String)

    var errorDescription: String? {
        switch self {
        case .sqlite(let message):
            return message
        case .missingColumn(let index):
            return "Missing value for database column \(index)"
        case .invalidDate(let value):
            return "Invalid database date: \(value)"
        }
    }
}
