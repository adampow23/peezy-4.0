# Post-Test Cleanup — Phase A report

## Result

Writer gates and independent validation pass for revised A1 and original
A2–A4.

## Acceptance evidence

- **A1.1 / A1.2 — outer exit and teardown:** the installed DEBUG candidate was
  launched through 21 routed flow families: `scan_inventory`,
  `quote_selection`, `admin_memo`, all four catalog in-app flows, all five
  packing/post-move flows, all eight custom flow families, and a config-driven
  `manage_bank` flow. Accessibility found exactly the router-owned 44pt
  `flow.exit` control in every route. Tapping it advanced every route to the
  fixture's terminal teardown marker; the final marker read
  `TERMINAL: dismissed 21/21 routes`. All 20 routes with known-empty answer
  state exited immediately. `scan_inventory` completes its one external-state
  discovery before enabling the X, so the X path itself performs no network
  wait; the fixture conservatively warned because Firestore could not prove
  that external inventory state was empty. Nested inventory mutations are
  cached in memory and force the unsaved state until persistence is confirmed.
- **A1.3 — confirmed saved state:** a DEBUG saved-answer fixture produced the
  exact `Leave this task?` title, exact saved body, and `Leave` / `Keep going`
  buttons. `Keep going` preserved the flow and a second saved-state prompt;
  `Leave` removed the entire flow and produced the terminal marker.
- **A1.4 — failed/unknown state:** the inventory lookup failure produced the
  exact locked connection body and `Leave anyway` / `Keep going` buttons. The
  coordinator exposes a flow-scoped `lastPersistenceError`; pending and failed
  generic step writes select the same unsaved prompt. Readiness writes mark the
  coordinator pending before the domain write, mark it succeeded only after
  that write returns, and retain an attempted-answer probe on failure so a
  failed first answer cannot fall through to immediate dismissal.
- **A1.5 — resume contract:** every route now shares one coordinator. Config
  flows and custom flows persist the full outer path plus the complete answer
  map atomically. Restores happen before the local mutation observer is armed,
  and custom paths clamp restored step/card indexes. Nested mover inventory,
  address drafts, kit customization, and externally persisted inventory answers
  feed the same flow snapshot. Standard-flow content cannot receive taps until
  restoration completes. The mover restore rebuilds scope, comparison data,
  quote route, and the selected quote required by its saved outer stage,
  including vendor booking and vendor confirmation. Nested presentation
  booleans are not restored, so re-entry starts at the outer saved step and a
  nested sheet cannot outlive the removed outer hierarchy.
- **A2:** on a separate fresh iOS 26.4 simulator, explainer card 1 rendered
  before any auth control. Cards 1–5 were walked; card 5 contained the exact
  sanctioned signup body. `Let's go` routed to Auth. A process relaunch went
  directly to Auth, proving the existing device-scoped seen key was retained.
- **A3:** both `.dailyComplete` and `.allComplete` now render
  `dailyCompleteEmptyState`, which has no `glassCard` wrapper. The deleted
  render path was `PeezyHomeView.allCompleteCard`: its named completion card,
  glass chrome, personalized `You're all set` title, and
  `all_complete_view` render path were removed entirely. The shared empty state
  keeps the locked `That's today.` / pace copy and uses a bordered secondary
  get-ahead action.
- **A4:** a separate **Snoozed** section was chosen because it preserves the
  existing three Tasks filters and the app's four-tab shell while keeping
  deferred work visible in context. Every visible task with a future
  `snoozedUntil` enters the section before its status bucket is evaluated;
  expired and dateless tasks stay in their normal buckets. Each snoozed row
  renders `Returns {abbreviated date}`.

## CORE walked diff

- `FlowExitControl.swift` owns the one outer X, answer aggregation, serialized
  persistence state, last-error tracking, exact dialogs, and teardown callback.
  Restore results cannot overwrite newer local or externally confirmed writes;
  the X is disabled until generic restoration and any declared external answer
  discovery have completed.
- `FlowProgressSession.swift` is the common custom-flow adapter: restore first,
  block interaction until restore finishes, then observe and persist the whole
  snapshot. It also registers the one whole-flow answer probe used by
  domain-persisted nested state.
- `TaskFlowRouter.swift` wraps every capture, admin, in-app, packing/post-move,
  custom, and config-driven route once. Leaf `onDismiss` actions request an
  outer exit; nested sheets keep their own native bindings.
- `TaskActionService.swift` replaces the old swallowed per-key progress write
  with throwing, atomic `{flowPath, flowAnswers}` writes and a throwing restore.
  Supplies-kit loading now returns its persisted customization marker.
- `PeezyMainContainer.swift` and `PeezyHomeView.swift` capture and restore the
  originating tab only after the routed hierarchy actually dismisses.
- `MoversFlowViewModel.swift` and `FindMoversFlow.swift` persist only user
  refinement deltas, aggregate capture answers, restore the outer mover stage,
  rebuild that stage's scope/quote dependencies, and deliberately do not
  resurrect the nested inventory cover.
- The standard custom flows, in-app flows, packing/post-move flows, quote flow,
  and inventory route each expose their answer/path state through the shared
  coordinator. Kit/address/inventory sub-surfaces retain native dismissal to
  the parent.
- `AppRootView.swift` changes routing only; auth/SIWA internals are untouched.
  `ExplainerView.swift` changes only the pre-auth documentation and locked card
  5 body.
- `PeezyHomeView.swift` deletes the `.allComplete` card renderer and unifies
  both completion cases on the chrome-free empty state.
- `TaskGrouping.swift`, `TasksList.swift`, `TaskRowHeader.swift`, and
  `TasksTabView.swift` separate future-dated snoozes, show their return dates,
  and keep existing tab counts/filter structure.
- `PeezyV1App.swift` adds DEBUG-only validation fixtures; production routing is
  unchanged.

## A1.6 future-chip persistence audit

This is deliberately scoped to persistence reached while walking task-flow
answer and terminal paths; it is not a repository-wide `try?` audit. Phase A
does not change the following pre-existing behaviors:

- `TaskActionService.swift:20` — `setStage` catches and logs a failed stage
  write without propagating it.
- `TaskActionService.swift:74` — `clearFlowState` catches and logs a failed
  terminal cleanup write; callers still continue their terminal action.
- `TaskActionService.swift:85`, `:96`, `:111`, and `:126` — completion,
  in-progress, user-in-progress, and snooze writes each catch and log without
  propagating failure; their Home/Tasks call sites proceed with local terminal
  teardown.
- `TaskActionService.swift:692–694` — readiness prefill uses two `try?` reads
  for reserve-access task/response evidence, collapsing read failure to absent
  evidence.
- `IdentityService.swift:64`, `:73`, `:78`, and `:94` — identity loading and
  assessment migration use three `try?` reads, and migration catches its
  identity write without surfacing failure; in-app answer flows can therefore
  continue from missing or not-actually-persisted identity context.
- `IdentityService.swift:178` — add-address answer persistence encounters a
  swallowed geocoding failure: `geocodedDistance` returns `nil`, so the address
  write can continue without derived distance/interstate context.
- `InventorySessionManager.swift:186` — an inventory metadata read failure is
  collapsed to `.draft`; the outer scan flow's separate probe now treats its
  own lookup failure as unknown, but this loader still swallows the cause.
- `InventorySessionManager.swift:191` — coverage setup reads user knowledge
  with `try?`, collapsing a failed knowledge read to missing knowledge.
- `InventorySessionManager.swift:203` — coverage-input failure is swallowed by
  configuring empty fallback inputs.
- `InventorySessionManager.swift:233` — inventory-row load failure is logged
  only in DEBUG and the flow continues with the previously derived status.
- `InventoryStorageService.swift:82` — an individual captured-frame upload
  failure is logged only in DEBUG and upload continues with remaining frames.
- `ScanInventoryFlow.swift:110` — an external inventory-status read failure is
  converted to `.unknown`; Phase A safely maps that to the unsaved-exit dialog,
  but the underlying persistence-read error is not propagated.
- `InAppTaskFlows.swift:47` — the assessment-to-user-knowledge mirror uses
  `try?`; the primary assessment write can succeed while the mirror fails.
- `InAppTaskFlows.swift:68` — incremental task generation catches and logs its
  persistence failure; answer-writing flow callers still complete.
- `InAppTaskFlows.swift:233` — move-date identity persistence uses `try?`; the
  assessment write can complete while the identity write fails.
- `AdminMemoFlow.swift:199` — mark-read task completion uses `try?` and fires
  `onComplete` without awaiting the result.
- `SetupInternetFlow.swift:209` — workflow-answer submission uses `try?` and
  completes the flow regardless of the result.
- `QuoteSelectionFlow.swift:397` — one catch covers both the selected-quote
  task-document update and the notification callable, then completes the flow
  regardless of which operation failed.
- `MoversBookingPayload.swift:142` — terminal booking-answer JSON encoding uses
  `try?` and writes the fallback string `{}` when serialization fails.
- `BoxReturnService.swift:92` — persisted supplies-kit answer decoding uses
  `try?`, collapsing malformed or unreadable kit JSON to no delivered count.
- `CheckInService.swift:98` — persisted mover-booking answer decoding uses
  `try?`, collapsing malformed or unreadable booking JSON to missing check-in
  context.
- `SuppliesKitView.swift:329` — post-order matching-task generation catches and
  logs failure while the order flow still enters its submitted terminal.
- `FlowEngineView.swift:470` — a `flowRows` read failure is logged and replaced
  with an empty row set.
- `FlowEngineView.swift:523` — summary submission failure is swallowed by the
  legacy best-effort terminal path, which clears state and completes anyway.
- `FindCleanersFlow.swift:250`, `RentTruckFlow.swift:106`,
  `RemoveItemsFlow.swift:229`, `SellItemsFlow.swift:186`,
  `HandleAutoInsuranceFlow.swift:452`, and
  `HandleHomeInsuranceFlow.swift:451` — each custom flow catches workflow
  submission failure and calls `onComplete` anyway.
- `PeezyHomeViewModel.swift:424` — concierge-notification callable failure is
  logged after the status transition, and the task-flow terminal teardown
  continues.

The new `writeFlowProgress` path itself contains no `try?` or swallowed catch:
errors propagate into `FlowExitCoordinator.lastPersistenceError` and select the
locked unsaved-answer dialog.

### A1.6 completion recheck

A fresh `rg` pass covered the flow engine, every routed task-card family,
inventory flow/session/storage, task progress/status writers, mover flow and
payload construction, persisted box-return/check-in answer readers, workflow
submission, and the identity/geocode path reached by in-app address answers.
Every `try?`/`catch` hit reconciled as follows:

- **Reported future-chip hazards above:** `TaskActionService.swift:20,74,85,96,111,126,692–694`;
  `InventorySessionManager.swift:186,191,203,233`;
  `InventoryStorageService.swift:82`; `IdentityService.swift:64,73,78,94,178`;
  `ScanInventoryFlow.swift:110`; `InAppTaskFlows.swift:47,68,233`;
  `AdminMemoFlow.swift:199`; `SetupInternetFlow.swift:209`;
  `QuoteSelectionFlow.swift:397`; `MoversBookingPayload.swift:142`;
  `BoxReturnService.swift:92`; `CheckInService.swift:98`;
  `SuppliesKitView.swift:329`; `FlowEngineView.swift:470,523`;
  `FindCleanersFlow.swift:250`; `RentTruckFlow.swift:106`;
  `RemoveItemsFlow.swift:229`; `SellItemsFlow.swift:186`;
  `HandleAutoInsuranceFlow.swift:452`; `HandleHomeInsuranceFlow.swift:451`;
  and `PeezyHomeViewModel.swift:424`.
- **Surfaced or rethrown, so not swallowed hazards:**
  `FlowExitControl.swift:88,146`; `InventorySessionManager.swift:273,349`;
  `InventoryStorageService.swift:43,105`;
  `MoversFlowViewModel.swift:137,151,163,237,268,323,367,402`;
  `PeezyHomeViewModel.swift:309`; `PackingReadinessView.swift:202,229`;
  `AdminMemoFlow.swift:186`; `WorkflowService.swift:49`;
  `MoveCheckInView.swift:344,372`; `InAppTaskFlows.swift:170,242,315,384`;
  `PackingSessionView.swift:190,209`; `BoxReturnView.swift:244,265`;
  `SetupInternetFlow.swift:181`; `SuppliesKitView.swift:266,286,334,346`;
  and `QuoteSelectionFlow.swift:349`. These paths set visible error/failed state,
  retain the flow for retry, or rethrow after recording the error.
- **Matched by the source sweep but outside flow-answer persistence:**
  `PeezyHomeViewModel.swift:235` is best-effort packing-plan reconciliation
  during task-list load; `FlowDefinition.swift:260,280` is definition-source
  fallback; and `FlowEngineHarness.swift:116` is DEBUG fixture-file loading
  with a visible harness error. None persists or decodes a user's flow answer.

This reconciliation leaves no unmatched hit in the declared A1.6 closure.

## Independent validator

PASS. The functional validator passed A1.1–A1.5 and A2–A4 after exercising all
21 routed flow families. Per the user's report-only completion instruction, a
fresh validator then reran only A1.6: all 77 bounded `try?`/`catch` hits
reconciled across the three categories above, `IdentityService.swift:178` was
present, and no hit was unmatched or misclassified.
