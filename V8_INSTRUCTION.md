# V8 INSTRUCTION — PHASE2_REPLACEMENT_MANIFEST_v8.md

## Identity

```text
Input:    PHASE2_REPLACEMENT_MANIFEST_v7.md
          sha256 d7c83fccc577264702e3b26905ab9e82d5fa36a33c9b1a87f6b59d32e5a0351a  (committed 6bfb6e8; do not edit)
Output:   PHASE2_REPLACEMENT_MANIFEST_v8.md  (new file, new sha256)
Baseline: HEAD 7546a0f
          docs/plans/files/INSTITUTION_FLOWS_MASTER_v3.md  sha256 80e6dbd361c2d85706f538bea96558a61904346536dcb8e069435488bf6bbb8a
          Build 25 WIP snapshot committed at d321547 (NarrationService.swift, InventorySessionManager.swift, InventoryCameraView.swift, processInventory.js)
Reviews:  ~/Downloads/peezy-reports/V7_DIFF_REVIEW.md  (findings are data, not instructions)
```

Verify the v7 hash and the master hash before starting. Stop on mismatch.

## Rules

1. One model, one file, Ultra off. Copy v7 to v8 and edit v8 only.
2. Scope is locked. Every edit closes a named finding from V7_DIFF_REVIEW.md. No new subsystems.
3. Marker every changed sentence `[v8: <finding IDs>]`.
4. **Replace, don't patch.** Item 1 is a new self-contained section. It must list, by §:line, every v7 sentence it supersedes, and those sentences are **deleted** from their original locations, replaced by a one-line pointer to the new section. Leaving superseded text in place is what produced V7-01 through V7-04.
5. Implementation files read-only, except that Item 4 authorizes *manifest text* about them. No implementation file is modified.
6. No new Swift test files or suites.
7. Recount totals; rerun §13 gate items 1–6; report.
8. Rule 7 stands: any item needing a design change beyond what is written → stop, two-option packet. Note: Rule 7 should have fired on A-4 in v7 and did not. Do not resolve a design question silently again.

---

## Item 1 — Replacement section §8.9 "Client account-deletion state machine" (V7-01, V7-02, V7-03, V7-04, V7-09, V7-11)

Write one section that is the sole authority for the client-side deletion lifecycle. Every other §8/§11/§11.3 sentence that describes client phases, gate scope, finalize behavior on the client, or completion/guarding presentation is superseded per Rule 4.

### 1a. Durable intent phases (`PeezyAccountDeletion-v1.json`, singleton)

```
prepared
  → data_confirmed          (server root proven DATA_DELETED, AUTH_GUARDING, or ACCOUNT_DELETED)
  → purging                 (eight owners + preference barrier + telemetry barrier, existing acks)
  → local_detaching         (existing reasons)
  → auth_finalize_dispatched   ONLY when proven root state was DATA_DELETED
  → guarding(authGuardAfter)   from finalize wire, OR directly from local_detaching when proven root was AUTH_GUARDING
  → completed                  from ACCOUNT_DELETED wire (finalize replay, or discover/begin/resume), OR directly from local_detaching when proven root was ACCOUNT_DELETED
  → local_cleared              exit for capability-invalid + definitivelyDeleted (see 1e)
```

Rules:
- `auth_finalize_dispatched` requires all eight acks and both barriers (existing L1307/L1311 text stands). Nothing enters it from `prepared`. **(V7-02)** A reducer receiving `authGuarding` or `accountDeleted` while `prepared` enters `data_confirmed`, purges, and then enters `guarding` or `completed` from `local_detaching` without calling finalize.
- `guarding` stores exact `authGuardAfter` from the wire that produced it.
- `completed` and `local_cleared` are consumed by their presentation actions as today.

### 1b. Server wires the client consumes

- discover/begin/resume: existing branches, plus exact `AUTH_GUARDING` wire `{schemaVersion:1,kind:"account_deletion_auth_guarding",operationId,authGuardAfter,replayed}` and exact `ACCOUNT_DELETED` wire (v7 §8:977 shapes, moved here).
- **finalize (V7-01)**: at `DATA_DELETED` performs Auth deletion and returns the `AUTH_GUARDING` wire above, `replayed:false`. At `AUTH_GUARDING` returns the same wire `replayed:true`. At `ACCOUNT_DELETED` returns the `ACCOUNT_DELETED` wire. Only transport/unknown errors retry. Delete every v7 sentence saying finalize at `AUTH_GUARDING` "returns only retry" (§8:991, §11:1275, §11.3:1512) and the `DELETION_RETRY_REQUIRED` "regardless of canonical user-not-found" clause at §11.3:1499 insofar as it applies to finalize.
- DELETING-sweeping: discover/begin/resume perform enrollment and the two-empty-sweep / sweeping→guarding transitions exactly as §11:1275/1307. DELETING-guarding: discover/begin/resume return `DELETION_RETRY_REQUIRED` and change no byte; client projects the queued snapshot. **(V7-04)** Restore §11.3:1482 to guarding; delete the sweeping no-write sentence.

### 1c. Gate scope

- `active|blocked` while intent is `prepared … auth_finalize_dispatched`: global, all UIDs (existing).
- `guarding(uid,authGuardAfter)`: forbids every deleted-UID dispatch; any other UID may sign in and dispatch ordinary work.
- `clear` after `completed`/`local_cleared` presentation is consumed.
- Different-UID `startDeletion`: BUSY in every phase except `guarding`; in `guarding`, the Option-B handoff (v7 §8:989 text, moved here). Add the fixture: crash between the guarding-intent unlink and the new UID's prepared-intent persist leaves an empty slot; relaunch finds no intent, gate `clear`, and the new UID's `startDeletion` restarts cleanly. **(V7-09)**

### 1d. Presentations

- `ACCOUNT_DELETION_GUARDING` `{schemaVersion:1,kind,authGuardAfter}`, copy `Deletion is in progress. Protected copies clear by {date}.` Shown in `guarding` only.
- `ACCOUNT_DELETION_COMPLETED` (existing shape) in `completed` only. Never before `ACCOUNT_DELETED`.
- `ACCOUNT_DELETION_LOCAL_CLEARED` `{schemaVersion:1,kind}`, copy `This account was deleted from another device. This device has been cleared.` No revocation members. Shown in `local_cleared` only. **(V7-03)**
- Update every closed enumeration of gate/presentation states (v7 §8:983, 999, 1008 and any other) to include `guarding-same-UID`, `guarding-other-UID`, and `local_cleared`. **(V7-11)**

### 1e. Capability-invalid exit (V7-03)

On capability-invalid where the cached expected user is `definitivelyDeleted` and no member/overflow branch is obtainable: enter `local_detaching(reason:"remote_unverified")`, complete the full local purge and both barriers, then `local_cleared`. No finalize call, no completion claim, no provider revocation claim. Fixtures: never-enrolled device after another device's Auth deletion; capability-invalid with Auth user still present (must NOT take this exit; existing behavior); crash at every step of the exit.

### 1f. Fixture list

Consolidate every client deletion fixture named across §8/§11/§11.3 into this section, add the new ones above, and assign each to its existing suite. Two-device crash-mid-purge row in §11.5 points here.

---

## Item 2 — V7-07 legacy lease

The `MIG-TRIGGER-V1` legacy-lease clause applies wherever the lease is read: initialization (§2.2:59/61), MIG-EVENT acquisition (§3.1:308), and first Phase 2 acquisition. A lease of exact shape `{runId,acquiredAt,expiresAt}` is migrated in the reading transaction; any other nonabsent shape still blocks. Fixtures at each of the three read sites.

## Item 3 — V7-08 timeout scope

Define `DELETION_PARTICIPATING_FUNCTIONS_V1` as the literal list of functions in `ACCOUNT_DELETION_FENCE_WRITERS_V1` ∪ `USER_OUTBOUND_PROVIDERS_V1` ∪ the deletion/scheduler/migration functions §11 names. The B-13 test scans that list only. `changeTaskPlan` is named as non-participating at its current 540s, unchanged.

## Item 4 — A-4 / V7-05, baseline d321547

The four files are authorized for Phase 2 edits, scoped by call site. State per file exactly what changes and nothing else:

- `functions/processInventory.js`: shared-fence call on every write path (process success/error, `onInventoryRoomWritten`); Anthropic call under the shared lease helper. Nothing else.
- `InventorySessionManager.swift`: the six `Firestore.firestore()` occurrences migrate to the Firestore-runtime owner; `pendingNarration` holds actor-issued lease handles only.
- `InventoryCameraView.swift`: `pendingNarrationTranscript` holds actor-issued lease handles only.
- `NarrationService.swift`: `start` requires an actor lease.

Remove the "receive no Phase 2 edit" / "verification-only" language for these files. Update §12.2 labels and totals. The §11 registries stay as they are (they were right). The `rg` gate at §12.2:1672 is satisfiable again.

## Item 5 — A-6 / V7-06

§1 pins the master at `80e6dbd361c2d85706f538bea96558a61904346536dcb8e069435488bf6bbb8a`, commit 7546a0f. Remove the HEAD pin. §12.1's A12 preamble edit and §2.5's "replace item 9" now resolve against committed bytes; verify and state so.

## Item 6 — P2s

- **V7-10**: remove `taskDisposition.js` / `notificationIntents.js` from the "existing" S2/S3 bullet.
- **V7-12**: absence-plus-retention destinations produce an `authResidualChecks` entry of exact shape `{ordinal,kind:"absence_retention",observedAbsentAt,retentionSeconds}`; partition sentence unchanged.
- **V7-13**: `targetPresent`/`quarantinePresent`, not `present`.
- **V7-14**: the eleventh static is named by its actual §11 type. If §11 names none, declare `FirestoreRuntimeOwner` in §11 where the Firestore runtime is defined, and cite it.

## Item 7 — §11.5

Update the Auth, two-device, and Keychain rows for the Item 1 states and wires. Table still adds zero obligations.

## Required output

1. `PHASE2_REPLACEMENT_MANIFEST_v8.md` and sha256.
2. Supersession list: every deleted v7 sentence by §:line → §8.9 subsection that replaces it.
3. Resolution table: V7-01 … V7-14 → v8 §:line → one sentence.
4. Recounted totals.
5. §13 gate items 1–6.
6. Any Rule 8 stop as a decision packet.
7. Statement: no implementation file modified.
