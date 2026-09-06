# STATUS — Phase 2 at the S4 close (2026-09-06)

Authority: `docs/plans/PHASE2_CONTRACT.md` (sha256 `f675caaf93dc0203cbceb57ad32a687843c44de1de109f8cb4b0554a6d9e6c78`). Project state: `PEEZY_STATE.md`. Workflow: `PHASE2_WORKFLOW_v2.md`. This file is the one-page snapshot a reader needs before opening either; it is rewritten at every slice close.

## Where Phase 2 stands

| Slice | State | Head |
|---|---|---|
| S1 seams / reset stamps / runtime consumers / TaskPlanService transport | closed | `c967d59` (I6) + amendments `b2cf756`, `73dbd18` |
| S2 workflow / server implementation | closed | `8f9cbdf` |
| S3 scheduler / migration / deletion / outbound integration | closed; head `e31db84` (tag `351f2da`), review at `docs/reviews/S3_DIFF_REVIEW.md`, close-out amendments S3-CD5..CD9, trust anchor `5d1a90b` | see the ledger |
| S4 recovery / privacy UI + durable deletion orchestration | code complete at `d1bf095` (I0–I11); the rule-4 diff review (Sol, three rounds + one owner-scoped round) and the Swift review pass are recorded under "S4 close-out" in `tasks/todo.md`; the final reviewed commit is tagged there as the S4 head | see the ledger |
| S5 identity, S6 (after S4), S7 close-out | not started | — |

## Verification envelope at `d1bf095`

| Suite | Result | Log |
|---|---|---|
| Offline Node (C10.9 list that exists + `accountDeletionFence.test.js`, node@24 by path) | 370 tests, 365 pass, 5 emulator-gated skips, 0 fail (no `functions/` file changed in S4) | `logs/S4-close-offline-node.log` |
| Emulator Node subset (`scripts/test-emulator.sh node`) | 191 / 191 | `logs/S4-close-emu-node.log` |
| Rules (`scripts/test-emulator.sh rules`, Firestore + Storage) | 25 / 25 | `logs/S4-close-emu-rules.log` |
| Swift, thirteen `-only-testing` positions on the emulator (DurableStoreRecovery, TaskPlanDisposition, TaskSupersession, AppRootAuthRace, TasksStoreNamespace, DispositionContract, PeezyNudgeAnswer, TaskDispositionSurface, TaskRowLegacySnapshot, TaskGrouping, Build24Regression, EstimateIntegrityPhaseB, CoverageFirestoreIntegration) | 171 Swift Testing tests in 11 suites + 29 XCTest (1 pre-existing skip) passed | `logs/S4-I11-swift-all-green.log` |

Static gates at the same commit (named tests in `DurableStoreRecoveryTests`): `UID-interpolated preference keys are registry-complete`, `Release call graph and adversarial NSError are sink-free`, `Firebase Auth keychain item is absent after terminal detach`, and zero production `Firestore.firestore()` in every S4-owned file but `LocalPrivacyPurgeCoordinator.swift`. `project.pbxproj`, both plists, `PeezySettingsView.swift`, `PeezyV1App.swift`, and every `functions/` file are untouched. The `Firestore.firestore()` occurrences outside S4's files (`TaskDetailView`, `TaskContentSections`, `TaskResearchModule`, and the S1-recorded rest) stay pending for S7.

Baseline failures (pre-existing, not Phase 2's): the whole unit target carries 19 failures that reproduce identically on pre-S1 commit `2d45a54`; the named suites above are the envelope.

## What exists now (client, S4)

- `Peezy 4.0/Tasks/Durable/DurableStoreRecoveryCoordinator.swift`: the one actor of `PeezyAccountDeletion-v1.json` — the C2.1 intent envelope with its per-phase member table and generation/hash/inode CAS, the capability (`adel1_` + UUID, 32-byte base64url nonce, `proofSHA256`), the C2.2 reducer (`prepared → data_confirmed → purging → local_detaching → auth_finalize_dispatched → guarding → completed | local_cleared`, staged/nonstaged variants, the honest `remote_unverified` terminal), C2.3 error handling, the gate projection through `AccountDeletionGateControlling`, singleflight with `ACCOUNT_DELETION_BUSY`, Option B, the terminal consumption order (matching sign-out → keychain scrub → linked all-scope journal → eight owners and barriers → intent unlink → journal unlink → `clear`), crash recovery from journal/intent/stray file, `authTransition` for SIGNED_OUT/A→B, the Apple credential-state rule; plus `DurableFileObserver`, `JSONObjectScanner`, `DurableStoreRecoveryDriver` (every store through `DurableStoreRecovering`), `ForeignResolutionChoices`.
- `Peezy 4.0/Tasks/Durable/LocalPrivacyPurgeCoordinator.swift`: `FirestoreRuntimeOwner` (terminate → clearPersistence → fresh → probe → generation +1) over an instance seam and the one-time `FirestoreRuntime.install`; `ClientTelemetryPrivacyAuthority` (C2.2 barrier verbatim, process-lifetime singleflight, 10 s timeout); `RoomCaptureArtifactOwner` with `NarrationLease`/`TransferHandle` (acquire/revalidate/deposit/materialize/register/settle/revokeAll) and its environment key; `PrivacyDurableFile`; the C2.5 completion presenter (`PeezyAccountDeletionCompletion-v1.json`, exact copy and URLs); `PreferenceBarrier` (eleven keys + conditional first name); the purge journal (`PeezyLocalPrivacyPurge-v1.json`) and `LocalPrivacyPurgeCoordinator` (eight owners in order, acks journaled and mirrored, barriers, intent-linked priority); `FirebaseAuthKeychainScrub`.
- `Peezy 4.0/Tasks/Durable/DurableStoreRecoveryView.swift`: the surface model and views (blocked-store actions with the C9.7.12 names and expectations, epoch options enabling only the actionable epoch, foreign-choice gating, the deletion overlay, the completion surface in Apple-then-Google order).
- `Peezy 4.0/Tasks/Disposition/TaskDispositionSurface.swift`: the C9.5.20 superseded decoder, C9.5.21 formatter/copy, C9.5.22 undo eligibility, C9.5.23 history presentation, the C9.5.24 tri-state over the raw stored contract.
- `TaskPlanService.swift` (S4-CD2 scope): `ResetOperationRegistry: DurableStoreRecovering` (C9.7.3 order, C9.7.4 actions under whole-state CAS, receipt provenance and reconcile) and the C9.4.5 `LegacyResetMigrationV1` rows (grammar, key guards, reserve interactions, per-UID drive with alias candidates 1–4 and every error branch, materialization/retirement, APPLYING compare-and-remove, invalid-alias inspection, `inspectLegacyTaskReset` transport). `DailyDoseEngine.swift`: `observeMalformed`/`quarantineMalformed`/the dose slot. `DurableStoreReadiness.swift`: the runtime registry/installation, the three account-deletion `DurableFileKind` cases, the recovery declarations.
- Consumers: `TasksStore` (UID + listener-token namespace, seams, namespace-bound mutations, raw contracts retained, the C9.3.14 projection over injected fixtures with an empty production registry), `AppRootView` (load-token guards, completion surface host), `AssessmentCoordinator` (completion guard), `PeezyHomeViewModel`/`PeezyHomeView` (injected UID, runtime Firestore, `HomeDoseDefaults`), `AnalyticsEvents` (collection gate, fixed-parameter sink rule), the task row/list/tab views (surface state), the inventory scope (leases, transfer registry, §8.9.3 admission).

## Behaviors that wait for later slices (read before running a build)

- Until S7 installs the runtime in `PeezyV1App`, the production root, Home load, and task listener trap with `FIRESTORE_RUNTIME_NOT_INSTALLED` (C9.7.16's stated design: S7 installs before `AppRootView` is created). The S4-owned files acquire Firestore only through the runtime.
- With no `\.roomCaptureArtifactOwner` injected, narration is not captured (no lease); the inventory generation check is skipped while the runtime is uninstalled. `InventorySessionManager` holds a transitional owner over a clear gate until `attachArtifactOwner` (S7).
- Nothing is mounted: no `Phase2ProductionRuntime`, no `StartupBarrier` publication, no coordinator/presenter instance; the C2.7 two-device and A→B families run on seam fakes (S5's close-out re-runs them on the real conformers; C10.3 row).
- Home dose reads and writes stay on the shipped v0 keys (`HomeDoseDefaults`) because S5's `PeezyNudgeAnswerTests` pins the raw keys after view-model writes; moving Home onto the C9.5.16 v2 store means moving that pin (owner decision, Decision 8 rule).

## Interpretations recorded for the close-out register (each a ledger line; none changes a contract row's meaning)

Client mappings the contract leaves silent (`AUTH_REQUIRED` → `REMOTE_UNAVAILABLE`; capability-invalid with an Auth user or after `prepared` → `REMOTE_MALFORMED`; malformed/over-cap intent bytes → `FILE_IO`; monotonic injected clocks; `DELETING-guarding` at discovery persists `prepared(startup_discover)`; `finalize` on the capability alone in `auth_finalize_dispatched`/`guarding`; the honest `remote_unverified` trigger); the sign-out closure seam; the all-scope purge retiring a complete UID journal; `RecoveryObservedStateV1.files` display members and the fallback state's `quarantineEnumerable:false`; same-process drive rows without provenance (C9.7.8 "may retain"); the legacy ID grammar; the C9.5.7 matrix enforced only with a migration row present; the task row's required stores (route, handoff); the typed history row; the superseded copy rendered in `TaskRow` (not `TaskRowHeader`); the keychain scrub inside the consumption. Boundary exceptions: the three account-deletion `DurableFileKind` cases; `TaskPlanService.swift` internals (`Envelope` fileprivate, provenance properties, `epochConflictDigest`, one `reserve()` routing line).

## Owner inputs outstanding (input only the owner has)

1. S7 pre-ship gate owner action list (unchanged): run the sealer to produce the evidence artifact (Build B); wire the historical-migration observers; deploy the C7 index file and the rules; any arming. None happens from inside a task.
2. The Home dose pin (above) and the register candidates in the ledger's I3–I11 entries, at the S4 gate.

## Carried to later slices

- S5: the seam conformers (`GoogleIdentityAuthority`, `NotificationIdentityAuthority`, `HandoffSessionStore`, `WorkflowService` purge/recovery conformances); real auth epochs; the C2.7 two-device/A→B re-run on real conformers; the `AppRootAuthRaceTests` scans and callback-slot fixtures.
- S6: the C9.3.11 policy-present wake branches and live wake evidence for the C9.3.14 projection; `TaskDispositionSurfaceTests` adapter cases; D12/D13.
- S7: `Phase2ProductionRuntime` (eleven statics), the barrier/gate/recovery-surface mount, the Settings `deleteAccount()` hunk, the remaining `Firestore.firestore()` sites, the drive's caller reporting `LEGACY_RESET_MIGRATION_REQUIRED` to `noteMigrationRequired`, the pre-ship gate, PEEZY_STATE regeneration.
