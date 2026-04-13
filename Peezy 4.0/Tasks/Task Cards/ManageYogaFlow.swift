//
//  ManageYogaFlow.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/12/26.
//

import SwiftUI

// MARK: - Manage Yoga Flow

struct ManageYogaFlow: View {
    let taskTitle = "Handle my yoga membership"
    let workflowId = "manage_yoga"

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
            return "We'll cancel your current membership and help find you a new studio near your new place."
        } else if cancelWantsPeezy {
            return "We'll cancel your current membership. You're all set to find a new one on your own."
        } else {
            return "We'll help find you a new studio near your new place."
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
                icon: "figure.yoga",
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

        // ── Card 3: Which studio? (Peezy needs to know) ──
        case updateBusinessCard:
            TaskFlowBusinessSearchCard(
                taskTitle: taskTitle,
                question: "Which studio do you go to?",
                placeholder: "Search for a yoga studio...",
                searchHint: "yoga studio",
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
                bodyText: "We'll reach out to your studio and get your address updated.",
                showBack: true,
                onPrimary: { submitAndComplete() },
                onBack: { goBack() }
            )

        // ── Card 5: Update Tip (Self path) ──
        case updateTipCard:
            TaskFlowInfoCard(
                taskTitle: taskTitle,
                title: "Good to Know",
                bodyText: "Most studios let you update your address online through your account settings or their app. If not, a quick call to the front desk usually takes less than 5 minutes.",
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
                onLater: { onStatusAction(.later) },
                onInProgress: { onStatusAction(.inProgress) },
                onDone: { onStatusAction(.done) },
                onBack: { goBack() }
            )

        // ═══════════════════════════════════════
        // FIND NEW PATH
        // ═══════════════════════════════════════

        // ── Card 7: Want help canceling your current membership? ──
        case cancelDecisionCard:
            TaskFlowDecisionCard(
                taskTitle: taskTitle,
                question: "Want help canceling your current membership?",
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

        // ── Card 8: Which studio are you canceling? (Peezy needs to know) ──
        case cancelBusinessCard:
            TaskFlowBusinessSearchCard(
                taskTitle: taskTitle,
                question: "Which studio are you canceling?",
                placeholder: "Search for a yoga studio...",
                searchHint: "yoga studio",
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
                question: "Would you like help finding a new studio near your new place?",
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
                bodyText: "Check your membership terms for cancellation requirements — some need 30 days written notice. For the new place, check if your current chain has a location nearby before signing up somewhere new.",
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
#Preview("Manage Yoga Flow") {
    ManageYogaFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismiss") },
        onStatusAction: { action in print("📋 Status: \(action)") }
    )
}
#endif
