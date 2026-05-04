import Foundation

enum TimelineSearchMatchSource: String, CaseIterable, Identifiable, Hashable {
    case text
    case comments
    case summary
    case transcript
    case tags

    var id: String {
        rawValue
    }

    func title(language: AppResolvedLanguage = .english) -> String {
        switch self {
        case .text:
            return L10n.t("Text", language)
        case .comments:
            return L10n.t("Comments", language)
        case .summary:
            return L10n.t("Summary", language)
        case .transcript:
            return L10n.t("Transcript", language)
        case .tags:
            return L10n.t("Tags", language)
        }
    }

    func badgeTitle(language: AppResolvedLanguage = .english) -> String {
        switch self {
        case .text:
            return L10n.t("Matched text", language)
        case .comments:
            return L10n.t("Matched comment", language)
        case .summary:
            return L10n.t("Matched summary", language)
        case .transcript:
            return L10n.t("Matched transcript", language)
        case .tags:
            return L10n.t("Matched tag", language)
        }
    }

    var systemImage: String {
        switch self {
        case .text:
            return "text.alignleft"
        case .comments:
            return "text.bubble"
        case .summary:
            return "sparkles"
        case .transcript:
            return "waveform"
        case .tags:
            return "tag"
        }
    }
}

struct TimelineSearchResult: Equatable {
    var sources: Set<TimelineSearchMatchSource>

    var isMatch: Bool {
        !sources.isEmpty
    }

    func includes(_ source: TimelineSearchMatchSource) -> Bool {
        sources.contains(source)
    }
}

enum TimelineSearch {
    static func result(
        for item: TimelineItem,
        query: String,
        aliasesByTagId: [String: [TimelineTagAlias]] = [:]
    ) -> TimelineSearchResult {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return TimelineSearchResult(sources: [])
        }

        var sources = Set<TimelineSearchMatchSource>()
        if textMatches(MomentTextMarkdown.searchableText(item.post.text), query: trimmedQuery) {
            sources.insert(.text)
        }

        if item.comments.contains(where: { textMatches($0.text, query: trimmedQuery) }) {
            sources.insert(.comments)
        }

        if textMatches(summaryText(for: item.aiSummaries), query: trimmedQuery) {
            sources.insert(.summary)
        }

        if item.media.contains(where: { media in
            guard let transcriptionText = media.transcriptionText else {
                return false
            }

            return textMatches(transcriptionText, query: trimmedQuery)
        }) {
            sources.insert(.transcript)
        }

        if item.tags.contains(where: { assignedTag in
            L10n.defaultPrimaryTagSearchNames(for: assignedTag.tag).contains { name in
                textMatches(name, query: trimmedQuery)
            }
                || (aliasesByTagId[assignedTag.tagId] ?? []).contains(where: { alias in
                    alias.deletedAt == nil && textMatches(alias.alias, query: trimmedQuery)
                })
        }) {
            sources.insert(.tags)
        }

        return TimelineSearchResult(sources: sources)
    }

    static func matches(_ item: TimelineItem, query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || result(for: item, query: query).isMatch
    }

    static func textMatches(_ text: String, query: String) -> Bool {
        let queryTokens = tokens(in: query)
        guard !queryTokens.isEmpty else {
            return true
        }

        let haystack = normalizedCompact(text)
        let haystackTokens = tokens(in: text)
        return queryTokens.allSatisfy { token in
            let normalizedToken = normalizedCompact(token)
            guard !normalizedToken.isEmpty else {
                return true
            }

            if haystack.contains(normalizedToken) {
                return true
            }

            guard isASCIILetters(normalizedToken), normalizedToken.count >= 4 else {
                return false
            }

            let maxDistance = normalizedToken.count >= 7 ? 2 : 1
            return haystackTokens.contains { candidate in
                let normalizedCandidate = normalizedCompact(candidate)
                guard isASCIILetters(normalizedCandidate) else {
                    return false
                }

                return levenshteinDistance(normalizedToken, normalizedCandidate, maxDistance: maxDistance) <= maxDistance
            }
        }
    }

    private static func summaryText(for summaries: [TimelineAISummary]) -> String {
        summaries
            .filter { $0.deletedAt == nil }
            .flatMap(summaryParts)
            .joined(separator: "\n")
    }

    private static func summaryParts(_ summary: TimelineAISummary) -> [String] {
        var parts = [String]()
        append(summary.documentTitle, to: &parts)
        append(summary.oneLiner, to: &parts)
        append(summary.overview, to: &parts)
        append(summary.summaryText, to: &parts)
        parts.append(contentsOf: summary.keyPoints)

        for section in summary.sections {
            append(section.heading, to: &parts)
            parts.append(contentsOf: section.bullets)
        }

        for block in summary.documentBlocks {
            append(block.text, to: &parts)
            parts.append(contentsOf: block.items)
        }

        return parts
    }

    private static func append(_ value: String?, to parts: inout [String]) {
        guard let value else {
            return
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(trimmed)
        }
    }

    private static func tokens(in value: String) -> [String] {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        var tokens = [String]()
        var current = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || isCJK(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    private static func normalizedCompact(_ value: String) -> String {
        tokens(in: value).joined()
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(Int(scalar.value))
            || (0x3400...0x4DBF).contains(Int(scalar.value))
            || (0x3040...0x30FF).contains(Int(scalar.value))
            || (0xAC00...0xD7AF).contains(Int(scalar.value))
    }

    private static func isASCIILetters(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.lowercaseLetters.contains(scalar) && scalar.value < 128
        }
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String, maxDistance: Int) -> Int {
        if abs(lhs.count - rhs.count) > maxDistance {
            return maxDistance + 1
        }

        let lhs = Array(lhs)
        let rhs = Array(rhs)
        var previous = Array(0...rhs.count)
        var current = Array(repeating: 0, count: rhs.count + 1)

        for lhsIndex in 1...lhs.count {
            current[0] = lhsIndex
            var rowMinimum = current[0]

            for rhsIndex in 1...rhs.count {
                let substitutionCost = lhs[lhsIndex - 1] == rhs[rhsIndex - 1] ? 0 : 1
                current[rhsIndex] = min(
                    previous[rhsIndex] + 1,
                    current[rhsIndex - 1] + 1,
                    previous[rhsIndex - 1] + substitutionCost
                )
                rowMinimum = min(rowMinimum, current[rhsIndex])
            }

            if rowMinimum > maxDistance {
                return maxDistance + 1
            }

            swap(&previous, &current)
        }

        return previous[rhs.count]
    }
}
