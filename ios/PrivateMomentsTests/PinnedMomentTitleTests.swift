import XCTest
@testable import PrivateMoments

final class PinnedMomentTitleTests: XCTestCase {
    func testTitleUsesFirstMarkdownHeading() {
        let item = timelineItem(text: "intro\n## Travel Day\nBody")

        XCTAssertEqual(PinnedMomentTitle.title(for: item, language: .english), "Travel Day")
    }

    func testTitleFallsBackToFirstBodyLineBeforeSummary() {
        let item = timelineItem(
            text: "\nFirst useful line\nSecond line",
            summaries: [summary(title: "Summary Title")]
        )

        XCTAssertEqual(PinnedMomentTitle.title(for: item, language: .english), "First useful line")
    }

    func testTitleUsesReadySummaryWhenTextIsEmpty() {
        let item = timelineItem(text: "", summaries: [summary(title: "Voice Memo")])

        XCTAssertEqual(PinnedMomentTitle.title(for: item, language: .english), "Voice Memo")
    }

    func testTitleUsesMediaFallback() {
        let item = timelineItem(text: "", media: [media(kind: "audio")])

        XCTAssertEqual(PinnedMomentTitle.title(for: item, language: .english), "Audio moment")
    }

    private func timelineItem(
        text: String,
        media: [TimelineMedia] = [],
        summaries: [TimelineAISummary] = []
    ) -> TimelineItem {
        let now = Date(timeIntervalSince1970: 1_800)
        return TimelineItem(
            post: TimelinePost(
                id: "post",
                text: text,
                isFavorite: false,
                isPinned: true,
                pinnedAt: now,
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
            comments: [],
            aiSummaries: summaries,
            tags: []
        )
    }

    private func media(kind: String) -> TimelineMedia {
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
            transcriptionText: nil,
            transcriptionStatus: "not_requested",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: 0,
            checksum: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func summary(title: String) -> TimelineAISummary {
        let now = Date(timeIntervalSince1970: 1_800)
        return TimelineAISummary(
            id: "summary",
            postId: "post",
            mediaId: "media",
            status: "ready",
            format: "document",
            language: "en",
            overview: nil,
            keyPoints: [],
            sections: [],
            summaryText: nil,
            documentTitle: title,
            oneLiner: nil,
            documentBlocks: [],
            inputTranscriptLength: nil,
            inputDurationSeconds: nil,
            promptVersion: "test",
            provider: nil,
            model: nil,
            errorCode: nil,
            errorMessage: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
    }
}
