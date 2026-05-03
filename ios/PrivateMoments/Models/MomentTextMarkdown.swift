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
}
