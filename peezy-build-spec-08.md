# Peezy v1 Build — Spec 08: Verify Layer + Launch Audit
Prereqs: Spec 07 complete. Read repo peezy-conventions-v2.md, peezy-v1-architecture.md §1 (VERIFY), peezy-execution-protocol.md. Model: Fable 5 or Sol, xhigh. Autonomy: A–B CORE (accountability data + one callable deploy), C–D PERIPHERY. This is the final machine-track spec of v1.

## Phase A: Post-move check-in (CORE)
1. **Post-move surfacing:** the dose engine currently schedules toward moveDate. Add date-gated task support: catalog rows may carry `surfaceAfterDaysPastMove: n`; the dose includes them once today ≥ moveDate + n (they join the frozen dose normally). READ DailyDoseEngine + generation first; smallest change that works.
2. **Catalog adds (reseed sanctioned):** MOVE_CHECKIN (surfaceAfterDaysPastMove: 1, condition: none — everyone gets asked how it went; branch inside for booked-vendor vs general) and BOX_RETURN (surfaceAfterDaysPastMove: 7, condition: kit purchasers — gate on the supplies_kit submission's existence, evaluated at generation refresh; if that check can't run cleanly at generation time, NEEDS-CLARIFICATION rather than hacking it).
3. **Check-in flow** (config-driven where the kit supports it): the four factual questions (LOCKED): "Did they arrive in the window?" / "Did the crew work steadily?" / "Did anything cost more than quoted?" / "Was anything damaged?" — yes/no tiles + one optional free-text. Submission via new callable `submitCheckIn` → writes vendorReviews {vendorId?, userId, answers, flags[], submittedAt} (backend-owned collection, no client rule needed). Any negative answer sets a flag; flags fire the SMS: "PEEZY FLAG: {vendor} — {flag}." General (no-vendor) check-ins store product feedback the same shape, vendorId null.
**Acceptance:** date-gated task appears only past the gate (simulated dates); check-in flow end-to-end with a flagged answer → vendorReviews doc read-back + SMS-or-not-configured log; general path stores with null vendor.

## Phase B: Strike ladder + standards doc (CORE)
1. **Strikes:** vendors.accountability gains strikes: [{date, source: reviewId, severity, status: pendingReview|confirmed|dismissed, note}]. A "charged more than quoted" or "damage" flag auto-creates severity: high, status: pendingReview (server-side in submitCheckIn — deterministic, no LLM). Adam confirms/dismisses via console for MVP (document the exact console path in the report). Ladder policy encoded as a pure function `ladderState(strikes) -> ok|conversation|warning|removed` (thresholds: 1 confirmed = conversation, 2 = warning, 3 or any confirmed day-of-price-change = removed) with unit tests; `removed` flips active:false on confirm #3 (server-side).
2. **Vendor standards one-pager:** write docs/vendor-standards.md in the repo — the vendor-facing standards (arrival windows, steady crews, no surprise fees, NO day-of price changes = removal offense, the check-in system, the ladder, rate-card acceptance of our scope basis). Voice: direct, warm, zero legalese (peezy-copywriter register). This is the doc Adam hands vendors with the rate card.
**Acceptance:** ladder unit tests incl. the day-of-price-change instant-removal path; a confirmed third strike flips active:false (emulated) and the vendor vanishes from comparison results (client evidence); standards doc committed.

## Phase C: Kit calibration hook (PERIPHERY)
BOX_RETURN flow: "How many boxes are you returning/recycling?" numeric + optional pickup-request toggle (concierge submission when toggled). Returned count writes users/{uid}/kitCalibration {delivered, returned} — the estimator-tuning loop's data. No estimator changes now.
**Acceptance:** flow round-trips; pickup toggle produces a concierge submission.

## Phase D: Launch readiness audit (PERIPHERY)
Sweep conventions open-items, todo.md chips, and every "before launch" note across the repo into a single LAUNCH_CHECKLIST.md: each item, owner (Adam/machine), status, and the exact command or console path to close it. Expected members (verify, don't assume): Twilio env + one live SMS; 5 affiliate URLs; admin review of source:resolved providers; real vendor rate cards replacing Test Movers; kit supplier; Xcode-scheme StoreKit subscribed-pass-through check; PrivacyInfo NSPrivacyCollectedDataTypes + auth-screen legal links; App Store screenshot/metadata refresh for the new surface area. Doc sync per protocol §6.
**Acceptance:** checklist committed; every item carries an owner and a close-path; conventions/CLAUDE.md current.

## Files Summary
Created: check-in + box-return flow definitions/views, functions/submitCheckIn.js, ladder function + tests, docs/vendor-standards.md, LAUNCH_CHECKLIST.md. Modified: DailyDoseEngine (date gates), taskCatalogData.json, vendors schema, functions/index.js. Deployed (sanctioned): submitCheckIn, catalog reseed, functions:submitWorkflowAnswers if the SMS format family changes.

## Delegation Prompt
```
cd ~/Desktop/Peezy 4.0/. Read peezy-conventions-v2.md, peezy-v1-architecture.md,
peezy-execution-protocol.md, then peezy-build-spec-08.md. Execute Phases A→D.
A–B are CORE: walked diffs, unit tests for the ladder, separate commits.
Validators per phase. Sanctioned deploys only: submitCheckIn + catalog reseed
(+ submitWorkflowAnswers only if the SMS family changes). STOP on anything
not covered. Investigate and execute.
```
(Codex variant: standard no-hooks block; read CLAUDE.md.)
