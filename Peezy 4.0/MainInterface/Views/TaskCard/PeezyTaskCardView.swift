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
            }

            Spacer()

            // Task title — right-aligned
            Text(headerTaskTitle.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
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

                if !data.body.isEmpty {
                    accentDivider

                    Text(data.body)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                // Caution icon (e.g. insurance warning)
                if let cautionIcon = data.cautionIcon {
                    Image(systemName: cautionIcon)
                        .font(.system(size: 36))
                        .foregroundStyle(.yellow)
                }

                Text(data.title)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)

                accentDivider

                // Bold prefix + body, or plain body
                if let boldPrefix = data.boldPrefix {
                    (Text(boldPrefix).fontWeight(.bold) + Text(" ") + Text(data.body))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(data.body)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
        let hasFillBars = data.tiles.contains { $0.fillPercent != nil }
        let isCompactPair = data.tiles.count == 2 && data.mode == .single && data.skipLabel == nil && !hasFillBars

            return VStack(spacing: 0) {
            cardHeader

            if isCompactPair {
                // Yes/No layout: question top, tiles pushed toward bottom
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
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
                Spacer()

                HStack(spacing: 12) {
                    ForEach(data.tiles) { tile in
                        compactTile(tile: tile, isSelected: selectedAnswers.contains(tile.id)) {
                            onSelect?(tile.id, tile.isExclusive)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)

            } else {
                // Standard layout: question top, tiles middle
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

                    if data.showDivider {
                        accentDivider
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)

                if hasFillBars {
                    VStack(spacing: 10) {
                        ForEach(data.tiles) { tile in
                            fillBarTile(
                                tile: tile,
                                isSelected: selectedAnswers.contains(tile.id)
                            ) {
                                onSelect?(tile.id, tile.isExclusive)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                } else {
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
                }

                Spacer()

                if data.mode == .multi {
                    PeezyAssessmentButton(selectedAnswers.isEmpty ? "None" : "Continue") {
                        onPrimary()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                } else if let skipLabel = data.skipLabel {
                    PeezyAssessmentButton(skipLabel) {
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
    }

    // MARK: - Compact Tile (side-by-side yes/no)

    private func compactTile(tile: TileOption, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: {
            PeezyHaptics.light()
            onTap()
        }) {
            VStack(spacing: 10) {
                Image(systemName: tile.icon)
                    .font(.system(size: 26))
                    .foregroundStyle(isSelected ? .white : PeezyTheme.Colors.deepInk.opacity(0.4))

                Text(tile.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : PeezyTheme.Colors.deepInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? PeezyTheme.Colors.deepInk : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.primary.opacity(0.07), lineWidth: 1)
            )
            .shadow(
                color: isSelected ? PeezyTheme.Colors.deepInk.opacity(0.2) : Color.black.opacity(0.05),
                radius: isSelected ? 8 : 4,
                x: 0,
                y: isSelected ? 4 : 2
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tile.label)
    }

    // MARK: - Fill Bar Tile (percentage fill)

    private func fillBarTile(tile: TileOption, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        let percent = tile.fillPercent ?? 0
        let textInside = percent >= 0.75

        return Button(action: {
            PeezyHaptics.light()
            onTap()
        }) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.04))

                    // Fill bar
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(PeezyTheme.Colors.deepInk)
                        .frame(width: geo.size.width * percent)

                    // Label — positioned at fill edge
                    HStack(spacing: 0) {
                        if textInside {
                            Spacer()
                                .frame(width: max(0, geo.size.width * percent - labelWidth(tile.label) - 16))
                            Text(tile.label)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.leading, 4)
                        } else {
                            Spacer()
                                .frame(width: geo.size.width * percent + 12)
                            Text(tile.label)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(PeezyTheme.Colors.deepInk)
                        }
                        Spacer()
                    }

                    // Selected checkmark
                    if isSelected {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(textInside ? .white : PeezyTheme.Colors.deepInk)
                                .padding(.trailing, 16)
                        }
                    }
                }
            }
            .frame(height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? PeezyTheme.Colors.deepInk : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tile.label)
    }

    private func labelWidth(_ text: String) -> CGFloat {
        CGFloat(text.count) * 11
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
                    .font(.system(size: 40))
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

                if let subtext = data.subtext {
                    Text(subtext)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.35))
                        .padding(.top, 4)
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
