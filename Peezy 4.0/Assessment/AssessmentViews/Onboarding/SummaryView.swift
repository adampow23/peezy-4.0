//
//  SummaryView.swift
//  Peezy
//
//  Stage 3 of the completion flow: Confetti + task count + "Let's Get Started".
//  Confetti goes BEHIND content in the ZStack with .allowsHitTesting(false).
//  Content is always visible — no opacity animations starting at 0.
//  Calls onGetStarted when the button is tapped.
//

import SwiftUI

struct SummaryView: View {

    let userName: String
    let taskCount: Int
    let onGetStarted: () -> Void

    // MARK: - Confetti State

    @State private var showConfetti: Bool = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Confetti BEHIND content — always in hierarchy to avoid layout changes
            ConfettiView(isActive: $showConfetti, intensity: .high)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .opacity(showConfetti ? 1 : 0)
                .animation(.easeOut(duration: 0.5), value: showConfetti)

            // Content ALWAYS on top, visible immediately
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 8) {
                        Text(displayName + " Personalized Moving Plan")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(PeezyTheme.Colors.deepInk)
                            .multilineTextAlignment(.center)

                        Text("Here's what we built for you")
                            .font(.system(size: 16))
                            .foregroundColor(Color.gray)
                    }

                    // Total count — hero number
                    VStack(spacing: 4) {
                        Text("\(taskCount)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        Text("personalized tasks")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(Color.gray)
                    }
                    .padding(.vertical, 8)
                }

                Spacer()

                // CTA
                PeezyAssessmentButton("Let's Get Started") {
                    onGetStarted()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showConfetti = true
            }
        }
    }

    // MARK: - Display Name

    /// Formats userName for display: "Adam's" or "Your" if empty.
    private var displayName: String {
        if userName.isEmpty {
            return "Your"
        }
        return userName + "'s"
    }
}
