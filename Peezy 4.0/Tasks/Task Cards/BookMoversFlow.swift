//
//  BookMovers.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/10/26.
//

import SwiftUI

// MARK: - Book Movers Flow
// Complete card flow for the "Book your movers" task.
// Each card is assembled from shared templates.
// Skip logic, answers, and submission are self-contained.

struct BookMoversFlow: View {
    let taskTitle = "Book your movers"
    let workflowId = "book_movers"

    // Passed in from the parent that opens this flow
    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false

    // MARK: - Card Indices
    // Named constants so skip logic reads clearly

    private let titleCard = 0
    private let heavyItemsCard = 1
    private let delicateItemsCard = 2
    private let packingCard = 3
    private let storageCard = 4
    private let storageSizeCard = 5
    private let storageFullnessCard = 6
    private let insuranceWarningCard = 7
    private let insurancePreferenceCard = 8
    private let summaryCard = 9

    private let totalCards = 10

    // MARK: - Skip Logic

    private var storageNeeded: Bool {
        answers["storage_needed"]?.contains("yes") == true
    }

    private func shouldSkip(_ index: Int) -> Bool {
        switch index {
        case storageSizeCard, storageFullnessCard:
            return !storageNeeded
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
                title: "Book your movers",
                bodyText: "We have a few questions to help us match you with the best movers for you.",
                primaryLabel: "Continue",
                secondaryLabel: "Go back",
                onPrimary: { advance() },
                onSecondary: { onDismiss() }
            )

        // ── Card 1: Heavy Items (multi-select) ──
        case heavyItemsCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "Any heavy items making the move?",
                options: [
                    FlowOption(id: "piano", label: "Piano / Organ", icon: "pianokeys"),
                    FlowOption(id: "safe", label: "Gun Safe / Safe", icon: "lock.shield"),
                    FlowOption(id: "hot_tub", label: "Hot Tub / Spa", icon: "drop.fill"),
                    FlowOption(id: "pool_table", label: "Pool Table", icon: "circle.grid.3x3"),
                ],
                mode: .multi,
                selectedIds: answers["heavy_items"] ?? [],
                showBack: true,
                onSelect: { id in toggleMulti("heavy_items", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 2: Delicate Items (multi-select) ──
        case delicateItemsCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "What about any items requiring a little extra care?",
                options: [
                    FlowOption(id: "art", label: "Art / Antiques", icon: "photo.artframe"),
                    FlowOption(id: "glass", label: "Large Mirrors / Glass", icon: "rectangle"),
                    FlowOption(id: "china", label: "China / Dishware", icon: "wineglass"),
                ],
                mode: .multi,
                selectedIds: answers["specialty_items"] ?? [],
                showBack: true,
                onSelect: { id in toggleMulti("specialty_items", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 3: Packing (multi-select, exclusive options) ──
        case packingCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "Interested in what packing help might cost?",
                options: [
                    FlowOption(id: "full", label: "Full service — pack everything", icon: "shippingbox.fill", isExclusive: true),
                    FlowOption(id: "partial", label: "Just fragile / kitchen items", icon: "wineglass", isExclusive: true),
                ],
                mode: .multi,
                selectedIds: answers["packing_help"] ?? [],
                showBack: true,
                onSelect: { id in toggleExclusive("packing_help", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 4: Storage Yes/No (compact side-by-side) ──
        case storageCard:
            TaskFlowCompactTilesCard(
                taskTitle: taskTitle,
                question: "Anything in storage that you'd like included in the quotes?",
                options: [
                    FlowOption(id: "yes", label: "Yes", icon: "hand.thumbsup.fill"),
                    FlowOption(id: "no", label: "No", icon: "hand.thumbsdown.fill"),
                ],
                selectedId: answers["storage_needed"]?.first,
                showBack: true,
                onSelect: { id in selectSingle("storage_needed", id: id) },
                onBack: { goBack() }
            )

        // ── Card 5: Storage Size (single-select, conditional) ──
        case storageSizeCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "What size unit is it?",
                options: [
                    FlowOption(id: "5x5", label: "Small (5×5)", icon: "shippingbox"),
                    FlowOption(id: "10x10", label: "Medium (10×10)", icon: "shippingbox.fill"),
                    FlowOption(id: "10x20", label: "Large (10×20)", icon: "archivebox.fill"),
                ],
                selectedIds: answers["storage_size"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("storage_size", id: id) },
                onBack: { goBack() }
            )

        // ── Card 6: Storage Fullness (fill bars, conditional) ──
        case storageFullnessCard:
            TaskFlowFillBarCard(
                taskTitle: taskTitle,
                question: "And about how full is the unit?",
                options: [
                    FlowOption(id: "quarter", label: "~¼", icon: "circle", fillPercent: 0.25),
                    FlowOption(id: "half", label: "~½", icon: "circle", fillPercent: 0.50),
                    FlowOption(id: "three_quarter", label: "~¾", icon: "circle", fillPercent: 0.75),
                    FlowOption(id: "full", label: "Full", icon: "circle", fillPercent: 1.0),
                ],
                selectedId: answers["storage_fullness"]?.first,
                showBack: true,
                onSelect: { id in selectSingle("storage_fullness", id: id) },
                onBack: { goBack() }
            )

        // ── Card 7: Insurance Warning (info card) ──
        case insuranceWarningCard:
            TaskFlowInfoCard(
                taskTitle: taskTitle,
                title: "Very important to understand",
                bodyText: "So, if your $1,000 TV weighs 50lbs, by law, you are only entitled to receive $30.",
                primaryLabel: "I understand",
                cautionIcon: "exclamationmark.triangle.fill",
                boldPrefix: "By law, companies are required to provide basic coverage for your belongings, which covers $0.60 per pound for items damaged beyond repair.",
                showBack: true,
                onPrimary: { advance() },
                onBack: { goBack() }
            )

        // ── Card 8: Insurance Preference (single-select + skip) ──
        case insurancePreferenceCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "Based on what was just discussed, would you be interested in pricing for additional insurance?",
                options: [
                    FlowOption(id: "full_value", label: "Full Coverage — Full Replacement", icon: "shield.checkered"),
                    FlowOption(id: "supplemental", label: "Supplemental Partial Coverage", icon: "shield.lefthalf.filled"),
                ],
                selectedIds: answers["insurance_preference"] ?? [],
                skipLabel: "No — free basic coverage",
                showBack: true,
                onSelect: { id in selectSingle("insurance_preference", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 9: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                title: "That's it. We can take it from here.",
                bodyText: "This gives us what we need to get quotes from the top three companies that we believe will best assist you.",
                primaryLabel: "Submit Request",
                subtext: "Typical response time: 2–3 days",
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

    /// Single-select: set one answer and auto-advance after brief delay
    private func selectSingle(_ key: String, id: String) {
        answers[key] = [id]
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            advance()
        }
    }

    /// Multi-select: toggle option in the set
    private func toggleMulti(_ key: String, id: String) {
        var current = answers[key] ?? []
        if current.contains(id) {
            current.remove(id)
        } else {
            current.insert(id)
        }
        answers[key] = current
    }

    /// Multi-select with exclusive options: selecting one replaces others, tapping again deselects
    private func toggleExclusive(_ key: String, id: String) {
        if answers[key]?.contains(id) == true {
            answers[key] = []
        } else {
            answers[key] = [id]
        }
    }

    // MARK: - Submission

    private func submitAndComplete() {
        guard !isSubmitting else { return }
        isSubmitting = true

        // Build WorkflowAnswers from our local state
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
                    // For now, complete anyway — we can add error handling later
                    onComplete()
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Book Movers Flow") {
    BookMoversFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
