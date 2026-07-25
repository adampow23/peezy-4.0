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
- [ ] Commit, validator

## Phase D: reflect-back interstitials
- [ ] Resolve mechanism NEEDS-CLARIFICATION; copy-only or skip per spec rule
- [ ] Build, commit, validator

## Review
(appended at end of session with SESSION_NOTES)
