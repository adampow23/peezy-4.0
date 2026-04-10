//
//  UpdateStudentLoansFlow.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/10/26.
//

import SwiftUI

// MARK: - Update Student Loans Flow
// PATTERN: Simple Survey
// Short flow: Title → Single question → Summary with submission.

struct UpdateStudentLoansFlow: View {
    let taskTitle = "Update student loan accounts"
    let workflowId = "update_student_loans"

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
                title: "Student loans",
                bodyText: "Let's handle your student loans.",
                primaryLabel: "Continue",
                secondaryLabel: "Go back",
                onPrimary: { advance() },
                onSecondary: { onDismiss() }
            )

        // ── Card 1: Action (single-select) ──
        case actionCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "What would you like to do with your student loans?",
                options: [
                    FlowOption(id: "update_address", label: "Update my address", icon: "pencil.line",
                               subtitle: "Update with servicer and StudentAid.gov"),
                    FlowOption(id: "help_me", label: "Help me figure out what to do", icon: "questionmark.circle",
                               subtitle: "We'll walk you through it"),
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
#Preview("Update Student Loans Flow") {
    UpdateStudentLoansFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
