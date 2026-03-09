import SwiftUI
import AVFoundation

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}

    class CameraPreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

// MARK: - Room Capture View

struct RoomCaptureView: View {
    let roomName: String
    let onComplete: ([ExtractedFrame]) -> Void
    let onCancel: () -> Void

    @State private var viewModel = RoomCaptureViewModel()
    @State private var showSettingsAlert = false
    @State private var isRecordButtonPressed = false
    @State private var pacingRingScale: CGFloat = 1.0
    @State private var redDotOpacity: Double = 1.0

    var body: some View {
        ZStack {
            // Camera preview
            if let session = viewModel.captureSession {
                CameraPreviewView(session: session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            // Overlay UI
            VStack {
                topBar
                Spacer()
                bottomControls
            }

            // Processing overlay
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
            if denied {
                showSettingsAlert = true
            }
        }
        .onChange(of: viewModel.extractedFrames.count) { _, count in
            if count > 0 && !viewModel.isProcessingFrames {
                onComplete(viewModel.extractedFrames)
            }
        }
        .onChange(of: viewModel.isRecording) { _, recording in
            if recording {
                startPacingAnimation()
                startRedDotPulse()
            } else {
                pacingRingScale = 1.0
                redDotOpacity = 1.0
            }
        }
        .alert("Camera Access Required", isPresented: $showSettingsAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {
                onCancel()
            }
        } message: {
            Text("Peezy needs camera and microphone access to scan your room. Please enable them in Settings.")
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                viewModel.cleanup()
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(.regularMaterial)
                    .clipShape(Circle())
            }

            Spacer()

            HStack(spacing: 8) {
                if viewModel.isRecording {
                    Circle()
                        .fill(PeezyTheme.Colors.emotionalRed)
                        .frame(width: 8, height: 8)
                        .opacity(redDotOpacity)

                    Text(formattedDuration)
                        .font(PeezyTheme.Typography.calloutMedium)
                        .monospacedDigit()
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                } else {
                    Text(roomName)
                        .font(PeezyTheme.Typography.headline)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .clipShape(Capsule())

            Spacer()

            // Balance the close button width
            Color.clear
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .animation(PeezyTheme.Animation.spring, value: viewModel.isRecording)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            // Record button with pacing ring
            ZStack {
                // Pacing guide ring (visible during recording)
                if viewModel.isRecording {
                    Circle()
                        .stroke(PeezyTheme.Colors.brandYellow.opacity(0.3), lineWidth: 3)
                        .frame(width: 90, height: 90)
                        .scaleEffect(pacingRingScale)
                }

                // Record button
                Button {
                    if viewModel.isRecording {
                        Task {
                            await viewModel.stopRecording()
                        }
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
                                .fill(PeezyTheme.Colors.emotionalRed)
                                .frame(width: 28, height: 28)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Circle()
                                .fill(PeezyTheme.Colors.emotionalRed)
                                .frame(width: 54, height: 54)
                                .scaleEffect(isRecordButtonPressed ? PeezyTheme.Animation.pressScale : 1.0)
                        }
                    }
                    .shadow(color: PeezyTheme.Shadows.cardShadowColor, radius: PeezyTheme.Shadows.cardShadowRadius)
                }
                .disabled(viewModel.isProcessingFrames)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            withAnimation(PeezyTheme.Animation.spring) {
                                isRecordButtonPressed = true
                            }
                        }
                        .onEnded { _ in
                            withAnimation(PeezyTheme.Animation.spring) {
                                isRecordButtonPressed = false
                            }
                        }
                )
            }

            // Hint text
            if !viewModel.isRecording {
                Text("Pan slowly around the room")
                    .font(PeezyTheme.Typography.footnote)
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 40)
        .animation(PeezyTheme.Animation.spring, value: viewModel.isRecording)
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
                    .font(PeezyTheme.Typography.headline)
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
                    .foregroundStyle(PeezyTheme.Colors.warningOrange)

                Text(message)
                    .font(PeezyTheme.Typography.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button("Dismiss") {
                    viewModel.cleanup()
                    onCancel()
                }
                .font(PeezyTheme.Typography.headline)
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

    private func startPacingAnimation() {
        withAnimation(
            PeezyTheme.Animation.spring
                .repeatForever(autoreverses: true)
        ) {
            pacingRingScale = 1.15
        }
    }

    private func startRedDotPulse() {
        withAnimation(
            .easeInOut(duration: 0.75)
            .repeatForever(autoreverses: true)
        ) {
            redDotOpacity = 0.3
        }
    }
}
