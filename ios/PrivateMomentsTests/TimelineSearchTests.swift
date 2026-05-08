import XCTest
@testable import PrivateMoments

final class TimelineSearchTests: XCTestCase {
    func testMatchesAudioTranscript() {
        let item = timelineItem(
            text: "Lunch",
            media: [
                media(kind: "audio", transcriptionText: "Forgot to take a photo before eating")
            ],
            comments: []
        )

        XCTAssertTrue(TimelineSearch.matches(item, query: "photo"))
        XCTAssertFalse(TimelineSearch.matches(item, query: "coffee"))
    }

    func testMatchesCommentsAndPostText() {
        let item = timelineItem(
            text: "Dinner",
            media: [],
            comments: [
                comment(text: "spicy peppers")
            ]
        )

        XCTAssertTrue(TimelineSearch.matches(item, query: "dinner"))
        XCTAssertTrue(TimelineSearch.matches(item, query: "PEPPERS"))
    }

    func testMatchesAISummaryMetadata() {
        let item = timelineItem(
            text: "",
            media: [],
            comments: [],
            aiSummaries: [
                summary(
                    oneLiner: "面试之后的复盘",
                    blocks: [
                        TimelineAISummaryBlock(kind: "bullets", level: 0, text: "主要问题", items: ["沟通节奏偏快"])
                    ]
                )
            ]
        )

        let result = TimelineSearch.result(for: item, query: "面试 沟通")
        XCTAssertTrue(result.isMatch)
        XCTAssertTrue(result.includes(.summary))
    }

    func testLightweightFuzzyMatching() {
        XCTAssertTrue(TimelineSearch.textMatches("rehab training notes", query: "rehabb notes"))
        XCTAssertTrue(TimelineSearch.textMatches("今天面试结束后感觉很乱", query: "面试 感觉"))
        XCTAssertFalse(TimelineSearch.textMatches("rehab training notes", query: "coffee"))
    }

    func testMatchesTagsAndAliases() {
        let item = timelineItem(
            text: "",
            media: [],
            comments: [],
            tags: [
                assignedTag(name: "大语言模型", tagId: "topic-llm")
            ]
        )

        let aliasesByTagId = [
            "topic-llm": [
                TimelineTagAlias(
                    id: "alias-llm",
                    tagId: "topic-llm",
                    alias: "LLM",
                    normalizedAlias: "llm",
                    createdAt: Date(timeIntervalSince1970: 1_800),
                    deletedAt: nil
                )
            ]
        ]

        let result = TimelineSearch.result(for: item, query: "LLM", aliasesByTagId: aliasesByTagId)
        XCTAssertTrue(result.isMatch)
        XCTAssertTrue(result.includes(.tags))
    }

    private func timelineItem(
        text: String,
        media: [TimelineMedia],
        comments: [TimelineComment],
        aiSummaries: [TimelineAISummary] = [],
        tags: [TimelineAssignedTag] = []
    ) -> TimelineItem {
        let now = Date(timeIntervalSince1970: 1_800)
        return TimelineItem(
            post: TimelinePost(
                id: "post",
                text: text,
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
            ),
            media: media,
            comments: comments,
            aiSummaries: aiSummaries,
            tags: tags
        )
    }

    private func media(kind: String, transcriptionText: String?) -> TimelineMedia {
        let now = Date(timeIntervalSince1970: 1_800)
        return TimelineMedia(
            id: "media",
            postId: "post",
            kind: kind,
            localCompressedPath: "",
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: "uploaded",
            mimeType: nil,
            durationSeconds: nil,
            transcriptionText: transcriptionText,
            transcriptionStatus: transcriptionText == nil ? "not_requested" : "transcribed",
            transcriptionError: nil,
            transcriptionUpdatedAt: transcriptionText == nil ? nil : now,
            sortOrder: 0,
            checksum: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func comment(text: String) -> TimelineComment {
        let now = Date(timeIntervalSince1970: 1_800)
        return TimelineComment(
            id: "comment",
            postId: "post",
            text: text,
            createdAt: now,
            updatedAt: now,
            serverVersion: nil,
            deletedAt: nil
        )
    }

    private func summary(oneLiner: String, blocks: [TimelineAISummaryBlock]) -> TimelineAISummary {
        let now = Date(timeIntervalSince1970: 1_800)
        return TimelineAISummary(
            id: "summary",
            postId: "post",
            mediaId: "media",
            status: "ready",
            format: "document",
            language: "zh",
            overview: nil,
            keyPoints: [],
            sections: [],
            summaryText: nil,
            documentTitle: nil,
            oneLiner: oneLiner,
            documentBlocks: blocks,
            inputTranscriptLength: 42,
            inputDurationSeconds: 12,
            promptVersion: "media-summary-v2",
            provider: "openai",
            model: "gpt-5.5",
            errorCode: nil,
            errorMessage: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
    }

    private func assignedTag(name: String, tagId: String) -> TimelineAssignedTag {
        let now = Date(timeIntervalSince1970: 1_800)
        let tag = TimelineTag(
            id: tagId,
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

        return TimelineAssignedTag(
            id: "post-\(tagId)",
            postId: "post",
            tagId: tagId,
            role: "topic",
            source: "manual",
            confidence: nil,
            aiSummaryId: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            tag: tag
        )
    }
}
