# PHASE0_VERIFICATION — architect's check of PHASE0_BUILD.md against spec (2026-08-26)

**Verdict: ACCEPTED as Phase 0.** Both blockers named in BUILD_BRIDGE §1d/§2 are implemented as specified, protocol was honored (no deploy, no production-connected tests, isolated worktree, human commit gate), and the audit answered all eight checklist questions with file:line evidence. Committed as `e5a40e8` on main per the session transcript (the report predates the commit). Nothing is deployed; H43 still blocks.

## Spec conformance
| BUILD_BRIDGE requirement | Report evidence | Disposition |
|---|---|---|
| H7 transactional spawn guard, deterministic task identities | all-`create()` mixed batch incl. the token doc; `ALREADY_EXISTS` → fingerprint-checked replay; `t1_sha256(token|ordinal)` IDs; boundary validation pre-read | **Met.** Deterministic IDs are versioned (`t1_`), so Phase 1's canonical-key change can re-key without collision. |
| H8 awaited/propagating status writes before removal/credit | `claimNudgeTerminal` transaction nonterminal→terminal; single-flight state machine; Dismissed never credits; Converted credits once per opId; `.failed` blocks the opposite action; `.alreadyTerminal(other)` removes without credit | **Met.** Stronger than the bridge asked: same-choice-only retry and cross-instance answer detection. |
| Audit item 7 — subject-aware keys "in the same change" | Enumerated touchpoints; canonical key deliberately not built | **Accepted as Phase 1 scope.** Phase 0 was defined as "no visible features"; the key change touches catalog rowGeneration, FlowDefinition expansion, and rules — Phase 1 territory. The enumeration is the input Phase 1 needs. |
| PEEZY_STATE §4 addendum — no production-connected tests | DEBUG-only XCTest guard at three startup sites; simulator-only runs; Node suites offline | **Met.** |
| No live seeds/deploys | none; deploy-time instructions recorded | **Met.** |

## Discrepancies and notes (none blocking)
1. Part A labels Item 7 "evidence complete" in the heading and "CONTRADICTED" in the gate arbitration — cosmetic; the arbitration text explains it.
2. Merged-tree Node run counted 5 tests from the untracked narration WIP (132 vs 127) — harmless, but the WIP's tests are now exercised by any full run; note for the Build 25 session.
3. Review note 2 (fake not rules-aware for auth-switch) is the only test-backlog item that hides a *production-behavior* difference; the safer direction holds, but the Phase 1 rules pass (H21/R4) should add a rules-aware test.

## Phase 1 inputs the audit produced (carry into the Phase 1 spec)
- **Snooze is time-only with no trigger kind, payload, or evaluator** (Item 2 CONTRADICTED). §A's `DEFERRED (date or event)` and the scheduled-trigger function (BUILD_BRIDGE §1c) are **new construction**, not an extension. Phase 1 must add a `next_trigger {kind: date|event, payload}` on the disposition contract and the single cron export that evaluates it.
- **No push resumes at a step** (Item 6 CONTRADICTED). Phase 2's task-notification deep links are new routing; `flowPath` restore exists only inside an opened task.
- **researchTask confidence is section-level** (`SPECIFIC` / `SAFE GENERAL`), `degraded` is whole-brief. §A A5's per-claim postures (`RULE_VERIFIED` / `ACCOUNT_OR_DECISION_VERIFIED`) need an output-contract extension: per-item `posture` + `source`.
- **`pending` / `matching_in_progress` are retired human-handoff terminals with no live consumer conflict** — the BUILD_BRIDGE rename-in-place to `WAITING_ON_EXTERNAL` / `SUPPORT_ACTIVE` is clear on the client; deployed external workers unknown.
- **Mapper tolerates the additive contract field** (Item 8) — the `dispositionContract` map can ship without a mapper fork.
- **Router shadows to retire:** exactly two same-ID shadows, `update_auto_insurance` → `HandleAutoInsuranceFlow` and `setup_internet` → `SetupInternetFlow`. Entry 8's auto aliasing (§8.1) therefore includes retiring a bespoke Swift flow, not just catalog rows; retiring them exposes two more spawn terminals to the (now-guarded) spawnTasks surface. Add to the Phase 3 reseed checklist.
- **Per-row flow state survives backgrounding except the newest in-flight write** (no scene-phase flush) — a small Phase 2 item for `FlowExitControl`.

## PEEZY_STATE regeneration — required deltas (full evidence pass owed, per protocol; do not patch)
- H7 → SUPPORTED-LOCAL / DEPLOYED-UNKNOWN: race closed in source at `e5a40e8`; deployed revision retains it until a human deploy after H43. Deploy instruction: drain old revision ≥15s.
- H8 → SUPPORTED-LOCAL: nudge status persists transactionally before advancement/credit; `.failed` visible and retryable.
- **New row — financial flow zero-spawn:** row-expanded `{rowId}.provider` never matches `perSelectionFrom: "provider"` / exact `answers["provider"]` lookups [FlowDefinition.swift:184-207; flowDefinitionsData.json:1107-1142; FlowEngineView.swift:695-709]; existing tests cover only the unexpanded step. Severity HIGH (silent under-generation of institution tasks). Safe next action: row-aware lookup + a row-expanded test, in Phase 1 with the subject-aware key change.
- **New rows (architecture facts):** snooze time-only (Item 2 evidence); push routing support-only (Item 6); research confidence section-level (Item 4); two same-ID router shadows (Item 5, replaces H6/H11's general "bespoke shadows" with the exact list).
- R4: `spawnTokens` owner-writable under the recursive grant — attach to H21's row as an additional consequence.
- H38: hosted test target now guarded in DEBUG; production-connected test risk reduced but the credential/identifier debt in that row is unchanged.
- Snapshot commit for the regeneration: `e5a40e8`. Baseline still dirty with inventory/narration WIP — the regeneration must record it as such, not include it.

## BUILD_BRIDGE deltas
- §1a "DEFERRED — add trigger (date or event), today snooze is time-only — needs audit" → **audited: time-only, new construction** (above).
- §1c "Scheduled triggers: NEW" → confirmed; add "evaluator for `next_trigger.kind = event` consumes A11a events."
- §1d Phase 0 blockers → **done locally, undeployed**; H27 and H21 remain the pre-reseed items; add the financial zero-spawn bug and the two router shadows to the Phase 1 list.
- §3 audit checklist → all eight answered; deliverable of the code session (Phase 0 spec) complete; **Phase 1 spec is next**, with §A v3.3 A11a as the event vocabulary the scheduled-trigger function evaluates.
