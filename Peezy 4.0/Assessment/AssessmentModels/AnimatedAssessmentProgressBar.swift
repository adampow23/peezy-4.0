//
//  AnimatedAssessmentProgressBar.swift
//  PeezyV1.0
//
//  Energetic progress bar that builds excitement as completion approaches
//

import SwiftUI

// MARK: - Animated Progress Bar

struct AnimatedAssessmentProgressBar: View {
    let progress: Double // 0.0 to 1.0
    let onCompletion: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var shimmerOffset: CGFloat = -200
    @State private var breathingScale: CGFloat = 0.95
    @State private var showExplosion = false
    @State private var explosionScale: CGFloat = 1.0
    @State private var explosionOpacity: Double = 1.0
    @State private var showConfetti = false

    var body: some View {
        ZStack {
            if showExplosion {
                // Confetti explosion
                ConfettiView(isActive: $showConfetti, intensity: .high)
                    .zIndex(10)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: barHeight / 2)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: barHeight)

                    // Filled portion
                    RoundedRectangle(cornerRadius: barHeight / 2)
                        .fill(barColor)
                        .frame(width: geometry.size.width * progress, height: barHeight)
                        .overlay(
                            // Shimmer effect (70%+)
                            shimmerOverlay(width: geometry.size.width * progress)
                        )
                        .shadow(color: glowColor, radius: glowRadius)
                        .scaleEffect(x: 1.0, y: animationScale, anchor: .leading)
                }
            }
            .frame(height: baseBarHeight)
            .opacity(explosionOpacity)
            .scaleEffect(explosionScale)
            .onAppear {
                startAnimations()
            }
            .onChange(of: progress) { _, newProgress in
                triggerProgressAnimation()

                // Check for completion
                if newProgress >= 1.0 {
                    triggerCompletionAnimation()
                }
            }
        }
    }

    // MARK: - Visual Properties

    private var baseBarHeight: CGFloat {
        // Maps to maximum bar height for layout
        return 20
    }

    private var barHeight: CGFloat {
        if progress < 0.4 { return 4 }
        else if progress < 0.7 { return 6 }
        else if progress < 0.9 { return 8 }
        else if progress < 0.95 { return 10 }
        else { return 12 }
    }

    private var barColor: Color {
        if progress < 0.4 {
            return Color.gray.opacity(0.3)
        } else if progress < 0.7 {
            return Color.yellow.opacity(0.6)
        } else if progress < 0.95 {
            return Color(red: 0.98, green: 0.85, blue: 0.29)
        } else {
            // Pure gold at 95%+
            return Color(red: 1.0, green: 0.84, blue: 0.0)
        }
    }

    private var glowColor: Color {
        if progress >= 0.95 {
            return Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.6)
        } else if progress >= 0.9 {
            return Color(red: 0.98, green: 0.85, blue: 0.29).opacity(0.4)
        } else {
            return Color.clear
        }
    }

    private var glowRadius: CGFloat {
        if progress >= 0.95 { return 8 }
        else if progress >= 0.9 { return 4 }
        else { return 0 }
    }

    private var animationScale: CGFloat {
        if progress >= 0.95 {
            return pulseScale // Rapid pulse
        } else if progress >= 0.9 {
            return breathingScale // Gentle breathing
        } else if progress >= 0.7 {
            return pulseScale // Pulse on update
        } else if progress >= 0.4 {
            return pulseScale // Gentle pulse
        } else {
            return 1.0 // No animation
        }
    }

    // MARK: - Shimmer Effect

    @ViewBuilder
    private func shimmerOverlay(width: CGFloat) -> some View {
        if progress >= 0.7 {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.3),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 60)
                .offset(x: shimmerOffset)
                .mask(
                    RoundedRectangle(cornerRadius: barHeight / 2)
                        .frame(width: width)
                )
        }
    }

    // MARK: - Animations

    private func startAnimations() {
        // Start shimmer animation if in range
        if progress >= 0.7 {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 400
            }
        }

        // Start breathing animation if in range
        if progress >= 0.9 && progress < 0.95 {
            startBreathingAnimation()
        }

        // Start rapid pulse if at 95%+
        if progress >= 0.95 {
            startRapidPulse()
        }
    }

    private func triggerProgressAnimation() {
        let haptic = UIImpactFeedbackGenerator(style: progress >= 0.9 ? .medium : .light)
        haptic.impactOccurred()

        if progress >= 0.4 && progress < 0.7 {
            // Gentle pulse (40-70%)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                pulseScale = 1.05
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    pulseScale = 1.0
                }
            }
        } else if progress >= 0.7 && progress < 0.9 {
            // Medium pulse with shimmer (70-90%)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                pulseScale = 1.1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    pulseScale = 1.0
                }
            }

            // Restart shimmer
            shimmerOffset = -200
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 400
            }
        } else if progress >= 0.9 && progress < 0.95 {
            // Start breathing if not already
            startBreathingAnimation()
        } else if progress >= 0.95 {
            // Start rapid pulse
            startRapidPulse()
        }
    }

    private func startBreathingAnimation() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            breathingScale = 1.0
        }
    }

    private func startRapidPulse() {
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }
    }

    private func triggerCompletionAnimation() {
        // Stop all animations
        withAnimation(.none) {
            pulseScale = 1.0
            breathingScale = 1.0
        }

        // Heavy haptic
        let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
        heavyHaptic.impactOccurred()

        // Step 1: Bar finale (grows and glows)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            explosionScale = 1.5
        }

        // Step 2: Explosion (0.3s later)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showExplosion = true
            showConfetti = true

            withAnimation(.easeOut(duration: 0.3)) {
                explosionOpacity = 0
            }

            // Another heavy haptic for explosion
            heavyHaptic.impactOccurred()
        }

        // Step 3: Transition to completion (1.5s later)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            onCompletion()
        }
    }
}

// MARK: - Assessment Progress Header Component

struct AssessmentProgressHeader: View {
    let currentStep: Int
    let totalSteps: Int
    let onBack: () -> Void
    let onCompletion: () -> Void

    private var progress: Double {
        Double(currentStep) / Double(totalSteps)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Back button and step indicator
            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .foregroundColor(.cyan)
                        .font(.system(size: 20))
                }
                Spacer()
                Text("Step \(currentStep) of \(totalSteps)")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)

            // Animated progress bar
            AnimatedAssessmentProgressBar(
                progress: progress,
                onCompletion: onCompletion
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        Text("Progress Evolution Demo")
            .font(.title)

        AssessmentProgressHeader(
            currentStep: 14,
            totalSteps: 15,
            onBack: {},
            onCompletion: {}
        )

        Spacer()
    }
    .padding()
}
