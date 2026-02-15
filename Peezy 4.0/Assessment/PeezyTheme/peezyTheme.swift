//
//  PeezyTheme.swift
//  PeezyV1.0
//
//  Centralized design system for the Peezy app.
//  All colors, typography, layout constants, animations, and shadows.
//

import SwiftUI

// MARK: - TimeOfDay

/// Time-of-day helper for dynamic theming
enum TimeOfDay {
    case morning    // 0-11 (before noon)
    case afternoon  // 12-16 (noon to 5pm)
    case evening    // 17-23 (5pm to midnight)

    /// Current time of day based on system clock (or simulated date in DEBUG)
    static var current: TimeOfDay {
        let hour = Calendar.current.component(.hour, from: DateProvider.shared.now)
        switch hour {
        case 0..<12: return .morning
        case 12..<17: return .afternoon
        default: return .evening
        }
    }

    /// Greeting text for the time of day
    var greeting: String {
        switch self {
        case .morning: return "Good morning"
        case .afternoon: return "Good afternoon"
        case .evening: return "Good evening"
        }
    }

    /// Icon for the empty state view
    var emptyStateIcon: String {
        switch self {
        case .morning, .afternoon: return "sun.max.fill"
        case .evening: return "moon.stars.fill"
        }
    }

    /// Headline text for empty state
    var emptyStateHeadline: String {
        switch self {
        case .morning: return "Great start!"
        case .afternoon: return "Nice work!"
        case .evening: return "Relax."
        }
    }

    /// Background base color for the time of day
    var baseColor: Color {
        switch self {
        case .morning: return Color(red: 0.03, green: 0.06, blue: 0.12)    // Dark blue tint
        case .afternoon: return Color(red: 0.05, green: 0.05, blue: 0.1)   // Neutral dark
        case .evening: return Color(red: 0.02, green: 0.02, blue: 0.06)    // Current deep space
        }
    }

    /// Background orb colors (primary, secondary, accent)
    var orbColors: (primary: Color, secondary: Color, accent: Color) {
        switch self {
        case .morning:
            return (
                Color(red: 0.2, green: 0.35, blue: 0.6),    // Sky blue
                Color(red: 0.6, green: 0.4, blue: 0.2),     // Warm orange
                Color(red: 0.5, green: 0.45, blue: 0.2)     // Golden
            )
        case .afternoon:
            return (
                Color(red: 0.25, green: 0.4, blue: 0.65),   // Bright blue
                Color(red: 0.55, green: 0.35, blue: 0.2),   // Orange
                Color(red: 0.15, green: 0.4, blue: 0.35)    // Teal
            )
        case .evening:
            return (
                Color(red: 0.1, green: 0.1, blue: 0.25),    // Deep navy (current)
                Color(red: 0.18, green: 0.1, blue: 0.3),    // Purple (current)
                Color(red: 0.05, green: 0.2, blue: 0.25)    // Teal (current)
            )
        }
    }

    /// Icon gradient for empty state
    @ViewBuilder
    var emptyStateIconStyle: some View {
        switch self {
        case .morning:
            Image(systemName: emptyStateIcon)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .afternoon:
            Image(systemName: emptyStateIcon)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .pink],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        case .evening:
            Image(systemName: emptyStateIcon)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - PeezyDarkBackground

/// Animated dark gradient background matching the main PeezyStackView
struct PeezyDarkBackground: View {
    @State private var start = UnitPoint(x: 0, y: -2)
    @State private var end = UnitPoint(x: 4, y: 0)

    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [Color.black, Color(red: 0.1, green: 0.1, blue: 0.2)]),
            startPoint: start,
            endPoint: end
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                start = UnitPoint(x: 4, y: 0)
                end = UnitPoint(x: 0, y: 2)
            }
        }
    }
}

// MARK: - PeezyTheme

enum PeezyTheme {

    // MARK: - Colors

    enum Colors {
        // Brand
        /// Primary brand accent (#FFE36B)
        static let brandYellow = Color(red: 1.0, green: 0.89, blue: 0.42)
        /// Lighter brand accent to pair with primary
        static let brandYellowLight = Color(red: 1.0, green: 0.94, blue: 0.63)

        // Semantic
        static let emotionalRed = Color(red: 0.95, green: 0.45, blue: 0.45)
        /// Secondary accent (#6BFFE3)
        static let infoBlue = Color(red: 0.42, green: 1.0, blue: 0.89)
        static let supportPurple = Color(red: 0.55, green: 0.45, blue: 0.95)
        static let successGreen = Color(red: 0.34, green: 0.78, blue: 0.47)
        static let warningOrange = Color(red: 0.95, green: 0.65, blue: 0.25)

        // Dark Theme - Charcoal Glass (matches CardView in PeezyStackView)
        /// Deep space base color for backgrounds
        static let deepSpaceBase = Color(red: 0.02, green: 0.02, blue: 0.06)
        /// Charcoal color for glass tint overlays
        static let charcoalGlass = Color(red: 0.15, green: 0.15, blue: 0.17)
        /// Accent blue for buttons and highlights
        static let accentBlue = Color(red: 0.2, green: 0.5, blue: 1.0)

        // Confidence indicators
        static let confidenceVerified = Color(red: 0.2, green: 0.6, blue: 0.3)
        static let confidenceGeneral = Color(red: 0.98, green: 0.85, blue: 0.29)
        static let confidenceEscalate = Color(red: 0.8, green: 0.3, blue: 0.3)

        // Backgrounds
        static let backgroundPrimary = Color(uiColor: .systemGroupedBackground)
        static let backgroundSecondary = Color(uiColor: .systemGray6)
        static let backgroundTertiary = Color(uiColor: .systemGray5)
        static let backgroundChat = Color(red: 0.95, green: 0.95, blue: 0.97)

        // Text
        static let textPrimary = Color(uiColor: .label)
        static let textSecondary = Color(uiColor: .secondaryLabel)
        static let textTertiary = Color(uiColor: .tertiaryLabel)
    }

    // MARK: - Typography

    enum Typography {
        static let largeTitle = Font.system(size: 28, weight: .bold)
        static let title = Font.system(size: 22, weight: .bold)
        static let title2 = Font.system(size: 20, weight: .bold)
        static let headline = Font.system(size: 17, weight: .semibold)
        static let body = Font.system(size: 17, weight: .regular)
        static let bodyMedium = Font.system(size: 17, weight: .medium)
        static let callout = Font.system(size: 15, weight: .regular)
        static let calloutMedium = Font.system(size: 15, weight: .medium)
        static let calloutSemibold = Font.system(size: 15, weight: .semibold)
        static let footnote = Font.system(size: 13, weight: .regular)
        static let footnoteMedium = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 11, weight: .regular)
        static let captionMedium = Font.system(size: 11, weight: .medium)
    }

    // MARK: - Layout

    enum Layout {
        // Corner radii
        static let cornerRadiusLarge: CGFloat = 20
        static let cornerRadius: CGFloat = 16
        static let cornerRadiusMedium: CGFloat = 14
        static let cornerRadiusSmall: CGFloat = 12
        static let cornerRadiusPill: CGFloat = 25
        /// Fixed shape radius for uniform controls/tiles
        static let cornerRadiusFixed: CGFloat = 41

        // Padding
        static let cardPadding: CGFloat = 16
        static let cardPaddingSmall: CGFloat = 12
        static let horizontalPadding: CGFloat = 20
        static let horizontalPaddingSmall: CGFloat = 16

        // Spacing
        static let verticalSpacing: CGFloat = 12
        static let verticalSpacingSmall: CGFloat = 8
        static let sectionSpacing: CGFloat = 32
        static let itemSpacing: CGFloat = 16

        // Specific dimensions
        static let tabBarHeight: CGFloat = 70
        static let buttonHeight: CGFloat = 56
        static let buttonHeightSmall: CGFloat = 44
        static let iconSizeLarge: CGFloat = 80
        static let iconSizeMedium: CGFloat = 36
        static let iconSizeSmall: CGFloat = 24
    }

    // MARK: - Animation

    enum Animation {
        static let springResponse: Double = 0.3
        static let springDamping: Double = 0.7
        static let springResponseSlow: Double = 0.6
        static let springDampingSlow: Double = 0.8

        static let pressScale: CGFloat = 0.98
        static let tabPressScale: CGFloat = 0.95
        static let pillPressScale: CGFloat = 0.95

        static let quickDuration: Double = 0.1
        static let standardDuration: Double = 0.2
        static let slowDuration: Double = 0.3

        static var spring: SwiftUI.Animation {
            .spring(response: springResponse, dampingFraction: springDamping)
        }

        static var springSlow: SwiftUI.Animation {
            .spring(response: springResponseSlow, dampingFraction: springDampingSlow)
        }

        static var easeOut: SwiftUI.Animation {
            .easeOut(duration: standardDuration)
        }

        static var easeInOut: SwiftUI.Animation {
            .easeInOut(duration: standardDuration)
        }
    }

    // MARK: - Shadows

    enum Shadows {
        // Card shadows
        static let cardShadowColor = Color.black.opacity(0.15)
        static let cardShadowRadius: CGFloat = 20
        static let cardShadowY: CGFloat = 10

        // Subtle shadows
        static let subtleShadowColor = Color.black.opacity(0.05)
        static let subtleShadowRadius: CGFloat = 4
        static let subtleShadowY: CGFloat = 2

        // Button shadows
        static let buttonShadowColor = Color.black.opacity(0.1)
        static let buttonShadowRadius: CGFloat = 8
        static let buttonShadowY: CGFloat = 4

        // Glow effects
        static func brandGlow(opacity: Double = 0.4) -> Color {
            Colors.brandYellow.opacity(opacity)
        }

        static func infoGlow(opacity: Double = 0.4) -> Color {
            Colors.infoBlue.opacity(opacity)
        }
    }

    // MARK: - Gradients

    enum Gradients {
        static let brandYellow = LinearGradient(
            colors: [Colors.brandYellow, Colors.brandYellowLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let infoBlue = LinearGradient(
            colors: [
                Colors.infoBlue,
                Color(red: 0.66, green: 1.0, blue: 0.93)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        static let brandYellowBackground = LinearGradient(
            colors: [
                Colors.brandYellow.opacity(0.2),
                Colors.brandYellowLight.opacity(0.32)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
