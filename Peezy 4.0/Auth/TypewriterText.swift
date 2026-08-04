//
//  TypewriterText.swift
//  PeezyV1.0
//
//  Created by user285836 on 12/12/25.
//

import SwiftUI

struct TypewriterText: View {
    // MARK: - Configuration
    
    let phrases: [String]
    var typingSpeed: TimeInterval = 0.10
    var deleteSpeed: TimeInterval = 0.06
    var pauseDuration: TimeInterval = 1.5
    var font: Font = .body
    var foregroundColor: Color = .primary
    var repeatsPhrases: Bool = true
    var textAlignment: TextAlignment = .center
    var showsCursor: Bool = true
    
    // MARK: - State
    
    @State private var displayedText: String = ""
    @State private var currentPhraseIndex: Int = 0
    @State private var phase: AnimationPhase = .typing
    @State private var timer: Timer?
    @State private var cursorVisible: Bool = true
    @State private var cursorTimer: Timer?
    
    private enum AnimationPhase {
        case typing
        case pausing
        case deleting
    }
    
    // MARK: - Body
    
    var body: some View {
        Text(displayedText + cursor)
            .font(font)
            .foregroundColor(foregroundColor)
            .multilineTextAlignment(textAlignment)
            .accessibilityLabel(currentPhrase)
            .onAppear {
                startAnimation()
            }
            .onDisappear {
                cleanup()
            }
    }
    
    // MARK: - Animation Logic
    
    private func startAnimation() {
        guard !phrases.isEmpty else { return }
        timer?.invalidate()
        cursorVisible = true
        
        timer = Timer.scheduledTimer(withTimeInterval: typingSpeed, repeats: true) { _ in
            DispatchQueue.main.async {
                handleTick()
            }
        }
    }
    
    private func handleTick() {
        guard !phrases.isEmpty else { return }
        let phrase = phrases[currentPhraseIndex]
        
        switch phase {
        case .typing:
            if displayedText.count < phrase.count {
                let index = phrase.index(phrase.startIndex, offsetBy: displayedText.count)
                displayedText.append(phrase[index])
            } else {
                if repeatsPhrases {
                    phase = .pausing
                    schedulePause()
                } else {
                    timer?.invalidate()
                    timer = nil
                    cursorVisible = false
                }
            }
            
        case .pausing:
            // Handled by schedulePause()
            break
            
        case .deleting:
            if !displayedText.isEmpty {
                displayedText.removeLast()
            } else {
                phase = .pausing
                scheduleNextPhrase()
            }
        }
    }
    
    private func schedulePause() {
        timer?.invalidate()
        startCursorBlink()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + pauseDuration) {
            stopCursorBlink()
            phase = .deleting
            restartTimer(with: deleteSpeed)
        }
    }
    
    private func scheduleNextPhrase() {
        timer?.invalidate()
        startCursorBlink()
        
        // Brief pause before starting next phrase
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            stopCursorBlink()
            currentPhraseIndex = (currentPhraseIndex + 1) % phrases.count
            phase = .typing
            restartTimer(with: typingSpeed)
        }
    }
    
    private func restartTimer(with interval: TimeInterval) {
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            DispatchQueue.main.async {
                handleTick()
            }
        }
    }
    
    // MARK: - Cursor Blink
    
    private func startCursorBlink() {
        cursorVisible = true
        cursorTimer?.invalidate()
        
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async {
                cursorVisible.toggle()
            }
        }
    }
    
    private func stopCursorBlink() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        cursorVisible = true
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        timer?.invalidate()
        timer = nil
        cursorTimer?.invalidate()
        cursorTimer = nil
    }

    private var currentPhrase: String {
        guard phrases.indices.contains(currentPhraseIndex) else { return "" }
        return phrases[currentPhraseIndex]
    }

    private var cursor: String {
        guard showsCursor else { return "" }
        return cursorVisible ? "|" : " "
    }
}

// MARK: - Preview

#Preview {
    TypewriterText(
        phrases: ["Let's get moving.", "Moving made Peezy.", "Your move, simplified."],
        font: .system(size: 32, weight: .semibold),
        foregroundColor: .black
    )
}
