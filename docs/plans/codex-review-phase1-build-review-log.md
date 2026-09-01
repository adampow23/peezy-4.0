# Phase 1 executable-spec adversarial review log

Plan: `docs/plans/codex-review-phase1-build.md`

Reviewer continuity: the primary reviewer is one continuing Codex agent across
rounds. A second read-only reviewer was used in round 1 only for a focused rules,
event-ordering, and external-amendment pass. No implementation starts before the
primary thread converges.

## Round 1 — primary review of revision 1

Verdict: **ITERATE**. Fifteen findings; all accepted into revision 2.

1. **HIGH — mapped nonterminal contract copy can be unreachable or falsely
   Done.** Accepted. Revision 2 defines contract-aware Home/Tasks projection for
   every status, table tests legacy/contract variants, and removes direct row
   actions for contracted nonterminal cards.
2. **HIGH — preserving a server-owned contract while allowing client status
   changes creates incoherent status/contract pairs.** Accepted. Rules now deny
   client lifecycle transitions on contracted tasks. Phase 1 hides their legacy
   controls; W3/W4 are the only server transitions in scope.
3. **HIGH — whole-task owner delete bypasses contract ownership.** Accepted.
   Delete is allowed only for legacy tasks without the map.
4. **HIGH — merge-based initial generation can resurrect terminal tasks while
   preserving stale lifecycle data.** Accepted. Initial generation is add-only
   for every existing ID and receives Completed/Snoozed/superseded fixtures.
5. **HIGH — external supersession retires the sent artifact before institution
   confirmation, contrary to A7.** Accepted. External supersession is now a
   pending amendment; explicit confirmation performs retirement.
6. **HIGH — replacement reuse may equal the original or reuse a terminal task.**
   Accepted. Amendment IDs are revision/original-specific `a2_` IDs; same catalog
   task and ordinary/terminal/other-original collisions fail closed.
7. **HIGH — reopen is neither retry-idempotent nor a coherent undo.** Accepted.
   Operation tokens, monotonic revisions, append-only cycles, untouched-amendment
   cancellation, and progressed-amendment failure are specified and tested.
8. **HIGH — A11a source-version ordering is absent.** Accepted. Per-user/per-key
   high-water records transactionally order fire, correction, stale, duplicate,
   conflict, and retraction envelopes.
9. **HIGH — `fired != true` excludes missing fields.** Accepted. Date query no
   longer filters fired; each candidate is rechecked transactionally.
10. **MEDIUM — scheduled wrapper cannot inject the lexical evaluator.** Accepted.
    A handler factory supplies db, time, and evaluator seams before `onSchedule`.
11. **HIGH — category ordinal and display label are mutable identity.** Accepted.
    Flow rows get persisted subject UUIDs; option ID is canonical institutionId;
    label is presentation only. Reorder/rename/same-category tests were added.
12. **MEDIUM — Swift does not test the exact callable payload.** Accepted.
    `SpawnService.makePayload` is pure and has exact legacy/t2 shape tests.
13. **HIGH — the general Node glob would run the rules test without an emulator.**
    Accepted. Rules tests moved to `functions/rules-tests` and run exactly once.
14. **MEDIUM — selected XCTest can pass with zero tests.** Accepted. The unique
    xcresult is recursively parsed for exact suite equality, nonzero counts,
    passing leaves, and absence of every UI/integration class.
15. **MEDIUM — `[String:String]` loses valid A11 payload values.** Accepted. W1
    now specifies a recursive Firestore value with mixed round-trip fixtures.

## Round 1 — focused rules/event/amendment review of revision 1

Verdict: **ITERATE**. Nine findings; all accepted into revision 2. Findings 2,
3, 6, 7, 8, and 9 independently corroborated primary findings 3, 8, 6, 7, 9,
and 13 respectively.

1. **HIGH — narrowing removes active client reads.** Accepted. Explicit owner-
   read/client-write-false rules and emulator rows cover packingAggregate,
   research, workflowResponses, nested chats/messages, and moveAnswers.
2. **HIGH — contracted task deletion bypass.** Accepted as primary finding 3.
3. **HIGH — event ordering absent.** Accepted as primary finding 8.
4. **HIGH — query-then-process events have an event-first/task-later lost wake.**
   Accepted. Event ingestion only advances durable high-water state; a separately
   paginated task-driven reconciler can observe already-processed events.
5. **HIGH — poison events can starve the bounded query and event fan-out is
   unbounded.** Accepted. Invalid events become terminal quarantined rows; the
   task-driven model removes per-event fan-out and uses max+1/cursor pagination.
6. **HIGH — replacement reuse contradicts amendment guarantees.** Accepted as
   primary finding 6, with amendment-specific revision keys.
7. **MEDIUM — reopen replay/cycles undefined.** Accepted as primary finding 7.
8. **MEDIUM — scheduled queries/index JSON not executable-spec complete.**
   Accepted. Exact order/limits and deep-equal composite/fieldOverride assertions
   are required; missing-fired behavior is explicit.
9. **MEDIUM — rules suite runs outside emulator.** Accepted as primary finding 13;
   emulator invocation also unsets credentials/config and disables CLI telemetry
   and update checks.

## Round 2 — primary review of revision 2

Verdict: **ITERATE**. Fifteen new/residual findings; all accepted into revision 3.

1. **HIGH — terminal meanings are not representable.** Accepted. Contracts now
   carry canonical disposition plus explicit not_applicable/retired/superseded
   terminal kind; malformed pairs fail safe and table tests cover all meanings.
2. **HIGH — Home still launches rejected actions for contracted cards.**
   Accepted. A pure Home projection separates passive contract status from the
   Daily Dose; passive copy is untappable and cannot flow/write/credit/remove.
3. **HIGH — generation's pre-read/add-only plan is race-prone.** Accepted. Both
   generation paths use one read-before-write Firestore transaction seam and a
   retry/concurrent-lifecycle fixture.
4. **HIGH — businessSearch still uses mutable labels as institution identity.**
   Accepted. The business card now returns a persisted identity object, using a
   MapKit provider identifier when available and once-generated UUID otherwise;
   progress/resume/migration tests and all required files were added to scope.
5. **HIGH — confirmed amendment lacks A7 brief undo.** Accepted. A five-minute,
   operation-idempotent undo restores truthful pending verification without
   claiming the institution reversed reality; expiry/progress/replay are tested.
6. **HIGH — different operation IDs can create parallel pending cycles.**
   Accepted. The full closed state table rejects all non-replay supersedes while
   pending/confirmed/retired and tests simultaneous/sequential contention.
7. **HIGH — event high-water delimiter collision.** Accepted. Key preimage is
   canonical JSON of a two-element array; the stated collision pair is tested.
8. **HIGH — same-version arbitration ignores semantic drift.** Accepted. Full
   canonical envelope fingerprint equality is required for duplicate; all drift
   is version_conflict.
9. **MEDIUM — missing observed_at never reaches quarantine.** Accepted. Pending
   events order only by full document name; the missing-field fixture is terminal.
10. **HIGH — scheduler runtime/concurrency budget absent.** Accepted. Endpoint-
    local region/timeout/memory/instance/concurrency/retry options, a durable
    lease, ten-way work cap, and metadata/overlap tests are specified.
11. **MEDIUM — event cursor is not unique or concurrency-safe.** Accepted. Named
    server-only state stores full paths; lease-bound advancement/wrap handles
    duplicate leaf IDs, restart, and overlaps.
12. **MEDIUM — poison date candidates can starve later rows.** Accepted. Date
    cursor stores `(at, fullPath)`, advances past every processed page, and wraps;
    a 200-poison-plus-valid test is required.
13. **HIGH — W5 leaves lifecycle-adjacent fields client-writable.** Accepted.
    Contracted tasks are entirely client-read-only; contractless tasks freeze the
    enumerated server-authored identity/plan/provenance set.
14. **HIGH — clients can preclaim t1/t2/a2 IDs.** Accepted. Reserved client create
    is denied; t2 reuse validates complete provenance. Legacy t1/t2 lifecycle and
    delete remain owner-allowed only while contractless, preserving the owner's
    explicit H20 constraint; identity mutation and every a2 mutation are denied.
15. **MEDIUM — red XCTest selector instructions contradict the global rule.**
    Accepted. W1, W2, W3, and final literal safety envelopes are distinct but all
    use named unit selectors, the UI skip, no test plan, and no integration env.

## Round 3 — primary review of revision 3

Verdict: **ITERATE**. Nine residual findings; all accepted into revision 4.

1. **HIGH — contracted tasks break Settings Retake Assessment deletes.**
   Accepted. Existing `changeTaskPlan` gains an idempotent, resumable
   `resetAllTasks` action; Settings awaits it before local assessment/dose reset.
   A protected reset marker blocks concurrent task creation. Gate item 6 remains
   SUPPORTED under this explicit binding rather than the old client delete loop.
2. **HIGH — status/disposition pairs conflate A2 and A7 and W3/W4 emit invalid
   pairs.** Accepted. A2 disposition and A7 terminal_kind are independent;
   external pending writes matching_in_progress/WAITING_ON_EXTERNAL, and wakes
   write Upcoming with no current disposition/terminal. Shared validation covers
   every W3/W4 output.
3. **HIGH — terminal Replaced copy is never rendered.** Accepted. Contract copy
   takes priority on every contracted row, including Done; exact copy is tested.
4. **HIGH — reopen permits client deletion of retained history.** Accepted.
   Direct delete requires no contract and no plan/audit fields; reset uses Admin.
5. **HIGH — durable flow row UUID is client mutable.** Accepted. flowRows may be
   set on initial normal create but are immutable on update; answer/identity
   progress remains writable.
6. **HIGH — terminal events do not explicitly leave the pending query.**
   Accepted. Every outcome atomically writes processingState terminal; >100 mixed
   terminal rows followed by a valid event is tested.
7. **MEDIUM — confirmation undo window can renew and history is mutated.**
   Accepted. One absolute first-confirmation deadline and one undo per revision;
   every transition appends a new immutable history record.
8. **MEDIUM — flowAnswerIdentities is not cleared.** Accepted. All progress keys
   clear atomically, with restart/stale-identity tests.
9. **MEDIUM — passive Home copy is optional/missing on empty states and get-ahead
   can select it.** Accepted. Passive rendering is mandatory across every Home
   state and separate from allActiveTasks/taskQueue/getAhead.

## Round 4 — primary review of revision 4

Verdict: **ITERATE**. Six residual findings; all accepted into revision 5.

1. **HIGH — getWorkflow Admin writes can corrupt contracted status pairs.**
   Accepted. Every task mutation now checks the reset marker and target inside a
   transaction. Contractless/missing paths preserve exact legacy behavior;
   contracted guidance/vendor paths atomically emit validated pairs, while
   collisions or malformed pairs fail closed. Dedicated W1 Node tests and a
   literal per-workstream command are required.
2. **HIGH — reopened ordinary tasks can delete retained audit history.**
   Accepted. Delete of every task ID now requires both no contract and absence of
   every plan/audit field; a nonreserved, previously contractless reopen fixture
   is required.
3. **HIGH — Retake paging lacks exclusive, crash-safe progress.** Accepted.
   Reset uses an expiring worker lease, per-page marker/owner transaction,
   atomic unique-deletion checkpoint, owner-checked empty-query transition, and
   stale-worker denial, with contention/crash/count/regeneration fixtures.
4. **HIGH — Settings reset is not durably resumable or offline-testable.**
   Accepted. An injected Retake coordinator durably stores/adopts the per-user
   operation ID, propagates every cleanup failure, retains it through ambiguous
   finalize, and notifies only after successful/replayed finalize.
5. **HIGH — internal replacement behavior is contradictory.** Accepted.
   Internal requests reject replacement pre-read, never write supersededBy, and
   return a null replacementTaskId; external replacement remains mandatory.
6. **MEDIUM — stale scheduler owner can release successor lease.** Accepted.
   Finally release transactionally compares runId; a delayed stale release is a
   tested no-op.

## Round 5 — primary review of revision 5

Verdict: **ITERATE**. Two residual findings; both accepted into revision 6.

1. **HIGH — impossible pre-read external/internal decision.** Accepted. Only
   structural replacement shape is validated pre-DB. The transaction reads the
   user root/original, decides the stored branch, rejects internal replacement
   with zero writes, and reads catalog/move inputs inside the same transaction.
2. **HIGH — pair validation permits stale mandatory A2 fields.** Accepted. The
   shared validator now requires the complete nonterminal owner/action/evidence-
   bearing trigger/resume/copy contract. State builders replace rather than
   merge fields; vendor/external/undo paths have exact maps and fail closed when
   truthful trigger evidence is unavailable.

## Revision 6 review

The reviewer first identified three residual executable-spec gaps; all were
accepted without changing scope:

1. Reactivation cleared disposition but retained stale deferred obligation
   fields. Accepted. One exact Upcoming builder now clears the current
   owner/action/trigger/resume state for both date and event wakes; durable event
   high-water holds the audit evidence.
2. The amendment USER_ACTION map and undo map were underspecified. Accepted.
   External replacement now requires distinct amendmentAction and verification
   trigger/resume descriptors, with exact server-derived owner/action/copy maps
   and full-map tests.
3. Operation replay conflicted with reset/original preconditions. Accepted.
   Non-reset transactions read the operation record first; exact replay is a
   read-only result even during reset or after task deletion, while drift fails
   before root/original reads.

A final wording residual made the two descriptors appear optional. Corrected:
both are required as a pair whenever replacement is present and both participate
in the pre-DB evidence validation matrix.

Final verdict: **APPROVE**. No new or residual material findings at revision 6,
SHA-256
`f0780a9d4e1aff072c3f8ed3d9ef617a5108875774c58379c77f5d84ace012ac`.

## Execution diff review — implementation-loop addendum

Execution used separate read-only Swift and Node adversarial reviewers. Findings
were returned to the owning workstream with a failing regression first; the
complete accumulated diff was re-reviewed after each correction. This addendum
records two manifest additions required by those findings:
`Peezy 4.0/MainInterface/Models/WorkflowService.swift` and
`Peezy 4.0/Tasks/FlowEngine/FlowProgressSession.swift`. It also binds the
existing `getWorkflowQualifying.js` surface to durable workflow-submission
idempotency. These additions do not change the Phase 1 product scope.

### Node review rounds

1. **ITERATE.** Corrected Timestamp fingerprint normalization, callable date
   conversion, missing scheduler pagination cases, expired prior-contract
   validation, unconditional `a2_` immutability, assessment move-date fallback,
   and reset lease/checkpoint coverage.
2. **ITERATE.** Corrected raw trigger validation ordering, null/nonfinite
   evidence bounds, reused-amendment baseline snapshots, and mixed-terminal
   scheduler cursor/wrap coverage.
3. **ITERATE.** Canonical `t2_` reuse returned the new invocation's due date
   rather than the persisted task result. A red test proved the mismatch;
   replay now returns exact persisted metadata across changed time/move inputs.
4. **ITERATE.** Cleanup-failure review exposed a non-idempotent vendor workflow
   submission boundary. The callable now accepts an optional bounded token,
   hashes authenticated UID + token into a deterministic document, fingerprints
   canonical payload, returns the exact stored result on replay/concurrency,
   rejects drift with zero writes, and preserves tokenless legacy behavior.
5. **ITERATE (P0).** The first legacy branch passed explicit `undefined` to
   Firestore `doc()`. Strict fakes now reject that SDK-invalid call and the
   production branch uses the true zero-argument auto-ID API.
6. **APPROVE.** No material Node, scheduler, index, or rules finding remained.

### Swift review rounds

1. **ITERATE.** Corrected unawaited terminal cleanup, stale/uncontrolled
   BusinessSearch resolution, identity reuse after clear/edit, weak byte/retry
   acceptance tests, and lax TaskPlan response decoding.
2. **ITERATE.** Made the Firestore transaction body/access seam nonisolated and
   background-safe; corrected submit-success/cleanup-failure retry behavior;
   fixed the exact server-valid supersession evidence descriptors.
3. **ITERATE.** In-memory submit state was not durable and queued progress could
   rewrite cleared fields. Added the server token integration plus a terminal
   barrier that rejects new persistence and drains the serialized write chain
   before clear.
4. **ITERATE.** Added a persisted per-flow attempt UUID so Retake/regeneration
   starts a new submission lifecycle, canonicalized Set-backed answer arrays,
   and blocked FindCleaners mutation through submission/cleanup failure.
5. **ITERATE.** The attempt UUID was queued but not required durable before the
   callable. Added a pre-submit barrier that locks the flow, drains persistence,
   verifies the exact persisted attempt ID, and prevents submission on failure.
6. **APPROVE.** The reviewer confirmed all four submitters await the durable
   attempt identity, the post-submit clear barrier remains ordered, and no
   material Swift/client finding remained.
