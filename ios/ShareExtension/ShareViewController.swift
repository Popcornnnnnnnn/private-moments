import Foundation
import Social
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
    private let videoTypeIdentifiers = [
        UTType.movie.identifier,
        UTType.video.identifier,
        "com.apple.quicktime-movie",
        "public.mpeg-4"
    ]
    private let audioTypeIdentifiers = [
        UTType.audio.identifier,
        "public.mpeg-4-audio",
        "com.apple.m4a-audio",
        "public.mp3",
        "com.microsoft.waveform-audio"
    ]
    private let imageTypeIdentifiers = [
        UTType.image.identifier
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Save to Moments"
        placeholder = "Add a note..."
    }

    override func isContentValid() -> Bool {
        true
    }

    override func didSelectPost() {
        Task {
            do {
                let importID = try await savePendingImport()
                await finish(importID: importID)
            } catch {
                await cancel(with: error)
            }
        }
    }

    override func configurationItems() -> [Any]! {
        []
    }

    private func savePendingImport() async throws -> String {
        let importID = UUID().uuidString
        let importDirectory = try ShareImportInbox.newImportDirectory(id: importID)
        let filesDirectory = try ShareImportInbox.filesDirectory(for: importDirectory)
        let providers = inputItemProviders

        var textParts = [String]()
        let note = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            textParts.append(note)
        }
        textParts.append(contentsOf: await loadTextPayloads(from: providers))

        let attachments = try await loadMediaAttachments(from: providers, into: filesDirectory)
        let importRecord = PendingShareImport(
            id: importID,
            text: textParts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n"),
            attachments: attachments
        )

        guard !importRecord.text.isEmpty || !importRecord.attachments.isEmpty else {
            throw ShareImportInboxError.importNotFound
        }

        try ShareImportInbox.write(importRecord, to: importDirectory)
        return importID
    }

    private var inputItemProviders: [NSItemProvider] {
        (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
    }

    private func loadTextPayloads(from providers: [NSItemProvider]) async -> [String] {
        var values = [String]()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let value = try? await loadTextItem(from: provider, typeIdentifier: UTType.url.identifier),
               !values.contains(value) {
                values.append(value)
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let value = try? await loadTextItem(from: provider, typeIdentifier: UTType.plainText.identifier),
               !values.contains(value) {
                values.append(value)
            }
        }

        return values
    }

    private func loadMediaAttachments(
        from providers: [NSItemProvider],
        into filesDirectory: URL
    ) async throws -> [PendingShareAttachment] {
        if let videoProvider = providers.first(where: { firstSupportedType(in: videoTypeIdentifiers, provider: $0) != nil }),
           let typeIdentifier = firstSupportedType(in: videoTypeIdentifiers, provider: videoProvider) {
            return [
                try await copyFileAttachment(
                    from: videoProvider,
                    typeIdentifier: typeIdentifier,
                    kind: .video,
                    fallbackExtension: "mp4",
                    sortOrder: 0,
                    filesDirectory: filesDirectory
                )
            ]
        }

        if let audioProvider = providers.first(where: { firstSupportedType(in: audioTypeIdentifiers, provider: $0) != nil }),
           let typeIdentifier = firstSupportedType(in: audioTypeIdentifiers, provider: audioProvider) {
            return [
                try await copyFileAttachment(
                    from: audioProvider,
                    typeIdentifier: typeIdentifier,
                    kind: .audio,
                    fallbackExtension: "m4a",
                    sortOrder: 0,
                    filesDirectory: filesDirectory
                )
            ]
        }

        let imageProviders = providers.filter { firstSupportedType(in: imageTypeIdentifiers, provider: $0) != nil }
        var attachments = [PendingShareAttachment]()
        for (index, provider) in imageProviders.prefix(9).enumerated() {
            let typeIdentifier = firstSupportedType(in: imageTypeIdentifiers, provider: provider) ?? UTType.image.identifier
            do {
                attachments.append(
                    try await copyFileAttachment(
                        from: provider,
                        typeIdentifier: typeIdentifier,
                        kind: .image,
                        fallbackExtension: "jpg",
                        sortOrder: index,
                        filesDirectory: filesDirectory
                    )
                )
            } catch {
                attachments.append(
                    try await copyImageDataAttachment(
                        from: provider,
                        typeIdentifier: typeIdentifier,
                        sortOrder: index,
                        filesDirectory: filesDirectory
                    )
                )
            }
        }

        return attachments
    }

    private func firstSupportedType(in typeIdentifiers: [String], provider: NSItemProvider) -> String? {
        typeIdentifiers.first { provider.hasItemConformingToTypeIdentifier($0) }
    }

    private func loadTextItem(from provider: NSItemProvider, typeIdentifier: String) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else if let url = item as? NSURL {
                    continuation.resume(returning: url.absoluteString)
                } else if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let data = item as? Data,
                          let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func copyFileAttachment(
        from provider: NSItemProvider,
        typeIdentifier: String,
        kind: PendingShareAttachment.Kind,
        fallbackExtension: String,
        sortOrder: Int,
        filesDirectory: URL
    ) async throws -> PendingShareAttachment {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { sourceURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sourceURL else {
                    continuation.resume(throwing: ShareImportInboxError.importNotFound)
                    return
                }

                do {
                    let fileExtension = sourceURL.pathExtension.isEmpty ? fallbackExtension : sourceURL.pathExtension
                    let filename = "\(UUID().uuidString).\(fileExtension)"
                    let destinationURL = filesDirectory.appending(path: filename)
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    continuation.resume(
                        returning: PendingShareAttachment(
                            kind: kind,
                            filename: filename,
                            typeIdentifier: typeIdentifier,
                            suggestedName: sourceURL.lastPathComponent,
                            sortOrder: sortOrder
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func copyImageDataAttachment(
        from provider: NSItemProvider,
        typeIdentifier: String,
        sortOrder: Int,
        filesDirectory: URL
    ) async throws -> PendingShareAttachment {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data else {
                    continuation.resume(throwing: ShareImportInboxError.importNotFound)
                    return
                }

                do {
                    let filename = "\(UUID().uuidString).image"
                    let destinationURL = filesDirectory.appending(path: filename)
                    try data.write(to: destinationURL, options: [.atomic])
                    continuation.resume(
                        returning: PendingShareAttachment(
                            kind: .image,
                            filename: filename,
                            typeIdentifier: typeIdentifier,
                            suggestedName: nil,
                            sortOrder: sortOrder
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @MainActor
    private func finish(importID: String) {
        let openURL = URL(string: "\(ShareImportConstants.urlScheme)://import/\(importID)")
        if let openURL {
            extensionContext?.open(openURL) { [weak self] _ in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        } else {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    @MainActor
    private func cancel(with error: Error) {
        extensionContext?.cancelRequest(withError: error)
    }
}
