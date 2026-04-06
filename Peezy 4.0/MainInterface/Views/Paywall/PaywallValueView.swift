import SwiftUI

// MARK: - PaywallValueView
//
// Pure value builder — no purchase logic. Single CTA advances to PaywallGateView.

struct PaywallValueView: View {

    let onContinue: () -> Void

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // MARK: - Header & Copy
                VStack(spacing: 12) {
                    Text("PEEZY+")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .multilineTextAlignment(.center)

                    Text("Can you really put\na price on peace\nof mind?")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 32)

                // MARK: - Value Props
                VStack(spacing: 20) {
                    Text("We did. And then we made it free\nfor 3 days so you don't have to\ntake our word for it.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    Text("25+ hours saved. Zero stress.\nAnd less than a dollar a week.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .padding(.horizontal, 32)

                Spacer()

                // MARK: - Single CTA
                VStack(spacing: 12) {
                    PeezyAssessmentButton("Try it free", action: onContinue)

                    Text("3-day free trial · Then $49.99/year")
                        .font(.system(size: 13))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }
}

#Preview {
    PaywallValueView(onContinue: {})
}
