import Foundation

struct MomentCommentDraftPolicy: Equatable {
    let rawText: String

    init(rawText: String) {
        self.rawText = rawText
    }

    var trimmedText: String {
        rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool {
        !trimmedText.isEmpty
    }

    func submissionText() -> String? {
        let text = trimmedText
        return text.isEmpty ? nil : text
    }
}
