//
//  PaywallPolicy.swift
//  Peezy 4.0
//
//  Guided task flows are free. Move Pass is required only for the scanner,
//  packing, supplies fulfillment, and research help surfaces.
//

import SwiftUI

enum MovePassSurface {
    case scanner
    case packing
    case supplies
    case research

    fileprivate var analyticsTrigger: AnalyticsEvents.PaywallTrigger {
        switch self {
        case .scanner, .packing, .research:
            return .concierge
        case .supplies:
            return .kit
        }
    }
}

enum PaywallPolicy {
    /// Guided task flows are free; these dedicated help surfaces require the
    /// Move Pass.
    static func requiresMovePass(for surface: MovePassSurface) -> Bool {
        switch surface {
        case .scanner, .packing, .supplies, .research:
            return true
        }
    }
}

/// Presents the value screen before the StoreKit purchase screen. Callers
/// decide whether a dismissal returns to the originating surface or opens it
/// after entitlement state has updated.
struct PaywallGateSheet: View {
    let surface: MovePassSurface
    let onFinished: (Bool) -> Void

    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var stage: Stage = .value
    @State private var presentedAt: Date?

    private enum Stage {
        case value
        case purchase
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            switch stage {
            case .value:
                PaywallValueView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        stage = .purchase
                    }
                }
                .transition(.opacity)

                Button {
                    finish()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.15))
                        .padding()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("paywall_value_dismiss_button")

            case .purchase:
                PaywallGateView(onDismiss: finish)
                    .environmentObject(subscriptionManager)
                    .transition(.opacity)
            }
        }
        .onAppear {
            guard presentedAt == nil else { return }
            presentedAt = Date()
            AnalyticsEvents.paywallViewed(trigger: surface.analyticsTrigger)
        }
        .accessibilityIdentifier("paywall.gate_sheet")
    }

    private func finish() {
        let subscribed = subscriptionManager.isSubscribed
        if subscribed {
            AnalyticsEvents.paywallConverted(
                trigger: surface.analyticsTrigger,
                productId: SubscriptionManager.ProductID.move.rawValue
            )
        }
        onFinished(subscribed)
    }
}
