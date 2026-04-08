import SwiftUI

// MARK: - Task Card Stack View
// Renders a TaskCardSequence as a visible 3-card stack.
// Top card is interactive. Cards behind show at reduced scale/offset for depth.
// Advancing removes top card with a leading slide, next card scoots forward.
// Smart advance() skips cards whose showWhen conditions aren't met.

struct PeezyTaskCardStackView: View {
    let sequence: TaskCardSequence
    let userState: UserState?
    let onComplete: () -> Void
    let onSkip: () -> Void
    let onSubmit: ([String: String], String?) -> Void
    let onWorkflowContinue: () -> Void

    @State private var currentIndex: Int = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var confirmFieldValues: [String: String] = [:]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Visible cards: up to 3 starting from currentIndex, skipping hidden ones
    private var visibleCards: [(offset: Int, spec: TaskCardSpec)] {
        var result: [(Int, TaskCardSpec)] = []
        var idx = currentIndex
        while result.count < 3 && idx < sequence.cards.count {
            let spec = sequence.cards[idx]
            // Only include cards whose conditions are met (or have no condition)
            if shouldShowCard(spec) {
                result.append((result.count, spec))
            }
            idx += 1
        }
        return result
    }

    var body: some View {
        ZStack {
            ForEach(visibleCards, id: \.spec.id) { idx, spec in
                PeezyTaskCardView(
                    spec: spec,
                    isTopCard: idx == 0,
                    showBackButton: currentIndex > 0,
                    showVerifiedBadge: sequence.showVerifiedBadge,
                    selectedAnswers: answersForSpec(spec),
                    userState: userState,
                    onPrimary: { handlePrimary(spec: spec) },
                    onSecondary: { handleSecondary(spec: spec) },
                    onBack: { goBack() },
                    onSelect: { optionId, isExclusive in
                        handleSelect(spec: spec, optionId: optionId, isExclusive: isExclusive)
                    },
                    onConfirmSubmit: { fieldValues in
                        confirmFieldValues = fieldValues
                    }
                )
                .scaleEffect(1.0 - CGFloat(idx) * 0.05)
                .offset(y: CGFloat(idx) * 25)
                .zIndex(Double(3 - idx))
                .allowsHitTesting(idx == 0)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.85),
            value: currentIndex
        )
    }

    // MARK: - Condition Check

    private func shouldShowCard(_ spec: TaskCardSpec) -> Bool {
        guard let condition = spec.showWhen else { return true }
        guard let userAnswers = answers[condition.answerKey] else { return false }
        return !condition.requiredValues.isDisjoint(with: userAnswers)
    }

    // MARK: - Answer Lookup

    private func answersForSpec(_ spec: TaskCardSpec) -> Set<String> {
        if case .tiles(let data) = spec {
            return answers[data.answerKey] ?? []
        }
        return []
    }

    // MARK: - Primary Action

    private func handlePrimary(spec: TaskCardSpec) {
        switch spec {
        case .title:
            advance()

        case .info:
            advance()

        case .tiles(let data):
            if data.mode == .multi {
                // Multi-select Continue button tapped (or "None" if empty)
                advance()
                if sequence.needsWorkflowContinue, data.workflowQuestionId != nil {
                    onWorkflowContinue()
                }
            }
            // Single-select handled via handleSelect

        case .confirm:
            let transferChoice = answers["transferChoice"]?.first
            onSubmit(confirmFieldValues, transferChoice)
            advance()

        case .summary:
            onComplete()

        case .paywall:
            onSkip()
        }
    }

    // MARK: - Secondary Action

    private func handleSecondary(spec: TaskCardSpec) {
        switch spec {
        case .title:
            onSkip()

        case .confirm:
            goBack()

        default:
            break
        }
    }

    // MARK: - Tile Selection

    private func handleSelect(spec: TaskCardSpec, optionId: String, isExclusive: Bool) {
        guard case .tiles(let data) = spec else { return }

        if data.mode == .single {
            answers[data.answerKey] = [optionId]

            Task {
                try? await Task.sleep(for: .seconds(0.3))
                advance()
                if sequence.needsWorkflowContinue, data.workflowQuestionId != nil {
                    onWorkflowContinue()
                }
            }
        } else {
            var current = answers[data.answerKey] ?? []
            if isExclusive {
                current = [optionId]
            } else {
                let exclusiveIds = Set(data.tiles.filter { $0.isExclusive }.map { $0.id })
                current = current.subtracting(exclusiveIds)

                if current.contains(optionId) {
                    current.remove(optionId)
                } else {
                    current.insert(optionId)
                }
            }
            answers[data.answerKey] = current
        }
    }

    // MARK: - Navigation

    /// Advance to the next card, skipping any whose showWhen condition isn't met.
    private func advance() {
        var nextIndex = currentIndex + 1
        while nextIndex < sequence.cards.count {
            if shouldShowCard(sequence.cards[nextIndex]) {
                break
            }
            nextIndex += 1
        }
        guard nextIndex < sequence.cards.count else { return }
        currentIndex = nextIndex
    }

    /// Go back to the previous visible card, skipping hidden ones.
    private func goBack() {
        var prevIndex = currentIndex - 1
        while prevIndex >= 0 {
            if shouldShowCard(sequence.cards[prevIndex]) {
                break
            }
            prevIndex -= 1
        }
        guard prevIndex >= 0 else { return }
        currentIndex = prevIndex
    }
}

// MARK: - Preview

#Preview("Full Task Sequence") {
    let sequence = TaskCardSequence(
        id: "preview",
        task: PeezyCard(
            type: .task,
            title: "Book Movers",
            subtitle: "Find the right movers for your move"
        ),
        cards: [
            .tiles(TaskCardTilesData(
                cardId: "t1", category: "Moving", headerIcon: "shippingbox",
                title: "Any really heavy items?", body: "These need special equipment.",
                tiles: [
                    TileOption(id: "piano", label: "Piano / Organ", icon: "pianokeys"),
                    TileOption(id: "safe", label: "Gun Safe / Safe", icon: "lock.shield"),
                    TileOption(id: "hot_tub", label: "Hot Tub / Spa", icon: "drop.fill")
                ],
                mode: .multi, answerKey: "heavy_items", workflowQuestionId: "heavy_items"
            )),
            .tiles(TaskCardTilesData(
                cardId: "t2", category: "Moving", headerIcon: "shippingbox",
                title: "Need storage?", body: nil,
                tiles: [
                    TileOption(id: "yes", label: "Yes", icon: "archivebox"),
                    TileOption(id: "no", label: "No", icon: "xmark.circle")
                ],
                mode: .single, answerKey: "storage_needed", workflowQuestionId: "storage_needed"
            )),
            .tiles(TaskCardTilesData(
                cardId: "t3", category: "Moving", headerIcon: "shippingbox",
                title: "Tell us about your storage", body: nil,
                tiles: [
                    TileOption(id: "5x5_full", label: "Small (5×5) — full", icon: "square.grid.2x2.fill"),
                    TileOption(id: "10x10_partial", label: "Medium (10×10) — partial", icon: "square.grid.3x3")
                ],
                mode: .single, answerKey: "storage_details", workflowQuestionId: "storage_details",
                showWhen: CardCondition(answerKey: "storage_needed", requiredValues: ["yes"])
            )),
            .summary(TaskCardSummaryData(
                cardId: "t4", category: "Moving", headerIcon: "shippingbox",
                title: "Here's what we've got",
                body: "We'll find the top 3 companies and get you quotes.",
                primaryLabel: "Request Quotes"
            ))
        ],
        isPaywallGated: false,
        needsWorkflowContinue: true,
        showVerifiedBadge: true
    )

    ZStack {
        InteractiveBackground().ignoresSafeArea()
        PeezyTaskCardStackView(
            sequence: sequence,
            userState: nil,
            onComplete: { print("Complete") },
            onSkip: { print("Skip") },
            onSubmit: { fields, choice in print("Submit: \(fields)") },
            onWorkflowContinue: { print("Workflow continue") }
        )
    }
}
