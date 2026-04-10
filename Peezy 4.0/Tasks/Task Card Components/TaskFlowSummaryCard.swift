//
//  TaskFlowSummaryCard.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/10/26.
//

import SwiftUI

// MARK: - Task Flow Summary Card
// Final card in a task flow. Shows completion state and submit button.
// Used for: recap screens, submission confirmations.

struct TaskFlowSummaryCard: View {
    let taskTitle: String
    let title: String
    let bodyText: String
    var primaryLabel: String = "Submit Request"
    var subtext: String? = nil
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

            VStack(alignment: .leading, spacing: 15) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(PeezyTheme.Colors.successGreen)

                Text(title)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                accentDivider

                Text(bodyText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                if let subtext {
                    Text(subtext)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.35))
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            PeezyAssessmentButton(primaryLabel) {
                onPrimary()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
