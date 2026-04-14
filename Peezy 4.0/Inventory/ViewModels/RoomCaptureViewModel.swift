import AVFoundation
import AudioToolbox
import UIKit

@Observable
final class RoomCaptureViewModel: NSObject {
    var isRecording = false
    var recordingDuration: TimeInterval = 0
    var permissionGranted = false
    var permissionDenied = false
    var isProcessingFrames = false
    var extractedFrames: [ExtractedFrame] = []
    var error: String?
    var playPacingAudio = true

    private(set) var captureSession: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var tempVideoURL: URL?
    private var recordingTimer: Timer?
    private var hapticTimer: Timer?
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)
    private let frameService = FrameExtractionService()
    private var recordingContinuation: CheckedContinuation<URL, Error>?

    func requestPermissions() async {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

        var cameraGranted = cameraStatus == .authorized

        if cameraStatus == .notDetermined {
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        }

        if cameraGranted {
            permissionGranted = true
            permissionDenied = false
        } else {
            permissionGranted = false
            permissionDenied = true
        }
    }

    func setupCaptureSession() throws {
        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CaptureError.noCameraAvailable
        }

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        guard session.canAddInput(videoInput) else {
            throw CaptureError.cannotAddInput
        }
        session.addInput(videoInput)

        let output = AVCaptureMovieFileOutput()
        guard session.canAddOutput(output) else {
            throw CaptureError.cannotAddOutput
        }
        session.addOutput(output)

        captureSession = session
        movieOutput = output

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func startRecording() {
        guard let movieOutput = movieOutput, !isRecording else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "peezy_room_\(UUID().uuidString).mp4"
        let fileURL = tempDir.appendingPathComponent(fileName)
        tempVideoURL = fileURL

        isRecording = true
        recordingDuration = 0
        error = nil

        hapticGenerator.prepare()

        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.recordingDuration += 1.0
        }

        hapticTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.hapticGenerator.impactOccurred()
            if self?.playPacingAudio == true {
                AudioServicesPlaySystemSound(1057)
            }
        }

        movieOutput.startRecording(to: fileURL, recordingDelegate: self)
    }

    func stopRecording() async {
        guard let movieOutput = movieOutput, isRecording else { return }

        recordingTimer?.invalidate()
        recordingTimer = nil
        hapticTimer?.invalidate()
        hapticTimer = nil

        isProcessingFrames = true

        do {
            let videoURL: URL = try await withCheckedThrowingContinuation { continuation in
                self.recordingContinuation = continuation
                movieOutput.stopRecording()
            }

            let frames = try await frameService.extractFrames(from: videoURL)
            isRecording = false
            isProcessingFrames = false
            extractedFrames = frames
        } catch {
            self.error = error.localizedDescription
            isRecording = false
            isProcessingFrames = false
        }
    }

    func cleanup() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        hapticTimer?.invalidate()
        hapticTimer = nil

        captureSession?.stopRunning()
        captureSession = nil
        movieOutput = nil

        if let tempURL = tempVideoURL {
            try? FileManager.default.removeItem(at: tempURL)
            tempVideoURL = nil
        }

        extractedFrames = []
        error = nil
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension RoomCaptureViewModel: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        if let error = error {
            recordingContinuation?.resume(throwing: error)
        } else {
            recordingContinuation?.resume(returning: outputFileURL)
        }
        recordingContinuation = nil
    }
}

// MARK: - Errors

enum CaptureError: LocalizedError {
    case noCameraAvailable
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable: return "No camera available on this device"
        case .cannotAddInput: return "Cannot configure camera input"
        case .cannotAddOutput: return "Cannot configure video recording output"
        }
    }
}
