//
//  RentTruckFlow.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/10/26.
//

import SwiftUI

// MARK: - Rent Truck Flow
// PATTERN: Simple Survey / Pattern B
// Short flow: Title → Single question → Summary with submission.

struct RentTruckFlow: View {
    let taskTitle = "Rent your moving truck"
    let workflowId = "rent_truck"

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
                title: "Let's get you a truck",
                bodyText: "We'll use the details from your inventory to find the right size and best price.",
                primaryLabel: "Continue",
                secondaryLabel: "Go back",
                onPrimary: { advance() },
                onSecondary: { onDismiss() }
            )

        // ── Card 1: One-way or round-trip? (single-select) ──
        case actionCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "One-way or round-trip?",
                options: [
                    FlowOption(id: "one_way", label: "One-way", icon: "arrow.right",
                               subtitle: nil),
                    FlowOption(id: "round_trip", label: "Round-trip", icon: "arrow.triangle.2.circlepath",
                               subtitle: nil),
                    FlowOption(id: "not_sure", label: "Not sure", icon: "questionmark.circle",
                               subtitle: nil)
                ],
                selectedIds: answers["trip_type"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("trip_type", id: id) },
                onBack: { goBack() }
            )

        // ── Card 2: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                title: "Here's what we've got",
                bodyText: "We'll compare options from the major rental companies and get you the best deal. We'll reach out as soon as we have quotes.",
                primaryLabel: "Request Quotes",
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
#Preview("Rent Truck Flow") {
    RentTruckFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
