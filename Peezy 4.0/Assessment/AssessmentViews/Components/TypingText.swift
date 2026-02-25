//
//  TypingText.swift
//  Peezy
//
//  Reusable one-shot typewriter text component.
//  Reveals text character-by-character at a configurable speed.
//  Reserves full text height via hidden backing Text to prevent layout jumps.
//

import SwiftUI

struct TypingText: View {
    let fullText: String
    let speed: Double // seconds per character batch
    var onComplete: (() -> Void)? = nil

    @State private var displayedCount: Int = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Hidden full text reserves layout space to prevent jumps
            Text(fullText)
                .hidden()
                .accessibilityHidden(true)

            // Visible typed text
            Text(String(fullText.prefix(displayedCount)))
        }
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
                // Batch 2 characters per tick to match existing typewriter feel
                displayedCount = min(displayedCount + 2, fullText.count)
            }
            if displayedCount >= fullText.count {
                t.invalidate()
                onComplete?()
            }
        }
    }
}
