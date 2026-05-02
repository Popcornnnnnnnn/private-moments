import PhotosUI
import SwiftUI
import UIKit
import AVFoundation

struct ComposerView: View {
    @Environment(\.dismiss) private var dismiss
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
    @State private var mediaError: String?
    @StateObject private var audioRecorder = AudioRecorderController()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PlainTextListEditor(text: $text)
                        .frame(minHeight: 140)

                    DatePicker("Date", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                }

                Section {
                    mediaControls
                    mediaPreview
                }
            }
            .navigationTitle("New Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
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
                            Text("Publish")
                        }
                    }
                    .disabled(!canPublish || isPublishing)
                    .accessibilityLabel(isPublishing ? "Publishing" : "Publish")
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
                    imageData = Array((imageData + [data]).prefix(9))
                    try? ComposerDraftStore.saveImages(imageData)
                }
            }
            .task {
                await loadRecoverableAudioDraft()
            }
            .alert("Media unavailable", isPresented: mediaErrorBinding) {
                Button("OK", role: .cancel) {}
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
        PhotosPicker(selection: $selectedItems, maxSelectionCount: 9, matching: .images) {
            Label("Add Photos", systemImage: "photo.on.rectangle.angled")
        }
        .disabled(hasNonImageMedia)

        Button {
            showingCamera = true
        } label: {
            Label("Use Camera", systemImage: "camera")
        }
        .disabled(!CameraPicker.isAvailable || hasNonImageMedia)

        PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
            Label("Add Video", systemImage: "video")
        }
        .disabled(hasAnyMedia || isProcessingVideo)

        Button {
            toggleRecording()
        } label: {
            Label(audioRecorder.isRecording ? "Stop Recording" : "Record Audio", systemImage: audioRecorder.isRecording ? "stop.circle" : "mic")
        }
        .disabled((hasAnyMedia && !audioRecorder.isRecording) || isProcessingVideo)
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if isProcessingVideo {
            HStack(spacing: 10) {
                ProgressView()
                Text("Processing video")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }

        if audioRecorder.isRecording {
            HStack {
                Label(
                    audioRecorder.isPaused ? "Recording paused" : "Recording",
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
                            .accessibilityLabel("Remove image")
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
                occurredAt: occurredAt
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

        for item in items.prefix(9) {
            if let data = try? await item.loadTransferable(type: Data.self) {
                result.append(data)
            }
        }

        return result
    }

    private func removeImage(at index: Int) {
        guard imageData.indices.contains(index) else {
            return
        }

        imageData.remove(at: index)
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
            .accessibilityLabel("Remove video")
        }
    }
}

private struct DraftAudioPreview: View {
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
            .accessibilityLabel(isPlaying ? "Pause audio" : "Play audio")

            VStack(alignment: .leading, spacing: 3) {
                Text("Audio")
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
            .accessibilityLabel("Remove audio")
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
