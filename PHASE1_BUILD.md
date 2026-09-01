# PHASE1_BUILD — Phase 1 local build report (2026-08-27)

## Audit gate (read-only at committed `b25e9b3`)

| Item | Disposition | Gate result |
|---|---|---|
| 1 — mapper | **SUPPORTED** | The additive optional map decodes through the one shared mapper. |
| 2 — status writers | **INVENTORY COMPLETE · SUPPORTED** | Every runtime writer is bound below; client writers preserve/omit the server-owned contract and server writers validate coherent status/contract pairs. |
| 3 — `snoozedUntil` readers | **INVENTORY COMPLETE · SUPPORTED** | Every reachable reader is bound below; missing means not snoozed and an atomic wake can clear the field. |
| 4 — spawn validation | **INVENTORY COMPLETE · SUPPORTED** | Every validation/identity touchpoint is bound below; omitted identity fields preserve byte-identical `t1_` behavior. |
| 5 — H51 | **SUPPORTED** | Only `financial_accounts` intersects `forEachRow` and the repository's sole `perSelectionFrom`. |
| 6 — rules | **SUPPORTED** | Explicit replacement rules plus the Admin Retake reset preserve reachable behavior while protecting server-owned state. |
| 7 — runtime | **SUPPORTED** | Node 24.19.0, `firebase-functions` 7.0.3, v2 `onSchedule`, Functions Test 3.4.1, Firebase CLI 15.6.0. |
| 8 — offline XCTest selection | **SUPPORTED** | The four exact unit classes exclude UI and Firestore/calibration/geocoding integration suites. |

No assertion was CONTRADICTED and no design assumption was contradicted. The
inventory findings expanded the executable surface as expected; the gate
continued.

### Item 2 — exhaustive task-status writer inventory

- `TaskGenerationService.swift:101-120,157-165` initial `Upcoming` full set;
  `:219-220,233-251,267` add-only incremental `Upcoming`.
- `TasksStore.swift:73-109,116-137` complete/undo through one `updateData`.
- `TaskActionService.swift:28-46,183-210` nudge transaction; `:215-220`
  generic unused setter; `:282-323` movers complete/booking/snooze;
  `:365-411` Home complete/InProgress/UserInProgress/snooze; `:604-617`
  supplies dismissal; `:674-741` readiness/packing completion;
  `:797-823,956-1043` packing/readiness replacement builders/writes; and
  `:828-846,1074-1103` merge-written supplies task.
- `MoversChainCoordinator.swift:102-116,245-275,300-317` supplies booking
  payload and delegates. `PeezyHomeViewModel.swift:672-780` and
  `FlowEngineView.swift:541-557` orchestrate shared writers only.
- `spawnTasks.js:239-269,302-339` creates `Upcoming`.
- `getWorkflowQualifying.js:176-186,210-237,267-280` writes Completed,
  pending, and matching_in_progress.
- `supportAdmin.js`, unexported diagnostics, test-profile seeders, previews,
  and tests are not runtime task-status writers.

### Item 3 — exhaustive reachable `snoozedUntil` reader inventory

`PeezyCardFirestoreMapper.swift:30-37,65-82` ·
`PeezyCard.swift:235-239,269-280` ·
`PeezyHomeViewModel.swift:366-389` ·
`TaskGrouping.swift:29-61,80-110` ·
`TaskRowHeader.swift:9-13,86-105` ·
`TaskActionService.swift:989-999,1035-1042`.

`PeezyStackViewModel.swift:128-154,523-537` is an additional but unreachable
reader per H4. No reachable reader treats a missing value as still snoozed, and
packing regeneration cannot copy the field after status becomes Upcoming.

### Item 4 — exhaustive spawn-validation/identity inventory

- `spawnTasks.js:15-73`: canonicalization, fingerprint, and `t1_` identity.
- `spawnTasks.js:98-181`: current request validation.
- `spawnTasks.js:136-154`: current institution boundary.
- `spawnTasks.js:302-308`: first database read.
- `spawnTasks.js:367-395`: auth/validation ordering.
- `FlowDefinition.swift:168-207`: row expansion rewrites provider to
  `{rowId}.provider`.
- `FlowEngineView.swift:690-709`: old exact lookup yielded zero;
  `:720-727` silently completed.
- `flowDefinitionsData.json:1080-1143`: `medical_records`,
  `financial_accounts`, and `memberships` use `forEachRow`; only
  `financial_accounts` has `perSelectionFrom`.

### Item 6 — bound client-write/read matrix

| Path | Baseline client evidence | Phase 1 binding |
|---|---|---|
| user root | `DailyDoseEngine.swift:30-51`; `BoxReturnService.swift:59-63` | retain protected-root rule |
| `fcmTokens` | `PeezyV1App.swift:93-102` | explicit owner CRUD |
| `identity` | `IdentityService.swift:23-48,70-97` | explicit owner CRUD |
| `inventory` | `InventorySessionManager.swift:31-45,540-649,679-723` | explicit owner CRUD |
| `inventorySessions` | `InventoryStorageService.swift:24-45,105-116` | explicit owner CRUD |
| `packingPlan` | `TaskActionService.swift:753-763,768-851,898-903` | explicit owner CRUD |
| `readiness` | `TaskActionService.swift:674-713,753-763,905-910` | explicit owner CRUD |
| `supportChat` | `SupportChatService.swift:137-149,206-220` | retain narrow rule |
| `tasks` | item-2 writers plus Settings/packing deletes | legacy owner CRUD; contracted/audited reset through Admin |
| `user_assessments` | `AssessmentDataManager.swift:267-299`; `InAppTaskFlows.swift:29-54`; Settings | explicit owner CRUD |

Server-owned surfaces retained explicit owner reads and denied client writes:
`moveAnswers` (`firestore.rules:73-77`), `packingAggregate`
(`SuppliesKitView.swift:401-405`), `research`
(`TaskResearchModule.swift:284-295`), `workflowResponses`
(`CheckInService.swift:59-64`; `TaskDetailView.swift:407-420`), and nested
`chats/{chatId}/messages` (`SupportChatView.swift:779-794`).

## Governing input and preflight

- `PEEZY_STATE.md` was read first and governed over `PHASE1_PLAN.md`.
- Baseline: `b25e9b3e066324af3bf3634f467dcea627cf6a0e` on `main`.
- Execution worktree: `/tmp/peezy-phase1.o5kB7P`, detached at that baseline.
- Node: `/opt/homebrew/opt/node@24/bin/node` (`v24.19.0`).
- Java: OpenJDK `21.0.12.1` at
  `/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`.
- Firebase CLI: `15.6.0`. Xcode: `26.6` (`17F113`).
- Simulator: iPhone 17 Pro,
  `DC0CC10C-6DB0-496A-8B0E-51E60D958A27` (iOS 26.5).
- The worktree-only `File.txt` placeholder was present only for Xcode's frozen
  resource reference and was deleted after the last test. The main checkout's
  untracked Build 25 `File.txt` was never touched.

### Protected Build 25 WIP baseline/closeout hashes

All remained byte-identical before and after applying the Phase 1 patch:

| Path | SHA-1 |
|---|---|
| `File.txt` | `09d342c86c096e6ab1c04fab6b749ec86ef3f370` |
| `PEEZY_STATE_REGEN_SPEC.md` | `2237d8cc3051c9bd62bd5a698ed89997f8bcef26` |
| `PHASE0_VERIFICATION.md` | `f4ac4b31d87aae1f6072fc2efe808d96d66daa18` |
| `PHASE1_PLAN.md` | `36b72e13f638d95bff57974bb89d4d42ef4363c8` |
| `Peezy 4.0.xcodeproj/project.pbxproj` | `d8bcd845e4e446275bae9cb4890afb2b1403b604` |
| `Peezy 4.0/MainInterface/Models/PeezyV1App.swift` | `645b1721a01c9b316b70dddc8eaec1f2feefc0ab` |
| `Peezy 4.0/Inventory/Models/InventorySessionManager.swift` | `b59610bfdecca53c897490bd6bf3f98fb4ff219e` |
| `Peezy 4.0/Inventory/Services/InventoryAPIClient.swift` | `68ad32d532eb23d85e0035d75625f4c0040a81f3` |
| `Peezy 4.0/Inventory/Services/NarrationService.swift` | `150a0cb8851296ce8e64b6cdef79232edc413f97` |
| `Peezy 4.0/Inventory/Views/InventoryCameraView.swift` | `4f474c8aba853e70df51b8e30d0b17cf6273e296` |
| `Peezy 4.0/Inventory/Views/InventoryFlowView.swift` | `9c8499e944ecb416a9a9f6c3a2f3d61fb46c6419` |
| `Peezy 4.0/Inventory/Views/InventoryScanCoachingView.swift` | `80491398c0ad883727e42f7c2f4658165faa87a5` |
| `Peezy 4.0/Inventory/Views/NarrationOfferCard.swift` | `772650c8ea32d184b67b5272a6cff29f2dfec3bf` |
| `functions/processInventory.js` | `2de24033c234ca3924e73147bc6a9b3765cf4c7d` |
| `functions/tests/processInventoryNarration.test.js` | `4b3a97874a95aecbf159c30b6e00a2e02cc05def` |
| `docs/plans/BUILD_BRIDGE.md` | `8adcb23d5b2e64e04cb6067d711d3c6b22d93fc0` |
| `docs/plans/files.zip` | `c1a1366a4f5efb1b7a8510ded58cc2dd2737bce9` |
| `docs/plans/files/DAYCARE_FLOW_SPEC_v3_LOCKED.md` | `5d0a7032e24b502add075192d0e8ea369e034024` |
| `docs/plans/files/INSTITUTION_FLOWS_MASTER_v3.md` | `4ce38762c4b97469f9909ddbe6cd34b4a1d80bc5` |

## Executable spec and review convergence

- Executable spec:
  `docs/plans/codex-review-phase1-build.md`.
- Approved revision: 6; SHA-256
  `f0780a9d4e1aff072c3f8ed3d9ef617a5108875774c58379c77f5d84ace012ac`.
- Spec review: five primary adversarial rounds, a revision-6 residual pass,
  and final APPROVE. A focused rules/event/amendment reviewer independently
  contributed nine round-1 findings.
- Execution diff review used separate Node and Swift reviewers. Every finding
  was fixed behind a red regression and the complete accumulated diff was
  re-reviewed. Both final verdicts were **APPROVE**.
- Execution-loop manifest addendum: `WorkflowService.swift` and
  `FlowProgressSession.swift` joined the client surface, and
  `getWorkflowQualifying.js` gained the durable workflow-submission boundary.
  The addendum and review rounds are recorded in
  `docs/plans/codex-review-phase1-build-review-log.md`.

## Implemented result

### W1 — dispositions and truthful task projection

- Added the recursive Firestore-safe value/trigger/disposition model and the
  single shared mapper path with additive legacy behavior.
- Added exact status/contract validation and complete server builders.
- Contracted Home/task rows are passive and use truthful visible copy;
  malformed contracts fail safe.
- Initial/incremental generation is add-only, reset-aware, transactional, and
  background-safe under Firebase's transaction queue.
- Packing/readiness replacement paths preserve contract data; server workflow
  mutations validate coherent pairs and reset state.

### W2 — subject-aware canonical task identity and H51

- Added per-spawn subject, canonical institution ID, and display label.
- Preserved exact `t1_` vectors for legacy callers; subject-aware callers use
  canonical `t2_` identity and exact provenance validation.
- Canonical `t2_` reuse returns the persisted task result, including the
  persisted due date, across changed invocation time/move inputs.
- Persisted row subject UUIDs and BusinessSearch identities survive reorder,
  rename, resume, and migration. H51 row-expanded financial providers now
  generate one subject-aware spawn per selection.

### W3 — supersession, amendment, undo, reopen, and Retake

- Added authenticated `changeTaskPlan` actions with operation fingerprints,
  immutable history, pending external amendment, confirmation, bounded undo,
  reopen cycles, collision validation, and exact evidence-bearing contracts.
- Added strict Swift payload/response validation and the Retake coordinator.
- Retake reset is leased, paged, crash-resumable, uniquely checkpointed,
  stale-worker safe, reset-marker protected, and locally resumable.

### W4 — scheduled date/event trigger evaluator

- Added the sole scheduled subsystem/export with fixed runtime metadata.
- Added run leases, bounded work, date/event/task cursors, poison-row progress,
  canonical event fingerprints, per-key high-water ordering, retraction/stale/
  conflict behavior, and same-run reconciliation.
- Added exact Firestore index/config declarations.

### W5 — explicit Firestore rules

- Removed reliance on the recursive owner grant for server-owned surfaces.
- Preserved every inventoried owner CRUD/read path.
- Contracted tasks and all `a2_` tasks are client immutable; legacy task
  lifecycle remains available only when contract/audit/provenance rules allow.
- Reserved task creates, plan/audit mutation, reset state, events, scheduler
  state, and server result surfaces are denied to clients as specified.

### Execution-loop durability addendum

- Vendor workflow submissions accept an optional bounded idempotency token.
  Authenticated UID + token select one deterministic Admin document; canonical
  payload fingerprints distinguish exact replay from drift. Concurrent/fresh
  callers return the stored result; drift fails with zero writes; tokenless
  legacy calls still use the true zero-argument Firestore auto-ID API.
- Each flow lifecycle persists a `flowAttemptId`. A pre-submit barrier locks
  exit/mutation, drains queued progress, and proves that exact attempt ID is
  durable before the callable. A terminal barrier then rejects/drains writes
  before clearing. Cleanup retry and process recreation cannot duplicate the
  submission; Retake/regeneration receives a new attempt.

## Red-first evidence

Representative Swift RED bundles (all used Debug, the named unit selector(s),
the UI skip, signing disabled, and no test plan/integration environment):

- W1 contract/legacy bytes: `/tmp/peezy-phase1-final-w1-byte-red.xcresult`.
- W1 transaction queue isolation: `/tmp/peezy-phase1-final2-w1-background-red.xcresult`.
- W2/W3 adversarial fixtures: `/tmp/peezy-phase1-final-adversarial-red.xcresult`,
  `/tmp/peezy-phase1-final2-w3-red.xcresult`.
- Durable submit/token and terminal barrier:
  `/tmp/peezy-phase1-final3-red.xcresult`.
- Flow attempt lifecycle/canonical arrays/mutation gate:
  `/tmp/peezy-phase1-final4-red.xcresult`.
- Required pre-submit persistence ordering:
  `/tmp/peezy-phase1-final5-red.xcresult`.

Node REDs covered absent contract/task-plan/scheduler modules, malformed raw
trigger acceptance, amendment/reopen/reset boundary gaps, `t2_` persisted-result
drift, non-idempotent workflow submissions, and explicit `doc(undefined)`.
Rules RED began at 9 failures / 4 passes before the explicit rule set.

Final workstream GREEN envelopes:

| Workstream | Result |
|---|---|
| Swift W1 — `DispositionContractTests` + `TaskGroupingTests` | 20/20 |
| Swift W2 — `ConversationFlowTests` | 25/25 |
| Swift W3 — `TaskSupersessionTests` | 6/6 |
| Node W1 | 17/17 |
| Node W2 | 68/68 |
| Node W3 | 24/24 |
| Node scheduler | 22/22 |

## Final verification

### Simulator build

Fresh accepted-tree command:

```sh
xcodebuild build -project 'Peezy 4.0.xcodeproj' -scheme 'Peezy 4.0' \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=DC0CC10C-6DB0-496A-8B0E-51E60D958A27' \
  CODE_SIGNING_ALLOWED=NO
```

Result: **BUILD SUCCEEDED**. The existing Crashlytics no-output warning and
AppIntents “no dependency” notice were unchanged.

### Exact simulator unit-test envelope

```sh
xcodebuild test -project 'Peezy 4.0.xcodeproj' -scheme 'Peezy 4.0' \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=DC0CC10C-6DB0-496A-8B0E-51E60D958A27' \
  -only-testing:'Peezy 4.0Tests/ConversationFlowTests' \
  -only-testing:'Peezy 4.0Tests/DispositionContractTests' \
  -only-testing:'Peezy 4.0Tests/TaskGroupingTests' \
  -only-testing:'Peezy 4.0Tests/TaskSupersessionTests' \
  -skip-testing:'Peezy 4.0UITests' \
  -resultBundlePath '/tmp/peezy-phase1-final-approved-01a04168.xcresult' \
  CODE_SIGNING_ALLOWED=NO
```

Result: **TEST SUCCEEDED**. Recursive `xcresulttool` verification found exactly
the four expected suites, 51 passed leaves, no failures/skips, and no UI or
integration class:

- `ConversationFlowTests`: 25
- `DispositionContractTests`: 14
- `TaskGroupingTests`: 6
- `TaskSupersessionTests`: 6

The full leaf roster is preserved in the xcresult. It includes the durable
attempt pre-submit delay/failure cases, terminal queued-write drain, submission
recreation/idempotency, canonical Set payload, FindCleaners mutation lock,
off-main Firestore transaction body, legacy byte snapshot, exact supersession
evidence maps, and strict response-schema cases.

The hosted app's DEBUG XCTest guard remains byte-identical to the Phase 0
baseline (`PeezyV1App.swift` SHA-1
`645b1721a01c9b316b70dddc8eaec1f2feefc0ab`). No default test plan and no
integration opt-in environment were used.

### Offline Node and rules suites

```sh
/opt/homebrew/opt/node@24/bin/node --test functions/tests/*.test.js
/opt/homebrew/opt/node@24/bin/node --test functions/*.test.js
```

Results: **208/208** and **10/10**.

Rules ran once more from the accepted tree with credentials/config removed,
telemetry/update checks disabled, local OpenJDK 21, and project
`demo-peezy-phase1`:

```sh
firebase emulators:exec --only firestore --project demo-peezy-phase1 \
  "/opt/homebrew/opt/node@24/bin/node --test functions/rules-tests/firestoreRules.test.js"
```

Result: **14/14**; emulator script exit 0. No non-emulated service was available
under the demo project.

### Static/shape checks

- `git diff --check`: clean for the complete isolated Phase 1 patch.
- `node --check`: passed for `index.js`, `spawnTasks.js`,
  `dispositionContract.js`, `taskPlan.js`, `dispositionTriggers.js`, and
  `getWorkflowQualifying.js`.
- `functions/index.js` loads offline with 24 exports: 20 callables, 2 HTTP,
  1 Firestore trigger, and 1 scheduler.
- `project.pbxproj` and `PeezyV1App.swift` have no Phase 1 diff.
- All 45 implementation paths in the main checkout hash-match the accepted
  isolated worktree patch.

## Production and regeneration status

- No seed, deploy, Functions packaging, production-connected test, production
  Firestore/Storage write, StoreKit action, or integration opt-in occurred.
- Production is unchanged. H43 continues to block packaging/deployment.
- `PEEZY_STATE.md` was not regenerated in this code session. A full-evidence
  regeneration is owed for at least H19 (20 callable + 2 HTTP + 1 Firestore +
  1 scheduler), H21/rules, H41d/index configuration, H51, and the local
  disposition/supersession/trigger implementation rows.

## Commit gate

No commit was created. The accepted Phase 1 implementation has been applied to
the main checkout without staging or altering the protected Build 25 WIP.

Phase 1 implementation-only diff stat:

```text
45 files changed, 9224 insertions(+), 591 deletions(-)
```

Session documentation adds this report plus the approved executable spec and
review log. The complete Phase 1 change, including those three documents, is:

```text
48 files changed, 11148 insertions(+), 591 deletions(-)
```

Stop here for human diff review and commit authorization.
