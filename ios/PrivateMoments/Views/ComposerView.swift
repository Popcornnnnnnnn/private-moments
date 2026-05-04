import PhotosUI
import SwiftUI
import UIKit
import AVFoundation

struct ComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: TimelineStore

    @State private var text = ComposerDraftStore.loadText()
    @State private var occurredAt = ComposerDraftStore.loadOccurredAt()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var imageData: [Data] = ComposerDraftStore.loadImages()
    @State private var videoDraft: PreparedMomentMedia?
    @State private var audioDraft: PreparedMomentMedia?
    @State private var showingCamera = false
    @State private var isPublishing = false
    @State private var isProcessingVideo = false
    @State private var isImportingShare = false
    @State private var mediaError: String?
    @State private var selectedPrimaryTagId: String?
    @StateObject private var audioRecorder = AudioRecorderController()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MarkdownTextEditor(text: $text, onPasteImages: handlePastedImages)
                        .frame(minHeight: 140)

                    DatePicker(L10n.t("Date", appLanguage), selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])

                    if !store.activePrimaryTags.isEmpty {
                        Picker(L10n.t("Primary Tag", appLanguage), selection: $selectedPrimaryTagId) {
                            Text(L10n.t("AI decides", appLanguage)).tag(nil as String?)
                            ForEach(store.activePrimaryTags) { tag in
                                Text(L10n.tagName(tag, language: appLanguage)).tag(Optional(tag.id))
                            }
                        }
                    }
                }

                Section {
                    mediaControls
                    mediaPreview
                }
            }
            .navigationTitle(L10n.t("New Moment", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("Cancel", appLanguage)) {
                        dismiss()
                    }
                    .disabled(isPublishing)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        publish()
                    } label: {
                        if isPublishing {
                            ProgressView()
                        } else {
                            Text(L10n.t("Publish", appLanguage))
                        }
                    }
                    .disabled(!canPublish || isPublishing)
                    .accessibilityLabel(L10n.t(isPublishing ? "Publishing" : "Publish", appLanguage))
                }
            }
            .onChange(of: text) { _, value in
                ComposerDraftStore.save(text: value, occurredAt: occurredAt)
            }
            .onChange(of: occurredAt) { _, value in
                ComposerDraftStore.save(text: text, occurredAt: value)
            }
            .onChange(of: selectedItems) { _, items in
                Task {
                    imageData = await loadImageData(from: items)
                    try? ComposerDraftStore.saveImages(imageData)
                }
            }
            .onChange(of: selectedVideoItem) { _, item in
                guard let item else { return }
                Task {
                    await processVideo(item)
                    selectedVideoItem = nil
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker { data in
                    imageData = Array((imageData + [data]).prefix(ComposerImageDraft.maxImageCount))
                    try? ComposerDraftStore.saveImages(imageData)
                }
            }
            .task {
                await loadPendingShareImportIfNeeded()
                await loadRecoverableAudioDraft()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else {
                    return
                }

                audioRecorder.refreshElapsedTime()
            }
            .alert(L10n.t("Media unavailable", appLanguage), isPresented: mediaErrorBinding) {
                Button(L10n.t("OK", appLanguage), role: .cancel) {}
            } message: {
                Text(mediaError ?? "")
            }
        }
    }

    private var canPublish: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !imageData.isEmpty ||
            videoDraft != nil ||
            audioDraft != nil) &&
            !isProcessingVideo &&
            !isImportingShare &&
            !audioRecorder.isRecording
    }

    private var hasNonImageMedia: Bool {
        videoDraft != nil || audioDraft != nil || audioRecorder.isRecording
    }

    private var hasAnyMedia: Bool {
        !imageData.isEmpty || videoDraft != nil || audioDraft != nil || audioRecorder.isRecording
    }

    private var mediaErrorBinding: Binding<Bool> {
        Binding(
            get: { mediaError != nil || audioRecorder.errorMessage != nil },
            set: { _ in
                mediaError = nil
                audioRecorder.errorMessage = nil
            }
        )
    }

    @ViewBuilder
    private var mediaControls: some View {
        PhotosPicker(selection: $selectedItems, maxSelectionCount: ComposerImageDraft.maxImageCount, matching: .images) {
            Label(L10n.t("Add Photos", appLanguage), systemImage: "photo.on.rectangle.angled")
        }
        .disabled(hasNonImageMedia)

        Button {
            showingCamera = true
        } label: {
            Label(L10n.t("Use Camera", appLanguage), systemImage: "camera")
        }
        .disabled(!CameraPicker.isAvailable || hasNonImageMedia)

        PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
            Label(L10n.t("Add Video", appLanguage), systemImage: "video")
        }
        .disabled(hasAnyMedia || isProcessingVideo)

        Button {
            toggleRecording()
        } label: {
            Label(L10n.t(audioRecorder.isRecording ? "Stop Recording" : "Record Audio", appLanguage), systemImage: audioRecorder.isRecording ? "stop.circle" : "mic")
        }
        .disabled((hasAnyMedia && !audioRecorder.isRecording) || isProcessingVideo)
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if isProcessingVideo {
            HStack(spacing: 10) {
                ProgressView()
                Text(L10n.t("Processing video", appLanguage))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }

        if isImportingShare {
            HStack(spacing: 10) {
                ProgressView()
                Text(L10n.t("Importing shared item", appLanguage))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }

        if audioRecorder.isRecording {
            HStack {
                Label(
                    L10n.t(audioRecorder.isPaused ? "Recording paused" : "Recording", appLanguage),
                    systemImage: audioRecorder.isPaused ? "pause.circle.fill" : "waveform"
                )
                Spacer()
                Text(mediaDurationLabel(audioRecorder.elapsedSeconds))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button(audioRecorder.isPaused ? "Resume" : "Pause") {
                    audioRecorder.pauseOrResume()
                }
            }
            .padding(.vertical, 8)
        }

        if let videoDraft {
            DraftVideoPreview(media: videoDraft) {
                self.videoDraft = nil
            }
        }

        if let audioDraft {
            DraftAudioPreview(media: audioDraft) {
                audioRecorder.discard()
                self.audioDraft = nil
            }
        }

        if !imageData.isEmpty {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(Array(imageData.enumerated()), id: \.offset) { index, data in
                    if let image = UIImage(data: data) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(1, contentMode: .fill)
                                .frame(minHeight: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            if imageData.count > 1 {
                                HStack(spacing: 2) {
                                    Button {
                                        moveImage(from: index, to: index - 1)
                                    } label: {
                                        Image(systemName: "chevron.left.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.62))
                                    }
                                    .disabled(index == 0)
                                    .accessibilityLabel(L10n.t("Move image left", appLanguage))

                                    Button {
                                        moveImage(from: index, to: index + 1)
                                    } label: {
                                        Image(systemName: "chevron.right.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.62))
                                    }
                                    .disabled(index == imageData.count - 1)
                                    .accessibilityLabel(L10n.t("Move image right", appLanguage))
                                }
                                .font(.title3)
                                .buttonStyle(.plain)
                                .padding(4)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            }

                            Button {
                                removeImage(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.62))
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                            .padding(4)
                            .accessibilityLabel(L10n.t("Remove image", appLanguage))
                        }
                    }
                }
            }
        }
    }

    private func publish() {
        guard canPublish, !isPublishing else {
            return
        }

        isPublishing = true
        Task {
            let didCreate = await store.createPost(
                text: text,
                imageData: imageData,
                video: videoDraft,
                audio: audioDraft,
                occurredAt: occurredAt,
                primaryTagId: selectedPrimaryTagId
            )
            isPublishing = false

            if didCreate {
                ComposerDraftStore.clear()
                dismiss()
            }
        }
    }

    private func loadImageData(from items: [PhotosPickerItem]) async -> [Data] {
        var result: [Data] = []

        for item in items.prefix(ComposerImageDraft.maxImageCount) {
            if let data = try? await item.loadTransferable(type: Data.self) {
                result.append(data)
            }
        }

        return result
    }

    private func handlePastedImages(_ pastedImages: [Data]) {
        guard !pastedImages.isEmpty else {
            return
        }

        guard !hasNonImageMedia else {
            mediaError = L10n.t("Remove audio or video before adding photos.", appLanguage)
            return
        }

        let result = ComposerImageDraft.appending(pastedImages, to: imageData)
        guard result.didAppend else {
            mediaError = L10n.t("You can add up to 9 photos.", appLanguage)
            return
        }

        imageData = result.images
        try? ComposerDraftStore.saveImages(imageData)

        if result.didDiscard {
            mediaError = L10n.t("Only the available photo slots were added.", appLanguage)
        }
    }

    private func removeImage(at index: Int) {
        guard imageData.indices.contains(index) else {
            return
        }

        imageData.remove(at: index)
        try? ComposerDraftStore.saveImages(imageData)
    }

    private func moveImage(from sourceIndex: Int, to destinationIndex: Int) {
        guard imageData.indices.contains(sourceIndex),
              imageData.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else {
            return
        }

        let item = imageData.remove(at: sourceIndex)
        imageData.insert(item, at: destinationIndex)
        try? ComposerDraftStore.saveImages(imageData)
    }

    private func processVideo(_ item: PhotosPickerItem) async {
        isProcessingVideo = true
        defer {
            isProcessingVideo = false
        }

        do {
            guard let picked = try await item.loadTransferable(type: PickedVideoFile.self) else {
                throw MediaPreparationError.videoExportUnavailable
            }

            videoDraft = try await VideoMediaProcessor.prepareVideo(from: picked.url)
            imageData = []
            try? ComposerDraftStore.saveImages([])
        } catch {
            mediaError = error.localizedDescription
        }
    }

    private func loadPendingShareImportIfNeeded() async {
        let envelope: PendingShareImportEnvelope?
        do {
            envelope = try ShareImportInbox.nextPendingImport()
        } catch ShareImportInboxError.appGroupUnavailable {
            return
        } catch {
            mediaError = error.localizedDescription
            return
        }

        guard let envelope else {
            return
        }

        isImportingShare = true
        defer {
            isImportingShare = false
        }

        do {
            applySharedText(envelope.importRecord.text, createdAt: envelope.importRecord.createdAt)
            try await applySharedAttachments(envelope)
            ComposerDraftStore.save(text: text, occurredAt: occurredAt)
            try ShareImportInbox.delete(envelope)
        } catch {
            mediaError = "Could not import shared item: \(error.localizedDescription)"
        }
    }

    private func applySharedText(_ sharedText: String, createdAt: Date) {
        let trimmedSharedText = sharedText.trimmingCharacters(in: .whitespacesAndNewlines)
        occurredAt = createdAt
        guard !trimmedSharedText.isEmpty else {
            return
        }

        let trimmedCurrentText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = trimmedCurrentText.isEmpty
            ? trimmedSharedText
            : "\(trimmedCurrentText)\n\n\(trimmedSharedText)"
    }

    private func applySharedAttachments(_ envelope: PendingShareImportEnvelope) async throws {
        let attachments = envelope.importRecord.attachments.sorted { $0.sortOrder < $1.sortOrder }
        guard !attachments.isEmpty else {
            return
        }

        if let video = attachments.first(where: { $0.kind == .video }) {
            isProcessingVideo = true
            defer {
                isProcessingVideo = false
            }
            videoDraft = try await VideoMediaProcessor.prepareVideo(from: envelope.fileURL(for: video))
            audioDraft = nil
            imageData = []
            selectedItems = []
            selectedVideoItem = nil
            audioRecorder.discard()
            try? ComposerDraftStore.saveImages([])
            return
        }

        if let audio = attachments.first(where: { $0.kind == .audio }) {
            audioDraft = try await AudioMediaInspector.prepareImportedAudio(from: envelope.fileURL(for: audio))
            videoDraft = nil
            imageData = []
            selectedItems = []
            selectedVideoItem = nil
            try? ComposerDraftStore.saveImages([])
            return
        }

        let importedImages = attachments
            .filter { $0.kind == .image }
            .prefix(ComposerImageDraft.maxImageCount)
            .compactMap { try? Data(contentsOf: envelope.fileURL(for: $0)) }

        guard !importedImages.isEmpty else {
            return
        }

        imageData = importedImages
        videoDraft = nil
        audioDraft = nil
        selectedItems = []
        selectedVideoItem = nil
        audioRecorder.discard()
        try ComposerDraftStore.saveImages(imageData)
    }

    private func toggleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stop()
            guard let url = audioRecorder.recordedURL else {
                return
            }

            Task {
                do {
                    audioDraft = try await AudioMediaInspector.preparedAudio(from: url)
                    imageData = []
                    videoDraft = nil
                    try? ComposerDraftStore.saveImages([])
                } catch {
                    mediaError = error.localizedDescription
                }
            }
            return
        }

        audioDraft = nil
        videoDraft = nil
        imageData = []
        try? ComposerDraftStore.saveImages([])
        audioRecorder.start()
    }

    private func loadRecoverableAudioDraft() async {
        guard imageData.isEmpty, videoDraft == nil, audioDraft == nil else {
            return
        }

        do {
            let directory = try AppDirectories.draftMediaDirectory()
            let audioFiles = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            )
            .filter { $0.lastPathComponent.hasPrefix("composer-audio-") && $0.pathExtension == "m4a" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }

            guard let latest = audioFiles.first else {
                return
            }

            audioDraft = try await AudioMediaInspector.preparedAudio(from: latest)
        } catch {
            return
        }
    }
}

private struct DraftVideoPreview: View {
    @Environment(\.appLanguage) private var appLanguage

    let media: PreparedMomentMedia
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if let thumbnailURL = media.thumbnailURL,
                   let image = UIImage(contentsOfFile: thumbnailURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.secondarySystemBackground)
                    Image(systemName: "video")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.35))
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomLeading) {
                if let duration = media.durationSeconds {
                    Text(mediaDurationLabel(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.48), in: Capsule())
                        .padding(8)
                }
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.62))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel(L10n.t("Remove video", appLanguage))
        }
    }
}

private struct DraftAudioPreview: View {
    @Environment(\.appLanguage) private var appLanguage

    let media: PreparedMomentMedia
    let onRemove: () -> Void

    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t(isPlaying ? "Pause audio" : "Play audio", appLanguage))

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("Audio", appLanguage))
                    .font(.subheadline.weight(.semibold))
                Text(mediaDurationLabel(media.durationSeconds ?? 0))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.secondary, .quaternary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Remove audio", appLanguage))
        }
        .padding(.vertical, 8)
    }

    private func togglePlayback() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }

        if player == nil {
            player = AVPlayer(url: media.fileURL)
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
        isPlaying = true
    }
}

func mediaDurationLabel(_ seconds: TimeInterval) -> String {
    let totalSeconds = max(0, Int(seconds.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let remainingSeconds = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    return String(format: "%d:%02d", minutes, remainingSeconds)
}

struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    let onCapture: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (Data) -> Void

        init(onCapture: @escaping (Data) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.9) {
                onCapture(data)
            }

            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
