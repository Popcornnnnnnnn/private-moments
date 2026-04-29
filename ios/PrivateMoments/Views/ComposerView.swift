import PhotosUI
import SwiftUI
import UIKit

struct ComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TimelineStore

    @State private var text = ComposerDraftStore.loadText()
    @State private var occurredAt = ComposerDraftStore.loadOccurredAt()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var imageData: [Data] = ComposerDraftStore.loadImages()
    @State private var showingCamera = false
    @State private var isPublishing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PlainTextListEditor(text: $text)
                        .frame(minHeight: 140)

                    DatePicker("Date", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                }

                Section {
                    PhotosPicker(selection: $selectedItems, maxSelectionCount: 9, matching: .images) {
                        Label("Add from Library", systemImage: "photo.on.rectangle.angled")
                    }

                    Button {
                        showingCamera = true
                    } label: {
                        Label("Use Camera", systemImage: "camera")
                    }
                    .disabled(!CameraPicker.isAvailable)

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
            .sheet(isPresented: $showingCamera) {
                CameraPicker { data in
                    imageData = Array((imageData + [data]).prefix(9))
                    try? ComposerDraftStore.saveImages(imageData)
                }
            }
        }
    }

    private var canPublish: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imageData.isEmpty
    }

    private func publish() {
        guard canPublish, !isPublishing else {
            return
        }

        isPublishing = true
        Task {
            let didCreate = await store.createPost(text: text, imageData: imageData, occurredAt: occurredAt)
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
