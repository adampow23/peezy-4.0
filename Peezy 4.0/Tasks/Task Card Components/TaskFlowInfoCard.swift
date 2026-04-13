//
//  TaskFlowInfoCard.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/10/26.
//

import SwiftUI

// MARK: - Task Flow Info Card
// Informational card with title, body text, optional caution icon, optional bold prefix.
// Used for: insurance warnings, educational content, instructions.

struct TaskFlowInfoCard: View {
    let taskTitle: String
    let title: String
    let bodyText: String
    var primaryLabel: String = "Continue"
    var cautionIcon: String? = nil
    var boldPrefix: String? = nil
    var showBack: Bool = false
    let onPrimary: () -> Void
    var onBack: (() -> Void)? = nil

    // Shared divider
    private var accentDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.15))
            .frame(width: 50, height: 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: taskTitle, showBack: showBack, onBack: onBack)

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                
                // UX Gestalt Fix: Tightly group the warning icon with the title it belongs to
                VStack(alignment: .leading, spacing: 8) {
                    if let cautionIcon {
                        Image(systemName: cautionIcon)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.orange) // Accessibility Fix: Contrast ratio
                    }

                    Text(title)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }

                accentDivider

                // UX Typography Fix: Consolidate modifiers and apply line spacing for readability
                Group {
                    if let boldPrefix {
                        (Text(boldPrefix).fontWeight(.bold) + Text(" ") + Text(bodyText))
                    } else {
                        Text(bodyText)
                    }
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                .lineSpacing(4) // Gives dense warning text necessary breathing room
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            PeezyAssessmentButton(primaryLabel) {
                onPrimary()
            }
            .accessibilityIdentifier("taskflow_info_primary")
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
