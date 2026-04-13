import SwiftUI

struct InventoryFlowView: View {
    @State private var sessionManager = InventorySessionManager()
    @Environment(\.dismiss) private var dismiss

    @State private var showSavedPopup = false
    @State private var savedRoomName = ""
    @State private var savedItemCount = 0

    var body: some View {
        ZStack {
            switch sessionManager.state {
            case .intro:
                ZStack(alignment: .topLeading) {
                    InteractiveBackground()
                        .ignoresSafeArea()

                    TaskFlowTitleCard(
                        taskTitle: "Scan my home",
                        icon: "camera.viewfinder",
                        onContinue: {
                            withAnimation(PeezyTheme.Animation.spring) {
                                sessionManager.state = .info
                            }
                        }
                    )
                    .peezyCardChrome()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    TaskFlowDismissButton(onDismiss: { dismiss() })
                }

            case .info:
                ZStack(alignment: .topLeading) {
                    InteractiveBackground()
                        .ignoresSafeArea()

                    TaskFlowInfoCard(
                        taskTitle: "Scan my home",
                        title: "Here's how it works",
                        bodyText: "Pan your camera slowly around each room. Peezy identifies furniture and belongings in about 20 seconds per room.\n\nOpen closets and cabinets — Peezy catches what you'd forget to mention. Go one room at a time for the best results.",
                        primaryLabel: "Let's go",
                        showBack: true,
                        onPrimary: {
                            withAnimation(PeezyTheme.Animation.spring) {
                                sessionManager.state = .roomList
                            }
                        },
                        onBack: {
                            withAnimation(PeezyTheme.Animation.spring) {
                                sessionManager.state = .intro
                            }
                        }
                    )
                    .peezyCardChrome()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    TaskFlowDismissButton(onDismiss: { dismiss() })
                }

            case .roomList:
                RoomListView(
                    sessionManager: sessionManager,
                    onDismiss: { dismiss() }
                )

            case .enteringRoomName:
                // Handled by RoomListView's sheet — transition back to roomList
                RoomListView(
                    sessionManager: sessionManager,
                    onDismiss: { dismiss() }
                )

            case .scanning(let roomName):
                RoomCaptureView(
                    roomName: roomName,
                    onComplete: { frames in
                        Task {
                            await sessionManager.handleFramesExtracted(frames, roomName: roomName)
                        }
                    },
                    onCancel: {
                        sessionManager.state = .roomList
                    }
                )

            case .processing(_, let progress):
                InventoryProcessingView(progressMessage: progress)

            case .confirming(let roomName, let items, let sessionId):
                if let userId = sessionManager.userId {
                    InventoryConfirmationView(
                        items: items,
                        sessionId: sessionId,
                        userId: userId,
                        onComplete: { updatedItems in
                            sessionManager.handleConfirmationCompleted(updatedItems, roomName: roomName)
                        }
                    )
                }

            case .reviewing(let roomName, let items):
                InventoryReviewView(
                    items: items,
                    roomName: roomName,
                    onConfirm: { confirmedItems in
                        sessionManager.handleReviewConfirmed(confirmedItems, roomName: roomName)
                    },
                    onRescan: {
                        sessionManager.state = .scanning(roomName: roomName)
                    }
                )

            case .estimate:
                InventoryEstimateView(
                    estimate: InventoryEstimator.estimate(from: sessionManager.scannedRooms),
                    onSave: {
                        Task {
                            try? await sessionManager.saveAllToFirestore()
                            dismiss()
                        }
                    },
                    onScanMore: {
                        sessionManager.state = .roomList
                    }
                )
            }

            // Room saved popup overlay
            if showSavedPopup {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { }

                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Color(uiColor: .systemGreen))

                        Text("Room saved!")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)

                        Text("\(savedItemCount) items in \(savedRoomName)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                    }
                    .padding(32)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(PeezyTheme.Animation.spring, value: stateKey)
        .onChange(of: sessionManager.stateDescription) { oldValue, newValue in
            if oldValue.hasPrefix("reviewing") && newValue == "roomList" {
                if let lastRoom = sessionManager.scannedRooms.last {
                    savedRoomName = lastRoom.name
                    savedItemCount = lastRoom.items.count
                    withAnimation(.easeOut(duration: 0.3)) {
                        showSavedPopup = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showSavedPopup = false
                        }
                    }
                }
            }
        }
    }

    /// Stable string key for animating state transitions
    private var stateKey: String {
        switch sessionManager.state {
        case .intro: return "intro"
        case .info: return "info"
        case .roomList: return "roomList"
        case .enteringRoomName: return "enteringRoomName"
        case .scanning(let name): return "scanning-\(name)"
        case .processing(let name, _): return "processing-\(name)"
        case .confirming(let name, _, _): return "confirming-\(name)"
        case .reviewing(let name, _): return "reviewing-\(name)"
        case .estimate: return "estimate"
        }
    }
}
