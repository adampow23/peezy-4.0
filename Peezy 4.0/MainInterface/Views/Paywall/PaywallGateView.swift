import SwiftUI
import StoreKit

// MARK: - PaywallGateView
//
// Shown when trial expires or a non-subscriber taps a gated task type.
// 3-tier CTA hierarchy: Primary (subscribe) → Secondary (not now) → Tertiary (utilities)

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

                // MARK: - Header & Value Prop
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
                        .minimumScaleFactor(0.8)

                    // UX Fix: Bumped size up to 17, weight to medium, and opacity to 0.7
                    // to give this statement the authority it deserves.
                    Text("The average move costs people 25+ hours of\nadmin headaches. Peezy costs less than\none hour of therapy.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .minimumScaleFactor(0.9)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 24)

                // MARK: - Plan Selector
                HStack(spacing: 16) {
                    planCard(for: .annual)
                    planCard(for: .weekly)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 32)

                // MARK: - Primary Action
                PeezyAssessmentButton(
                    subscriptionManager.isPurchasing ? "Processing..." : "Let's do this",
                    action: purchaseSelected
                )
                .padding(.horizontal, 24)

                Spacer(minLength: 20)

                // MARK: - Dismiss & Utilities (Grouped at the bottom)
                VStack(spacing: 16) {
                    
                    // Secondary Action
                    Button(action: onDismiss) {
                        Text("Not now")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())

                    // Tertiary Utilities (Side-by-Side)
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                                try? await AppStore.presentOfferCodeRedeemSheet(in: windowScene)
                            }
                        } label: {
                            Text("Redeem a code").underline()
                        }
                        .buttonStyle(.plain)

                        Text("·")

                        Button {
                            Task {
                                await subscriptionManager.restorePurchases()
                                if subscriptionManager.isSubscribed {
                                    onDismiss()
                                }
                            }
                        } label: {
                            Text("Restore Purchases").underline()
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                }

                Spacer(minLength: 16)

                // MARK: - Subscription Terms (Apple 3.1.2)
                VStack(spacing: 8) {
                    Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Manage subscriptions in Settings > Apple ID > Subscriptions.")
                        .font(.system(size: 11))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    HStack(spacing: 4) {
                        Link("Privacy Policy", destination: URL(string: "https://peezy-1ecrdl.web.app/privacy.html")!)
                        Text("·")
                        Link("Terms of Service", destination: URL(string: "https://peezy-1ecrdl.web.app/terms.html")!)
                    }
                    .font(.caption)
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                }
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
                        .padding(.top, 10)
                }

                VStack(spacing: 4) {
                    Text(plan == .annual ? "YEARLY" : "WEEKLY")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))

                    Text(priceText(for: plan))
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)

                    Text(subtitleText(for: plan))
                        .font(.system(size: 12))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                }
                .padding(.top, 36)
                .padding(.bottom, 20)
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

    // MARK: - Dynamic Price Helpers

    private func priceText(for plan: SubscriptionManager.ProductID) -> String {
        subscriptionManager.product(for: plan)?.displayPrice ?? "—"
    }

    private func subtitleText(for plan: SubscriptionManager.ProductID) -> String {
        guard let product = subscriptionManager.product(for: plan) else {
            return plan == .annual ? "per year" : "per week"
        }
        if plan == .annual,
           let intro = product.subscription?.introductoryOffer,
           intro.paymentMode == .freeTrial {
            let days = intro.period.value
            let unit = intro.period.unit == .day ? (days == 1 ? "day" : "days") : ""
            return "\(days)-\(unit) free trial"
        }
        return plan == .annual ? "per year" : "per week"
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
// MARK: - Preview

#Preview {
    PaywallGateView(onDismiss: {})
        .environmentObject(SubscriptionManager.shared)
}
