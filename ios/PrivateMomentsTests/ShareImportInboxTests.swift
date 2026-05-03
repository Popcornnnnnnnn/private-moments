import XCTest
@testable import PrivateMoments

final class ShareImportInboxTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "ShareImportInboxTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try super.tearDownWithError()
    }

    func testPendingImportsAreReadOldestFirstAndCanBeDeleted() throws {
        let newerDirectory = try ShareImportInbox.newImportDirectory(id: "newer", rootURL: temporaryRoot)
        let olderDirectory = try ShareImportInbox.newImportDirectory(id: "older", rootURL: temporaryRoot)

        let newer = PendingShareImport(
            id: "newer",
            createdAt: Date(timeIntervalSince1970: 200),
            text: "Newer",
            attachments: []
        )
        let older = PendingShareImport(
            id: "older",
            createdAt: Date(timeIntervalSince1970: 100),
            text: "Older",
            attachments: [
                PendingShareAttachment(
                    kind: .image,
                    filename: "001.image",
                    typeIdentifier: "public.image",
                    suggestedName: nil,
                    sortOrder: 0
                )
            ]
        )

        try ShareImportInbox.write(newer, to: newerDirectory)
        try ShareImportInbox.write(older, to: olderDirectory)

        let pending = try ShareImportInbox.pendingImports(rootURL: temporaryRoot)
        XCTAssertEqual(pending.map(\.importRecord.id), ["older", "newer"])
        XCTAssertEqual(pending.first?.fileURL(for: older.attachments[0]).lastPathComponent, "001.image")

        guard let first = pending.first else {
            XCTFail("Expected a pending import")
            return
        }

        try ShareImportInbox.delete(first)
        XCTAssertEqual(try ShareImportInbox.pendingImports(rootURL: temporaryRoot).map(\.importRecord.id), ["newer"])
    }
}

