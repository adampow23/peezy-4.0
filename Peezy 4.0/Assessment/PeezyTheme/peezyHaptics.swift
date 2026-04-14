//
//  PeezyHaptics.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 1/12/26.
//


//
//  PeezyHaptics.swift
//  PeezyV1.0
//
//  Centralized haptic feedback utilities.
//  Use these instead of creating UIImpactFeedbackGenerator instances inline.
//

import UIKit
import CoreHaptics

// MARK: - PeezyHaptics

enum PeezyHaptics {

    // MARK: - Impact Feedback

    /// Light impact - for subtle interactions like selections
    static func light() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Medium impact - for standard button presses
    static func medium() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    /// Heavy impact - for significant actions
    static func heavy() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    /// Soft impact - for gentle feedback
    static func soft() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
    }

    /// Rigid impact - for firm feedback
    static func rigid() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
    }

    // MARK: - Notification Feedback

    /// Success notification - for completed actions
    static func success() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Warning notification - for alerts that need attention
    static func warning() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    /// Error notification - for failed actions
    static func error() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    // MARK: - Selection Feedback

    /// Selection changed - for picker/selection changes
    static func selection() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    // MARK: - Contextual Haptics

    /// Haptic for sending a message
    static func sendMessage() {
        light()
    }

    /// Haptic for task completion
    static func taskComplete() {
        success()
    }

    /// Haptic for escalation/help request
    static func escalate() {
        medium()
    }

    /// Haptic for navigation
    static func navigate() {
        light()
    }

    /// Haptic for toggle changes
    static func toggle() {
        light()
    }

    /// Haptic for pull-to-refresh
    static func refresh() {
        soft()
    }
}