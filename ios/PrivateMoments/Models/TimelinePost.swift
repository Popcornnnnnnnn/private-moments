import Foundation

struct TimelinePost: Identifiable, Codable {
    var id: String
    var text: String
    var isFavorite: Bool
    var isPinned: Bool
    var pinnedAt: Date?
    var aiTagProcessedAt: Date?
    var tagsUserEditedAt: Date?
    var occurredAt: Date
    var localCreatedAt: Date
    var localUpdatedAt: Date
    var localEditedAt: Date?
    var serverVersion: Int?
    var syncStatus: String
    var deletedAt: Date?
}

struct TimelineTag: Identifiable, Codable, Equatable {
    private static let defaultPrimaryTagIds: Set<String> = [
        "tag-primary-diary",
        "tag-primary-idea",
        "tag-primary-learning",
        "tag-primary-emotion",
        "tag-primary-casual",
        "tag-primary-review",
    ]

    var id: String
    var type: String
    var name: String
    var normalizedName: String
    var colorHex: String?
    var isDefault: Bool
    var isArchived: Bool
    var aiUsableAsPrimary: Bool
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?

    var isPrimary: Bool {
        type == "primary"
    }

    var isTopic: Bool {
        type == "topic"
    }

    var isDefaultPrimaryTag: Bool {
        isPrimary && (isDefault || Self.defaultPrimaryTagIds.contains(id))
    }
}

struct TimelineTagAlias: Identifiable, Codable, Equatable {
    var id: String
    var tagId: String
    var alias: String
    var normalizedAlias: String
    var createdAt: Date
    var deletedAt: Date?
}

struct TimelineAssignedTag: Identifiable, Codable, Equatable {
    var id: String
    var postId: String
    var tagId: String
    var role: String
    var source: String
    var confidence: Double?
    var aiSummaryId: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var tag: TimelineTag
}

struct TimelineMedia: Identifiable, Codable {
    var id: String
    var postId: String
    var kind: String
    var localCompressedPath: String
    var localOriginalStagingPath: String?
    var localThumbnailPath: String?
    var remoteCompressedPath: String?
    var remoteOriginalPath: String?
    var remoteThumbnailPath: String?
    var originalPreserved: Bool
    var uploadStatus: String
    var mimeType: String?
    var durationSeconds: Double?
    var transcriptionText: String?
    var transcriptionStatus: String
    var transcriptionError: String?
    var transcriptionUpdatedAt: Date?
    var sortOrder: Int
    var checksum: String?
    var createdAt: Date
    var updatedAt: Date
}

extension TimelineMedia {
    var isImage: Bool {
        kind == "image"
    }

    var isVideo: Bool {
        kind == "video"
    }

    var isAudio: Bool {
        kind == "audio"
    }

    var localDisplayImagePath: String {
        if isVideo, let localThumbnailPath, !localThumbnailPath.isEmpty {
            return localThumbnailPath
        }

        return localCompressedPath
    }

    var hasLocalPlayableFile: Bool {
        !localCompressedPath.isEmpty && FileManager.default.fileExists(atPath: localCompressedPath)
    }
}

struct TimelineComment: Identifiable, Codable, Equatable {
    var id: String
    var postId: String
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var serverVersion: Int?
    var deletedAt: Date?
}

struct TimelineAISummarySection: Codable, Equatable {
    var heading: String
    var bullets: [String]
}

struct TimelineAISummaryBlock: Codable, Equatable {
    var kind: String
    var level: Int
    var text: String
    var items: [String]
}

struct TimelineAISummary: Identifiable, Codable, Equatable {
    var id: String
    var postId: String
    var mediaId: String
    var status: String
    var format: String?
    var language: String?
    var overview: String?
    var keyPoints: [String]
    var sections: [TimelineAISummarySection]
    var summaryText: String?
    var documentTitle: String? = nil
    var oneLiner: String? = nil
    var documentBlocks: [TimelineAISummaryBlock] = []
    var inputTranscriptLength: Int?
    var inputDurationSeconds: Double?
    var promptVersion: String
    var provider: String?
    var model: String?
    var errorCode: String?
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var isReady: Bool {
        status == "ready" && deletedAt == nil
    }

    var isSummarizing: Bool {
        (status == "transcribing" || status == "summarizing") && deletedAt == nil
    }

    var isFailed: Bool {
        status == "failed" && deletedAt == nil
    }

    var hasDisplayContent: Bool {
        guard deletedAt == nil else {
            return false
        }

        return Self.hasText(overview)
            || Self.hasText(summaryText)
            || Self.hasText(documentTitle)
            || Self.hasText(oneLiner)
            || !keyPoints.isEmpty
            || !sections.isEmpty
            || !documentBlocks.isEmpty
    }

    private static func hasText(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct TimelineItem: Identifiable {
    let post: TimelinePost
    let media: [TimelineMedia]
    let comments: [TimelineComment]
    let aiSummaries: [TimelineAISummary]
    let tags: [TimelineAssignedTag]

    var id: String {
        post.id
    }

    var primaryTag: TimelineAssignedTag? {
        tags.first { $0.role == "primary" && $0.deletedAt == nil && !$0.tag.isArchived }
    }

    var topicTags: [TimelineAssignedTag] {
        tags.filter { $0.role == "topic" && $0.deletedAt == nil && !$0.tag.isArchived }
    }
}
