# HANDOFF — from the S4 close to the next session (2026-09-06)

Read first, in this order and by section only: `PEEZY_STATE.md` §4, the last entry of `tasks/todo.md`, the current brief under `briefs/`, then `STATUS.md`. The contract (`docs/plans/PHASE2_CONTRACT.md`, sha256 `f675caaf…`) is the sole executable authority; the manifest v9 and spec v5 are archived under `docs/archive/phase2/` and are never read again (Reconciled 12: a missing shape is a contract defect to fix in the contract).

## Next work

1. S4 is closed once the rule-4 diff review recorded under "S4 close-out" in `tasks/todo.md` has every finding fixed or dispositioned and the final reviewed commit is tagged there as the S4 head; the review report lands at `docs/reviews/S4_DIFF_REVIEW.md` after the owner's read. The review packet is in `~/Downloads/peezy-reports/S4_GATE/` (packet, brief, diff `49d21c3..d1bf095`, inventory, ledger section, log index, Sol rounds under `run/`).
2. S5 brief (identity/provider conformance), per the `PHASE2_WORKFLOW_v2.md` template with a Codex gate at the brief. S5 inherits from S4: the four `DurableStoreRecovering` conformers it owns (`HandoffSessionStore`, `WorkflowService`) and the purge conformances (`GoogleIdentityAuthority`, `NotificationIdentityAuthority`, `HandoffSessionStore`, `WorkflowService`), real auth epochs replacing `TransitionalFirebaseAuthAuthority`, the C10.3 row re-running the C2.7 two-device/A→B families on the real conformers, and its `AppRootAuthRaceTests` contributions (S4-CD4 order).
3. Owner decisions carried in the ledger's S4 entries: the Home dose pin (S5's `PeezyNudgeAnswerTests` pins the raw v0 keys, so Home cannot move onto the C9.5.16 v2 store without moving that pin); the client mappings and interpretations listed in `STATUS.md` are register candidates.
4. Owner actions at the S7 pre-ship gate (unchanged): the owner-run sealer (Build B artifact), the observer wiring, the deploys.

## Commands and environment

- Node is node@24 by explicit path: `/opt/homebrew/opt/node@24/bin/node`; never PATH node. Java for the emulators: `/opt/homebrew/opt/openjdk@21/bin` (the emulator script exports both).
- Offline Node envelope: the C10.9 command in the contract, restricted to the files that exist today, plus `functions/tests/accountDeletionFence.test.js` (the exact list is in `scratchpad`-free form inside `tasks/todo.md`'s S4 close-out entry). There is no `npm test` script.
- Emulator runs (`demo-peezy-phase1` only; never production): `scripts/test-emulator.sh node | rules | swift [Suite ...]`. The Swift default set is three suites; S4 added ten more positions — pass them explicitly (the thirteen are listed in `STATUS.md`). Runs share the emulator ports: chain them in one background script with a `.done` marker and wait once.
- Swift: one `xcodebuild build-for-testing` per session with project signing (simulator `DC0CC10C-6DB0-496A-8B0E-51E60D958A27`, iPhone 17 Pro); the summary line is `Test run with N tests in M suites passed`; XCTest suites print `Executed N tests`. Disk is chronically low: one DerivedData at a time.
- `PHASE_MANIFEST` is enforced by `.claude/hooks/pre_tool_use.py`: a new file must be listed before it is written. The project uses synchronized root groups, so a new Swift file is compiled without a `project.pbxproj` edit (SourceKit diagnostics lag behind; trust the build).
- Codex (Sol): `codex exec --skip-git-repo-check -m gpt-5.6-sol -s read-only --json -o <verdict> - <prompt`; resume with `codex exec resume <thread> -m gpt-5.6-sol -c sandbox_mode="read-only"` (always pass `-m`; check the first jsonl lines for `turn.failed`); ~25 min a round, run in the background with a `.done` marker.
- The `/swiftui-pro` and `/swift-concurrency-pro` skills do not exist in this environment; the equivalent close-out passes ran as read-only subagents (their findings are in the ledger's S4 close-out entry).

## Rules that decided S4 boundary questions (apply the same way)

- Contract outranks brief; a disclosed boundary exception or a contract-versus-brief conflict where the contract wins is a ledger line and continue. Stop only for a destructive action, a real scope change, input only the owner has, or being blocked.
- Where two contract rows disagree the more specific literal wins and the correction is a ledger line: C9.5.18's exact `reset_epoch_conflict` digest formula outranked the generic C9.7.12 map (I7 corrected I5).
- Read-only test files pin implementation shapes: grep them for every symbol before writing (the three inventory initializers, the six-argument `PeezyHomeViewModel` init, the raw dose keys, `TaskRowButtons.layout(for:section:)`, `AppRootView()`); add overloads or seams, never move a pin without an owner decision.
- RED means one named assertion fails; a deliberate break must be caught by a named test — when a break is not observable (the dose removal order, the same-UID retired token), add the case that observes it before declaring RED.
- Mirror, don't invent: registries, wires, IDs, copy, and tables are copied from the contract; where the contract is silent on a client mapping, choose the most conservative behavior (retain bytes, block with Retry) and record it as a register candidate.

## Seams and traps worth knowing

- Swift Testing: no `await` right of `&&`/`||` inside `#expect` (hoist to a `let`); `Comment(rawValue:)` for dynamic messages; a three-value enum pattern written with two placeholders makes the compiler give up; `id` is not a usable parameter name in a nested helper; a `Result` failure type must conform to `Error`; a test that constructs a `@MainActor` model must itself be `@MainActor`.
- `UserDefaults` subclasses (`VerificationFailingDefaults`) prove copy-before-remove sequences; UID-interpolated keys are caught by the registry scan only when they are string literals.
- The simulator keychain carries the real app's persisted Firebase Auth user under the production app ID; a plain `signOut()` leaves it, which is why the consumption scrubs every `firebase_auth_*` item (the installation item is untouched).
- `RecordingTelemetrySDK.complete` can race the double's continuation store; retry the completion after yields.
- Until S7 installs the runtime, every S4-owned Firestore acquisition traps by design; do not "fix" that by reintroducing `Firestore.firestore()` (the named gate test fails).
