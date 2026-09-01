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

    private let totalCards = 8

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
                bodyText: actionSheetText,
                primaryLabel: submissionError == nil ? "Done" : "Try again",
                subtext: submissionError ?? "Confirm accepted items, access requirements, and timing before scheduling.",
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
        let intent = labels(for: "disposal_intent", mapping: [
            "donate": "donate", "haul_away": "haul away", "not_sure": "compare donation and haul-away options"
        ])
        let items = labels(for: "item_types", mapping: [
            "furniture": "furniture", "appliances": "appliances", "electronics": "electronics",
            "mattresses": "mattresses", "household": "household items and clothing", "outdoor": "outdoor items or debris"
        ])
        let condition = labels(for: "item_condition", mapping: [
            "like_new": "like new", "gently_used": "gently used", "worn": "worn but functional", "needs_repair": "needs repair"
        ])
        let quantity = labels(for: "quantity", mapping: [
            "few_small": "a few small items", "several_large": "several large items",
            "full_room": "a full room", "multiple_rooms": "multiple rooms"
        ])
        let location = labels(for: "item_location", mapping: [
            "ground_floor": "inside on the ground floor", "upstairs": "upstairs, basement, or attic",
            "garage": "garage", "curbside": "curbside or driveway"
        ])
        let handoff = labels(for: "pickup_preference", mapping: [
            "need_pickup": "pickup needed", "can_dropoff": "drop-off works", "either": "pickup or drop-off"
        ])

        return "You're set. Here's everything you need.\n\nWhat to say\n“I need to \(intent) \(quantity) of \(items). They are \(condition), located \(location), and \(handoff). What do you accept and what access do you need?”\n\nWhat to have ready\nPhotos, item dimensions, stairs or elevator details, parking access, and preferred dates."
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
#Preview("Remove Items Flow") {
    RemoveItemsFlow(
        userId: "preview-user",
        taskId: "REMOVE_ITEMS",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismiss") },
        onStatusAction: { action in print("📋 Status: \(action)") }
    )
}
#endif
