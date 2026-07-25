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
- [ ] VALIDATOR DEFERRED: fresh-context agent hit the session usage limit (resets 12:40pm CT).
      Re-run after reset; Phase A+B validators must BOTH pass before the Phase C deploy batch.
      Harness lesson already folded in: stage defs JSON inside the app container
      (host-path sync read blocks first render on TCC).

## Phase B: Catalog v2 + row-generation (CORE) — todo (own manifest at start)

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

(filled at close)
