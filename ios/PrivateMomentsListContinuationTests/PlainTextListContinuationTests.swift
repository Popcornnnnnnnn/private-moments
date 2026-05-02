import XCTest
@testable import PrivateMoments

final class PlainTextListContinuationTests: XCTestCase {
    func testContinuesDashListAfterNonEmptyItem() {
        let result = PlainTextListContinuation.replacement(
            in: "- apples",
            selectedRange: nsRange(in: "- apples", after: "- apples"),
            replacementText: "\n"
        )

        XCTAssertEqual(result?.replacementText, "\n- ")
        XCTAssertEqual(result?.selectedRange.location, 11)
        XCTAssertEqual(result?.selectedRange.length, 0)
    }

    func testContinuesBulletListAfterNonEmptyItem() {
        let text = "• apples"
        let result = PlainTextListContinuation.replacement(
            in: text,
            selectedRange: nsRange(in: text, after: text),
            replacementText: "\n"
        )

        XCTAssertEqual(result?.replacementText, "\n• ")
        XCTAssertEqual(result?.selectedRange.location, 11)
        XCTAssertEqual(result?.selectedRange.length, 0)
    }

    func testIncrementsNumberedListAfterNonEmptyItem() {
        let text = "9. apples"
        let result = PlainTextListContinuation.replacement(
            in: text,
            selectedRange: nsRange(in: text, after: text),
            replacementText: "\n"
        )

        XCTAssertEqual(result?.replacementText, "\n10. ")
        XCTAssertEqual(result?.selectedRange.location, 14)
        XCTAssertEqual(result?.selectedRange.length, 0)
    }

    func testExitsEmptyDashMarkerWithTrailingSpaces() {
        let text = "Shopping\n-   "
        let result = PlainTextListContinuation.replacement(
            in: text,
            selectedRange: nsRange(in: text, after: text),
            replacementText: "\n"
        )

        XCTAssertEqual(result?.replacementText, "\n")
        XCTAssertEqual(result?.selectedRange.location, 10)
        XCTAssertEqual(result?.selectedRange.length, 0)
    }

    func testExitsEmptyBulletMarker() {
        let text = "Shopping\n• "
        let result = PlainTextListContinuation.replacement(
            in: text,
            selectedRange: nsRange(in: text, after: text),
            replacementText: "\n"
        )

        XCTAssertEqual(result?.replacementText, "\n")
        XCTAssertEqual(result?.selectedRange.location, 10)
        XCTAssertEqual(result?.selectedRange.length, 0)
    }

    func testExitsEmptyNumberedMarkerWithTrailingSpaces() {
        let text = "Shopping\n12.   "
        let result = PlainTextListContinuation.replacement(
            in: text,
            selectedRange: nsRange(in: text, after: text),
            replacementText: "\n"
        )

        XCTAssertEqual(result?.replacementText, "\n")
        XCTAssertEqual(result?.selectedRange.location, 10)
        XCTAssertEqual(result?.selectedRange.length, 0)
    }

    func testNormalParagraphNewlineFallsBack() {
        let text = "Just a paragraph"
        let result = PlainTextListContinuation.replacement(
            in: text,
            selectedRange: nsRange(in: text, after: text),
            replacementText: "\n"
        )

        XCTAssertNil(result)
    }

    func testMiddleOfNonListLineFallsBack() {
        let text = "hello world"
        let result = PlainTextListContinuation.replacement(
            in: text,
            selectedRange: nsRange(in: text, after: "hello"),
            replacementText: "\n"
        )

        XCTAssertNil(result)
    }

    func testEmojiAndUnicodeBeforeSelectionUseUTF16SafeCursor() {
        let text = "Intro 🧡\n- café"
        let result = PlainTextListContinuation.replacement(
            in: text,
            selectedRange: nsRange(in: text, after: text),
            replacementText: "\n"
        )

        XCTAssertEqual(result?.replacementText, "\n- ")
        XCTAssertEqual(result?.selectedRange.location, (text as NSString).length + 3)
        XCTAssertEqual(result?.selectedRange.length, 0)
    }

    func testInvalidRangeFallsBackWithoutCrashing() {
        let result = PlainTextListContinuation.replacement(
            in: "- apples",
            selectedRange: NSRange(location: 99, length: 0),
            replacementText: "\n"
        )

        XCTAssertNil(result)
    }

    func testEmptyStringAtStartFallsBack() {
        let result = PlainTextListContinuation.replacement(
            in: "",
            selectedRange: NSRange(location: 0, length: 0),
            replacementText: "\n"
        )

        XCTAssertNil(result)
    }

    func testOutOfRangeReplacementFallsBackWithoutCrashing() {
        let result = PlainTextListContinuation.replacement(
            in: "- apples",
            selectedRange: NSRange(location: 2, length: 99),
            replacementText: "\n"
        )

        XCTAssertNil(result)
    }

    func testNumberedPrefixAtMaxIntFallsBack() {
        let text = "\(Int.max). final"
        let result = PlainTextListContinuation.replacement(
            in: text,
            selectedRange: nsRange(in: text, after: text),
            replacementText: "\n"
        )

        XCTAssertNil(result)
    }

    func testNonNewlineReplacementFallsBack() {
        let result = PlainTextListContinuation.replacement(
            in: "- apples",
            selectedRange: NSRange(location: 8, length: 0),
            replacementText: "x"
        )

        XCTAssertNil(result)
    }

    private func nsRange(in text: String, after prefix: String) -> NSRange {
        XCTAssertTrue(text.hasPrefix(prefix), "Test fixture prefix must be at the start of the text.")
        return NSRange(location: (prefix as NSString).length, length: 0)
    }
}
