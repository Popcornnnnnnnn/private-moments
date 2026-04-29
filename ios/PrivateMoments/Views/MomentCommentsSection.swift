import Foundation
import SwiftUI

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

    func draftText(afterSubmissionSucceeded didSucceed: Bool) -> String {
        didSucceed ? "" : rawText
    }
}

struct MomentCommentsSection: View {
    let comments: [TimelineComment]
    @Binding var draftText: String
    let isSubmitting: Bool
    let onSubmit: (String) async -> Bool

    private var policy: MomentCommentDraftPolicy {
        MomentCommentDraftPolicy(rawText: draftText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Private Comments")
                .font(.headline)

            if comments.isEmpty {
                Text("No private comments yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(comments) { comment in
                        MomentCommentRow(comment: comment)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draftText)
                        .font(.body)
                        .frame(minHeight: 96)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .disabled(isSubmitting)
                        .accessibilityLabel("Private comment draft")

                    if draftText.isEmpty {
                        Text("Add a private comment…")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack {
                    Text("Only visible in your private archive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        submit()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Add")
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isSubmitting || !policy.canSubmit)
                    .accessibilityLabel("Add private comment")
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func submit() {
        guard !isSubmitting,
              let submissionText = policy.submissionText() else {
            return
        }

        let draftSnapshot = draftText
        Task {
            let didCreate = await onSubmit(submissionText)
            let snapshotPolicy = MomentCommentDraftPolicy(rawText: draftSnapshot)
            await MainActor.run {
                draftText = snapshotPolicy.draftText(afterSubmissionSucceeded: didCreate)
            }
        }
    }
}

private struct MomentCommentRow: View {
    let comment: TimelineComment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(comment.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                SyncBadge(status: comment.syncStatus)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
