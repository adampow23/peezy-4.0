//
//  AuthFormButton.swift
//  PeezyV1.0
//
//  Capsule-style submit button for auth forms (Log In, Sign Up).
//  Matches PeezyAssessmentButton: deepInk capsule, glow shadow, press gesture.
//

import SwiftUI

struct AuthFormButton: View {
    let title: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isPressed = false

    private let deepInk = PeezyTheme.Colors.deepInk

    private var effectiveDisabled: Bool { isDisabled || isLoading }

    var body: some View {
        Button(action: {
            guard !effectiveDisabled else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            ZStack {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(effectiveDisabled ? .white.opacity(0.5) : .white)
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Capsule(style: .continuous)
                    .fill(deepInk.opacity(effectiveDisabled ? 0.3 : 1.0))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(effectiveDisabled ? 0.0 : 0.25), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: effectiveDisabled ? .clear : deepInk.opacity(isPressed ? 0.2 : 0.4),
                radius: isPressed ? 8 : 16,
                x: 0,
                y: isPressed ? 4 : 8
            )
        }
        .disabled(effectiveDisabled)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .animation(.easeInOut(duration: 0.2), value: effectiveDisabled)
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !effectiveDisabled && !isPressed {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}
