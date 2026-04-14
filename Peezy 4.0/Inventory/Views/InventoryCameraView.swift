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

struct InventoryCameraView: View {
    let roomName: String
    let onComplete: ([ExtractedFrame]) -> Void
    let onCancel: () -> Void

    @State private var viewModel = RoomCaptureViewModel()
    @State private var showSettingsAlert = false

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

    var body: some View {
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

            // Layer 4: Bottom controls
            VStack {
                Spacer()
                bottomControls
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
        .task {
            await viewModel.requestPermissions()
            if viewModel.permissionGranted {
                do {
                    try viewModel.setupCaptureSession()
                } catch {
                    viewModel.error = error.localizedDescription
                }
            }
        }
        .onChange(of: viewModel.permissionDenied) { _, denied in
            if denied { showSettingsAlert = true }
        }
        .onChange(of: viewModel.extractedFrames.count) { _, count in
            if count > 0 && !viewModel.isProcessingFrames {
                onComplete(viewModel.extractedFrames)
            }
        }
        .onChange(of: viewModel.isRecording) { _, recording in
            if recording {
                startRecordingAnimations()
            } else {
                stopRecordingAnimations()
            }
        }
        .alert("Camera Access Required", isPresented: $showSettingsAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { onCancel() }
        } message: {
            Text("Peezy needs camera and microphone access to scan your room. Please enable them in Settings.")
        }
        .onDisappear {
            viewModel.cleanup()
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
                viewModel.cleanup()
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(.regularMaterial)
                    .clipShape(Circle())
            }

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
                    .foregroundStyle(PeezyTheme.Colors.brandYellow)
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            Spacer()

            // Balance spacer
            Color.clear
                .frame(width: 36, height: 36)
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
                        .stroke(PeezyTheme.Colors.brandYellow.opacity(0.25), lineWidth: 3)
                        .frame(width: 90, height: 90)
                        .scaleEffect(reticleScale)
                }

                Button {
                    if viewModel.isRecording {
                        Task { await viewModel.stopRecording() }
                    } else {
                        viewModel.startRecording()
                    }
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
                .disabled(viewModel.isProcessingFrames)
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
                .foregroundStyle(PeezyTheme.Colors.brandYellow)
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
                    viewModel.cleanup()
                    onCancel()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PeezyTheme.Colors.brandYellow)
            }
        }
    }

    // MARK: - Helpers

    private var formattedDuration: String {
        let minutes = Int(viewModel.recordingDuration) / 60
        let seconds = Int(viewModel.recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
