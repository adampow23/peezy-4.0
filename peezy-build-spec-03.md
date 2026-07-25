# Peezy v1 Build — Spec 03: Card + Stage Model
Prereqs: Specs 01–02 complete. Read peezy-conventions-v2.md (latest — includes both run corrections), peezy-v1-architecture.md §3, peezy-execution-protocol.md. Runs under the execution protocol. Model: Fable 5, effort xhigh.

## Scope statement

This spec rebuilds the card data layer so it can carry the v1 architecture: one decoding path, honest SwiftUI diffing, persisted stages, and a bounded daily dose the user can finish. It does NOT touch the flow engine, router, or any flow screen — those are Spec 04. All 47 existing flows must behave identically after this spec.

**Autonomy tier: CORE** (per execution protocol §4) — PeezyCard has ~20 dependents and both loaders are LESSON-bearing. Sub-phases commit separately; every hub-file diff gets walked in the phase report.

## Phase A: PeezyCard rewrite + single decoding path

**READ FIRST:** PeezyCard.swift in full; PeezyCardFirestoreMapper.swift; PeezyHomeViewModel.loadTasks (:295 region); TasksStore; every construction site (`grep -rn "PeezyCard(" --include="*.swift"`); every `==`/onChange consumer that could depend on Equatable semantics.

Changes:
1. **Memberwise Equatable.** Delete the custom id-only `==` (:365-367). Derive Equatable memberwise (synthesized). Then audit every usage that *relied* on id-only semantics (e.g., array diffing, `.onChange(of: card)`) and fix call sites to compare `card.id` explicitly where identity—not value—was intended. Cite each site in the report.
2. **New fields:** `stage: TaskStage?` and `payload: CardPayload?` where `CardPayload` is an enum with associated values, starting minimal: `.none` semantics via nil, `.vendor(VendorRef)` and `.capture(CaptureRef)` as empty-shell structs (populated in Specs 04–05; defined now so decode/encode round-trips).
3. **Single decoder.** PeezyCardFirestoreMapper becomes the ONLY Firestore→PeezyCard constructor. PeezyHomeViewModel.loadTasks consumes the mapper (delete its inline field-by-field construction). Static factories/previews remain. Add the parity-marker comment LE-025/031 demanded — now the comment says "single path; do not add a second."
4. **TaskStatus reconciliation:** add explicit case `pending` mapping the server's lowercase `"pending"` string. Render semantics: pending == matching-in-progress (a waiting card, not an actionable one) — map `matchingInProgress` and `pending` to the same UI treatment, and DELETE the dormant `matchingInProgress` enum case in favor of `pending` unless a live query references it (grep first; cite).

**Acceptance criteria:**
- GIVEN a snoozed card, WHEN snoozedUntil lapses and status mutates, THEN the Home UI visibly updates without relaunch (the id-only-Equatable bug, demonstrated fixed — before/after screenshots).
- GIVEN a server doc with status "pending", WHEN decoded, THEN the card renders the waiting treatment, not .upcoming (screenshot + decode evidence).
- GIVEN the full test-bot task set, WHEN Home and Tasks tab both load, THEN field-identical cards (automated diff of both paths' output for the same docs).
- Build succeeds; all 47 flows still open from their cards (validator spot-checks 5 across types).

## Phase B: TaskStage model (persisted, not yet rendered)

New `TaskStage` enum: `notStarted, capture, measure, scope, price, compare, book, verify, complete` — Codable, stored on the task doc as `stage: String`, decoded by the mapper, nil-tolerant (absent = notStarted for workflow tasks, irrelevant for off-app). Write path: a `TaskActionService.setStage(taskId:stage:)` callable-free direct write matching existing status-write patterns. NO UI consumes stage yet (Spec 04 renders resume-at-stage); this phase is model + persistence + decode round-trip only.

**Acceptance criteria:** write stage → kill app → relaunch → mapper decodes the same stage (evidence via read-back); no visual change anywhere (screenshot parity on Home + Tasks).

## Phase C: PeezyHomeViewModel split

**READ FIRST:** PeezyHomeViewModel.swift in full (766 lines, mixes 4 concerns).

Split into: `DailyDoseEngine` (the target math :182-193 and urgency sort :336-341 — PORT THE MATH VERBATIM, it is correct and calibrated), `TaskActionService` (all status/snooze/complete writes, absorbing Phase B's setStage), and a thin PeezyHomeViewModel that composes them. The hardcoded `newFlowIds` allowlist STAYS for now (it dies with the router in Spec 04) — move it unchanged into the thin VM.

**Acceptance criteria:** dose target for the test bot's task set and days-out computes to the identical number pre/post split (numeric evidence); snooze +2d/+1d writes byte-identical Firestore updates (before/after doc diff); build + 5-flow spot-check.

## Phase D: Dose counter + completion feel + done-for-today

**READ FIRST:** PeezyHomeView.swift, the greeting-card rendering (locate it — likely within PeezyHomeView's state machine; cite where), PeezyHaptics.

1. **Counter:** greeting/home surface shows "N for today" and per-card "X of N" (source: DailyDoseEngine). 
2. **Completion feel:** on complete — success haptic + card-exit animation + the counter ticking. Use existing PeezyHaptics + SwiftUI transitions; no new dependencies.
3. **Done-for-today state:** when the day's dose completes, a closing card: "That's today. You're on pace for [move date]." (Copy LOCKED.) Tomorrow's dose does not leak in. Tasks tab remains fully accessible (the pressure valve).
4. Accessibility ids on all new elements.

**Acceptance criteria:**
- GIVEN a 3-task dose, WHEN each completes, THEN counter shows 1/3→2/3→3/3 with haptic+animation per completion (screen recording or sequential screenshots), THEN the done-for-today card renders with the move date, THEN no further task cards render on Home today, THEN Tasks tab still lists everything (screenshots).
- GIVEN next app-day (simulated date change or dose recompute), THEN a fresh dose appears.

## Files Summary
Modified: PeezyCard.swift, PeezyCardFirestoreMapper.swift, PeezyHomeViewModel.swift, PeezyHomeView.swift, TasksStore.swift (if decode touches it — cite), call sites surfaced by the Equatable audit (manifest lists them as discovered, per the read-site rule). Created: TaskStage.swift (or within PeezyCard.swift — agent's call, cite), DailyDoseEngine.swift, TaskActionService.swift, CardPayload shells. Deployed: NOTHING.

## Delegation Prompt
```
cd ~/Desktop/Peezy 4.0/. Read peezy-conventions-v2.md, peezy-v1-architecture.md,
peezy-execution-protocol.md, then peezy-build-spec-03.md. Execute Phases A→D in
order. CORE tier: separate commits per phase, walk every hub-file diff in the
report, PHASE_MANIFEST includes read-site files. Validator per phase. Nothing
deploys. STOP on anything the spec doesn't cover. Investigate and execute.
```
