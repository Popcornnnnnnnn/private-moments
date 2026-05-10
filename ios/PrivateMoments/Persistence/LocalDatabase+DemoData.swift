import Foundation
import UIKit

extension LocalDatabase {
    func seedDemoDataIfNeeded(
        reset: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws {
        if reset {
            try deleteDemoData()
        }

        let existingDemoPosts = try count("SELECT COUNT(*) FROM local_posts WHERE id LIKE 'demo-%'")
        guard existingDemoPosts == 0 else {
            return
        }

        let today = calendar.startOfDay(for: now)
        let demoDeviceDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        let topicTags = [
            TimelineTag(
                id: "demo-topic-local-first",
                type: "topic",
                name: "local-first",
                normalizedName: Self.normalizedTagName("local-first"),
                colorHex: "#B9D6C2",
                isDefault: false,
                isArchived: false,
                aiUsableAsPrimary: false,
                createdAt: demoDeviceDate,
                updatedAt: demoDeviceDate,
                archivedAt: nil
            ),
            TimelineTag(
                id: "demo-topic-audio-notes",
                type: "topic",
                name: "audio notes",
                normalizedName: Self.normalizedTagName("audio notes"),
                colorHex: "#D8C6F0",
                isDefault: false,
                isArchived: false,
                aiUsableAsPrimary: false,
                createdAt: demoDeviceDate,
                updatedAt: demoDeviceDate,
                archivedAt: nil
            ),
            TimelineTag(
                id: "demo-topic-trip",
                type: "topic",
                name: "weekend trip",
                normalizedName: Self.normalizedTagName("weekend trip"),
                colorHex: "#F0D0B6",
                isDefault: false,
                isArchived: false,
                aiUsableAsPrimary: false,
                createdAt: demoDeviceDate,
                updatedAt: demoDeviceDate,
                archivedAt: nil
            ),
        ]

        let posts = [
            DemoPost(
                id: "demo-post-audio-summary",
                text: "## Morning field note\nRecorded a short reflection after the walk. The Mac server turned it into a structured summary and suggested topic tags.",
                primaryTagId: "tag-primary-learning",
                topicTagIds: ["demo-topic-audio-notes", "demo-topic-local-first"],
                dayOffset: 0,
                hour: 9,
                minute: 12,
                isFavorite: true,
                isPinned: true,
                mediaKind: "audio",
                mediaTitle: "audio-note",
                imagePalette: nil,
                comments: ["Keep the next summary short enough to reuse as the title."],
                summary: DemoSummary(
                    title: "Morning field note",
                    oneLiner: "A compact reflection about local-first capture, walking, and the next writing block.",
                    bullets: [
                        "Capture happened offline first, then synced when the server was reachable.",
                        "The useful action item is to keep the next draft small and concrete.",
                        "Suggested tags reused the existing local-first vocabulary."
                    ]
                )
            ),
            DemoPost(
                id: "demo-post-photo-grid",
                text: "## Weekend archive pass\nSorted photos, clipped the important context, and left the rest in the archive instead of the main timeline.",
                primaryTagId: "tag-primary-diary",
                topicTagIds: ["demo-topic-trip"],
                dayOffset: -1,
                hour: 16,
                minute: 35,
                isFavorite: false,
                isPinned: false,
                mediaKind: "image",
                mediaTitle: "weekend-photo",
                imagePalette: DemoImagePalette(top: UIColor(red: 0.84, green: 0.91, blue: 0.88, alpha: 1), bottom: UIColor(red: 0.93, green: 0.76, blue: 0.61, alpha: 1), accent: UIColor(red: 0.23, green: 0.35, blue: 0.30, alpha: 1)),
                comments: ["This is the right level of detail for the public demo."],
                summary: nil
            ),
            DemoPost(
                id: "demo-post-text",
                text: "## Release checklist\nREADME should explain the actual product path: local Mac server, iOS capture, optional remote access, and no provider lock-in.",
                primaryTagId: "tag-primary-review",
                topicTagIds: ["demo-topic-local-first"],
                dayOffset: -3,
                hour: 21,
                minute: 4,
                isFavorite: true,
                isPinned: false,
                mediaKind: nil,
                mediaTitle: nil,
                imagePalette: nil,
                comments: [],
                summary: nil
            ),
        ]

        let checkInItems = [
            DemoCheckInItem(
                id: "demo-checkin-morning-pages",
                name: "Morning pages",
                symbolName: "text.book.closed",
                colorHex: "#9CB7D8",
                recordMode: .oncePerDay,
                timeVisualization: .timeLine,
                defaultShowInTimeline: true,
                sortOrder: 0
            ),
            DemoCheckInItem(
                id: "demo-checkin-workout",
                name: "Workout",
                symbolName: "figure.run",
                colorHex: "#77B889",
                recordMode: .multiplePerDay,
                timeVisualization: .timeHeatmap,
                defaultShowInTimeline: true,
                sortOrder: 1
            ),
            DemoCheckInItem(
                id: "demo-checkin-sleep",
                name: "Sleep wind-down",
                symbolName: "moon.zzz",
                colorHex: "#B7A5D8",
                recordMode: .oncePerDay,
                timeVisualization: .none,
                defaultShowInTimeline: false,
                sortOrder: 2
            ),
        ]

        try transaction {
            for tag in topicTags {
                try upsertTag(tag)
            }

            for post in posts {
                try insertDemoPost(post, today: today, calendar: calendar, createdAt: demoDeviceDate)
            }

            for item in checkInItems {
                try upsertCheckInItemOnly(item.item(createdAt: demoDeviceDate))
            }

            try insertDemoCheckInEntries(today: today, calendar: calendar, createdAt: demoDeviceDate)
        }
    }

    private func deleteDemoData() throws {
        try transaction {
            try execute("DELETE FROM local_ai_summaries WHERE id LIKE 'demo-%' OR postId LIKE 'demo-%' OR mediaId LIKE 'demo-%'")
            try execute("DELETE FROM local_post_tags WHERE id LIKE 'demo-%' OR postId LIKE 'demo-%' OR tagId LIKE 'demo-topic-%'")
            try execute("DELETE FROM local_comments WHERE id LIKE 'demo-%' OR postId LIKE 'demo-%'")
            try execute("DELETE FROM local_media WHERE id LIKE 'demo-%' OR postId LIKE 'demo-%'")
            try execute("DELETE FROM local_posts WHERE id LIKE 'demo-%'")
            try execute("DELETE FROM local_tag_aliases WHERE id LIKE 'demo-%' OR tagId LIKE 'demo-topic-%'")
            try execute("DELETE FROM local_tags WHERE id LIKE 'demo-topic-%'")
            try execute("DELETE FROM local_checkin_media WHERE id LIKE 'demo-%' OR entryId LIKE 'demo-%'")
            try execute("DELETE FROM local_checkin_entries WHERE id LIKE 'demo-%' OR itemId LIKE 'demo-%'")
            try execute("DELETE FROM local_checkin_items WHERE id LIKE 'demo-%'")
        }
    }

    private func insertDemoPost(
        _ demo: DemoPost,
        today: Date,
        calendar: Calendar,
        createdAt: Date
    ) throws {
        let occurredAt = demo.date(relativeTo: today, calendar: calendar)
        let post = TimelinePost(
            id: demo.id,
            text: demo.text,
            isFavorite: demo.isFavorite,
            isPinned: demo.isPinned,
            pinnedAt: demo.isPinned ? occurredAt : nil,
            aiTagProcessedAt: demo.summary == nil ? nil : occurredAt,
            tagsUserEditedAt: nil,
            occurredAt: occurredAt,
            localCreatedAt: occurredAt,
            localUpdatedAt: occurredAt,
            localEditedAt: nil,
            serverVersion: nil,
            syncStatus: "synced",
            deletedAt: nil
        )

        try insert(post)

        if let media = try demo.makeMedia(createdAt: occurredAt) {
            try insert(media)

            if let summary = demo.summary {
                try upsertAISummary(summary.summary(postId: demo.id, mediaId: media.id, createdAt: occurredAt))
            }
        }

        for (index, text) in demo.comments.enumerated() {
            let commentDate = calendar.date(byAdding: .minute, value: index + 6, to: occurredAt) ?? occurredAt
            try insert(
                TimelineComment(
                    id: "demo-comment-\(demo.id)-\(index)",
                    postId: demo.id,
                    text: text,
                    createdAt: commentDate,
                    updatedAt: commentDate,
                    serverVersion: nil,
                    deletedAt: nil
                )
            )
        }

        if let tag = try fetchTag(id: demo.primaryTagId) {
            try upsertAssignedTag(
                TimelineAssignedTag(
                    id: "demo-post-tag-\(demo.id)-primary",
                    postId: demo.id,
                    tagId: tag.id,
                    role: "primary",
                    source: "manual",
                    confidence: nil,
                    aiSummaryId: nil,
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    deletedAt: nil,
                    tag: tag
                )
            )
        }

        for tagId in demo.topicTagIds {
            guard let tag = try fetchTag(id: tagId) else {
                continue
            }

            try upsertAssignedTag(
                TimelineAssignedTag(
                    id: "demo-post-tag-\(demo.id)-\(tagId)",
                    postId: demo.id,
                    tagId: tag.id,
                    role: "topic",
                    source: "ai",
                    confidence: 0.86,
                    aiSummaryId: demo.summary == nil ? nil : "demo-summary-\(demo.id)",
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    deletedAt: nil,
                    tag: tag
                )
            )
        }
    }

    private func insertDemoCheckInEntries(today: Date, calendar: Calendar, createdAt: Date) throws {
        let entries = [
            CheckInEntry(
                id: "demo-checkin-entry-pages-today",
                itemId: "demo-checkin-morning-pages",
                occurredAt: date(dayOffset: 0, hour: 7, minute: 40, relativeTo: today, calendar: calendar),
                note: "Three pages before opening the laptop.",
                showInTimeline: true,
                createdAt: createdAt,
                updatedAt: createdAt,
                deletedAt: nil,
                syncStatus: "synced"
            ),
            CheckInEntry(
                id: "demo-checkin-entry-workout-yesterday",
                itemId: "demo-checkin-workout",
                occurredAt: date(dayOffset: -1, hour: 18, minute: 20, relativeTo: today, calendar: calendar),
                note: "Easy 35 minute run.",
                showInTimeline: true,
                createdAt: createdAt,
                updatedAt: createdAt,
                deletedAt: nil,
                syncStatus: "synced"
            ),
            CheckInEntry(
                id: "demo-checkin-entry-sleep",
                itemId: "demo-checkin-sleep",
                occurredAt: date(dayOffset: -2, hour: 22, minute: 15, relativeTo: today, calendar: calendar),
                note: "Phone away before bed.",
                showInTimeline: false,
                createdAt: createdAt,
                updatedAt: createdAt,
                deletedAt: nil,
                syncStatus: "synced"
            ),
        ]

        for entry in entries {
            try upsertCheckInEntryOnly(entry)
        }
    }

    private func date(
        dayOffset: Int,
        hour: Int,
        minute: Int,
        relativeTo today: Date,
        calendar: Calendar
    ) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

private struct DemoPost {
    let id: String
    let text: String
    let primaryTagId: String
    let topicTagIds: [String]
    let dayOffset: Int
    let hour: Int
    let minute: Int
    let isFavorite: Bool
    let isPinned: Bool
    let mediaKind: String?
    let mediaTitle: String?
    let imagePalette: DemoImagePalette?
    let comments: [String]
    let summary: DemoSummary?

    func date(relativeTo today: Date, calendar: Calendar) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    func makeMedia(createdAt: Date) throws -> TimelineMedia? {
        guard let mediaKind, let mediaTitle else {
            return nil
        }

        let mediaId = "demo-media-\(id)"
        let fileExtension = mediaKind == "audio" ? "m4a" : "png"
        let fileURL = try AppDirectories.mediaDirectory().appending(path: "\(mediaId).\(fileExtension)")

        if mediaKind == "image" {
            let palette = imagePalette ?? DemoImagePalette.default
            try DemoImageRenderer.writePNG(title: mediaTitle, palette: palette, to: fileURL)
        } else {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try Data("demo audio placeholder".utf8).write(to: fileURL, options: [.atomic])
            }
        }

        return TimelineMedia(
            id: mediaId,
            postId: id,
            kind: mediaKind,
            localCompressedPath: fileURL.path,
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: "uploaded",
            mimeType: mediaKind == "audio" ? "audio/mp4" : "image/png",
            durationSeconds: mediaKind == "audio" ? 94 : nil,
            transcriptionText: mediaKind == "audio" ? "Demo transcript placeholder for screenshot fixtures." : nil,
            transcriptionStatus: mediaKind == "audio" ? "completed" : "not_requested",
            transcriptionError: nil,
            transcriptionUpdatedAt: mediaKind == "audio" ? createdAt : nil,
            sortOrder: 0,
            checksum: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}

private struct DemoSummary {
    let title: String
    let oneLiner: String
    let bullets: [String]

    func summary(postId: String, mediaId: String, createdAt: Date) -> TimelineAISummary {
        TimelineAISummary(
            id: "demo-summary-\(postId)",
            postId: postId,
            mediaId: mediaId,
            status: "ready",
            format: "document-v1",
            language: "en",
            overview: oneLiner,
            keyPoints: bullets,
            sections: [],
            summaryText: nil,
            documentTitle: title,
            oneLiner: oneLiner,
            documentBlocks: [
                TimelineAISummaryBlock(kind: "heading", level: 2, text: "Key points", items: []),
                TimelineAISummaryBlock(kind: "list", level: 0, text: "", items: bullets),
                TimelineAISummaryBlock(kind: "callout", level: 0, text: "AI suggested tags are shown as topic tags on the moment.", items: []),
            ],
            inputTranscriptLength: 248,
            inputDurationSeconds: 94,
            promptVersion: "media-summary-v4",
            provider: "demo",
            model: "fixture",
            errorCode: nil,
            errorMessage: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }
}

private struct DemoCheckInItem {
    let id: String
    let name: String
    let symbolName: String
    let colorHex: String
    let recordMode: CheckInRecordMode
    let timeVisualization: CheckInTimeVisualization
    let defaultShowInTimeline: Bool
    let sortOrder: Int

    func item(createdAt: Date) -> CheckInItem {
        CheckInItem(
            id: id,
            name: name,
            symbolName: symbolName,
            colorHex: colorHex,
            recordMode: recordMode,
            timeVisualization: timeVisualization,
            dayStartHour: 0,
            activeWeekdays: [1, 2, 3, 4, 5, 6, 7],
            sortOrder: sortOrder,
            defaultShowInTimeline: defaultShowInTimeline,
            tagId: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            archivedAt: nil,
            deletedAt: nil,
            syncStatus: "synced"
        )
    }
}

private struct DemoImagePalette {
    static let `default` = DemoImagePalette(
        top: UIColor(red: 0.80, green: 0.88, blue: 0.93, alpha: 1),
        bottom: UIColor(red: 0.91, green: 0.84, blue: 0.72, alpha: 1),
        accent: UIColor(red: 0.22, green: 0.31, blue: 0.40, alpha: 1)
    )

    let top: UIColor
    let bottom: UIColor
    let accent: UIColor
}

private enum DemoImageRenderer {
    static func writePNG(title: String, palette: DemoImagePalette, to url: URL) throws {
        let size = CGSize(width: 1200, height: 900)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            let cgContext = context.cgContext
            let colors = [palette.top.cgColor, palette.bottom.cgColor] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])
            cgContext.drawLinearGradient(
                gradient!,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            palette.accent.withAlphaComponent(0.18).setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: 120, dy: 120), cornerRadius: 44).fill()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 76, weight: .semibold),
                .foregroundColor: palette.accent,
                .paragraphStyle: paragraph,
            ]
            NSString(string: title).draw(
                in: CGRect(x: 120, y: 390, width: size.width - 240, height: 120),
                withAttributes: attributes
            )
        }

        guard let data = image.pngData() else {
            return
        }

        try data.write(to: url, options: [.atomic])
    }
}
