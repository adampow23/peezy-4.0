# PEEZY_STATE Regeneration — Spec (post-Phase 0)

## Purpose
Regenerate PEEZY_STATE.md §1–3 from a fresh evidence pass at commit `e8d6133`, so Phase 1 spec-writing reads a true state document. Documentation only: **no source file is modified, no test is run against production, no seed, no deploy.**

## Current State (read from the actual files, not memory)
- `PEEZY_STATE.md` snapshot is `7215cf2` (2026-08-23). Rows H7 and H8 are stale by owner deferral (PHASE0_BUILD.md, Owner preconditions 1). Three commits landed between the snapshot and Phase 0's BASE_HEAD `04c38c9`, then Phase 0 itself as `e8d6133`.
- The generating spec for the current document is `docs/plans/codex-review-peezy-state-doc.md`; its input drift and exact commands are in `STATE_GEN.md`, which lives **outside the repo at `~/Downloads/peezy-reports/STATE_GEN.md`** (the §4 report location), not at the project root. PEEZY_STATE.md's citations to it are therefore to an out-of-repo record; note this in the snapshot line. **That spec's evidence rules are binding here**, restated in PEEZY_STATE's header: §1–3 use only active reachable code/data; prior documentation and the generating spec are excluded as evidence; `LOCAL_METADATA` and `LOCAL_TOOLCHAIN_OBSERVED` are the only narrow exceptions; tests annotate only as `TEST_ASSERTED_UNVERIFIED`; `UNKNOWN` rows name the static search scope and the missing live fact.
- Working tree is dirty with inventory/narration WIP (Build 25). It must be recorded as dirty in the snapshot line and **excluded from evidence** (untracked files are not "active reachable code" for this pass).
- `PHASE0_VERIFICATION.md` and `PHASE0_BUILD.md` list the deltas expected; they are **hypotheses to verify with fresh file:line evidence, not evidence themselves** (same rule as the prior spec).

## Lessons Learned
- LE-019: fresh session per phase — this is a single-phase session; do not carry the Phase 0 build session's context.
- LE-032: undirected edits — the closeout diff must show exactly three changed paths (PEEZY_STATE.md, STATE_GEN.md, ARCHIVE_MANIFEST.md if the root document set changed) and nothing else.
- Prior regeneration lesson (PEEZY_STATE header): the review-log input drift was caught only because every command and its output were recorded — record them again.

## Pre-Flight Check
```bash
cd ~/Desktop/"Peezy 4.0" || exit 1
git rev-parse HEAD            # must print e8d6133...
git status --porcelain | tee /tmp/state-gen-preflight.txt   # dirty WIP expected; record it verbatim
STATE_GEN=~/Downloads/peezy-reports/STATE_GEN.md
test -f PEEZY_STATE.md && test -f "$STATE_GEN" && test -f docs/plans/codex-review-peezy-state-doc.md || exit 1
git hash-object PEEZY_STATE.md PHASE0_BUILD.md >> /tmp/state-gen-preflight.txt
shasum -a 256 "$STATE_GEN" >> /tmp/state-gen-preflight.txt
```
Abort if HEAD is not `e8d6133` or if any of the three files is missing.

---

## Phase 1: Regenerate §1–3 (files: 2 modify, 0 create; +1 conditional)

**READ FIRST:** `docs/plans/codex-review-peezy-state-doc.md` (method and disposition vocabulary) · `~/Downloads/peezy-reports/STATE_GEN.md` (every exact command from the prior pass — rerun each, do not paraphrase) · `PEEZY_STATE.md` (row inventory to regenerate) · `PHASE0_BUILD.md` Part A and Part B (hypotheses) · `PHASE0_VERIFICATION.md` "PEEZY_STATE regeneration — required deltas."

**Order of operations:** for every existing row H1–H43 and every proposed new row, (1) rerun the prior exact command or write a new one, (2) capture output verbatim into STATE_GEN.md under the row ID, (3) assign the disposition from the output alone, (4) write the row. Regenerate the three sections whole — **never append to or edit the old rows in place** (§4). Section 4 (working protocol) and the addendum are copied unchanged.

**The break:** rows H7 and H8 describe defects that no longer exist in source; four architecture facts the Phase 0 audit established have no row; one HIGH defect the audit found has no row; several rows cite line numbers that moved after Phase 0's 10-file change (H3, H4, H8, H12d, H20's Swift citations at minimum — verify every citation in every row, not only these).

**Required content changes (each still needs fresh evidence):**
1. **H7** → disposition on the *source*: create-only mixed batch, fingerprint-checked replay, versioned deterministic IDs, `expectedUserId` pre-read rejection [cite spawnTasks.js lines at `e8d6133`]. Add the split disposition the prior doc uses for deployment: source `SUPPORTED`; deployed revision `UNKNOWN` (search scope: source only; live function revision not queried). In §3, the H7 row moves from CRITICAL-open to a **deploy-blocked** item: "fixed in source; deployed revision retains the race until a human deploy after H43; drain the old revision ≥15 s."
2. **H8** → source `SUPPORTED` for transactional claim before advancement/credit, single-flight state machine, visible retryable failure [cite TaskActionService.swift, PeezyHomeViewModel.swift, NudgeCardView.swift]. §3 row closes or becomes a residual-risk note (R1 Yes-vs-No self-race, R2 lost local dose count) — record the residuals as `SUPPORTED` facts with evidence, not as the Phase 0 report's assertions.
3. **New §1 rows** (IDs H44+; do not renumber existing rows):
   - Snooze persistence is time-only: `snoozedUntil`/`lastSnoozedAt`, two-day hardcode on both user paths, wake = `snoozedUntil > now`; no trigger kind/payload/evaluator [PeezyCard.swift; PeezyCardFirestoreMapper.swift; TaskActionService.swift; PeezyHomeViewModel.swift; TaskGrouping.swift].
   - Push payloads carry only `thread: support`; no step-level deep link; URL handling is Google Sign-In only [supportAdmin.js; PeezyV1App.swift; PeezyMainContainer.swift].
   - researchTask confidence is section-level (`SPECIFIC`/`SAFE GENERAL`), `degraded` whole-brief; brief persisted under `brief` [researchTask.js; TaskResearchModule.swift].
   - Exactly two same-ID router shadows over `flowDefinitions`: `update_auto_insurance` → HandleAutoInsuranceFlow, `setup_internet` → SetupInternetFlow; list the hardcoded TaskFlowSummaryCard inventory [TaskFlowRouter.swift; flowDefinitionsData.json line ranges]. Cross-reference H6/H11 rather than restating them.
   - Per-row flow state persists as `flowPath` + `flowAnswers`; no scene-phase flush exists (newest in-flight write under suspension `UNKNOWN`) [FlowEngineView.swift; FlowExitControl.swift; PeezyV1App.swift].
   - Spawn identity is `users/{uid}/spawnTokens/{token}` with the four token producers enumerated; institution travels only as `titleParams.institution`; no subject/institution field on stored tasks [FlowEngineView.swift; PeezyHomeViewModel.swift; RentTruckFlow.swift; MoversChainCoordinator.swift; spawnTasks.js].
   - DEBUG-only XCTest guard at three startup sites; hosted TEST_HOST target unchanged [PeezyV1App.swift; project.pbxproj].
4. **New §3 row — financial flow zero-spawn (HIGH):** row-expanded `{rowId}.provider` never matches `perSelectionFrom: "provider"` or exact `answers["provider"]` lookups; tests cover only the unexpanded step [FlowDefinition.swift; flowDefinitionsData.json; FlowEngineView.swift; ConversationFlowTests.swift]. Safe next action: row-aware lookup + row-expanded test, Phase 1. Blocks: none. Sign-off: PENDING. **Reproduce it statically** — show the lookup site and the rewritten key side by side in STATE_GEN.md.
5. **H21** gains the consequence: `spawnTokens` is owner-writable under the recursive grant [firestore.rules lines]; no new capability versus direct owner task writes.
6. **H38** — re-evaluate: the DEBUG guard changes the production-connected-test exposure for hosted runs; credential/identifier debt unchanged unless evidence says otherwise.
7. **H24/H25 structural counts** — rerun the exact jq commands; the catalog/flow files should be unchanged (63/35) but confirm; note that the reseed for the locked institution flows (Entries 1–10) is still future.
8. **Snapshot line:** `e8d6133`, date, dirty-tree note verbatim from pre-flight, and `PHASE0_BUILD.md` as a root document (update ARCHIVE_MANIFEST.md if it lists root documents).
9. **Next post-Phase-2 regeneration — H57 quarantine consumer (do not replace or renumber H56):** after fresh static evidence verifies the producer, add one split-disposition §1 row: `H57` producer source `SUPPORTED` · deployed/consumer `UNKNOWN`. The row must state that scheduler phase 0 uses a persisted full-path cursor and, after three identical deterministic validation failures, atomically terminalizes the source and writes one bounded digest-only record at `phase1System/dispositionTriggerState/quarantinedEvents/{quarantineId}`. Static search must cover `functions/index.js` and its active backend graph, active project Swift sources, `firestore.rules`, `firestore.indexes.json`, `firebase.json`, `public/`, and repository ops/CI configuration. If it finds no active reachable reader, alert, export, admin surface, cleanup/TTL, or named operational owner, the consumer remains `UNKNOWN`; name that negative search scope and the missing live facts (deployed revision, stored quarantine documents, Cloud Logging/Monitoring alerts, and out-of-repo operator/runbook practice were not queried). Capture both producer-path hits and the quiet negative consumer search in the evidence log. A producer/quarantine record is not proof of consumption, and this regeneration spec/amendment is hypothesis rather than evidence.

**Disposition vocabulary (unchanged):** `SUPPORTED · CONTRADICTED · UNKNOWN`, with `DEPLOY_CONFIGURED`, `LOCAL_OBSERVED`, `LOCAL_METADATA`, `TEST_ASSERTED_UNVERIFIED` evidence tags. No new labels. "Fixed locally, undeployed" is expressed as two dispositions (source / deployed), not a new word.

**BLAST RADIUS:** NONE (documents only).
**DO NOT CHANGE:** any file under `Peezy 4.0/`, `functions/`, `public/`, `firestore.rules`, `storage.rules`, `firebase.json`, `.firebaserc`, `Configuration.storekit`, `project.pbxproj`, any test file, `PHASE0_BUILD.md`, `PHASE_MANIFEST`, `docs/plans/*`, and every dirty/untracked WIP path from the pre-flight porcelain. Do not run xcodebuild, node tests, seeds, or any Firebase CLI command — static reads only (`grep`, `sed -n`, `jq`, `git show`, `wc`, `shasum`).
**FALLBACK:** if a prior STATE_GEN command no longer applies (path moved), record the failure verbatim, write the replacement command beneath it, and mark the row's evidence with both.

**Verification:**
```bash
git status --porcelain | diff - <(head -n $(grep -c . /tmp/state-gen-preflight.txt) /tmp/state-gen-preflight.txt)   # only PEEZY_STATE.md (/ ARCHIVE_MANIFEST.md) may differ; STATE_GEN.md is outside the repo
git diff --stat -- PEEZY_STATE.md ARCHIVE_MANIFEST.md
shasum -a 256 ~/Downloads/peezy-reports/STATE_GEN.md   # must differ from pre-flight (appended), and the pre-flight section must still be byte-present at the top
grep -c '^| H' PEEZY_STATE.md                                        # row count ≥ prior + 8 (H44–H51 or as numbered)
grep -n 'e8d6133' PEEZY_STATE.md | head -1                           # snapshot line present
grep -n 'TODO\|TBD' PEEZY_STATE.md ~/Downloads/peezy-reports/STATE_GEN.md && exit 1 || true    # no placeholders
```
Then diff the regenerated §1–3 against the old text row by row and confirm every retained row's citations were re-verified (STATE_GEN.md must show a command and output for each). Commit gate is the human's: present the diff, do not commit.

---

## Files Summary
- **Modified:** `PEEZY_STATE.md` (§1–3 regenerated whole; §4 + addendum unchanged) in the repo; `~/Downloads/peezy-reports/STATE_GEN.md` (every command and output, appended under a new dated header `## 2026-08-26 regeneration @ e8d6133` — append-only; never rewrite the prior section).
- **Conditionally modified:** `ARCHIVE_MANIFEST.md` (only if root documents changed).
- **NOT modified:** everything else, including the Build 25 WIP.

## Delegation Prompt
```
I need you to run a documentation-only evidence pass. Read-only against source; you may edit exactly two files (three if ARCHIVE_MANIFEST.md lists root documents) plus the out-of-repo STATE_GEN.md.

1. My Peezy project root is at ~/Desktop/Peezy 4.0/. HEAD must be e8d6133; the tree is dirty with unrelated Build 25 WIP — record it, never touch it, never cite it. The prior evidence record is at ~/Downloads/peezy-reports/STATE_GEN.md (outside the repo); append to it, never rewrite it.
2. The spec is PEEZY_STATE_REGEN_SPEC.md at the project root. Follow it exactly: rerun every command in STATE_GEN.md, record every command and output, regenerate PEEZY_STATE.md §1–3 whole (never append to old rows), keep §4 and the addendum verbatim.
3. Do not run xcodebuild, node tests, seeds, or firebase commands. Static reads only.
4. When the verification block passes, show me `git diff --stat` and the regenerated §3 table, then stop. I commit.

Do not ask questions — investigate and execute.
```
