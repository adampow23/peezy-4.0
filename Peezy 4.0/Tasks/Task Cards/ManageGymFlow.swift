//
//  ManageGymFlow.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/12/26.
//

import SwiftUI

// MARK: - Manage Gym Flow
// REFERENCE FILE for Type 2: Manage-Provider
// Full branching flow: Update address OR Find a new one.
//
// UPDATE PATH:
//   TitleCard → Select2 (action) → DecisionCard (help?) →
//     YES: BusinessSearch → SummaryCard
//     NO:  InfoCard (tip) → StatusCard
//
// FIND NEW PATH:
//   TitleCard → Select2 (action) → DecisionCard (help canceling?) →
//     YES: BusinessSearch (current provider) →
//     NO:  (skip search) →
//   DecisionCard (help finding new?) →
//     Either YES: SummaryCard
//     Both NO:    InfoCard (tip) → StatusCard
//
// Nothing saves until SummaryCard submission. If the user bails mid-flow,
// the task stays untouched in their queue. They open it again, start fresh.

struct ManageGymFlow: View {
    let taskTitle = "Handle my gym membership"
    let workflowId = "manage_gym"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    // Status callbacks for self-service ending
    let onSnooze: () -> Void
    let onMarkInProgress: () -> Void
    let onMarkDone: () -> Void

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false

    // MARK: - Card Indices

    private let titleCard = 0
    private let actionCard = 1

    // Update path
    private let updateDecisionCard = 2
    private let updateBusinessCard = 3
    private let updateSummaryCard = 4
    private let updateTipCard = 5
    private let updateStatusCard = 6

    // Find new path
    private let cancelDecisionCard = 7
    private let cancelBusinessCard = 8
    private let findDecisionCard = 9
    private let findSummaryCard = 10
    private let findTipCard = 11
    private let findStatusCard = 12

    private let totalCards = 13

    // MARK: - Path Logic

    private var isUpdatePath: Bool {
        answers["action"]?.contains("update") == true
    }

    private var isFindNewPath: Bool {
        answers["action"]?.contains("find_new") == true
    }

    private var updateWantsPeezy: Bool {
        answers["handling_update"]?.contains("peezy") == true
    }

    private var cancelWantsPeezy: Bool {
        answers["handling_cancel"]?.contains("peezy") == true
    }

    private var findWantsPeezy: Bool {
        answers["handling_find"]?.contains("peezy") == true
    }

    private var eitherPeezy: Bool {
        cancelWantsPeezy || findWantsPeezy
    }

    // MARK: - Dynamic Summary Text

    private var findNewSummaryText: String {
        if cancelWantsPeezy && findWantsPeezy {
            return "We'll cancel your current membership and help find you a new gym near your new place."
        } else if cancelWantsPeezy {
            return "We'll cancel your current membership. You're all set to find a new gym on your own."
        } else {
            return "We'll help find you a new gym near your new place."
        }
    }

    // MARK: - Skip Logic

    private func shouldSkip(_ index: Int) -> Bool {
        switch index {

        // Update path — skip all if find_new chosen
        case updateDecisionCard:
            return isFindNewPath
        case updateBusinessCard:
            return isFindNewPath || !updateWantsPeezy
        case updateSummaryCard:
            return isFindNewPath || !updateWantsPeezy
        case updateTipCard:
            return isFindNewPath || updateWantsPeezy
        case updateStatusCard:
            return isFindNewPath || updateWantsPeezy

        // Find new path — skip all if update chosen
        case cancelDecisionCard:
            return isUpdatePath
        case cancelBusinessCard:
            return isUpdatePath || !cancelWantsPeezy
        case findDecisionCard:
            return isUpdatePath
        case findSummaryCard:
            return isUpdatePath || !eitherPeezy
        case findTipCard:
            return isUpdatePath || eitherPeezy
        case findStatusCard:
            return isUpdatePath || eitherPeezy

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
        // SHARED — Title + Action Choice
        // ═══════════════════════════════════════

        // ── Card 0: Title ──
        case titleCard:
            TaskFlowTitleCard(
                taskTitle: taskTitle,
                icon: "dumbbell.fill",
                onContinue: { advance() }
            )

        // ── Card 1: Update or Find New (single-select) ──
        case actionCard:
            TaskFlowSelect2Card(
                taskTitle: taskTitle,
                question: "What would you like to do?",
                option1: FlowOption(id: "update", label: "Update my address", icon: "pencil.line"),
                option2: FlowOption(id: "find_new", label: "Find a new one", icon: "magnifyingglass"),
                selectedIds: answers["action"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("action", id: id) },
                onBack: { goBack() }
            )

        // ═══════════════════════════════════════
        // UPDATE PATH
        // ═══════════════════════════════════════

        // ── Card 2: Want us to handle the update? ──
        case updateDecisionCard:
            TaskFlowDecisionCard(
                taskTitle: taskTitle,
                showBack: true,
                onPeezy: {
                    answers["handling_update"] = ["peezy"]
                    advance()
                },
                onSelf: {
                    answers["handling_update"] = ["self"]
                    advance()
                },
                onBack: { goBack() }
            )

        // ── Card 3: Which gym? (Peezy needs to know) ──
        case updateBusinessCard:
            TaskFlowBusinessSearchCard(
                taskTitle: taskTitle,
                question: "Which gym do you go to?",
                placeholder: "Search for a gym...",
                searchHint: "gym",
                selectedBusiness: answers["business_name"]?.first,
                showBack: true,
                onConfirm: { name in
                    answers["business_name"] = [name]
                    advance()
                },
                onBack: { goBack() }
            )

        // ── Card 4: Update Summary (Peezy path) ──
        case updateSummaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                bodyText: "We'll reach out to your gym and get your address updated.",
                showBack: true,
                onPrimary: { submitAndComplete() },
                onBack: { goBack() }
            )

        // ── Card 5: Update Tip (Self path) ──
        case updateTipCard:
            TaskFlowInfoCard(
                taskTitle: taskTitle,
                title: "Good to Know",
                bodyText: "Most gyms let you update your address online through your account settings or their app. If not, a quick call to the front desk usually takes less than 5 minutes.",
                primaryLabel: "Got it",
                showBack: true,
                onPrimary: { advance() },
                onBack: { goBack() }
            )

        // ── Card 6: Update Status (Self path) ──
        case updateStatusCard:
            TaskFlowStatusCard(
                taskTitle: taskTitle,
                showBack: true,
                onLater: { onSnooze() },
                onInProgress: { onMarkInProgress() },
                onDone: { onMarkDone() },
                onBack: { goBack() }
            )

        // ═══════════════════════════════════════
        // FIND NEW PATH
        // ═══════════════════════════════════════

        // ── Card 7: Want help canceling your current one? ──
        case cancelDecisionCard:
            TaskFlowDecisionCard(
                taskTitle: taskTitle,
                question: "First, do you want help canceling your current membership?",
                showBack: true,
                onPeezy: {
                    answers["handling_cancel"] = ["peezy"]
                    advance()
                },
                onSelf: {
                    answers["handling_cancel"] = ["self"]
                    advance()
                },
                onBack: { goBack() }
            )

        // ── Card 8: Which gym are you canceling? (Peezy needs to know) ──
        case cancelBusinessCard:
            TaskFlowBusinessSearchCard(
                taskTitle: taskTitle,
                question: "Which gym are you canceling?",
                placeholder: "Search for a gym...",
                searchHint: "gym",
                selectedBusiness: answers["current_business"]?.first,
                showBack: true,
                onConfirm: { name in
                    answers["current_business"] = [name]
                    advance()
                },
                onBack: { goBack() }
            )

        // ── Card 9: Want help finding a new one? ──
        case findDecisionCard:
            TaskFlowDecisionCard(
                taskTitle: taskTitle,
                question: "Would you like help finding a new gym near your new place?",
                showBack: true,
                onPeezy: {
                    answers["handling_find"] = ["peezy"]
                    advance()
                },
                onSelf: {
                    answers["handling_find"] = ["self"]
                    advance()
                },
                onBack: { goBack() }
            )

        // ── Card 10: Find New Summary (either Peezy) ──
        case findSummaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                bodyText: findNewSummaryText,
                showBack: true,
                onPrimary: { submitAndComplete() },
                onBack: { goBack() }
            )

        // ── Card 11: Find New Tip (both self) ──
        case findTipCard:
            TaskFlowInfoCard(
                taskTitle: taskTitle,
                title: "Good to Know",
                bodyText: "Call your gym to cancel — most require a phone call or in-person visit. For the new place, check if your current chain has a location nearby before signing up somewhere new.",
                primaryLabel: "Got it",
                showBack: true,
                onPrimary: { advance() },
                onBack: { goBack() }
            )

        // ── Card 12: Find New Status (both self) ──
        case findStatusCard:
            TaskFlowStatusCard(
                taskTitle: taskTitle,
                showBack: true,
                onLater: { onSnooze() },
                onInProgress: { onMarkInProgress() },
                onDone: { onMarkDone() },
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
#Preview("Manage Gym Flow") {
    ManageGymFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismiss") },
        onSnooze: { print("🕐 Later") },
        onMarkInProgress: { print("➡️ In Progress") },
        onMarkDone: { print("✅ Done") }
    )
}
#endif
