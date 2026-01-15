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
            Image(systemName: "list.clipboard.fill")
                .font(.system(size: 80))
                .foregroundColor(Color(red: 0.98, green: 0.85, blue: 0.29))
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
            Text("Let's build your moving plan")
                .font(.system(size: 28, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .padding(.horizontal, 40)
                .padding(.bottom, 16)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
                .animation(.easeOut(duration: 0.6).delay(0.4), value: showContent)

            // Description with entrance animation
            Text("Answer 15 quick questions and we'll generate a personalized task list to guide you through every step of your move.")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
                .padding(.bottom, 8)
                .opacity(showContent ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.6), value: showContent)

            // Time estimate with entrance animation
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 14))
                Text("Takes about 2 minutes")
                    .font(.system(size: 15))
            }
            .foregroundColor(.secondary)
            .opacity(showContent ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.7), value: showContent)

            Spacer()

            // Continue button
            PeezyAssessmentButton("Start Assessment") {
                showAssessment = true
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.8), value: showContent)
        }
        .background(
            // Subtle gradient background
            LinearGradient(
                colors: [
                    Color.white,
                    Color(red: 0.98, green: 0.85, blue: 0.29).opacity(0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
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
