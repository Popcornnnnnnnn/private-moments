import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var store: TimelineStore
    @State private var isComposerPresented = false
    @State private var gallery: MediaGallery?
    @State private var detailRoute: DetailRoute?
    @State private var pendingDelete: TimelineItem?
    @State private var searchText = ""
    @State private var selectedFilter: TimelineFilter = .all
    @State private var monthJumpRequest: TimelineMonthJump?
    @State private var floatingMonthTitle: String?
    @State private var isFloatingMonthVisible = false
    @State private var lastFloatingMonthAnchor: MonthAnchorValue?
    @State private var hideFloatingMonthTask: Task<Void, Never>?
    @State private var showDeleteDialogTask: Task<Void, Never>?
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if !store.isReady {
                    ProgressView()
                } else if store.items.isEmpty && !store.isAuthenticated {
                    ContentUnavailableView(
                        "Log in to sync",
                        systemImage: "lock",
                        description: Text("Open Settings and log in to your Mac server.")
                    )
                } else if store.items.isEmpty {
                    ContentUnavailableView("No moments", systemImage: "rectangle.stack")
                } else if filteredItems.isEmpty {
                    ContentUnavailableView(emptyStateTitle, systemImage: emptyStateSystemImage)
                } else {
                    ScrollViewReader { proxy in
                        ZStack(alignment: .top) {
                            List {
                                ForEach(groupedItems) { group in
                                    Section {
                                        monthAnchor(for: group)

                                        ForEach(group.items) { item in
                                            TimelineRow(item: item) { media, index in
                                                gallery = MediaGallery(media: media, startIndex: index)
                                            }
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                detailRoute = DetailRoute(postId: item.id)
                                            }
                                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                                Button {
                                                    Task {
                                                        await store.toggleFavorite(item)
                                                    }
                                                } label: {
                                                    Label(
                                                        item.post.isFavorite ? "Unfavorite" : "Favorite",
                                                        systemImage: item.post.isFavorite ? "star.slash" : "star"
                                                    )
                                            }
                                            .tint(.yellow)
                                        }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button {
                                                    requestDelete(item)
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                                .tint(.red)
                                            }
                                        }
                                    }
                                }
                            }
                            .listStyle(.plain)
                            .coordinateSpace(name: "timelineList")
                            .onPreferenceChange(MonthAnchorPreferenceKey.self) { anchors in
                                updateFloatingMonth(from: anchors)
                            }
                            .refreshable {
                                if store.isAuthenticated {
                                    await store.syncNow()
                                } else {
                                    try? await store.reload()
                                }
                            }

                            if let floatingMonthTitle {
                                FloatingMonthIndicator(title: floatingMonthTitle)
                                    .opacity(isFloatingMonthVisible ? 1 : 0)
                                    .offset(y: isFloatingMonthVisible ? 0 : -8)
                                    .animation(.easeOut(duration: 0.18), value: isFloatingMonthVisible)
                                    .allowsHitTesting(false)
                            }
                        }
                        .onChange(of: monthJumpRequest) { _, request in
                            guard let request else {
                                return
                            }

                            withAnimation(.easeInOut(duration: 0.24)) {
                                proxy.scrollTo(request.monthID, anchor: .top)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Moments")
            .searchable(text: $searchText, prompt: "Search")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        ForEach(TimelineFilter.allCases) { filter in
                            Button {
                                selectedFilter = filter
                            } label: {
                                Label(filter.title, systemImage: selectedFilter == filter ? "checkmark" : filter.systemImage)
                            }
                        }
                    } label: {
                        Image(systemName: selectedFilter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filter moments")

                    Menu {
                        ForEach(groupedItems) { group in
                            Button(group.title) {
                                monthJumpRequest = TimelineMonthJump(monthID: group.id)
                            }
                        }
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .disabled(groupedItems.isEmpty)
                    .accessibilityLabel("Jump to month")

                    Button {
                        isComposerPresented = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New moment")
                }
            }
            .sheet(isPresented: $isComposerPresented) {
                ComposerView()
            }
            .navigationDestination(item: $detailRoute) { route in
                MomentDetailView(postId: route.postId)
            }
            .fullScreenCover(item: $gallery) { gallery in
                MediaGalleryView(media: gallery.media, initialIndex: gallery.startIndex)
            }
            .alert("Delete this moment?", isPresented: deleteConfirmationBinding) {
                Button("Cancel", role: .cancel) {
                    isDeleteConfirmationPresented = false
                    pendingDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let pendingDelete {
                        Task {
                            await store.deletePost(pendingDelete)
                        }
                    }
                    isDeleteConfirmationPresented = false
                    pendingDelete = nil
                }
            } message: {
                Text("This removes the moment from your timeline and syncs the deletion to your Mac.")
            }
            .alert("Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
            .onDisappear {
                hideFloatingMonthTask?.cancel()
                showDeleteDialogTask?.cancel()
            }
        }
    }

    private var groupedItems: [TimelineMonthGroup] {
        let idFormatter = DateFormatter()
        idFormatter.dateFormat = "yyyy-MM"

        let groups = Dictionary(grouping: filteredItems) { item in
            idFormatter.string(from: item.post.occurredAt)
        }

        return groups
            .compactMap { id, items -> TimelineMonthGroup? in
                guard let representative = items.first?.post.occurredAt else {
                    return nil
                }

                return TimelineMonthGroup(
                    id: id,
                    title: MomentDateFormatter.monthTitle(for: representative),
                    items: items.sorted { $0.post.occurredAt > $1.post.occurredAt }
                )
            }
            .sorted { lhs, rhs in
                guard let left = lhs.items.first?.post.occurredAt,
                      let right = rhs.items.first?.post.occurredAt else {
                    return lhs.title > rhs.title
                }

                return left > right
            }
    }

    private var filteredItems: [TimelineItem] {
        let filteredByMode = store.items.filter(selectedFilter.includes)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return filteredByMode
        }

        return filteredByMode.filter { item in
            item.post.text.localizedCaseInsensitiveContains(query)
        }
    }

    private var emptyStateTitle: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No results"
        }

        return selectedFilter.emptyTitle
    }

    private var emptyStateSystemImage: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "magnifyingglass"
        }

        return selectedFilter.systemImage
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { _ in store.clearError() }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { isDeleteConfirmationPresented },
            set: { isPresented in
                isDeleteConfirmationPresented = isPresented
                if !isPresented {
                    pendingDelete = nil
                    showDeleteDialogTask?.cancel()
                }
            }
        )
    }

    private func requestDelete(_ item: TimelineItem) {
        showDeleteDialogTask?.cancel()
        pendingDelete = item

        showDeleteDialogTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard pendingDelete?.id == item.id else {
                    return
                }
                isDeleteConfirmationPresented = true
            }
        }
    }

    private func monthAnchor(for group: TimelineMonthGroup) -> some View {
        Color.clear
            .frame(height: 1)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: MonthAnchorPreferenceKey.self,
                        value: [
                            MonthAnchorValue(
                                id: group.id,
                                title: group.title,
                                minY: proxy.frame(in: .named("timelineList")).minY
                            ),
                        ]
                    )
                }
            }
            .id(group.id)
    }

    private func updateFloatingMonth(from anchors: [MonthAnchorValue]) {
        guard let active = activeMonthAnchor(from: anchors) else {
            return
        }

        guard let previous = lastFloatingMonthAnchor else {
            floatingMonthTitle = active.title
            lastFloatingMonthAnchor = active
            return
        }

        let didMoveVertically = abs(previous.minY - active.minY) >= 4
        let didChangeMonth = previous.id != active.id
        guard didMoveVertically || didChangeMonth else {
            return
        }

        floatingMonthTitle = active.title
        lastFloatingMonthAnchor = active

        withAnimation(.easeOut(duration: 0.16)) {
            isFloatingMonthVisible = true
        }
        scheduleFloatingMonthHide()
    }

    private func activeMonthAnchor(from anchors: [MonthAnchorValue]) -> MonthAnchorValue? {
        let sortedAnchors = anchors.sorted { $0.minY < $1.minY }
        return sortedAnchors.last { $0.minY <= 72 } ?? sortedAnchors.first
    }

    private func scheduleFloatingMonthHide() {
        hideFloatingMonthTask?.cancel()
        hideFloatingMonthTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.24)) {
                    isFloatingMonthVisible = false
                }
            }
        }
    }
}

private enum TimelineFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case photos
    case needsSync

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            return "All Moments"
        case .favorites:
            return "Favorites"
        case .photos:
            return "With Photos"
        case .needsSync:
            return "Needs Sync"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all:
            return "No moments"
        case .favorites:
            return "No favorites"
        case .photos:
            return "No photo moments"
        case .needsSync:
            return "Nothing needs sync"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "rectangle.stack"
        case .favorites:
            return "star"
        case .photos:
            return "photo.on.rectangle"
        case .needsSync:
            return "arrow.triangle.2.circlepath"
        }
    }

    func includes(_ item: TimelineItem) -> Bool {
        switch self {
        case .all:
            return true
        case .favorites:
            return item.post.isFavorite
        case .photos:
            return !item.media.isEmpty
        case .needsSync:
            return item.post.syncStatus != "synced"
        }
    }
}

private struct TimelineMonthGroup: Identifiable {
    let id: String
    let title: String
    let items: [TimelineItem]
}

private struct MonthAnchorValue: Equatable {
    let id: String
    let title: String
    let minY: CGFloat
}

private struct MonthAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [MonthAnchorValue] = []

    static func reduce(value: inout [MonthAnchorValue], nextValue: () -> [MonthAnchorValue]) {
        value.append(contentsOf: nextValue())
    }
}

private struct FloatingMonthIndicator: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
            .padding(.top, 8)
    }
}

private struct TimelineMonthJump: Equatable {
    let requestID = UUID()
    let monthID: String
}

private struct DetailRoute: Identifiable, Hashable {
    let postId: String

    var id: String {
        postId
    }
}

private struct MediaGallery: Identifiable {
    let media: [TimelineMedia]
    let startIndex: Int

    var id: String {
        "\(media.map(\.id).joined(separator: "-"))-\(startIndex)"
    }
}
