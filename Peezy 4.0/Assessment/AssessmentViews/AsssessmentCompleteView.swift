//
//  AssessmentCompleteView.swift
//  Peezy
//
//  Simple celebration screen after assessment completion.
//  Navigation is handled by AppRootView via .assessmentCompleted notification.
//

import SwiftUI

struct AssessmentCompleteView: View {
    @Environment(\.dismiss) var dismiss

    // Animation states
    @State private var showContent = false
    @State private var starScale: CGFloat = 1.0

    // Haptic feedback
    private let successHaptic = UINotificationFeedbackGenerator()

    var body: some View {
        ZStack {
            // Background
            InteractiveBackground()

            VStack(spacing: 32) {
                Spacer()

                // Celebration icon
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 120, height: 120)

                    Image(systemName: "star.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                        .scaleEffect(starScale)
                }
                .opacity(showContent ? 1 : 0)
                .scaleEffect(showContent ? 1.0 : 0.5)
                .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.2), value: showContent)

                // Title and subtitle
                VStack(spacing: 12) {
                    Text("Assessment Complete!")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 20)
                        .animation(.easeOut(duration: 0.6).delay(0.4), value: showContent)

                    Text("Your personalized moving plan is ready")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.5).delay(0.5), value: showContent)
                }

                Spacer()

                // Continue button
                PeezyAssessmentButton("Let's Go!") {
                    PeezyHaptics.medium()
                    dismiss()
                }
                .padding(.horizontal, 24)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 30)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.6), value: showContent)

                Spacer()
                    .frame(height: 40)
            }
            .padding(.vertical, 40)
        }
        .interactiveDismissDisabled()
        .onAppear {
            successHaptic.notificationOccurred(.success)

            withAnimation {
                showContent = true
            }

            // Gentle pulse animation on star
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                starScale = 1.05
            }
        }
    }
}

#Preview {
    AssessmentCompleteView()
}

