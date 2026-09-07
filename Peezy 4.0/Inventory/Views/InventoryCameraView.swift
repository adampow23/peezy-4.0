//
//  InventoryCameraView.swift
//  Peezy 4.0
//
//  Camera screen with cinematic viewfinder overlay.
//  Corner reticles frame the shot. Branded top bar shows "peezy · [Room Name]".
//  During recording, reticles breathe, AI scanning status bar pulses.
//  Uses existing RoomCaptureViewModel for all camera logic.
//

import SwiftUI
import AVFoundation
import FirebaseAuth
import UIKit

struct InventoryCameraView: View {
    let roomName: String
    let onComplete: ([ExtractedFrame], String?) -> Void
    let onCancel: () -> Void

    @State private var viewModel = RoomCaptureViewModel()
    @State private var narration = NarrationService()
    @State private var showScanCoaching: Bool
    @State private var showNarrationOffer = false
    /// S4 (S4-CD7): holds only the actor-issued lease; the transcript itself is deposited in `RoomCaptureArtifactOwner`.
    @State private var pendingNarrationTranscript: NarrationLease?
    @Environment(\.roomCaptureArtifactOwner) private var artifactOwner
    @State private var isStoppingRecording = false
    @AppStorage private var narrationOfferSeen: Bool

    private let coachingPreferenceKey: String

    // Animation state
    @State private var isRecordButtonPressed = false
    @State private var reticleScale: CGFloat = 1.0
    @State private var redDotOpacity: Double = 1.0
    @State private var sparkleOpacity: Double = 1.0
    @State private var scanMessageIndex = 0

    private let scanMessages = [
        "Peezy AI is scanning...",
        "Identifying items...",
        "Keep panning slowly..."
    ]

    init(
        roomName: String,
        onComplete: @escaping ([ExtractedFrame], String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.roomName = roomName
        self.onComplete = onComplete
        self.onCancel = onCancel

        let accountID = Auth.auth().currentUser?.uid ?? "anonymous"
        let preferenceKey = "inventory.scanCoaching.seen.\(accountID)"
        coachingPreferenceKey = preferenceKey
        _showScanCoaching = State(
            initialValue: !UserDefaults.standard.bool(forKey: preferenceKey)
        )
        _narrationOfferSeen = AppStorage(
            wrappedValue: false,
            "inventory.narrationOffer.seen.\(accountID)"
        )
    }

    var body: some View {
        ZStack {
            if showScanCoaching {
                InventoryScanCoachingView(onStart: dismissCoaching)
                    .transition(.opacity)
            } else {
                switch viewModel.permissionState {
                case .authorized:
                    authorizedCameraContent
                case .denied, .restricted:
                    cameraPermissionDeniedView
                case .notDetermined:
                    permissionLoadingView
                }
            }
        }
        .onAppear {
            if !showScanCoaching {
                viewModel.checkCameraPermission()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if !showScanCoaching {
                viewModel.checkCameraPermission()
            }
        }
        .onChange(of: showScanCoaching) { _, isShowing in
            if !isShowing {
                viewModel.checkCameraPermission()
            }
        }
        .onChange(of: viewModel.extractedFrames.count) { _, count in
            guard count > 0, !viewModel.isProcessingFrames else { return }
            let lease = pendingNarrationTranscript
            pendingNarrationTranscript = nil
            onComplete(viewModel.extractedFrames, lease?.leaseId)
        }
        .onChange(of: viewModel.isRecording) { _, recording in
            if recording {
                startRecordingAnimations()
            } else {
                stopRecordingAnimations()
            }
        }
        .onDisappear {
            cleanupAndDiscardNarration()
        }
    }

    // MARK: - Authorized Camera Content

    private var authorizedCameraContent: some View {
        ZStack {
            // Layer 1: Camera preview
            cameraLayer

            // Layer 2: Corner reticles
            reticleOverlay

            // Layer 3: Top bar
            VStack {
                topBar
                Spacer()
            }

            // Layer 4: Narration offer + bottom controls
            VStack(spacing: 12) {
                Spacer()

                if showNarrationOffer {
                    NarrationOfferCard(
                        onAccept: acceptNarrationOffer,
                        onDecline: declineNarrationOffer
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                bottomControls
                    .allowsHitTesting(!showNarrationOffer)
                    .accessibilityHidden(showNarrationOffer)
            }

            // Processing overlay (extracting frames after stop)
            if viewModel.isProcessingFrames {
                processingOverlay
            }

            // Error overlay
            if let error = viewModel.error, !viewModel.isProcessingFrames {
                errorOverlay(error)
            }
        }
        .onAppear {
            presentNarrationOfferIfEligible()
        }
    }

    // MARK: - Camera Layer

    @ViewBuilder
    private var cameraLayer: some View {
        if let session = viewModel.captureSession {
            CameraPreviewView(session: session)
                .ignoresSafeArea()
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    // MARK: - Permission States

    private var permissionLoadingView: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            ProgressView()
                .tint(PeezyTheme.Colors.deepInk)
        }
    }

    private var cameraPermissionDeniedView: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "camera.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))

                VStack(spacing: 12) {
                    Text("Camera access needed")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)

                    Text("Peezy uses your camera to scan rooms and identify what you're moving. You can enable access in iOS Settings.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                VStack(spacing: 12) {
                    PeezyAssessmentButton("Open Settings") {
                        openSettings()
                    }

                    Button {
                        onCancel()
                    } label: {
                        Text("Go back")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Corner Reticles

    private var reticleOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let inset: CGFloat = 28
            let arm: CGFloat = 40
            let r: CGFloat = 4

            // All four corners
            ZStack {
                // Top-left
                reticlePath(
                    corner: CGPoint(x: inset, y: inset),
                    hDir: 1, vDir: 1, arm: arm, radius: r
                )
                // Top-right
                reticlePath(
                    corner: CGPoint(x: w - inset, y: inset),
                    hDir: -1, vDir: 1, arm: arm, radius: r
                )
                // Bottom-left
                reticlePath(
                    corner: CGPoint(x: inset, y: h - inset),
                    hDir: 1, vDir: -1, arm: arm, radius: r
                )
                // Bottom-right
                reticlePath(
                    corner: CGPoint(x: w - inset, y: h - inset),
                    hDir: -1, vDir: -1, arm: arm, radius: r
                )
            }
            .scaleEffect(viewModel.isRecording ? reticleScale : 1.0)
        }
        .allowsHitTesting(false)
    }

    private func reticlePath(corner: CGPoint, hDir: CGFloat, vDir: CGFloat, arm: CGFloat, radius: CGFloat) -> some View {
        Path { p in
            // Vertical arm
            p.move(to: CGPoint(x: corner.x, y: corner.y + (arm * vDir)))
            p.addLine(to: CGPoint(x: corner.x, y: corner.y + (radius * vDir)))

            // Corner curve
            p.addQuadCurve(
                to: CGPoint(x: corner.x + (radius * hDir), y: corner.y),
                control: corner
            )

            // Horizontal arm
            p.addLine(to: CGPoint(x: corner.x + (arm * hDir), y: corner.y))
        }
        .stroke(
            PeezyTheme.Colors.deepInk.opacity(0.5),
            style: StrokeStyle(lineWidth: 2, lineCap: .round)
        )
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Close button
            Button {
                cleanupAndDiscardNarration()
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(.regularMaterial)
                    .clipShape(Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close scanner")

            Spacer()

            // Branded capsule
            HStack(spacing: 6) {
                // Red dot (recording only)
                if viewModel.isRecording {
                    Circle()
                        .fill(Color(uiColor: .systemRed))
                        .frame(width: 8, height: 8)
                        .opacity(redDotOpacity)
                }

                // Brand name
                Text("peezy")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.infoBlue)
                    .tracking(0.5)

                Text("·")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))

                // Room name
                Text(roomName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                // Timer (recording only)
                if viewModel.isRecording {
                    Text(formattedDuration)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }

                if narration.isListening {
                    Image(systemName: "mic.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .accessibilityLabel("Peezy is listening")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            Spacer()

            Button {
                showScanCoaching = true
            } label: {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(.regularMaterial)
                    .clipShape(Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(
                viewModel.isRecording
                    || viewModel.isProcessingFrames
                    || showNarrationOffer
            )
            .opacity(
                viewModel.isRecording
                    || viewModel.isProcessingFrames
                    || showNarrationOffer ? 0.4 : 1.0
            )
            .accessibilityLabel("Scanning tips")
            .accessibilityIdentifier("inventory.camera.coaching")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isRecording)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            // AI scanning status bar (recording only)
            if viewModel.isRecording {
                scanningStatusBar
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Record / Stop button
            ZStack {
                // Pacing ring (recording only)
                if viewModel.isRecording {
                    Circle()
                        .stroke(PeezyTheme.Colors.infoBlue.opacity(0.25), lineWidth: 3)
                        .frame(width: 90, height: 90)
                        .scaleEffect(reticleScale)
                }

                Button {
                    handleRecordButtonTapped()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 70, height: 70)

                        if viewModel.isRecording {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(uiColor: .systemRed))
                                .frame(width: 28, height: 28)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Circle()
                                .fill(Color(uiColor: .systemRed))
                                .frame(width: 54, height: 54)
                                .scaleEffect(isRecordButtonPressed ? 0.95 : 1.0)
                        }
                    }
                }
                .disabled(viewModel.isProcessingFrames || isStoppingRecording)
                .accessibilityLabel(
                    viewModel.isRecording ? "Stop recording" : "Start recording"
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                isRecordButtonPressed = true
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                isRecordButtonPressed = false
                            }
                        }
                )
            }

            // Label
            if viewModel.isRecording {
                Text("Stop Recording")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Text("Pan slowly around the room")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 40)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isRecording)
    }

    // MARK: - Scanning Status Bar

    private var scanningStatusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PeezyTheme.Colors.infoBlue)
                .opacity(sparkleOpacity)

            Text(scanMessages[scanMessageIndex])
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .id(scanMessageIndex)
                .transition(.opacity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 40)
    }

    // MARK: - Processing Overlay

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)

                Text("Processing frames...")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Error Overlay

    private func errorOverlay(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color(uiColor: .systemOrange))

                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button("Dismiss") {
                    cleanupAndDiscardNarration()
                    onCancel()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PeezyTheme.Colors.infoBlue)
            }
        }
    }

    // MARK: - Helpers

    private var formattedDuration: String {
        let minutes = Int(viewModel.recordingDuration) / 60
        let seconds = Int(viewModel.recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private func dismissCoaching() {
        UserDefaults.standard.set(true, forKey: coachingPreferenceKey)
        withAnimation(.easeOut(duration: 0.2)) {
            showScanCoaching = false
        }
    }

    private func presentNarrationOfferIfEligible() {
        guard !narrationOfferSeen,
              !showNarrationOffer,
              !NarrationService.isAuthorized,
              !viewModel.isRecording,
              !viewModel.isProcessingFrames,
              viewModel.error == nil
        else { return }
        guard case .available = NarrationService.availability() else { return }

        withAnimation(.easeOut(duration: 0.25)) {
            showNarrationOffer = true
        }
    }

    private func acceptNarrationOffer() {
        narrationOfferSeen = true
        withAnimation(.easeOut(duration: 0.2)) {
            showNarrationOffer = false
        }
        Task {
            _ = await NarrationService.requestPermissions()
        }
    }

    private func declineNarrationOffer() {
        narrationOfferSeen = true
        withAnimation(.easeOut(duration: 0.2)) {
            showNarrationOffer = false
        }
    }

    private func handleRecordButtonTapped() {
        if viewModel.isRecording {
            guard !isStoppingRecording else { return }
            isStoppingRecording = true
            Task {
                await viewModel.stopRecording()
                isStoppingRecording = false
            }
            let transcript = narration.stopAndSnapshot()
            if let lease = pendingNarrationTranscript, let transcript, let owner = artifactOwner {
                Task { _ = await owner.deposit(transcript, for: lease) } // dropped when the lease no longer revalidates
            }
        } else {
            viewModel.startRecording()
            guard viewModel.isRecording else { return }
            pendingNarrationTranscript = nil
            guard let owner = artifactOwner, let uid = Auth.auth().currentUser?.uid else { return } // no owner or user: no lease, no narration
            let sessionId = roomName
            Task { @MainActor in
                guard let lease = await owner.acquire(uid: uid, sessionId: sessionId) else { return }
                // the recording may have stopped or the frames may already be extracting during the actor hop: release, never start
                guard viewModel.isRecording, !isStoppingRecording, !viewModel.isProcessingFrames, pendingNarrationTranscript == nil else {
                    await owner.release(lease)
                    return
                }
                pendingNarrationTranscript = lease
                narration.start(lease: lease, revocation: await owner.narrationRevocation(for: lease))
            }
        }
    }

    private func cleanupAndDiscardNarration() {
        viewModel.cleanup()
        _ = narration.stopAndSnapshot()
        if let lease = pendingNarrationTranscript, let owner = artifactOwner { Task { await owner.release(lease) } }
        pendingNarrationTranscript = nil
        isStoppingRecording = false
    }

    // MARK: - Animations

    private func startRecordingAnimations() {
        // Reticle breathing
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            reticleScale = 1.02
        }

        // Red dot pulse
        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
            redDotOpacity = 0.3
        }

        // Sparkle pulse
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            sparkleOpacity = 0.5
        }

        // Message cycling
        startMessageCycling()
    }

    private func stopRecordingAnimations() {
        reticleScale = 1.0
        redDotOpacity = 1.0
        sparkleOpacity = 1.0
        scanMessageIndex = 0
    }

    private func startMessageCycling() {
        Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { timer in
            if !viewModel.isRecording {
                timer.invalidate()
                return
            }
            withAnimation(.easeInOut(duration: 0.4)) {
                scanMessageIndex = (scanMessageIndex + 1) % scanMessages.count
            }
        }
    }
}
