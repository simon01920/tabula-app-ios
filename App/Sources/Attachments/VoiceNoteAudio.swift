// Voice-note recording and playback for attachments (stage B3).
// Recording: AVAudioRecorder → AAC (.m4a) in the temporary directory; the attachments section copies the finished file
// into the attachment store and deletes the temporary one. Microphone permission is requested only when the user taps
// Record (`NSMicrophoneUsageDescription` in Config/App-Info.plist).
// APIs: AVAudioApplication.shared.recordPermission + requestRecordPermission(completionHandler:) (iOS 17; handler
//       @Sendable), AVAudioSession.setCategory(.playAndRecord / .playback) + setActive(_:options:),
//       AVAudioRecorder(url:settings:) + record(forDuration:), AVAudioPlayer(contentsOf:) + delegate.
//       Docs checked 2026-10-10 (docs/ENVIRONMENT.md §22).
import AVFoundation
import Foundation
import Observation
import TimetableCore

/// Records one voice note at a time.
@MainActor
@Observable
final class VoiceNoteRecorder {
    enum Failure: Equatable {
        /// Microphone access denied (or restricted).
        case denied
        /// The session or recorder could not start.
        case failed
    }

    /// Why a recording stopped without the user tapping Stop.
    enum AutoStop: Equatable {
        /// The 10-minute cap (`record(forDuration:)`) was reached.
        case limitReached
        /// A phone call, Siri, an alarm or another app took the audio session.
        case interrupted
        /// The encoder failed; what was recorded so far is kept.
        case failed
    }

    /// Longest recording (seconds).
    static let maxDuration: TimeInterval = 600

    private(set) var isRecording = false
    /// The finished (or in-progress) recording's temporary file.
    private(set) var recordedURL: URL?
    private(set) var startedAt: Date?
    private(set) var recordedDuration: TimeInterval = 0
    /// Set when the recording stopped by itself (shown under the timer).
    private(set) var autoStop: AutoStop?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private let delegate = RecorderDelegate()
    // Written once in init, removed in deinit (no other access).
    @ObservationIgnored nonisolated(unsafe) private var interruptionObserver: (any NSObjectProtocol)?

    init() {
        delegate.onFinish = { [weak self] finished, successfully in
            // Only the CURRENT recorder may stop the session: a stopped recorder's late callback (delivered after a new
            // recording started) must not end the new one (B3 QA low finding).
            guard let self, let current = self.recorder, current === finished.recorder else { return }
            self.finishedByItself(successfully ? .limitReached : .failed)
        }
        // Posted on the main thread (AVAudioSession.interruptionNotification docs).
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
            MainActor.assumeIsolated {
                if began { self?.finishedByItself(.interrupted) }
            }
        }
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    /// The recorder stopped on its own (limit, interruption, encoder error): keep the file, show why.
    private func finishedByItself(_ reason: AutoStop) {
        guard isRecording else { return }
        stop()
        autoStop = reason
    }

    /// Starts recording, asking for microphone access first when it was never asked.
    func start() async -> Failure? {
        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            return .denied
        case .undetermined:
            guard await Self.requestPermission() else { return .denied }
        case .granted:
            break
        @unknown default:
            break
        }
        discard()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tabula-voice-\(UUID().uuidString).m4a", isDirectory: false)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = delegate
            autoStop = nil
            guard recorder.record(forDuration: Self.maxDuration) else {
                try? FileManager.default.removeItem(at: url)
                deactivateSession()
                return .failed
            }
            self.recorder = recorder
            recordedURL = url
            startedAt = Date()
            recordedDuration = 0
            isRecording = true
            return nil
        } catch {
            try? FileManager.default.removeItem(at: url)
            deactivateSession()
            return .failed
        }
    }

    /// Stops recording (the file stays until `take()` or `discard()`).
    func stop() {
        guard let recorder else { return }
        recordedDuration = elapsed(at: Date())
        recorder.stop()
        self.recorder = nil
        isRecording = false
        startedAt = nil
        deactivateSession()
    }

    /// Seconds recorded so far (capped at `maxDuration`, where the recorder stops by itself).
    func elapsed(at date: Date) -> TimeInterval {
        guard isRecording, let startedAt else { return recordedDuration }
        return min(max(0, date.timeIntervalSince(startedAt)), Self.maxDuration)
    }

    /// Hands the finished recording over (the caller now owns the temporary file).
    func take() -> URL? {
        stop()
        defer { recordedURL = nil }
        return recordedURL
    }

    /// Stops and deletes the recording.
    func discard() {
        stop()
        if let recordedURL { try? FileManager.default.removeItem(at: recordedURL) }
        recordedURL = nil
        recordedDuration = 0
        autoStop = nil
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated private static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in continuation.resume(returning: granted) }
        }
    }
}

/// Plays one voice note at a time.
@MainActor
@Observable
final class VoiceNotePlayer {
    /// The attachment playing now.
    private(set) var playingID: AttachmentRef.ID?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private let delegate = PlaybackDelegate()

    init() {
        delegate.onFinish = { [weak self] in self?.stop() }
    }

    /// Plays `url` for `id`, or stops when `id` is already playing.
    func toggle(id: AttachmentRef.ID, url: URL) {
        if playingID == id {
            stop()
            return
        }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = delegate
            guard player.play() else { return }
            self.player = player
            playingID = id
        } catch {
            playingID = nil
        }
    }

    func stop() {
        guard player != nil || playingID != nil else { return }
        player?.stop()
        player = nil
        playingID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Duration of an audio file (seconds), read off the main actor.
    nonisolated static func duration(of url: URL) async -> TimeInterval? {
        await Task.detached(priority: .utility) { () -> TimeInterval? in
            (try? AVAudioPlayer(contentsOf: url)).map(\.duration)
        }.value
    }
}

/// The recorder a delegate callback is about. Holds it strongly until the main actor compared it, so the identity check
/// (`===`) can never match a new recorder allocated at a freed one's address.
private final class FinishedRecorder: @unchecked Sendable {
    // Immutable; only compared by identity on the main actor.
    let recorder: AVAudioRecorder
    init(_ recorder: AVAudioRecorder) { self.recorder = recorder }
}

/// AVAudioRecorder's delegate: the recorder finished by itself (time limit) or failed to encode. Reports WHICH recorder
/// finished so the owner can ignore callbacks of recorders it already stopped or replaced.
private final class RecorderDelegate: NSObject, AVAudioRecorderDelegate, @unchecked Sendable {
    // Written once on the main actor before any recording starts; read in the callbacks.
    var onFinish: (@MainActor @Sendable (FinishedRecorder, Bool) -> Void)?

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let finish = onFinish
        let finished = FinishedRecorder(recorder)
        Task { @MainActor in finish?(finished, flag) }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        let finish = onFinish
        let finished = FinishedRecorder(recorder)
        Task { @MainActor in finish?(finished, false) }
    }
}

/// AVAudioPlayer's delegate (callbacks may arrive on any thread; forwarded to the main actor).
private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    // Written once on the main actor before any playback starts; read in the callbacks.
    var onFinish: (@MainActor @Sendable () -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finish = onFinish
        Task { @MainActor in finish?() }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let finish = onFinish
        Task { @MainActor in finish?() }
    }
}
