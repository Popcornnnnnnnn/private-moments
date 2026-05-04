import SwiftUI
import UIKit

struct AISummarySheet: View {
    let media: TimelineMedia
    let summary: TimelineAISummary?
    let onRegenerate: () async -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    @State private var isDeleteAlertPresented = false
    @State private var didCopy = false
    @State private var isRegenerateRequestInFlight = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let displaySummary {
                        if isGenerationActive {
                            generationStatusBanner()
                        }
                        if isFailed {
                            failureStatusBanner()
                        }
                        readySummaryContent(displaySummary)
                    } else if isGenerationActive {
                        generationProgressContent()
                    } else if isFailed {
                        failureContent()
                    } else {
                        ContentUnavailableView(L10n.t("Summary unavailable", appLanguage), systemImage: "sparkles")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle(L10n.t("Summary", appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.t("Close", appLanguage))
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        copyContent()
                    } label: {
                        Label(L10n.t(didCopy ? "Copied" : "Copy", appLanguage), systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(copyText == nil)

                    Spacer()

                    if canRegenerate {
                        Button {
                            startRegeneration()
                        } label: {
                            regenerateButtonLabel
                        }
                        .disabled(isGenerationActive)

                        Button(role: .destructive) {
                            isDeleteAlertPresented = true
                        } label: {
                            Label(L10n.t("Delete", appLanguage), systemImage: "trash")
                        }
                        .disabled(isGenerationActive)
                    }
                }
            }
            .alert(L10n.t("Delete summary?", appLanguage), isPresented: $isDeleteAlertPresented) {
                Button(L10n.t("Cancel", appLanguage), role: .cancel) {}
                Button(L10n.t("Delete", appLanguage), role: .destructive) {
                    onDelete()
                }
            } message: {
                Text(L10n.t("This removes only the generated AI summary.", appLanguage))
            }
            .onChange(of: copyText) { _, _ in
                didCopy = false
            }
            .onChange(of: summary?.id) { _, _ in
                isRegenerateRequestInFlight = false
            }
            .onChange(of: summary?.status) { _, newStatus in
                if newStatus != "transcribing" && newStatus != "summarizing" {
                    isRegenerateRequestInFlight = false
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var regenerateButtonLabel: some View {
        Label {
            Text(L10n.t(isGenerationActive ? "Regenerating" : "Regenerate", appLanguage))
        } icon: {
            if isGenerationActive {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
    }

    private func generationStatusBanner() -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(generationStatusTitle)
                    .font(.subheadline.weight(.semibold))
                Text(generationStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func generationProgressContent() -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(generationStatusTitle)
                .font(.headline)
            Text(generationStatusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func failureStatusBanner() -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("Summary update failed", appLanguage))
                    .font(.subheadline.weight(.semibold))
                Text(failureMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func failureContent() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.orange)
            Text(L10n.t("Summary failed", appLanguage))
                .font(.headline)
            Text(failureMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func startRegeneration() {
        guard !isGenerationActive else {
            return
        }

        isRegenerateRequestInFlight = true
        didCopy = false

        Task {
            await onRegenerate()
            await MainActor.run {
                isRegenerateRequestInFlight = false
            }
        }
    }

    @ViewBuilder
    private func readySummaryContent(_ summary: TimelineAISummary) -> some View {
        if hasDocumentContent(summary) {
            documentSummaryContent(summary)
        } else {
            legacySummaryContent(summary)
        }
    }

    @ViewBuilder
    private func documentSummaryContent(_ summary: TimelineAISummary) -> some View {
        if let title = cleaned(summary.documentTitle) {
            Text(title)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
        }

        if let oneLiner = cleaned(summary.oneLiner ?? summary.overview) {
            Text(oneLiner)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.vertical, 2)
        }

        let groups = documentGroups(from: summary.documentBlocks)
        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
            documentGroup(group)
        }
    }

    @ViewBuilder
    private func legacySummaryContent(_ summary: TimelineAISummary) -> some View {
        if let overview = cleaned(summary.overview) {
            Text(overview)
                .font(.body)
                .textSelection(.enabled)
        }

        if !summary.keyPoints.isEmpty {
            summaryBlock(title: L10n.t("Key Points", appLanguage)) {
                bulletList(summary.keyPoints)
            }
        }

        ForEach(summary.sections, id: \.heading) { section in
            summaryBlock(title: section.heading) {
                bulletList(section.bullets)
            }
        }

        if cleaned(summary.overview) == nil,
           summary.keyPoints.isEmpty,
           summary.sections.isEmpty {
            if let summaryText = cleaned(summary.summaryText) {
                Text(summaryText)
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                ContentUnavailableView(L10n.t("Summary unavailable", appLanguage), systemImage: "sparkles")
            }
        }
    }

    @ViewBuilder
    private func documentGroup(_ group: SummaryDocumentGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let heading = group.heading {
                Text(heading)
                    .font(group.level == 2 ? .subheadline.weight(.semibold) : .headline)
                    .textSelection(.enabled)
            }

            if !group.blocks.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(group.blocks.enumerated()), id: \.offset) { _, block in
                            documentBlock(block)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text(L10n.t("Details", appLanguage))
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(.leading, group.level == 2 ? 12 : 0)
    }

    @ViewBuilder
    private func documentBlock(_ block: TimelineAISummaryBlock) -> some View {
        switch block.kind {
        case "paragraph":
            if let text = cleaned(block.text) {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
            }
        case "bullets":
            if let title = cleaned(block.text) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .textSelection(.enabled)
            }
            bulletList(block.items)
        case "numbered_list":
            if let title = cleaned(block.text) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .textSelection(.enabled)
            }
            numberedList(block.items)
        case "ai_suggested":
            aiSuggestedBlock(block)
        default:
            if let text = cleaned(block.text) {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func summaryBlock<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
                .font(.callout)
        }
    }

    @ViewBuilder
    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(item)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func numberedList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(item)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func aiSuggestedBlock(_ block: TimelineAISummaryBlock) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(L10n.t("AI suggested", appLanguage), systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let text = cleaned(block.text) {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
            }

            if !block.items.isEmpty {
                bulletList(block.items)
                    .font(.callout)
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func copyContent() {
        guard let copyText else {
            return
        }

        UIPasteboard.general.string = copyText
        didCopy = true
    }

    private var displaySummary: TimelineAISummary? {
        guard let summary, summary.hasDisplayContent else {
            return nil
        }

        return summary
    }

    private var isSummarizing: Bool {
        summary?.isSummarizing == true
    }

    private var isGenerationActive: Bool {
        isRegenerateRequestInFlight || isSummarizing
    }

    private var isFailed: Bool {
        summary?.isFailed == true
    }

    private var canRegenerate: Bool {
        summary?.deletedAt == nil
    }

    private var generationStatusTitle: String {
        if isRegenerateRequestInFlight {
            return L10n.t("Regenerating summary...", appLanguage)
        }

        if summary?.status == "transcribing" {
            return L10n.t("Transcribing media...", appLanguage)
        }

        return L10n.t("Summarizing...", appLanguage)
    }

    private var generationStatusMessage: String {
        if displaySummary != nil {
            return L10n.t("The current summary will update when the new result is ready.", appLanguage)
        }

        return L10n.t("This can take a moment.", appLanguage)
    }

    private var failureMessage: String {
        if let message = cleaned(summary?.errorMessage) {
            return message
        }

        if displaySummary != nil {
            return L10n.t("The previous summary is still available. Try regenerating again when the Mac is reachable.", appLanguage)
        }

        return L10n.t("Try regenerating again when the Mac is reachable.", appLanguage)
    }

    private var copyText: String? {
        if let displaySummary {
            return summaryText(for: displaySummary)
        }

        return nil
    }

    private func summaryText(for summary: TimelineAISummary) -> String? {
        if hasDocumentContent(summary) {
            return documentSummaryText(for: summary)
        }

        if let text = cleaned(summary.summaryText) {
            return text
        }

        var lines = [String]()
        if let overview = cleaned(summary.overview) {
            lines.append(overview)
        }

        if !summary.keyPoints.isEmpty {
            lines.append(contentsOf: summary.keyPoints.map { "- \($0)" })
        }

        for section in summary.sections {
            lines.append(section.heading)
            lines.append(contentsOf: section.bullets.map { "- \($0)" })
        }

        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private func documentSummaryText(for summary: TimelineAISummary) -> String? {
        var lines = [String]()
        if let title = cleaned(summary.documentTitle) {
            lines.append("# \(title)")
            lines.append("")
        }

        if let oneLiner = cleaned(summary.oneLiner ?? summary.overview) {
            lines.append(oneLiner)
        }

        for block in summary.documentBlocks {
            switch block.kind {
            case "heading":
                if let text = cleaned(block.text) {
                    lines.append("")
                    lines.append("\(block.level == 2 ? "###" : "##") \(text)")
                }
            case "paragraph":
                if let text = cleaned(block.text) {
                    lines.append("")
                    lines.append(text)
                }
            case "bullets":
                appendListBlock(block, prefix: "-", lines: &lines)
            case "numbered_list":
                appendNumberedBlock(block, lines: &lines)
            case "ai_suggested":
                lines.append("")
                lines.append("> AI suggested\(cleaned(block.text).map { ": \($0)" } ?? "")")
                lines.append(contentsOf: block.items.map { "> - \($0)" })
            default:
                if let text = cleaned(block.text) {
                    lines.append("")
                    lines.append(text)
                }
            }
        }

        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private func appendListBlock(_ block: TimelineAISummaryBlock, prefix: String, lines: inout [String]) {
        lines.append("")
        if let text = cleaned(block.text) {
            lines.append(text)
        }
        lines.append(contentsOf: block.items.map { "\(prefix) \($0)" })
    }

    private func appendNumberedBlock(_ block: TimelineAISummaryBlock, lines: inout [String]) {
        lines.append("")
        if let text = cleaned(block.text) {
            lines.append(text)
        }
        lines.append(contentsOf: block.items.enumerated().map { "\($0.offset + 1). \($0.element)" })
    }

    private func hasDocumentContent(_ summary: TimelineAISummary) -> Bool {
        cleaned(summary.documentTitle) != nil ||
            cleaned(summary.oneLiner) != nil ||
            !summary.documentBlocks.isEmpty
    }

    private func documentGroups(from blocks: [TimelineAISummaryBlock]) -> [SummaryDocumentGroup] {
        var groups = [SummaryDocumentGroup]()
        var currentHeading: String?
        var currentLevel = 1
        var currentBlocks = [TimelineAISummaryBlock]()

        func flush() {
            if currentHeading != nil || !currentBlocks.isEmpty {
                groups.append(
                    SummaryDocumentGroup(
                        heading: currentHeading,
                        level: currentLevel,
                        blocks: currentBlocks
                    )
                )
            }
            currentBlocks = []
        }

        for block in blocks {
            if block.kind == "heading" {
                flush()
                currentHeading = block.text
                currentLevel = block.level == 2 ? 2 : 1
            } else {
                currentBlocks.append(block)
            }
        }

        flush()
        return groups
    }

    private func cleaned(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private struct SummaryDocumentGroup {
    let heading: String?
    let level: Int
    let blocks: [TimelineAISummaryBlock]
}
