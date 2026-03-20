import SwiftUI

struct InventoryFlowView: View {
    @State private var sessionManager = InventorySessionManager()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            switch sessionManager.state {
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
        }
        .animation(PeezyTheme.Animation.spring, value: stateKey)
    }

    /// Stable string key for animating state transitions
    private var stateKey: String {
        switch sessionManager.state {
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
