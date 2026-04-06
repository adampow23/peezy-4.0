//
//  TypingText.swift
//  Peezy
//
//  Animated text reveal — fade-in with subtle upward slide.
//  Replaces character-by-character typewriter with a faster, cleaner animation.
//  Keeps identical public interface for backward compatibility with all templates.
//

import SwiftUI

struct TypingText: View {
    let fullText: String
    let speed: Double  // Kept for API compatibility — not used
    let visibleColor: Color
    let onComplete: (() -> Void)?

    @State private var appeared = false
    @State private var completionFired = false

    init(
        fullText: String,
        speed: Double,
        visibleColor: Color = Color(red: 0.05, green: 0.10, blue: 0.20),
        onComplete: (() -> Void)? = nil
    ) {
        self.fullText = fullText
        self.speed = speed
        self.visibleColor = visibleColor
        self.onComplete = onComplete
    }

    var body: some View {
        Text(fullText)
            .foregroundStyle(visibleColor)
            .accessibilityLabel(fullText)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .animation(.easeOut(duration: 0.4), value: appeared)
            .onAppear {
                // Trigger the animation on next frame
                DispatchQueue.main.async {
                    appeared = true
                }
                // Fire onComplete after animation finishes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    guard !completionFired else { return }
                    completionFired = true
                    onComplete?()
                }
            }
    }

    // Legacy method — kept for API compatibility, no longer needed
    func revealAll() {
        // No-op: text is always fully visible
    }
}

// ═══════════════════════════════════════════
//  PREVIEW
// ═══════════════════════════════════════════
#Preview {
    VStack(spacing: 20) {
        TypingText(
            fullText: "Would you like quotes for professional movers?",
            speed: 0.04,
            visibleColor: Color(red: 0.05, green: 0.1, blue: 0.2)
        )
        .font(.system(size: 32, weight: .semibold))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(red: 0.96, green: 0.97, blue: 0.98))
}
