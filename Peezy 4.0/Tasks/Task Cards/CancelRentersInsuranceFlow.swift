//
//  CancelRentersInsuranceFlow.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/10/26.
//

import SwiftUI

// MARK: - Cancel Renters Insurance Flow
// PATTERN: Complex Survey (skip logic)
// current_provider card only shows when help_preference answer contains "help_me".

struct CancelRentersInsuranceFlow: View {
    let taskTitle = "Cancel your renter's insurance"
    let workflowId = "cancel_renters_insurance"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false

    // MARK: - Card Indices

    private let titleCard = 0
    private let helpPreferenceCard = 1
    private let currentProviderCard = 2
    private let summaryCard = 3

    private let totalCards = 4

    // MARK: - Skip Logic

    private var wantsHelp: Bool {
        answers["help_preference"]?.contains("help_me") == true
    }

    private func shouldSkip(_ index: Int) -> Bool {
        switch index {
        case currentProviderCard:
            return !wantsHelp
        default:
            return false
        }
    }

    private var cardsRemaining: Int {
        var count = 0
        for i in currentIndex..<totalCards {
            if !shouldSkip(i) { count += 1 }
        }
        return count
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
                title: "Renter's insurance",
                bodyText: "We'll make sure you're covered through your last day.",
                primaryLabel: "Continue",
                secondaryLabel: "Go back",
                onPrimary: { advance() },
                onSecondary: { onDismiss() }
            )

        // ── Card 1: Help preference (single-select) ──
        case helpPreferenceCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "Would you like help canceling?",
                options: [
                    FlowOption(id: "help_me", label: "Yes, help me cancel", icon: "hands.sparkles.fill"),
                    FlowOption(id: "self", label: "I'll handle it myself", icon: "person.fill")
                ],
                selectedIds: answers["help_preference"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("help_preference", id: id) },
                onBack: { goBack() }
            )

        // ── Card 2: Current provider (single-select, conditional) ──
        case currentProviderCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "Who is your current provider?",
                subtitle: "So we know who to contact.",
                options: [
                    FlowOption(id: "state_farm", label: "State Farm", icon: "shield.fill"),
                    FlowOption(id: "lemonade", label: "Lemonade", icon: "shield.fill"),
                    FlowOption(id: "progressive", label: "Progressive", icon: "shield.fill"),
                    FlowOption(id: "allstate", label: "Allstate", icon: "shield.fill"),
                    FlowOption(id: "other", label: "Other", icon: "ellipsis.circle")
                ],
                selectedIds: answers["current_provider"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("current_provider", id: id) },
                onBack: { goBack() }
            )

        // ── Card 3: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                title: "We're on it",
                bodyText: "We'll reach out and get this canceled effective your move date.",
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
        var next = currentIndex + 1
        while next < totalCards && shouldSkip(next) {
            next += 1
        }
        guard next < totalCards else { return }
        currentIndex = next
    }

    private func goBack() {
        var prev = currentIndex - 1
        while prev >= 0 && shouldSkip(prev) {
            prev -= 1
        }
        guard prev >= 0 else { return }
        currentIndex = prev
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
#Preview("Cancel Renters Insurance Flow") {
    CancelRentersInsuranceFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
