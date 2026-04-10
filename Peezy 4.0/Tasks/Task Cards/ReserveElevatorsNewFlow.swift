//
//  ReserveElevatorsNewFlow.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/10/26.
//

import SwiftUI

// MARK: - Reserve Elevators New Flow
// PATTERN: Simple Survey / Pattern B
// Short flow: Title → Single question → Summary with submission.

struct ReserveElevatorsNewFlow: View {
    let taskTitle = "Reserve unloading elevator"
    let workflowId = "reserve_elevators_new"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false

    // MARK: - Card Indices

    private let titleCard = 0
    private let actionCard = 1
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
                title: "Let's reserve the elevator for move-in",
                bodyText: "We'll figure out when you need it and for how long based on your inventory.",
                primaryLabel: "Continue",
                secondaryLabel: "Go back",
                onPrimary: { advance() },
                onSecondary: { onDismiss() }
            )

        // ── Card 1: What time are you planning to start your move? (single-select) ──
        case actionCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "What time are you planning to start your move?",
                options: [
                    FlowOption(id: "morning", label: "Morning", icon: "sunrise.fill",
                               subtitle: "Before 10am"),
                    FlowOption(id: "midday", label: "Midday", icon: "sun.max.fill",
                               subtitle: "10am – 1pm"),
                    FlowOption(id: "afternoon", label: "Afternoon", icon: "sunset.fill",
                               subtitle: "After 1pm")
                ],
                selectedIds: answers["move_start_time"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("move_start_time", id: id) },
                onBack: { goBack() }
            )

        // ── Card 2: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                title: "Elevator reservation plan ready",
                bodyText: "We'll calculate the time window you need based on your inventory.",
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
                    if response.success {
                        onComplete()
                    }
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
#Preview("Reserve Elevators New Flow") {
    ReserveElevatorsNewFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
