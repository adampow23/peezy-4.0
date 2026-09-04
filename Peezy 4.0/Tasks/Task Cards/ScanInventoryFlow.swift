//
//  ScanInventoryFlow.swift
//  Peezy 4.0
//

import SwiftUI
import FirebaseFirestore

struct ScanInventoryFlow: View {
    let workflowId = "scan_inventory"

    let userId: String
    let taskId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @State private var didFireCallback = false
    @State private var isCheckingDismiss = false
    @State private var inventoryStatus: InventoryStatus = .loading
    @State private var hasLocalInventoryAnswers = false
    @Environment(FlowExitCoordinator.self) private var exitCoordinator

    private enum InventoryStatus: Equatable {
        case loading
        case submitted
        case draft
        case empty
        case unknown
    }

    var body: some View {
        InventoryFlowView(
            hostingMode: .task,
            onUserDismiss: {
                // User dismissed without submitting.
                guard !didFireCallback, !isCheckingDismiss else { return }
                isCheckingDismiss = true

                // Check once if they actually submitted (edge case: submit -> dismiss happens fast)
                Task {
                    let status = await checkInventoryStatus()
                    await MainActor.run {
                        inventoryStatus = status
                        isCheckingDismiss = false
                        switch status {
                        case .submitted:
                            onComplete()
                        case .draft:
                            exitCoordinator.noteExternallyPersistedAnswer(
                                path: ["inventory"],
                                answers: ["inventory": ["draft"]]
                            )
                            onDismiss()
                        case .loading, .empty, .unknown:
                            onDismiss()
                        }
                    }
                }
            },
            onSubmitted: {
                // User completed submission flow - fire onComplete directly
                guard !didFireCallback else { return }
                didFireCallback = true
                onComplete()
            },
            onLater: {
                guard !didFireCallback else { return }
                didFireCallback = true
                onStatusAction(.later)
            },
            onLocalAnswerChange: { hasAnswers in
                hasLocalInventoryAnswers = hasAnswers
                exitCoordinator.noteExternalPersistencePending()
            },
            dismissesAfterUserAction: false
        )
        .task {
            let status = await checkInventoryStatus()
            inventoryStatus = status
            if status == .submitted || status == .draft {
                exitCoordinator.noteExternallyPersistedAnswer(
                    path: ["inventory"],
                    answers: ["inventory": [status == .submitted ? "submitted" : "draft"]]
                )
            }
            exitCoordinator.noteExternalAnswerStateReady()
        }
        .flowAnswerProbe {
            switch inventoryStatus {
            case .submitted, .draft, .unknown, .loading:
                return true
            case .empty:
                return hasLocalInventoryAnswers
            }
        }
    }

    private func checkInventoryStatus() async -> InventoryStatus {
        guard !userId.isEmpty else { return .empty }

        let db = FirestoreRuntime.firestore()
        do {
            let doc = try await db.collection("users").document(userId)
                .collection("inventory").document("_metadata")
                .getDocument()
            let status = doc.data()?["submissionStatus"] as? String
            if status == "submitted" { return .submitted }
            if status == "draft" { return .draft }
            return .empty
        } catch {
            return .unknown
        }
    }
}

#if DEBUG
#Preview("Scan my home") {
    ScanInventoryFlow(
        userId: "preview-user",
        taskId: "SCAN_INVENTORY",
        onComplete: { print("Complete") },
        onDismiss: { print("Dismiss") },
        onStatusAction: { action in print("Status: \(action)") }
    )
}
#endif
