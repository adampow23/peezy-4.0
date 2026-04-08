import SwiftUI

// MARK: - Task Card Stack View
// Renders a TaskCardSequence as a visible 3-card stack.
// Top card is interactive. Cards behind show at reduced scale/offset for depth.
// Advancing removes top card with a leading slide, next card scoots forward.

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

    // Visible cards: up to 3 starting from currentIndex
    private var visibleCards: [(offset: Int, spec: TaskCardSpec)] {
        let endIndex = min(currentIndex + 3, sequence.cards.count)
        guard currentIndex < endIndex else { return [] }
        return Array(sequence.cards[currentIndex..<endIndex]).enumerated().map { ($0.offset, $0.element) }
    }

    var body: some View {
        ZStack {
            ForEach(visibleCards, id: \.spec.id) { idx, spec in
                PeezyTaskCardView(
                    spec: spec,
                    isTopCard: idx == 0,
                    showVerifiedBadge: sequence.showVerifiedBadge,
                    selectedAnswers: answersForSpec(spec),
                    userState: userState,
                    onPrimary: { handlePrimary(spec: spec) },
                    onSecondary: { handleSecondary(spec: spec) },
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
                // Multi-select Continue button tapped
                advance()
                if sequence.needsWorkflowContinue, data.workflowQuestionId != nil {
                    onWorkflowContinue()
                }
            }
            // Single-select handled via handleSelect

        case .confirm:
            // "Looks Good" — submit and advance
            let transferChoice = answers["transferChoice"]?.first
            onSubmit(confirmFieldValues, transferChoice)
            advance()

        case .summary:
            // "Done" — complete the task
            onComplete()

        case .paywall:
            // Paywall dismissed (user subscribed or cancelled)
            // If subscribed, advance past paywall to show task content
            advance()
        }
    }

    // MARK: - Secondary Action

    private func handleSecondary(spec: TaskCardSpec) {
        switch spec {
        case .title:
            // "Later" — skip the whole task
            onSkip()

        case .confirm:
            // "Go Back" — go back one card
            if currentIndex > 0 {
                currentIndex -= 1
            }

        default:
            break
        }
    }

    // MARK: - Tile Selection

    private func handleSelect(spec: TaskCardSpec, optionId: String, isExclusive: Bool) {
        guard case .tiles(let data) = spec else { return }

        if data.mode == .single {
            // Single-select: set answer and auto-advance
            answers[data.answerKey] = [optionId]

            // Check if user chose "self" on a Peezy/self choice — adjust remaining sequence
            // (The builder already included all possible cards; the stack just advances through them)

            // Delay then advance
            Task {
                try? await Task.sleep(for: .seconds(0.3))
                advance()
                if sequence.needsWorkflowContinue, data.workflowQuestionId != nil {
                    onWorkflowContinue()
                }
            }
        } else {
            // Multi-select: toggle
            var current = answers[data.answerKey] ?? []
            if isExclusive {
                // Exclusive option: clear all others, set this one
                current = [optionId]
            } else {
                // Remove any exclusive options when selecting a non-exclusive
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

    private func advance() {
        guard currentIndex < sequence.cards.count - 1 else { return }
        currentIndex += 1
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
            .title(TaskCardTitleData(
                cardId: "t1", category: "Moving", headerIcon: "shippingbox",
                title: "Book Movers", body: "Find the right movers for your move.",
                primaryLabel: "Let's Go", secondaryLabel: "Later"
            )),
            .info(TaskCardInfoData(
                cardId: "t2", category: "Moving", headerIcon: "shippingbox",
                title: "Why this matters",
                body: "Booking movers early gets you better rates and availability.",
                primaryLabel: "Continue"
            )),
            .tiles(TaskCardTilesData(
                cardId: "t3", category: "Moving", headerIcon: "shippingbox",
                title: "How would you like to handle this?", body: nil,
                tiles: [
                    TileOption(id: "peezy", label: "Let Peezy handle it", icon: "hands.sparkles.fill", subtitle: "~30 seconds"),
                    TileOption(id: "self", label: "I'll do it myself", icon: "person.fill", subtitle: "Usually 2-3 hours")
                ],
                mode: .single, answerKey: "choice", workflowQuestionId: nil
            )),
            .summary(TaskCardSummaryData(
                cardId: "t4", category: "Moving", headerIcon: "shippingbox",
                title: "You're all set!",
                body: "We'll take it from here.",
                primaryLabel: "Done"
            ))
        ],
        isPaywallGated: false,
        needsWorkflowContinue: false,
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
