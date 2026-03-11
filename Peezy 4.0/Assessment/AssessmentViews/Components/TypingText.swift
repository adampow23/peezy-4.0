//
//  TypingText.swift
//  Peezy
//
//  Typewriter text reveal using AttributedString.
//
//  HOW IT WORKS:
//  The full text is ALWAYS rendered. Unrevealed characters have .clear foreground color.
//  On each timer tick, one more character becomes visible. Because the string content
//  never changes, SwiftUI computes the layout exactly once. No shake, no jitter,
//  no alignment shift — structurally impossible.
//

import SwiftUI

struct TypingText: View {

    // ═══════════════════════════════════════════
    //  PUBLIC API — same as before, drop-in replacement
    // ═══════════════════════════════════════════
    let fullText: String
    let speed: Double                        // seconds per character
    var visibleColor: Color = Color(red: 0.05, green: 0.1, blue: 0.2)
    var onComplete: (() -> Void)? = nil

    // ═══════════════════════════════════════════
    //  INTERNAL STATE
    // ═══════════════════════════════════════════
    @State private var revealedCount: Int = 0
    @State private var timer: Timer?

    // ═══════════════════════════════════════════
    //  ATTRIBUTED STRING — the magic
    // ═══════════════════════════════════════════
    private var styledText: AttributedString {
        var result = AttributedString(fullText)

        // Everything starts with the visible color
        result.foregroundColor = visibleColor

        // Hide unrevealed characters
        if revealedCount < fullText.count {
            let hideStart = result.index(result.startIndex, offsetByCharacters: revealedCount)
            result[hideStart..<result.endIndex].foregroundColor = .clear
        }

        return result
    }

    // ═══════════════════════════════════════════
    //  BODY
    // ═══════════════════════════════════════════
    var body: some View {
        Text(styledText)
            .accessibilityLabel(fullText)
            .onAppear { startTyping() }
            .onChange(of: fullText) { _, _ in
                revealedCount = 0
                timer?.invalidate()
                startTyping()
            }
            .onDisappear {
                timer?.invalidate()
            }
    }

    // ═══════════════════════════════════════════
    //  TIMER
    // ═══════════════════════════════════════════
    private func startTyping() {
        guard revealedCount < fullText.count else {
            onComplete?()
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: speed, repeats: true) { t in
            if revealedCount < fullText.count {
                revealedCount += 1
            }
            if revealedCount >= fullText.count {
                t.invalidate()
                onComplete?()
            }
        }
    }

    /// Instantly reveal all text (for skip-on-tap)
    func revealAll() {
        timer?.invalidate()
        revealedCount = fullText.count
        onComplete?()
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
