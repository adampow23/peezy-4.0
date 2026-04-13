//
//  TaskFlowTitleCard.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/12/26.
//

import SwiftUI

// MARK: - Task Flow Title Card (Premium Token v2.1)
// Center-aligned, tactile cover page.
// Typography has been balanced to harmonize with the delicate token layout.

struct TaskFlowTitleCard: View {
    let taskTitle: String
    let icon: String
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            
            Spacer()

            // MARK: - The Premium Token Cluster
            VStack(spacing: 36) { // Nudged spacing slightly tighter to connect the token and text
                
                // The Larger Physical Token
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.05))
                    
                    Image(systemName: icon)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                }
                .frame(width: 150, height: 150)
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)

                // The Hero Title
                Text(taskTitle)
                    // UX Typography Fix: .bold instead of .heavy, scaled to 32pt
                    .font(.system(size: 32, weight: .bold))
                    // UX Polish: Negative tracking makes the font look custom and expensive
                    .tracking(-0.5)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4) // Adds breathing room if text wraps to two lines
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            PeezyHaptics.light()
            onContinue()
        }
        .accessibilityLabel(taskTitle)
        .accessibilityHint("Tap anywhere to continue")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Title — Book Movers") {
    TaskFlowTitleCard(
        taskTitle: "Book your movers",
        icon: "truck.box.fill",
        onContinue: { print("Continue") }
    )
    .peezyCardChrome()
}

#Preview("Title — Forward Mail") {
    TaskFlowTitleCard(
        taskTitle: "Forward your mail",
        icon: "envelope.fill",
        onContinue: { print("Continue") }
    )
    .peezyCardChrome()
}

#Preview("Title — Handle Dentist") {
    TaskFlowTitleCard(
        taskTitle: "Handle your dentist",
        icon: "mouth.fill",
        onContinue: { print("Continue") }
    )
    .peezyCardChrome()
}
#endif
