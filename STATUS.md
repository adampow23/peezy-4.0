# STATUS — Phase 2 at the S4 close (2026-09-08)

Authority: `docs/plans/PHASE2_CONTRACT.md` (sha256 `26db63b8b52eab3f34344568f5fce36158a1e93e2836c0de725355be20a8ddfa`, amended 2026-09-08 by S5-CD1..CD11; prior `090f98dc…` before the owner's Decision 10-12 rulings, `f675caaf…` at the S4 close). Project state: `PEEZY_STATE.md`. Workflow: `PHASE2_WORKFLOW_v2.md`. This file is the one-page snapshot a reader needs before opening either; it is rewritten at every slice close.

## Where Phase 2 stands

| Slice | State | Head |
|---|---|---|
| S1 seams / reset stamps / runtime consumers / TaskPlanService transport | closed | `c967d59` (I6) + amendments `b2cf756`, `73dbd18` |
| S2 workflow / server implementation | closed | `8f9cbdf` |
| S3 scheduler / migration / deletion / outbound integration | closed; review at `docs/reviews/S3_DIFF_REVIEW.md`, close-out amendments S3-CD5..CD9, trust anchor `5d1a90b` | `e31db84` (tag `351f2da`) |
| S4 recovery / privacy UI + durable deletion orchestration | **closed 2026-09-08**; the rule-4 diff review returned APPROVE after ten Sol rounds; two findings registered for the owner (below) | **`994afac`** |
| S5 identity / provider conformance | **I1 done and green** (`HandoffSession.swift`, 14 tests, RED proved on three falsifiers). I0 gated twice (Sol, then **GPT-6 Astra**); S5-CD1..CD11 registered, the last two from the owner's Decision 10–12 rulings. Stopped for three blockers in those rulings' own text | `briefs/S5_BRIEF.md`, `cc663de` |
| S6, S7 close-out | not started | — |

## Verification envelope at `994afac`

| Suite | Result | Log |
|---|---|---|
| Offline Node (the C10.9 list that exists + `accountDeletionFence.test.js`, node@24 by path) | 370 tests, 365 pass, 5 emulator-gated skips, 0 fail | `logs/S4-final-offline-node.log` |
| Emulator Node subset (`scripts/test-emulator.sh node`) | 191 / 191 | `logs/S4-final-emu-node.log` |
| Rules (`scripts/test-emulator.sh rules`, Firestore + Storage) | 25 / 25 | `logs/S4-final-emu-rules.log` |
| Swift, thirteen `-only-testing` positions on the emulator | 197 Swift Testing tests in 11 suites + 29 XCTest (1 pre-existing skip) | `logs/S4-review10-swift-final-green.log` |

No `functions/` file, plist, or `project.pbxproj` was touched by the slice, so the Node and rules numbers are unchanged from the S3 close. Static gates at the same commit (named tests in `DurableStoreRecoveryTests`): `UID-interpolated preference keys are registry-complete`, `Release call graph and adversarial NSError are sink-free`, `Firebase Auth keychain item is absent after terminal detach`, and zero production `Firestore.firestore()` in every S4-owned file but `LocalPrivacyPurgeCoordinator.swift`. The occurrences outside S4's files stay pending for S5–S7.

Baseline failures (pre-existing, not Phase 2's): the whole unit target carries 19 failures that reproduce identically on pre-S1 commit `2d45a54`; the named suites above are the envelope.

## The review that closed S4

Ten Sol rounds on one thread, plus a two-subagent Swift review pass and a six-lens fresh-context verification of the S5 brief. Round 1 raised 17 BLOCKER + 3 HIGH; rounds 2–9 each closed the surviving findings; round 10 returned APPROVE. Every fix carried a named falsifier that was RED under a one-line deliberate break and GREEN once restored byte-identically. The verbatim rounds are in `~/Downloads/peezy-reports/S4_GATE/` (`S4_SOL_ROUND1..10`), with the per-round responses (`S4_ROUND1..3_RESPONSE.md`) and every fix delta as a patch. The report at `docs/reviews/S4_DIFF_REVIEW.md` is deliberately not written yet: the owner's ruling defers it until after the owner's read.

Three defects that survived several rounds are worth carrying forward as review lessons: a client validator that mirrors a server sanitizer must copy *its* bounds exactly (S4 first omitted the closed subject-kind set, then invented a byte cap the server does not impose); a positive test fixture must be byte-shaped like the writer's real output or it pins the wrong grammar; and no cross-runtime character set may be derived from a platform set whose membership has not been enumerated (`CharacterSet.whitespaces` still contains U+200B, which JavaScript's `trim` keeps).

## What exists now (client, S4)

- `Peezy 4.0/Tasks/Durable/DurableStoreRecoveryCoordinator.swift`: the one actor of `PeezyAccountDeletion-v1.json` — the C2.1 intent envelope with its per-phase member table and generation/hash/inode CAS, the capability, the C2.2 reducer through `prepared → data_confirmed → purging → local_detaching → auth_finalize_dispatched → guarding → completed | local_cleared` plus the honest `remote_unverified` terminal, C2.3 error handling and the `AccountDeletionWireBinding` that binds every wire to the durable capability, immutable authority and deadline before any transition, the gate projection, singleflight with re-arbitration after every await, Option B, the terminal consumption order, the exhaustive journal/completion residue classification, crash recovery, `authTransition`, and the Apple credential-state rule; plus `DurableFileObserver`, `JSONObjectScanner`, `DurableStoreRecoveryDriver`, `ForeignResolutionChoices`.
- `Peezy 4.0/Tasks/Durable/LocalPrivacyPurgeCoordinator.swift`: `FirestoreRuntimeOwner` with its strict probe outcomes, `ClientTelemetryPrivacyAuthority`, `RoomCaptureArtifactOwner` with `NarrationLease` and the `NarrationRevocationRegistry` that makes revocation inseparable from a lease, `PrivacyDurableFile`, the C2.5 completion presenter with its typed observation, `PreferenceBarrier` over the eleven keys with dotted-UID enumeration, the purge journal and the eight-owner coordinator, `FirebaseAuthKeychainScrub`.
- `Peezy 4.0/Tasks/Durable/DurableStoreRecoveryView.swift`: the surface model and views.
- `Peezy 4.0/Tasks/Disposition/TaskDispositionSurface.swift`: the C9.5.20 decoder, the C9.5.21 formatter and copy, C9.5.22 undo eligibility, C9.5.23 history, and the C9.5.24 union whose `actionable` member carries `contractPresent` so Home consumes the union instead of the stored map.
- `TaskPlanService.swift` (S4-CD2 scope): `ResetOperationRegistry: DurableStoreRecovering` with whole-state CAS on both files, receipt provenance selecting the canonical-minimum mismatch across reset and migration rows, the `LEGACY_RESET_MIGRATION` inspection transport, and the C9.4.5 rows with fail-closed authority retirement. `DailyDoseEngine.swift`: presence by `object(forKey:)`, so a non-`Data` value is malformed and quarantined rather than overwritten. `DurableStoreReadiness.swift`: the runtime registry, the three account-deletion file kinds, the strict recovery-receipt grammar.
- Consumers: `TasksStore` (UID + listener-token namespace, sequence-stamped callbacks, retained raw contracts and routing authorities, the C9.3.14 projection with C9.3.12 precedence), `AppRootView`, `AssessmentCoordinator` (load generation), `PeezyHomeViewModel`/`PeezyHomeView`, `AnalyticsEvents` (one critical section for admission and the SDK call), the task row/list/tab views, and the inventory scope.

## Findings registered for the owner (input only the owner has)

1. **The Home dose keys (C9.5.16).** Home still reads and writes the three shipped v0 keys through `HomeDoseDefaults`, which C9.5.16 L2842 forbids. The reviewer confirmed this is correctly registered rather than fixed inside S4: `PeezyHomeViewModel.swift` is S4's but `DailyDoseEngine.swift` is S1's and the pin file `PeezyNudgeAnswerTests.swift` is S5's, so the move needs a C10.3 ordered-writer row. Drafted as Decision 1 of the S5 brief.
2. **The assessment geocode seam (P1-R).** `AssessmentDataManager.computeDistanceAndInterstate()` applies its result to the shared data manager before the completion's UID and load-generation guard can run, so a stale completion's fields survive into a replacement flow. The file is S1's at C10.2 L4131. Drafted as Decision 2 of the S5 brief.
3. **S7 pre-ship gate owner actions (unchanged):** run the sealer for the Build B evidence artifact; wire the historical-migration observers; deploy the C7 index file and the rules; any arming. None happens from inside a task.

## Behaviors that wait for later slices (read before running a build)

- Until S7 installs the runtime in `PeezyV1App`, the production root, Home load, and task listener trap with `FIRESTORE_RUNTIME_NOT_INSTALLED` (C9.7.16's stated design). The S4-owned files acquire Firestore only through the runtime.
- With no `\.roomCaptureArtifactOwner` injected, narration is not captured; `InventorySessionManager` holds a transitional owner over a clear gate until `attachArtifactOwner` (S7).
- Nothing is mounted: no `Phase2ProductionRuntime`, no `StartupBarrier` publication, no coordinator or presenter instance. The C2.7 two-device and A→B families run on seam fakes; S5's close-out re-runs them on the real conformers (C10.3 L4209).
- The urgent-recovery projection produces no line until S6 writes live wake evidence; its registry is empty in production by design.

## Interpretations recorded for the close-out register

The client mappings the contract leaves silent, each a ledger line and none changing a row's meaning: `AUTH_REQUIRED` → `REMOTE_UNAVAILABLE`; capability-invalid with an Auth user or after `prepared` → `REMOTE_MALFORMED`; malformed or over-cap intent bytes → `FILE_IO`; monotonic injected clocks; `DELETING-guarding` at discovery persisting `prepared(startup_discover)`; the honest `remote_unverified` trigger; the sign-out closure seam; the all-scope purge retiring a complete UID journal; a **UID-scope journal with no intent blocking as unmatched authority**; the C9.7.8 same-process drive rows retaining their first response without installing provenance; the task row's required stores; the superseded copy rendered in `TaskRow`; and the keychain scrub inside the consumption. Boundary exceptions: the three account-deletion `DurableFileKind` cases and the `TaskPlanService.swift` internals named in S4-CD2.

## Carried to later slices

- **S5**: the four real conformers (`GoogleIdentityAuthority`, `NotificationIdentityAuthority`, `HandoffSessionStore`, `WorkflowService`), the handoff store itself, real auth epochs, the C2.7 re-run on real conformers, and its `AppRootAuthRaceTests` contributions. The brief is drafted at `briefs/S5_BRIEF.md` with six owner decisions and its own fresh-context verification already applied; the Codex gate at the brief is the next step.
- **S6**: the C9.3.11 policy-present wake branches and live wake evidence for the C9.3.14 projection; the `TaskDispositionSurfaceTests` adapter cases; D12/D13.
- **S7**: `Phase2ProductionRuntime`, the barrier/gate/recovery-surface mount, the Settings `deleteAccount()` hunk, the remaining `Firestore.firestore()` sites, `TaskRouteTests` and the P1-P/A3-7 route half, the pre-ship gate, and the PEEZY_STATE regeneration.
