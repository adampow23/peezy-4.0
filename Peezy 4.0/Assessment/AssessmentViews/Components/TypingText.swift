//
//  TypingText.swift
//  Peezy
//
//  One-shot typewriter text component.
//  Uses AttributedString to reveal characters by changing foreground color
//  from .clear to visible. The full text layout is computed once and never
//  changes — eliminating all layout shift, jitter, and alignment issues.
//

import SwiftUI

struct TypingText: View {
    let fullText: String
    let speed: Double
    var onComplete: (() -> Void)? = nil

    @State private var displayedCount: Int = 0
    @State private var timer: Timer?

    private var attributedText: AttributedString {
        var result = AttributedString(fullText)
        // Revealed characters: use the inherited foreground color from parent
        // (don't set anything — let the parent .foregroundColor() apply)

        // Unrevealed characters: transparent
        if displayedCount < fullText.count {
            let startIndex = result.index(result.startIndex, offsetByCharacters: displayedCount)
            result[startIndex..<result.endIndex].foregroundColor = .clear
        }
        return result
    }

    var body: some View {
        Text(attributedText)
            .accessibilityLabel(fullText)
            .onAppear {
                startTyping()
            }
            .onChange(of: fullText) { _, _ in
                displayedCount = 0
                timer?.invalidate()
                startTyping()
            }
            .onDisappear {
                timer?.invalidate()
            }
    }

    private func startTyping() {
        guard displayedCount < fullText.count else {
            onComplete?()
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: speed, repeats: true) { t in
            if displayedCount < fullText.count {
                displayedCount += 1
            }
            if displayedCount >= fullText.count {
                t.invalidate()
                onComplete?()
            }
        }
    }
}
