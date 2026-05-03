import XCTest
@testable import PrivateMoments

final class MomentTextMarkdownTests: XCTestCase {
    func testParsesOnlyLineLeadingHeadings() {
        let lines = MomentTextMarkdown.parse("## Voice note title\nbody\n not a heading")

        XCTAssertEqual(
            lines.map(\.kind),
            [
                .heading(level: 2, text: "Voice note title"),
                .paragraph("body"),
                .paragraph(" not a heading")
            ]
        )
    }

    func testDetectsExistingLeadingTitleAfterBlankLines() {
        XCTAssertTrue(MomentTextMarkdown.hasLeadingTitle("\n\n# Existing title\nbody"))
        XCTAssertFalse(MomentTextMarkdown.hasLeadingTitle("\n\nbody\n## Later heading"))
        XCTAssertFalse(MomentTextMarkdown.hasLeadingTitle("##   "))
    }

    func testAITitleNormalizationAndInsertion() {
        XCTAssertEqual(MomentTextMarkdown.normalizedAITitle("## 康复训练复盘"), "康复训练复盘")
        XCTAssertNil(MomentTextMarkdown.normalizedAITitle(String(repeating: "题", count: 41)))
        XCTAssertEqual(
            MomentTextMarkdown.insertingAITitle("康复训练复盘", into: "今天练了肩胛控制"),
            "## 康复训练复盘\n\n今天练了肩胛控制"
        )
    }

    func testSearchableTextStripsHeadingMarkers() {
        XCTAssertEqual(
            MomentTextMarkdown.searchableText("## 面试复盘\n沟通节奏"),
            "面试复盘\n沟通节奏"
        )
    }
}
