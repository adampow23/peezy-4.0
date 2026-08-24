# Peezy Launch Plan — August 2026 (Subscription-First)

**Target: App Store submission Friday, August 7, 2026.**
This document supersedes the launch scope of peezy-complete-launch-plan.md. Where they conflict, this wins.

---

## 1. Locked Decisions (the constitution of this launch)

These were decided explicitly and are not open for reinterpretation during the build:

| # | Decision | Ruling |
|---|----------|--------|
| 1 | Business model | Subscription-only at launch. No vendor backend, no concierge, no marketplace. |
| 2 | Product | Single SKU: **Peezy Move Pass** — non-renewing subscription, $49.99, 6 months of access, founding-price framing. No fabricated reference prices, ever. |
| 3 | Vendor task endings | Fully self-serve. Nothing fires to Adam or n8n. All vendor-workflow webhook endings are removed. |
| 4 | Pinky Promise | Retired until the vendor accountability layer actually exists. All copy referencing it (app, App Store, website) comes out. It returns later as a launch event of its own. |
| 5 | Core paid feature | **Live AI research per task**, generated on demand, web-search-capable. Hard rule: **never return an uncited URL.** Results cached per user per task. |
| 6 | Scanner | All four outputs are launch-gating: move cost estimate, truck size, packing plan, supplies estimate. Ships complete or not at all. |
| 7 | Free tier | **List-only from minute one.** Assessment is free, the personalized task list is free to view. Paywall triggers on the first tap of anything gated. The old 3-completed-tasks trigger is dead. |
| 8 | Realtor gift codes | In Friday scope. Custom Firestore mechanism (Apple offer codes do not exist for non-renewing products). |
| 9 | Post-launch revenue | ISP affiliate live within ~2 weeks of launch (Allconnect primary). Ads flywheel funded by subscription revenue, gated on CAC < subscription price. Features added one at a time, ranked by revenue potential × user value. |
| 10 | Operating principle | The app runs on autopilot. The only ongoing work is code. Every design decision is single-sided: what serves the user. |

---

## 2. The Product at Launch

### 2.1 Free tier (the demo)
The assessment and the personalized task list. That's it. The list is the proof — it shows the user Peezy already understands their specific move. Every task is visible (title, timing, why it matters at a glance). Tapping into any task's substance hits the paywall.

The conversion path: download → assessment → list revealed ("here's your move, fully mapped") → first gated tap → value screen → Move Pass price. One moment of conversion, placed at peak investment.

### 2.2 Paid tier (Move Pass)
Everything the app *does*: AI research on every task, all guided flows, the room scanner and all four of its outputs, the packing plan, the supplies estimate.

### 2.3 Universal task anatomy (proposed — edit before Day 3 build)
Every task in the catalog renders in one format:

1. **The what & why** — one or two sentences. Free-visible? No — gated with everything else; the free list shows title + timing only.
2. **Pointers** — the expert spine. Short, punchy, from nine years in the industry, stored in the task catalog (Firestore, config-driven — editable without releases).
3. **"Research this for me"** — the core feature. Generates a situational brief for *their* move (see §3).
4. **Mini-assessment (vendor-type tasks only)** — 2-4 preference questions ("what matters most: price, speed, care with fragile items?") asked before research runs, so the brief is shaped by their priorities. Output for vendor tasks always includes: the right questions to ask companies, the red flags to watch for, and (where web research applies) real local options with cited links.
5. **Complete / Snooze / Chat** — existing simple-button interaction, unchanged.

Tasks that currently end in an n8n webhook instead end at a clear "you're equipped — here's your action" state.

---

## 3. The Research Pipeline (core feature — deepest verification, no corners)

### 3.1 Architecture
```
Client tap → Cloud Function: researchTask(userId, taskId)
  → Assemble context: assessment answers, addresses, move date,
    inventory data (if scanned), task definition, mini-assessment answers
  → Claude API call with web search enabled
  → Structured brief returned (sections defined per task type)
  → CITATION GUARD: post-process pass. Any URL not present in an
    actual search/fetch result is stripped. A brief with a stripped
    load-bearing link is regenerated, not shipped with a hole.
  → Cache to Firestore: userTasks/{uid}/{taskId}/research
  → Client renders (typewriter, existing patterns)
```

### 3.2 Rules
- **Cache-first.** Generate once per user per task; revisits are instant and free. Regenerate button allowed (cost per generation is cents; total per user across a full move is low single-digit dollars against $49.99).
- **Model string lives in Firestore config, never hardcoded** (the retired-model-string incident broke production silently — never again).
- **Web search scope per task type is defined in the task catalog**, not guessed at runtime: utilities/ISP/local-services tasks get web research; questions-and-red-flags tasks (book movers) run on reasoning over context.
- **Server-side iteration forever.** Prompt quality, brief structure, and content depth improve in Cloud Functions with zero App Store releases. The Friday binary ships the surface and a working v1 brain; the brain gets smarter daily.

### 3.3 Quality gate for launch
The top 10 highest-frequency task types must each produce a brief that Adam — nine years in the industry — would sign his name to. That review is a Thursday human gate, not an automated check.

---

## 4. Gift Code System (realtor channel)

Apple offer codes don't exist for non-renewing subscriptions, so this is custom:

- `giftCodes/{code}` collection: `{ status, batchId, issuedTo, redeemedBy, redeemedAt, termMonths: 6 }`
- Redemption: Cloud Function `redeemGiftCode(code)` — validates, marks redeemed, writes entitlement to `users/{uid}.subscription` with `source: "giftCode"` and `expirationDate: redemption + 6 months`. Critical write first, cleanup after (established doctrine).
- Client: `SubscriptionManager` entitlement check becomes StoreKit-active **OR** Firestore-gift-active. (Small delta to the Move Pass spec's Phase 1 — noted in §7.)
- "Redeem a code" on the paywall points at a code-entry sheet (the Apple redeem sheet is dead weight for non-renewing — replace it).
- Code generation: a simple admin script Adam runs to mint a batch per realtor. No UI needed at launch.
- **Compliance posture:** codes are promotional/partner access granted by the developer — a comped entitlement, not an alternative payment path inside the app. Nothing in-app references buying codes. Realtor transactions happen entirely outside the app, B2B. Flag this framing in App Review notes proactively.

---

## 5. The Five-Day Build

Audit and fix stay separate sessions. Writer/validator split on every phase. Bounded retry: 2 attempts, then human review. Fresh Claude Code context per phase.

### Day 1 — Monday (today): Read-only audits. Zero write access.
- **Audit A — Scanner pipeline, end to end.** Scan → upload → inventory → each of the four outputs. What actually works today, on a real device, with a real room? Evidence, not memory.
- **Audit B — Task catalog + n8n touchpoints.** Every task that ends in a webhook, every workflow referencing concierge handling. Full inventory of what Day 2 removes.
- **Audit C — Research remnants.** What survives of peezyBrain.js, the chat client surface, and the provider-directory resolver after the April strip? Resurrect-vs-rebuild swings Day 3 by hours.
- **Audit D — Copy inventory.** Every instance of Pinky Promise, money-back, concierge, "we'll handle it," trial language, weekly pricing — app, App Store listing, website.
- Output: four audit reports feeding Days 2-4 specs. Cross-reference git log on every claim.

### Day 2 — Tuesday: Pricing + gate + removal.
- Run the Move Pass pricing build (spec exists) with the §7 deltas applied.
- New gate logic: first-gated-tap trigger. List renders free; every gated surface routes to PaywallValueView.
- Remove all n8n workflow endings per Audit B; replace with self-serve completion states.
- Copy retirement per Audit D (in-app strings this day; App Store listing text drafted for Friday).

### Day 3 — Wednesday: The core feature. (Highest-risk day.)
- `researchTask` Cloud Function: context assembly, web search, citation guard, caching.
- Universal task format on the client: pointers section + research surface + mini-assessment insertion for vendor-type tasks.
- Task catalog updates: research scope flags, pointer content for top task types (Firestore writes — extendable after launch without releases).
- **Fallback if the day overruns:** the client surface and pipeline plumbing are the Friday gate; brief quality for lower-frequency task types iterates server-side during review. The top-10 quality gate (§3.3) is the only content bar the binary waits for.

### Day 4 — Thursday: Scanner + gift codes + sweep.
- Fix everything Audit A surfaced. Verify all four scanner outputs against reality: Adam scans a real room and checks the truck size and estimate against his own professional judgment. That's the calibration standard.
- Gift code system (§4): function, entitlement merge, redeem sheet, mint script.
- Settings, onboarding, and residual copy sweep.
- **Thursday night: Launch Gates review (§6). Every gate green or Friday doesn't happen.**

### Day 5 — Friday: QA + submission.
- Full device pass: fresh install → assessment → list → gated tap → purchase → relaunch persistence → research on 5 task types → full scan → all four outputs → gift code redemption on a second account.
- App Store Connect: create the non-renewing IAP, **attach it to the version before submitting the binary** (this exact miss caused a prior rejection). Legacy annual/weekly stay on sale until this build is approved, then Remove from Sale.
- Screenshots: the 7-slot AppScreens sequence re-shot to match the new positioning — no concierge frames, no Pinky Promise, no trial language.
- App Review notes: non-renewing product with app-managed 6-month term synced cross-device via Firebase account (Guideline 3.1.2 requires stating the mechanism); gift codes described as promotional partner access.
- Submit.

---

## 6. Launch Gates (all true Thursday night, or we don't submit)

1. Scanner: real-room scan produces all four outputs; truck size and cost estimate pass Adam's professional-judgment check.
2. Research: top 10 task types return briefs Adam would sign; zero uncited URLs across all test generations.
3. Gate: free user sees full list, first gated tap hits paywall, no gated surface leaks.
4. Purchase: sandbox buy → kill app → relaunch → access persists (exercises the `Transaction.latest` path).
5. Gift code: mint → redeem on clean account → full access → persists across relaunch.
6. Zero: n8n endings, Pinky Promise strings, trial copy, weekly-price copy, hardcoded prices (`grep` verified).
7. App Store Connect: IAP created, priced, localized, screenshot attached, **bound to the version**.

---

## 7. Deltas to MOVEPASS_PRICING_SPEC.md (apply before running Day 2)

1. **Gate trigger:** replace all "paywall after 3 completed tasks" logic and copy with first-gated-tap. PaywallValueView copy drops any tasks-window framing.
2. **Entitlement merge:** Phase 1's `updateSubscriptionStatus()` gains a Step 3 — Firestore gift entitlement check (`source: "giftCode"`, expiry future) when StoreKit finds nothing.
3. **Redeem a code:** Phase 3's redeem button routes to the custom code-entry sheet, not `presentOfferCodeRedeemSheet`.

---

## 8. Post-Launch Tracks (start in parallel where noted)

**Track 1 — ISP revenue (target: live within 2 weeks of launch).**
Website fixes start *now*, in parallel with the app build — they're not iOS work: FTC affiliate disclosure page, About page with founder credentials, brand-domain contact, verify/clear the suspected `noindex` in Search Console. Email `allconnectpartnerships@redventures.com` the day the site is clean. The ISP task ships in the Friday binary as research-guidance; when Allconnect approves, the affiliate integration switches on via Firestore config — no release. CJ Affiliate and Impact applications go out the same week as Allconnect.

**Track 2 — Ads flywheel.**
Trigger: first 10 organic paid conversions validate the paywall converts at all. Then Apple Search Ads first (highest intent: moving checklist / moving app / moving planner terms), small daily budget, kill/scale weekly. Target CAC under $25 — half the subscription price, leaving margin for the flywheel to actually spin. Every other channel (YouTube blitz, blog/SEO, Product Hunt backlink) continues per existing plans as the organic floor.

**Track 3 — Realtor channel.**
Codes exist at launch. First batch goes to the warm KC realtor contact and the ~50-agent speaking opportunity. Pricing to realtors, batch sizes, and the pitch one-pager are a week-2 work item — after the app has proven the redemption flow with a small friendly batch.

**Track 4 — Feature ladder (post-launch, one at a time, ranked revenue × value).**
Current ranking to revisit monthly: 1) ISP affiliate (Track 1), 2) supplies kit affiliate links off the scanner's supply estimate, 3) additional affiliate verticals (truck rental, storage), 4) vendor accountability layer — which resurrects the Pinky Promise as its own launch moment.

## 9. Risks, Named

- **Day 3 is the schedule's center of gravity.** If the research pipeline fights back, everything else compresses. The fallback in §5 is the pressure valve; gift codes are the only Friday-scope item with any give, and only as a last resort.
- **Review rejection vectors:** IAP not bound to version (solved by checklist), non-renewing disclosure wording (solved by spec Phase 3 text), gift-code mechanism read as IAP circumvention (mitigated by review-notes framing — if rejected on this, ship without the redeem entry point and resubmit while appealing).
- **Season math:** submission Friday + review time puts approval mid-August — the season tail is real but short. The plan's honesty: launch revenue proves the paywall; spring 2027 is where volume lives. Winter is for the feature ladder and the ad-creative library.
- **Calibration risk:** the scanner's estimates carry the paywall's money-saving pitch. Adam's professional judgment is the launch calibration standard; post-launch, real user outcomes (did the truck fit?) become the feedback loop.
