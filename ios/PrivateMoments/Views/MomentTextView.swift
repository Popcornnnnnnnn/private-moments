import SwiftUI

struct MomentTextView: View {
    enum Style {
        case timeline
        case detail

        var heading1Font: Font {
            switch self {
            case .timeline:
                return .title3.weight(.semibold)
            case .detail:
                return .title2.weight(.semibold)
            }
        }

        var heading2Font: Font {
            switch self {
            case .timeline:
                return .headline.weight(.semibold)
            case .detail:
                return .title3.weight(.semibold)
            }
        }

        var lineSpacing: CGFloat {
            switch self {
            case .timeline:
                return 5
            case .detail:
                return 7
            }
        }

        var blankHeight: CGFloat {
            switch self {
            case .timeline:
                return 4
            case .detail:
                return 6
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

        case .paragraph(let text):
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

        case .blank:
            Spacer()
                .frame(height: style.blankHeight)
        }
    }
}
