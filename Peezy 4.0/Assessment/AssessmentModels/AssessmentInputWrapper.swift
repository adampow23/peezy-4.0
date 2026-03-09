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

    private let typewriterSpeed: TimeInterval = 0.06

    // MARK: - Reveal Sequence State

    @State private var headerComplete = false
    @State private var subtextComplete = false
    @State private var showControls = false
    @State private var isHero = true       // true = centered/large, false = top-left/small
    @State private var skipped = false     // true = user tapped to skip typewriter

    // MARK: - Helpers

    /// Post-typewriter processing delay. The user read along as text typed,
    /// so this is just a brief beat to let them finish the last few words.
    private func processingDelay(for lastText: String) -> Double {
        let wordCount = lastText.split(separator: " ").count
        let delay = 0.3 + (Double(wordCount) * 0.04)
        return min(max(delay, 0.3), 1.2)
    }

    // MARK: - Morph Helpers

    /// Triggers the hero-to-header morph after a brief reading pause, then reveals controls.
    private func triggerMorph(lastText: String) {
        let delay = processingDelay(for: lastText)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard isHero else { return } // Prevent double-fire if user skipped
            performMorph()
        }
    }

    /// Executes the morph animation and schedules control reveal.
    private func performMorph() {
        // Morph text from center to top-left
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            isHero = false
        }
        // Reveal controls slightly after morph begins so they rise into place together
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.35)) {
                showControls = true
            }
        }
    }

    /// Tap-to-skip: instantly completes all text and triggers the morph.
    private func skipToControls(context: InputContext) {
        guard isHero else { return } // Only active during hero state — won't eat button taps
        skipped = true
        headerComplete = true
        subtextComplete = true
        performMorph()
    }

    // MARK: - Body

    var body: some View {
        let context = coordinator.inputContext(for: step)

        ZStack {
            InteractiveBackground()

            VStack(spacing: 0) {
                // Top spacer — pushes text to vertical center when in hero state
                if isHero {
                    Spacer()
                }

                // MARK: - Text Area (morphs from center to top)
                VStack(spacing: 8) {
                    // Header
                    Group {
                        if skipped {
                            Text(context.header)
                        } else {
                            TypingText(fullText: context.header, speed: typewriterSpeed, onComplete: {
                                headerComplete = true
                                if context.subheader == nil {
                                    triggerMorph(lastText: context.header)
                                }
                            })
                        }
                    }
                    .font(.system(size: isHero ? 32 : 22, weight: .semibold))
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .lineSpacing(4)
                    .multilineTextAlignment(isHero ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: isHero ? .center : .leading)

                    // Subheader (types in after header, still in hero state)
                    if let subheader = context.subheader {
                        if headerComplete || skipped {
                            Group {
                                if skipped {
                                    Text(subheader)
                                } else {
                                    TypingText(fullText: subheader, speed: typewriterSpeed, onComplete: {
                                        subtextComplete = true
                                        triggerMorph(lastText: subheader)
                                    })
                                }
                            }
                            .font(.system(size: isHero ? 16 : 14))
                            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
                            .lineSpacing(3)
                            .multilineTextAlignment(isHero ? .center : .leading)
                            .frame(maxWidth: .infinity, alignment: isHero ? .center : .leading)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, isHero ? 0 : 24)
                .padding(.bottom, isHero ? 0 : 40)

                // Bottom spacer — keeps text vertically centered in hero state
                if isHero {
                    Spacer()
                }

                // MARK: - Controls (revealed after morph)
                if showControls {
                    content()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if !isHero {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.keyboard)   // Content views handle keyboard avoidance manually via KeyboardObserver
        .contentShape(Rectangle())
        .onTapGesture {
            skipToControls(context: context)
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
