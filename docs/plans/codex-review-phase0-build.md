# Plan under review: Phase 0 build (H7 + H8) with audit checklist

Source: user-issued task, 2026-08-26. Revision 4.1 (after consensus rounds
1–6; owner-directed simplification in round 4 returned the H8 design to
surgical scope with an owner-accepted residual-risk register; rounds 5–6
added the cross-account `expectedUserId` binding, bounded spawn wait, and
verification-precision fixes).
Context documents (read in this order; they govern):
1. `PEEZY_STATE.md` (repo root) — canonical project state; outranks all other context
2. `docs/plans/BUILD_BRIDGE.md` — the build map for this work
3. `docs/plans/INSTITUTION_FLOWS_MASTER.md` — the locked design this build serves

## Task

Phase 0 from BUILD_BRIDGE.md, plus its audit checklist, with a codex review pass
before finalizing. Nothing more. Phase 0 is defined by BUILD_BRIDGE as
**"small, surgical … no visible features"** — that definition governs design
arbitration in this plan.

**Recorded scope amendment (owner-issued):** the owner's task bounds this
session to the audit + the two Phase 0 defects ("Nothing more"). BUILD_BRIDGE
§3's "deliverable = Phase 0 spec + Phase 1 spec" is superseded for this
session by that instruction; the audit still records all 8 items so the
Phase 1 spec session starts scoped.

## Owner-decision preconditions

Resolved in-session (2026-08-26, review rounds 3–4):

3. **Node runtime:** provisioning a Node 24 executable (nvm or `node@24`) is
   an approval precondition — this machine currently has only v25.2.1. Both
   Node suites run under the Node 24 binary's absolute path, recorded in the
   report, matching the deploy runtime (`engines.node = 24`).
4. **Swift test hosting:** the unit-test target is hosted (`TEST_HOST` →
   Peezy 4.0.app, project.pbxproj:582,604). Owner chose the **app test-mode
   guard**: one DEBUG-only test predicate (XCTest configuration detection)
   applied at ALL THREE startup sites — `AppDelegate`, `PeezyV1App.init`,
   and the body's `SubscriptionManager.shared` references — skipping
   Firebase configure, Messaging, Crashlytics, and the StoreKit transaction
   listener under test. `PeezyV1App.swift` joins the manifest for this guard
   only. The guard is bootstrapped GREEN FIRST: test (s) with subsystem
   probes (Firebase nil; no StoreKit listener started; no Messaging
   delegate) passes before any hosted red test runs. Production behavior is
   unchanged by construction (predicate inert outside XCTest).
5. **Design altitude (round-4 decision, amended round 5):** the owner
   directs the surgical H8 design below and **accepts the residual-risk
   register** in place of reservation leases, cancellation tombstones, a
   durable credit ledger, and persisted operation state. Those remain
   available to Phase 1 if the residuals ever matter in practice. (The
   round-4 rejection of a SpawnService API change was withdrawn in round 5:
   the optional `expectedUserId` field IS adopted — see the H7 section and
   retired residual R3.)

Resolved at final plan approval (2026-08-26, owner decision):

1. **PEEZY_STATE regeneration: DEFERRED.** The owner explicitly defers the
   §4 regeneration of sections 1–3. The build report must flag H7/H8 rows
   (and any other row its changes touch) as stale and record the
   regeneration as owed to a dedicated full-evidence session. This is the
   exact owner amendment the addendum requires — not a report-time request.
2. **Simulator-build authorization: GRANTED.** The owner authorizes this
   task's `xcodebuild` invocations exactly as the standing spec-01 build
   gate already runs them, including the checked-in `[Firebase] Crashlytics`
   run-script phase (`Crashlytics/run`, dSYM inputs). Named target: the
   default Firebase project's Crashlytics symbol upload, build-gate builds
   only. The phase itself stays frozen.

### Part A0 — Preflight (before anything else)

- Record `git rev-parse HEAD`, full `git status --porcelain`, and
  `git hash-object` of every existing manifest file AND every
  initially-dirty path reported by porcelain (a file not yet on disk records
  the literal sentinel `ABSENT`) to the report. Known at plan time: HEAD
  (04c38c9) is three commits past the PEEZY_STATE snapshot commit (7215cf2);
  the working tree carries unrelated inventory/narration changes — untouched
  and preserved. **Closeout reconciliation:** final porcelain + hashes
  (manifest files and the initially-dirty set) are diffed against this
  baseline; any content change outside the manifest fails the closeout.
  Part C review rounds receive session-relative diffs against these hashes.
- Amend `PHASE_MANIFEST` to exactly this implementation surface:
  - `functions/spawnTasks.js`
  - `functions/tests/spawnTasks.test.js`
  - `functions/spawnTasks.test.js` (root-level contract tests)
  - `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift`
  - `Peezy 4.0/MainInterface/Models/TaskActionService.swift`
  - `Peezy 4.0/MainInterface/Models/PeezyV1App.swift` (test-mode guard only
    — owner precondition 4)
  - `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift` (failure-state
    rendering + retry affordance only)
  - `Peezy 4.0/MainInterface/Views/NudgeCardView.swift` (in-flight disable +
    failure/retry state only)
  - `Peezy 4.0Tests/PeezyNudgeAnswerTests.swift` (new)
  - plus the report/plan/log files. Nothing else becomes writable.
  - `Peezy 4.0/MainInterface/Models/SpawnService.swift` (optional
    `expectedUserId` field only — round-5 cross-account fix)
  `project.pbxproj` is NOT in scope (`Peezy 4.0Tests` is a
  `PBXFileSystemSynchronizedRootGroup`, objectVersion 77 — automatic test
  membership).
- `File.txt`: transient build-gate placeholder only — created only if absent
  (`[ ! -e File.txt ]`), removed via a cleanup trap that runs on success,
  failure, or interrupt, per the Build 25 pattern. Never committed.
- Toolchain: resolve the Node 24 binary (precondition 3) and record its
  absolute path and `--version` output; halt if unavailable.

### Part A — Audit (read-only, before any code)

Work through all 8 items in BUILD_BRIDGE.md §3. For each, record findings
with file:line evidence AND a disposition (`SUPPORTED` / `CONTRADICTED` /
`UNKNOWN`) against the assumption it scopes. Do not skip items even if they
seem unrelated to Phase 0 — they scope Phase 1.

**Gate:** items whose evidence touches the two Phase 0 surfaces (item 7
always; any other item whose findings land on `functions/spawnTasks.js` or
the nudge-answer path) must resolve `SUPPORTED`. A `CONTRADICTED` **or
`UNKNOWN`** disposition on a load-bearing item STOPS the session before
Part B. Items that only scope Phase 1 record evidence and do not gate.

### Part B — Phase 0 implementation

#### 1. H7 — spawn idempotency race (`functions/spawnTasks.js`)

Defect: the token existence check (`spawnTasks.js:164-167`) precedes the
write batch; the token write (`:209`) is a plain `set`; task doc IDs are
random (`:185`). Concurrent same-token calls both pass the check and both
commit.

Fix shape:
- **Input validation before any read** (extends `validateRequest`):
  - Token AND every catalog `taskId` validated as Firestore document IDs:
    UTF-8 length ≤ 256 bytes, no `/`, not `.` or `..`, no `__…__` reserved
    form — violation → `invalid-argument` (typed contract, never an SDK
    path error from reference construction).
  - String caps: `source.id` ≤ 256 bytes; `titleParams.institution` ≤ 512
    bytes. Caps: spawns ≤ 20 per request; answers ≤ 200 keys; total
    canonical request serialization ≤ 48KB; nesting depth ≤ 4. Over-limit →
    `invalid-argument`, nothing read or written.
  - **Cross-account binding (round-5 fix):** optional `expectedUserId`
    string (≤ 128 bytes). When present and ≠ `request.auth.uid` →
    `failed-precondition` BEFORE any read or write. Old callers that omit
    it are unaffected; the nudge path always sends the operation UID
    captured at entry, so an auth switch mid-operation makes the spawn fail
    cleanly instead of writing the task into the new user's account.
    `expectedUserId` is excluded from the request fingerprint (same intent,
    same fingerprint).
- Catalog and moveDate reads stay before any write (unknown catalog id
  still rejects with nothing written).
- **One mixed atomic batch:** token doc via `create()` (fails on exists),
  task docs via `create()`, and the existing `moveAnswers/answers` write
  **retained as `set(..., {merge:true})`** (that fixed-ID doc legitimately
  pre-exists). Batch atomicity means a losing concurrent call applies none.
- **Deterministic request-instance task IDs, versioned:** doc ID = `t1_` +
  first 40 hex chars of SHA-256 of `"${token}|${ordinal}"`. Request-instance
  identity is NOT cross-request dedup (repeated catalog taskIds across
  requests stay legitimate, e.g. per-provider `UPDATE_INSTITUTION`,
  FlowEngineView.swift:682-710) and is distinct from Phase 1's future
  subject-aware `canonicalTaskKey` (audit item 7 records the touchpoints;
  not implemented).
- **Request fingerprint, versioned, checked on BOTH replay paths:**
  fingerprint = `f1_` + SHA-256 hex of canonical JSON of
  `{source, spawns, answers}` (recursive key-sort). Fast path and
  create-failure path both compare: match → stored result, zero writes;
  mismatch → `failed-precondition`, zero writes. Legacy tokens without a
  fingerprint keep today's behavior (stored result).
- Documented limitation: `firestore.rules:43-48` recursive owner grant makes
  `spawnTokens` owner-writable (no new capability vs. direct owner task
  writes); narrowing belongs to the H21 rules pass (BUILD_BRIDGE §1d).
  Recorded as Phase 1 input (residual R4).

#### 2. H8 — detached/swallowed nudge status writes (client) — surgical form

Defect: `PeezyHomeViewModel.answerNudge` (`:338-373`) detaches the "No"
status write and advances immediately; the "Yes" path awaits
`TaskActionService.setStatus` (`:81-90`), which swallows errors internally.

Fix shape:
- **One transaction-backed claim API** in TaskActionService, behind an
  injected transaction-runner protocol (production default = Firestore;
  tests use a fake runner or `demo-*` emulator):
  `claimNudgeTerminal(userId, taskId, choice, opId) → ClaimResult` — the
  transaction moves the task to the terminal status for `choice`
  (`Dismissed` / `Converted`) only if currently nonterminal, stamping
  `answeredBy {choice, opId}`; results: `.won` /
  `.alreadyTerminal(choice, opId)` / typed thrown failure
  (`missingIdentity` on empty ids — movers throwing-core precedent). The
  legacy swallowing `setStatus` remains for callers outside this surface.
- **Choice-aware accounting (round-4 F1):** dose credit and
  `completedThisSession` increment happen ONLY for a Converted (Yes)
  outcome — `.won`, or `.alreadyTerminal` carrying MY opId with choice
  Converted (retry-after-ambiguity, credited at most once per operation).
  Dismissed NEVER credits, on any path including retries.
- **Flows:** "No" → awaited `claimNudgeTerminal(.dismissed)`. "Yes" →
  awaited spawn (existing deterministic token `"\(task.id)-convert"`,
  idempotent under the H7 fix) → awaited `claimNudgeTerminal(.converted)`.
- **Outcome semantics:**
  - `.won` → (Yes only: haptic + credit) → local removal → advancement.
  - `.alreadyTerminal(myOpId, .converted)` → my earlier claim landed:
    credit once, remove, advance.
  - `.alreadyTerminal(other)` → answered elsewhere: no credit, remove
    locally, advance. (See residual R1 for the Yes-vs-No race outcome.)
  - Thrown failure (offline included — Firestore transactions fail with an
    error offline; they are NOT queued) → `.failed(choice, phase)`: card
    stays, nothing removed, nothing advanced, no credit.
- **Failure/retry, no cancel path:** `.failed(choice, phase ∈ {preSpawn,
  postSpawn, claim})` offers SAME-CHOICE retry only. Any spawn error —
  including ambiguous transport/timeout/unparsable-response failures where
  the backend may have committed — is retried by same-token replay, which
  is safe in both worlds (H7 replay contract). There is deliberately no
  cancel/release affordance and no opposite-choice switch after an attempt
  starts: strictly conservative, and it removes the reservation machinery
  wholesale.
- **Bounded wait — both awaits:** the awaited claim races an
  injected-clock bound (~10s) into `.failed(choice, .claim)` (retryable).
  If the timed-out attempt actually won, the retry observes
  `.alreadyTerminal(myOpId)` and settles correctly (credit once for
  Converted; none for Dismissed). The awaited SPAWN gets its own injected
  bound (~15s — Firebase's default callable timeout is 70s, which would
  lock both choices for over a minute on a stalled call): a spawn timeout
  is just another ambiguous error → `.failed(.yes, .preSpawn)`,
  same-choice same-token replay only; the abandoned call is
  cancellation-insensitive and its late success is absorbed by the replay's
  idempotency.
- **Single-flight per instance:** `.idle / .inFlight(choice) / .failed(…)`;
  both NudgeCardView buttons disabled while in flight.
- **Injected seam:** transaction runner, spawn service, UID provider, clock
  — initializer-injected with production defaults
  (`PeezyHomeViewModel.swift:147-149` currently hard-codes services;
  `init(previewViewModel:)` exists). One operation UID is captured at entry
  and used for the claim and ALL local accounting.

#### Residual-risk register (owner-accepted, precondition 5; each is a
#### documented non-goal of Phase 0 and a Phase 1 candidate)

- **R1 — Two-instance Yes-vs-No race:** tab-away destroys Home's
  locally-owned ViewModel (PeezyHomeView.swift:24); a second instance can
  claim Dismissed while the first instance's Yes spawn is in flight. Result:
  a spawned task exists behind a Dismissed nudge. Severity: rare
  single-user self-race; the task was affirmatively requested by the Yes
  tap; recoverable by normal task dismissal; double credit is impossible
  (claim transaction is the single authority). Strictly better than the
  pre-fix behavior on every axis.
- **R2 — Crash between claim-won and local credit:** at most one local dose
  count is lost (UserDefaults UX counter, not data or billing). No durable
  per-UID operation ledger in Phase 0.
- **R3 — RETIRED (round 5):** the auth-switch spawn-binding gap was
  re-assessed as cross-account state pollution (account B would receive
  A's unsolicited task) and is now FIXED via the `expectedUserId` binding
  in the H7 section — no longer an accepted residual. Local accounting
  additionally always uses the captured operation UID (test p2).
- **R4 — `spawnTokens` owner-writable** (rules wildcard): carried from
  round 1; H21 rules pass owns it.

#### Acceptance matrix (red tests first; each row is a named test)

H7 (Node, both suites kept green; fake or `demo-*` emulator with faithful
atomic create semantics — `create()` fails on existing doc, batches
all-or-nothing):
- (a) Two interleaved same-token calls past the read phase before either
  commits (barrier) → exactly one commit applies; the other fails
  `ALREADY_EXISTS`, rereads the token, returns the stored winner result;
  exactly N task docs + 1 token doc; reread-finds-no-token propagates the
  error.
- (b) Replay after success (fast path) → stored result, zero new writes.
- (c) Same token, different payload, sequential → `failed-precondition`,
  zero writes — on BOTH the fast path and the create-failure path.
- (d) Same token, different payloads, barriered-concurrent → winner-only
  tasks and answers; loser gets `failed-precondition`.
- (e) Legacy token doc without fingerprint → stored result returned.
- (f) Pre-existing `moveAnswers/answers` doc → batch succeeds, answers
  merged.
- (g) Task-doc ID collision → whole batch fails closed; no partial write.
- (h) Boundary validation: 21 spawns; oversized/over-deep answers; token
  with `/`, 257-byte token, `.`, `__x__`; invalid catalog taskId as doc ID;
  oversized `source.id`/`institution`; >48KB canonical request →
  `invalid-argument` before any read.
- (h2) `expectedUserId` ≠ auth uid → `failed-precondition` before any
  read; omitted → unaffected; present-and-matching → normal flow; excluded
  from the fingerprint (same intent replays identically with or without
  it); non-string value, 129-byte value, and multibyte-boundary value →
  `invalid-argument` with zero database access.
- (i) Unknown catalog id → `not-found`, nothing written.
- (j) Canonicalization: key order invariance; value sensitivity.

H8 (Swift, `@MainActor` tests in `Peezy 4.0Tests/PeezyNudgeAnswerTests.swift`
against the seam, with injected clock and transaction runner):
- (s) FIRST, guard bootstrap: under XCTest the app skipped Firebase
  configure, Messaging, Crashlytics, and the StoreKit listener — subsystem
  probes at all three guard sites (owner precondition 4). Green before any
  red test runs.
- (k) "No" claim throws → task not removed, `.failed(.no, .claim)`, no
  advancement, no credit, dose counters unchanged.
- (k2) "No" succeeds → Dismissed, removal, advancement, ZERO credit
  (choice-aware accounting; includes the retry path).
- (l) "Yes": spawn succeeds, claim throws → no credit, no removal,
  `.failed(.yes, .postSpawn)`, same-choice retry only; retry replays spawn
  (same token) then re-claims.
- (l2) "Yes": spawn fails (including ambiguous transport error) →
  `.failed(.yes, .preSpawn)`, zero claims/credit/removal/advancement;
  same-choice retry only — no cancel, no "No"; retry is a same-token
  replay.
- (m) Double-tap while in flight → exactly one spawn, one claim, one
  credit, one advancement.
- (n) Fresh instance answers a nudge another actor already claimed →
  `.alreadyTerminal(other)`: removal + advancement, no credit, no double
  credit anywhere (the residual-R1 surrogate).
- (o) Claim timeout via injected clock → `.failed(.yes|.no, .claim)`
  within the bound, no advancement; retry after the first attempt actually
  won → `.alreadyTerminal(myOpId)`: Converted credits exactly once,
  Dismissed credits never.
- (p) Missing auth / empty task id / missing `nudgeSpawnsId` → explicit
  error state, nothing advanced.
- (p2a) Auth switch BEFORE the spawn resolves → the spawn (carrying
  `expectedUserId` = captured UID) is REJECTED server-side; nothing lands
  in the new user's account; no claim or accounting runs; card in
  `.failed(.yes, .preSpawn)`, same-choice retry only.
- (p2b) Auth switch AFTER spawn success, before the claim → the claim and
  ALL local accounting are verified (via the fake runner and UID provider)
  to use the captured operation UID; nothing writes to or credits the new
  user.
- (p3) Held spawn past the injected ~15s bound, using a manually-resumable
  cancellation-insensitive fake → `.failed(.yes, .preSpawn)` at the bound
  with ONLY same-choice retry exposed (no "No", per the no-cancel rule);
  no advancement; then the fake's late success is resumed and discarded
  locally, the user retries, and the replay is asserted to yield exactly
  one task, one claim, and at most one credit.
- (q) Happy paths both branches → claim persisted before haptic, credit,
  removal, advancement.
- (r) Claim API with empty ids → throws typed `missingIdentity`.

Test infrastructure constraints: pure-logic fakes preferred; emulator use
pinned to a `demo-*` project id, no credentials. No production-connected
tests (binding addendum; guard test (s) enforces it for hosted runs).

#### Regression (all must pass before Part C) — literal commands

- `<abs-path-to-node24> --test functions/tests/*.test.js` and
  `<abs-path-to-node24> --test functions/*.test.js` (root
  `functions/spawnTasks.test.js` is outside the tests/ glob).
- Swift tests:
  1. `xcrun simctl list devices available --json` → select an available
     iPhone simulator **by UDID**; record UDID + name.
  2. `xcodebuild test -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0"
     -destination 'platform=iOS Simulator,id=<UDID>'
     -only-testing:"Peezy 4.0Tests/PeezyNudgeAnswerTests"
     -resultBundlePath ~/Downloads/peezy-reports/artifacts/PHASE0-<UTC
     timestamp>.xcresult` (path must not pre-exist).
  3. `xcrun xcresulttool get test-results tests --path <bundle>` (the
     `summary` subcommand does not list passing-test identifiers) →
     recursively extract every Test Case node and set-compare the LITERAL
     full XCTest identifiers (`Peezy 4.0Tests/PeezyNudgeAnswerTests/
     test…()`) against the roster file the build session records when the
     red tests are written (one literal identifier per matrix row
     s,k,k2,l,l2,m,n,o,p,p2a,p2b,p3,q,r; the roster file ships in the
     report) — exact set equality AND per-test passed status, not just
     exit status.
- Full simulator build:
  `xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0"
  -destination 'generic/platform=iOS Simulator' build` → `BUILD SUCCEEDED`,
  with the guarded File.txt placeholder + trap (Part A0), under the owner
  authorization from precondition 2.

### Part C — Codex review loop (before finalizing)

Mechanism: fresh `codex exec -m gpt-5.6-sol` sessions in read-only sandbox
(`-s read-only` / `-c sandbox_mode="read-only"` on resume). Blocking
severities: CRITICAL and HIGH. Reviewers receive the session-relative diff
against the Part A0 hashes, the report draft, AND the residual-risk register
with its owner acceptance — findings that re-litigate an accepted residual
without new severity evidence are answered from the register, not by scope
expansion.

Attack surface: create-guard correctness under concurrency (retries, partial
failure, token reuse, fingerprint on both paths, answers-merge exception,
ID validation); claim correctness (choice-aware credit, alreadyTerminal
paths, timeout-retry settlement); UI deadlock/actor-isolation/slow-network
UX vs the bug fixed; any call site still swallowing errors; test quality
(interleaving and atomic-create fidelity proven, not asserted). After every
accepted change: focused tests + both Node suites + simulator build before
the next round. A fix that would exceed the Part A0 manifest stops the loop
for owner amendment. Record the full exchange in the report.

## Constraints (binding, from PEEZY_STATE.md §4 and its addendum)

- No deploys, no live seeds, no production-connected tests, no
  billing/StoreKit operations. Tests: `demo-*` emulator or pure logic; the
  hosted Swift run is production-disconnected via the precondition-4 guard,
  proven by test (s) before red tests.
- Test-driven: red → green → full regression → simulator build.
- Nothing outside the Part A0 manifest is touched.
- The 4 stale `File.txt` pbxproj references are not fixed; the guarded
  placeholder pattern is the only accommodation.

## Close-out and report

Write the checkpoint report to `~/Downloads/peezy-reports/PHASE0_BUILD.md`:
audit findings (8 items, file:line, dispositions), preflight snapshot (HEAD,
porcelain, hashes incl. `ABSENT` sentinels and initially-dirty paths),
red/green evidence, codex exchange summary, full regression results (parsed
xcresult roster, recorded tool paths/UDID), closeout reconciliation, files
changed with per-file diff counts, the residual-risk register with owner
acceptance, and the H7 rules-limitation note as Phase 1 input.

Label the outcome honestly: **"local implementation only — production
unchanged"** — nothing is deployed; deployed functions retain the H7 race
until a human-run deploy, and **no Functions packaging or deployment may
occur until H43 (CRITICAL, deploy-blocking) receives sign-off.** The report
records the owner's precondition-1 decision (deferral vs regeneration of
PEEZY_STATE).

## Reviewer pushback (deliberate rejections, rounds 1–4)

- R1-F1/R2-F1 (partial): no second pre-implementation consensus review —
  this review is that gate; audit STOP-gate + Part C cover residual risk;
  Phase 1 spec exclusion is a recorded owner scope amendment.
- R1-F4: rules narrowing deferred to the H21 pass (reviewer accepted in
  round 2); residual R4.
- R2-F6 (bounded): deterministic task IDs kept per the owner's instruction;
  simpler-alternative steelman recorded; versioned encodings + tests
  adopted.
- R2-F11 → R3-F4: the transaction-runner injection was adopted in round 3
  (earlier rejection withdrawn and logged).
- R4-F1 accepted (choice-aware credit). R4-F2 accepted in simplified form
  (no cancel path at all; ambiguous spawn errors → same-token replay only).
  R4-F9 accepted (three-site guard + probes + bootstrap-first). R4-F10
  accepted (full ID/string/size validation). R4-F11 accepted (UDID
  selection, literal commands, roster equality, dirty-path hashing).
- R4-F3/F7 superseded: no reservations exist in revision 4 — nothing to
  fence, no `.blockedByReservation` state needed; the Yes-vs-No overlap is
  residual R1, owner-accepted.
- R4-F4/F5 rejected as Phase-0 machinery (owner precondition 5): no
  persisted operation state, no durable credit ledger — the protected
  quantity is a local UX counter (residual R2), not data or billing;
  within-instance opId dedup suffices for the timeout-retry path.
- R4-F6 → R5-F1 (deferral withdrawn): round 5 demonstrated the auth-switch
  race is cross-account state pollution (account B receives A's unsolicited
  task), which fails the register's own severity standard. The
  `expectedUserId` binding is adopted; `SpawnService.swift` joins the
  manifest for that field only. Logged as a corrected position.
- R4-F8 partially superseded: reservation-boundary tests dropped with the
  reservations; the surviving crash/timeout boundaries are tests (o), (n),
  (l), (l2).

## ADR — consensus review outcome (2026-08-26)

- **Decision:** execute Phase 0 as specified above — audit-gated, two
  surgical fixes (H7 atomic create-guard with fingerprint + expectedUserId
  binding; H8 awaited choice-aware claim with single-flight UI and bounded
  waits), TDD with the 24-row acceptance matrix, diff-review loop before
  finalizing, honest close-out labeling.
- **Status:** accepted by owner at chain-budget exhaustion (6 Sol rounds,
  final verdict ITERATE on drafting-text only, zero unresolved
  disagreements). No formal APPROVE stamp exists; the full exchange is in
  `codex-review-phase0-build-review-log.md`.
- **Drivers:** PEEZY_STATE §3 flags H7/H8 as HIGH; BUILD_BRIDGE makes them
  Phase 0 blockers for the entire disposition/notification model ("truth in
  the state layer"); Phase 0's governing definition is "small, surgical, no
  visible features."
- **Alternatives considered:** (1) reviewer's round-4 full-machinery design
  (reservation leases, cancellation tombstones, durable per-UID credit
  ledger, persisted operation state) — rejected by owner precondition 5 as
  Phase-1-grade for the protected quantities involved; residuals R1/R2
  documented and accepted instead. (2) Reviewer's round-2 steelman (atomic
  token create with random preallocated task refs, no deterministic IDs) —
  recorded as a valid simpler option; owner's task text kept deterministic
  identities. (3) ViewModel hoisting for cross-instance safety — rejected;
  the claim transaction is the authority instead.
- **Why chosen:** closes both defects with the smallest surface that is
  strictly better than the status quo on every failure axis, keeps every
  cross-account and money/data-relevant hazard fixed (expectedUserId,
  choice-aware credit, no-cancel ambiguity rule) while accepting only
  cosmetic/self-race residuals, and preserves the frozen surfaces and
  no-deploy constraints.
- **Consequences:** deployed functions retain the H7 race until a human-run
  deploy (blocked on H43 sign-off); PEEZY_STATE §1/§3 rows H7/H8 go stale on
  merge (owner precondition 1 governs); residuals R1/R2/R4 carry to Phase 1;
  the H21 rules-narrowing and subject-aware key design consume the audit's
  item-7 notes.
- **Follow-ups:** Phase 1 spec session (dispositions/contract
  field/supersession/subject keys) consumes the 8-item audit; H21 rules
  pass narrows the `spawnTokens` wildcard; Phase 1 revisits R1/R2 if
  telemetry ever shows them mattering.
