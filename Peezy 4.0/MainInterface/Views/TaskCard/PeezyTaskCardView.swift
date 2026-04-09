import SwiftUI

// MARK: - Unified Task Card Renderer

struct PeezyTaskCardView: View {
    let spec: TaskCardSpec
    let isTopCard: Bool
    let showBackButton: Bool
    let showVerifiedBadge: Bool
    let selectedAnswers: Set<String>
    let userState: UserState?
    let onPrimary: () -> Void
    let onSecondary: (() -> Void)?
    let onBack: (() -> Void)?
    let onSelect: ((String, Bool) -> Void)?
    var onConfirmSubmit: (([String: String]) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Extract task title from any spec variant for the header
    private var headerTaskTitle: String {
        switch spec {
        case .title(let d): return d.taskTitle
        case .info(let d): return d.taskTitle
        case .tiles(let d): return d.taskTitle
        case .confirm(let d): return d.taskTitle
        case .summary(let d): return d.taskTitle
        case .paywall: return ""
        }
    }

    var body: some View {
        Group {
            switch spec {
            case .title(let data):  titleBody(data)
            case .info(let data):   infoBody(data)
            case .tiles(let data):  tilesBody(data)
            case .confirm(let data): confirmBody(data)
            case .summary(let data): summaryBody(data)
            case .paywall:          paywallBody
            }
        }
        .peezyCardChrome()
    }

    // MARK: - Header (always shows task name)

    private var cardHeader: some View {
        HStack(spacing: 6) {
            // Back button
            if showBackButton, let onBack {
                Button(action: {
                    PeezyHaptics.light()
                    onBack()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }

            // Verified badge icon (if applicable)
            if showVerifiedBadge {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(PeezyTheme.Colors.successGreen)
            }

            // Task title — always visible, always tells user what task this is
            Text(headerTaskTitle.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(showVerifiedBadge ? PeezyTheme.Colors.successGreen : PeezyTheme.Colors.deepInk.opacity(0.5))

            Spacer()
        }
        .padding(.top, 24)
        .padding(.horizontal, 24)
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
            cardHeader

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
            cardHeader

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

                if let urlString = data.linkURL, let url = URL(string: urlString) {
                    Link(data.linkLabel ?? "Open link", destination: url)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PeezyTheme.Colors.accentBlue)
                        .padding(.top, 8)
                }
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
            cardHeader

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

            if data.mode == .multi {
                PeezyAssessmentButton(selectedAnswers.isEmpty ? "None" : "Continue") {
                    onPrimary()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            } else {
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
            showBackButton: showBackButton,
            onConfirm: { fieldValues in
                onConfirmSubmit?(fieldValues)
                onPrimary()
            },
            onBack: {
                onBack?()
            }
        )
    }

    // MARK: - Summary Card

    private func summaryBody(_ data: TaskCardSummaryData) -> some View {
        VStack(spacing: 0) {
            cardHeader

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
                cardId: "p1", category: "Moving", headerIcon: "shippingbox",
                taskTitle: "Book Movers",
                title: "Let's get this sorted",
                body: "Find the right moving company for your move and get multiple quotes.",
                primaryLabel: "Let's Go", secondaryLabel: "Later"
            )),
            isTopCard: true, showBackButton: false, showVerifiedBadge: false,
            selectedAnswers: [], userState: nil,
            onPrimary: {}, onSecondary: {}, onBack: nil, onSelect: nil, onConfirmSubmit: nil
        )
    }
}

#Preview("Info Card") {
    ZStack {
        InteractiveBackground().ignoresSafeArea()
        PeezyTaskCardView(
            spec: .info(TaskCardInfoData(
                cardId: "p2", category: "Utilities", headerIcon: "bolt.fill",
                taskTitle: "Set Up Internet",
                title: "Here's what to know",
                body: "Without internet set up before your move, you could be offline for days.",
                primaryLabel: "Continue"
            )),
            isTopCard: true, showBackButton: true, showVerifiedBadge: false,
            selectedAnswers: [], userState: nil,
            onPrimary: {}, onSecondary: nil, onBack: {}, onSelect: nil, onConfirmSubmit: nil
        )
    }
}

#Preview("Tiles — Verified") {
    ZStack {
        InteractiveBackground().ignoresSafeArea()
        PeezyTaskCardView(
            spec: .tiles(TaskCardTilesData(
                cardId: "p3", category: "Moving", headerIcon: "shippingbox",
                title: "How would you like to handle this?",
                tiles: [
                    TileOption(id: "peezy", label: "Let Peezy handle it", icon: "hands.sparkles.fill", subtitle: "~30 seconds"),
                    TileOption(id: "self", label: "I'll do it myself", icon: "person.fill", subtitle: "Usually 2-3 hours")
                ],
                mode: .single, answerKey: "choice",
                taskTitle: "Book Movers"
            )),
            isTopCard: true, showBackButton: true, showVerifiedBadge: true,
            selectedAnswers: [], userState: nil,
            onPrimary: {}, onSecondary: nil, onBack: {}, onSelect: { _, _ in }, onConfirmSubmit: nil
        )
    }
}

#Preview("Summary Card") {
    ZStack {
        InteractiveBackground().ignoresSafeArea()
        PeezyTaskCardView(
            spec: .summary(TaskCardSummaryData(
                cardId: "p4", category: "Moving", headerIcon: "shippingbox",
                taskTitle: "Book Movers",
                title: "You're all set!",
                body: "We'll take it from here.",
                primaryLabel: "Done"
            )),
            isTopCard: true, showBackButton: true, showVerifiedBadge: false,
            selectedAnswers: [], userState: nil,
            onPrimary: {}, onSecondary: nil, onBack: {}, onSelect: nil, onConfirmSubmit: nil
        )
    }
}
