//
//  ScanInventoryFlow.swift
//  Peezy 4.0
//

import SwiftUI
import FirebaseFirestore

struct ScanInventoryFlow: View {
    let workflowId = "scan_inventory"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @State private var didFireCallback = false

    private enum InventoryStatus {
        case submitted
        case draft
        case empty
    }

    var body: some View {
        InventoryFlowView(
            onUserDismiss: {
                // User dismissed without submitting.
                guard !didFireCallback else { return }
                didFireCallback = true

                // Check once if they actually submitted (edge case: submit -> dismiss happens fast)
                Task {
                    let status = await checkInventoryStatus()
                    await MainActor.run {
                        switch status {
                        case .submitted:
                            onComplete()
                        case .draft:
                            // User saved progress; keep it off today's active queue.
                            onStatusAction(.inProgress)
                        case .empty:
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
            }
        )
    }

    private func checkInventoryStatus() async -> InventoryStatus {
        guard !userId.isEmpty else { return .empty }

        let db = Firestore.firestore()
        do {
            let doc = try await db.collection("users").document(userId)
                .collection("inventory").document("_metadata")
                .getDocument()
            let status = doc.data()?["submissionStatus"] as? String
            if status == "submitted" { return .submitted }
            if status == "draft" { return .draft }
            return .empty
        } catch {
            return .empty
        }
    }
}

#if DEBUG
#Preview("Scan my home") {
    ScanInventoryFlow(
        userId: "preview-user",
        onComplete: { print("Complete") },
        onDismiss: { print("Dismiss") },
        onStatusAction: { action in print("Status: \(action)") }
    )
}
#endif
