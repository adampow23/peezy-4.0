# PHASE2_BUILD — Phase 2 v4 audit-gate stop report (2026-09-01)

## Audit gate (read-only at committed `b4b047d`)

| Item | Disposition | Gate result |
|---|---|---|
| 1 — external CTA sites | **INVENTORY COMPLETE · SUPPORTED** | Every reachable call/portal/website/map/share escape can await a handoff persist before opening without changing the action or moving an existing side effect. Ancillary Settings/legal escapes are explicitly excluded from outcome handoffs. |
| 2 — row-render paths | **INVENTORY COMPLETE · SUPPORTED WITH BINDING** | Home and Tasks receive the shared mapped `PeezyCard`, including all current contract fields, with no per-row fetch. A non-rendering context menu can preserve legacy model bytes and closed-row rendering; the menu is an intentional interaction delta, so literal behavior identity cannot also be claimed. |
| 3 — URL/notification entry points | **INVENTORY COMPLETE · SUPPORTED** | The single Google `onOpenURL` handler can retain Google as its fallback, while the notification delegate can add a typed task route and cold-start persistence. |
| 4 — W0 disposition actions | **SUPPORTED WITH v3/v4 TRIGGER BINDINGS** | All six enumerated actions can use the Phase 1 builder/validation/fingerprint/history machinery. `assignOwner` and `markSelfHandling` require a newly user-confirmed future consequential trigger; `markWaitingOnExternal` requires a user-confirmed institution-promised date or labeled move estimate/user-picked fallback. Missing/unconfirmed triggers fail closed; the server supplies no default and retains no wake-cleared trigger. |
| Design — W1 contracted outcome coverage | **CONTRADICTED — STOP** | v4 fixes the processing outcome with `markWaitingOnExternal`, but “I couldn't finish → Get help from a person” still has no authorized task transition. Locked A6 requires `pending` + `SUPPORT_ACTIVE`; W0 has no support action, H54 has none, support chat writes no task contract, and rules deny a client-side contracted-task writer. |
| 5 — notification-intent surface | **SUPPORTED WITH BINDING** | Admin/server direct writes need no client rule or composite index. Keep the queue server-only and test through offline fakes; any production client query/read requires a fresh rules/index audit. |
| 6 — research posture schema | **SUPPORTED AS AN ADDITIVE MIGRATION** | The current schema is string-only, but cached legacy briefs can remain byte-identical while normalization, cleanup, and Swift decode jointly accept a new object item shape. |
| 7 — scene-phase flush | **SUPPORTED WITH BINDING** | Flush only when submission and terminal locks are both clear; existing barriers own their drains. A background task is required to support the zero-loss suspension claim. |
| 8 — offline XCTest selection | **SUPPORTED** | The four Phase 1 unit suites and future named Phase 2 suites can be selected exactly; retain the UI skip, no test plan, and no integration opt-in environment. |

Gate result: **STOPPED before executable-spec authoring and implementation.**
The v3 trigger amendment and v4 sixth action resolve the two prior item-4/W1
contradictions, and gate items 1–8 are individually supportable under the
recorded bindings. The claimed full outcome-to-action mapping is nevertheless
contradicted: the locked support outcome has no truthful server-owned task
transition within the exhaustively authorized six-action surface. No
executable spec, post-gate executable-spec review artifact, implementation worktree, code change,
seed, deploy, production connection, StoreKit action, callable invocation,
remote write, or FCM send was performed.

### v4 outcome-to-action reconciliation

| A4 outcome path | Required persisted result | Authorized route | Result |
|---|---|---|---|
| Fully handled | `Completed` + `COMPLETED` after the caller confirms the required profile is closed | `markCompleted` | **SUPPORTED** |
| Got what I needed | Action/profile-keyed: `COMPLETED` only if this closes every required milestone; otherwise the remaining milestone stays in an owned nonterminal state | caller policy selects `markCompleted`, `markSelfHandling`, or `markWaitingOnExternal`; never label-hardcoded | **SUPPORTED WITH BINDING** |
| They're handling it / They're processing it | `matching_in_progress` + `WAITING_ON_EXTERNAL` with owner, expectation, and confirmed verification trigger | `markWaitingOnExternal` | **SUPPORTED by v4** |
| Sent | Action-keyed: `COMPLETED` only if sending satisfies the row's final required milestone; otherwise `WAITING_ON_EXTERNAL` for the required response/receipt/money tail | caller-supplied outcome policy selects `markCompleted` or `markWaitingOnExternal`; never label-hardcoded | **SUPPORTED WITH BINDING** |
| I need to do one more thing / submit something else / need proof or another document | Current row remains `InProgress` + `USER_ACTION_TRACKED`; an optional child may represent a distinct follow-up | `markSelfHandling(nextAction, confirmedTrigger)` is mandatory for the current row; existing spawn is secondary only | **SUPPORTED WITH BINDING** |
| Ready to send later | `InProgress` + `USER_ACTION_TRACKED`; the known written notice remains the concrete action with its send-by trigger | `markSelfHandling("Send …", confirmedTrigger)` | **SUPPORTED WITH BINDING** |
| I couldn't finish / It didn't work / Couldn't complete it | No terminal write; reveal the same three-way failure resolver | resolver branches below | **SUPPORTED WITH BINDING** |
| Failure resolver → Do this later | `Snoozed` + `DEFERRED` | `deferTask(confirmed date/event)` | **SUPPORTED** |
| Failure resolver → Try another route | Preserve/replace the concrete user action and resume at the alternate handoff; never complete the row | a fresh confirmed `markSelfHandling` envelope before the alternate CTA | **SUPPORTED WITH BINDING** |
| Failure resolver → Get help from a person / It's stuck | `pending` + `SUPPORT_ACTIVE` with backed SLA and self-service fallback | none of W0, H54, legacy, or Support Chat | **CONTRADICTED — STOP** |

### Item 1 — exhaustive external CTA inventory

| Surface | Committed file:line evidence | Existing ordering and executable-spec binding |
|---|---|---|
| Provider portal / official website | `Peezy 4.0/MainInterface/Views/ProviderActionCard.swift:156-159,228-236,374-379` | Tap sets the Safari destination and the sheet creates `SFSafariViewController`; there is no task write. A future handoff persist can be awaited before setting the destination. |
| Provider phone call | `ProviderActionCard.swift:239-261` | Tap sanitizes the number, creates `tel:`, and calls `openURL`; there is no prior mutation. Persist can run first. |
| Provider fallback/citation website (defensive branch) | `ProviderActionCard.swift:264-280`; `ProviderDirectoryService.swift:55-64,188-200,294-295` | A direct `Link` can open a citation URL, but current production concierge construction supplies no citations, so the branch is presently unreachable. If a resolver later preserves citations, bind it by replacing `Link` with an async button that persists before opening. |
| Data-driven provider mount | `Peezy 4.0/Tasks/FlowEngine/FlowEngineView.swift:246-280,453-483,510-518,546-555` | The flow records provider/method progress before the action card appears. This is queued flow progress, not a handoff record. The mount has `taskId`; pass it into the shared session. |
| Auto-insurance provider mount | `Peezy 4.0/Tasks/Task Cards/HandleAutoInsuranceFlow.swift:171-177,243-271` | Resumable local flow state precedes the same action card. The external tap has no required pre-open side effect. |
| Home-insurance provider mount | `Peezy 4.0/Tasks/Task Cards/HandleHomeInsuranceFlow.swift:170-176,242-270` | Same ordering and binding as auto insurance. |
| Task-detail directions | `Peezy 4.0/Tasks/Views/TaskDetailView.swift:118-124`; `Peezy 4.0/Tasks/Views/TaskContentSections.swift:145-150,279-305` | `TripKitSection` uses a direct Apple Maps `Link`; checklist changes are independent. `TaskContentContainer` already has the task document ID. |
| Task-detail catalog deep link | `TaskContentSections.swift:20-51,151-155,344-404` | All visible branches use one direct link helper. Persist can precede open. The current deep-link catalog rows are flow-routed, so the site is conditionally reachable but no active committed row presently displays it. |
| Research source website — task detail | `Peezy 4.0/Tasks/Views/TaskResearchModule.swift:142-164,591-624`; `TaskDetailView.swift:200-213` | The allowlisted source is a direct `Link`; task detail already has `taskDocumentId`. |
| Research source website — post-flow | `TaskResearchModule.swift:142-164,591-624`; `Peezy 4.0/Tasks/FlowEngine/PostFlowForkView.swift:18-28,112-137`; `FlowEngineView.swift:126-135` | The caller has `taskId`, but the fork initializer currently drops it. Passing the ID is plumbing, not a design contradiction. |
| Movers inventory share | `Peezy 4.0/Tasks/Task Cards/MoversEquipView.swift:83-104`; `FindMoversFlow.swift:127-138`; `TaskFlowRouter.swift:202-210` | `ShareLink` immediately presents the system share sheet. An awaited guarantee requires an explicit button/share presenter with unchanged share content. |
| Scanner submitted-inventory share | `Peezy 4.0/Inventory/Views/InventoryLockedView.swift:26-50,70-79`; `InventoryFlowView.swift:54-60`; `Peezy 4.0/Tasks/Task Cards/ScanInventoryFlow.swift:32-77` | Same `ShareLink` binding. Task-hosted scanner has `taskId`; Settings reuse has no row handoff context and must not create one. |
| Scanner permission Settings | `Peezy 4.0/Inventory/Views/InventoryCameraView.swift:175-202,507-511`; `InventoryFlowView.swift:86-96` | `canOpenURL` then opens iOS Settings with no task mutation. This is system remediation, not an action/outcome CTA, and must not create an outcome question. |
| Task-reachable paywall legal links | `Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift:125-131`; `TaskDetailView.swift:99-106`; `PostFlowForkView.swift:33-37`; `TaskFlowRouter.swift:277-323` | Direct policy/terms links have no mutation. They are ancillary legal navigation and must not mark a task in progress or request an outcome. |

Negative reconciliation for item 1:

- FlowEngine summary, status, and spawn routes have no external CTA
  (`FlowEngineView.swift:310-346`). `TaskFlowSummaryCard` changes local
  presentation state and calls its internal terminal
  (`Peezy 4.0/Tasks/Task Card Components/TaskFlowSummaryCard.swift:74-81`);
  `TaskFlowStatusCard` invokes internal callbacks only
  (`TaskFlowStatusCard.swift:38-55`).
- Task-detail call-sheet content is text only
  (`TaskContentSections.swift:207-235`).
- Supplies has no external call/portal/website/mail/map/share transition.
  “Send kit request” is an in-app server submission
  (`Peezy 4.0/Tasks/Task Cards/SuppliesKitView.swift:213-219,446-480`).
- The remainder of the movers chain has no external action CTA. Its buttons
  perform internal durable chain/support operations
  (`Peezy 4.0/MainInterface/Models/MoversFlowViewModel.swift:284-321,384-415`).
- No committed task UI uses `mailto:`, `MFMailComposeViewController`, or
  `MKMapItem.openInMaps`; there is no additional map escape beyond the
  inventoried Directions `Link`. The active flow JSON has no URL/mail/tel
  literal.

Search scope: every committed Swift source under task, inventory, and main UI
was searched for `Link`, `ShareLink`, `openURL`,
`UIApplication.shared.open/canOpenURL`, `SFSafariViewController`, `tel:`,
`mailto:`, map/mail/web/activity APIs, then every hit was traced through its
committed router and mount. Catalog and flow JSON were searched separately.

### Item 2 — exhaustive reachable row-render inventory

Reachability and shared data:

- `AppRootView.swift:91-94` mounts the main container for assessed users;
  `PeezyMainContainer.swift:64-84` contains the only reachable Home and Tasks
  branches.
- Home maps query documents at
  `PeezyHomeViewModel.swift:411-425`; Tasks maps its collection listener at
  `Peezy 4.0/Tasks/Store/TasksStore.swift:31-54`. Both use the explicit shared
  path in `PeezyCardFirestoreMapper.swift:4-15`.
- The mapper supplies `status` (`:16-17`), dates including `snoozedUntil`
  (`:30-37,81-90`), contract presence and recursive nested values
  (`:64-65,108,112-166`). The decoded contract includes disposition,
  terminal kind, owner, next action, next trigger, resume destination, visible
  copy, profile version, external-submission marker, and supersession pointer
  (`:127-138`).
- The same model surface and coherence rules are in
  `PeezyCard.swift:45-143,229-232,487-557`. WAITING owner, expectation,
  trigger, destination, and visible copy therefore reach every row without a
  per-row fetch.

Home variants:

- Home loads six queried nonterminal status strings and maps every document
  (`PeezyHomeViewModel.swift:411-425`). Contract presence precedes legacy
  status/snooze classification and routes to `readOnlyContractStatus`
  (`:335-380`); the state is installed at `:450-458`.
- `PeezyHomeView.swift:72-106` selects the reachable surface. Its contracted
  row is the separate `passiveContractStatus` mini-surface, displaying the
  task title and `visibleStatusCopy` fallback at `:455-468`, with no action.
- Legacy nudges remain `NudgeCardView` (`:350-366`). Other legacy Home tasks
  open `TaskFlowRouter` (`:139-174`; selection at
  `PeezyHomeViewModel.swift:470-489`). Contract presence keeps them out of
  that actionable queue (`:347-350,477`).

Tasks variants:

- `TasksTabView.swift:18-30,68-99` partitions listener-backed tasks and mounts
  `TasksList`.
- `TaskGrouping.swift:19-68` routes coherent contract terminals to Done and
  every other contract to Peezy-on-it; legacy grouping reads status and
  snooze. Sorting/merge inputs are at `:71-84,107-125`. Packing-session merge
  ordering preserves reserved slots by scheduled date with `dueDate` fallback,
  then document ID (`:128-146`); legacy byte/snapshot coverage must freeze this
  behavior.
- To-do, You're-on-it, Peezy-on-it, and Done all call the same factory
  (`TasksList.swift:25-74`), which passes the already-mapped card to the sole
  production `TaskRow` constructor. `TaskRow.swift:7-36` mounts one header and
  optional button surface.
- `TaskRowHeader.swift:9-13,34-114` reads title/category/section, due/snooze
  dates, and workflow state. Contract presence already uses
  `visibleStatusCopy`; legacy To-do retains the effective snooze fallback.
  This Phase 2 behavior is substantially present and should be regression-
  tested, not duplicated.
- `TaskRowButtons.swift:104-143` reads contract presence, section, status, and
  scanner identity. Contract presence currently yields no buttons at `:107`.

There is no per-row Firebase import, listener, `.task` fetch, or other read in
`TasksList`, `TaskRow`, `TaskRowHeader`, or `TaskRowButtons`. The only Tasks
fetch is the parent listener; row-open dispatch reuses the same card
(`TasksStore.swift:39-72,166`). `PeezyStackViewModel` has no committed app
constructor and is unreachable.

Executable-spec binding had the gate continued: factor the future row menu and
WAITING surface over `PeezyCard` so both Home's distinct one-row surface and
all four Tasks sections reuse it. The mapper omits `planChangeState`,
`pendingAmendmentTaskId`, `planChangeRevision`, `planChangeHistory`,
`confirmationUndoUsed`, `firstConfirmationUndoUntil`, `supersedes`, `subject`,
`institutionId`, and `institution`. The listener already has the complete
documents, so any required subset is client-only model/mapper expansion; the
bounded-undo surface specifically needs its deadline and used state.

The current contract has no explicit `contradicting_evidence` property or
semantic shared-amendment anchor. `next_trigger.payload` is already recursively
decoded, but evidence presence does not mean contradiction. A future spec must
prove and freeze an existing canonical/payload/link field for each semantic;
inventing a new producer field would cross the server-scope gate. No per-row
fetch is needed either way.

### Item 3 — exhaustive inbound URL and notification inventory

- The only committed `.onOpenURL` is
  `Peezy 4.0/MainInterface/Models/PeezyV1App.swift:167-174`. It unconditionally
  passes the URL to `GIDSignIn.sharedInstance.handle` and ignores its Bool.
  Google sign-in initiation/configuration is at `AuthViewModel.swift:120-156`.
- The app plist registers only the reversed Google scheme and remote-
  notification background mode (`Peezy-4-0-Info.plist:5-19`); the entitlements
  have APNs development and Apple sign-in but no associated domains
  (`Peezy 4.0/Peezy 4.0.entitlements:5-10`). No application-open delegate,
  scene URL handler, `NSUserActivity` continuation, or second `.onOpenURL`
  exists.
- `AppDelegate` is the sole application, Messaging, and notification-center
  delegate (`PeezyV1App.swift:24,135-137`). Launch registration is at `:28-49`,
  APNs/FCM token entry at `:54-67,93-106`, foreground presentation at `:69-75`,
  and notification response at `:77-91`. The response routes only
  `userInfo["thread"] == "support"` and drops all other payloads.
- The support cold/live route uses a static pending bit plus NotificationCenter
  (`PeezyMainContainer.swift:11-29,112-119,137-155`) and switches to Chat.
  `functions/supportAdmin.js:108-134,285-288` is the only current push payload
  producer and writes `data.thread = "support"`.
- Assessment/retake and camera-active notifications are internal events, not
  URL/push routes (`AppRootView.swift:45-57`;
  `InventoryCameraView.swift:72-81`).

Binding: dispatch a recognized Peezy task URL before preserving the unchanged
Google fallback. A custom task URL requires an additional plist scheme (or a
separately approved universal-link configuration). Generalize the proven
pending-bit pattern into a typed `taskId` + `resume` route consumed after the
main container/task data is ready. Payload `taskId` must mean the Firestore task
document ID, not the catalog-level `PeezyCard.taskId`. The route cannot reuse
`focusedTask` alone because `PeezyHomeViewModel.focusTask` rejects contracted
cards (`PeezyHomeViewModel.swift:735-745`): `row` must select Tasks and expand
by document ID, while `outcome` and `flow-step` require their typed destination
surfaces.

### Item 4 — v3/v4 W0 action and trigger contract

Result: **SUPPORTED WITH v3/v4 TRIGGER BINDINGS.** The v3 and v4 amendments at
`PHASE2_PLAN.md:5-7` govern the six-action enumeration at `:27-28`; the stale
“five action specifications” wording in gate item 4 at `:39` is an editorial
remainder, not authority to drop the explicitly added sixth action.

The existing builders mechanically express every one of the six pairs:
`buildCompletedContract`, `buildTerminalContract`, `buildDeferredContract`,
`buildUserActionContract`, and `buildWaitingOnExternalContract`, with the
status/disposition map validated centrally
(`functions/dispositionContract.js:178-228,230-289`). No Phase 1 invariant must
be weakened to implement those six actions individually.

Phase 1 requires every unresolved disposition to carry `owner`, `next_action`,
`next_trigger`, and `resume_destination` (`functions/dispositionContract.js:178-195`).
`buildUserActionContract` validates the supplied trigger, normalizes it, maps it
to `InProgress` + `USER_ACTION_TRACKED`, and revalidates the coherent pair
(`:230-253`). Date triggers must be future and carry an approved evidence basis;
promised/acceptance dates require evidence, while derived dates require a
protected outcome, source, and meaningful bound (`:94-134`). Event triggers
require an event name, canonical key, source-version fence, and source evidence
(`:135-149`). These checks exclude generic intervals.

The executable API binding, had the design gate continued, is:

- `markCompleted()` → `Completed` + `COMPLETED`;
- `markNotApplicable(reason)` → `Dismissed` + `NOT_APPLICABLE`;
- `deferTask(nextTrigger, triggerConfirmed: true)` → `Snoozed` + `DEFERRED`;
- `assignOwner(owner, expectation?, nextTrigger, triggerConfirmed: true)` →
  `InProgress` + `USER_ACTION_TRACKED`;
- `markSelfHandling(nextAction, nextTrigger, triggerConfirmed: true)` →
  `InProgress` + `USER_ACTION_TRACKED` with canonical owner `user:${uid}`;
- `markWaitingOnExternal(owner, expectation, nextTrigger,
  triggerConfirmed: true)` → `matching_in_progress` +
  `WAITING_ON_EXTERNAL`.

The wire request uses the existing callable camelCase convention; persistence
remains snake_case (`Peezy 4.0/MainInterface/Models/TaskPlanService.swift:14-39`).
The confirmed-trigger envelope for `assignOwner` and `markSelfHandling` must
send `triggerSource` as exact `existing`, `move_estimate`, or `user_picked`.
`markWaitingOnExternal` instead accepts exact `institution_promised`,
`move_estimate`, or `user_picked`: a reported future institution promise is the first prefilled
candidate, otherwise the visibly labeled move-anchored estimate is offered,
otherwise the user must pick a future date. Every path still requires an
explicit confirmation and sends `fired: false`; the source and every
action-specific field are part of the cleaned operation fingerprint.
The server must reject missing/null/malformed triggers, `fired:true`, and any
confirmation value other than exact `true`. It must not default, retain, or
derive a submitted trigger from `dueDate`, `snoozedUntil`, or the prior contract;
it may read the current persisted trigger only to verify an explicitly submitted
`existing` candidate. The non-timing fields are
total and deterministic: `deferTask` stores canonical self owner, exact action
`Return to this task`, and resume destination `row`; `assignOwner` trims a bounded nonempty owner, uses the
trimmed expectation when present or exact fallback `Handle this task`, stores
exact resume destination `row`, and renders `<owner> is handling this`;
`markSelfHandling` stores canonical owner `user:${uid}`, the trimmed bounded
nonempty submitted `nextAction`, resume destination `row`, and visible copy
`You're handling this outside Peezy`. Both must then use
`buildUserActionContract` (`functions/taskPlan.js:210-227`).

`markWaitingOnExternal` requires bounded nonempty external `owner` and
`expectation`; the expectation deterministically supplies the contract's
`next_action`, resume destination is `outcome`, and its visible copy must state
who is acting and what is expected. It uses
`buildWaitingOnExternalContract`, which already maps to the coherent pair
(`functions/dispositionContract.js:230-257`). It cannot set or infer
`external_submission`; it may only preserve an existing exact `true` value.

Every W0 action must reject a contractless legacy row; legacy rows keep their
existing client paths. It must also reject any H54 graph state except absent,
null, or `reopened`, matching the existing safe-start allowlist
(`functions/taskPlan.js:276-280,308-313`). Each nonterminal W0 action—including
`deferTask`, `assignOwner`, `markSelfHandling`, and
`markWaitingOnExternal`—must pass
`externalSubmission: task.dispositionContract.external_submission === true` to
the common builder. Otherwise `profileMetadata` would preserve only
`profile_version`, and `buildNonterminal` would silently drop the H54 marker
(`functions/dispositionContract.js:86-91,230-242`).

Within the authorized boundary, household-owner validation can enforce a
bounded nonempty value and reject exact canonical self owner `user:${uid}`, but
cannot prove roster membership because no roster authority is available.
Membership must therefore remain a user-confirmed client selection; the server
must not claim it verified a household relationship.

The client can implement the v3 source chain for `assignOwner` and
`markSelfHandling` without a per-row read.
The shared mapper exposes the current trigger and recursive evidence payload
(`PeezyCardFirestoreMapper.swift:4-15,64-65,112-166`); `UserState.moveDate` is
loaded once and passed to Home and Tasks (`UserState.swift:6-13,164-177,268-296`;
`PeezyMainContainer.swift:63-84`). A pure resolver must evaluate these exact
candidates in order:

1. Reuse the current contract's date trigger only when it is consequential to
   this row, future, non-fired, approved-basis, and evidence-complete; tag it
   `existing`.
2. If a future `moveDate` exists, offer a visibly labeled `Estimate — anchored
   to your move date` candidate at that exact date—never `now + N`—with
   `basis: risk_based_estimate`, deterministic row-specific
   `protected_outcome: "Complete <card title>"` (or `"Complete task <document
   ID>"` when the title is empty), `derivation_source: move_date`, and ISO move
   date `bound`. The move date alone is not presented as verified or safe; the
   complete labeled payload makes the derivation explicit. Tag it
   `move_estimate`.
3. Otherwise require a future user-picked date with
   `basis: user_adjustable_bounded`, the same row-specific `protected_outcome`,
   `source: explicit_user_selection`, and ISO picked date `adjustable_bound`.
   The picked date is the user's explicit bound, not a server default or a
   claimed safe threshold. Tag it `user_picked`.

For `markWaitingOnExternal`, replace step 1 with a future
institution-promised date explicitly reported in the disposition card. Its
payload uses exact `basis: institution_promised_date` and a nonempty
operation-bound `source_evidence_id` equal to
`task-plan:<operationId>`; tag it `institution_promised`. That exact evidence
ID remains inside the cleaned trigger fingerprint and history record. If no
valid promise was reported, steps 2 and 3 apply unchanged. No old contract
trigger is retained merely because a scheduler wake or prior disposition once
carried one.

`deferTask` freezes a separate picker provenance: exact `user_picked` for a
date or exact `eligible_event` for an event. An event candidate must be
canonically equal to one entry in the row's additive eligible-event envelope
and must carry the Phase 1-required event name, canonical key, source-version
fence, and source evidence; if the row exposes no eligible event, the event
choice is absent rather than guessed. Both date and event choices cross the
same explicit confirmation type boundary.

Every selected date trigger carries `kind: date`, ISO `at`, the complete
payload, and explicit `fired: false`. On an operation-missing fresh execution, the server
must enforce the source tag rather than trusting client construction:

- `existing` must be canonically identical to the task's current persisted
  trigger after normalization;
- `institution_promised` must be a future date with exact
  `basis: institution_promised_date`, exact
  `source_evidence_id: task-plan:<operationId>`, and no derived-date fields; it
  is accepted only for `markWaitingOnExternal`;
- `move_estimate` must have exactly the four payload fields above, with parsed
  `at` and `bound` equal to `users/{uid}/identity/identity.moveDate` when
  parseable, otherwise `users/{uid}/user_assessments.limit(1).moveDate`, using
  `dateFromValue`; it must also have exact `derivation_source` and the protected
  outcome recomputed from the current task title/ID;
- `user_picked` must have exactly its four payload fields above, with parsed
  `at` equal to `adjustable_bound`, exact source, and the same server-recomputed
  protected outcome.

Cross-basis keys or additional fields fail closed. These are action-local checks
in `functions/taskPlan.js`; the shared Phase 1 validator remains unchanged and
runs afterward. The server compares supplied dates but supplies no date or
fallback itself.

That identity-first/assessment-second precedence is the existing server and
client resolution order (`functions/taskPlan.js:357-364`;
`functions/spawnTasks.js:331-342`; `UserState.swift:164-177,268-286`;
`IdentityService.swift:23-35,60-97,132-136`). W0 must mirror it locally in
`functions/taskPlan.js`; `spawnTasks.js` does not export its move-date reader.

The existing-trigger path needs an all-or-nothing recursive
conversion from `PeezyCard.FirestoreValue` to callable-safe values: dates become
ISO strings; null/bool/safe number/string, arrays, and maps retain their shape.
Reject integers outside JavaScript's safe range, nonfinite doubles, and blank or
whitespace-only map keys at every depth; the W0 server cleaner must enforce the
same bounds before fingerprinting because a callable client is not trusted
(`functions/dispositionContract.js:72-83`). Preserve the Phase 1 mapper behavior
that drops unsupported leaves while
keeping the card, but add lossless-decoding provenance to the mapped trigger:
the recursive decoder returns the supported projection plus `wasLossless`, and
only `DispositionTriggerSelection` rejects reuse when that flag is false. Then
apply the same complete-basis predicate before selection
(`Peezy 4.0Tests/DispositionContractTests.swift:49-57`;
`PeezyCard.swift:32-43,61-70`;
`PeezyCardFirestoreMapper.swift:116-124,146-166`;
`TaskPlanService.swift:14-30`). A recursive round-trip test and tests for a
dropped required nested value, each numeric bound, and a blank nested key must
respectively preserve the full payload or reject the candidate with zero calls,
while the existing drop-without-card-rejection test stays green.

Confirmation is a type boundary, not a preselected Boolean. Drafts cannot call
the service. Only the explicit confirmation action may construct a nonoptional
`ConfirmedDispositionTrigger`, after re-running completeness plus `at > now`
for a date, or event name/key/version/evidence and row eligibility for an
event;
every trigger-bearing W0 client method accepts only that type and sends exact
`triggerConfirmed: true`. Bind every draft to generation
`(documentID, title, status, nextTrigger, moveDate,
eligibleEventsFingerprint)` from the shared `TasksStore`
listener and `UserState`—even for Home's one-shot projection—and clear it
whenever that generation changes or disappears (`TasksStore.swift:31-54`;
`PeezyHomeViewModel.swift:411-428`). A reported institution promise is
action-local input, not live-listener generation state: freeze it inside that
draft and revalidate it when constructing the confirmation. The confirmed
value must also encapsulate the task document ID, selected W0 action, and that
action's complete action-specific inputs—including owner, expectation, and
`nextAction`—so it cannot be transferred to another task/action or paired with
changed copy. Repeat the generation and date-freshness or event-eligibility check
immediately before creating a fresh logical operation. Cancellation, an
unchanged picker without explicit confirmation, conversion/validation failure,
or a wake invalidation must produce zero operations.

One explicit valid confirmation freezes exactly one semantic request and
operation ID. The first transport call uses that immutable envelope; an
ambiguous transport failure may retry only the byte-equivalent request with the
same operation ID. Such a retry is the same logical operation, may pass the
date trigger time, must not reconstruct evidence from new title/move-date or
event-eligibility state, and must not repopulate a disposition draft after a
wake.

Both scheduler paths rebuild persisted state as `Upcoming`
(`functions/dispositionTriggers.js:237-249,320-344`), and
`buildUpcomingContract` removes the persisted trigger
(`functions/dispositionContract.js:292-298`). The live generation change to
`(documentID, Upcoming, nil)` must invalidate any SwiftUI draft; persisted
cleanup alone must not be claimed to clear client memory.

Fingerprint/replay ordering is binding. The W0 cleaner must perform only
shape/type/bound checks, normalize the trigger (including `fired:false`) to one
canonical semantic representation—Date-backed for date triggers—and
fingerprint that cleaned request
(`functions/dispositionContract.js:54-69`;
`functions/taskPlan.js:41-60,161-163`). The transaction must read the operation
record first: an exact fingerprint replays immediately, while a collision fails.
Only an operation-missing path may read current root/task state and apply
identity/assessment state as needed, then apply date freshness or event
eligibility, generation/source semantics, contract, reset, and H54 guards
(`functions/taskPlan.js:195-200,260-280`). This two-stage cleaner is required
because the current descriptor cleaner performs temporal validation before the
transaction (`:85-99`) and cannot be copied for W0. Fresh operations retain the
Phase 1 bounded history, atomic task/op write, and collision semantics
(`:180-183,603-608`).

### Cross-workstream contradiction — W1 lacks a support transition

v4 truthfully fixes the call/portal “They're handling it / processing” outcome:
that meaning is `WAITING_ON_EXTERNAL`, and the new sixth action can write its
coherent `matching_in_progress` pair. The remaining branch is distinct. Locked
A4 exposes “Get help from a person” under “I couldn't finish,” while A2 makes
`SUPPORT_ACTIVE` a real owned disposition and A6 requires visible expectation,
an operationally backed SLA, a retained self-service fallback, and graph-based
resolution (`docs/plans/files/INSTITUTION_FLOWS_MASTER_v3.md:38-50,72-78,93-98`).
Its coherent task pair is `pending` + `SUPPORT_ACTIVE`
(`functions/dispositionContract.js:178-195,230-266`).

Plan v4 nevertheless exhaustively authorizes only complete, not-applicable,
defer, household-owner, self-handling, and waiting actions
(`PHASE2_PLAN.md:27-30`). It simultaneously claims that those six complete the
outcome mapping (`:7`), requires every outcome to land through legacy or W0/H54
with no new client writer (`:29`), and accepts only when every outcome writes a
coherent pair (`:53`). Those claims cannot all hold:

1. H54's existing action set contains only supersession, amendment confirmation,
   undo, reopen, and reset/finalize operations (`functions/taskPlan.js:26-29,135-158`).
   None is a support transition.
2. The coherent builder exists, but `buildSupportActiveContract` has no
   production caller; it is only defined/exported and exercised by contract
   tests (`functions/dispositionContract.js:264-265,301-308`;
   `functions/tests/dispositionContract.test.js:132`).
3. `SupportChatService.sendMessage` persists a chat message and, for the
   movers expert-review path only, an `expertReview` marker. It never writes
   task status or `dispositionContract`
   (`Peezy 4.0/MainInterface/Models/SupportChatService.swift:103-180`). The
   awaited callable opens/updates `supportThreads`, not the task
   (`functions/index.js:105-205`); `requestConcierge` similarly writes only
   `conciergeRequests` (`functions/index.js:42-68`).
4. Legacy task writers update status-only fields
   (`Peezy 4.0/MainInterface/Models/TaskActionService.swift:247-258,399-448`),
   and rules reject a client update whenever either side has a disposition
   contract (`firestore.rules:117-138`).

Overloading `markWaitingOnExternal`, `assignOwner`, `markSelfHandling`, or
`deferTask` would lie about who owns the work and erase A6's distinct semantics.
Opening Chat while leaving the prior state untouched may be a navigation path,
but it is not the persisted outcome v4 claims and cannot satisfy the acceptance
criterion. The full outcome-to-action mapping is therefore **CONTRADICTED**.

The smallest truthful correction is a seventh W0 action inside the already
authorized `functions/taskPlan.js` surface, for example
`markSupportActive(owner, expectation, nextAction, nextTrigger,
triggerConfirmed: true, supportRequestEvidence)` → `pending` +
`buildSupportActiveContract(...)`. It must use the same op-first fingerprint,
history, idempotency, contract/H54 guards, and atomic intent pattern, and it
must bind the transition to a durably admin-queued request or recorded human
acceptance, with an operationally backed SLA and retained self-service
fallback. The stuck tap may initiate that action, but merely navigating to or
opening Chat is insufficient evidence. If that evidence cannot be
verified inside the authorized scope, the alternative amendment is to keep the
prior owned disposition until support accepts the work and explicitly defer the
SUPPORT_ACTIVE writer; that also requires removing v4's claims that support is
already a persisted outcome and that all outcomes land in Phase 2.

The separate legacy-byte wording does not require a second stop if bound
precisely: attach A8 as a non-rendering context menu, preserve serialized model
bytes, and keep the closed-row layout and ordinary tap/expand paths unchanged.
The existing snapshot proves model bytes only; closed-row pixel/layout identity
remains a feasibility claim until a SwiftUI visual-regression test proves it.
The menu and explicit accessibility actions are the intentional interaction
delta, and long-press-only discovery needs accessibility coverage. Literal
behavior identity must not be claimed (`TaskRow.swift:14-36`;
`Peezy 4.0Tests/DispositionContractTests.swift:60-86`).

### Additional future executable-spec bindings

- A contracted external CTA cannot truthfully acquire a next-day contract
  trigger from local `HandoffSession` persistence alone. Before opening the
  external app, the UI must obtain the explicit confirmed W0 disposition
  envelope and await that server write; if the plan instead intends only local
  resume persistence, it must remove “via the contract” from that guarantee.
- The current shared card schema has no named contradiction-evidence flag,
  eligible-event envelope, legal-deadline envelope, or semantic amendment
  anchor (`PeezyCard.swift:98-143,229-232`;
  `PeezyCardFirestoreMapper.swift:64-65,112-138`). A corrected plan/spec must
  name those additive fields and their canonical meanings; optional decoding
  and fixture-backed UI are in scope, but guessing evidence from arbitrary
  payload keys is not.
- A scheduler wake rebuilds `Upcoming` and removes `next_trigger` for both date
  and event paths (`functions/dispositionTriggers.js:237-249,320-344`;
  `functions/dispositionContract.js:292-298`). The permitted scheduler change
  therefore needs an additive, non-trigger wake-reason/evidence marker on the
  task if W2 must group the row later as urgent recovery. A server-only
  notification-intent document cannot feed client list rendering.
- The plan's example “when my address is confirmed” is not itself a canonical
  A11a event. The eligible-event envelope must refer to an actual declared
  event name/key/version/evidence tuple or omit the event choice.

### Items 5–8 — completed assertion bindings

#### 5 — notification-intent documents

Admin SDK writes bypass Firestore client rules. Existing server-owned examples
use owner-read/client-write-denied rules (`firestore.rules:154-170`), while an
undeclared intent collection is default-denied to all clients. The offline
scheduler fake exposes committed document data
(`functions/tests/dispositionTriggers.test.js:26-84`), and task-plan tests
provide transaction seams (`functions/tests/taskPlan.test.js:148-190`). Direct
deterministic document writes need no composite index; current composites serve
only task/date/event queries (`firestore.indexes.json:2-29`;
`dispositionTriggers.js:363-443`).

Binding: keep notification intents server-only and test the payload through
offline fakes. A production client listener/query or owner read would reopen
rules and index design. The offline rules suite must prove read and write
denial for the owner, a different authenticated user, and an anonymous client.

#### 6 — additive research posture

The server currently requires string `sections[].items` and normalizes away
unknown section fields (`functions/researchTask.js:72-85,493-545`); URL cleanup
reconstructs only heading/items (`:604-617`), then the normalized brief is
persisted wholesale under `brief` (`:814-824`). Swift strictly decodes
`items as? [String]` and renders them
(`Peezy 4.0/Tasks/Views/TaskResearchModule.swift:98-139,540-569`).

An additive implementation must update prompt, normalization, URL cleanup,
Swift decode, and render together, preserving legacy strings while accepting
new item objects such as `{text, posture, source, date}`. Cached briefs already
return without rewrite (`researchTask.js:782-788`), and storage persists the
normalized map generically (`:814-824`), so legacy strings can remain strings.
W0 explicitly authorizes `researchTask.js`; assertion 6 is supported under this
dual-shape binding and is not an independent stop.

#### 7 — scene-phase flush and H56 barriers

`FlowExitControl.swift:260-297` rejects new writes while locked and serializes
through `persistenceTask`. Pre-submit locks synchronously, captures/drains the
queue, and validates the exact attempt (`:299-341,447-468`); terminalization
locks and drains before clear (`:353-370`). The outer flow host is at
`:476-546`.

Binding: a scene coordinator may capture/await the current persistence task
only while both locks are clear. If either lock is active, skip because the
barrier owns the drain. Use a bounded iOS background execution assertion while
awaiting; a bare unstructured `Task` cannot prove loss-free draining after
suspension. The testable zero-loss claim must remain scoped to the serialized
H56 queue while the background assertion remains live. iOS background time is
bounded and best-effort, so expiry/offline termination cannot be described as
an absolute OS guarantee. External persistence announced through
`noteExternalPersistencePending` is outside the claim unless made awaitable
(`FlowExitControl.swift:380-410`).

The lock check and tail capture can be synchronous on the coordinator's
`@MainActor`, but the implementation must distinguish a real serialized queue
tail from `noteExternalPersistencePending`, which also sets `.pending` while
cancelling/superseding the generic task. Start the background lease before the
first await only for a genuine queue-backed tail, end it exactly once on normal
completion or expiration, and never start it for no work, either lock, or the
external-pending marker. RED cases must cover each branch plus persisted
failure state (`FlowExitControl.swift:126-146,260-297,380-410,470-473`).

#### 8 — named offline test envelope

The retained classes are `ConversationFlowTests`,
`DispositionContractTests`, `TaskGroupingTests`, and `TaskSupersessionTests`
(`Peezy 4.0Tests/ConversationFlowTests.swift:14`;
`DispositionContractTests.swift:6`; `TaskGroupingTests.swift:5`;
`TaskSupersessionTests.swift:6`). The test directory is a synchronized root
group bound to the unit target (`Peezy 4.0.xcodeproj/project.pbxproj:48-64,165-184`),
so new Swift suites would auto-enumerate. The scheme includes unit and UI
bundles (`Peezy 4.0.xcodeproj/xcshareddata/xcschemes/Peezy 4.0.xcscheme:26-55`).

Binding: exact `-only-testing:'Peezy 4.0Tests/<Class>'` selectors for those four
plus frozen new Phase 2 classes `HandoffSessionTests`,
`ContextualOutcomeTests`, `TaskPlanDispositionTests`,
`DispositionTriggerSelectionTests`, `TaskDispositionSurfaceTests`, and
`TaskRowLegacySnapshotTests`, plus `TaskRouteTests`, `FlowSceneFlushTests`, and
`ResearchPostureTests` for W4/W5. The trigger suite owns candidate order,
recursive conversion, confirmation, zero-call, and wake invalidation. The
route suite owns URL/payload/cold-start routing; the flush suite owns every
lease/barrier branch enumerated above; the posture suite owns legacy/new
dual-shape decode and rendering. Retain
`-skip-testing:'Peezy 4.0UITests'`; omit `-testPlan`; never set
`PEEZY_RUN_FIRESTORE_INTEGRATION`. This excludes both Firestore integration
classes, the live geocoder integration class, every unselected unit class, and
all UI suites.

### Bound W0 server file surface

The minimal future W0 source surface reconciles to
`functions/taskPlan.js`, `functions/dispositionTriggers.js` (the H55 writer
explicitly required by W4), and `functions/researchTask.js`. A new
`functions/notificationIntents.js` helper is permissible only as the literal
notification-intent surface. Tests bind to
`functions/tests/taskPlan.test.js`,
`functions/tests/dispositionTriggers.test.js`, a new
`functions/tests/researchTask.test.js`, and
`functions/rules-tests/firestoreRules.test.js`. The rules test must assert the
existing default denial; `firestore.rules` itself remains unchanged because no
new grant is required.

No change is required or authorized in `functions/index.js`,
`functions/dispositionContract.js`, `functions/getWorkflowQualifying.js`,
`functions/spawnTasks.js`, `firestore.indexes.json`, `firebase.json`, or
`functions/package.json`. Existing exports already bind all three handlers
(`functions/index.js:14,18-19,291,296-297`). Any server source/config path
beyond the reconciled W0 surface remains a mandatory stop.

## Governing input and preflight

- `PEEZY_STATE.md` was read first and governed over `PHASE2_PLAN.md`.
- Root `PHASE2_PLAN.md` v4 (`SHA-1
  28e4c38a9f8e9efbd8c51958805e4a59756fc2da`) contains both amendments:
  the two USER_ACTION actions require newly confirmed complete triggers, and
  the sixth WAITING action requires its separately confirmed promised/estimate/
  picked trigger. The latest user instruction confirms that v4 is governing.
- The plan names source snapshot `e8d6133`; current committed `HEAD` is
  `b4b047d29bea6a1721729b69e0d01aa7a1dc9923`, whose only delta from `e8d6133`
  is the committed `PEEZY_STATE.md` regeneration. All audit evidence used the
  committed tree, never dirty Build 25 content.
- Main checkout: `main`, ahead of `origin/main` by four commits and dirty with
  pre-existing protected Build 25 WIP.
- Xcode 26.6 (`17F113`); available simulator iPhone 17 Pro
  `DC0CC10C-6DB0-496A-8B0E-51E60D958A27` on iOS 26.5.
- Node `/opt/homebrew/opt/node@24/bin/node` v24.19.0; Firebase CLI 15.6.0.
- The audit used the untracked governing plan plus committed `git show`/`git
  grep` source evidence; carried inventories were reconciled against the same
  `b4b047d` source snapshot. No live service, credential, `.env` content,
  deployment state, or production data was read.

### Protected pre-existing dirty/untracked baseline/closeout hashes

All protected pre-existing inputs, including the Build 25 WIP, were left
byte-identical across the audit and report-only closeout:

| Path | SHA-1 |
|---|---|
| `ARCHIVE_MANIFEST.md` | `ba9522c89d632d8f4b343638167cd6ec988f43de` |
| `PEEZY_STATE_REGEN_SPEC.md` | `f09b8f8f452fa0d3cacd2247850330973749bcd6` |
| `Peezy 4.0/Inventory/Models/InventorySessionManager.swift` | `7554988e5418a188e84bb31e23025217dac83a41` |
| `Peezy 4.0/Inventory/Services/InventoryAPIClient.swift` | `9b8c74154dda9996b574c0a4e8a8a2ce6c065d40` |
| `Peezy 4.0/Inventory/Views/InventoryCameraView.swift` | `480fcc24cc8b4f2a0a20497d4575b61326b37e7a` |
| `Peezy 4.0/Inventory/Views/InventoryFlowView.swift` | `7a3f3d9c638f62e2df859e35098463f13184b3a9` |
| `Peezy 4.0/Inventory/Views/InventoryScanCoachingView.swift` | `c05648593c03e6140e9451e0b7baa4744dbd358e` |
| `functions/processInventory.js` | `73601c49f93f1b460c2e04302497fb6f4e874602` |
| `File.txt` | `e0efc448f37d9394de350c3ad5a54dacbeacd48e` |
| `PHASE2_PLAN.md` | `28e4c38a9f8e9efbd8c51958805e4a59756fc2da` |
| `Peezy 4.0/PHASE2_PLAN.md` | `fef0d50a3e37f38c32754d2fb26ee26141062368` |
| `Peezy 4.0/Inventory/Services/NarrationService.swift` | `bba0c81ec81974cea3f108b0a80e28a956d220f3` |
| `Peezy 4.0/Inventory/Views/NarrationOfferCard.swift` | `f4fdd03858c31fa37ad179a8f3bded91d9e569d3` |
| `functions/tests/processInventoryNarration.test.js` | `273257cdced50b3a922847fd5bf7c9733bc43630` |

## Adversarial review convergence

- Three independent Codex reviewers audited committed source only: external
  CTA/row/entry-point inventories; W0/research/notification assertions; and
  scene-flush/test-envelope assertions.
- The v4 pass independently reproduced the nonterminal field validator, both
  scheduler wake builders, client trigger-source plumbing, every production
  WAITING writer, the absence of any production SUPPORT_ACTIVE task writer,
  both support callables, the contracted-row rules wall, and the governing
  no-unowned-state/trigger hierarchy.
- All reviewers converged: items 1–3 SUPPORTED with the inventories above;
  v4 item 4's six actions are implementable; items 5–8 remain supported under
  their recorded bindings; and v4's full outcome mapping is CONTRADICTED
  because no authorized production writer can land the support branch in
  `pending` + `SUPPORT_ACTIVE`. Chat persistence and admin queueing are not a
  task disposition.
- The red-first `tdd-feature` process stopped before complete per-workstream
  executable-spec and RED test-file authoring because the cross-workstream
  design gate failed. No executable spec or executable-spec review-log
  artifact was created; the skill requires a complete outcome-to-action API
  contract before RED tests.

## Execution status

No Phase 2 workstream was executed. No RED/GREEN cycle, simulator build,
XCTest, Node suite, rules emulator, or implementation diff review was run
because the W1 outcome contradiction requires a pre-execution stop. The
accepted Phase 1 source and all Build 25 WIP remain unchanged.

## Required plan correction before a new Phase 2 execution

Authorize a seventh W0 action for the support branch, for example:

`markSupportActive(owner, expectation, nextAction, nextTrigger,
triggerConfirmed: true, supportRequestEvidence)` → `pending` +
`SUPPORT_ACTIVE`.

Keep it in `functions/taskPlan.js` and implement it through the existing
`buildSupportActiveContract`. It inherits the W0 validation/fingerprint/
op-first replay/history/atomic-intent rules, the contract/H54 state gates, and
the no-default trigger discipline. The plan must also define verifiable durable
admin-queue/acceptance evidence, an operationally backed SLA, and the
self-service fallback; opening Chat alone cannot qualify. If support
acceptance/evidence is deferred,
amend W1 and acceptance so the old owned disposition remains until acceptance
and stop claiming that the support route is already a persisted Phase 2
outcome.

Also narrow “legacy byte-identical” to persisted/model bytes. Closed-row
rendering and ordinary tap/expand behavior must remain unchanged, with pixel/
layout identity proven by a visual-regression test before acceptance. The
non-rendering A8 context menu and explicit accessibility actions are the
intentional interaction delta. Gate items 5–8 require no additional amendment
beyond their recorded bindings.

## Commit gate

No commit was created. The only Phase 2-owned working-tree artifact is this
blocked build report. Closeout integrity: **PASS**; every protected hash above
is byte-identical. Report-only diff stat (`git diff --no-index /dev/null PHASE2_BUILD.md`): `1 file changed, 743 insertions(+)`; pre-existing tracked WIP stat (`git diff --stat`): `8 files changed, 237 insertions(+), 50 deletions(-)`.
