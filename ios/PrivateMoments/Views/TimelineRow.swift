import AVFoundation
import SwiftUI
import UIKit

struct TimelineRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let item: TimelineItem
    let isCommentsExpanded: Bool
    let searchQuery: String
    let relativeTimeNow: Date
    let aiSummaryRequestMediaIDs: Set<String>
    let searchResult: TimelineSearchResult?
    let showTagsInTimeline: Bool
    let onOpenMedia: ([TimelineMedia], Int) -> Void
    let onOpenDetail: () -> Void
    let onComment: () -> Void
    let onToggleComments: () -> Void
    let onDeleteComment: (TimelineComment) -> Void
    let onOpenSummary: (TimelineMedia) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(MomentDateFormatter.timelineLabel(for: item.post.occurredAt, language: appLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if showTagsInTimeline, let primaryTag = item.primaryTag {
                    TimelineTagChip(tag: primaryTag.tag, compact: true)
                }
                if item.post.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.yellow)
                        .accessibilityLabel(L10n.t("Favorite", appLanguage))
                }
                if item.post.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(L10n.t("Pinned", appLanguage))
                }
                if item.post.syncStatus != "synced" {
                    SyncBadge(status: item.post.syncStatus)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onOpenDetail()
            }

            if !item.post.text.isEmpty {
                MomentTextView(text: item.post.text, style: .timeline)
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
                    .accessibilityLabel(L10n.t("Open video", appLanguage))
                } else if item.media.count == 1, let media = item.media.first {
                    Button {
                        onOpenMedia(item.media, 0)
                    } label: {
                        TimelineImage(media: media, style: .single)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Open image", appLanguage))
                } else {
                    LazyVGrid(columns: imageColumns, spacing: 6) {
                        ForEach(Array(item.media.enumerated()), id: \.element.id) { index, media in
                            Button {
                                onOpenMedia(item.media, index)
                            } label: {
                                TimelineImage(media: media, style: .grid)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(L10n.t("Open image", appLanguage)) \(index + 1)")
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
            return L10n.t("Add comment", appLanguage)
        }

        return "\(L10n.t("Comment", appLanguage)), \(item.comments.count)"
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

struct TimelineTagChip: View {
    @Environment(\.appLanguage) private var appLanguage

    let tag: TimelineTag
    var compact = false

    var body: some View {
        Text(L10n.tagName(tag, language: appLanguage))
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.primary.opacity(0.78))
            .padding(.horizontal, compact ? 7 : 9)
            .frame(height: compact ? 22 : 26)
            .background(chipColor.opacity(0.34), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(chipColor.opacity(0.48), lineWidth: 0.6)
            )
    }

    private var chipColor: Color {
        Color(hex: tag.colorHex) ?? Color.secondary.opacity(0.22)
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex else {
            return nil
        }

        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6,
              let value = Int(cleaned, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

enum TimelineAISummaryControlState {
    case ready
    case summarizing
    case regenerating
    case failed

    func title(language: AppResolvedLanguage) -> String {
        switch self {
        case .ready:
            return L10n.t("Summary ready", language)
        case .summarizing:
            return L10n.t("Summarizing", language)
        case .regenerating:
            return L10n.t("Regenerating", language)
        case .failed:
            return L10n.t("Summary failed", language)
        }
    }

    func accessibilityLabel(language: AppResolvedLanguage) -> String {
        switch self {
        case .ready:
            return L10n.t("Summary ready", language)
        case .summarizing:
            return L10n.t("Summarizing", language)
        case .regenerating:
            return L10n.t("Summary regenerating", language)
        case .failed:
            return L10n.t("Summary failed", language)
        }
    }
}

private struct TimelineSearchMatchBadges: View {
    @Environment(\.appLanguage) private var appLanguage

    let sources: Set<TimelineSearchMatchSource>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TimelineSearchMatchSource.allCases.filter { sources.contains($0) }) { source in
                    Label(source.badgeTitle(language: appLanguage), systemImage: source.systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Color.secondary.opacity(0.08), in: Capsule())
                }
            }
        }
        .scrollClipDisabled()
        .accessibilityLabel(L10n.t("Search match sources", appLanguage))
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

struct TimelineAISummaryControl: View {
    @Environment(\.appLanguage) private var appLanguage

    let media: TimelineMedia
    let state: TimelineAISummaryControlState
    let onOpenSummary: (TimelineMedia) -> Void

    var body: some View {
        Button {
            activate()
        } label: {
            HStack(spacing: 7) {
                icon

                Text(state.title(language: appLanguage))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(backgroundStyle, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.accessibilityLabel(language: appLanguage))
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .ready:
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
        case .summarizing, .regenerating:
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
        case .summarizing, .regenerating:
            return .secondary
        case .failed:
            return .orange
        }
    }

    private var backgroundStyle: Color {
        switch state {
        case .ready:
            return Color.accentColor.opacity(0.11)
        case .summarizing, .regenerating:
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

enum TimelineAudioCardStyle {
    case compact
    case detail

    var buttonSize: CGFloat {
        switch self {
        case .compact:
            return 30
        case .detail:
            return 36
        }
    }

    var waveformHeight: CGFloat {
        switch self {
        case .compact:
            return 28
        case .detail:
            return 36
        }
    }

    var barCount: Int {
        switch self {
        case .compact:
            return 54
        case .detail:
            return 70
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .compact:
            return 14
        case .detail:
            return 16
        }
    }
}

struct TimelineAudioCard: View {
    @EnvironmentObject private var store: TimelineStore
    @EnvironmentObject private var playbackCenter: MediaPlaybackCenter
    @EnvironmentObject private var videoAutoplayCenter: TimelineVideoAutoplayCenter
    @Environment(\.appLanguage) private var appLanguage

    let media: TimelineMedia
    var style: TimelineAudioCardStyle = .compact

    @State private var isLoading = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
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
            .frame(width: style.buttonSize, height: style.buttonSize)
            .background(Color.accentColor.opacity(0.14), in: Circle())
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityLabel(L10n.t(isActive && playbackCenter.isPlaying ? "Pause audio" : "Play audio", appLanguage))

            VStack(alignment: .leading, spacing: 3) {
                AudioWaveformScrubber(
                    mediaId: media.id,
                    progress: progress,
                    duration: sliderDuration,
                    barCount: style.barCount,
                    height: style.waveformHeight,
                    isEnabled: !isLoading,
                    accessibilityLabel: L10n.t("Audio", appLanguage),
                    onToggle: togglePlayback,
                    onSeek: seekOrStart
                )

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
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.065), in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
    }

    private var isActive: Bool {
        playbackCenter.activeMediaId == media.id
    }

    private var timeLabel: String {
        let duration = isActive ? max(playbackCenter.duration, media.durationSeconds ?? 0) : (media.durationSeconds ?? 0)
        guard isActive else {
            return mediaDurationLabel(duration)
        }

        let current = playbackCenter.currentTime
        return "\(mediaDurationLabel(current)) / \(mediaDurationLabel(duration))"
    }

    private var sliderDuration: Double {
        if isActive {
            return max(playbackCenter.duration, media.durationSeconds ?? 1, 1)
        }

        return max(media.durationSeconds ?? 1, 1)
    }

    private var progress: Double {
        guard isActive else {
            return 0
        }

        let duration = sliderDuration
        guard duration > 0 else {
            return 0
        }

        return min(max(playbackCenter.currentTime / duration, 0), 1)
    }

    private func togglePlayback() {
        if playbackCenter.toggleActive(mediaId: media.id) {
            return
        }

        loadAndPlay(seekTo: nil)
    }

    private func seekOrStart(to seconds: Double) {
        if isActive {
            playbackCenter.seek(to: seconds)
        } else if !isLoading {
            loadAndPlay(seekTo: seconds)
        }
    }

    private func loadAndPlay(seekTo seconds: Double?) {
        isLoading = true
        Task {
            do {
                let url = try await store.localPlayableURL(for: media)
                await MainActor.run {
                    videoAutoplayCenter.stop()
                    if let seconds {
                        playbackCenter.play(media: media, url: url, startAt: seconds)
                    } else {
                        playbackCenter.toggle(media: media, url: url)
                    }
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

private struct AudioWaveformScrubber: View {
    let mediaId: String
    let progress: Double
    let duration: Double
    let barCount: Int
    let height: CGFloat
    let isEnabled: Bool
    let accessibilityLabel: String
    let onToggle: () -> Void
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let bars = AudioWaveformPattern.values(for: mediaId, count: barCount)
            HStack(alignment: .center, spacing: 1) {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, value in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(barColor(index: index, count: bars.count))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(3, height * value))
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled, isScrub(value) else {
                            return
                        }
                        onSeek(seconds(for: value.location.x, width: width))
                    }
                    .onEnded { value in
                        guard isEnabled else {
                            return
                        }

                        if isScrub(value) {
                            onSeek(seconds(for: value.location.x, width: width))
                        } else {
                            onToggle()
                        }
                    }
            )
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func barColor(index: Int, count: Int) -> Color {
        let cutoff = progress * Double(max(count - 1, 1))
        if Double(index) <= cutoff {
            return Color.accentColor.opacity(0.82)
        }

        return Color.secondary.opacity(0.26)
    }

    private func isScrub(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > 4 || abs(value.translation.height) > 4
    }

    private func seconds(for x: CGFloat, width: CGFloat) -> Double {
        let clampedX = min(max(x, 0), max(width, 1))
        let progress = clampedX / max(width, 1)
        return Double(progress) * max(duration, 1)
    }
}

private enum AudioWaveformPattern {
    static func values(for seed: String, count: Int) -> [Double] {
        let base = stableSeed(seed)
        return (0..<count).map { index in
            let mixed = sin(Double(base % 97 + index * 17)) + cos(Double(base % 53 + index * 11))
            let normalized = (mixed + 2) / 4
            return 0.28 + normalized * 0.72
        }
    }

    private static func stableSeed(_ seed: String) -> Int {
        seed.unicodeScalars.reduce(0) { partialResult, scalar in
            (partialResult &* 31 &+ Int(scalar.value)) & 0x7fffffff
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
