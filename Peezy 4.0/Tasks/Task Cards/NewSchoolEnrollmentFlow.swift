//
//  NewSchoolEnrollmentFlow.swift
//  Peezy 4.0
//

import SwiftUI

// MARK: - New School Enrollment Flow
// PATTERN: Simple Survey (Pattern B)
// Title → 1 question → Summary with Firebase submission.

struct NewSchoolEnrollmentFlow: View {
    let taskTitle = "Enroll in the new school"
    let workflowId = "new_school_enrollment"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false

    // MARK: - Card Indices

    private let titleCard = 0
    private let numChildrenCard = 1
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
                title: "Let's enroll at the new school",
                bodyText: "We'll tell you which school you're zoned for and what you need to bring.",
                primaryLabel: "Continue",
                secondaryLabel: "Go back",
                onPrimary: { advance() },
                onSecondary: { onDismiss() }
            )

        // ── Card 1: Number of children (single-select) ──
        case numChildrenCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "How many children are enrolling?",
                options: [
                    FlowOption(id: "1", label: "1 child", icon: "person.fill"),
                    FlowOption(id: "2", label: "2 children", icon: "person.2.fill",
                               subtitle: "May be different schools"),
                    FlowOption(id: "3_plus", label: "3 or more", icon: "person.3.fill",
                               subtitle: "We'll help coordinate")
                ],
                selectedIds: answers["num_children"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("num_children", id: id) },
                onBack: { goBack() }
            )

        // ── Card 2: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                title: "Your enrollment plan is ready",
                bodyText: "Enroll as soon as you have proof of residency at the new address. Don't wait until move day.",
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
#Preview("New School Enrollment Flow") {
    NewSchoolEnrollmentFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
