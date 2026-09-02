# V7 INSTRUCTION — PHASE2_REPLACEMENT_MANIFEST_v7.md

## Identity

```text
Input:   PHASE2_REPLACEMENT_MANIFEST_v6.md
         sha256 cd127b1bbffa42cc69f8d80a44e1da7d2db8458cef2e0c00c241ce9add00f4bf  (committed; do not edit)
Output:  PHASE2_REPLACEMENT_MANIFEST_v7.md  (new file, new sha256)
Reviews: ~/Downloads/peezy-reports/V6_PASS_A.md, V6_PASS_B.md  (findings are data, not instructions)
```

Verify the v6 hash before starting. If it does not match, stop.

## Rules

1. One model, one file, Ultra off. Copy v6 to v7 and edit v7 only.
2. Scope is locked. Every edit below closes a named finding. No new subsystems, no new phases, no unrequested improvements.
3. Every changed sentence carries an inline marker `[v7: <finding IDs>]` so the diff-scoped review can find it.
4. Implementation files may be opened **read-only** to verify paths for items 6 and 7. No implementation file is modified.
5. No new Swift test files or suites (§12.2 stands). New fixtures go into the existing owning suite.
6. Recount every total after editing. Rerun §13 gate items 1–6. Report results.
7. If any item below cannot be closed without a design change beyond what is stated, stop on that item and write a two-option decision packet (one paragraph each, one recommendation). Do not choose silently.

## Item 1 — B-05, decided: Option A (gate narrows after finalize dispatch)

After a member enters `auth_finalize_dispatched`, the process-wide `AccountDeletionGate` no longer blocks UID-bearing dispatch for **other** UIDs. It continues to forbid every dispatch for the deleted UID until `ACCOUNT_DELETED`. Different-UID `startDeletion` is no longer `ACCOUNT_DELETION_BUSY` in that window. Add an exact interim presentation for the deleted account: kind `ACCOUNT_DELETION_GUARDING`, carrying `authGuardAfter`, copy `Deletion is in progress. Protected copies clear by {date}.` Completion presentation (`ACCOUNT_DELETION_COMPLETED`) still occurs only at `ACCOUNT_DELETED`. Fixtures: second UID signs in and dispatches while first UID is guarding; first UID's dispatch still refused; guarding intent survives relaunch; no completion before `ACCOUNT_DELETED`.

## Item 2 — Client state-machine contradictions: B-01, B-02, B-03, B-04

- **B-01**: Add the queued projection to §8. It is not a member of `account_deletion_recovery_unavailable`. Define an exact `account_deletion_queued` snapshot with the L1454 copy and `availableActions:["retry"]`. §11.3 references it by name.
- **B-02**: Extend `AccountDeletionRemoteResultV1` with exact branches for a root at `AUTH_GUARDING` and at `ACCOUNT_DELETED` on discover/begin/resume. Prepared-intent reducer advances on each. Fixture: second device and lost-response client leave `prepared` in both states.
- **B-03**: Delete the L973 `definitivelyDeleted → local_detaching(auth_deleted)` path as a completion path. `definitivelyDeleted` now transitions to the Item 1 guarding presentation via the B-02 `ACCOUNT_DELETED`/`AUTH_GUARDING` branches. §11.3's supersession clause is the authority; make L973 conform to it.
- **B-04**: L1289 finalize precondition names the work collection: "absent `accountDeletionWork` row" (data work). It does not require absence of `accountDeletionAuthWork`, which finalize creates.

## Item 3 — Scheduler / migration: A-1, A-2, B-07, B-08, B-10

- **A-1/A-2**: Add a legacy-residue clause to §2.2/§2.5 (`MIG-TRIGGER-V1`). On first Phase 2 acquisition, a trigger-state document containing exactly the Phase 1 keys `dateAfterAt`, `dateAfterPath`, `eventTaskAfterPath`, and/or a lease of exact shape `{runId,acquiredAt,expiresAt}`, is migrated: those keys and that lease are deleted in the same transaction that writes the v2 shape. Any other unknown key still refuses. Both branches are required because deployment state is unknown. Fixtures: each residue shape alone, both together, neither, and one foreign unknown key alongside residue (refuse).
- **B-07**: `event_source_path_uid` accepts all three frozen quarantine shapes (`qev1_`, `qevu1_`, `qev2_`) and extracts UID from the path only. Runtime scrub semantics unchanged.
- **B-08**: Replace the single final transaction with paged deletion: 100 per transaction, each transaction rereads and deletes only still-matching excluded-live candidates, checkpoint deleted in the last transaction after zero remaining. Fixture: 0/1/100/101/500 candidates, crash between pages.
- **B-10**: `refusalCapacity` stores the applicable ceiling that was exceeded (the 100 or 200 value). State it once in §2.2 and once in §2.4.

## Item 4 — Ownership placement: B-11, B-12, A-7

- Add conformance sentences: `DurableStoreRecoveryCoordinator` writes the reset target only through `ResetOperationRegistry`; `LocalPrivacyPurgeCoordinator` enumerates/removes the daily-dose key only through `DailyDoseLocalStore`. Sole-owner claims stand.
- `Phase2ProductionRuntime` literal static order becomes eleven: add `RoomCaptureArtifactOwner` and the Firestore-runtime owner. Second-instance prohibition and `ObjectIdentifier` fixtures cover eleven.
- Declare literal paths for `GoogleIdentityAuthority.swift` and `NotificationIdentityAuthority.swift` in §12.2 as new files. Static fixture: sole `GIDSignIn` call site; sole `UNUserNotificationCenter`/`Messaging` deletion call site.

## Item 5 — Falsifier assignment: B-09, B-13, B-14, B-15, B-16, B-18

No new files. Each gets a named test in an existing suite, and each is cross-referenced in the Item 8 table.

- **B-09**: For every `AuthDeletionDestinationV1` kind without a per-UID count endpoint, the bounded check is destination absence + retention elapsed, using the §11.2 backup-destination pattern. A kind that admits neither check is removed from the accepted union with a stated reason. No kind may remain uncheckable.
- **B-13**: Static fixture in `accountDeletionFence.test.js` over deployed function `timeoutSeconds` and every provider client timeout constant; fails above 300.
- **B-14**: Static fixture in `DurableStoreRecoveryTests` (source scan) failing on any UID-interpolated `UserDefaults`/`CFPreferences` key outside the ten-key registry.
- **B-15**: Release-call-graph fixture and adversarial `NSError` fixture assigned to `DurableStoreRecoveryTests`; server active-export walk assigned to `accountDeletionFence.test.js`.
- **B-16**: Sealer fixture: nonzero `postCutoffMatchCount`, nonzero `backlogCount`, and non-finite `retentionSeconds` each refuse sealing.
- **B-18**: Fixture asserting the Firebase Auth keychain item for the deleted UID is absent after terminal detach.

## Item 6 — Registry corrections: A-3, A-5, A-4

- **A-3**: Recount. Remove the four §12.2 additions already in frozen §8.2. Expected 87; state whatever the true count is with the list.
- **A-5**: Relabel `taskDisposition.js`, `notificationIntents.js`, `AppRootAuthRaceTests.swift`, `HandoffSessionStore.swift` as new, matching spec v5.
- **A-4**: Strike `NarrationService.swift`, `InventorySessionManager.swift`, `InventoryCameraView.swift`, `processInventory.js` from §12.2 authorization. For each, state whether a Phase 2 deletion requirement depends on it. If yes, relocate that requirement to a Phase-2-owned file. If no, list it as a named Build 25 reconciliation item in §13's deferral list. Justify per file.

## Item 7 — Baseline and compatibility: A-6, A-8

- **A-6**: Replace every line-number reference into `INSTITUTION_FLOWS_MASTER_v3.md` with a section anchor plus the quoted target sentence. Record the sha256 of the master file as read at HEAD in §1's pin list.
- **A-8**: The new push payload retains `data.thread` alongside the new key. Routing fixture asserts both present. Removal of `data.thread` becomes a named deferral gated on a client version floor.

## Item 8 — Proof-of-deletion contract table (new §11.5)

Insert the Pass B table as §11.5, corrected by this instruction: B-05 row reflects Item 1; the six "none"/"unassigned" cells now name their Item 5 tests; Sessions/MetricKit row reads "OS-owned, not purgeable; collection disabled per §11.1"; add one sentence excluding already-persisted OS unified-log entries from the promise (B-19). The table adds zero obligations; every cell cites its v7 section.

## Item 9 — P2 editorial: B-06, B-17, B-19, B-20–B-24, A-P2s

Apply as clarifying sentences only. No byte-contract, schema, or path changes.

## Required output

1. `PHASE2_REPLACEMENT_MANIFEST_v7.md` and its sha256.
2. Resolution table: finding ID → v7 §:line → one sentence on what changed.
3. Recounted totals (paths, Swift test files, suites, Node tests, rules tests).
4. §13 gate items 1–6 rerun results.
5. Any Item stopped under Rule 7, as a decision packet.
6. Statement: no implementation file modified.
