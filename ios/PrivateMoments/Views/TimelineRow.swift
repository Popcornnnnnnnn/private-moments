import AVFoundation
import SwiftUI
import UIKit

struct TimelineRow: View {
    let item: TimelineItem
    let isCommentsExpanded: Bool
    let searchQuery: String
    let relativeTimeNow: Date
    let aiSummaryRequestMediaIDs: Set<String>
    let searchResult: TimelineSearchResult?
    let onOpenMedia: ([TimelineMedia], Int) -> Void
    let onOpenDetail: () -> Void
    let onComment: () -> Void
    let onToggleComments: () -> Void
    let onDeleteComment: (TimelineComment) -> Void
    let onOpenSummary: (TimelineMedia) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(MomentDateFormatter.timelineLabel(for: item.post.occurredAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if item.post.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Favorite")
                }
                SyncBadge(status: item.post.syncStatus)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onOpenDetail()
            }

            if !item.post.text.isEmpty {
                Text(item.post.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onOpenDetail()
                    }
            }

            if !item.media.isEmpty {
                if let media = item.media.first, media.isAudio {
                    TimelineAudioCard(media: media)
                } else if let media = item.media.first, media.isVideo {
                    Button {
                        onOpenMedia(item.media, 0)
                    } label: {
                        TimelineVideoCard(media: media)
                            .background {
                                TimelineVideoVisibilityReader(mediaId: media.id)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open video")
                } else if item.media.count == 1, let media = item.media.first {
                    Button {
                        onOpenMedia(item.media, 0)
                    } label: {
                        TimelineImage(media: media, style: .single)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open image")
                } else {
                    LazyVGrid(columns: imageColumns, spacing: 6) {
                        ForEach(Array(item.media.enumerated()), id: \.element.id) { index, media in
                            Button {
                                onOpenMedia(item.media, index)
                            } label: {
                                TimelineImage(media: media, style: .grid)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open image \(index + 1)")
                        }
                    }
                }
            }

            if let searchResult, searchResult.isMatch {
                TimelineSearchMatchBadges(sources: searchResult.sources)
            }

            HStack(spacing: 10) {
                if let media = summaryControlMedia,
                   let state = aiSummaryControlState(for: media) {
                    TimelineAISummaryControl(
                        media: media,
                        state: state,
                        onOpenSummary: onOpenSummary
                    )
                }

                Spacer(minLength: 0)

                Button {
                    onComment()
                } label: {
                    TimelineCommentButtonContent(commentCount: item.comments.count)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(commentAccessibilityLabel)
            }
            .frame(maxWidth: .infinity)

            TimelineCommentsSection(
                comments: item.comments,
                isExpanded: isCommentsExpanded,
                searchQuery: searchQuery,
                now: relativeTimeNow,
                onToggleExpanded: onToggleComments,
                onDeleteRequest: onDeleteComment
            )
        }
        .padding(.vertical, 4)
    }

    private var commentAccessibilityLabel: String {
        if item.comments.isEmpty {
            return "Add comment"
        }

        return "Comment, \(item.comments.count)"
    }

    private var imageColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: item.media.count == 1 ? 1 : 3)
    }

    private var summaryControlMedia: TimelineMedia? {
        item.media.first { media in
            (media.isAudio || media.isVideo) && aiSummaryControlState(for: media) != nil
        }
    }

    private func aiSummaryControlState(for media: TimelineMedia) -> TimelineAISummaryControlState? {
        let summary = aiSummary(for: media)
        if aiSummaryRequestMediaIDs.contains(media.id) || (summary?.isSummarizing == true && summary?.hasDisplayContent == true) {
            return .regenerating
        }

        if summary?.isFailed == true {
            return .failed
        }

        if summary?.isReady == true || summary?.hasDisplayContent == true {
            return .ready
        }

        return nil
    }

    private func aiSummary(for media: TimelineMedia) -> TimelineAISummary? {
        item.aiSummaries.first { $0.mediaId == media.id && $0.deletedAt == nil }
    }
}

private enum TimelineAISummaryControlState {
    case ready
    case regenerating
    case failed

    var title: String {
        switch self {
        case .ready:
            return "Summary ready"
        case .regenerating:
            return "Regenerating"
        case .failed:
            return "Summary failed"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .ready:
            return "Summary ready"
        case .regenerating:
            return "Summary regenerating"
        case .failed:
            return "Summary failed"
        }
    }
}

private struct TimelineSearchMatchBadges: View {
    let sources: Set<TimelineSearchMatchSource>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TimelineSearchMatchSource.allCases.filter { sources.contains($0) }) { source in
                    Label(source.badgeTitle, systemImage: source.systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Color.secondary.opacity(0.08), in: Capsule())
                }
            }
        }
        .scrollClipDisabled()
        .accessibilityLabel("Search match sources")
    }
}

private struct TimelineCommentButtonContent: View {
    let commentCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.and.pencil")
                .font(.caption.weight(.semibold))

            if commentCount > 0 {
                Text("\(commentCount)")
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Color.secondary.opacity(0.08), in: Capsule())
    }
}

private struct TimelineAISummaryControl: View {
    let media: TimelineMedia
    let state: TimelineAISummaryControlState
    let onOpenSummary: (TimelineMedia) -> Void

    var body: some View {
        Button {
            activate()
        } label: {
            HStack(spacing: 7) {
                icon

                Text(state.title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(backgroundStyle, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.accessibilityLabel)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .ready:
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
        case .regenerating:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
        }
    }

    private var foregroundStyle: Color {
        switch state {
        case .ready:
            return Color.accentColor
        case .regenerating:
            return .secondary
        case .failed:
            return .orange
        }
    }

    private var backgroundStyle: Color {
        switch state {
        case .ready:
            return Color.accentColor.opacity(0.11)
        case .regenerating:
            return Color.secondary.opacity(0.08)
        case .failed:
            return Color.orange.opacity(0.12)
        }
    }

    private func activate() {
        onOpenSummary(media)
    }
}

struct TimelineVideoCard: View {
    @EnvironmentObject private var videoAutoplayCenter: TimelineVideoAutoplayCenter

    let media: TimelineMedia

    var body: some View {
        ZStack {
            TimelineImage(media: media, style: .single)

            if isAutoplaying, let player = videoAutoplayCenter.player {
                InlineMutedVideoPlayer(player: player)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if isAutoplaying {
                Image(systemName: "speaker.slash.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(.black.opacity(0.42), in: Circle())
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity)
            } else {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.32))
            }

            if let duration = media.durationSeconds {
                Text(mediaDurationLabel(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.46), in: Capsule())
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .animation(.easeInOut(duration: 0.18), value: isAutoplaying)
    }

    private var isAutoplaying: Bool {
        videoAutoplayCenter.activeMediaId == media.id
    }
}

struct TimelineAudioCard: View {
    @EnvironmentObject private var store: TimelineStore
    @EnvironmentObject private var playbackCenter: MediaPlaybackCenter
    @EnvironmentObject private var videoAutoplayCenter: TimelineVideoAutoplayCenter

    let media: TimelineMedia

    @State private var isLoading = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                togglePlayback()
            } label: {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isActive && playbackCenter.isPlaying ? "pause.fill" : "play.fill")
                        .font(.caption.weight(.bold))
                }
            }
            .frame(width: 34, height: 34)
            .background(Color.accentColor.opacity(0.14), in: Circle())
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityLabel(isActive && playbackCenter.isPlaying ? "Pause audio" : "Play audio")

            VStack(alignment: .leading, spacing: 3) {
                Slider(
                    value: Binding(
                        get: { isActive ? playbackCenter.currentTime : 0 },
                        set: { playbackCenter.seek(to: $0) }
                    ),
                    in: 0...sliderDuration
                )
                .disabled(!isActive)

                Text(timeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Menu {
                ForEach([Float(1), Float(1.5), Float(2)], id: \.self) { rate in
                    Button("\(rate.formatted(.number.precision(.fractionLength(rate == 1 ? 0 : 1))))x") {
                        playbackCenter.setRate(rate)
                    }
                }
            } label: {
                Text("\(playbackCenter.playbackRate.formatted(.number.precision(.fractionLength(playbackCenter.playbackRate == 1 ? 0 : 1))))x")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 28)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 5)
    }

    private var isActive: Bool {
        playbackCenter.activeMediaId == media.id
    }

    private var timeLabel: String {
        let current = isActive ? playbackCenter.currentTime : 0
        let duration = isActive ? max(playbackCenter.duration, media.durationSeconds ?? 0) : (media.durationSeconds ?? 0)
        return "\(mediaDurationLabel(current)) / \(mediaDurationLabel(duration))"
    }

    private var sliderDuration: Double {
        if isActive {
            return max(playbackCenter.duration, media.durationSeconds ?? 1, 1)
        }

        return max(media.durationSeconds ?? 1, 1)
    }

    private func togglePlayback() {
        isLoading = true
        Task {
            do {
                let url = try await store.localPlayableURL(for: media)
                await MainActor.run {
                    videoAutoplayCenter.stop()
                    playbackCenter.toggle(media: media, url: url)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    store.errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

struct TimelineVideoVisibilityValue: Equatable {
    let mediaId: String
    let minY: CGFloat
    let midY: CGFloat
    let height: CGFloat
}

struct TimelineVideoVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: [TimelineVideoVisibilityValue] = []

    static func reduce(
        value: inout [TimelineVideoVisibilityValue],
        nextValue: () -> [TimelineVideoVisibilityValue]
    ) {
        value.append(contentsOf: nextValue())
    }
}

private struct TimelineVideoVisibilityReader: View {
    let mediaId: String

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named("timelineList"))
            Color.clear.preference(
                key: TimelineVideoVisibilityPreferenceKey.self,
                value: [
                    TimelineVideoVisibilityValue(
                        mediaId: mediaId,
                        minY: frame.minY,
                        midY: frame.midY,
                        height: frame.height
                    ),
                ]
            )
        }
    }
}

private struct InlineMutedVideoPlayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> InlineVideoPlayerView {
        let view = InlineVideoPlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: InlineVideoPlayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class InlineVideoPlayerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

enum TimelineImageStyle {
    case single
    case grid
}

struct TimelineImage: View {
    let media: TimelineMedia
    let style: TimelineImageStyle

    var body: some View {
        Group {
            switch style {
            case .single:
                singleImage
            case .grid:
                gridImage
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var singleImage: some View {
        if let image = UIImage(contentsOfFile: media.localDisplayImagePath) {
            let aspectRatio = image.size.width / max(image.size.height, 1)

            Image(uiImage: image)
                .resizable()
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
        } else {
            ZStack {
                Color(.secondarySystemBackground)
                PlaceholderImage()
            }
            .frame(maxWidth: .infinity, minHeight: 160)
        }
    }

    private var gridImage: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.secondarySystemBackground)

                if let image = UIImage(contentsOfFile: media.localDisplayImagePath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    PlaceholderImage()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct PlaceholderImage: View {
    var body: some View {
        Image(systemName: "photo")
            .font(.title2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SyncBadge: View {
    let status: String

    var body: some View {
        Text(status)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch status {
        case "synced":
            return Color.green.opacity(0.16)
        case "failed":
            return Color.red.opacity(0.16)
        case "partial":
            return Color.blue.opacity(0.16)
        default:
            return Color.orange.opacity(0.16)
        }
    }

    private var foreground: Color {
        switch status {
        case "synced":
            return Color.green
        case "failed":
            return Color.red
        case "partial":
            return Color.blue
        default:
            return Color.orange
        }
    }
}
