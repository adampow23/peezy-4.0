//
//  ReadyView.swift
//  Peezy
//

import SwiftUI

struct ReadyView: View {

    let onContinue: () -> Void

    // MARK: - Animation State

    @State private var checkmarkTrim: CGFloat = 0
    @State private var checkmarkCircleTrim: CGFloat = 0
    @State private var checkmarkScale: CGFloat = 0.4
    @State private var readyTextOpacity: Double = 0
    @State private var buttonOpacity: Double = 0

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 36) {
                
                // Animated checkmark matched to the 160x160 size of the progress wheel
                ZStack {
                    Circle()
                        .trim(from: 0, to: checkmarkCircleTrim)
                        .stroke(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 160, height: 160)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: .green.opacity(0.3), radius: 12, x: 0, y: 6)

                    CheckmarkShape()
                        .trim(from: 0, to: checkmarkTrim)
                        .stroke(
                            Color.green,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 60, height: 60)
                        .offset(x: 4, y: 4) // Optically center the checkmark
                }
                .scaleEffect(checkmarkScale)

                VStack(spacing: 12) {
                    Text("Your task list is ready")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(PeezyTheme.Colors.deepInk)
                    
                    Text("We've organized everything you need for a smooth move.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .opacity(readyTextOpacity)

                PeezyAssessmentButton("See Your Custom Plan") {
                    onContinue()
                }
                .padding(.top, 8)
                .opacity(buttonOpacity)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 48)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.2))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 40)

            Spacer()
        }
        .onAppear {
            animateCheckmark()
        }
    }

    // MARK: - Checkmark Animation

    private func animateCheckmark() {
        // Pop the container scale
        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
            checkmarkScale = 1.0
        }
        // Draw the outer ring quickly
        withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
            checkmarkCircleTrim = 1.0
        }
        // Snap the checkmark lines
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.35)) {
            checkmarkTrim = 1.0
        }
        // Fade in the text contextually
        withAnimation(.easeIn(duration: 0.4).delay(0.5)) {
            readyTextOpacity = 1.0
        }
        // Fade in the CTA last so the user digests the success first
        withAnimation(.easeIn(duration: 0.4).delay(0.7)) {
            buttonOpacity = 1.0
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
