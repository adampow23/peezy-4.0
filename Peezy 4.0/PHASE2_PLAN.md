# PHASE 2 — Shared Client Components: Handoff, Outcomes, Row Surface, Trigger UX, Push, Research Posture — Plan/Spec (v1)

Status: architect's plan for the Claude Code session; codex adversarial review loop then execution, audit gate first. Snapshot: PEEZY_STATE.md at `e8d6133` (regenerated 2026-08-31) outranks everything here. No seeds, no deploys (H17/H43 still block), no production-connected tests; every `xcodebuild test` uses the Phase 1 selection discipline (named `-only-testing` unit classes, `-skip-testing:'Peezy 4.0UITests'`, no default test plan, no integration env).

## Purpose
Phase 1 made the state layer able to represent §A v3.3; the UI is still passive (H52: contracted rows render truthful copy but route no interactions). Phase 2 builds the shared client components every entry reuses — external handoff with return-and-resume, contextual outcomes, the row disposition surface, trigger UX, task push with deep links, and the research posture contract — so Phase 3's reseed is data plus flows, not new UI.

## Current state (from PEEZY_STATE, not memory)
- H52: shared disposition-contract model, server-owned, coherent status/contract validation; contracted rows passive; `visible_status_copy` renders when present; malformed contracts fail safe.
- H54: `changeTaskPlan` (source SUPPORTED, deployed UNKNOWN): six actions, operation fingerprints, immutable history, pending external amendment + confirmation, bounded undo, reopen, collision validation.
- H55: `evaluateDispositionTriggers` every-15-min scheduler, singleton lease, date/event cursors, wake clears `snoozedUntil`.
- H56: `flowAttemptId` submission barrier; client restoration persists flow state; H48 residual: newest in-flight write can be lost on suspension (no scene-phase flush).
- H45: push payloads carry only `thread: support`; no task deep link; URL handling is Google Sign-In only.
- H46: research confidence is section-level (`SPECIFIC`/`SAFE GENERAL`); brief persisted under `brief`.
- H44 (amended): `snoozedUntil` time triggers coexist with contract triggers; TaskRowHeader still renders `snoozedUntil` directly (Phase 1 deferred the header migration to Phase 2).
- H6: ten step kinds incl. status; H47: two router shadows (Phase 3); H27: catalog divergence (Phase 3).

## Locked design inputs (do not re-derive)
§A v3.3 A3 (no help/self; one-row focus) · A4 (handoff contract, contextual outcomes ≤5 primaries, chips after intent, time-aware CTA, legal-trigger display, batched amendment card, dependency-conflict card with support door, urgent-recovery consolidation) · A2 (WAITING display: owner/expectation/trigger/two exits; second cycle changes channel) · A8 (row menu is the disposition menu; "doesn't apply" resolver only on contradicting evidence) · A6 (support door; household handoff shares the task) · A5 (posture shown quietly) · A11a envelope (events the trigger UX writes).

## Scope — five workstreams, in order
1. **W1 — External handoff + contextual outcome components.** One `HandoffSession` client component: persist row + expected action + CTA kind before any call/portal/mail/map CTA (extends H56's persistence pattern to non-flow rows); mark in-progress; on return (immediate or next-day trigger via the contract) present the action-keyed outcome question (call/portal/written-notice variants, ≤5 primaries, chips only under "I need to do one more thing", free text visible); every outcome lands in a contract write via the existing writers or `changeTaskPlan` — no new status writer (Phase 1 W1 rule stands). Time-aware CTA (known-closed → schedule primary, number beneath). Resume: reopening the app or tapping the row returns to the exact outcome question with context line; "since you were gone" one-liner when anything changed.
2. **W2 — Row disposition surface.** The A8 row menu on every task row (*Already handled / This doesn't apply / Come back later / Someone else is handling it / I'm handling this outside Peezy / Edit this list*), mapping to W0's disposition actions and H54's supersession actions; "doesn't apply" one tap unless the contract carries contradicting evidence (then the resolver sheet). WAITING rows render the full A2 contract line with the two exits ("It happened" → outcome question; "It's stuck" → support door). Change plan on every row (supersede/undo per H54, bounded undo surfaced). The batched "Update your active dates" card derives **client-side** from the mapped contracts (2+ cards in the pending-external-amendment state sharing an anchor — no bulk server result); the consolidated "Needs attention now" view when 2+ urgent-recovery triggers have fired. **TaskRowHeader migrates to `visible_status_copy` with `snoozedUntil` fallback** (closes the Phase 1 deferral). Contracted rows become interactive through these paths only; legacy rows keep legacy behavior byte-identical.
3. **W3 — Trigger UX.** The DEFERRED picker: date or event (event list from the row's contract-eligible A11a events, e.g. "when my address is confirmed"), writing `next_trigger` through the existing writers; H55 wakes it. Deadline display rule: legal deadline dominant when confidence is high; `PEEZY_TARGET` as pacing copy; no alarm inside the window; passed safe date renders the urgent-recovery card (consolidating per W2).
4. **W4 — Task push + deep links + scene-phase flush.** Server: the H55 scheduler and `changeTaskPlan` write notification-intent documents (no FCM send added in this phase — sending requires deploy; the intent queue is the deployable unit and is exercised offline); payload schema `{taskId, resume: row|outcome|flow-step}`. Client: notification tap routing to the exact row/outcome (extends the Google-Sign-In-only URL handling at H45's cited sites); cold-start route persistence. **Scene-phase flush** for the newest in-flight flow write (H48 residual): `scenePhase` observer drains the queue H56 already maintains.
5. **W5 — Research posture contract.** Server `researchTask` output gains optional per-item `{posture: RULE_VERIFIED|ACCOUNT_OR_DECISION_VERIFIED|LABELED, source, date}` alongside the section-level fields (additive; old briefs render unchanged); client `TaskResearchModule` renders the quiet posture line. No prompt-engineering beyond the contract; content quality is Phase 3's research work.

## Audit gate (read-only at `e8d6133`; inventory items produce lists and bind, stop only on a contradicted design assumption)
1. **Inventory — every CTA site** (call/portal/website/mail/map buttons across task UI: TaskDetailView, FlowEngineView status/summary steps, movers chain, supplies, research module links). Assumption: each can route through `HandoffSession` without changing its action; contradicted if a CTA fires side effects before the persist point can run.
2. **Inventory — every row-render path** (Home cards, Tasks list, TaskRowHeader, grouping) and what each reads (`status`, `snoozedUntil`, contract fields). Assumption: menu + WAITING line + truthful copy can render from the mapper's existing decode with no per-row fetch; contradicted if any list row lacks access to the contract.
3. **Inventory — URL/notification entry points** (H45 sites: PeezyV1App, PeezyMainContainer, any `onOpenURL`/delegate). Assumption: a task deep-link route can be added without touching Google Sign-In handling; contradicted if routing is single-purpose by construction.
4. **Assertion (v2) —** W0's five action specifications are implementable with the Phase 1 validation/fingerprint/history/builder machinery and produce coherent status/contract pairs the rules suite can encode; contradicted if any transition cannot be expressed without weakening a Phase 1 invariant.
5. **Assertion —** notification-intent documents can be written by the scheduler/`changeTaskPlan` under the Phase 1 rules (server-only surface) and read offline in tests; contradicted if rules or index config must change in ways Phase 1's declarations don't cover.
6. **Assertion —** `researchTask`'s brief schema tolerates the additive per-item posture (persisted under `brief`; client decode additive per H3's mapper pattern).
7. **Assertion —** scene-phase flush can drain H56's queue without violating the pre-submit/terminal barriers (flush never runs during a locked submit window).
8. **Assertion —** test selection: the four Phase 1 unit classes plus the new Phase 2 classes are enumerable in `-only-testing`; UI/integration exclusions unchanged.

## Explicitly deferred (each with the assumption that keeps it safe)
- FCM send + deploy (H17/H43 block deploys; the intent queue is inert until deployed — nothing in Phase 2 reads it in production).
- Router shadow retirement + catalog reseed (Phase 3; W2's menu renders on shadowed rows too, via the same row surface — no dependency).
- Wallet UI, ADDRESS_UPDATE_LEDGER surface, household rosters UI (Phase 3/4; nothing in W1–W5 writes those surfaces).
- Delegation slot (hidden until fulfillment ops; support door only).
- Entry-specific outcome copy (Phase 3 data; W1 ships the component with the generic A4 variants).

## Acceptance
- A contracted WAITING row shows owner/expectation/trigger and both exits; "It happened" opens the action-keyed outcome question; every outcome writes a coherent status/contract pair; no new status writer (grep-verified against the Phase 1 inventory).
- A CTA tap persists the handoff before the external app opens (kill the app mid-handoff → relaunch resumes at the outcome question with context).
- The A8 menu works on contracted rows; "doesn't apply" is one tap on a row with no contradicting evidence and opens the resolver on one that has it; legacy rows are byte-identical (snapshot test).
- TaskRowHeader shows `visible_status_copy` when present and never a stale snooze date after a wake.
- A DEFERRED-to-event row wakes when the event document lands (offline scheduler test) and the woken row appears once in "Needs attention now" when its safe date has passed.
- A notification-intent document round-trips: written by the scheduler in the offline test, and a simulated tap on its payload routes to the exact row (unit-level routing test; no push sent).
- Backgrounding mid-flow loses zero queued writes (red-first test on the H48 residual); flush never fires inside a submit barrier.
- An old research brief renders unchanged; a new brief with per-item posture shows the quiet source line.
- Node, rules, and Swift suites green under the Phase 1 invocation discipline; Build 25 WIP hashes byte-identical; PEEZY_STATE regeneration owed at the end (H45, H46, H48, H52 truth changes).

## DO NOT CHANGE
Build 25 WIP paths; entitlement/validateSubscription; `TaskFlowRouter` shadows; catalog/flow JSON; firestore.rules and indexes except the notification-intent surface if gate item 5 shows Phase 1's declarations already cover it (prefer no rules diff; a required rules change returns to the architect); `spawnTasks.js`; the Phase 1 barriers' semantics; `PEEZY_STATE.md`.

## Delegation prompt
```
Run the Phase 2 plan through the codex adversarial review loop, then execute.

1. Project root ~/Desktop/Peezy 4.0/. Read PEEZY_STATE.md first; it outranks this plan. The plan is PHASE2_PLAN.md at the root.
2. Run the audit gate (read-only, file:line). Items 1-3 are inventories: produce the exhaustive list, bind the executable spec to it, continue; stop only on a contradicted design assumption or a CONTRADICTED assertion (4-8). Report the gate table at the top of PHASE2_BUILD.md either way.
3. Write the executable spec per workstream (complete code, red-first tests), review with codex to convergence, execute in an isolated worktree, verify (simulator build + the named-class test envelope with UI skip and no test plan; offline Node and rules suites), diff-review every touched file, merge back, write PHASE2_BUILD.md in the PHASE1_BUILD.md format.
4. No seeds, no deploys, no production-connected tests, no FCM sends. Do not touch the Build 25 WIP. If a workstream needs a server change outside the notification-intent documents, stop and report instead of expanding scope. Stop at the commit gate and show me the diff stat.

Do not ask questions — investigate and execute.
```
