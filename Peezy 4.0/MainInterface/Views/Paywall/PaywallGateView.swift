import SwiftUI
import StoreKit

// MARK: - PaywallGateView
//
// Shown when trial expires or a non-subscriber taps a gated task type.
// 3-tier CTA hierarchy: Primary (subscribe) → Secondary (not now) → Tertiary (redeem code)

struct PaywallGateView: View {

    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    let onDismiss: () -> Void

    @State private var selectedPlan: SubscriptionManager.ProductID = .annual

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

                    Text("Your easiest move ever.\nOr your money back.")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 32)

                // MARK: - Value Props
                VStack(spacing: 20) {
                    Text("We handle the vendors. We handle the calls.\nWe handle the stuff you keep putting off.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    Text("The average move costs people 25+ hours of\nadmin headaches. Peezy costs less than\none hour of therapy.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .padding(.horizontal, 32)

                Spacer().frame(height: 40)

                // MARK: - Plan Selector
                HStack(spacing: 16) {
                    planCard(for: .annual)
                    planCard(for: .weekly)
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 48)

                // MARK: - Primary Decision Zone
                VStack(spacing: 16) {
                    PeezyAssessmentButton(
                        subscriptionManager.isPurchasing ? "Processing..." : "Let's do this",
                        action: purchaseSelected
                    )

                    // Binary alternative — tightly coupled to primary CTA
                    Button(action: onDismiss) {
                        Text("Not now")
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
                .padding(.bottom, 12)

                // MARK: - Subscription Terms (Apple 3.1.2)
                Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Manage subscriptions in Settings > Apple ID > Subscriptions.")
                    .font(.system(size: 10))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 8)

                HStack(spacing: 4) {
                    Link("Privacy Policy", destination: URL(string: "https://peezy-1ecrdl.web.app/privacy.html")!)
                    Text("·")
                    Link("Terms of Service", destination: URL(string: "https://peezy-1ecrdl.web.app/terms.html")!)
                }
                .font(.system(size: 10))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Plan Card

    @ViewBuilder
    private func planCard(for plan: SubscriptionManager.ProductID) -> some View {
        let isSelected = selectedPlan == plan

        Button(action: { selectedPlan = plan }) {
            ZStack(alignment: .top) {
                if plan == .annual {
                    Text("BEST VALUE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(PeezyTheme.Colors.deepInk))
                        .padding(.top, 12)
                }

                VStack(spacing: 6) {
                    Text(plan == .annual ? "YEARLY" : "WEEKLY")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))

                    Text(plan == .annual ? "$49.99" : "$6.99")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)

                    Text(plan == .annual ? "3-day free trial" : "per week")
                        .font(.system(size: 12))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                }
                .padding(.top, 44)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .foregroundStyle(.regularMaterial)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        isSelected
                            ? PeezyTheme.Colors.deepInk
                            : PeezyTheme.Colors.deepInk.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Purchase

    private func purchaseSelected() {
        guard let product = subscriptionManager.product(for: selectedPlan) else { return }
        Task {
            let result = await subscriptionManager.purchase(product)
            if case .success = result {
                onDismiss()
            }
        }
    }
}

#Preview {
    PaywallGateView(onDismiss: {})
        .environmentObject(SubscriptionManager.shared)
}
