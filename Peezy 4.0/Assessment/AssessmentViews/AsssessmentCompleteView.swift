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
    @State private var showBackground = false
    @State private var starScale: CGFloat = 1.0

    // Haptic feedback
    private let successHaptic = UINotificationFeedbackGenerator()

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    PeezyTheme.Colors.brandYellow.opacity(0.15),
                    Color(UIColor.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .opacity(showBackground ? 1 : 0)
            .animation(.easeIn(duration: 0.5), value: showBackground)

            VStack(spacing: 32) {
                Spacer()

                // Celebration icon
                ZStack {
                    Circle()
                        .fill(PeezyTheme.Colors.brandYellow.opacity(0.2))
                        .frame(width: 120, height: 120)

                    Image(systemName: "star.fill")
                        .font(.system(size: 50))
                        .foregroundColor(PeezyTheme.Colors.brandYellow)
                        .scaleEffect(starScale)
                }
                .opacity(showContent ? 1 : 0)
                .scaleEffect(showContent ? 1.0 : 0.5)
                .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.2), value: showContent)

                // Title and subtitle
                VStack(spacing: 12) {
                    Text("Assessment Complete!")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.primary)
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 20)
                        .animation(.easeOut(duration: 0.6).delay(0.4), value: showContent)

                    Text("Your personalized moving plan is ready")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.5).delay(0.5), value: showContent)
                }

                Spacer()

                // Continue button
                Button {
                    PeezyHaptics.medium()
                    dismiss()
                } label: {
                    Text("Let's Go!")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(PeezyTheme.Colors.brandYellow)

                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.clear)
                                    .peezyLiquidGlass(
                                        cornerRadius: 16,
                                        intensity: 0.55,
                                        speed: 0.22,
                                        tintOpacity: 0.05,
                                        highlightOpacity: 0.12
                                    )
                            }
                        )
                }
                .buttonStyle(.peezyPress)
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
                showBackground = true
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

