import SwiftUI

struct CheckInsView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage

    @State private var mode: CheckInsMode = .today
    @State private var isManagePresented = false
    @State private var itemEditorRoute: CheckInItemEditorRoute?
    @State private var contentItem: CheckInItem?
    @State private var detailRoute: CheckInEntryDetailRoute?
    @State private var undoEntry: CheckInEntry?
    @State private var historyFilterItemId: String?

    private var today: Date {
        Date()
    }

    private var activeItems: [CheckInItem] {
        store.checkInItems.filter { $0.deletedAt == nil && $0.archivedAt == nil }
    }

    private var historyFilterItems: [CheckInItem] {
        store.checkInItems
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.name < rhs.name
                }

                return lhs.sortOrder < rhs.sortOrder
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !store.isReady {
                    ProgressView()
                } else if activeItems.isEmpty {
                    ContentUnavailableView {
                        Text(L10n.t("Create your first check-in.", appLanguage))
                    } actions: {
                        Button(L10n.t("Create", appLanguage)) {
                            itemEditorRoute = CheckInItemEditorRoute(itemId: nil)
                        }
                    }
                } else {
                    List {
                        if mode == .today {
                            todaySections
                        } else {
                            historySections
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(L10n.t("Check-ins", appLanguage))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        mode = mode == .today ? .history : .today
                    } label: {
                        Label(mode.toggleTitle(language: appLanguage), systemImage: mode.toggleSystemImage)
                    }

                    Button {
                        isManagePresented = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel(L10n.t("Manage", appLanguage))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let undoEntry {
                    CheckInUndoBar(entry: undoEntry) {
                        Task {
                            await store.deleteCheckInEntry(undoEntry)
                            self.undoEntry = nil
                        }
                    } dismiss: {
                        self.undoEntry = nil
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
            }
            .sheet(isPresented: $isManagePresented) {
                CheckInManageView(onEdit: { item in
                    itemEditorRoute = CheckInItemEditorRoute(itemId: item.id)
                }, onAdd: {
                    itemEditorRoute = CheckInItemEditorRoute(itemId: nil)
                })
            }
            .sheet(item: $itemEditorRoute) { route in
                CheckInItemEditorView(item: route.itemId.flatMap(store.checkInItem))
            }
            .sheet(item: $contentItem) { item in
                CheckInContentEntryView(item: item)
            }
            .sheet(item: $detailRoute) { route in
                CheckInEntryDetailView(entryId: route.entryId)
            }
        }
    }

    @ViewBuilder
    private var todaySections: some View {
        let scheduled = activeItems.filter { $0.isScheduled(on: today) }
        let unscheduled = activeItems.filter { !$0.isScheduled(on: today) }
        let scheduledRows = scheduled.map { item in
            CheckInTodayRowModel(item: item, entries: store.entries(for: item, on: today))
        }
        let pendingRows = scheduledRows.filter { !$0.isCompletedOnce }
        let completedRows = scheduledRows.filter(\.isCompletedOnce)
        let unscheduledWithEntries = unscheduled
            .map { CheckInTodayRowModel(item: $0, entries: store.entries(for: $0, on: today)) }
            .filter { !$0.entries.isEmpty }
        let hiddenRows = unscheduled
            .filter { store.entries(for: $0, on: today).isEmpty }
            .map { CheckInTodayRowModel(item: $0, entries: []) }

        if !pendingRows.isEmpty {
            Section {
                ForEach(pendingRows) { row in
                    CheckInTodayRow(
                        row: row,
                        onTap: { handlePrimaryTap(row) },
                        onAddContent: { contentItem = row.item },
                        onOpenEntry: { entry in detailRoute = CheckInEntryDetailRoute(entryId: entry.id) }
                    )
                }
            }
        }

        if !completedRows.isEmpty || !unscheduledWithEntries.isEmpty {
            Section {
                ForEach(completedRows + unscheduledWithEntries) { row in
                    CheckInTodayRow(
                        row: row,
                        onTap: { handlePrimaryTap(row) },
                        onAddContent: { contentItem = row.item },
                        onOpenEntry: { entry in detailRoute = CheckInEntryDetailRoute(entryId: entry.id) }
                    )
                }
            }
        }

        if !hiddenRows.isEmpty {
            Section {
                DisclosureGroup(L10n.t("Not scheduled", appLanguage)) {
                    ForEach(hiddenRows) { row in
                        CheckInTodayRow(
                            row: row,
                            onTap: { handlePrimaryTap(row) },
                            onAddContent: { contentItem = row.item },
                            onOpenEntry: { entry in detailRoute = CheckInEntryDetailRoute(entryId: entry.id) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var historySections: some View {
        let allEntries = store.checkInFeedEntries.sorted { lhs, rhs in
            if lhs.occurredAt == rhs.occurredAt {
                return lhs.id > rhs.id
            }

            return lhs.occurredAt > rhs.occurredAt
        }
        let entries = allEntries.filter { entry in
            historyFilterItemId == nil || entry.item.id == historyFilterItemId
        }

        if allEntries.isEmpty {
            Section {
                ContentUnavailableView(L10n.t("No check-ins yet", appLanguage), systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
        } else {
            Section {
                CheckInHistoryFilterBar(
                    items: historyFilterItems,
                    selectedItemId: $historyFilterItemId
                )
            }

            Section {
                CheckInHistorySummary(entries: entries)
            }

            if entries.isEmpty {
                Section {
                    ContentUnavailableView(
                        L10n.t("No check-ins for this item", appLanguage),
                        systemImage: selectedHistoryFilterSymbol
                    )
                    .frame(maxWidth: .infinity)
                }
            } else {
                Section {
                    ForEach(entries) { entry in
                        Button {
                            detailRoute = CheckInEntryDetailRoute(entryId: entry.id)
                        } label: {
                            CheckInHistoryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var selectedHistoryFilterSymbol: String {
        guard let historyFilterItemId,
              let item = store.checkInItem(id: historyFilterItemId) else {
            return "line.3.horizontal.decrease.circle"
        }

        return item.symbolName
    }

    private func handlePrimaryTap(_ row: CheckInTodayRowModel) {
        if row.item.recordMode == .oncePerDay, let entry = row.entries.first {
            detailRoute = CheckInEntryDetailRoute(entryId: entry.id)
            return
        }

        Task {
            if let entry = await store.recordCheckIn(item: row.item) {
                undoEntry = entry
            }
        }
    }
}

private enum CheckInsMode {
    case today
    case history

    func toggleTitle(language: AppResolvedLanguage) -> String {
        switch self {
        case .today:
            return L10n.t("History", language)
        case .history:
            return L10n.t("Today", language)
        }
    }

    var toggleSystemImage: String {
        switch self {
        case .today:
            return "clock.arrow.circlepath"
        case .history:
            return "sun.max"
        }
    }
}

private struct CheckInTodayRowModel: Identifiable {
    let item: CheckInItem
    let entries: [CheckInEntry]

    var id: String {
        item.id
    }

    var isCompletedOnce: Bool {
        item.recordMode == .oncePerDay && !entries.isEmpty
    }
}

private struct CheckInTodayRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let row: CheckInTodayRowModel
    let onTap: () -> Void
    let onAddContent: () -> Void
    let onOpenEntry: (CheckInEntry) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                Image(systemName: leadingImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 36, height: 36)
                    .background(iconColor.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.isCompletedOnce ? L10n.t("Open check-in", appLanguage) : L10n.t("Check in", appLanguage))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(row.item.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if row.item.recordMode == .multiplePerDay, !row.entries.isEmpty {
                        Text("\(row.entries.count)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(iconColor)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(iconColor.opacity(0.12), in: Capsule())
                    }
                }

                if let latest = row.entries.first {
                    Button {
                        onOpenEntry(latest)
                    } label: {
                        Text(subtitle(for: latest))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(row.item.defaultShowInTimeline ? L10n.t("Shows in Timeline", appLanguage) : L10n.t("Private to check-ins", appLanguage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button(action: onAddContent) {
                Image(systemName: "ellipsis.bubble")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Add content", appLanguage))
        }
        .contentShape(Rectangle())
    }

    private var leadingImage: String {
        row.isCompletedOnce ? "checkmark.circle.fill" : row.item.symbolName
    }

    private var iconColor: Color {
        Color(hex: row.item.colorHex) ?? .accentColor
    }

    private func subtitle(for entry: CheckInEntry) -> String {
        let time = DateFormatter.checkInTime.string(from: entry.occurredAt)
        if entry.hasNote {
            return "\(time) · \(entry.note)"
        }

        return time
    }
}

struct CheckInTimelineRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let checkIn: CheckInFeedEntry
    var showsDate = true
    var showTagsInTimeline = true
    let onOpenDetail: () -> Void

    var body: some View {
        Button(action: onOpenDetail) {
            VStack(alignment: .leading, spacing: 9) {
                if showsDate {
                    HStack(spacing: 8) {
                        Text(MomentDateFormatter.timelineLabel(for: checkIn.occurredAt, language: appLanguage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if showTagsInTimeline, let tag = checkIn.tag {
                            TimelineTagChip(tag: tag, compact: true)
                        }
                        if checkIn.syncStatus != "synced" {
                            SyncBadge(status: checkIn.syncStatus)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: checkIn.item.symbolName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: 30, height: 30)
                        .background(iconColor.opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(checkIn.item.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)

                        if checkIn.entry.hasNote {
                            Text(checkIn.entry.note)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(5)
                        }

                        if !checkIn.media.isEmpty {
                            LazyVGrid(columns: imageGridColumns, alignment: .leading, spacing: 6) {
                                ForEach(checkIn.media.filter(\.isImage)) { media in
                                    CheckInImageThumbnail(media: media)
                                        .frame(width: 58, height: 58)
                                }
                            }
                            .padding(.top, checkIn.entry.hasNote ? 4 : 2)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var iconColor: Color {
        Color(hex: checkIn.item.colorHex) ?? .accentColor
    }

    private var imageGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 58, maximum: 72), spacing: 6)
        ]
    }
}

private struct CheckInHistorySummary: View {
    @Environment(\.appLanguage) private var appLanguage

    let entries: [CheckInFeedEntry]

    var body: some View {
        HStack(spacing: 10) {
            CheckInSummaryPill(title: L10n.t("Week", appLanguage), value: "\(recentCount(days: 7))")
            CheckInSummaryPill(title: L10n.t("Month", appLanguage), value: "\(recentCount(days: 30))")
            CheckInSummaryPill(title: L10n.t("Items", appLanguage), value: "\(Set(entries.map(\.item.id)).count)")
        }
    }

    private func recentCount(days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return entries.filter { $0.occurredAt >= cutoff }.count
    }
}

private struct CheckInSummaryPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: 56)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct CheckInHistoryFilterBar: View {
    @Environment(\.appLanguage) private var appLanguage

    let items: [CheckInItem]
    @Binding var selectedItemId: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CheckInHistoryFilterChip(
                    title: L10n.t("All", appLanguage),
                    symbolName: "tray.full",
                    color: .accentColor,
                    isSelected: selectedItemId == nil
                ) {
                    selectedItemId = nil
                }

                ForEach(items) { item in
                    CheckInHistoryFilterChip(
                        title: item.name,
                        symbolName: item.symbolName,
                        color: Color(hex: item.colorHex) ?? .accentColor,
                        isSelected: selectedItemId == item.id
                    ) {
                        selectedItemId = item.id
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct CheckInHistoryFilterChip: View {
    let title: String
    let symbolName: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            } icon: {
                Image(systemName: symbolName)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? color : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(isSelected ? color.opacity(0.16) : Color.secondary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct CheckInHistoryRow: View {
    let entry: CheckInFeedEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.item.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(hex: entry.item.colorHex) ?? .accentColor)
                .frame(width: 30, height: 30)
                .background((Color(hex: entry.item.colorHex) ?? .accentColor).opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.item.name)
                    .font(.body.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let media = entry.media.first(where: \.isImage) {
                CheckInImageThumbnail(media: media)
                    .frame(width: 44, height: 44)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var subtitle: String {
        let date = DateFormatter.checkInHistory.string(from: entry.occurredAt)
        if entry.entry.hasNote {
            return "\(date) · \(entry.entry.note)"
        }

        return date
    }
}

private struct CheckInImageThumbnail: View {
    let media: CheckInMedia

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.secondarySystemBackground)

                if let image = UIImage(contentsOfFile: media.localCompressedPath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    PlaceholderImage()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct CheckInCapturedImagePreview: View {
    let image: UIImage
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove photo")
        }
        .padding(.vertical, 4)
    }
}

private struct CheckInUndoBar: View {
    @Environment(\.appLanguage) private var appLanguage

    let entry: CheckInEntry
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(L10n.t("Checked in", appLanguage))
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Button(L10n.t("Undo", appLanguage), action: undo)
                .font(.subheadline.weight(.semibold))
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }
}

private struct CheckInManageView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage

    let onEdit: (CheckInItem) -> Void
    let onAdd: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.checkInItems.filter { $0.deletedAt == nil }) { item in
                        Button {
                            dismiss()
                            onEdit(item)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.symbolName)
                                    .foregroundStyle(Color(hex: item.colorHex) ?? .accentColor)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name)
                                        .font(.body.weight(.semibold))
                                    Text(item.recordMode.title(language: appLanguage))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if item.isArchived {
                                    Text(L10n.t("Archived", appLanguage))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(L10n.t("Manage", appLanguage))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("Done", appLanguage)) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                        onAdd()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(L10n.t("New check-in", appLanguage))
                }
            }
        }
    }
}

private struct CheckInItemEditorRoute: Identifiable {
    let itemId: String?

    var id: String {
        itemId ?? "new"
    }
}

private struct CheckInItemEditorView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage

    let item: CheckInItem?

    @State private var name: String
    @State private var symbolName: String
    @State private var colorHex: String
    @State private var recordMode: CheckInRecordMode
    @State private var activeWeekdays: Set<Int>
    @State private var defaultShowInTimeline: Bool
    @State private var tagId: String
    @State private var isSaving = false
    @State private var isDeleteConfirmationPresented = false

    init(item: CheckInItem?) {
        self.item = item
        _name = State(initialValue: item?.name ?? "")
        _symbolName = State(initialValue: item?.symbolName ?? "checkmark.circle")
        _colorHex = State(initialValue: item?.colorHex ?? "#61B88D")
        _recordMode = State(initialValue: item?.recordMode ?? .oncePerDay)
        _activeWeekdays = State(initialValue: Set(item?.activeWeekdays ?? [1, 2, 3, 4, 5, 6, 7]))
        _defaultShowInTimeline = State(initialValue: item?.defaultShowInTimeline ?? false)
        _tagId = State(initialValue: item?.tagId ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.t("Name", appLanguage), text: $name)
                    Picker(L10n.t("Mode", appLanguage), selection: $recordMode) {
                        ForEach(CheckInRecordMode.allCases) { mode in
                            Label(mode.title(language: appLanguage), systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                }

                Section(L10n.t("Icon", appLanguage)) {
                    CheckInIconPresetGrid(selection: $symbolName)
                    DisclosureGroup(L10n.t("Custom icon", appLanguage)) {
                        TextField("SF Symbol", text: $symbolName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section(L10n.t("Color", appLanguage)) {
                    CheckInColorPresetGrid(selection: $colorHex)
                    TextField("HEX", text: $colorHex)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: colorHex) { _, newValue in
                            colorHex = normalizedHexInput(newValue)
                        }
                }

                Section(L10n.t("Schedule", appLanguage)) {
                    WeekdayToggleGrid(selection: $activeWeekdays)
                }

                Section {
                    Toggle(L10n.t("Show in Timeline by default", appLanguage), isOn: $defaultShowInTimeline)
                    Picker(L10n.t("Tag", appLanguage), selection: $tagId) {
                        Text(L10n.t("None", appLanguage)).tag("")
                        ForEach(store.activePrimaryTags + store.activeTopicTags) { tag in
                            Text(L10n.tagName(tag, language: appLanguage)).tag(tag.id)
                        }
                    }
                }

                if item != nil {
                    Section {
                        Button(L10n.t("Archive", appLanguage)) {
                            if let item {
                                Task {
                                    await store.archiveCheckInItem(item)
                                    dismiss()
                                }
                            }
                        }

                        Button(L10n.t("Delete", appLanguage), role: .destructive) {
                            isDeleteConfirmationPresented = true
                        }
                    }
                }
            }
            .navigationTitle(item == nil ? L10n.t("New check-in", appLanguage) : L10n.t("Edit check-in", appLanguage))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("Cancel", appLanguage)) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("Save", appLanguage)) {
                        save()
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(L10n.t("Delete check-in?", appLanguage), isPresented: $isDeleteConfirmationPresented) {
                Button(L10n.t("Cancel", appLanguage), role: .cancel) {}
                Button(L10n.t("Delete", appLanguage), role: .destructive) {
                    if let item {
                        Task {
                            await store.deleteCheckInItem(item)
                            dismiss()
                        }
                    }
                }
            } message: {
                Text(L10n.t("This also removes its check-in history.", appLanguage))
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            let didSave: Bool
            if var item {
                item.name = name
                item.symbolName = symbolName
                item.colorHex = colorHex
                item.recordMode = recordMode
                item.activeWeekdays = Array(activeWeekdays)
                item.defaultShowInTimeline = defaultShowInTimeline
                item.tagId = tagId.isEmpty ? nil : tagId
                didSave = await store.updateCheckInItem(item)
            } else {
                didSave = await store.createCheckInItem(
                    name: name,
                    symbolName: symbolName,
                    colorHex: colorHex,
                    recordMode: recordMode,
                    activeWeekdays: Array(activeWeekdays),
                    defaultShowInTimeline: defaultShowInTimeline,
                    tagId: tagId.isEmpty ? nil : tagId
                )
            }
            isSaving = false
            if didSave {
                dismiss()
            }
        }
    }

    private func normalizedHexInput(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
            trimmed = "#\(trimmed)"
        }
        if trimmed.count > 7 {
            trimmed = String(trimmed.prefix(7))
        }
        return trimmed
    }
}

private struct CheckInIconPreset: Identifiable {
    let symbolName: String
    let title: String

    var id: String {
        symbolName
    }

    static let all: [CheckInIconPreset] = [
        CheckInIconPreset(symbolName: "fork.knife", title: "Meal"),
        CheckInIconPreset(symbolName: "figure.run", title: "Workout"),
        CheckInIconPreset(symbolName: "sun.max", title: "Wake up"),
        CheckInIconPreset(symbolName: "drop", title: "Water"),
        CheckInIconPreset(symbolName: "pills", title: "Medicine"),
        CheckInIconPreset(symbolName: "book.closed", title: "Read"),
        CheckInIconPreset(symbolName: "bed.double", title: "Sleep"),
        CheckInIconPreset(symbolName: "heart", title: "Health"),
        CheckInIconPreset(symbolName: "leaf", title: "Diet"),
        CheckInIconPreset(symbolName: "figure.mind.and.body", title: "Mindful"),
        CheckInIconPreset(symbolName: "cup.and.saucer", title: "Coffee"),
        CheckInIconPreset(symbolName: "checkmark.circle", title: "Check")
    ]
}

private struct CheckInIconPresetGrid: View {
    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(CheckInIconPreset.all) { preset in
                Button {
                    selection = preset.symbolName
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: preset.symbolName)
                            .font(.body.weight(.semibold))
                        Text(preset.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(selection == preset.symbolName ? Color.accentColor : Color.secondary)
                    .background(
                        selection == preset.symbolName ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CheckInColorPreset: Identifiable {
    let hex: String

    var id: String {
        hex
    }

    static let all: [CheckInColorPreset] = [
        CheckInColorPreset(hex: "#D94F45"),
        CheckInColorPreset(hex: "#E07A2F"),
        CheckInColorPreset(hex: "#F2B705"),
        CheckInColorPreset(hex: "#2EAD67"),
        CheckInColorPreset(hex: "#008C7A"),
        CheckInColorPreset(hex: "#2F80ED"),
        CheckInColorPreset(hex: "#7B61FF"),
        CheckInColorPreset(hex: "#C23883"),
        CheckInColorPreset(hex: "#5C6670"),
        CheckInColorPreset(hex: "#111827")
    ]
}

private struct CheckInColorPresetGrid: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
            ForEach(CheckInColorPreset.all) { preset in
                Button {
                    selection = preset.hex
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: preset.hex) ?? .accentColor)
                            .frame(width: 32, height: 32)
                        if selection.uppercased() == preset.hex {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        selection.uppercased() == preset.hex ? Color(hex: preset.hex)?.opacity(0.14) ?? Color.accentColor.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct WeekdayToggleGrid: View {
    @Binding var selection: Set<Int>

    private var symbols: [(Int, String)] {
        let formatter = DateFormatter()
        let names = formatter.shortStandaloneWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return names.enumerated().map { index, name in
            (index + 1, name)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(symbols, id: \.0) { weekday, title in
                Button {
                    if selection.contains(weekday), selection.count > 1 {
                        selection.remove(weekday)
                    } else {
                        selection.insert(weekday)
                    }
                } label: {
                    Text(String(title.prefix(1)))
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(selection.contains(weekday) ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: Capsule())
                        .foregroundStyle(selection.contains(weekday) ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CheckInContentEntryView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage

    let item: CheckInItem

    @State private var note = ""
    @State private var showInTimeline: Bool
    @State private var occurredAt = Date()
    @State private var isSaving = false
    @State private var capturedImageData: Data?
    @State private var isCameraPresented = false

    init(item: CheckInItem) {
        self.item = item
        _showInTimeline = State(initialValue: item.defaultShowInTimeline)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(L10n.t("Time", appLanguage), selection: $occurredAt)
                    Toggle(L10n.t("Show in Timeline", appLanguage), isOn: $showInTimeline)
                }

                Section(L10n.t("Note", appLanguage)) {
                    TextEditor(text: $note)
                        .frame(minHeight: 110)
                }

                Section(L10n.t("Photo", appLanguage)) {
                    if let capturedImageData, let image = UIImage(data: capturedImageData) {
                        CheckInCapturedImagePreview(image: image) {
                            self.capturedImageData = nil
                        }
                    }

                    Button {
                        isCameraPresented = true
                    } label: {
                        Label(L10n.t("Use Camera", appLanguage), systemImage: "camera")
                    }
                    .disabled(!CameraPicker.isAvailable)

                    Menu {
                        Button(L10n.t("Add Video", appLanguage), systemImage: "video") {}
                            .disabled(true)
                        Button(L10n.t("Record Audio", appLanguage), systemImage: "mic") {}
                            .disabled(true)
                    } label: {
                        Label(L10n.t("More media", appLanguage), systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(item.name)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("Cancel", appLanguage)) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("Save", appLanguage)) {
                        save()
                    }
                    .disabled(isSaving)
                }
            }
            .sheet(isPresented: $isCameraPresented) {
                CameraPicker { data in
                    capturedImageData = data
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            if await store.recordCheckIn(
                item: item,
                note: note,
                occurredAt: occurredAt,
                showInTimeline: showInTimeline,
                imageData: capturedImageData
            ) != nil {
                dismiss()
            }
            isSaving = false
        }
    }
}

struct CheckInEntryDetailRoute: Identifiable, Hashable {
    let entryId: String

    var id: String {
        entryId
    }
}

struct CheckInEntryDetailView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage

    let entryId: String

    @State private var draft: CheckInEntry?
    @State private var isSaving = false
    @State private var isDeleteConfirmationPresented = false
    @State private var capturedImageData: Data?
    @State private var removesExistingImage = false
    @State private var isCameraPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if let entry = draft,
                   let item = store.checkInItem(id: entry.itemId) {
                    Form {
                        Section {
                            LabeledContent(L10n.t("Check-in", appLanguage), value: item.name)
                            DatePicker(
                                L10n.t("Time", appLanguage),
                                selection: Binding(
                                    get: { entry.occurredAt },
                                    set: { draft?.occurredAt = $0 }
                                )
                            )
                            Toggle(
                                L10n.t("Show in Timeline", appLanguage),
                                isOn: Binding(
                                    get: { entry.showInTimeline },
                                    set: { draft?.showInTimeline = $0 }
                                )
                            )
                        }

                        Section(L10n.t("Note", appLanguage)) {
                            TextEditor(
                                text: Binding(
                                    get: { entry.note },
                                    set: { draft?.note = $0 }
                                )
                            )
                            .frame(minHeight: 120)
                        }

                        Section(L10n.t("Photo", appLanguage)) {
                            if let capturedImageData, let image = UIImage(data: capturedImageData) {
                                CheckInCapturedImagePreview(image: image) {
                                    self.capturedImageData = nil
                                    self.removesExistingImage = false
                                }
                            } else if let existingMedia, !removesExistingImage {
                                ZStack(alignment: .topTrailing) {
                                    CheckInImageThumbnail(media: existingMedia)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 180)

                                    Button {
                                        removesExistingImage = true
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.55))
                                            .padding(8)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(L10n.t("Remove photo", appLanguage))
                                }
                                .padding(.vertical, 4)
                            }

                            Button {
                                isCameraPresented = true
                            } label: {
                                Label(L10n.t(existingMedia == nil && capturedImageData == nil ? "Use Camera" : "Replace Photo", appLanguage), systemImage: "camera")
                            }
                            .disabled(!CameraPicker.isAvailable)

                            Menu {
                                Button(L10n.t("Add Video", appLanguage), systemImage: "video") {}
                                    .disabled(true)
                                Button(L10n.t("Record Audio", appLanguage), systemImage: "mic") {}
                                    .disabled(true)
                            } label: {
                                Label(L10n.t("More media", appLanguage), systemImage: "plus.circle")
                            }
                        }

                        Section {
                            Button(L10n.t("Cancel check-in", appLanguage), role: .destructive) {
                                isDeleteConfirmationPresented = true
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(L10n.t("Check-in unavailable", appLanguage), systemImage: "checkmark.circle")
                }
            }
            .navigationTitle(L10n.t("Check-in", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("Close", appLanguage)) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("Save", appLanguage)) {
                        save()
                    }
                    .disabled(isSaving || draft == nil)
                }
            }
            .onAppear {
                draft = store.checkInEntry(id: entryId)
            }
            .sheet(isPresented: $isCameraPresented) {
                CameraPicker { data in
                    capturedImageData = data
                    removesExistingImage = false
                }
            }
            .alert(L10n.t("Cancel check-in?", appLanguage), isPresented: $isDeleteConfirmationPresented) {
                Button(L10n.t("Keep", appLanguage), role: .cancel) {}
                Button(L10n.t("Cancel check-in", appLanguage), role: .destructive) {
                    if let draft {
                        Task {
                            await store.deleteCheckInEntry(draft)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var existingMedia: CheckInMedia? {
        store.checkInMedia
            .filter { $0.entryId == entryId && $0.deletedAt == nil && $0.isImage }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }

                return lhs.sortOrder < rhs.sortOrder
            }
            .first
    }

    private func save() {
        guard let draft else {
            return
        }

        isSaving = true
        Task {
            guard await store.updateCheckInEntry(draft) else {
                isSaving = false
                return
            }

            if capturedImageData != nil || removesExistingImage {
                guard await store.replaceCheckInEntryImage(entry: draft, imageData: capturedImageData) else {
                    isSaving = false
                    return
                }
            }

            dismiss()
            isSaving = false
        }
    }
}

private extension DateFormatter {
    static let checkInTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let checkInHistory: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
