//
//  UpdateDaycareFlow.swift
//  Peezy 4.0
//

import SwiftUI

struct UpdateDaycareFlow: View {
    let taskTitle = "Update my daycare"
    let workflowId = "transfer_daycare"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @State private var currentIndex = 0

    private let titleCard = 0
    private let infoCard = 1
    private let statusCard = 2
    private let totalCards = 3

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()
            TaskFlowStack(cardsRemaining: totalCards - currentIndex, currentIndex: currentIndex) {
                cardContent
            }
            TaskFlowDismissButton(onDismiss: onDismiss)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        switch currentIndex {
        case titleCard:
            TaskFlowTitleCard(
                taskTitle: taskTitle,
                icon: "figure.and.child.holdinghands",
                onContinue: { advance() }
            )
        case infoCard:
            TaskFlowInfoCard(
                taskTitle: taskTitle,
                title: "Good to Know",
                bodyText: "Give your current daycare 2-4 weeks written notice. Request copies of developmental records and immunization history. Ask for recommendations near your new address.",
                primaryLabel: "Got it",
                showBack: true,
                onPrimary: { advance() },
                onBack: { goBack() }
            )
        case statusCard:
            TaskFlowStatusCard(
                taskTitle: taskTitle,
                showBack: true,
                onLater: { onStatusAction(.later) },
                onInProgress: { onStatusAction(.inProgress) },
                onDone: { onStatusAction(.done) },
                onBack: { goBack() }
            )
        default:
            EmptyView()
        }
    }

    private func advance() {
        guard currentIndex + 1 < totalCards else { return }
        currentIndex += 1
    }

    private func goBack() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }
}

#if DEBUG
#Preview("Update my daycare") {
    UpdateDaycareFlow(
        userId: "preview-user",
        onComplete: { print("Complete") },
        onDismiss: { print("Dismiss") },
        onStatusAction: { action in print("Status: \(action)") }
    )
}
#endif
