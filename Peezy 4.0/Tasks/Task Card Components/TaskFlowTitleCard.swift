//
//  TaskFlowTitleCard.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/10/26.
//

import SwiftUI

// MARK: - Task Flow Title Card
// First card in a task flow. Shows task name, optional body text, and buttons.
// Usage: TaskFlowTitleCard(taskTitle: "Book your movers", title: "Book your movers", body: "We have a few questions...", onPrimary: { advance() }, onSecondary: { dismiss() })

struct TaskFlowTitleCard: View {
    let taskTitle: String
    let title: String
    var bodyText: String = ""
    var primaryLabel: String = "Continue"
    var secondaryLabel: String? = nil
    let onPrimary: () -> Void
    var onSecondary: (() -> Void)? = nil

    // Shared divider
    private var accentDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.15))
            .frame(width: 50, height: 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: taskTitle)

            Spacer()

            // UX Gestalt Fix: Standardized to 16pt spacing to match Info and Summary cards
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)

                if !bodyText.isEmpty {
                    accentDivider

                    Text(bodyText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .lineLimit(6)
                        // UX Typography Fix: Breathing room for introductory paragraphs
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            VStack(spacing: 12) {
                PeezyAssessmentButton(primaryLabel) {
                    onPrimary()
                }

                if let secondaryLabel, let onSecondary {
                    Button(action: {
                        PeezyHaptics.light() // UX Polish: Haptic feedback for secondary actions
                        onSecondary()
                    }) {
                        Text(secondaryLabel)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                            // UX Hitbox Fix: Expands the invisible tap target to the edges
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
