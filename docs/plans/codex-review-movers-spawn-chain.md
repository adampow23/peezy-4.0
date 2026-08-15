# Plan: Movers Three-Task Spawn Chain + Expert Review Button (v7 — FINAL)

Status: CONVERGED BY USER DECISION after 6 review rounds (Codex gpt-5.6-sol, persistent
session). Round 6 left 1 HIGH (fixed below exactly as the reviewer specified) + 3 text
edits; the user closed the loop at v7 and authorized execution by Claude. Sol formally
re-affirmed the two structural decisions (direct SpawnService; client-only support with
no retry) in rounds 5 and 6. Full argument transcript:
docs/plans/codex-review-movers-spawn-chain-review-log.md.

## Required reading before implementation

CLAUDE.md, peezy-conventions-v2.md, then: FindMoversFlow.swift, MoversFlowViewModel.swift,
MoversFlowStage.swift, MoversQuotesView.swift, MoversScenarioMatrixView.swift,
functions/spawnTasks.js, SpawnService.swift, functions/taskCatalogData.json +
seedTaskCatalog.js (BOOK_MOVERS row, spawnedOnly patterns, seeder projection +
Swift-custom allowlist), SupportChatService.swift, SupportChatView.swift,
TaskActionService.swift, QuoteTrackerView.swift, TaskFlowRouter.swift, and (round-4
finding 3) the completion-handshake load-bearing files: PeezyHomeViewModel.swift,
PeezyHomeView.swift, FlowExitControl.swift. Also TaskGenerationService.swift +
PeezyCardFirestoreMapper.swift (denormalized title path, round-4 finding 1),
MoversScenarioMatrixView.swift (notes save path, round-4 finding 5), and (round-6
finding 4, load-bearing for the durable marker) SupportMessage.swift + firestore.rules.

## GOAL A — Split Book Movers into a three-task spawn chain

### A1. BOOK_MOVERS becomes "Get Moving Quotes"

Education cards + equip screen (call sheet, share inventory). Completion button
("I'm getting quotes"):

- **Spawn mechanism (decided, round 1 finding 1):** flow-local direct `SpawnService`
  call — NOT `onCompleteSpawns` metadata, which has no execution path (generation does
  not copy it; completion paths only update status). Call with
  `source.kind = "onComplete"`, `source.id` = the user-task **document ID**, and a
  stable per-edge idempotency token: `"BOOK_MOVERS->COMPARE_MOVING_QUOTES:<taskDocId>"`.
- **Ordering (round-1 findings 1+7, round-2 finding 3, round-3 finding 2; contradiction
  removed per round-5 finding 1):** spawn COMPARE_MOVING_QUOTES first and await
  success, THEN perform a **movers-only throwing completion write** on the task doc
  (this write owns `completedAt` — written exactly once, at true completion time) and
  await it. Successful persistence does exactly ONE thing next: it sets the flow's
  confirmation state. **No callback of any kind fires at persistence time** — no local
  removal, no analytics, no Home invocation (the current local-removal path also
  dismisses the cover, which would skip confirmation or double-account). Confirmation
  Done alone calls `completeTaskFlowAlreadyPersisted()` (defined below), which performs
  the local removal + analytics and dismisses, and never writes.
  **Two-phase handshake (round-4 finding 3):** phase 1 = durable persistence →
  confirmation state, nothing else. Phase 2 = confirmation Done →
  `completeTaskFlowAlreadyPersisted()`, one new movers-facing method that records local
  completion (removes the card locally, fires analytics) and dismisses — and never
  writes. An end-to-end state-transition unit test covers: durable-complete →
  confirmation shown, no callback fired → Done → local completion + dismissal, no
  write.
  **Exit locking (seam specified per round-5 finding 4):** the outer X currently reads
  only `FlowExitCoordinator.isReadyForExit` and cannot observe movers state, so the
  plan adds an explicit **`isExitLocked` binding/environment contract** consumed by
  `OutermostTaskFlowContainer`: locked while a spawn/complete edge is in flight AND
  through the confirmation state (after durable completion the only way out is Done —
  never a mid-flow dismiss that would allow reopen-and-respawn); unlocked again on edge
  failure so the user isn't trapped. Unit tests cover the in-flight, failure, and
  confirmation transitions of that contract — not just coordinator-internal
  suppression.
  On spawn or completion-write failure: button returns to enabled with a visible error
  state; retry re-sends the same token (idempotent server-side replay). Button disabled
  while the sequence is in flight. No userInProgress staging — a real crossed-off win.
- **Orchestration + tests (round-3 finding 6, phrase corrected per round-6 finding 2):**
  the **spawn→complete→confirmation** sequence, token construction, and failure
  boundaries live in a small **flow-local, protocol-injected `MoversChainCoordinator`**
  (not an app-wide completion coordinator — that stays rejected). The coordinator never
  owns the Home callback: its terminal output is confirmation state, and only Done's
  `completeTaskFlowAlreadyPersisted()` touches local Home accounting. Unit tests cover: exact call ordering, stable token reuse across
  retries, failure at each boundary (spawn fails / completion write fails / both), no
  callback before durable completion, exit- and double-tap suppression, all three
  `MoversFlowRole`s paired with random task document IDs, and the support delivery
  state machine from GOAL B.

### A2. COMPARE_MOVING_QUOTES ("Compare your moving quotes") — new spawnedOnly row

- Opens the quote-entry list + scenario matrix (the views built today, rehomed from the
  staged flow). Quotes persist on THIS task's doc.
- **Date rule (round-1 finding 3, semantics fixed per round-3 finding 7):**
  `{"anchor": "spawn", "offsetDays": 3}` — preserves the current three-day return
  behavior. `resolveDueDate` in functions/spawnTasks.js currently understands only
  `moveDate` anchors, so add an **additive** `spawn` anchor branch. Exact semantics:
  **due = the spawn instant + offsetDays × 24h** — plain UTC millisecond arithmetic, no
  midnight normalization (which could display as the prior local date). Tests assert
  exact ISO-8601 outputs for a non-midnight input (e.g. spawn
  2026-08-14T21:37:12.000Z + 3d → 2026-08-17T21:37:12.000Z) and a DST-boundary input
  (UTC arithmetic is DST-immune; the test documents that). This modifies the existing
  callable only — no new backend functions. New anchor is only referenced by the new
  rows, so no other flow's spawn behavior changes.
- Completing it spawns BOOK_YOUR_MOVERS (same direct-SpawnService pattern, token
  `"COMPARE_MOVING_QUOTES->BOOK_YOUR_MOVERS:<taskDocId>"`, spawn-then-complete
  ordering). Date rule for BOOK_YOUR_MOVERS: `{"anchor": "spawn", "offsetDays": 1}`.
- **Notes ordering (round-4 finding 5):** the compare screen's Done first runs
  `await persistNotesThrowing()` and only on success hands off to the coordinator's
  spawn→complete sequence; notes failure blocks spawning with a visible error. The
  competing unstructured blur-save is removed/serialized so it cannot race Done's
  persist. Coordinator tests include the notes-failure-prevents-spawn case.

### A3. BOOK_YOUR_MOVERS ("Book your movers") — new spawnedOnly row

One screen — "Did you book with the company you chose?"

- **Yes** → capture fields, all optional: company (prefill chips), move date, arrival
  window, crew size, hourly rate. **Persisted schema (round-1 finding 11):** a
  `bookingDetails` map with required `booked: true` + `savedAt` (server timestamp);
  optional `company: String`, `moveDate: Timestamp`, `arrivalWindow: String`,
  `crewSize` (NSNumber-safe Int), `crewHourlyRate` (crew-total dollars, NOT per-man).
  **Durability (round-3 finding 3, exact contract per round-4 finding 2):** Done
  performs ONE awaited atomic update whose exact payload is `"status": "Completed"`
  (the precise status-contract string — lowercase would decode as `.upcoming` and leave
  the booked task visually active) + `completedAt` + the `bookingDetails` map, together
  — not a bookingDetails write followed by a detached completion. A unit test asserts
  that exact payload. Only after it succeeds do non-writing local callbacks run (task
  removal, analytics). Visible error + retry on failure.
- **Prefill chips (finding 5):** quotes live on the predecessor doc, not this one. The
  view reads its own task's `spawnedFrom.id`, fetches that completed predecessor task
  doc, and derives deduplicated company-name chips from its quotes. Works for both
  COMPARE_MOVING_QUOTES predecessors and legacy BOOK_MOVERS predecessors (migration
  path below). Predecessor fetch failure or empty quotes → no chips, free-text entry
  still works.
- **Not yet** → "I'll book later" keeps the existing **two-day** snooze semantics
  (round-2 finding 4), but NOT the existing `.later` code path, whose write is detached
  and failure-swallowing (round-3 finding 3): the movers flow awaits a **throwing
  two-day snooze write**, and only on success invokes the non-writing local callbacks
  and dismisses. Visible error + retry on failure. Writes NO booked state.

### A4. Routing + catalog (finding 6)

- **No new flow definitions.** Tiny flow defs cannot supply the quote editor/matrix or
  the conditional booking form. All three IDs route to Swift customs: explicit
  TaskFlowRouter cases for `compare_moving_quotes` and `book_your_movers` alongside
  `book_movers`, backed by one movers container/view model.
- **Role passing (round-2 finding 1):** the role can NOT be derived from the task
  document ID — spawned docs have random IDs. Each router case passes an explicit
  `MoversFlowRole` (`.getQuotes` / `.compareQuotes` / `.bookMovers`) derived from the
  **flowId** it matched on, with `taskDocumentId` carried separately for persistence.
- **Catalog row contract (round-2 finding 9, corrected per round-3 finding 4):** the
  key is **`taskId`** (matching the JSON and seeder — not `id`). THREE rows change:
  - **BOOK_MOVERS (modified):** title → "Get Moving Quotes", description updated to
    match its new education+equip scope. All other fields unchanged.
  - **COMPARE_MOVING_QUOTES (new):** title "Compare your moving quotes", description,
    same category as BOOK_MOVERS, actionType `workflow`, workflowId
    `compare_moving_quotes`, `spawnedOnly: true`, no assessment conditions, dateRule
    `{"anchor":"spawn","offsetDays":3}`, plus every metadata field present on sibling
    rows (estimate, etc. — copied and adjusted, none omitted).
  - **BOOK_YOUR_MOVERS (new):** title "Book your movers", same shape, workflowId
    `book_your_movers`, dateRule `{"anchor":"spawn","offsetDays":1}`.
  A **static Node test** asserts, for all three rows: exact `taskId`s, exact
  user-visible titles (including the BOOK_MOVERS retitle), spawnedOnly true on the two
  new rows only, workflowId == lowercased taskId, exact date rules, and presence of
  every field the seeder projection reads. Seeder projection extended for any new
  fields AND both new IDs added to the seeder's Swift-custom allowlist.

### A5. Migration for mid-flight users (finding 4)

Legacy detection must not rely on stage alone, because stage/quote writes historically
swallowed errors: treat a BOOK_MOVERS doc as **legacy-inline** when
`stage ∈ {.compare, .verify, .complete}` **OR** its quotes array is nonempty — with
`.complete` as an explicit **legacy-terminal residue** (round-5 finding 5: the old flow
writes `.complete` before Home's detached, failure-swallowing status write, so an
active doc can carry `.complete` without ever having completed; classifying it
state-free would wrongly restart it in the new chain). A migration/resume test covers
this residue state. Legacy-inline docs
resume the old quotes/matrix experience in place on BOOK_MOVERS (no data movement, no
quote loss); on completion they spawn **only** BOOK_YOUR_MOVERS (they already compared).
State-free BOOK_MOVERS docs get the new chain (A1). Fresh generations are chain-only.

**Denormalized title migration (round-4 finding 1):** the catalog retitle alone never
reaches existing users — generation copies title/description into each user task doc
and the UI reads that copy. So the client runs an awaited one-shot migration for an
existing BOOK_MOVERS doc (at task-load time, once per session, via TaskActionService —
not inside the shared mapper, which stays a pure decoder): classify the doc with the
legacy predicate, then if its title is stale, await an update whose payload contains
EXACTLY the keys `title` and `desc` (round-5 finding 3: the stored/read field is
`desc`, not `description`) — state-free docs → "Get Moving Quotes" (+ new desc),
legacy-inline docs → "Compare your moving quotes" (an honest name for the matrix they
resume). The migration is cosmetic, so **failure is nonblocking**: the flow proceeds
with the stale title, and the once-per-session guard is set only after a successful
write (a failed attempt retries next session). Unit tests cover both branches, the
exact `title`/`desc` payload keys, quote preservation (no quote or stage fields in the
payload), and the nonblocking-failure path.

### A6. Persistence hardening scoped to this flow (finding 7)

The movers flow's quote saves, stage writes, and completion currently log-and-continue.
For the paths this plan touches: throwing persistence via **movers-specific throwing
entry points** (or a shared throwing core retained behind the existing catch-and-log
wrappers, so every current caller keeps byte-identical behavior — round-2 finding 8);
the UI advances, dismisses, or spawns only after the write succeeds, with visible retry
affordances. `setStage`/`updateQuotes` as called by other flows behave exactly as today.

### A7. Successor visibility (finding 13)

Spawned successors appear immediately in the Tasks tab (TasksStore snapshot listener).
They do NOT join the already-frozen Home daily dose for the current day — expected
behavior, not a failed spawn. **Copy surface (round-2 finding 10):** after the
spawn+complete sequence succeeds, the flow shows a confirmation state on its final
screen — "Nice — your next step is waiting in Tasks" with a Done button — and dismisses
only on Done. No timed toast, no auto-dismiss. Manual QA asserts this copy appears after
a successful spawn.

## GOAL B — Expert review button on the scenario matrix

"Have a move expert look these over" button under the matrix, accessibility id
`expertReviewButton`. Free — rides support, no paywall.

- **Message composition (finding 10):** deterministic formatter (pure function, unit
  tested with exact-output assertions) producing an admin-readable body: per quote —
  company, crew size, hours, **crew-total hourly rate** (stored per-man rate × crew),
  travel fee, computed man-hours (crew × hours); plus Peezy's estimated man-hours when
  present.
- **Send semantics (round-1 finding 9, round-2 finding 7, round-3 finding 1 — resolved
  CLIENT-ONLY by user decision):** `SupportChatService.sendMessage` currently returns
  "was first user message", and the `submitSupportMessage` callable — the thing that
  actually updates `supportThreads` for the admin inbox — is detached behind `try?`.
  Change sendMessage to return a structured result with **separate states**:
  `persisted` (message doc written) and `adminQueued` (callable awaited and succeeded),
  plus `wasFirstUserMessage`; update existing call sites (their current behavior
  preserved). The callable is NOT modified and NOT retried: it is not idempotent
  (increments admin unread + fires a notification per invocation), so a targeted retry
  can duplicate admin effects, and fixing that requires a backend change the user
  explicitly declined. Expert flow behavior:
  - `persisted && adminQueued` → present the support thread sheet (same pattern as
    TaskDetailView's chat button) with the request visible as a bubble.
  - `persisted && !adminQueued` → present the thread with a non-blocking notice using
    honest copy (round-4 finding 4 — nothing background-retries, so no promise of
    follow-up): **"Saved in Chat, but we couldn't confirm delivery. Send a new Chat
    message to alert support."** No retry button. The message doc is durably in the
    thread; a subsequent organic support message goes through the normal
    indexing/notification path.
  - `!persisted` → stay on the matrix with an actionable error (this state CAN retry —
    nothing was written).
  **Durable send suppression (round-5 finding 2, marker made MANDATORY per round-6
  finding 1):** "disabled for the session" is not enough — dismissing and reopening the
  task resets view state and would permit a second bubble plus another non-idempotent
  callable invocation. And the persisted message alone can prove only `persisted`, never
  `adminQueued`: SupportMessage has no queue-status field, and Firestore rules bar
  clients from updating user messages, so after an app exit the delivery-pending notice
  could not be reconstructed and an unqueued request would go silent. Therefore the
  **client-owned task-doc marker is mandatory, not a fallback**: the expert send
  atomically persists the message AND writes `expertReview: {messageId,
  adminQueued: false}` on the task doc, then updates `adminQueued: true` after callable
  success. The button renders disabled whenever the marker exists — including after
  dismiss→reopen — and reopening shows the delivery-pending notice iff
  `adminQueued == false`. Unit tests cover reopen in both queued and pending states
  (correct notice, button disabled, callable NEVER re-invoked). No callable
  modification, no retry: the accepted client-only rationale stands.
  Follow-up recorded in LAUNCH_CHECKLIST.md: make submitSupportMessage idempotent on
  uid+messageId so a targeted retry becomes safe (out of scope here by user decision).
- **Duplicate-send mitigation (round-1 finding 10, wording per round-6 finding 3):**
  button disabled while sending and after persistence for this task, **including after
  dismiss or relaunch** (durable per-task state, below).
- Sends with `taskContext` so the admin inbox threads it to the task.

## CONSTRAINTS

- No NEW backend functions. The only backend edit is the additive `spawn` anchor in the
  existing spawnTasks callable + catalog data/seeder projection. No rules changes. No
  changes to other flows' spawn behavior. Matrix math untouched.
- NSNumber-safe casts, empty-id guards, accessibility ids on every new control.
- Update PHASE_MANIFEST first.

## ROLLOUT SEQUENCING (documented, NOT executed in this task — finding 8)

This task ships code + data only; no deploys, no seeding, no commits. When Adam ships
(round-2 findings 2 + 6 folded in):

0. **Preflight:** run the Node test suites (incl. the new spawn-anchor and catalog
   static tests) green. **Export** the current remote `taskCatalog` and
   `flowDefinitions` collections to a dated backup file (read-only) — the seeder
   deletes-then-rewrites BOTH collections, so a failure between delete and rewrite must
   be recoverable from the export, not from memory. Run a read-only diff of remote
   rows vs the post-change JSON and confirm the only deltas are the intended ones.
1. Deploy the updated `spawnTasks` callable (backward compatible — `spawn` anchor is
   additive; existing rows/anchors unaffected).
2. Reseed via the existing full-reseed path, in a low-traffic window (the
   delete→rewrite gap is user-visible). Verify the remote catalog row count equals the
   **post-change JSON-derived count** (derived at seed time, never hardcoded — the JSON
   already holds 61 rows today, not the 47 of Spec 08), verify the flowDefinitions
   count matches the seeded set, and spot-check both new rows' fields. **Recovery from
   partial failure:** re-run the seeder (it is a full rewrite, so a clean re-run is the
   repair); if the JSON itself is suspect, restore from the step-0 export.
3. Ship the client build.
   Old clients against the new catalog never see the spawnedOnly rows (spawnedOnly rows
   are not generated at assessment; they appear only via spawn, and old clients never
   call spawn for them). New clients against the old callable are protected by ordering
   (step 1 precedes step 2/3).
   **Rollback is phase-dependent (round-3 finding 5):**
   - Before the client release (after steps 1–2 only): restore the prior catalog JSON
     from git and reseed — safe, no client references the new rows yet.
   - After the client release: do NOT remove the successor rows — installed v-next
     clients call spawn for them and would fail `not-found` (the callable change is
     additive, but the rows are load-bearing). Roll back other changes around them and
     retain COMPARE_MOVING_QUOTES/BOOK_YOUR_MOVERS until the client is rolled back or
     superseded.

## ACCEPTANCE CRITERIA + VERIFY (finding 12)

Unit tests (new, in existing test targets):
- Expert-message formatter: exact-output tests incl. crew-total rate math, man-hours,
  missing travel fee, missing Peezy estimate.
- Legacy-detection predicate: stage-only, quotes-only, both, neither → correct
  legacy/chain classification.
- Chip derivation: dedup, empty quotes, predecessor missing.
- bookingDetails encoding: all-fields, minimal (booked+savedAt only), NSNumber-safe
  crewSize decode.

Node tests (round-2 findings 5 + 9 — the existing suites already cover
`resolveDueDate`, so the changed function gets real cases, not just `node --check`):
- Spawn-anchor cases added to the existing spawnTasks suites: offsets 3 and 1, missing
  move date (spawn anchor must not require one), non-midnight `now`, UTC boundary, and
  unchanged behavior for every existing moveDate-anchored case.
- Catalog static test for both new rows (contract in A4).
- Both existing Node suites run green.

Static/build verification:
- xcodebuild simulator build succeeds, AND `xcodebuild test` runs the unit-test target
  green (round-4 finding 6 — build alone executes no tests).
- `node -e 'JSON.parse(...)'` on functions/taskCatalogData.json; `node --check` on
  spawnTasks.js and seedTaskCatalog.js.
- Existing ManHourNormalizer + PricingEngine tests still pass.
- New accessibility identifiers present on: expertReviewButton, chain completion
  buttons, booking capture fields, snooze control (grep check).

Additional unit tests (round-3 finding 6 — pure client seams, no live harness needed):
- `MoversChainCoordinator`: ordered notes→spawn→complete calls; stable token reuse
  across retries; failure at each boundary (notes / spawn / completion write); notes
  failure prevents spawning; **no callback fires at persistence — persistence yields
  only confirmation state** (round-5 finding 1); double-tap suppression; all three
  roles with random task document IDs.
- Completion handshake state transitions (round-4 finding 3 + round-5 finding 1):
  durable-complete → confirmation state, zero callbacks → Done →
  `completeTaskFlowAlreadyPersisted()` local completion + dismissal with no write.
- `isExitLocked` contract (round-5 finding 4): in-flight → locked; edge failure →
  unlocked; confirmation → locked until Done.
- Throwing quote/stage persistence (round-5 finding 6): failed quote add/edit/delete
  and failed stage writes preserve retryable UI state and never advance the flow.
- Support delivery state machine: persisted/adminQueued permutations → correct
  presentation state, button disablement once persisted, no retry path when persisted.
- BOOK_YOUR_MOVERS terminal writes: "Yes" produces one atomic update with the exact
  payload `"status": "Completed"` + completedAt + bookingDetails; "Not yet" produces a
  throwing two-day snooze.
- Title migration (round-4 finding 1 + round-5 findings 3+5): state-free,
  legacy-inline, and `.complete`-residue branches produce the correct classification
  and titles; migration payload contains exactly the keys `title` and `desc`; failure
  is nonblocking and leaves the session guard unset.
- Spawn-anchor due dates (Node): exact ISO expectations per A2.

Not unit-testable here (documented as manual QA for Adam, not silently skipped): live
spawn edge against deployed callable, support message arrival in admin inbox (incl. the
delivery-pending state), two-day snooze round-trip on device, post-spawn confirmation
copy ("Nice — your next step is waiting in Tasks"), and — round-3 finding 8 — the free
path end-to-end: an UNSUBSCRIBED user opens the matrix, submits expert review, sees the
thread (or delivery-pending state), with no paywall at any step.

Do not commit.

## Reviewer pushback (rejected findings, with rationale)

- **Finding 2 (transactional token claim in spawnTasks.js + concurrency test):**
  rejected for this task. The read-before-batch race predates this work and is shared
  by every spawn flow; changing it violates the explicit "no changes to other flows'
  spawn behavior" constraint. This flow serializes calls (button disabled in flight),
  and the stable token keeps serial retries idempotent. Logged as a follow-up
  candidate outside this task.
- **Finding 8, upsert-seeder portion:** rejected. A targeted guarded upsert seeder is
  new tooling this task doesn't need; the full-reseed path is the established,
  previously acceptance-tested mechanism (Spec 08). The unsafe-rollout substance of the
  finding IS accepted via the documented sequencing + remote verification above.
- **Finding 12, full Given/When/Then including live spawn/support/paywall:** partially
  accepted. Pure seams get real unit tests (above); live-backend edges are explicit
  manual QA items rather than pretend-automation this repo has no harness for.

## ADR

- **Decision:** three-task spawn chain via flow-local SpawnService calls with stable
  per-edge tokens and spawn-before-complete ordering; spawn-anchored due dates via an
  additive resolveDueDate branch; legacy-inline migration keyed on stage OR quotes;
  expert review rides existing support with a structured send result.
- **Drivers:** real crossed-off wins per stage; no new backend surface; zero quote loss
  for mid-flight users; admin inbox gets actionable quote summaries for free users.
- **Alternatives considered:** onCompleteSpawns metadata (no execution path exists);
  centralized completion coordinator (touches every completion surface — out of
  scope); moveDate-anchored compare due date (breaks the 3-day return rhythm and
  misbehaves for near-term moves); quote-doc duplication onto successor docs (data
  copying where a spawnedFrom fetch suffices).
- **Consequences:** spawnTasks deploy must precede catalog reseed; BOOK_YOUR_MOVERS
  reads a predecessor doc at render time; SupportChatService call sites updated for the
  structured result.
- **Follow-ups:** recorded in `LAUNCH_CHECKLIST.md` during implementation (the repo's
  sole open-item ledger — round-2 finding 11), not duplicated here: transactional token
  claim in spawnTasks (all flows), RENT_TRUCK's dormant onCompleteSpawns metadata
  cleanup, submitSupportMessage idempotency on uid+messageId (unlocks a safe targeted
  retry — deferred by user decision). LAUNCH_CHECKLIST.md joins PHASE_MANIFEST for that
  write.
