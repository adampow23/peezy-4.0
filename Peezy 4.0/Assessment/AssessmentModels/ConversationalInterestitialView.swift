//
//  ConversationalInterstitialView.swift
//  Peezy
//
//  Single-phase interstitial: shows Peezy's reaction to the previous answer.
//  One typewriter line, tap anywhere to advance.
//
//  Context (header + subheader) has moved to the input screens via AssessmentInputWrapper.
//  This view is now ONLY the post-comment reaction.
//

import SwiftUI

struct ConversationalInterstitialView: View {
    
    // MARK: - Configuration
    
    /// The comment text — Peezy's reaction to the user's previous answer.
    let commentText: String
    
    /// Called when user taps to advance past this interstitial.
    let onContinue: () -> Void
    
    // MARK: - State
    
    @State private var displayedText: String = ""
    @State private var isTypingComplete: Bool = false
    @State private var showTapHint: Bool = false
    
    // MARK: - Animation Config
    
    private let typewriterSpeed: TimeInterval = 0.03
    private let tapHintDelay: TimeInterval = 1.5
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Spacer()
                
                // Comment text — typewriter animation
                Text(displayedText)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 32)
                
                // Tap hint — subtle prompt after typing finishes
                if showTapHint {
                    Text("tap to continue")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.3))
                        .transition(.opacity)
                }
                
                Spacer()
            }
        }
        .contentShape(Rectangle()) // Make entire area tappable
        .onTapGesture {
            handleTap()
        }
        .onAppear {
            startTypewriter()
        }
    }
    
    // MARK: - Interaction
    
    private func handleTap() {
        if isTypingComplete {
            // Typing done — advance to next screen
            onContinue()
        } else {
            // Still typing — complete instantly
            displayedText = commentText
            isTypingComplete = true
            showTapHintAfterDelay()
        }
    }
    
    // MARK: - Typewriter
    
    private func startTypewriter() {
        let characters = Array(commentText)
        var index = 0
        
        func appendNext() {
            guard index < characters.count else {
                isTypingComplete = true
                showTapHintAfterDelay()
                return
            }
            
            let batchSize = 2
            let end = min(index + batchSize, characters.count)
            displayedText += String(characters[index..<end])
            index = end
            
            DispatchQueue.main.asyncAfter(deadline: .now() + typewriterSpeed) {
                appendNext()
            }
        }
        
        appendNext()
    }
    
    private func showTapHintAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + tapHintDelay) {
            withAnimation(.easeIn(duration: 0.5)) {
                showTapHint = true
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ConversationalInterstitialView(
        commentText: "Great to meet you, Adam. We're going to make this the smoothest move you've ever had."
    ) {
        print("Continue tapped")
    }
}
#endif
