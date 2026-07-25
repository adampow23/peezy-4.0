# Spec 03 — Card + Stage Model — execution plan (session 2026-07-25)

Governing docs: peezy-build-spec-03.md, peezy-execution-protocol.md, peezy-conventions-v2.md.
CORE tier: per-phase PHASE_MANIFEST (incl. read-site files) → build → xcodebuild → commit → fresh-context validator (bounded retry 2). Nothing deploys.

## Pre-flight findings (evidence: this session's reads/greps)

- Tree clean at 39c4477. Baseline xcodebuild on the untouched tree: BUILD SUCCEEDED.
- Live Firestore→PeezyCard paths confirmed exactly two: PeezyHomeViewModel.loadTasks:295 (inline construction) and TasksStore:51 → PeezyCardFirestoreMapper.card():36. PeezyStackViewModel constructs cards (:140,:171) but is DEAD — zero instantiation (PeezyMainContainer:18 is a stale comment only; DEAD_CODE_REMOVAL_LIST item 6 predates the cleanup commit). Left untouched (deletion is Adam's Xcode task).
- Project uses PBXFileSystemSynchronizedRootGroup (5 hits) — new .swift files under the source root compile without pbxproj edits.
- Server status writes: 'pending' (functions/index.js:405,425,464; getWorkflowQualifying.js:210). Nothing anywhere writes "MatchingInProgress" (CamelCase). No client Firestore query references it (queries: PeezyHomeViewModel:261, dead PeezyStackViewModel:92, TasksStore listener unfiltered) → spec's deletion condition met.
- Server also writes 'pending_matching' (getWorkflowQualifying.js:231,274) and queries 'matching_in_progress' (index.js:225) — OUT OF SPEC 03 SCOPE (orphaned workflow system, adopted Spec 04). Reported, not built.
- Equatable(id-only) consumers audited: TasksTabView:54 onChange(of: store.tasks) — id-membership check inside, safe under memberwise; PeezyHomeView:140 onChange(of: focusedTask) — always transitions through nil, safe; TasksList:72-77 .id(rowIdentity incl. status) — existing WORKAROUND for the id-only staleness; all removeAll/firstIndex sites already compare $0.id explicitly. No firstIndex(of:)/contains(element:) on PeezyCard. TaskGrouping.Groups: Equatable declared, never compared.
- PeezyCard has no JSON persistence (PeezyClient decodes its own response types; PeezyResponse:95 constructs cards via explicit string switch, no matchingInProgress reference) → enum case deletion has no decode-migration risk.
- [NEEDS CLARIFICATION — bounded interpretation, Phase A criterion 1] "Home UI visibly updates" / "snoozedUntil lapses": Home renders greeting/flow states only (no live card-diffing surface; one-shot loader, view state discarded on tab switch), and a time lapse alone produces no Firestore event, so no Equatable change can repaint anything without a data push. Closest faithful demonstration of the id-only bug: Tasks tab (the live listener surface), server-side mutation of a field NOT in rowIdentity (set/clear snoozedUntil on an Upcoming task → "Snoozed" badge via TaskGrouping.isSnoozedEffective) with unchanged id+section+status. Before: row stays stale. After: repaints. Home shown updating on tab re-entry (fresh load) for the without-relaunch half.
- Phase D "greeting-card rendering" located: PeezyHomeView state switch :65-80; dailyGreetingCard :235-269, returningMidDayCard :273-307, dailyCompleteCard :325-368. PeezyHaptics at Assessment/PeezyTheme/peezyHaptics.swift (has .success()). Dose reset uses raw Date() (not DateProvider) → next-day criterion via dose recompute (UserDefaults lastDate rewind + relaunch).

## Phase A: PeezyCard rewrite + single decoding path
- [ ] PHASE_MANIFEST (edit sites + read sites)
- [ ] Delete custom == (PeezyCard.swift:365-367) → synthesized memberwise; cite audited call sites in report
- [ ] TaskStatus: add case pending = "pending"; delete matchingInProgress; fix consumers TaskRowHeader:15-16,:87 + TaskGrouping:7,:26; shouldShow excludes .pending
- [ ] New fields stage: TaskStage?, payload: CardPayload? (+ VendorRef/CaptureRef empty shells, Codable+Equatable). TaskStage.swift new file; CardPayload declared in PeezyCard.swift (cited)
- [ ] loadTasks consumes PeezyCardFirestoreMapper (delete inline construction); Home keeps its query + buffering; .pending buffers with .inProgress
- [ ] Mapper: single-path marker comment (LE-025/031 successor)
- [ ] xcodebuild SUCCEEDED → commit → validator (criteria incl. pending waiting-treatment screenshot, both-paths parity, 5-flow spot-check)

## Phase B: TaskStage persisted
- [ ] Mapper decodes stage (nil-tolerant); TaskActionService.setStage direct write (new file, absorbed by Phase C)
- [ ] Round-trip evidence: write → relaunch → decode read-back; screenshot parity Home+Tasks
- [ ] Build → commit → validator

## Phase C: PeezyHomeViewModel split
- [ ] DailyDoseEngine (target math :182-193 + urgency sort :336-341 VERBATIM), TaskActionService (absorbs status/snooze/complete writes + setStage), thin VM keeps newFlowIds
- [ ] Pre/post numeric dose parity for test bot; byte-identical snooze update payloads
- [ ] Build → commit → validator

## Phase D: Dose counter + completion feel + done-for-today
- [ ] "N for today" + "X of N" from DailyDoseEngine; success haptic + exit animation + counter tick; done-for-today card with move date (copy LOCKED); Tasks tab untouched as pressure valve; accessibility ids
- [ ] Build → commit → validator (sequential completion evidence + next-day recompute)

## Review
(filled at close)
