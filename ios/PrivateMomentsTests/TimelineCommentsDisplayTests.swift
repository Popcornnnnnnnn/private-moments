import XCTest
@testable import PrivateMoments

final class TimelineCommentsDisplayTests: XCTestCase {
    func testCollapsedPreviewShowsLatestTwoInChronologicalOrder() {
        let comments = [
            comment(id: "1", text: "first", minute: 0),
            comment(id: "2", text: "second", minute: 1),
            comment(id: "3", text: "third", minute: 2),
        ]

        let display = TimelineCommentDisplay(comments: comments, isExpanded: false, searchQuery: "")

        XCTAssertEqual(display.visibleComments.map(\.id), ["2", "3"])
    }

    func testExpandedDisplayShowsAllCommentsChronologically() {
        let comments = [
            comment(id: "3", text: "third", minute: 2),
            comment(id: "1", text: "first", minute: 0),
            comment(id: "2", text: "second", minute: 1),
        ]

        let display = TimelineCommentDisplay(comments: comments, isExpanded: true, searchQuery: "")

        XCTAssertEqual(display.visibleComments.map(\.id), ["1", "2", "3"])
    }

    func testSearchPreviewPrioritizesMatchingComments() {
        let comments = [
            comment(id: "1", text: "coffee", minute: 0),
            comment(id: "2", text: "walk", minute: 1),
            comment(id: "3", text: "Coffee again", minute: 2),
            comment(id: "4", text: "dinner", minute: 3),
        ]

        let display = TimelineCommentDisplay(comments: comments, isExpanded: false, searchQuery: "coffee")

        XCTAssertEqual(display.visibleComments.map(\.id), ["1", "3"])
        XCTAssertEqual(display.highlightedCommentIDs, Set(["1", "3"]))
    }

    func testCommentRelativeTitleUsesCompactEnglishLabels() {
        let now = Date(timeIntervalSince1970: 1_800)

        XCTAssertEqual(MomentDateFormatter.commentRelativeTitle(for: Date(timeIntervalSince1970: 1_770), now: now), "Just now")
        XCTAssertEqual(MomentDateFormatter.commentRelativeTitle(for: Date(timeIntervalSince1970: 1_500), now: now), "5m ago")
    }

    private func comment(id: String, text: String, minute: TimeInterval) -> TimelineComment {
        let createdAt = Date(timeIntervalSince1970: minute * 60)
        return TimelineComment(
            id: id,
            postId: "post",
            text: text,
            createdAt: createdAt,
            updatedAt: createdAt,
            serverVersion: nil,
            deletedAt: nil
        )
    }
}
