import AVKit
import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var store: TimelineStore
    @EnvironmentObject private var playbackCenter: MediaPlaybackCenter
    @EnvironmentObject private var videoAutoplayCenter: TimelineVideoAutoplayCenter
    @State private var isComposerPresented = false
    @State private var gallery: MediaGallery?
    @State private var videoPlayer: VideoPlayerRoute?
    @State private var detailRoute: DetailRoute?
    @State private var summaryRoute: AISummaryRoute?
    @State private var pendingDelete: TimelineItem?
    @State private var searchText = ""
    @State private var selectedContentFilter: TimelineContentFilter = .all
    @State private var isFavoritesOnly = false
    @State private var isCommentedOnly = false
    @State private var isNeedsSyncOnly = false
    @State private var selectedMonthFilter: TimelineMonthFilter?
    @State private var selectedMatchSourceFilter: TimelineMatchSourceFilter = .all
    @State private var dateJumpRequest: TimelineDateJumpRequest?
    @State private var floatingMonthTitle: String?
    @State private var isFloatingMonthVisible = false
    @State private var lastFloatingMonthAnchor: MonthAnchorValue?
    @State private var hideFloatingMonthTask: Task<Void, Never>?
    @State private var showDeleteDialogTask: Task<Void, Never>?
    @State private var isDeleteConfirmationPresented = false
    @State private var expandedCommentPostIDs = Set<String>()
    @State private var commentTargetPostId: String?
    @State private var pendingCommentTarget: TimelineItem?
    @State private var commentDraft = ""
    @State private var isDiscardDraftConfirmationPresented = false
    @State private var pendingDeleteComment: TimelineComment?
    @State private var isCommentDeleteConfirmationPresented = false
    @State private var relativeTimeNow = Date()
    @State private var commentFeedbackScrollTask: Task<Void, Never>?
    @State private var videoAutoplayCandidateMediaId: String?
    @State private var videoAutoplayTask: Task<Void, Never>?
    @FocusState private var isCommentInputFocused: Bool

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
                } else {
                    VStack(spacing: 0) {
                        if hasActiveFilters {
                            TimelineActiveFilterBar(chips: activeFilterChips, onClearAll: clearAllFilters)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(.systemBackground))
                        }

                        if filteredItems.isEmpty {
                            ContentUnavailableView(emptyStateTitle, systemImage: emptyStateSystemImage)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollViewReader { proxy in
                                ZStack(alignment: .top) {
                                    GeometryReader { listProxy in
                                        List {
                                            ForEach(groupedItems) { group in
                                                Section {
                                                    monthAnchor(for: group)

                                                    ForEach(group.items) { item in
                                                        TimelineRow(
                                                            item: item,
                                                            isCommentsExpanded: expandedCommentPostIDs.contains(item.id),
                                                            searchQuery: searchText,
                                                            relativeTimeNow: relativeTimeNow,
                                                            aiSummaryRequestMediaIDs: store.aiSummaryRequestsInFlight,
                                                            searchResult: searchResult(for: item)
                                                        ) { media, index in
                                                            openMedia(media, index: index)
                                                        } onOpenDetail: {
                                                            stopVideoAutoplay()
                                                            detailRoute = DetailRoute(postId: item.id)
                                                        } onComment: {
                                                            beginComment(on: item, proxy: proxy)
                                                        } onToggleComments: {
                                                            toggleComments(for: item.id)
                                                        } onDeleteComment: { comment in
                                                            requestCommentDelete(comment)
                                                        } onOpenSummary: { media in
                                                            summaryRoute = AISummaryRoute(mediaId: media.id)
                                                        }
                                                        .id(item.id)
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
                                        .onPreferenceChange(TimelineVideoVisibilityPreferenceKey.self) { videos in
                                            updateVideoAutoplay(from: videos, viewportHeight: listProxy.size.height)
                                        }
                                        .refreshable {
                                            if store.isAuthenticated {
                                                await store.syncNow()
                                            } else {
                                                try? await store.reload()
                                            }
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
                                .onChange(of: dateJumpRequest) { _, request in
                                    guard let request else {
                                        return
                                    }

                                    withAnimation(.easeInOut(duration: 0.24)) {
                                        proxy.scrollTo(request.targetID, anchor: request.anchor.unitPoint)
                                    }
                                }
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
                        Section("Content") {
                            ForEach(TimelineContentFilter.allCases) { filter in
                                Button {
                                    selectedContentFilter = filter
                                } label: {
                                    Label(filter.title, systemImage: selectedContentFilter == filter ? "checkmark" : filter.systemImage)
                                }
                            }
                        }

                        Section("Attributes") {
                            Button {
                                isFavoritesOnly.toggle()
                            } label: {
                                Label("Favorites", systemImage: isFavoritesOnly ? "checkmark" : "star")
                            }

                            Button {
                                isCommentedOnly.toggle()
                            } label: {
                                Label("Commented", systemImage: isCommentedOnly ? "checkmark" : "text.bubble")
                            }

                            Button {
                                isNeedsSyncOnly.toggle()
                            } label: {
                                Label("Needs Sync", systemImage: isNeedsSyncOnly ? "checkmark" : "arrow.triangle.2.circlepath")
                            }
                        }

                        if hasSearchQuery {
                            Section("Match Source") {
                                ForEach(TimelineMatchSourceFilter.allCases) { filter in
                                    Button {
                                        selectedMatchSourceFilter = filter
                                    } label: {
                                        Label(filter.title, systemImage: selectedMatchSourceFilter == filter ? "checkmark" : filter.systemImage)
                                    }
                                }
                            }
                        }

                        if hasActiveFilters {
                            Section {
                                Button("Clear Filters", role: .destructive) {
                                    clearAllFilters()
                                }
                            }
                        }
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter moments")

                    Menu {
                        if selectedMonthFilter != nil {
                            Button("Clear Month Filter", role: .destructive) {
                                selectedMonthFilter = nil
                            }
                        }

                        ForEach(monthMenuGroups) { group in
                            Menu(group.title) {
                                Button("Show This Month") {
                                    selectedMonthFilter = TimelineMonthFilter(monthStart: group.monthStart, title: group.title)
                                }

                                Button("Jump to Month") {
                                    dateJumpRequest = TimelineDateJumpRequest(targetID: group.id)
                                }

                                ForEach(group.days) { day in
                                    Button(day.title) {
                                        dateJumpRequest = TimelineDateJumpRequest(targetID: day.targetItemID)
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: selectedMonthFilter == nil ? "calendar" : "calendar.badge.clock")
                    }
                    .disabled(monthMenuGroups.isEmpty)
                    .accessibilityLabel("Jump to date")

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
            .fullScreenCover(item: $videoPlayer) { route in
                VideoMomentPlayerView(media: route.media)
            }
            .sheet(item: $summaryRoute) { route in
                if let media = mediaForSummaryRoute(route) {
                    AISummarySheet(
                        media: media,
                        summary: aiSummary(for: media),
                        onRegenerate: {
                            await requestAISummary(media: media, forceRegenerate: true)
                        },
                        onDelete: {
                            if let summary = aiSummary(for: media) {
                                deleteAISummary(summary)
                            }
                        }
                    )
                } else {
                    ContentUnavailableView("Summary unavailable", systemImage: "sparkles")
                }
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
            .alert("Delete comment?", isPresented: commentDeleteConfirmationBinding) {
                Button("Cancel", role: .cancel) {
                    isCommentDeleteConfirmationPresented = false
                    pendingDeleteComment = nil
                }
                Button("Delete", role: .destructive) {
                    confirmCommentDelete()
                }
            }
            .alert("Discard draft?", isPresented: discardDraftConfirmationBinding) {
                Button("Cancel", role: .cancel) {
                    pendingCommentTarget = nil
                }
                Button("Discard", role: .destructive) {
                    discardCommentDraft()
                }
            }
            .alert("Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
            .safeAreaInset(edge: .bottom) {
                if let target = activeCommentTarget {
                    TimelineCommentInputBar(
                        targetSummary: commentTargetSummary(for: target),
                        text: $commentDraft,
                        isFocused: $isCommentInputFocused,
                        onCancel: requestCloseCommentInput,
                        onSend: sendComment
                    )
                }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now in
                relativeTimeNow = now
            }
            .onChange(of: searchText) { _, value in
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    selectedMatchSourceFilter = .all
                }
            }
            .onChange(of: isComposerPresented) { _, isPresented in
                if isPresented {
                    stopVideoAutoplay()
                }
            }
            .onChange(of: gallery?.id) { _, id in
                if id != nil {
                    stopVideoAutoplay()
                }
            }
            .onChange(of: videoPlayer?.id) { _, id in
                if id != nil {
                    stopVideoAutoplay()
                } else {
                    videoAutoplayCandidateMediaId = nil
                }
            }
            .onDisappear {
                hideFloatingMonthTask?.cancel()
                showDeleteDialogTask?.cancel()
                commentFeedbackScrollTask?.cancel()
                stopVideoAutoplay()
            }
        }
    }

    private var groupedItems: [TimelineDateJumpMonthGroup] {
        TimelineDateJumpBuilder.groups(from: filteredItems)
    }

    private var monthMenuGroups: [TimelineDateJumpMonthGroup] {
        TimelineDateJumpBuilder.groups(from: store.items)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSearchQuery: Bool {
        !trimmedSearchText.isEmpty
    }

    private var filteredItems: [TimelineItem] {
        store.items.filter { item in
            guard selectedContentFilter.includes(item) else {
                return false
            }

            if isFavoritesOnly && !item.post.isFavorite {
                return false
            }

            if isCommentedOnly && item.comments.isEmpty {
                return false
            }

            if isNeedsSyncOnly && !itemNeedsSync(item) {
                return false
            }

            if let selectedMonthFilter,
               !Calendar.current.isDate(item.post.occurredAt, equalTo: selectedMonthFilter.monthStart, toGranularity: .month) {
                return false
            }

            guard hasSearchQuery else {
                return true
            }

            let result = TimelineSearch.result(for: item, query: trimmedSearchText)
            return result.isMatch && selectedMatchSourceFilter.includes(result)
        }
    }

    private var hasActiveFilters: Bool {
        selectedContentFilter != .all
            || isFavoritesOnly
            || isCommentedOnly
            || isNeedsSyncOnly
            || selectedMonthFilter != nil
            || (hasSearchQuery && selectedMatchSourceFilter != .all)
    }

    private var activeFilterChips: [TimelineFilterChip] {
        var chips = [TimelineFilterChip]()

        if selectedContentFilter != .all {
            chips.append(
                TimelineFilterChip(
                    id: "content-\(selectedContentFilter.rawValue)",
                    title: selectedContentFilter.title,
                    systemImage: selectedContentFilter.systemImage
                ) {
                    selectedContentFilter = .all
                }
            )
        }

        if isFavoritesOnly {
            chips.append(
                TimelineFilterChip(id: "favorites", title: "Favorites", systemImage: "star") {
                    isFavoritesOnly = false
                }
            )
        }

        if isCommentedOnly {
            chips.append(
                TimelineFilterChip(id: "commented", title: "Commented", systemImage: "text.bubble") {
                    isCommentedOnly = false
                }
            )
        }

        if isNeedsSyncOnly {
            chips.append(
                TimelineFilterChip(id: "needs-sync", title: "Needs Sync", systemImage: "arrow.triangle.2.circlepath") {
                    isNeedsSyncOnly = false
                }
            )
        }

        if let selectedMonthFilter {
            chips.append(
                TimelineFilterChip(id: "month-\(selectedMonthFilter.id)", title: selectedMonthFilter.title, systemImage: "calendar") {
                    self.selectedMonthFilter = nil
                }
            )
        }

        if hasSearchQuery && selectedMatchSourceFilter != .all {
            chips.append(
                TimelineFilterChip(
                    id: "match-\(selectedMatchSourceFilter.rawValue)",
                    title: selectedMatchSourceFilter.title,
                    systemImage: selectedMatchSourceFilter.systemImage
                ) {
                    selectedMatchSourceFilter = .all
                }
            )
        }

        return chips
    }

    private func clearAllFilters() {
        selectedContentFilter = .all
        isFavoritesOnly = false
        isCommentedOnly = false
        isNeedsSyncOnly = false
        selectedMonthFilter = nil
        selectedMatchSourceFilter = .all
    }

    private func searchResult(for item: TimelineItem) -> TimelineSearchResult? {
        guard hasSearchQuery else {
            return nil
        }

        return TimelineSearch.result(for: item, query: trimmedSearchText)
    }

    private func itemNeedsSync(_ item: TimelineItem) -> Bool {
        item.post.syncStatus != "synced"
            || item.media.contains { $0.uploadStatus != "uploaded" }
            || item.comments.contains { $0.serverVersion == nil }
    }

    private var activeCommentTarget: TimelineItem? {
        guard let commentTargetPostId else {
            return nil
        }

        return store.item(id: commentTargetPostId)
    }

    private var emptyStateTitle: String {
        if hasSearchQuery {
            return "No results"
        }

        if hasActiveFilters {
            return "No matching moments"
        }

        return "No moments"
    }

    private var emptyStateSystemImage: String {
        if hasSearchQuery {
            return "magnifyingglass"
        }

        if hasActiveFilters {
            return "line.3.horizontal.decrease.circle"
        }

        return "rectangle.stack"
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

    private var commentDeleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { isCommentDeleteConfirmationPresented },
            set: { isPresented in
                isCommentDeleteConfirmationPresented = isPresented
                if !isPresented {
                    pendingDeleteComment = nil
                }
            }
        )
    }

    private var discardDraftConfirmationBinding: Binding<Bool> {
        Binding(
            get: { isDiscardDraftConfirmationPresented },
            set: { isPresented in
                isDiscardDraftConfirmationPresented = isPresented
                if !isPresented {
                    pendingCommentTarget = nil
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

    private func openMedia(_ media: [TimelineMedia], index: Int) {
        guard media.indices.contains(index) else {
            return
        }

        let selected = media[index]
        if selected.isVideo {
            stopVideoAutoplay()
            videoPlayer = VideoPlayerRoute(media: selected)
            return
        }

        let imageMedia = media.filter(\.isImage)
        let imageIndex = imageMedia.firstIndex { $0.id == selected.id } ?? 0
        gallery = MediaGallery(media: imageMedia, startIndex: imageIndex)
    }

    private func beginComment(on item: TimelineItem, proxy: ScrollViewProxy) {
        if commentTargetPostId != item.id && !commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingCommentTarget = item
            isDiscardDraftConfirmationPresented = true
            return
        }

        commentTargetPostId = item.id
        pendingCommentTarget = nil

        withAnimation(.easeInOut(duration: 0.22)) {
            proxy.scrollTo(item.id, anchor: .center)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            isCommentInputFocused = true
        }
    }

    private func requestCloseCommentInput() {
        if commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            closeCommentInput()
            return
        }

        pendingCommentTarget = nil
        isDiscardDraftConfirmationPresented = true
    }

    private func discardCommentDraft() {
        commentDraft = ""
        isDiscardDraftConfirmationPresented = false

        if let pendingCommentTarget {
            commentTargetPostId = pendingCommentTarget.id
            dateJumpRequest = TimelineDateJumpRequest(targetID: pendingCommentTarget.id)
            self.pendingCommentTarget = nil
            isCommentInputFocused = true
        } else {
            closeCommentInput()
        }
    }

    private func closeCommentInput() {
        commentTargetPostId = nil
        commentDraft = ""
        isCommentInputFocused = false
    }

    private func sendComment() {
        let text = commentDraft
        guard let postId = commentTargetPostId else {
            return
        }

        Task {
            if await store.createComment(postId: postId, text: text) != nil {
                commentDraft = ""
                relativeTimeNow = Date()
                expandedCommentPostIDs.insert(postId)
                commentTargetPostId = nil
                isCommentInputFocused = false
                scheduleCommentFeedbackScroll(postId: postId)
            }
        }
    }

    private func scheduleCommentFeedbackScroll(postId: TimelineItem.ID) {
        commentFeedbackScrollTask?.cancel()
        commentFeedbackScrollTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                dateJumpRequest = TimelineDateJumpRequest(
                    targetID: postId,
                    anchor: .bottom
                )
            }

            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                dateJumpRequest = TimelineDateJumpRequest(
                    targetID: postId,
                    anchor: .bottom
                )
            }
        }
    }

    private func toggleComments(for postId: String) {
        if expandedCommentPostIDs.contains(postId) {
            expandedCommentPostIDs.remove(postId)
        } else {
            expandedCommentPostIDs.insert(postId)
        }
    }

    private func requestCommentDelete(_ comment: TimelineComment) {
        pendingDeleteComment = comment
        isCommentDeleteConfirmationPresented = true
    }

    private func confirmCommentDelete() {
        guard let comment = pendingDeleteComment else {
            return
        }

        pendingDeleteComment = nil
        isCommentDeleteConfirmationPresented = false

        Task {
            await store.deleteComment(comment)
            relativeTimeNow = Date()
        }
    }

    private func requestAISummary(media: TimelineMedia, forceRegenerate: Bool) async {
        await store.requestAISummary(for: media, forceRegenerate: forceRegenerate)
    }

    private func deleteAISummary(_ summary: TimelineAISummary) {
        Task {
            await store.deleteAISummary(summary)
        }
    }

    private func mediaForSummaryRoute(_ route: AISummaryRoute) -> TimelineMedia? {
        store.items
            .flatMap(\.media)
            .first { $0.id == route.mediaId }
    }

    private func aiSummary(for media: TimelineMedia) -> TimelineAISummary? {
        store.items
            .flatMap(\.aiSummaries)
            .first { $0.mediaId == media.id && $0.deletedAt == nil }
    }

    private func commentTargetSummary(for item: TimelineItem) -> String {
        let trimmedText = item.post.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            if trimmedText.count > 36 {
                return "\(trimmedText.prefix(36))..."
            }

            return trimmedText
        }

        if item.media.count == 1 {
            if item.media.first?.isAudio == true {
                return "Audio moment"
            }
            if item.media.first?.isVideo == true {
                return "Video moment"
            }
            return "Photo moment"
        }

        if item.media.count > 1 {
            return "Photo moment · \(item.media.count) photos"
        }

        return "this moment"
    }

    private func monthAnchor(for group: TimelineDateJumpMonthGroup) -> some View {
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

    private func updateVideoAutoplay(
        from videos: [TimelineVideoVisibilityValue],
        viewportHeight: CGFloat
    ) {
        guard videoPlayer == nil else {
            stopVideoAutoplay()
            return
        }

        guard let target = videoAutoplayTarget(from: videos, viewportHeight: viewportHeight),
              let media = videoMedia(withId: target.mediaId) else {
            stopVideoAutoplay()
            return
        }

        guard videoAutoplayCandidateMediaId != media.id else {
            return
        }

        videoAutoplayCandidateMediaId = media.id
        videoAutoplayTask?.cancel()
        videoAutoplayTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else {
                return
            }

            do {
                let url = try await store.localPlayableURL(for: media)
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard videoAutoplayCandidateMediaId == media.id, videoPlayer == nil else {
                        return
                    }

                    playbackCenter.stop()
                    videoAutoplayCenter.play(media: media, url: url)
                }
            } catch {
                await MainActor.run {
                    if videoAutoplayCandidateMediaId == media.id {
                        videoAutoplayCandidateMediaId = nil
                    }
                }
            }
        }
    }

    private func videoAutoplayTarget(
        from videos: [TimelineVideoVisibilityValue],
        viewportHeight: CGFloat
    ) -> TimelineVideoVisibilityValue? {
        let viewportCenter = viewportHeight / 2

        return videos
            .compactMap { video -> (video: TimelineVideoVisibilityValue, score: CGFloat)? in
                let visibleHeight = max(0, min(video.minY + video.height, viewportHeight) - max(video.minY, 0))
                let visibleRatio = visibleHeight / max(video.height, 1)
                let centerIsVisible = video.midY >= 0 && video.midY <= viewportHeight

                guard visibleRatio >= 0.55 || (centerIsVisible && visibleHeight >= 160) else {
                    return nil
                }

                return (video, abs(video.midY - viewportCenter))
            }
            .min { lhs, rhs in
                lhs.score < rhs.score
            }?
            .video
    }

    private func videoMedia(withId mediaId: String) -> TimelineMedia? {
        for item in filteredItems {
            if let media = item.media.first(where: { $0.id == mediaId && $0.isVideo }) {
                return media
            }
        }

        return nil
    }

    private func stopVideoAutoplay() {
        videoAutoplayTask?.cancel()
        videoAutoplayTask = nil
        videoAutoplayCandidateMediaId = nil
        videoAutoplayCenter.stop()
    }
}

private enum TimelineContentFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case photos
    case audio
    case video

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            return "All Moments"
        case .text:
            return "Text"
        case .photos:
            return "With Photos"
        case .audio:
            return "Audio"
        case .video:
            return "Video"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "rectangle.stack"
        case .text:
            return "text.alignleft"
        case .photos:
            return "photo.on.rectangle"
        case .audio:
            return "waveform"
        case .video:
            return "video"
        }
    }

    func includes(_ item: TimelineItem) -> Bool {
        switch self {
        case .all:
            return true
        case .text:
            return !item.post.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .photos:
            return item.media.contains { $0.isImage }
        case .audio:
            return item.media.contains { $0.isAudio }
        case .video:
            return item.media.contains { $0.isVideo }
        }
    }
}

private enum TimelineMatchSourceFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case comments
    case summary
    case transcript

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            return "Any Match"
        case .text:
            return "Post Text"
        case .comments:
            return "Comments"
        case .summary:
            return "Summary"
        case .transcript:
            return "Transcript"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "magnifyingglass"
        case .text:
            return TimelineSearchMatchSource.text.systemImage
        case .comments:
            return TimelineSearchMatchSource.comments.systemImage
        case .summary:
            return TimelineSearchMatchSource.summary.systemImage
        case .transcript:
            return TimelineSearchMatchSource.transcript.systemImage
        }
    }

    func includes(_ result: TimelineSearchResult) -> Bool {
        switch self {
        case .all:
            return true
        case .text:
            return result.includes(.text)
        case .comments:
            return result.includes(.comments)
        case .summary:
            return result.includes(.summary)
        case .transcript:
            return result.includes(.transcript)
        }
    }
}

private struct TimelineMonthFilter: Equatable {
    let monthStart: Date
    let title: String

    var id: String {
        String(Int(monthStart.timeIntervalSince1970))
    }
}

private struct TimelineFilterChip: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let onRemove: () -> Void
}

private struct TimelineActiveFilterBar: View {
    let chips: [TimelineFilterChip]
    let onClearAll: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Button {
                        chip.onRemove()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: chip.systemImage)
                            Text(chip.title)
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(chip.title) filter")
                }

                if !chips.isEmpty {
                    Button("Clear") {
                        onClearAll()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear filters")
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }
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

private struct TimelineDateJumpRequest: Equatable {
    let requestID = UUID()
    let targetID: TimelineItem.ID
    var anchor: TimelineScrollAnchor = .top
}

private enum TimelineScrollAnchor: Equatable {
    case top
    case bottom

    var unitPoint: UnitPoint {
        switch self {
        case .top:
            return .top
        case .bottom:
            return .bottom
        }
    }
}

private struct DetailRoute: Identifiable, Hashable {
    let postId: String

    var id: String {
        postId
    }
}

private struct AISummaryRoute: Identifiable, Hashable {
    let mediaId: String

    var id: String {
        mediaId
    }
}

private struct MediaGallery: Identifiable {
    let media: [TimelineMedia]
    let startIndex: Int

    var id: String {
        "\(media.map(\.id).joined(separator: "-"))-\(startIndex)"
    }
}

struct VideoPlayerRoute: Identifiable {
    let media: TimelineMedia

    var id: String {
        media.id
    }
}

struct VideoMomentPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TimelineStore
    @EnvironmentObject private var playbackCenter: MediaPlaybackCenter
    @EnvironmentObject private var videoAutoplayCenter: TimelineVideoAutoplayCenter

    let media: TimelineMedia

    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        videoAutoplayCenter.stop()
                        playbackCenter.stop()
                        player.play()
                    }
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                ContentUnavailableView(
                    "Video unavailable",
                    systemImage: "video.slash",
                    description: Text(errorMessage ?? "Try again after sync finishes.")
                )
                .foregroundStyle(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.45))
                    .padding(18)
            }
            .accessibilityLabel("Close video")
        }
        .task {
            await loadVideo()
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func loadVideo() async {
        do {
            let url = try await store.localPlayableURL(for: media)
            await MainActor.run {
                player = AVPlayer(url: url)
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
