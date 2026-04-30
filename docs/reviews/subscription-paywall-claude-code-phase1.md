# Phase 1: Subscription / Paywall — How It Works

**Reviewer:** claude-code (Opus 4.7)
**Date:** 2026-04-29
**Files reviewed:**
- `Peezy 4.0/MainInterface/Models/SubscriptionManager.swift`
- `Peezy 4.0/MainInterface/Models/SubscriptionAPIClient.swift`
- `Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift`
- `Peezy 4.0/MainInterface/Views/Paywall/PaywallValueView.swift`
- `Peezy 4.0/Assessment/AssessmentViews/Onboarding/CompletionFlowView.swift`
- `Peezy 4.0/MainInterface/Models/PeezyV1App.swift` (init/injection only)
- `Peezy 4.0/Menu/PeezySettingsView.swift` (subscription section + restore handling, lines ~330–445)

## 1. High-level summary

Subscription handling is centralized in a single `@MainActor` singleton (`SubscriptionManager`) that wraps StoreKit 2. The paywall is a two-screen flow inside the post-assessment `CompletionFlowView`: a soft "value" screen (`PaywallValueView`) followed by a hard "gate" screen (`PaywallGateView`) that exposes the actual pricing cards and purchase CTA. A second restore-only entry point lives in `PeezySettingsView`. There is no runtime gating elsewhere — the app does not block any feature or screen based on `isSubscribed`; the dismiss button on the paywall routes the user straight into the main app.

## 2. SubscriptionManager lifecycle

- **Instantiation:** Singleton via `SubscriptionManager.shared` (SubscriptionManager.swift:26). Declared as `@MainActor` (line 21) and conforms to `ObservableObject` with `@Published` properties (lines 48–52). It is touched eagerly in `PeezyV1App.init()` (PeezyV1App.swift:20: `_ = SubscriptionManager.shared`) and injected into the view hierarchy via `.environmentObject(SubscriptionManager.shared)` on the root `WindowGroup` (PeezyV1App.swift:27).
- **Product loading:** Triggered from the private initializer (SubscriptionManager.swift:108–115). The `init` spawns an unstructured `Task { await loadProducts(); await updateSubscriptionStatus() }`. `loadProducts()` (lines 123–140) calls `Product.products(for:)` on the two hardcoded IDs `peezy.plus.weekly` and `peezy.plus.annual` (enum at lines 30–33), sorts annual first, sets `isLoaded = true`, and on failure sets `purchaseError = .networkError`.
- **Purchase state tracked:** Five `@Published` properties — `products`, `subscriptionStatus`, `isPurchasing`, `purchaseError`, `isLoaded`. `subscriptionStatus` is an enum with cases `.notSubscribed`, `.trial`, `.subscribed`, `.expired`, `.revoked` (lines 56–69). Two computed views over it: `isSubscribed` (line 37) and `isTrialActive` (line 41).
- **Threading model:** Class is fully `@MainActor`, so all `@Published` mutations occur on the main actor. The transaction listener is the one exception — `listenForTransactions()` (lines 260–270) uses `Task.detached` and then hops back via `await self.updateSubscriptionStatus()` / `await self.syncToServer(...)`, both of which are main-actor calls.
- **Transaction listener lifecycle:** Stored in `private var transactionListener: Task<Void, Error>?` (line 104), started in `init` (line 109), cancelled in `deinit` (line 118). Because the manager is a process-lifetime singleton, the deinit will not fire in normal app use; the listener runs for the lifetime of the app. Each `Transaction.updates` event triggers `updateSubscriptionStatus()`, then `syncToServer(...)`, then `transaction.finish()`.

## 3. Paywall presentation

- **Where it appears:** Only inside `CompletionFlowView` (CompletionFlowView.swift:51), which is itself presented as a `.fullScreenCover` from `AssessmentFlowView` when `coordinator.isComplete == true` (per the file header comment, line 11).
- **Trigger:** A linear, advance-only stage machine (`Stage` enum, CompletionFlowView.swift:24–34). Order is `generating → ready → summary → paywall → paywallGate`. The paywall is reached only by progressing through the assessment-completion stages; it is not presented from a button outside the assessment, and there is no auto-gating elsewhere in the app. `advanceStage(to:)` (line 42) refuses to move backwards.
- **Conditions for automatic appearance:** None beyond completing the assessment. Paywall presentation is not conditional on `subscriptionManager.isSubscribed` — an already-subscribed user who completes the assessment will still see `PaywallValueView` and `PaywallGateView`. (Confirmed by inspection: no `isSubscribed` / `subscriptionStatus` check in CompletionFlowView.swift.)
- **What the user sees:**
  - **PaywallValueView** (PaywallValueView.swift): centered headline "Can you really put a price on peace of mind?", a 3-day free trial value-prop block, and a single CTA button labeled "Try it free" plus a `trialPriceText` line that reads e.g. "3-day free trial · Then $X/year". No purchase happens here; the CTA only advances the stage.
  - **PaywallGateView** (PaywallGateView.swift): a `ScrollView` over an `InteractiveBackground` containing an X dismiss button (top-right, lines 26–39), a hero block, a six-item feature checklist (lines 64–69), two side-by-side pricing cards (annual + weekly, with annual pre-selected and badged "BEST VALUE"), a primary CTA whose label is computed by `ctaLabel` (lines 150–167), tertiary "Redeem a code" / "Restore Purchases" links, the Apple-required subscription terms paragraph (lines 124–129), and Privacy Policy / Terms of Service `Link`s (lines 131–137).

## 4. Purchase flow

Path of a tap on the primary CTA in `PaywallGateView`:

1. CTA tap calls `purchaseSelected()` (PaywallGateView.swift:275).
2. `purchaseSelected()` resolves the selected `SubscriptionManager.ProductID` to a StoreKit `Product` via `subscriptionManager.product(for:)` (SubscriptionManager.swift:274), and bails silently if the product is nil.
3. Spawns a `Task` that calls `await subscriptionManager.purchase(product)` (SubscriptionManager.swift:144).
4. `purchase(_:)`:
   - Sets `isPurchasing = true`, clears `purchaseError` (lines 145–146).
   - Calls `try await product.purchase()` (line 149).
   - On `.success(.verified(let transaction))`: awaits `updateSubscriptionStatus()`, fires unstructured `Task { await syncToServer(transaction:) }`, calls `transaction.finish()`, sets `isPurchasing = false`, returns `.success` (lines 152–162).
   - On `.success(.unverified(_, error))`: sets `purchaseError = .verificationFailed`, returns `.failed(error)` (lines 164–171).
   - On `.userCancelled`: sets `purchaseError = .purchaseCancelled`, returns `.cancelled` (lines 173–176).
   - On `.pending`: sets `purchaseError = .purchasePending`, returns `.pending` (lines 178–181).
   - On thrown error: sets `purchaseError = .purchaseFailed(underlying:)`, returns `.failed(error)` (lines 187–191).
5. Back in `purchaseSelected()`, only `.success` is acted on — it calls `onDismiss()` (PaywallGateView.swift:280), which in `CompletionFlowView` is bound to `routeToMainApp()` (CompletionFlowView.swift:94–96, 124).
6. Non-success cases do nothing in the view layer beyond clearing `isPurchasing` via the published property change. The CTA label changes to "Processing..." while `isPurchasing` is true (PaywallGateView.swift:151–153).

States tracked during purchase: `isPurchasing` (drives the CTA label) and `purchaseError` (a `LocalizedError` enum at lines 82–100).

**Surfacing of failures:** Within the paywall view, `purchaseError` is **not bound to any UI** — there is no `.alert`, no inline error text, and no banner reading from `subscriptionManager.purchaseError`. The only user-visible signal of failure is that `onDismiss()` is not called (so the paywall stays open) and the CTA label flips back from "Processing..." to its idle string. Errors are only logged in `#if DEBUG` `print` statements (lines 136, 166, 203, 304).

## 5. Restore purchases flow

Two entry points:

1. **PaywallGateView** (PaywallGateView.swift:107–118): tertiary text button "Restore Purchases" inside the footer row. Tap spawns a `Task` that:
   - Calls `await subscriptionManager.restorePurchases()`.
   - Immediately reads `subscriptionManager.isSubscribed` and, if true, calls `onDismiss()`.
   - There is no UI feedback on the paywall itself for a "no purchases to restore" outcome.

2. **PeezySettingsView** (PeezySettingsView.swift:374–385): a settings row "Restore purchases". Tap spawns a `Task` that:
   - Calls `await subscriptionManager.restorePurchases()`.
   - Then sets a local `restoreMessage` based on whether `subscriptionManager.purchaseError == nil` ("Purchases restored successfully." vs "Unable to restore purchases. Please try again.").
   - `restoreMessage` drives a `.alert` bound at lines 205–212.

Underlying call: `SubscriptionManager.restorePurchases()` (SubscriptionManager.swift:196–206) calls `try await AppStore.sync()` then `await updateSubscriptionStatus()`. On thrown error it sets `purchaseError = .purchaseFailed(underlying:)`. Note that the settings handler's success heuristic — `purchaseError == nil` — will report "successfully" even when the restore found no purchases at all (because no error was thrown in that case).

## 6. Error handling

- **Error types defined:** `PurchaseError` enum (SubscriptionManager.swift:82–100): `.productNotFound`, `.purchaseFailed(underlying:)`, `.purchaseCancelled`, `.purchasePending`, `.verificationFailed`, `.networkError`. All conform to `LocalizedError`. `.purchaseCancelled` returns `nil` for `errorDescription`.
- **Where caught:**
  - `loadProducts()` catches and sets `.networkError`.
  - `purchase(_:)` translates StoreKit results/throws into `PurchaseError` cases.
  - `restorePurchases()` catches and sets `.purchaseFailed(underlying:)`.
  - `syncToServer(...)` catches and only `print`s in DEBUG (line 304); errors are intentionally swallowed (the `// Fire-and-forget` comment at line 157 confirms this is by design).
- **Surfacing to user:**
  - **PaywallGateView:** none. `purchaseError` is set on the manager but never read by the view's body.
  - **PeezySettingsView restore row:** an alert ("Purchases restored successfully." / "Unable to restore purchases. Please try again."). The alert text does not include `purchaseError.errorDescription`.
- **Specific scenarios:**
  - **Network failure during product load:** `purchaseError = .networkError`. Pricing cards in `PaywallGateView` fall back to `"—"` for `displayPrice` (line 191) and the weekly CTA label falls back to `"Subscribe Weekly"` (line 165).
  - **Purchase cancellation:** silently absorbed; CTA returns to idle.
  - **Payment declined / generic StoreKit throw:** `.purchaseFailed(underlying:)` set, no UI surface in paywall.
  - **Verification failed (unverified transaction):** `.verificationFailed` set, no UI surface; the unverified transaction is **not** finished (line 164–171 do not call `transaction.finish()`).
  - **Pending (e.g. Ask to Buy):** `.purchasePending` set, no UI surface.

## 7. State management edge cases

- **App launch with active subscription:** `SubscriptionManager.init` runs `loadProducts()` then `updateSubscriptionStatus()` (lines 111–114). `updateSubscriptionStatus()` (lines 210–256) iterates `Transaction.currentEntitlements`, breaks on the first verified, non-revoked, non-expired auto-renewable transaction, and assigns either `.trial` or `.subscribed` based on `transaction.offerType == .introductory`. State is reflected in `PeezySettingsView`'s subscription section.
- **Sign-in / sign-out:** `SubscriptionManager` does not observe Firebase auth state. It is a process-singleton; subscription status persists across sign-out/sign-in within the same app session. `syncToServer` reads `Auth.auth().currentUser?.uid` at call time (line 285) and silently no-ops if there is no user. There is no logic that clears or re-fetches subscription state on auth changes.
- **Subscription expires:** Handled in two places. (1) `Transaction.updates` listener will fire on Apple-driven changes and call `updateSubscriptionStatus()`. (2) The `if !foundActive` branch at lines 245–254 transitions a previously-`.trial`/`.subscribed` state to `.expired` only when `updateSubscriptionStatus()` is re-run and finds no active entitlements.
- **Renewal failure / billing retry:** Apple emits a `Transaction.updates` event when billing retry resolves; the listener (lines 260–270) handles this generically by re-running `updateSubscriptionStatus()`. There is no explicit handling of grace period or "in billing retry" status — the manager either sees the entitlement (active) or doesn't (transitions to `.expired`).
- **Revocation (refund):** `updateSubscriptionStatus()` checks `transaction.revocationDate != nil` before checking expiration (lines 217–221) and assigns `.revoked`. The `if !foundActive` branch explicitly preserves `.revoked` (line 250–251) rather than overwriting to `.notSubscribed`.
- **Already-subscribed user re-enters paywall:** As noted in §3, the assessment-completion flow does not skip the paywall stages for subscribed users. A subscribed user could tap a pricing card and trigger `product.purchase()` again; StoreKit would handle this server-side.

## 8. Apple documentation status (as of April 2026)

Verified via web search on 2026-04-29:

- **3.1.2 disclosure requirements (verified):** Users must see full pricing, renewal terms, and cancellation info before paying; subscription must provide ongoing value; minimum 7-day period; no tricking users into multiple variations of the same product. The existing `PaywallGateView` displays per-plan prices, the standard auto-renew disclosure paragraph (lines 124–129), and Privacy/Terms links — these align with the disclosure requirements.
- **3.1.1 in-app purchase (not specifically re-verified this session):** Could not confirm any 2025–2026 changes that affect this flow beyond what 3.1.2 covers. No external-payment links or alternative billing flows exist in the reviewed code, so the standard IAP path is in use.
- **StoreKit 2 best practices (partially verified via existing knowledge, not re-fetched):** Code uses `Product.products(for:)`, `product.purchase()`, `Transaction.currentEntitlements`, `Transaction.updates`, `AppStore.sync()`, and `transaction.finish()` after state update — these are the canonical StoreKit 2 patterns Apple has documented since iOS 15. The unverified transaction at lines 164–171 is intentionally not finished, which matches Apple's guidance.
- **Paywall UI requirements 2025–2026 (verified):** Apple's checklist explicitly expects a Restore option on any paywall (present here, line 107). Trial details must not be hidden; price must be shown clearly. Free-trial information must be hidden from users who are *not* eligible for another intro offer — see §9 observation about `isEligibleForTrial`.
- **2025–2026 rejection patterns (verified):** Apple began rejecting "toggle paywalls" (the free-trial toggle pattern) in mid-January 2026 under 3.1.2 as confusing. The paywall here is a side-by-side plan-card pattern with a fixed CTA, not a toggle paywall, so this specific 2026 rejection vector does not apply.
- **Restore Purchases reachability (verified):** Required to be reachable on the paywall and from a non-paywall location. Both are present (PaywallGateView.swift:107, PeezySettingsView.swift:374).

What I could not independently verify in this session: the exact current wording Apple expects in the auto-renew disclosure paragraph; whether the privacy.html / terms.html pages on `peezy-1ecrdl.web.app` are reachable, current, and contain the EULA / subscription terms that 3.1.2(c) requires (the URLs are referenced at PaywallGateView.swift:132 and :135 but the linked pages were not fetched).

## 9. Specific observations

- **SubscriptionManager.swift:30–33** — Product IDs are a hardcoded enum (`peezy.plus.weekly`, `peezy.plus.annual`). Any product change requires a code change.
- **SubscriptionManager.swift:108–115** — Init spawns an unstructured `Task` to load products. There is no public `await`able "ready" signal; views read `isLoaded` to detect product availability.
- **SubscriptionManager.swift:228** — Trial detection uses `transaction.offerType == .introductory`. This treats only Apple's introductory offer type as a "trial"; promo offers and non-paid offer types are classified under `.subscribed`.
- **SubscriptionManager.swift:245–255** — Expiration transition relies on a previously-set in-memory state. On a fresh app launch where `subscriptionStatus` starts at `.notSubscribed` and no active entitlement is found, the user lands on `.notSubscribed` (not `.expired`), regardless of past subscription history.
- **SubscriptionManager.swift:260–270** — Transaction listener uses `Task.detached` and captures `self` strongly without `[weak self]`. Because this is a process-lifetime singleton, this is intentional but should be noted.
- **SubscriptionManager.swift:284–307** — `syncToServer` posts a JSON payload to `<firebaseFunctionURL>/validateSubscription`. Failure is logged in DEBUG only. The payload includes `originalTransactionId`, `transactionId`, `purchaseDate`, `expirationDate`, `environment`, `isUpgraded`.
- **SubscriptionAPIClient.swift:14–32** — `validateReceipt` posts JSON without an Authorization header or Firebase ID token; the only auth signal sent is the `userId` field in the body.
- **PaywallGateView.swift:154–162 and 196–206** — The CTA label and the annual pricing card's subtext both branch on `intro.paymentMode == .freeTrial` to show "Start N-Day Free Trial" / "N-day free trial". Neither location calls `subscriptionManager.isEligibleForTrial(product:)` (which exists at SubscriptionManager.swift:278) before showing the trial copy. Result: the paywall advertises the free trial to all users, including those who already consumed it. Per the 2026 paywall guidance verified in §8, free-trial information must be hidden from ineligible users.
- **PaywallGateView.swift:107–118** — Restore tap path. After `await subscriptionManager.restorePurchases()`, the code reads `subscriptionManager.isSubscribed` synchronously on the next line. Both calls are main-actor isolated, so the read sees the post-update value. There is no user-facing message inside the paywall when restore finds no purchases.
- **PaywallGateView.swift:151–153** — When `isPurchasing` is true, the CTA label changes to "Processing..." but the `PeezyAssessmentButton` is not declared `disabled`. The button's internal disabled handling was not inspected.
- **PaywallGateView.swift:96–98** — Redeem-code button uses `UIApplication.shared.connectedScenes.first as? UIWindowScene` to find the scene for `AppStore.presentOfferCodeRedeemSheet(in:)`. There is no fallback if `connectedScenes` is empty or the cast fails.
- **PaywallGateView.swift:132 and 135** — Privacy Policy and Terms of Service are remote URLs (`https://peezy-1ecrdl.web.app/privacy.html` and `.../terms.html`). The `git status` at session start shows uncommitted edits to `public/privacy.html` and a new `public/support.html`; the deployed pages backing the paywall links were not fetched in this review.
- **CompletionFlowView.swift:87–98** — Paywall is presented unconditionally in the post-assessment flow regardless of `subscriptionManager.isSubscribed`. There is no skip path for already-subscribed users.
- **CompletionFlowView.swift:124–139** — `routeToMainApp()` posts `.assessmentCompleted` and sets `coordinator.isComplete = false` after a 0.1s `DispatchQueue.main.asyncAfter`, with a 5.0s failsafe that re-posts and re-clears. This is the dismiss path for both "purchase succeeded" and "user tapped X".
- **PeezySettingsView.swift:339, 342** — Subscription status row uses `.foregroundColor(...)` (the older API) rather than `.foregroundStyle(...)`. Other surfaces in the paywall use `.foregroundStyle`.
- **PeezySettingsView.swift:374–385** — Restore success heuristic is `purchaseError == nil` after the call, which is set to nil at the start of `purchase(...)` but is **not** cleared at the start of `restorePurchases()` (SubscriptionManager.swift:196). A stale `purchaseError` from a prior failed purchase could cause the settings restore alert to incorrectly say "Unable to restore purchases" even when `AppStore.sync()` succeeded.
- **SubscriptionManager.swift:117–119** — `deinit` cancels the listener, but since this is a `static let shared` singleton, deinit will not run during normal app lifetime.

## 10. Things you could not determine

- Whether `PeezyAssessmentButton` becomes interactively disabled while `isPurchasing == true` — the type was not opened in this review.
- Whether `InteractiveBackground` introduces any state coupling (e.g., timers, animations) relevant to paywall presentation.
- Whether the deployed `privacy.html` and `terms.html` pages contain the EULA / subscription terms required by 3.1.2(c). The local working tree shows uncommitted modifications to `public/privacy.html` and a `public/privacy.html.bak`, but the live pages were not fetched.
- Whether Firebase Cloud Function `validateSubscription` enforces any auth check on the userId field or trusts the client — only the client side (`SubscriptionAPIClient`) was reviewed.
- Whether `PeezyConfig.firebaseFunctionURL` differs by environment (debug vs. release); the config file was not opened.
- Apple's exact current wording requirements for the on-paywall auto-renew disclosure paragraph were not byte-compared against the string at PaywallGateView.swift:124.
- Whether StoreKit configuration in the Xcode project (StoreKit configuration file, App Store Connect product setup) matches the two product IDs and intro-offer assumptions in code — only Swift sources were reviewed.
