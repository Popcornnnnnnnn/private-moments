import SwiftUI

struct TagManagementView: View {
    @EnvironmentObject private var store: TimelineStore
    @State private var addTagRequest: AddTagRequest?
    @State private var isBatchEditing = false
    @State private var selectedTopicTagIds = Set<String>()
    @State private var selectedArchivedTagIds = Set<String>()
    @State private var isBatchWorking = false
    @State private var isShowingBatchMergeTargets = false
    @State private var batchDeleteConfirmation: BatchTagDeleteConfirmation?

    var body: some View {
        Form {
            Section("Primary Tags") {
                ForEach(primaryTags) { tag in
                    NavigationLink {
                        TagDetailManagementView(tagId: tag.id)
                    } label: {
                        TagManagementRow(tag: tag, usageCount: usageCount(for: tag))
                    }
                }

                if !isBatchEditing {
                    Button {
                        addTagRequest = AddTagRequest(type: "primary")
                    } label: {
                        Label("Add Primary Tag", systemImage: "plus")
                    }
                }
            }

            Section("Topic Tags") {
                if topicTags.isEmpty {
                    Text("No topic tags yet")
                        .foregroundStyle(.secondary)
                }

                ForEach(topicTags) { tag in
                    topicTagRow(tag)
                }

                if isBatchEditing {
                    topicBatchActions
                } else {
                    Button {
                        addTagRequest = AddTagRequest(type: "topic")
                    } label: {
                        Label("Add Topic Tag", systemImage: "plus")
                    }
                }
            }

            if !archivedTags.isEmpty {
                Section("Archived") {
                    ForEach(archivedTags) { tag in
                        archivedTagRow(tag)
                    }

                    if isBatchEditing {
                        archivedBatchActions
                    }
                }
            }
        }
        .navigationTitle("Tags")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isBatchEditing ? "Done" : "Edit") {
                    setBatchEditing(!isBatchEditing)
                }
                .disabled(isBatchWorking || (topicTags.isEmpty && archivedTags.isEmpty))
            }
        }
        .sheet(item: $addTagRequest) { request in
            AddTagSheet(type: request.type)
                .environmentObject(store)
        }
        .alert(
            "Delete Tags Permanently?",
            isPresented: Binding(
                get: { batchDeleteConfirmation != nil },
                set: { isPresented in
                    if !isPresented {
                        batchDeleteConfirmation = nil
                    }
                }
            ),
            presenting: batchDeleteConfirmation
        ) { confirmation in
            Button("Delete \(confirmation.tags.count)", role: .destructive) {
                let tags = confirmation.tags
                batchDeleteConfirmation = nil
                Task {
                    await deleteArchivedTags(tags)
                }
            }
            Button("Cancel", role: .cancel) {
                batchDeleteConfirmation = nil
            }
        } message: { confirmation in
            Text("This removes \(confirmation.tags.count) archived tags from Tags, aliases, and moments. Their names will be available again.")
        }
        .confirmationDialog(
            "Merge Selected Into",
            isPresented: $isShowingBatchMergeTargets,
            titleVisibility: .visible
        ) {
            ForEach(batchMergeTargets) { target in
                Button(target.name) {
                    Task {
                        await mergeSelectedTopicTags(into: target)
                    }
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Selected topic tags will be archived and kept as aliases of the target.")
        }
    }

    private var primaryTags: [TimelineTag] {
        store.tags
            .filter { $0.type == "primary" && !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault {
                    return lhs.isDefault && !rhs.isDefault
                }

                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var topicTags: [TimelineTag] {
        store.tags
            .filter { $0.type == "topic" && !$0.isArchived }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var archivedTags: [TimelineTag] {
        store.tags
            .filter(\.isArchived)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var selectedTopicTags: [TimelineTag] {
        topicTags.filter { selectedTopicTagIds.contains($0.id) }
    }

    private var selectedArchivedTags: [TimelineTag] {
        archivedTags.filter { selectedArchivedTagIds.contains($0.id) }
    }

    private var batchMergeTargets: [TimelineTag] {
        topicTags.filter { !selectedTopicTagIds.contains($0.id) }
    }

    @ViewBuilder
    private func topicTagRow(_ tag: TimelineTag) -> some View {
        if isBatchEditing {
            Button {
                toggleTopicTagSelection(tag)
            } label: {
                SelectableTagManagementRow(
                    tag: tag,
                    usageCount: usageCount(for: tag),
                    isSelected: selectedTopicTagIds.contains(tag.id)
                )
            }
            .buttonStyle(.plain)
            .disabled(isBatchWorking)
        } else {
            NavigationLink {
                TagDetailManagementView(tagId: tag.id)
            } label: {
                TagManagementRow(tag: tag, usageCount: usageCount(for: tag))
            }
        }
    }

    @ViewBuilder
    private func archivedTagRow(_ tag: TimelineTag) -> some View {
        if isBatchEditing {
            Button {
                toggleArchivedTagSelection(tag)
            } label: {
                SelectableTagManagementRow(
                    tag: tag,
                    usageCount: usageCount(for: tag),
                    isSelected: selectedArchivedTagIds.contains(tag.id)
                )
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isBatchWorking)
        } else {
            NavigationLink {
                TagDetailManagementView(tagId: tag.id)
            } label: {
                TagManagementRow(tag: tag, usageCount: usageCount(for: tag))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var topicBatchActions: some View {
        Group {
            Button("Archive Selected (\(selectedTopicTags.count))", role: .destructive) {
                Task {
                    await archiveSelectedTopicTags()
                }
            }
            .disabled(isBatchWorking || selectedTopicTags.isEmpty)

            Button("Merge Selected...", role: .destructive) {
                isShowingBatchMergeTargets = true
            }
            .disabled(isBatchWorking || selectedTopicTags.isEmpty || batchMergeTargets.isEmpty)
        }
    }

    private var archivedBatchActions: some View {
        Group {
            Button("Restore Selected (\(selectedArchivedTags.count))") {
                Task {
                    await restoreSelectedArchivedTags()
                }
            }
            .disabled(isBatchWorking || selectedArchivedTags.isEmpty)

            Button("Delete Selected (\(deletableSelectedArchivedTags.count))", role: .destructive) {
                batchDeleteConfirmation = BatchTagDeleteConfirmation(tags: deletableSelectedArchivedTags)
            }
            .disabled(isBatchWorking || deletableSelectedArchivedTags.isEmpty)
        }
    }

    private var deletableSelectedArchivedTags: [TimelineTag] {
        selectedArchivedTags.filter { !$0.isDefault }
    }

    private func usageCount(for tag: TimelineTag) -> Int {
        store.tagUsageCounts[tag.id] ?? 0
    }

    private func setBatchEditing(_ isEditing: Bool) {
        isBatchEditing = isEditing
        if !isEditing {
            clearBatchSelections()
        }
    }

    private func clearBatchSelections() {
        selectedTopicTagIds.removeAll()
        selectedArchivedTagIds.removeAll()
    }

    private func toggleTopicTagSelection(_ tag: TimelineTag) {
        toggleSelection(tag.id, in: &selectedTopicTagIds)
    }

    private func toggleArchivedTagSelection(_ tag: TimelineTag) {
        toggleSelection(tag.id, in: &selectedArchivedTagIds)
    }

    private func toggleSelection(_ tagId: String, in selection: inout Set<String>) {
        if selection.contains(tagId) {
            selection.remove(tagId)
        } else {
            selection.insert(tagId)
        }
    }

    private func archiveSelectedTopicTags() async {
        await runBatchOperation(selectedTopicTags) { tag in
            await store.archiveTag(tag)
        }
    }

    private func restoreSelectedArchivedTags() async {
        await runBatchOperation(selectedArchivedTags) { tag in
            await store.restoreTag(tag)
        }
    }

    private func deleteArchivedTags(_ tags: [TimelineTag]) async {
        await runBatchOperation(tags) { tag in
            await store.deleteTag(tag)
        }
    }

    private func mergeSelectedTopicTags(into target: TimelineTag) async {
        let sourceTags = selectedTopicTags.filter { $0.id != target.id }
        await runBatchOperation(sourceTags) { sourceTag in
            await store.mergeTopicTag(sourceTag, into: target)
        }
    }

    private func runBatchOperation(
        _ tags: [TimelineTag],
        operation: (TimelineTag) async -> Bool
    ) async {
        guard !tags.isEmpty else {
            return
        }

        isBatchWorking = true
        var allSucceeded = true
        for tag in tags {
            let succeeded = await operation(tag)
            allSucceeded = allSucceeded && succeeded
        }
        isBatchWorking = false

        if allSucceeded {
            setBatchEditing(false)
        }
    }
}

private struct AddTagRequest: Identifiable {
    let type: String
    let id = UUID()
}

private struct BatchTagDeleteConfirmation: Identifiable {
    let tags: [TimelineTag]
    let id = UUID()
}

private struct TagManagementRow: View {
    let tag: TimelineTag
    let usageCount: Int

    var body: some View {
        HStack(spacing: 10) {
            if tag.type == "primary" {
                TimelineTagChip(tag: tag, compact: true)
            } else {
                Label(tag.name, systemImage: "tag")
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text("\(usageCount)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct SelectableTagManagementRow: View {
    let tag: TimelineTag
    let usageCount: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(isSelected ? .blue : .secondary)

            TagManagementRow(tag: tag, usageCount: usageCount)
        }
        .contentShape(Rectangle())
    }
}

private struct TagDetailManagementView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.dismiss) private var dismiss

    let tagId: String

    @State private var name = ""
    @State private var colorHex = ""
    @State private var aliasText = ""
    @State private var mergeTargetTagId: String?
    @State private var isWorking = false
    @State private var tagPendingDeletion: TimelineTag?

    var body: some View {
        Form {
            if let tag {
                Section("Tag") {
                    LabeledContent("Type", value: tag.type == "primary" ? "Primary" : "Topic")
                    LabeledContent("Usage", value: "\(store.tagUsageCounts[tag.id] ?? 0)")

                    if tag.isDefault {
                        LabeledContent("Name", value: tag.name)
                    } else {
                        TextField("Name", text: $name)
                    }

                    if tag.type == "primary" {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Color")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TagColorPalette(selection: $colorHex)
                        }
                    }

                    Button("Save Changes") {
                        Task {
                            await save(tag)
                        }
                    }
                    .disabled(isWorking || !canSave(tag))
                }

                if tag.type == "topic" {
                    aliasesSection(tag)

                    if !tag.isArchived {
                        mergeSection(tag)
                    }
                }

                Section {
                    if tag.isArchived {
                        Button("Restore") {
                            Task {
                                await runAndDismiss {
                                    await store.restoreTag(tag)
                                }
                            }
                        }

                        if !tag.isDefault {
                            Button("Delete Permanently", role: .destructive) {
                                tagPendingDeletion = tag
                            }
                        }
                    } else if !tag.isDefault {
                        Button("Archive", role: .destructive) {
                            Task {
                                await runAndDismiss {
                                    await store.archiveTag(tag)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(tag?.name ?? "Tag")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Delete Tag Permanently?",
            isPresented: Binding(
                get: { tagPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        tagPendingDeletion = nil
                    }
                }
            ),
            presenting: tagPendingDeletion
        ) { tag in
            Button("Delete", role: .destructive) {
                Task {
                    await runAndDismiss {
                        await store.deleteTag(tag)
                    }
                    tagPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {
                tagPendingDeletion = nil
            }
        } message: { tag in
            Text("This removes \"\(tag.name)\" from Tags, aliases, and moments. The name will be available again for a new Primary or Topic Tag.")
        }
        .onAppear(perform: reset)
        .onChange(of: tagId) { _, _ in
            reset()
        }
    }

    private var tag: TimelineTag? {
        store.tags.first { $0.id == tagId }
    }

    private var activeTopicTargets: [TimelineTag] {
        store.activeTopicTags.filter { $0.id != tagId }
    }

    private func aliasesSection(_ tag: TimelineTag) -> some View {
        Section("Aliases") {
            let aliases = store.aliasesByTagId[tag.id] ?? []
            if aliases.isEmpty {
                Text("No aliases")
                    .foregroundStyle(.secondary)
            }

            ForEach(aliases) { alias in
                HStack {
                    Text(alias.alias)
                    Spacer()
                    Button(role: .destructive) {
                        Task {
                            await store.deleteTagAlias(alias)
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack {
                TextField("Add alias", text: $aliasText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Add") {
                    Task {
                        await addAlias(tag)
                    }
                }
                .disabled(isWorking || aliasText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func mergeSection(_ tag: TimelineTag) -> some View {
        Section("Merge") {
            if activeTopicTargets.isEmpty {
                Text("No target topic tags")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Merge Into", selection: $mergeTargetTagId) {
                    Text("Choose").tag(nil as String?)
                    ForEach(activeTopicTargets) { target in
                        Text(target.name).tag(Optional(target.id))
                    }
                }

                Button("Merge and Archive This Tag", role: .destructive) {
                    Task {
                        await merge(tag)
                    }
                }
                .disabled(isWorking || mergeTargetTagId == nil)
            }
        }
    }

    private func reset() {
        guard let tag else {
            return
        }

        name = tag.name
        colorHex = tag.colorHex ?? ""
        mergeTargetTagId = nil
        aliasText = ""
    }

    private func canSave(_ tag: TimelineTag) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return false
        }

        guard tag.type != "primary" || colorHex.isEmpty || isValidTagColorHex(colorHex) else {
            return false
        }

        if tag.isDefault && trimmedName != tag.name {
            return false
        }

        return trimmedName != tag.name || (tag.type == "primary" && colorHex != (tag.colorHex ?? ""))
    }

    private func save(_ tag: TimelineTag) async {
        await run {
            await store.updateTag(tag, name: name, colorHex: colorHex.isEmpty ? nil : colorHex)
        }
    }

    private func addAlias(_ tag: TimelineTag) async {
        let succeeded = await run {
            await store.createTagAlias(tag: tag, alias: aliasText)
        }

        if succeeded {
            aliasText = ""
        }
    }

    private func merge(_ tag: TimelineTag) async {
        guard let mergeTargetTagId,
              let target = store.tags.first(where: { $0.id == mergeTargetTagId }) else {
            return
        }

        await runAndDismiss {
            await store.mergeTopicTag(tag, into: target)
        }
    }

    @discardableResult
    private func run(_ action: () async -> Bool) async -> Bool {
        isWorking = true
        let succeeded = await action()
        isWorking = false
        return succeeded
    }

    private func runAndDismiss(_ action: () async -> Bool) async {
        if await run(action) {
            dismiss()
        }
    }
}

private struct AddTagSheet: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.dismiss) private var dismiss

    let type: String

    @State private var name = ""
    @State private var colorHex = "#DDEBD8"
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section(type == "primary" ? "Primary Tag" : "Topic Tag") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if type == "primary" {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Color")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TagColorPalette(selection: $colorHex)
                        }
                    }

                    if let duplicateTag {
                        TagDuplicateNotice(tag: duplicateTag, requestedType: type)
                    }
                }
            }
            .navigationTitle("New Tag")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await add()
                        }
                    }
                    .disabled(isWorking || trimmedName.isEmpty || !canAdd)
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var duplicateTag: TimelineTag? {
        let normalizedName = LocalDatabase.normalizedTagName(trimmedName)
        guard !normalizedName.isEmpty else {
            return nil
        }

        return store.tags.first { $0.normalizedName == normalizedName }
    }

    private var canAdd: Bool {
        duplicateTag == nil && (type != "primary" || isValidTagColorHex(colorHex))
    }

    private func add() async {
        isWorking = true
        let tag = await store.createTag(
            type: type,
            name: name,
            colorHex: type == "primary" ? colorHex : nil
        )
        isWorking = false

        if tag != nil {
            dismiss()
        }
    }
}

private struct TagDuplicateNotice: View {
    let tag: TimelineTag
    let requestedType: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Tag already exists", systemImage: "exclamationmark.circle")
                .font(.subheadline.weight(.semibold))

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.orange)
        .padding(.vertical, 4)
    }

    private var message: String {
        let existingType = tag.type == "primary" ? "Primary Tag" : "Topic Tag"
        let requestedTypeTitle = requestedType == "primary" ? "Primary Tag" : "Topic Tag"

        if tag.isArchived {
            return "\"\(tag.name)\" is archived under \(existingType). Restore it from the Archived section instead of creating a duplicate."
        }

        if tag.type == requestedType {
            return "\"\(tag.name)\" is already in \(existingType)s."
        }

        return "\"\(tag.name)\" already exists as a \(existingType). Tag names are shared across \(requestedTypeTitle)s and \(existingType)s."
    }
}

private let tagColorPresets: [String] = [
    // Soft defaults.
    "#D7E3F4",
    "#E3DCF4",
    "#DDEBD8",
    "#F4DEE4",
    "#E7E2DA",
    "#F0E4D4",
    // Clearer, more saturated choices.
    "#4F7DBA",
    "#6F5CC2",
    "#3C9567",
    "#C75F86",
    "#C57835",
    "#2F9A9A",
    "#D04F4F",
    "#6EA43A",
    "#D1A22E",
    "#3B78D8"
]

private struct TagColorPalette: View {
    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.fixed(36), spacing: 12), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(tagColorPresets, id: \.self) { colorHex in
                    Button {
                        selection = colorHex
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: colorHex) ?? Color.secondary.opacity(0.22))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(isSelected(colorHex) ? 0.42 : 0.16), lineWidth: 1)
                                )

                            if isSelected(colorHex) {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.primary.opacity(0.72))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tag color")
                    .accessibilityValue(isSelected(colorHex) ? "Selected" : "Not selected")
                }
            }

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: selection) ?? Color.secondary.opacity(0.18))
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                    )

                TextField("#RRGGBB", text: hexBinding)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Custom HEX color")

            if !selection.isEmpty && !isValidTagColorHex(selection) {
                Text("Invalid HEX")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var hexBinding: Binding<String> {
        Binding(
            get: { selection },
            set: { selection = normalizedTagColorHexInput($0) }
        )
    }

    private func isSelected(_ colorHex: String) -> Bool {
        selection.caseInsensitiveCompare(colorHex) == .orderedSame
    }
}

private func normalizedTagColorHexInput(_ rawValue: String) -> String {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ""
    }

    let hexDigits = trimmed
        .uppercased()
        .filter { $0.isHexDigit }
        .prefix(6)

    guard !hexDigits.isEmpty else {
        return ""
    }

    return "#\(String(hexDigits))"
}

private func isValidTagColorHex(_ value: String) -> Bool {
    Color(hex: value) != nil
}
