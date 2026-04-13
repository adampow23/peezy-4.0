//
//  TaskFlowTitleCard.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/12/26.
//

import SwiftUI

// MARK: - Task Flow Title Card
// Cover page for every task flow. Clean, high-contrast token left-aligned.
// Uses a controlled typographic rag (forcing a newline before the 3rd word)
// to create a beautiful, balanced text block that fills the negative space.
//
// Character limit: taskTitle max 30 chars, first-person verb + subject.

struct TaskFlowTitleCard: View {
    let taskTitle: String
    let icon: String
    var primaryLabel: String = "Continue"
    let onContinue: () -> Void

    // MARK: - Controlled Rag Logic
    // Splits the string and injects a newline after the second word.
    // "Update your auto insurance" -> "Update your\nauto insurance"
    private var formattedTitle: String {
        let words = taskTitle.split(separator: " ")
        
        // If it's a super short title (2 words or less), leave it alone
        guard words.count >= 3 else { return taskTitle }
        
        let firstTwoWords = words.prefix(2).joined(separator: " ")
        let remainingWords = words.dropFirst(2).joined(separator: " ")
        
        return "\(firstTwoWords)\n\(remainingWords)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 24) {
                
                // Solid, high-contrast anchor token
                ZStack {
                    Circle()
                        .fill(PeezyTheme.Colors.deepInk)
                    
                    Image(systemName: icon)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 72, height: 72)

                // The formatted title
                Text(formattedTitle)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    // UX Polish: Slightly tightens line spacing for multi-line headers
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Continue button
            PeezyAssessmentButton(primaryLabel) {
                onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(taskTitle)
        .accessibilityHint("Tap continue to start")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Title — Book Movers") {
    // Becomes "Find my\nmovers"
    TaskFlowTitleCard(
        taskTitle: "Find my movers",
        icon: "truck.box.fill",
        onContinue: { print("Continue") }
    )
    .peezyCardChrome()
}

#Preview("Title — Forward Mail") {
    // Becomes "Forward your\nmail"
    TaskFlowTitleCard(
        taskTitle: "Forward your mail",
        icon: "envelope.fill",
        onContinue: { print("Continue") }
    )
    .peezyCardChrome()
}

#Preview("Title — Auto Insurance") {
    // Becomes "Update your\nauto insurance"
    TaskFlowTitleCard(
        taskTitle: "Update your auto insurance",
        icon: "car.fill",
        onContinue: { print("Continue") }
    )
    .peezyCardChrome()
}
#endif
