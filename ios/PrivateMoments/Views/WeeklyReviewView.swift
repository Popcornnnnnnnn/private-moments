import SwiftUI

struct WeeklyReviewListView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        List {
            Section {
                Button {
                    Task {
                        await store.generateWeeklyReview()
                    }
                } label: {
                    Label(L10n.t("Generate Last 7 Days", appLanguage), systemImage: "sparkles")
                }
                .disabled(!store.isAuthenticated || store.isLoadingReviews)
            }

            Section(L10n.t("Recent Reviews", appLanguage)) {
                if store.isLoadingReviews && store.weeklyReviews.isEmpty {
                    ProgressView()
                } else if store.weeklyReviews.isEmpty {
                    ContentUnavailableView(
                        L10n.t("No weekly reviews yet", appLanguage),
                        systemImage: "doc.text.magnifyingglass"
                    )
                } else {
                    ForEach(store.weeklyReviews) { review in
                        NavigationLink {
                            WeeklyReviewDetailView(review: review)
                        } label: {
                            WeeklyReviewRow(review: review)
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.t("Reviews", appLanguage))
        .task {
            await store.refreshReviews()
        }
        .refreshable {
            await store.refreshReviews()
        }
    }
}

private struct WeeklyReviewRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let review: ReviewPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(review.content.title?.isEmpty == false ? review.content.title! : L10n.t("Weekly Review", appLanguage))
                .font(.headline)
                .lineLimit(2)

            if let oneLiner = review.content.oneLiner, !oneLiner.isEmpty {
                Text(oneLiner)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let errorMessage = review.errorMessage, review.status == "failed" {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(rangeTitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    private var rangeTitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        if let start = review.parsedRangeStart, let end = review.parsedRangeEnd {
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        }

        return review.status.capitalized
    }
}

struct WeeklyReviewDetailView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage

    let review: ReviewPayload

    @State private var selectedMomentId: String?
    @State private var feedbackNote = ""
    @State private var showMissedPointPrompt = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if review.status == "ready" {
                    reviewBody
                } else {
                    statusBody
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .navigationTitle(L10n.t("Weekly Review", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task {
                            await store.regenerateReview(review)
                        }
                    } label: {
                        Label(L10n.t("Regenerate", appLanguage), systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isLoadingReviews)

                    Button {
                        Task {
                            await store.publishReviewAsMoment(review)
                        }
                    } label: {
                        Label(L10n.t("Publish as Moment", appLanguage), systemImage: "square.and.arrow.up")
                    }
                    .disabled(review.status != "ready" || review.publishedPostId != nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: selectedMomentBinding) { item in
            NavigationStack {
                MomentDetailView(postId: item.id)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L10n.t("Done", appLanguage)) {
                                selectedMomentId = nil
                            }
                        }
                    }
            }
        }
        .alert(L10n.t("What did it miss?", appLanguage), isPresented: $showMissedPointPrompt) {
            TextField(L10n.t("Short note", appLanguage), text: $feedbackNote)
            Button(L10n.t("Send", appLanguage)) {
                Task {
                    await store.sendReviewFeedback(review: review, type: "missed_point", note: feedbackNote)
                    feedbackNote = ""
                }
            }
            Button(L10n.t("Cancel", appLanguage), role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(review.content.title?.isEmpty == false ? review.content.title! : L10n.t("Weekly Review", appLanguage))
                .font(.largeTitle.weight(.semibold))
                .fontDesign(.rounded)

            if let oneLiner = review.content.oneLiner, !oneLiner.isEmpty {
                Text(oneLiner)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Text(rangeTitle)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var reviewBody: some View {
        if let keywords = review.content.keywords, !keywords.isEmpty {
            ReviewSection(title: L10n.t("Keywords", appLanguage), systemImage: "number") {
                FlowLayout(spacing: 8) {
                    ForEach(keywords) { keyword in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(keyword.label)
                                .font(.subheadline.weight(.semibold))
                            Text(keyword.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }

        if let themes = review.content.themes, !themes.isEmpty {
            ReviewSection(title: L10n.t("Themes", appLanguage), systemImage: "square.grid.2x2") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(themes) { theme in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(theme.title)
                                .font(.headline)
                            Text(theme.body)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }

        if let reflection = review.content.emotionalReflection, !reflection.body.isEmpty {
            ReviewSection(title: L10n.t("State Response", appLanguage), systemImage: "heart.text.square") {
                Text(reflection.body)
                    .font(.body)
            }
        }

        if let progress = review.content.progressAndOpenLoops {
            ReviewSection(title: L10n.t("Progress and Open Loops", appLanguage), systemImage: "point.3.connected.trianglepath.dotted") {
                VStack(alignment: .leading, spacing: 12) {
                    bulletGroup(title: L10n.t("Progress", appLanguage), items: progress.progress)
                    bulletGroup(title: L10n.t("Open loops", appLanguage), items: progress.openLoops)
                }
            }
        }

        if let rhythm = review.content.rhythm, !rhythm.body.isEmpty || !rhythm.observations.isEmpty {
            ReviewSection(title: L10n.t("Rhythm", appLanguage), systemImage: "waveform.path.ecg") {
                VStack(alignment: .leading, spacing: 10) {
                    if !rhythm.body.isEmpty {
                        Text(rhythm.body)
                    }
                    bulletGroup(title: nil, items: rhythm.observations)
                }
            }
        }

        if let notableMoments = review.content.notableMoments, !notableMoments.isEmpty {
            ReviewSection(title: L10n.t("Worth Revisiting", appLanguage), systemImage: "bookmark") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(notableMoments) { notable in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(notable.title)
                                .font(.headline)
                            Text(notable.note)
                                .font(.body)
                                .foregroundStyle(.secondary)

                            if let firstMomentId = notable.momentIds.first, store.item(id: firstMomentId) != nil {
                                Button {
                                    selectedMomentId = firstMomentId
                                } label: {
                                    Label(L10n.t("Open moment preview", appLanguage), systemImage: "arrow.up.left.and.arrow.down.right")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }

        if let suggestions = review.content.gentleSuggestions, !suggestions.isEmpty {
            ReviewSection(title: L10n.t("Gentle Suggestions", appLanguage), systemImage: "leaf") {
                bulletGroup(title: nil, items: suggestions)
            }
        }

        if let uncertainty = review.content.uncertainty, !uncertainty.isEmpty {
            ReviewSection(title: L10n.t("Uncertainty", appLanguage), systemImage: "questionmark.circle") {
                bulletGroup(title: nil, items: uncertainty)
            }
        }

        feedbackControls
    }

    private var statusBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if review.status == "generating" {
                ProgressView()
                Text(L10n.t("Generating review", appLanguage))
                    .foregroundStyle(.secondary)
            } else {
                Text(review.errorMessage ?? L10n.t("Review failed", appLanguage))
                    .foregroundStyle(.secondary)
                Button(L10n.t("Regenerate", appLanguage)) {
                    Task {
                        await store.regenerateReview(review)
                    }
                }
            }
        }
    }

    private var feedbackControls: some View {
        ReviewSection(title: L10n.t("Feedback", appLanguage), systemImage: "slider.horizontal.3") {
            FlowLayout(spacing: 8) {
                feedbackButton("Useful", type: "useful")
                feedbackButton("Too much inference", type: "too_much_inference")
                feedbackButton("Too dry", type: "too_dry")
                Button(L10n.t("Missed the point", appLanguage)) {
                    showMissedPointPrompt = true
                }
                .buttonStyle(.bordered)
                feedbackButton("Hide this theme", type: "hide_theme")
            }
        }
    }

    private func feedbackButton(_ title: String, type: String) -> some View {
        Button(L10n.t(title, appLanguage)) {
            Task {
                await store.sendReviewFeedback(review: review, type: type)
            }
        }
        .buttonStyle(.bordered)
    }

    private func bulletGroup(title: String?, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title, !items.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(item)
                }
            }
        }
    }

    private var selectedMomentBinding: Binding<TimelineItem?> {
        Binding(
            get: {
                guard let selectedMomentId else {
                    return nil
                }
                return store.item(id: selectedMomentId)
            },
            set: { value in
                selectedMomentId = value?.id
            }
        )
    }

    private var rangeTitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        if let start = review.parsedRangeStart, let end = review.parsedRangeEnd {
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        }

        return review.rangeMode
    }
}

private struct ReviewSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var size = CGSize(width: maxWidth, height: 0)
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let subviewSize = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + spacing + subviewSize.width > maxWidth {
                size.height += rowHeight + spacing
                rowWidth = subviewSize.width
                rowHeight = subviewSize.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + subviewSize.width
                rowHeight = max(rowHeight, subviewSize.height)
            }
        }

        size.height += rowHeight
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var point = CGPoint(x: bounds.minX, y: bounds.minY)
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let subviewSize = subview.sizeThatFits(.unspecified)
            if point.x > bounds.minX && point.x + subviewSize.width > bounds.maxX {
                point.x = bounds.minX
                point.y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: point,
                proposal: ProposedViewSize(width: subviewSize.width, height: subviewSize.height)
            )
            point.x += subviewSize.width + spacing
            rowHeight = max(rowHeight, subviewSize.height)
        }
    }
}
