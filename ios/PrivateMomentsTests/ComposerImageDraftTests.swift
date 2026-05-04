import XCTest
@testable import PrivateMoments

final class ComposerImageDraftTests: XCTestCase {
    func testAppendsPastedImagesIntoAvailableSlots() {
        let existing = [Data([0x01]), Data([0x02])]
        let incoming = [Data([0x03]), Data([0x04])]

        let result = ComposerImageDraft.appending(incoming, to: existing)

        XCTAssertEqual(result.images, existing + incoming)
        XCTAssertEqual(result.appendedCount, 2)
        XCTAssertEqual(result.discardedCount, 0)
        XCTAssertTrue(result.didAppend)
        XCTAssertFalse(result.didDiscard)
    }

    func testTruncatesPastedImagesAtComposerLimit() {
        let existing = (0..<8).map { Data([UInt8($0)]) }
        let incoming = [Data([0x11]), Data([0x12]), Data([0x13])]

        let result = ComposerImageDraft.appending(incoming, to: existing)

        XCTAssertEqual(result.images.count, ComposerImageDraft.maxImageCount)
        XCTAssertEqual(result.images.last, incoming[0])
        XCTAssertEqual(result.appendedCount, 1)
        XCTAssertEqual(result.discardedCount, 2)
        XCTAssertTrue(result.didDiscard)
    }

    func testDoesNotAppendWhenImageSlotsAreFull() {
        let existing = (0..<ComposerImageDraft.maxImageCount).map { Data([UInt8($0)]) }
        let incoming = [Data([0x21])]

        let result = ComposerImageDraft.appending(incoming, to: existing)

        XCTAssertEqual(result.images, existing)
        XCTAssertEqual(result.appendedCount, 0)
        XCTAssertEqual(result.discardedCount, 1)
        XCTAssertFalse(result.didAppend)
    }
}
