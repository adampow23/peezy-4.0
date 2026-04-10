//
//  AssessmentIntroView.swift
//  Peezy 4.0
//

import SwiftUI

struct AssessmentIntroView: View {
    @Binding var showAssessment: Bool

    @State private var showIcon = false
    @State private var showHeader = false
    @State private var showDescription = false
    @State private var showFooter = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let headerText = "Welcome to the easy part"
    private let descriptionText = "You're in! Take a deep breath—we've got the heavy lifting from here. To build your perfect game plan, we just need to grab a few quick details about your move."

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "wand.and.stars")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                    .padding(.bottom, 24)
                    .scaleEffect(showIcon ? 1.0 : 0.3)
                    .opacity(showIcon ? 1 : 0)

                Text(headerText)
                    .font(.system(size: 34, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .opacity(showHeader ? 1 : 0)

                Text(descriptionText)
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .opacity(showDescription ? 1 : 0)

                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 14))
                    Text("Just a quick 90 second setup")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                .opacity(showFooter ? 1 : 0)

                Spacer()

                PeezyAssessmentButton("Take the first step") {
                    showAssessment = true
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .opacity(showFooter ? 1 : 0)
                .offset(y: showFooter ? 0 : 20)
            }
            .onAppear {
                let anim: Animation? = reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7)

                withAnimation(anim) { showIcon = true }

                Task {
                    try? await Task.sleep(for: .seconds(0.4))
                    withAnimation(anim) { showHeader = true }

                    try? await Task.sleep(for: .seconds(0.3))
                    withAnimation(anim) { showDescription = true }

                    try? await Task.sleep(for: .seconds(0.3))
                    withAnimation(anim) { showFooter = true }
                }
            }
        }
    }
}

#Preview {
    AssessmentIntroView(showAssessment: .constant(false))
}
