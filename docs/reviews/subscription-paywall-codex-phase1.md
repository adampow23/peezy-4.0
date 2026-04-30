# Phase 1: Subscription / Paywall — How It Works

**Reviewer:** codex  
**Date:** April 29, 2026  
**Files reviewed:**  
- `Peezy 4.0/MainInterface/Models/SubscriptionManager.swift`
- `Peezy 4.0/MainInterface/Models/SubscriptionAPIClient.swift`
- `Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift`
- `Peezy 4.0/MainInterface/Views/Paywall/PaywallValueView.swift`
- `Peezy 4.0/Assessment/AssessmentViews/Onboarding/CompletionFlowView.swift`
- `Peezy 4.0/Assessment/AssessmentModels/AssessmentFlowView.swift`
- `Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift`
- `Peezy 4.0/MainInterface/Models/PeezyV1App.swift`
- `Peezy 4.0/MainInterface/Views/AppRootView.swift`
- `Peezy 4.0/Auth/AuthViewModel.swift`
- `Peezy 4.0/Menu/PeezySettingsView.swift` (subscription/sign-out sections)

## 1. High-level summary

Peezy's subscription system is centered on a `@MainActor` `SubscriptionManager` singleton that loads StoreKit 2 products, tracks current entitlements, starts a transaction listener, and exposes published state to SwiftUI (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:21-52`). The paywall UI is split into a value screen with no purchase logic and a gate screen that displays plans, purchase, restore, offer-code redemption, subscription terms, privacy, and terms links (`Peezy 4.0/MainInterface/Views/Paywall/PaywallValueView.swift:4-12`, `Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:84-140`). At runtime, the paywall appears in the post-assessment completion flow after the summary stage (`Peezy 4.0/Assessment/AssessmentViews/Onboarding/CompletionFlowView.swift:77-99`).

## 2. SubscriptionManager lifecycle

- `SubscriptionManager` is declared `@MainActor`, conforms to `ObservableObject`, and is implemented as a singleton via `static let shared = SubscriptionManager()` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:21-27`).
- The app initializes the singleton in `PeezyV1App.init()` before views appear, with a comment that this starts the StoreKit transaction listener early (`Peezy 4.0/MainInterface/Models/PeezyV1App.swift:16-20`).
- The singleton is injected into the root SwiftUI hierarchy with `.environmentObject(SubscriptionManager.shared)` on `AppRootView()` (`Peezy 4.0/MainInterface/Models/PeezyV1App.swift:23-28`).
- `SubscriptionManager.init()` is private. It assigns `transactionListener = listenForTransactions()`, then launches a `Task` that awaits `loadProducts()` and `updateSubscriptionStatus()` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:106-115`).
- Products are loaded from hardcoded StoreKit product identifiers `peezy.plus.weekly` and `peezy.plus.annual` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:30-33`). `loadProducts()` calls `Product.products(for:)`, sorts the loaded products with annual first, sets `products`, and sets `isLoaded = true` on success (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:123-139`).
- Purchase state is stored in `@Published` properties: `products`, `subscriptionStatus`, `isPurchasing`, `purchaseError`, and `isLoaded` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:46-52`).
- The subscription state enum has five cases: `.notSubscribed`, `.trial(productId:expirationDate:)`, `.subscribed(productId:expirationDate:)`, `.expired`, and `.revoked` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:54-69`). `isSubscribed` returns `subscriptionStatus.isActive`; `.trial` and `.subscribed` are active (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:35-44`, `Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:63-68`).
- `updateSubscriptionStatus()` iterates `Transaction.currentEntitlements`, ignores unverified results and non-auto-renewable products, treats revoked transactions as `.revoked`, treats future-dated auto-renewable entitlements as either `.trial` or `.subscribed` based on `transaction.offerType == .introductory`, and falls back to `.expired` only if the previous status was `.trial` or `.subscribed` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:210-256`).
- `listenForTransactions()` returns a detached task that loops over `Transaction.updates`, handles only verified transactions, calls `updateSubscriptionStatus()`, calls `syncToServer(transaction:)`, and then finishes the transaction (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:258-270`).
- `deinit` cancels `transactionListener`, although the singleton lifetime means this is only reached if the singleton is deallocated (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:117-119`).

## 3. Paywall presentation

- The paywall is presented from the assessment completion flow. `AssessmentFlowView` presents `CompletionFlowView` in a `.fullScreenCover` when `coordinator.isComplete` is true (`Peezy 4.0/Assessment/AssessmentModels/AssessmentFlowView.swift:55-60`).
- `AssessmentCoordinator.completeAssessment()` sets `isComplete = true` immediately before geocoding, save, and task generation work continues (`Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift:517-533`).
- `CompletionFlowView` has a local `Stage` enum with `.generating`, `.ready`, `.summary`, `.paywall`, and `.paywallGate` stages (`Peezy 4.0/Assessment/AssessmentViews/Onboarding/CompletionFlowView.swift:22-34`). It renders exactly one stage in a `switch` (`Peezy 4.0/Assessment/AssessmentViews/Onboarding/CompletionFlowView.swift:55-103`).
- The automatic path to the paywall is: `.summary` renders `SummaryView`; its `onGetStarted` closure calls `advanceStage(to: .paywall)` (`Peezy 4.0/Assessment/AssessmentViews/Onboarding/CompletionFlowView.swift:77-84`). The `.paywall` case renders `PaywallValueView`; its `onContinue` closure advances to `.paywallGate` (`Peezy 4.0/Assessment/AssessmentViews/Onboarding/CompletionFlowView.swift:87-91`). The `.paywallGate` case renders `PaywallGateView`; its dismiss closure calls `routeToMainApp()` (`Peezy 4.0/Assessment/AssessmentViews/Onboarding/CompletionFlowView.swift:93-99`).
- `PaywallValueView` displays a Peezy+ value screen with headline copy, free-trial/price text derived from the annual product, and one "Try it free" CTA that calls `onContinue` (`Peezy 4.0/MainInterface/Views/Paywall/PaywallValueView.swift:22-83`).
- `PaywallGateView` displays a dismiss button, hero copy, six feature rows, annual and weekly pricing cards, a purchase CTA, "Redeem a code", "Restore Purchases", subscription terms text, and Privacy Policy / Terms of Service links (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:23-145`).
- The paywall gate can be dismissed without purchase via the top-right dismiss button; the button calls `onDismiss()` (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:25-39`). In `CompletionFlowView`, that dismiss callback routes to the main app (`Peezy 4.0/Assessment/AssessmentViews/Onboarding/CompletionFlowView.swift:93-99`, `Peezy 4.0/Assessment/AssessmentViews/Onboarding/CompletionFlowView.swift:122-139`).

## 4. Purchase flow

- The annual plan is selected by default with `@State private var selectedPlan: SubscriptionManager.ProductID = .annual` (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:16`).
- Plan cards update `selectedPlan` when tapped and use `subscriptionManager.product(for:)` to display StoreKit `displayPrice` and introductory offer text (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:188-271`).
- The purchase CTA is a `PeezyAssessmentButton(ctaLabel)` that calls `purchaseSelected()` (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:84-90`).
- `purchaseSelected()` looks up the selected product. If no product is loaded for the selected plan, it returns without changing local UI state (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:273-283`).
- If a product exists, `purchaseSelected()` starts a `Task`, awaits `subscriptionManager.purchase(product)`, and calls `onDismiss()` only for `.success` (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:275-282`).
- The StoreKit purchase call is `let result = try await product.purchase()` inside `SubscriptionManager.purchase(_:)` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:144-150`).
- `purchase(_:)` sets `isPurchasing = true` and clears `purchaseError` before calling StoreKit (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:144-147`). The CTA label reads "Processing..." while `subscriptionManager.isPurchasing` is true (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:148-153`).
- On verified success, `purchase(_:)` awaits `updateSubscriptionStatus()`, starts a fire-and-forget server sync task, finishes the transaction, sets `isPurchasing = false`, and returns `.success` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:151-162`).
- On unverified success, it sets `purchaseError = .verificationFailed`, sets `isPurchasing = false`, and returns `.failed(error)` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:164-170`).
- On `.userCancelled`, it sets `purchaseError = .purchaseCancelled`, sets `isPurchasing = false`, and returns `.cancelled` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:173-176`). The localized description for `.purchaseCancelled` is `nil` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:82-99`).
- On `.pending`, it sets `purchaseError = .purchasePending`, sets `isPurchasing = false`, and returns `.pending` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:178-181`).
- On thrown errors, it sets `purchaseError = .purchaseFailed(underlying: error)`, sets `isPurchasing = false`, and returns `.failed(error)` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:187-190`).
- `PaywallGateView` does not read `subscriptionManager.purchaseError` in its body, so purchase failures are stored in `SubscriptionManager` but no paywall-local error text or alert is rendered there (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:18-146`, `Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:273-283`).

## 5. Restore purchases flow

- The paywall restore UI is a tertiary "Restore Purchases" button in `PaywallGateView` (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:92-119`).
- That button starts a `Task`, awaits `subscriptionManager.restorePurchases()`, and dismisses the paywall only if `subscriptionManager.isSubscribed` is true after restore returns (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:107-113`).
- `restorePurchases()` calls `try await AppStore.sync()` and then `await updateSubscriptionStatus()` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:194-205`).
- On restore failure, `restorePurchases()` sets `purchaseError = .purchaseFailed(underlying: error)` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:196-205`).
- The settings screen also has a subscription section with "Restore purchases"; it calls `subscriptionManager.restorePurchases()` and then sets `restoreMessage` to either "Purchases restored successfully." or "Unable to restore purchases. Please try again." based on whether `subscriptionManager.purchaseError == nil` (`Peezy 4.0/Menu/PeezySettingsView.swift:330-385`).
- The settings restore message is displayed by an alert titled "Restore purchases" when `restoreMessage != nil` (`Peezy 4.0/Menu/PeezySettingsView.swift:205-212`).
- The paywall restore flow itself does not set a local success or failure message in `PaywallGateView`; success is represented by dismissing when `isSubscribed` is true, and failure leaves the paywall visible (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:107-113`).

## 6. Error handling

- Product loading errors are caught in `loadProducts()`. In debug builds they are printed, and `purchaseError` is set to `.networkError`; `isLoaded` is only set on success (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:123-139`).
- Purchase errors represented by `PurchaseError` include `.productNotFound`, `.purchaseFailed(underlying:)`, `.purchaseCancelled`, `.purchasePending`, `.verificationFailed`, and `.networkError` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:80-100`).
- The `PurchaseError.errorDescription` strings are: "Subscription not available.", the underlying error localized description, `nil` for cancellation, "Purchase pending approval.", "Could not verify purchase.", and "Network error. Please try again." (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:90-99`).
- `purchaseSelected()` handles missing products by returning early; it does not set `purchaseError = .productNotFound` (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:273-283`).
- StoreKit `.userCancelled` is tracked as `.purchaseCancelled` and returned as `.cancelled` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:173-176`).
- StoreKit `.pending` is tracked as `.purchasePending` and returned as `.pending` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:178-181`).
- Thrown errors from `product.purchase()` are tracked as `.purchaseFailed(underlying:)` and returned as `.failed(error)` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:187-190`).
- Unverified transactions returned from `product.purchase()` are tracked as `.verificationFailed` and returned as `.failed(error)` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:164-170`).
- Restore failures are caught in `restorePurchases()` and stored as `.purchaseFailed(underlying:)` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:196-205`).
- Server sync errors are caught and printed in debug builds only; the comment and behavior make this non-fatal to the purchase flow (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:157-160`, `Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:282-307`).
- `SubscriptionAPIClient.validateReceipt(payload:)` can throw for a bad URL, JSON serialization, URLSession failure, or non-2xx HTTP response (`Peezy 4.0/MainInterface/Models/SubscriptionAPIClient.swift:14-31`).
- The paywall body does not display `purchaseError`; the settings restore flow displays a generic restore success/failure message through `restoreMessage` (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:18-146`, `Peezy 4.0/Menu/PeezySettingsView.swift:205-212`, `Peezy 4.0/Menu/PeezySettingsView.swift:374-384`).

## 7. State management edge cases

- On app launch, `PeezyV1App.init()` initializes `SubscriptionManager.shared` (`Peezy 4.0/MainInterface/Models/PeezyV1App.swift:16-20`). The manager starts the transaction listener, loads products, and updates subscription status during its private initializer (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:106-115`).
- If the user has an active subscription available in `Transaction.currentEntitlements`, `updateSubscriptionStatus()` sets `.trial` or `.subscribed` when the verified auto-renewable transaction has an expiration date later than `Date()` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:213-242`).
- Sign-in changes are handled in `AppRootView` through `AuthViewModel.isAuthenticated`; on sign-in it calls `checkAssessmentStatus()`, and on sign-out it sets `appState = .notAuthenticated` and clears `userState` (`Peezy 4.0/MainInterface/Views/AppRootView.swift:64-71`).
- `AuthViewModel.signOut()` calls `Auth.auth().signOut()`, then sets `isAuthenticated = false` and `currentUser = nil` (`Peezy 4.0/Auth/AuthViewModel.swift:202-208`). The reviewed sign-out code does not call any `SubscriptionManager` method.
- Server sync includes Firebase Auth user ID only if `Auth.auth().currentUser?.uid` exists; otherwise `syncToServer(transaction:)` returns without sending a payload (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:282-286`).
- When no active entitlement is found, `updateSubscriptionStatus()` changes the previous `.trial` or `.subscribed` state to `.expired`; it keeps `.revoked` as `.revoked`; otherwise it sets `.notSubscribed` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:245-255`).
- `Transaction.currentEntitlements` processing only sets `.revoked` when a verified entitlement in the loop has a non-nil `revocationDate` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:213-221`).
- Renewal and external purchase updates are handled by the detached `Transaction.updates` listener, which updates local subscription status, attempts server sync, and finishes each verified transaction (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:258-270`).
- Billing retry and grace period are not represented as explicit cases in `SubscriptionStatus`; the local enum has `.notSubscribed`, `.trial`, `.subscribed`, `.expired`, and `.revoked` only (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:54-69`). The code path reviewed does not call StoreKit subscription renewal-state APIs.

## 8. Apple documentation status (as of April 2026)

- **Guideline 3.1.2 subscriptions — confirmed current from Apple.** Apple's current App Review Guidelines say auto-renewable subscriptions may be offered in any App Store category, must provide ongoing value, must last at least seven days, must work across the user's devices, and before asking the customer to subscribe the app should clearly describe what the user gets for the price ([Apple App Review Guidelines, lines 361-375](https://developer.apple.com/app-store/review/guidelines/)). In the reviewed implementation, the paywall describes Peezy+ features before purchase (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:55-70`) and shows weekly/yearly plan pricing from StoreKit product data (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:188-206`).
- **Guideline 3.1.1 in-app purchase — confirmed current from Apple.** Apple's current guidelines state that unlocking app features or functionality through subscriptions must use in-app purchase, and apps may not use their own unlock mechanisms for that content ([Apple App Review Guidelines, lines 341-356](https://developer.apple.com/app-store/review/guidelines/)). In the reviewed paywall purchase flow, the subscription CTA calls StoreKit `Product.purchase()` (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:144-150`).
- **StoreKit 2 best-practice source status — confirmed current from Apple documentation pages.** Apple documents `Transaction.currentEntitlements` as the sequence of latest transactions that entitle the customer to IAPs/subscriptions, including auto-renewable subscriptions in subscribed or grace-period state ([Apple `Transaction.currentEntitlements`](https://developer.apple.com/documentation/storekit/transaction/currententitlements)). Apple documents `Transaction.updates` as the sequence for transactions created or updated outside the app or on other devices ([Apple `Transaction.updates`](https://developer.apple.com/documentation/storekit/transaction/updates)). The implementation uses both APIs (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:210-270`).
- **Restore purchases requirements — confirmed current from Apple documentation.** Apple's `AppStore.sync()` documentation says to include a mechanism such as a Restore Purchases button and to call `sync()` only in response to explicit user action because it displays an App Store authentication prompt ([Apple `AppStore.sync()`](https://developer.apple.com/documentation/storekit/appstore/sync%28%29)). The implementation calls `AppStore.sync()` from explicit restore buttons in the paywall and settings (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:107-118`, `Peezy 4.0/Menu/PeezySettingsView.swift:374-384`, `Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:196-199`).
- **Subscription paywall UI requirements — confirmed at the App Review guideline level and App Store subscription overview level.** Apple states that before subscription purchase the app should clearly describe what the customer receives for the price ([Apple App Review Guidelines, lines 374-375](https://developer.apple.com/app-store/review/guidelines/)). Apple's auto-renewable subscription overview says subscriptions are configured in App Store Connect with name, price, and description; it also says to follow App Review Guidelines and Human Interface Guidelines ([Apple Auto-renewable Subscriptions, lines 174-189](https://developer.apple.com/app-store/subscriptions/)). The implementation renders feature bullets, plan cards, renewal terms text, and privacy/terms links on the gate screen (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:62-140`).
- **Common 2025-2026 paywall rejection reasons — partially verified.** Apple officially documents misleading marketing/scams in subscription flows as removable behavior ([Apple App Review Guidelines, lines 370-371](https://developer.apple.com/app-store/review/guidelines/)), incomplete or nonfunctional IAPs as App Completeness issue 2.1(b) ([Apple App Review Guidelines, lines 263-267](https://developer.apple.com/app-store/review/guidelines/)), and broken privacy/support links as common review issues ([Apple App Review overview](https://developer.apple.com/app-store/review/)). I also found current Apple Developer Forum examples of 3.1.2 rejections citing missing Terms of Use and Privacy Policy links in-app and in metadata, but forum posts are anecdotal reviewer/developer reports rather than normative Apple documentation ([Apple Developer Forums thread 813493](https://developer.apple.com/forums/thread/813493)).
- **Recent subscription changes — confirmed current from Apple News.** On April 27, 2026, Apple announced monthly subscriptions with a 12-month commitment, configurable in App Store Connect and testable in Xcode, with listed platform/storefront availability details ([Apple Developer News, lines 160-167](https://developer.apple.com/news/?id=agq42lxe)). The reviewed implementation defines weekly and annual product IDs only (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:30-33`).
- **Billing retry / grace period docs — confirmed current from Apple subscription overview.** Apple states subscription renewal failures can trigger billing retry, App Store Server Notifications `DID_FAIL_TO_RENEW`, StoreKit renewal state, App Store Server API status checks, and optional Billing Grace Period behavior ([Apple Auto-renewable Subscriptions, lines 382-401](https://developer.apple.com/app-store/subscriptions/)). The reviewed local subscription enum does not model billing retry or grace period separately (`Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:54-69`).

## 9. Specific observations

- `SubscriptionManager.swift:30-33` hardcodes two product IDs: `peezy.plus.weekly` and `peezy.plus.annual`.
- `SubscriptionManager.swift:128-131` sorts products with a closure that only checks whether `p1.id` is the annual product ID.
- `SubscriptionManager.swift:133` sets `isLoaded = true` only after product loading succeeds. The reviewed paywall does not branch on `isLoaded` (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:18-146`).
- `PaywallGateView.swift:150-167` builds the purchase CTA label dynamically. Annual uses introductory offer information when present; weekly uses `displayPrice` when loaded.
- `PaywallValueView.swift:72-83` displays "Free trial available" if the annual StoreKit product is not yet loaded.
- `PaywallGateView.swift:123-129` contains subscription renewal terms text in the binary.
- `PaywallGateView.swift:131-136` links to `https://peezy-1ecrdl.web.app/privacy.html` and `https://peezy-1ecrdl.web.app/terms.html`.
- `PaywallGateView.swift:94-103` includes an offer-code redemption button that calls `AppStore.presentOfferCodeRedeemSheet(in:)`.
- `PaywallGateView.swift:25-39` includes a dismiss button. In the reviewed presentation path, dismissing the paywall routes to the main app (`Peezy 4.0/Assessment/AssessmentViews/Onboarding/CompletionFlowView.swift:93-99`, `Peezy 4.0/Assessment/AssessmentViews/Onboarding/CompletionFlowView.swift:124-139`).
- `CompletionFlowView.swift:41-47` only allows stage advancement to stages with a greater raw value.
- `CompletionFlowView.swift:105` applies `.interactiveDismissDisabled()` to the completion flow.
- `SubscriptionManager.swift:157-160` starts server sync as a separate `Task` after a verified purchase and before `transaction.finish()`.
- `SubscriptionManager.swift:282-307` syncs transaction data to `SubscriptionAPIClient.validateReceipt(payload:)` only when Firebase Auth has a current user ID.
- `SubscriptionAPIClient.swift:15` posts to `"\(PeezyConfig.firebaseFunctionURL)/validateSubscription"`.
- `PeezySettingsView.swift:365-370` includes a "Manage Subscription" row that opens `https://apps.apple.com/account/subscriptions`.
- `PeezySettingsView.swift:390-419` maps local subscription states to settings labels and detail text. `.trial` displays "Free Trial Active"; `.subscribed` displays "Peezy Premium"; `.expired` displays "Subscription Expired"; `.revoked` displays "Subscription Revoked"; `.notSubscribed` displays "Not Subscribed".

## 10. Things you could not determine

- I could not determine from the reviewed code whether the App Store Connect subscription group, product metadata, screenshots, review notes, EULA URL, and privacy URL are configured correctly, because those settings are not stored in the Swift files reviewed.
- I could not determine whether `peezy.plus.weekly` and `peezy.plus.annual` are approved, available in all target storefronts, in the same subscription group, or configured with the intended introductory offer, because that requires App Store Connect state.
- I could not verify whether the hosted privacy and terms URLs are live from inside the code-reading pass; the Swift code only shows the URL strings (`Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:131-136`).
- I could not determine whether the Firebase Cloud Function `/validateSubscription` records renewal, refund, billing retry, or grace-period events beyond the client POST shape, because the Cloud Function implementation was not in the searched Swift files (`Peezy 4.0/MainInterface/Models/SubscriptionAPIClient.swift:14-31`).
- I could not determine whether StoreKit configuration files or App Store Server Notification settings exist outside the reviewed Swift search results; `find "Peezy 4.0" -name "*Paywall*.swift" -o -name "*Subscription*.swift" -o -name "*StoreKit*.swift"` returned only the four subscription/paywall Swift files listed above.
- I could not comprehensively verify "common 2025-2026 paywall rejection reasons" as a complete list. I verified current Apple guideline language and found current Apple Developer Forum examples, but forum examples are not a complete or official rejection taxonomy.
