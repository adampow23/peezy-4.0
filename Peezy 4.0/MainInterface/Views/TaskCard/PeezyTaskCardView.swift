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
                // Store field values — parent handles via onPrimary
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

// MARK: - Task Card Tile

struct TaskCardTile: View {
    let tile: TileOption
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: {
            PeezyHaptics.light()
            onTap()
        }) {
            HStack(spacing: 14) {
                Image(systemName: tile.icon)
                    .font(.system(size: 20))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.label)
                        .font(.system(size: 16, weight: .medium))
                    if let subtitle = tile.subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? PeezyTheme.Colors.deepInk : Color.clear)
            )
            .foregroundStyle(isSelected ? .white : PeezyTheme.Colors.deepInk)
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
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
            .animation(reduceMotion ? nil : .spring(response: 0.2), value: isPressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tile.label)
        .accessibilityHint(tile.subtitle ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Confirm Card Content

struct ConfirmCardContent: View {
    let data: TaskCardConfirmData
    let userState: UserState?
    let showVerifiedBadge: Bool
    let onConfirm: ([String: String]) -> Void
    let onBack: () -> Void

    @State private var fieldValues: [String: String] = [:]
    @State private var editingFieldLabel: String?
    @State private var hasInitialized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
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
                    Image(systemName: data.headerIcon)
                        .font(.system(size: 11))
                    Text(data.category.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.5)
                    Spacer()
                }
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                .padding(.top, 24)
                .padding(.horizontal, 24)
            }

            // Title
            VStack(alignment: .leading, spacing: 6) {
                Text("Just to confirm...")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)

                Text("For: \(data.taskTitle)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Rectangle()
                    .fill(Color.black.opacity(0.15))
                    .frame(width: 50, height: 2)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            // Scrollable fields
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(data.fields) { field in
                        confirmFieldRow(field)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)

            // Buttons
            VStack(spacing: 12) {
                PeezyAssessmentButton("Looks Good") {
                    onConfirm(fieldValues)
                }

                Button("Go Back") {
                    onBack()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true
            initializeFieldValues()
        }
    }

    private func initializeFieldValues() {
        for field in data.fields {
            switch field.fieldType {
            case .currentAddress:
                let parts = [userState?.originCity, userState?.originState].compactMap { $0 }
                fieldValues[field.label] = parts.isEmpty ? "Not provided" : parts.joined(separator: ", ")
            case .newAddress:
                let parts = [userState?.destinationCity, userState?.destinationState].compactMap { $0 }
                fieldValues[field.label] = parts.isEmpty ? "Not provided" : parts.joined(separator: ", ")
            case .moveDate:
                if let moveDate = userState?.moveDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    fieldValues[field.label] = formatter.string(from: moveDate)
                } else {
                    fieldValues[field.label] = "Not set"
                }
            case .userInput:
                fieldValues[field.label] = ""
            }
        }
    }

    @ViewBuilder
    private func confirmFieldRow(_ field: ConfirmField) -> some View {
        let isEditing = editingFieldLabel == field.label

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(field.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                    .textCase(.uppercase)

                Spacer()

                if case .userInput = field.fieldType {
                    // Always editable
                } else {
                    Button(isEditing ? "Done" : "Edit") {
                        PeezyHaptics.light()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            editingFieldLabel = isEditing ? nil : field.label
                        }
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isEditing ? PeezyTheme.Colors.accentBlue : .secondary)
                    .frame(minHeight: 44)
                    .padding(.leading, 8)
                }
            }

            if case .userInput(let placeholder) = field.fieldType {
                confirmInputField(placeholder: placeholder, key: field.label)
            } else if isEditing {
                confirmInputField(placeholder: field.label, key: field.label)
            } else {
                Text(fieldValues[field.label, default: ""])
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func confirmInputField(placeholder: String, key: String) -> some View {
        TextField(placeholder, text: Binding(
            get: { fieldValues[key, default: ""] },
            set: { fieldValues[key] = $0 }
        ), axis: .vertical)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(PeezyTheme.Colors.deepInk)
            .frame(minHeight: 44)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.04))
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                }
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
            onSelect: nil
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
            onSelect: nil
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
            onSelect: { _, _ in }
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
            onSelect: nil
        )
    }
}
