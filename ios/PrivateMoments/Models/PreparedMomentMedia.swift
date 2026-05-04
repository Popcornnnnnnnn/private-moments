import Foundation

struct PreparedMomentMedia: Identifiable, Equatable, Sendable {
    let id: String
    let kind: String
    let fileURL: URL
    let thumbnailURL: URL?
    let mimeType: String
    let durationSeconds: Double?

    init(
        id: String = UUID().uuidString,
        kind: String,
        fileURL: URL,
        thumbnailURL: URL? = nil,
        mimeType: String,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.fileURL = fileURL
        self.thumbnailURL = thumbnailURL
        self.mimeType = mimeType
        self.durationSeconds = durationSeconds
    }
}
