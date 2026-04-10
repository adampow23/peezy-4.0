import SwiftUI

// MARK: - Update Drivers License Flow
// PATTERN: Self-service / Provide Info
// Simple 3-card flow: Title → Info → Summary
// No questions, no Firebase submission. User acknowledges they'll handle it.
// Use this as the reference for: all selfServiceOnly / provide_info / off-app tasks.

struct UpdateDriversLicenseFlow: View {
    let taskTitle = "Update your license address"
    let workflowId = "update_drivers_license"

    let onComplete: () -> Void
    let onDismiss: () -> Void

    // MARK: - State

    @State private var currentIndex = 0

    // MARK: - Card Indices

    private let titleCard = 0
    private let infoCard = 1
    private let summaryCard = 2

    private let totalCards = 3

    private var cardsRemaining: Int {
        totalCards - currentIndex
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: cardsRemaining, currentIndex: currentIndex) {
                cardContent
            }
        }
    }

    // MARK: - Card Router

    @ViewBuilder
    private var cardContent: some View {
        switch currentIndex {

        // ── Card 0: Title ──
        case titleCard:
            TaskFlowTitleCard(
                taskTitle: taskTitle,
                title: "Update your license address",
                bodyText: "Bring your current license and two proofs of new address to the DMV. Most states require updates within 30 days.",
                primaryLabel: "On It",
                secondaryLabel: "Go back",
                onPrimary: { advance() },
                onSecondary: { onDismiss() }
            )

        // ── Card 1: Info ──
        case infoCard:
            TaskFlowInfoCard(
                taskTitle: taskTitle,
                title: "Good to Know",
                bodyText: "Check your state — many let you update online without an appointment. An outdated address can void traffic ticket service and jury duty notices.",
                primaryLabel: "Got it",
                showBack: true,
                onPrimary: { advance() },
                onBack: { goBack() }
            )

        // ── Card 2: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                title: "You're all set!",
                bodyText: "We'll check in on this closer to your move date to make sure it gets done.",
                primaryLabel: "Done",
                showBack: true,
                onPrimary: { onComplete() },
                onBack: { goBack() }
            )

        default:
            EmptyView()
        }
    }

    // MARK: - Navigation

    private func advance() {
        guard currentIndex + 1 < totalCards else { return }
        currentIndex += 1
    }

    private func goBack() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Update Drivers License Flow") {
    UpdateDriversLicenseFlow(
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
