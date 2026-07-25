# Peezy v1 Architecture — Locked Decisions
Status: LOCKED except items marked DECISION. Grounded in V1_ARCHITECTURE_MAP.md (audit @ f7e47ad) and cleanup commits through da1916e. This document is the authoritative input to the v1 build spec. Read peezy-conventions-v2.md first.

## 0. Non-negotiables

**Pillars:** (1) Fully directed actions — the app decides, the user taps; never choose-your-own-adventure. (2) Less is more — only needle-moving steps and information. (3) People over profit — revenue must align with genuinely helping; the Peezy Promise stays. (4) Clarity and transparency — any confusion collapses trust.

**Standard held throughout the build:** the app *does the task*, it does not describe the task. Any design that degrades into "we'll send you a message with options" is rejected on sight. Scope is never reduced for complexity; blocked dependencies are decomposed (ship what we control, queue what we don't).

**v1/v1.1 line:** who owns the clock. Anything requiring only our work (code, local vendor outreach, curation) ships in v1 regardless of effort. Anything gated on an external approval queue is v1.1: Gmail/CASA detection, Plaid, U-Haul affiliate API, ISP serviceability APIs, in-app AI chat. All four applications/inquiries are sent immediately; their clocks run in parallel with the build.

## 1. The workflow spine

One universal workflow; every industry is an adapter:

```
CAPTURE → MEASURE → SCOPE → PRICE → COMPARE → BOOK → VERIFY
```

- CAPTURE: per-task, invoked at the moment the daily dose surfaces the task. Never a general-purpose scan. One capture = one job, framed as such (perceived accuracy requires it).
- MEASURE: pipeline turns capture into structured data (frames→vision, or structured questions as fallback). Every capture path has a no-sensor/no-video fallback that produces a wider range. A missing capture never dead-ends a flow.
- SCOPE: engine outputs a **scope object** — quantities only, no dollars (cube ft, crew-hours per crew size, item counts, wall sq ft).
- PRICE: scope × vendor rate card = range, never a point estimate. Always shown with the disclosure: estimates are averages; the specific variables that push cost higher are listed visibly (not packed when crew arrives, unreserved elevator, long carry, undisclosed stairs). Users are armed, not warned.
- COMPARE: hotel-scan pattern. One reusable comparison card component; 3 vendor cards; each carries only decision-driving fields (price range, window, crew, insurance, rating, one line of why). Renders movers, cleaners, junk, ISP plans identically.
- BOOK: one tap → vendor confirmation request (service) or attributed pre-filled handoff (affiliate).
- VERIFY: post-job check-in with specific factual questions (arrived in window? crew worked steadily? charged more than quoted? damage?) feeding the accountability ladder: conversation → warning → removal. Day-of price changes are a bannable offense, stated in vendor terms. Marketing promise is about OUR behavior ("we hold them accountable"), never a price guarantee.

## 2. Flow engine (replaces the 39 templated screens)

**Decision (Q4): config-driven engine.** Rationale: a new vertical must be a Firestore write, not an App Store review cycle. Vendor onboarding speed cannot be gated on Apple.

- The 18-component kit in `Tasks/Task Card Components/` is the renderer library. PORT VERBATIM, untouched. TaskFlowTitleCard(49 deps), TaskFlowStack(47), TilesCard+variants, DecisionCard(18), BusinessSearchCard(13), ConfirmAddressCard(7), ConfirmDateCard, StatusCard(40), SummaryCard(26), InfoCard(42) already cover every screen type the templated flows use.
- New `FlowEngine` view interprets a flow definition (ordered card specs + branching) and renders via the kit. New `FlowDefinition` model decodes from Firestore.
- **Adopt the orphaned server system (Q11):** `getWorkflowQualifying` + `WORKFLOW_QUALIFYING` (44 keys) + `MINI_ASSESSMENT_WORKFLOWS` (6) become the definition source. The server side of this engine is already deployed and paid for.
- Router: `TaskFlowRouter`'s closed switch + `newFlowIds` allowlist are replaced by data-driven resolution on the dormant `taskType`/`workflowId` fields (already flowing catalog→Firestore→PeezyCard, currently never read). Unroutable task renders a graceful "coming right up" card + logs — never the permanent spinner (PeezyHomeView:311-321 behavior dies).
- Migration: Types 1–3 (38 templated files) supersede first. Type 4–6 customs (insurance, FindMovers, FindCleaners, SetupInternet, SellItems, RemoveItems, RentTruck) port as-is, then FindMovers/FindCleaners/SetupInternet/RemoveItems are rebuilt on the spine (they become the first real vendor verticals). TaskFlowDismissButton (inert, 48 refs) is dropped from files as the engine supersedes them — never as a standalone pass.

## 3. Stage model + card model

- New persisted `TaskStage` (spine stages + notStarted/complete) stored on the task doc; server may write it; client renders resume-at-stage. Answer capture persists per stage (kills the ephemeral `[String:[String]]`-once pattern; enables resume and cross-stage handoff).
- `TaskStatus` reconciliation: add explicit `pending` case mapping the server's lowercase "pending"; `matchingInProgress` either gets queried or gets deleted — no dormant cases.
- **PeezyCard: REWRITE (Q5).** Memberwise Equatable (kills the id-only `==` diffing hazard). Adds `stage: TaskStage?` and a per-type payload enum (`.vendor(VendorPayload)`, `.capture(CaptureRef)`, …). Single decoding path: `PeezyCardFirestoreMapper` becomes the ONLY Firestore→PeezyCard constructor; PeezyHomeViewModel.loadTasks consumes it (ends the LE-025/031 parity coupling structurally). 20 dependents migrate in one phase with compile-driven fix-ups; static factories and previews update mechanically.
- PeezyHomeViewModel: REWRITE, split into DailyDoseEngine (target math :182-193 ports as-is — it works), TaskActionService (status writes), and a thin VM. Concierge payload moves to the identity object.

## 4. Identity object

Single authoritative model + single Firestore doc `users/{uid}/identity` (new, greenfield):

```
PeezyIdentity {
  name, email (from Auth), phone (NEW — collected in first vendor booking, not assessment),
  currentAddress {street, unit?, city, state, zip, raw},
  newAddress   {street, unit?, city, state, zip, raw},
  moveDate, moveDistanceMiles, isInterstate
}
```

- Written once at assessment completion (parsing the AddressSearchManager string formats — parser from commit 8413f2d is the seed), updated via Settings edits that write THIS doc (kills the `.limit(to:1)` nondeterminism) and recompute distance on address change.
- `UserState` remains the app-side struct (21 consumers keep their @Binding) but is rebuilt to load from the identity doc; the city/state-only stopgap fields are replaced by full address structs.
- Contract rot purge: the ~15 always-empty assessment keys (bedrooms, sq-ft, storage, hasVehiclesDetail, hirePackers, wantToSell, moveConcerns, referral/promo, *Details maps) are removed from `getAllAssessmentData()` and the catalog conditions that reference them are corrected or retired in the same pass. hasVehicles-always-"No" and default autoRoomList are known-wrong signals — no task may condition on them until re-collected.
- `userKnowledge/{uid}` (greenfield — zero successful writes ever): becomes the assistant-context store, schema `{entries: {key: {value, source, updatedAt}}}` matching contextBuilder.js. Client adopts this shape; rule deploys after waitlist reconciliation.

## 5. Capture architecture

- Video→inventory pipeline: capture UI, frame extraction, upload, callable transport all PORT VERBATIM (verified domain-blind). Frozen regions per conventions.
- **Parameterization layer (new, server):** `processInventory.js`'s inline prompt (:95-144) + whitelists (:183-185) refactor into per-vertical config `{visionPrompt, outputSchema, validators}` keyed by `verticalId` on the callable payload. Moving is config #1, byte-identical output to today (regression-gated). Junk removal is config #2 (items + disposal class + truck fraction).
- Review UI: extract the moving-specific constants (categories/tiers/copy, InventoryReviewViewModel:52-56,110-118) into the same vertical config; the review screens themselves are generic.
- RoomPlan (painting/flooring measurement) is a **separate capture modality**, second wave, LiDAR-gated with structured-question fallback. Not built in v1 week; architecture reserves `CaptureKind.roomScan`.
- Capture registry: `CaptureKind` enum + protocol replacing ScanInventoryFlow's bespoke special-casing (TasksStore:111-179, TaskRowButtons:82-98) so the 8th vertical attaches without touching TasksStore.

## 6. Pricing engine (movers first)

- Inputs: inventory cube volume, drive time, access multipliers (flights of stairs both ends, elevator shared/reserved, long carry), packed status, specialty items.
- Output: hours per crew configuration {2,3,4 movers}; engine selects optimal config (hours drop faster than rate rises — surfaced to the user as insight).
- Vendor rate card (the recruiting deliverable): hourly by crew size, trip charge model, minimum hours, clock policy, materials, valuation tiers, weekend/month-end/peak surcharges, blackout dates, radius. 3–5 KC movers for launch.
- Calibration: five recent real KC moves run through the engine before any user sees a number; Adam's 9 years is the seed model.
- No-video fallback: bedrooms + rooms → cube estimate, wider range, flow never dead-ends.

## 7. Packing plan + supplies kit

- Reverse-scheduled from move date, generated from the inventory: rarely-used → daily-use → first-night bag. One daily-dose card per session ("Today: the guest closet, ~40 min"). Plan silently reflows remaining rooms when the user slips — never a wall of overdue.
- Readiness gate T-1: everything boxed, disassembly done, elevator reserved, path clear, essentials out. Gate results are stored — they are the evidence layer for vendor-overage adjudication.
- Supplies kit: derived quantities (boxes by size from cube+mix, wardrobe from hanging count, dish packs, mattress bags) + 10–15% disclosed headroom, offered as ONE bundle, one tap, at plan creation, delivery dated before session 1. No line-item shopping UI; single "customize" escape hatch. Fulfillment: local KC supplier first, national affiliate cart-handoff as the always-available fallback.
- Return loop: post-move box pickup as a scheduled rate-card line item; returned counts feed kit-estimate calibration.

## 8. Non-service tasks (tiered execution)

- Tier 1 (v1.1): detection — Gmail metadata on-device, Plaid recurring charges.
- Tier 2 (v1): deep-link directory — maintained Firestore collection of provider address-change URLs, opened with identity pre-fill. Seeded with top ~40 providers.
- Tier 3 (v1): concierge — n8n path via requestConcierge, now carrying the full identity payload. Signed authorization copy in the flow.
- ISP (v1): curated KC provider/plan cards through the comparison component + Impact/CJ attributed handoff, identity pre-filled. Serviceability API swaps in at v1.1 without UI change. U-Haul: assessment-conditioned task card + deep link now; affiliate API later.
- The daily dose sequences all of this on the real deadline graph (insurance before move day, DMV window, USPS lead time) — cards surface one at a time in dependency order.

## 9. Onboarding explainer

Five tap-through cards before question 1: (1) name the pain, (2) directed action promise, (3) boring-on-purpose declared as respect, (4) the wedge — "we do the parts you hate," (5) why the questions earn their length. Copy through peezy-copywriter voice. This ships first — it is self-contained and reframes everything behind it.

## 10. Paywall timing — LOCKED: option (c)

Soft, dismissible offer post-assessment (current PaywallGateView presentation, unchanged — it is Review #3-approved) + hard gate at first vendor booking. Free tier: assessment, daily dose, self-service tasks, inventory scan, packing plan. Peezy+ gates: vendor booking (BOOK stage), supplies kit one-tap order, concierge execution. Rationale: monetize at the moment of maximal demonstrated value; the paid line matches the concierge wedge exactly — everything a checklist can do is free, everything only Peezy can do is Peezy+. Implementation: one gating function `requiresSubscription(for:)` consulted at stage transitions; the gate itself reuses PaywallGateView (COMPLIANCE — presentation code untouched, only a second call site). The three-task trigger is retired from all docs.

## 11. Build order (v1)

1. Explainer (self-contained) + accessibility-id convention live from file one
2. Identity object + assessment write path + Settings edit path + contract-rot purge
3. PeezyCard rewrite + single mapper + stage model + status reconciliation
4. FlowEngine + definitions in Firestore + router replacement (Types 1–3 superseded; customs ported)
5. Capture parameterization (moving regression-gated, junk config added) + capture registry
6. Pricing engine + rate-card schema + comparison card component
7. Movers vertical end-to-end on the spine (capture→verify), then junk/cleaning/storage as vendors sign
8. Packing plan + kit + readiness gate
9. ISP curated cards + deep-link directory + concierge identity payload
10. Verify layer: post-job check-in + strike ladder + vendor standards doc

Each phase: spec → build → diff review → commit → simulator screenshot verification (XcodeBuildMCP) → next. Hooks enforce the protected-file list and manifest.
