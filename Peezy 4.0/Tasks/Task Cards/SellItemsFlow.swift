//
//  SellItemsFlow.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/13/26.
//

import SwiftUI

// MARK: - Sell Items Flow
// Type 6: Complex-Vendor
//
// Card sequence (no skip logic):
//   TitleCard → Multi5 (item types) → Select4 (estimated value)
//   → Multi5 (platforms) → SummaryCard

struct SellItemsFlow: View {
    let taskTitle = "Sell what I don't need"
    let workflowId = "sell_items"

    let userId: String
    let taskId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @Environment(FlowExitCoordinator.self) private var exitCoordinator

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @State private var submissionAttempt = 0
    @State private var terminalSubmissionState = FlowTerminalSubmissionState()

    // MARK: - Card Indices

    private let totalCards = 5

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: totalCards - currentIndex, currentIndex: currentIndex) {
                cardContent
            }

        }
        .resumableFlowProgress(
            path: ["card.\(currentIndex)"],
            answers: FlowProgressCoding.encode(answers)
        ) { restored in
            currentIndex = min(max(FlowProgressCoding.cardIndex(from: restored.path), 0), totalCards - 1)
            answers = FlowProgressCoding.decode(restored.answers)
        }
    }

    // MARK: - Card Router

    @ViewBuilder
    private var cardContent: some View {
        switch currentIndex {

        // ── Card 0: Title ──
        case 0:
            TaskFlowTitleCard(
                taskTitle: taskTitle,
                icon: "tag.fill",
                onContinue: { advance() }
            )

        // ── Card 1: Item types (multi-select) ──
        case 1:
            TaskFlowMulti5Card(
                taskTitle: taskTitle,
                question: "What types of items are you selling?",
                option1: FlowOption(id: "furniture", label: "Furniture", icon: "sofa"),
                option2: FlowOption(id: "appliances", label: "Appliances", icon: "refrigerator"),
                option3: FlowOption(id: "electronics", label: "Electronics", icon: "desktopcomputer"),
                option4: FlowOption(id: "clothing", label: "Clothing / household", icon: "tshirt"),
                option5: FlowOption(id: "outdoor", label: "Outdoor items", icon: "leaf"),
                selectedIds: answers["item_types"] ?? [],
                showBack: true,
                onSelect: { id in toggleMulti("item_types", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 2: Estimated value ──
        case 2:
            TaskFlowSelect4Card(
                taskTitle: taskTitle,
                question: "Roughly, what do you think everything is worth?",
                option1: FlowOption(id: "under_500", label: "Under $500", icon: "dollarsign.circle"),
                option2: FlowOption(id: "500_2000", label: "$500 – $2,000", icon: "dollarsign.circle.fill"),
                option3: FlowOption(id: "2000_5000", label: "$2,000 – $5,000", icon: "banknote"),
                option4: FlowOption(id: "over_5000", label: "$5,000+", icon: "banknote.fill"),
                selectedIds: answers["estimated_value"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("estimated_value", id: id) },
                onBack: { goBack() }
            )

        // ── Card 3: Platforms (multi-select) ──
        case 3:
            TaskFlowMulti5Card(
                taskTitle: taskTitle,
                question: "Which platforms are you open to?",
                option1: FlowOption(id: "fb_marketplace", label: "Facebook Marketplace", icon: "storefront"),
                option2: FlowOption(id: "offerup", label: "OfferUp", icon: "tag"),
                option3: FlowOption(id: "craigslist", label: "Craigslist", icon: "list.bullet"),
                option4: FlowOption(id: "consignment", label: "Consignment store", icon: "building.columns"),
                option5: FlowOption(id: "any", label: "Any of them", icon: "checkmark.circle"),
                selectedIds: answers["platforms"] ?? [],
                showBack: true,
                onSelect: { id in toggleMulti("platforms", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 4: Summary ──
        case 4:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                bodyText: actionSheetText,
                primaryLabel: submissionError == nil ? "Done" : "Try again",
                subtext: submissionError ?? "Use the same facts and photos on each platform you selected.",
                showBack: true,
                onPrimary: { submitAndComplete() },
                onBack: { goBack() }
            )
            .id("summary.\(submissionAttempt)")

        default:
            EmptyView()
        }
    }

    // MARK: - Navigation

    private func advance() {
        guard !exitCoordinator.isTerminalizing else { return }
        guard currentIndex + 1 < totalCards else { return }
        currentIndex += 1
    }

    private func goBack() {
        guard !isSubmitting, !exitCoordinator.isTerminalizing else { return }
        guard currentIndex > 0 else { return }
        currentIndex -= 1
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

    private var actionSheetText: String {
        let itemTypes = labels(
            for: "item_types",
            mapping: [
                "furniture": "furniture", "appliances": "appliances",
                "electronics": "electronics", "clothing": "clothing and household items",
                "outdoor": "outdoor items"
            ]
        )
        let valueBand = labels(
            for: "estimated_value",
            mapping: [
                "under_500": "lower-value group", "500_2000": "midrange group",
                "2000_5000": "higher-value group", "over_5000": "top value range"
            ]
        )
        let platforms = labels(
            for: "platforms",
            mapping: [
                "fb_marketplace": "Facebook Marketplace", "offerup": "OfferUp",
                "craigslist": "Craigslist", "consignment": "a consignment store",
                "any": "any suitable platform"
            ]
        )

        return "You're set. Here's everything you need.\n\nWhat to list\n• Items: \(itemTypes)\n• Value range: \(valueBand)\n• Platforms: \(platforms)\n\nWhat to have ready\nClear photos, dimensions, condition notes, pickup details, and the lowest offer you would accept."
    }

    private func labels(for key: String, mapping: [String: String]) -> String {
        (answers[key] ?? [])
            .map { mapping[$0] ?? $0.replacingOccurrences(of: "_", with: " ") }
            .sorted()
            .joined(separator: ", ")
    }

    // MARK: - Submission

    private func submitAndComplete() {
        guard !isSubmitting else { return }
        isSubmitting = true
        submissionError = nil
        let preSubmitBarrier = exitCoordinator.beginPreSubmitBarrier()

        let workflowAnswers = FlowProgressCoding.workflowAnswers(
            workflowId: workflowId,
            setAnswers: answers
        )

        Task { @MainActor in
            do {
                let persistedFlowAttemptId = try await preSubmitBarrier.value
                try await terminalSubmissionState.run(
                    submit: {
                        let response = try await WorkflowService().submitAnswers(
                            workflowId: workflowId,
                            answers: workflowAnswers,
                            userId: userId,
                            submissionToken: WorkflowSubmissionToken.make(
                                userId: userId,
                                taskId: taskId,
                                workflowId: workflowId,
                                flowAttemptId: persistedFlowAttemptId
                            )
                        )
                        guard response.success else { throw FlowTerminalSubmissionError.rejected }
                    },
                    clear: {
                        exitCoordinator.beginTerminalization()
                        try await exitCoordinator.terminalize {
                            try await TaskActionService().clearFlowState(taskId: taskId)
                        }
                    },
                    onSuccess: {
                        isSubmitting = false
                        onComplete()
                    }
                )
            } catch {
                isSubmitting = false
                exitCoordinator.releaseSubmissionLockAfterFailure()
                if terminalSubmissionState.submissionSucceeded {
                    submissionError = "Your answers were saved, but the completed flow couldn't be cleared. Check your connection, then try again."
                } else {
                    submissionError = "Couldn't save your answers. Check your connection, then try again."
                }
                submissionAttempt += 1
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Sell Items Flow") {
    SellItemsFlow(
        userId: "preview-user",
        taskId: "SELL_ITEMS",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismiss") },
        onStatusAction: { action in print("📋 Status: \(action)") }
    )
}
#endif
