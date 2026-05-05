import XCTest
@testable import PrivateMoments

final class MomentTextMarkdownTests: XCTestCase {
    func testParsesOnlyLineLeadingHeadings() {
        let lines = MomentTextMarkdown.parse("## Voice note title\nbody\n- item\n not a heading")

        XCTAssertEqual(
            lines.map(\.kind),
            [
                .heading(level: 2, text: "Voice note title"),
                .paragraph("body"),
                .paragraph("- item"),
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
            MomentTextMarkdown.searchableText("## 面试复盘\n- 沟通节奏"),
            "面试复盘\n- 沟通节奏"
        )
    }

    func testParsesStandaloneHTTPURLsAsLinks() {
        let lines = MomentTextMarkdown.parse("微信文章\nhttps://mp.weixin.qq.com/s/example\nnot https://example.com inline")

        XCTAssertEqual(
            lines.map(\.kind),
            [
                .paragraph("微信文章"),
                .link(URL(string: "https://mp.weixin.qq.com/s/example")!),
                .paragraph("not https://example.com inline")
            ]
        )
        XCTAssertEqual(
            MomentTextMarkdown.searchableText("https://mp.weixin.qq.com/s/example"),
            "https://mp.weixin.qq.com/s/example"
        )
    }

    func testTogglesHeadingOnCurrentLine() {
        let text = "first\nsecond"
        let selection = NSRange(location: 7, length: 0)

        XCTAssertEqual(
            MomentTextMarkdown.togglingLineStyle(.heading(level: 2), in: text, selectedRange: selection),
            .init(
                replacementRange: NSRange(location: 6, length: 6),
                replacementText: "## second",
                selectedRange: NSRange(location: 10, length: 0)
            )
        )
    }

    func testHeadingToggleReplacesOrRemovesExistingMarker() {
        XCTAssertEqual(
            MomentTextMarkdown.togglingLineStyle(
                .heading(level: 1),
                in: "## second",
                selectedRange: NSRange(location: 4, length: 0)
            ),
            .init(
                replacementRange: NSRange(location: 0, length: 9),
                replacementText: "# second",
                selectedRange: NSRange(location: 3, length: 0)
            )
        )

        XCTAssertEqual(
            MomentTextMarkdown.togglingLineStyle(
                .heading(level: 1),
                in: "# second",
                selectedRange: NSRange(location: 3, length: 0)
            ),
            .init(
                replacementRange: NSRange(location: 0, length: 8),
                replacementText: "second",
                selectedRange: NSRange(location: 1, length: 0)
            )
        )
    }

}
