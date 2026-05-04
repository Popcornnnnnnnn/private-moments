import Foundation

enum ComposerImageDraft {
    static let maxImageCount = 9

    struct AppendResult: Equatable {
        let images: [Data]
        let appendedCount: Int
        let discardedCount: Int

        var didAppend: Bool {
            appendedCount > 0
        }

        var didDiscard: Bool {
            discardedCount > 0
        }
    }

    static func appending(_ incomingImages: [Data], to existingImages: [Data]) -> AppendResult {
        let existing = Array(existingImages.prefix(maxImageCount))
        let availableSlots = max(0, maxImageCount - existing.count)
        let accepted = Array(incomingImages.prefix(availableSlots))
        let discardedCount = max(0, incomingImages.count - accepted.count)

        return AppendResult(
            images: existing + accepted,
            appendedCount: accepted.count,
            discardedCount: discardedCount
        )
    }
}
