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

    var onComplete: (() -> Void)?

    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var currentPage: Int = 0

    var body: some View {
        ZStack {
            InteractiveBackground()

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
        onComplete?()
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
                    .foregroundColor(PeezyTheme.Colors.deepInk)
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
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                // Bell icon with notification badge
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 64))
                        .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.2))

                    // Notification badge
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 28, height: 28)

                        Text("1")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(PeezyTheme.Colors.deepInk)
                    }
                    .offset(x: 8, y: -4)
                }
                .padding(.top, 8)

                // Reassurance copy
                Text("We genuinely want Peezy to provide value for your move. Try everything free — if it's not for you, cancel anytime before the trial ends and you won't be charged a thing.")
                    .font(.system(size: 15))
                    .foregroundColor(Color.gray)
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
                        .foregroundColor(PeezyTheme.Colors.deepInk)
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
                .frame(maxWidth: .infinity)
            }

            // Bottom section — pinned below scroll
            VStack(spacing: 8) {
                // Checkmark (only if trial eligible)
                if isTrialEligible {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(PeezyTheme.Colors.deepInk)

                        Text("No Payment Due Now")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(PeezyTheme.Colors.deepInk)
                    }
                    .padding(.bottom, 2)
                }

                // CTA Button
                Button(action: {
                    Task { await handlePurchase() }
                }) {
                    Group {
                        if subscriptionManager.isPurchasing {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(isTrialEligible ? "Start My 3-Day Free Trial" : "Subscribe Now")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(subscriptionManager.isPurchasing ? .white.opacity(0.4) : .white)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 56)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(.regularMaterial)
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(PeezyTheme.Colors.deepInk.opacity(subscriptionManager.isPurchasing ? 0.4 : 0.6))
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(subscriptionManager.isPurchasing ? 0.1 : 0.3), radius: 15, x: 0, y: 8)
                }
                .disabled(subscriptionManager.isPurchasing)
                .padding(.horizontal, 24)

                // Price detail + restore on same line
                VStack(spacing: 4) {
                    Text(priceDetailText)
                        .font(.system(size: 13))
                        .foregroundColor(Color.gray)

                    Button("Restore Purchases") {
                        Task {
                            await subscriptionManager.restorePurchases()
                            if subscriptionManager.subscriptionStatus.isActive {
                                onComplete()
                            }
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundColor(Color.gray)
                }
                .padding(.top, 4)
            }
            .padding(.bottom, 24)
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
            if let error = subscriptionManager.purchaseError, let desc = error.errorDescription {
                errorMessage = desc
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
        let iconSize: CGFloat = 36
        let iconColumnWidth: CGFloat = 36

        return ZStack(alignment: .topLeading) {
            // Continuous vertical line — positioned at horizontal center of icon column
            GeometryReader { geo in
                Rectangle()
                    .fill(PeezyTheme.Colors.deepInk.opacity(0.1))
                    .frame(width: 2)
                    // Inset top/bottom by half icon height so line runs center-to-center
                    .padding(.top, iconSize / 2)
                    .padding(.bottom, iconSize / 2)
                    .frame(height: geo.size.height)
                    // Center the line within the icon column
                    .offset(x: (iconColumnWidth - 2) / 2)
            }

            // Steps layered on top of the line
            VStack(spacing: 0) {
                timelineStep(
                    icon: "lock.open.fill",
                    iconBackground: Color.green,
                    title: "Today",
                    subtitle: "Unlock all features — your AI moving concierge, personalized task list, vendor coordination, and more.",
                    isLast: false
                )

                timelineStep(
                    icon: "bell.fill",
                    iconBackground: Color.orange,
                    title: "In 2 Days — Reminder",
                    subtitle: "We'll send you a reminder that your trial is ending soon.",
                    isLast: false
                )

                timelineStep(
                    icon: "crown.fill",
                    iconBackground: Color.yellow,
                    title: "In 3 Days — Billing Starts",
                    subtitle: "You'll be charged unless you cancel anytime before.",
                    isLast: true
                )
            }
        }
    }

    private func timelineStep(
        icon: String,
        iconBackground: Color,
        title: String,
        subtitle: String,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon circle — sits on top of the continuous background line
            ZStack {
                Circle()
                    .fill(iconBackground.opacity(0.2))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconBackground)
            }
            .frame(width: 36)

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(PeezyTheme.Colors.deepInk)

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(Color.gray)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, isLast ? 0 : 24)
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
                    .foregroundColor(isSelected ? PeezyTheme.Colors.lightBase : PeezyTheme.Colors.deepInk)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(price)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(isSelected ? PeezyTheme.Colors.lightBase : PeezyTheme.Colors.deepInk)

                    Text(priceUnit)
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? PeezyTheme.Colors.lightBase.opacity(0.6) : Color.gray)
                }

                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? PeezyTheme.Colors.lightBase.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(PeezyTheme.Colors.lightBase)
                            .frame(width: 24, height: 24)

                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(PeezyTheme.Colors.deepInk)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(PeezyTheme.Colors.deepInk)
                    } else {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.regularMaterial)
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.15))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(
                color: isSelected ? PeezyTheme.Colors.deepInk.opacity(0.25) : Color.black.opacity(0.1),
                radius: isSelected ? 10 : 12,
                x: 0,
                y: isSelected ? 4 : 8
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
                .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))
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
                .foregroundColor(PeezyTheme.Colors.deepInk)

            Text(checkmarkText)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(PeezyTheme.Colors.deepInk)
        }
        .padding(.bottom, 4)

        // CTA Button
        PeezyAssessmentButton(buttonText, action: action)
            .padding(.horizontal, 24)

        // Price line
        Text(priceText)
            .font(.system(size: 13))
            .foregroundColor(Color.gray)
            .padding(.top, 4)
    }
    .padding(.bottom, 40)
}

// MARK: - Preview

#Preview("Page 3") {
    PaywallFlowView()
        .environmentObject(SubscriptionManager.shared)
}
