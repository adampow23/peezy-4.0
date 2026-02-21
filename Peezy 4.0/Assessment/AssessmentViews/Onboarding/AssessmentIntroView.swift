//
//  AssessmentIntroView.swift
//  PeezyV1.0
//
//  Created by user285836 on 11/11/25.
//

import SwiftUI

struct AssessmentIntroView: View {
    @Binding var showAssessment: Bool

    // Animation states
    @State private var showContent = false
    @State private var iconScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon with breathing animation and entrance
            Image(systemName: "wand.and.stars")
                .font(.system(size: 80))
                .foregroundColor(.white)
                .padding(.bottom, 32)
                .scaleEffect(showContent ? iconScale : 0.5)
                .opacity(showContent ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.2), value: showContent)
                .onAppear {
                    // Continuous breathing animation
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        iconScale = 1.05
                    }
                }

            // Header with entrance animation
            Text("Welcome to the easy part")
                .font(.system(size: 28, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .padding(.horizontal, 40)
                .padding(.bottom, 16)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
                .animation(.easeOut(duration: 0.6).delay(0.4), value: showContent)

            // Description with entrance animation
            Text("You're in! Take a deep breath—we've got the heavy lifting from here. To build your perfect game plan, we just need to grab a few quick details about your move.")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 40)
                .padding(.bottom, 8)
                .opacity(showContent ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.6), value: showContent)

            // Time estimate with entrance animation
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 14))
                Text("Just a quick 90 second setup")
                    .font(.system(size: 15))
            }
            .foregroundColor(.white.opacity(0.6))
            .opacity(showContent ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.7), value: showContent)

            Spacer()

            // Continue button
            PeezyAssessmentButton("Take the first step") {
                showAssessment = true
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.8), value: showContent)
        }
        .background(InteractiveBackground())
        .onAppear {
            // Trigger entrance animations
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    AssessmentIntroView(showAssessment: .constant(false))
}
