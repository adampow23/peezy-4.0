# STATUS — Phase 2 at the S3 close (2026-09-06)

Authority: `docs/plans/PHASE2_CONTRACT.md` (sha256 `fb6a8bf63da7d0388229bcc8525f7333c51d544568506af37c66f19b18a94ce8`). Project state: `PEEZY_STATE.md`. Workflow: `PHASE2_WORKFLOW_v2.md`. This file is the one-page snapshot a reader needs before opening either; it is rewritten at every slice close.

## Where Phase 2 stands

| Slice | State | Head |
|---|---|---|
| S1 seams / reset stamps / runtime consumers / TaskPlanService transport | closed | `c967d59` (I6) + amendments `b2cf756`, `73dbd18` |
| S2 workflow / server implementation | closed | `8f9cbdf` |
| S3 scheduler / migration / deletion / outbound integration | code complete at `eb0cc81`; close-out review checkpoint in progress (workflow rule 4) | the close-out commit is tagged in `tasks/todo.md` under "S3 close-out" |
| S4 recovery / privacy UI + deletion orchestration | not started; next deletion slice, diff-reviewed | — |
| S5 identity, S6 (after S4), S7 close-out | not started | — |

## Verification envelope at `eb0cc81`

| Suite | Result | Log |
|---|---|---|
| Offline Node (C10.9 list that exists + `accountDeletionFence.test.js`, node@24 by path) | 368 tests, 363 pass, 5 emulator-gated skips, 0 fail | `logs/S3-close-offline.log` |
| Emulator Node subset (`scripts/test-emulator.sh node`) | 189 / 189 | `logs/S3-close-emulator-node.log` |
| Rules (`scripts/test-emulator.sh rules`, Firestore + Storage) | 25 / 25 | `logs/S3-close-emulator-rules.log` |
| Swift (`DurableStoreRecoveryTests`, `TaskPlanDispositionTests`, `TaskSupersessionTests` on the emulator) | 67 tests in 3 suites passed | `logs/S3-close-emulator-swift.log` |
| `xcodebuild build-for-testing` (project signing) | TEST BUILD SUCCEEDED | `logs/S3-swift-build-for-testing.log` |

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

## Owner inputs outstanding (input only the owner has)

1. Trust anchor: the base64url Ed25519 public key and its SHA-256, inserted in one commit into `PROVIDER_EVIDENCE_TRUST_ANCHOR_V1` (`functions/accountDeletionFence.js`) and `SEALER_TRUST_ANCHOR_V1` (the sealer). Until then Build A holds and no Build-B artifact can be produced.
2. Build-B operational wiring, outside any slice: the evidence artifact (owner-run sealer invocation) and the historical-migration observers (barrier, gate, Firestore config, global zero proof) that refuse by default in production.
3. Live deploys at the S7 pre-ship gate: the C7 index file, the rules, and any arming; none happens from inside a task.

## Carried to later slices

- S4: C9.4.5 client legacy-migration rows (`LegacyResetMigrationV1` state machine, alias candidates, inspect flow, APPLYING compare-and-remove of `phase1.pendingRetakeOperation.<uid>`); `PeezySettingsView.deleteAccount()` hunk (with S7); `FirestoreRuntimeOwner`; `PeezyHomeViewModel` dose keys; `InventorySessionManager.pendingNarration`.
- S5: real auth epochs replace `TransitionalFirebaseAuthAuthority`.
- S6: C9.3.11 intent-producing scheduler branches and the claim's live policy validation; `functions/taskDisposition.js` (its fence-writer entry stays recorded pending; the sealer's 27-path digest needs it).
- S7: barrier instance for gate admission; pre-ship gate; PEEZY_STATE regeneration.
- Unedited by decision: `functions/validateResolveProvider.js` (deployment-inactive, Decision 8).
