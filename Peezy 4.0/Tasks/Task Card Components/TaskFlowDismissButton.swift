//
//  TaskFlowDismissButton.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/12/26.
//

import SwiftUI

// MARK: - Task Flow Dismiss Button
// Glass circle with house icon. Lives at the flow level, not on individual cards.
// Always visible in the top-left corner above the card stack.
// Tap → exits the entire flow back to home.
//
// Styling matches PeezyTimelineView's home button exactly.
//
// Usage in every flow's body:
//
//   var body: some View {
//       ZStack(alignment: .topLeading) {
//           InteractiveBackground()
//               .ignoresSafeArea()
//
//           TaskFlowStack(cardsRemaining: ..., currentIndex: ...) {
//               cardContent
//           }
//
//           TaskFlowDismissButton(onDismiss: onDismiss)
//       }
//   }

struct TaskFlowDismissButton: View {
    let onDismiss: () -> Void

    var body: some View {
        Button(action: {
            PeezyHaptics.light()
            onDismiss()
        }) {
            Image(systemName: "house.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                .frame(width: 36, height: 36)
                .background(.regularMaterial.opacity(0.8))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        // UX Hitbox Fix: 44pt invisible touch target around 36pt visual
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .padding(.leading, 20)
        .padding(.top, 12)
        .accessibilityLabel("Go home")
        .accessibilityIdentifier("taskflow_dismiss_button")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Dismiss Button") {
    ZStack(alignment: .topLeading) {
        InteractiveBackground()
            .ignoresSafeArea()

        TaskFlowDismissButton(onDismiss: { print("Dismiss") })
    }
}
#endif
