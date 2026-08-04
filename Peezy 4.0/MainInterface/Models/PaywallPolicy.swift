//
//  PaywallPolicy.swift
//  Peezy 4.0
//
//  The free tier is the personalized task list. Opening any task substance
//  or entering a task-adjacent tool requires an active Move Pass.
//

import SwiftUI

enum MovePassSurface {
    case task
    case scanner
    case packing
    case supplies
    case research

    fileprivate var analyticsTrigger: AnalyticsEvents.PaywallTrigger {
        switch self {
        case .task:
            return .postAssessment
        case .scanner, .packing, .research:
            return .concierge
        case .supplies:
            return .kit
        }
    }
}

enum PaywallPolicy {
    /// The task list is the complete free tier. All task substance and every
    /// task-adjacent tool named here requires Move Pass access.
    static func requiresMovePass(for surface: MovePassSurface) -> Bool {
        switch surface {
        case .task, .scanner, .packing, .supplies, .research:
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
