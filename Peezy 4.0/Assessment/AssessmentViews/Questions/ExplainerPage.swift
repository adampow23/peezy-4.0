//
//  ExplainerPage.swift
//  Peezy
//
//  Reusable explainer page for assessment section transitions.
//  Shows an icon and a Continue button. Header/subheader text is
//  handled by AssessmentInputWrapper via inputContext().
//

import SwiftUI

struct ExplainerPage: View {
    let icon: String
    let onContinue: () -> Void

    @State private var showButton = false

    var body: some View {
        VStack(spacing: 0) {
            // Icon displayed after morph reveals controls
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.6))
                .padding(.top, 16)
                .padding(.bottom, 32)

            Spacer()

            // Continue button fades in after a short delay
            PeezyAssessmentButton("Continue") {
                onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showButton ? 1 : 0)
            .animation(.easeOut(duration: 0.35).delay(0.3), value: showButton)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showButton = true
            }
        }
    }
}
