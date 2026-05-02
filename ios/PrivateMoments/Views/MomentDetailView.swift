import PhotosUI
import SwiftUI
import UIKit

struct MomentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TimelineStore

    let postId: String

    @State private var isEditing = false
    @State private var confirmDelete = false
    @State private var gallery: DetailMediaGallery?
    @State private var videoPlayer: VideoPlayerRoute?

    var body: some View {
        Group {
            if let item = store.item(id: postId) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(item)

                        if !item.post.text.isEmpty {
                            Text(item.post.text)
                                .font(.body)
                                .textSelection(.enabled)
                        }

                        if !item.media.isEmpty {
                            mediaGrid(item.media)
                        }
                    }
                    .padding()
                }
                .navigationTitle("Moment")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await store.toggleFavorite(item)
                            }
                        } label: {
                            Image(systemName: item.post.isFavorite ? "star.fill" : "star")
                                .foregroundStyle(item.post.isFavorite ? Color.yellow : Color.primary)
                        }
                        .accessibilityLabel(item.post.isFavorite ? "Remove favorite" : "Favorite moment")

                        Button {
                            isEditing = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .disabled(!store.canEdit(item))
                        .accessibilityLabel("Edit moment")

                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete moment")
                    }
                }
                .sheet(isPresented: $isEditing) {
                    EditMomentView(postId: postId)
                }
                .fullScreenCover(item: $gallery) { gallery in
                    MediaGalleryView(media: gallery.media, initialIndex: gallery.startIndex)
                }
                .fullScreenCover(item: $videoPlayer) { route in
                    VideoMomentPlayerView(media: route.media)
                }
                .confirmationDialog("Delete this moment?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        Task {
                            await store.deletePost(item)
                            dismiss()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes the moment from your timeline and syncs the deletion to your Mac.")
                }
            } else {
                ContentUnavailableView("Moment unavailable", systemImage: "rectangle.stack.badge.minus")
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
                Text("Edited \(editedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !store.canEdit(item) {
                Text("Editing is available after this moment finishes syncing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func mediaGrid(_ media: [TimelineMedia]) -> some View {
        if let audio = media.first, audio.isAudio {
            TimelineAudioCard(media: audio)
        } else if let video = media.first, video.isVideo {
            Button {
                videoPlayer = VideoPlayerRoute(media: video)
            } label: {
                TimelineVideoCard(media: video)
            }
            .buttonStyle(.plain)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: media.count == 1 ? 1 : 3), spacing: 6) {
                ForEach(Array(media.enumerated()), id: \.element.id) { index, item in
                    Button {
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
            .navigationTitle("Edit Moment")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isSaving)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
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
                            Text("Save")
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
            .confirmationDialog("Continue editing draft?", isPresented: $showDraftChoice, titleVisibility: .visible) {
                Button("Continue Editing Draft") {
                    loadDraft()
                }
                Button("Discard Draft", role: .destructive) {
                    EditDraftStore.clear(postId: postId)
                    loadFromCurrentItem()
                }
            } message: {
                Text("There is an unsaved edit draft for this moment.")
            }
            .confirmationDialog("Discard edit draft?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Draft", role: .destructive) {
                    EditDraftStore.clear(postId: postId)
                    loadFromCurrentItem()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var editFieldsSection: some View {
        VStack(spacing: 0) {
            PlainTextListEditor(text: $text)
                .frame(minHeight: 160)

            Divider()

            DatePicker("Date", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
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
                Label("Add from Library", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .padding(.vertical, 14)
            .disabled(mediaItems.count >= 9)

            Divider()
                .padding(.leading, 80)

            Button {
                showingCamera = true
            } label: {
                Label("Use Camera", systemImage: "camera")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .padding(.vertical, 14)
            .disabled(!CameraPicker.isAvailable || mediaItems.count >= 9)

            if !mediaItems.isEmpty {
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

    private var discardDraftSection: some View {
        Button("Discard Draft", role: .destructive) {
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
            .accessibilityLabel("Remove image")
        }
        .frame(width: sideLength, height: sideLength)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private var image: some View {
        CachedEditMediaImage(item: item)
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
