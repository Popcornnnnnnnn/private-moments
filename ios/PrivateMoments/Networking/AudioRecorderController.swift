import AVFoundation
import Foundation

@MainActor
final class AudioRecorderController: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var recordedURL: URL?
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private let maxDurationSeconds: TimeInterval = 60 * 60

    var hasRecording: Bool {
        recordedURL != nil
    }

    func start() {
        guard !isRecording else {
            return
        }

        requestRecordPermission { [weak self] isGranted in
            Task { @MainActor in
                guard let self else { return }
                guard isGranted else {
                    self.errorMessage = "Microphone access is required to record audio."
                    return
                }

                self.startRecordingAfterPermission()
            }
        }
    }

    func pauseOrResume() {
        guard let recorder, isRecording else {
            return
        }

        if isPaused {
            recorder.record()
            isPaused = false
            startTimer()
        } else {
            recorder.pause()
            isPaused = true
            stopTimer()
        }
    }

    func stop() {
        guard isRecording else {
            return
        }

        recorder?.stop()
        finishRecording()
    }

    func refreshElapsedTime() {
        guard isRecording else {
            return
        }

        elapsedSeconds = recorder?.currentTime ?? elapsedSeconds
    }

    func discard() {
        stopTimer()
        recorder?.stop()
        recorder = nil
        isRecording = false
        isPaused = false
        elapsedSeconds = 0

        if let recordedURL {
            try? FileManager.default.removeItem(at: recordedURL)
        }
        recordedURL = nil
    }

    private func startRecordingAfterPermission() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let directory = try AppDirectories.draftMediaDirectory()
            let url = directory.appending(path: "composer-audio-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = false
            recorder.prepareToRecord()
            let didStart = recorder.record(forDuration: maxDurationSeconds)
            guard didStart else {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                try? FileManager.default.removeItem(at: url)
                errorMessage = "Audio recording could not start."
                return
            }

            self.recorder = recorder
            recordedURL = url
            isRecording = true
            isPaused = false
            elapsedSeconds = 0
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestRecordPermission(_ completion: @escaping @Sendable (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: completion)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(completion)
        }
    }

    private func finishRecording() {
        stopTimer()
        recorder = nil
        isRecording = false
        isPaused = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsedSeconds = self.recorder?.currentTime ?? self.elapsedSeconds
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            finishRecording()
            if !flag {
                errorMessage = "Audio recording stopped unexpectedly."
            }
        }
    }
}
