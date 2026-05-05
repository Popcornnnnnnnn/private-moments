import SwiftUI

struct MomentTextView: View {
    enum Style: Equatable {
        case timeline
        case detail
        case preview

        var heading1Font: Font {
            switch self {
            case .timeline:
                return .title3.weight(.semibold)
            case .detail:
                return .title2.weight(.semibold)
            case .preview:
                return .headline.weight(.semibold)
            }
        }

        var heading2Font: Font {
            switch self {
            case .timeline:
                return .headline.weight(.semibold)
            case .detail:
                return .title3.weight(.semibold)
            case .preview:
                return .subheadline.weight(.semibold)
            }
        }

        var lineSpacing: CGFloat {
            switch self {
            case .timeline:
                return 5
            case .detail:
                return 7
            case .preview:
                return 3
            }
        }

        var blankHeight: CGFloat {
            switch self {
            case .timeline:
                return 4
            case .detail:
                return 6
            case .preview:
                return 2
            }
        }

        var bodyFont: Font {
            switch self {
            case .timeline, .detail:
                return .body
            case .preview:
                return .subheadline
            }
        }

    }

    let text: String
    let style: Style

    private var lines: [MomentTextMarkdown.Line] {
        MomentTextMarkdown.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.lineSpacing) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                renderedLine(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .allowsHitTesting(style != .preview)
    }

    @ViewBuilder
    private func renderedLine(_ line: MomentTextMarkdown.Line) -> some View {
        switch line.kind {
        case .heading(let level, let text):
            Text(text)
                .font(level == 1 ? style.heading1Font : style.heading2Font)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 1)

        case .link(let url):
            MomentLinkCard(url: url, style: style)

        case .paragraph(let text):
            Text(text)
                .font(style.bodyFont)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

        case .blank:
            Spacer()
                .frame(height: style.blankHeight)
        }
    }
}

private struct MomentLinkCard: View {
    let url: URL
    let style: MomentTextView.Style

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.secondary.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(style == .detail ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(url.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, style == .detail ? 12 : 10)
            .padding(.vertical, style == .detail ? 10 : 8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    private var displayTitle: String {
        if let host = url.host, !host.isEmpty {
            return host.replacingOccurrences(of: "www.", with: "")
        }

        return "Link"
    }
}
