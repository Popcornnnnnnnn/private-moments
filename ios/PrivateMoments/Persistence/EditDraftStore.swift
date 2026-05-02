import Foundation

enum EditDraftStore {
    struct Draft {
        var text: String
        var occurredAt: Date
        var mediaItems: [MomentEditMediaItem]
    }

    private struct DraftFile: Codable {
        var text: String
        var occurredAt: Date
        var media: [DraftMedia]
    }

    private struct DraftMedia: Codable {
        var id: String
        var kind: String
        var filename: String?
    }

    static func hasDraft(postId: String) -> Bool {
        FileManager.default.fileExists(atPath: metadataURL(postId: postId).path)
    }

    static func load(postId: String, currentItem: TimelineItem) -> Draft? {
        do {
            let data = try Data(contentsOf: metadataURL(postId: postId))
            let file = try decoder.decode(DraftFile.self, from: data)
            let existingMedia = Dictionary(uniqueKeysWithValues: currentItem.media.map { ($0.id, $0) })
            let directory = draftDirectory(postId: postId)

            let mediaItems = file.media.compactMap { item -> MomentEditMediaItem? in
                if item.kind == "existing", let media = existingMedia[item.id] {
                    return MomentEditMediaItem(id: item.id, source: .existing(media))
                }

                if item.kind == "new", let filename = item.filename {
                    let url = directory.appending(path: filename)
                    guard let data = try? Data(contentsOf: url) else {
                        return nil
                    }

                    return MomentEditMediaItem(id: item.id, source: .new(data))
                }

                return nil
            }

            return Draft(text: file.text, occurredAt: file.occurredAt, mediaItems: mediaItems)
        } catch {
            return nil
        }
    }

    static func save(
        postId: String,
        text: String,
        occurredAt: Date,
        mediaItems: [MomentEditMediaItem]
    ) throws {
        let fileManager = FileManager.default
        let directory = draftDirectory(postId: postId, create: true)

        let media = try mediaItems.map { item -> DraftMedia in
            switch item.source {
            case .existing:
                return DraftMedia(id: item.id, kind: "existing", filename: nil)

            case .new(let data):
                let filename = "\(item.id).image"
                try data.write(to: directory.appending(path: filename), options: [.atomic])
                return DraftMedia(id: item.id, kind: "new", filename: filename)
            }
        }

        let activeFilenames = Set(media.compactMap(\.filename))
        let existingFiles = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in existingFiles where file.lastPathComponent != "draft.json" && !activeFilenames.contains(file.lastPathComponent) {
            try? fileManager.removeItem(at: file)
        }

        let draft = DraftFile(text: text, occurredAt: occurredAt, media: media)
        let data = try encoder.encode(draft)
        try data.write(to: metadataURL(postId: postId), options: [.atomic])
    }

    static func clear(postId: String) {
        try? FileManager.default.removeItem(at: draftDirectory(postId: postId))
    }

    private static func metadataURL(postId: String) -> URL {
        draftDirectory(postId: postId).appending(path: "draft.json")
    }

    private static func draftDirectory(postId: String, create: Bool = false) -> URL {
        let base = (try? AppDirectories.applicationSupportDirectory()) ?? FileManager.default.temporaryDirectory
        let directory = base
            .appending(path: "edit-drafts", directoryHint: .isDirectory)
            .appending(path: postId, directoryHint: .isDirectory)

        if create {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
