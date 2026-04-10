//
//  SetupUtilitiesFlow.swift
//  Peezy 4.0
//

import SwiftUI

// MARK: - Setup Utilities Flow
// PATTERN: Simple Survey (Pattern B)
// Title → 1 question → Summary with Firebase submission.

struct SetupUtilitiesFlow: View {
    let taskTitle = "Set up new utilities"
    let workflowId = "setup_utilities"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false

    // MARK: - Card Indices

    private let titleCard = 0
    private let internetCard = 1
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
                title: "Let's get utilities set up at your new place",
                bodyText: "We'll make sure everything is on when you arrive.",
                primaryLabel: "Continue",
                secondaryLabel: "Go back",
                onPrimary: { advance() },
                onSecondary: { onDismiss() }
            )

        // ── Card 1: Internet provider (single-select) ──
        case internetCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "Have you already chosen an internet provider?",
                options: [
                    FlowOption(id: "yes", label: "Yes, I know which one", icon: "checkmark.circle.fill",
                               subtitle: "Just need setup steps"),
                    FlowOption(id: "no", label: "No, I need to pick one", icon: "magnifyingglass",
                               subtitle: "Show me what's available"),
                    FlowOption(id: "building_provided", label: "My building has one option", icon: "building.2.fill",
                               subtitle: "No choice to make")
                ],
                selectedIds: answers["internet_chosen"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("internet_chosen", id: id) },
                onBack: { goBack() }
            )

        // ── Card 2: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                title: "Your utility setup plan",
                bodyText: "Priority order: Electric and gas first (1-3 day lead time), then internet (7-14 days for installation).",
                primaryLabel: "Submit",
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

    // MARK: - Answer Handlers

    private func selectSingle(_ key: String, id: String) {
        answers[key] = [id]
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            advance()
        }
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
#Preview("Setup Utilities Flow") {
    SetupUtilitiesFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
