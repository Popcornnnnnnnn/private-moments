import XCTest
@testable import PrivateMoments

final class LocalDatabasePostTagSyncTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "LocalDatabasePostTagSyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try super.tearDownWithError()
    }

    func testAppliesServerMovedPostTagAssignmentById() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "test.sqlite"))
        let now = Date(timeIntervalSince1970: 1_800)
        let post = timelinePost(id: "post-1", now: now)
        let sourceTag = topicTag(id: "topic-source", name: "HTTPS 中间人攻击", now: now)
        let targetTag = topicTag(id: "topic-target", name: "中间人攻击", now: now)

        try database.transaction {
            try database.insert(post)
            try database.upsertAssignedTag(
                assignedTag(id: "assignment-source", postId: post.id, tag: sourceTag, now: now)
            )
            try database.upsertAssignedTag(
                assignedTag(id: "assignment-target", postId: post.id, tag: targetTag, now: now)
            )
        }

        try database.applyPostTagUpdated(
            assignedTag(
                id: "assignment-source",
                postId: post.id,
                tag: targetTag,
                now: now.addingTimeInterval(60)
            ),
            serverVersion: 779
        )

        let assignedTags = try database.fetchAssignedTags(postId: post.id)
        XCTAssertEqual(assignedTags.count, 1)
        XCTAssertEqual(assignedTags.first?.id, "assignment-source")
        XCTAssertEqual(assignedTags.first?.tagId, targetTag.id)
        XCTAssertEqual(assignedTags.first?.tag.name, "中间人攻击")

        XCTAssertEqual(
            try database.count(
                "SELECT COUNT(*) FROM local_post_tags WHERE id = ?",
                bind: { statement in
                    try database.bind("assignment-source", to: 1, in: statement)
                }
            ),
            1
        )
    }

    private func timelinePost(id: String, now: Date) -> TimelinePost {
        TimelinePost(
            id: id,
            text: "Tag merge regression",
            isFavorite: false,
            isPinned: false,
            pinnedAt: nil,
            aiTagProcessedAt: nil,
            tagsUserEditedAt: nil,
            occurredAt: now,
            localCreatedAt: now,
            localUpdatedAt: now,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        )
    }

    private func topicTag(id: String, name: String, now: Date) -> TimelineTag {
        TimelineTag(
            id: id,
            type: "topic",
            name: name,
            normalizedName: name,
            colorHex: nil,
            isDefault: false,
            isArchived: false,
            aiUsableAsPrimary: false,
            createdAt: now,
            updatedAt: now,
            archivedAt: nil
        )
    }

    private func assignedTag(id: String, postId: String, tag: TimelineTag, now: Date) -> TimelineAssignedTag {
        TimelineAssignedTag(
            id: id,
            postId: postId,
            tagId: tag.id,
            role: "topic",
            source: "ai",
            confidence: 0.91,
            aiSummaryId: "summary-1",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            tag: tag
        )
    }
}
