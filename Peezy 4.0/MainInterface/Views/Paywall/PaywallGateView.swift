//
//  PaywallGateView.swift
//  Peezy 4.0
//
//  Single-screen paywall for the six-month, non-renewing Peezy Move Pass.
//  The StoreKit product provides the localized price shown to the user.
//

import SwiftUI
import StoreKit
import FirebaseFunctions

struct PaywallGateView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    let onDismiss: () -> Void

    @State private var isShowingGiftCodeRedeem = false

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
                            Text("PEEZY MOVE PASS")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .tracking(1.5)
                                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))

                            Text("One price.\nYour whole move.")
                                .font(.system(size: 34, weight: .heavy))
                                .foregroundStyle(PeezyTheme.Colors.deepInk)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Six months of Peezy doing the work.\nNo subscription. Nothing to cancel.\nIt just ends when your move does.")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.7))
                                .lineSpacing(4)
                                .padding(.top, 4)
                        }

                        // MARK: - Feature checklist
                        VStack(alignment: .leading, spacing: 16) {
                            featureRow("Personalized moving plan built from your assessment")
                            featureRow("AI inventory scanner for every room")
                            featureRow("Daily task stream so nothing slips through the cracks")
                            featureRow("Plan updates as your move evolves")
                        }
                        .padding(.vertical, 8)

                        // MARK: - Price
                        movePassPriceCard
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 32)

                    // MARK: - CTA and footer
                    VStack(spacing: 16) {
                        PeezyAssessmentButton(ctaLabel) {
                            purchaseMovePass()
                        }
                        .disabled(isPurchaseDisabled)
                        .opacity(isPurchaseDisabled ? 0.5 : 1.0)
                        .accessibilityIdentifier("paywall_purchase_button")

                        // Tertiary actions
                        HStack(spacing: 12) {
                            Button {
                                isShowingGiftCodeRedeem = true
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

                        // Move Pass terms
                        Text("One-time payment charged to your Apple ID at confirmation of purchase. Includes 6 months of Peezy Move Pass access. This is not an auto-renewing subscription — access ends automatically and nothing renews.")
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
        .sheet(isPresented: $isShowingGiftCodeRedeem) {
            GiftCodeRedeemSheet {
                isShowingGiftCodeRedeem = false
                onDismiss()
            }
            .environmentObject(subscriptionManager)
        }
    }

    // MARK: - Computed UI State

    private var isPurchaseDisabled: Bool {
        subscriptionManager.isPurchasing || subscriptionManager.product(for: .move) == nil
    }

    private var ctaLabel: String {
        subscriptionManager.isPurchasing ? "Processing..." : "Get the Move Pass"
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

    // MARK: - Price Card

    private var movePassPriceCard: some View {
        VStack(spacing: 8) {
            Text(subscriptionManager.product(for: .move)?.displayPrice ?? "—")
                .font(.system(size: 40, weight: .heavy))
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .minimumScaleFactor(0.7)

            Text("Founding price — locked for early users")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.75))
                .multilineTextAlignment(.center)

            Text("One-time payment · 6 months of access")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PeezyTheme.Colors.deepInk.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: PeezyTheme.Colors.deepInk.opacity(0.12), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("paywall_move_pass_price")
    }

    // MARK: - Purchase

    private func purchaseMovePass() {
        guard let product = subscriptionManager.product(for: .move) else { return }
        Task {
            let result = await subscriptionManager.purchase(product)
            if case .success = result {
                onDismiss()
            }
        }
    }
}

private struct GiftCodeRedeemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    let onRedeemed: () -> Void

    @State private var code = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                InteractiveBackground()
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Redeem a gift code")
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)

                        Text("Enter your code to add Move Pass access to this account.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.65))
                    }

                    TextField("Gift code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(PeezyTheme.Colors.deepInk.opacity(0.12), lineWidth: 1)
                        )
                        .disabled(isSubmitting)
                        .accessibilityIdentifier("gift_code_text_field")

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("gift_code_error")
                    }

                    PeezyAssessmentButton(isSubmitting ? "Redeeming..." : "Redeem code") {
                        redeemCode()
                    }
                    .disabled(isSubmitDisabled)
                    .opacity(isSubmitDisabled ? 0.5 : 1.0)
                    .accessibilityIdentifier("gift_code_submit_button")

                    Spacer()
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isSubmitting)
    }

    private var trimmedCode: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSubmitDisabled: Bool {
        isSubmitting || trimmedCode.isEmpty
    }

    private func redeemCode() {
        guard !trimmedCode.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let result = try await Functions.functions()
                    .httpsCallable("redeemGiftCode")
                    .call(["code": trimmedCode])

                if let response = result.data as? [String: Any],
                   response["success"] as? Bool == false {
                    errorMessage = response["message"] as? String
                        ?? response["error"] as? String
                        ?? "That code could not be redeemed."
                    isSubmitting = false
                    return
                }

                await subscriptionManager.updateSubscriptionStatus()
                isSubmitting = false
                dismiss()
                onRedeemed()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

#Preview("Move Pass") {
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
