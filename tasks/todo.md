# Spec 02 — Data Truth — execution plan (session 2026-07-25)

Governing docs: peezy-build-spec-02.md, peezy-execution-protocol.md.
Per-phase: PHASE_MANIFEST → build → xcodebuild → commit → fresh-context validator (bounded retry 2).

## Pre-flight findings (evidence in phase reports)

- Inherited dirty tree = Adam's in-progress dead-code removal (peezyLayout.swift + TaskFlowSelect5Card, matches DEAD_CODE_REMOVAL_LIST.md items 5/9). Left untouched; per-phase commits stage only Spec 02 files. Baseline xcodebuild on the inherited tree: BUILD SUCCEEDED.
- [NEEDS CLARIFICATION — resolved by bounded interpretation] Spec A assumes question views exist with broken bindings. Reality: HasVehicles/WantToSell/HasStorage/StorageSize/StorageFullness/CurrentBedrooms/NewBedrooms views were DELETED in eab4193 and their steps removed from AssessmentCoordinator. Acceptance criteria require answering these questions, so the break-point fix is restoring them from git history at their historical sequence positions (reversible, template API unchanged).
- [NEEDS CLARIFICATION — resolved by bounded interpretation] Spec B's "existing moveDateType Flexible option" was also deleted in eab4193. Restoring MoveDateType (Strict/Flexible) is the only way to satisfy the flexible-date criterion.
- moveConcerns: already absent from step sequence and views (deleted eab4193). Remaining: dict key, @Published, dead inputContext reference. Zero catalog conditions reference it (verified against functions/taskCatalogData.json).
- sqft ×4: already absent from step sequence; views already deleted (b851224). Zero catalog conditions. Spec's "views stay in repo" is moot — nothing to do beyond evidence.
- [NEEDS CLARIFICATION — Phase D] "interstitialComment system" has zero matches in the codebase; ConversationalInterestitialView deleted in eab4193; coordinator inputContext has zero consumers (dead code). Phase D handling decided at Phase D.

## Phase A: persistence repairs
- [x] PHASE_MANIFEST written
- [x] Restore 7 question views (current template API + accessibilityIdentifier)
- [x] Coordinator: 7 enum cases + historical sequence positions + isBranchingStep(hasStorage, hasDeclutter) + inputContext cases (dead but exhaustive)
- [x] AssessmentFlowView: routing cases (default: EmptyView would swallow them otherwise)
- [x] getAllAssessmentData: financialInstitutionCounts / healthcareProviderCounts / fitnessWellnessCounts
- [x] xcodebuild BUILD SUCCEEDED
- [x] Commit e8ee378
- [x] Validator PASS 3/3 (Firestore read-back + task query + code citation; evidence in validator report)

## Phase B: escape hatches + removals
- [x] newAddress "I don't have it yet" (locked copy) + newAddressPending → dict + identity doc
- [x] Restore MoveDateType; Flexible → moveDatePending; locked copy as pre-choice subtext (auto-advance tiles leave no post-choice surface)
- [x] Remove moveConcerns dict key + @Published + dead moveDate-context reference (zero catalog conditions reference it; functions/testProfile/seedTestUser.js:34 still seeds it — backend test fixture, out of client scope)
- [x] sqft: already out of sequence, views already deleted (b851224) — evidence-only
- [x] xcodebuild BUILD SUCCEEDED
- [x] Commit 2a0b67e; validator PASS 3/3 (screen-by-screen evidence, condition-level task-count reconciliation 19−5+2=16, both pending flags in both docs)

## Phase C: reweights + reseed
- [x] BOOK_CLEANERS 25→55, TRANSFER_PHARMACY_RECORDS 55→75 in functions/taskCatalogData.json (two-line diff, JSON valid, 56 tasks)
- [x] node seedTaskCatalog.js — deleted 56, wrote 56 (the ONLY deploy)
- [x] Ghost-task check: independent Admin-SDK read-back — 56 docs, BOOK_CLEANERS=55, TRANSFER_PHARMACY_RECORDS=75. Seeder's "CANCEL_YOGA NOT FOUND" is its own stale spot-check constant (catalog has MANAGE_YOGA) — pre-existing, flagged as separate task
- [x] Commit 1caeeae; validator PASS 3/3 (independent object-by-object JSON diff of both blob versions, own read-only Admin-SDK script, ID-set equality live-vs-seed with empty differences)

## Phase D: reflect-back interstitials — SKIPPED, all four beats [NEEDS CLARIFICATION]
- Evidence: zero case-insensitive "interstitial" matches in any Swift file (current AND pre-cleanup coordinator); ConversationalInterestitialView.swift deleted in eab4193; coordinator inputContext(for:) has ZERO consumers (dead code — question views own their headers).
- Spec's own rule applied: "if the mechanism can't support a beat without new UI, mark NEEDS-CLARIFICATION and skip that beat rather than building UI." With no mechanism at all, that is all four beats. The acceptance criterion (screenshots of interstitials rendering) is unfulfillable without inventing a render mechanism, which the protocol forbids (NEEDS-CLARIFICATION beats invention).
- The "after address pair" beat has a second, independent blocker: "That's a [Local/Long Distance] move" requires distance mid-flow, but geocoding runs only at completion (completeAssessment) — surfacing it mid-assessment is new behavior, not copy.
- Options for the spec revision (Adam/Claude.ai decision):
  (a) Revive inputContext: render coordinator.inputContext(for:) as a banner line above the question in AssessmentFlowView — one render site, copy stays in the coordinator, all beats become data edits. Closest to the spec's intent.
  (b) Conditional copy prepends on existing screens (HasVet header for the kids beat, ServicesIntro for pets, AddressChangeIntro for services) — copy-only but bends "question views own their page" and still can't do the address beat.
  (c) Restore a ConversationalInterestitialView-style step type from eab4193^ — real interstitials, but that IS new UI in the sequence.

## Review

All four phases executed under the protocol: A (e8ee378, validator PASS 3/3), B (2a0b67e, PASS 3/3), C (1caeeae + live reseed, PASS 3/3), D (no code — NEEDS-CLARIFICATION skip per spec rule). Catalog reseed was the only deploy. Adam's in-progress dead-code working-tree changes were preserved untouched throughout (pathspec commits).

## SESSION_NOTES (execution-protocol §6 — proposed doc edits)

1. **Spec 02's Phase A/B premises were stale**: the seven dead-key question views + MoveDateType were deleted wholesale in eab4193 ("Cleanup complete", 2026-04-10), not left with broken bindings; moveConcerns/sqft were ALREADY out of the sequence. Proposed conventions-v2 addition: "eab4193 deleted 8 question views (vehicles/sell/storage×3/bedrooms×2/moveDateType) and the interstitial view; V1_ARCHITECTURE_MAP audit facts postdate it but spec authors must diff question-view existence against the coordinator's step enum, not the data manager's @Published list — the data manager kept all keys alive after the views died."
2. **The 'interstitialComment system' named in Spec 02 Phase D does not exist and never existed under that name** — closest artifacts: ConversationalInterestitialView (deleted eab4193) and the dead inputContext(for:) switch (zero consumers). Proposed conventions-v2 line: "AssessmentCoordinator.inputContext(for:) is dead code — question views own their full page; any 'show copy between questions' feature needs a render site first."
3. **Firestore doc-order gotcha for validators**: user_assessments has no client timestamp; wipe-then-run (test bot only) is the reliable evidence pattern. readback.js-style scripts need NODE_PATH=functions/node_modules when run from outside functions/.
4. **iOS Simulator MCP was unusable this session** (stale xcode-select env in the server process; `xcode-select -p` is correct). AXe + simctl fallback per project_sim_automation.md worked for both validators. Restart the MCP server or run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` before a session that wants the live panel.
5. **Seeder quirk**: seedTaskCatalog.js spot-checks "CANCEL_YOGA", which hasn't existed in the catalog (it's MANAGE_YOGA) — prints a misleading NOT FOUND every reseed. Spun off as a separate one-line task.
6. **What went right worth keeping**: restoring deleted UI verbatim-from-history (adjusted only to current sibling conventions + accessibility ids) made Phase A a 12-file change that passed its validator first attempt; both sim validators passed first attempt (no bounded-retry consumed) — the read-everything-first + spec-deviation-markers pattern is paying for itself.
