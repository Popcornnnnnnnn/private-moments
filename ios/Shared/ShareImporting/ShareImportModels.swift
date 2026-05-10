import Foundation

enum ShareImportConstants {
    static let appGroupIdentifier: String = {
        let key = "PrivateMomentsAppGroupIdentifier"
        let fallback = "group.dev.privatemoments.app"
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return fallback
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return fallback
        }

        return trimmed
    }()
    static let inboxDirectoryName = "ShareImports"
    static let filesDirectoryName = "files"
    static let metadataFilename = "import.json"
    static let urlScheme = "moments"
}

struct PendingShareImport: Codable, Equatable {
    var schemaVersion: Int
    var id: String
    var createdAt: Date
    var text: String
    var attachments: [PendingShareAttachment]

    init(
        schemaVersion: Int = 1,
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        text: String,
        attachments: [PendingShareAttachment]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.attachments = attachments
    }
}

struct PendingShareAttachment: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case image
        case video
        case audio
    }

    var id: String
    var kind: Kind
    var filename: String
    var typeIdentifier: String
    var suggestedName: String?
    var sortOrder: Int

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        filename: String,
        typeIdentifier: String,
        suggestedName: String?,
        sortOrder: Int
    ) {
        self.id = id
        self.kind = kind
        self.filename = filename
        self.typeIdentifier = typeIdentifier
        self.suggestedName = suggestedName
        self.sortOrder = sortOrder
    }
}

struct PendingShareImportEnvelope: Equatable {
    var importRecord: PendingShareImport
    var directoryURL: URL

    func fileURL(for attachment: PendingShareAttachment) -> URL {
        directoryURL
            .appending(path: ShareImportConstants.filesDirectoryName, directoryHint: .isDirectory)
            .appending(path: attachment.filename)
    }
}
