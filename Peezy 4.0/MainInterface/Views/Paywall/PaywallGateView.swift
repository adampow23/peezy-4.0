import SwiftUI
import StoreKit

// MARK: - PaywallGateView
//
// Shown when trial expires or a non-subscriber taps a gated task type.
// Presents annual vs. weekly plan selection and triggers StoreKit purchase.
// onDismiss: called after successful purchase OR when user taps "Not now"

struct PaywallGateView: View {

    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    let onDismiss: () -> Void

    @State private var selectedPlan: SubscriptionManager.ProductID = .annual

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            glassCard {
                VStack(spacing: 0) {
                    // Header label
                    Text("PEEZY+")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .tracking(1.5)
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 30)
                        .padding(.top, 30)

                    Spacer()

                    // Value copy
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your easiest move ever. Or your money back.")
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("We handle the vendors. We handle the calls. We handle the stuff you keep putting off.")
                            .font(.system(size: 16))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)

                        Text("The average move costs people 25+ hours of admin headaches. Peezy costs less than one hour of therapy.")
                            .font(.system(size: 15))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 30)

                    Spacer()

                    // Plan selector
                    HStack(spacing: 12) {
                        planCard(for: .annual)
                        planCard(for: .weekly)
                    }
                    .padding(.horizontal, 30)

                    Spacer()

                    // CTA
                    VStack(spacing: 12) {
                        PeezyAssessmentButton(
                            subscriptionManager.isPurchasing ? "Processing..." : "Let's do this",
                            disabled: subscriptionManager.isPurchasing,
                            action: purchaseSelected
                        )
                        .padding(.horizontal, 30)

                        Button(action: onDismiss) {
                            Text("Not now")
                                .font(.subheadline)
                                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 30)
                }
            }
        }
    }

    // MARK: - Plan Card

    @ViewBuilder
    private func planCard(for plan: SubscriptionManager.ProductID) -> some View {
        let isSelected = selectedPlan == plan

        Button(action: { selectedPlan = plan }) {
            VStack(spacing: 6) {
                if plan == .annual {
                    Text("BEST VALUE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(PeezyTheme.Colors.deepInk)
                        )
                } else {
                    // Spacer to keep card heights equal
                    Color.clear.frame(height: 20)
                }

                Text(plan == .annual ? "YEARLY" : "WEEKLY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))

                Text(plan == .annual ? "$49.99" : "$6.99")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)

                Text(plan == .annual ? "3-day free trial" : "per week")
                    .font(.system(size: 11))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .foregroundStyle(.regularMaterial)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        isSelected
                            ? PeezyTheme.Colors.deepInk
                            : PeezyTheme.Colors.deepInk.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
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
            // Cancelled/failed: stay on screen (silent)
        }
    }

    // MARK: - Glass Card

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .foregroundStyle(.regularMaterial)
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.white.opacity(0.15))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    .padding(1)
            }
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 15)

            content()
        }
        .frame(width: 340, height: 500)
    }
}

// MARK: - Preview

#Preview("Annual selected") {
    PaywallGateView(onDismiss: { print("Dismissed") })
        .environmentObject(SubscriptionManager.shared)
}

#Preview("Weekly selected") {
    PaywallGateView(onDismiss: { print("Dismissed") })
        .environmentObject(SubscriptionManager.shared)
}
