# Plan under review: Phase 1 dispositions, subject keys, supersession, triggers, and rules

Source: `PHASE1_PLAN.md` v3, owner-issued 2026-08-26. Revision 6, after five
adversarial review rounds. The governing sources, in order, are:

1. `PEEZY_STATE.md` at committed HEAD `b25e9b3`.
2. `PHASE1_PLAN.md` v3.
3. `docs/plans/BUILD_BRIDGE.md` and §A v3.3 in
   `docs/plans/files/INSTITUTION_FLOWS_MASTER_v3.md`.

Outcome remains **local implementation only — production unchanged**. No seed,
deploy, Functions packaging, production-connected test, StoreKit action, remote
Firestore/Storage write, or integration opt-in environment is authorized. H43
continues to block Functions packaging/deployment.

## Audit gate (completed read-only at `b25e9b3`)

| Item | Disposition | Binding result |
|---|---|---|
| 1 — mapper | SUPPORTED | Optional map decodes additively through the one shared mapper. |
| 2 — status writers | INVENTORY COMPLETE · SUPPORTED | All runtime writers are enumerated below. Client writes preserve/omit the server-owned map; server writers may carry it with status. |
| 3 — `snoozedUntil` readers | INVENTORY COMPLETE · SUPPORTED | Missing means not snoozed everywhere reachable; atomic status wake + delete is consistent. |
| 4 — spawn validation | INVENTORY COMPLETE · SUPPORTED | Per-spawn subject/institution can be validated pre-read and enters the existing fingerprint through cleaned `spawns`; omitted fields retain byte-identical `t1_` behavior. |
| 5 — H51 | SUPPORTED | Only `financial_accounts` intersects `forEachRow` with the repository's sole `perSelectionFrom`. |
| 6 — rules | SUPPORTED | Explicit replacements plus W3's server-authorized Retake reset preserve every reachable behavior while denying server-owned surfaces. |
| 7 — runtime | SUPPORTED | Node 24.19.0, `firebase-functions` 7.0.3, v2 `onSchedule`, Functions Test 3.4.1, Firebase CLI 15.6.0. |
| 8 — offline XCTest selection | SUPPORTED | Exact class selectors exclude Firestore/calibration/geocoding integration classes and the UI restore flow. |

### Bound inventory: task-document status writers

- `TaskGenerationService.swift:101-120,157-165` initial `Upcoming` full set;
  `:219-220,233-251,267` add-only incremental `Upcoming`.
- `TasksStore.swift:73-109,116-137` complete/undo through one `updateData`.
- `TaskActionService.swift:28-46,183-210` nudge transaction;
  `:215-220` generic unused setter; `:282-323` movers complete/booking/snooze;
  `:365-411` Home complete/InProgress/UserInProgress/snooze;
  `:604-617` supplies dismissal; `:674-741` readiness and packing completion;
  `:797-823,956-1043` packing/readiness replacement builders/writes;
  `:828-846,1074-1103` merge-written supplies task.
- `MoversChainCoordinator.swift:102-116,245-275,300-317` supplies the booking
  payload and delegates; `PeezyHomeViewModel.swift:672-780` and
  `FlowEngineView.swift:541-557` only orchestrate shared writers.
- `spawnTasks.js:239-269,302-339` creates `Upcoming`;
  `getWorkflowQualifying.js:176-186,210-237,267-280` writes Completed, pending,
  and matching_in_progress.
- `supportAdmin.js`, unexported diagnostics, test-profile seeders, previews, and
  tests are not task-status runtime writers.

### Bound inventory: reachable `snoozedUntil` readers

`PeezyCardFirestoreMapper.swift:30-37,65-82` ·
`PeezyCard.swift:235-239,269-280` ·
`PeezyHomeViewModel.swift:366-389` ·
`TaskGrouping.swift:29-61,80-110` ·
`TaskRowHeader.swift:9-13,86-105` ·
`TaskActionService.swift:989-999,1035-1042`. The additional reader in
`PeezyStackViewModel.swift:128-154,523-537` is unreachable per H4. No reachable
reader treats a missing value as still snoozed, and packing regeneration cannot
re-copy it after the status has become Upcoming.

### Bound inventory: spawn validation and H51

`spawnTasks.js:15-73` canonicalization/fingerprint/t1 ID; `:98-181` all current
validation; `:136-154` current institution boundary; `:302-308` first DB read;
`:367-395` auth/validation ordering. Row expansion rewrites provider to
`{rowId}.provider` at `FlowDefinition.swift:168-207`, while exact lookups at
`FlowEngineView.swift:690-709` yield zero and `:720-727` silently completes.
`medical_records`, `financial_accounts`, and `memberships` have forEachRow;
only `financial_accounts` has perSelectionFrom (`flowDefinitionsData.json:1080-1143`).

### Bound inventory: client-write matrix under `users/{uid}/**`

| Path | Client evidence | Replacement rule required |
|---|---|---|
| root user | `DailyDoseEngine.swift:30-51`; `BoxReturnService.swift:59-63` | existing protected-root rule |
| `fcmTokens` | `PeezyV1App.swift:93-102` at committed HEAD | explicit owner CRUD |
| `identity` | `IdentityService.swift:23-48,70-97` | retain explicit owner CRUD |
| `inventory` | `InventorySessionManager.swift:31-45,540-649,679-723` at committed HEAD | retain explicit owner CRUD |
| `inventorySessions` | `InventoryStorageService.swift:24-45,105-116` | retain explicit owner CRUD |
| `packingPlan` | `TaskActionService.swift:753-763,768-851,898-903` | explicit owner CRUD |
| `readiness` | `TaskActionService.swift:674-713,753-763,905-910` | explicit owner CRUD |
| `supportChat` | `SupportChatService.swift:137-149,206-220` | existing narrow rule |
| `tasks` | every item-2 writer plus Settings/packing deletes | explicit legacy owner CRUD; contracted/audited Retake delete is routed through W3 Admin reset |
| `user_assessments` | `AssessmentDataManager.swift:267-299`; `InAppTaskFlows.swift:29-54`; Settings | explicit owner CRUD |

Server-owned client-read surfaces also need explicit replacement reads when the
recursive grant is removed: `moveAnswers` (`firestore.rules:73-77`),
`packingAggregate` (`SuppliesKitView.swift:401-405`), `research`
(`TaskResearchModule.swift:284-295`), `workflowResponses`
(`CheckInService.swift:59-64`; `TaskDetailView.swift:407-420`), and nested
`chats/{chatId}/messages` (`SupportChatView.swift:779-794`). Additive rules mean
W5 must exclude the server-owned collections from the recursive grant rather
than merely layering narrower matches over it, while preserving these reads.

## Preflight and phase manifest

The initially dirty Build 25 WIP is outside this manifest and is protected by
the recorded preflight hashes. `PeezyV1App.swift`, `project.pbxproj`, every
Inventory source, `functions/processInventory.js`, its narration test, and the
pre-existing untracked planning/source files remain byte-identical.

Implementation surface:

- W1: `PeezyCard.swift`, `PeezyCardFirestoreMapper.swift`, `TaskRowHeader.swift`,
  `TaskGrouping.swift`, `TaskRowButtons.swift`, `PeezyHomeViewModel.swift`,
  `PeezyHomeView.swift`, `TaskGenerationService.swift`, `TaskActionService.swift`,
  `DispositionContractTests.swift`, `TaskGroupingTests.swift`, and new shared
  server validator `functions/dispositionContract.js`; reset-aware,
  contract-coherent transaction guards in `functions/getWorkflowQualifying.js`
  and new `functions/tests/dispositionContract.test.js` and
  `functions/tests/getWorkflowQualifying.test.js`.
- W2: `SpawnService.swift`, `FlowDefinition.swift`, `FlowExitControl.swift`,
  `TaskGenerationService.swift`, `FlowEngineView.swift`,
  `TaskFlowBusinessSearchCard.swift`,
  `ConversationFlowTests.swift`, `functions/spawnTasks.js`, and
  `functions/tests/spawnTasks.test.js`.
- W3: new `TaskPlanService.swift`, new `RetakeAssessmentCoordinator.swift`,
  `PeezySettingsView.swift`, new
  `TaskSupersessionTests.swift`, new
  `functions/taskPlan.js`, new `functions/tests/taskPlan.test.js`, and
  `functions/index.js`.
- W4: new `functions/dispositionTriggers.js`, new
  `functions/tests/dispositionTriggers.test.js`, `functions/index.js`,
  `firestore.indexes.json`, and `firebase.json`.
- W5: `firestore.rules`, `functions/package.json`, `functions/package-lock.json`,
  and new `functions/rules-tests/firestoreRules.test.js`.
- Session artifacts: this spec, its review log, and root `PHASE1_BUILD.md`.

No catalog/flow JSON changes are planned: H51 is fixed in code. New Swift files
join filesystem-synchronized app/test groups automatically; project.pbxproj is
not writable.

## Cross-workstream invariants and arbitration

1. **Server-owned lifecycle.** A task carrying `dispositionContract` may not be
   created, status-transitioned, contract-mutated, or deleted by a client. A
   server transaction must update its status and contract coherently. Legacy
   tasks without a contract retain their current owner status writes and delete
   behavior. Initial generation becomes add-only for any existing task ID;
   packing/readiness replacement builders preserve an existing contract map but
   rules still reject any client lifecycle change to such a task. This is the
   arbitration required by W1/W5, not map preservation alone.
2. **Two new exports, one new subsystem.** W3 necessarily adds one callable
   export (`changeTaskPlan`). W4 adds the sole new export *type* and sole new
   subsystem (`evaluateDispositionTriggers`, scheduler). H19 therefore moves to
   20 callables + 2 HTTP + 1 Firestore + 1 scheduler, not “one total export.”
3. **Per-spawn durable identity.** Subject, canonical institution ID, and
   institution display label live on each spawn entry because one financial
   terminal can spawn several institutions. Generated flow rows receive a
   persisted UUID subject ID once; option IDs are canonical institution IDs and
   labels remain presentation only. Existing callers omit all three and remain
   on t1. A request may not mix legacy and t2 spawns; mixed identity mode is
   invalid-argument before DB access.
4. **Canonical TASK_TYPE.** The tuple's TASK_TYPE is the catalog `taskId`, not
   the broad catalog `taskType` (`provide_info`, etc.). The t2 digest is over
   canonical JSON of
   `{householdUid,subject:{kind,id},institutionId,taskId}` to avoid delimiter
   ambiguity. The display label is deliberately excluded from identity.
5. **External amendment is a pending lifecycle.** The existing task contract flag
   `external_submission: true` requires an explicit subject-aware `replacement`
   descriptor in the supersede request. Without it, supersession fails closed;
   Phase 1 never invents or seeds an amendment catalog ID. With it, the
   original stays active and visible while an amendment is created/reused as
   InProgress/USER_ACTION_TRACKED. Only `confirmAmendment` retires the original.
   Internal-only work can retire immediately. Phase 2 owns the handoff UI.
6. **Events are ordered canonical envelopes.** A server-written event contains
   the A11a envelope plus `event_name`, `canonical_key`, integer
   `source_version`, `effect` (`fire` or `retract`), payload, and
   `processed:false`. Event triggers identify `event_name` plus canonical key,
   not one delivery ID. A server-only per-key high-water document is advanced in
   the consuming transaction. Duplicate/stale versions and retractions are
   consumed without waking; a later `fire` correction may wake. This implements
   A11a ordering rather than delegating it to a future publisher.
7. **Index completeness.** The scheduled queries are not shippable with H41d's
   absent index configuration. W4 adds the exact local index file/config needed
   by its collection-group date/event scans; H41d becomes stale and joins the
   final regeneration debt.

## W1 — additive disposition contract and truthful status copy

### Read first

The item-1/item-2/item-3 inventories above, then the complete current definitions
of `PeezyCard`, its mapper, `TaskRowHeader`, Home active-task loading copy,
TaskGeneration's two creation loops, and TaskActionService's packing builders.

### Order and break

1. Add red tests against types and mapper behavior that do not yet exist.
2. Run the literal W1 safety envelope—only `DispositionContractTests` and
   `TaskGroupingTests`, plus the UI-target skip: compile/assertion failure is RED.
3. Add the model/mapper/UI projection and preservation changes.
4. Re-run the same selectors GREEN before W2 tests are introduced.

### Exact code contract

Add nested `PeezyCard.DispositionContract: Codable, Equatable` with Swift names
mapping the Firestore keys:

```swift
enum FirestoreValue: Codable, Equatable {
    case null, bool(Bool), int(Int64), double(Double), string(String), date(Date)
    indirect case array([FirestoreValue]), map([String: FirestoreValue])
}

struct DispositionContract: Codable, Equatable {
    enum Disposition: String, Codable {
        case completed = "COMPLETED"
        case notApplicable = "NOT_APPLICABLE"
        case userActionTracked = "USER_ACTION_TRACKED"
        case waitingOnExternal = "WAITING_ON_EXTERNAL"
        case deferred = "DEFERRED"
        case supportActive = "SUPPORT_ACTIVE"
    }
    enum TerminalKind: String, Codable {
        case notApplicable = "not_applicable"
        case retired, superseded
    }
    var disposition: Disposition?
    var terminalKind: TerminalKind?
    var owner: String?
    var nextAction: String?
    var nextTrigger: Trigger?
    var resumeDestination: String?
    var visibleStatusCopy: String?
    var profileVersion: Int?
    var externalSubmission: Bool
    var supersededBy: String?

    struct Trigger: Codable, Equatable {
        enum Kind: String, Codable { case date, event }
    var kind: Kind
    var at: Date?
    var eventName: String?
    var canonicalKey: String?
    var afterSourceVersion: Int?
        var payload: [String: FirestoreValue]?
        var fired: Bool
    }
}
```

`PeezyCard` gains optional `dispositionContract` defaulting nil and computed
`visibleStatusCopy` that trims whitespace and returns nil for empty copy. The
mapper decodes only known contract keys, accepts `Timestamp` for dates and
NSNumber for numeric values, distinguishes NSNumber booleans, recursively
preserves Firestore-safe null/scalar/date/array/map payloads, and defaults
external/fired false. Unsupported payload leaf values make that leaf absent but
never reject the card. No second decoder is added.

Server-authored contracts use one shared status-pair validator in Swift tests and
`functions/dispositionContract.js` in every Admin task writer added or changed
by W1/W3/W4. A2 disposition and A7 graph
resolution remain separate:

- Completed + COMPLETED + no terminal_kind;
- Dismissed + NOT_APPLICABLE + terminal_kind `not_applicable`, only for a row
  generated incorrectly or carrying no obligation;
- Dismissed + no current A2 disposition + terminal_kind `retired` or
  `superseded`, for A7 graph resolution;
- Upcoming + no current disposition + no terminal_kind for a W4-reactivated row;
- InProgress/USER_ACTION_TRACKED, matching_in_progress/WAITING_ON_EXTERNAL,
  Snoozed/DEFERRED, and pending/SUPPORT_ACTIVE for nonterminal pairs.

Every W1/W3/W4 Admin task write calls/asserts this validator. A malformed pair is
fail-safe projected as read-only noncomplete with its provided copy (or “Status
needs attention”), never guessed Done/hidden.

Pair validation is necessary but not sufficient. The shared validator also
requires every noncomplete disposition to have trimmed nonempty `owner`,
`next_action`, `resume_destination`, and `visible_status_copy`, plus exactly one
valid date/event `next_trigger`. It rejects stale fields from another disposition,
terminal fields on nonterminal states, and partial trigger shapes. Export
`buildUserActionContract(base, input, now)`,
`buildWaitingOnExternalContract(base, input, now)`,
`buildCompletedContract(base, copy)`, and
`buildTerminalContract(base, terminalKind, copy)`, and
`buildUpcomingContract(base, copy)`. Each constructs the whole
disposition map rather than merging individual keys: it keeps only unrelated
profile metadata, replaces all state-specific fields, clears every field invalid
for the new state, and then validates the complete result. A date trigger must
carry a Firestore-safe payload naming a non-generic `basis` from
`institution_promised_date`, `recipient_acceptance_date`, `safe_threshold`,
`user_adjustable_bounded`, or `risk_based_estimate`. Promised/acceptance bases
also require `source_evidence_id`; threshold/bounded/estimate bases require
`protected_outcome` and the source/bound used to derive the date. A past date is
rejected rather than stored as a backdated reminder. An event trigger requires
event name, canonical key, safe integer source-version boundary, and
`source_evidence_id`. No builder invents a fixed interval.
`buildUpcomingContract` retains only unrelated profile metadata and a nonempty
copy; it clears disposition, terminal kind, owner, next action, current trigger,
resume destination, external-submission state, and supersession state. Upcoming
validation requires those fields absent, so a fired DEFERRED obligation cannot
masquerade as the current contract.

Contract-aware projection is gated solely by map presence:

- A contract-bearing `Completed` is Done with disposition COMPLETED. A
  contract-bearing `Dismissed` is Done, never silently hidden, and follows one
  of the three terminal pairs above. All other mapped/nonterminal statuses (`InProgress`, `pending`,
  `matching_in_progress`, Upcoming, Snoozed, UserInProgress) are visible as
  noncomplete. They use the existing `peezyOnIt` section as a presentation
  bucket, but `TaskRowButtons` returns no action layout while a contract is
  present so legacy direct status writers cannot create incoherent pairs.
- A card without a contract executes the current `TaskGrouping`, Home filter,
  `shouldShow`, and button behavior byte-for-byte.
- `TaskRowHeader.badgeRow` renders nonempty `visibleStatusCopy` first for **every**
  contracted card, including Done. Thus exact `Replaced — <date>` and terminal
  not-applicable/retired/completed copy are visible. When absent it executes the
  existing legacy switch unchanged.
- Contracted cards never enter `allActiveTasks`, `taskQueue`, the frozen Daily
  Dose, or `getAhead`, and never set
  `showTaskFlow`. A pure Home projection returns separate `actionableLegacy` and
  `readOnlyContractStatus` arrays. `PeezyHomeView` renders the first pending
  contract's title plus visible copy as a passive, untappable line on **every**
  relevant Home state: greeting, returning, active legacy task, daily-complete,
  and all-complete. Rendering is mandatory, not conditional on an actionable
  legacy row. No button, gesture, flow callback, lifecycle write, local dose
  credit, or queue removal is attached. This is the only Home UI addition and
  contains status copy only.

Preservation changes:

- Both initial and incremental generation call one injected transaction-runner
  seam. The production Firestore transaction first reads the user root and
  rejects an active taskReset marker, then reads every candidate task ref before
  any write, sets only refs missing in that transaction snapshot, and
  safely retries on concurrent mutation. It never updates an existing document;
  no read-then-batch-set path remains. Candidate count is checked against the
  Firestore transaction limit before running and fails closed if exceeded.
- `packingTaskData`, `readinessTaskData`, and `suppliesKitTaskData` copy
  `previousData["dispositionContract"]` into the replacement dictionary when
  present. Existing status/snooze preservation logic is otherwise untouched.
- Existing updateData writers continue to omit the field; W5 rejects their
  status transition if the stored task has a contract. Server W3/W4 transactions
  update status and contract together. Phase 2 must call the server lifecycle
  surface when it adds controls for contracted rows.
- Every task mutation in `getWorkflowQualifying.js` becomes reset-aware and uses
  an exported injected transaction helper. Each real Firestore transaction reads
  the user root marker, then every target task ref, before any task write. While
  reset is active it fails precondition with zero task writes. A missing or
  contractless target retains the exact legacy create/update data and response.
  A guidance completion on a contracted target atomically writes
  `Completed`/`COMPLETED` with no terminal kind and clears every nonterminal
  owner/action/trigger/resume field. A contracted vendor handoff may write
  `matching_in_progress`/`WAITING_ON_EXTERNAL` only through the complete builder:
  its existing server-authored trigger payload must explicitly contain the
  intended `waiting_owner`, `waiting_next_action`,
  `waiting_resume_destination`, and trigger evidence/basis. The builder derives
  copy from those fields and the named workflow; absent/expired/generic evidence
  fails closed. Neither path preserves stale disposition-specific fields. A
  mini-assessment create that collides with a contracted target, or any malformed
  existing contract, fails closed instead of overwriting or emitting a
  status-only pair. The old best-effort catch may
  remain only for missing contractless guidance/vendor task refs; it may not
  swallow reset, contract, validation, or transaction errors.

### RED acceptance tests

`DispositionContractTests`:

- `contractMapDecodesAllKnownFieldsAndPreservesRecursivePayload` with mixed
  bool/integer/double/string/Timestamp/array/map/null values.
- `missingContractProducesByteIdenticalLegacyCardSnapshot`: fixed Timestamp
  fixture, sorted-key JSON encoding of mapped card equals the explicit legacy
  expected card bytes.
- `emptyVisibleCopyFallsBackToNil`.
- table-driven shared-validator fixtures reject every missing mandatory
  owner/action/trigger/resume/copy field, partial event/date triggers, generic or
  backdated evidence, terminal/nonterminal stale fields, and accept exact
  USER_ACTION/WAITING/COMPLETED/terminal builder outputs.
- `existingContractSurvivesPackingAndReadinessReplacementBuilders` through
  internal pure builder seams (make them `nonisolated static`/internal without
  changing production call shape).
- `bothGenerationPathsDoNotRewriteExistingCompletedSnoozedOrSupersededTasks`
  through an injected transaction fake whose first attempt observes a concurrent
  lifecycle mutation and whose retry must preserve it and the first row UUID.
- `upcomingWithClearedSnoozedUntilIsNotSnoozedAndHasNoScheduledDate`.
- Table-driven contract projection covers every status mapping with and without
  a contract; legacy expectations equal the pre-Phase-1 fixtures exactly.
- Every visible noncomplete contracted mapping has status copy and no direct
  task-row status action; completed and confirmed-superseded terminal cases keep
  their defined terminal projection.
- `notApplicableRetiredAndSupersededHaveDistinctTerminalKindsAndDoneProjection`.
- `terminalContractCopyRendersOnDoneIncludingExactReplacedDate`.
- Home projection puts every contracted status in passive status only and every
  legacy fixture in its byte-identical prior queue; starting/focusing a passive
  row cannot invoke a flow callback, mutation, dose credit, or removal seam.
- passive-only, daily-complete, all-complete, active-legacy, and get-ahead
  fixtures all retain the passive copy while get-ahead sees legacy tasks only.
- getWorkflow characterization covers exact missing/contractless legacy bytes
  and responses for guidance, mini-assessment, and vendor paths; contracted
  guidance has no stale nonterminal keys; contracted vendor maps are asserted in
  full for valid explicit evidence, while missing/generic/past evidence,
  contracted mini-assessment collision, and malformed contract fail closed; an
  active-reset fixture rejects every mutation with zero task writes.

### Blast radius / do not change / fallback

PeezyCard memberwise construction is centralized through its defaulted custom
initializer, so additive default is source-compatible. Do not alter TaskStatus,
legacy grouping/Home queue results, existing legacy status strings, snooze
duration, or Build 25 startup code. If model Codable synthesis breaks, add
explicit CodingKeys only; never fork the mapper.

## W2 — subject-aware t2 keys and row-aware H51 resolution

### Read first

The bound item-4/item-5 inventories, all Phase 0 spawn tests, SpawnService,
FlowDefinition row resolution, and FlowEngine's spawn display/submit path.

### Order and break

1. Extend `ConversationFlowTests` and Node spawn tests first.
2. Run the literal W2 safety envelope—only `ConversationFlowTests`, plus the
   UI-target skip—and the Node spawn suite: missing subject fields and
   row-expanded zero-spawn assertions are RED.
3. Implement client resolution/serialization, then server validation and t2
   transaction path. Keep the t1 functions byte-for-byte behaviorally stable.
4. Run ConversationFlowTests and both spawn Node suites GREEN.

### Exact Swift code contract

`SpawnService` adds:

```swift
struct Subject: Equatable { let kind: String; let id: String }
struct Spawn: Equatable {
    let taskId: String
    var titleParams: [String: String]? = nil
    var subject: Subject? = nil
    var institutionId: String? = nil
    var institution: String? = nil
}
```

Extract pure `SpawnService.makePayload(requestToken:expectedUserId:spawns:answers:)`.
It adds first-class `subject {kind,id}`, canonical `institutionId`, and display
`institution` only when all are present; existing titleParams stays for
backwards-compatible title rendering. Legacy payload dictionaries compare
exactly equal to their pre-Phase-1 fixtures, including omitted optionals and
`expectedUserId`.

`FlowRow` gains persisted `subjectId`. When TaskGeneration first authors
`flowRows`, it assigns a UUID per row and retains it forever through W1's
add-only behavior. Legacy stored rows lacking the field decode with their row ID
as a migration fallback; no read-path writeback occurs. Resolved row instances
carry `rowSubjectId` separately from their display/category-derived row ID.

Add `FlowAnswerIdentity: Codable, Equatable { id, label, source }`, where source
is `mapkit` or `manual`. `FlowProgressSnapshot` gains a defaulted
`answerIdentities` dictionary; `TaskActionService` persists/restores it under
`flowAnswerIdentities` in the same progress write as path/answers. Existing
snapshots decode with an empty dictionary. Every terminal/abandon cleanup deletes
`flowPath`, `flowAnswers`, and `flowAnswerIdentities` atomically; a fresh flow can
never reuse a stale identity. The business-search card accepts and
returns this object, not a bare String:

- selecting an autocomplete result resolves its `MKMapItem.Identifier` when
  available; otherwise it assigns one UUID at selection time;
- confirming typed/manual text assigns one UUID exactly once and retains it
  across label edits, back navigation, persistence, and resume;
- display answers remain the current String arrays for branch/submission
  compatibility, while the parallel identity object is canonical for spawning;
- restoration of a legacy business-search String without identity assigns a
  UUID once, immediately persists the additive identity, and then reuses it.

The MapKit lookup is behind an injected resolver, and pure construction accepts
an injected UUID factory so unit tests are offline. `TaskFlowBusinessSearchCard`
and `FlowExitControl` are therefore mandatory W2 files, not incidental scope.

Flow resolution treats the exact source step and every resolved step whose id
ends in `.<sourceId>` as sources, in resolved step order. For each recorded
selection it resolves option ID and label and emits:

- unexpanded step: subject `{kind:"service", id:selection}`;
- `{rowId}.provider`: subject `{kind:"service", id:rowSubjectId}`;
- institutionId: option ID for select steps or the persisted business identity
  ID; institution: display label. A mutable raw label is never an institutionId.
  The display label is also in legacy titleParams.

Guarded non-per-selection spawns remain legacy t1 unless their future definition
or caller explicitly supplies identity. The financial test asserts all row IDs,
labels, durable subjects, and stable order. Reordering same-category rows or
renaming an institution label leaves canonical identity unchanged; two same-
category rows remain distinct. Medical/memberships expansion remains unchanged.

### Exact server code contract

Validation allows subject kinds exactly
`person|pet|vehicle|property|service|child`. `subject.id` is trimmed nonempty and
≤256 UTF-8 bytes; institutionId is trimmed nonempty and ≤256 bytes; display
institution is trimmed nonempty and ≤512 bytes. Subject, institutionId, and
institution must appear together. If titleParams.institution also appears it
must equal display institution after cleaning. A request may have all legacy
spawns or all subject-aware spawns, never a mix. All checks occur in
`validateRequest` before `dbFactory()`/any read. Omitted fields produce the exact
old cleaned spawn object and fingerprint.

Export pure helpers:

```js
canonicalTaskIdV2(userId, spawn) // t2_ + 40 digest hex
isSubjectAwareSpawn(spawn)
executeSubjectAwareSpawn(db, userId, request, now)
```

`canonicalTaskIdV2` hashes canonicalJSON of the locked tuple using institutionId.
`buildTaskDoc` stores first-class `subject`, `institutionId`, display
`institution`, and `canonicalKeyVersion: 2`; title substitution uses display
institution and falls back to titleParams for t1.

Legacy-only requests preserve the exact t1 IDs, fingerprints, document shapes,
replay results, all-create preconditions, and answer merge, but their final
create/token commit moves into a Firestore transaction solely so it can read the
user taskReset marker atomically. Phase-0 characterization and concurrency tests
must stay byte-for-byte green. Subject-aware requests use the same reset-aware
transaction discipline:

1. Fast token read/replay remains fingerprint checked.
2. Catalog and move-date reads complete before the transaction; unknown rows
   still write nothing.
3. Precompute unique t2 refs; duplicate canonical keys within one request are
   invalid-argument before transaction writes.
4. In one transaction, read the user root/reset marker, token, then all t2 task
   refs before any write; an active reset fails precondition without creation.
5. Existing t2 doc is reusable only when its full server provenance matches:
   document `id`, `userId`, `taskId`, exact subject/institutionId,
   `canonicalKeyVersion:2`, and `spawnedFrom` are all present and valid. Any
   missing/mismatched provenance fails precondition; a preclaimed arbitrary doc
   is never adopted. Display-label drift may enrich only display fields without
   changing identity or lifecycle. Missing doc is transactionally created.
   Existing status and user state are never overwritten.
6. Merge answers and create the token result/fingerprint in the same transaction.
   Concurrent different-token calls for the same tuple converge on one task;
   each valid token records the same task result. Same-token Phase 0 replay
   remains unchanged.

### RED acceptance tests

Swift additions:

- `rowExpandedFinancialProvidersProduceOneSubjectAwareSpawnPerRow` — two row
  instances and three total provider answers yield exactly three spawns with
  durable row-specific service subjects, institution IDs, and display labels.
- Existing `perSelectionExpandsWithOptionLabels` now asserts subject/institution.
- `medicalAndMembershipRowExpansionStillChainsWithoutSpawnMutation`.
- `rowSubjectIdentitySurvivesReorderAndInstitutionLabelRename` and
  `twoSameCategoryRowsRetainDistinctSubjects`.
- `makePayloadPreservesExactLegacyShapeAndSerializesExactT2Identity`.
- `businessSearchSelectionPersistsStableProviderOrManualIdentityAcrossRename`
  and `legacyLabelMigrationGeneratesAndPersistsOneUUIDOnly` using offline fakes.
- `terminalClearRemovesAnswerIdentityAndRestartGeneratesFreshIdentity`.

Node additions:

- exact hard-coded t2 digest vector;
- same tuple/different tokens/concurrent → one task doc, two replay tokens;
- same institutionId/task/different subject → two docs;
- different institutionId or task → distinct docs; display-label rename reuses;
- t1 and t2 coexist; old t1 hard-coded digest/fingerprint vector unchanged;
- t2 replay same token same payload succeeds; drift fails on both replay paths;
- existing t2 task is reused without overwriting status/custom fields;
- contractless/preclaimed or incomplete-provenance t2 doc fails closed;
- validation type/kind/empty/multibyte caps, missing institutionId, mismatched legacy title param,
  partial identity, mixed request, duplicate canonical key all fail pre-read.

### Blast radius / do not change / fallback

Do not change token paths, t1 IDs, the Phase 0 fingerprint version, answer merge,
nudge/movers/rent-truck callers, observable t1 replay/create semantics, or flow
JSON. If transaction fakes become too
coupled, extract an injected transaction adapter, but production must still use
one real Firestore transaction and tests must model retry/read-before-write.

## W3 — one transactional Change-plan callable and client

### Read first

W2 helpers, the W1 model, Functions callable auth patterns, SpawnService response
parsing, and §A A7 external amendment.

### Order and break

1. Write Node task-plan and Swift client payload/response tests first; both are
   RED because files/export do not exist.
2. Implement the server core/export, then the thin client.
3. Run the literal W3 safety envelope—only `TaskSupersessionTests`, plus the
   UI-target skip—and the Node task-plan suite GREEN before W4.

### Request and response contract

One callable export `changeTaskPlan` supports:

```js
{ action:"supersede", taskId, reason, operationId,
  replacement?: {
    taskId, subject:{kind,id}, institutionId, institution,
    amendmentAction:{ nextTrigger, resumeDestination },
    verification:{ nextTrigger, resumeDestination }
  } }
{ action:"confirmAmendment", taskId, reason, operationId }
{ action:"undoConfirmation", taskId, reason, operationId }
{ action:"reopen", taskId, reason, operationId }
{ action:"resetAllTasks", reason:"retake_assessment", operationId }
{ action:"finalizeTaskReset", reason:"retake_assessment", operationId }
```

All IDs and operationId use Phase 0 doc-ID checks; reason is trimmed nonempty
≤1000 bytes. Replacement validation reuses W2's subject-aware validation and
must include the full t2 identity. Its catalog taskId must differ from the
original task's catalog taskId. Whenever `replacement` is present,
`amendmentAction` and `verification` are both required as a pair and are
structurally validated before DB access; each supplies its own
complete evidence-bearing trigger plus a nonempty stable resume destination.
They may not alias mutable objects. Owner/action/copy are derived server-side
from the authenticated user, stored task, and named institution. Auth and request-shape
validation occur before DB creation/read. Whether replacement is required or
forbidden depends on the stored task's `external_submission` flag and is decided
inside the transaction after re-reading the original: external requires it;
internal rejects it with zero writes and never creates, links, or returns a
replacement. Response:

```js
{ taskId, status, replacementTaskId: string|null,
  lifecycleState:"retired"|"pending_amendment"|"pending_confirmation"|"confirmed"|"reopened",
  revision: number, replayed: boolean }
// reset union:
{ reset:true, deletedCount:number, replayed:boolean }
```

### Transaction semantics

`handleTaskPlanRequest(request, dbFactory, now)` is the injected test seam.
Every non-reset action transaction reads its operation document first. When it
exists, exact fingerprint equality returns the recorded response with
`replayed:true` immediately, without requiring the user root or original task;
drift fails precondition immediately. This read-only replay remains valid while
a task reset marker is active and after Retake deletes the original. Only a new
operation reads the user root and original task next, fails while a reset marker
is active, and revalidates the stored external/internal flag before any write.
For a new external branch, the same transaction then reads replacement catalog
and move-date inputs; there is no catalog/move pre-read whose result can race the
original. All transaction reads precede all writes.
`canonicalAmendmentId(uid, originalTaskId, revision, replacement)` uses an
`a2_` prefix and canonical JSON including the original task, cycle revision,
subject, institutionId, and amendment catalog taskId. It can never resolve to
the original t1/t2 ref or collide with an ordinary spawned t2 task.

Each new operation writes `users/{uid}/taskPlanOperations/{operationId}` in the
same transaction with request fingerprint and response. The operation-first
read above defines identical replay and drift behavior. Each original stores
monotonic `planChangeRevision`, current `planChangeState`, and append-only
`planChangeHistory` transition records. Every action appends a new immutable
record (`supersede`, `confirm`, `undo_confirmation`, `reconfirm`, or `reopen`);
prior records are never edited. History has a tested bound of 50 records; overflow
fails closed instead of truncating audit history.

Reset is the one two-phase operation: its operation document stores
`kind:"reset"`, the reset request fingerprint, `tasks_deleted`, and `finalized`
phase results. `finalizeTaskReset` with the same operationId is a permitted phase
advance, not fingerprint drift; any non-reset action or mismatched reset reason
using that ID still fails precondition. Both phases replay independently.

The complete current-state transition table is closed by default:

| Current state | Allowed new action | Result |
|---|---|---|
| absent/reopened | supersede internal | retired, new revision |
| absent/reopened | supersede external | pending_amendment, new revision |
| pending_amendment | confirmAmendment | confirmed |
| pending_amendment | reopen | reopened only if amendment untouched |
| confirmed, within 5 minutes | undoConfirmation | pending_confirmation |
| pending_confirmation | confirmAmendment | confirmed again, same revision |
| retired internal | reopen | reopened |

An identical stored operation is a read-only replay from any state, including an
active reset or missing original. Every new operation and every drifted replay
continues through the closed table. Every other new action,
including a different-operation supersede while pending, confirmed, retired, or
pending_confirmation, fails precondition. Transactions re-read state so
simultaneous different operation IDs cannot orphan or replace a pending pointer.

Internal supersede (no external submission) immediately sets Dismissed, updates
the contract coherently with no current A2 disposition and terminal_kind
retired, removes any stale `supersededBy`, and appends an immutable supersede
record containing reason, prior status/contract, at, revision, and no
replacement. Its response always has `replacementTaskId:null`.

External supersede requires a replacement. It leaves the submission artifact in
force but atomically changes the task status to matching_in_progress and its
contract to the complete WAITING_ON_EXTERNAL builder output. Owner is the named
institution; next action is “Review and apply the requested amendment”; trigger
and resume destination come from the validated evidence-bearing verification
descriptor; copy is “Your existing submission is still active; confirm the
amendment with <institution>.” Missing, generic, partial, expired, or malformed
verification fails closed. The transition records
`pendingAmendmentTaskId`, and appends an immutable supersede record. It creates the
amendment at the amendment-specific ref as InProgress with `supersedes`, revision,
subject/institution identity, and exact
`buildAmendmentActionContract(uid, institution, amendmentAction, now)` output:
USER_ACTION_TRACKED; owner `user:<uid>`; next action “Submit the amendment to
<institution>”; the amendmentAction evidence-bearing trigger and resume
destination; and copy “Amendment ready to submit to <institution>.” This wrapper
calls the shared USER_ACTION builder and persists both immutable action and
verification descriptors on the plan-change cycle for later transitions. An
existing ref is reusable only when it is already the exact active amendment for
this original/revision and its required identity/contract match; an ordinary,
other-original, missing-contract, Completed, or Dismissed document is a failed
precondition. No state is silently reopened.

`confirmAmendment` requires the exact pending_amendment or pending_confirmation
cycle. In one transaction it marks
the original Dismissed with no current A2 disposition, terminal_kind
superseded, `supersededBy`, and “Replaced — <date>”, marks the
amendment Completed with a coherent completed contract/copy, closes the history
state as `confirmed`, appends an immutable confirm/reconfirm record, and records
`firstConfirmationUndoUntil = first confirmation time + 5 minutes` only on the
first confirmation. Reconfirmation never extends it.

`undoConfirmation` is operation-idempotent and allowed only before that deadline
when neither document changed after confirmation. It does **not** claim the
institution reversed anything: it moves the original to matching_in_progress
with a freshly built complete WAITING_ON_EXTERNAL map: owner is the institution,
next action is “Confirm whether the amendment remained in effect,” copy is
“Confirm whether <institution> kept the amendment,” and it reuses the immutable
evidence-bearing verification descriptor stored on the cycle. It never merges
the prior USER_ACTION/COMPLETED map. If that trigger is now expired, undo fails
closed rather than inventing or backdating a reminder. The transition removes
terminal_kind/supersededBy, restores the amendment to InProgress with a freshly
built exact USER_ACTION_TRACKED verification map: owner `user:<uid>`; next action
“Check the amendment status with <institution>”; the stored verification trigger
and resume destination; and copy “Verify whether <institution> kept the
amendment.” A named `buildAmendmentVerificationActionContract` wrapper calls the
shared USER_ACTION builder; it never reuses the initial amendmentAction trigger.
The transaction marks current state `pending_confirmation`, appends a new immutable undo record, and sets
`confirmationUndoUsed:true`. Expiry, independent progress, invalid evidence, or
any second undo for that revision fails closed.

`reopen` is operation-idempotent. It is permitted for an internal retired cycle,
or for a pending external cycle whose amendment is still the untouched generated
InProgress document. It restores the original prior status/contract and retires
that untouched amendment atomically with cancellation copy. If the amendment
progressed, was independently modified, or the cycle is confirmed or
pending_confirmation, reopen fails closed. A later supersede after a successful reopen uses the next
revision and a distinct amendment ref; prior cycles remain append-only.

`resetAllTasks` preserves the audited Retake Assessment behavior without giving
clients authority to delete contracted/audited rows. A first request
transactionally writes a server-owned `taskReset` marker on `users/{uid}` with
operationId/state `deleting`, `deletedCount:0`, and an empty worker lease; **all** task create/status paths in W1/W2/W3 and
`getWorkflowQualifying` check it transactionally, and W5 rules deny
client task creates while it is active.

Reset paging has one exclusive, crash-safe worker. Each invocation chooses a
random workerId and transactionally acquires or takes over an expired ten-minute
lease stored in the marker; a live foreign worker makes an identical request
return a retryable unavailable result without scanning. A page query selects at
most 400 task refs ordered by full document name. One Firestore transaction then
reads the marker/operation, verifies `deleting`, operationId, workerId, and a live
lease, reads every selected task ref, deletes only the still-existing snapshots,
renews the lease, and atomically increments the marker and operation document's
cumulative `deletedCount` by that unique committed count. There is no
query-then-batch-delete path. A crash after a page commit therefore preserves
both deletion and its exact count; after lease expiry a new identical caller
continues from the remaining query. Phase transition uses a final transaction
that re-verifies owner/lease and performs an empty ordered task query before
setting `awaiting_local_reset`, persisting the exact count, and clearing the
worker lease. A stale worker fails closed on every page or transition after
ownership, phase, or marker changes, so it cannot delete a task regenerated
after finalization. A different reset operation fails precondition. The reset
never deletes assessments, dose state, or other collections.

`RetakeAssessmentCoordinator` owns the client sequence behind
`PeezySettingsView`; the view no longer touches Auth, Firestore, DailyDose, or
notifications inside its Retake operation. The coordinator is initialized with
injected current-user, task-plan-callable, assessment-delete,
userKnowledge-delete, dose-reset, durable-operation-store, and notification
closures. Production adapters use the existing services and `UserDefaults` for
a per-user pending operation UUID. Before phase one it loads an existing UUID or
creates and durably saves one; reconstruction adopts that same value. It then
awaits `resetAllTasks`, deletes assessment documents, deletes userKnowledge with
errors propagated (never `try?`), resets Daily Dose, and awaits
`finalizeTaskReset`, all with the same operation ID. Local cleanup operations are
idempotent and may safely replay after any partial or ambiguous failure. The UUID
is cleared only after successful or replayed finalization, and the navigation
notification is posted strictly after that clear. Any error retains the UUID and
posts no notification, so the next tap or reconstructed coordinator resumes the
same operation. The marker remains active throughout local cleanup. No UI copy
changes.

The Swift `TaskPlanService` exposes `supersedeTask`, `confirmAmendment`,
`undoConfirmation`, `reopenTask`, `resetAllTasks`, and `finalizeTaskReset`. It
requires a caller-created operationId, serializes
the exact payloads, invokes only `changeTaskPlan`, validates the response, and has an
injected async callable closure for pure unit tests. No UI is added. Other
contract-bearing complete/undo/snooze/in-progress controls remain hidden in
Phase 1 and fail direct rules writes; Phase 2 must add validated server actions.

### RED acceptance tests

Node:

- unauthenticated/invalid shape/reason/replacement fail before DB access;
- replacement on an internal supersede fails after the transactional original
  read with zero writes; a valid internal supersede writes no `supersededBy` and
  returns `replacementTaskId:null`;
- ordinary supersede is atomic and preserves unrelated fields;
- external submission without replacement fails closed with zero writes;
- external submission + replacement keeps the original active/visible and
  creates one subject-keyed pending InProgress amendment; full original and
  amendment contract maps exactly match the mandatory builders with distinct
  amendmentAction versus verification trigger/resume inputs, and
  missing/partial/generic/past amendmentAction or verification evidence fails
  the pre-DB validation matrix and produces zero writes;
- confirmation atomically retires the original and completes the amendment;
- confirmation undo is bounded, replayable, restores truthful pending
  verification with the exact institution WAIT map plus user verification-action
  map, and rejects expiry or post-confirmation progress;
- confirm→undo→reconfirm retains the first absolute deadline and immutable
  transition sequence; a second undo fails;
- same-ref/same-catalog, ordinary-t2, terminal-existing, and other-original
  replacement collisions fail closed;
- concurrent/repeated same operation never duplicates amendment; operation
  fingerprint drift fails precondition;
- exact stored non-reset operation replays during an active reset and after its
  original task has been deleted; drift still fails before root/original reads;
- simultaneous and sequential different-operation supersedes while pending both
  fail and preserve the first amendment pointer;
- injected failure aborts both original and replacement writes;
- reopen replay returns the recorded response; pending reopen restores the
  original and cancels only an untouched amendment; progressed/confirmed fails;
- supersede→reopen→supersede increments revision and preserves both cycles;
- reopen non-superseded task fails precondition.
- reset marker blocks client/server creates; a live worker excludes a concurrent
  same-operation caller; multi-page deletion resumes after a crash immediately
  after a committed page with the exact cumulative unique count; expired-owner
  takeover succeeds; same-operation replay is exact; different reset conflicts;
  only tasks are removed; an owner-checked empty page alone advances phase;
  marker remains through local reset; same-operation finalize clears it exactly
  once; and a stale worker cannot delete a same-ID task regenerated after
  finalization.
- every task document output from supersede/confirm/undo/reopen passes the shared
  W1 full-contract validator; fixtures assert all owner/action/trigger/resume/copy
  fields and absence of stale fields, not merely status/disposition pairs.

Swift `TaskSupersessionTests`:

- exact supersede/confirm/undo-confirmation/reopen/reset payloads, operation IDs, and callable name;
- subject/institutionId/display serialization;
- valid response decode and invalid response error;
- callable error propagates, no retry invented client-side.
- the injected Retake coordinator waits for reset success before local cleanup,
  persists/adopts its operation ID across reconstruction, propagates assessment,
  userKnowledge, and dose failures independently, safely replays each partial
  sequence, retains the ID after an ambiguous finalize, clears it only after
  successful/replayed finalize, and posts navigation strictly afterward.

### Blast radius / do not change / fallback

No Change-plan UI, optimistic undo, catalog seed, or external call. The sole task
deletion is the authenticated Retake reset action above.
A missing amendment catalog row is a not-found failure with no writes. If a
transaction/history limit is hit, reject the request; never split an operation
across commits or erase prior cycles.

## W4 — one scheduled date/event evaluator

### Read first

W1 contract keys, item-3 readers, A11a envelope/lifecycle lines 139-164,
Functions index/export conventions, and committed firebase config.

### Order and break

1. Add scheduler/helper tests and index-config assertions first; RED on missing
   module/export/config.
2. Implement pure predicates, injected evaluator, and thin onSchedule wrapper.
3. Run the new Node suite twice against the same fake state to prove idempotence.

### Exact module contract

New `dispositionTriggers.js` imports `onSchedule` from
`firebase-functions/v2/scheduler` and exports:

```js
evaluateDispositionTriggers // onSchedule({schedule:"every 15 minutes", ...})
makeDispositionTriggerHandler({dbFactory, nowFactory, evaluator})
runDispositionTriggerEvaluation(db, now)
acquireEvaluationLeaseInTransaction(db, runId, now)
wakeDateTaskInTransaction(db, ref, now)
consumeEventEnvelopeInTransaction(db, eventRef, now)
reconcileEventTaskInTransaction(db, taskRef, now)
validateEventEnvelope(data, documentId)
canonicalEventStateId(eventName, canonicalKey)
canonicalEventEnvelope(data, documentId)
mapWithConcurrency(items, limit, operation)
```

The factory returns a zero-argument handler that invokes the injected evaluator.
The production export is constructed with endpoint-local options—region
`us-central1`, schedule `every 15 minutes`, timeout 540 seconds, memory 512 MiB,
maxInstances 1, concurrency 1, and retryCount 0—so import order/global options
cannot alter its budget. It wraps a factory handler using `admin.firestore`,
`new Date`, and the real evaluator. The offline wrapper test constructs its own
handler with fakes before passing it to `onSchedule`; no lexical export
reassignment is used. No notification code is imported or called.

Every run first transactionally acquires
`phase1System/dispositionTriggerLease` with random runId and ten-minute
expiresAt. A live foreign lease returns `{skipped:"lease-held"}` with no scans;
the owner releases in `finally` through a transaction that deletes/clears the
lease only when the stored runId still equals its runId. An expired former
owner's delayed release is a no-op and cannot clear its successor's lease or
cursors. `phase1System/dispositionTriggerState` stores
the cursors below. Cursor updates require the same live runId, preventing an
overlap/restart from regressing state. Candidate transactions use bounded
parallelism 10; no unbounded Promise.all appears.

Date query is a collection-group query with exact predicates `status ==
Snoozed`, `dispositionContract.next_trigger.kind == date`, and `at <= now`,
ordered by `at` then full document name and fetched with `limit(201)`. Cursor
state is the tuple `{dateAfterAt, dateAfterPath}`; startAfter uses both the saved
timestamp and `db.doc(fullPath)`. It deliberately
does not filter `fired`, so legacy/missing false values remain candidates. At
most 200 are processed. After every page, including failed/no-op/poison
candidates, the live lease transaction advances to candidate 200; when no 201st
row exists it clears the tuple to wrap on the next run. Thus 200 poison rows
cannot permanently hide row 201. Each
task transaction re-reads and rechecks every predicate including `fired !==
true`, then writes status Upcoming, deletes `snoozedUntil`, and replaces the
contract with exact `buildUpcomingContract(base, "Ready to continue")` output.
The consumed current trigger and all deferred owner/action/resume fields are
removed; no stale `next_trigger.fired` audit marker remains in the current
contract. Status no longer matches the Snoozed query, so a second run is a no-op.
The resulting document must pass the shared W1 full-contract validator.

Event ingestion is separated from task wakeup so publication cannot be lost:

1. Server authors `users/{uid}/events/{event_id}` with `processingState:
   "pending"`, `processed:false`, nonempty event_name/canonical_key,
   integer safe `source_version >= 0`, observed_at, source_evidence_id,
   `effect:"fire"|"retract"`, and a Firestore-safe payload. The pending
   collection-group query orders by full document name only and fetches 101; at
   most 100 are processed per run. Missing observed_at is therefore still
   selected for quarantine.
2. A transaction validates event_id == document ID and compares the envelope to
   `users/{uid}/eventState/{sha256(canonicalJSON([event_name,canonical_key]))}`.
   Canonical JSON removes delimiter ambiguity. The complete semantic envelope
   includes event_id, event_name, canonical_key, source_version, normalized
   observed_at, source_evidence_id, effect, and recursively canonical payload;
   its fingerprint is stored in high-water state. A strictly newer
   version advances the high-water record with version, effect, event ID,
   evidence, and payload. An older event becomes terminal `stale`; exact replay
   means full fingerprint equality and becomes terminal `duplicate`; **any**
   same-version drift—including event ID, evidence, effect, payload, or metadata—
   becomes terminal `version_conflict` without changing high-water. Every terminal row
   atomically sets `processingState:"terminal"`, processed true, processedAt,
   and outcome. Invalid envelopes become terminal
   `quarantined` with processingError and no longer occupy the pending query.
3. Independently query Snoozed event-trigger tasks, ordered by full document
   name, with `limit(201)`. Cursor state is full `eventTaskAfterPath`, applied as
   `startAfter(db.doc(path))`; candidate 200 advances it under the live lease,
   and a final page clears it to wrap. Duplicate task leaf IDs under different
   users remain distinct. For each task, a
   transaction reads its corresponding high-water record. It wakes only when
   event_name and canonical_key match, high-water source_version is greater than
   trigger.after_source_version (default -1), effect is `fire`, and fired is not
   true. A retraction only advances high-water; it never wakes. Wake sets status
   Upcoming, deletes snoozedUntil, and uses exact `buildUpcomingContract` output,
   clearing the consumed event trigger and all deferred fields. The durable
   high-water record already holds source version/event/evidence, and status no
   longer matches the query, so no duplicate audit marker is written into the
   current contract. The shared W1 full-contract validator must accept it.
   The cursor wraps after the last page, so unmatched tasks cannot starve later
   tasks. Event-first/task-later and concurrent publication are therefore
   reconciled on a later pass rather than lost.

All task/event/high-water/cursor writes are Admin SDK writes. Add and parse-test
exact `firestore.indexes.json` configuration:

- collection-group `tasks`: status ASC,
  `dispositionContract.next_trigger.kind` ASC,
  `dispositionContract.next_trigger.at` ASC (date cursor query);
- collection-group `tasks`: status ASC,
  `dispositionContract.next_trigger.kind` ASC (event-task document-name query;
  Firestore appends `__name__` ordering);
- collection-group field override for `events.processingState`, ASCENDING,
  queryScope COLLECTION_GROUP (pending equality + document-name query).

Wire that file through `firebase.json`. Tests deep-equal the full indexes and
fieldOverrides arrays, not substrings. No index/deploy command runs.

### RED acceptance tests

- future date no-op; due date wakes once; re-run no-op;
- date trigger with missing fired wakes; exact query order/limit is asserted;
  date and event wakes both equal the exact Upcoming builder map and retain none
  of the prior deferred owner/action/trigger/resume fields;
- wake clears snoozedUntil and every item-3 predicate fixture reads not snoozed;
- newer event followed by older event leaves high-water at newer and consumes
  the older stale; duplicate and same-version conflict outcomes are terminal;
- correction with a greater version advances and may wake; retraction advances
  but never wakes;
- hard-coded `("a|b","c")` versus `("a","b|c")` state-key vector is distinct;
- same-version effect-only, payload-only, evidence-only, and event-ID drift are
  conflicts; only full canonical equality is duplicate;
- event-first/task-later and concurrent task/event publication wake on a later
  reconciliation; another user's/canonical-key task never wakes;
- 100 invalid events are quarantined, then the following valid event progresses;
- more than 100 stale/duplicate/version-conflict terminal outcomes all leave the
  pending query and the following valid event progresses across repeated runs;
- missing-observed-at is selected and quarantined;
- full-path cursor pagination reaches a later date/event task behind 200 poison
  or unmatched tasks, handles duplicate leaf IDs under two users, wraps, and
  survives restart; concurrent runs cannot regress either cursor;
- no push/notification dependency or write appears;
- a factory-built scheduled wrapper `.run` invokes its injected evaluator
  offline; the production export exposes a scheduler endpoint;
- endpoint metadata, ten-way work cap, lease skip, expiry takeover, and
  owner-matching finally release are exact; a delayed stale-owner release leaves
  its successor's lease and cursor writes untouched;
- index config deep-equals every required index/fieldOverride signature.

### Blast radius / do not change / fallback

No push/deep link, research, scene-phase flush, or generalized cross-entry event
router. Batch bounds and cursor defer overflow. A per-document failure is logged
and does not prevent later candidates, but no transaction partially wakes. A
retraction never tries to reverse an already-observed user-visible wake.

## W5 — explicit owner rules and offline emulator suite

### Read first

The complete item-6 matrix, effective additive-rule semantics, root subscription
protection, supportChat/moveAnswers rules, and local Firebase emulator docs bundled
with the installed CLI.

### Order and break

1. Add `@firebase/rules-unit-testing` as a dev dependency and write the suite.
2. Run it against current rules in a `demo-peezy-phase1` local emulator: the
   spawnTokens/events/contract denial rows must be RED while legacy-allow rows
   identify any harness problem.
3. Replace the recursive grant with explicit rules; re-run GREEN.

### Exact rules shape

- Root user, supportChat, moveAnswers, inventorySessions, inventory, identity,
  and top-level userKnowledge rules retain current semantics, except root-user
  client create/update now protects both `subscription` and server-owned
  `taskReset` from add/modify/delete.
- Add owner CRUD for fcmTokens, packingPlan, readiness, tasks, and
  user_assessments.
- Task IDs beginning `t1_`, `t2_`, or `a2_` are reserved: client create is
  always denied. Any ordinary client create must omit the server-authored set
  `spawnedFrom`, `subject`, `institutionId`, `institution`,
  `canonicalKeyVersion`, `supersedes`, `planChangeRevision`, `planChangeState`,
  `planChangeHistory`, and `pendingAmendmentTaskId`. An existing contractless
  task may use current lifecycle fields, but client updates may not affect that
  set or `flowRows`; reserved t1/t2 tasks additionally freeze `id`, `userId`,
  and `taskId`. Initial normal task create may include flowRows, while
  `flowAnswers` and `flowAnswerIdentities` remain client-writable progress fields.
  Contractless reserved t1/t2 status/snooze/delete remain owner-allowed **only
  when no planChangeRevision/state/history/pending marker exists** because
  the audited current app relies on them; W2 refuses any incomplete provenance,
  and reserved create denial closes preclaim after these rules. A normal catalog
  task create retains the audited current document shape and requires only that
  dispositionContract and plan-change fields are absent.
- A contracted task is read-only to clients: all client update and whole-document
  delete are false, not merely status/contract diffs. This protects contract,
  plan history, identities, supersession links, and scheduling fields together.
  Every task delete, including an ordinary nonreserved ID, additionally requires
  absence of `planChangeRevision`, `planChangeState`, `planChangeHistory`,
  `pendingAmendmentTaskId`, and every other plan/audit field. Thus a reopened row
  whose prior contract was absent remains undeletable because its retained audit
  history is sufficient to deny delete. W1/W3/W4 Admin transactions are the only
  Phase-1 mutation surface for contracted/audited rows.
- All client task creates, updates, and deletes additionally require that the
  parent user document has no `taskReset` in `deleting` or
  `awaiting_local_reset`. This rules-level guard covers every inventoried legacy
  TaskActionService/TasksStore writer while reset owns the collection; W1/W2/W3
  server/client creation paths and getWorkflow also check the marker
  transactionally. Retake deletion itself is W3 Admin SDK work.
- `spawnTokens`, `events`, `eventState`, and `taskPlanOperations` are
  owner-readable but client write false.
- Top-level `phase1System/{document}` (scheduler lease/cursors) has explicit
  client read/write false; Admin SDK remains the only accessor.
- Preserve active server-owned read surfaces with owner-read/write-false rules:
  `packingAggregate`, `research`, `workflowResponses`, and nested
  `chats/{chatId}/messages`. This closes the read side of the item-6 inventory;
  do not rely on the removed recursive grant.
- Replace the recursive owner match with a residual explicit allowlist for any
  inventoried client-write collection not already matched; do not leave a broad
  wildcard that makes the denials additive no-ops.

### Emulator tests

Using owner uid, other uid, and unauthenticated contexts, assert:

- owner task create/update and delete of an untouched contractless, audit-free
  row allowed; a contractless ordinary row with any retained plan/audit field is
  undeletable;
- owner task create with contract or reserved ID denied; add/modify/delete
  contract and **every** contracted update/delete denied; complete, undo, snooze,
  in-progress, plan-history, identity, canonical-key, supersession, provenance,
  and scheduling mutation rows are enumerated;
- `flowRows` mutation is denied while flowAnswers/flowAnswerIdentities progress
  updates remain allowed when no reset is active; every task create/update/delete
  is denied during a reset marker;
- server-created t1/t2 provenance fields are immutable while allowed legacy
  status/snooze/delete paths remain green only for untouched audit-free docs;
  supersede→reopen→client-delete is denied for both reserved and ordinary task
  IDs, including an ordinary task whose pre-supersede contract was absent;
  preclaimed/incomplete t2 is rejected by the W2 server suite; a2 remains
  contracted and client-immutable;
- owner spawnToken/event/eventState/taskPlanOperation create/update/delete denied
  and read allowed;
- phase1System read/write denied to every client context;
- owner root profile write allowed but subscription create/modify/delete denied;
- assessment, fcmToken, packingPlan, readiness, inventorySessions, inventory,
  identity CRUD remains allowed;
- supportChat user-message create/read and support-reply read-only update shape
  remains; moveAnswers owner read/client write denied;
- packingAggregate, research, workflowResponses, and chat messages are owner
  readable/client-write-false; other-user and unauthenticated access is denied;
- other user/unauthenticated denied across every user path.

The suite lives at `functions/rules-tests/firestoreRules.test.js`, outside both
general Node globs, and runs exactly once. The runner uses Firebase CLI's
Firestore emulator only, a `demo-*` project, Node 24, explicitly unset
`GOOGLE_APPLICATION_CREDENTIALS`, `GCLOUD_PROJECT`, and
`FIREBASE_CONFIG`, disabled CLI telemetry/update checks, and no network service
calls.

### Blast radius / do not change / fallback

No wallet rule, storage rule, top-level catalog/definition/provider rule, or
subscription relaxation. If Java is absent, provision a local JDK, record its
absolute JAVA_HOME, and rerun; do not replace emulator evidence with source regex.

## Full red/green and regression commands

Use Node exactly `/opt/homebrew/opt/node@24/bin/node` (v24.19.0). Select simulator
UDID from `xcrun simctl list devices available`; record it. Every XCTest command
must use one of these literal selector envelopes, always include the UI skip, and
contain no `-testPlan`:

```text
W1 RED/GREEN:
  -only-testing:'Peezy 4.0Tests/DispositionContractTests'
  -only-testing:'Peezy 4.0Tests/TaskGroupingTests'
  -skip-testing:'Peezy 4.0UITests'
W2 RED/GREEN:
  -only-testing:'Peezy 4.0Tests/ConversationFlowTests'
  -skip-testing:'Peezy 4.0UITests'
W3 RED/GREEN:
  -only-testing:'Peezy 4.0Tests/TaskSupersessionTests'
  -skip-testing:'Peezy 4.0UITests'
FINAL:
  all four -only-testing selectors above
  -skip-testing:'Peezy 4.0UITests'
```

Never set `PEEZY_RUN_FIRESTORE_INTEGRATION`. Each workstream's red and green use
its same literal selector envelope.
The DEBUG XCTest guard at all three startup sites remains unchanged and active.

Literal per-workstream command forms (each invocation substitutes a unique,
nonexistent absolute result path and the recorded UDID; no other flags change):

```sh
# W1 RED and GREEN
xcodebuild test -project 'Peezy 4.0.xcodeproj' -scheme 'Peezy 4.0' \
  -configuration Debug -destination 'platform=iOS Simulator,id=<UDID>' \
  -only-testing:'Peezy 4.0Tests/DispositionContractTests' \
  -only-testing:'Peezy 4.0Tests/TaskGroupingTests' \
  -skip-testing:'Peezy 4.0UITests' \
  -resultBundlePath '<unique-absent-W1.xcresult>' CODE_SIGNING_ALLOWED=NO
/opt/homebrew/opt/node@24/bin/node --test \
  functions/tests/dispositionContract.test.js \
  functions/tests/getWorkflowQualifying.test.js

# W2 RED and GREEN
xcodebuild test -project 'Peezy 4.0.xcodeproj' -scheme 'Peezy 4.0' \
  -configuration Debug -destination 'platform=iOS Simulator,id=<UDID>' \
  -only-testing:'Peezy 4.0Tests/ConversationFlowTests' \
  -skip-testing:'Peezy 4.0UITests' \
  -resultBundlePath '<unique-absent-W2.xcresult>' CODE_SIGNING_ALLOWED=NO
/opt/homebrew/opt/node@24/bin/node --test \
  functions/spawnTasks.test.js functions/tests/spawnTasks.test.js

# W3 RED and GREEN
xcodebuild test -project 'Peezy 4.0.xcodeproj' -scheme 'Peezy 4.0' \
  -configuration Debug -destination 'platform=iOS Simulator,id=<UDID>' \
  -only-testing:'Peezy 4.0Tests/TaskSupersessionTests' \
  -skip-testing:'Peezy 4.0UITests' \
  -resultBundlePath '<unique-absent-W3.xcresult>' CODE_SIGNING_ALLOWED=NO
/opt/homebrew/opt/node@24/bin/node --test functions/tests/taskPlan.test.js

# W4 RED and GREEN
/opt/homebrew/opt/node@24/bin/node --test \
  functions/tests/dispositionTriggers.test.js
```

Final commands, with absolute worktree/result paths substituted:

```sh
xcodebuild build -project 'Peezy 4.0.xcodeproj' -scheme 'Peezy 4.0' \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test -project 'Peezy 4.0.xcodeproj' -scheme 'Peezy 4.0' \
  -configuration Debug -destination 'platform=iOS Simulator,id=<UDID>' \
  -only-testing:'Peezy 4.0Tests/ConversationFlowTests' \
  -only-testing:'Peezy 4.0Tests/DispositionContractTests' \
  -only-testing:'Peezy 4.0Tests/TaskGroupingTests' \
  -only-testing:'Peezy 4.0Tests/TaskSupersessionTests' \
  -skip-testing:'Peezy 4.0UITests' \
  -resultBundlePath '<unique-absent-PHASE1.xcresult>' CODE_SIGNING_ALLOWED=NO

xcrun xcresulttool get test-results tests \
  --path '<unique-absent-PHASE1.xcresult>' --format json \
  > '<unique-absent-PHASE1-tests.json>'

/opt/homebrew/opt/node@24/bin/node --test functions/tests/*.test.js
/opt/homebrew/opt/node@24/bin/node --test functions/*.test.js

env -u GOOGLE_APPLICATION_CREDENTIALS -u GCLOUD_PROJECT -u FIREBASE_CONFIG \
  PATH="/opt/homebrew/opt/node@24/bin:$PATH" JAVA_HOME="<local-jdk>" \
  CI=1 FIREBASE_CLI_DISABLE_TELEMETRY=1 FIREBASE_CLI_DISABLE_UPDATE_CHECK=1 \
  firebase emulators:exec --only firestore --project demo-peezy-phase1 \
  "/opt/homebrew/opt/node@24/bin/node --test functions/rules-tests/firestoreRules.test.js"
```

Parse the xcresult JSON recursively. Set-compare its suite names to exactly
`ConversationFlowTests`, `DispositionContractTests`, `TaskGroupingTests`, and
`TaskSupersessionTests`; require every recorded leaf test passed and each suite
has a nonzero count. Assert no identifier contains `UITests`,
`IntegrationTests`, `CoverageFirestoreIntegrationTests`,
`PhaseFCalibrationFirestoreIntegrationTests`, or `MoveDistanceIntegrationTests`.
Record the literal full leaf-test roster and counts in PHASE1_BUILD.md; a zero or
missing suite fails verification even if xcodebuild exits zero.

The worktree may contain a transient empty `File.txt` only for Xcode's frozen
resource reference; remove it before diff/merge. Node suites use fakes only.

## Adversarial review and execution protocol

Review this document in one continuing Codex thread. Each round returns numbered
CRITICAL/HIGH/MEDIUM/LOW findings plus APPROVE/ITERATE. Apply every valid finding
or log a bounded disagreement with evidence. Continue until APPROVE or the latest
round contains no new material findings; preserve the full exchange in
`codex-review-phase1-build-review-log.md`.

After convergence, create a git worktree from `b25e9b3`. No Build 25 untracked or
dirty file is copied in. Write all red tests before implementation per workstream,
capture failing command/output, then implement and capture green evidence.

The orchestrator—not implementation workers—runs final build, selected XCTest,
both Node globs, rules emulator, `git diff --check`, forbidden-path reconciliation,
and a read-only adversarial final diff review. Apply the verified worktree diff to
main without committing. Recompute all preflight hashes; any Build 25 drift fails
closeout. Write root `PHASE1_BUILD.md` in PHASE0_BUILD format with the gate table
first, exact commands/counts/artifacts, review dispositions, state rows owed, and
production-unchanged label. Stop before commit and show only the Phase 1 diff stat
separate from the pre-existing WIP.

## Phase-wide do not change

Every Build 25 WIP path; PEEZY_STATE.md; PHASE1_PLAN.md; BUILD_BRIDGE.md;
`validateSubscription.js`; entitlement/StoreKit; support push payloads;
TaskFlowRouter shadows; catalog/flow JSON; Phase 0 report; research output;
scene-phase behavior; wallet/delegation. No seeds, deploys, packaging, or live
service operations.
