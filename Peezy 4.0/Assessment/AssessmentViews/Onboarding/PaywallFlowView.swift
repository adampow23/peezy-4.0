//
//  PaywallFlowView.swift
//  Peezy
//
//  Three-page paywall sequence between assessment summary and main app:
//    Page 1 — "We want you to try Peezy for free" (value pitch)
//    Page 2 — "We'll send you a reminder" (reassurance)
//    Page 3 — Trial timeline + pricing + subscribe (paywall)
//
//  Presented from AssessmentCompleteView's "Let's Get Started" button.
//  Final action posts .assessmentCompleted to route to main app.
//
//  StoreKit 2 integration — subscribe button triggers a real purchase.
//

import SwiftUI
import StoreKit

// MARK: - Paywall Flow Container

struct PaywallFlowView: View {

    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var currentPage: Int = 0

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            switch currentPage {
            case 0:
                PaywallPage1(
                    onContinue: { withAnimation(.easeInOut(duration: 0.35)) { currentPage = 1 } },
                    onBypass: { bypassPaywall() }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            case 1:
                PaywallPage2(
                    onBack: { withAnimation(.easeInOut(duration: 0.35)) { currentPage = 0 } },
                    onContinue: { withAnimation(.easeInOut(duration: 0.35)) { currentPage = 2 } }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            case 2:
                PaywallPage3(
                    onBack: { withAnimation(.easeInOut(duration: 0.35)) { currentPage = 1 } },
                    onComplete: { finishPaywall() }
                )
                .environmentObject(subscriptionManager)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            default:
                EmptyView()
            }
        }
        .interactiveDismissDisabled()
    }

    private func finishPaywall() {
        NotificationCenter.default.post(name: .assessmentCompleted, object: nil)
    }

    // TODO: REMOVE BEFORE PRODUCTION
    private func bypassPaywall() {
        print("⚠️ DEV: Paywall bypassed via triple-tap")
        subscriptionManager.subscriptionStatus = .subscribed(
            productId: "dev.bypass",
            expirationDate: Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        )
        finishPaywall()
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - PAGE 1: Value Pitch
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct PaywallPage1: View {
    let onContinue: () -> Void
    // TODO: REMOVE BEFORE PRODUCTION
    var onBypass: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Main headline — centered
            // TODO: REMOVE BEFORE PRODUCTION — triple-tap bypasses paywall for dev testing
            VStack(spacing: 16) {
                Text("We want you to\ntry Peezy for free.")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .onTapGesture(count: 3) {
                        onBypass?()
                    }
            }

            Spacer()

            // Bottom section
            bottomSection(
                checkmarkText: "No Payment Due Now",
                buttonText: "Try for $0.00",
                priceText: "Just $29.99 per year ($2.49/mo)",
                action: onContinue
            )
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - PAGE 2: Reassurance
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct PaywallPage2: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Back button
            backButton(action: onBack)

            Spacer()

            // Content
            VStack(spacing: 24) {
                Text("We'll send you\na reminder before\nyour free trial ends")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                // Bell icon with notification badge
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white.opacity(0.15))

                    // Notification badge
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 28, height: 28)

                        Text("1")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: 8, y: -4)
                }
                .padding(.top, 8)

                // Reassurance copy
                Text("We genuinely want Peezy to provide value for your move. Try everything free — if it's not for you, cancel anytime before the trial ends and you won't be charged a thing.")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Bottom section
            bottomSection(
                checkmarkText: "No Payment Due Now",
                buttonText: "Continue for FREE",
                priceText: "Just $29.99 per year ($2.49/mo)",
                action: onContinue
            )
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - PAGE 3: Trial + Pricing
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct PaywallPage3: View {
    let onBack: () -> Void
    let onComplete: () -> Void

    @EnvironmentObject var subscriptionManager: SubscriptionManager

    @State private var selectedPlan: PlanOption = .yearly
    @State private var isTrialEligible: Bool = true
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    enum PlanOption {
        case monthly
        case yearly
    }

    var body: some View {
        VStack(spacing: 0) {
            // Back button
            backButton(action: onBack)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Headline
                    Text(isTrialEligible
                         ? "Start your 3-day\nFREE trial to continue."
                         : "Subscribe to\ncontinue.")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.top, 16)
                        .padding(.bottom, 32)

                    // Timeline (only show if trial eligible)
                    if isTrialEligible {
                        timelineSection
                            .padding(.horizontal, 32)
                            .padding(.bottom, 32)
                    }

                    // Plan selector
                    planSelector
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }

            // Bottom section
            VStack(spacing: 12) {
                // Checkmark (only if trial eligible)
                if isTrialEligible {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)

                        Text("No Payment Due Now")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.bottom, 4)
                }

                // CTA Button
                Button(action: {
                    Task { await handlePurchase() }
                }) {
                    if subscriptionManager.isPurchasing {
                        ProgressView()
                            .tint(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.7))
                            )
                    } else {
                        Text(isTrialEligible ? "Start My 3-Day Free Trial" : "Subscribe Now")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white)
                            )
                    }
                }
                .disabled(subscriptionManager.isPurchasing)
                .padding(.horizontal, 24)

                // Price detail
                Text(priceDetailText)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.top, 4)

                // Restore purchases
                Button("Restore Purchases") {
                    Task {
                        await subscriptionManager.restorePurchases()
                        if subscriptionManager.subscriptionStatus.isActive {
                            onComplete()
                        }
                    }
                }
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.35))
                .padding(.top, 2)
            }
            .padding(.bottom, 40)
        }
        .task {
            if let yearly = subscriptionManager.product(for: .yearly) {
                isTrialEligible = await subscriptionManager.isEligibleForTrial(product: yearly)
            }
        }
        .alert("Something went wrong", isPresented: $showError) {
            Button("OK") { showError = false }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Purchase Handler

    private func handlePurchase() async {
        let productID: SubscriptionManager.ProductID = selectedPlan == .yearly ? .yearly : .monthly

        guard let product = subscriptionManager.product(for: productID) else {
            errorMessage = "Subscription not available. Please try again."
            showError = true
            return
        }

        let result = await subscriptionManager.purchase(product)

        switch result {
        case .success:
            onComplete()
        case .cancelled:
            break // No-op, stay on paywall
        case .pending:
            errorMessage = "Your purchase is pending approval. You'll get access once it's approved."
            showError = true
        case .failed:
            if let error = subscriptionManager.purchaseError, error.errorDescription != nil {
                errorMessage = error.errorDescription!
            } else {
                errorMessage = "Purchase failed. Please try again."
            }
            showError = true
        }
    }

    // MARK: - Price Text

    private var priceDetailText: String {
        if selectedPlan == .yearly {
            let price = subscriptionManager.product(for: .yearly)?.displayPrice ?? "$29.99"
            if isTrialEligible {
                return "3 days free, then \(price) per year"
            } else {
                return "\(price) per year"
            }
        } else {
            let price = subscriptionManager.product(for: .monthly)?.displayPrice ?? "$9.99"
            if isTrialEligible {
                return "3 days free, then \(price) per month"
            } else {
                return "\(price) per month"
            }
        }
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(spacing: 0) {
            // Step 1: Today
            timelineStep(
                icon: "lock.open.fill",
                iconBackground: Color.green,
                title: "Today",
                subtitle: "Unlock all features — your AI moving concierge, personalized task list, vendor coordination, and more.",
                isFirst: true,
                isLast: false
            )

            // Step 2: In 2 Days
            timelineStep(
                icon: "bell.fill",
                iconBackground: Color.orange,
                title: "In 2 Days — Reminder",
                subtitle: "We'll send you a reminder that your trial is ending soon.",
                isFirst: false,
                isLast: false
            )

            // Step 3: In 3 Days
            timelineStep(
                icon: "crown.fill",
                iconBackground: Color.yellow,
                title: "In 3 Days — Billing Starts",
                subtitle: "You'll be charged unless you cancel anytime before.",
                isFirst: false,
                isLast: true
            )
        }
    }

    private func timelineStep(
        icon: String,
        iconBackground: Color,
        title: String,
        subtitle: String,
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline track + icon
            VStack(spacing: 0) {
                // Line above (invisible for first)
                Rectangle()
                    .fill(isFirst ? Color.clear : Color.white.opacity(0.15))
                    .frame(width: 2, height: 12)

                // Icon circle
                ZStack {
                    Circle()
                        .fill(iconBackground.opacity(0.2))
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(iconBackground)
                }

                // Line below (invisible for last)
                Rectangle()
                    .fill(isLast ? Color.clear : Color.white.opacity(0.15))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 36)

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.45))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 20)
        }
    }

    // MARK: - Plan Selector

    private var planSelector: some View {
        HStack(spacing: 12) {
            // Monthly
            planCard(
                label: "Monthly",
                price: subscriptionManager.product(for: .monthly)?.displayPrice ?? "$9.99",
                priceUnit: "/mo",
                badge: nil,
                isSelected: selectedPlan == .monthly
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { selectedPlan = .monthly }
            }

            // Yearly
            planCard(
                label: "Yearly",
                price: yearlyMonthlyPrice,
                priceUnit: "/mo",
                badge: isTrialEligible ? "3 DAYS FREE" : "BEST VALUE",
                isSelected: selectedPlan == .yearly
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { selectedPlan = .yearly }
            }
        }
    }

    private var yearlyMonthlyPrice: String {
        if let yearly = subscriptionManager.product(for: .yearly) {
            let monthlyEquivalent = yearly.price / 12
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.maximumFractionDigits = 2
            return formatter.string(from: monthlyEquivalent as NSDecimalNumber) ?? "$2.49"
        }
        return "$2.49"
    }

    private func planCard(
        label: String,
        price: String,
        priceUnit: String,
        badge: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Badge
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.green)
                        )
                } else {
                    // Spacer to keep alignment
                    Text(" ")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .opacity(0)
                }

                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(price)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)

                    Text(priceUnit)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }

                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.white : Color.white.opacity(0.2), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 24, height: 24)

                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? Color.white.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Shared Components
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Back button — top left
private func backButton(action: @escaping () -> Void) -> some View {
    HStack {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 44, height: 44)
        }
        Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.top, 8)
}

// Bottom section — checkmark, button, price line
private func bottomSection(
    checkmarkText: String,
    buttonText: String,
    priceText: String,
    action: @escaping () -> Void
) -> some View {
    VStack(spacing: 12) {
        // Checkmark line
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)

            Text(checkmarkText)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.bottom, 4)

        // CTA Button
        Button(action: action) {
            Text(buttonText)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                )
        }
        .padding(.horizontal, 24)

        // Price line
        Text(priceText)
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.35))
            .padding(.top, 4)
    }
    .padding(.bottom, 40)
}

// MARK: - Preview

#Preview("Page 1") {
    PaywallFlowView()
        .environmentObject(SubscriptionManager.shared)
}
