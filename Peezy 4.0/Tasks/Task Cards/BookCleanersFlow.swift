//
//  BookCleanersFlow.swift
//  Peezy 4.0
//

import SwiftUI

// MARK: - Book Cleaners Flow
// Complete card flow for the "Book your cleaners" task.
// Skip logic: move_out_timing shows only if which_place is "move_out" or "both".
//             move_in_timing shows only if which_place is "move_in" or "both".

struct BookCleanersFlow: View {
    let taskTitle = "Book your cleaners"
    let workflowId = "book_cleaners"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

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

    private var whichPlace: String? { answers["which_place"]?.first }

    private func shouldSkip(_ index: Int) -> Bool {
        switch index {
        case moveOutTimingCard:
            return whichPlace != "move_out" && whichPlace != "both"
        case moveInTimingCard:
            return whichPlace != "move_in" && whichPlace != "both"
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
                title: "Book your cleaners",
                bodyText: "A couple quick questions to match you with the right service.",
                primaryLabel: "Continue",
                secondaryLabel: "Go back",
                onPrimary: { advance() },
                onSecondary: { onDismiss() }
            )

        // ── Card 1: Which Place (single-select) ──
        case whichPlaceCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "Which place needs cleaning?",
                options: [
                    FlowOption(id: "move_out", label: "Old place — move-out clean", icon: "door.left.hand.open"),
                    FlowOption(id: "move_in", label: "New place — move-in clean", icon: "door.right.hand.open"),
                    FlowOption(id: "both", label: "Both places", icon: "arrow.left.arrow.right"),
                ],
                mode: .single,
                selectedIds: answers["which_place"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("which_place", id: id) },
                onContinue: nil,
                onBack: { goBack() }
            )

        // ── Card 2: Services (multi-select) ──
        case servicesCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "What services do you need?",
                subtitle: "Select all that apply.",
                options: [
                    FlowOption(id: "standard", label: "Standard clean", icon: "sparkles"),
                    FlowOption(id: "deep", label: "Deep clean (baseboards, inside appliances)", icon: "bubbles.and.sparkles"),
                    FlowOption(id: "carpet", label: "Carpet cleaning", icon: "square.grid.3x3.topleft.filled"),
                    FlowOption(id: "windows", label: "Window cleaning", icon: "window.horizontal"),
                ],
                mode: .multi,
                selectedIds: answers["services"] ?? [],
                showBack: true,
                onSelect: { id in toggleMulti("services", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 3: Move-Out Timing (single-select, conditional) ──
        case moveOutTimingCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "When do you need the move-out clean?",
                subtitle: "Rough time preference.",
                options: [
                    FlowOption(id: "morning", label: "Morning", icon: "sunrise"),
                    FlowOption(id: "afternoon", label: "Afternoon", icon: "sun.max"),
                    FlowOption(id: "evening", label: "Evening", icon: "sunset"),
                    FlowOption(id: "flexible", label: "Flexible", icon: "clock"),
                ],
                mode: .single,
                selectedIds: answers["move_out_timing"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("move_out_timing", id: id) },
                onContinue: nil,
                onBack: { goBack() }
            )

        // ── Card 4: Move-In Timing (single-select, conditional) ──
        case moveInTimingCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "When do you need the move-in clean?",
                subtitle: "Rough time preference.",
                options: [
                    FlowOption(id: "morning", label: "Morning", icon: "sunrise"),
                    FlowOption(id: "afternoon", label: "Afternoon", icon: "sun.max"),
                    FlowOption(id: "evening", label: "Evening", icon: "sunset"),
                    FlowOption(id: "flexible", label: "Flexible", icon: "clock"),
                ],
                mode: .single,
                selectedIds: answers["move_in_timing"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("move_in_timing", id: id) },
                onContinue: nil,
                onBack: { goBack() }
            )

        // ── Card 5: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                title: "Here's what we've got",
                bodyText: "We'll find cleaners who can handle everything you selected and get you quotes.",
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
#Preview("Book Cleaners Flow") {
    BookCleanersFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
