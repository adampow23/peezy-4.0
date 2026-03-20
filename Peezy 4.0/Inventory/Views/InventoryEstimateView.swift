import SwiftUI

struct InventoryEstimateView: View {
    let estimate: MovingEstimate
    var onSave: () -> Void
    var onScanMore: () -> Void

    @State private var savePressed = false
    @State private var scanMorePressed = false
    @State private var appeared = false
    @State private var furnitureExpanded = false

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: PeezyTheme.Layout.sectionSpacing) {
                    // Title
                    VStack(spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                        Text("Your Scan Summary")
                            .font(PeezyTheme.Typography.title)
                            .foregroundStyle(PeezyTheme.Colors.textPrimary)

                        Text("\(estimate.totalItemCount) items across \(estimate.roomCount) room\(estimate.roomCount == 1 ? "" : "s")")
                            .font(PeezyTheme.Typography.callout)
                            .foregroundStyle(PeezyTheme.Colors.textSecondary)
                    }
                    .padding(.top, PeezyTheme.Layout.sectionSpacing)

                    // Packing estimate card
                    packingCard

                    // Furniture summary
                    if !estimate.furnitureItems.isEmpty {
                        furnitureCard
                    }

                    // Warning badges
                    warningBadges

                    // Disclaimer
                    Text("Packing varies from person to person — these are ballpark numbers. Your inventory will be shared with moving companies so they can provide accurate estimates for your move.")
                        .font(PeezyTheme.Typography.footnote)
                        .foregroundStyle(PeezyTheme.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)

                    // Buttons
                    buttons
                        .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            withAnimation(PeezyTheme.Animation.springSlow) {
                appeared = true
            }
        }
    }

    // MARK: - Packing Card

    private var packingCard: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
            HStack(spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.warningOrange)

                Text("Packing Estimate")
                    .font(PeezyTheme.Typography.headline)
                    .foregroundStyle(PeezyTheme.Colors.textPrimary)
            }

            HStack(spacing: PeezyTheme.Layout.sectionSpacing) {
                // Boxes
                VStack(spacing: 4) {
                    Text(estimate.boxRangeDescription)
                        .font(PeezyTheme.Typography.title2)
                        .foregroundStyle(PeezyTheme.Colors.textPrimary)
                    Text("estimated")
                        .font(PeezyTheme.Typography.footnote)
                        .foregroundStyle(PeezyTheme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 40)

                // Packing time
                VStack(spacing: 4) {
                    Text(estimate.packingTimeDescription)
                        .font(PeezyTheme.Typography.title2)
                        .foregroundStyle(PeezyTheme.Colors.textPrimary)
                    Text("to pack")
                        .font(PeezyTheme.Typography.footnote)
                        .foregroundStyle(PeezyTheme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }

            Text("Every household packs differently — this is a ballpark based on what we found during your scan.")
                .font(PeezyTheme.Typography.caption)
                .foregroundStyle(PeezyTheme.Colors.textTertiary)
        }
        .padding(PeezyTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .shadow(color: PeezyTheme.Shadows.subtleShadowColor, radius: PeezyTheme.Shadows.subtleShadowRadius, x: 0, y: PeezyTheme.Shadows.subtleShadowY)
        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }

    // MARK: - Furniture Card

    private var furnitureCard: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
            HStack(spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                Image(systemName: "sofa.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.supportPurple)

                Text("Furniture & Large Items")
                    .font(PeezyTheme.Typography.headline)
                    .foregroundStyle(PeezyTheme.Colors.textPrimary)

                Spacer()

                Text("\(estimate.furnitureItems.count)")
                    .font(PeezyTheme.Typography.headline)
                    .foregroundStyle(PeezyTheme.Colors.textTertiary)
            }

            // Always show first few, expandable for the rest
            let previewCount = 5
            let itemsToShow = furnitureExpanded ? estimate.furnitureItems : Array(estimate.furnitureItems.prefix(previewCount))

            VStack(spacing: 8) {
                ForEach(Array(itemsToShow.enumerated()), id: \.offset) { index, item in
                    HStack {
                        Text(item.name)
                            .font(PeezyTheme.Typography.callout)
                            .foregroundStyle(PeezyTheme.Colors.textPrimary)

                        if item.quantity > 1 {
                            Text("×\(item.quantity)")
                                .font(PeezyTheme.Typography.callout)
                                .foregroundStyle(PeezyTheme.Colors.textTertiary)
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            if item.isFragile {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(PeezyTheme.Colors.warningOrange)
                            }
                            if item.isHighValue {
                                Image(systemName: "shield.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(PeezyTheme.Colors.supportPurple)
                            }
                        }

                        Text(item.roomName)
                            .font(PeezyTheme.Typography.caption)
                            .foregroundStyle(PeezyTheme.Colors.textTertiary)
                    }

                    if index < itemsToShow.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.1))
                    }
                }
            }

            if estimate.furnitureItems.count > previewCount {
                Button {
                    withAnimation(PeezyTheme.Animation.spring) {
                        furnitureExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(furnitureExpanded ? "Show less" : "Show all \(estimate.furnitureItems.count) items")
                            .font(PeezyTheme.Typography.callout)
                            .foregroundStyle(PeezyTheme.Colors.infoBlue)
                        Image(systemName: furnitureExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PeezyTheme.Colors.infoBlue)
                    }
                }
            }
        }
        .padding(PeezyTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .shadow(color: PeezyTheme.Shadows.subtleShadowColor, radius: PeezyTheme.Shadows.subtleShadowRadius, x: 0, y: PeezyTheme.Shadows.subtleShadowY)
        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }

    // MARK: - Warning Badges

    @ViewBuilder
    private var warningBadges: some View {
        VStack(spacing: PeezyTheme.Layout.verticalSpacingSmall) {
            if estimate.fragileItemCount > 0 {
                warningBadge(
                    icon: "exclamationmark.triangle.fill",
                    text: "\(estimate.fragileItemCount) fragile item\(estimate.fragileItemCount == 1 ? "" : "s") — consider specialty packing",
                    color: PeezyTheme.Colors.warningOrange
                )
            }

            if estimate.highValueItemCount > 0 {
                warningBadge(
                    icon: "shield.fill",
                    text: "\(estimate.highValueItemCount) high-value item\(estimate.highValueItemCount == 1 ? "" : "s") — consider moving insurance",
                    color: PeezyTheme.Colors.supportPurple
                )
            }
        }
        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
    }

    private func warningBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: PeezyTheme.Layout.verticalSpacingSmall) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)

            Text(text)
                .font(PeezyTheme.Typography.callout)
                .foregroundStyle(PeezyTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PeezyTheme.Layout.cardPaddingSmall)
        .background(
            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }

    // MARK: - Buttons

    private var buttons: some View {
        VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
            Button {
                savePressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    savePressed = false
                    onSave()
                }
            } label: {
                Text("Save & Finish")
                    .font(PeezyTheme.Typography.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .frame(height: PeezyTheme.Layout.buttonHeight)
                    .frame(maxWidth: .infinity)
                    .background(PeezyTheme.Gradients.brandYellow)
                    .clipShape(RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusPill, style: .continuous))
                    .shadow(color: PeezyTheme.Shadows.buttonShadowColor, radius: PeezyTheme.Shadows.buttonShadowRadius, x: 0, y: PeezyTheme.Shadows.buttonShadowY)
            }
            .scaleEffect(savePressed ? PeezyTheme.Animation.pressScale : 1.0)
            .animation(PeezyTheme.Animation.spring, value: savePressed)

            Button {
                scanMorePressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    scanMorePressed = false
                    onScanMore()
                }
            } label: {
                Text("Scan More Rooms")
                    .font(PeezyTheme.Typography.headline)
                    .foregroundStyle(PeezyTheme.Colors.textPrimary)
                    .frame(height: PeezyTheme.Layout.buttonHeight)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusPill, style: .continuous))
            }
            .scaleEffect(scanMorePressed ? PeezyTheme.Animation.pressScale : 1.0)
            .animation(PeezyTheme.Animation.spring, value: scanMorePressed)
        }
        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
    }

    // MARK: - Shared Background

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.15))
            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
    }
}
