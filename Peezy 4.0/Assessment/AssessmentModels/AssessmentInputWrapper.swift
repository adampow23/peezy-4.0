//
//  AssessmentInputWrapper.swift
//  Peezy
//
//  Wraps any assessment input view with context animation.
//  The context header typewriters in at the top, followed by subheader.
//  Input controls auto-reveal after typing completes + a short processing delay.
//
//  Usage: Used ONCE in AssessmentFlowView around the question view switch.
//  Individual question views are unchanged — they just render their controls.
//

import SwiftUI

struct AssessmentInputWrapper<Content: View>: View {

    // MARK: - Configuration

    let step: AssessmentInputStep
    @ObservedObject var coordinator: AssessmentCoordinator
    @ViewBuilder let content: () -> Content

    // MARK: - Animation Config

    private let typewriterSpeed: TimeInterval = 0.03

    // MARK: - Reveal Sequence State

    @State private var headerComplete = false
    @State private var subtextComplete = false
    @State private var showControls = false

    // MARK: - Helpers

    /// Post-typewriter processing delay. The user read along as text typed,
    /// so this is just a brief beat to let them finish the last few words.
    private func processingDelay(for lastText: String) -> Double {
        let wordCount = lastText.split(separator: " ").count
        let delay = 0.3 + (Double(wordCount) * 0.04)
        return min(max(delay, 0.3), 1.2)
    }

    // MARK: - Body

    var body: some View {
        let context = coordinator.inputContext(for: step)

        ZStack {
            InteractiveBackground()

            VStack(alignment: .leading, spacing: 0) {
                // Context area — header typewriters in, subtext types after
                VStack(alignment: .leading, spacing: 8) {
                    TypingText(fullText: context.header, speed: typewriterSpeed, onComplete: {
                        headerComplete = true
                        if context.subheader == nil {
                            let delay = processingDelay(for: context.header)
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                withAnimation(.easeOut(duration: 0.35)) {
                                    showControls = true
                                }
                            }
                        }
                    })
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .lineSpacing(4)

                    if let subheader = context.subheader {
                        if headerComplete {
                            TypingText(fullText: subheader, speed: typewriterSpeed, onComplete: {
                                subtextComplete = true
                                let delay = processingDelay(for: subheader)
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    withAnimation(.easeOut(duration: 0.35)) {
                                        showControls = true
                                    }
                                }
                            })
                            .font(.subheadline)
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                            .lineSpacing(3)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)

                // Input controls — auto-revealed after typing completes + processing delay
                if showControls {
                    content()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let dataManager = AssessmentDataManager()
    let coordinator = AssessmentCoordinator(dataManager: dataManager)

    AssessmentInputWrapper(step: .userName, coordinator: coordinator) {
        // Simulated question controls
        VStack(spacing: 16) {
            TextField("Your name", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 24)

            Button("Continue") {}
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                .padding(.horizontal, 24)
        }
    }
}
#endif
