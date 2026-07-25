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
- [ ] PHASE_MANIFEST written
- [ ] Restore 7 question views (current template API + accessibilityIdentifier)
- [ ] Coordinator: 7 enum cases + historical sequence positions + isBranchingStep(hasStorage, hasDeclutter) + inputContext cases (dead but exhaustive)
- [ ] AssessmentFlowView: routing cases (default: EmptyView would swallow them otherwise)
- [ ] getAllAssessmentData: financialInstitutionCounts / healthcareProviderCounts / fitnessWellnessCounts
- [ ] xcodebuild BUILD SUCCEEDED
- [ ] Commit
- [ ] Validator PASS

## Phase B: escape hatches + removals
- [ ] newAddress "I don't have it yet" (locked copy) + newAddressPending → dict + identity doc
- [ ] Restore MoveDateType; Flexible → moveDatePending; locked copy
- [ ] Remove moveConcerns dict key + @Published + dead references
- [ ] sqft: evidence-only (already out of sequence)
- [ ] Build, commit, validator

## Phase C: reweights + reseed
- [ ] BOOK_CLEANERS 25→55, TRANSFER_PHARMACY_RECORDS 55→75 in functions/taskCatalogData.json
- [ ] node seedTaskCatalog.js (the ONLY deploy)
- [ ] Ghost-task check: exactly 56 docs, values verified
- [ ] Commit, validator

## Phase D: reflect-back interstitials
- [ ] Resolve mechanism NEEDS-CLARIFICATION; copy-only or skip per spec rule
- [ ] Build, commit, validator

## Review
(appended at end of session with SESSION_NOTES)
