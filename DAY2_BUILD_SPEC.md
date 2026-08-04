# Day 2 Build Spec — Pricing, Gate, Demolition, Copy

Inputs: audit_reports/AUDIT_A_REPORT.md through AUDIT_D_REPORT.md (evidence),
PEEZY_LAUNCH_PLAN_AUG2026.md (locked decisions), PEEZY_CUBE_SHEET.md (Day 4
reference only). This spec supersedes MOVEPASS_PRICING_SPEC.md — its phases
are incorporated here with the §7 launch-plan deltas already applied.

## Session Protocol (every phase)
- One phase per fresh session. Read this spec's phase + the audit sections it
  cites BEFORE any edit. The audit tables are the authoritative inventories —
  do not re-derive them, do not skip entries.
- After the phase: build must succeed
  (`xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build`
  for iOS phases; `node --check` on every touched JS file for functions phases).
- Commit per phase: `git add -A && git commit -m "day2: phase N — <name>"`.
- Review `git diff --stat` before committing — only files this phase names.
- Never hardcode prices or model strings. Never compare raw product-ID strings.
- Copy tone rule for every rewritten string (locked brand DNA): the app equips
  and informs; it never promises to perform, contact, reach out, arrange,
  scout, or handle. No "we'll <verb> for you," no follow-up windows, no fixed
  dollar claims. Informed choice: state what the user does next and what
  Peezy prepared for them.

## Reference Model — Non-Renewing Subscriptions (StoreKit 2, authoritative)
- The new product's `productType` is `.nonRenewable`. Guards on `.autoRenewable`
  silently skip it.
- `transaction.expirationDate` is nil for non-renewing products. The app
  computes expiry: `purchaseDate + 6 months` via `Calendar.date(byAdding:)`.
- Finished non-renewing transactions are EXCLUDED from
  `Transaction.currentEntitlements`. Entitlement lookup uses
  `Transaction.latest(for:)` (returns the most recent transaction even after
  `finish()`), plus the computed expiry.
- `product.subscription` is nil for non-renewing products — any path through
  `introductoryOffer` is dead for the Move Pass.
- Apple requires developer-provided cross-device availability for non-renewing
  subscriptions: the existing validateSubscription → Firestore sync satisfies
  this; the client sends the computed expirationDate (Apple's is nil).

---

## Phase 1 — SubscriptionManager: Move Pass entitlement
READ FIRST: `Peezy 4.0/MainInterface/Models/SubscriptionManager.swift` (whole
file), AUDIT_D evidence rows for SubscriptionManager (lines 30-32, 227-229).

1. `ProductID` enum becomes:
```swift
    enum ProductID: String, CaseIterable {
        /// The only product sold. Non-renewing subscription, 6-month access.
        case move = "peezy.plus.move"
        /// Legacy — no longer sold. Kept permanently so existing subscribers
        /// retain access (grandfathered). Do not remove.
        case weekly = "peezy.plus.weekly"
        case annual = "peezy.plus.annual"
    }

    /// Client-computed access term: StoreKit does not manage non-renewing duration.
    static let movePassTermMonths = 6
```
2. `loadProducts()` sorts the Move Pass first:
   `products = storeProducts.sorted { p1, _ in p1.id == ProductID.move.rawValue }`
3. `updateSubscriptionStatus()` becomes a three-step check, in order:
   - Step 1 (existing logic, unchanged semantics): `Transaction.currentEntitlements`
     for legacy auto-renewables — revocation, expiry, trial detection as today.
   - Step 2 (new): if no legacy entitlement, `Transaction.latest(for:
     ProductID.move.rawValue)` — verified, non-revoked, computed expiry
     (`purchaseDate + movePassTermMonths` months). Future → `.subscribed(
     productId:, expirationDate: computedExpiry)`; past → `.expired`.
   - Step 3 (new, gift codes): if still nothing, read
     `users/{uid}.subscription` from Firestore; if `source == "giftCode"` and
     `expirationDate` is in the future → `.subscribed(productId:
     ProductID.move.rawValue, expirationDate:)`. Read-only; the write side is
     Day 4's redeemGiftCode function. Wrap in do/catch — a Firestore failure
     must degrade to `.notSubscribed`, never crash.
   - Fallback block at the end: preserve today's semantics (was
     trial/subscribed → `.expired`; revoked stays; else `.notSubscribed`).
4. `syncToServer(transaction:)` — expirationDate payload: use Apple's if
   present; else if productID == move, the computed expiry; else empty string.
5. FALLBACK: if `Transaction.latest(for:)` misbehaves in the simulator, use
   `Transaction.all` filtered by productID, newest purchaseDate. Never leave
   the transaction unfinished.

DO NOT TOUCH: paywall views, Settings, functions/, project.pbxproj.
VERIFY: build succeeds; diff confined to SubscriptionManager.swift.

## Phase 2 — Configuration.storekit
READ FIRST: `Configuration.storekit` (whole file).
Replace the empty `"nonRenewingSubscriptions" : []` with one product:
productID `peezy.plus.move`, referenceName/displayName "Peezy Move Pass",
displayPrice "49.99", description "6 months of full Peezy access. One payment.
No renewal.", type "NonRenewingSubscription", familyShareable false, a fresh
internalID. Leave the legacy subscription group and both recurring products
untouched (grandfather testing needs them).
VERIFY: build succeeds; the Move Pass loads in the simulator paywall.

## Phase 3 — PaywallGateView: single price, founding framing
READ FIRST: `Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift`
(whole file), AUDIT_D "iOS paywall copy" row.

1. Delete the plan selector, `selectedPlan` state, `planCard(for:)`,
   `subtitleText(for:)`, all trial CTA branches, and the feature bullets that
   claim "most tasks done for you" and "Priority support" (AUDIT_D lines 58,
   68, 71, 78).
2. Header block:
   - Eyebrow: "PEEZY MOVE PASS"
   - Headline: "One price.\nYour whole move."
   - Sub: "Six months of Peezy doing the work.\nNo subscription. Nothing to
     cancel.\nIt just ends when your move does."
3. Single price card: `product(for: .move)?.displayPrice ?? "—"` large;
   "Founding price — locked for early users" below; "One-time payment ·
   6 months of access" small. Match the app's existing card/glass style.
   NEVER render a fabricated reference price (no "$99", no strikethrough).
4. Primary CTA purchases the Move Pass; on `.success`, dismiss.
5. "Redeem a code" no longer calls Apple's offer-code sheet (it cannot serve
   non-renewing products). It presents a new minimal `GiftCodeRedeemSheet`
   (same file or new file in the Paywall folder): one text field, one submit
   button calling Functions callable `redeemGiftCode` with `{ code }`, loading
   state, and an error state that surfaces the server message. The server
   function ships Day 4 — until then the sheet errors cleanly. On success,
   call `updateSubscriptionStatus()` and dismiss.
6. Replace the auto-renew disclosure paragraph with: "One-time payment charged
   to your Apple ID at confirmation of purchase. Includes 6 months of Peezy
   Move Pass access. This is not an auto-renewing subscription — access ends
   automatically and nothing renews." Keep Restore Purchases and both legal
   links exactly where they are.
VERIFY: build; `grep -n '\$' <file>` shows no price literals; diff confined
to the Paywall folder.

## Phase 4 — PaywallValueView: value screen
READ FIRST: `Peezy 4.0/MainInterface/Views/Paywall/PaywallValueView.swift`.
Delete `trialPriceText` and every `introductoryOffer`/trial reference. New copy:
- Eyebrow "PEEZY MOVE PASS"; headline "What's six months of\nsomeone in your
  corner\nworth?"
- Body: "The research done for you. Your home\nscanned. The right truck the
  first time.\nA packing plan built around your date."
- Anchor: "Renting one wrong-sized truck costs more\nthan all of it. Peezy
  works out to less\nthan the change in your cupholder."
- CTA "See my price" → onContinue; caption "One-time payment · Nothing renews".
No dollar figures in string literals. No tasks-window/trial framing anywhere.
VERIFY: build; diff confined to this file.

## Phase 5 — PeezySettingsView: Move Pass status
READ FIRST: `Peezy 4.0/Menu/PeezySettingsView.swift` lines ~190-450 (subscription
section + label computed properties), AUDIT_D Settings rows (202, 350, 369-370,
397, 414-440).
1. Status label: `.subscribed` with the Move Pass product → "Peezy Move Pass";
   legacy products keep "Peezy Premium".
2. Detail label: Move Pass → "Access through {medium-formatted expiry}". Fix
   the live mislabel while here: the non-annual legacy plan is **Weekly**, not
   "Monthly" (no monthly product has ever existed). Kill "renews"/"resubscribe"
   wording for the Move Pass path.
3. Hide the "Manage Subscription" row when the active product is the Move Pass
   (nothing recurring exists to manage; Apple's page would show nothing).
   Keep Restore Purchases for everyone.
4. Account-deletion copy (line ~202): remove the instruction to cancel an
   active subscription first when the entitlement is a Move Pass; reword to
   "Your Move Pass access ends with your account."
VERIFY: build; diff confined to this file.

## Phase 6 — First-gated-tap gate
READ FIRST: AUDIT_B "Day 2 removal and gate" (report lines 103-113) — it is
the exact call-site map. Then each cited file in full.

1. `PaywallPolicy` rewrite: the free tier is the task LIST only. Every task
   open, scanner entry, packing surface, supplies surface, and (Day 3) research
   surface is gated. Express as a single `requiresMovePass(for:)` that returns
   true for all task substance; delete the current free-list of scanner/packing.
2. Central gate: one subscription check where task routing begins
   (`TasksStore` open dispatch → `TaskFlowRouter`) — unsubscribed → present
   PaywallValueView → PaywallGateView instead of the task. Also gate the
   non-task entry points AUDIT_B names: Settings scanner entry, FindMoversFlow
   scanner entry, SuppliesKitView. Remove the now-redundant per-action gates
   at the FlowEngine/FindMovers/FindCleaners/SuppliesKit call sites the audit
   lists, so gating logic lives in exactly one place.
3. Remove the post-assessment paywall from `CompletionFlowView` (lines 50-60,
   91-115): assessment completion flows straight to the list. The list IS the
   free demo; the first gated tap is the conversion moment.
4. Free-list presentation fix (AUDIT_B line 111): rows render `title` +
   timing/due date; stop rendering `desc` as the subtitle. `desc` and
   `whyNeeded` move behind the gate (Day 3's universal renderer consumes them).
VERIFY: build; manual simulator pass: fresh account → assessment → list
visible → tap any task → paywall; purchase in sandbox → task opens.

## Phase 7 — Functions demolition (server side)
READ FIRST: AUDIT_B evidence rows 25-32 and "Day 2 removal and gate";
AUDIT_C `peezyRespond` security row. Then each cited functions file.

1. Remove the three `NOTIFICATION_WEBHOOK_URL` POST blocks and their adjacent
   `notifyAdmin` invocations (`functions/index.js:413-446, 472-503, 546-574`
   per audit). The handlers still write their Firestore records and return
   success — the writes become the audit trail, nothing pages a human.
2. Remove: packageInventory's notify call (`functions/packageInventory.js:
   180-221`), the mover/supplies direct-SMS branch (`functions/
   getWorkflowQualifying.js:281-365`), and the health-check SMS
   (`functions/index.js:664-701` — delete the scheduled function entirely).
3. Remove the `peezyRespond` export and route (`functions/index.js:91-203`)
   — it is application-dead (AUDIT_C) and an unauthenticated UID-read hole.
   Leave `peezyBrain.js`/`systemPrompt.js`/`knowledgeBase.js` files in place
   untouched: Day 3's rebuild replaces them; with no export they are inert.
   (Adam separately deletes the deployed instance from the console.)
4. Support auto-ack (`functions/index.js:32`): reword to "Thanks for reaching
   out — Peezy will answer here. For account or billing issues, email
   support@peezymove.com." No response-time promise. (Day 3 wires the AI
   responder to this surface.)
5. Fallback briefing string (`functions/index.js:371`): reword per copy tone
   rule — guidance, not "take care of it for you."
VERIFY: `node --check` on every touched file; `firebase deploy --only
functions` from Adam after review; grep functions/ for NOTIFICATION_WEBHOOK_URL
returns nothing.

## Phase 8 — Client self-serve terminals
READ FIRST: AUDIT_B rows 25-27, 32, 39 and report lines 109-113; AUDIT_D
"in-app execution promises" row. Then each cited file.

1. Retire the admin-pushed routes: remove `quote_selection` and `admin_memo`
   from `TaskFlowRouter` (76-81) and delete/orphan their renderers
   (QuoteSelectionFlow, AdminMemoFlow) — no producer exists (AUDIT_B Q4 ruling:
   retire).
2. Human-ending terminals → equipped terminals: everywhere a flow ends by
   promising contact/follow-up (FlowEngineView 348-385, 508-547;
   PeezyHomeViewModel pending states 451-470; TaskGrouping 28-35;
   TaskRowHeader 81-88), the terminal state becomes: "You're set. Here's
   everything you need." + the flow's collected info presented back as the
   user's action sheet (numbers to call, what to say, what to have ready —
   from data already in the flow). Remove "pending Peezy" statuses from
   grouping/labels: a submitted flow is COMPLETE the moment the user has
   their marching orders.
3. BoxReturnView (196-250): remove the concierge-pickup path and confirmation;
   the ending is donation/recycling guidance (content from the existing flow's
   own options).
4. ProviderActionCard fallback (273): "We'll take it from here" → "Here's how
   to reach them directly" with the resolver's cited info; no handoff.
5. InventoryLockedView (50): reword the locked-state promise per tone rule.
6. Non-terminal failures (AUDIT_B line 113 list, nine files): a failed
   submission write shows a retry state; it never advances or completes the
   task as if it succeeded.
7. iOS copy kills from AUDIT_D's table: ExplainerView 28-29,
   AssessmentIntroView 19/55, Addresschangeintro 11, HandleHomeInsuranceFlow
   331 (drop the fixed $15-30/month claim; guidance without prices). Apply
   the tone rule; keep the strings' surfaces.
VERIFY: build; simulator pass of two flows end-to-end (utilities transfer,
box return) confirming no "we'll contact/expect word" language renders.

## Phase 9 — Seed-data copy sweep + reseed
READ FIRST: AUDIT_D consolidated table rows for `functions/taskCatalogData.json`,
`functions/flowDefinitionsData.json`, `functions/ispPlansData.json`.

1. `taskCatalogData.json`: apply every KILL/REWRITE row (71, 74, 152, 473,
   917-1047 series). Rewrite formula for descriptions: [what this task
   protects or saves] + [what the user does] — no "we'll," no fixed dollars,
   no accountability claims. Example, line 1011's "One tap and we'll handle
   the rest." → "Know before move day whether it all fits — and what a unit
   near you actually costs."
2. `flowDefinitionsData.json`: every "We'll contact/reach out/reserve/scout …
   Expect word back within 24–48 hours" summary (AUDIT_D rows 126-144) becomes
   an equipped ending: "Your [utilities/vet/pharmacy/building/records] list is
   ready — here's each contact and exactly what to say." Question steps that
   offered execution ("Want us to find you the right unit?") become research
   offers ("Want the current options near your new place, with sources?").
   Two worked examples, apply the pattern to all:
   - 373: "We'll contact each provider to transfer service…" → "Your transfer
     list is ready: each provider, their number, and the script for a
     no-overlap switch."
   - 801: "We'll contact your current building and reserve {rowsList}…" →
     "Here's the reservation script for your building — what to book
     ({rowsList}) and the questions that prevent move-day surprises."
3. `ispPlansData.json` + `SetupInternetFlow`: remove the curated plan
   comparison from the user path (the Xfinity record's own text says the offer
   ended July 27, 2026 — stale prices are live right now). The internet task
   ships as guidance (what to check, when to order, self-install advice
   without fixed savings) until Day 3 research and the Allconnect integration
   take over. Keep the flow's data collection; kill the plan cards.
4. Reseed: after JSON edits build clean, run the seeders against production
   (`node seedTaskCatalog.js`, and the flow/ISP seeders per their headers).
   These are destructive by design; existing per-user task docs are copies and
   are unaffected. Verify one reseeded doc in the console before proceeding.
VERIFY: `node --check` all touched; JSON parses (`node -e "require('./functions/
taskCatalogData.json')"` etc.); reseed confirmed.

## Phase 10 — Verification sweep (launch-gate greps)
Run and record output in SESSION_NOTES:
- `grep -rn "NOTIFICATION_WEBHOOK_URL\|notifyAdmin" functions/*.js` → only
  inert un-exported legacy files, no live call sites.
- `grep -rni "pinky\|money back\|money-back\|concierge" "Peezy 4.0" functions/*.json functions/index.js` → zero user-visible hits.
- `grep -rni "trial\|weekly\|annual\|renew" "Peezy 4.0/MainInterface/Views/Paywall" "Peezy 4.0/Menu/PeezySettingsView.swift"` → only grandfathered-path labels.
- `grep -rn '\$[0-9]' --include='*.swift' "Peezy 4.0"` → only the WORKING
  exceptions AUDIT_D cleared (SellItemsFlow value bands, MoveCheckIn validation).
- `grep -rn "We'll\|we'll" functions/flowDefinitionsData.json functions/taskCatalogData.json` → zero execution promises (equipped phrasing only).
- Full build + the Phase 6 simulator pass repeated on a clean install.

## Explicitly Deferred (do not touch in Day 2 sessions)
Research pipeline, `researchTask`, brief schema, appConfig/ai, task-context/
support AI chat, catalog research/vendor-question fields, universal detail
renderer (Day 3). Scanner fixes, truck size, cube-sheet integration,
redeemGiftCode server function + mint script (Day 4). App Store listing,
screenshots, IAP creation (Friday). peezy-site copy (Track 1, this week,
separate repo).
