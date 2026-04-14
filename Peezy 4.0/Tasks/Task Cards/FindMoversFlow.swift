//
//  FindMoversFlow.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/13/26.
//

import SwiftUI

// MARK: - Find Movers Flow
// Type 6: Complex-Vendor
//
// Card sequence:
//   TitleCard → Multi4 (heavy items) → Multi3 (delicate items)
//   → TilesCard/multi/exclusive (packing help) → CompactTiles (storage?)
//   → [SKIP if no storage] Select3 (storage size) → FillBar (storage fill)
//   → InfoCard (insurance warning) → TilesCard/single/skip (add. insurance)
//   → SummaryCard
//
// Skip logic:
//   Cards 5 (storage size) and 6 (storage fill): skip when storage_needed != "yes"

struct FindMoversFlow: View {
    let taskTitle = "Find my movers"
    let workflowId = "book_movers"

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
    private let heavyItemsCard = 1
    private let delicateItemsCard = 2
    private let packingHelpCard = 3
    private let storageCard = 4
    private let storageSizeCard = 5
    private let storageFillCard = 6
    private let insuranceInfoCard = 7
    private let insuranceOptionsCard = 8
    private let summaryCard = 9
    private let totalCards = 10

    // MARK: - Skip Logic

    private func shouldSkip(_ index: Int) -> Bool {
        switch index {
        case storageSizeCard, storageFillCard:
            return answers["storage_needed"]?.contains("yes") != true
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
                icon: "truck.box.fill",
                onContinue: { advance() }
            )

        // ── Card 1: Heavy items (multi-select) ──
        case heavyItemsCard:
            TaskFlowMulti4Card(
                taskTitle: taskTitle,
                question: "Any heavy items making the move?",
                option1: FlowOption(id: "piano", label: "Piano / Organ", icon: "pianokeys"),
                option2: FlowOption(id: "safe", label: "Gun Safe / Safe", icon: "lock.shield"),
                option3: FlowOption(id: "hot_tub", label: "Hot Tub / Spa", icon: "drop.fill"),
                option4: FlowOption(id: "pool_table", label: "Pool Table", icon: "circle.grid.3x3"),
                selectedIds: answers["heavy_items"] ?? [],
                showBack: true,
                onSelect: { id in toggleMulti("heavy_items", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 2: Delicate items (multi-select) ──
        case delicateItemsCard:
            TaskFlowMulti3Card(
                taskTitle: taskTitle,
                question: "Any items needing extra care?",
                option1: FlowOption(id: "art", label: "Art / Antiques", icon: "photo.artframe"),
                option2: FlowOption(id: "glass", label: "Large Mirrors / Glass", icon: "rectangle"),
                option3: FlowOption(id: "china", label: "China / Dishware", icon: "wineglass"),
                selectedIds: answers["delicate_items"] ?? [],
                showBack: true,
                onSelect: { id in toggleMulti("delicate_items", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 3: Packing help (exclusive multi + skip) ──
        // Raw TilesCard: 2 exclusive options, mode .multi, skipLabel.
        // In multi mode TilesCard shows "None"/"Continue" (skipLabel not rendered).
        // Tapping "None" advances without a packing selection — functional skip.
        case packingHelpCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "Interested in what packing help might cost?",
                options: [
                    FlowOption(id: "full", label: "Full service — pack everything", icon: "shippingbox.fill", isExclusive: true),
                    FlowOption(id: "partial", label: "Just fragile / kitchen items", icon: "wineglass", isExclusive: true)
                ],
                mode: .multi,
                selectedIds: answers["packing_help"] ?? [],
                skipLabel: "No — I'll pack myself",
                showBack: true,
                onSelect: { id in toggleExclusive("packing_help", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 4: Storage to include? (compact yes/no) ──
        case storageCard:
            TaskFlowCompactTilesCard(
                taskTitle: taskTitle,
                question: "Anything in storage to include?",
                options: [
                    FlowOption(id: "yes", label: "Yes", icon: "hand.thumbsup.fill"),
                    FlowOption(id: "no", label: "No", icon: "hand.thumbsdown.fill")
                ],
                selectedId: answers["storage_needed"]?.first,
                showBack: true,
                onSelect: { id in selectSingle("storage_needed", id: id) },
                onBack: { goBack() }
            )

        // ── Card 5: Storage unit size [SKIP if no storage] ──
        case storageSizeCard:
            TaskFlowSelect3Card(
                taskTitle: taskTitle,
                question: "What size unit is it?",
                option1: FlowOption(id: "5x5", label: "Small (5×5)", icon: "shippingbox"),
                option2: FlowOption(id: "10x10", label: "Medium (10×10)", icon: "shippingbox.fill"),
                option3: FlowOption(id: "10x20", label: "Large (10×20)", icon: "archivebox.fill"),
                selectedIds: answers["storage_size"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("storage_size", id: id) },
                onBack: { goBack() }
            )

        // ── Card 6: Storage fill level [SKIP if no storage] ──
        case storageFillCard:
            TaskFlowFillBarCard(
                taskTitle: taskTitle,
                question: "About how full is the unit?",
                options: [
                    FlowOption(id: "quarter", label: "~¼", icon: "circle", fillPercent: 0.25),
                    FlowOption(id: "half", label: "~½", icon: "circle", fillPercent: 0.50),
                    FlowOption(id: "three_quarter", label: "~¾", icon: "circle", fillPercent: 0.75),
                    FlowOption(id: "full", label: "Full", icon: "circle", fillPercent: 1.0)
                ],
                selectedId: answers["storage_fullness"]?.first,
                showBack: true,
                onSelect: { id in selectSingle("storage_fullness", id: id) },
                onBack: { goBack() }
            )

        // ── Card 7: Insurance info ──
        case insuranceInfoCard:
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

        // ── Card 8: Additional insurance interest (single + skip) ──
        // Single mode: tapping an option auto-advances via selectSingle.
        // Skip button ("No — free basic coverage") advances without storing an answer.
        case insuranceOptionsCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "Would you be interested in pricing for additional insurance?",
                options: [
                    FlowOption(id: "full_value", label: "Full Coverage — Full Replacement", icon: "shield.checkered"),
                    FlowOption(id: "supplemental", label: "Supplemental Partial Coverage", icon: "shield.lefthalf.filled")
                ],
                mode: .single,
                selectedIds: answers["additional_insurance"] ?? [],
                skipLabel: "No — free basic coverage",
                showBack: true,
                onSelect: { id in selectSingle("additional_insurance", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 9: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                bodyText: "We'll get you quotes from top-rated movers in your area.",
                subtext: "Response times are typically 24–48 hours.",
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
        advance()
    }

    private func toggleMulti(_ key: String, id: String) {
        if answers[key] == nil { answers[key] = [] }
        if answers[key]!.contains(id) {
            answers[key]!.remove(id)
        } else {
            answers[key]!.insert(id)
        }
    }

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
#Preview("Find Movers Flow") {
    FindMoversFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismiss") },
        onStatusAction: { action in print("📋 Status: \(action)") }
    )
}
#endif
