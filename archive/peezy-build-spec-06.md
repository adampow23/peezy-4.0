# Peezy v1 Build — Spec 06: Packing Plan + Supplies Kit + Readiness Gate
Prereqs: Spec 05 + pricing chip complete. Read the repo's peezy-conventions-v2.md, peezy-v1-architecture.md §7, peezy-execution-protocol.md. Model: Fable 5 or Sol, effort xhigh. Autonomy: A CORE (dose integration), B–D PERIPHERY.

## Scope statement
The hand-holding centerpiece: a reverse-scheduled packing plan generated from the user's own inventory, surfaced one session at a time through the daily dose; a derived supplies kit offered as one tap; and the T-1 readiness gate that protects the estimate and feeds vendor accountability. No supplier is signed yet — the kit orders through the existing concierge submission path (SMS notify), with the supplier handoff swapping in later as data.

## Phase A: PackingPlan engine + dose integration (CORE)
**READ FIRST:** DailyDoseEngine.swift, TaskActionService.swift, the inventory session's item/room persistence (Firestore shapes), TaskGenerationService, PeezyCardFirestoreMapper.

1. **`PackingPlanEngine`** (pure, unit-tested in /Tests/): inputs = inventory items grouped by room + move date + today. Output = ordered sessions, each {room(s), estMinutes (~40 target, split large rooms), scheduledDate, itemSummary}. Room order (LOCKED, constants file): storage/seasonal → decor/books → guest/spare → garage → secondary bedrooms → kitchen non-essentials → primary bedroom → bathrooms → kitchen essentials → first-night bag (always last, always its own session). Reverse-schedule from moveDate−1 backward; if days < sessions, merge smallest-adjacent sessions rather than dropping any.
2. **Persistence + generation:** plan stored at users/{uid}/packingPlan; sessions materialize as task docs (taskId PACKING_SESSION_{n}, actionType in-app) via TaskActionService — catalog-external by design (engine-generated, per architecture). Generated at inventory-review completion; regenerated (statuses preserved for completed sessions) when moveDate or inventory changes.
3. **Dose integration:** at most ONE packing session joins each day's frozen dose, scheduled-date-driven, counted in the target. Reflow: on load, if past-dated sessions are incomplete, re-spread remaining sessions across remaining days silently — never render an overdue pile (LOCKED behavior).
4. **Session card + view:** "Today: {room}. About {est} minutes." with the room's item summary from the scan ("Here's what's in it"), complete/snooze via existing actions. Completion consequence line (LOCKED): "{room} done — {x} of {n} rooms packed. On pace for {moveDate}."

**Acceptance:** unit tests for ordering, reverse-scheduling, merge-on-short-timeline, reflow; live run: scan → plan generated → session card in tomorrow's dose (screenshots); complete a session → consequence line + next session scheduled; date change regenerates preserving completed.

## Phase B: Supplies kit (PERIPHERY)
1. **`KitEstimator`** (pure, unit-tested): inventory cube + item mix → {small, medium, large, wardrobe (from hanging count), dishPack (kitchen presence), tape, paper, wrap, mattressBags (bed count)} with +12% headroom, rounded up. Constants LOCKED-pending-calibration (the box-return loop tunes them later).
2. **Kit card** surfaces at plan creation (once): the single bundle, itemized, one price line (constants-priced placeholder until a supplier signs), disclosed headroom copy (LOCKED): "Includes a few extra — running out mid-pack is worse than spares." One tap = paywall gate (kit is a gated action, already wired) → concierge submission (workflowId supplies_kit, full kit + identity payload, SMS notify fires "PEEZY KIT ORDER: ..." — extend the approved format family). "Customize" opens a quantity sheet (the one escape hatch); "No thanks" dismisses permanently to a Tasks-tab row.
3. **Catalog edit + reseed (sanctioned):** BUY_PACKING_SUPPLIES retired from taskCatalog (the kit card is its TRANSFORM successor); ghost-check after reseed.

**Acceptance:** estimator tests (bedcount→mattressBags, hanging→wardrobe, headroom math); live: plan creation → kit card → tap → paywall → submission doc with complete payload (read-back) + SMS-or-not-configured log; catalog count updated, no ghosts.

## Phase C: Readiness gate (PERIPHERY)
1. **T-1 gate card** (engine-scheduled like a session, always moveDate−1, never reflowed away): checklist — all sessions complete, furniture disassembled, elevator/parking reserved (pre-filled from RESERVE_ACCESS answers when present), path clear, first-night bag set aside. Each item tap-toggles; results persist to users/{uid}/readiness {items, completedAt} — this is the vendor-accountability evidence layer (LOCKED purpose comment).
2. **Behind-pace nudge:** when reflow compresses remaining sessions below a threshold (>1.5 sessions/day required), the next session card carries one extra line (LOCKED): "You're behind pace — movers charge by the hour, and unpacked homes run long. Today's session matters."
3. Incomplete gate at day's end → single consequence line on the gate card (LOCKED): "Heads up: unready homes are the #1 cause of moving-day overages." No blocking, no guilt loops.

**Acceptance:** gate card renders at T-1 with pre-filled reservation state (screenshot); toggles persist and read back; nudge line appears under compressed reflow (simulated date) and not otherwise.

## Phase D: Doc sync (protocol §6) — conventions, CLAUDE.md, SESSION_NOTES; add open item "kit supplier: replace concierge fulfillment with local supplier handoff when signed."

## Files Summary
Created: PackingPlanEngine.swift, PackingConstants.swift, KitEstimator.swift, session/gate views, /Tests/ for both engines. Modified: DailyDoseEngine.swift (one-session rule), TaskActionService.swift, PeezyCardFirestoreMapper.swift (in-app routing for the new taskIds), taskCatalogData.json, functions/index.js (KIT SMS line), firestore rules NOT touched (users/{uid} subpaths already owner-readable — verify, else NEEDS-CLARIFICATION). Deployed: catalog reseed + functions:submitWorkflowAnswers (sanctioned).

## Delegation Prompt
```
cd ~/Desktop/Peezy 4.0/. Read peezy-conventions-v2.md, peezy-v1-architecture.md,
peezy-execution-protocol.md, then peezy-build-spec-06.md. Execute Phases A→D.
Phase A is CORE: separate commit, walked diff, unit tests mandatory. Validator
per phase against the acceptance lists. Sanctioned deploys only: catalog reseed
+ functions:submitWorkflowAnswers. STOP on anything not covered. Investigate
and execute.
```
(Codex variant: prepend the standard no-hooks self-enforcement block and read CLAUDE.md in place of AGENTS.md.)
