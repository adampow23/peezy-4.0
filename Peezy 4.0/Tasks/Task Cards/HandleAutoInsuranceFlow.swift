//
//  HandleAutoInsuranceFlow.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/12/26.
//

import SwiftUI

// MARK: - Handle Auto Insurance Flow
// REFERENCE FILE for Type 4: Insurance
// Consolidated flow replacing update_auto_insurance.
//
// 4 PATHS:
//   NO INSURANCE:  TitleCard → HasInsurance(No) → InfoCard (why you need it) → StatusCard
//   HAS AGENT:     TitleCard → HasInsurance(Yes) → HelpChoice(Agent) → InfoCard (what to tell agent) → StatusCard
//   UPDATE:        TitleCard → HasInsurance(Yes) → HelpChoice(Help) → Action(Update) → BusinessSearch → SummaryCard
//   SWITCH:        TitleCard → HasInsurance(Yes) → HelpChoice(Help) → Action(Switch) → BusinessSearch → QuoteChoice → SummaryCard
//
// Nothing saves until SummaryCard submission. If the user bails mid-flow,
// the task stays untouched in their queue.

struct HandleAutoInsuranceFlow: View {
    let taskTitle = "Handle my auto insurance"
    let workflowId = "handle_auto_insurance"

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
    private let hasInsuranceCard = 1
    private let helpChoiceCard = 2
    private let actionCard = 3

    // Update path
    private let updateSearchCard = 4
    private let updateSummaryCard = 5

    // Switch path
    private let switchSearchCard = 6
    private let quoteChoiceCard = 7
    private let switchSummaryCard = 8

    // No insurance path
    private let noInsuranceInfoCard = 9
    private let noInsuranceStatusCard = 10

    // Agent path
    private let agentInfoCard = 11
    private let agentStatusCard = 12

    private let totalCards = 13

    // MARK: - Path Logic

    private var hasInsurance: Bool {
        answers["has_insurance"]?.contains("yes") == true
    }

    private var noInsurance: Bool {
        answers["has_insurance"]?.contains("no") == true
    }

    private var choseAgent: Bool {
        answers["help_choice"]?.contains("agent") == true
    }

    private var choseHelp: Bool {
        answers["help_choice"]?.contains("help") == true
    }

    private var isUpdatePath: Bool {
        answers["action"]?.contains("update") == true
    }

    private var isSwitchPath: Bool {
        answers["action"]?.contains("switch") == true
    }

    // MARK: - Dynamic Summary Text

    private var switchSummaryText: String {
        if answers["quote_choice"]?.contains("keep") == true {
            return "We'll reach out to \(providerName) about switching your policy to cover your new place."
        } else {
            return "We'll get you 3 options — one from \(providerName) and two of the best alternatives."
        }
    }

    private var providerName: String {
        answers["provider_name"]?.first ?? "your provider"
    }

    // MARK: - Skip Logic

    private func shouldSkip(_ index: Int) -> Bool {
        switch index {

        // Help/Agent choice — only if they have insurance
        case helpChoiceCard:
            return noInsurance || !hasInsurance

        // Action choice — only if they have insurance AND chose help
        case actionCard:
            return !hasInsurance || !choseHelp

        // Update path — only if has insurance + help + update
        case updateSearchCard, updateSummaryCard:
            return !(hasInsurance && choseHelp && isUpdatePath)

        // Switch path — only if has insurance + help + switch
        case switchSearchCard, quoteChoiceCard, switchSummaryCard:
            return !(hasInsurance && choseHelp && isSwitchPath)

        // No insurance path — only if they said no
        case noInsuranceInfoCard, noInsuranceStatusCard:
            return !noInsurance

        // Agent path — only if they chose agent
        case agentInfoCard, agentStatusCard:
            return !choseAgent

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

        // ═══════════════════════════════════════
        // SHARED — Title + Has Insurance + Help/Agent
        // ═══════════════════════════════════════

        // ── Card 0: Title ──
        case titleCard:
            TaskFlowTitleCard(
                taskTitle: taskTitle,
                icon: "car.fill",
                onContinue: { advance() }
            )

        // ── Card 1: Do you have auto insurance? ──
        case hasInsuranceCard:
            TaskFlowCompactTilesCard(
                taskTitle: taskTitle,
                question: "Do you currently have auto insurance?",
                options: [
                    FlowOption(id: "yes", label: "Yes", icon: "hand.thumbsup.fill"),
                    FlowOption(id: "no", label: "No", icon: "hand.thumbsdown.fill")
                ],
                selectedId: answers["has_insurance"]?.first,
                showBack: true,
                onSelect: { id in selectSingle("has_insurance", id: id) },
                onBack: { goBack() }
            )

        // ── Card 2: Help or Agent? ──
        case helpChoiceCard:
            TaskFlowSelect2Card(
                taskTitle: taskTitle,
                question: "How would you like to handle this?",
                option1: FlowOption(id: "help", label: "I'd like help", icon: "hands.sparkles.fill"),
                option2: FlowOption(id: "agent", label: "I have an agent", icon: "person.fill"),
                selectedIds: answers["help_choice"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("help_choice", id: id) },
                onBack: { goBack() }
            )

        // ── Card 3: Update or Switch? ──
        case actionCard:
            TaskFlowSelect2Card(
                taskTitle: taskTitle,
                question: "What would you like to do?",
                option1: FlowOption(id: "update", label: "Update my address", icon: "pencil.line"),
                option2: FlowOption(id: "switch", label: "Switch to a new policy", icon: "arrow.triangle.swap"),
                selectedIds: answers["action"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("action", id: id) },
                onBack: { goBack() }
            )

        // ═══════════════════════════════════════
        // UPDATE PATH
        // ═══════════════════════════════════════

        // ── Card 4: Who's your provider? ──
        case updateSearchCard:
            TaskFlowBusinessSearchCard(
                taskTitle: taskTitle,
                question: "Who's your current provider?",
                placeholder: "Search for an insurance company...",
                searchHint: "auto insurance",
                selectedBusiness: answers["provider_name"]?.first,
                showBack: true,
                onConfirm: { name in
                    answers["provider_name"] = [name]
                    advance()
                },
                onBack: { goBack() }
            )

        // ── Card 5: Update Summary ──
        case updateSummaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                bodyText: "We'll reach out to \(providerName) and get your address updated.",
                showBack: true,
                onPrimary: { submitAndComplete() },
                onBack: { goBack() }
            )

        // ═══════════════════════════════════════
        // SWITCH PATH
        // ═══════════════════════════════════════

        // ── Card 6: Who do you have it with now? ──
        case switchSearchCard:
            TaskFlowBusinessSearchCard(
                taskTitle: taskTitle,
                question: "Who do you have it with now?",
                placeholder: "Search for an insurance company...",
                searchHint: "auto insurance",
                selectedBusiness: answers["provider_name"]?.first,
                showBack: true,
                onConfirm: { name in
                    answers["provider_name"] = [name]
                    advance()
                },
                onBack: { goBack() }
            )

        // ── Card 7: Keep provider or get quotes? ──
        case quoteChoiceCard:
            TaskFlowSelect2Card(
                taskTitle: taskTitle,
                question: "Would you like to stay with \(providerName), or get quotes from others too?",
                option1: FlowOption(id: "keep", label: "Keep my current provider", icon: "checkmark.circle"),
                option2: FlowOption(id: "quotes", label: "Get quotes from others too", icon: "doc.text.magnifyingglass"),
                selectedIds: answers["quote_choice"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("quote_choice", id: id) },
                onBack: { goBack() }
            )

        // ── Card 8: Switch Summary ──
        case switchSummaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                bodyText: switchSummaryText,
                showBack: true,
                onPrimary: { submitAndComplete() },
                onBack: { goBack() }
            )

        // ═══════════════════════════════════════
        // NO INSURANCE PATH
        // ═══════════════════════════════════════

        // ── Card 9: Why you might need it ──
        case noInsuranceInfoCard:
            TaskFlowInfoCard(
                taskTitle: taskTitle,
                title: "Good to Know",
                bodyText: "Most states require auto insurance to legally drive. If you're getting a car at your new place, you'll need a policy before registration.",
                primaryLabel: "Got it",
                showBack: true,
                onPrimary: { advance() },
                onBack: { goBack() }
            )

        // ── Card 10: No Insurance Status ──
        case noInsuranceStatusCard:
            TaskFlowStatusCard(
                taskTitle: taskTitle,
                showBack: true,
                onLater: { onStatusAction(.later) },
                onInProgress: { onStatusAction(.inProgress) },
                onDone: { onStatusAction(.done) },
                onBack: { goBack() }
            )

        // ═══════════════════════════════════════
        // AGENT PATH
        // ═══════════════════════════════════════

        // ── Card 11: What to tell your agent ──
        case agentInfoCard:
            TaskFlowInfoCard(
                taskTitle: taskTitle,
                title: "Good to Know",
                bodyText: "Here's what to tell your agent: your new address, your move date, and whether your housing type is changing. Ask them to confirm your new rate before the move — rates change by zip code.",
                primaryLabel: "Got it",
                showBack: true,
                onPrimary: { advance() },
                onBack: { goBack() }
            )

        // ── Card 12: Agent Status ──
        case agentStatusCard:
            TaskFlowStatusCard(
                taskTitle: taskTitle,
                showBack: true,
                onLater: { onStatusAction(.later) },
                onInProgress: { onStatusAction(.inProgress) },
                onDone: { onStatusAction(.done) },
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
#Preview("Handle Auto Insurance") {
    HandleAutoInsuranceFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismiss") },
        onStatusAction: { action in print("📋 Status: \(action)") }
    )
}
#endif
