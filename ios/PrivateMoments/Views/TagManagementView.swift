import SwiftUI

struct TagManagementView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage
    @State private var addTagRequest: AddTagRequest?
    @State private var isBatchEditing = false
    @State private var selectedPrimaryTagIds = Set<String>()
    @State private var selectedTopicTagIds = Set<String>()
    @State private var selectedArchivedTagIds = Set<String>()
    @State private var isBatchWorking = false
    @State private var isShowingBatchPrimaryColorSheet = false
    @State private var isShowingBatchMergeTargets = false
    @State private var batchDeleteConfirmation: BatchTagDeleteConfirmation?

    var body: some View {
        Form {
            Section(L10n.t("Primary Tags", appLanguage)) {
                ForEach(primaryTags) { tag in
                    primaryTagRow(tag)
                }

                if isBatchEditing {
                    primaryBatchActions
                } else {
                    Button {
                        addTagRequest = AddTagRequest(type: "primary")
                    } label: {
                        Label(L10n.t("Add Primary Tag", appLanguage), systemImage: "plus")
                    }
                }
            }

            Section(L10n.t("Topic Tags", appLanguage)) {
                if topicTags.isEmpty {
                    Text(L10n.t("No topic tags yet", appLanguage))
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
                        Label(L10n.t("Add Topic Tag", appLanguage), systemImage: "plus")
                    }
                }
            }

            if !archivedTags.isEmpty {
                Section(L10n.t("Archived", appLanguage)) {
                    ForEach(archivedTags) { tag in
                        archivedTagRow(tag)
                    }

                    if isBatchEditing {
                        archivedBatchActions
                    }
                }
            }
        }
        .navigationTitle(L10n.t("Tags", appLanguage))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L10n.t(isBatchEditing ? "Done" : "Edit", appLanguage)) {
                    setBatchEditing(!isBatchEditing)
                }
                .disabled(isBatchWorking || (primaryTags.isEmpty && topicTags.isEmpty && archivedTags.isEmpty))
            }
        }
        .sheet(item: $addTagRequest) { request in
            AddTagSheet(type: request.type)
                .environmentObject(store)
        }
        .sheet(isPresented: $isShowingBatchPrimaryColorSheet) {
            BatchPrimaryTagColorSheet(
                selectedCount: selectedPrimaryTags.count,
                initialColorHex: selectedPrimaryTags.first?.colorHex ?? "#EF4444"
            ) { colorHex in
                isShowingBatchPrimaryColorSheet = false
                Task {
                    await updateSelectedPrimaryTagColors(colorHex)
                }
            }
        }
        .alert(
            L10n.t("Delete Tags Permanently?", appLanguage),
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
            Button("\(L10n.t("Delete", appLanguage)) \(confirmation.tags.count)", role: .destructive) {
                let tags = confirmation.tags
                batchDeleteConfirmation = nil
                Task {
                    await deleteArchivedTags(tags)
                }
            }
            Button(L10n.t("Cancel", appLanguage), role: .cancel) {
                batchDeleteConfirmation = nil
            }
        } message: { confirmation in
            Text("\(L10n.t("This removes", appLanguage)) \(confirmation.tags.count) \(L10n.t("archived tags from Tags, aliases, and moments. Their names will be available again.", appLanguage))")
        }
        .confirmationDialog(
            L10n.t("Merge Selected Into", appLanguage),
            isPresented: $isShowingBatchMergeTargets,
            titleVisibility: .visible
        ) {
            ForEach(batchMergeTargets) { target in
                Button(L10n.tagName(target, language: appLanguage)) {
                    Task {
                        await mergeSelectedTopicTags(into: target)
                    }
                }
            }

            Button(L10n.t("Cancel", appLanguage), role: .cancel) {}
        } message: {
            Text(L10n.t("Selected topic tags will be archived and kept as aliases of the target.", appLanguage))
        }
    }

    private var primaryTags: [TimelineTag] {
        store.tags
            .filter { $0.type == "primary" && !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.isDefaultPrimaryTag != rhs.isDefaultPrimaryTag {
                    return lhs.isDefaultPrimaryTag && !rhs.isDefaultPrimaryTag
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

    private var selectedPrimaryTags: [TimelineTag] {
        primaryTags.filter { selectedPrimaryTagIds.contains($0.id) }
    }

    private var selectedArchivedTags: [TimelineTag] {
        archivedTags.filter { selectedArchivedTagIds.contains($0.id) }
    }

    private var batchMergeTargets: [TimelineTag] {
        topicTags.filter { !selectedTopicTagIds.contains($0.id) }
    }

    @ViewBuilder
    private func primaryTagRow(_ tag: TimelineTag) -> some View {
        if isBatchEditing {
            Button {
                togglePrimaryTagSelection(tag)
            } label: {
                SelectableTagManagementRow(
                    tag: tag,
                    usageCount: usageCount(for: tag),
                    isSelected: selectedPrimaryTagIds.contains(tag.id)
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

    private var primaryBatchActions: some View {
        Button("\(L10n.t("Change Color Selected...", appLanguage)) (\(selectedPrimaryTags.count))") {
            isShowingBatchPrimaryColorSheet = true
        }
        .disabled(isBatchWorking || selectedPrimaryTags.isEmpty)
    }

    private var topicBatchActions: some View {
        Group {
            Button("\(L10n.t("Archive Selected", appLanguage)) (\(selectedTopicTags.count))", role: .destructive) {
                Task {
                    await archiveSelectedTopicTags()
                }
            }
            .disabled(isBatchWorking || selectedTopicTags.isEmpty)

            Button(L10n.t("Merge Selected...", appLanguage), role: .destructive) {
                isShowingBatchMergeTargets = true
            }
            .disabled(isBatchWorking || selectedTopicTags.isEmpty || batchMergeTargets.isEmpty)
        }
    }

    private var archivedBatchActions: some View {
        Group {
            Button("\(L10n.t("Restore Selected", appLanguage)) (\(selectedArchivedTags.count))") {
                Task {
                    await restoreSelectedArchivedTags()
                }
            }
            .disabled(isBatchWorking || selectedArchivedTags.isEmpty)

            Button("\(L10n.t("Delete Selected", appLanguage)) (\(deletableSelectedArchivedTags.count))", role: .destructive) {
                batchDeleteConfirmation = BatchTagDeleteConfirmation(tags: deletableSelectedArchivedTags)
            }
            .disabled(isBatchWorking || deletableSelectedArchivedTags.isEmpty)
        }
    }

    private var deletableSelectedArchivedTags: [TimelineTag] {
        selectedArchivedTags.filter { !$0.isDefaultPrimaryTag }
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
        selectedPrimaryTagIds.removeAll()
        selectedTopicTagIds.removeAll()
        selectedArchivedTagIds.removeAll()
    }

    private func togglePrimaryTagSelection(_ tag: TimelineTag) {
        toggleSelection(tag.id, in: &selectedPrimaryTagIds)
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

    private func updateSelectedPrimaryTagColors(_ colorHex: String) async {
        guard isValidTagColorHex(colorHex) else {
            return
        }

        await runBatchOperation(selectedPrimaryTags) { tag in
            await store.updateTag(tag, name: tag.name, colorHex: colorHex)
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
    @Environment(\.appLanguage) private var appLanguage

    let tag: TimelineTag
    let usageCount: Int

    var body: some View {
        HStack(spacing: 10) {
            if tag.type == "primary" {
                TimelineTagChip(tag: tag, compact: true)
            } else {
                Label(L10n.tagName(tag, language: appLanguage), systemImage: "tag")
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
    @Environment(\.appLanguage) private var appLanguage

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
                Section(L10n.t("Tag", appLanguage)) {
                    LabeledContent(L10n.t("Type", appLanguage), value: tag.type == "primary" ? L10n.t("Primary", appLanguage) : L10n.t("Topic", appLanguage))
                    LabeledContent(L10n.t("Usage", appLanguage), value: "\(store.tagUsageCounts[tag.id] ?? 0)")

                    if tag.isDefaultPrimaryTag {
                        LabeledContent(L10n.t("Name", appLanguage), value: L10n.tagName(tag, language: appLanguage))
                    } else {
                        TextField(L10n.t("Name", appLanguage), text: $name)
                    }

                    if tag.type == "primary" {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.t("Color", appLanguage))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TagColorPalette(selection: $colorHex)
                        }
                    }

                    Button(L10n.t("Save Changes", appLanguage)) {
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
                        Button(L10n.t("Restore", appLanguage)) {
                            Task {
                                await runAndDismiss {
                                    await store.restoreTag(tag)
                                }
                            }
                        }

                        if !tag.isDefaultPrimaryTag {
                            Button(L10n.t("Delete Permanently", appLanguage), role: .destructive) {
                                tagPendingDeletion = tag
                            }
                        }
                    } else if !tag.isDefaultPrimaryTag {
                        Button(L10n.t("Archive", appLanguage), role: .destructive) {
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
        .navigationTitle(tag.map { L10n.tagName($0, language: appLanguage) } ?? L10n.t("Tag", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            L10n.t("Delete Tag Permanently?", appLanguage),
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
            Button(L10n.t("Delete", appLanguage), role: .destructive) {
                Task {
                    await runAndDismiss {
                        await store.deleteTag(tag)
                    }
                    tagPendingDeletion = nil
                }
            }
            Button(L10n.t("Cancel", appLanguage), role: .cancel) {
                tagPendingDeletion = nil
            }
        } message: { tag in
            Text("\(L10n.t("This removes", appLanguage)) \"\(L10n.tagName(tag, language: appLanguage))\" \(L10n.t("from Tags, aliases, and moments. The name will be available again for a new Primary or Topic Tag.", appLanguage))")
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
        Section(L10n.t("Aliases", appLanguage)) {
            let aliases = store.aliasesByTagId[tag.id] ?? []
            if aliases.isEmpty {
                Text(L10n.t("No aliases", appLanguage))
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
                TextField(L10n.t("Add alias", appLanguage), text: $aliasText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button(L10n.t("Add", appLanguage)) {
                    Task {
                        await addAlias(tag)
                    }
                }
                .disabled(isWorking || aliasText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func mergeSection(_ tag: TimelineTag) -> some View {
        Section(L10n.t("Merge", appLanguage)) {
            if activeTopicTargets.isEmpty {
                Text(L10n.t("No target topic tags", appLanguage))
                    .foregroundStyle(.secondary)
            } else {
                Picker(L10n.t("Merge Into", appLanguage), selection: $mergeTargetTagId) {
                    Text(L10n.t("Choose", appLanguage)).tag(nil as String?)
                    ForEach(activeTopicTargets) { target in
                        Text(L10n.tagName(target, language: appLanguage)).tag(Optional(target.id))
                    }
                }

                Button(L10n.t("Merge and Archive This Tag", appLanguage), role: .destructive) {
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

        if tag.isDefaultPrimaryTag && trimmedName != tag.name {
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
    @Environment(\.appLanguage) private var appLanguage

    let type: String

    @State private var name = ""
    @State private var colorHex = "#DDEBD8"
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t(type == "primary" ? "Primary Tag" : "Topic Tag", appLanguage)) {
                    TextField(L10n.t("Name", appLanguage), text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if type == "primary" {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.t("Color", appLanguage))
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
            .navigationTitle(L10n.t("New Tag", appLanguage))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("Cancel", appLanguage)) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("Add", appLanguage)) {
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
    @Environment(\.appLanguage) private var appLanguage

    let tag: TimelineTag
    let requestedType: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.t("Tag already exists", appLanguage), systemImage: "exclamationmark.circle")
                .font(.subheadline.weight(.semibold))

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.orange)
        .padding(.vertical, 4)
    }

    private var message: String {
        let existingType = L10n.t(tag.type == "primary" ? "Primary Tag" : "Topic Tag", appLanguage)
        let requestedTypeTitle = L10n.t(requestedType == "primary" ? "Primary Tag" : "Topic Tag", appLanguage)

        if tag.isArchived {
            return "\"\(L10n.tagName(tag, language: appLanguage))\" \(L10n.t("is archived under", appLanguage)) \(existingType). \(L10n.t("Restore it from the Archived section instead of creating a duplicate.", appLanguage))"
        }

        if tag.type == requestedType {
            return "\"\(L10n.tagName(tag, language: appLanguage))\" \(L10n.t("is already in", appLanguage)) \(existingType)."
        }

        return "\"\(L10n.tagName(tag, language: appLanguage))\" \(L10n.t("already exists as a", appLanguage)) \(existingType). \(L10n.t("Tag names are shared across", appLanguage)) \(requestedTypeTitle) \(L10n.t("and", appLanguage)) \(existingType)."
    }
}

private struct BatchPrimaryTagColorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage

    let selectedCount: Int
    let onApply: (String) -> Void

    @State private var colorHex: String

    init(
        selectedCount: Int,
        initialColorHex: String,
        onApply: @escaping (String) -> Void
    ) {
        self.selectedCount = selectedCount
        self.onApply = onApply
        _colorHex = State(initialValue: initialColorHex.isEmpty ? "#EF4444" : initialColorHex)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("Selected Primary Tags", appLanguage)) {
                    LabeledContent(L10n.t("Tags", appLanguage), value: "\(selectedCount)")
                    Text(L10n.t("This updates only the color of selected primary tags.", appLanguage))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.t("Color", appLanguage)) {
                    TagColorPalette(selection: $colorHex)
                }
            }
            .navigationTitle(L10n.t("Apply Color", appLanguage))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("Cancel", appLanguage)) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("Apply", appLanguage)) {
                        onApply(colorHex)
                        dismiss()
                    }
                    .disabled(!isValidTagColorHex(colorHex))
                }
            }
        }
    }
}

private let tagColorPresets: [String] = [
    // Soft defaults kept for the existing quiet tag style.
    "#D7E3F4",
    "#E3DCF4",
    "#DDEBD8",
    "#F4DEE4",
    "#E7E2DA",
    "#F0E4D4",
    // High-contrast standard colors.
    "#EF4444",
    "#F97316",
    "#F59E0B",
    "#EAB308",
    "#84CC16",
    "#22C55E",
    "#10B981",
    "#14B8A6",
    "#06B6D4",
    "#0EA5E9",
    "#3B82F6",
    "#2563EB",
    "#6366F1",
    "#8B5CF6",
    "#A855F7",
    "#D946EF",
    "#EC4899",
    "#F43F5E"
]

private struct TagColorPalette: View {
    @Environment(\.appLanguage) private var appLanguage

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
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Tag color", appLanguage))
                    .accessibilityValue(L10n.t(isSelected(colorHex) ? "Selected" : "Not selected", appLanguage))
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
            .accessibilityLabel(L10n.t("Custom HEX color", appLanguage))

            if !selection.isEmpty && !isValidTagColorHex(selection) {
                Text(L10n.t("Invalid HEX", appLanguage))
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
