import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - ViewModel

@Observable
final class InventoryTestHarnessViewModel {
    enum PipelineState: Equatable {
        case idle
        case enterRoomName
        case capturing
        case extractingFrames
        case uploading(progress: Double)
        case processing
        case reviewing(items: [InventoryItem])
        case complete
        case error(String)

        static func == (lhs: PipelineState, rhs: PipelineState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.enterRoomName, .enterRoomName),
                 (.capturing, .capturing),
                 (.extractingFrames, .extractingFrames),
                 (.processing, .processing),
                 (.complete, .complete):
                return true
            case (.uploading(let a), .uploading(let b)):
                return a == b
            case (.reviewing(let a), .reviewing(let b)):
                return a.map(\.id) == b.map(\.id)
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    var state: PipelineState = .idle
    var roomName: String = ""
    var session: InventoryScanSession?

    private let storageService = InventoryStorageService()
    private let apiClient = InventoryAPIClient()
    private var sessionListener: ListenerRegistration?

    func startCapture(roomName: String) {
        self.roomName = roomName
        state = .capturing
    }

    func handleFramesExtracted(_ frames: [ExtractedFrame]) async {
        #if DEBUG
        print("[TestHarness] handleFramesExtracted called with \(frames.count) frames")
        #endif

        guard let userId = Auth.auth().currentUser?.uid else {
            state = .error("Not signed in. Please sign in first.")
            return
        }

        state = .uploading(progress: 0.0)

        do {
            // Upload frames to Firebase Storage
            let uploadedSession = try await storageService.uploadFrames(
                frames,
                userId: userId,
                roomName: roomName
            )
            session = uploadedSession

            #if DEBUG
            print("[TestHarness] Upload done. sessionId=\(uploadedSession.id) frameCount=\(uploadedSession.frameCount)")
            #endif

            guard uploadedSession.frameCount > 0 else {
                state = .error("No frames were uploaded successfully. Check your network connection and try again.")
                return
            }

            state = .processing

            // Trigger Cloud Function
            try await apiClient.processInventory(
                userId: userId,
                sessionId: uploadedSession.id,
                roomName: roomName,
                frameCount: uploadedSession.frameCount
            )

            // Observe Firestore session document for completion
            sessionListener?.remove()
            sessionListener = storageService.observeSession(
                userId: userId,
                sessionId: uploadedSession.id
            ) { [weak self] updatedSession in
                guard let self else { return }
                switch updatedSession.status {
                case .complete:
                    self.sessionListener?.remove()
                    self.sessionListener = nil
                    self.session = updatedSession
                    self.state = .reviewing(items: updatedSession.items)
                case .error:
                    self.sessionListener?.remove()
                    self.sessionListener = nil
                    self.state = .error(updatedSession.errorMessage ?? "Unknown processing error")
                case .uploading, .processing:
                    break
                }
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func handleReviewConfirmed(_ items: [InventoryItem]) {
        state = .complete
        // In Stage 2, this would save finalized items to permanent Firestore location
    }

    func reset() {
        sessionListener?.remove()
        sessionListener = nil
        state = .idle
        roomName = ""
        session = nil
    }
}

// MARK: - Test Harness View

struct InventoryTestHarness: View {
    @State private var viewModel = InventoryTestHarnessViewModel()

    var body: some View {
        ZStack {
            PeezyTheme.Colors.backgroundPrimary
                .ignoresSafeArea()

            switch viewModel.state {
            case .idle, .enterRoomName:
                roomNameEntry

            case .capturing:
                RoomCaptureView(
                    roomName: viewModel.roomName,
                    onComplete: { frames in
                        Task {
                            await viewModel.handleFramesExtracted(frames)
                        }
                    },
                    onCancel: {
                        viewModel.reset()
                    }
                )

            case .extractingFrames:
                extractingView

            case .uploading(let progress):
                uploadingView(progress: progress)

            case .processing:
                processingView

            case .reviewing(let items):
                InventoryReviewView(
                    items: items,
                    roomName: viewModel.roomName,
                    onConfirm: { confirmedItems in
                        viewModel.handleReviewConfirmed(confirmedItems)
                    }
                )

            case .complete:
                completeView

            case .error(let message):
                errorView(message: message)
            }
        }
        .animation(PeezyTheme.Animation.spring, value: viewModel.state)
    }

    // MARK: - Room Name Entry

    private var roomNameEntry: some View {
        VStack(spacing: PeezyTheme.Layout.sectionSpacing) {
            Spacer()

            VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 56))
                    .foregroundStyle(PeezyTheme.Colors.brandYellow)

                Text("Scan a Room")
                    .font(PeezyTheme.Typography.largeTitle)
                    .foregroundStyle(PeezyTheme.Colors.textPrimary)

                Text("Record a slow pan of the room and Peezy will identify your items.")
                    .font(PeezyTheme.Typography.body)
                    .foregroundStyle(PeezyTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
            }

            VStack(spacing: PeezyTheme.Layout.itemSpacing) {
                TextField("Room name (e.g. Living Room)", text: $viewModel.roomName)
                    .font(PeezyTheme.Typography.body)
                    .padding(PeezyTheme.Layout.cardPadding)
                    .background(PeezyTheme.Colors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius))
                    .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)

                Button {
                    let name = viewModel.roomName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    viewModel.startCapture(roomName: name)
                } label: {
                    Text("Start Scan")
                        .font(PeezyTheme.Typography.headline)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .frame(height: PeezyTheme.Layout.buttonHeight)
                        .frame(maxWidth: .infinity)
                        .background(PeezyTheme.Colors.brandYellow)
                        .clipShape(RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius))
                }
                .disabled(viewModel.roomName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(viewModel.roomName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
                .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
            }

            Spacer()
        }
    }

    // MARK: - Extracting Frames

    private var extractingView: some View {
        VStack(spacing: PeezyTheme.Layout.itemSpacing) {
            ProgressView()
                .tint(PeezyTheme.Colors.brandYellow)
                .scaleEffect(1.5)

            Text("Extracting frames...")
                .font(PeezyTheme.Typography.headline)
                .foregroundStyle(PeezyTheme.Colors.textPrimary)
        }
    }

    // MARK: - Uploading

    private func uploadingView(progress: Double) -> some View {
        VStack(spacing: PeezyTheme.Layout.itemSpacing) {
            ProgressView(value: progress)
                .tint(PeezyTheme.Colors.brandYellow)
                .padding(.horizontal, PeezyTheme.Layout.horizontalPadding * 2)

            Text("Uploading frames... \(Int(progress * 100))%")
                .font(PeezyTheme.Typography.headline)
                .foregroundStyle(PeezyTheme.Colors.textPrimary)
                .monospacedDigit()
        }
    }

    // MARK: - Processing (Typewriter)

    private var processingView: some View {
        ProcessingAnimationView()
    }

    // MARK: - Complete

    private var completeView: some View {
        VStack(spacing: PeezyTheme.Layout.sectionSpacing) {
            Spacer()

            VStack(spacing: PeezyTheme.Layout.itemSpacing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(PeezyTheme.Colors.successGreen)

                Text("Scan Complete!")
                    .font(PeezyTheme.Typography.largeTitle)
                    .foregroundStyle(PeezyTheme.Colors.textPrimary)

                if let session = viewModel.session {
                    Text("\(session.items.count) items cataloged in \(session.roomName)")
                        .font(PeezyTheme.Typography.body)
                        .foregroundStyle(PeezyTheme.Colors.textSecondary)
                }
            }

            Button {
                viewModel.reset()
            } label: {
                Text("Scan Another Room")
                    .font(PeezyTheme.Typography.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .frame(height: PeezyTheme.Layout.buttonHeight)
                    .frame(maxWidth: .infinity)
                    .background(PeezyTheme.Colors.brandYellow)
                    .clipShape(RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius))
            }
            .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)

            Spacer()
        }
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: PeezyTheme.Layout.sectionSpacing) {
            Spacer()

            VStack(spacing: PeezyTheme.Layout.itemSpacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(PeezyTheme.Colors.warningOrange)

                Text("Something went wrong")
                    .font(PeezyTheme.Typography.title)
                    .foregroundStyle(PeezyTheme.Colors.textPrimary)

                Text(message)
                    .font(PeezyTheme.Typography.body)
                    .foregroundStyle(PeezyTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
            }

            Button {
                viewModel.reset()
            } label: {
                Text("Try Again")
                    .font(PeezyTheme.Typography.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .frame(height: PeezyTheme.Layout.buttonHeight)
                    .frame(maxWidth: .infinity)
                    .background(PeezyTheme.Colors.brandYellow)
                    .clipShape(RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius))
            }
            .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)

            Spacer()
        }
    }
}

// MARK: - Processing Animation (Typewriter)

private struct ProcessingAnimationView: View {
    private let messages = [
        "Identifying furniture...",
        "Counting items...",
        "Checking for fragile items...",
        "Estimating sizes...",
        "Almost done..."
    ]

    @State private var currentMessageIndex = 0
    @State private var displayedText = ""
    @State private var charIndex = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: PeezyTheme.Layout.sectionSpacing) {
            ProgressView()
                .tint(PeezyTheme.Colors.brandYellow)
                .scaleEffect(1.5)

            VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
                Text("Peezy is scanning your room...")
                    .font(PeezyTheme.Typography.title)
                    .foregroundStyle(PeezyTheme.Colors.textPrimary)

                Text(displayedText)
                    .font(PeezyTheme.Typography.body)
                    .foregroundStyle(PeezyTheme.Colors.textSecondary)
                    .frame(height: 24)
                    .animation(.none, value: displayedText)
            }
        }
        .onAppear {
            startTypewriter()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startTypewriter() {
        displayedText = ""
        charIndex = 0

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { t in
            let currentMessage = messages[currentMessageIndex]
            if charIndex < currentMessage.count {
                let index = currentMessage.index(currentMessage.startIndex, offsetBy: charIndex)
                displayedText += String(currentMessage[index])
                charIndex += 1
            } else {
                // Pause at end of message, then move to next
                t.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    currentMessageIndex = (currentMessageIndex + 1) % messages.count
                    displayedText = ""
                    charIndex = 0
                    startTypewriter()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    InventoryTestHarness()
}
