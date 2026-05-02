import Foundation
import SwiftUI
import UIKit

struct PlainTextListEditor: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.text = text
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        textView.textContainer.lineFragmentPadding = 0
        textView.dataDetectorTypes = []
        textView.smartInsertDeleteType = .default
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.text = $text

        if uiView.text != text {
            uiView.text = text
        }

        uiView.font = .preferredFont(forTextStyle: .body)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard replacement == "\n" else {
                return true
            }

            guard let edit = PlainTextListContinuation.replacement(
                in: textView.text ?? "",
                selectedRange: range,
                replacementText: replacement
            ) else {
                return true
            }

            guard let currentText = textView.text,
                  let stringRange = Range(edit.replacementRange, in: currentText) else {
                return true
            }

            let updatedText = currentText.replacingCharacters(in: stringRange, with: edit.replacementText)
            textView.text = updatedText
            text.wrappedValue = updatedText
            textView.selectedRange = edit.selectedRange
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text ?? ""
        }
    }
}

struct PlainTextListContinuation {
    struct Edit: Equatable {
        let replacementRange: NSRange
        let replacementText: String
        let selectedRange: NSRange
    }

    static func replacement(
        in text: String,
        selectedRange: NSRange,
        replacementText: String
    ) -> Edit? {
        guard replacementText == "\n",
              selectedRange.length >= 0,
              isValid(range: selectedRange, in: text) else {
            return nil
        }

        let nsText = text as NSString
        let cursorLocation = selectedRange.location
        let currentLineRange = nsText.lineRange(for: NSRange(location: cursorLocation, length: 0))
        let lineEnd = min(cursorLocation, currentLineRange.location + currentLineRange.length)
        let linePrefixRange = NSRange(location: currentLineRange.location, length: lineEnd - currentLineRange.location)
        let linePrefix = nsText.substring(with: linePrefixRange)

        guard let marker = ListMarker(linePrefix: linePrefix) else {
            return nil
        }

        if marker.hasEmptyItemText {
            let replacementRange = NSRange(
                location: currentLineRange.location,
                length: linePrefixRange.length + selectedRange.length
            )
            let selectedLocation = currentLineRange.location + 1
            return Edit(
                replacementRange: replacementRange,
                replacementText: "\n",
                selectedRange: NSRange(location: selectedLocation, length: 0)
            )
        }

        guard let nextPrefix = marker.nextPrefix else {
            return nil
        }

        let customReplacement = "\n" + nextPrefix
        let selectedLocation = selectedRange.location + customReplacement.utf16.count
        return Edit(
            replacementRange: selectedRange,
            replacementText: customReplacement,
            selectedRange: NSRange(location: selectedLocation, length: 0)
        )
    }

    private static func isValid(range: NSRange, in text: String) -> Bool {
        guard range.location >= 0,
              range.length >= 0,
              range.location <= text.utf16.count,
              range.location + range.length <= text.utf16.count else {
            return false
        }

        return Range(range, in: text) != nil
    }
}

private struct ListMarker {
    let nextPrefix: String?
    let hasEmptyItemText: Bool

    init?(linePrefix: String) {
        if linePrefix.hasPrefix("- ") {
            self.nextPrefix = "- "
            self.hasEmptyItemText = Self.isEmptyItemText(linePrefix.dropFirst(2))
            return
        }

        if linePrefix.hasPrefix("• ") {
            self.nextPrefix = "• "
            self.hasEmptyItemText = Self.isEmptyItemText(linePrefix.dropFirst(2))
            return
        }

        guard let numbered = Self.numberedPrefix(in: linePrefix) else {
            return nil
        }

        self.nextPrefix = numbered.nextPrefix
        self.hasEmptyItemText = Self.isEmptyItemText(linePrefix.dropFirst(numbered.prefixLength))
    }

    private static func isEmptyItemText(_ text: Substring) -> Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func numberedPrefix(in linePrefix: String) -> (prefixLength: Int, nextPrefix: String?)? {
        var digits = ""
        var cursor = linePrefix.startIndex

        while cursor < linePrefix.endIndex, linePrefix[cursor].isNumber {
            digits.append(linePrefix[cursor])
            cursor = linePrefix.index(after: cursor)
        }

        guard !digits.isEmpty,
              cursor < linePrefix.endIndex,
              linePrefix[cursor] == "." else {
            return nil
        }

        cursor = linePrefix.index(after: cursor)

        guard cursor < linePrefix.endIndex,
              linePrefix[cursor] == " " else {
            return nil
        }

        let prefixLength = linePrefix.distance(from: linePrefix.startIndex, to: linePrefix.index(after: cursor))
        guard let number = Int(digits), number < Int.max else {
            return (prefixLength, nil)
        }

        return (prefixLength, "\(number + 1). ")
    }
}
