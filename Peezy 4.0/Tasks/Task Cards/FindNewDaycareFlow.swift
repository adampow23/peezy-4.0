//
//  FindNewDaycareFlow.swift
//  Peezy 4.0
//

import SwiftUI

struct FindNewDaycareFlow: View {
    let taskTitle = "Find my new daycare"
    let workflowId = "setup_daycare"

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
                bodyText: "Start calling providers now — waitlists for infant and toddler spots can be 3-6 months. Contact at least 5 providers near your new address, ask about openings for your child's age group, and get on every waitlist. It costs nothing and saves you from scrambling after the move.",
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
#Preview("Find my new daycare") {
    FindNewDaycareFlow(
        userId: "preview-user",
        onComplete: { print("Complete") },
        onDismiss: { print("Dismiss") },
        onStatusAction: { action in print("Status: \(action)") }
    )
}
#endif
