//
//  RemoveItemsFlow.swift
//  Peezy 4.0
//

import SwiftUI

// MARK: - Remove Items Flow
// Complete card flow for the "Schedule donation pickup" task.
// No skip logic — all 6 questions are shown to every user.

struct RemoveItemsFlow: View {
    let taskTitle = "Schedule donation pickup"
    let workflowId = "remove_items"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false

    // MARK: - Card Indices

    private let titleCard = 0
    private let removalRouteCard = 1
    private let itemCategoriesCard = 2
    private let itemConditionCard = 3
    private let quantityCard = 4
    private let itemLocationCard = 5
    private let pickupPreferenceCard = 6
    private let summaryCard = 7

    private let totalCards = 8

    // MARK: - Body

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: totalCards - currentIndex, currentIndex: currentIndex) {
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
                title: "Schedule donation pickup",
                bodyText: "A few questions to find the right option for you.",
                primaryLabel: "Continue",
                secondaryLabel: "Go back",
                onPrimary: { advance() },
                onSecondary: { onDismiss() }
            )

        // ── Card 1: Removal Route (single-select) ──
        case removalRouteCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "What are you looking to do with these items?",
                options: [
                    FlowOption(id: "donate", label: "Donate them", icon: "heart"),
                    FlowOption(id: "haul_away", label: "Have them hauled away", icon: "truck.box"),
                    FlowOption(id: "not_sure", label: "Not sure — help me decide", icon: "questionmark.circle"),
                ],
                mode: .single,
                selectedIds: answers["removal_route"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("removal_route", id: id) },
                onContinue: nil,
                onBack: { goBack() }
            )

        // ── Card 2: Item Categories (multi-select) ──
        case itemCategoriesCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "What types of items are we talking about?",
                subtitle: "Select all that apply.",
                options: [
                    FlowOption(id: "furniture", label: "Furniture", icon: "sofa"),
                    FlowOption(id: "appliances", label: "Appliances", icon: "refrigerator"),
                    FlowOption(id: "electronics", label: "Electronics", icon: "desktopcomputer"),
                    FlowOption(id: "mattresses", label: "Mattresses", icon: "bed.double"),
                    FlowOption(id: "household", label: "Household / clothing", icon: "house"),
                    FlowOption(id: "outdoor", label: "Outdoor / debris", icon: "leaf"),
                ],
                mode: .multi,
                selectedIds: answers["item_categories"] ?? [],
                showBack: true,
                onSelect: { id in toggleMulti("item_categories", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 3: Item Condition (single-select) ──
        case itemConditionCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "What condition are most of the items in?",
                options: [
                    FlowOption(id: "like_new", label: "Like new", icon: "star.fill"),
                    FlowOption(id: "gently_used", label: "Gently used", icon: "star.leadinghalf.filled"),
                    FlowOption(id: "worn", label: "Worn but functional", icon: "star"),
                    FlowOption(id: "needs_repair", label: "Needs repair", icon: "wrench"),
                ],
                mode: .single,
                selectedIds: answers["item_condition"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("item_condition", id: id) },
                onContinue: nil,
                onBack: { goBack() }
            )

        // ── Card 4: Quantity (single-select) ──
        case quantityCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "How much stuff are we talking about?",
                options: [
                    FlowOption(id: "few_small", label: "A few small items", icon: "bag"),
                    FlowOption(id: "several_large", label: "Several large items", icon: "shippingbox"),
                    FlowOption(id: "full_room", label: "A full room's worth", icon: "sofa.fill"),
                    FlowOption(id: "multiple_rooms", label: "Multiple rooms", icon: "building.2"),
                ],
                mode: .single,
                selectedIds: answers["quantity"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("quantity", id: id) },
                onContinue: nil,
                onBack: { goBack() }
            )

        // ── Card 5: Item Location (single-select) ──
        case itemLocationCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "Where are the items right now?",
                options: [
                    FlowOption(id: "ground_floor", label: "Inside home — ground floor", icon: "house"),
                    FlowOption(id: "upstairs", label: "Inside home — upstairs, basement, or attic", icon: "stairs"),
                    FlowOption(id: "garage", label: "Garage", icon: "car.garage"),
                    FlowOption(id: "curbside", label: "Curbside or driveway", icon: "road.lanes"),
                ],
                mode: .single,
                selectedIds: answers["item_location"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("item_location", id: id) },
                onContinue: nil,
                onBack: { goBack() }
            )

        // ── Card 6: Pickup Preference (single-select) ──
        case pickupPreferenceCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "Can you drop items off, or do you need them picked up?",
                options: [
                    FlowOption(id: "need_pickup", label: "I need pickup", icon: "truck.box"),
                    FlowOption(id: "can_dropoff", label: "I can drop off", icon: "arrow.down.to.line"),
                    FlowOption(id: "either", label: "Either works", icon: "arrow.left.arrow.right"),
                ],
                mode: .single,
                selectedIds: answers["pickup_preference"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("pickup_preference", id: id) },
                onContinue: nil,
                onBack: { goBack() }
            )

        // ── Card 7: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                title: "Got it — I'll find the best option",
                bodyText: "Based on your answers, I'll match you with the right service to get these items taken care of.",
                primaryLabel: "Find my options",
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
        guard currentIndex - 1 >= 0 else { return }
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
#Preview("Remove Items Flow") {
    RemoveItemsFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
