//
//  TaskFlowStack.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/10/26.
//

import SwiftUI

// MARK: - Task Flow Stack
// Renders the current card with depth cards behind it.
// Handles slide-out transition when currentIndex changes.
// Each per-task flow file uses this to wrap its current card.
// .ignoresSafeArea(.keyboard) locks the card frame in place —
// individual cards handle keyboard avoidance internally if needed.

struct TaskFlowStack<Content: View>: View {
    let cardsRemaining: Int
    let currentIndex: Int
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Depth cards behind (empty chrome shapes for peek effect)
            ForEach(1..<min(3, max(1, cardsRemaining)), id: \.self) { depth in
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .fill(Color.white.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )
                    .frame(width: 340)
                    .frame(maxHeight: 500)
                    .scaleEffect(1.0 - CGFloat(depth) * 0.05)
                    .offset(y: CGFloat(depth) * 25)
                    .zIndex(Double(-depth))
            }

            // Current card
            content()
                .peezyCardChrome()
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(currentIndex)
                .zIndex(1)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.85),
            value: currentIndex
        )
        .ignoresSafeArea(.keyboard)
    }
}
