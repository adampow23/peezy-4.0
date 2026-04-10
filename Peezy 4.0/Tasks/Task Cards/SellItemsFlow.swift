//
//  SellItemsFlow.swift
//  Peezy 4.0
//

import SwiftUI

// MARK: - Sell Items Flow
// Complete card flow for the "Sell what you're not bringing" task.
// No skip logic — all 3 questions are shown to every user.

struct SellItemsFlow: View {
    let taskTitle = "Sell what you're not bringing"
    let workflowId = "sell_items"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false

    // MARK: - Card Indices

    private let titleCard = 0
    private let itemCategoriesCard = 1
    private let estimatedValueCard = 2
    private let platformsCard = 3
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
                title: "Sell what you're not bringing",
                bodyText: "A few questions so we can point you in the right direction.",
                primaryLabel: "Continue",
                secondaryLabel: "Go back",
                onPrimary: { advance() },
                onSecondary: { onDismiss() }
            )

        // ── Card 1: Item Categories (multi-select) ──
        case itemCategoriesCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "What are you looking to sell?",
                subtitle: "Select all that apply.",
                options: [
                    FlowOption(id: "furniture", label: "Furniture", icon: "sofa"),
                    FlowOption(id: "electronics", label: "Electronics", icon: "desktopcomputer"),
                    FlowOption(id: "clothing", label: "Clothing", icon: "tshirt"),
                    FlowOption(id: "appliances", label: "Appliances", icon: "refrigerator"),
                    FlowOption(id: "collectibles", label: "Collectibles or valuables", icon: "tag"),
                    FlowOption(id: "other", label: "Other", icon: "shippingbox"),
                ],
                mode: .multi,
                selectedIds: answers["item_categories"] ?? [],
                showBack: true,
                onSelect: { id in toggleMulti("item_categories", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 2: Estimated Value (single-select) ──
        case estimatedValueCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "Roughly, what do you think everything is worth?",
                options: [
                    FlowOption(id: "under_500", label: "Under $500", icon: "dollarsign.circle"),
                    FlowOption(id: "500_2000", label: "$500 – $2,000", icon: "dollarsign.circle.fill"),
                    FlowOption(id: "2000_5000", label: "$2,000 – $5,000", icon: "banknote"),
                    FlowOption(id: "over_5000", label: "$5,000+", icon: "banknote.fill"),
                ],
                mode: .single,
                selectedIds: answers["estimated_value"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("estimated_value", id: id) },
                onContinue: nil,
                onBack: { goBack() }
            )

        // ── Card 3: Platforms (multi-select) ──
        case platformsCard:
            TaskFlowTilesCard(
                taskTitle: taskTitle,
                question: "Which platforms are you open to?",
                subtitle: "Select all you'd be willing to use.",
                options: [
                    FlowOption(id: "fb_marketplace", label: "Facebook Marketplace", icon: "storefront"),
                    FlowOption(id: "offerup", label: "OfferUp", icon: "tag"),
                    FlowOption(id: "craigslist", label: "Craigslist", icon: "list.bullet"),
                    FlowOption(id: "consignment", label: "Consignment store", icon: "building.columns"),
                    FlowOption(id: "any", label: "Any of them", icon: "checkmark.circle"),
                ],
                mode: .multi,
                selectedIds: answers["platforms"] ?? [],
                showBack: true,
                onSelect: { id in toggleMulti("platforms", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 4: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                title: "Nice — let's get these sold",
                bodyText: "I'll put together a game plan based on what you're selling and where.",
                primaryLabel: "Get my selling plan",
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
#Preview("Sell Items Flow") {
    SellItemsFlow(
        userId: "preview-user",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismissed") }
    )
}
#endif
