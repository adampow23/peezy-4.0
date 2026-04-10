//
//  BeginSchoolTransferFlow.swift
//  Peezy 4.0
//

import SwiftUI

// MARK: - Begin School Transfer Flow
// PATTERN: Simple Survey (Pattern B)
// Title → 2 questions (single-select, multi-select) → Summary with Firebase submission.

struct BeginSchoolTransferFlow: View {
    let taskTitle = "Notify the current school"
    let workflowId = "begin_school_transfer"

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
    private let gradeLevelsCard = 2
    private let summaryCard = 3

    private let totalCards = 4

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
                title: "Let's start the school transfer",
                bodyText: "A couple quick questions so we can give you the right checklist.",
                primaryLabel: "Continue",
                secondaryLabel: "Go back",
                onPrimary: { advance() },
                onSecondary: { onDismiss() }
            )

        // ── Card 1: Number of children (single-select) ──
        case numChildrenCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "How many children are transferring?",
                options: [
                    FlowOption(id: "1", label: "1 child", icon: "person.fill"),
                    FlowOption(id: "2", label: "2 children", icon: "person.2.fill"),
                    FlowOption(id: "3_plus", label: "3 or more", icon: "person.3.fill",
                               subtitle: "We'll help you coordinate")
                ],
                selectedIds: answers["num_children"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("num_children", id: id) },
                onBack: { goBack() }
            )

        // ── Card 2: Grade levels (multi-select) ──
        case gradeLevelsCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "What grade level(s)?",
                subtitle: "Select all that apply",
                options: [
                    FlowOption(id: "elementary", label: "Elementary (K-5)", icon: "book.fill",
                               subtitle: "Report cards, immunizations"),
                    FlowOption(id: "middle", label: "Middle (6-8)", icon: "books.vertical.fill",
                               subtitle: "Course placement records"),
                    FlowOption(id: "high", label: "High School (9-12)", icon: "graduationcap.fill",
                               subtitle: "Transcripts, credits, AP records")
                ],
                mode: .multi,
                selectedIds: answers["grade_levels"] ?? [],
                showBack: true,
                onSelect: { id in toggleMulti("grade_levels", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 3: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                title: "Your school transfer checklist is ready",
                bodyText: "Start this process 2-3 weeks before your move. Schools typically take 5-10 business days to process records.",
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

    private func toggleMulti(_ key: String, id: String) {
        var current = answers[key] ?? []
        if current.contains(id) {
            current.remove(id)
        } else {
            current.insert(id)
        }
        answers[key] = current
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
#Preview("Begin School Transfer Flow") {
    BeginSchoolTransferFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
