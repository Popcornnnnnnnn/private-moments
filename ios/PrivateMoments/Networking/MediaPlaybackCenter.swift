import AVFoundation
import Foundation

@MainActor
final class MediaPlaybackCenter: ObservableObject {
    @Published private(set) var activeMediaId: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var playbackRate: Float = 1

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var playbackFinishedObserver: NSObjectProtocol?

    func toggle(media: TimelineMedia, url: URL) {
        if activeMediaId == media.id {
            isPlaying ? pause() : playCurrent()
            return
        }

        stop()
        configureAudioSession()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        activeMediaId = media.id
        currentTime = savedProgress(for: media.id)
        duration = media.durationSeconds ?? 0

        if currentTime > 0 {
            player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
        }

        addTimeObserver(mediaId: media.id)
        addPlaybackFinishedObserver(for: item, mediaId: media.id)
        playCurrent()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        saveProgress()
    }

    func stop() {
        stop(preservingProgress: true)
    }

    private func stop(preservingProgress: Bool) {
        if preservingProgress {
            saveProgress()
        } else if let activeMediaId {
            clearProgress(for: activeMediaId)
        }

        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        removePlaybackFinishedObserver()

        player?.pause()
        player = nil
        timeObserver = nil
        activeMediaId = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        saveProgress()
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
    }

    private func playCurrent() {
        configureAudioSession()
        player?.rate = playbackRate
        isPlaying = true
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func addTimeObserver(mediaId: String) {
        guard let player else {
            return
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, self.activeMediaId == mediaId else { return }
                self.currentTime = CMTimeGetSeconds(time)
                if let itemDuration = self.player?.currentItem?.duration {
                    let seconds = CMTimeGetSeconds(itemDuration)
                    if seconds.isFinite {
                        self.duration = seconds
                    }
                }
                self.saveProgress()
            }
        }
    }

    private func addPlaybackFinishedObserver(for item: AVPlayerItem, mediaId: String) {
        removePlaybackFinishedObserver()
        playbackFinishedObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.finishPlayback(mediaId: mediaId)
            }
        }
    }

    private func finishPlayback(mediaId: String) {
        guard activeMediaId == mediaId else {
            return
        }

        stop(preservingProgress: false)
    }

    private func removePlaybackFinishedObserver() {
        if let playbackFinishedObserver {
            NotificationCenter.default.removeObserver(playbackFinishedObserver)
        }
        playbackFinishedObserver = nil
    }

    private func saveProgress() {
        guard let activeMediaId else {
            return
        }

        UserDefaults.standard.set(currentTime, forKey: progressKey(activeMediaId))
    }

    private func clearProgress(for mediaId: String) {
        UserDefaults.standard.removeObject(forKey: progressKey(mediaId))
    }

    private func savedProgress(for mediaId: String) -> Double {
        UserDefaults.standard.double(forKey: progressKey(mediaId))
    }

    private func progressKey(_ mediaId: String) -> String {
        "audio.progress.\(mediaId)"
    }
}

@MainActor
final class TimelineVideoAutoplayCenter: ObservableObject {
    @Published private(set) var activeMediaId: String?
    @Published private(set) var player: AVPlayer?

    private var playbackFinishedObserver: NSObjectProtocol?

    func play(media: TimelineMedia, url: URL) {
        if activeMediaId == media.id {
            player?.play()
            return
        }

        stop()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none

        self.player = player
        activeMediaId = media.id
        addLoopObserver(for: item, mediaId: media.id)
        player.play()
    }

    func stop() {
        removePlaybackFinishedObserver()
        player?.pause()
        player = nil
        activeMediaId = nil
    }

    private func addLoopObserver(for item: AVPlayerItem, mediaId: String) {
        removePlaybackFinishedObserver()
        playbackFinishedObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.activeMediaId == mediaId else {
                    return
                }

                self.player?.seek(to: .zero)
                self.player?.play()
            }
        }
    }

    private func removePlaybackFinishedObserver() {
        if let playbackFinishedObserver {
            NotificationCenter.default.removeObserver(playbackFinishedObserver)
        }
        playbackFinishedObserver = nil
    }
}
