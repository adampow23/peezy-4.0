# STATUS — Phase 2 at the S3 close (2026-09-06)

Authority: `docs/plans/PHASE2_CONTRACT.md` (sha256 `97ed60b758f3287a315c6cc4e07207527feaf4b6cb4347d6ce4be8054514b8b2`). Project state: `PEEZY_STATE.md`. Workflow: `PHASE2_WORKFLOW_v2.md`. This file is the one-page snapshot a reader needs before opening either; it is rewritten at every slice close.

## Where Phase 2 stands

| Slice | State | Head |
|---|---|---|
| S1 seams / reset stamps / runtime consumers / TaskPlanService transport | closed | `c967d59` (I6) + amendments `b2cf756`, `73dbd18` |
| S2 workflow / server implementation | closed | `8f9cbdf` |
| S3 scheduler / migration / deletion / outbound integration | code complete at `eb0cc81`; the close-out review (Swift pass, three Sol rounds) fixed 18 findings and refuted or gap-recorded the rest; the S3 head is tagged in `tasks/todo.md` under "S3 close-out" | see the ledger |
| S4 recovery / privacy UI + deletion orchestration | not started; next deletion slice, diff-reviewed | — |
| S5 identity, S6 (after S4), S7 close-out | not started | — |

## Verification envelope at the S3 head (after the close-out review fixes)

| Suite | Result | Log |
|---|---|---|
| Offline Node (C10.9 list that exists + `accountDeletionFence.test.js`, node@24 by path) | 369 tests, 364 pass, 5 emulator-gated skips, 0 fail | `logs/S3-review-r3-offline.log` |
| Emulator Node subset (`scripts/test-emulator.sh node`) | 190 / 190 | `logs/S3-review-r4-emulator-node.log` |
| Rules (`scripts/test-emulator.sh rules`, Firestore + Storage) | 25 / 25 | `logs/S3-review-r4-emulator-rules.log` |
| Swift (`DurableStoreRecoveryTests`, `TaskPlanDispositionTests`, `TaskSupersessionTests` on the emulator) | 72 tests in 3 suites passed | `logs/S3-review-r3-swift-green.log` |
| `xcodebuild build-for-testing` (project signing) | TEST BUILD SUCCEEDED | `logs/S3-swift-build-for-testing.log` |

The pre-review envelope at `eb0cc81` (368/363/5, 189/189, 25/25, 67 tests) is in `logs/S3-close-*.log`.

Static gates at the same commit: `firestore.rules` sha256 `0d271775…` and `firestore.indexes.json` (5,872 bytes, sha256 `a6de8daf…`) equal `ROLLOUT_TUPLE_V1` in `functions/scripts/migrateOversizeEvents.js`; C7 pins re-verified at I4 and I12b; `node --check` on every touched `.js`.

Baseline failures (pre-existing, not Phase 2's): the whole unit target carries 19 failures that reproduce identically on pre-S1 commit `2d45a54` (MoversChainHandshakeTests 7, MoversPreparationPagesTests 6, AssessmentTier3MigrationTests 1, EstimateIntegrityPhaseBTests 1, MoveDistanceIntegrationTests 4); the test host configures no FirebaseApp. The S3 Node baseline at slice start was 277 tests / 274 pass / 3 skips.

## What exists now (server)

- Scheduler (C9.1, `functions/dispositionTriggers.js`): v2 fenced lease, due observation, catch-up capacity, threshold fixed-point scan, Phase-2b alert slots, durable refusals (`srf1_`), eligible retry admission, fairness alerts, wake-latency samples; OriginalEventBytesV1 encoder, the qev1 table, retry member 1→2→qev1, `qevu1` unencodable quarantine; D8 storage equations over decoded and raw values, `fitsPhase0Transition`, `phase0Envelope`, `POST_CUTOFF_SOURCE_SIZE_INVARIANT`, RawPhase0SizingV1 through the REST document read; D11 regeneration item (C9.1.30) in `PEEZY_STATE_REGEN_SPEC.md`.
- MIG-EVENT-V1 (C9.2, `functions/scripts/migrateOversizeEvents.js`): pinned public-v1 client, exact query, presence classification, mandatory reread, FirestoreDocumentArchiveV1, chunk gate, cross-fence lease, manifest/chunks/seal writes, four-write terminal commit, orphan cleanup, pre-ship gate, `ROLLOUT_TUPLE_V1`, arming triple. Never armed; emulator project only.
- Notification intents (C9.3, `functions/notificationIntents.js`; `claimTaskIntent` and `inspectLegacyTaskReset` in `functions/taskPlan.js`): producer, urgency upgrade, cancellation, record-first claim replay, intent grammar; rules deny every client access to `users/{uid}/notificationIntents`.
- Deletion (C9.4, C2–C3, C6): the shared fence inside every existing `ACCOUNT_DELETION_FENCE_WRITERS_V1` path; outbound leases on every C6.2 caller; C3 fixed-code logging across the active export graph; global-scheduler cleanup inside the application sweep; `purgeLegacyResolvedProviders.js`, `sealAccountDeletionProviderEvidence.js` (Build A: null trust anchor), `purgeLegacyDeletedAccounts.js` (23-row registry, 27-member checkpoint, discovering→reducing→waiting_guards→confirming); `phase2LegacyCreateBlocker` exported only under `PHASE2_LEGACY_CREATE_BLOCKER=armed`.
- Rules and indexes: deletion boundaries in `firestore.rules` and `storage.rules`; all-client denials for `notificationIntents`, `eventArchive`, `accountDeletionLegacyCandidates`; `firestore.indexes.json` is the exact C7 result (frozen base plus the eight appends).

## What exists now (client)

- `TaskPlanService.swift`: reset/inspection/reconciliation DTOs and `ResetTransport`, `ResetLocalCleanupAuthorityV1`, the awaiting-marker validator, `ResetOperationRegistry.drive` (inspect-before-each-callback, committed short-circuit, durable dispatch phases) and `recoverEpoch`.
- `RetakeAssessmentCoordinator.swift`: drives through the registry with authority-taking cleanup closures; at-most-once notification; C9.4.6 outcome switch.
- `DailyDoseEngine.swift`: `DailyDoseLocalStore` epoch-r cleanup and the exact 0→1 bridge; `resetForRetake(authority:)`.
- Frozen cross-language wires: `functions/tests/fixtures/resetWiresV1.json` (produced by the real handler, byte-asserted from Node, decoded by the Swift mirrors).

## Amendments adopted after the close-out review (S3-CD5..CD9, owner directions 2026-09-06)

- C9.1.20 branch (5): a deletion-fenced candidate settles past the cursor with zero writes beneath the owner (never a refusal).
- C9.2.2 audit exit: MIG-EVENT audit exits zero only when the C9.2.9 criterion holds; a complete pass with failing or out-of-scope rows exits nonzero.
- C9.4.1: a NEW_UID found during confirmation is nominated as a pending candidate in the failure transaction before reduction resumes.
- C9.3.11 (with C10.1 rows): the policy-present wake branches belong to S6, effective when C9.3 defines the policy-state, deadline-evidence, and handoff shapes. Until S6 lands, scheduler wakes for policy-bearing tasks do not fire: a policy-present row settles with zero writes (no task byte, no refusal record, no intent) and is counted as `policyPresent`; the claim requires the present policy state's epoch and fingerprint; PC linkage is not validated until its referent is defined.
- C9.5.16: a malformed dose store preserves every byte and every legacy key, blocks the reset's dose cleanup, and is marked for durable-store recovery (S4); a later reset removes legacy keys only after an accepted cleanup.
- Trust anchor: the owner's Ed25519 public key and its SHA-256 are the reviewed literals in the fence and the sealer (Build B is armed; the evidence artifact is produced by the owner-run sealer, on the S7 pre-ship gate's owner action list).

## Contract gaps surfaced by the close-out review (now amended above; kept for the record)

- C9.1.20: whether a deletion-fenced candidate settles the lane cursor (the code settles it without a write).
- C9.2.1/C9.2.2: no audit-mode exit criterion for MIG-EVENT; L1256's second-pass sequencing wording.
- C9.4.1: NEW_UID during confirmation is never nominated (candidate amendment: NEW_UID → discovering at row 0, `pass_ordinal + 1`).
- C9.3: the live policy-state shape and the PC-linkage referent on the intent document are undefined; C10.1/C6.5 charge the C9.3.11 firing branches to `dispositionTriggers.js` (S3) while the ledger records them as S6's (Sol accepted this as an owner scope decision in round 3).
- Review budget: Sol's third and final round still listed four small items; all four are fixed with RED/GREEN tests after the cap. A fourth round is the owner's call.
- C9.5.16: whether a later reset removes the legacy dose keys when v2 is malformed (the code now preserves them, matching the bridge).

## Owner inputs outstanding (input only the owner has)

1. Trust anchor: supplied and inserted (2026-09-06); Build B is armed in the fence and the sealer.
2. S7 pre-ship gate owner action list: run the sealer to produce the evidence artifact (Build B); wire the historical-migration observers (barrier, gate, Firestore config, global zero proof) from the Build-B evidence/ops artifacts; deploy the C7 index file and the rules; any arming. None happens from inside a task.

## Carried to later slices

- S4: C9.4.5 client legacy-migration rows (`LegacyResetMigrationV1` state machine, alias candidates, inspect flow, APPLYING compare-and-remove of `phase1.pendingRetakeOperation.<uid>`); `PeezySettingsView.deleteAccount()` hunk (with S7); `FirestoreRuntimeOwner`; `PeezyHomeViewModel` dose keys; `InventorySessionManager.pendingNarration`.
- S5: real auth epochs replace `TransitionalFirebaseAuthAuthority`.
- S6: C9.3.11 intent-producing scheduler branches and the claim's live policy validation; `functions/taskDisposition.js` (its fence-writer entry stays recorded pending; the sealer's 27-path digest needs it).
- S7: barrier instance for gate admission; pre-ship gate; PEEZY_STATE regeneration.
- Unedited by decision: `functions/validateResolveProvider.js` (deployment-inactive, Decision 8).
