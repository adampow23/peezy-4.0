import SwiftUI
import StoreKit

// MARK: - PaywallValueView
//
// Shown once after assessment completion, before entering the app.
// 3-tier CTA hierarchy: Primary (try free) → Secondary (skip) → Tertiary (redeem code)

struct PaywallValueView: View {

    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    let onStartTrial: () -> Void
    let onSkip: () -> Void

    private func startTrial() {
        guard let product = subscriptionManager.product(for: .annual) else {
            onStartTrial()
            return
        }
        Task {
            let result = await subscriptionManager.purchase(product)
            if case .success = result {
                onStartTrial()
            }
        }
    }

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // MARK: - Header & Copy
                VStack(spacing: 12) {
                    Text("YOUR PLAN IS READY")
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

                // MARK: - Primary Decision Zone
                VStack(spacing: 16) {
                    PeezyAssessmentButton(subscriptionManager.isPurchasing ? "Processing..." : "Try it free", action: startTrial)

                    Text("3-day free trial · Then $49.99/year")
                        .font(.system(size: 13))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))

                    // Binary alternative — tightly coupled to primary CTA
                    Button(action: onSkip) {
                        Text("Skip")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 32)

                // MARK: - Utility Footer
                Button {
                    Task {
                        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                        try? await AppStore.presentOfferCodeRedeemSheet(in: windowScene)
                    }
                } label: {
                    Text("Redeem a code")
                        .font(.system(size: 12, weight: .regular))
                        .underline()
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
        }
    }
}

#Preview {
    PaywallValueView(onStartTrial: {}, onSkip: {})
        .environmentObject(SubscriptionManager.shared)
}
