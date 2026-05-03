import Foundation

enum ShareImportInboxError: LocalizedError {
    case appGroupUnavailable
    case importNotFound

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "Shared import storage is unavailable."
        case .importNotFound:
            return "Shared import was not found."
        }
    }
}

enum ShareImportInbox {
    static func sharedRootURL(fileManager: FileManager = .default) throws -> URL {
        guard let url = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: ShareImportConstants.appGroupIdentifier
        ) else {
            throw ShareImportInboxError.appGroupUnavailable
        }
        return url
    }

    static func inboxDirectory(
        rootURL: URL? = nil,
        create: Bool,
        fileManager: FileManager = .default
    ) throws -> URL {
        let root = try rootURL ?? sharedRootURL(fileManager: fileManager)
        let directory = root.appending(path: ShareImportConstants.inboxDirectoryName, directoryHint: .isDirectory)
        if create {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func newImportDirectory(
        id: String,
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let inbox = try inboxDirectory(rootURL: rootURL, create: true, fileManager: fileManager)
        let directory = inbox.appending(path: id, directoryHint: .isDirectory)
        let files = directory.appending(path: ShareImportConstants.filesDirectoryName, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: files, withIntermediateDirectories: true)
        return directory
    }

    static func filesDirectory(for importDirectory: URL, fileManager: FileManager = .default) throws -> URL {
        let directory = importDirectory.appending(path: ShareImportConstants.filesDirectoryName, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func write(
        _ importRecord: PendingShareImport,
        to importDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        let metadataURL = importDirectory.appending(path: ShareImportConstants.metadataFilename)
        let temporaryURL = importDirectory.appending(path: "\(ShareImportConstants.metadataFilename).tmp")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(importRecord)
        try data.write(to: temporaryURL, options: [.atomic])
        if fileManager.fileExists(atPath: metadataURL.path) {
            try fileManager.removeItem(at: metadataURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: metadataURL)
    }

    static func pendingImports(
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> [PendingShareImportEnvelope] {
        let inbox = try inboxDirectory(rootURL: rootURL, create: false, fileManager: fileManager)
        guard fileManager.fileExists(atPath: inbox.path) else {
            return []
        }

        let directories = try fileManager
            .contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { url in
                var isDirectory: ObjCBool = false
                return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            }

        let envelopes = directories.compactMap { directory -> PendingShareImportEnvelope? in
            try? loadImport(from: directory)
        }

        return envelopes.sorted { lhs, rhs in
            lhs.importRecord.createdAt < rhs.importRecord.createdAt
        }
    }

    static func nextPendingImport(
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> PendingShareImportEnvelope? {
        try pendingImports(rootURL: rootURL, fileManager: fileManager).first
    }

    static func hasPendingImports(
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        (try? nextPendingImport(rootURL: rootURL, fileManager: fileManager)) != nil
    }

    static func delete(_ envelope: PendingShareImportEnvelope, fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: envelope.directoryURL.path) else {
            throw ShareImportInboxError.importNotFound
        }
        try fileManager.removeItem(at: envelope.directoryURL)
    }

    private static func loadImport(from directory: URL) throws -> PendingShareImportEnvelope {
        let metadataURL = directory.appending(path: ShareImportConstants.metadataFilename)
        let data = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let importRecord = try decoder.decode(PendingShareImport.self, from: data)
        return PendingShareImportEnvelope(importRecord: importRecord, directoryURL: directory)
    }
}

