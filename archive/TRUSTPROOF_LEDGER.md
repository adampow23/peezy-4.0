# TRUSTPROOF_LEDGER — Full-App Exit-Risk Audit

Run: 2026-08-03, per `peezy-trustproof-run.md` + the peezy-trustproof skill (inversion → classify → Sev/Silence/Clock → prevention-ladder rung). READ-ONLY run: zero source changes; this ledger is the only output. Free-tier ground truth is architecture §10 option (c). Findings below are exit-risk only — moments that plausibly end a session or the relationship. Cosmetics are one-liners in the appendix.

**Evidence key:** every finding carries a code citation (file:line, verified this session) and/or `[SIM]` = reproduced/observed live in the iPhone 17 Pro simulator on 2026-08-03 (fresh build `64aa5b2`, test account `peezy-test-bot@…`, move date Aug 5 2026 = T-2; screenshots in this session's transcript). Findings whose *mechanism* is inferred but not induced are marked `[HYP]` (hypothesis).

**[NEEDS CLARIFICATION — pilot import]** The run doc says to import the skill's pilot-run paywall findings as F-001..F-005. Those findings exist in no repo file and no prior Claude Code session transcript (searched both). Per execution-protocol §2, F-001..F-005 below were **re-derived from code this session** and occupy the reserved slots; swap in the canonical pilot text if it differs.

**Classes:** TC = Trust-Collapse · FR = Friction · FI = Filter. **Rungs:** 1 Impossible · 2 Constrained · 3 Loud · 4 Recovered.

---

## STOP-SHIP (read this first — six root-cause clusters)

**S1 — Nobody is behind the promises. (SILENT × CRITICAL — worst in audit.)** `ADAM_NOTIFY_NUMBER` is absent from `functions/.env` (verified), so `notifyMoverSubmission` / `notifySuppliesKitSubmission` / the quote path all hit `console.warn('SMS notify not configured'); return;` (functions/getWorkflowQualifying.js:317-326, 340-351) — and unlike `notifyAdmin`, these paths write **no** `adminNotifications` fallback record. The callable still returns `success:true`. Today a user can book movers ("Request sent to Test Mover B"), order a kit, request a >100-mi quote ("within a day"), or file a **damage report** at check-in (submitCheckIn.js:33-51, "we'll follow up on anything that needs attention", MoveCheckInView.swift:288) — and no human is ever notified. There is also **no vendor-facing transport at all** in functions/ (no email/webhook; `chosen_vendor` is only read by the SMS builder and check-in). Findings F-006..F-009, F-056, F-060, F-064. *Fix direction:* rung 1/4 — route every "we'll handle it" submission through the durable `notifyAdmin` (Firestore record first, SMS second) and close L01; until then the promise copy is false.

**S2 — Placeholder vendors and uncalibrated prices are live. [SIM-verified]** Real comparison UI serves "Test Mover B $1,394–$2,675" and "Test Mover C $1,132–$2,173" from production Firestore; nothing client-side filters them and no placeholder flag reaches the client (vendorsData.json:2-192 `_adminNote` never seeded; Vendor.swift:166-179 filters only vertical+active). PricingConstants.swift is LOCKED-pending-calibration and L06 says "Do not expose mover prices publicly." Catalog copy compounds it: "binding estimates from three USDOT-licensed movers" [SIM]. F-008. *Fix:* L04/L05/L06/L07 close before any real user reaches comparison; interim rung 1 = seed `active:false`.

**S3 — Fake success on submission (client pattern).** `FlowEngineView.swift:537-545` (verified): on submission error the engine **deletes the saved answers** (`clearFlowState`) and calls `onComplete()` — confetti fired 1s earlier (TaskFlowSummaryCard.swift:74-79), task shows "Peezy is on it," no server record, answers unrecoverable. On `success:false` (:535) there is no else — the card wedges and the exit alert then claims "Your answers are saved." Same pattern: SETUP_INTERNET discards its submission result (`_ = try?`, SetupInternetFlow.swift:252-259), concierge "Peezy handling it" advances after a failed callable (PeezyHomeViewModel.swift:404-437), Home task-complete is fire-and-forget with no rollback (PeezyHomeViewModel.swift:377-387 + TaskActionService catch/print). F-010, F-011, F-022, F-016, F-061. *Fix:* rung 3 — submission failures must be loud, keep the payload, and never celebrate before the write.

**S4 — First-session silent collapse.** (a) Any Firestore error/empty read at launch routes a **completed** user back to the assessment (AppRootView.swift:145-151, 165-170). (b) The last-question Continue can latch dead forever after one failed write (`isCompleting` set at AssessmentCoordinator.swift:617, cleared only in never-called `reset()`). (c) CurrentAddress has no escape hatch when autocomplete yields nothing (CurrentAddress.swift:83; errors → empty list, AddressSearchManager.swift:118-122). (d) If generation fails once, the user gets confetti, "Your task list is ready," possibly "0 personalized tasks," then the paywall — and lands on a permanently "All caught up" empty home; sole recovery is destructive retake (AssessmentCoordinator.swift:660-675; GeneratingView.swift:179-183; SummaryView.swift:53; PeezyHomeViewModel.swift:586-589). F-023, F-030, F-031, F-034 (+F-005/F-033). *Fix:* rung 2/3 — real error states in the completion flow, a retry path for generation, an address escape hatch, clear the latch.

**S5 — Scan integrity: silent truncation is priced with full confidence.** Per-frame upload and frame-extraction failures are swallowed (InventoryStorageService.swift:82-86; FrameExtractionService.swift:78-82); the backend analyzes `0..frameCount-1` so trailing losses simply shrink the room; the result is tagged `.inventoryScan` and gets the **narrow** confidence band with zero disclosure (PricingEngine.swift:343-346) → systematic underquote → move-day price shock. Plus: interruption (call/backgrounding) deadlocks the camera on an undismissable "Processing frames…" overlay (RoomCaptureViewModel.swift:231-237 nil-continuation; InventoryCameraView.swift:92-99,404-420); `sessionManager.error` is written 4× and rendered 0× so every pipeline failure silently dumps to the room list with the video already deleted; the 70s client vs 120s server timeout mismatch makes long scans succeed server-side while the app errors and never installs the listener. F-038..F-042. *Fix:* rung 2/3 — verify frame manifest end-to-end, render the error field, observe interruption notifications, align timeouts.

**S6 — Data integrity at the edges.** (a) Move-date edit: success toast fires **before** any write, both writes are `try?`-swallowed, and only the packing plan regenerates — every other task's dueDate silently keeps the old move date (PeezySettingsView.swift:149-171, 816-848; IdentityService.swift:50-55). (b) Delete account destroys data first and deletes auth last; a mid-failure shows "deletion failed — try again" to a user whose data is already gone, and "all your data" leaves `vendorReviews`, `workflowSubmissions`, `estimateCalibration`, `adminNotifications` (incl. addresses) behind (functions/index.js:598-635). (c) Inventory frames live under `inventory/{uid}/…` but deletion only clears `users/{uid}/…` — home-interior photos survive account deletion, against the in-app "not stored" disclosure (index.js:623-625; InventoryFlowView.swift:228). (d) Check-in/kit/box-return restore closures ignore the persisted `"submitted"` path → force-quit at confirmation re-arms Submit → duplicate reviews/**duplicate vendor strikes**/duplicate orders (MoveCheckInView.swift:74-84; SuppliesKitView.swift:60-66; BoxReturnView.swift:44-58; submitCheckIn.js:78). F-052, F-053, F-045, F-055. *Fix:* rung 1/2 — order-of-operations + idempotency keys + delete-scope audit.

An honest note: the stop-ship list is not empty, and most of it is invisible in a happy-path demo — five of the six clusters are SILENT-dominant.

---

## Findings table

### Paywall moment — F-001..F-005 (reserved pilot slots, re-derived; see NEEDS CLARIFICATION above)

| ID | Moment | Failure | Class | Sev | Silence | Clock | Rung | Direction | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| F-001 | Paywall renders | StoreKit products fail to load → CTA disabled at 50% forever, prices "—"; `loadProducts` runs once at init, no retry, `purchaseError` never shown | TC (dead end at money moment) | MED | QUIET | any (CRITICAL at hard gate) | 3 | Retry products on paywall appear + visible failure copy | SubscriptionManager.swift:114-147; PaywallGateView.swift:163-165, 219 (verified: only init call site) |
| F-002 | Tap Subscribe | Purchase `.failed`/`.pending` → nothing happens; no error UI exists in the paywall; button silently re-enables | TC | MED | QUIET | any | 3 | Render purchaseError inline; distinct pending copy | PaywallGateView.swift:308-316; purchaseError read only in PeezySettingsView.swift:381 (verified) |
| F-003 | Tap Restore Purchases | Restore failure or nothing-to-restore → zero feedback; user taps repeatedly into silence (offer-code sheet errors also `try?`-dropped) | FR | MED | QUIET | any | 3 | Result feedback for both outcomes | PaywallGateView.swift:100-124 |
| F-004 | Hard gate at booking/kit/concierge | Reused paywall says "ASSESSMENT COMPLETE" weeks after assessment and sells features the user already has free (scanner, daily tasks, plan) at the booking moment | FR (confusion + feeling sold to) | MED | LOUD | CRITICAL | 2 | Context-aware header/features per PaywallGatedAction (copy via peezy-copywriter) | PaywallGateView.swift:47-73 fixed copy; PaywallPolicy.swift:63-90 reuse; **[SIM]** screenshot at vendor-select, T-2 |
| F-005 | Paywall immediately after generation | 15s failsafe forces ring→100%, "Your task list is ready," confetti, possibly "0 personalized tasks" — then asks for money right after a silent failure | TC | HIGH | SILENT | EARLY | 2 | Gate ReadyView on actual save/generation success; real error state instead of failsafe advance | GeneratingView.swift:173-183, 239-242; CompletionFlowView.swift:38; SummaryView.swift:53 (verified) — feeds S4 |

### First launch & auth

| ID | Moment | Failure | Class | Sev | Silence | Clock | Rung | Direction | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| F-023 | Signed-in relaunch | Any assessment-status query error or empty snapshot → completed user re-routed into the assessment; error is DEBUG-print only; no retry | TC | HIGH | QUIET | EARLY | 2 | Distinguish error from "no assessment"; retry + offline state | AppRootView.swift:145-151, 165-170 — S4 |
| F-024 | Cold start | `AppLoadingView` = spinner + "Loading..." with no timeout/retry/escape; stale-callback guard can leave `.loading` forever on server-side token revocation | TC | MED | QUIET | EARLY | 3 | Timeout → retry affordance | AppRootView.swift:71-72, 139-143, 178-242 `[HYP for revocation path]` |
| F-025 | SIWA/Google cancel | System-sheet Cancel treated as failure: error haptic + raw "AuthorizationError 1001" toast at the first trust moment | FR | MED | LOUD | EARLY | 1 | Filter `.canceled` codes; no toast on cancel | AuthViewModel.swift:113-115; AuthView.swift:64-70, 207 |
| F-026 | Auth button tapped | `loadingState` disables every control with no timeout; if completion never fires the screen is fully dead | TC | MED | QUIET | EARLY | 3 | Timeout resets loadingState | AuthView.swift:76-141 `[HYP]` |
| F-027 | Explainer → auth wall | `peezy.explainer.seen` set before an account exists; a user who bails at signup never sees the value proposition again | FR | LOW | QUIET | EARLY | 2 | Set flag at first authenticated session | ExplainerView.swift:80; AppRootView.swift:26 |
| F-028 | Forgot password | No loading state; three chained alerts race — a failed reset can look identical to success; unknown-email says "sent" | TC | MED | QUIET | EARLY | 3 | Single stateful reset UI | LogInView.swift:88-95, 131-152 `[HYP for race]` |
| F-029 | SIWA first auth | displayName commit is fire-and-forget; Apple sends the name once ever — both stores failing loses it permanently, no re-prompt | FR | LOW | SILENT | EARLY | 2 | Await + fallback name prompt in assessment | AuthViewModel.swift:92-101 |

### Assessment & plan generation

| ID | Moment | Failure | Class | Sev | Silence | Clock | Rung | Direction | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| F-030 | Last question Continue | `isCompleting` latches on a failed first write (`reset()` has zero callers) → dead button, no error, force-quit loses all answers | TC | HIGH | SILENT | EARLY | 2 | Clear latch on failure + surface saveError | AssessmentCoordinator.swift:617-618, 249, 648-656 — S4 |
| F-031 | Current address entry | Autocomplete empty/error → Continue disabled forever; no "I don't have it" hatch (NewAddress has one); completer errors silently emptied | TC | HIGH | QUIET | EARLY | 2 | Escape hatch + manual entry parity with NewAddress | CurrentAddress.swift:83; AddressSearchManager.swift:118-122; NewAddress.swift:95-105 — S4 |
| F-032 | Backgrounding mid-assessment | Zero draft persistence — process death loses ~30 answers, restart at intro | FR | HIGH | QUIET | EARLY | 2 | Persist answers per step (fence tension T1) | grep: no scenePhase/@AppStorage under Assessment/ |
| F-033 | Assessment save | saveAssessment failure fully silent: Crashlytics only; `saveError` rendered nowhere; `assessment_complete` analytics fires before writes | TC | HIGH | SILENT | EARLY | 3 | Render saveError + retry; move analytics after commit | AssessmentCoordinator.swift:627-629, 648-656 |
| F-034 | Plan generation | Generation failure → confetti + "ready" + permanently empty "All caught up" home; only recovery is destructive retake | TC | HIGH | SILENT | EARLY | 2 | Retryable generation + empty-plan repair path | AssessmentCoordinator.swift:660-675; PeezyHomeViewModel.swift:586-589 — S4 |
| F-035 | Move-date question | Continue disabled until the date is *changed*; returning users with a correct restored date are stuck until they wiggle the picker | FR | LOW | LOUD | EARLY | 1 | Treat restored value as selected | Datepickertemplate.swift:31, 85-87, 101 |
| F-036 | Retake (mid-failure) | Unbatched delete loop; partial failure leaves zero tasks + valid assessment → permanent "All caught up" empty state | TC | MED | QUIET | any | 2 | Batch/transaction the reset | PeezySettingsView.swift:633-682 |
| F-037 | Retake (aftermath) | `packingPlan/current` + `readiness/current` survive retake; plan exists in Firestore but is invisible until a full rescan; dialog under-discloses what's destroyed | TC | MED | SILENT | MID | 2 | Include packing docs in reset; honest dialog copy | PeezySettingsView.swift:643-658; TaskActionService.swift:220-234; **[SIM]** dialog text captured |

### Home & daily dose

| ID | Moment | Failure | Class | Sev | Silence | Clock | Rung | Direction | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| F-015 | Home load | Load error → "You're all caught up for today!" then "That's today." — network failure presented as a completed day; only signal is a dismissible raw-error toast, no retry | TC | HIGH | QUIET | any | 3 | Distinct error state + retry on Home | PeezyHomeViewModel.swift:309-314, 319-324 (verified) |
| F-016 | Task complete tap | Fire-and-forget write, no rollback: card leaves, confetti, counter++ — task resurrects next load; Tasks tab has proper rollback, Home doesn't | TC | MED | SILENT | any | 3 | Adopt Tasks-tab optimistic-revert pattern on Home | PeezyHomeViewModel.swift:377-387; TaskActionService.swift:79-88 — S3 |
| F-017 | Tasks tab error | "Couldn't load tasks / Tap to retry" — retry is dead: `start()` early-returns because the failed listener was never cleared; tab unrecoverable all session; error wall also replaces an already-loaded list | TC | MED | LOUD | any | 3 | Clear listener on failure; keep stale list visible | TasksStore.swift:31-32, 44-47 (verified); TasksTabView.swift:74-77 |
| F-018 | Dose freeze | Transient read failure (`try?`) is indistinguishable from "no dose" → today's frozen dose silently recomputed and overwritten mid-day | TC | MED | SILENT | any | 2 | Distinguish read-error from absent; never overwrite same-day | DailyDoseEngine.swift:21-28, 38-40 |
| F-019 | Snooze | Snooze increments the *done* counter — "3 of 5 done" and "on pace for [move date]" shown for deferred work | FR | MED | LOUD | CRITICAL | 2 | Count snoozes separately from completions | PeezyHomeViewModel.swift:519-532, 363, 182-186 |
| F-020 | Mid-day return | Device-local counter vs server dose desync → "Pick up where I left off / 3 tasks to go" button delivers "That's today."; get-ahead button can visibly no-op | TC | MED | QUIET | any | 2 | Derive progress from server task states | PeezyHomeViewModel.swift:578-651; PeezyHomeView.swift:323-325, 388-399 |
| F-021 | Card → flow present | `.activeTask` renders an exit-less "Loading your task..." spinner meant to hide behind the cover; re-present-from-onDismiss pattern can drop → permanent spinner (the pre-Spec-04 spinner class, mitigated not eliminated) | TC | MED | QUIET | any | 3 | Escape/timeout on activeTaskContent | PeezyHomeView.swift:336-352, 134-137; PeezyHomeViewModel.swift:76-82 `[HYP — intermittent]` |
| F-022 | "Peezy handles it" tap | `requestConcierge` failure caught+printed; task still advances to "Peezy is on it" — user waits on a request never delivered | TC | HIGH | SILENT | any | 3 | Loud failure; do not advance on error | PeezyHomeViewModel.swift:404-437 — S3 |

### Flow engine (all config-driven task flows)

| ID | Moment | Failure | Class | Sev | Silence | Clock | Rung | Direction | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| F-010 | Summary submit (throw) | Error → answers deleted + `onComplete()` + "Peezy is on it"; confetti fired before the call; no server record; unrecoverable | TC | HIGH | SILENT | any (paid path) | 3 | Keep payload, loud failure, retry; never complete on error | FlowEngineView.swift:510-547 (verified); TaskFlowSummaryCard.swift:74-79 — S3 |
| F-011 | Summary submit (`success:false`) | No else branch: card wedges (button disabled, back removed), flow state already cleared, exit alert then says "Your answers are saved" | TC | HIGH | SILENT | any | 3 | Handle false; reconcile exit-alert promise with clearFlowState | FlowEngineView.swift:532-535; FlowExitControl.swift:296-299 |
| F-012 | Any in-flow error toast | ToastOverlay is mounted once under the fullScreenCover — every error toast fired inside a flow is invisible (incl. all InAppTaskFlows save failures) | TC (enabler) | MED | SILENT | any | 3 | Mount overlay above covers / in-flow banner | PeezyMainContainer.swift:89 (sole mount); InAppTaskFlows.swift:174, 246, 319, 389 |
| F-013 | Flow open (offline/slow) | Definition fetch failure → "Coming right up — this one isn't quite ready in the app" for a fully-supported task; no retry affordance, copy discourages reopening | TC | MED | QUIET | any | 3 | Distinguish network failure from unbuilt; retry CTA | FlowEngineView.swift:573-606, 645-653; FlowDefinition.swift:243-284 |
| F-014 | "Open Task" on mini-assessment child rows | Server writes them without `workflowId` → routed to coming-right-up on a task badged "Peezy is on it" | FR | MED | LOUD | any | 2 | Stamp workflowId server-side or suppress Open | getWorkflowQualifying.js mini-assessment branch; PeezyCardFirestoreMapper.swift:40-41 |
| F-057b | Flow open (restore) | The only exit (X) is disabled until a no-timeout Firestore read resolves; slow network = trapped behind a greyed close | TC | MED | QUIET | any | 3 | Timeout on restore; enable exit | FlowExitControl.swift:57-59, 261, 305-306 |
| F-042b | Mid-flow resume | Restore failure silently restarts at step 1 with answers apparently gone (empty snapshot returned on `.failed`) | TC | MED | SILENT | any | 3 | Loud restore failure + retry | FlowEngineView.swift:467-506; FlowExitControl.swift:105-109 |

### Inventory scan

| ID | Moment | Failure | Class | Sev | Silence | Clock | Rung | Direction | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| F-038 | Mid-scan interruption | Call/Siri/backgrounding kills the session; delegate error dropped on nil continuation; Stop → permanent undismissable "Processing frames…" overlay swallowing the close button; scan lost, force-quit only | TC | HIGH | LOUD (trap) | MID | 2 | Observe interruption notifications; recover or fail loud | RoomCaptureViewModel.swift:231-237, 175-200; InventoryCameraView.swift:92-99, 347, 404-420 — S5 |
| F-039 | Upload/extraction losses | Per-frame failures swallowed; backend reads `0..frameCount-1`; truncated room → `status:'complete'` → priced with the narrow scan band, no disclosure → systematic underquote, move-day price shock | TC | HIGH | SILENT | CRITICAL (consequence) | 2 | Frame manifest verified end-to-end; widen band on loss | InventoryStorageService.swift:82-104; FrameExtractionService.swift:78-82; processInventory.js:102-111; PricingEngine.swift:343-346 — S5 |
| F-040 | Any pipeline failure | `sessionManager.error` assigned 4×, rendered 0× — user silently teleports to room list, temp video already deleted, no retry, no message | TC | HIGH | SILENT | MID | 3 | Render the error field (highest-leverage single fix) | InventorySessionManager.swift:277, 349-355; RoomCaptureViewModel.swift:212-215 — S5 |
| F-041 | Long processing | Client 70s default vs server 120s timeout → server completes, client errors first, snapshot listener never installed → finished scan permanently invisible | TC | HIGH | SILENT | MID | 2 | Align timeouts; install listener before the callable | InventoryAPIClient.swift:22; processInventory.js:63; InventorySessionManager.swift:341-347 — S5 |
| F-042 | Exit with unsaved rooms | Exit alert reads stale `_metadata` → "Your answers are saved. Pick up where you left off anytime." while today's scanned rooms are memory-only → Leave discards them | TC | HIGH | SILENT | MID | 2 | Alert from in-memory dirty state; offer Save-and-leave | ScanInventoryFlow.swift:48-52, 98-113; InventorySessionManager.swift:451-460; FlowExitControl.swift:176-199 — S5 |
| F-043 | Vision returns empty | `[]` = success: "Looks Good — 0 items"; confirmed empty room marks coverage resolved → priced confidently with no "rooms weren't scanned" disclosure | TC | MED | SILENT | MID | 2 | Zero-item review triggers a rescan-first state | processInventory.js:270-274; InventoryReviewViewModel.swift:103-106; InventoryCoverage.swift:147-171 |
| F-044 | Submit inventory | Batch commits, then move-date check throws → button flickers back, no message, inventory now locked server-side with no in-app edit path | TC | MED | SILENT | MID | 2 | Check prerequisites before commit; loud failure | InventorySessionManager.swift:507-539; InventoryFlowView.swift:48-54 |
| F-046 | Force-quit during processing | Session completes server-side but `loadExistingInventory` never scans `inventorySessions` → completed scan unreachable forever | TC | MED | SILENT | MID | 2 | Reconcile in-flight sessions on load | InventorySessionManager.swift:207-210 |
| F-045 | Account deletion vs frames | Frames live at `inventory/{uid}/…`; deletion clears `users/{uid}/…` only → home-interior photos persist after account deletion, contradicting the in-app "not stored" disclosure | TC | HIGH | SILENT | any | 1 | Fix deletion prefix + add reaper; reconcile disclosure copy | InventoryStorageService.swift:67; functions/index.js:623-625; InventoryFlowView.swift:228 — S6 |

### Movers booking spine

| ID | Moment | Failure | Class | Sev | Silence | Clock | Rung | Direction | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| F-006 | Booking submit (backend) | Submission lands in Firestore, callable returns `success:true`, "Matching vendors" badge — but `ADAM_NOTIFY_NUMBER` is absent → SMS skipped with a console.warn and **no adminNotifications fallback**; nobody is notified, ever | TC | HIGH | SILENT | CRITICAL | 1/4 | Durable notify (record-first) + close L01 | getWorkflowQualifying.js:283-289, 317-326 (verified); functions/.env keys (verified); LAUNCH_CHECKLIST L01 — S1 |
| F-007 | Confirmation screen | "Request sent to {vendor}" / "we'll confirm … as soon as the company responds" — no vendor-facing transport exists anywhere in functions/; the company was never contacted | TC | HIGH | SILENT | CRITICAL | 1 | Copy states the real mechanism until transport exists | MoversConfirmationView.swift:24-34; grep functions/ (no vendor email/webhook) — S1 |
| F-008 | Comparison cards | Live production UI shows Test Mover B/C with uncalibrated LOCKED prices as bookable movers; no client filter, no placeholder flag in the docs; task copy promises "binding estimates from three USDOT-licensed movers" | TC | HIGH | LOUD | CRITICAL | 1 | Close L04-L07; interim `active:false` on placeholders | **[SIM]** screenshots ($1,394–$2,675 / $1,132–$2,173); vendorsData.json:2-192; Vendor.swift:166-179; PricingConstants.swift:5-7 — S2 |
| F-009 | >100mi / concierge quote | "Hand-built mover quote within a day" — same absent-notify root cause; no timer, no tracking, no paywall parity with booking path | TC | HIGH | SILENT | CRITICAL | 4 | Same S1 fix + SLA tracking record | MoversFlowViewModel.swift:22-30; getWorkflowQualifying.js:347-351 (verified) — S1 |
| F-047 | Distance unknown | `moveDistanceMiles:nil` (migration or geocode failure) silently routes a crosstown move to "long-distance" concierge with a false explanation; comparison never shown | TC | MED | SILENT | MID | 2 | Distinguish nil from >100; re-geocode on demand | IdentityService.swift:90; PricingEngine.swift:205-210; AssessmentDataManager.swift:252 |
| F-048 | Out-of-market user | Full scan + up to 14 questions, then "No active movers currently cover this address" — Try again/Close only; nothing offered for the invested effort | FR | HIGH | LOUD | MID | 2 | Gate market coverage before capture; offer concierge/waitlist | MoversFlowViewModel.swift:321; MoversFlowErrorView.swift:27-32; vendorsData.json radii |
| F-049 | Reopen after booking | Re-entry re-runs `prepareComparisons()` (fresh geocodes, vendor query) — can show "Couldn't prepare prices," recomputed different prices, or dump the user back to capture for a booking already submitted; stale flow state never cleared | TC | HIGH | QUIET | CRITICAL | 2 | Terminal submitted state; never re-price a placed request | MoversFlowViewModel.swift:253-255, 555-563; clearFlowState never called by FindMoversFlow |
| F-050 | Vendor decode | One malformed vendor doc (missing crew tier) throws and kills the whole list for everyone; raw DecodingError shown | TC | MED | LOUD | CRITICAL | 2 | Per-document decode isolation | Vendor.swift:39-48, 171 |
| F-051 | Submit retry | Backend partial write (submission stored, later step throws) → client says "Nothing was booked"; retry `.add()`s a duplicate submission — no idempotency key | TC | MED | SILENT | CRITICAL | 2 | Idempotency key per booking | getWorkflowQualifying.js:242-295 |
| F-052b | Booking gate dismissed | Paywall dismissal silently voids the vendor tap — no message, tap-loop | FR | LOW | QUIET | CRITICAL | 3 | One-line "booking needs Peezy+" reminder state | FindMoversFlow.swift:69-74; **[SIM]** dismissal returns cleanly (selection preserved) |

### Packing, kit, readiness

| ID | Moment | Failure | Class | Sev | Silence | Clock | Rung | Direction | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| F-053 | Move-date edit | "Move date updated" toast fires before any write; both writes `try?`/guard-swallowed; only the packing plan regenerates — all other task dueDates silently keep the old date | TC | HIGH | SILENT | CRITICAL | 2 | Toast after commit; regenerate/recompute all date-derived tasks | PeezySettingsView.swift:149-171, 816-848; IdentityService.swift:43-56; TaskGenerationService.swift:338-360 — S6 |
| F-054 | Move-date edit (collateral) | Silently deletes the readiness checklist evidence and rewrites `deliveryBy` on a possibly already-placed kit order; completed packing sessions can resurrect via chunk renumbering | TC | MED | SILENT | CRITICAL | 2 | Warn + preserve; stable source keys | TaskActionService.swift:476-521, 498-501; PackingPlanEngine.swift:125, 340-343, 434-461 |
| F-058 | Readiness gate T-1 | All five items required, no N/A — house/full-service users can never truthfully complete; only exit is a false attestation that becomes vendor-overage *evidence against the user*; the "unready homes" consequence line renders only from move day, after it's actionable | TC | MED | LOUD | CRITICAL | 2 | N/A states per item; show consequence on T-1 | ReadinessGate.swift:61-77; PackingReadinessView.swift:97, 118-128; TaskActionService.swift:368-370 |
| F-059 | Kit offer | `deliveryBy = firstSession − 2d` with no clamp → "Deliver by [date already past] — before your first packing session"; no too-late state or alternative | TC | MED | LOUD | CRITICAL | 2 | Clamp to today; late-order path | TaskActionService.swift:181-187; SuppliesKitView.swift:130-135 |
| F-060 | Kit order tap | Paywall only at final tap after full customize; no delivery-address/charge confirmation, no cancel, no order view; human trigger is the S1 silent SMS; restore ignores "submitted" path → duplicate orders | TC | HIGH | SILENT | CRITICAL | 2/4 | S1 fix + order record UI + idempotency + disclose gate earlier | SuppliesKitView.swift:60-66, 295-337; getWorkflowQualifying.js:281-288, 340-360 — S1/S6 |
| F-055b | Packing session save | Save failure renders as "Couldn't load this session" and nils the loaded session — wrong diagnosis, state destroyed | FR | MED | LOUD | CRITICAL | 3 | Distinct save-failure copy, keep state | PackingSessionView.swift:167, 209-214 |
| F-019b | Session snooze at T-1 | "Do this later" = +2 days → hides the session past move day; it silently disappears while the plan counts it incomplete | TC | MED | SILENT | CRITICAL | 2 | Clamp snooze to pre-move dates | PeezyHomeViewModel.swift:519-532, 260 |
| F-020b | Behind pace | Dose admits max one packing session/day while reflow stacks several due — the "you're behind, movers charge by the hour" warning is real but the surface throttles the remedy | FR | MED | LOUD | CRITICAL | 2 | Allow catch-up sessions in dose when behind | DailyDoseEngine.swift:100-112; PackingPlanEngine.swift:152-155, 180-216 |

### ISP & providers

| ID | Moment | Failure | Class | Sev | Silence | Clock | Rung | Direction | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| F-061 | ISP plan chosen | Submission result discarded (`_ = try?`) then `onComplete()` unconditionally — choice silently dropped, task complete | TC | MED | SILENT | MID | 3 | Await result; loud failure | SetupInternetFlow.swift:239-262 — S3 |
| F-062 | ISP list load | <3 plans or any error → "We couldn't load internet plans. Check your connection and try again" — blames the user's connection for a catalog/seed problem; retry can never succeed; CTA hidden = dead end. One malformed seed doc kills the list for all users | TC | MED | LOUD | MID | 3 | Distinct error copy; per-doc decode isolation | SetupInternetFlow.swift:203-220, 154-164; ISPPlanService.swift:110 |
| F-062b | ISP for non-KC movers | Fixed KC catalog renders under "Plans for Denver, CO" with no serviceability caveat surfaced per-plan; staleness (`researchedAt`) parsed but never shown | FR | MED | LOUD | MID | 2 | Market gate or explicit KC-only banner; show as-of date | SetupInternetFlow.swift:113, 210-214; ISPPlanService.swift:31-43, 85-86 |
| F-063 | Provider row tap | Every resolver failure (offline, missing API key, timeout, parse) is laundered into concierge "We'll take it from here" — paid promise, no ticket/ETA; a backend outage converts every provider row into silent concierge; terminal then subject to F-010 fake-complete | TC | HIGH | SILENT | MID | 3/4 | Distinguish failure from genuine concierge; ticket record + copy | ProviderDirectoryService.swift:136-160; resolveProvider.js:360-362; ProviderActionCard.swift:264-273 — S1/S3 |

### Support chat

| ID | Moment | Failure | Class | Sev | Silence | Clock | Rung | Direction | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| F-064 | Send message | Input cleared before await; send failure erases the typed message with zero feedback (`service.error` never rendered); notify callable is `try?` — message can sit looking sent while support was never paged; offline is worst case; no per-message delivery state | TC | HIGH | SILENT | CRITICAL | 3 | Delivery states + failed-send retention; await notify or queue it | SupportChatService.swift:30-33, 66-78; SupportChatView.swift:205-211; **[SIM]** expectation copy verified good — S1 |

### Settings & account

| ID | Moment | Failure | Class | Sev | Silence | Clock | Rung | Direction | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| F-052 | Delete account | Data destroyed first, auth deleted last; mid-failure shows "deletion failed — try again" to a user whose data is gone; "all your data" leaves vendorReviews, workflowSubmissions, estimateCalibration, adminNotifications (with addresses) | TC | HIGH | QUIET | any | 2 | Reorder + widen delete scope + honest copy | functions/index.js:583-635; PeezySettingsView.swift:196-208, 679-710 — S6 |
| F-065 | Sign out | `try?` sign-out: a throw dismisses the alert and silently leaves the user signed in; per-device dose counters persist across accounts | FR | LOW | QUIET | any | 3 | Surface failure; clear per-user defaults | PeezySettingsView.swift:188-195; AuthViewModel.swift:204-208 |

### Post-move (check-in, box return)

| ID | Moment | Failure | Class | Sev | Silence | Clock | Rung | Direction | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| F-056 | Check-in submit (flags) | Damage/overcharge report saved; "we'll follow up on anything that needs attention" — flag SMS unconfigured (S1) and send failures swallowed; user's own report is never visible to them again | TC | HIGH | SILENT | CRITICAL | 4 | S1 durable notify; show the user their filed report | submitCheckIn.js:25-52, 98-108; MoveCheckInView.swift:288 — S1 |
| F-055 | Check-in re-submit | Restore ignores `"submitted"` path → force-quit at confirmation re-arms Submit; new review doc id each call → duplicate review + duplicate vendor strike; post-commit Twilio timeout surfaces as false "couldn't save" inviting exactly that retry | TC | MED | SILENT | CRITICAL | 2 | Honor restored path; idempotency key; commit-then-ack | MoveCheckInView.swift:74-84; submitCheckIn.js:78, 98-108; submitCheckInCore.js:165-178 — S6 |
| F-057 | Check-in open | Failure of the *optional* booking-context read blocks the entire check-in ("Couldn't load your check-in") the day after the move | TC | MED | LOUD | CRITICAL | 3 | Degrade gracefully without context | MoveCheckInView.swift:112-134, 388-397 |
| F-066 | Box return | Honest partial-failure copy (the template to copy!) — but pickup retry is non-idempotent (duplicate concierge tickets), read-back can report false failure, and unparseable kit JSON bricks the card ("couldn't find the packing kit you ordered") | FR | MED | QUIET | CRITICAL | 2 | Request ids; tolerant kit parse | BoxReturnService.swift:36-40, 65-81; BoxReturnView.swift:44-58; index.js:399-411 |
| F-067 | Pre-move To-Do list | "Tell us how moving day went" sits in To-Do *before* the move (surface gating applies to the dose, not the Tasks tab) — time confusion at a glance | FR | MED | LOUD | CRITICAL | 2 | Hide date-gated tasks from To-Do until eligible | **[SIM]** visible at T-2; taskCatalogData.json `surfaceAfterDaysPastMove`; TasksStore shows all docs |

---

## Fence tensions (locked fences — tensions recorded, no fence changes proposed)

1. **Long assessment (tribe filter)** × F-032: the fence multiplies the cost of the missing draft persistence — losing 30 answers to a phone call is not filtering, it's tax. Tension resolves at the persistence layer, not the length.
2. **Paywall placement §10(c)** × F-004/F-060: placement is locked and untouched; the tension is stale header copy at the hard gate and the kit gate disclosed only at the final tap. Copy/disclosure fixes stay inside the fence.
3. **Dose boundary ("done for today" is a feature)** × F-019/F-020: deferrals counted as completions make the boundary read as flattery; the fence stays honest only if the counting is honest.
4. **Directed action (no choose-your-own-adventure)** × F-058/F-048: fully-directed checklists need N/A states, and directed capture needs a market gate before investment — otherwise direction becomes a trap for the user the design didn't imagine.
5. **Boring-on-purpose plainness** × the fabricated progress theaters (GeneratingView's synthetic %, camera's "Peezy AI is scanning…", processing view's looped copy): declared honesty elsewhere makes simulated liveliness a liability when it masks real failure (F-005, F-038-41).

## Accepted as-is (do not relitigate)

- **KC-only vendor market at launch** — geographic scope is a launch decision (L04); the *finding* is only the late discovery point (F-048), not the limitation.
- **Assessment length** — tribe filter, locked founding principle.
- **One-bundle supplies kit, no line-item shopping** — locked design; customize hatch exists.
- **Hard gate at booking/kit/concierge with dismissible soft offer post-assessment** — Review #3-approved §10(c).
- **Buttons-not-swipes, boring-on-purpose visual plainness** — locked.
- **ISP affiliate fallback to official provider URLs** — correct behavior while L02 is pending; user experience is unharmed.
- **Concierge (n8n/manual) fulfillment model itself** — the MVP is human-powered by design; findings target only its *silent* notification layer and missing expectation-setting, not the model.

## Observability adds (required companions for QUIET/SILENT fixes)

1. Every submission path (booking, kit, quote, check-in, concierge, support notify): durable Firestore record **before** best-effort SMS + an alert on `SMS notify not configured` in production (S1).
2. Client: report the swallowed-error classes to Crashlytics as non-fatals with distinct keys — flow submission failure (F-010), task-write failure (F-016), dose overwrite (F-018), scan pipeline failure (F-040), userKnowledge/assessment save (F-033). Several exist as prints today; none are queryable.
3. Funnel gaps: no `explainer_start`, no auth events, `assessment_complete` fires pre-write — the acquisition funnel cannot currently reveal any of S4.
4. `workflowSubmissions` age alarm: any `pending_matching` doc older than N hours with no admin action = the S1 black hole made visible.

## Appendix — cosmetics (one-liners, out of scope)

- Two stacked X buttons on inventory hub/submitted views [SIM].
- "Same scope. Three prices." headline hardcoded regardless of quote count (MoversComparisonView.swift:21).
- Explainer advances on any-tap + button (possible double-advance skip), progress dots not tappable.
- Pull-to-refresh on Tasks list is a 400ms cosmetic sleep (TasksList.swift:18-20).
- Paywall weekly card shows no savings math against annual.
- Sign-up password rules only visible as placeholder text; disabled button gives no reason.
- Greeting shows account first name ("Hey, Peezy." for the test bot) — verify real-name rendering widths.
- `arrivalWindow` free-text accepts any string into the vendor payload (validation, not exit-risk).

## Method & evidence notes

- Moment inventory per run-doc Phase 1 executed across six parallel read-only subsystem audits (auth/launch, assessment/completion, home/dose/flow-engine, inventory scan, movers/paywall, packing/ISP/settings/post-move) + LAUNCH_CHECKLIST live-state reconciliation + direct reads of the paywall stack.
- Simulator pass (fresh build of `64aa5b2`, iPhone 17 Pro, test account at T-2): comparison placeholders, hard-gate paywall copy, paywall dismissal return, force-quit mid-flow → resume, exit-confirmation copy, support-chat expectation copy, Settings/retake dialog, pre-move check-in visibility. Screenshots live in the session transcript.
- Independently re-verified against source before ledger entry: FlowEngineView:537-545 catch-completes; TasksStore:31-32 dead retry; `functions/.env` key names + getWorkflowQualifying.js:317-326/347-351 notify guards; PeezyHomeViewModel:309-324 error→"caught up". LAUNCH_CHECKLIST L01/L04/L05/L06 corroborate S1/S2 as live production state.
- Offline-specific behaviors were **not** induced live (cutting the host network would sever this autonomous session); all offline findings rest on code citations and are conservative.
- Known incidents imported: the pre-Spec-04 permanent-spinner class appears as F-021 (mitigated, not eliminated); pilot paywall findings occupy F-001..F-005 as re-derivations (see header).
