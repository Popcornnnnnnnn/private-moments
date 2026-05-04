import SwiftUI

struct TimelineCommentInputBar: View {
    @Environment(\.appLanguage) private var appLanguage

    let targetSummary: String
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onCancel: () -> Void
    let onSend: () -> Void

    private let maxLength = 500

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedText.isEmpty && text.count <= maxLength
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(L10n.t("Commenting on:", appLanguage)) \(targetSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("Cancel comment", appLanguage))
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextEditor(text: $text)
                    .focused(isFocused)
                    .font(.body)
                    .frame(minHeight: 38, maxHeight: 112)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel(L10n.t("Comment text", appLanguage))

                Button(L10n.t("Send", appLanguage)) {
                    onSend()
                }
                .font(.body.weight(.semibold))
                .disabled(!canSend)
            }

            if text.count > maxLength {
                Text("\(L10n.t("Comments can be up to", appLanguage)) \(maxLength) \(L10n.t("characters.", appLanguage))")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                isFocused.wrappedValue = true
            }
        }
    }
}
