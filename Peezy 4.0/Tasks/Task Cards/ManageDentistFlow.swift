//
//  ManageDentistFlow.swift
//  Peezy 4.0
//

import SwiftUI

// MARK: - Manage Dentist Flow
// PATTERN: Simple Survey / Transfer-Cancel
// Short flow: Title → Single question → Summary with submission.

struct ManageDentistFlow: View {
    let taskTitle = "Handle your dentist"
    let workflowId = "manage_dentist"

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
                title: "Your dentist",
                bodyText: "Let's figure out what you need for your dentist.",
                primaryLabel: "Continue",
                secondaryLabel: "Go back",
                onPrimary: { advance() },
                onSecondary: { onDismiss() }
            )

        // ── Card 1: What would you like to do? (single-select) ──
        case actionCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "What would you like to do?",
                options: [
                    FlowOption(id: "transfer_records", label: "Transfer records to new dentist", icon: "doc.arrow.forward",
                               subtitle: "Request records and X-rays be sent to a new dentist"),
                    FlowOption(id: "update_address", label: "Update address with current dentist", icon: "pencil.line",
                               subtitle: "Keep your current dentist, just update your contact info"),
                    FlowOption(id: "already_handled", label: "Already handled", icon: "checkmark.circle",
                               subtitle: "I've already taken care of this")
                ],
                selectedIds: answers["action"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("action", id: id) },
                onBack: { goBack() }
            )

        // ── Card 2: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                title: "We're on it",
                bodyText: "We'll take it from here.",
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
#Preview("Manage Dentist Flow") {
    ManageDentistFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
