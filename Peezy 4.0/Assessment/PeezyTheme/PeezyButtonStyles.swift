//
//  PeezyButtonStyles.swift
//  PeezyV1.0
//
//  Reusable button styles for consistent press animations throughout the app.
//

import SwiftUI

// MARK: - Press Scale Style

/// Generic press style with configurable scale
struct PeezyPressStyle: ButtonStyle {
    var scale: CGFloat = PeezyTheme.Animation.pressScale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.easeInOut(duration: PeezyTheme.Animation.quickDuration), value: configuration.isPressed)
    }
}

// MARK: - Primary Button Style

/// Style for primary action buttons (yellow brand color)
struct PeezyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? PeezyTheme.Animation.pressScale : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: PeezyTheme.Animation.quickDuration), value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style

/// Style for secondary action buttons
struct PeezySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? PeezyTheme.Animation.pressScale : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: PeezyTheme.Animation.quickDuration), value: configuration.isPressed)
    }
}

// MARK: - Tab Bar Button Style

/// Style for tab bar buttons
struct PeezyTabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? PeezyTheme.Animation.tabPressScale : 1.0)
            .animation(.easeInOut(duration: PeezyTheme.Animation.quickDuration), value: configuration.isPressed)
    }
}

// MARK: - Pill Button Style

/// Style for pill-shaped buttons (quick replies, suggestions)
struct PeezyPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? PeezyTheme.Animation.pillPressScale : 1.0)
            .animation(.easeInOut(duration: PeezyTheme.Animation.quickDuration), value: configuration.isPressed)
    }
}

// MARK: - Card Button Style

/// Style for card-style buttons
struct PeezyCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? PeezyTheme.Animation.pressScale : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeInOut(duration: PeezyTheme.Animation.quickDuration), value: configuration.isPressed)
    }
}

// MARK: - Scale Button Style (Legacy Compatibility)

/// Style with configurable scale and opacity - replaces local ScaleButtonStyle
struct ScaleButtonStyle: ButtonStyle {
    var scaleAmount: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleAmount : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: PeezyTheme.Animation.quickDuration), value: configuration.isPressed)
    }
}

// MARK: - Convenience Extensions

extension ButtonStyle where Self == PeezyPressStyle {
    /// Default press style
    static var peezyPress: PeezyPressStyle { PeezyPressStyle() }

    /// Press style with custom scale
    static func peezyPress(scale: CGFloat) -> PeezyPressStyle {
        PeezyPressStyle(scale: scale)
    }
}

extension ButtonStyle where Self == PeezyPrimaryButtonStyle {
    /// Primary button style (for main CTAs)
    static var peezyPrimary: PeezyPrimaryButtonStyle { PeezyPrimaryButtonStyle() }
}

extension ButtonStyle where Self == PeezySecondaryButtonStyle {
    /// Secondary button style
    static var peezySecondary: PeezySecondaryButtonStyle { PeezySecondaryButtonStyle() }
}

extension ButtonStyle where Self == PeezyTabButtonStyle {
    /// Tab bar button style
    static var peezyTab: PeezyTabButtonStyle { PeezyTabButtonStyle() }
}

extension ButtonStyle where Self == PeezyPillButtonStyle {
    /// Pill button style (for quick replies, suggestions)
    static var peezyPill: PeezyPillButtonStyle { PeezyPillButtonStyle() }
}

extension ButtonStyle where Self == PeezyCardButtonStyle {
    /// Card button style
    static var peezyCard: PeezyCardButtonStyle { PeezyCardButtonStyle() }
}
