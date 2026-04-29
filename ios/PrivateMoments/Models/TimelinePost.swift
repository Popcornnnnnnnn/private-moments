import Foundation

struct TimelinePost: Identifiable, Codable {
    var id: String
    var text: String
    var isFavorite: Bool
    var occurredAt: Date
    var localCreatedAt: Date
    var localUpdatedAt: Date
    var localEditedAt: Date?
    var serverVersion: Int?
    var syncStatus: String
    var deletedAt: Date?
}

struct TimelineMedia: Identifiable, Codable {
    var id: String
    var postId: String
    var localCompressedPath: String
    var localOriginalStagingPath: String?
    var remoteCompressedPath: String?
    var remoteOriginalPath: String?
    var originalPreserved: Bool
    var uploadStatus: String
    var sortOrder: Int
    var checksum: String?
    var createdAt: Date
    var updatedAt: Date
}

struct TimelineItem: Identifiable {
    let post: TimelinePost
    let media: [TimelineMedia]

    var id: String {
        post.id
    }
}
