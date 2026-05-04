import Foundation

enum ComposerDraftStore {
    private static let textKey = "composer.draft.text"
    private static let occurredAtKey = "composer.draft.occurredAt"

    static func loadText() -> String {
        UserDefaults.standard.string(forKey: textKey) ?? ""
    }

    static func loadOccurredAt() -> Date {
        guard let value = UserDefaults.standard.string(forKey: occurredAtKey),
              let date = ISO8601DateFormatter().date(from: value) else {
            return Date()
        }

        return date
    }

    static func save(text: String, occurredAt: Date) {
        UserDefaults.standard.set(text, forKey: textKey)
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: occurredAt), forKey: occurredAtKey)
    }

    static func loadImages() -> [Data] {
        do {
            let directory = try draftMediaDirectory(create: false)
            let urls = try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "image" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            return urls.compactMap { try? Data(contentsOf: $0) }
        } catch {
            return []
        }
    }

    static func saveImages(_ imageData: [Data]) throws {
        let fileManager = FileManager.default
        let directory = try draftMediaDirectory(create: true)

        if fileManager.fileExists(atPath: directory.path) {
            let existingImages = try fileManager
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "image" }

            for imageURL in existingImages {
                try fileManager.removeItem(at: imageURL)
            }
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        for (index, data) in imageData.prefix(9).enumerated() {
            let filename = String(format: "%03d.image", index)
            try data.write(to: directory.appending(path: filename), options: [.atomic])
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: textKey)
        UserDefaults.standard.removeObject(forKey: occurredAtKey)

        if let directory = try? draftMediaDirectory(create: false) {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func draftMediaDirectory(create: Bool) throws -> URL {
        let directory = try AppDirectories.applicationSupportDirectory()
            .appending(path: "draft-media", directoryHint: .isDirectory)

        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }
}
