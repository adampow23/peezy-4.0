//
//  FindCleanersFlow.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/13/26.
//

import SwiftUI

// MARK: - Find Cleaners Flow
// Type 6: Complex-Vendor
//
// Card sequence:
//   TitleCard → Select3 (which place) → Multi4 (services)
//   → [SKIP if move_in only] Select4 (move-out timing)
//   → [SKIP if move_out only] Select4 (move-in timing)
//   → SummaryCard
//
// Skip logic:
//   Card 3 (move-out timing): skip if which_place contains "move_in" (only move_in chosen)
//   Card 4 (move-in timing):  skip if which_place contains "move_out" (only move_out chosen)
//   If "both" is chosen, BOTH timing cards show.

struct FindCleanersFlow: View {
    let taskTitle = "Find my cleaners"
    let workflowId = "book_cleaners"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false

    // MARK: - Card Indices

    private let titleCard = 0
    private let whichPlaceCard = 1
    private let servicesCard = 2
    private let moveOutTimingCard = 3
    private let moveInTimingCard = 4
    private let summaryCard = 5
    private let totalCards = 6

    // MARK: - Skip Logic

    private func shouldSkip(_ index: Int) -> Bool {
        switch index {
        case moveOutTimingCard:
            // Skip if only "move_in" was chosen (not "move_out" or "both")
            return answers["which_place"]?.contains("move_in") == true
        case moveInTimingCard:
            // Skip if only "move_out" was chosen (not "move_in" or "both")
            return answers["which_place"]?.contains("move_out") == true
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
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: cardsRemaining, currentIndex: currentIndex) {
                cardContent
            }

            TaskFlowDismissButton(onDismiss: onDismiss)
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
                icon: "sparkles",
                onContinue: { advance() }
            )

        // ── Card 1: Which place needs cleaning? ──
        case whichPlaceCard:
            TaskFlowSelect3Card(
                taskTitle: taskTitle,
                question: "Which place needs cleaning?",
                option1: FlowOption(id: "move_out", label: "Old place — move-out clean", icon: "door.left.hand.open"),
                option2: FlowOption(id: "move_in", label: "New place — move-in clean", icon: "door.right.hand.open"),
                option3: FlowOption(id: "both", label: "Both places", icon: "arrow.left.arrow.right"),
                selectedIds: answers["which_place"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("which_place", id: id) },
                onBack: { goBack() }
            )

        // ── Card 2: Services needed (multi-select) ──
        case servicesCard:
            TaskFlowMulti4Card(
                taskTitle: taskTitle,
                question: "What services do you need?",
                option1: FlowOption(id: "standard", label: "Standard clean", icon: "sparkles"),
                option2: FlowOption(id: "deep", label: "Deep clean", icon: "bubbles.and.sparkles"),
                option3: FlowOption(id: "carpet", label: "Carpet cleaning", icon: "square.grid.3x3.topleft.filled"),
                option4: FlowOption(id: "windows", label: "Window cleaning", icon: "window.horizontal"),
                selectedIds: answers["services"] ?? [],
                showBack: true,
                onSelect: { id in toggleMulti("services", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 3: Move-out clean timing [SKIP if only move_in chosen] ──
        case moveOutTimingCard:
            TaskFlowSelect4Card(
                taskTitle: taskTitle,
                question: "When do you need the move-out clean?",
                option1: FlowOption(id: "morning", label: "Morning", icon: "sunrise"),
                option2: FlowOption(id: "afternoon", label: "Afternoon", icon: "sun.max"),
                option3: FlowOption(id: "evening", label: "Evening", icon: "sunset"),
                option4: FlowOption(id: "flexible", label: "Flexible", icon: "clock"),
                selectedIds: answers["move_out_timing"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("move_out_timing", id: id) },
                onBack: { goBack() }
            )

        // ── Card 4: Move-in clean timing [SKIP if only move_out chosen] ──
        case moveInTimingCard:
            TaskFlowSelect4Card(
                taskTitle: taskTitle,
                question: "When do you need the move-in clean?",
                option1: FlowOption(id: "morning", label: "Morning", icon: "sunrise"),
                option2: FlowOption(id: "afternoon", label: "Afternoon", icon: "sun.max"),
                option3: FlowOption(id: "evening", label: "Evening", icon: "sunset"),
                option4: FlowOption(id: "flexible", label: "Flexible", icon: "clock"),
                selectedIds: answers["move_in_timing"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("move_in_timing", id: id) },
                onBack: { goBack() }
            )

        // ── Card 5: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                bodyText: "We'll find cleaners who can handle everything you selected and get you quotes.",
                showBack: true,
                onPrimary: { submitAndComplete() },
                onBack: { goBack() }
            )

        default:
            EmptyView()
        }
    }

    // MARK: - Navigation (skip-aware)

    private func advance() {
        var next = currentIndex + 1
        while next < totalCards && shouldSkip(next) { next += 1 }
        guard next < totalCards else { return }
        currentIndex = next
    }

    private func goBack() {
        var prev = currentIndex - 1
        while prev >= 0 && shouldSkip(prev) { prev -= 1 }
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

    private func toggleMulti(_ key: String, id: String) {
        if answers[key] == nil { answers[key] = [] }
        if answers[key]!.contains(id) {
            answers[key]!.remove(id)
        } else {
            answers[key]!.insert(id)
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

// MARK: - Previews

#if DEBUG
#Preview("Find Cleaners Flow") {
    FindCleanersFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismiss") },
        onStatusAction: { action in print("📋 Status: \(action)") }
    )
}
#endif
