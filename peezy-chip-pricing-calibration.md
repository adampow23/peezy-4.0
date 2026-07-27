# Chip: Pricing Engine Calibration (post-Spec 05)
Adam's calibration decisions, 2026-07-26. Small session — touches PricingEngine.swift, PricingConstants.swift, MoveScopeFactory.swift, Vendor.swift, vendorsData.json, FindMoversFlow (why-line + gate copy), /Tests/PricingEngineTests.swift. Runs under the execution protocol; PERIPHERY except PricingEngine (CORE, unit tests mandatory).

## 1. Crew selection: 6-hour ceiling rule (replaces cost-optimization)
The selector is no longer "lowest total cost." Rule: start at 2 movers; add a mover whenever PHYSICAL load/unload hours exceed 6.0; quote the SMALLEST crew satisfying the ceiling. Drive time does not count against the ceiling. Rationale (comment in code): vendors can't be forced into larger crews, so we request the minimum viable crew every company can staff.
- Why-line copy (LOCKED): "Sized so your move wraps in one solid morning — not a marathon."
- Calibration instrument: per Adam, total price across adjacent crew sizes should be FAIRLY SIMILAR. Tune the crew-scaling curve (add diminishing returns per added mover) until adjacent-crew totals in the 5-scenario harness sit within ~10% of each other. The current near-linear scaling (Scenario 2 showed 2-crew 20% over 4-crew) is wrong.
- Tests: ceiling-trigger boundary (5.9h stays, 6.1h adds), smallest-crew selection, adjacent-crew price-similarity assertion on fixtures.

## 2. Specialty items: vendor flat fee + load-hours
- Vendor schema: add rateCard.specialtyFees: {itemKey: fee} (piano, safe/gunSafe, treadmill, marbleTops as starter keys). Seed distinct plausible fees on Test Mover A/B/C.
- Engine: each flagged specialty item adds (a) the SELECTED vendor's flat fee to that vendor's card price, and (b) item load-hours (PricingConstants table, e.g. piano ~1.5h — LOCKED-pending-real-vendor feedback) to physical hours BEFORE the 6-hour ceiling check — a piano may legitimately trigger the extra mover.
- Scan flags the item (inventory categories already carry it); comparison cards show a one-line "Includes piano handling" note when fees apply (copy pattern LOCKED).
- Tests: fee-per-vendor divergence on cards; hours added pre-ceiling; ceiling flip caused by a specialty item.

## 3. Interstate gate: 100 miles
- moveDistanceMiles > 100 (identity doc) → NO instant comparison. The mover flow renders a concierge card instead: "Long-distance moves get a hand-built quote from us — you'll have it within a day." (LOCKED.) Submission routes through the existing concierge path with full scope payload (identity, inventory scope, date, addresses) — same payload shape as booking, flagged quoteRequest: true.
- ≤100 miles: unchanged instant path. Missing miles (pending address): treat as over-gate (concierge) — over-prepare rule.
- Scenario 5 in the harness updates to demonstrate the gate, not an hourly interstate price. Delete the hourly-drive-billing path for >100mi.
- Tests: gate boundary, pending-address routing, payload flag.

## 4. Baselines: confirmed
Packed local 1BR ≈ $700 and unpacked 2BR ≈ $1,500 confirmed as KC-plausible. Do NOT retune base rates; placeholder vendor hourlies stay. Re-run the 5-scenario harness after changes 1–3 and include output verbatim in the report for Adam's final glance (Scenario 1 should now select 2 crew; Scenario 3's piano should show fee + hours; Scenario 5 should show the gate).

## 5. Booking notifications via Twilio SMS (replaces the webhook plan)
Adam's decision: SMS for reliability. n8n/webhook indirection is retired — the function texts directly.
- In submitWorkflowAnswers (functions/index.js), where NOTIFICATION_WEBHOOK_URL was consulted: replace with a Twilio send using env TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN / TWILIO_FROM_NUMBER → ADAM_NOTIFY_NUMBER. If env values are absent, log "SMS notify not configured" and continue (submission must never fail on notify failure — wrap the send, best-effort per the Cloud Functions pattern).
- Message format (LOCKED): "PEEZY BOOKING: {name}, {originCity}→{destCity}, {date}, {vendor}, est ${low}–${high}." Quote requests: same with "PEEZY QUOTE REQ:" prefix. No PII beyond first name + cities in the SMS; full payload stays in Firestore.
- Remove NOTIFICATION_WEBHOOK_URL from the code path and from open items; conventions gains: "Booking notify = direct Twilio SMS; env vars in functions/.env (Adam-owned)."
- Deploy: functions:submitWorkflowAnswers only (sanctioned, added to this chip's deploy list). Then ONE isolated test submission (TEST RUN prefix) — acceptance is Adam receiving the text. If env vars are missing at session time, build + deploy the code path, run the test submission, and accept the "SMS notify not configured" log as terminal evidence with the open item retained.

## Acceptance (validator)
All PricingEngine tests pass (existing 24 + new); harness output shows the three behavior changes above; a live >100mi profile in the sim reaches the concierge quote card (screenshot); a piano-flagged scan changes both price and crew on the comparison screen (screenshot).

## Delegation prompt
```
cd ~/Desktop/Peezy 4.0/. Read peezy-conventions-v2.md, peezy-execution-protocol.md,
then peezy-chip-pricing-calibration.md. Execute it as one session: PricingEngine
changes are CORE (unit tests mandatory, walked diff); the rest PERIPHERY.
Validator runs the acceptance list. Nothing deploys except the vendors reseed
(sanctioned). STOP on anything not covered. Investigate and execute.
```
