//
//  TransferUtilitiesFlow.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/13/26.
//

import SwiftUI

// MARK: - Transfer Utilities Flow
// TYPE 3: DECISION ONLY — Peezy path: confirm address → submit.
//                          Self path: tip → status card.
//
// Card 0: TitleCard
// Card 1: DecisionCard
// Card 2: ConfirmAddressCard  [SKIP if self]
// Card 3: SummaryCard         [SKIP if self]
// Card 4: InfoCard (tip)      [SKIP if peezy]
// Card 5: StatusCard          [SKIP if peezy]
// totalCards = 6

struct TransferUtilitiesFlow: View {
    let taskTitle = "Transfer my utilities"
    let workflowId = "transfer_utilities"

    let userId: String
    let currentAddress: String  // newAddress from UserState (destination)
    let moveDate: Date
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false

    // MARK: - Card Indices

    private let titleCard = 0
    private let decisionCard = 1
    private let confirmAddressCard = 2
    private let summaryCard = 3
    private let tipCard = 4
    private let statusCard = 5
    private let totalCards = 6

    // MARK: - Path Logic

    private var wantsPeezy: Bool {
        answers["handling"]?.contains("peezy") == true
    }

    // MARK: - Skip Logic

    private func shouldSkip(_ index: Int) -> Bool {
        switch index {
        case confirmAddressCard, summaryCard:
            return !wantsPeezy
        case tipCard, statusCard:
            return wantsPeezy
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

        case titleCard:
            TaskFlowTitleCard(
                taskTitle: taskTitle,
                icon: "bolt.fill",
                onContinue: { advance() }
            )

        case decisionCard:
            TaskFlowDecisionCard(
                taskTitle: taskTitle,
                timeSaved: "~1.5 hrs",
                showBack: true,
                onPeezy: {
                    answers["handling"] = ["peezy"]
                    advance()
                },
                onSelf: {
                    answers["handling"] = ["self"]
                    advance()
                },
                onBack: { goBack() }
            )

        case confirmAddressCard:
            TaskFlowConfirmAddressCard(
                taskTitle: taskTitle,
                question: "Is this your new address?",
                currentAddress: currentAddress,
                displayIcon: "mappin.and.ellipse",
                showBack: true,
                onConfirm: { address in
                    answers["confirmed_address"] = [address]
                    advance()
                },
                onBack: { goBack() }
            )

        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                bodyText: "We'll contact each provider to transfer service to your new address with no overlap in billing.",
                subtext: "Response times are typically 24–48 hours.",
                showBack: true,
                onPrimary: { submitAndComplete() },
                onBack: { goBack() }
            )

        case tipCard:
            TaskFlowInfoCard(
                taskTitle: taskTitle,
                title: "Good to Know",
                bodyText: "Same provider = no new deposit, no credit check, no setup fee.",
                primaryLabel: "Got it",
                showBack: true,
                onPrimary: { advance() },
                onBack: { goBack() }
            )

        case statusCard:
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
#Preview("Transfer Utilities Flow") {
    TransferUtilitiesFlow(
        userId: "preview-user",
        currentAddress: "4201 Main St, Denver, CO 80205",
        moveDate: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date(),
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismiss") },
        onStatusAction: { action in print("📋 Status: \(action)") }
    )
}
#endif
