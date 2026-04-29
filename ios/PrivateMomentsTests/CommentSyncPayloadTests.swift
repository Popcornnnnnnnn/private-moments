import XCTest
@testable import PrivateMoments

@MainActor
final class CommentSyncPayloadTests: XCTestCase {
    func testCreateCommentOutboxOperationEncodesExpectedPayload() throws {
        let createdAt = ISO8601DateFormatter().date(from: "2026-04-30T12:00:00Z")!
        let store = TimelineStore()
        let payloadJson = try store.makeCreateCommentPayload(
            postId: "post-1",
            text: "Private note",
            createdAt: createdAt
        )
        let operation = OutboxOperation(
            id: "operation-row-1",
            opId: "op-1",
            type: "create_comment",
            entityType: "comment",
            entityId: "comment-1",
            payloadJson: payloadJson,
            status: "pending",
            attemptCount: 0,
            lastError: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            sentAt: nil
        )

        let change = try operation.syncLocalChange()

        XCTAssertEqual(change.type, "create_comment")
        XCTAssertEqual(change.entityType, "comment")
        XCTAssertEqual(change.entityId, "comment-1")
        XCTAssertEqual(change.payload["postId"]?.stringValue, "post-1")
        XCTAssertEqual(change.payload["text"]?.stringValue, "Private note")
        XCTAssertEqual(change.payload["createdAt"]?.stringValue, "2026-04-30T12:00:00Z")
    }

    func testDeleteCommentOutboxOperationIncludesParentPostContext() throws {
        let deletedAt = ISO8601DateFormatter().date(from: "2026-04-30T12:10:00Z")!
        let store = TimelineStore()
        let payloadJson = try store.makeDeleteCommentPayload(postId: "post-1", deletedAt: deletedAt)
        let operation = OutboxOperation(
            id: "operation-row-2",
            opId: "op-2",
            type: "delete_comment",
            entityType: "comment",
            entityId: "comment-1",
            payloadJson: payloadJson,
            status: "pending",
            attemptCount: 0,
            lastError: nil,
            createdAt: deletedAt,
            updatedAt: deletedAt,
            sentAt: nil
        )

        let change = try operation.syncLocalChange()

        XCTAssertEqual(change.type, "delete_comment")
        XCTAssertEqual(change.entityType, "comment")
        XCTAssertEqual(change.entityId, "comment-1")
        XCTAssertEqual(change.payload["postId"]?.stringValue, "post-1")
        XCTAssertEqual(change.payload["deletedAt"]?.stringValue, "2026-04-30T12:10:00Z")
    }
}
