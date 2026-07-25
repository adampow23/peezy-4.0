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

## Phase A: PeezyCard rewrite + single decoding path — COMMIT 8ab37c4, VALIDATOR PASS 4/4
- [x] PHASE_MANIFEST (edit sites + read sites)
- [x] Custom == deleted → synthesized memberwise. Bug demonstrated live pre-fix (server title edit invisible 175s despite data in store; only view recreation repainted) and fixed post-fix (passive repaint <10s; badge + reorder live). Audited id-only-semantics sites: TasksTabView:54 (id-membership check — safe), PeezyHomeView:140 (nil-mediated — safe), TasksList:72-77 rowIdentity workaround (retained)
- [x] TaskStatus: + pending = "pending"; matchingInProgress deleted (no live query; nothing ever wrote the CamelCase string); TaskRowHeader/TaskGrouping/shouldShow reconciled. Temp pending doc rendered waiting treatment (To-Do stayed 16, In Progress 1, "Matching vendors" badge)
- [x] stage/payload fields + TaskStage.swift + CardPayload/VendorRef/CaptureRef shells in PeezyCard.swift
- [x] loadTasks consumes the mapper; .pending buffers with .inProgress; dead colorNameForPriority removed
- [x] Single-path marker comment in mapper
- [x] Build green → commit → validator PASS 4/4 (independent re-run of mutations, pending doc, parity citation, build + 5-flow spot-check)

## Phase B: TaskStage persisted — COMMIT 830416d, VALIDATOR PASS 4/4
- [x] Mapper decodes stage nil-tolerantly; TaskActionService.setStage (no caller by design — Phase C absorbs, Spec 04 renders)
- [x] Round trip: write → kill → relaunch → in-process decode proof via lldb frame variable on the listener assignment ((Peezy_4_0.TaskStage?) tasks[0].stage = compare); Firestore read-back; screenshot parity Home+Tasks
- [x] Build green → commit → validator PASS 4/4 (own round trip with a different value; honesty check on the setStage-proxy accepted)

## Phase C: PeezyHomeViewModel split — COMMIT 9cfedc6, VALIDATOR PASS 4/4
- [x] DailyDoseEngine (math + urgency sort verbatim), TaskActionService absorbs 4 write funcs verbatim, thin VM composes; newFlowIds byte-identical
- [x] Dose target "Just 4 tasks per day" identical pre/post; validator re-derived 4 from identity moveDate 2026-07-30 + engine formula
- [x] Live +2d snooze through the split path: doc diff exactly {status Snoozed, snoozedUntil tap+48h, lastSnoozedAt serverTS}; +1d path (skipCurrentTask) has zero UI callers — source-level identity
- [x] Build green → commit → validator PASS 4/4

## Phase D: Dose counter + completion feel + done-for-today — COMMIT db99a3f, VALIDATOR PASS
- [x] "N for today" chip (home.dose_counter) + per-card "X of N" (home.card_position, numericText transition); haptic on 3 completion paths; card-exit transition on state switch (reduce-motion honored)
- [x] Done-for-today locked copy "That's today. / You're on pace for [move date]." (home.done_today_pace); celebrationSubtext removed with its only consumer; get-ahead retained (existing feature)
- [x] Validator live run: 1/3→2/3→3/3 sequential evidence, done card with July 30, same-day relaunch no-leak, Tasks tab To-Do 9/Done 7, next-day fresh dose
- [x] Fixture restored to pristine (16 Upcoming, fresh app container, keychain sign-in intact)

## Review

All four phases executed under the execution protocol at CORE tier: separate commits (8ab37c4, 830416d, 9cfedc6, db99a3f), per-phase PHASE_MANIFEST including read sites, fresh-context validator per phase — 4× PASS, zero bounded-retry cycles needed. Nothing deployed. Test-bot fixture and app container restored to pristine after every evidence run.

Observed items for the next spec author (details in SESSION_NOTES):
- Server also writes 'pending_matching' and queries 'matching_in_progress' (snake) — no TaskStatus case; falls back to .upcoming. Reconcile in Spec 04 when adopting getWorkflowQualifying.
- dailyTarget recomputes from the LIVE active count, so the announced target can shrink mid-day (from 9 actives: "3 for today" closed after 2). Pre-existing verbatim math, surfaced by Phase D's counter. DECISION candidate: freeze the day's target at first computation.
- skipCurrentTask (+1d snooze) has zero UI callers — dead path.
- Runtime a11y-id shadowing: container card ids (daily_greeting_card etc.) clobber child ids in the AX tree (pre-existing pattern).

## SESSION_NOTES (protocol §6)

What the spec got wrong / underspecified:
1. Phase A criterion 1 says "the Home UI visibly updates" when "snoozedUntil lapses" — Home has no live card-diffing surface (one-shot loader, state discarded on tab switch) and a time lapse alone produces no Firestore event. The demonstration surface had to be the Tasks tab listener with a server-side field mutation. Proposed conventions edit under Live data paths: "Only the Tasks tab live-updates (listener). Home re-queries on tab entry. Any UI-update criterion must specify a data event, not time passing."
2. Phase B's round-trip criterion implies exercising setStage, but the phase itself forbids any UI consumer — setStage necessarily has zero callers until Phase C/Spec 04 wires it. The admin-write payload-identity proxy + lldb decode proof was accepted by the validator; future specs should name the acceptable proxy up front.
3. Phase D's "GIVEN a 3-task dose" needs the fixture shape stated: with 9 actives the live-recomputed target shrinks mid-day and the day closes early; only a 12-active shape keeps the target at 3 across three completions.

What surprised us:
- The id-only Equatable staleness is total, not cosmetic: data arrives in the store, and even unrelated re-renders keep showing stale row content; only view recreation (tab switch) refreshed. TasksList's .id(rowIdentity-with-status) was a fossil workaround for exactly this bug.
- lldb `po`/`expr` cannot evaluate in [weak self] closure frames ("non-nominal type $__lldb_context"); `frame variable` with member paths is the reliable in-process inspection tool.
- `xcrun simctl spawn <udid> defaults` (read AND write) targets the device-level prefs domain, not the app container — writes look successful but the app never sees them. Deterministic prefs manipulation: shut the sim down, plutil the container plist, boot. Fresh install (uninstall+install) is the clean full reset; Firebase keychain keeps the test bot signed in.
- Flow-kit buttons expose the card TITLE as their a11y label (Continue vs the snooze-writing "Later" link distinguishable only by frame geometry). New Phase D elements got explicit ids; the flow kit predates the convention — Spec 04's FlowEngine should id every control.

Proposed doc edits: fold items 1–3 + the simulator lessons into peezy-conventions-v2 §Environment; add 'pending_matching'/'matching_in_progress' reconciliation as a Spec 04 line item; put the shrinking-dose-target DECISION in front of Adam before Spec 04 renders resume-at-stage against the dose.
