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
                    Text("PEEZY MOVE PASS")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .multilineTextAlignment(.center)

                    Text("What's six months of\nsomeone in your corner\nworth?")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 32)

                // MARK: - Value Props
                VStack(spacing: 20) {
                    Text("The research done for you. Your home\nscanned. The right truck the first time.\nA packing plan built around your date.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    Text("Renting one wrong-sized truck costs more\nthan all of it. Peezy works out to less\nthan the change in your cupholder.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .padding(.horizontal, 32)

                Spacer()

                // MARK: - Single CTA
                VStack(spacing: 12) {
                    PeezyAssessmentButton("See my price", action: onContinue)

                    Text("One-time payment · Nothing renews")
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
