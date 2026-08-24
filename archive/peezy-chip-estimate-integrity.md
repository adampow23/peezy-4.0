# Chip: Estimate Integrity (pre-mortem fixes)
From the red-team pass on scanner → cube → pricing → packing. Read repo peezy-conventions-v2.md + peezy-execution-protocol.md. Autonomy: CORE for PricingEngine/PackingPlanEngine (unit tests mandatory), PERIPHERY elsewhere. Deploys sanctioned: processInventory (prompt/config edit), submitCheckIn, catalog reseed if flows change.

## A. Hidden-goods factor (cube model)
PricingConstants gains hiddenGoodsCubeByBedrooms (LOCKED-pending-calibration; e.g. 1BR +80, 2BR +140, 3BR +220, 4BR+ +300 cu ft — Adam tunes) applied to inventoryScan-sourced cube (bedrooms fallback already implicitly includes it — do NOT double-apply; document why in code). Disclosure line joins the estimate (LOCKED): "Includes what scans can't see — closets, cabinets, drawers."
Tests: applied to scan source only; range shifts accordingly.

## B. Coverage check (inventory review)
At review, compare rooms detected against the identity/assessment room expectation (bedrooms count + standard rooms + dwelling-implied garage/basement). Render a coverage strip: "Scanned: X, Y, Z. Not seen: garage, basement" with per-room [Add a clip] / [Nothing there] actions. "Nothing there" records coverageConfirmed; unresolved unseen rooms widen the estimate range one confidence notch and add disclosure "Some rooms weren't scanned."
Acceptance: unseen-room flow round-trips both actions; range widens only when unresolved (screenshots + evidence).

## C. Big-move gate
cubicFeet (post hidden-goods) > bigMoveCubicFeetGate (constant, start 1300) → same treatment as the 100-mile gate: no instant cards; concierge quote card, copy (LOCKED): "This is a big one. Big moves deserve a hand-built quote — we'll have yours within a day." quoteRequest submission with full scope. The "one solid morning" why-line therefore only ever renders on moves that satisfy the 6-hour ceiling — assert this invariant in tests.
Acceptance: over-gate scope in the sim shows the concierge card (screenshot); unit test proves why-line never accompanies >6h physical hours.

## D. Storage stop legs
Refinement step (only when hasStorage=Yes): "Is your storage unit a stop on moving day?" + optional unit address/city. Yes → MoveScope.storageStop {address?} → drive time = leg(origin→storage) + leg(storage→dest) via existing MapKit path (city-level geocode acceptable; missing address → +30 min flat, disclosed), plus storageStopLoadHours constant added to physical hours (pre-ceiling).
Tests: legs sum; flat fallback; ceiling interaction.

## E. Packing room-type floors
PackingConstants gains minimum session-minutes floors by room type (kitchen 150, garage 120, bedroom 60, bathroom 30 — LOCKED-pending-calibration). Session estimate = max(floor, item-derived). Kitchen always ≥2 sessions.
Tests: floors bind when items sparse; item-derived wins when larger.

## F. Calibration capture (the feedback loops)
1. Check-in adds optional "What was the final bill?" numeric (only for booked-vendor path) → estimateCalibration {userId, vendorId, estimatedRange, finalBill, scopeSnapshot, submittedAt} via submitCheckIn.
2. Box-return flow adds "Did you run out of boxes before move day?" yes/no → kitCalibration gains ranOut flag.
No client-side analysis; data collection only.
Acceptance: both fields persist via read-back; check-in without a booking never shows the bill question.

## G. Duplicate-count verification (diagnostic, then fix only if needed)
Diagnostic first: run one multi-frame single-room fixture (same furniture visible across ≥5 frames) through processInventory and report the item count vs ground truth. If duplicates appear: fix in the vision prompt/config (instruct cross-frame dedup by item identity) and re-run; regression-gate the moving config's existing byte-identical fixture. If no duplicates: record the evidence in SESSION_NOTES and change nothing.

## Delegation Prompt
```
cd ~/Desktop/Peezy 4.0/. Read peezy-conventions-v2.md, peezy-execution-protocol.md,
then peezy-chip-estimate-integrity.md. Execute A→G; G runs its diagnostic before
any prompt change. CORE items: unit tests + walked diffs. Validators per the
acceptance lines. Sanctioned deploys only: processInventory (only if G requires),
submitCheckIn, catalog/flow reseed if flows change. STOP on anything not covered.
Investigate and execute.
```
(Codex variant: standard no-hooks block; read CLAUDE.md.)
