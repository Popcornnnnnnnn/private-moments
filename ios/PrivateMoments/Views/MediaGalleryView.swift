import Photos
import SwiftUI
import UIKit

struct MediaGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage

    let media: [TimelineMedia]
    @State private var selection: Int
    @State private var chromeVisible = true
    @State private var isSaving = false
    @State private var saveMessage: String?

    init(media: [TimelineMedia], initialIndex: Int) {
        self.media = media
        _selection = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(Array(media.enumerated()), id: \.element.id) { index, item in
                    ZoomableLocalImage(
                        path: item.localCompressedPath,
                        resetToken: selection,
                        onSingleTap: toggleChrome
                    )
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if chromeVisible {
                galleryChrome
                    .transition(.opacity)
            }

            if let saveMessage {
                Text(saveMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.62), in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 88)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: chromeVisible)
        .animation(.easeInOut(duration: 0.18), value: saveMessage)
    }

    private var galleryChrome: some View {
        VStack(spacing: 0) {
            HStack {
                Text(counterText)
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(.black.opacity(0.45), in: Capsule())

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .accessibilityLabel(L10n.t("Close", appLanguage))
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            Spacer()

            VStack(spacing: 14) {
                GalleryPageDots(count: media.count, selection: selection)

                HStack(spacing: 12) {
                    if let currentFileURL {
                        ShareLink(item: currentFileURL) {
                            galleryActionLabel(L10n.t("Share", appLanguage), systemImage: "square.and.arrow.up")
                        }
                        .accessibilityLabel(L10n.t("Share image", appLanguage))
                    } else {
                        galleryActionLabel(L10n.t("Share", appLanguage), systemImage: "square.and.arrow.up")
                            .opacity(0.45)
                    }

                    Button {
                        saveCurrentImage()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 88, height: 44)
                                .background(.black.opacity(0.45), in: Capsule())
                        } else {
                            galleryActionLabel(L10n.t("Save", appLanguage), systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(isSaving || currentFileURL == nil)
                    .accessibilityLabel(L10n.t("Save image to Photos", appLanguage))
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }

    private var currentMedia: TimelineMedia? {
        guard media.indices.contains(selection) else {
            return nil
        }

        return media[selection]
    }

    private var currentFileURL: URL? {
        guard let currentMedia,
              FileManager.default.fileExists(atPath: currentMedia.localCompressedPath) else {
            return nil
        }

        return URL(fileURLWithPath: currentMedia.localCompressedPath)
    }

    private var counterText: String {
        media.count > 1 ? "\(selection + 1) \(L10n.t("of", appLanguage)) \(media.count)" : "1 \(L10n.t("image", appLanguage))"
    }

    private func galleryActionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(minWidth: 88, minHeight: 44)
            .padding(.horizontal, 4)
            .background(.black.opacity(0.45), in: Capsule())
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.18)) {
            chromeVisible.toggle()
        }
    }

    private func saveCurrentImage() {
        guard let currentMedia,
              let image = UIImage(contentsOfFile: currentMedia.localCompressedPath) else {
            showSaveMessage(L10n.t("Image unavailable", appLanguage))
            return
        }

        isSaving = true
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    isSaving = false
                    showSaveMessage(L10n.t("Photo access denied", appLanguage))
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                Task { @MainActor in
                    isSaving = false
                    showSaveMessage(success ? L10n.t("Saved to Photos", appLanguage) : error?.localizedDescription ?? L10n.t("Save failed", appLanguage))
                }
            }
        }
    }

    private func showSaveMessage(_ message: String) {
        saveMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.7))
            if saveMessage == message {
                saveMessage = nil
            }
        }
    }
}

private struct GalleryPageDots: View {
    let count: Int
    let selection: Int

    var body: some View {
        if count > 1 {
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(index == selection ? Color.white : Color.white.opacity(0.35))
                        .frame(width: index == selection ? 18 : 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(.black.opacity(0.32), in: Capsule())
        }
    }
}
