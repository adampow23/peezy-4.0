//
//  TaskFlowSummaryCard.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/10/26.
//

import SwiftUI

// MARK: - Task Flow Summary Card
// Final card in a task flow. Shows completion state with branded sign-off.
// Title is always "Eezy Peezy!" — universal brand moment across every flow.
// Submission happens on the previous card. This is pure closure.

struct TaskFlowSummaryCard: View {
    let taskTitle: String
    let bodyText: String
    var primaryLabel: String = "Done"
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

            VStack(alignment: .leading, spacing: 16) {

                // UX Gestalt Fix: Tightly group the Hero Icon with the Victory Title
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(PeezyTheme.Colors.successGreen)

                    Text("Eezy Peezy!")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                accentDivider

                // UX Typography Fix: Group reading text and apply line spacing
                VStack(alignment: .leading, spacing: 8) {
                    Text(bodyText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtext {
                        Text(subtext)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
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

// MARK: - Previews

#if DEBUG
#Preview("Summary — Movers") {
    TaskFlowSummaryCard(
        taskTitle: "Book your movers",
        bodyText: "We'll reach out as soon as we have quotes.",
        onPrimary: { print("Complete") }
    )
    .peezyCardChrome()
}

#Preview("Summary — Self-Service") {
    TaskFlowSummaryCard(
        taskTitle: "Return all access devices",
        bodyText: "We'll check in on this closer to your move date.",
        onPrimary: { print("Complete") }
    )
    .peezyCardChrome()
}

#Preview("Summary — Insurance") {
    TaskFlowSummaryCard(
        taskTitle: "Update your auto insurance",
        bodyText: "We'll reach out and get this updated for you.",
        onPrimary: { print("Complete") }
    )
    .peezyCardChrome()
}
#endif
