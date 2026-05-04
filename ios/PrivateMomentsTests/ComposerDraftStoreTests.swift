import XCTest
@testable import PrivateMoments

final class ComposerDraftStoreTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        ComposerDraftStore.clear()
    }

    override func tearDownWithError() throws {
        ComposerDraftStore.clear()
        try super.tearDownWithError()
    }

    func testSavingEmptyImagesDoesNotDeletePreparedVideoDraftFiles() throws {
        let directory = try AppDirectories.draftMediaDirectory()
        let videoURL = directory.appending(path: "prepared-video.mp4")
        let posterURL = directory.appending(path: "prepared-video-poster.jpg")

        try Data([0x01, 0x02, 0x03]).write(to: videoURL, options: [.atomic])
        try Data([0x04, 0x05, 0x06]).write(to: posterURL, options: [.atomic])

        try ComposerDraftStore.saveImages([])

        XCTAssertTrue(FileManager.default.fileExists(atPath: videoURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: posterURL.path))
        XCTAssertEqual(ComposerDraftStore.loadImages(), [])
    }

    func testLoadImagesIgnoresNonImageDraftFiles() throws {
        let directory = try AppDirectories.draftMediaDirectory()
        let imageURL = directory.appending(path: "000.image")
        let videoURL = directory.appending(path: "prepared-video.mp4")

        let imageData = Data([0x10, 0x11, 0x12])
        try imageData.write(to: imageURL, options: [.atomic])
        try Data([0x20, 0x21, 0x22]).write(to: videoURL, options: [.atomic])

        XCTAssertEqual(ComposerDraftStore.loadImages(), [imageData])
    }
}
