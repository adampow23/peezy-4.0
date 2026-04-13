//
//  SetupInternetFlow.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/13/26.
//

import SwiftUI

// MARK: - Setup Internet Flow
// Type 6: Complex-Vendor
//
// Card sequence (no skip logic):
//   TitleCard → Multi5 (usage) → Select3 (household size)
//   → Select4 (contract preference) → SummaryCard

struct SetupInternetFlow: View {
    let taskTitle = "Set up my internet"
    let workflowId = "setup_internet"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false

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
                icon: "wifi",
                onContinue: { advance() }
            )

        // ── Card 1: Internet usage (multi-select) ──
        case 1:
            TaskFlowMulti5Card(
                taskTitle: taskTitle,
                question: "Who's using the internet?",
                option1: FlowOption(id: "work_from_home", label: "Work from home", icon: "laptopcomputer"),
                option2: FlowOption(id: "streaming", label: "Streaming", icon: "play.tv.fill"),
                option3: FlowOption(id: "gaming", label: "Gaming", icon: "gamecontroller.fill"),
                option4: FlowOption(id: "smart_home", label: "Smart home devices", icon: "homekit"),
                option5: FlowOption(id: "basic", label: "Just browsing and email", icon: "globe"),
                selectedIds: answers["internet_usage"] ?? [],
                showBack: true,
                onSelect: { id in toggleMulti("internet_usage", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 2: Household size ──
        case 2:
            TaskFlowSelect3Card(
                taskTitle: taskTitle,
                question: "How many people in the household?",
                option1: FlowOption(id: "1_2", label: "1–2", icon: "person"),
                option2: FlowOption(id: "3_5", label: "3–5", icon: "person.2"),
                option3: FlowOption(id: "6_plus", label: "6+", icon: "person.3"),
                selectedIds: answers["household_size"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("household_size", id: id) },
                onBack: { goBack() }
            )

        // ── Card 3: Contract preference ──
        case 3:
            TaskFlowSelect4Card(
                taskTitle: taskTitle,
                question: "Contract preference?",
                option1: FlowOption(id: "month_to_month", label: "Month-to-month", icon: "calendar"),
                option2: FlowOption(id: "1_year", label: "1 year", icon: "calendar.badge.clock"),
                option3: FlowOption(id: "2_year", label: "2 year", icon: "calendar.badge.checkmark"),
                option4: FlowOption(id: "no_preference", label: "No preference", icon: "hand.thumbsup"),
                selectedIds: answers["contract_preference"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("contract_preference", id: id) },
                onBack: { goBack() }
            )

        // ── Card 4: Summary ──
        case 4:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                bodyText: "We'll match you with providers in your area and get you options.",
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
#Preview("Setup Internet Flow") {
    SetupInternetFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismiss") },
        onStatusAction: { action in print("📋 Status: \(action)") }
    )
}
#endif
