# Plan Review Log: Movers three-task spawn chain + expert review button

MAX_ROUNDS=3, BUDGET=6 chain rounds, strict=false, reviewer model=gpt-5.6-sol, codex-cli 0.147.0.

Plan under review: docs/plans/codex-review-movers-spawn-chain.md

## Round 1 — Codex (VERDICT: ITERATE)

1. [CRITICAL] `onCompleteSpawns` is metadata without an execution path. Normal generation does not copy it, the mapper only decodes it, and every completion path merely updates status ([TaskGenerationService.swift:101](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Assessment/AssessmentModels/TaskGenerationService.swift:101>), [PeezyHomeViewModel.swift:453](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift:453>)). Steelman: a centralized completion coordinator would reduce duplication and activate existing RENT_TRUCK metadata, but it would alter every completion surface and violate this plan’s “no changes to other flows” constraint.  
Fix: Lock the plan to flow-local `SpawnService` calls using `source.kind = "onComplete"`, the user-task document ID as `source.id`, a stable per-edge token, and await spawn success before calling `onComplete`.

2. [HIGH] The callable’s claimed idempotency is race-prone: two concurrent calls can both read a missing token before either batch commits, creating duplicate random-ID tasks ([spawnTasks.js:154](</Users/adampowell/Desktop/Peezy 4.0/functions/spawnTasks.js:154>)).  
Fix: Transactionally claim the token and create successors, and add a concurrent same-token test proving exactly one task is created.

3. [HIGH] `spawn+3d` is the correct COMPARE date rule because it preserves the current `.inProgress` three-day return behavior, but `resolveDueDate` currently understands only `moveDate` anchors ([spawnTasks.js:81](</Users/adampowell/Desktop/Peezy 4.0/functions/spawnTasks.js:81>), [PeezyHomeViewModel.swift:500](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift:500>)). Per-spawn rules inside `onCompleteSpawns` are not sent to the callable; only the target catalog row’s rule matters.  
Fix: Put `{"anchor":"spawn","offsetDays":3}` on COMPARE_MOVING_QUOTES, add that anchor to `resolveDueDate`, test UTC boundary/missing-move-date cases, and deploy the backward-compatible callable before catalog rollout.

4. [CRITICAL] Migration is not sufficiently defined. Because `setStage` and quote persistence swallow errors, a legacy document can contain quotes without `.compare`/`.verify`; checking stage alone can strand those quotes ([MoversFlowViewModel.swift:148](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/MoversFlowViewModel.swift:148>), [TaskActionService.swift:107](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/TaskActionService.swift:107>)).  
Fix: Treat BOOK_MOVERS as legacy-inline when stage is compare/verify **or quotes are nonempty;** resume quotes/matrix in place, then spawn only BOOK_YOUR_MOVERS, while state-free BOOK_MOVERS documents use the new chain.

5. [HIGH] BOOK_YOUR_MOVERS cannot prefill company chips under the stated persistence design. Spawned task documents use random IDs and only retain the predecessor through `spawnedFrom.id`; the quotes remain on the predecessor document ([spawnTasks.js:175](</Users/adampowell/Desktop/Peezy 4.0/functions/spawnTasks.js:175>)).  
Fix: Specify that BOOK_YOUR_MOVERS loads its own `spawnedFrom.id`, fetches that completed predecessor task, and derives deduplicated company chips from its quotes, including legacy BOOK_MOVERS predecessors.

6. [HIGH] Routing is left undecided even though tiny flow definitions cannot supply the existing quote editor/matrix or the proposed conditional booking form. The router currently recognizes only `book_movers`, and the seeder’s Swift-custom allowlist lacks both new IDs ([TaskFlowRouter.swift:43](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/TaskFlowRouter.swift:43>), [seedTaskCatalog.js:268](</Users/adampowell/Desktop/Peezy 4.0/functions/seedTaskCatalog.js:268>)).  
Fix: Use one role-driven custom movers container/view model for all three IDs, add explicit router cases and seeder allowlist entries, and do not add unnecessary flow definitions.

7. [HIGH] Persistence failures currently look successful: quote saves, notes, and stage writes log and return, while UI advances or closes; `MoversFlowViewModel.complete()` even writes `.complete` before the successor is known to exist ([MoversFlowViewModel.swift:114](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/MoversFlowViewModel.swift:114>)).  
Fix: Add throwing persistence methods for this flow and advance, dismiss, or spawn only after writes succeed, with visible retry state on failure.

8. [CRITICAL] The production rollout is unsafe and unsequenced. `seedTaskCatalog.js` deletes the entire catalog, rewrites it, then wipes and reseeds every flow definition; the plan provides no backup, dry run, rollback, or remote verification ([seedTaskCatalog.js:47](</Users/adampowell/Desktop/Peezy 4.0/functions/seedTaskCatalog.js:47>), [seedTaskCatalog.js:252](</Users/adampowell/Desktop/Peezy 4.0/functions/seedTaskCatalog.js:252>)).  
Fix: Use a targeted guarded upsert for the two new rows plus BOOK_MOVERS, export affected documents first, verify exact remote fields/counts, and sequence callable → catalog → client with a documented rollback.

9. [HIGH] `SupportChatService.sendMessage` returns “was first user message,” not send success; therefore a successful later expert request returns `false` ([SupportChatService.swift:85](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/SupportChatService.swift:85>)).  
Fix: Return a structured result containing `sent` and `wasFirstUserMessage`, present the thread only after the Firestore write succeeds, and retain the matrix with an actionable error on failure.

10. [MEDIUM] The expert-review action has no duplicate-send or cost mitigation even though each success invokes a Cloud Function and support notification; rapid taps can create duplicate messages and admin alerts. The required message’s “rate” is also ambiguous because storage is per-man while the UI collects crew-total hourly rate ([QuoteTrackerView.swift:40](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Tasks/Views/QuoteTrackerView.swift:40>)).  
Fix: Disable during submission and after success, report crew-total hourly rate (`perManRate × crew`), man-hours (`crew × hours`), travel fee, and Peezy man-hours through a deterministic formatter covered by exact-output tests.

11. [HIGH] BOOK_YOUR_MOVERS lacks a durable schema and failure contract. If every optional field is blank, “yes” currently has no specified persisted fact; move-date representation and whether hourly rate means crew-total or per-man are undefined.  
Fix: Define a `bookingDetails` map with required `booked: true` and `savedAt`, optional company, Timestamp moveDate, arrivalWindow, NSNumber crewSize, and `crewHourlyRate`, and complete only after the write succeeds; “later” must use the existing three-day snooze without writing booked state.

12. [HIGH] The verification section tests almost none of the new behavior: JSON syntax, compilation, and unchanged math do not cover spawning, migration, handoff, booking, support delivery, accessibility, or deployment ([plan:61](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-movers-spawn-chain.md:61>)).  
Fix: Add Given/When/Then acceptance tests for both spawn edges and replay, spawn+3 due dates, every legacy-state fixture, predecessor quote handoff, booking round-trip/snooze, exact expert text/taskContext, failure retry, free-user no-paywall behavior, and all new accessibility identifiers.

13. [MEDIUM] Successor visibility is unspecified. TasksStore will see spawned documents via its listener, but Home is one-shot and its daily dose is frozen, so the next task will not reliably appear in the current Home session.  
Fix: State explicitly that spawned successors appear immediately in Tasks but do not enter the already-frozen Home dose, and test that behavior so it is not mistaken for a failed spawn.

VERDICT: ITERATE
### Response (round 1)

Accepted with concrete plan changes: 1 (direct SpawnService, stable per-edge token,
spawn-before-complete), 3 (spawn+3d anchor added additively to resolveDueDate; rollout
sequencing documented), 4 (legacy-inline = stage compare/verify OR nonempty quotes;
legacy completion spawns only BOOK_YOUR_MOVERS), 5 (spawnedFrom.id predecessor fetch for
chips), 6 (no flow defs; router cases + seeder allowlist; one role-driven container),
7 (throwing persistence scoped to this flow), 9 (structured sendMessage result), 10
(deterministic formatter + exact-output tests, crew-total rate, disable-during/after
send), 11 (bookingDetails schema with required booked+savedAt), 12 (unit tests for pure
seams + explicit manual-QA list), 13 (successor visibility documented + copy points to
Tasks tab).

Rejected with rationale (see plan "Reviewer pushback"): 2 (transactional token claim —
pre-existing shared behavior, out of scope per "no changes to other flows' spawn
behavior"; UI serializes; follow-up candidate), 8-partial (upsert seeder — full reseed
is the established mechanism; sequencing/verification substance accepted), 12-partial
(no pretend-automation for live backend edges; manual QA listed instead).

## Round 2 — Codex (VERDICT: ITERATE)

The revision materially addresses prior findings 1, 3–7, 9–11, and 13. I accept the finding-2 pushback as a bounded residual risk, and I accept manual QA for genuinely live-only edges. I no longer insist on an upsert seeder, but the full-reseed path still needs safeguards below.

1. [CRITICAL] The role cannot be derived from the passed `taskId`: for spawned tasks that value is the random user-task document ID, not `COMPARE_MOVING_QUOTES` or `BOOK_YOUR_MOVERS` ([TaskFlowRouter.swift:64](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/TaskFlowRouter.swift:64>), [spawnTasks.js:175](</Users/adampowell/Desktop/Peezy 4.0/functions/spawnTasks.js:175>)).  
Fix: Have each router case pass an explicit `MoversFlowRole` derived from `flowId`, while keeping `taskDocumentId` separate for persistence.

2. [CRITICAL] Rollout expects 49 catalog rows, but the current JSON already contains 61; adding two produces 63, potentially deploying unrelated catalog changes if production differs. The full seeder also rewrites 35 flow definitions, not just the catalog.  
Fix: Replace the hardcoded count with the post-change JSON-derived count, perform a read-only remote diff before reseeding, and verify both catalog and flow-definition collections after the run.

3. [HIGH] “Spawn then complete” is still not operationally defined. The existing synchronous `onComplete` callback starts a detached, error-swallowing completion write and immediately removes the task locally ([PeezyHomeViewModel.swift:453](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift:453>)).  
Fix: Specify a movers-only throwing completion write awaited after spawn; only after it succeeds invoke the existing callback for UI/analytics, documenting its duplicate completion write as intentionally idempotent.

4. [HIGH] A3 says the existing snooze mechanism is three days, but `.later` currently snoozes for two days ([PeezyHomeViewModel.swift:515](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift:515>)).  
Fix: Either state and test the existing two-day behavior or define a movers-specific throwing three-day snooze path without routing through `.later`.

5. [HIGH] The finding-12 pushback is valid only for live edges; the plan still omits tests for the pure backend function it directly changes. Two existing Node suites already test `resolveDueDate`, yet verification runs only `node --check`.  
Fix: Add spawn-anchor cases to the existing `spawnTasks` tests and run both Node suites, covering offsets 3 and 1, missing move date, non-midnight `now`, and unchanged moveDate behavior.

6. [HIGH] The accepted full-reseed rationale does not address failure between the delete and rewrite commits, or the unrequested flow-definition rewrite performed by the same script ([seedTaskCatalog.js:47](</Users/adampowell/Desktop/Peezy 4.0/functions/seedTaskCatalog.js:47>), [seedTaskCatalog.js:242](</Users/adampowell/Desktop/Peezy 4.0/functions/seedTaskCatalog.js:242>)).  
Fix: Keep the established seeder, but add preflight tests, remote exports, a maintenance-window instruction, explicit recovery after partial failure, and post-run verification of all affected collections.

7. [HIGH] `sent` still risks meaning only “message document persisted.” `submitSupportMessage` remains detached behind `try?`, while that callable is what updates `supportThreads`; a new expert request can show a success bubble yet never enter the admin inbox ([SupportChatService.swift:105](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/SupportChatService.swift:105>), [index.js:168](</Users/adampowell/Desktop/Peezy 4.0/functions/index.js:168>)).  
Fix: Return separate persisted/admin-queued states, await the callable, and provide a same-message notification retry that does not create another support bubble.

8. [MEDIUM] A6’s “convert to throwing persistence” could unintentionally change other flows because `setStage` and `updateQuotes` are shared APIs.  
Fix: Add movers-specific throwing entry points—or a shared throwing core retained behind the existing catch-and-log wrappers—so current callers keep identical behavior.

9. [MEDIUM] The two catalog deliverables remain underspecified: required workflow IDs, action types, categories, descriptions, estimates, and other row fields are not enumerated or tested.  
Fix: Define the complete JSON contract for both rows and add a static test for unique IDs, `spawnedOnly`, workflow routing IDs, required metadata, and exact date rules.

10. [MEDIUM] The promised “Your next step is waiting in Tasks” copy has no specified surface; successful `onComplete` dismisses the full-screen flow immediately.  
Fix: Name the concrete surface—such as a toast or pre-dismiss confirmation—and add a manual assertion that the copy appears after successful spawn.

11. [LOW] The ADR’s follow-up list conflicts with the repository rule that `LAUNCH_CHECKLIST.md` is the sole open-item ledger.  
Fix: Record the accepted concurrency and dormant-metadata follow-ups in `LAUNCH_CHECKLIST.md` and remove the duplicate open-item list from the ADR.

VERDICT: ITERATE
### Response (round 2)

All 11 findings accepted, no pushback this round:
1 (explicit MoversFlowRole from flowId, taskDocumentId separate), 2 (JSON-derived row
count — 61 today, not 47/49; read-only remote diff + both collections verified),
3 (movers-only throwing completion write awaited after spawn; existing onComplete
callback invoked after, duplicate write documented idempotent), 4 (snooze corrected to
existing two-day behavior, stated and tested as such), 5 (spawn-anchor cases added to
existing Node suites; both suites run), 6 (preflight exports of both collections,
low-traffic window, re-run-as-repair recovery, post-run verification), 7 (structured
result with separate persisted/adminQueued; callable awaited; callable-only retry with
no duplicate bubble), 8 (throwing core behind existing catch-and-log wrappers — other
callers byte-identical), 9 (full catalog row contract enumerated + static Node test),
10 (confirmation state on final screen with Done button, no auto-dismiss), 11
(follow-ups recorded in LAUNCH_CHECKLIST.md, removed from ADR as open-item list).

Plan revised to v3.

## Round 3 — Codex (VERDICT: ITERATE) — round cap reached

v3 correctly resolves most round-2 findings, including explicit role routing, derived catalog counts, two-day snoozing, Node coverage, reseed safeguards, scoped throwing writes, and the canonical follow-up ledger. I also accept the full-reseed and live-manual-QA pushbacks. The following remain.

### Blocking findings

1. [HIGH] Support retry is not idempotent. `submitSupportMessage` ignores `messageId`, increments `unreadForAdmin` on every invocation, and starts another notification; an ambiguous timeout followed by retry can duplicate admin effects even if the bubble is reused ([index.js:168](</Users/adampowell/Desktop/Peezy 4.0/functions/index.js:168>), [plan:134](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-movers-spawn-chain.md:134>)). The result also lacks the message ID needed for the promised targeted retry, and “disable after successful send” could permit a second bubble when persistence succeeded but queuing failed.  
Fix: Authorize an additive `submitSupportMessage` change that transactionally claims `uid+messageId`, increments/notifies only on the first claim, return the message ID/pending-delivery token, disable the expert button once `persisted == true`, and deploy/test this callable before the client.

2. [HIGH] The confirmation lifecycle is incompatible with the existing completion callback. `onComplete` immediately hides the flow, while its “idempotent” duplicate write also rewrites `completedAt`; delaying it until confirmation Done can move the completion timestamp by minutes or hours ([PeezyHomeViewModel.swift:453](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift:453>), [TaskActionService.swift:118](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/TaskActionService.swift:118>), [plan:27](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-movers-spawn-chain.md:27>)). The outer X remains active during requests and confirmation, allowing dismiss/reopen and undermining the reviewer-pushback claim that button disabling serializes spawn calls ([FlowExitControl.swift:249](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Tasks/FlowEngine/FlowExitControl.swift:249>)).  
Fix: Add a movers-specific “completion already persisted” callback that performs only local state/analytics, invoke it from confirmation Done, and lock or terminal-route the outer exit while an edge is in flight or durably complete.

3. [HIGH] Both BOOK_YOUR_MOVERS terminal branches still violate A6’s durability rule. “Yes” awaits only `bookingDetails`, not durable completion; “Not yet” delegates to `.later`, whose current write is detached and failure-swallowing while the UI dismisses immediately ([plan:55](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-movers-spawn-chain.md:55>), [PeezyHomeViewModel.swift:515](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift:515>)).  
Fix: Make “Yes” one awaited atomic update containing `bookingDetails`, `status`, and `completedAt`, and make “Not yet” await a throwing two-day snooze before invoking non-writing local callbacks.

4. [HIGH] The catalog contract remains internally wrong and incomplete. A4 names the key `id`, but the JSON and seeder require `taskId`; it also specifies only two new rows without explicitly changing BOOK_MOVERS’s catalog title from “Book your movers” to “Get Moving Quotes” ([plan:83](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-movers-spawn-chain.md:83>), [seedTaskCatalog.js:96](</Users/adampowell/Desktop/Peezy 4.0/functions/seedTaskCatalog.js:96>)).  
Fix: Replace `id` with `taskId`, explicitly update BOOK_MOVERS’s title/description, and statically assert the IDs and exact user-visible titles of all three rows.

5. [HIGH] The stated rollback is incompatible after phase 3. Reseeding the prior catalog while v3 clients remain installed removes the successor rows, causing their spawn calls to fail `not-found`; the callable is not merely “inert” ([plan:178](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-movers-spawn-chain.md:178>), [spawnTasks.js:174](</Users/adampowell/Desktop/Peezy 4.0/functions/spawnTasks.js:174>)).  
Fix: Split rollback by phase—before client release, restore the old catalog; after release, retain the successor rows until the client is rolled back or superseded.

6. [HIGH] The critical orchestration still has no deterministic acceptance coverage. The listed tests cover helpers, but not spawn→completion ordering, exact token reuse, failure/retry behavior, callback suppression, role/document-ID separation, persisted-completion finalization, or support retry semantics ([plan:186](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-movers-spawn-chain.md:186>)). These are pure client seams, so the live-harness pushback does not apply.  
Fix: Steelman a small protocol-injected, flow-local `MoversChainCoordinator`—not the rejected app-wide coordinator—and unit-test ordered calls, every failure boundary, stable retry tokens, exit/double-tap suppression, all three roles with random document IDs, and support delivery states.

### Nice-to-haves

7. [MEDIUM] “Spawn time + offset” remains ambiguous about retaining the instant versus UTC-midnight normalization; the non-midnight/UTC tests name cases but give no expected timestamp, while UTC midnight can display as the prior local date ([spawnTasks.js:74](</Users/adampowell/Desktop/Peezy 4.0/functions/spawnTasks.js:74>), [TaskRowHeader.swift:76](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Tasks/Views/TaskRowHeader.swift:76>)).  
Fix: State exact ISO expectations for non-midnight and DST-boundary inputs, preferably preserving the spawn instant plus whole-day offsets.

8. [MEDIUM] “Free—no paywall” still lacks an acceptance check despite being an explicit deliverable.  
Fix: Add manual QA that an unsubscribed user can open the matrix, submit expert review, retry pending delivery, and reach the support thread without any paywall.

VERDICT: ITERATE
### Response (round 3)

User authorized one extra round (round 4) and resolved finding 1's scope question:
CLIENT-ONLY — no submitSupportMessage modification, no backend deploy beyond spawnTasks.

Accepted: 2 (movers-specific completion-persisted callback, completedAt written once by
the throwing completion write, outer X locked in flight / terminal-routed after), 3
("Yes" = one atomic update {bookingDetails, status, completedAt}; "Not yet" = awaited
throwing two-day snooze), 4 (taskId key; explicit BOOK_MOVERS retitle to "Get Moving
Quotes"; static test asserts all three rows' taskIds + exact titles), 5 (phase-split
rollback — successor rows retained after client release), 6 (flow-local
protocol-injected MoversChainCoordinator + full orchestration unit tests), 7 (spawn
instant + whole-day offsets, exact ISO test expectations, DST-immune UTC arithmetic),
8 (unsubscribed-user end-to-end manual QA item).

Finding 1 resolved by user decision, not rejection of the analysis: the analysis is
accepted (callable is non-idempotent; targeted retry can duplicate admin effects), so
the targeted retry is REMOVED rather than made safe via backend change. persisted &&
!adminQueued shows "Delivery pending — support will follow up" with no retry; expert
button disables permanently once persisted; callable idempotency recorded as a
LAUNCH_CHECKLIST.md follow-up.

Plan revised to v4. Round 4 authorized by user (chain rounds spent after it: 4 of 6).

## Round 4 — Codex (VERDICT: ITERATE) — user-granted extra round exhausted

v4 resolves the rollout, testing, date semantics, catalog-key, snooze, and client-only support-scope findings. Three blockers remain.

### Blocking findings

1. [HIGH] The BOOK_MOVERS retitle only changes the catalog; existing user task documents retain their denormalized old title and description. Task generation copies these fields into each user document, and the UI reads that copy—not the catalog ([TaskGenerationService.swift:101](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Assessment/AssessmentModels/TaskGenerationService.swift:101>), [PeezyCardFirestoreMapper.swift:65](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Tasks/Store/PeezyCardFirestoreMapper.swift:65>)). Therefore A5’s state-free mid-flight users enter the new get-quotes flow from a card still titled “Book your movers.”  
Fix: Add an awaited user-task migration—state-free BOOK_MOVERS → “Get Moving Quotes,” legacy-inline → an explicitly chosen legacy title such as “Compare your moving quotes”—with tests for both branches and quote preservation.

2. [HIGH] A3 specifies `status: complete`, but the task status contract is exactly `"Completed"`; an unknown lowercase value decodes as `.upcoming`, leaving a successfully booked task visually active ([plan:80](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-movers-spawn-chain.md:80>), [PeezyCard.swift:20](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/PeezyCard.swift:20>), [PeezyCardFirestoreMapper.swift:15](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Tasks/Store/PeezyCardFirestoreMapper.swift:15>)).  
Fix: Specify and test the exact atomic payload `"status": "Completed"` plus `completedAt` and `bookingDetails`.

3. [HIGH] The completion handshake is still not operationally closed. v4 requires the local completion callback immediately after persistence, then separately says confirmation Done dismisses; current Home callbacks either dismiss immediately or requeue on dismissal, and no two-phase API exists ([plan:29](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-movers-spawn-chain.md:29>), [PeezyHomeViewModel.swift:453](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift:453>)). The required-reading list also omits the load-bearing files this change necessarily touches: `PeezyHomeViewModel.swift`, `PeezyHomeView.swift`, and `FlowExitControl.swift`.  
Fix: After durable completion, show confirmation without invoking Home; confirmation Done calls one `completeTaskFlowAlreadyPersisted()` method that records local completion and dismisses without writing, while X remains disabled, and add those three files plus an end-to-end state-transition unit test.

### Nice-to-haves

4. [MEDIUM] The client-only no-retry decision is coherent, but “Delivery pending — support will follow up” overpromises: `adminQueued == false` means there is no confirmed `supportThreads` update and no background retry ([plan:168](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-movers-spawn-chain.md:168>), [index.js:191](</Users/adampowell/Desktop/Peezy 4.0/functions/index.js:191>)).  
Fix: Use honest copy such as “Saved in Chat, but we couldn’t confirm delivery. Send a new Chat message to alert support.”

5. [MEDIUM] A2 does not explicitly order the notes write before spawning, although current Done persists notes and blur starts a second unstructured save; the coordinator tests cover spawn/completion failures but not notes failure ([MoversScenarioMatrixView.swift:75](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Tasks/Task Cards/MoversScenarioMatrixView.swift:75>), [MoversFlowViewModel.swift:139](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/MoversFlowViewModel.swift:139>)).  
Fix: Define A2 Done as `await persistNotesThrowing` before coordinator execution, serialize/remove the competing blur save, and test that notes failure prevents spawning.

6. [LOW] The plan adds substantial Swift unit coverage but verification names only an `xcodebuild` build, which does not execute tests.  
Fix: Add an explicit simulator `xcodebuild test` requirement covering the app’s unit-test target.

VERDICT: ITERATE
### Response (round 4)

User authorized round 5 as the closing re-review. All 6 findings accepted:
1 (awaited one-shot client title migration at task load via TaskActionService — never
the shared mapper; state-free → "Get Moving Quotes", legacy-inline → "Compare your
moving quotes"; tests for both branches + quote preservation), 2 (exact payload
"status": "Completed" + completedAt + bookingDetails, unit-tested), 3 (two-phase
handshake: confirmation without Home invocation; Done → completeTaskFlowAlreadyPersisted()
local-only; X locked through confirmation; three load-bearing files added to required
reading; state-transition unit test), 4 (honest copy: "Saved in Chat, but we couldn't
confirm delivery. Send a new Chat message to alert support."), 5 (A2 Done awaits
persistNotesThrowing before coordinator; blur-save removed/serialized; notes-failure-
prevents-spawn test), 6 (xcodebuild test added to verification).

Plan revised to v5. Round 5 authorized by user (chain rounds spent after it: 5 of 6).

## Round 5 — Codex (VERDICT: ITERATE)

v5 still has two blocking inconsistencies. The direct `SpawnService` choice remains justified: `onCompleteSpawns` would be more declarative, but initial generation does not copy it and no completion executor consumes it.

1. [HIGH] The completion handshake contradicts itself. The plan first invokes a local-removal/analytics callback immediately after persistence ([plan:36](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-movers-spawn-chain.md:36>)), then requires no Home callback until confirmation Done ([plan:41](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-movers-spawn-chain.md:41>)); current local removal also dismisses the cover ([PeezyHomeViewModel.swift:453](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift:453>)), so the first sequence skips confirmation or causes double accounting.  
   Fix: Remove the pre-confirmation callback from A1 and coordinator tests; persistence should only set confirmation state, and Done alone should call `completeTaskFlowAlreadyPersisted()`.

2. [HIGH] Expert-send suppression is only “for the session” ([plan:213](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-movers-spawn-chain.md:213>)); dismissing and reopening the task resets view state and permits another bubble and another non-idempotent callable invocation, which increments unread and triggers notification work ([index.js:168](</Users/adampowell/Desktop/Peezy 4.0/functions/index.js:168>)). This does not require retrying or modifying the callable—the accepted client-only rationale still stands.  
   Fix: Derive a durable per-task “already sent” state from the persisted support message or an atomic client-owned marker, and test dismiss→reopen→button remains disabled with no second send.

3. [MEDIUM] The title migration names `description` in its payload and test, but the stored/read field is `desc` ([TaskGenerationService.swift:105](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Assessment/AssessmentModels/TaskGenerationService.swift:105>), [PeezyCardFirestoreMapper.swift:71](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Tasks/Store/PeezyCardFirestoreMapper.swift:71>)); its failure behavior is also unspecified for a cosmetic awaited migration.  
   Fix: Assert exact keys `title` and `desc`, keep migration failure nonblocking, and mark the session guard only after success.

4. [MEDIUM] Exit locking lacks an integration seam: the outer X currently depends only on `FlowExitCoordinator.isReadyForExit` and cannot observe mover in-flight/confirmation state ([FlowExitControl.swift:219](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Tasks/FlowEngine/FlowExitControl.swift:219>)). Coordinator-only suppression tests would not prove the actual X is disabled.  
   Fix: Specify an `isExitLocked` binding/environment contract into `OutermostTaskFlowContainer` and test its in-flight, failure, and confirmation transitions.

5. [MEDIUM] Legacy detection omits `.complete`, although the old flow writes that stage before Home launches its detached, failure-swallowing status completion ([MoversFlowViewModel.swift:139](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/MoversFlowViewModel.swift:139>), [PeezyHomeViewModel.swift:459](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift:459>)). An active residue with `stage == .complete` and failed quote persistence is misclassified as state-free.  
   Fix: Define `.complete` as an explicit legacy-terminal residue and add a migration/resume test for it.

6. [MEDIUM] A6 promises throwing quote and stage persistence with visible retries, but acceptance tests cover notes and terminal writes only.  
   Fix: Add tests proving failed quote add/edit/delete and stage writes preserve retryable UI state and never advance.

VERDICT: ITERATE
### Response (round 5)

User authorized round 6 (final budgeted round). All 6 findings accepted:
1 (contradiction removed — persistence yields ONLY confirmation state, zero callbacks;
Done alone calls completeTaskFlowAlreadyPersisted(); coordinator tests updated to
match), 2 (durable per-task already-sent state derived from the persisted expert
message — atomic client-owned task-doc marker as fallback; dismiss→reopen test; still
no callable change), 3 (exact keys title + desc; nonblocking failure; session guard set
only on success), 4 (explicit isExitLocked binding/environment contract into
OutermostTaskFlowContainer with in-flight/failure/confirmation transition tests),
5 (.complete added to the legacy predicate as legacy-terminal residue + test),
6 (throwing quote add/edit/delete + stage write failure tests — retryable UI state,
never advance).

Plan revised to v6. Round 6 spends the last chain round (6 of 6).

## Round 6 — Codex (VERDICT: ITERATE) — chain budget exhausted (6 of 6)

v6 resolves the six prior findings substantively, but one new blocking failure mode remains. Direct `SpawnService` and the client-only no-retry decision remain justified.

1. [HIGH] The persisted support message proves only `persisted`; it cannot durably preserve `adminQueued`. `SupportMessage` has no queue-status field ([SupportMessage.swift:51](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/SupportMessage.swift:51>)), and rules prohibit clients from updating user messages ([firestore.rules:18](</Users/adampowell/Desktop/Peezy 4.0/firestore.rules:18>)). If the app exits after persistence, reopening disables the button but cannot determine whether to show the required delivery-pending notice—potentially leaving an unqueued request silent.  
   Fix: Make the task-doc marker mandatory: atomically persist the message plus `{messageId, adminQueued:false}`, update it to `true` after callable success, and test reopen for both queued and pending states without retrying the callable.

2. [MEDIUM] A1 still says the coordinator owns a `spawn→complete→callback` sequence ([plan:62](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-movers-spawn-chain.md:62>)), contradicting the corrected zero-callback persistence contract and tests.  
   Fix: Replace that phrase with `spawn→complete→confirmation` and state that the coordinator never owns the Home callback.

3. [LOW] The duplicate-send bullet still says suppression lasts “for this task session” ([plan:241](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-movers-spawn-chain.md:241>)), despite the new durable per-task requirement.  
   Fix: Change it to “after persistence for this task, including after dismiss or relaunch.”

4. [MEDIUM] `SupportMessage.swift` and `firestore.rules` are now load-bearing for the durable-marker design but remain absent from Required Reading.  
   Fix: Add both files to Required Reading alongside `SupportChatService.swift`.

VERDICT: ITERATE
### Response (round 6) — LOOP CLOSED

All 4 findings accepted verbatim: 1 (task-doc marker mandatory — atomic message +
expertReview{messageId, adminQueued:false}, flipped true after callable success; reopen
tests for both states, callable never re-invoked), 2 (spawn→complete→confirmation;
coordinator never owns the Home callback), 3 (durable suppression wording), 4
(SupportMessage.swift + firestore.rules added to Required Reading).

## Final summary

Round → verdict → findings: R1 ITERATE (13) · R2 ITERATE (11) · R3 ITERATE (8, cap hit)
· R4 ITERATE (6, user round) · R5 ITERATE (6, user round) · R6 ITERATE (4, budget
exhausted). Chain budget: 6 of 6 review rounds spent; 0 remain for codex-execute.

Terminal state: CONVERGED BY USER DECISION at v7. No formal APPROVE was issued; round 6
retained one HIGH whose exact fix the reviewer itself specified and which v7 adopts
verbatim, plus three text edits. Sol re-affirmed both structural decisions (direct
SpawnService, round 5; client-only no-retry support, rounds 5–6). User-decided scope
call on record: no submitSupportMessage backend change (round 3).

Execution: by Claude directly (user decision, post-budget), against plan v7.
