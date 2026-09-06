# HANDOFF — from the S3 close to the next session (2026-09-06)

Read first, in this order and by section only: `PEEZY_STATE.md` §4, the last entry of `tasks/todo.md`, the current brief under `briefs/`, then `STATUS.md`. The contract (`docs/plans/PHASE2_CONTRACT.md`, sha256 `1ab1c970…`) is the sole executable authority; the manifest v9 and spec v5 are archived under `docs/archive/phase2/` and are never read again (Reconciled 12: a missing shape is a contract defect to fix in the contract).

## Next work

1. S3 is closed: the diff review is at `docs/reviews/S3_DIFF_REVIEW.md` (four Sol rounds and the Swift pass, every finding fixed or dispositioned in `tasks/todo.md`); the close-out amendments S3-CD5..CD9 are in the contract (sha256 `1ab1c970…`).
2. S4 brief (recovery / privacy UI + durable deletion orchestration), written per the `PHASE2_WORKFLOW_v2.md` template with a Codex gate at the brief. S4 inherits from S3: the C9.4.5 client legacy-migration rows, the Settings `deleteAccount()` hunk (needs `Phase2ProductionRuntime.accountDeletionCoordinator`), `FirestoreRuntimeOwner` replacing `TransitionalFirestoreRuntime`, and the client halves of the C2 residual rows the S3 brief lists as "client halves remain S4's". S4 is a deletion slice: diff-reviewed at close.
3. Owner actions at the S7 pre-ship gate (see `STATUS.md`): the owner-run sealer (Build B artifact), the observer wiring, the deploys.

## Commands and environment

- Node is node@24 by explicit path: `/opt/homebrew/opt/node@24/bin/node`; never PATH node. Java for the emulators: `/opt/homebrew/opt/openjdk@21/bin` (the emulator script exports both).
- Offline Node envelope: the C10.9 command in the contract, restricted to the files that exist today, plus `functions/tests/accountDeletionFence.test.js`. There is no `npm test` script.
- Emulator runs (`demo-peezy-phase1` only; never production): `scripts/test-emulator.sh node | rules | swift`. Runs share the emulator ports, so chain them in one background script with a `.done` marker and wait once; do not run two at a time.
- Swift: one `xcodebuild build-for-testing` per session with project signing (simulator `DC0CC10C-6DB0-496A-8B0E-51E60D958A27`, iPhone 17 Pro); the test script's summary line is `Test run with N tests in M suites passed`. Disk is chronically low: one DerivedData at a time.
- `PHASE_MANIFEST` is enforced by `.claude/hooks/pre_tool_use.py`: a new file must be listed before it is written. `STATUS.md`, `HANDOFF.md`, `docs/reviews/S3_DIFF_REVIEW.md`, `functions/tests/support/*.js`, `functions/scripts/*.js`, and `logs/*` are listed.
- Logs live under `logs/` (gitignored); the S3 RED, deliberate-break, GREEN, offline, and emulator logs are indexed in `~/Downloads/peezy-reports/S3_GATE/S3_LOG_INDEX.txt`.

## Rules that decided S3 boundary questions (apply the same way)

- Contract outranks brief. A brief-versus-contract conflict where the contract wins, or a disclosed boundary exception, is a ledger line and continue. Stop only for a destructive action, a real scope change, input only the owner has, or being blocked.
- Ownership resolves from the contract's C10 rows (file and test-family ownership), not from code comments or earlier ledger prose. Example: an S1 comment assigned legacy-migration transitions to S3, but C10.4 gives that test family to S4.
- RED means one named assertion fails; build and compile failures are not RED. Every increment: RED, deliberate-break confirmation, GREEN, offline envelope, emulator subsets, commit, push, ledger line.
- Read-only test files pin implementation shapes; grep them for every symbol a slice must change before the brief is written.
- Mirror, don't invent: registries, wires, IDs, and tables are copied from the contract verbatim; where the contract carries only a pointer row, code nothing until the contract states the behavior.

## Seams and traps worth knowing

- The emulator's REST and gapic surfaces need `Authorization: Bearer owner`; a raw public-v1 client needs `servicePath`/`port`/insecure `sslCreds`, and probe scripts must live under `functions/` to resolve modules.
- `fakeFirestore.js` (shared test support) is extended once per slice before the slice's first Node RED; `fakeV1Client.js` is the binding-shaped stand-in for the pinned public-v1 client (transactions, preconditions, commit-time bumping).
- Fixture facts that bit S3: enum values are numeric in binding shapes; integral doubles and `-0`/subnormals must be raw `doubleValue`; vector elements are doubles; a Date inside a fake sentinel resolver must not be flattened; tombstones derive from a real marker; deliberate breaks must be syntactically valid and caught by a named assertion.
- `ROLLOUT_TUPLE_V1` in `migrateOversizeEvents.js` must be refrozen whenever `firestore.rules` or `firestore.indexes.json` changes; the arming gate fails closed on a mismatch.
- The whole unit target has 19 pre-existing failures (test host without a FirebaseApp); the named S1–S3 suites are the envelope.
