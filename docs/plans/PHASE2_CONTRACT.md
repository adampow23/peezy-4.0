# PHASE 2 CONTRACT

Extracted 2026-09-02 from `PHASE2_REPLACEMENT_MANIFEST_v8.md` (sha256 `12ea8ee1b1fcd43dc88a993ebc4b6706a4b3d8f2ed93ebd09a59d2399262a251`). This file states only what must be true for implementation: schemas, transitions, gates, registries, pins, and the test that falsifies each. Procedure, supersession ledgers, slice ownership, and review rules stay in the manifest. Where this file and v8 disagree, the "Reconciled" list at the end names the sentence that lost. `§n` cites v8; `Cn` cites this file. "Exact" means unknown, missing, null-for-optional, or surplus members reject. Amended 2026-09-02 (Reconciled 7): C7's Settings pin regained §12.2:1866's runtime-provider normalization clause, a v9 decision missed in extraction. Amended 2026-09-06 (Reconciled 8–9): the data-final wire is stated in C2.3, and the `taskReset` marker shape is reconciled; S2 mirrors/writes both, S3 consumes them. Amended 2026-09-06 (Reconciled 10): C2.8 carries, verbatim with source lines, the `inspectCommittedOperation` union, the `reconcileLegacyTaskReset` union and its legacy/migration authority, the `reset_progress`/`reset_final` receipts with the `rso1_` record/tombstone and dispatch rules, and `PHASE2_RESET_PROTOCOL_MODE`; C2.3 states wire time encoding, the `replayed` rule, unauthenticated resume, and that `DELETION_RETRY_REQUIRED` is thrown; Reconciled 9 names S2 as the marker's server writer; C7's Node pin is 24. Amended 2026-09-06 (Reconciled 11): the fence error member (C6.1), enrollment on every present branch (C2.3), Build A's evidence-absent retry member (C3), the marker `lease` inner shape and the detail-less `unavailable` responses (C2.8), runtime residual-retention validation against the check array (C3), and the deployment scope of the protocol-mode initialization rule (C2.8) are stated; each is what S2 built and S3 consumes.

Three decisions are applied throughout: (D1) the capability-invalid exit persists `detachReason:"capability_invalid"`, a token distinct from `remote_unverified`; (D2) the deletion gate clears when the terminal presentation is consumed, and §6.6 defers to §8.9; (D3) `absence_retention` residual checks carry `destinationOrdinals` with exactly one ordinal, and the partition covers both check kinds.

## C1 Frozen inputs

| Artifact | Pin |
|---|---|
| Frozen spec under repair | `docs/plans/PHASE2_EXECUTABLE_SPEC_v5.md` · 462,684 bytes · 2,148 lines · sha256 `e02ef93867b744ec0ace9c0860ac309cb7e5fc14ee8c4762a265bd544ca2d2ab` |
| Master baseline | `docs/plans/files/INSTITUTION_FLOWS_MASTER_v3.md` at commit `7546a0f` · sha256 `80e6dbd361c2d85706f538bea96558a61904346536dcb8e069435488bf6bbb8a` (no moving HEAD pin) |
| Four Build 25 WIP files | baseline commit `d321547`; authorized only at the call sites named in the C6.1 note |
| Resolution register | exactly the 36 IDs in C8: D1–D15, D18–D32, B1–B4, MIG-EVENT-V1, MIG-RESET-V1; D16/D17 withdrawn |

## C2 Client account-deletion state machine (§8.9)

§8.9 is the sole authority for client phases, wires, gate scope, presentation, the capability-invalid exit, and client fixtures. Nothing outside it may restate a phase, transition, or gate value.

### C2.1 Durable intent file

- Owner: one actor in `DurableStoreRecoveryCoordinator.swift`. Target `PeezyAccountDeletion-v1.json`, protection `.completeUntilFirstUserAuthentication`, no quarantine sibling.
- Envelope exact `{schemaVersion:1,fileKind:"ACCOUNT_DELETION_INTENT_V1",generationId,payload,sha256}`, cap 16,384 canonical bytes; `sha256` covers the complete canonical envelope with only itself omitted; replacement is unique-temp → complete write → file `fsync` → atomic rename → directory `fsync`.
- Payload exact `{schemaVersion:1,uid,authEpochUUID,credentialRevision,operationId,proofNonce,appleRevocation:"not_required"|"manual_required",googleRevocation:"not_required"|"sdk_disconnect_required"|"manual_required",googleProviderUid?,phase,purpose?,authorityKind?,detachReason?,stagedRoot?,startedAt?,dataDeletedAt?,authGuardAfter?,acks:[...],createdAt,updatedAt}`. `phase` ∈ `prepared|data_confirmed|purging|local_detaching|auth_finalize_dispatched|guarding|completed|local_cleared`. `detachReason` ∈ `auth_deleted|remote_unverified|capability_invalid` (D1). Every missing, surplus, unknown, wrong-phase, or cross-branch member rejects.
- `acks` is an exact displayed-order prefix of `["route","handoff","reset","workflow","room_capture","firestore_cache","notifications","google"]`.
- Provider dispositions are computed before the first intent write and are immutable; `googleProviderUid` is required only for `sdk_disconnect_required`; ambiguity chooses manual-required and never blocks deletion.
- Capability: `operationId = "adel1_" + <lowercase RFC-4122 UUID>`; `proofNonce` is 32 random bytes, unpadded base64url; server capability `{operationId,proofSHA256 = sha256(TaskCanonicalV1({uid,operation_id,proof_nonce}))}`.

### C2.2 Phase order and per-phase members

```text
prepared → data_confirmed → purging → local_detaching
  → auth_finalize_dispatched   only from stagedRoot:"DATA_DELETED"
  → guarding(authGuardAfter)   only from stagedRoot:"AUTH_GUARDING" or the finalize wire
  → completed                  only from detachReason:"auth_deleted" after an ACCOUNT_DELETED wire/root
  → local_cleared              only from detachReason:"capability_invalid" (C2.6)          [D1]
```

| Phase | Requires | Forbids |
|---|---|---|
| `prepared` | `purpose:"confirmed_begin"|"startup_discover"`, `acks:[]` | authorityKind, detachReason, stagedRoot, every server time |
| `data_confirmed` | `authorityKind:"member"|"authenticatedOverflow"`, `startedAt`, `dataDeletedAt`, `acks:[]` | purpose, detachReason, stagedRoot, authGuardAfter |
| `purging` | same authority and data times; ack prefix only | purpose, detachReason, stagedRoot, authGuardAfter |
| `local_detaching` (staged) | `stagedRoot:"DATA_DELETED"|"AUTH_GUARDING"`; retains authorityKind/startedAt/dataDeletedAt; `authGuardAfter` present iff `AUTH_GUARDING`, byte-copied from the wire | detachReason |
| `local_detaching` (nonstaged) | `detachReason` per D1; ack prefix only | purpose, authorityKind, stagedRoot, startedAt, dataDeletedAt, authGuardAfter |
| `auth_finalize_dispatched` | all eight acks, both barriers freshly proved, authority and data times | purpose, detachReason, stagedRoot, authGuardAfter; direct entry from `prepared` |
| `guarding` | all eight acks, authority and data times, exact wire `authGuardAfter` | purpose, detachReason, stagedRoot |
| `completed` | all eight acks, both barriers, immutable dispositions, prior ACCOUNT_DELETED authority; consumed only by `ACCOUNT_DELETION_COMPLETED` | purpose, authorityKind, detachReason, stagedRoot, every server time, authGuardAfter |
| `local_cleared` | all eight acks, both barriers, immutable dispositions, the C2.6 exit; consumed only by `ACCOUNT_DELETION_LOCAL_CLEARED` | same as `completed` |

- `detachReason` is absent iff `stagedRoot` is present; both present or both absent rejects.
- Terminal mapping for nonstaged variants (D1): `auth_deleted → completed`; `remote_unverified →` the existing remote-unconfirmed terminal (linked all-scope handoff plus the C2.5 remote-unconfirmed presentation), entering neither `completed` nor `local_cleared`; `capability_invalid → local_cleared`. Relaunch at any phase resolves the terminal from intent bytes alone; no cached observation, journal member, or completion file selects it.
- Every `local_detaching` variant executes the complete eight-owner detach work plus the preference and telemetry barriers before its next transition. Staged DATA_DELETED clears `stagedRoot` and enters `auth_finalize_dispatched`; staged AUTH_GUARDING clears `stagedRoot`, preserves the deadline, and enters `guarding`.
- A reducer in `prepared` receiving an `authGuarding` or `accountDeleted` wire stores the data authority, enters `data_confirmed`, performs `purging`, executes every owner and both barriers, then enters `guarding` or `completed` without calling finalize. Data-final success/replay routes `data_confirmed → purging →` staged DATA_DELETED `local_detaching → auth_finalize_dispatched`.
- Clocks, generation/hash/inode CAS, and forward/equal/backward injected-clock behavior are exact; clock failure or a nonrepresentable instant writes nothing.
- Singleflight: an intent-linked UID purge has absolute priority; an all-scope or different-UID request waits and reclassifies after all eight owners and both barriers; an all-scope ack is never mirrored into the UID intent. Launch resumes a valid intent and matching UID journal before creating any signed-out/all-scope journal.
- Terminal consumption: a `completed` or `local_cleared` intent stays durable and keeps the gate nonclear while C2.5 publishes its presentation; only that presentation's exact-snapshot acknowledge consumes the phase. Then, in order: conditionally sign out only a matching Firebase user → create the all-scope journal with byte-matching `terminalDeletionLink` before unlinking the intent → repeat all eight owners plus both barriers → unlink/fsync the intent → unlink/fsync the journal → publish `clear`. A nonmatching all-scope-plus-intent pair is `LOCAL_PRIVACY_PURGE_FAILED`; a surviving linked journal is crash-recovery authority; a surviving terminal intent recreates the presentation.
- Eight owners: route (`AppRouteInbox`), handoff (`HandoffSessionStore`), reset (`ResetOperationRegistry`), workflow, room_capture (`RoomCaptureArtifactOwner`), firestore_cache (`FirestoreRuntimeOwner`: `terminate()` without `waitForPendingWrites()` → `clearPersistence()` → fresh instance → probe), notifications (`NotificationIdentityAuthority`: unregister, remove delivered/pending, badge zero → `Messaging.messaging().deleteData` → `Installations.installations().delete`), google (`GoogleIdentityAuthority`: `disconnect(expectedProviderUID:)` acked only on exact `disconnected` for `sdk_disconnect_required`; `manual_required|not_required` acks with no SDK mutation; all-scope `signOutAll()`). For route/handoff/reset/workflow an ack requires fresh bounded postcondition rereads; an unprovable source is privacy-wipe-only with fixed `LOCAL_ACCOUNT_PURGE_WHOLE_STORE`.
- Preference barrier: remove the C6.6 keys, `CFPreferencesAppSynchronize` success, reread absence. Telemetry barrier: `Analytics.setAnalyticsCollectionEnabled(false)`, `setUserID(nil)`, `setUserProperty(nil,forName:"has_subscription")`, `resetAnalyticsData()`, then the sole process-lifetime `checkForUnsentReports`; `false` = cleared; `true` calls `deleteUnsentReports()` once and stays blocked as `LOCAL_PRIVACY_PURGE_FAILED` with copy `Close and reopen Peezy to finish clearing local diagnostics.` until a fresh process observes `false`. Sessions/MetricKit are OS-owned and outside the promise; collection is bundled off (`FIREBASE_ANALYTICS_COLLECTION_ENABLED=false`, `FirebaseCrashlyticsCollectionEnabled=false`, `FirebaseMessagingAutoInitEnabled=false`).

### C2.3 Server wires consumed by the client

- `AccountDeletionRemoteProviding.perform(_ request: AccountDeletionRequestV1) async throws -> AccountDeletionRemoteResultV1`; requests are only `discover|begin|resume|finalize(uid,operationId,proofNonce)`; authority kind `member|authenticatedOverflow`; the existing absent and data-final branches remain.
- Absent wire exact `{schemaVersion:1,kind:"account_deletion_discovery",state:"absent",operationId}` (marker absence; zero write). Data-final wire exact `{schemaVersion:1,kind:"account_deletion_data_final",operationId,authorityKind:"member"|"authenticatedOverflow",startedAt,dataDeletedAt,replayed}`, returned or replayed by a later discover/begin/resume against an exact DATA_DELETED marker (restored from manifest v7:1307; Reconciled 8).
- Guarding wire exact `{schemaVersion:1,kind:"account_deletion_auth_guarding",operationId,authorityKind,startedAt,dataDeletedAt,authAbsenceObservedAt,authGuardAfter,replayed}`. Deleted wire exact `{schemaVersion:1,kind:"account_deletion_account_deleted",operationId,authorityKind,startedAt,dataDeletedAt,authAbsenceObservedAt,authGuardAfter,authGuardCompletedAt,accountDeletedAt,replayed}`. Every value is copied from the validated root; Auth state alone never synthesizes a branch.
- Finalize: at DATA_DELETED performs the bounded evidence fence and Auth deletion, creates/adopts the Auth work row, returns the guarding wire with `replayed:false`; at AUTH_GUARDING returns it with `replayed:true`; at ACCOUNT_DELETED returns the deleted wire. Only transport or unknown errors retry; user-not-found never yields `DELETION_RETRY_REQUIRED`.
- Thrown union: `REQUEST_INVALID(field)`, `AUTH_REQUIRED`, `DELETION_CAPABILITY_INVALID`, `DELETION_RETRY_REQUIRED`; any unknown code, detail, or member is protocol ambiguity and retains durable bytes. Every member is thrown as an `HttpsError` whose `details` is exactly `{schemaVersion:1,reason:"REQUEST_INVALID",field}` (`invalid-argument`), `{schemaVersion:1,reason:"AUTH_REQUIRED"}` (`unauthenticated`), `{schemaVersion:1,reason:"DELETION_CAPABILITY_INVALID"}` (`permission-denied`), or `{schemaVersion:1,reason:"DELETION_RETRY_REQUIRED"}` (`unavailable`); no member is ever a returned map (Decision 5, 2026-09-06; §11:1437).
- Wire times: every `startedAt`, `dataDeletedAt`, `authAbsenceObservedAt`, `authGuardAfter`, `authGuardCompletedAt`, and `accountDeletedAt` on a wire is the canonical UTC RFC 3339 millisecond string `YYYY-MM-DDTHH:MM:SS.mmmZ` of the corresponding root Timestamp; every C3 root, work-row, and reconciler-state time is written at millisecond precision, so the wire string and the stored value denote the same instant byte-for-byte (Decision 3, 2026-09-06).
- `replayed` is `false` only when the responding transaction itself performed the root transition that produced the wire (finalize's DATA_DELETED → AUTH_GUARDING); every other response, including every data-final wire, every deleted wire, and every discover/begin/resume return of a guarding or deleted wire, carries `replayed:true`. The client never branches on it (C2.2) (Decision 3, 2026-09-06).
- Resume may be unauthenticated but only continues for an exact member and never adds or retargets one (§11:1435).
- DELETING-sweeping: discover/begin/resume may mutate only capability enrollment and the two-empty-sweep → guarding transition; the two-empty-sweep transaction itself throws the `DELETION_RETRY_REQUIRED` member. DELETING-guarding: they throw `unavailable` with details exact `{schemaVersion:1,reason:"DELETION_RETRY_REQUIRED"}`, change no byte, and the client stays `prepared` projecting the queued presentation. Startup and Retry reuse the same durable capability until DATA_DELETED or a later root wire.
- Enrollment on every present branch (Reconciled 11): capability classification runs against every valid marker. At DELETING-sweeping, DATA_DELETED, AUTH_GUARDING, and the permanent ACCOUNT_DELETED tombstone, an authenticated discover/begin whose capability is a distinct nonmember below 64 appends it (canonically resorted, every time/state byte preserved) and becomes `member`; at 64 it becomes request-scoped `authenticatedOverflow` with zero write; an exact member is `member` with zero write; the same `operationId` with a different proof is `DELETION_CAPABILITY_INVALID`. DELETING-guarding alone changes no byte. The tombstone's capability list may therefore grow after ACCOUNT_DELETED (§11:1435).

### C2.4 Gate scope and identity handoff

- `StartupBarrier` owns `AccountDeletionGate = loading|clear|active(uid)|guarding(uid,authGuardAfter)|blocked`. The closed consumer projection is `clear|loading|blocked|active-same-UID|active-other-UID|active-with-nil-current-UID|guarding-same-UID|guarding-other-UID|local_cleared`; every enumeration uses all applicable members. Deletion, journal, and presentation classification complete before any store publishes readiness.
- `prepared` through `auth_finalize_dispatched`: `active|blocked` is global for all UIDs and forbids every UID-bearing dispatch, nonreducer server call, protected callback, presentation, opener, Firestore acquisition/use, recording start, and notification-token registration.
- `guarding(deletedUID,authGuardAfter)`: forbids every deleted-UID dispatch and protected operation; permits another UID to sign in and dispatch ordinary work after all non-UID barriers clear; permits the deleted UID only its exact Retry reducer.
- `clear` is published only after the `completed` or `local_cleared` presentation action is consumed (D2). Auth callback URLs and route dispatch obey the same UID scope.
- Consumer admission: fresh room capture requires the current signed UID and `clear`; gate activation closes the room/media registry and forbids narration materialization or a next segment; Firestore cannot be acquired before its purge ack; notification registration authority is true only for `clear` plus a matching signed-auth/startup-discovery generation; notification taps during a nonclear gate take the no-op result and finish exactly once.
- Every SIGNED_OUT transition and direct A→B switch enters `loading`, creates/resumes the crash-durable all-accounts purge, and may publish `clear` or B only after the journal and startup discovery finish. That purge claims no remote deletion or revocation; provider/offline failure is `blocked` with Retry.
- Different-UID `startDeletion` returns exact local `{schemaVersion:1,reason:"ACCOUNT_DELETION_BUSY"}` in every phase except `guarding`; the same UID joins the singleton and never replaces its capability. In `guarding`, Option B byte-matches server AUTH_GUARDING authority and every local postcondition, CAS-unlinks/fsyncs the guarding intent, reclassifies, and persists the new UID's `prepared` intent before its first await. A crash between unlink and persist leaves the slot empty: relaunch finds no intent, publishes `clear`, and the next `startDeletion` restarts cleanly. Any missing, malformed, unavailable, DATA_DELETED, or ACCOUNT_DELETED observation or local/CAS/auth drift refuses the handoff with retained bytes.

### C2.5 Presentations

| Kind | Exact map / copy |
|---|---|
| queued | `{schemaVersion:1,state:"account_deletion_queued",copy:"Deletion is queued while Peezy finishes clearing protected copies. You can close the app and try again later.",availableActions:["retry"]}` |
| blocked | `{schemaVersion:1,state:"account_deletion_recovery_unavailable",reason:"FILE_IO"|"REMOTE_UNAVAILABLE"|"REMOTE_MALFORMED"|"LOCAL_PRIVACY_PURGE_FAILED",availableActions:["retry"]}` |
| guarding | `{schemaVersion:1,kind:"ACCOUNT_DELETION_GUARDING",authGuardAfter,copy:"Deletion is in progress. Protected copies clear by {date}."}`; `{date}` from the stored server deadline under the frozen formatter |
| completed | `{schemaVersion:1,kind:"ACCOUNT_DELETION_COMPLETED",appleRevocation:"not_required"|"manual_required",googleRevocation:"not_required"|"revoked"|"manual_required"}`; never before an ACCOUNT_DELETED wire |
| local_cleared | `{schemaVersion:1,kind:"ACCOUNT_DELETION_LOCAL_CLEARED"}`; copy `This account was deleted from another device. This device has been cleared.`; no revocation members |
| remote-unconfirmed | `{schemaVersion:1,kind:"ACCOUNT_DELETION_REMOTE_UNCONFIRMED"}`; copy `Local data for this account was removed, but remote account deletion could not be verified. Sign in again to retry if the account still exists.`; never server completion |

- Completion file `PeezyAccountDeletionCompletion-v1.json`, owner `LocalPrivacyPurgeCoordinator.swift`, envelope `fileKind:"ACCOUNT_DELETION_COMPLETION_V1"`, cap 4,096, payload exact `{schemaVersion:1,result,createdAt}`; `result` is exactly one of completed, local-cleared, or remote-unconfirmed; the file carries no UID, auth tuple, operation/proof, provider UID/token, server time, or user content. Entry to `completed` or `local_cleared` derives it before publication; the honest remote-unverified branch derives it before its existing handoff. Exact replay preserves bytes; a different pending snapshot blocks; write failure retains the source phase.
- `CompletionSnapshotV1 = {generationId,sha256,result,createdAt}`. `AccountDeletionCompletionPresenting`: `current() async -> CompletionSnapshotV1?` (nil only for observed absence); `acknowledge(expectedGenerationId:expectedSHA256:) async -> acknowledged|stale|failed`; `open(expectedGenerationId:expectedSHA256:provider:) async -> opened|stale|notOffered|failed`, provider `apple|google`. Both reread complete bytes/device/inode and require the expected generation/hash; drift makes zero opener or unlink call. Acknowledge is the sole consuming action. Open is offered only for the matching manual-required provider and its frozen URL and never consumes.
- Surface: title `Account deleted`; body `Your Peezy account was deleted.`; button `Done`. Apple manual-required adds `Your Peezy account was deleted. To stop using Sign in with Apple for Peezy, open Settings, tap your name, tap Sign in with Apple, select Peezy, then tap Delete.` and `Apple instructions` → `https://support.apple.com/102571`. Google manual-required adds `Your Peezy account was deleted. To stop using Sign in with Google for Peezy, open your Google Account's linked apps, select Peezy, and choose Stop using Sign in with Google.` and `Google instructions` → `https://support.google.com/accounts/answer/13533235?hl=en`. Both-manual order is Apple then Google. Local-cleared shows only its copy and `Done`; remote-unconfirmed uses title `Deletion not verified`, its copy, and `Done`.
- Sign in with Apple stays manual (no `authorizationCode` or server token is captured). Apple `revoked|notFound` for still-matching authority signs out and resumes only an already-named deletion; `authorized` is a no-op; every other state emits fixed `APPLE_CREDENTIAL_STATE_UNRESOLVED`.

### C2.6 Capability-invalid exit (D1)

- Trigger: `DELETION_CAPABILITY_INVALID` while `confirmAccountDeleted(expected:)` returns exact `definitivelyDeleted` (provider still holds the cached user, epoch unreplaced, forced refresh fails with Firebase user-not-found) and no member or authenticated-overflow branch is obtainable.
- The reducer persists nonstaged `local_detaching(detachReason:"capability_invalid")` before any purge work, executes the full local purge and both barriers, and enters `local_cleared`. It makes no finalize call, asserts no ACCOUNT_DELETED completion, and claims no Apple/Google revocation.
- Capability-invalid while the Auth user remains present must not take this exit. Confirmed-begin `notProven` and startup-discover absence remain separate and never project `ACCOUNT_DELETION_LOCAL_CLEARED`.
- The honest `remote_unverified` branch persists `detachReason:"remote_unverified"`, takes the remote-unconfirmed presentation and linked all-scope handoff, and enters neither `completed` nor `local_cleared`.

### C2.7 Client fixture ownership (§8.9.6)

- `Peezy 4.0Tests/DurableStoreRecoveryTests.swift`: every intent phase/member cross-product (exact/missing/surplus/unknown); every presentation map; stagedRoot/detachReason both-present/both-absent rejection; staged retention; `authGuardAfter` iff AUTH_GUARDING; prepared→data_confirmed→purging→local_detaching routing; all eight acks; selective and whole-source purge; both barriers; clocks; malformed/over-cap/FILE_IO intent and completion classification; exact-snapshot consumption; link nonconsumption; stale CAS; provider paragraphs/labels/URLs/titles/copy; singleflight priority; A→B and mid-purge journal precedence; crash/relaunch at every file, phase, ack, barrier, detach, finalize-dispatch, guarding, completion, local-cleared, presentation, sign-out, terminal-link, intent-unlink, journal-unlink, and gate boundary; signed-in reinstall at every server root; response loss; 64-member/overflow; capability-invalid never-enrolled remote deletion; Auth-user-present refusal of that exit; Option-B unlink→empty-slot→clean-restart; purge-journal envelope/atomic replacement; narration, media, Firestore cache, and telemetry cases.
- `Peezy 4.0Tests/AppRootAuthRaceTests.swift`: Firebase/Google/Apple authority drift and Apple credential state; manual sign-out versus user-not-found; A→B; consumer projection for all nine gate states; same-UID guarding refusal; second UID sign-in and dispatch while the first guards; auth-callback UID scope; guarding relaunch; completion/local-cleared survival across auth-root replacement; both-manual nonconsuming links; stale A→B callbacks; the eleven runtime `ObjectIdentifier` identities; pinned Messaging/Installations API order; A-disconnect/B-sign-in interleavings.
- `functions/tests/accountDeletionFence.test.js`: exact discover/begin/resume/finalize request and wire maps; decoder mirrors; enrollment and overflow; sweeping mutation versus guarding no-write; finalize `replayed:false`/`true`/deleted replay; transport/unknown retry only; signed-out member replay; two-device/lost-response roots; residual guard exact/equal/+1; no completed result or presentation authority before ACCOUNT_DELETED.
- No new Swift test file or suite beyond `DurableStoreRecoveryTests` and `AppRootAuthRaceTests`; no new Node test file beyond `accountDeletionFence.test.js`.

### C2.8 Server wires consumed by the reset and recovery clients (Reconciled 10)

Each block is copied verbatim from the cited source line; S2 mirrors it on the server and S3 consumes it on the client. "Above"/"below" inside a block refers to the same block.

**`inspectCommittedOperation` (v9 §7:830, 832–839, 841, 843)**

§7:830 — `receipt_mismatch` is narrower than item recovery and uses one authenticated read-only action in existing `functions/taskPlan.js`: `inspectCommittedOperation`. Its request is the exact nested union `{action:"inspectCommittedOperation",family,authority,requestAuthority,identityDigest}`. Every hash is a lowercase full SHA-256, every ID/token follows its frozen grammar, and every missing, surplus, or cross-branch member rejects. Family projections are literal:

| `family` | exact request `authority` | exact `requestAuthority` | exact read set and accepted stored shape | legal outcomes |
|---|---|---|---|---|
| `ROUTE_CLAIM` | `{operationId}` | `{requestSHA256}` | `users/{uid}/taskPlanOperations/{operationId}`; exact ordinary `INTENT_CLAIM/COMMITTED`, action `claimTaskIntent`, matching owner/ID/hash/identity, exact stored task-route response | `absent|committed` |
| `HANDOFF` | `{operationId}` | `{requestSHA256}` | same task-plan-operation path; exact ordinary `TASK_OPERATION/COMMITTED`, the candidate's retained handoff action, matching owner/ID/hash/identity, exact stored response | `absent|committed` |
| `HANDOFF_CANCEL` | `{operationId}` | `{requestSHA256}` | same path; exact ordinary `TASK_OPERATION/COMMITTED`, action `cancelHandoff`, matching owner/ID/hash/identity, exact stored response | `absent|committed` |
| `RESET` | `{operationId}` | `{requestFingerprint}` | one read-only transaction/same-read-time snapshot of `users/{uid}/taskPlanOperations/{operationId}` and root `users/{uid}`; exact `RESET_OPERATION` with matching owner/canonical ID/fingerprint/identity plus total active marker equality, or finalized tombstone plus marker absence; active deleting/awaiting is pending, finalized reconstructs its frozen final receipt | `absent|pending|committed` |
| `LEGACY_RESET_MIGRATION` | `{migrationId}` | `{requestFingerprint}` | `users/{uid}/legacyResetMigrations/{migrationId}`; exact permanent migration kind/owner/derived ID/fingerprint/identity/outcome and its exact §6.2 response projection | `absent|committed` |
| `WORKFLOW` | `{submissionToken}` | `{requestFingerprint}` | derive `workflowSubmissionId = "ws2_" + first40(SHA-256(TaskCanonicalV1({owner:uid,submissionToken})))`; read only root `workflowSubmissions/{workflowSubmissionId}`; require exact owner/token/fingerprint/identity and stored workflow outcome | `absent|committed` |

§7:841 — The RESET request authority must equal the already-frozen `"reset1_" + SHA-256(TaskCanonicalV1({kind:"reset",reason:"retake_assessment",expected_task_generation_epoch:e}))`. LEGACY_RESET_MIGRATION must equal the exact alias-free `rlmreq1_` derivation in §6.2 over only UID and legacy operation ID. The workflow fingerprint is recomputed from fully validated local `requestCanonicalJSON` under the frozen workflow fingerprint rule and is not the complete-request SHA-256. For every family, request `identityDigest` is exactly the same full lowercase SHA-256 used as that row's `mismatchIdentityDigest` over the exact private identity map below; no second identity projection exists. The handler authenticates UID, performs exactly that table row's read set, and performs no create/update/delete. From the authenticated UID and fully validated stored operation/response—or the reset/migration/workflow authority named in that row—it reconstructs that exact map, hashes `TaskCanonicalV1(map)`, and requires equality; the client digest is never accepted as a substitute for field validation. RESET pending reconstructs and validates the exact current progress projection from the active operation plus matching root marker; RESET committed reconstructs and verifies the final receipt/digest from its tombstone and marker absence. Migration committed reconstructs the exact §6.2 response from its terminal permanent record; neither family assumes a receipt map is stored verbatim.

§7:843 — The result is exactly `{schemaVersion:1,kind:"committed_operation_inspection",accountUid,family,authority,requestAuthority,identityDigest,outcome,receipt?}`. For WORKFLOW only, returned `authority` is `{submissionToken,workflowSubmissionId}`; every other branch echoes its exact request authority. That expanded workflow member is response-validation data only: the provenance key and every retained local request authority always use the request-form `authority:{submissionToken}` and never `{submissionToken,workflowSubmissionId}`. `receipt` is required only for `committed` and forbidden for absent/pending. Ordinary route/handoff/cancel and workflow return their exact stored response with only outer `replayed:true`; a RESET tombstone reconstructs exact `reset_final` with `replayed:true`; LEGACY_RESET_MIGRATION reconstructs its exact §6.2 response with only the outer reconciliation `replayed:true` while preserving every already-frozen nested receipt replay flag. Active RESET is the sole pending case and returns no receipt. Receipt reconciliation always enters the loaded/replay local application path and never invokes first-response ephemeral notification, accounting, or callback behavior. A present malformed, wrong-owner/kind/action/path-ID/fingerprint/hash/identity/receipt record returns exact no-write `failed-precondition/OPERATION_REUSED`, naming `operationId` for every non-WORKFLOW family (including legacy migration) and `submissionToken` only for WORKFLOW. For inspect only, invalid top-level/type/member-set input is exactly `invalid-argument/{schemaVersion:1,reason:"REQUEST_INVALID",field:"request"}`; otherwise the first invalid value in exact order `action,family,authority,requestAuthority,identityDigest` names that literal field. A branch-incompatible authority or requestAuthority shape names that member; every unknown or surplus member names `request`. Unauthenticated inspection is exactly `unauthenticated/{schemaVersion:1,reason:"AUTH_REQUIRED"}`. Malformed or colliding stored authority uses only the already-stated `failed-precondition/OPERATION_REUSED` shape. No other inspection error detail is legal, and transport ambiguity is never synthesized. Fixtures cover every row of the table, every replay projection and zero first-response side effect, RESET as the sole pending member, literal root workflow path/derived ID/wrong owner, request-form versus expanded workflow authority, zero `taskPlanOperations` read for workflow, and missing/wrong/surplus/cross-family values for every request field in the exact precedence order.

**`reconcileLegacyTaskReset` and the legacy/migration authority (v9 §6.1:577–600, §6.2:608–664, §6.3:666–689, §6.4:693/699)**

§6.1:577–583 — Accepted legacy operation maps are exactly:

```text
L-deleting = {kind:"reset",fingerprint,deletedCount,state:"deleting",at}

L-tasks-deleted = {kind:"reset",fingerprint,deletedCount,state:"tasks_deleted",at,
 tasks_deleted:{reset:true,deletedCount,replayed:false}}

L-finalized = {kind:"reset",fingerprint,deletedCount,state:"finalized",at,
 tasks_deleted:{reset:true,deletedCount,replayed:false},
 finalized:{reset:true,deletedCount,replayed:false},finalizedAt}
```

§6.1:585 — `fingerprint = "reset1_" + SHA-256(committed legacy canonical({kind:"reset",reason:"retake_assessment"}))`; counts are equal safe nonnegative integers; times are Firestore timestamps.

§6.1:589–594 — Accepted legacy markers are exactly:

```text
M-deleting = {operationId,state:"deleting",deletedCount,
 workerLease:null|{workerId,expiresAt},startedAt}

M-awaiting = {operationId,state:"awaiting_local_reset",deletedCount,
 workerLease:null,startedAt}
```

§6.1:596 — `workerLease` is either literal null or exact `{workerId,expiresAt}`; worker ID is a lowercase RFC 4122 UUID and expiry is a Firestore Timestamp. For either active accepted pair, `M.operationId == requested legacyOperationId`, `M.deletedCount == L.deletedCount`, and `L.at == M.startedAt` byte-for-byte; a present worker lease additionally requires `expiresAt > startedAt` (it may be expired at migration time). Every nested `deletedCount` equals the operation's top-level count. Finalized additionally requires `finalizedAt >= at`.

§6.1:598 — The transaction reads the requested operation, the root marker, and—when a marker is present—the marker's operation before classifying. With no marker, requested L absent → `not_dispatched`; requested L-finalized → `finalized_compat`; requested L-deleting/tasks-deleted/malformed → `LEGACY_RESET_CORRUPT`. With an exact legacy marker, the matching requested L-deleting/M-deleting or L-tasks-deleted/M-awaiting pair → `upgraded`. If that exact active legacy marker belongs to a different ID B, requested A absent or finalized returns exact no-write `failed-precondition/{schemaVersion:1,reason:"LEGACY_RESET_MIGRATION_REQUIRED",legacyOperationId:B}`; requested A active/malformed is corruption. No migration record for A is created and no B/root byte changes. The local redirect rule in §6.5 then makes the immutable request about the actual active authority B before any further server call.

§6.1:600 — With an exact active Phase-2 marker C and its byte-matching canonical operation, a requested record that is absent, finalized legacy, or that same Phase-2 canonical record → permanent `phase2_active` for A carrying C's exact progress projection, without changing C/root. A requested legacy-active/malformed record beside C is corruption. Any requested Phase-2 record/tombstone that is not the byte-matching authority selected by that exact active marker is `LEGACY_RESET_CORRUPT` with `recordClass:"phase2"` and zero writes. Every malformed/orphan marker, mismatched active pair, wrong count/fingerprint/time/lease relation, or active operation without its marker is likewise `LEGACY_RESET_CORRUPT`, zero writes. Thus both a requested alias that is itself current Phase-2 authority and an unrelated current Phase-2 authority use the same durable `phase2_active` branch.

§6.2:608–618 — The server authority identity is deterministic, but the reset alias is not. Define:

```text
migrationId = "rlm1_" + first40(SHA-256(TaskCanonicalV1({
  account_uid:uid,legacy_operation_id:legacyOperationId
})))
requestFingerprint = "rlmreq1_" + SHA-256(TaskCanonicalV1({
  account_uid:uid,legacy_operation_id:legacyOperationId
}))
migrationAlias = "rsa1_" + <fresh lowercase RFC-4122 UUIDv4>
```

Freeze parity fixture: UID `phase2-rule-owner` and legacy ID `20000000-0000-4000-8000-000000000001` yield migration ID `rlm1_0a4d53a438873090f69e4255426310b0feb4cfd6` and request fingerprint `rlmreq1_0a4d53a438873090f69e4255426310b0feb4cfd63eabd6ce68c851ce827ad8e1`; its alias is any separately validated fresh `rsa1_` UUIDv4 candidate.

§6.2:622 — `rlm1_` remains reserved on every client-supplied operation/claim/submission/reset/legacy ID surface, but reservation is defense in depth rather than the migration-authority namespace. Ordinary actions reject it after their frozen normalization and before any authenticated document lookup, using their existing `invalid-argument/REQUEST_INVALID` field. Raw legacy reset/finalize rejects normalized `rlm1_` as `{schemaVersion:1,reason:"REQUEST_INVALID",field:"operationId"}`; reconciliation rejects client-supplied `legacyOperationId` beginning `rlm1_` with `field:"legacyOperationId"`. The migration authority lives only at the new server-only path in §6.3, which no shipped client or old callable could preoccupy. A historical `taskPlanOperations/{migrationId}` document is never read as migration authority and cannot block reconciliation.

§6.2:624 — `changeTaskPlan` adds authenticated exact request `{action:"reconcileLegacyTaskReset",legacyOperationId,migrationAlias}`. The server validates `migrationAlias` as exact `ResetAliasV1` with `rsa1_` plus lowercase RFC-4122 UUIDv4 syntax; it never recomputes the random value. It derives `migrationId` and alias-free `requestFingerprint`, then reads `users/{uid}/legacyResetMigrations/{migrationId}` first. A valid matching record is replay authority and returns its stored `migration_alias`, even when it differs from the request candidate; malformed, wrong-owner, wrong-ID, wrong-kind, or wrong-fingerprint content is `OPERATION_REUSED`. Only when that path is absent does the transaction classify the legacy/root authority and, immediately before any record creation, read `users/{uid}/taskPlanOperations/{migrationAlias}`. An occupied proposed alias returns the exact zero-write collision below. A valid migration record always takes precedence over candidate occupancy, so concurrent devices converge on the winner's stored alias.

§6.2:626–649 — Success union is exact:

```text
{schemaVersion:1,kind:"legacy_reset_reconciliation",
 outcome:"not_dispatched",migrationId,legacyOperationId,migrationAlias,
 accountUid,replayed}

{schemaVersion:1,kind:"legacy_reset_reconciliation",
 outcome:"upgraded",migrationId,legacyOperationId,migrationAlias,
 accountUid,sourceState:"deleting"|"tasks_deleted",replayed,
 progressReceipt:<exact Phase-2 reset_progress>}

{schemaVersion:1,kind:"legacy_reset_reconciliation",
 outcome:"phase2_active",migrationId,legacyOperationId,migrationAlias,
 accountUid,replayed,
 progressReceipt:<exact Phase-2 reset_progress>}

{schemaVersion:1,kind:"legacy_reset_reconciliation",
 outcome:"finalized_compat",migrationId,legacyOperationId,migrationAlias,
 accountUid,sourceState:"finalized",replayed,
 legacyFinalReceipt:{schemaVersion:1,kind:"legacy_reset_final",
   operationId:legacyOperationId,replayed:false,accountUid,
   deletedCount,state:"finalized"}}
```

§6.2:651 — For `upgraded`, `progressReceipt.replayed` is literal `false` because that reconciliation transaction creates the canonical Phase-2 reset. For `phase2_active`, `progressReceipt.replayed` is literal `true` because it projects a preexisting canonical reset without mutating it. These inner values are stored permanently and never change; replay of the migration changes only outer `replayed:false→true`. An opposite or missing inner value is a protocol error and writes no local receipt. First-call and replay fixtures freeze both outcomes and both replay layers.

§6.2:653–664 — Only outer replay changes on reconciliation replay. The D30 actions plus cutoff/discovery branches use this closed mapping; existing common reasons retain the frozen member names, while the migration-specific rows extend §4.6. Every unshown member is forbidden:

| Firebase code | Exact details |
|---|---|
| `unauthenticated` | `{schemaVersion:1,reason:"AUTH_REQUIRED"}` |
| `invalid-argument` | `{schemaVersion:1,reason:"REQUEST_INVALID",field:"request"|"action"|"legacyOperationId"|"migrationAlias"}` |
| `failed-precondition` | `{schemaVersion:1,reason:"OPERATION_REUSED",operationId}` |
| `failed-precondition` | `{schemaVersion:1,reason:"LEGACY_RESET_CORRUPT",context:"reconcile",legacyOperationId,recordClass,markerClass}` |
| `failed-precondition` | `{schemaVersion:1,reason:"LEGACY_RESET_CORRUPT",context:"inspect",recordClass,markerClass}` |
| `failed-precondition` | `{schemaVersion:1,reason:"LEGACY_RESET_MIGRATION_REQUIRED",legacyOperationId}` |
| `failed-precondition` | `{schemaVersion:1,reason:"LEGACY_RESET_ALIAS_OCCUPIED",legacyOperationId,migrationAlias}` |
| `failed-precondition` | `{schemaVersion:1,reason:"CLIENT_UPGRADE_REQUIRED",requiredProtocol:"phase2"}` |

§6.3:666 — `operationId` in OPERATION_REUSED is the deterministic migration ID. Both corruption cases use recordClass `absent|deleting|tasks_deleted|finalized|phase2|malformed` and markerClass `absent|deleting|awaiting_local_reset|phase2|malformed`; reconcile requires its requested legacy ID, while inspection intentionally exposes none. `recordClass:"phase2"` classifies only an occupied/malformed derived canonical reset path; candidate alias occupancy has its own exact error and never becomes corruption. `RESET_ACTIVE` is not a legal reconciliation result; receipt of that error for this action is a protocol contradiction because exact active Phase-2 authority must be committed as `phase2_active`. `field:"request"` covers a non-map, missing/unknown/surplus member set; otherwise validation reports the first value-invalid field in request member order. Every semantic error, including alias occupancy, writes nothing. Transport loss has no synthetic result.

§6.3:670–679 — Add permanent client-denied server-authority member:

```text
{schema_version:1,kind:"LEGACY_RESET_MIGRATION",account_uid,
 migration_id,legacy_operation_id,migration_alias,request_fingerprint,
 outcome:"not_dispatched"|"upgraded"|"phase2_active"|"finalized_compat",
 source_state?,expected_task_generation_epoch?,task_generation_epoch?,
 canonical_operation_id?,active_move_event_id?,progress_receipt?,
 legacy_final_receipt?,created_at}
```

§6.3:681 — Not-dispatched forbids source/epoch/canonical/move/receipts. Upgraded requires source deleting/tasks_deleted, adjacent safe epochs, canonical/move IDs, and progress; forbids legacy final. Phase2-active requires adjacent safe epochs, canonical/move IDs, and exact progress; forbids source state and legacy final. Finalized-compat requires source finalized and exact compatibility receipt; forbids epoch/canonical/move/progress. Cap 16,384 canonical bytes; no TTL; excluded from ordinary reset deletion. Its permanent path is exactly `users/{uid}/legacyResetMigrations/{migrationId}`; stored `migration_id == migrationId ==` the deterministic derivation, `account_uid == uid`, and the path ID is never `legacyOperationId`, `migrationAlias`, or the canonical reset ID. Create-only/exact-existing semantics apply. `LEGACY_RESET_MIGRATION` is forbidden from the `taskPlanOperations` operation union. Any such old-location document is an unrelated decoy. Original legacy operation stays byte-identical. This server-only record is the permanent raw-alias fence: every delayed legacy reset/finalize reads it before root or legacy-operation state. It is retained through reset completion and deleted only by the recursive account-deletion sweep.

§6.3:683 — Every fresh reconciliation transaction uses the frozen retry-attempt `migrationAt = server_write_time`; retry obtains a new value, while exact replay preserves committed bytes. Transaction precedence is literal: (1) read the server-only migration path; (2) replay a complete matching record using its stored alias, regardless of the proposed candidate; (3) reject malformed/mismatched presence as OPERATION_REUSED; (4) only when absent, classify all legacy/root authority; (5) before any create, read the proposed alias path; (6) return exact zero-write LEGACY_RESET_ALIAS_OCCUPIED if it is present; (7) otherwise commit reconciliation and the authority record atomically. For an active pair, the same transaction reads effective root epoch `e`, requires safe `r=e+1`, derives the frozen `rso1_` canonical ID, and requires that derived canonical path absent. Unsafe/exhausted epoch or occupied/malformed derived canonical path returns zero-write reconcile-context `LEGACY_RESET_CORRUPT` with `recordClass:"phase2"`; complete-content adoption is forbidden because no atomic migration record exists. The transaction then creates the **ordinary exact Phase 2 active reset record with no migration-only surplus member**, first alias `migrationAlias`, `target_index:0`, no cursor/lease/awaiting time, legacy committed count in `deleted_counts.tasks`, other counts zero, sum equality, `created_at=L.at`, and `updated_at=migrationAt`. Restart at target zero catches tasks inserted after the legacy empty check without recounting earlier deletes. It replaces the legacy marker with the exact canonical marker with `createdAt=L.at`, `updatedAt=migrationAt`, and no awaiting time; rotates root epoch `e→r`; and derives `activeMoveEventId` by the frozen deterministic formula `"me1_" + first40(SHA-256(TaskCanonicalV1({uid,new_task_generation_epoch:r,reset_operation_id:canonicalId})))`. It creates the server-only migration record with `created_at=migrationAt` and returns the exact committed progress projection.

§6.3:685 — Not-dispatched, phase2-active, and finalized-compat records also use `created_at=migrationAt`. An unrelated exact legacy B produces only the no-write migration-required redirect above and therefore creates no permanent A record. When §6.1 proves active Phase-2 C, the transaction validates C/root/operation completely and writes only A's `phase2_active` migration record carrying C's exact progress, preserving every C/root byte. All committed effects are atomic.

§6.3:689 — Finalized legacy is compatibility-terminal: do not rotate epoch, delete server tasks, rerun unfenced local destructive cleanup, or invent e/r; successor task/assessment/knowledge/dose work may now be legitimate. Server finalization alone is not proof of cleanup, but the supported migration case additionally has the retained per-UID key written by the shipped coordinator whose enforced order was cleanup before finalize. That pair is compatibility evidence only; it authorizes non-destructive reload/notification, never another delete. A direct/forged finalize without that local authority is not auto-repaired. The permanent record fences replay.

§6.4:693 — Before a fresh Phase 2 reset creates a canonical record, it reads the root marker. An exact legacy marker returns the exact no-write `failed-precondition/LEGACY_RESET_MIGRATION_REQUIRED` member above.

§6.4:699 — The raw fence is transactional and precedes every root-marker or legacy-operation mutation. The raw request retains its committed legacy validation behavior, including ECMAScript trimming; after `cleanDocId` succeeds, the handler uses the **returned normalized cleanDocId string**, never the raw request bytes, as `legacyOperationId` for `migrationId(uid,legacyOperationId)` and reads that literal permanent path in the same transaction as the contemplated raw reset/finalize write. Absence follows the mode/legacy-state rules above. A byte-exact `finalized_compat` migration plus its byte-exact finalized legacy operation returns the original old wire `{reset:true,deletedCount,replayed:true}` and writes nothing. A byte-exact `not_dispatched`, `upgraded`, or `phase2_active` migration returns exact no-write `failed-precondition/{schemaVersion:1,reason:"CLIENT_UPGRADE_REQUIRED",requiredProtocol:"phase2"}` for every delayed raw start, resume, or finalize. A present wrong-kind, wrong-shape, wrong-fingerprint, or deterministic-ID/content disagreement returns exact no-write `failed-precondition/OPERATION_REUSED` naming the deterministic migration ID.

**Canonical per-epoch reset record, receipts, and dispatch (spec v5 §4.2:1005, §3.3:693/695, §3.3:631–638, §4.4:1068–1073, §4.2:1025)**

§4.2:1005 — the reset response union:

```text
reset      = {schemaVersion:1,kind:"reset_progress"|"reset_final",
              operationId,replayed,accountUid,expectedTaskGenerationEpoch,
              taskGenerationEpoch,
              activeMoveEventId,deletedCount,
              deletedCounts:{tasks,notificationIntents,
                             taskDeadlineEvidence,confirmationSnapshots},state}
```

§3.3:693 — For a reset request let `e = expectedTaskGenerationEpoch`, require safe `r = e + 1`, and derive `reset_record_id = "rso1_" + first40(SHA-256(TaskCanonicalV1({account_uid:auth.uid,task_generation_epoch:r})))`. Its sole canonical path is `users/{uid}/taskPlanOperations/{reset_record_id}`; `operation_id == reset_record_id`. Caller operation IDs are `ResetAliasV1`, exact `rsa1_` followed by one lowercase RFC 4122 UUID. They are aliases stored only in that record and never create alias documents. Before appending a new alias, the transaction also requires `users/{uid}/taskPlanOperations/{alias}` absent; every non-reset action rejects the reserved `rsa1_` namespace, so an accepted alias cannot collide now or later with an ordinary record identity. `aliases` is the unique first-seen ordered list, contains the winning suggestion first, and is capped at 16. A later distinct alias after capacity is not persisted but must still satisfy the absent-alias-path check and resolves from `(uid,e)` to the same record/receipt; capacity can never create another reset. `expected_task_generation_epoch == e`, `task_generation_epoch == r`, and the §4.4 family fingerprint binds `e`. Counts are safe nonnegative integers and `deleted_count` equals their sum. The complete active record is capped at 32,768 `TaskCanonicalV1` bytes and the complete finalized tombstone at 16,384; either one byte over its cap fails closed before a write.

§3.3:695 — An active `deleting` record requires target index `0...3`, permits only that target's document-ID `page_after_path` and an unexpired UUID owner-token lease, and forbids awaiting/final members. A completed target atomically increments the index, clears the page cursor, and releases the lease. `awaiting_local_reset` requires target index `4`, no cursor/lease, and `awaiting_local_reset_at`. Finalization does not retain the active record: before exposing the first final receipt, its transaction deletes the marker and replaces the active map with the exact permanent tombstone above. Active-only `target_index`, cursor, counts-in-progress lease, `updated_at`, and awaiting time are forbidden on the tombstone. The normalized final receipt is reconstructed exactly as `{schemaVersion:1,kind:"reset_final",operationId:reset_record_id,replayed:false,accountUid,expectedTaskGenerationEpoch:e,taskGenerationEpoch:r,activeMoveEventId,deletedCount,deletedCounts:{tasks,notificationIntents,taskDeadlineEvidence,confirmationSnapshots},state:"finalized"}` from the tombstone projection and is capped at 8,192 canonical bytes. `final_receipt_digest` is the full lowercase SHA-256 of those `TaskCanonicalV1` bytes. Every terminal lookup recomputes and verifies it, returns that receipt with only `replayed:true`, and never increments generation, recreates a marker, or deletes another document. Digest mismatch, malformed deterministic-path content, or UID/epoch/formula mismatch fails closed. Tombstones have no TTL/eviction and remain one bounded document per reset epoch. A terminal alias append may change only the bounded `aliases` list: `created_at`, `finalized_at`, the receipt projection, and `final_receipt_digest` remain byte-identical.

§3.3:631–638 — the finalized reset tombstone:

```text
finalized reset tombstone = {
  schema_version:1, kind:"RESET_OPERATION", state:"finalized",
  account_uid, operation_id, aliases,
  reason:"retake_assessment", request_fingerprint,
  expected_task_generation_epoch, task_generation_epoch, active_move_event_id,
  deleted_counts:{tasks,notification_intents,
                  task_deadline_evidence,confirmation_snapshots},
  deleted_count, final_receipt_digest, created_at, finalized_at
```

The active record is the same map with `state:"deleting"|"awaiting_local_reset"`, the active-only members named in §3.3:695 (`target_index`, `page_after_path?`, `lease?:{owner_token,expires_at}`, `updated_at`, `awaiting_local_reset_at?`), and no `final_receipt_digest`/`finalized_at`; the Reconciled 9 `taskReset` marker is its total equality projection (spec v5 §697). On the marker, `lease` is exact `{ownerToken,expiresAt}`: `ownerToken` is the record's `owner_token` (one lowercase RFC 4122 UUID) and `expiresAt` its `expires_at` (a millisecond Timestamp); no other member (Reconciled 11).

§4.4:1068–1069 —

| `resetAllTasks` | no reset active at captured expected epoch, or matching per-result-epoch record/tombstone | Derive the canonical `rso1_` record, adopt/append the caller alias, and either create/resume the lease/pages that delete task docs, notification intents, deadline-authority seam docs, and H54 confirmation-snapshot records, or return the verified permanent final receipt; checkpoint exact unique total and per-collection counts. |
| `finalizeTaskReset` | matching canonical `awaiting_local_reset` record, or its tombstone | Atomically delete the marker and replace the active record with the digest-bound terminal tombstone before the first final receipt; exact alias/tombstone replay returns the same count without another reset. |

§4.4:1071 — `resetAllTasks` and `finalizeTaskReset` are two messages to one per-epoch state machine. Both carry literal `reason:"retake_assessment"`, the same retained caller `operationId` alias, and the same captured `expectedTaskGenerationEpoch:e`. Their shared fingerprint is exactly `"reset1_" + SHA-256(TaskCanonicalV1({kind:"reset",reason:"retake_assessment",expected_task_generation_epoch:e}))`, intentionally omitting action and alias. Dispatch validates the complete request and computes safe result epoch `r`, canonical ID/path, and fingerprint before consulting mutable root state, then reads that deterministic record before any marker/task/time validation. A matching active record appends the alias subject to the bound and resumes/returns its exact progress. A matching tombstone appends the alias subject to the bound, verifies the final digest/projection, and returns the reconstructed final receipt with `replayed:true` for either action. Neither branch can create epoch `r+1`.

§4.4:1073 — If the canonical path is absent, `finalizeTaskReset` returns no-write `STALE_STATE`. If absent for `resetAllTasks`, one transaction may create it only when root epoch equals `e`, result epoch is `r`, and no marker exists; that transaction stores the first alias, creates the canonical marker, rotates `taskGenerationEpoch e→r` and `activeMoveEventId`, and returns progress. A live marker for a different computed record returns `RESET_ACTIVE` with its canonical ID and expected epoch; a conflicting/malformed record at the deterministic path fails closed. A later intentional reset captures then-current root epoch `r` and therefore addresses the different `r+1` record. A losing scene retaining `e` always addresses/adopts the old active record or tombstone, regardless of the root now being `r`; it never starts the later reset. A different reason, overflow epoch, reserved/malformed alias, non-reset use of the canonical ID, mismatched marker/record, finalize-before-ready, or deterministic-path collision fails with zero destructive mutation.

§4.2:1025 (excerpt) — Callable errors use Firebase code `invalid-argument`, `unauthenticated`, `permission-denied`, `not-found`, `failed-precondition`, `aborted`, or `resource-exhausted`, and exact details `{schemaVersion:1,reason,operationId?,expectedTaskGenerationEpoch?,submissionToken?,field?,…}`; optional detail members are present only for the exact reason that names them. `RESET_ACTIVE` alone requires canonical `operationId` plus the active reset's safe `expectedTaskGenerationEpoch`.

Detail-less `unavailable` (Reconciled 11) — `changeTaskPlan` throws `HttpsError("unavailable")` with a fixed message and no `details` for exactly four conditions: a live foreign reset lease (a legacy `workerLease` or a Phase 2 `lease` held by another owner), a Phase 2 lease lost between pages, reset document-budget exhaustion while the record is `deleting`, and an unconfigured protocol mode outside a deployment (below). The client classifies detail-less `unavailable` as transport ambiguity: it retains durable bytes and retries the same message; it is never a returned map and never a `reason` member.

**`PHASE2_RESET_PROTOCOL_MODE` (v9 §6.4:697)**

§6.4:697 — Deployment order: add exact immutable deployment environment `PHASE2_RESET_PROTOCOL_MODE`, whose only values are `compat` and `phase2_required`; missing or unknown value fails module initialization and its deployment health check, so no reset handler starts and no unlisted wire response is invented. […] In required mode, fresh raw-legacy reset with no existing legacy op returns the exact no-write `failed-precondition/CLIENT_UPGRADE_REQUIRED` member above; an existing exact legacy op may finish until reconciled. Once any Phase 2/migration record exists, rollback may retain required mode and the compatibility bridge but may never restore fresh legacy creation.

Deployment scope of that rule (Decision 2, 2026-09-06; Reconciled 11) — the initialization failure applies to a deployed revision, identified by `FUNCTION_TARGET` or `K_SERVICE` present in the process environment. Outside a deployment (local tooling, the offline and emulator suites) a missing value loads the module, and every reset action (`resetAllTasks`, `finalizeTaskReset`, `reconcileLegacyTaskReset`) answers the detail-less `unavailable` above until a mode is configured; an unknown value fails initialization everywhere.

## C3 Server deletion root, work rows, and residual checks (§11, §11.3)

- Root `users/{uid}.accountDeletion` branches, all with `schemaVersion:1`, the exact sorted `capabilities` array (1…64, unique `operationId`, unsigned-UTF8 order, ≤16,384 canonical bytes), and `startedAt`: DELETING-sweeping `{state:"DELETING",capabilities,startedAt,storageGuardAfter}`; DELETING-guarding adds `firestoreCleanupAt` and optionally `storageGuardCompletedAt` (strictly after `storageGuardAfter`) and/or `firestoreVersionGuardCompletedAt` (≥ `firestoreCleanupAt`); DATA_DELETED adds both completions plus `dataDeletedAt`; AUTH_GUARDING adds `authAbsenceObservedAt,authGuardAfter`; ACCOUNT_DELETED adds `authGuardCompletedAt,accountDeletedAt`. `storageGuardAfter == startedAt + 604800 s`; `authGuardAfter == authAbsenceObservedAt + authResidualRetentionSeconds`; `authGuardCompletedAt > authGuardAfter`; `accountDeletedAt >= authGuardCompletedAt`. The ACCOUNT_DELETED tombstone is permanent and retains the UID as document ID plus capability-proof hashes; that retention is an explicit limit of the promise.
- Two consecutive empty application sweeps write only DELETING-sweeping→DELETING-guarding. Only the scheduled Storage guard writes DATA_DELETED, and only after `storageGuardCompletedAt`, `firestoreVersionGuardCompletedAt` (fresh `earliestVersionTime` strictly later than `firestoreCleanupAt`), zero `outboundLeases`, and zero soft-deleted/noncurrent generations. Data authority never deletes Auth.
- Work rows: `accountDeletionStorageWork/{"adsw1_"+first40(sha256(TaskCanonicalV1({account_uid:uid})))}` exists from marker creation until DATA_DELETED; `accountDeletionAuthWork/{"adaw1_"+…}` has branches `delete_pending` and `guarding` (`auth_guard_after == auth_absence_observed_at + authResidualRetentionSeconds`); each ≤2,048 canonical bytes, `failure_count` 0…8, client access denied.
- Reconcilers: `reconcileAccountDeletionStorage` = `onSchedule({schedule:"*/5 * * * *",timeZone:"UTC",region:"us-central1",timeoutSeconds:270,memory:"512MiB",maxInstances:1,retryCount:0})`, state `phase2System/accountDeletionStorageReconcilerV1`; `reconcileAccountDeletionAuth` = same with `schedule:"2-57/5 * * * *"`, state `phase2System/accountDeletionAuthReconcilerV1`. Every mutation fences its live lease tuple; one eligible row per run; cursor advances before any provider await; backoff `failure_count=min(old+1,8)`, `next_eligible_run=ordinal+min(2^count,16)`.
- Auth reducer: pending → 3-second `auth().getUser(uid)`; user-not-found or an accepted `deleteUser` transitions DATA_DELETED→AUTH_GUARDING and pending→guarding at one server read time; guarding after the deadline requires fresh user-not-found, every `authResidualChecks` query zero, and an unchanged authority fence, then writes ACCOUNT_DELETED and deletes the work row.
- Evidence activation gate, Build A (Reconciled 11): until `functions/accountDeletionProviderEvidenceV1.json` loads and verifies against the compiled trust anchor, begin's marker creation, every capability append, the application sweep, finalize, both scheduled reconcilers, and the historical apply path emit fixed `PROVIDER_EVIDENCE_NOT_ACTIVATED` before any provider or Firestore mutation: the callable paths throw the C2.3 `DELETION_RETRY_REQUIRED` member and the reconcilers return before acquiring a lease. This is the one non-transport source of that member; C2.3's retry rule is otherwise unchanged. Discover's absent wire, exact-member classification, and the DATA_DELETED/AUTH_GUARDING/ACCOUNT_DELETED wire replays need no authority (§11.2:1652–1656).
- Residual checks (D3): `authResidualRetentionSeconds` 0…31536000 equals the maximum `retentionSeconds` across the accepted `AuthDeletionDestinationV1` array. Runtime validates it against the check array — every `authResidualChecks[].retentionSeconds` is at most that value and their maximum equals it — because the artifact carries only the destination arrays' `AcceptedArrayDigestV1`; equality with the maximum over the accepted destination array is proved by the sealer, which alone holds that array (Reconciled 11). `authResidualChecks` is a sorted 1…12-member closed union with contiguous ordinals: Firebase `{ordinal,destinationOrdinals,adapterId:"firebase_admin_get_user_v1",retentionSeconds}` covering every `auth_user` destination; provider query `{ordinal,destinationOrdinals,adapterId:"google_authenticated_uid_zero_v1",resourceURLTemplate,method:"GET"|"POST",bodyTemplate,uidEncoding:"percent_utf8"|"taskcanonical_sha256_hex",zeroCountField:"matchCount"|"totalSize",retentionSeconds}`; absence-plus-retention `{ordinal,kind:"absence_retention",destinationOrdinals,observedAbsentAt,retentionSeconds}` where `destinationOrdinals` has exactly one member. Every `destinationOrdinals` array is nonempty, sorted, and disjoint from every other check's, and every accepted Auth-destination ordinal appears in exactly one check, whether a count check or an `absence_retention` check. A destination kind admitting none of the three checks cannot be sealed.
- Outbound leases `users/{uid}/outboundLeases/{"uol1_"+UUID}` exact `{schema_version:1,kind:"USER_OUTBOUND_LEASE",account_uid,delivery_id,channel:"fcm"|"support_email"|"support_sms"|"inventory_email"|"checkin_sms"|"anthropic",state:"sending",created_at,expires_at}`, `expires_at == created_at + 600 s`, ≤1,024 bytes, ≤64 live; marker creation requires the collection empty; a lease observed after DELETING is `OUTBOUND_LEASE_INVARIANT` and blocks DATA_DELETED. Every participating function deadline is ≤300 s.
- Global scheduler cleanup deletes `phase1System/dispositionTriggerState/quarantinedEvents` rows whose reread `sourcePath` parses exactly as `users/{uid}/events/{id}` (range `[users/{uid}/events/, users/{uid}/events0)`, `limit(100)`), removes the seven cursor-map members, `dueObservation`, and the `p2b1_oldest_due_over_900_seconds` alert only when their exact path names the UID; a malformed in-range path blocks DATA_DELETED with `ACCOUNT_DELETION_GLOBAL_PATH_MALFORMED`.
- Provider cache: `functions/resolveProvider.js` writes nothing (`cacheResolved` deleted); `loadDirectory()` admits only exact `source:"seeded"` rows; `purgeLegacyResolvedProviders.js` removes every non-seeded `providerDirectory` row under reread until two fresh passes observe zero.
- Local purge journal `PeezyLocalPrivacyPurge-v1.json`, `fileKind:"LOCAL_PRIVACY_PURGE_V1"`, cap 4,096, payload exact `{schemaVersion:1,scope:{kind:"all"}|{kind:"uid",uid},providerContext?,terminalDeletionLink?,acks,createdAt,updatedAt}`; `providerContext` `{deletionOperationId,deletionProofSHA256,googleRevocation,googleProviderUid?}` required iff UID scope and must match the intent; `terminalDeletionLink` `{deletionOperationId,deletionProofSHA256}` only for the terminal all-scope handoff.
- Logging closure: the Release product has zero `print`/`debugPrint`/`dump`/`NSLog`/raw `os_log` argument derived from UID, auth, path, payload, user value, or `Error`; every active function logs only fixed event codes, bounded counts, and fixed error classes. Already-persisted OS unified-log entries are outside the promise.

## C4 Proof-of-deletion contract table (§11.5)

Each row restates an obligation defined in C2, C3, or C6 and adds none.

| Store | Must be gone | Contract | Named falsifier |
|---|---|---|---|
| Firestore user root and fence-covered descendants | Every direct subcollection and orphaned nested descendant; only the minimal tombstone remains | C3, C6.1 | `functions/tests/accountDeletionFence.test.js` — `Firestore 0/1/100/101 and two universal empty sweeps` |
| Storage current, noncurrent, soft-deleted, held, copied, late-upload objects | Every `inventory/{uid}/` and `users/{uid}/` generation and retained copy | C3, C7 | `functions/tests/accountDeletionFence.test.js` — `Storage 0/1/100/101 retained-copy and guard boundary` |
| Auth record and retained Auth copies | Auth user absent; every accepted residual destination zero/absent after retention | C2.3, C3 | `functions/tests/accountDeletionFence.test.js` — exact finalize wires; `Auth destination partition is completely falsifiable`; Auth guard exact/equal/+1 |
| Local durable stores and deletion intent/journals | Zero deleted-UID target/quarantine bytes; staged/nonstaged detach complete; terminal presentation consumed; intent and journal unlinked | C2.1, C2.2, C3 | `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` — C2.7 purge, phase, presentation, and crash fixtures |
| Local/server quarantine | Local all-scope unlink or UID removal; server quarantine rows for the UID | C2.2, C3 | `DurableStoreRecoveryTests` quarantine wipe; `accountDeletionFence.test.js` 100/101 server rows |
| Keychain/provider credentials | Firebase Auth keychain item absent after terminal detach; Google revocation claimed only by `completed`; installation key retained by design | C2.2, C2.5 | `DurableStoreRecoveryTests` — `Firebase Auth keychain item is absent after terminal detach`; `AppRootAuthRaceTests` completed/local-cleared Google interleavings |
| Provider cache and Firestore local cache | Non-seeded provider rows absent; Firestore persistence empty; queued writes discarded | C2.2, C2.4, C3 | `accountDeletionFence.test.js` provider-cache graph; `DurableStoreRecoveryTests` offline A/B cache fixture |
| UserDefaults/preferences | Ten exact UID-scoped keys and conditional global first name | C2.2, C6.6 | `DurableStoreRecoveryTests` — `UID-interpolated preference keys are registry-complete` |
| Notifications, FCM token, installation identity | Pending/delivered zero, badge zero, Messaging/FID deleted, server token rows absent | C2.2, C2.4, C6.8 | `AppRootAuthRaceTests`/`DurableStoreRecoveryTests` API spies; `functions/rules-tests/firestoreRules.test.js` boundaries |
| Analytics, Crashlytics, Sessions/MetricKit | Analytics reset, collection off, no unsent Crashlytics reports; Sessions/MetricKit OS-owned, collection disabled | C2.2 | `DurableStoreRecoveryTests` telemetry lifecycle; `accountDeletionFence.test.js` evidence drift |
| Release and server logs | No UID/path/payload/error-derived Release sink; only fixed server codes/counts | C3 | `DurableStoreRecoveryTests` — `Release call graph and adversarial NSError are sink-free`; `accountDeletionFence.test.js` — `active exports contain no dynamic server log sink` |
| Gmail, Twilio, Anthropic, other legacy provider destinations | Legacy copies deleted/expired; future traffic content-free or zero-retention | C3, C6.2, C6.3 | `accountDeletionFence.test.js` — `sealer refuses nonzero matches, backlog, and nonfinite retention`; `timeouts do not exceed 300 seconds` |
| External indexed families | Every exact family row deleted/scrubbed under owner reread | C6.7, C7 | `accountDeletionFence.test.js` equal/+1 page and restart cases; rules/index parity |
| Backup/export destinations | Firestore destination array empty; other destination copies expired/deleted to zero | C3 | `accountDeletionFence.test.js` policy-check, generation, and break-glass cases |
| Two-device crash-mid-purge and guarding handoff | Device B resumes every staged detach owner/barrier; first UID stays forbidden while a second UID signs in and dispatches during guarding | C2.2, C2.4, C2.7 | `DurableStoreRecoveryTests` crash/relaunch at every boundary and Option-B empty-slot; `AppRootAuthRaceTests` second-UID sign-in during guarding; `accountDeletionFence.test.js` two-device/lost-response roots (the C2.7 assignments; adds zero obligation) |

## C5 Named falsifier index

| Test file | Named tests and fixture families it owns |
|---|---|
| `functions/tests/accountDeletionFence.test.js` (new; in Node `--test` before `accountabilityLadder.test.js`) | `timeouts do not exceed 300 seconds` (scans only C6.3 plus reached Anthropic/Twilio/SMTP timeout constants; asserts `changeTaskPlan` stays 540); `active exports contain no dynamic server log sink`; `Auth destination partition is completely falsifiable`; `sealer refuses nonzero matches, backlog, and nonfinite retention`; `Firestore 0/1/100/101 and two universal empty sweeps`; `Storage 0/1/100/101 retained-copy and guard boundary`; C2.7 server set; external families equal/+1/restart; provider-cache graph and purge CLI guards; policy-check 1/12/13, generation, break-glass; both reconciler state/work fences; historical migration; package/lock/config/evidence digests |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` (new; `-only-testing` after `DispositionTriggerSelectionTests`) | `UID-interpolated preference keys are registry-complete`; `Release call graph and adversarial NSError are sink-free`; `Firebase Auth keychain item is absent after terminal detach`; C2.7 client set; offline A/B cache; telemetry lifecycle; quarantine wipe; blocked-store recovery (D22/B3); reset envelope (D14/D24/B2); readiness (D23/D28); coordinator (D30) |
| `Peezy 4.0Tests/AppRootAuthRaceTests.swift` (new) | C2.7 set; sole-`GIDSignIn.sharedInstance` call-site scan; sole-`UNUserNotificationCenter`/`Messaging` deletion call-site scan |
| `functions/rules-tests/firestoreRules.test.js` (existing; `firebase emulators:exec --only firestore,storage`) | Owner denial while DELETING/DATA_DELETED/AUTH_GUARDING/ACCOUNT_DELETED; `fcmTokens` create/update/delete grammar and read/list denial; `phase2System` docs, work rows, candidates, `outboundLeases`, `legacyResetMigrations`, quarantine, archive, refusal denial; equal/+1 access budgets; late Storage; other/anonymous denial |
| `functions/tests/taskInteraction.test.js` | C6.4 registry test (every stored operation/response shape; any `ev1_` member absent from both tables fails); C6.5 registry/oracle; D25/D26/D27 |
| `functions/tests/taskPlan.test.js` | `inspectCommittedOperation` branches; D12/D13; MIG-RESET-V1 |
| `functions/tests/dispositionTriggers.test.js` | D1–D11, B1, MIG-EVENT-V1 codec/oracle/migration |
| `Peezy 4.0Tests/TaskRouteTests.swift`, `TaskPlanDispositionTests.swift`, `TaskSupersessionTests.swift` | B4; D15; D18–D21 |

Literal totals: 89 unique authorized client paths; 22 Swift test files; 23 named suites equal to expected set `E`; 24 main Node files; 25 unique Node/rules files. Node `--check` covers the four `functions/scripts/*.js` files.

## C6 Registries

### C6.1 `ACCOUNT_DELETION_FENCE_WRITERS_V1` (exported by `functions/accountDeletionFence.js`)

`functions/index.js` requestConcierge, submitTaskFlow, submitSupportMessage (with `deleteAccount`, `reconcileAccountDeletionStorage`, `reconcileAccountDeletionAuth` as marker/cleanup coordinator exceptions); every committing branch/shared child in `functions/taskDisposition.js`, `functions/taskPlan.js` (`inspectCommittedOperation` read-only; includes `users/{uid}/legacyResetMigrations/{migrationId}` creation), `functions/getWorkflowQualifying.js` submitWorkflowAnswers, `functions/dispositionTriggers.js`, `functions/notificationIntents.js`, `functions/spawnTasks.js`; process success/error plus `onInventoryRoomWritten` in `functions/processInventory.js`; `functions/researchTask.js`; `functions/peezyChat.js`; `functions/packageInventory.js`; `functions/submitCheckIn.js` plus `functions/submitCheckInCore.js`; `functions/entitlement.js`; `functions/validateSubscription.js`; writing tails of supportAdmin adminGetThread, adminReplySupport, adminMarkSeen, adminSetThreadStatus. Explicit exclusions: scheduler lease/heartbeat-only writes, generation-preconditioned Storage deletion, support invalid-token deletion, getWorkflowQualifying read-only branch, healthCheck, adminListThreads, requireMovePass; scripts, `functions/notifyAdmin.js`, and test-profile utilities are deployment-inactive. Before each registered write the transaction reads every current and prospective owner root in unsigned-UTF8 order and requires `accountDeletion` absent. A registered write that observes `accountDeletion` present (any value, a malformed marker included) throws `HttpsError("failed-precondition")` with details exact `{schemaVersion:1,reason:"ACCOUNT_DELETION_FENCED"}` and writes nothing; this member belongs to fence-covered writers only and is not part of the C2.3 union (Reconciled 11). Note: the four `d321547` files are authorized only for `processInventory.js` fence/lease call sites, six `Firestore.firestore()` substitutions plus `pendingNarration` in `InventorySessionManager.swift`, `pendingNarrationTranscript` in `InventoryCameraView.swift`, and `NarrationService.start`.

### C6.2 `USER_OUTBOUND_PROVIDERS_V1`

`functions/index.js` submitSupportMessage → `functions/notifySupport.js` support email/SMS; `functions/supportAdmin.js` adminReplySupport → support-reply FCM; `functions/packageInventory.js` → inventory email; `functions/submitCheckIn.js` → one check-in SMS per flag; every Anthropic `client.messages.create` in `functions/processInventory.js`, `functions/researchTask.js`, `functions/peezyChat.js`, `functions/resolveProvider.js`. Every entry is dominated by the shared lease helper and its surface's root-fenced business-record rule.

### C6.3 `DELETION_PARTICIPATING_FUNCTIONS_V1` (deployed-function projection of C6.1 ∪ C6.2 plus deletion, scheduler, and migration functions)

```text
requestConcierge submitTaskFlow submitSupportMessage deleteAccount
reconcileAccountDeletionStorage reconcileAccountDeletionAuth phase2LegacyCreateBlocker
submitWorkflowAnswers evaluateDispositionTriggers spawnTasks processInventory
onInventoryRoomWritten researchTask peezyChat packageInventory submitCheckIn
redeemGiftCode validateSubscription adminGetThread adminReplySupport adminMarkSeen
adminSetThreadStatus resolveProvider
```

`changeTaskPlan` is expressly non-participating and stays at 540 s.

### C6.4 Evidence pointer registries (`functions/taskInteraction.js`)

`EVIDENCE_POINTER_PATHS_V1` — the only traversed paths:

```text
taskInteractionState.milestone_profile.resolved_from_evidence_ids[]
taskInteractionState.required_milestones[].evidence_id
taskInteractionState.required_milestones[].not_required_source
taskInteractionState.companion_milestones[].evidence_id
taskInteractionState.contradiction.evidence_ids[]
taskInteractionState.deadline_evidence.evidence_id
taskInteractionState.external_submission.evidence_id
taskInteractionState.waiting_state.entry_evidence_id
taskInteractionState.waiting_fallback_state.fallback_evidence_id
taskInteractionState.pending_handoff.source_entry_evidence_id
dispositionContract.next_trigger.evidence_id
activeHandoff.opened_evidence_id
activeHandoff.return_evidence_id
wakeEvidence.cause.original_trigger.evidence_id
wakeEvidence.cause.displaced_trigger.evidence_id
wakeEvidence.cause.deadline_evidence_id
wakeEvidence.urgency_basis.deadline_evidence_id
thresholdProjection.deadline_evidence_id
resolution.external_submission_archive.evidence_id
interactionHistory[ordinary].evidence_ids[]
interactionHistory[ordinary].external_submission_archive.evidence_id
planChangeCycle.confirmation_attempts[].confirmation_evidence_id
planChangeHistory[ordinary].evidence_refs[].evidence_id
foreignRoots.counts.<evidence_id key>
planChangeHistory[policy-absent legacy ordinary].evidence_ids[]
evidence_records[].source_ref when exact ev1_
evidence_records[].facts.source_evidence_id
evidence_records[].facts.trigger_evidence_id
evidence_records[].facts.opened_evidence_id
evidence_records[].facts.return_evidence_id
evidence_records[].facts.entry_evidence_id
planChangeCycle.confirmation_attempts[].source.evidence_id                       # cross-instance
taskPlanOperations.CONFIRMATION_SNAPSHOT.source.evidence_id                      # cross-instance, only while its snapshot_record_id is referenced by current confirmation_attempts[]; zero foreignRoots count
planChangeHistory[ordinary].evidence_refs[].evidence_id when replacement-owned   # cross-instance
```

`EVIDENCE_NON_POINTER_PATHS_V1` — required regression sentinels, never traversed:

```text
wakeEvidence.intent_id
notificationIntents[TASK_RESUME].cause.wake_evidence_id
activeHandoff.prior_dynamic_snapshot_id
activeHandoff.adapter_operation_id
activeHandoff.restoration.operation_id
activeHandoff.presentation_snapshot.source_refs[]
taskInteractionState.pending_handoff.selection_operation_id
planChangeCycle.pre_supersede_operation_id
planChangeCycle.confirmation_attempts[].snapshot_record_id
planChangeCycle.confirmation_attempts[].source.receipt_identity.operation_id
planChangeCycle.confirmation_attempts[].source.receipt_identity.submission_token
planChangeHistory[ordinary].request_identity.operation_id
planChangeHistory[ordinary].request_identity.submission_token
planChangeHistory[ordinary].snapshot_record_id
interactionHistory[ordinary].operation_id
events.source_evidence_id
eventState.source_evidence_id
wakeEvidence.cause.event_high_water.source_evidence_id
evidence_records[].id
evidence_records[AMENDMENT_CONFIRMATION].facts.replacement_evidence_copy.evidence_id
users/{uid}/research/{taskId}.brief.sections[].items[].applicability_evidence_ids[]   # required []
taskPlanOperations.CONFIRMATION_SNAPSHOT.source.evidence_id when no current confirmation_attempts[] references its snapshot_record_id
```

Policy-bearing `planChangeHistory[ordinary].evidence_ids` is forbidden (zero paths); the policy-absent legacy path above is the sole positive registry/decoder path. `foreignRoots` is exact `{schema_version:1,original_task_document_id,original_task_instance_id,plan_change_revision,counts:{<ev1_ key>:1…17}}`, 1…128 keys, cap 16,384, replacement-only, wildcard-index-exempt, client-immutable.

### C6.5 `EVIDENCE_RESERVATION_WRITERS_V1` (fresh-task-mutation registry)

```text
functions/taskDisposition.js = [assertAlreadyHandled, markNotApplicable:none, deferTask, markSelfHandling,
  markWaitingOnExternal, beginHandoff, acknowledgeHandoffOpened, recordHandoffReturned, continueHandoff,
  cancelHandoff, resolveHandoff:mutating, resolveWaiting:mutating, initializeFlowProgress, continueFlowProgress,
  clearFlowProgress, replaceTaskNotes, replaceTaskQuotes, mutateLegacyTask:applicable, persistLegacyPackingPlan:applicable]
functions/taskPlan.js = [supersede, confirmAmendment, undoConfirmation, reopen, resetAllTasks:root-fenced-delete-exception]
functions/getWorkflowQualifying.js = [submitWorkflowAnswers:COMPLETE, submitWorkflowAnswers:WAIT, submitWorkflowAnswers:WAIT_DISPLAY_FALLBACK]
functions/dispositionTriggers.js = [date_snoozed_deferred, event_snoozed_deferred, date_inprogress_user_action,
  event_inprogress_user_action, date_matching_waiting, event_matching_waiting, threshold_attention]
```

Cap vector: evidence records 128; evidence bytes 131,072; foreign-root entries 128; foreign-root bytes 16,384; interaction-history bytes 65,536; taskInteractionState bytes 196,608; semantic snapshot bytes 262,144; task bytes with `evidence_reservation` omitted 638,952; reservation map ≤16,384; complete task ≤655,360; transaction budget 8,388,608.

### C6.6 UID-scoped preference keys (ten; source-scan registry)

`phase1.pendingRetakeOperation.{uid}`, `peezy.{uid}.dailyDose.completedCount`, `peezy.{uid}.dailyDose.lastDate`, `peezy.{uid}.dailyDose.firstLaunchDate`, `peezy.{uid}.dailyDose.v2`, `peezy.{uid}.hasSeenFirstTimeWelcome`, `peezy.{uid}.lastGreetingDate`, `peezy.{uid}.totalCompletedCount`, `inventory.scanCoaching.seen.{uid}`, `inventory.narrationOffer.seen.{uid}`. All-scope additionally removes global `peezy.user.firstName`; UID deletion removes it only while Firebase still names that UID or no different current UID is established. `peezy.{uid}.dailyDose.v2` is accessed only through `DailyDoseLocalStore`.

### C6.7 `ACCOUNT_DELETION_EXTERNAL_FAMILIES_V1`

Direct deletes `userKnowledge/{uid}`, `supportThreads/{uid}`. Query deletes `conciergeRequests.userId`, `taskFlowSubmissions.userId`, `inventorySessions.userId`, `workflowSubmissions.userId`, `workflowSubmissions.owner` (unioned, deduplicated by path), `subscriptions.userId`, `vendorReviews.userId` (strike removal from the referenced vendor in the same transaction), `estimateCalibration.userId`, `admin/inventoryPackages/packages.userId`, `adminNotifications.userId`. `giftCodes.redeemedBy` is scrubbed by removing only the UID field. `ACCOUNT_DELETION_FIRESTORE_PAGE_SIZE = 100`; a page nominates, the reread transaction authorizes; no cursor persists.

### C6.8 Notification and FCM constants

Sole FCM surface: support-reply multicast in `functions/supportAdmin.js`, payload `notification:{title:"Peezy",body:"You have a new support reply."}`, `data:{thread:"support"}`, `android:{ttl:0}`, `apns:{headers:{"apns-expiration":"0"},payload:{aps:{sound:"default",badge:1,category:"PEEZY_SUPPORT_REPLY_V1"}}}`; `limit(501)` on `users/{uid}/fcmTokens`, 501 rows = `FCM_DESTINATION_CAPACITY`. Token write is exact `users/{uid}/fcmTokens/{token} = {createdAt:<server Timestamp>,platform:"ios"}`. `FCM_ACCEPTED_FAILURE_CODES_V1` is the 19-code union frozen from Firebase Admin 13.6.0; only `messaging/invalid-registration-token` and `messaging/registration-token-not-registered` permit token deletion. Support email/SMS text `New support message. Open Peezy admin.`; inventory email `New inventory package. Open Peezy admin.`; check-in SMS `New move check-in requires review. Open Peezy admin.`

## C7 Frozen byte-hash and version pins

| Target | Pin |
|---|---|
| `build/src/v1/firestore_client_config.json` (`@google-cloud/firestore` 7.11.6, exact direct dependency) | sha256 `2ed7a9046d766121b7f308b22384b1a6caaf7c6eaed5d9ea553556af3c987e41`; `Commit.timeout_millis == 60000`; `BatchWrite.timeout_millis == 60000` |
| `build/src/recursive-delete.js` (same package) | sha256 `2a17d8fb6d975cdf3863c3826783f061a728a8a710fa7a3f81b10d0e7c407270`; `RECURSIVE_DELETE_MAX_PENDING_OPS == 5000`; `RECURSIVE_DELETE_MIN_PENDING_OPS == 1000` |
| Transitive packages | `@google-cloud/storage` 7.18.0; google-gax 4.6.1; `google-auth-library` 9.15.1; `firebase-admin` 13.6.0; Firebase iOS SDK 12.7.0; Node 24 (`/opt/homebrew/opt/node@24/bin/node` v24.19.0 per spec v5 §9.1; `functions/package.json` engines 24; Decision 9, 2026-09-06 — v9 §11.2:1646's "Node 22" lost) |
| `Peezy 4.0/Menu/PeezySettingsView.swift` pre-edit | whole file `419055c9eb0e756daf70f68aeb37d5761888460a65f4c129243fe3f28a4c34d5`; `retakeAssessment()` lines 662–679 `348ec7db63aeecb76e7012d4fac91e41b60df78562a32b9528a5e40553a5a2e2` (unchanged after patch); `deleteAccount()` lines 681–712 `8f86efa8523960588cfe8a17d6351645cba50bb14f4258a77a4dc8ccf98a5bbf`; file minus that slice `ef856d3bf2f89b79d4340e5b4afe8e3844b13bb6167854486d5919d83b37e4cc` (identical after patch; per §12.2:1866, "For Settings, §6.6's remainder hash is evaluated after normalizing its one exact runtime-provider line back to the frozen preimage; no other outside-deleteAccount byte changes.") |
| `RetakeAssessmentCoordinator.swift` closure slice (`deleteAssessments: { userId in` … `resetDose` `},`) | preimage `a7cf81cab9bfa9c49e5dba2c12c618bbfe309818284156f9594b0be127515e93`; next line must be `            operationStore: store,` |
| `Peezy 4.0/Documents/GoogleService-Info.plist` | sha256 `2f67a70dd2cd4daebb988e7f45be2d64904714dbfa5dd9b4308ff3486e0cfa6c`; `REVERSED_CLIENT_ID` = `com.googleusercontent.apps.833904565407-m9jhkhdhvih0aeeknk4fpcfbnv3g4oso` |
| `Peezy-4-0-Info.plist` pre-edit | sha256 `603c9c711ccd47d7a2929a2c794b88b5b50d78e722703c501f30aac70e7ffbbf`; exactly one URL-scheme entry preserved byte-for-byte |
| `firestore.indexes.json` base (frozen §7.4 registry) | 4,432 bytes; sha256 `a7a432ec8e0511176b890432c5e4cb4a07e59a6dba0c9d920948cc446f3a7bbb`; 3 indexes / 28 overrides |
| `firestore.indexes.json` result (base + 8 appends: `schedulerRefusals` composite; empty overrides for `eventArchiveChunks.payload`, `tasks.foreignRoots`, `tasks.evidence_reservation`, `legacyResetMigrations.*`, `outboundLeases.*`; ASCENDING re-enables for `workflowSubmissions.userId` and `.owner`) | `JSON.stringify(value,null,2)+"\n"`; 5,872 bytes; sha256 `a6de8daf701a75ff3db025ca244dbf2218432c5c1a06b0992cd88358250d88e8`; 4 indexes / 35 overrides |
| Legacy reset fingerprint (§6.1) | accepted literal `reset1_862fe3fc8a08ce3eced6f25dfd2a8765b408e8386fa28f081f393d36f04e94a1` = `"reset1_" + sha256(committed legacy canonical({kind:"reset",reason:"retake_assessment"}))` |
| Migration parity fixture (§6.2) | UID `phase2-rule-owner` + legacy ID `20000000-0000-4000-8000-000000000001` → `rlm1_0a4d53a438873090f69e4255426310b0feb4cfd6` and `rlmreq1_0a4d53a438873090f69e4255426310b0feb4cfd63eabd6ce68c851ce827ad8e1` |
| `Peezy 4.0.xcodeproj/project.pbxproj` | byte-identical |
| Firebase identity | project `peezy-1ecrdl`; database `(default)`; bucket `peezy-1ecrdl.firebasestorage.app`; iOS app `1:833904565407:ios:d03ca5a2ca59f5f10156aa`; sender `833904565407`; region `us-central1` |
| Provider evidence trust anchor | one offline Ed25519 public key (32 bytes) whose base64url and sha256 are literal constants in `sealAccountDeletionProviderEvidence.js` and `accountDeletionFence.js`; `functions/accountDeletionProviderEvidenceV1.json` is the sole runtime authority, ≤131,072 canonical bytes, imported only by `accountDeletionFence.js` |

## C8 Defect resolution map (§13, 36 rows)

| ID | § | Resolution | Closure |
|---|---|---|---|
| D1 | §2.2 | Scheduler slot, lease, heartbeat, capacity, overload, and completed-evaluation telemetry are exact | `functions/dispositionTriggers.js` · `functions/tests/dispositionTriggers.test.js` |
| D2 | §2.3 | Ordinary-lane page size, ordering, and post-settlement cursor semantics are exact | same |
| D3 | §2.3 | Candidate projection and missing-tag identity are exact and bounded | same |
| D4 | §2.4 | Refusals are durable per-candidate rows with exact backoff and no eviction | same |
| D5 | §2.3 | Admission deadlines, concurrency, settlement, and checkpoint ordering are exact | same |
| D6 | §2.5 | `OriginalEventBytesV1` is a complete deterministic raw-value codec | same |
| D7 | §2.5 | Runtime value classification uses the closed two-token error vocabulary | same |
| D8 | §2.5 | Firestore storage/index sizing and raw Vector discrimination are copied and executable | same |
| D9 | §2.5 | Validation, unencodable, too-large, stale, duplicate, and conflict precedence is total | same |
| D10 | §3 | Every legacy oversize event is archived and terminalized through the total migration | `functions/scripts/migrateOversizeEvents.js` · `functions/tests/dispositionTriggers.test.js` |
| D11 | §2.5 | H57 regeneration adds the exact scheduler, migration, refusal, deletion, and purge observables | `PEEZY_STATE_REGEN_SPEC.md` · `dispositionTriggers.test.js` · `accountDeletionFence.test.js` |
| D12 | §4 | Terminal-child reuse removes only create-time-zero comparisons, preserves immutable equality | `functions/taskPlan.js` · `functions/tests/taskPlan.test.js` |
| D13 | §4 | Progress revisions remain structurally validated, not immutable create-time identity | same |
| D14 | §5 | Gesture identity is durably reserved before the first reset await and is singleflight | `RetakeAssessmentCoordinator.swift` · `DurableStoreRecoveryTests.swift` |
| D15 | §5 | Reset authority resolves by deterministic UID/epoch point path, no alias scan | `TaskPlanService.swift` · `TaskPlanDispositionTests.swift` |
| D18 | §9 | Superseded v1/v2 stored shapes and malformed fallback are exact | `functions/taskPlan.js` · `TaskSupersessionTests.swift` |
| D19 | §9 | Superseded timestamps use the frozen local-day formatter with injected tests | `TaskDispositionSurface.swift` · `TaskSupersessionTests.swift` |
| D20 | §9 | Undo remains available across trigger drift until success, expiry, or authoritative change | `TaskDispositionCoordinator.swift` · `TaskSupersessionTests.swift` |
| D21 | §9 | Five ordinary history actions and the rollup have exact safe copy, order, and dates | `TaskDispositionSurface.swift` · `TaskSupersessionTests.swift` |
| D22 | §7 | Blocked-store recovery is a total disjoint union with exact actions, CAS, and crash semantics | `DurableStoreRecoveryCoordinator.swift` · `DurableStoreRecoveryTests.swift` |
| D23 | §8 | Operation-indexed store dependency graph and auth/readiness seams are exact | `DurableStoreReadiness.swift` · `DurableStoreRecoveryTests.swift` |
| D24 | §5 | Reset envelope payload, gesture/migration/record matrix, order, uniqueness, and cap are exact | `TaskPlanService.swift` · `DurableStoreRecoveryTests.swift` |
| D25 | §10 | Evidence roots and foreign-root counts are per-instance, recomputed from retained pointers | `functions/taskInteraction.js` · `functions/tests/taskInteraction.test.js` |
| D26 | §10 | Pointer and non-pointer fields are literal closed registries with full stored-shape enumeration | same |
| D27 | §11 | H54 capacity is protected by two-copy durable reservation and complete writer admission | `functions/taskPlan.js` · `functions/tests/taskInteraction.test.js` |
| D28 | §8 | Startup readiness and deletion gating mount at `PeezyV1App` before dispatch consumers | `PeezyV1App.swift` · `DurableStoreRecoveryTests.swift` |
| D29 | §12.3 | Recovery tests are present in the literal file list, selection list, and expected-suite set | `PHASE2_EXECUTABLE_SPEC_v5.md` §9.2/§9.3 · `DurableStoreRecoveryTests.swift` |
| D30 | §6.6 | Coordinator/hash guards plus generation-fenced assessment, knowledge, and daily-dose cleanup are exact | `RetakeAssessmentCoordinator.swift` · `DurableStoreRecoveryTests.swift` |
| D31 | §12.2 | Authorized-path, Swift-test, suite, Node-test, and ordered-owner totals are literal | `PHASE2_EXECUTABLE_SPEC_v5.md` §8/§9 count gate |
| D32 | §12.5 | New-file no-index normalization preserves shell state and validates pinned input/captures | `PHASE2_EXECUTABLE_SPEC_v5.md` §9.4 helper and shell fixture |
| B1 | §2.2 | Urgent delivery is a monitored objective with exact scheduler controls, not a wall-clock guarantee | `functions/dispositionTriggers.js` · `dispositionTriggers.test.js` |
| B2 | §5 | One reset-envelope actor owns auth-scoped reserve, bind, and drive singleflights | `TaskPlanService.swift` · `DurableStoreRecoveryTests.swift` |
| B3 | §7 | Quarantine, collision, cleanup, receipt, foreign, I/O, and epoch recovery are total | `DurableStoreRecoveryCoordinator.swift` · `DurableStoreRecoveryTests.swift` |
| B4 | §8 | Route receipt is durable before readiness; the barrier gates only dispatch/application | `PeezyV1App.swift` · `TaskRouteTests.swift` |
| MIG-EVENT-V1 | §3 | Cross-fenced archive migration has exact bytes, manifests, leases, budgets, and rollout gates | `migrateOversizeEvents.js` · `dispositionTriggers.test.js` |
| MIG-RESET-V1 | §6 | Legacy reset authority is reconciled through a server-only record, durable random alias, and bounded collision reducer | `functions/taskPlan.js` · `functions/tests/taskPlan.test.js` |

## Reconciled

1. §6.6:770 says Settings follows a client order ending "…Auth finalization → durable terminal presentation → conditional-sign-out → all-scope-purge" and that the presentation owner projects dispositions "after the gate clears". §8.9.1/§8.9.3 own that order and clear the gate only on presentation consumption (D2). C2.2 and C2.4 state it once; §6.6 defers.
2. §8.9.1 and §8.9.5 both name `remote_unverified` as the capability-invalid exit reason while §8.9.1's terminal rule maps `remote_unverified` to the remote-unconfirmed terminal. D1 resolves the collision: `capability_invalid → local_cleared`; `remote_unverified` keeps its existing terminal. C2.1, C2.2, and C2.6 carry the three-token union.
3. §11.3:1673 gives `absence_retention` the shape `{ordinal,kind,observedAbsentAt,retentionSeconds}` with no `destinationOrdinals`, while the same paragraph requires every accepted ordinal to sit in exactly one check. D3 adds `destinationOrdinals` (exactly one) and makes the partition cover both check kinds. §14.1's V7-12 row ("partition sentence remains unchanged") is superseded by C3.
4. §8 (notification-tap precedence, line 1001) and §12.2 enumerate gate states outside §8.9. C2.4 is the single enumeration; those sentences are pointers.
5. §11:1510 says Firestore terminate/clear failure "leaves the purge journal and global gate blocked". Gate state is owned by §8.9.3; C3 keeps only the journal-blocked consequence, and C2.4 owns the gate.
6. §11 (line 1416) and §11.3 both describe finalize results and DELETING-guarding client behavior; C2.3 is the sole statement and §11/§11.3 defer to it.
7. C7's Settings pin was extracted as "file minus that slice … identical after patch" and dropped §12.2:1866's v9 normalization sentence ("For Settings, §6.6's remainder hash is evaluated after normalizing its one exact runtime-provider line back to the frozen preimage; no other outside-deleteAccount byte changes."). Restored 2026-09-02 as a v9 decision missed in extraction; the C7 row carries the sentence verbatim, and S1 may change exactly that one line outside `deleteAccount()`.
8. C2.3 said "the existing absent and data-final branches remain" without stating them: v8 pointered v7 §11:1307 (`A later discover/begin/resume against an exact DATA_DELETED marker returns or replays the data-authority wire exact {schemaVersion:1,kind:"account_deletion_data_final",operationId,authorityKind:"member"|"authenticatedOverflow",startedAt,dataDeletedAt,replayed}`) and v9 §11:1678 still names it only as "the existing exact data-final wire". Restored 2026-09-06 into C2.3 together with the §11:1435 absent wire; S2 mirrors both, S3 consumes them.
9. The `taskReset` marker shape disagreed across three sources. Decided 2026-09-06: spec v5 §697 is canonical, exact `{schemaVersion:1,kind:"reset",operationId,requestFingerprint,state:"deleting"|"awaiting_local_reset",expectedTaskGenerationEpoch,taskGenerationEpoch,activeMoveEventId,targetIndex,pageAfterPath?,deletedCounts:{tasks,notificationIntents,taskDeadlineEvidence,confirmationSnapshots},deletedCount,lease?,createdAt,updatedAt,awaitingLocalResetAt?}`, with manifest v9 §5:543's terminal-state invariants layered on top: when `state == "awaiting_local_reset"`, `pageAfterPath` and `lease` are absent and `createdAt <= awaitingLocalResetAt <= updatedAt`. The marker is the `taskReset` field of the user root document `users/{uid}` (`functions/taskPlan.js:656` writes `{ taskReset: marker }` on `userRef`; spec v5 §697 calls it the user-root marker), so the account is implied by the path and the marker carries no `uid` or account member; §5:543's "account" is `ResetLocalCleanupAuthorityV1.accountUid`, compared against that path. `functions/taskPlan.js` lines 649–656 are the legacy preimage S2 replaces on the server, not a source; S3 consumes the marker (client cleanup callbacks and rules predicates). (Decision 4, 2026-09-06.)
10. S2 must mirror, and S3's client consume, unions the contract did not state: `inspectCommittedOperation` (only v9 §7:830–843), `reconcileLegacyTaskReset` with its legacy/migration authority (only v9 §6.1–6.4), the `reset_progress`/`reset_final` receipts with the canonical `rso1_` record/tombstone and dispatch rules (only spec v5 §3.3:631–638/693/695, §4.2:1005, §4.4:1068–1073), and `PHASE2_RESET_PROTOCOL_MODE` (only v9 §6.4:697). Added 2026-09-06 as C2.8, each block verbatim with its source line. C2.3 gained wire time encoding, the `replayed` rule, the §11:1435 resume sentence, and the thrown form of `DELETION_RETRY_REQUIRED` (v9 §11.3:1678's "returns" lost to §11:1437's `unavailable`). C7's Node pin became 24 (Decisions 3, 5, 9, 2026-09-06).
11. S2's fresh-context verification found six behaviors the code has and the contract did not state, and one reading the owner accepted (Decisions 1–2, 2026-09-06). Added 2026-09-06, each where S3 will read it: the fence error `failed-precondition/{schemaVersion:1,reason:"ACCOUNT_DELETION_FENCED"}` (C6.1); enrollment at DATA_DELETED, AUTH_GUARDING, and the permanent ACCOUNT_DELETED tombstone, so the tombstone's capability list may grow (C2.3; §11:1435 already said so, C2.3 did not); Build A's evidence-absent `DELETION_RETRY_REQUIRED`, the one non-transport source of that member (C3; §11.2:1652–1656); the marker `lease` inner shape `{ownerToken,expiresAt}` (C2.8, Reconciled 9 left it unstated); the four detail-less `unavailable` responses of `changeTaskPlan` as client-retried transport ambiguity (C2.8; spec v5 §4.2:1025); runtime validation of `authResidualRetentionSeconds` against `authResidualChecks` because the artifact holds only the destination digest (C3); and the deployment scope of `PHASE2_RESET_PROTOCOL_MODE`'s initialization failure (`FUNCTION_TARGET`/`K_SERVICE`), with detail-less `unavailable` outside a deployment (C2.8; v9 §6.4:697 did not say where the rule applies).

## Open

1. `capability_invalid` token: v8 names no fixture that rejects `capability_invalid` outside the C2.6 exit or that proves relaunch-from-bytes selects `local_cleared` for that token specifically; §8.9.6 covers only "capability-invalid never-enrolled remote deletion" and the generic crash-at-every-phase family.
2. Different-UID `ACCOUNT_DELETION_BUSY` in non-guarding phases (C2.4): no fixture is named in §8.9.6; only same-UID guarding refusal and Option-B are assigned.
3. Conditional global `peezy.user.firstName` removal (deleting A never clears B's cache): no named fixture; the registry source scan covers only UID-interpolated keys.
4. `storage.rules` owner/existing-root/no-marker predicate: the rules run includes `storage` in `emulators:exec` but the only named rules test file is `firestoreRules.test.js`; no Storage Rules test is named.
5. `phase2LegacyCreateBlocker` (§11.4): listed in C6.3, but no test is named for its permission-denied throw or blocking-configuration coverage; §11.4 fixtures name only the migration core and CLI guards.
6. Provider-copy destination arrays (Gmail, Twilio, FCM, Anthropic, Analytics, Crashlytics, Cloud Audit): zero-match and retention are owner-sealed evidence; the only in-repo falsifier is the sealer refusal test. No test observes a destination.
