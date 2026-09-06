# Spec 04 — Flow Engine + Catalog v2 — execution plan (session 2026-07-25)

Governing docs: peezy-build-spec-04.md, peezy-execution-protocol.md, peezy-conventions-v2.md,
peezy-v1-architecture.md (§2 §3 §9b §10), peezy-v1-catalog-sheet.md.
CORE tier A–C: per-phase PHASE_MANIFEST (incl. read sites) → build → xcodebuild → commit →
fresh-context validator (bounded retry 2). PERIPHERY D–F. Deploys: ONE batch after Phase C
(catalog v2 reseed + flowDefinitions seed + functions edits), nothing else.

## Pre-flight findings (evidence: this session's reads)

- Flow census: 47 files in Tasks/Task Cards. 38 are template instances across exactly 3 families:
  Type 1 (20 × 88 lines: title→info→status; config = taskTitle/workflowId/icon/bodyText),
  Type 2 (11 × ~405: 13-card branching manage-provider; per-flow strings + 3-variant find-summary
  keyed on handling_cancel/handling_find), Type 3 (4 × 246 access: decision→confirmAddr→confirmDate→
  summary | tip→status; 3 × 230 utilities: same minus confirmDate). All deltas captured via diff —
  every config string in hand. The spec's "39 templated" over-counts by one: 47 − 8 customs
  (insurance ×2, FindMovers, FindCleaners, SetupInternet, SellItems, RemoveItems, RentTruck) −
  ScanInventory (bespoke, kept) = 38. [NEEDS CLARIFICATION marker carried in phase report; 38 is
  the code-verified count.]
- Kit usage by the 38: TitleCard, InfoCard, StatusCard, DecisionCard, TilesCard-single-2 (via
  Select2), BusinessSearchCard, ConfirmAddressCard, ConfirmDateCard, SummaryCard. Nothing else
  (FillBar/CompactTiles/Multi*/Select3-5 are custom-flow-only). componentKind enum capped there.
- One conditional transition exists (ManageBank family): find-decision "self" routes to
  find-summary iff handling_cancel=peezy else find-tip → branch model needs {value, when?, next}.
- Off-app tasks (12) carry NO workflowId in catalog; routing today falls back to lowercased
  taskId (PeezyHomeViewModel.newFlowId :115-122). Data-driven router must keep this fallback.
- MANAGE_GOLF is in catalog with workflowId manage_golf but has NO router case and NO Swift flow —
  it is a live unroutable task today (EmptyView → spinner). Dies in Phase B merge (MEMBERSHIPS).
- Presentation funnel is single: PeezyHomeView fullScreenCover :129-149. Tasks tab routes through
  focusedTask → container switches to Home tab. One integration point for FlowEngineView.
- submitWorkflowAnswers (deployed): guidance → marks task Completed; vendor → workflowSubmissions
  ('pending_matching') + task status 'matching_in_progress' (getWorkflowQualifying.js:254).
  index.js:225 queries BOTH snake strings on tasks; 'pending_matching' never lands on task docs →
  the query fix. Spec C.4 names `pending_matching` as the client case but the string actually
  written to task docs is `matching_in_progress` — implement per reality, cite in report.
- DEPLOYED Firestore rules fetched read-only via Rules REST API: default-deny; NO flowDefinitions
  read; rules deploys are Adam-gated (waitlist reconciliation). → Client cannot read a new
  flowDefinitions collection directly. Bounded resolution [NEEDS CLARIFICATION, reversible]:
  definitions live in Firestore `flowDefinitions` (seeded from flowDefinitionsData.json per spec);
  client fetches THROUGH the already-deployed getWorkflowQualifying callable (Q11 "adopt the
  orphaned server system — becomes the definition source"), extended with a Firestore-first
  lookup. Ships inside the sanctioned Phase B/C deploy batch. Swap to direct reads is a one-
  function change after Adam's rules deploy.
- TaskConditionParser: Bool→"Yes"/"No", nil matches ["nil",""], multi-select arrays, ">=N".
  newAddressPending/moveDatePending are Bools in assessment data; hasDeclutter/wantToSell exist
  (Spec 02); storageNeeded does not exist yet (STORAGE_NEED card writes it).
- TaskGenerationService is one-shot at assessment completion; batch.setData would RESET existing
  docs on rerun → dose cards (DECLUTTER_INTENT/STORAGE_NEED) need an add-only incremental
  generation (skip existing doc ids), never a full rerun.
- Catalog v2 arithmetic: 56 − 24 removed (23 merged sources + BUY_CLEANING_SUPPLIES absorbed)
  + 9 merge targets + 5 adds (ADD_NEW_ADDRESS, CONFIRM_MOVE_DATE, DECLUTTER_INTENT, STORAGE_NEED,
  STORAGE_UNIT) = 46 rows. Sheet said ~40; exact number stated per acceptance criterion.
- Xcode project uses PBXFileSystemSynchronizedRootGroup → file create/delete needs no pbxproj edit.

## Phase A: FlowDefinition + FlowEngine (CORE) — BUILT + COMMITTED (a6c04cb), VALIDATOR DEFERRED

- [ ] PHASE_MANIFEST written (edit + read sites)
- [ ] FlowDefinition.swift — Codable model: FlowDefinition{workflowId, taskTitle, steps},
      FlowStep{id, kind, config fields, next, branches[{value, when?, next}], stage?},
      StepKind ∈ {title, info, decision, select, businessSearch, confirmAddress, confirmDate,
      summary, status}; SummaryVariant{when, body}; + FlowDefinitionStore (in-memory cache;
      callable fetch lands here, harness injects local JSON in DEBUG)
- [ ] flowDefinitionsData.json — 38 definitions transcribed from the Swift flows (strings/icons/
      options byte-exact from this session's diffs); WORKFLOW_QUALIFYING folded in as the
      documented seed for Phase B's merged-flow definitions
- [ ] FlowEngineView.swift — renders steps via the kit verbatim; per-step answer persistence to
      task doc (flowAnswers.{stepId}, flowPath) via TaskActionService; resume from persisted path;
      stage transitions via setStage where a step declares one; submission via WorkflowService
      unchanged; flow-state cleared on terminal (summary submit / status action); a11y ids
      flow.<workflowId>.<stepId>
- [ ] TaskActionService — writeFlowProgress/clearFlowState (same direct-write pattern as setStage)
- [ ] FlowEngineHarness.swift (DEBUG) + 3-line AppRootView hook — env-driven: FLOW_DEFS_PATH
      (host JSON path) + FLOW_HARNESS_WORKFLOW; drives Phase A validation before router lands
- [x] All build items above complete; build green first attempt; commit a6c04cb
- [x] Writer smoke evidence: manage_bank title/action/cancel-decision/business-search/
      conditional-branch-to-find_summary with cancelOnly bodyVariant (AX dumps);
      setup_utilities persistence {flowPath, flowAnswers, stage:capture} + kill/relaunch
      resume at confirmed_address (Firestore reads); fixture restored pristine
- [x] VALIDATOR PASS 3/3 (fresh-context, 141 evidence files in scratchpad/validation_A/):
      parity — 26 screen pairs across 5 flows (both manage_bank branches) pixel-identical
      after masking status bar/caret; resume — kill/relaunch landed on current_business with
      the variant-proving answer restored; payload — old vs new manage_vet submissions
      byte-identical on canonicalized answers (2 expected admin SMS). Findings: (1)
      harness-only SIGABRT — setStage with empty taskId → uncatchable Firestore ObjC
      exception (FIXED, 45d3197); (2) businessSearch dropdown never renders visually in
      EITHER binary — pre-existing kit bug, spun off as its own task; (3) engine leaves
      stage:"capture" on the doc post-submit (old wrote none) — stage-model nuance for
      SESSION_NOTES; (4) first validator attempt died on the session limit mid-fixture —
      3 orphan docs found + cleaned. Fixture verified pristine post-run.

## Build status (writer side, evidence in commits + this session)

- Phase B — BUILT + COMMITTED (16217a9). Catalog v2 = 46 rows (32 kept + 9 merges + 5 adds;
  reweights verified already live). Definitions v2 = 25. Engine rows: forEachRow expansion
  (2 bank taps → bank_credit_union_1/2 instances walked live in-sim), requiresRow skip
  (DMV registration aliased away with no rows — walked live), FieldPath keeps dotted answer
  keys flat (Firestore evidence). In-app flows built. Incremental add-only generation built.
- Phase C — BUILT + COMMITTED (ffbbc78) + DEPLOY BATCH DONE. Router = thin resolver;
  38 screens + TaskFlowDismissButton + newFlowIds + skipCurrentTask + rowIdentity fossil
  deleted (−8,164 lines). TaskStatus.matchingInProgress added (the string actually written;
  spec's pending_matching never lands on task docs — discrepancy cited). index.js:225 drops
  phantom 'pending_matching'. DEPLOYED (sanctioned batch): getWorkflowQualifying +
  submitWorkflowAnswers + peezyRespond (targeted — full deploy blocked on orphaned cloud
  resetInventory function, flagged for Adam, NOT deleted); catalog v2 reseed (46, no ghosts);
  flowDefinitions seed (25, full coverage). Post-deploy live walk: schedule_time_off_work
  renders via engine from Firestore definition through the real app path; scan_inventory
  bespoke via CaptureRegistry; unknown id → coming-right-up card (verified pre-deploy).
- Phase D — BUILT + COMMITTED (a27694f). PaywallPolicy + PaywallGateSheet (the one
  sanctioned second call site); gates: engine concierge submissions + FindMovers/FindCleaners
  BOOK submissions.
- Phase E — BUILT + COMMITTED (11e62e2). Dose freeze verified live: users/{uid}.dailyDose =
  {date 2026-07-25, 4 taskIds} written on first load. Reflect-backs: sequence-relative beat
  resolver + banner (validator screenshots pending).

## Validation ledger

- Phase A validator: DEFERRED (subagent session limit; resets 12:40 CT). Runs FIRST
  (needs the pre-retake fixture + old binary from a6c04cb for side-by-sides).
- Phases B+C+D+E validator: runs SECOND — assessment retake IS the spec's migration plan;
  covers v2 generation evidence, full-catalog walk, 2-bank rows, ADD_NEW_ADDRESS distance
  recompute, dose-freeze stability under mid-day insert, banners, paywall gates.
- Cleanup done this session: 3 validator-orphan task docs (ARRANGE_PARKING_OLD, MANAGE_BANK,
  UPDATE_INVESTMENT) deleted — fixture back to 16 before the retake.

## Phase B: Catalog v2 + row-generation (CORE) — original plan (superseded by status above)

Merges per sheet (9 targets), conditions/urgencies per sheet notes; BOOK_CLEANERS 25→55,
TRANSFER_PHARMACY 55→75; adds ADD_NEW_ADDRESS/CONFIRM_MOVE_DATE (in-app flows reusing Settings
sheets), DECLUTTER_INTENT/STORAGE_NEED one-tap dose cards (write keys + add-only incremental
generation), STORAGE_UNIT (thin, conditions storageNeeded=Yes); REMOVE_ITEMS/SELL_ITEMS stay on
wantToSell; row-generation for FINANCIAL_ACCOUNTS/MEDICAL_RECORDS/MEMBERSHIPS as repeatable step
group (engine extension, count-expanded from Spec 02 count keys); merged-flow definitions authored
into flowDefinitionsData.json (seeded from Swift merge sources + WORKFLOW_QUALIFYING + mini-
assessment question data); seedTaskCatalog.js gains flowDefinitions seeding + CANCEL_YOGA
spot-check fix; getWorkflowQualifying.js Firestore-first definition lookup. NO deploy yet.

## Phase C: Router replacement (CORE) — todo (own manifest at start)

Data-driven resolution workflowId→definition→FlowEngineView; explicit map for 8 customs + 4 new
in-app tasks; ScanInventory via CaptureKind registry shim; DELETE 38 templated files +
TaskFlowDismissButton + 47-case switch body + newFlowIds + skipCurrentTask + rowIdentity fossil;
coming-right-up card for unroutable; TaskStatus snake-case case (matching_in_progress — the string
actually written; cite discrepancy); index.js:225 query fix. THEN the single deploy batch:
functions deploy + catalog v2 reseed + flowDefinitions seed. Validator walks EVERY catalog task.

## Phase D: Paywall gate (c) (PERIPHERY) — todo

PaywallPolicy.swift (requiresSubscription(for:)); gates BOOK-stage/kit/concierge; PaywallGateView
second call site (manifest-sanctioned); soft post-assessment offer untouched.

## Phase E: Dose freeze + reflect-backs (PERIPHERY) — todo

DailyDoseEngine freeze: once/calendar-day {date, taskIds} persisted on user doc; served frozen;
done-for-today on frozen-set completion. Reflect-back banners (mechanism (a), LOCKED copy) after
pets/kids/address-pair/services questions.

## Phase F: SESSION_NOTES + doc sync (PERIPHERY) — todo

CLAUDE.md corrected-facts update (catalog count, router, deleted files); conventions edits
proposal per protocol §6.

## Review

Six phases executed under the execution protocol: CORE A–C as separate commits with per-phase
manifests and hub-diff-walkable histories (a6c04cb, 16217a9, ffbbc78 + follow-up 45d3197),
PERIPHERY D–F (a27694f, 11e62e2, + this close). ONE deploy batch, exactly as sanctioned:
targeted functions deploy (getWorkflowQualifying + submitWorkflowAnswers + peezyRespond;
full deploy aborts on the orphaned cloud resetInventory — flagged, not deleted) + catalog v2
reseed (46, ghost-check clean) + flowDefinitions seed (25, coverage-check clean).

Validation: two fresh-context validators, zero bounded-retry cycles.
- Phase A: PASS 3/3 (parity 26 screen pairs / resume / payload byte-parity), 141 evidence files.
- Phases B–E: 13 PASS, 1 ENVIRONMENT-LIMITED (subscribed pass-through needs an Xcode-scheme
  launch for StoreKit test config; code path documented), 0 FAIL, 101 evidence files.
  46/46 catalog rows route; dose froze at 4 through a urgency-97 insert; three banners
  rendered + the address banner correctly absent under newAddressPending; both paywall
  gates fired with live prices and zero submissions leaked (zero admin SMS in the B–E run;
  2 expected SMS in the A payload test).

End state: test bot on the fresh catalog-v2 fixture (27 tasks; ADD_NEW_ADDRESS Completed by
design — its completion recomputed distance to 561.7 mi / interstate). Defect found by
validation fixed in-session (setStage empty-taskId SIGABRT). Two pre-existing bugs spun off
as task chips (businessSearch dropdown invisible; retake doesn't reset dose counters).

## SESSION_NOTES (protocol §6)

What the spec got wrong / underspecified:
1. "39 templated flows" — code-verified 38 (47 − 8 customs − ScanInventory). No harm; count
   corrected in conventions.
2. Phase C.4 named the client case `pending_matching`; the string actually written to task
   docs is `matching_in_progress` (pending_matching is workflowSubmissions-only). Built per
   reality, cited in the commit and conventions. Spec-author rule: name the WRITE SITE, not
   the string, when reconciling statuses.
3. The spec assumed the client can read a new `flowDefinitions` collection; deployed rules
   are default-deny and rules deploys are Adam-gated. Resolved inside Q11's own decision:
   getWorkflowQualifying serves the definitions (Firestore-first lookup). Spec-author rule:
   any new client-read collection needs a rules line-item or a callable transport decision
   IN the spec.
4. Phase A's acceptance criteria (side-by-sides, resume, payload parity) predate the router —
   nothing routes to the engine in Phase A. Filled with an env-gated DEBUG harness
   (FlowEngineHarness + a 3-line AppRootView hook) that later phases kept using. Spec-author
   rule: when a phase builds an engine before its router, the spec should name the
   validation harness up front.
5. "Deploys: the Phase B/C batch only" collided with `firebase deploy --only functions`
   aborting on the orphaned resetInventory function — targeted deploy was the escape.
6. Validator-brief errata worth keeping: account counts raise via the "+" stepper (not
   re-taps); FindMovers' Book control is the summary's "Done" button.

What surprised us:
- A sync host-path file read from a sim process freezes FIRST RENDER (TCC) — white screen,
  EMPTY AX tree. Container-staged files + async reads are mandatory harness hygiene.
- Firestore ObjC exceptions sail through Swift catch: empty document path = SIGABRT.
- Subagent session limits can kill a validator mid-fixture-mutation; debris audit
  (rounded .000 createdAt copies) is now part of the recipe.
- The kit's businessSearch dropdown has NEVER rendered visually (zero-height ScrollView);
  free-text + Continue is what every user has actually been doing.
- StoreKit test config is scheme-scoped: simctl-launched builds can't purchase, so
  subscribed-path criteria need an Xcode-side check.

Proposed doc edits: all applied this session (CLAUDE.md corrected facts §3–5, key files;
conventions "Corrections from Spec 04 run" + open items). Decisions for Adam surfaced in
open items: orphaned resetInventory deletion; rules reconciliation (deployed text captured);
Xcode-side subscribed-path verification before submission.

# Spec 05 Close - Pricing Engine + Movers Vertical

## Review

Phases were committed independently under the execution protocol:

- Phase 0 `5b06b5a`: rules/flow-definition transport and housekeeping batch.
- Phase A `51f6932`: vendor schema, placeholder mover rate cards, and seed path.
- Phase B `e790088`: pure pricing engine, centralized calibration constants, scope factory,
  standalone tests, and the five-scenario DEBUG harness.
- Phase C `feabc58`: generic comparison card plus the complete mover capture/refinement/
  comparison/paywall/submission/confirmation spine.
- Phase D `6bf364c`: storage and bedroom tier-3 inputs removed from the assessment sequence.

Phase C terminal evidence is the Firestore workflowSubmissions document plus the function log
`NOTIFICATION_WEBHOOK_URL not configured — vendor submission not notified`. The accepted
submission contains all six booking sections (`identity`, `scope`, `estimate`, `chosen_vendor`,
`requested_window`, `notes`); `MoversBookingPayloadTests` passed, and the app build succeeded.
Webhook delivery was deliberately not exercised because the fulfillment target is being
reselected.

Phase D validation passed `AssessmentTier3MigrationTests`. Its maximal branch profile contains
26 steps, excludes current/new bedrooms plus the storage trio, retains current/new floor access,
hasVehicles, and moveDateType, and leaves the generated task set unchanged for the control
profile. A read-only catalog audit found zero condition keys among the five migrated keys.

### Pricing calibration output

Generated from `PricingCalibrationHarness.report()` during Phase E:

```text
SCENARIO 1: 1BR local walkup
  scope: 480 cu ft | 18 min drive | inventoryScan | packed
  2-crew: load 4.1h, total 4.4h, billable 4.4h, $767
  3-crew: load 2.9h, total 3.2h, billable 3.2h, $721
  4-crew: load 2.3h, total 2.6h, billable 2.6h, $701
  selected: 4-crew, 2.6h, $617–$785
  why: 4 movers finishes 0.6h sooner and costs less.
  disclosures: none

SCENARIO 2: 2BR local elevator, unreserved
  scope: 900 cu ft | 28 min drive | inventoryScan | unpacked
  2-crew: load 8.3h, total 8.8h, billable 8.8h, $1827
  3-crew: load 5.6h, total 6.1h, billable 6.1h, $1635
  4-crew: load 4.2h, total 4.7h, billable 4.7h, $1512
  selected: 4-crew, 4.7h, $1331–$1693
  why: 4 movers finishes 1.4h sooner and costs less.
  disclosures: Unpacked boxes; Unreserved elevator at origin

SCENARIO 3: 3BR scan with storage and piano
  scope: 1420 cu ft | 42 min drive | inventoryScan | packed
  2-crew: load 12.6h, total 13.3h, billable 13.3h, $2675
  3-crew: load 9.0h, total 9.7h, billable 9.7h, $2501
  4-crew: load 7.3h, total 8.0h, billable 8.0h, $2456
  selected: 4-crew, 8.0h, $2161–$2751
  why: 4 movers finishes 1.7h sooner and costs less.
  disclosures: Long carry at destination

SCENARIO 4: 3BR bedrooms fallback, access unknown
  scope: 1275 cu ft | 35 min drive | bedroomsFallback | unknown
  2-crew: load 10.4h, total 11.0h, billable 11.0h, $1896
  3-crew: load 6.8h, total 7.4h, billable 7.4h, $1648
  4-crew: load 5.1h, total 5.7h, billable 5.7h, $1521
  selected: 4-crew, 5.7h, $882–$2160
  why: 4 movers finishes 1.7h sooner and costs less.
  disclosures: Undisclosed stairs or access

SCENARIO 5: 4BR interstate
  scope: 2100 cu ft | 540 min drive | inventoryScan | packed
  2-crew: load 18.4h, total 27.4h, billable 27.4h, $5333
  3-crew: load 13.0h, total 22.0h, billable 22.0h, $5459
  4-crew: load 10.4h, total 19.4h, billable 19.4h, $5716
  selected: 2-crew, 27.4h, $4693–$5973
  why: 2 movers is the lowest total; 4 movers finishes 8.0h sooner but costs more.
  disclosures: Long carry at origin
```

The values above are generated from the current LOCKED-pending-calibration constants. They are
the field-calibration handoff for Adam's review.

## SESSION_NOTES (protocol §6)

What the spec got wrong or underspecified:

1. Phase C required a live webhook, but no notification target is configured while fulfillment
   infrastructure is being reselected. The accepted terminal evidence is the durable Firestore
   submission, complete payload, and explicit unconfigured-webhook log.
2. WorkflowService's answer contract is `[String: [String]]`; the mover serializer therefore
   expresses each of the six booking sections through string-valued maps and JSON strings where
   nested values are required.
3. The Phase D count is branch-dependent. The maximal all-branches profile is 26 steps after the
   five migrated inputs are removed; there is no single fixed count for every assessment path.
4. Phase 0's remote resetInventory deletion could not be independently rechecked at closeout:
   `firebase functions:list` failed because the local Firebase credentials require reauthentication.

What surprised us:

- The submission path preserves a complete Firestore audit record before notification delivery,
  so an absent webhook target is visible as a distinct terminal log state rather than payload loss.
- The control catalog has no conditions on any of the five tier-3 mover refinement keys, making
  the Phase D generation-parity result directly auditable from taskCatalogData.json.

Doc edits applied in Phase E: CLAUDE.md now records direct flow-definition reads, vendor/pricing/
mover-spine ownership, and the current submission contract; peezy-conventions-v2.md records the
Spec 05 corrections, Phase C evidence boundary, Phase D migration facts, and current open items.

# Pricing Calibration Chip — 2026-07-26

## SESSION_NOTES (protocol §6)

What the chip got wrong or underspecified:

1. `AGENTS.md` is absent from the repository. Adam acknowledged the absence and directed this
   session to use `CLAUDE.md` as the equivalent repository instruction source.
2. The chip named `functions/index.js` as the submitWorkflowAnswers implementation site. That
   file only imports and exports the callable; the implementation is in
   `functions/getWorkflowQualifying.js`, so the direct Twilio replacement belongs there.
3. The chip said inventory categories already carry specialty flags. `InventoryItem.category`
   remains generic; `MoveScopeFactory` currently derives specialty flags from normalized item
   names. The starter mappings were extended for treadmill and marble tops without changing the
   frozen Inventory/Camera area.
4. The initial quote-request SMS wording inherited booking vendor/estimate fields even though a
   concierge request has neither. Adam resolved it to
   `PEEZY QUOTE REQ: {name}, {originCity}→{destCity}, {date}.` Booking wording is unchanged.

Environment/evidence decisions:

- `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, and `TWILIO_FROM_NUMBER` are present in the
  read-only functions/.env; `ADAM_NOTIFY_NUMBER` is absent. Per the confirmed terminal-evidence
  path, the single isolated test submission must prove Firestore payload completeness and the
  deployed function log `SMS notify not configured`.
- Open launch item: configure `ADAM_NOTIFY_NUMBER`, then verify one live booking or quote-request
  SMS before launch.

---

# V9 manifest execution (session 2026-09-02) — V9_INSTRUCTION.md via /codex-consensus:codex-review

Governing: V9_INSTRUCTION.md (Rules 1–8), PEEZY_STATE.md §4, ~/Downloads/peezy-reports/V8_DIFF_REVIEW.md (data). Reviewer: Codex gpt-5.6-sol, read-only, one persistent thread. Repo edits: PHASE2_REPLACEMENT_MANIFEST_v9.md only (plus this file). No implementation file touched.

- [x] Step 0: codex-cli 0.147.0, ChatGPT login, gpt-5.6-sol OK; v8 sha256 12ea8ee1 verified; v9 copied from v8
- [x] Item 1 (V8-01/V7-02): `capability_invalid` detachReason; nonstaged member closure (restored v7 §11:1311); terminal mapping in §8.9.1; notProven entry restored in §8.9.5 (v7 §8:991); crash-at-every-phase fixture in §8.9.6
- [x] Item 2 (V8-02): §6.6:770 order clause + "after the gate clears" sentence → pointers
- [x] Item 3 (V8-03/V7-12): absence_retention gets `destinationOrdinals` (exactly one); partition sentence rewritten; fixture extended
- [x] Item 4 (V8-04..07): §8:1001, §8:1005, §11:1510, §11:1522 → pointers; rules relocated into §8.9.3/§8.9.1
- [x] Item 4 sweep: §8:973, §11:1418, §11.1:1589, §11.5 rows 1773/1775/1777/1784, §12.2:1847, §14.4 → pointers/removed
- [x] Rule 5: regenerate §8.9.7 from final v9 text with grep keys; mechanical absence check
- [x] Item 5: confirm V7-03, V7-11, V7-12, v8-Item 1, v8-Item 6 closed; cite §:line
- [x] Rule 7: recount totals; rerun §13 gate items 1–6 (scripts); §14 → v9 execution report
- [x] Rule 8: none expected (restorations are deleted-v7 text, not new design) — record explicitly
- [x] Outputs 1–7 in v9 §14 + ~/Downloads/peezy-reports/V9_DIFF_REVIEW.md Appendix B (final sha256 a064bc6803f2ac416e1e1d35cb7462a24d0f94d6d95697dd056ee896b1344fc9); report to ~/Downloads/peezy-reports/V9_DIFF_REVIEW.md + log
- [x] Codex round 1 (thread 01a0636e…): ITERATE, 5 P1 + 1 P2 (V9-01..06); all fixed (order deferral to §8.9.4, §11:1541/§11.5:1803 pointers, §14 meta-only rewrite, marker/ledger nits); round-2 input sha256 a064bc6803f2ac416e1e1d35cb7462a24d0f94d6d95697dd056ee896b1344fc9
- [x] Codex round 2 (same thread, read-only): APPROVE — 16/16 CLOSED, 0 P1/P2, V9-01..06 all ADDRESSED; 2 of 3 rounds, 2 of 6 chain budget

## Review (v9 close-out)
- Delivered: PHASE2_REPLACEMENT_MANIFEST_v9.md (uncommitted) sha256 a064bc68…44fc9; report ~/Downloads/peezy-reports/V9_DIFF_REVIEW.md; log …/V9_DIFF_REVIEW-log.md; tooling …/v9-tools/.
- Lessons: (1) the v9 execution report must be meta-only — Sol treats any lifecycle restatement in §14 as a Rule 4 hit; (2) never sharpen an order between §8.9.1 and §8.9.4 in prose — defer to the subsection that owns it; (3) a residual clause ("retains durable state") next to a pointer still counts as outside authority under "replace wins".
- Owner next steps: commit v9 with hash; update PEEZY_STATE §4 register to v9; §13 item 7 whole-manifest passes before applying to the spec.

---

# Phase 2 handoff recovery + S1 brief (session 2026-09-02, local Mac)

Context: the Claude Code on the web session cloned GitHub (04c38c9) and could not see the 15 unpushed local commits or ~/Downloads. The block it handed Adam expected ~/Downloads/S1_BRIEF.md, which never existed on this Mac, so briefs/ stayed empty and phase2/inputs was never pushed. Commits c9e14b9 and 6ac2ea4 named files that were never staged.

- [x] Commit stranded artifacts (0673d0c): docs/plans/PHASE2_CONTRACT.md, PHASE2_WORKFLOW_v2.md, PHASE2_REPLACEMENT_MANIFEST_v9.md (sha256 a064bc68), V9_INSTRUCTION.md, V9_DIFF_REVIEW.md (copied from ~/Downloads/peezy-reports, V7/V8 pattern), tasks/todo.md, tasks/lessons.md
- [x] C7 pins re-verified against the working tree: PeezySettingsView whole-file 419055c9; RetakeAssessmentCoordinator closure slice lines 89–99 with next line `operationStore: store,`; InventorySessionManager exactly six `Firestore.firestore()`
- [x] Read-only S1 audit (subagent): no StartupBarrier/DurableStore/FirestoreRuntimeOwner/epoch code exists; 77 `Firestore.firestore()` sites in 36 files (S1 list = 15 sites in 14 files + 6 in InventorySessionManager; PaywallGateView has none, it is Functions-only); TaskPlanService is a struct with an injectable `Callable` closure and no account-deletion type; no Swift emulator config, functions tests run from explicit `node --test` file lists; rules tests need FIRESTORE_EMULATOR_HOST
- [x] briefs/S1_BRIEF.md drafted from manifest v9 + contract per the PHASE2_WORKFLOW_v2 template, every path/test/hash cited; PHASE_MANIFEST gains `briefs/*`
- [ ] Owner decisions before S1 starts: (1) contract C7:287 says Settings file-minus-deleteAccount is identical after patch, manifest §12.2:1866 normalizes one runtime-provider line, and line 833 holds a `Firestore.firestore()` outside the slice; (2) S1's falsifiers live in DurableStoreRecoveryTests.swift (manifest: S4 creates) and TaskPlanDispositionTests.swift (spec v5: S2 creates), so either S1 creates them with its families or S1's done criterion is compile + static gates; (3) push main (16 ahead of origin)?
- [ ] S1 execution after go-ahead: DurableStoreReadiness.swift seams → TaskPlanService `ResetOperationRegistry` + `AccountDeletionRemoteProviding` transport → RetakeAssessmentCoordinator / AssessmentDataManager / UserKnowledgeService / DailyDoseEngine epoch stamps → Firestore-runtime substitution (15 + 6 sites) → firestore.rules first pass + rules tests → red/green falsifiers → xcodebuild → static gates (rg, six-substitution diff, C7 hashes) → commit

## Review
- Delivered: commit 0673d0c (7 files, 3,390 lines); briefs/S1_BRIEF.md; PHASE_MANIFEST `briefs/*`; lessons entry on stranded commits and cloud handoff.
- Not done: S1 implementation, blocked on the three owner decisions above.

---

# S1 execution (session 2026-09-02, started after owner decisions 1–4)

Governing: briefs/S1_BRIEF.md; docs/plans/PHASE2_CONTRACT.md (bbba0a18); PHASE2_REPLACEMENT_MANIFEST_v9.md §5, §6.5, §6.6, §7 (envelope, BlockedSnapshot), §8 (967–1008), §8.9.2–8.9.3, §11:1529, §12.2–12.3. Tests: Swift Testing (`@Test`) as in TaskSupersessionTests; rules cases in functions/rules-tests/firestoreRules.test.js. Red first, then green, per the TDD skill.

Increments (each ends green + committed):
- [x] I1 Emulator config (item 4): firebase.json `emulators` block; Peezy 4.0Tests/FirebaseEmulatorTestSupport.swift (configures the default FirebaseApp for project demo-peezy-phase1, Firestore/Auth emulator hosts from TEST_RUNNER_-forwarded env, clears documents between tests); scripts/test-emulator.sh (`firebase emulators:exec --only firestore,auth,storage` → xcodebuild test + rules tests; Homebrew openjdk@21 on PATH). Proof: script runs a suite that reads/writes the emulator.
- [x] I2 Seams + vocabulary: Peezy 4.0/Tasks/Durable/DurableStoreReadiness.swift declares every §8:971 protocol, closed unions (§8:975–989), readiness vector `{route,handoff,reset,workflow}` each `loading|ready|blocked(BlockedSnapshot)` (§7 union), `StartupBarrier` with `AccountDeletionGate` + nine-member consumer projection (C2.4/§8.9.3) and exact required sets (§8:989), `FirestoreRuntimeGeneration` + the Firestore-runtime seam consumers code against; no file I/O. Tests: DurableStoreRecoveryTests readiness family (D23/D28): required sets exact, gate projection for all nine states, empty required set never bypasses a nonclear gate, clear adds no store dependency.
- [x] I3 Firestore-runtime consumers (25 of 27 sites; the two inside RetakeAssessmentCoordinator's pinned closure slice move with that slice's replacement): 15 sites in the 14 §12.2:1858 files + 6 in InventorySessionManager + Settings line 833 + RetakeAssessmentCoordinator/DailyDoseEngine/AssessmentDataManager/UserKnowledgeService acquire through the seam; static gate `rg 'Firestore.firestore()'` over S1-owned files = 0 production hits; InventorySessionManager diff = exactly six substitutions. Transitional production conformer returns `Firestore.firestore()` until S4's `FirestoreRuntimeOwner` replaces it.
- [x] I4 Epoch stamps only (owner re-scope 2026-09-03: no cleanup/deletion semantics, those belong to S3; `resetForRetake(authority:)`, the coordinator closure slice, DailyDoseLocalStore cleanup/0→1 bridge, and the cleanup rules predicates are S3's) (§5:540–546, 549–551): AssessmentDataManager.saveAssessment root-read + auto-ID create in one transaction with `task_generation_epoch`; UserKnowledgeService.merge transactional stamp rules incl. unstamped-at-epoch-0 upgrade; DailyDoseEngine dose map `{schema_version:1,task_generation_epoch,date,taskIds}`, legacy read only at epoch 0, `resetForRetake(authority:)` marker validation; `DailyDoseLocalStore` actor for `peezy.{uid}.dailyDose.v2` (cap 1,024, CAS, 0→1 bridge). Rules first pass: stamp/marker predicates for user_assessments, userKnowledge, root dailyDose. Tests: Swift transactions on the emulator (older/equal/newer epoch, unstamped 0→1, malformed, marker absent/wrong/drift) + rules cases.
- [x] I5 TaskPlanService `AccountDeletionRemoteProviding` transport: `AccountDeletionRequestV1` (discover|begin|resume|finalize), `AccountDeletionRemoteResultV1` (guarding wire, deleted wire, existing absent/data-final branches), thrown union, strict decoders. Tests: decoder mirrors with the injected callable.
- [x] I6 (approved scope 2026-09-06) `ResetOperationRegistry` in TaskPlanService.swift: envelope file, reserve → bind → prepared row, phase vocabulary, epoch-conflict snapshot, coordinator reserve-first with today's sequence unchanged (drive reducer, cleanup authority, cleanup callbacks, legacy migration transitions → S3); original plan: envelope `PeezyTaskPlanReset-v2.json` (DurableFileEnvelopeV1, TASK_PLAN_RESET_V2 cap 131,072), gesture reserve→bind→prepared, phase table + recovery actions, `ResetLocalCleanupAuthorityV1`, generation-fenced drive with inspect-before-each-callback, epoch conflict snapshot + `recoverEpoch`, capacity errors, `LocalDurableClock`, `ResetEpochAuthorityProviding` production conformer; legacy-migration rows represented and mapped per §6.5 outcomes. Coordinator rewrite per §6.6 (closure slice replaced; exact call trace). Tests: reset envelope (D14/D24/B2), coordinator (D30), D15 in TaskPlanDispositionTests.
- [ ] I7 Close: xcodebuild BUILD SUCCEEDED; all S1 suites green on the emulator; C7 hashes re-verified (retakeAssessment slice unchanged; Settings remainder identical after normalizing line 833); LESSONS/lessons.md updated; commit.

Residuals carried to later slices (recorded, not hidden): PeezySettingsView `deleteAccount()` hunk needs `Phase2ProductionRuntime.accountDeletionCoordinator` (S4/S7); gate admission at the PaywallGateView/SubscriptionManager/PeezyStackViewModel/InventorySessionManager dispatch edges needs the S7-published barrier instance; S1 declares the seams and types only.

## S3 inputs recorded 2026-09-06 (owner decisions)
- `taskReset` marker: spec v5 §697 canonical + manifest v9 §5:543 terminal invariants (contract Reconciled 9). Marker is the `taskReset` field of `users/{uid}`; account implied by path, no `uid` member. `functions/taskPlan.js:649-656` is the preimage S3 replaces.
- Data-final wire restored into contract C2.3 from manifest v7:1307 (Reconciled 8); S2 mirrors, S3 consumes.
- I6 scope (approved): S1 builds the reset envelope file, reserve → bind → prepared row, phase vocabulary, epoch-conflict snapshot, and the coordinator calling reserve first. Drive-reducer cleanup authority and the three cleanup callbacks go to S3 with the closure slice. Condition: a test proves that with S1 landed and S3 absent the user-visible retake path is identical to today, with no half-wired gesture and no reachable state nothing owns.
