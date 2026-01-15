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
    var typingSpeed: TimeInterval = 0.05
    var deleteSpeed: TimeInterval = 0.03
    var pauseDuration: TimeInterval = 1.5
    var font: Font = .body
    var foregroundColor: Color = .primary
    
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
        Text(displayedText + (cursorVisible ? "|" : " "))
            .font(font)
            .foregroundColor(foregroundColor)
            .multilineTextAlignment(.center)
            .accessibilityLabel(phrases[currentPhraseIndex])
            .onAppear {
                startAnimation()
            }
            .onDisappear {
                cleanup()
            }
    }
    
    // MARK: - Animation Logic
    
    private func startAnimation() {
        timer?.invalidate()
        cursorVisible = true
        
        timer = Timer.scheduledTimer(withTimeInterval: typingSpeed, repeats: true) { _ in
            DispatchQueue.main.async {
                handleTick()
            }
        }
    }
    
    private func handleTick() {
        let currentPhrase = phrases[currentPhraseIndex]
        
        switch phase {
        case .typing:
            if displayedText.count < currentPhrase.count {
                let index = currentPhrase.index(currentPhrase.startIndex, offsetBy: displayedText.count)
                displayedText.append(currentPhrase[index])
            } else {
                phase = .pausing
                schedulePause()
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
}

// MARK: - Preview

#Preview {
    TypewriterText(
        phrases: ["Let's get moving.", "Moving made Peezy.", "Your move, simplified."],
        font: .system(size: 32, weight: .semibold),
        foregroundColor: .black
    )
}
