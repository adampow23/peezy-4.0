//
//  AssessmentIntroView.swift
//  PeezyV1.0
//
//  Created by user285836 on 11/11/25.
//

import SwiftUI

struct AssessmentIntroView: View {
    @Binding var showAssessment: Bool

    // Sequential animation states
    @State private var showIcon = false
    @State private var startHeader = false
    @State private var startDescription = false
    @State private var showFooter = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon with scale-up entrance + sparkle effect
            Image(systemName: "wand.and.stars")
                .font(.system(size: 80))
                .foregroundColor(PeezyTheme.Colors.deepInk)
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating, value: showIcon)
                .padding(.bottom, 32)
                .scaleEffect(showIcon ? 1.0 : 0.3)
                .opacity(showIcon ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showIcon)

            // Header typewriters in after icon settles
            if startHeader {
                TypingText(
                    fullText: "Welcome to the easy part",
                    speed: 0.04,
                    onComplete: {
                        startDescription = true
                    }
                )
                .font(.system(size: 28, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundColor(PeezyTheme.Colors.deepInk)
                .padding(.horizontal, 40)
                .padding(.bottom, 16)
            } else {
                // Invisible placeholder to reserve layout space
                Text("Welcome to the easy part")
                    .font(.system(size: 28, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 16)
                    .hidden()
            }

            // Description typewriters in after header completes
            if startDescription {
                TypingText(
                    fullText: "You're in! Take a deep breath—we've got the heavy lifting from here. To build your perfect game plan, we just need to grab a few quick details about your move.",
                    speed: 0.02,
                    onComplete: {
                        withAnimation(.easeOut(duration: 0.4)) {
                            showFooter = true
                        }
                    }
                )
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                .padding(.horizontal, 40)
                .padding(.bottom, 8)
            } else {
                // Invisible placeholder to reserve layout space
                Text("You're in! Take a deep breath—we've got the heavy lifting from here. To build your perfect game plan, we just need to grab a few quick details about your move.")
                    .font(.system(size: 17))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
                    .hidden()
            }

            // Time estimate fades in after description completes
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 14))
                Text("Just a quick 90 second setup")
                    .font(.system(size: 15))
            }
            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
            .opacity(showFooter ? 1 : 0)

            Spacer()

            // Continue button appears after all text finishes
            PeezyAssessmentButton("Take the first step") {
                showAssessment = true
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showFooter ? 1 : 0)
            .offset(y: showFooter ? 0 : 20)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showFooter)
        }
        .background(InteractiveBackground())
        .onAppear {
            // Icon appears first
            withAnimation {
                showIcon = true
            }
            // Header typewriter starts after icon settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                startHeader = true
            }
        }
    }
}

#Preview {
    AssessmentIntroView(showAssessment: .constant(false))
}
