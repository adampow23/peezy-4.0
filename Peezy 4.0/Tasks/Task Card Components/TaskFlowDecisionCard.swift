//
//  TaskFlowDecisionCard.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/12/26.
//

import SwiftUI

// MARK: - Task Flow Decision Card (Typographic Polish)
// Asks user if they want Peezy to handle the task or do it themselves.
// UX Pivot: Concatenated Text views allow the "Time Saved" subtext to be
// smaller, italicized, and slightly muted while remaining on a single line.

struct TaskFlowDecisionCard: View {
    let taskTitle: String
    var question: String = "Would you like us to take care of this for you?"
    var yesLabel: String = "Yes"
    var noLabel: String = "No, I got it"
    
    // UX Pivot: The Time Delta (Loss Aversion)
    var timeSaved: String = "~1 hr"
    
    var showBack: Bool = false
    let onPeezy: () -> Void
    let onSelf: () -> Void
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: taskTitle, showBack: showBack, onBack: onBack)

            Spacer()

            // Question text
            VStack(alignment: .leading, spacing: 15) {
                Text(question)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            // UX Ergonomic Fix: Pushes buttons into the Thumb Zone
            Spacer()

            // Button stack
            VStack(spacing: 12) {

                // MARK: - Primary: Styled Subtext
                // We use a native button to bypass the String limitation of PeezyAssessmentButton,
                // while perfectly mimicking its physical UI shell.
                Button(action: {
                    PeezyHaptics.light()
                    onPeezy()
                }) {
                    // UX Typography Fix: Concatenating Text views keeps them on the exact same baseline
                    (Text("\(yesLabel) · ")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    + Text("Saves \(timeSaved)")
                        .font(.system(size: 14, weight: .medium).italic()) // Slightly smaller and italicized
                        .foregroundStyle(.white.opacity(0.75))) // Subtext styling
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(PeezyTheme.Colors.deepInk)
                )

                // MARK: - Secondary: Muted, clear, with proper haptics/hitbox
                Button(action: {
                    PeezyHaptics.light()
                    onSelf()
                }) {
                    Text(noLabel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Decision — Parking") {
    TaskFlowDecisionCard(
        taskTitle: "Reserve unloading parking",
        timeSaved: "~45 mins",
        showBack: true,
        onPeezy: { print("Peezy") },
        onSelf: { print("Self") },
        onBack: { print("Back") }
    )
    .peezyCardChrome()
}

#Preview("Decision — Insurance") {
    TaskFlowDecisionCard(
        taskTitle: "Update your auto insurance",
        timeSaved: "~1.5 hrs",
        onPeezy: { print("Peezy") },
        onSelf: { print("Self") }
    )
    .peezyCardChrome()
}

#Preview("Decision — Elevator") {
    TaskFlowDecisionCard(
        taskTitle: "Reserve loading elevator",
        timeSaved: "~30 mins",
        showBack: true,
        onPeezy: { print("Peezy") },
        onSelf: { print("Self") },
        onBack: { print("Back") }
    )
    .peezyCardChrome()
}
#endif
