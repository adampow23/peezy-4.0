# Peezy v1 Build — Spec 02: Data Truth
Prereqs: Spec 01 complete (7 commits, hooks active from this session onward). Read peezy-conventions-v2.md, peezy-v1-architecture.md, peezy-execution-protocol.md, peezy-v1-catalog-sheet.md first. Runs under the execution protocol: PHASE_MANIFEST per phase, writer/validator split, bounded retry (2), NEEDS-CLARIFICATION over invention.

Model: Fable 5, `claude --effort xhigh`.

## Scope statement

This spec makes the data layer tell the truth: every question asked persists, every persisted key generates the tasks it gates, and no user gets stuck on a question they can't answer. It does NOT restructure the catalog (merges, new taskIds, RESOLVER) — those ride with the flow engine in Spec 04, because a new taskId without a routable flow = the permanent-spinner bug. Resurrections here use EXISTING taskIds routed by EXISTING flows only.

Known from Spec 01's run: the method is `AssessmentDataManager.saveAssessment()` (not completeAssessment); the userKnowledge write THROWS under deployed rules, so new persistence code must be ordered BEFORE it; hooks are live this session.

## Phase A: Persistence repairs (the four dead tasks + supporting keys)

**READ FIRST:** AssessmentDataManager.swift in full — every @Published property, `getAllAssessmentData()`, `saveAssessment()`. The question views for: hasVehicles, wantToSell, hasStorage/storageSize/storageFullness, currentBedrooms/newBedrooms, and all multi-select templates. Trace each from UI tap → @Published → dict → Firestore, and identify the exact break per key.

**Fix so that these keys persist real answers:**
1. `hasVehicles` — currently always "No". Resurrects UPDATE_AUTO_INSURANCE + REGISTER_VEHICLE.
2. `wantToSell` — currently always empty. Resurrects SELL_ITEMS + REMOVE_ITEMS.
3. `hasStorage`, `storageSize`, `storageFullness` — currently always empty. These are ESTIMATE INPUTS (extra cube volume for mover pricing, consumed by the Spec 05 pricing engine — per Adam, not vertical triggers). No task gates on them; the pipe must work and packageInventory.js already reads them for admin emails.
4. `currentBedrooms` / `newBedrooms` — feed the no-video cube fallback + packageInventory emails.
5. Multi-select tap COUNTS (financialInstitutions, healthcareProviders, fitnessWellness) — persist counts alongside categories, e.g. `financialInstitutionCounts: {"Bank / Credit Union": 2}`. Categories array stays unchanged (conditions depend on it). Honors the UI's stated "each tap adds a task" promise; consumed by row-generation in Spec 04.

Boundary: fix persistence ONLY. Do not change question UI, condition strings, or the parser. If a key's break is upstream of the data manager (e.g., the question view never writes the binding), fix at the actual break point and cite it.

**Acceptance criteria (validator executes):**
- GIVEN a fresh assessment run answering vehicles=Yes, sell=Yes, storage=Yes(+size/fullness), 3 bedrooms, 2 bank taps, WHEN saveAssessment completes, THEN the user_assessments doc contains all keys with those values (Firestore read-back evidence).
- GIVEN that data, WHEN TaskGenerationService runs, THEN UPDATE_AUTO_INSURANCE, REGISTER_VEHICLE (if interstate), and SELL_ITEMS exist in users/{uid}/tasks (query evidence).
- GIVEN the identity doc write order, THEN all new persistence executes BEFORE the userKnowledge write (code citation).

## Phase B: Escape hatches + question removals

**READ FIRST:** AssessmentCoordinator.swift (step sequence, inputContext, interstitialComment), NewAddress.swift, MoveDate.swift, MoveConcerns.swift, the sqft question views, AddressSearchManager.swift.

1. **newAddress escape hatch.** Add a "I don't have it yet" affordance on the NewAddress question. Selecting it: sets `newAddressPending: true` on the assessment dict + identity doc; accepts optional city/state-or-ZIP if the user has that much (feeds a coarse geocode); otherwise distance defaults apply (existing fail-open: Long Distance/Yes — over-prepare). Assessment continues normally. Copy: "No address yet? No problem — most people start planning before they've signed. We'll build your plan and you can drop it in later." (LOCKED.)
2. **moveDate escape hatch.** The existing moveDateType "Flexible" option sets `moveDatePending: true` when the user indicates the date is approximate; require a best-guess date regardless (the dose math needs a denominator). Copy addition on the flexible path: "We'll plan against your best guess — adjusting later takes one tap in Settings." (LOCKED.)
3. **Delete moveConcerns** from the step sequence entirely (question view, coordinator case, dict key). Confirm zero catalog conditions reference it (grep the seed JSON).
4. **Relocate the four sqft questions** (currentSquareFootage, currentFinishedSqFt, newSquareFootage, newFinishedSqFt) OUT of the assessment step sequence. Views stay in the repo (they return at mover-capture in Spec 05); keys stay in the dict schema, empty. Confirm zero catalog conditions reference them first.
5. **floorAccess stays** — RESERVE_ELEVATORS_* conditions gate on it. Do not touch.

Settings already round-trips addresses (Spec 01); no pending-task cards are generated yet — the ADD_NEW_ADDRESS / CONFIRM_MOVE_DATE catalog rows arrive in Spec 04 with routable flows. The flags persist now so those tasks generate retroactively for pending users when seeded.

**Acceptance criteria:**
- GIVEN NewAddress, WHEN "don't have it yet" is chosen with no input, THEN assessment completes, newAddressPending=true persists, moveDistance defaults applied, and a full task set still generates (count evidence vs a control run).
- GIVEN the step sequence, THEN moveConcerns and the four sqft steps never render across a full assessment run (screen-by-screen evidence), and total question count drops accordingly.
- GIVEN the flexible-date path, THEN a date is still captured and moveDatePending=true persists.

## Phase C: Seed-file reweights + reseed

**Edit functions/taskCatalogData.json only:** BOOK_CLEANERS urgencyPercentage 25→55; TRANSFER_PHARMACY_RECORDS 55→75. No other rows change in this spec.

Then `cd functions && node seedTaskCatalog.js` against peezy-1ecrdl. **Ghost-task check (per CLAUDE.md gotcha #1):** after reseed, verify the Firestore taskCatalog contains exactly 56 docs and no stale extras (count + diff evidence).

**Acceptance criteria:** Firestore taskCatalog docs for the two IDs show new urgency values; total doc count = 56.

## Phase D: Reflect-back interstitials (copy-only)

**READ FIRST:** the interstitialComment system in AssessmentCoordinator.

Add/extend reflect-backs at four beats, using the existing mechanism (no new UI): after pets → "Vet transfer just went on your plan." After kids → "School and daycare handling — on the plan." After address pair → "That's a [Local/Long Distance] move — pricing and paperwork planned accordingly." After services section → "Movers, cleaning, and supplies: we'll bring you options — you'll never chase quotes." Copy LOCKED; if the mechanism can't support a beat without new UI, mark NEEDS-CLARIFICATION and skip that beat rather than building UI.

**Acceptance criteria:** screenshots of each interstitial rendering in a full run.

## Files Summary
Modified: AssessmentDataManager.swift, AssessmentCoordinator.swift, NewAddress.swift, MoveDate.swift (or MoveDateType.swift — cite), affected question views for persistence breaks, PeezyIdentity.swift (+pending flags), functions/taskCatalogData.json. Deleted from step sequence (files remain): MoveConcerns + sqft views. Deployed: catalog reseed ONLY (no functions, no rules).
Phase manifests list read-site files per the Spec 01 lesson.

## Delegation Prompt
```
cd ~/Desktop/Peezy 4.0/. Read peezy-conventions-v2.md, peezy-v1-architecture.md,
peezy-execution-protocol.md, peezy-v1-catalog-sheet.md, then peezy-build-spec-02.md.
Execute Phases A→D. PHASE_MANIFEST per phase, commit per phase, validator per
phase with the spec's acceptance criteria. Catalog reseed is the only deploy.
STOP on anything the spec doesn't cover. Investigate and execute.
```
