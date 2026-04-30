# Phase 1: Subscription / Paywall — How It Works

**Reviewer:** Gemini CLI
**Date:** Wednesday, April 29, 2026
**Files reviewed:** 
- `Peezy 4.0/MainInterface/Models/SubscriptionManager.swift`
- `Peezy 4.0/MainInterface/Models/SubscriptionAPIClient.swift`
- `Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift`
- `Peezy 4.0/MainInterface/Views/Paywall/PaywallValueView.swift`
- `Peezy 4.0/Assessment/AssessmentViews/Onboarding/CompletionFlowView.swift`

## 1. High-level summary
The subscription feature is built using a modern StoreKit 2 architecture centered around a `SubscriptionManager` singleton. It implements a two-stage gated paywall (Value Teaser -> Purchase Gate) presented immediately after the user completes the initial move assessment. The system handles product fetching, transaction processing, local entitlement tracking, and fire-and-forget server-side validation via Firebase Cloud Functions.

## 2. SubscriptionManager lifecycle
- **Instantiation:** It is a `@MainActor` singleton (`SubscriptionManager.shared`) initialized on app start. It is injected into the SwiftUI view hierarchy via `.environmentObject()`.
- **Product Loading:** Products (`peezy.plus.weekly`, `peezy.plus.annual`) are loaded asynchronously in the `init` via `loadProducts()`.
- **Purchase State Tracking:** The manager tracks state using `@Published` properties: `products`, `subscriptionStatus`, `isPurchasing`, `purchaseError`, and `isLoaded`.
- **Threading Model:** The class is decorated with `@MainActor`, ensuring all UI updates and state changes occur on the main thread. 
- **Transaction Listener:** A detached `Task` is started in `init` to iterate over `Transaction.updates`. This listener handles background renewals, billing issues, and external purchases.

## 3. Paywall presentation
- **Location:** The paywall appears at the end of the `CompletionFlowView`, which follows the "Assessment" sequence.
- **Trigger:** It is triggered automatically when the user taps "Get Started" in the `SummaryView`, advancing the flow to `.paywall`.
- **Conditions:** The paywall is part of the linear completion sequence. `PaywallGateView` dismisses itself upon a successful purchase or manual dismissal.
- **User Experience:** The user first sees `PaywallValueView` (high-level value proposition). Tapping "Try it free" slides in the `PaywallGateView`, which contains specific feature lists, plan selection, and the final purchase CTA.

## 4. Purchase flow
- **Steps:**
    1. User selects a plan in `PaywallGateView`.
    2. User taps the CTA button, triggering `purchaseSelected()`.
    3. `SubscriptionManager.purchase(_:)` is called.
    4. StoreKit's `product.purchase()` is invoked.
    5. Upon success, the transaction is verified using JWS.
    6. Local state is updated via `updateSubscriptionStatus()`.
    7. `syncToServer()` is called (fire-and-forget).
    8. `transaction.finish()` is called.
- **States:** `isPurchasing` is set to `true` during the process, updating the CTA label to "Processing...".
- **Failures:** Failures are caught and mapped to `PurchaseError`.

## 5. Restore purchases flow
- **Location:** A "Restore Purchases" button is located in the footer of `PaywallGateView.swift` (line 118).
- **Logic:** It calls `subscriptionManager.restorePurchases()`, which invokes `AppStore.sync()`.
- **Feedback:** The view checks `subscriptionManager.isSubscribed` after sync. If true, it calls `onDismiss()`.

## 6. Error handling
- **Error Types:** `PurchaseError` covers `productNotFound`, `purchaseFailed`, `purchaseCancelled`, `purchasePending`, `verificationFailed`, and `networkError`.
- **Surfacing:** Errors are stored in the `@Published purchaseError` property.
- **Specific Scenarios:** `userCancelled` is handled to stop loading without showing an error state.

## 7. State management edge cases
- **App Launch:** `updateSubscriptionStatus()` is called in `init` to restore active state from `Transaction.currentEntitlements`.
- **Sign-in/Sign-out:** `syncToServer` requires an active Firebase UID.
- **Expiration:** `updateSubscriptionStatus()` transitions the state to `.expired` if no active entitlements are found.
- **Renewal/Billing Failure:** The background `transactionListener` updates `subscriptionStatus` for these events.

## 8. Apple documentation status (as of April 2026)
- **Guideline 3.1.2 (Subscriptions):** **Confirmed Current.** Required billing terms and links to Privacy/Terms are present.
- **Guideline 3.1.1 (In-App Purchase):** **Confirmed Current.** Uses StoreKit 2 for digital content.
- **StoreKit 2 Best Practices:** **Confirmed Current.** Uses `async/await`, JWS verification, and proper transaction finishing.
- **Restore Purchases:** **Confirmed Current.** Visible and functional button provided on the paywall.
- **Rejection Risks:** 
    - *Observation:* Hardcoded trial text in `PaywallValueView` ("free for 3 days") may conflict with dynamic StoreKit metadata, posing a risk of "misleading content" rejection if they diverge.

## 9. Specific observations
- `SubscriptionManager.swift:189`: Uses a detached task for the transaction listener.
- `PaywallGateView.swift:112`: Restore button check depends on immediate state update after `await`.
- `SubscriptionManager.swift:34`: Subscription IDs are hardcoded in an enum.
- `PaywallGateView.swift:217`: Correctly fetches dynamic trial duration for the CTA label.

## 10. Things you could not determine
- **Error UI:** I did not locate the specific UI code (e.g., `.alert`) that presents the `purchaseError` to the user.
- **Sync Reliability:** The "fire-and-forget" nature of `syncToServer` lacks a retry mechanism for failed server updates after a successful Apple purchase.
