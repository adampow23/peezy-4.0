import SwiftUI

struct InventoryEstimateView: View {
    let estimate: MovingEstimate
    var onSave: () -> Void
    var onScanMore: () -> Void

    @State private var savePressed = false
    @State private var scanMorePressed = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: PeezyTheme.Layout.sectionSpacing) {
                    // Title
                    VStack(spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                        Text("Your Moving Estimate")
                            .font(PeezyTheme.Typography.title)
                            .foregroundStyle(PeezyTheme.Colors.textPrimary)

                        Text("\(estimate.totalItemCount) items across \(estimate.roomCount) room\(estimate.roomCount == 1 ? "" : "s")")
                            .font(PeezyTheme.Typography.callout)
                            .foregroundStyle(PeezyTheme.Colors.textSecondary)
                    }
                    .padding(.top, PeezyTheme.Layout.sectionSpacing)

                    // 2x2 stat grid
                    statGrid

                    // Warning badges
                    warningBadges

                    // Disclaimer
                    Text("Estimates are based on your scanned inventory. Actual costs depend on distance, access, and seasonal pricing.")
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

    // MARK: - Stat Grid

    private var statGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: PeezyTheme.Layout.verticalSpacing),
            GridItem(.flexible(), spacing: PeezyTheme.Layout.verticalSpacing)
        ], spacing: PeezyTheme.Layout.verticalSpacing) {
            statCard(
                icon: "truck.box.fill",
                value: estimate.recommendedTruckSize,
                label: "Truck Size",
                color: PeezyTheme.Colors.infoBlue
            )
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)

            statCard(
                icon: "cube.fill",
                value: "\(Int(estimate.totalCubicFeet)) cu ft",
                label: "Volume",
                color: PeezyTheme.Colors.brandYellow
            )
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)

            statCard(
                icon: "shippingbox.fill",
                value: "\(estimate.estimatedBoxes)",
                label: "Boxes",
                color: PeezyTheme.Colors.successGreen
            )
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)

            statCard(
                icon: "clock.fill",
                value: formatHours(estimate.estimatedLaborHours),
                label: "Labor",
                color: PeezyTheme.Colors.supportPurple
            )
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
        }
        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
    }

    private func statCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: PeezyTheme.Layout.verticalSpacingSmall) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(color)

            Text(value)
                .font(PeezyTheme.Typography.headline)
                .foregroundStyle(PeezyTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(label)
                .font(PeezyTheme.Typography.footnote)
                .foregroundStyle(PeezyTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(PeezyTheme.Layout.cardPadding)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                    .fill(.regularMaterial)

                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.15))

                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            }
        )
        .shadow(color: PeezyTheme.Shadows.subtleShadowColor, radius: PeezyTheme.Shadows.subtleShadowRadius, x: 0, y: PeezyTheme.Shadows.subtleShadowY)
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
            // Save & Finish
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

            // Scan More Rooms
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

    // MARK: - Helpers

    private func formatHours(_ hours: Double) -> String {
        if hours == Double(Int(hours)) {
            return "\(Int(hours)) hrs"
        }
        return String(format: "%.1f hrs", hours)
    }
}
