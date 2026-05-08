import SwiftUI

struct EditTagsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    @EnvironmentObject private var store: TimelineStore

    let postId: String

    @State private var selectedPrimaryTagId: String?
    @State private var selectedTopicTagIds = Set<String>()
    @State private var newTopicName = ""
    @State private var hasLoaded = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("Primary", appLanguage)) {
                    Button {
                        selectedPrimaryTagId = nil
                    } label: {
                        Label(L10n.t("None", appLanguage), systemImage: selectedPrimaryTagId == nil ? "checkmark" : "tag")
                    }

                    ForEach(store.activePrimaryTags) { tag in
                        Button {
                            selectedPrimaryTagId = tag.id
                        } label: {
                            Label(L10n.tagName(tag, language: appLanguage), systemImage: selectedPrimaryTagId == tag.id ? "checkmark" : "tag")
                        }
                    }
                }

                Section(L10n.t("Topics", appLanguage)) {
                    HStack {
                        TextField(L10n.t("New topic", appLanguage), text: $newTopicName)
                            .textInputAutocapitalization(.never)

                        Button(L10n.t("Add", appLanguage)) {
                            addTopic()
                        }
                        .disabled(newTopicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if store.activeTopicTags.isEmpty {
                        Text(L10n.t("Topics appear after AI summaries create them.", appLanguage))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.activeTopicTags) { tag in
                            Button {
                                toggleTopic(tag.id)
                            } label: {
                                Label(tag.name, systemImage: selectedTopicTagIds.contains(tag.id) ? "checkmark" : "tag")
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.t("Edit Tags", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("Cancel", appLanguage)) {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(L10n.t("Save", appLanguage))
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .task {
                load()
            }
        }
    }

    private func load() {
        guard !hasLoaded, let item = store.item(id: postId) else {
            return
        }

        selectedPrimaryTagId = item.primaryTag?.tagId
        selectedTopicTagIds = Set(item.topicTags.map(\.tagId))
        hasLoaded = true
    }

    private func toggleTopic(_ tagId: String) {
        if selectedTopicTagIds.contains(tagId) {
            selectedTopicTagIds.remove(tagId)
        } else {
            selectedTopicTagIds.insert(tagId)
        }
    }

    private func save() {
        guard let item = store.item(id: postId) else {
            dismiss()
            return
        }

        isSaving = true
        let primary = selectedPrimaryTagId
        let topics = Array(selectedTopicTagIds)

        Task {
            let didSave = await store.updateTags(item: item, primaryTagId: primary, topicTagIds: topics)
            await MainActor.run {
                if didSave {
                    dismiss()
                } else {
                    isSaving = false
                }
            }
        }
    }

    private func addTopic() {
        let name = newTopicName
        newTopicName = ""

        Task {
            if let tag = await store.createTag(type: "topic", name: name) {
                await MainActor.run {
                    _ = selectedTopicTagIds.insert(tag.id)
                }
            }
        }
    }
}

struct DetailTagBadge: View {
    @Environment(\.appLanguage) private var appLanguage

    let tag: TimelineTag

    var body: some View {
        Text(L10n.tagName(tag, language: appLanguage))
            .font(.caption.weight(.semibold))
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.primary.opacity(0.78))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(chipColor.opacity(0.34), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(chipColor.opacity(0.48), lineWidth: 0.6)
            )
    }

    private var chipColor: Color {
        Color(hex: tag.colorHex) ?? Color.secondary.opacity(0.22)
    }
}

struct DetailFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let rows = rows(proposal: proposal, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * rowSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in rows(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(proposal: ProposedViewSize, subviews: Subviews) -> [FlowRow] {
        let proposedWidth = proposal.width
        let maxWidth = proposedWidth ?? .greatestFiniteMagnitude
        let itemProposal = proposedWidth.map { ProposedViewSize(width: $0, height: nil) } ?? .unspecified
        var rows: [FlowRow] = []
        var current = FlowRow()

        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(itemProposal)
            if let proposedWidth {
                size.width = min(size.width, proposedWidth)
            }
            if !current.items.isEmpty && current.width + spacing + size.width > maxWidth {
                rows.append(current)
                current = FlowRow()
            }

            current.append(index: index, size: size, spacing: spacing)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }

        return rows
    }

    private struct FlowRow {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func append(index: Int, size: CGSize, spacing: CGFloat) {
            if !items.isEmpty {
                width += spacing
            }
            items.append((index, size))
            width += size.width
            height = max(height, size.height)
        }
    }
}
