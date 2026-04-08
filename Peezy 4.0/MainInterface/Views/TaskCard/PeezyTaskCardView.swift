import SwiftUI

// MARK: - Unified Task Card Renderer
// Renders any TaskCardSpec with identical chrome and consistent layout zones.
// All variants: header → spacer → hero content → spacer → button at bottom.

struct PeezyTaskCardView: View {
    let spec: TaskCardSpec
    let isTopCard: Bool
    let showVerifiedBadge: Bool
    let selectedAnswers: Set<String>
    let userState: UserState?
    let onPrimary: () -> Void
    let onSecondary: (() -> Void)?
    let onSelect: ((String, Bool) -> Void)?
    var onConfirmSubmit: (([String: String]) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch spec {
            case .title(let data):
                titleBody(data)
            case .info(let data):
                infoBody(data)
            case .tiles(let data):
                tilesBody(data)
            case .confirm(let data):
                confirmBody(data)
            case .summary(let data):
                summaryBody(data)
            case .paywall:
                paywallBody
            }
        }
        .peezyCardChrome()
    }

    // MARK: - Shared Header

    @ViewBuilder
    private func cardHeader(category: String, icon: String) -> some View {
        if showVerifiedBadge {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(PeezyTheme.Colors.successGreen)
                Text("PEEZY VERIFIED")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(PeezyTheme.Colors.successGreen)
                Spacer()
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
        } else {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(category.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.5)
                Spacer()
            }
            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
            .padding(.top, 24)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Shared Divider

    private var accentDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.15))
            .frame(width: 50, height: 2)
    }

    // MARK: - Title Card

    private func titleBody(_ data: TaskCardTitleData) -> some View {
        VStack(spacing: 0) {
            cardHeader(category: data.category, icon: data.headerIcon)

            Spacer()

            VStack(alignment: .leading, spacing: 15) {
                Text(data.title)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)

                accentDivider

                Text(data.body)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            VStack(spacing: 12) {
                PeezyAssessmentButton(data.primaryLabel) {
                    onPrimary()
                }

                if let secondaryLabel = data.secondaryLabel {
                    Button(secondaryLabel) {
                        onSecondary?()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Info Card

    private func infoBody(_ data: TaskCardInfoData) -> some View {
        VStack(spacing: 0) {
            cardHeader(category: data.category, icon: data.headerIcon)

            Spacer()

            VStack(alignment: .leading, spacing: 15) {
                Text(data.title)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)

                accentDivider

                Text(data.body)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            PeezyAssessmentButton(data.primaryLabel) {
                onPrimary()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Tiles Card

    private func tilesBody(_ data: TaskCardTilesData) -> some View {
        VStack(spacing: 0) {
            cardHeader(category: data.category, icon: data.headerIcon)

            Spacer()

            VStack(alignment: .leading, spacing: 15) {
                Text(data.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)

                if let body = data.body {
                    Text(body)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .lineLimit(2)
                }

                accentDivider
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Tile options
            VStack(spacing: 10) {
                ForEach(data.tiles) { tile in
                    TaskCardTile(
                        tile: tile,
                        isSelected: selectedAnswers.contains(tile.id),
                        onTap: {
                            onSelect?(tile.id, tile.isExclusive)
                        }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            Spacer()

            // Multi-select: show Continue when selection exists
            // Single-select: auto-advances, button hidden
            if data.mode == .multi && !selectedAnswers.isEmpty {
                PeezyAssessmentButton("Continue") {
                    onPrimary()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            } else {
                // Reserve button space to prevent layout shift
                PeezyAssessmentButton("Continue") {}
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .hidden()
            }
        }
    }

    // MARK: - Confirm Card

    private func confirmBody(_ data: TaskCardConfirmData) -> some View {
        ConfirmCardContent(
            data: data,
            userState: userState,
            showVerifiedBadge: showVerifiedBadge,
            onConfirm: { fieldValues in
                onConfirmSubmit?(fieldValues)
                onPrimary()
            },
            onBack: {
                onSecondary?()
            }
        )
    }

    // MARK: - Summary Card

    private func summaryBody(_ data: TaskCardSummaryData) -> some View {
        VStack(spacing: 0) {
            cardHeader(category: data.category, icon: data.headerIcon)

            Spacer()

            VStack(alignment: .leading, spacing: 15) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(PeezyTheme.Colors.successGreen)

                Text(data.title)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                accentDivider

                Text(data.body)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            PeezyAssessmentButton(data.primaryLabel) {
                onPrimary()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Paywall Card

    private var paywallBody: some View {
        VStack(spacing: 0) {
            Spacer()
            // Delegates to existing PaywallGateView
            PaywallGateView(onDismiss: {
                onPrimary()
            })
            Spacer()
        }
    }
}

// MARK: - Previews

#Preview("Title Card") {
    ZStack {
        InteractiveBackground().ignoresSafeArea()
        PeezyTaskCardView(
            spec: .title(TaskCardTitleData(
                cardId: "preview-title",
                category: "Moving",
                headerIcon: "shippingbox",
                title: "Book Movers",
                body: "Find the right moving company for your move and get multiple quotes.",
                primaryLabel: "Let's Go",
                secondaryLabel: "Later"
            )),
            isTopCard: true,
            showVerifiedBadge: false,
            selectedAnswers: [],
            userState: nil,
            onPrimary: {},
            onSecondary: {},
            onSelect: nil,
            onConfirmSubmit: nil
        )
    }
}

#Preview("Info Card") {
    ZStack {
        InteractiveBackground().ignoresSafeArea()
        PeezyTaskCardView(
            spec: .info(TaskCardInfoData(
                cardId: "preview-info",
                category: "Utilities",
                headerIcon: "bolt.fill",
                title: "Why this matters",
                body: "Without internet set up before your move, you could be offline for days. Most providers need 2-3 weeks notice to schedule installation.",
                primaryLabel: "Continue"
            )),
            isTopCard: true,
            showVerifiedBadge: false,
            selectedAnswers: [],
            userState: nil,
            onPrimary: {},
            onSecondary: nil,
            onSelect: nil,
            onConfirmSubmit: nil
        )
    }
}

#Preview("Tiles Card — Verified") {
    ZStack {
        InteractiveBackground().ignoresSafeArea()
        PeezyTaskCardView(
            spec: .tiles(TaskCardTilesData(
                cardId: "preview-tiles",
                category: "Moving",
                headerIcon: "shippingbox",
                title: "How would you like to handle this?",
                body: nil,
                tiles: [
                    TileOption(id: "peezy", label: "Let Peezy handle it", icon: "hands.sparkles.fill", subtitle: "~30 seconds"),
                    TileOption(id: "self", label: "I'll do it myself", icon: "person.fill", subtitle: "Usually 2-3 hours")
                ],
                mode: .single,
                answerKey: "choice",
                workflowQuestionId: nil
            )),
            isTopCard: true,
            showVerifiedBadge: true,
            selectedAnswers: [],
            userState: nil,
            onPrimary: {},
            onSecondary: nil,
            onSelect: { _, _ in },
            onConfirmSubmit: nil
        )
    }
}

#Preview("Summary Card") {
    ZStack {
        InteractiveBackground().ignoresSafeArea()
        PeezyTaskCardView(
            spec: .summary(TaskCardSummaryData(
                cardId: "preview-summary",
                category: "Moving",
                headerIcon: "shippingbox",
                title: "You're all set!",
                body: "We'll take it from here. You can check on this task anytime in the Tasks tab.",
                primaryLabel: "Done"
            )),
            isTopCard: true,
            showVerifiedBadge: false,
            selectedAnswers: [],
            userState: nil,
            onPrimary: {},
            onSecondary: nil,
            onSelect: nil,
            onConfirmSubmit: nil
        )
    }
}
