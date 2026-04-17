//
//  PaywallGateView.swift
//  Peezy 4.0
//
//  Redesigned for Apple Guideline 3.1.2(c) compliance and max conversion.
//

import SwiftUI
import StoreKit
import UIKit

struct PaywallGateView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    let onDismiss: () -> Void

    @State private var selectedPlan: SubscriptionManager.ProductID = .annual

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // MARK: - Dismiss button
                    HStack {
                        Spacer()
                        Button(action: {
                            PeezyHaptics.light()
                            onDismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.15))
                                .padding()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("paywall_dismiss_button")
                    }

                    VStack(alignment: .leading, spacing: 24) {
                        // MARK: - Hero section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ASSESSMENT COMPLETE")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .tracking(1.5)
                                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))

                            Text("Let us handle the\nheavy lifting.")
                                .font(.system(size: 34, weight: .heavy))
                                .foregroundStyle(PeezyTheme.Colors.deepInk)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Moving costs the average person 25+ hours of stress. Upgrade to Peezy+ and get:")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.7))
                                .lineSpacing(4)
                                .padding(.top, 4)
                        }

                        // MARK: - Feature checklist (Apple 3.1.2(c) compliance)
                        VStack(alignment: .leading, spacing: 16) {
                            featureRow("Personalized moving plan built from your assessment")
                            featureRow("Most tasks, done for you. The rest, walked through step-by-step")
                            featureRow("AI inventory scanner for every room")
                            featureRow("Daily task stream so nothing slips through the cracks")
                            featureRow("Priority support via in-app chat")
                            featureRow("Plan updates as your move evolves")
                        }
                        .padding(.vertical, 8)

                        // MARK: - Pricing cards
                        HStack(spacing: 12) {
                            pricingCard(plan: .annual)
                            pricingCard(plan: .weekly)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 32)

                    // MARK: - CTA and footer
                    VStack(spacing: 16) {
                        PeezyAssessmentButton(ctaLabel) {
                            purchaseSelected()
                        }
                        .animation(.none, value: selectedPlan)
                        .accessibilityIdentifier("paywall_purchase_button")

                        // Tertiary actions
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
                            .accessibilityIdentifier("paywall_redeem_code")

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
                            .accessibilityIdentifier("paywall_restore_purchases")
                        }
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))

                        // Subscription terms
                        Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Manage subscriptions in Settings > Apple ID > Subscriptions.")
                            .font(.system(size: 11))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .accessibilityIdentifier("paywall_subscription_terms")

                        HStack(spacing: 4) {
                            Link("Privacy Policy", destination: URL(string: "https://peezy-1ecrdl.web.app/privacy.html")!)
                                .accessibilityIdentifier("paywall_privacy_link")
                            Text("·")
                            Link("Terms of Service", destination: URL(string: "https://peezy-1ecrdl.web.app/terms.html")!)
                                .accessibilityIdentifier("paywall_terms_link")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    // MARK: - CTA Label (dynamic based on plan and purchase state)

    private var ctaLabel: String {
        if subscriptionManager.isPurchasing {
            return "Processing..."
        }
        if selectedPlan == .annual {
            // Check if annual plan has a free trial
            if let product = subscriptionManager.product(for: .annual),
               let intro = product.subscription?.introductoryOffer,
               intro.paymentMode == .freeTrial {
                let days = intro.period.value
                return "Start \(days)-Day Free Trial"
            }
            return "Subscribe Yearly"
        } else {
            let price = subscriptionManager.product(for: .weekly)?.displayPrice ?? ""
            return price.isEmpty ? "Subscribe Weekly" : "Subscribe for \(price)/wk"
        }
    }

    // MARK: - Feature Row

    private func featureRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .padding(.top, 2)

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.85))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Pricing Card

    private func pricingCard(plan: SubscriptionManager.ProductID) -> some View {
        let isSelected = selectedPlan == plan
        let product = subscriptionManager.product(for: plan)
        let price = product?.displayPrice ?? "—"

        let title: String = plan == .annual ? "Yearly" : "Weekly"
        let duration: String = plan == .annual ? "/ yr" : "/ wk"
        let subtext: String = {
            if plan == .annual {
                if let intro = product?.subscription?.introductoryOffer,
                   intro.paymentMode == .freeTrial {
                    let days = intro.period.value
                    return "\(days)-day free trial"
                }
                return "Billed yearly"
            } else {
                return "Billed weekly"
            }
        }()
        let badge: String? = plan == .annual ? "BEST VALUE" : nil

        let identifier = plan == .annual ? "paywall_plan_annual" : "paywall_plan_weekly"

        return Button(action: {
            PeezyHaptics.light()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedPlan = plan
            }
        }) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isSelected ? PeezyTheme.Colors.deepInk : PeezyTheme.Colors.deepInk.opacity(0.5))

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(price)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(isSelected ? PeezyTheme.Colors.deepInk : PeezyTheme.Colors.deepInk.opacity(0.5))
                        .minimumScaleFactor(0.7)
                    Text(duration)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isSelected ? PeezyTheme.Colors.deepInk.opacity(0.6) : PeezyTheme.Colors.deepInk.opacity(0.3))
                }

                Text(subtext)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? PeezyTheme.Colors.deepInk.opacity(0.6) : PeezyTheme.Colors.deepInk.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.white : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? PeezyTheme.Colors.deepInk : PeezyTheme.Colors.deepInk.opacity(0.1),
                            lineWidth: isSelected ? 2 : 1)
            )
            .overlay(
                Group {
                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(PeezyTheme.Colors.deepInk)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .offset(y: -12)
                    }
                },
                alignment: .top
            )
            .shadow(color: isSelected ? PeezyTheme.Colors.deepInk.opacity(0.15) : Color.clear, radius: 10, x: 0, y: 4)
            .scaleEffect(isSelected ? 1.0 : 0.98)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
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

#Preview("Live (annual selected)") {
    PaywallGateView(onDismiss: {})
        .environmentObject(SubscriptionManager.shared)
}

#Preview("Dark Mode") {
    PaywallGateView(onDismiss: {})
        .environmentObject(SubscriptionManager.shared)
        .preferredColorScheme(.dark)
}

#Preview("iPad", traits: .fixedLayout(width: 834, height: 1194)) {
    PaywallGateView(onDismiss: {})
        .environmentObject(SubscriptionManager.shared)
}

#Preview("iPhone SE (small screen)", traits: .fixedLayout(width: 375, height: 667)) {
    PaywallGateView(onDismiss: {})
        .environmentObject(SubscriptionManager.shared)
}
