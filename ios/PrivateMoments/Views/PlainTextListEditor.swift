import Foundation

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
