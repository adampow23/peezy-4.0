# Peezy v1 Build — Spec 05: Pricing Engine + Movers Vertical
Prereqs: Spec 04 complete. Read the REPO's peezy-conventions-v2.md (now agent-maintained, includes Spec 04 corrections), peezy-v1-architecture.md (§1, §6, §9b), peezy-execution-protocol.md, peezy-v1-catalog-sheet.md. Model: Fable 5, effort xhigh. Autonomy: Phase 0 CORE (touches rules + functions), A–B CORE (money math), C–D PERIPHERY.

## Scope statement

Movers becomes the first full SPINE vertical: scope from the inventory, price from rate cards, three comparison cards, one-tap booking request through the existing concierge path. Rate cards seed with clearly-marked PLACEHOLDER vendors — real KC vendors swap in as data when Adam signs them; nothing in this spec blocks on vendor recruitment.

## Phase 0: Housekeeping batch (CORE — contains the Adam-gated deploy)

1. **Rules reconcile.** Merge the DEPLOYED ruleset's live waitlist rule into local firestore.rules (fetch deployed via the Rules REST API recipe in conventions); verify local additions preserved (userKnowledge, identity); ADD a read rule for flowDefinitions (authed read, no client write). Produce a full before/after diff of local-vs-deployed. **STOP and present the diff in-session. Deploy ONLY after Adam replies approving it.** After deploy: swap FlowDefinition loading from the getWorkflowQualifying callable to direct Firestore reads (keep the callable path as fallback for one release).
2. **Delete the orphaned cloud resetInventory function** (`firebase functions:delete resetInventory --project peezy-1ecrdl --force`) so full functions deploys work again. Verify with a `--dry-run`-style listing afterward.
3. **Bug chip: businessSearch dropdown.** Diagnose why results never visibly render (pre-existing, both binaries); fix within the component; validator proves suggestions appear on a live flow.
4. **Bug chip: dose counter across retakes.** Assessment retake clears/regenerates users/{uid}.dailyDose; validator proves a retake yields a fresh, correct dose.

**Acceptance criteria:** deployed rules match the approved diff; direct reads serve definitions (network evidence); full `firebase deploy --only functions` dry-path no longer aborts; dropdown screenshot; retake dose evidence.

## Phase A: Rate cards + vendors collection (CORE)

New Firestore collection `vendors` + seed `functions/vendorsData.json`. Schema per architecture §6: {vendorId, name, vertical: "movers", serviceRadius, rateCard: {hourlyByCrew: {2:_,3:_,4:_}, tripChargeModel, minimumHours, clockPolicy, materials: {...}, valuationTiers, surcharges: {weekend, monthEnd, peakSeason}, blackoutDates}, accountability: {standardsVersion, strikes}, active}. Seed THREE placeholders named "Test Mover A/B/C" with realistic-but-distinct KC-plausible numbers (Adam calibrates real ones later); `active` flag gates visibility. Admin note in the JSON header: real vendors are added by editing this file + reseeding, or direct console writes.

**Acceptance criteria:** seed round-trips; schema decode test in Swift; inactive vendor never surfaces downstream.

## Phase B: Pricing engine (CORE — the money math)

New `PricingEngine.swift` (pure functions, unit-tested — this is the one module where tests are mandatory, in /Tests/):

1. **Scope object:** `MoveScope {cubicFeet, driveMinutes, originAccess, destAccess, packedStatus, specialtyItems[], storageStop?}`. Cube derives from the inventory session via an item→cubic-feet lookup table (seeded from Adam's domain constants — mark the table LOCKED-pending-calibration); fallback: bedrooms → cube per the no-video rule (wider range flag). Storage trio (Spec 02 keys) contributes extra cube when hasStorage=Yes (size × fullness table). Access from the RESERVE_ACCESS answers when present, else defaults with widened range. Drive time via MapKit ETA between identity addresses.
2. **Hours model:** loadHours(cube, access, packed) + driveTime, computed per crew {2,3,4}; per-crew price = hours × hourlyByCrew + trip charge + surcharges(date) respecting minimumHours; engine selects optimal crew (lowest total; tie → fewer hours) and reports why ("3 movers finishes 2.1h sooner and costs less").
3. **Output:** `PriceEstimate {range(low, high), typicalHours, crew, disclosures[]}` — range width scales with input confidence (video vs bedrooms fallback; known vs default access). Disclosures are the LOCKED variable list (unpacked boxes, unreserved elevator, long carry, undisclosed stairs).
4. **Calibration harness:** a DEBUG-only runner that prints the full computation for 5 canned scenario fixtures (1BR local walkup → 4BR interstate) so Adam can sanity-check against his 9 years and tune the constants file. Constants live in ONE file (PricingConstants.swift) with his review explicitly invited in the report.

**Acceptance criteria:** unit tests pass covering each modifier + minimum-hours floor + crew selection flip case; the 5-scenario harness output included verbatim in the report for Adam's calibration pass; bedrooms-fallback produces a wider range than video-scope for the same home (asserted).

## Phase C: Comparison card + booked flow (PERIPHERY)

1. **`ComparisonCardView`** (generic, kit-styled): price range, typical hours + crew, arrival-window field, insurance tier, one why-line, "Price basis: your scan" tag. Renders N vendors; built once for movers, reused by cleaners/junk/ISP later — no movers-specific strings inside the component.
2. **BOOK_MOVERS flow upgrade** to the full spine: capture (existing video scan, invoked in-flow if no inventory session exists; else reuse latest) → scope-shown-back step ("3 bedrooms, ~1,180 cu ft, stairs at origin" — the show-your-work step, LOCKED pattern) → optional refinement step asking the storage trio + access questions IN-FLOW when unknown (this is the §9b tier-3 migration: these questions leave the assessment in Phase D) → three comparison cards from active vendors within radius → selection → paywall gate (already wired) → booking request submitted through the existing WorkflowService/concierge path with full payload {identity, scope, estimate, chosen vendor, requested window} → confirmation card with the accountability line ("Same price basis for every mover. If anything changes day-of, that's on them — and on us.") LOCKED.
3. n8n payload lands exactly like existing concierge submissions (manual fulfillment MVP per the master plan) — verify the webhook fires with the full payload.

**Acceptance criteria:** end-to-end run from task card → booked confirmation with screenshots at every stage; the three cards show the three placeholders with distinct prices ordered sensibly; no-inventory user gets routed through capture first; webhook payload captured and complete.

## Phase D: Tier-3 assessment migration (PERIPHERY)

Per §9b: remove the storage trio + both bedrooms questions from the assessment step sequence (views stay — they now render inside the mover flow's refinement step via the engine). Assessment shrinks accordingly. hasVehicles/moveDateType/everything-else untouched. Confirm zero catalog conditions reference the removed keys (wantToSell's DECLUTTER_INTENT dose card from Spec 04 covers the tier-2 side already).

**Acceptance criteria:** full assessment run shows the reduced count with no storage/bedrooms steps; mover flow's refinement step collects them for a user lacking the data; generation parity for a control profile.

## Phase E: Doc sync (protocol §6) — conventions corrections, CLAUDE.md facts, SESSION_NOTES.

## Files Summary
Created: PricingEngine.swift, PricingConstants.swift, MoveScope/PriceEstimate models, ComparisonCardView.swift, vendorsData.json, seedVendors.js, /Tests/PricingEngineTests.swift. Modified: firestore.rules (approved deploy), FlowDefinition loading, businessSearch component, DailyDoseEngine (retake reset), the movers flow definition, AssessmentCoordinator (step removals), functions/flowDefinitionsData.json. Deleted: cloud resetInventory (remote only). Deployed: rules (Adam-approved in-session), functions delete + reseed batch.

## Delegation Prompt
```
cd ~/Desktop/Peezy 4.0/. Read peezy-conventions-v2.md, peezy-v1-architecture.md,
peezy-execution-protocol.md, peezy-v1-catalog-sheet.md, then peezy-build-spec-05.md.
Execute Phases 0→E in order. Phase 0's rules deploy requires my explicit approval
in-session — present the diff and WAIT. CORE phases: separate commits, walked
diffs, read-site manifests, validators with the spec's criteria. PricingEngine
requires passing unit tests in /Tests/. Include the 5-scenario calibration
output verbatim in the report. STOP on anything the spec doesn't cover.
Investigate and execute.
```
