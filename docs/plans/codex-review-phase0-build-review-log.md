# Plan Review Log: Phase 0 build (H7 + H8) with audit checklist

MAX_ROUNDS=3, BUDGET=6 chain rounds, strict=false, reviewer model=gpt-5.6-sol, codex-cli 0.147.0.

Plan file: `docs/plans/codex-review-phase0-build.md`
Run scratch dir: `/private/tmp/claude-501/-Users-adampowell-Desktop-Peezy-4-0/3e821ee6-5dea-4613-b43d-bdaedfc999fa/scratchpad/codex-review.8D1N5S`

## Round 1 — Codex (thread 01a03d03-56c3-7bd2-a6c8-bfb25f2131c4)

1. [HIGH] The audit does not gate implementation. `BUILD_BRIDGE.md:3,66,76` requires audit → executable Phase 0/1 specs, but the plan proceeds directly from evidence collection to code.  
Fix — Require an eight-row `SUPPORTED/CONTRADICTED/UNKNOWN` checkpoint and another consensus review before implementation; any relevant unknown or contradiction stops the build.

2. [HIGH] Neither fix has complete testable acceptance criteria; “review later” is not a substitute.  
Fix — Add an acceptance matrix covering H7 concurrency, replay, mismatched reuse, atomicity and collisions, plus H8 No/Yes failures, spawn-success/status-failure retry, double taps, unchanged counters/queue on failure, and exactly-once advancement.

3. [HIGH] “Deterministic task identities” is undefined and conflicts with legitimate repeated task IDs and deferred subject-aware keys. One flow intentionally expands `UPDATE_INSTITUTION` once per provider (`FlowEngineView.swift:682-710`), while Phase 1’s canonical key still needs subject/institution design.  
Fix — Either define a versioned request-instance ID using token plus spawn ordinal, distinct from future `canonicalTaskKey`, or amend the recommendation and use the simpler atomic `batch.create(tokenRef)` guard with current auto-generated task IDs.

4. [HIGH] The H7 guard remains client-tamperable. `spawnTokens` falls through the owner-write grant in `firestore.rules:41-47`, so a client can precreate, alter, or delete a token and defeat idempotency.  
Fix — Add `spawnTokens` to the recursive-rule exclusion, deny client writes explicitly, add emulator rules tests, and require rules deployment before any later `spawnTasks` deployment.

5. [HIGH] Token-reuse, legacy, and collision behavior is unspecified. Existing code returns any stored result without comparing payloads (`spawnTasks.js:164-167`), while deterministic `set()` could overwrite an existing task’s status/progress.  
Fix — Store a canonical request fingerprint, reject same-token/different-payload reuse with zero writes, preserve legacy raw-token replay, and use create-only task writes that fail closed on collisions.

6. [HIGH] Existing H7 tests cannot prove contention, and the declared regression omits `functions/spawnTasks.test.js`, which contains the repeated-task contract.  
Fix — Add an emulator or faithful barrier/retry test asserting identical concurrent results, one token, exactly N tasks and zero partial writes, then run both `functions/*.test.js` and `functions/tests/*.test.js`.

7. [HIGH] H8 cannot be test-driven through current code: `PeezyHomeViewModel` hard-codes `TaskActionService()` and inline `SpawnService()` (`PeezyHomeViewModel.swift:147-149,351-357`).  
Fix — First add a behavior-preserving injected protocol seam with characterization tests, then add failing pure `@MainActor` tests and an explicit targeted `xcodebuild test -only-testing:` command.

8. [HIGH] Awaiting writes introduces a new re-entry race. Both nudge controls remain active (`NudgeCardView.swift:35-52`), and two Yes attempts can double-credit and advance past the next card; recreating Home across tab changes bypasses a per-instance guard.  
Fix — Specify `.idle/.inFlight/.failed` state, disable both controls, and use a retained coordinator or conditional terminal claim; test held-write double taps and tab-away/re-entry produce one credit and one advance.

9. [HIGH] A direct awaited Firestore update can hang indefinitely offline: the SDK completion runs only after an online server commit. Missing auth, empty IDs, and absent `nudgeSpawnsId` also currently return silently.  
Fix — Require a typed throwing, captured-UID, online-only conditional transition with bounded retryable UX and tests for offline/timeout, missing identity, malformed metadata, and status failure.

10. [HIGH] Verification is not fail-closed against production. No emulator project is named, and the simulator build invokes the Crashlytics upload script (`project.pbxproj:283-305`), which sends build events/symbols.  
Fix — Pin emulator tests to a guarded `demo-*` project with no credentials, run Swift tests selectively, and perform the build with verified network egress disabled or an explicitly non-production Crashlytics configuration.

11. [HIGH] The plan lacks a safe dirty-worktree/manifest preflight. Current HEAD differs from `PEEZY_STATE.md`, unrelated changes exist, `PHASE_MANIFEST` omits H7/H8 paths, and the supposedly missing `File.txt` currently exists untracked.  
Fix — Record HEAD, full porcelain state and target hashes; establish an exact editable manifest; preserve unrelated changes; remove `File.txt` only if this session proves it created it.

12. [HIGH] Reviewer-loop changes are not followed by mandatory final verification, and “implement every accepted fix” can illegally expand the frozen scope. No callable `codex` skill is identified in the current environment.  
Fix — Name the independent review mechanism, define blocking severities and an editable allowlist, pause for scope amendments, and rerun focused tests, both Node suites and the safe simulator build after every final code change.

13. [HIGH] Close-out contradicts the governing protocol: the plan forbids outside edits and produces only a report, while `PEEZY_STATE.md:101-108` requires a fresh full-evidence regeneration after code changes.  
Fix — Either include the required full state regeneration in scope or obtain an explicit owner amendment deferring it; label the report “local implementation only—production unchanged” until state, H43, rules and human rollout gates close.

VERDICT: ITERATE
### Response (round 1 → revision 1)

Accepted (plan changed): F2 acceptance matrix (rows a–k added); F3 request-instance IDs = (token, ordinal), explicitly distinct from Phase-1 canonicalTaskKey and from cross-request dedup; F5 fingerprint on token docs, mismatch → failed-precondition, legacy replay preserved, all-create() fail-closed batch; F6 both Node globs in regression (root functions/spawnTasks.test.js confirmed present); F7 injected protocol seam (hard-coded services confirmed at PeezyHomeViewModel.swift:147-149) + targeted -only-testing run; F8 .idle/.inFlight/.failed with both buttons disabled (NudgeCardView confirmed always-active); F9 bounded timeout, captured UID, explicit errors on missing auth/id; F11 preflight (HEAD/porcelain snapshot, exact PHASE_MANIFEST amendment, File.txt transient-placeholder rule; the "existing" File.txt Sol saw was this session's transient build placeholder, since removed); F12 mechanism named (codex exec gpt-5.6-sol read-only), blocking=CRITICAL/HIGH, re-verification after every accepted change, scope expansion → owner pause; F13 "local implementation only — production unchanged" label + explicit owner ask on PEEZY_STATE regeneration vs deferral; F1 audit STOP-gate with per-item dispositions.

Rejected/bounded (with rationale, mirrored in the plan's Reviewer pushback section): F1's second pre-implementation consensus round (this review is that gate); F4's rules edit in Phase 0 (own-uid tampering grants no new capability vs the same rule's direct task-write grant; H21 pass owns the narrowing per BUILD_BRIDGE §1d; recorded as documented limitation + Phase 1 input); F8's retained cross-instance coordinator (per-instance guard + Firestore-truth reload sufficient); F10's Crashlytics neutering / egress-disabled build (pre-existing mandatory session build gate, frozen surface; demo-* pinning and no-credential tests accepted).

## Round 2 — Codex (same thread)

The revision closes several prior gaps: legacy replay, request-instance identity, both Node test globs, basic H8 single-flight tests, and honest no-deploy labeling. R1-F4’s rules deferral is adequately justified. Remaining/new findings:

1. [HIGH] R1-F1 remains partially unresolved: `BUILD_BRIDGE.md` requires audit before an executable spec and delivery of Phase 0 and Phase 1 specs, while this plan fixes implementation details beforehand, proceeds on load-bearing `UNKNOWN` findings, and never produces Phase 1.  
Fix — Stop on `UNKNOWN` or `CONTRADICTED` H7/H8 findings, then freeze audit-informed Phase 0 and Phase 1 specs or record an explicit scope amendment.

2. [HIGH] The “exact” manifest is not executable: it omits `PeezyHomeView.swift`, uses unnamed “new Swift test file(s),” and includes protected, already-dirty `project.pbxproj` even though its synchronized test group gives new tests automatic membership.  
Fix — Name every test path, add `PeezyHomeView.swift` and any retained-owner surface, and remove `project.pbxproj` from scope.

3. [HIGH] H7’s “all-`create()` batch” conflicts with the existing atomic merge into the fixed `moveAnswers/answers` document, which cannot be created once per token.  
Fix — Specify one mixed atomic batch: `create` token/tasks, retain `set(..., {merge:true})` for answers, and test with a pre-existing answers document.

4. [HIGH] H7 test (a) can false-pass with a weak fake: deterministic IDs leave N tasks and one token even if both batches overwrite successfully. It also does not distinguish token contention from an unrelated task-ID collision.  
Fix — Require faithful atomic-create semantics proving two initial misses, one applied commit, one `ALREADY_EXISTS`, loser token reread, and propagation when the token remains absent.

5. [HIGH] Fingerprint validation is specified only after create failure; the retained existing-token fast path can still return an unrelated stored result, and concurrent mismatched requests are untested.  
Fix — Validate fingerprints on both replay paths and add separate sequential and barriered-concurrent mismatch tests asserting winner-only tasks and answers.

6. [MEDIUM] Task-ID and fingerprint algorithms remain unversioned and underspecified. Steelman: atomic token `create` with current preallocated random task refs already closes the race with fewer migration and collision concerns.  
Fix — Adopt that simpler design through a canonical-state amendment, or define versioned SHA-256 encodings, recursive canonicalization, and map-order/collision tests.

7. [MEDIUM] H7 still accepts unbounded spawn arrays and arbitrarily large/deep answers, risking excessive catalog reads, fingerprint work, timeout, and Firestore’s batch-operation ceiling.  
Fix — Add conservative spawn-count and answer-size/depth limits with fail-before-read validation tests.

8. [HIGH] R1-F8’s rejection is unsound: switching tabs destroys Home’s locally owned ViewModel while its answer task survives; during the awaited spawn, a recreated Home can reload the still-`Upcoming` nudge and double-credit or submit a conflicting answer.  
Fix — Hoist the ViewModel to `PeezyMainContainer` or use a conditional terminal claim, then test tab-away/re-entry during held spawn and status operations.

9. [HIGH] The timeout design treats “not acknowledged” as failure even though Firestore queues the mutation locally and cancellation does not retract it; a structured task-group race may also wait forever for the cancellation-insensitive child.  
Fix — Remove abandon-and-retry timeout semantics or introduce a durable indeterminate state with explicit late-success/rejection reconciliation and cancellation-insensitive tests.

10. [HIGH] `.failed` lacks attempted-choice and phase information: after Yes-spawn succeeds but status fails, re-enabling No can dismiss the nudge while leaving the spawned task behind.  
Fix — Track choice and commit phase, expose only same-choice retry after spawn success, and test that the opposite action is unavailable.

11. [HIGH] H8 tests still bypass the original failure boundary: a fake status protocol does not prove production `TaskActionService` propagates errors, while Auth identity and timeout remain global and nondeterministic.  
Fix — Inject the production document updater, UID provider, and clock, then test actual propagation plus spawn failure, missing auth/task/spawn IDs, and late completion.

12. [HIGH] `xcodebuild test -only-testing:` is not a runnable command; the shared scheme contains production-connected unit/UI tests, and the plan also runs Node tests under an unspecified runtime despite `package.json` requiring Node 24.  
Fix — Provide exact project, scheme, destination, test identifier, result-bundle assertion, build command, and a pinned Node 24 invocation.

13. [HIGH] R1-F10’s Crashlytics rationale is unsound: the checked-in build phase launches `upload-symbols` to send build events and symbols, while the binding addendum provides no “pre-existing build gate” exception.  
Fix — Require verified outbound denial, an enumerated non-production Crashlytics target, or explicit owner authorization naming the target and upload action before any `xcodebuild`.

14. [MEDIUM] Prior dirty-worktree mitigation remains incomplete: target hashes are absent, fresh reviewers receive no baseline-relative patch, and `File.txt` cleanup is neither ownership-checked nor failure-safe.  
Fix — Record target hashes/baseline diffs, review only session-relative patches, and create `File.txt` under an ownership check and cleanup trap.

15. [HIGH] Close-out still violates `PEEZY_STATE.md`: asking for regeneration deferral in the completed report is not an owner amendment, so the session would finalize with knowingly stale canonical H7/H8 state.  
Fix — Obtain explicit deferral before implementation or include the required full-evidence regeneration before declaring completion.

16. [MEDIUM] The rollout note says only that production waits for a human deploy, omitting canonical H43’s CRITICAL Functions-packaging blocker.  
Fix — State explicitly that no Functions packaging or deployment may occur until H43 receives sign-off.

VERDICT: ITERATE
### Response (round 2 → revision 2)

Accepted (plan changed): F2 manifest fixed — PeezyHomeView.swift added (VM ownership at PeezyHomeView.swift:24 confirmed), test file named, project.pbxproj REMOVED (Peezy 4.0Tests is a PBXFileSystemSynchronizedRootGroup, objectVersion 77 — auto membership verified); F3 mixed atomic batch retaining set-merge for moveAnswers/answers + test (f); F4 strengthened concurrency test (a): faithful atomic-create fake, ALREADY_EXISTS assertion, loser reread, token-absent propagation; F5 fingerprint on BOTH replay paths + sequential (c) and barriered-concurrent (d) mismatch tests; F6 versioned encodings t1_/f1_ SHA-256 + canonicalization/order/collision tests (j),(g); F7 input caps (spawns ≤20, answers ≤200 keys/32KB/depth 4) validated before reads + test (h); F8 conditional-terminal-claim adopted (reviewer's own alternative) as single-credit authority across VM recreation — tab-switch destruction confirmed at PeezyMainContainer switch + PeezyHomeView.swift:24 — + re-entry test (n); F9 indeterminate timeout (no abandonment claim, queued-mutation honesty, late-success → already-answered, injected clock) + tests (o); F10 choice+phase in failure state, same-choice-only retry post-spawn + test (l); F11 UID provider + clock injection + typed-error test (r) of the production wrapper; F12 exact xcodebuild test command with -only-testing + result-bundle count assertion + Node 24 pin; F14 target hashes, session-relative diffs to reviewers, guarded File.txt creation + cleanup trap; F15 regeneration decision moved BEFORE implementation as owner-decision precondition 1 at the approval gate; F16 H43 packaging-blocker sentence added to close-out; F1 gate now stops on UNKNOWN as well as CONTRADICTED for load-bearing items, Phase-1-spec exclusion recorded as owner scope amendment (reviewer's alternative fix).

Rejected/bounded (rationale in the plan's Reviewer pushback): F6 steelman (simpler random-ref design) recorded as an owner option, deterministic IDs kept per the owner's explicit instruction; F8 ViewModel hoisting rejected (structural refactor beyond surface) in favor of the adopted claim; F11 full production-updater DI rejected (thin precedented wrapper, movers throwing-core pattern; typed-error path unit-tested); F13 elevated to owner-decision precondition 2 (exact human authorization for the build gate incl. Crashlytics phase) rather than build-phase modification or egress denial.

## Round 3 — Codex (same thread; ROUND CAP REACHED)

Revision 2 resolves the prior H7 blockers, audit gate, manifest/project membership, H43 warning, and both owner-decision preconditions. Remaining findings:

1. [HIGH] Yes still spawns before acquiring the conditional claim, so another ViewModel can claim No while spawn is pending, leaving an unwanted spawned task after Yes loses; test (n) does not exercise this overlap.  
Fix — Atomically reserve the answer choice before spawning, finalize Converted afterward, and test held-spawn Yes-versus-No contention with zero orphan tasks.

2. [HIGH] Timeout accounting permanently loses credit: test (o) forbids the late winning operation from crediting, while its retry sees an already-terminal task and also receives no credit.  
Fix — Keep the original operation authoritative after timeout or persist a durable operation/credit marker that reconciles exactly one credit.

3. [HIGH] The timeout rationale uses incorrect Firestore semantics: transactions require connectivity, are not persisted offline, and complete with an error when offline rather than leaving a queued local mutation.  
Fix — Treat offline as a definitive failure and reserve indeterminate state for genuinely unresolved online transactions, with separate tests.

4. [HIGH] The implementation specifies incompatible persistence paths: `setStatusThrowing` is a direct `updateData`, but the actual answer transition is subsequently required to be transactional; R2-F11’s “thin wrapper” rationale therefore no longer holds.  
Fix — Define one transaction-backed `claimNudgeTerminal(...) -> ClaimResult` API and test its retry, predicate, single-winner, completion-bridge, and error behavior through an injected runner or `demo-*` emulator.

5. [HIGH] The targeted Swift test remains production-connected independently of the approved Crashlytics build gate: the unit target is hosted, so it launches `PeezyV1App`, which configures production Firebase, Messaging, Crashlytics, and the StoreKit transaction listener.  
Fix — Add an approved test-mode startup guard/emulator configuration or an unhosted pure target, with the required manifest amendment before running tests.

6. [HIGH] The Node 24 “pin” is only an assertion, while this machine currently exposes Node 25.2.1 and no Node 24 executable; implementation would stop before red tests.  
Fix — Make provision of an exact Node 24 executable an approval precondition and use its absolute path for both suites.

7. [HIGH] UID injection does not define account stability across awaits: the claim can target captured user A while `recordDoseProgress` still derives its UserDefaults key from the current Firebase user, potentially crediting user B or `anon`.  
Fix — Capture one operation UID and use it for both remote persistence and all local accounting, with an auth-switch-during-held-operation test.

8. [MEDIUM] Losing-claim behavior contradicts itself: lines 153–154 require local removal, while lines 175–176 prohibit removal and advancement for every non-winning path.  
Fix — Define outcomes separately for same-choice terminal, opposite-choice terminal, pending reservation, and genuine failure.

9. [MEDIUM] The acceptance matrix still lacks a Yes-spawn-failure test and does not define whether No remains available before any spawn succeeds.  
Fix — Add a named pre-spawn failure test asserting zero claims, credit, removal, and advancement plus explicit permitted actions.

10. [MEDIUM] Tokens remain raw `spawnTokens` document paths, but validation permits path-shaping slashes and overlong UTF-8 values that bypass the promised error contract.  
Fix — Validate Firestore document-ID constraints before constructing any reference and add boundary tests.

11. [MEDIUM] Verification remains partly placeholder-driven: no exact build command, simulator discovery command, unique result-bundle policy, expected identifiers/count, absent-file hash sentinel, or final baseline reconciliation is specified.  
Fix — Make those commands and assertions literal, use unique absent `.xcresult` paths, and compare final hashes/porcelain against the authorized baseline.

VERDICT: ITERATE
### Response (round 3 — arbiter assessment at cap)

MAX_ROUNDS=3 reached without APPROVE. Convergence check: findings are NOT restatements — they attack revision-2's own design (progress, not stall), so the cap, not convergence, is the limit hit. Arbiter verification: F6 TRUE (machine has Node v25.2.1, no Node 24 — plan's pin would halt preflight); F5 TRUE (unit-test target is hosted: TEST_HOST → Peezy 4.0.app at project.pbxproj:582,604 — Swift unit tests launch the production-configured app regardless of -only-testing). F1–F4, F7–F11 assessed valid on review (spawn-before-claim orphan window; timeout credit-loss contradiction in test (o); transactions fail offline rather than queue — rev-2's honesty text was written for updateData; setStatusThrowing/updateData vs required transaction inconsistency — consolidate into claimNudgeTerminal, reopening the bounded R2-F11 rejection legitimately; operation-UID stability; losing-claim contradiction lines 153-154 vs 175-176; missing pre-spawn failure test; token doc-ID constraints; literal verification commands). Disposition: owner consulted per protocol (accept as-is / one more round / abandon) with the two new environment decisions (test hosting strategy, Node 24 provision) surfaced explicitly.

### Owner decisions (in-session, after round 3)

Cap decision: owner chose ONE MORE ROUND (extends MAX_ROUNDS to 4; chain budget 3 of 6 spent at decision time).
Precondition 3 resolved: install/provision Node 24 (machine has only v25.2.1); suites run under its absolute path.
Precondition 4 resolved: app test-mode guard in PeezyV1App startup (hosted TEST_HOST target confirmed at project.pbxproj:582,604); PeezyV1App.swift added to manifest for the guard only; guard asserted by test (s).

### Response (round 3 → revision 3)

All 11 round-3 findings accepted; none rejected. F1 orphan window → reserve→spawn→finalize protocol (reservation blocks foreign-choice claims while live; releases on cancel pre-spawn; same-choice-only after spawn success). F2 credit loss → opId stamped in the claim; retry observing .alreadyMine grants the credit exactly once (opId-deduplicated) — never zero, never two; test (o) rewritten accordingly. F3 semantics corrected → transactions fail offline (not queued); offline = definitive retryable failure (.offline), indeterminate reserved for unresolved online timeout; tests (o)/(o2) split. F4 → one transaction-backed API family (reserveNudgeAnswer / claimNudgeTerminal / releaseNudgeReservation) behind an injected transaction runner; prior R2-F11 rejection withdrawn and logged as corrected. F5 → owner precondition 4 (guard + test (s)). F6 → owner precondition 3 (Node 24 binary). F7 → single captured operation UID for remote + local accounting; auth-switch test (p2). F8 → per-outcome semantics table (.won/.alreadyMine/.lostToOther/pending-own-reservation/failure) replacing the contradictory lines. F9 → tests (l2) pre-spawn failure with explicit allowed actions. F10 → token doc-ID validation (≤256 bytes, no '/', not '.'/'..', no __…__) + boundary rows in (h). F11 → literal discovery/build/test commands, unique non-pre-existing .xcresult parsed for exact test roster, ABSENT hash sentinels, closeout baseline reconciliation.

## Round 4 — Codex (same thread; owner-extended cap reached)

Revision 3 resolves the prior owner gates, Node provisioning, major H7 issues, hosted-test mechanism, and transaction-runner injection. Remaining findings:

1. [HIGH] Outcome semantics contradict the locked No behavior: both `.won` and `.alreadyMine` unconditionally grant dose credit, so a successful or retried No can earn credit.  
Fix — Make accounting choice-aware: Converted credits exactly once; Dismissed always removes and advances with zero dose/total credit, including timeout retries.

2. [HIGH] Test (l2) treats every spawn error as definitely pre-spawn, but the callable may commit its atomic task/token batch and then lose or return an unparsable response; releasing afterward permits No and recreates an orphan task.  
Fix — Permit cancellation only after a backend-confirmed pre-write error; treat transport, timeout, unavailable, and invalid-response failures as indeterminate and require same-token replay.

3. [HIGH] Time-only stale-reservation reclamation and cancellation are unfenced: a slow spawn may outlive the lease, or release may observe no reservation before the original timed-out reserve commits.  
Fix — Never allow opposite-choice age reclamation; require same-choice adoption/replay and use an acknowledged cancellation tombstone or generation fence.

4. [HIGH] A UUID held only by the ViewModel cannot remain stable across the tab destruction or crash/relaunch scenarios the design claims to support.  
Fix — Persist `{uid, taskId, choice, opId, phase}` before reserving or return/adopt the existing server reservation’s opId, then reconcile it when Home is recreated.

5. [HIGH] “Exactly once” credit lacks a durable atomic mechanism; an in-memory opId set fails across instances, while separate receipt and UserDefaults counter writes leave zero-credit or double-credit crash windows.  
Fix — Define a durable per-UID operation ledger that atomically records accounting state and reconcile pending terminal operations at startup.

6. [HIGH] Capturing a UID does not bind `SpawnService` to it: the callable authenticates whichever Firebase user is current at invocation, allowing reservation under user A but spawn under user B after an auth switch.  
Fix — Send `expectedUserId`, reject unless it equals `request.auth.uid`, add `SpawnService.swift` to the manifest, and test switches before and during the callable.

7. [MEDIUM] `ClaimResult` has no explicit live-reservation outcome; `.lostToOther` denotes an already-terminal task, whereas contention test (n) is blocked by a still-nonterminal Yes reservation.  
Fix — Add `.blockedByReservation` with no credit/removal/advancement and explicit wait or same-choice continuation behavior.

8. [MEDIUM] Acceptance omits reservation adoption after recreation, lease expiry during spawn, ambiguous committed-spawn errors, release failure/timeout, and crashes around finalization and credit.  
Fix — Add named barrier/relaunch tests for each boundary and require successful release before returning to `.idle`.

9. [MEDIUM] The approved hosted-test guard should explicitly cover `AppDelegate`, `PeezyV1App.init`, and the body’s unconditional `SubscriptionManager.shared` references; Firebase being nil alone does not prove StoreKit and Messaging stayed dormant.  
Fix — Apply one DEBUG-only test predicate at all three sites, add subsystem probes, and bootstrap this guard green before running any hosted red test.

10. [MEDIUM] H7 validation still leaves raw catalog `taskId` paths and `source.id`/`titleParams.institution` unbounded, allowing SDK path errors or oversized writes after reads.  
Fix — Validate task IDs as Firestore document IDs and cap every request string or the total canonical request size before any read.

11. [MEDIUM] Verification remains partly nonliteral: simulator selection uses a potentially ambiguous name, the full-build and `xcresulttool` commands are absent, and dirty outside-manifest paths are not content-hashed.  
Fix — Select a simulator UDID, provide exact test/build/result commands and expected roster, and hash every initially dirty path at preflight and closeout.

VERDICT: ITERATE
### Response (round 4 — arbiter assessment at extended cap)

Verdict ITERATE; 6 HIGH / 5 MEDIUM; 4 of 6 chain-budget rounds spent. Findings are again responsive to the newest revision, not restatements — F1 (Dismissed earning dose credit under the rev-3 outcome table) is an outright drafting bug and is accepted unconditionally; F2 (ambiguous spawn errors: callable may commit then lose the response — release-after-ambiguity recreates the orphan) is correct; F6 (SpawnService authenticates the CURRENT Firebase user, not the captured UID) is correct.

However, the arbiter notes a trajectory problem: each round's fixes add protocol surface (reservation → lease fencing → cancellation tombstones → durable per-UID operation ledger → persisted operation state → callable API change binding expectedUserId), and round-N+1 findings increasingly target machinery introduced in round N. BUILD_BRIDGE defines Phase 0 as "small, surgical … no visible features." The aggregate H8 design is drifting toward Phase-1/2-grade distributed-state machinery to close windows that are (a) milliseconds wide, (b) single-user/single-device self-races, and (c) strictly less harmful than the pre-fix behavior (today EVERY failure advances blindly). A simpler design — awaited choice-aware terminal claim, single-flight UI, failure-stays-put, spawn idempotent by token, with the multi-instance No-vs-Yes residual DOCUMENTED and accepted (worst case: a user-requested task exists while its nudge shows Dismissed; recoverable; no double credit possible) — may better satisfy the governing "surgical" constraint. Disposition: owner consulted with that counter-proposal alongside the full-machinery path.

### Owner decision (after round 4)

Owner chose SIMPLIFY + FINAL ROUND: surgical H8 design (awaited choice-aware claim transaction, single-flight, failure-stays-put, same-token replay, no cancel path) with an explicit owner-accepted residual-risk register (R1 two-instance Yes-vs-No race → recoverable spawned-task-behind-dismissed-nudge, no double credit; R2 crash between claim and local credit → at most one lost local dose count; R3 auth-switch mid-operation spawn binding → Phase 1 candidate; R4 spawnTokens rules wildcard → H21 pass). Reservation/lease/tombstone/durable-ledger/persisted-op-state/SpawnService-API machinery rejected as Phase-1-grade for a Phase 0 defined as "small, surgical". Recorded as precondition 5.

### Response (round 4 → revision 4)

Accepted: F1 choice-aware credit (Dismissed never credits, any path — this was a rev-3 drafting bug); F2 in simplified form (cancel path deleted entirely; every spawn failure including ambiguous transport/timeout/unparsable-response → same-choice same-token replay, safe in both committed/uncommitted worlds per the H7 replay contract); F9 three-site guard (AppDelegate, PeezyV1App.init, SubscriptionManager.shared refs) + subsystem probes + guard test bootstrapped green first; F10 full ID/doc-ID/string/total-size validation before reads + boundary rows; F11 UDID-based simulator selection, literal xcodebuild/xcresulttool commands, roster-equality assertion, initially-dirty-path hashing at preflight and closeout.

Superseded by simplification: F3, F7 (no reservations exist → nothing to fence, no blocked state), most of F8 (surviving boundaries covered by tests o, n, l, l2).

Rejected under owner precondition 5 (rationale in plan pushback): F4 persisted operation state and F5 durable credit ledger (protected quantity is a cosmetic local counter → residual R2); F6 expectedUserId callable binding (manifest/API expansion for an exotic on-device race with server-side per-uid consistency intact → residual R3, Phase 1 candidate).

## Round 5 — Codex (same thread; severity-framed final)

1. HIGH — R3 is materially under-severity: if account B supplies the callable token, B receives A’s unsolicited spawned task/token while A’s captured-UID claim is denied; if auth returns to A first, A can be Converted/credited while the target exists only in B. That is cross-account state corruption, not merely internal per-UID consistency (`SpawnService.swift:30-51`, `spawnTasks.js:160-163,217-232`, `firestore.rules:43-47`).
   Fix — Pass `expectedUserId` through `SpawnService`, reject mismatches against `request.auth.uid` before all reads/writes, and add a cross-auth ownership test.

2. MEDIUM — The roster check is not executable as specified: `xcresulttool … summary` reports counts and failures but not identifiers for passing tests.
   Fix — Use `xcresulttool get test-results tests --path …` and set-compare full XCTest identifiers against a literal roster.

3. MEDIUM — Only the claim has a ~10-second bound; `SpawnService` retains Firebase’s 70-second default timeout, leaving both choices locked during a stalled Yes call.
   Fix — Add an injected spawn bound whose timeout preserves same-token-only retry semantics and test a cancellation-insensitive held spawn.

VERDICT: ITERATE
### Response (round 5 → revision 4.1)

Convergence: 13 → 16 → 11 → 11 → 3 findings. ALL THREE round-5 findings accepted; zero disagreements remain. F1: the R3 severity assessment was factually unsound by the register's own standard — an auth switch makes the callable write A's intended task into B's account (cross-account pollution) — deferral withdrawn; optional expectedUserId binding adopted (server rejects mismatch before any read/write; omitted → unaffected; excluded from fingerprint), SpawnService.swift added to manifest for the field only, residual R3 retired, tests (h2)/(p2 revised) added. F2: xcresulttool command corrected to `get test-results tests` with set-comparison of full XCTest identifiers (summary lacks passing identifiers). F3: injected ~15s spawn bound added (Firebase 70s default would lock both choices); spawn timeout = ambiguous error → same-token replay only; cancellation-insensitive held-spawn test (p3) added.

## Round 6 — Codex (same thread; confirmation round, BUDGET EXHAUSTED)

The three edits are present, but several faithfulness defects remain:

1. HIGH — Test p3 re-enables “both buttons” after an ambiguous Yes timeout, contradicting same-choice-only retry; its “never resolves” fake also cannot later produce the required late success.
   Fix — Use a manually resumable cancellation-insensitive fake, expose only Retry Yes, discard the late result locally, then assert explicit replay yields exactly one task, claim, and credit.

2. MEDIUM — `xcresulttool get test-results tests` is correct, but `(s,k,k2,…)` are row labels—not literal full XCTest identifiers.
   Fix — Enumerate the exact test identifiers and specify recursive Test Case extraction plus exact set/status comparison.

3. MEDIUM — Owner precondition 5 still says a `SpawnService` API change is rejected, contradicting the adopted manifest and `expectedUserId` contract; the header also still says Revision 4.
   Fix — Remove that rejection, label the plan Revision 4.1, and keep R3 solely as retired history.

4. MEDIUM — p2’s rejected-spawn path never reaches claim or accounting, so it cannot prove those operations retain the captured UID.
   Fix — Split p2 into pre-spawn rejection and post-spawn/pre-claim auth-switch cases.

5. LOW — h2 omits non-string and over-128-byte `expectedUserId` validation cases.
   Fix — Add type, byte-boundary, and multibyte cases asserting zero database access.

VERDICT: ITERATE
### Response (round 6 → revision 4.1 final text)

All five findings are drafting-faithfulness defects in the revision-4.1 edit text; all five accepted and applied: F1 p3 rewritten (same-choice retry ONLY — the "both buttons" phrase was a contradiction; manually-resumable cancellation-insensitive fake; late result discarded; replay asserts exactly one task/claim/credit). F2 roster mechanism made literal (recursive Test Case extraction; set-equality + per-test status against a recorded roster file of literal XCTest identifiers). F3 precondition 5 amended (SpawnService rejection withdrawn-in-place with round-5 cross-reference) and header corrected to Revision 4.1 / rounds 1–6. F4 p2 split into p2a (pre-spawn rejection) and p2b (post-spawn/pre-claim auth switch proving captured-UID claim + accounting). F5 h2 extended with non-string / 129-byte / multibyte expectedUserId cases asserting zero database access.

### Terminal state (2026-08-26)

Limit hit: CHAIN BUDGET EXHAUSTED (6 of 6 Sol rounds; round caps at 3 and 4 were owner-extended). Final Sol verdict: ITERATE — on drafting faithfulness only; no design objection stands. Convergence trajectory: 13 → 16 → 11 → 11 → 3 → 5(text-only). Unresolved disagreements: NONE — every finding across six rounds is either implemented in the plan, superseded by an owner-directed design decision, or owner-adjudicated with logged rationale; no APPROVE stamp was emitted. Disposition: owner decides accept / extend budget / abandon.

### Verdict summary

Round 1: ITERATE (13 findings) · Round 2: ITERATE (16) · Round 3: ITERATE (11) · Round 4: ITERATE (11) · Round 5: ITERATE (3) · Round 6: ITERATE (5, all drafting-faithfulness, all applied).

### Owner acceptance (2026-08-26)

Owner ACCEPTED revision 4.1 at budget exhaustion (consensus-in-substance; no APPROVE stamp — recorded honestly). ADR block appended to the plan. Execution remains separately gated on the handoff decision plus preconditions 1 (PEEZY_STATE regen defer/include) and 2 (build-gate authorization).

### Handoff (2026-08-26)

Owner: EXECUTE NOW via codex-consensus:codex-execute (fresh --budget 6 for the build session). Precondition 1 resolved: PEEZY_STATE regeneration DEFERRED by explicit owner amendment (report flags stale rows, regeneration owed). Precondition 2 resolved: build-gate xcodebuild AUTHORIZED including the checked-in Crashlytics phase, build-gate builds only. Both recorded in the plan.
