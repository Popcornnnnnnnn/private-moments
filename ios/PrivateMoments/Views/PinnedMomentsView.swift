import SwiftUI

enum PinnedMomentTitle {
    static func title(for item: TimelineItem, language: AppResolvedLanguage) -> String {
        if let heading = firstMarkdownHeading(in: item.post.text) {
            return heading
        }

        if let firstLine = firstBodyLine(in: item.post.text) {
            return firstLine
        }

        if let summaryTitle = firstReadySummaryTitle(in: item.aiSummaries) {
            return summaryTitle
        }

        return mediaFallback(for: item, language: language)
    }

    private static func firstMarkdownHeading(in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                return cleaned(trimmed.dropFirst(3))
            }
            if trimmed.hasPrefix("# ") {
                return cleaned(trimmed.dropFirst(2))
            }
        }

        return nil
    }

    private static func firstBodyLine(in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            if trimmed.hasPrefix("## ") {
                continue
            }
            if trimmed.hasPrefix("# ") {
                continue
            }

            return cleaned(trimmed)
        }

        return nil
    }

    private static func firstReadySummaryTitle(in summaries: [TimelineAISummary]) -> String? {
        summaries
            .filter { $0.isReady }
            .compactMap { cleaned($0.documentTitle) }
            .first
    }

    private static func mediaFallback(for item: TimelineItem, language: AppResolvedLanguage) -> String {
        guard let media = item.media.first else {
            return L10n.t("Moment", language)
        }

        if media.isAudio {
            return L10n.t("Audio moment", language)
        }
        if media.isVideo {
            return L10n.t("Video moment", language)
        }
        if item.media.count > 1 {
            return "\(L10n.t("Photo moment", language)) · \(item.media.count)"
        }

        return L10n.t("Photo moment", language)
    }

    private static func cleaned(_ value: String.SubSequence) -> String? {
        cleaned(String(value))
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct PinnedMomentsSection: View {
    @Environment(\.appLanguage) private var appLanguage

    let items: [TimelineItem]
    @Binding var isExpanded: Bool
    let onOpenSheet: () -> Void
    let onOpenDetail: (TimelineItem) -> Void
    let onTogglePinned: (TimelineItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if items.count > 3 {
                    onOpenSheet()
                } else {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pin.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("\(L10n.t("Pinned", appLanguage)) · \(items.count)")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Image(systemName: items.count > 3 ? "list.bullet" : (isExpanded ? "chevron.up" : "chevron.down"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(L10n.t("Pinned", appLanguage)) \(items.count)")

            if isExpanded && items.count <= 3 {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        PinnedMomentTitleRow(
                            item: item,
                            onOpenDetail: {
                                onOpenDetail(item)
                            },
                            onTogglePinned: {
                                onTogglePinned(item)
                            }
                        )

                        if item.id != items.last?.id {
                            Divider()
                                .padding(.leading, 24)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct PinnedMomentsSheet: View {
    @Environment(\.appLanguage) private var appLanguage

    let items: [TimelineItem]
    let onTogglePinned: (TimelineItem) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    NavigationLink(value: item.id) {
                        PinnedMomentTitleRowLabel(item: item)
                    }
                    .contextMenu {
                        Button {
                            onTogglePinned(item)
                        } label: {
                            Label(L10n.t("Unpin moment", appLanguage), systemImage: "pin.slash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(L10n.t("Pinned", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { postId in
                MomentDetailView(postId: postId)
            }
        }
    }
}

private struct PinnedMomentTitleRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let item: TimelineItem
    let onOpenDetail: () -> Void
    let onTogglePinned: () -> Void

    var body: some View {
        Button(action: onOpenDetail) {
            PinnedMomentTitleRowLabel(item: item)
        }
        .buttonStyle(.plain)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contextMenu {
            Button {
                onTogglePinned()
            } label: {
                Label(L10n.t("Unpin moment", appLanguage), systemImage: "pin.slash")
            }
        }
    }
}

private struct PinnedMomentTitleRowLabel: View {
    @Environment(\.appLanguage) private var appLanguage

    let item: TimelineItem

    var body: some View {
        HStack(spacing: 10) {
            Text(PinnedMomentTitle.title(for: item, language: appLanguage))
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(MomentDateFormatter.timelineLabel(for: item.post.occurredAt, language: appLanguage))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
