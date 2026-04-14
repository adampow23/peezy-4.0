//
//  TaskFlowStack.swift
//  Peezy 4.0
//
//  Renders the current card with depth cards behind it.
//  Handles slide-out transition when currentIndex changes.
//
//  TAP FIX (Apr 2026): Animation shortened from spring(0.4, 0.85) to
//  easeOut(0.2). The spring took ~700ms to settle, during which SwiftUI
//  withheld tap events from the transitioning card. The new easeOut settles
//  in 200ms, reducing the non-interactive window to near-zero.
//  Depth cards now have .allowsHitTesting(false) to prevent ambiguous taps.
//

import SwiftUI

struct TaskFlowStack<Content: View>: View {
    let cardsRemaining: Int
    let currentIndex: Int
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Depth cards behind (decorative only — no hit testing)
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
                    .allowsHitTesting(false)
            }

            // Current card — interactive
            content()
                .peezyCardChrome()
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(currentIndex)
                .zIndex(1)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2),
            value: currentIndex
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.keyboard)
    }
}
