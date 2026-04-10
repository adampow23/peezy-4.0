//
//  SetupDaycareFlow.swift
//  Peezy 4.0
//

import SwiftUI

// MARK: - Setup Daycare Flow
// PATTERN: Simple Survey (Pattern B)
// Title → 2 questions (single-select, single-select) → Summary with Firebase submission.

struct SetupDaycareFlow: View {
    let taskTitle = "Find your new daycare"
    let workflowId = "setup_daycare"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false

    // MARK: - Card Indices

    private let titleCard = 0
    private let childAgeCard = 1
    private let careTypeCard = 2
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
                title: "Let's find daycare near your new home",
                bodyText: "A couple questions so we can point you to the right options.",
                primaryLabel: "Continue",
                secondaryLabel: "Go back",
                onPrimary: { advance() },
                onSecondary: { onDismiss() }
            )

        // ── Card 1: Child age (single-select) ──
        case childAgeCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "How old is your child?",
                subtitle: "Availability and waitlists vary significantly by age.",
                options: [
                    FlowOption(id: "infant", label: "Infant (0-12 mo)", icon: "figure.and.child.holdinghands",
                               subtitle: "Longest waitlists"),
                    FlowOption(id: "toddler", label: "Toddler (1-3 yrs)", icon: "figure.child",
                               subtitle: "Competitive but more options"),
                    FlowOption(id: "prek", label: "Pre-K (3-5 yrs)", icon: "book.and.wrench.fill",
                               subtitle: "Check for free public pre-K")
                ],
                selectedIds: answers["child_age"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("child_age", id: id) },
                onBack: { goBack() }
            )

        // ── Card 2: Care type (single-select) ──
        case careTypeCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "What type of care are you looking for?",
                options: [
                    FlowOption(id: "center", label: "Daycare center", icon: "building.2.fill",
                               subtitle: "Licensed facility"),
                    FlowOption(id: "in_home", label: "In-home daycare", icon: "house.fill",
                               subtitle: "Family daycare provider"),
                    FlowOption(id: "part_time", label: "Part-time or drop-in", icon: "clock.fill",
                               subtitle: "Flexible schedule")
                ],
                selectedIds: answers["care_type"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("care_type", id: id) },
                onBack: { goBack() }
            )

        // ── Card 3: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                title: "Your daycare search plan",
                bodyText: "Contact 3-5 providers and get on waitlists now — it costs nothing and can take months. Start tours before or right after your move.",
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
#Preview("Setup Daycare Flow") {
    SetupDaycareFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
