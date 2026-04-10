//
//  SetupInternetFlow.swift
//  Peezy 4.0
//

import SwiftUI

// MARK: - Setup Internet Flow
// Complete card flow for the "Schedule internet install" task.
// No skip logic — all 3 questions are shown to every user.

struct SetupInternetFlow: View {
    let taskTitle = "Schedule internet install"
    let workflowId = "setup_internet"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false

    // MARK: - Card Indices

    private let titleCard = 0
    private let usageCard = 1
    private let peopleCountCard = 2
    private let contractPreferenceCard = 3
    private let summaryCard = 4

    private let totalCards = 5

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
                title: "Schedule internet install",
                bodyText: "A few questions to find the best internet options at your new place.",
                primaryLabel: "Continue",
                secondaryLabel: "Go back",
                onPrimary: { advance() },
                onSecondary: { onDismiss() }
            )

        // ── Card 1: Usage (multi-select) ──
        case usageCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "Who's using the internet?",
                subtitle: "Select all that apply.",
                options: [
                    FlowOption(id: "work_from_home", label: "Work from home", icon: "laptopcomputer"),
                    FlowOption(id: "streaming", label: "Streaming (Netflix, YouTube)", icon: "play.tv.fill"),
                    FlowOption(id: "gaming", label: "Gaming", icon: "gamecontroller.fill"),
                    FlowOption(id: "smart_home", label: "Smart home devices", icon: "homekit"),
                    FlowOption(id: "basic", label: "Just browsing and email", icon: "globe"),
                ],
                mode: .multi,
                selectedIds: answers["usage"] ?? [],
                showBack: true,
                onSelect: { id in toggleMulti("usage", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 2: People Count (single-select) ──
        case peopleCountCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "How many people in the household?",
                options: [
                    FlowOption(id: "1_2", label: "1–2", icon: "person"),
                    FlowOption(id: "3_5", label: "3–5", icon: "person.2"),
                    FlowOption(id: "6_plus", label: "6+", icon: "person.3"),
                ],
                mode: .single,
                selectedIds: answers["people_count"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("people_count", id: id) },
                onContinue: nil,
                onBack: { goBack() }
            )

        // ── Card 3: Contract Preference (single-select) ──
        case contractPreferenceCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "Contract preference?",
                options: [
                    FlowOption(id: "month_to_month", label: "Month-to-month", icon: "calendar"),
                    FlowOption(id: "1_year", label: "1 year", icon: "calendar.badge.clock"),
                    FlowOption(id: "2_year", label: "2 year", icon: "calendar.badge.checkmark"),
                    FlowOption(id: "no_preference", label: "No preference", icon: "hand.thumbsup"),
                ],
                mode: .single,
                selectedIds: answers["contract_preference"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("contract_preference", id: id) },
                onContinue: nil,
                onBack: { goBack() }
            )

        // ── Card 4: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                title: "Here's what we've got",
                bodyText: "We'll match you with providers in your area and get you options. We'll reach out as soon as we have them.",
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
#Preview("Setup Internet Flow") {
    SetupInternetFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
