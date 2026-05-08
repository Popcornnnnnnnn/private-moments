import PhotosUI
import SwiftUI
import UIKit

struct MomentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    @EnvironmentObject private var store: TimelineStore
    @EnvironmentObject private var playbackCenter: MediaPlaybackCenter

    let postId: String

    @State private var isEditing = false
    @State private var confirmDelete = false
    @State private var gallery: DetailMediaGallery?
    @State private var videoPlayer: VideoPlayerRoute?
    @State private var isTagEditorPresented = false
    @State private var didCopyText = false

    var body: some View {
        Group {
            if let item = store.item(id: postId) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(item)
                        tagsSection(item)

                        if !item.post.text.isEmpty {
                            MomentTextView(text: item.post.text, style: .detail)
                        }

                        if !item.media.isEmpty {
                            mediaGrid(item.media)
                        }
                    }
                    .padding()
                }
                .navigationTitle(L10n.t("Moment", appLanguage))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if !item.post.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    copyMomentText(item.post.text)
                                } label: {
                                    Label(L10n.t(didCopyText ? "Copied" : "Copy text", appLanguage), systemImage: didCopyText ? "checkmark" : "doc.on.doc")
                                }
                            }

                            Button {
                                Task {
                                    await store.togglePinned(item)
                                }
                            } label: {
                                Label(
                                    L10n.t(item.post.isPinned ? "Unpin moment" : "Pin moment", appLanguage),
                                    systemImage: item.post.isPinned ? "pin.slash" : "pin"
                                )
                            }

                            Button {
                                Task {
                                    await store.toggleFavorite(item)
                                }
                            } label: {
                                Label(
                                    L10n.t(item.post.isFavorite ? "Remove favorite" : "Favorite moment", appLanguage),
                                    systemImage: item.post.isFavorite ? "star.slash" : "star"
                                )
                            }

                            Button {
                                playbackCenter.pause()
                                isEditing = true
                            } label: {
                                Label(L10n.t("Edit moment", appLanguage), systemImage: "square.and.pencil")
                            }
                            .disabled(!store.canEdit(item))

                            Button(role: .destructive) {
                                confirmDelete = true
                            } label: {
                                Label(L10n.t("Delete moment", appLanguage), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel(L10n.t("More", appLanguage))
                    }
                }
                .sheet(isPresented: $isEditing) {
                    EditMomentView(postId: postId)
                }
                .sheet(isPresented: $isTagEditorPresented) {
                    if store.showTagsInTimeline {
                        EditTagsView(postId: postId)
                    }
                }
                .fullScreenCover(item: $gallery) { gallery in
                    MediaGalleryView(media: gallery.media, initialIndex: gallery.startIndex)
                }
                .fullScreenCover(item: $videoPlayer) { route in
                    VideoMomentPlayerView(media: route.media)
                }
                .confirmationDialog(L10n.t("Delete this moment?", appLanguage), isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button(L10n.t("Delete", appLanguage), role: .destructive) {
                        Task {
                            await store.deletePost(item)
                            dismiss()
                        }
                    }
                    Button(L10n.t("Cancel", appLanguage), role: .cancel) {}
                } message: {
                    Text(L10n.t("This removes the moment from your timeline and syncs the deletion to your Mac.", appLanguage))
                }
                .onDisappear {
                    playbackCenter.pauseForInterfaceChange()
                }
                .onChange(of: item.post.text) { _, _ in
                    didCopyText = false
                }
            } else {
                ContentUnavailableView(L10n.t("Moment unavailable", appLanguage), systemImage: "rectangle.stack.badge.minus")
            }
        }
    }

    private func copyMomentText(_ text: String) {
        UIPasteboard.general.string = text
        didCopyText = true

        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                didCopyText = false
            }
        }
    }

    private func header(_ item: TimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.post.occurredAt, style: .date)
                    .font(.headline)
                Text(item.post.occurredAt, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                SyncBadge(status: item.post.syncStatus)
            }

            if let editedAt = item.post.localEditedAt {
                Text("\(L10n.t("Edited", appLanguage)) \(editedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !store.canEdit(item) {
                Text(L10n.t("Editing is available after this moment finishes syncing.", appLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func tagsSection(_ item: TimelineItem) -> some View {
        if store.showTagsInTimeline && (!item.tags.isEmpty || !store.activePrimaryTags.isEmpty || !store.activeTopicTags.isEmpty) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.t("Tags", appLanguage))
                        .font(.headline)
                    Spacer()
                    Button {
                        playbackCenter.pause()
                        isTagEditorPresented = true
                    } label: {
                        Image(systemName: "tag")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Edit tags", appLanguage))
                }

                if item.tags.isEmpty {
                    Text(L10n.t("No tags", appLanguage))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    DetailFlowLayout(spacing: 8, rowSpacing: 8) {
                        ForEach(item.tags) { assignedTag in
                            DetailTagBadge(tag: assignedTag.tag)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func mediaGrid(_ media: [TimelineMedia]) -> some View {
        if let audio = media.first, audio.isAudio {
            TimelineAudioCard(media: audio, style: .detail)
        } else if let video = media.first, video.isVideo {
            Button {
                playbackCenter.pause()
                videoPlayer = VideoPlayerRoute(media: video)
            } label: {
                TimelineVideoCard(media: video)
            }
            .buttonStyle(.plain)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: media.count == 1 ? 1 : 3), spacing: 6) {
                ForEach(Array(media.enumerated()), id: \.element.id) { index, item in
                    Button {
                        playbackCenter.pause()
                        gallery = DetailMediaGallery(media: media, startIndex: index)
                    } label: {
                        TimelineImage(media: item, style: media.count == 1 ? .single : .grid)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct DetailMediaGallery: Identifiable {
    let media: [TimelineMedia]
    let startIndex: Int

    var id: String {
        "\(media.map(\.id).joined(separator: "-"))-\(startIndex)"
    }
}

struct EditMomentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    @EnvironmentObject private var store: TimelineStore

    let postId: String

    @State private var text = ""
    @State private var occurredAt = Date()
    @State private var mediaItems: [MomentEditMediaItem] = []
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var showDraftChoice = false
    @State private var showDiscardConfirmation = false
    @State private var hasLoaded = false
    @State private var draggedItemID: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    editFieldsSection
                    mediaSection

                    if EditDraftStore.hasDraft(postId: postId) {
                        discardDraftSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDisabled(draggedItemID != nil)
            .navigationTitle(L10n.t("Edit Moment", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isSaving)
            .interactiveDismissDisabled(isSaving)
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
                                .controlSize(.small)
                        } else {
                            Text(L10n.t("Save", appLanguage))
                        }
                    }
                    .disabled(isSaving || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mediaItems.isEmpty))
                }
            }
            .task {
                loadInitialState()
            }
            .onChange(of: text) { _, _ in
                guard hasLoaded else { return }
                saveDraft()
            }
            .onChange(of: occurredAt) { _, _ in
                guard hasLoaded else { return }
                saveDraft()
            }
            .onChange(of: selectedItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    await appendPhotos(items)
                    selectedItems = []
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker { data in
                    appendNewImage(data)
                }
            }
            .confirmationDialog(L10n.t("Continue editing draft?", appLanguage), isPresented: $showDraftChoice, titleVisibility: .visible) {
                Button(L10n.t("Continue Editing Draft", appLanguage)) {
                    loadDraft()
                }
                Button(L10n.t("Discard Draft", appLanguage), role: .destructive) {
                    EditDraftStore.clear(postId: postId)
                    loadFromCurrentItem()
                }
            } message: {
                Text(L10n.t("There is an unsaved edit draft for this moment.", appLanguage))
            }
            .confirmationDialog(L10n.t("Discard edit draft?", appLanguage), isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button(L10n.t("Discard Draft", appLanguage), role: .destructive) {
                    EditDraftStore.clear(postId: postId)
                    loadFromCurrentItem()
                }
                Button(L10n.t("Cancel", appLanguage), role: .cancel) {}
            }
        }
    }

    private var editFieldsSection: some View {
        VStack(spacing: 0) {
            MarkdownTextEditor(text: $text)
                .frame(minHeight: 160)

            Divider()

            DatePicker(L10n.t("Date", appLanguage), selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                .padding(.vertical, 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var mediaSection: some View {
        VStack(spacing: 0) {
            PhotosPicker(selection: $selectedItems, maxSelectionCount: max(0, 9 - mediaItems.count), matching: .images) {
                Label(L10n.t("Add from Library", appLanguage), systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .padding(.vertical, 14)
            .disabled(mediaItems.count >= 9 || hasNonImageMedia)

            Divider()
                .padding(.leading, 80)

            Button {
                showingCamera = true
            } label: {
                Label(L10n.t("Use Camera", appLanguage), systemImage: "camera")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .padding(.vertical, 14)
            .disabled(!CameraPicker.isAvailable || mediaItems.count >= 9 || hasNonImageMedia)

            if hasNonImageMedia {
                Divider()
                    .padding(.leading, 80)

                ForEach(nonImageMediaItems) { item in
                    EditableFileMediaPreview(item: item) {
                        removeMedia(item)
                    }
                    .padding(.vertical, 12)
                }
            } else if !mediaItems.isEmpty {
                Divider()
                    .padding(.leading, 80)

                EditableMediaGrid(
                    items: $mediaItems,
                    draggedItemID: $draggedItemID,
                    onRemove: removeMedia,
                    onCommit: saveDraft
                )
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var hasNonImageMedia: Bool {
        mediaItems.contains { !$0.isEditableImage }
    }

    private var nonImageMediaItems: [MomentEditMediaItem] {
        mediaItems.filter { !$0.isEditableImage }
    }

    private var discardDraftSection: some View {
        Button(L10n.t("Discard Draft", appLanguage), role: .destructive) {
            showDiscardConfirmation = true
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func loadInitialState() {
        guard !hasLoaded else {
            return
        }

        loadFromCurrentItem()
        hasLoaded = true

        if EditDraftStore.hasDraft(postId: postId) {
            showDraftChoice = true
        }
    }

    private func loadFromCurrentItem() {
        guard let item = store.item(id: postId) else {
            return
        }

        text = item.post.text
        occurredAt = item.post.occurredAt
        mediaItems = item.media.map { MomentEditMediaItem(id: $0.id, source: .existing($0)) }
    }

    private func loadDraft() {
        guard let item = store.item(id: postId),
              let draft = EditDraftStore.load(postId: postId, currentItem: item) else {
            loadFromCurrentItem()
            return
        }

        text = draft.text
        occurredAt = draft.occurredAt
        mediaItems = Array(draft.mediaItems.prefix(9))
    }

    private func saveDraft() {
        try? EditDraftStore.save(postId: postId, text: text, occurredAt: occurredAt, mediaItems: mediaItems)
    }

    private func appendPhotos(_ items: [PhotosPickerItem]) async {
        for item in items.prefix(max(0, 9 - mediaItems.count)) {
            if let data = try? await item.loadTransferable(type: Data.self) {
                appendNewImage(data)
            }
        }
    }

    private func appendNewImage(_ data: Data) {
        guard mediaItems.count < 9 else {
            return
        }

        mediaItems.append(MomentEditMediaItem(id: UUID().uuidString, source: .new(data)))
        saveDraft()
    }

    private func removeMedia(_ item: MomentEditMediaItem) {
        mediaItems.removeAll { $0.id == item.id }
        saveDraft()
    }

    private func save() {
        guard !isSaving else {
            return
        }

        guard let item = store.item(id: postId) else {
            dismiss()
            return
        }

        let textSnapshot = text
        let occurredAtSnapshot = occurredAt
        let mediaSnapshot = mediaItems
        isSaving = true

        Task {
            let didSave = await store.updatePost(
                item: item,
                text: textSnapshot,
                occurredAt: occurredAtSnapshot,
                mediaItems: mediaSnapshot
            )

            await MainActor.run {
                if didSave {
                    EditDraftStore.clear(postId: postId)
                    dismiss()
                } else {
                    isSaving = false
                }
            }
        }
    }
}

private struct EditableMediaGrid: View {
    @Binding var items: [MomentEditMediaItem]
    @Binding var draggedItemID: String?

    let onRemove: (MomentEditMediaItem) -> Void
    let onCommit: () -> Void

    @State private var activeItemID: String?
    @State private var activeLocation: CGPoint?
    @State private var didReorder = false
    @State private var lastFeedbackIndex: Int?

    private let columns = 3
    private let spacing: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let cellSize = (proxy.size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)

            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let isDragging = activeItemID == item.id
                    let offset = offset(for: index, cellSize: cellSize, isDragging: isDragging)

                    EditableMediaThumbnail(item: item, sideLength: cellSize, isDragging: isDragging) {
                        onRemove(item)
                    }
                    .contentShape(Rectangle())
                    .offset(x: offset.width, y: offset.height)
                    .scaleEffect(isDragging ? 1.04 : 1)
                    .shadow(color: .black.opacity(isDragging ? 0.3 : 0), radius: isDragging ? 16 : 0, y: isDragging ? 8 : 0)
                    .zIndex(isDragging ? 2 : 0)
                    .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.9, blendDuration: 0.05), value: items.map(\.id))
                    .gesture(dragGesture(for: item, cellSize: cellSize))
                }
            }
            .coordinateSpace(name: "edit-media-grid")
        }
        .aspectRatio(gridAspectRatio, contentMode: .fit)
    }

    private var rowCount: Int {
        max(1, Int(ceil(Double(items.count) / Double(columns))))
    }

    private var gridAspectRatio: CGFloat {
        CGFloat(columns) / CGFloat(rowCount)
    }

    private func position(for index: Int, cellSize: CGFloat) -> CGSize {
        CGSize(
            width: CGFloat(index % columns) * (cellSize + spacing),
            height: CGFloat(index / columns) * (cellSize + spacing)
        )
    }

    private func center(for index: Int, cellSize: CGFloat) -> CGPoint {
        let position = position(for: index, cellSize: cellSize)
        return CGPoint(
            x: position.width + cellSize / 2,
            y: position.height + cellSize / 2
        )
    }

    private func offset(for index: Int, cellSize: CGFloat, isDragging: Bool) -> CGSize {
        if isDragging, let activeLocation {
            return CGSize(
                width: activeLocation.x - cellSize / 2,
                height: activeLocation.y - cellSize / 2
            )
        }

        return position(for: index, cellSize: cellSize)
    }

    private func dragGesture(for item: MomentEditMediaItem, cellSize: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.08)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("edit-media-grid")))
            .onChanged { value in
                switch value {
                case .first(true):
                    beginDragging(item, cellSize: cellSize)

                case .second(true, let drag?):
                    beginDragging(item, cellSize: cellSize)
                    activeLocation = drag.location
                    moveActiveItemIfNeeded(item, location: drag.location, cellSize: cellSize)

                default:
                    break
                }
            }
            .onEnded { _ in
                finishDragging(item)
            }
    }

    private func beginDragging(_ item: MomentEditMediaItem, cellSize: CGFloat) {
        guard activeItemID == nil else {
            return
        }

        activeItemID = item.id
        draggedItemID = item.id
        didReorder = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)

        if let index = items.firstIndex(where: { $0.id == item.id }) {
            activeLocation = center(for: index, cellSize: cellSize)
            lastFeedbackIndex = index
        }
    }

    private func moveActiveItemIfNeeded(_ item: MomentEditMediaItem, location: CGPoint, cellSize: CGFloat) {
        guard let from = items.firstIndex(where: { $0.id == item.id }),
              let target = nearestIndex(at: location, cellSize: cellSize),
              target != from else {
            return
        }

        withAnimation(.interactiveSpring(response: 0.14, dampingFraction: 0.92, blendDuration: 0.04)) {
            let moved = items.remove(at: from)
            items.insert(moved, at: target)
        }

        if lastFeedbackIndex != target {
            UISelectionFeedbackGenerator().selectionChanged()
            lastFeedbackIndex = target
        }

        didReorder = true
    }

    private func finishDragging(_ item: MomentEditMediaItem) {
        defer {
            activeItemID = nil
            draggedItemID = nil
            activeLocation = nil
            didReorder = false
            lastFeedbackIndex = nil
        }

        if didReorder {
            onCommit()
        }
    }

    private func nearestIndex(at location: CGPoint, cellSize: CGFloat) -> Int? {
        guard !items.isEmpty else {
            return nil
        }

        var nearest = 0
        var nearestDistance = CGFloat.greatestFiniteMagnitude

        for index in items.indices {
            let center = center(for: index, cellSize: cellSize)
            let distance = hypot(center.x - location.x, center.y - location.y)
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = index
            }
        }

        return nearest
    }
}

private struct EditableMediaThumbnail: View {
    @Environment(\.appLanguage) private var appLanguage

    let item: MomentEditMediaItem
    let sideLength: CGFloat
    let isDragging: Bool
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            image
                .allowsHitTesting(false)
                .frame(width: sideLength, height: sideLength)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .opacity(isDragging ? 0.78 : 1)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(4)
                }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.62))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel(L10n.t("Remove image", appLanguage))
        }
        .frame(width: sideLength, height: sideLength)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private var image: some View {
        CachedEditMediaImage(item: item)
    }
}

private struct EditableFileMediaPreview: View {
    @Environment(\.appLanguage) private var appLanguage

    let item: MomentEditMediaItem
    let onRemove: () -> Void

    var body: some View {
        if let media = item.existingMedia {
            ZStack(alignment: .topTrailing) {
                filePreview(media)

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.62))
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel(L10n.t(media.isAudio ? "Remove audio" : "Remove video", appLanguage))
            }
        }
    }

    @ViewBuilder
    private func filePreview(_ media: TimelineMedia) -> some View {
        if media.isAudio {
            TimelineAudioCard(media: media)
                .padding(.trailing, 34)
        } else if media.isVideo {
            TimelineVideoCard(media: media)
        }
    }
}

private struct CachedEditMediaImage: View {
    let item: MomentEditMediaItem

    @State private var uiImage: UIImage?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                PlaceholderImage()
                    .background(Color(.secondarySystemBackground))
            }
        }
        .task(id: item.id) {
            guard !didLoad else {
                return
            }

            didLoad = true
            uiImage = await Task.detached(priority: .userInitiated) {
                Self.loadImage(item)
            }.value
        }
    }

    nonisolated private static func loadImage(_ item: MomentEditMediaItem) -> UIImage? {
        switch item.source {
        case .existing(let media):
            return UIImage(contentsOfFile: media.localCompressedPath)

        case .new(let data):
            return UIImage(data: data)
        }
    }
}

private extension MomentEditMediaItem {
    var existingMedia: TimelineMedia? {
        if case .existing(let media) = source {
            return media
        }

        return nil
    }

    var isEditableImage: Bool {
        switch source {
        case .new:
            return true
        case .existing(let media):
            return media.isImage
        }
    }
}
