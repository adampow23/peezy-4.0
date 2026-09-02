import Foundation
import Speech
import AVFoundation
import Observation

/// On-device speech transcription that runs alongside a room scan.
/// Additive-only contract: every failure path resolves to an empty transcript
/// and never surfaces an error to the scan flow.
@Observable
@MainActor
final class NarrationService {

    enum Availability {
        case available
        case unavailable   // no on-device support for current locale/device
    }

    private(set) var isListening = false
    private var accumulated: [String] = []
    private var currentSegment = ""
    private var interruptedThisRecording = false

    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var interruptionObserver: NSObjectProtocol?
    private var activeSegmentID: UUID?
    private var consecutiveEmptyErrorCount = 0

    static let maxTranscriptChars = 4000
    private static let maxEmptyErrorRetries = 1

    /// Whether narration can run at all on this device/locale. Checked before
    /// ever showing the offer card, so we never ask permission for a feature
    /// that cannot work.
    static func availability() -> Availability {
        guard let r = SFSpeechRecognizer(locale: Locale.current),
              r.supportsOnDeviceRecognition else { return .unavailable }
        return .available
    }

    static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized &&
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Serial system asks: Speech first, then microphone. Returns final grant state.
    static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        return mic
    }

    /// Starts listening. Silently no-ops on any failure.
    func start() {
        guard !isListening, Self.isAuthorized,
              let recognizer = SFSpeechRecognizer(locale: Locale.current),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition
        else { return }

        accumulated = []
        currentSegment = ""
        activeSegmentID = nil
        consecutiveEmptyErrorCount = 0
        interruptedThisRecording = false
        self.recognizer = recognizer

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .measurement,
                                    options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true, options: [])
        } catch { return }

        observeInterruptions()
        guard beginRecognitionSegment() else {
            removeInterruptionObserver()
            stopEngine()
            deactivateAudioSession()
            return
        }
        isListening = true
    }

    /// Stops listening and returns the full transcript for this recording,
    /// or nil if nothing usable was heard.
    func stopAndSnapshot() -> String? {
        isListening = false
        finishSegment()
        removeInterruptionObserver()
        stopEngine()
        deactivateAudioSession()

        let joined = (accumulated + [currentSegment])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        accumulated = []
        currentSegment = ""
        guard !joined.isEmpty else { return nil }
        return String(joined.prefix(Self.maxTranscriptChars))
    }

    // MARK: - Recognition segments

    /// One SFSpeechRecognitionTask segment. On-device tasks can end on their
    /// own (~1 minute); if that happens while still listening and not
    /// interrupted, a fresh segment starts and text accumulates.
    private func beginRecognitionSegment() -> Bool {
        guard let recognizer else { return false }
        let engine = audioEngine ?? AVAudioEngine()
        audioEngine = engine

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        request = req
        let segmentID = UUID()
        activeSegmentID = segmentID

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            request = nil
            activeSegmentID = nil
            return false
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch {
                input.removeTap(onBus: 0)
                request = nil
                activeSegmentID = nil
                return false
            }
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.activeSegmentID == segmentID else { return }
                if let result {
                    self.consecutiveEmptyErrorCount = 0
                    self.currentSegment = result.bestTranscription.formattedString
                    if result.isFinal { self.rolloverSegmentIfStillListening() }
                } else if error != nil {
                    self.handleRecognitionError()
                }
            }
        }
        return true
    }

    private func handleRecognitionError() {
        let text = currentSegment.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            consecutiveEmptyErrorCount += 1
            guard consecutiveEmptyErrorCount <= Self.maxEmptyErrorRetries else {
                activeSegmentID = nil
                request?.endAudio()
                task?.cancel()
                request = nil
                task = nil
                isListening = false
                removeInterruptionObserver()
                stopEngine()
                deactivateAudioSession()
                return
            }
        } else {
            consecutiveEmptyErrorCount = 0
        }
        rolloverSegmentIfStillListening()
    }

    private func rolloverSegmentIfStillListening() {
        let text = currentSegment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { accumulated.append(text) }
        currentSegment = ""
        activeSegmentID = nil
        task = nil
        request = nil
        guard isListening, !interruptedThisRecording else {
            isListening = false
            removeInterruptionObserver()
            stopEngine()
            deactivateAudioSession()
            return
        }
        if !beginRecognitionSegment() {
            isListening = false
            removeInterruptionObserver()
            stopEngine()
            deactivateAudioSession()
        }
    }

    private func finishSegment() {
        activeSegmentID = nil
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
    }

    // MARK: - Audio plumbing

    private func stopEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func observeInterruptions() {
        removeInterruptionObserver()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isListening else { return }
                // Phone call / alarm: finalize what we have, do not restart
                // during this recording. Scan continues untouched.
                self.interruptedThisRecording = true
                self.finishSegment()
                self.stopEngine()
                self.deactivateAudioSession()
                self.isListening = false
            }
        }
    }

    private func removeInterruptionObserver() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
    }
}
