//
//  RemoveItemsFlow.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/13/26.
//

import SwiftUI

// MARK: - Remove Items Flow
// Type 6: Complex-Vendor
//
// Card sequence (no skip logic):
//   TitleCard → Select3 (disposal intent) → Multi6 (item types)
//   → Select4 (condition) → Select4 (quantity) → Select4 (location)
//   → Select3 (pickup/dropoff) → SummaryCard

struct RemoveItemsFlow: View {
    let taskTitle = "Schedule my donation pickup"
    let workflowId = "remove_items"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false

    // MARK: - Card Indices

    private let totalCards = 8

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: totalCards - currentIndex, currentIndex: currentIndex) {
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
        case 0:
            TaskFlowTitleCard(
                taskTitle: taskTitle,
                icon: "arrow.up.bin.fill",
                onContinue: { advance() }
            )

        // ── Card 1: Disposal intent ──
        case 1:
            TaskFlowSelect3Card(
                taskTitle: taskTitle,
                question: "What are you looking to do with these items?",
                option1: FlowOption(id: "donate", label: "Donate them", icon: "heart"),
                option2: FlowOption(id: "haul_away", label: "Have them hauled away", icon: "truck.box"),
                option3: FlowOption(id: "not_sure", label: "Not sure — help me decide", icon: "questionmark.circle"),
                selectedIds: answers["disposal_intent"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("disposal_intent", id: id) },
                onBack: { goBack() }
            )

        // ── Card 2: Item types (multi-select) ──
        case 2:
            TaskFlowMulti6Card(
                taskTitle: taskTitle,
                question: "What types of items are we talking about?",
                option1: FlowOption(id: "furniture", label: "Furniture", icon: "sofa"),
                option2: FlowOption(id: "appliances", label: "Appliances", icon: "refrigerator"),
                option3: FlowOption(id: "electronics", label: "Electronics", icon: "desktopcomputer"),
                option4: FlowOption(id: "mattresses", label: "Mattresses", icon: "bed.double"),
                option5: FlowOption(id: "household", label: "Household / clothing", icon: "house"),
                option6: FlowOption(id: "outdoor", label: "Outdoor / debris", icon: "leaf"),
                selectedIds: answers["item_types"] ?? [],
                showBack: true,
                onSelect: { id in toggleMulti("item_types", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 3: Item condition ──
        case 3:
            TaskFlowSelect4Card(
                taskTitle: taskTitle,
                question: "What condition are most of the items in?",
                option1: FlowOption(id: "like_new", label: "Like new", icon: "star.fill"),
                option2: FlowOption(id: "gently_used", label: "Gently used", icon: "star.leadinghalf.filled"),
                option3: FlowOption(id: "worn", label: "Worn but functional", icon: "star"),
                option4: FlowOption(id: "needs_repair", label: "Needs repair", icon: "wrench"),
                selectedIds: answers["item_condition"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("item_condition", id: id) },
                onBack: { goBack() }
            )

        // ── Card 4: Quantity ──
        case 4:
            TaskFlowSelect4Card(
                taskTitle: taskTitle,
                question: "How much stuff are we talking about?",
                option1: FlowOption(id: "few_small", label: "A few small items", icon: "bag"),
                option2: FlowOption(id: "several_large", label: "Several large items", icon: "shippingbox"),
                option3: FlowOption(id: "full_room", label: "A full room's worth", icon: "sofa.fill"),
                option4: FlowOption(id: "multiple_rooms", label: "Multiple rooms", icon: "building.2"),
                selectedIds: answers["quantity"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("quantity", id: id) },
                onBack: { goBack() }
            )

        // ── Card 5: Current location of items ──
        case 5:
            TaskFlowSelect4Card(
                taskTitle: taskTitle,
                question: "Where are the items right now?",
                option1: FlowOption(id: "ground_floor", label: "Inside home — ground floor", icon: "house"),
                option2: FlowOption(id: "upstairs", label: "Upstairs, basement, or attic", icon: "stairs"),
                option3: FlowOption(id: "garage", label: "Garage", icon: "car.garage"),
                option4: FlowOption(id: "curbside", label: "Curbside or driveway", icon: "road.lanes"),
                selectedIds: answers["item_location"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("item_location", id: id) },
                onBack: { goBack() }
            )

        // ── Card 6: Pickup or drop-off ──
        case 6:
            TaskFlowSelect3Card(
                taskTitle: taskTitle,
                question: "Do you need them picked up, or can you drop them off?",
                option1: FlowOption(id: "need_pickup", label: "I need pickup", icon: "truck.box"),
                option2: FlowOption(id: "can_dropoff", label: "I can drop off", icon: "arrow.down.to.line"),
                option3: FlowOption(id: "either", label: "Either works", icon: "arrow.left.arrow.right"),
                selectedIds: answers["pickup_preference"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("pickup_preference", id: id) },
                onBack: { goBack() }
            )

        // ── Card 7: Summary ──
        case 7:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                bodyText: "We'll find the best option for your items and get it scheduled.",
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
#Preview("Remove Items Flow") {
    RemoveItemsFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismiss") },
        onStatusAction: { action in print("📋 Status: \(action)") }
    )
}
#endif
