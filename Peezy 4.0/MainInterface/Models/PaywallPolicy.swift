//
//  PaywallPolicy.swift
//  Peezy 4.0
//
//  Paywall timing option (c) — LOCKED (architecture §10, Spec 04 Phase D).
//  Soft dismissible offer post-assessment (CompletionFlowView, untouched) +
//  hard gate at the moments only Peezy can deliver: vendor booking (BOOK
//  stage on SPINE flows), the supplies-kit one-tap order (when it exists),
//  and concierge execution (flow submissions that put Peezy to work).
//  Free tier untouched: assessment, daily dose, self-service paths,
//  inventory scan, packing plan.
//
//  This file hosts the ONE sanctioned second PaywallGateView call site
//  (PaywallGateSheet). SubscriptionManager and PaywallGateView themselves
//  are COMPLIANCE-frozen — consulted, never modified.
//

import SwiftUI

/// The actions Peezy+ gates. Everything a checklist can do stays free;
/// everything only Peezy can do is behind the gate.
enum PaywallGatedAction {
    /// BOOK-stage transition on a SPINE flow (movers, cleaners quotes).
    case vendorBooking
    /// A flow submission that puts Peezy to work on the user's behalf
    /// (resolver/concierge summaries — "we'll reach out to...").
    case conciergeSubmission
    /// Supplies-kit one-tap order (lands with the packing plan).
    case suppliesKitOrder

    var analyticsTrigger: AnalyticsEvents.PaywallTrigger {
        switch self {
        case .vendorBooking: .book
        case .conciergeSubmission: .concierge
        case .suppliesKitOrder: .kit
        }
    }
}

enum PaywallPolicy {

    /// The single gating function (architecture §10). Consulted at stage
    /// transitions / submission moments.
    static func requiresSubscription(for action: PaywallGatedAction) -> Bool {
        switch action {
        case .vendorBooking, .conciergeSubmission, .suppliesKitOrder:
            return true
        }
    }

    /// True when the action may proceed for this user right now.
    static func allows(_ action: PaywallGatedAction) -> Bool {
        !requiresSubscription(for: action) || SubscriptionManager.shared.isSubscribed
    }
}

// MARK: - Gate presentation (the sanctioned second call site)

/// Full-screen wrapper around PaywallGateView for the hard gate. Presented
/// over a flow when a gated action is attempted unsubscribed. Dismissal
/// returns to the flow; if the user subscribed inside the paywall, the
/// pending action re-fires.
struct PaywallGateSheet: View {
    let action: PaywallGatedAction
    /// Called on dismiss; `true` when the user is subscribed on the way out.
    let onFinished: (Bool) -> Void
    @State private var presentedAt: Date?

    var body: some View {
        PaywallGateView(onDismiss: {
            let subscribed = SubscriptionManager.shared.isSubscribed
            if subscribed, let presentedAt {
                Task {
                    await AnalyticsEvents.recordNewPaywallConversion(
                        trigger: action.analyticsTrigger,
                        presentedAt: presentedAt
                    )
                }
            }
            onFinished(subscribed)
        })
        .environmentObject(SubscriptionManager.shared)
        .onAppear {
            guard presentedAt == nil else { return }
            presentedAt = Date()
            AnalyticsEvents.paywallViewed(trigger: action.analyticsTrigger)
        }
        .accessibilityIdentifier("paywall.gate_sheet")
    }
}
