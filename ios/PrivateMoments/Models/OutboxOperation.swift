import Foundation

struct OutboxOperation: Identifiable, Codable {
    var id: String
    var opId: String
    var type: String
    var entityType: String
    var entityId: String
    var payloadJson: String
    var status: String
    var attemptCount: Int
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date
    var sentAt: Date?
}
