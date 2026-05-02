import SwiftUI
import UIKit

struct TimelineCommentsSection: View {
    let comments: [TimelineComment]
    let isExpanded: Bool
    let searchQuery: String
    let now: Date
    let onToggleExpanded: () -> Void
    let onDeleteRequest: (TimelineComment) -> Void

    private var display: TimelineCommentDisplay {
        TimelineCommentDisplay(
            comments: comments,
            isExpanded: isExpanded,
            searchQuery: searchQuery
        )
    }

    var body: some View {
        if !comments.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(display.visibleComments) { comment in
                    TimelineCommentRow(
                        comment: comment,
                        isHighlighted: display.highlightedCommentIDs.contains(comment.id),
                        now: now,
                        onDeleteRequest: {
                            onDeleteRequest(comment)
                        }
                    )
                }

                if comments.count > 2 {
                    Button {
                        onToggleExpanded()
                    } label: {
                        Text(isExpanded ? "Show less" : "View all \(comments.count) comments")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
    }
}

struct TimelineCommentDisplay {
    let comments: [TimelineComment]
    let isExpanded: Bool
    let searchQuery: String

    var visibleComments: [TimelineComment] {
        if isExpanded {
            return sortedComments
        }

        if !trimmedSearchQuery.isEmpty {
            let matches = sortedComments.filter { matchesSearch($0) }
            if !matches.isEmpty {
                return Array(matches.prefix(2))
            }
        }

        return Array(sortedComments.suffix(2))
    }

    var highlightedCommentIDs: Set<String> {
        guard !trimmedSearchQuery.isEmpty else {
            return []
        }

        return Set(sortedComments.filter { matchesSearch($0) }.map(\.id))
    }

    private var sortedComments: [TimelineComment] {
        comments.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id < $1.id
            }

            return $0.createdAt < $1.createdAt
        }
    }

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesSearch(_ comment: TimelineComment) -> Bool {
        TimelineSearch.textMatches(comment.text, query: trimmedSearchQuery)
    }
}

private struct TimelineCommentRow: View {
    let comment: TimelineComment
    let isHighlighted: Bool
    let now: Date
    let onDeleteRequest: () -> Void
    @State private var isPressing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(comment.text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(MomentDateFormatter.commentRelativeTitle(for: comment.createdAt, now: now))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isPressing {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.tertiarySystemFill))
                    .padding(.horizontal, -6)
                    .padding(.vertical, -5)
            } else if isHighlighted {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(0.10))
                    .padding(.horizontal, -6)
                    .padding(.vertical, -5)
            }
        }
        .scaleEffect(isPressing ? 0.985 : 1)
        .contentShape(Rectangle())
        .accessibilityHint("Long press to delete comment")
        .animation(.easeOut(duration: 0.12), value: isPressing)
        .onLongPressGesture(
            minimumDuration: 0.38,
            maximumDistance: 18,
            pressing: { isPressing in
                withAnimation(.easeOut(duration: 0.12)) {
                    self.isPressing = isPressing
                }
            },
            perform: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onDeleteRequest()
            }
        )
    }
}
