import SwiftUI

// MARK: - New Drivers License Flow
// PATTERN: Self-service / Provide Info
// Simple 3-card flow: Title → Info → Summary
// No questions, no Firebase submission. User acknowledges they'll handle it.
// Use this as the reference for: all selfServiceOnly / provide_info / off-app tasks.

struct NewDriversLicenseFlow: View {
    let taskTitle = "Get your new state license"
    let workflowId = "new_drivers_license"

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
                title: "Get your new state license",
                bodyText: "Surrender your old license at the new state's DMV. Bring proof of residency, your current license, and Social Security card.",
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
                bodyText: "Request REAL ID — TSA needs a new one in your new state. Driving past the deadline on an out-of-state license is a moving violation.",
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
#Preview("New Drivers License Flow") {
    NewDriversLicenseFlow(
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
