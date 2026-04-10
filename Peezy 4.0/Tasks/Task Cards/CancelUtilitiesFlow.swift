//
//  CancelUtilitiesFlow.swift
//  Peezy 4.0
//

import SwiftUI

// MARK: - Cancel Utilities Flow
// PATTERN: 0-question Pattern B — Title → Info → Summary with Firebase submission.

struct CancelUtilitiesFlow: View {
    let taskTitle = "Cancel your utilities"
    let workflowId = "cancel_utilities"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false

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
                title: "Time to cancel utilities at your current place",
                bodyText: "We'll tell you exactly which providers to contact and when.",
                primaryLabel: "Continue",
                secondaryLabel: "Go back",
                onPrimary: { advance() },
                onSecondary: { onDismiss() }
            )

        // ── Card 1: Info ──
        case infoCard:
            TaskFlowInfoCard(
                taskTitle: taskTitle,
                title: "Good to Know",
                bodyText: "Schedule disconnection for the day after your move so you have service through your last day. Most providers need 3-5 business days notice.",
                primaryLabel: "Continue",
                showBack: true,
                onPrimary: { advance() },
                onBack: { goBack() }
            )

        // ── Card 2: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                title: "Here's your utility cancellation plan",
                bodyText: "Your timeline has been updated. We'll take it from here.",
                primaryLabel: "Got it",
                showBack: true,
                onPrimary: { submitAndComplete() },
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

    // MARK: - Submission

    private func submitAndComplete() {
        guard !isSubmitting else { return }
        isSubmitting = true

        var workflowAnswers = WorkflowAnswers(workflowId: workflowId)
        workflowAnswers.answers = answers.mapValues { Array($0) }

        Task {
            do {
                let service = WorkflowService()
                let response = try await service.submitAnswers(
                    workflowId: workflowId,
                    answers: workflowAnswers,
                    userId: userId
                )
                await MainActor.run {
                    isSubmitting = false
                    if response.success { onComplete() }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    onComplete()
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Cancel Utilities Flow") {
    CancelUtilitiesFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
