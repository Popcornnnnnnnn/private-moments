import Foundation

enum MomentTextMarkdown {
    static let aiTitleMaxCharacters = 40

    enum LineKind: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case blank
    }

    struct Line: Equatable {
        let kind: LineKind
    }

    enum LineStyle: Equatable {
        case heading(level: Int)
    }

    struct TextEdit: Equatable {
        let replacementRange: NSRange
        let replacementText: String
        let selectedRange: NSRange
    }

    static func parse(_ text: String) -> [Line] {
        text.components(separatedBy: .newlines).map { rawLine in
            if let heading = heading(in: rawLine) {
                return Line(kind: .heading(level: heading.level, text: heading.text))
            }

            if rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return Line(kind: .blank)
            }

            return Line(kind: .paragraph(rawLine))
        }
    }

    static func hasLeadingTitle(_ text: String) -> Bool {
        for rawLine in text.components(separatedBy: .newlines) {
            if rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            return heading(in: rawLine) != nil
        }

        return false
    }

    static func searchableText(_ text: String) -> String {
        parse(text)
            .map { line in
                switch line.kind {
                case .heading(_, let text):
                    return text
                case .paragraph(let text):
                    return text
                case .blank:
                    return ""
                }
            }
            .joined(separator: "\n")
    }

    static func normalizedAITitle(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let withoutMarkdownMarker = value.replacingOccurrences(
            of: #"^\s*#{1,6}\s*"#,
            with: "",
            options: .regularExpression
        )
        let normalized = withoutMarkdownMarker
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !normalized.isEmpty,
              normalized.count <= aiTitleMaxCharacters else {
            return nil
        }

        return normalized
    }

    static func insertingAITitle(_ title: String, into text: String) -> String {
        let heading = "## \(title)"
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return heading
        }

        return "\(heading)\n\n\(text)"
    }

    static func togglingLineStyle(
        _ style: LineStyle,
        in text: String,
        selectedRange: NSRange
    ) -> TextEdit? {
        guard selectedRange.length >= 0,
              isValid(range: selectedRange, in: text),
              let line = currentLine(in: text, selectedRange: selectedRange) else {
            return nil
        }

        let currentLine = line.text
        let selectedOffset = max(0, selectedRange.location - line.contentRange.location)

        switch style {
        case .heading(let level):
            return headingToggleEdit(
                level: level,
                currentLine: currentLine,
                lineRange: line.contentRange,
                selectedOffset: selectedOffset
            )
        }
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let prefix: String
        let level: Int

        if line.hasPrefix("## ") {
            prefix = "## "
            level = 2
        } else if line.hasPrefix("# ") {
            prefix = "# "
            level = 1
        } else {
            return nil
        }

        let text = String(line.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            return nil
        }

        return (level, text)
    }

    private static func headingMarker(in line: String) -> (level: Int, length: Int)? {
        if line.hasPrefix("## ") {
            return (2, 3)
        }

        if line.hasPrefix("# ") {
            return (1, 2)
        }

        return nil
    }

    private static func currentLine(
        in text: String,
        selectedRange: NSRange
    ) -> (contentRange: NSRange, text: String)? {
        let nsText = text as NSString
        let safeLocation = min(selectedRange.location, text.utf16.count)
        let rawLineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
        var contentLength = rawLineRange.length

        if contentLength > 0 {
            let rawLine = nsText.substring(with: rawLineRange)
            if rawLine.hasSuffix("\r\n") {
                contentLength -= 2
            } else if rawLine.hasSuffix("\n") || rawLine.hasSuffix("\r") {
                contentLength -= 1
            }
        }

        let contentRange = NSRange(location: rawLineRange.location, length: max(0, contentLength))
        return (contentRange, nsText.substring(with: contentRange))
    }

    private static func headingToggleEdit(
        level: Int,
        currentLine: String,
        lineRange: NSRange,
        selectedOffset: Int
    ) -> TextEdit {
        let nextPrefix = String(repeating: "#", count: level) + " "

        if let currentHeading = headingMarker(in: currentLine),
           currentHeading.level == level {
            let nextLine = String(currentLine.dropFirst(currentHeading.length))
            let nextOffset = adjustedOffsetAfterRemovingPrefix(
                selectedOffset,
                prefixLength: currentHeading.length
            )
            return TextEdit(
                replacementRange: lineRange,
                replacementText: nextLine,
                selectedRange: NSRange(location: lineRange.location + nextOffset, length: 0)
            )
        }

        let oldPrefixLength = headingMarker(in: currentLine)?.length ?? 0
        let baseLine = String(currentLine.dropFirst(oldPrefixLength))
        let nextLine = nextPrefix + baseLine
        let nextOffset = adjustedOffsetAfterReplacingPrefix(
            selectedOffset,
            oldPrefixLength: oldPrefixLength,
            newPrefixLength: nextPrefix.utf16.count
        )

        return TextEdit(
            replacementRange: lineRange,
            replacementText: nextLine,
            selectedRange: NSRange(location: lineRange.location + nextOffset, length: 0)
        )
    }

    private static func adjustedOffsetAfterRemovingPrefix(_ offset: Int, prefixLength: Int) -> Int {
        guard offset >= prefixLength else {
            return 0
        }

        return offset - prefixLength
    }

    private static func adjustedOffsetAfterReplacingPrefix(
        _ offset: Int,
        oldPrefixLength: Int,
        newPrefixLength: Int
    ) -> Int {
        guard offset >= oldPrefixLength else {
            return newPrefixLength
        }

        return newPrefixLength + offset - oldPrefixLength
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
