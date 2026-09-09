# HANDOFF — from the S4 close to the S5 gate (2026-09-08)

Read first, in this order and by section only: `PEEZY_STATE.md` §4, the last entry of `tasks/todo.md`, `briefs/S5_BRIEF.md`, then `STATUS.md`. The contract (`docs/plans/PHASE2_CONTRACT.md`, sha256 `090f98dc…`, S5-CD1..CD9 registered 2026-09-08) is the sole executable authority; manifest v9 and spec v5 are archived under `docs/archive/phase2/` and are never read again — a missing shape is a contract defect to fix in the contract.

## Where things stand

S4 is closed at `994afac`, the final reviewed commit. The rule-4 diff review returned APPROVE after ten Sol rounds. Two findings are registered for the owner, both confirmed by the reviewer as correctly registered rather than fixable inside S4, and both drafted as decisions in the S5 brief: the Home dose keys (C9.5.16) and the assessment geocode seam (P1-R). The full close-out envelope is in `STATUS.md`.

## Next work

1. **S5 I0 is done, and the slice is stopped for three owner decisions — none of which blocks I1 through I10.** Read `~/Downloads/peezy-reports/S5_GATE/S5_OWNER_DECISIONS_10-12.md` first: **10** the workflow submission protocol (writer, inspector and client disagree on six points; every fix is S2's, and C9.7.19's `receipt_mismatch` can be neither specified nor implemented until one protocol is stated), **11** the three shapes that are S6's (per-action request maps, the application reducer's effects, and the per-action byte maxima C9.7.7 L3680's projection needs — no ceiling is invented here), **12** whether the self-contained transition table Decision 1 asked for should be replaced by the consolidated recovery-edge table that four review rounds now say it has to be. Decision 11 lands at I4/I5, Decision 10 at I11, and 12 is already narrowed conservatively enough to build on, so **I1 can start before any of them is answered.**
2. **What the amendments carry**: CD1 the handoff record grammar (both unions, per-phase required/forbidden, transitions, sort, request/receipt mapping); CD2 the workflow durable store's schema and physical targets plus the widened C10.3 `WorkflowService` row; CD3 the handoff store's file names; CD4 the `HANDOFF`/`HANDOFF_CANCEL`/`WORKFLOW` inspection transports in `TaskPlanService.swift`; CD5 the C2.7 real-conformer harness in `DurableStoreRecoveryTests.swift`; CD6 the Home dose ordered-writer row; CD7 the assessment geocode seam row; CD8 `PEEZY_STATE.md` excluded except §4. Decision 9 is a ledger interpretation with no contract change: the real auth-epoch conformer lands in `HandoffSessionStore.swift`, `AuthViewModel.swift` injects it and supplies `CurrentFirebaseUIDProviding`, and `TransitionalFirebaseAuthAuthority` stays declared so the S1 pin compiles.
3. **Then I1 onward** per the brief's Sequence (now I0–I13 + close-out), with fresh-context verification at every increment boundary. The S5-CD9 correction is the standing example of why: two passes over four blockers' worth of fixes found 24 more, including a missing happy path.
4. **After S5**: S6, then S7's close-out with the owner-run sealer, the observer wiring, and the deploys.

## Commands and environment

- Node is node@24 by explicit path: `/opt/homebrew/opt/node@24/bin/node`; never PATH node. Java for the emulators: `/opt/homebrew/opt/openjdk@21/bin` (the emulator script exports both).
- Offline Node envelope: the C10.9 command restricted to the files that exist, plus `functions/tests/accountDeletionFence.test.js`. Build the argument list in a shell loop and pass it with `${=LIST}` — zsh does not word-split an unquoted variable, and `node --test` then reports the whole string as one missing file. There is no `npm test` script.
- Emulator runs (`demo-peezy-phase1` only; never production): `scripts/test-emulator.sh node | rules | swift [Suite ...]`. The Swift default set is three suites; pass the thirteen positions explicitly (they are listed in the ledger's close-out entries). Runs share the emulator ports: chain them in one background script with a `.done` marker and wait once.
- Swift: one `xcodebuild build-for-testing` per session with project signing (simulator `DC0CC10C-6DB0-496A-8B0E-51E60D958A27`, iPhone 17 Pro); the summary line is `Test run with N tests in M suites passed`; XCTest suites print `Executed N tests`. Disk is chronically low: one DerivedData at a time.
- `PHASE_MANIFEST` is enforced by `.claude/hooks/pre_tool_use.py`: a new file must be listed before it is written (`briefs/*` and `logs` are already covered; `docs/reviews/S4_DIFF_REVIEW.md` is not). The project uses synchronized root groups, so a new Swift file compiles without a `project.pbxproj` edit; SourceKit lags, so trust the build.
- Codex, now **GPT-6 Astra** by owner direction (2026-09-08): `codex exec --skip-git-repo-check -m gpt-6-astra -s read-only --json -o <verdict> - <prompt`; resume with `codex exec resume <thread> -m gpt-6-astra -c sandbox_mode="read-only"` (always pass `-m`; check the first jsonl lines for `turn.failed`); run in the background with a `.done` marker. It needs codex-cli 0.153.4 or newer — 0.147.0 refuses with "requires a newer version of Codex", and `gpt-6.0-astra` and `astra` are not valid identifiers. Name the reviewer model in every gate packet and ledger entry. The S4 review ran on `gpt-5.6-sol`, thread `01a07911-0a35-71e0-80eb-f6267cbbfb6d`; the S5 brief gate ran on Sol before the change and is being re-gated on Astra.
- Fresh-context verification runs at every increment boundary (owner direction, 2026-09-08), not every other one.

## Rules that decided S4's boundary questions (apply the same way)

- Contract outranks brief; a disclosed boundary exception or a contract-versus-brief conflict where the contract wins is a ledger line and continue. Stop only for a destructive action, a real scope change, input only the owner has, or being blocked.
- A review finding you can fix without changing a contract row's meaning is fixed and re-reviewed, not escalated. That rule is what carried S4 through ten rounds; only two findings ever became owner decisions, both because the fix lay in another slice's file.
- Where two contract rows disagree the more specific literal wins and the correction is a ledger line (C9.5.18's exact digest formula outranked the generic C9.7.12 map).
- Ownership is an instrument question, not a permission question. When the work needs another slice's file, the shape is a C10.3 ordered-writer row on the S4-CD2/S4-CD5 pattern, never a new C10.2 entry — L4220 keeps the frozen owner and L4219 forbids editing a path merely because a test names it.
- Read-only test files pin implementation shapes: grep them for every symbol before writing; add overloads or seams, never move a pin without an owner decision.
- RED means one named assertion fails; when a break is not observable, add the case that observes it before declaring RED.
- Mirror, don't invent: registries, wires, IDs, copy and tables are copied from the contract. When mirroring a *server sanitizer*, copy its bounds exactly — every constraint it has and none it does not — and make the positive fixture byte-shaped like the writer's real output.

## Seams and traps worth knowing

- Swift Testing: no `await` right of `&&`/`||` inside `#expect` (hoist to a `let`); `Comment(rawValue:)` for dynamic messages; a three-value enum pattern written with two placeholders makes the compiler give up; `id` is not a usable parameter name in a nested helper; a `Result` failure type must conform to `Error`; a test that constructs a `@MainActor` model must itself be `@MainActor`.
- Actor singleflight: a `while let inflight { await inflight.value }` loop that never retires the completed task spins on the actor and hangs the whole run (`logs/S4-review3-swift-hung.log`). The waiter must clear the slot it observed before looking again.
- `CharacterSet.whitespaces` on Apple platforms contains U+200B even though its documentation says "Zs plus tab"; `.whitespacesAndNewlines` trims U+0085 and neither trims U+FEFF. None of them is ECMAScript's `trim` set — enumerate it and check both directions against `node`.
- `UserDefaults` subclasses prove copy-before-remove sequences; UID-interpolated keys are caught by the registry scan only when they are string literals.
- The simulator keychain carries the real app's persisted Firebase Auth user under the production app ID; a plain `signOut()` leaves it, which is why the consumption scrubs every `firebase_auth_*` item (the installation item is untouched).
- `RecordingTelemetrySDK.complete` can race the double's continuation store; retry the completion after yields.
- Until S7 installs the runtime, every S4-owned Firestore acquisition traps by design; do not "fix" that by reintroducing `Firestore.firestore()` (the named gate test fails).
