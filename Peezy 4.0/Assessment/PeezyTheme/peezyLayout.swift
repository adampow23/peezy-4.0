//
//  PeezyLayout.swift
//  PeezyV1.0
//
//  View modifiers and reusable layout components.
//

import SwiftUI

// MARK: - View Extensions

extension View {

    /// Applies standard Peezy card styling (padding + rounded background)
    func peezyCard(backgroundColor: Color = PeezyTheme.Colors.backgroundSecondary) -> some View {
        self
            .padding(PeezyTheme.Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius)
                    .fill(backgroundColor)
            )
    }

    /// Applies small card styling
    func peezyCardSmall(backgroundColor: Color = PeezyTheme.Colors.backgroundSecondary) -> some View {
        self
            .padding(PeezyTheme.Layout.cardPaddingSmall)
            .background(
                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall)
                    .fill(backgroundColor)
            )
    }

    /// Applies standard horizontal padding used throughout the app
    func peezyHorizontalPadding() -> some View {
        self.padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
    }

    /// Applies glass morphism effect for floating UI elements
    func peezyGlassBackground(cornerRadius: CGFloat = PeezyTheme.Layout.cornerRadius) -> some View {
        self.background(
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            }
        )
    }

    /// Applies standard card shadow
    func peezyCardShadow() -> some View {
        self.shadow(
            color: PeezyTheme.Shadows.cardShadowColor,
            radius: PeezyTheme.Shadows.cardShadowRadius,
            x: 0,
            y: PeezyTheme.Shadows.cardShadowY
        )
    }

    /// Applies subtle shadow
    func peezySubtleShadow() -> some View {
        self.shadow(
            color: PeezyTheme.Shadows.subtleShadowColor,
            radius: PeezyTheme.Shadows.subtleShadowRadius,
            x: 0,
            y: PeezyTheme.Shadows.subtleShadowY
        )
    }

    /// Applies button shadow
    func peezyButtonShadow() -> some View {
        self.shadow(
            color: PeezyTheme.Shadows.buttonShadowColor,
            radius: PeezyTheme.Shadows.buttonShadowRadius,
            x: 0,
            y: PeezyTheme.Shadows.buttonShadowY
        )
    }

    /// Applies brand glow effect
    func peezyBrandGlow() -> some View {
        self.shadow(
            color: PeezyTheme.Shadows.brandGlow(),
            radius: 8,
            x: 0,
            y: 4
        )
    }
}

// MARK: - Peezy Primary Button

/// Standard primary action button with brand styling
struct PeezyPrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false

    var body: some View {
        Button {
            PeezyHaptics.medium()
            action()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                } else {
                    Text(title)
                }
            }
            .font(PeezyTheme.Typography.headline)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: PeezyTheme.Layout.buttonHeight)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                        .fill(Color.clear)
                        .peezyLiquidGlass(
                            cornerRadius: PeezyTheme.Layout.cornerRadius,
                            intensity: 0.55,
                            speed: 0.22,
                            tintOpacity: 0.05,
                            highlightOpacity: 0.12
                        )

                    RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                        .fill(PeezyTheme.Colors.brandYellow.opacity(0.10))

                    RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                        .strokeBorder(PeezyTheme.Colors.brandYellow.opacity(0.35), lineWidth: 1)
                }
            )
        }
        .buttonStyle(.peezyPrimary)
        .disabled(isLoading)
    }
}

// MARK: - Peezy Secondary Button

/// Secondary action button
struct PeezySecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            PeezyHaptics.light()
            action()
        } label: {
            Text(title)
                .font(PeezyTheme.Typography.bodyMedium)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: PeezyTheme.Layout.buttonHeightSmall)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                            .fill(Color.clear)
                            .peezyLiquidGlass(
                                cornerRadius: PeezyTheme.Layout.cornerRadiusSmall,
                                intensity: 0.55,
                                speed: 0.22,
                                tintOpacity: 0.05,
                                highlightOpacity: 0.12
                            )

                        RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                            .fill(Color.white.opacity(0.08))

                        RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    }
                )
        }
        .buttonStyle(.peezySecondary)
    }
}

// MARK: - Peezy Section Header

/// Standard section header text
struct PeezySectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(PeezyTheme.Typography.calloutSemibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
    }
}

// MARK: - Peezy Icon Circle

/// Circular icon container with gradient background
struct PeezyIconCircle: View {
    let systemName: String
    var size: CGFloat = PeezyTheme.Layout.iconSizeLarge
    var iconScale: CGFloat = 0.45
    var gradient: LinearGradient = PeezyTheme.Gradients.brandYellowBackground
    var iconColor: Color = PeezyTheme.Colors.brandYellow

    var body: some View {
        ZStack {
            Circle()
                .fill(gradient)
                .frame(width: size, height: size)

            Image(systemName: systemName)
                .font(.system(size: size * iconScale, weight: .semibold))
                .foregroundColor(iconColor)
        }
    }
}

// MARK: - Peezy Divider

/// Styled divider with optional padding
struct PeezyDivider: View {
    var horizontalPadding: CGFloat = PeezyTheme.Layout.horizontalPadding

    var body: some View {
        Divider()
            .padding(.horizontal, horizontalPadding)
    }
}

// MARK: - Peezy Loading View

/// Standard loading indicator
struct PeezyLoadingView: View {
    var message: String?

    var body: some View {
        VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
            ProgressView()
                .scaleEffect(1.2)

            if let message = message {
                Text(message)
                    .font(PeezyTheme.Typography.callout)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Peezy Empty State

/// Standard empty state view
struct PeezyEmptyState: View {
    let systemName: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
            Image(systemName: systemName)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))

            Text(title)
                .font(PeezyTheme.Typography.headline)
                .foregroundColor(.primary)

            Text(message)
                .font(PeezyTheme.Typography.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(PeezyTheme.Layout.sectionSpacing)
    }
}
