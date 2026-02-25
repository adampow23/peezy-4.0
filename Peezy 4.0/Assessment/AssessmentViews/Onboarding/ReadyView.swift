//
//  ReadyView.swift
//  Peezy
//
//  Stage 2 of the completion flow: Animated checkmark + "See Your Custom Plan" button.
//  Plays the checkmark draw animation on appear, then reveals the button.
//  Calls onContinue when the button is tapped.
//

import SwiftUI

struct ReadyView: View {

    let onContinue: () -> Void

    // MARK: - Animation State

    @State private var checkmarkTrim: CGFloat = 0
    @State private var checkmarkCircleTrim: CGFloat = 0
    @State private var checkmarkScale: CGFloat = 0.6
    @State private var readyTextOpacity: Double = 1
    @State private var buttonOpacity: Double = 1

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Animated checkmark
                ZStack {
                    Circle()
                        .trim(from: 0, to: checkmarkCircleTrim)
                        .stroke(
                            LinearGradient(
                                colors: [.green.opacity(0.8), .cyan.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))

                    CheckmarkShape()
                        .trim(from: 0, to: checkmarkTrim)
                        .stroke(
                            Color.green,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 28, height: 28)
                }
                .scaleEffect(checkmarkScale)

                Text("Your task list is ready")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PeezyTheme.Colors.deepInk)

                PeezyAssessmentButton("See Your Custom Plan") {
                    onContinue()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 40)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 48)

            Spacer()
        }
        .onAppear {
            animateCheckmark()
        }
    }

    // MARK: - Checkmark Animation (from original)

    private func animateCheckmark() {
        withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
            checkmarkCircleTrim = 1.0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.6)) {
            checkmarkTrim = 1.0
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.5)) {
            checkmarkScale = 1.0
        }
    }
}

// MARK: - Checkmark Shape

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.15, y: rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.width * 0.40, y: rect.height * 0.80))
        path.addLine(to: CGPoint(x: rect.width * 0.85, y: rect.height * 0.20))
        return path
    }
}
