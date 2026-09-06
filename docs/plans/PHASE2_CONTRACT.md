# PHASE 2 CONTRACT

This file states only what must be true for implementation: schemas, state tables, transitions, gates, registries, pins, ownership, and the test that falsifies each. "Exact" means unknown, missing, null-for-optional, or surplus members reject. `Cn` cites this file; there is no other authority. Amendment provenance lives in `docs/archive/phase2/PHASE2_CONTRACT_PROVENANCE.md`.

Three decisions are applied throughout: (D1) the capability-invalid exit persists `detachReason:"capability_invalid"`, a token distinct from `remote_unverified`; (D2) the deletion gate clears when the terminal presentation is consumed, and §6.6 defers to §8.9; (D3) `absence_retention` residual checks carry `destinationOrdinals` with exactly one ordinal, and the partition covers both check kinds.

## C1 Frozen inputs

| Artifact | Pin |
|---|---|
| Master baseline | `docs/plans/files/INSTITUTION_FLOWS_MASTER_v3.md` at commit `7546a0f` · sha256 `80e6dbd361c2d85706f538bea96558a61904346536dcb8e069435488bf6bbb8a` (no moving HEAD pin) |
| Four Build 25 WIP files | baseline commit `d321547`; authorized only at the call sites named in the C6.1 note |
| Resolution register | exactly 36 IDs: D1–D15, D18–D32, B1–B4, MIG-EVENT-V1, MIG-RESET-V1; D16/D17 withdrawn; sign-off trail in PEEZY_STATE §4; shapes in C2–C3, C9, C10 |

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

`EVIDENCE_POINTER_PATHS_V1` and `EVIDENCE_NON_POINTER_PATHS_V1` are stated once, in C9.6.4 and C9.6.5.

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

Cap vector: the eight escrow components and the other limits are stated once, in C9.6.8.

### C6.6 UID-scoped preference keys (ten; source-scan registry)

`phase1.pendingRetakeOperation.{uid}`, `peezy.{uid}.dailyDose.completedCount`, `peezy.{uid}.dailyDose.lastDate`, `peezy.{uid}.dailyDose.firstLaunchDate`, `peezy.{uid}.dailyDose.v2`, `peezy.{uid}.hasSeenFirstTimeWelcome`, `peezy.{uid}.lastGreetingDate`, `peezy.{uid}.totalCompletedCount`, `inventory.scanCoaching.seen.{uid}`, `inventory.narrationOffer.seen.{uid}`. All-scope additionally removes global `peezy.user.firstName`; UID deletion removes it only while Firebase still names that UID or no different current UID is established. `peezy.{uid}.dailyDose.v2` is accessed only through `DailyDoseLocalStore`.

### C6.7 `ACCOUNT_DELETION_EXTERNAL_FAMILIES_V1`

Direct deletes `userKnowledge/{uid}`, `supportThreads/{uid}`. Query deletes `conciergeRequests.userId`, `taskFlowSubmissions.userId`, `inventorySessions.userId`, `workflowSubmissions.userId`, `workflowSubmissions.owner` (unioned, deduplicated by path), `subscriptions.userId`, `vendorReviews.userId` (strike removal from the referenced vendor in the same transaction), `estimateCalibration.userId`, `admin/inventoryPackages/packages.userId`, `adminNotifications.userId`. `giftCodes.redeemedBy` is scrubbed by removing only the UID field. `ACCOUNT_DELETION_FIRESTORE_PAGE_SIZE = 100`; a page nominates, the reread transaction authorizes; no cursor persists.

### C6.8 Notification and FCM constants

Sole FCM surface: support-reply multicast in `functions/supportAdmin.js`, payload `notification:{title:"Peezy",body:"You have a new support reply."}`, `data:{thread:"support"}`, `android:{ttl:0}`, `apns:{headers:{"apns-expiration":"0"},payload:{aps:{sound:"default",badge:1,category:"PEEZY_SUPPORT_REPLY_V1"}}}`; `limit(501)` on `users/{uid}/fcmTokens`, 501 rows = `FCM_DESTINATION_CAPACITY`. Token write is exact `users/{uid}/fcmTokens/{token} = {createdAt:<server Timestamp>,platform:"ios"}`. `FCM_ACCEPTED_FAILURE_CODES_V1` is the 19-code union frozen from Firebase Admin 13.6.0; only `messaging/invalid-registration-token` and `messaging/registration-token-not-registered` permit token deletion. Support email/SMS text `New support message. Open Peezy admin.`; inventory email `New inventory package. Open Peezy admin.`; check-in SMS `New move check-in requires review. Open Peezy admin.`

## C7 Version and constant pins, and the diff gate

| Target | Pin |
|---|---|
| `@google-cloud/firestore` 7.11.6 (exact direct dependency) | `build/src/v1/firestore_client_config.json`: `Commit.timeout_millis == 60000`, `BatchWrite.timeout_millis == 60000`; `build/src/recursive-delete.js`: `RECURSIVE_DELETE_MAX_PENDING_OPS == 5000`, `RECURSIVE_DELETE_MIN_PENDING_OPS == 1000` |
| Transitive packages | `@google-cloud/storage` 7.18.0; google-gax 4.6.1; `google-auth-library` 9.15.1; `firebase-admin` 13.6.0; Firebase iOS SDK 12.7.0; Node 24 (`/opt/homebrew/opt/node@24/bin/node`, `functions/package.json` engines 24) |
| `firestore.indexes.json` | frozen base (3 indexes / 28 overrides) plus exactly eight appends: `schedulerRefusals` composite; empty overrides for `eventArchiveChunks.payload`, `tasks.foreignRoots`, `tasks.evidence_reservation`, `legacyResetMigrations.*`, `outboundLeases.*`; ASCENDING re-enables for `workflowSubmissions.userId` and `.owner`; result 4 indexes / 35 overrides, serialized `JSON.stringify(value,null,2)+"\n"`; the base and the appends are C9.2's index delta |
| Legacy reset fingerprint | accepted literal `reset1_862fe3fc8a08ce3eced6f25dfd2a8765b408e8386fa28f081f393d36f04e94a1` = `"reset1_" + sha256(committed legacy canonical({kind:"reset",reason:"retake_assessment"}))` |
| Migration parity fixture | UID `phase2-rule-owner` + legacy ID `20000000-0000-4000-8000-000000000001` → `rlm1_0a4d53a438873090f69e4255426310b0feb4cfd6` and `rlmreq1_0a4d53a438873090f69e4255426310b0feb4cfd63eabd6ce68c851ce827ad8e1` |
| Firebase identity | project `peezy-1ecrdl`; database `(default)`; bucket `peezy-1ecrdl.firebasestorage.app`; iOS app `1:833904565407:ios:d03ca5a2ca59f5f10156aa`; sender `833904565407`; region `us-central1`; `REVERSED_CLIENT_ID` = `com.googleusercontent.apps.833904565407-m9jhkhdhvih0aeeknk4fpcfbnv3g4oso`; exactly one URL-scheme entry in `Peezy-4-0-Info.plist` |
| Provider evidence trust anchor | one offline Ed25519 public key (32 bytes) whose base64url and sha256 are literal constants in `sealAccountDeletionProviderEvidence.js` and `accountDeletionFence.js`; `functions/accountDeletionProviderEvidenceV1.json` is the sole runtime authority, ≤131,072 canonical bytes, imported only by `accountDeletionFence.js` |

Diff gate (replaces the preimage hashes): at every checkpoint `git diff <base>..<head> -- <path>` shows no byte outside the named hunk.

| Path | Named hunk |
|---|---|
| `Peezy 4.0/Menu/PeezySettingsView.swift` | `deleteAccount()` and the one runtime-provider line of `retakeAssessment()`'s Firestore acquisition; `retakeAssessment()` otherwise unchanged |
| `Peezy 4.0/MainInterface/Models/RetakeAssessmentCoordinator.swift` | S3 (Decision 10): the initializer (authority-taking `ResetCleanupCallbacks`, `ResetRemoteProviding`, no operation store), `retake()` (reserve → bind/operation → `drive` → notification on `notify`), `production()`, and the removal of `RetakeOperationStore`/`UserDefaultsRetakeOperationStore`; `Error` cases and messages unchanged |
| `Peezy 4.0/Inventory/Models/InventorySessionManager.swift` | exactly six `Firestore.firestore()` substitutions plus `pendingNarration` |
| `Peezy 4.0/Inventory/Views/InventoryCameraView.swift` | `pendingNarrationTranscript` |
| `functions/processInventory.js` | process success, process error, `onInventoryRoomWritten`, the Anthropic call sites, and their logging sinks |
| `Peezy 4.0/Documents/GoogleService-Info.plist`, `Peezy-4-0-Info.plist`, `Peezy 4.0.xcodeproj/project.pbxproj` | zero hunks |
| `functions/index.js` | every pre-existing export line byte-identical; the armed-only `phase2LegacyCreateBlocker` block is the only export addition |

## C9 State tables, unions, and shapes behind the resolution register

Each subsection carries the shapes an implementer needs for the IDs in its title; C2–C6 remain the authority for anything they already state, and a C9 row never overrides them.

### C9.1 Scheduler (D1–D9, B1, D11)

#### C9.1.1 Function configuration (B1)

```text
region:         us-central1
schedule:       */5 * * * *
timeZone:       Etc/UTC
timeoutSeconds: 270
memory:         512MiB
maxInstances:   1
concurrency:    1
retryCount:     0
```

#### C9.1.2 Literal document paths

```text
phase1System/dispositionTriggerLease                                            (singleton scheduler lease)
phase1System/dispositionTriggerState                                            (scheduler state)
phase1System/dispositionTriggerState/migrationLeases/legacyOversizeMigrationV1  (cross-fence)
phase1System/dispositionTriggerState/phase2bAlerts/{alertId}                    (Phase-2b condition slots, server-only)
users/{uid}/schedulerRefusals/{refusalId}                                       (durable refusal, server-only)
```

| Rule | Exact statement |
|---|---|
| Client access, lease paths | Rules deny every client operation (owner/other/anonymous get/list/create/update/delete) at both lease paths. |
| Client access, refusals | Rules deny every client read/write at `users/{uid}/schedulerRefusals/{refusalId}`. |
| Account deletion | Account deletion removes the user-root `schedulerRefusals` collection (recursive). |
| Read budget | Acquisition read-count/budget constructor and its independent oracle include all three literal documents. |

#### C9.1.3 Time and ordinal sources

```text
runOrdinal            = floor(parseRFC3339(event.scheduleTime).epochSeconds / 300)
R                     = server readTime of initialization transaction (lease + trigger-state read)
activatedOrdinal      = floor(R.epochSeconds / 300) + 1
lastStartedOrdinal@init = activatedOrdinal - 1
leaseNow              = trigger-state snapshot server readTime in acquisition transaction
startedAt = runNow    = leaseNow
expiresAt             == leaseNow + 270 seconds
scheduledAt           = exact Firestore Timestamp parsed from event.scheduleTime
observationNow = observedAt = runNow
thresholdCutoff       = observationNow
completedAt           = server readTime of completion transaction's trigger-state read
ordinalFloor          = max(lastStartedOrdinal, lastCompletedOrdinal ?? activatedOrdinal - 1)
effectiveLast         = lastCompletedOrdinal ?? activatedOrdinal - 1
missingBeforeThisRun  = o - effectiveLast - 1
```

| Rule | Exact statement |
|---|---|
| Event acceptance | Handler accepts only the scheduler event delivered by this trigger; `scheduleTime` required. |
| Ordinal selection | Arrival time and process-local time never select an ordinal. |
| Malformed scheduleTime | Missing or malformed `scheduleTime` stops before lease or scheduler state is written. |
| Acceptance bound | Require `runOrdinal > ordinalFloor`. |
| Arithmetic | Every arithmetic result must be a safe nonnegative integer; all ordinal additions safe. |
| Process time | No process `Date` supplies a persisted or candidate-comparison time; process wall time only for monotonic admission elapsed time. |
| Expiry comparison | Same `leaseNow` compares prior v2 scheduler-lease expiry. |
| Frozen cutoff | Both threshold observation queries use frozen `observationNow`. |

#### C9.1.4 Lease shapes

```text
v2 scheduler lease (captured fencing tuple):
{schemaVersion:1,runOrdinal,ownerToken,startedAt,expiresAt}
ownerToken: pregenerated lowercase UUID

exact legacy lease (migrated by MIG-TRIGGER-V1, deleted in the reading transaction):
{runId,acquiredAt,expiresAt}
```

| Rule | Exact statement |
|---|---|
| Legacy migration sites | Exact legacy-lease migration applies at every lease read: initialization, MIG-EVENT acquisition, first Phase 2 scheduler acquisition. |
| Non-v2 shapes | Any other nonabsent non-v2 lease shape blocks at that reading transaction with zero write. |
| Release | Live owner deletes only its matching scheduler lease in `finally`; process death relies on expiry. |

#### C9.1.5 Initialization (schedule disabled)

| State | Event/condition | Next state | Writes |
|---|---|---|---|
| Uninitialized | `schedulerHealth` absent; lease absent | Initialized | `activatedOrdinal`, `lastStartedOrdinal = activatedOrdinal - 1`, `recentRuns:[]`; `lastCompletedOrdinal`, `dueObservation` absent |
| Uninitialized | `schedulerHealth` absent; lease exact `{runId,acquiredAt,expiresAt}` | Initialized | delete legacy lease + initialized fields, same transaction |
| Uninitialized | any other nonabsent lease shape | Blocked | none |
| Uninitialized | present/malformed health map, missing/nonempty initialization array, underflow/overflow, active schedule, unprovable enablement state | Rollout blocked | none |
| Initialized | commit + schedule enabled before UTC boundary of `activatedOrdinal` | Active | none |
| Initialized | tooling misses boundary | Active | floor not rewritten; first delivered later ordinal records the gap |

#### C9.1.6 Acquisition

| State | Event/condition | Next state | Writes |
|---|---|---|---|
| Idle | cross-fence document present (valid or malformed) | Refused | none (before heartbeat, state, scheduler-lease, cursor, refusal, alert, candidate) |
| Idle | `runOrdinal <= ordinalFloor` (duplicate/out-of-order) | Refused | no lease, health, cursor, refusal, alert |
| Idle | v2 lease present, nonexpired at leaseNow (other owner) | Refused | none |
| Idle | v2 lease present, expired | Running | atomic replacement of state + scheduler lease in the state-plus-scheduler-lease-plus-cross-fence transaction; `running` heartbeat appended; `lastStartedOrdinal` advanced |
| Idle | lease absent | Running | v2 lease + `running` heartbeat + `lastStartedOrdinal` |
| Idle | exact legacy lease and/or Phase 1 residue keys (`MIG-TRIGGER-V1`) | Running | delete legacy lease and residue keys; write v2 state and lease, same transaction |
| Idle | any other nonabsent non-v2 lease shape or foreign trigger-state key | Blocked | none |
| Running | `missingBeforeThisRun >= 2` | Running | observe/update `p2b1_two_missed_completions` before candidate work |
| Running | `missingBeforeThisRun` 0 or 1, gap observation succeeded | Running | delete prior missed-completion slot |
| Running | all admitted candidates settled and all page checkpoints committed | Completed | fenced completion transaction: heartbeat → `completed`, `lastCompletedOrdinal` advanced, samples + metric state |
| Running | any query, candidate, refusal-bookkeeping, checkpoint, metric-state, completion-write failure, deadline, timeout, kill | Incomplete | heartbeat stays `running`; `lastCompletedOrdinal` unchanged |
| Completed | completion commit | Emitted | `DISPOSITION_SCHEDULER_COMPLETED` `{runOrdinal}` only |

| Rule | Exact statement |
|---|---|
| Read set | The acquisition transaction reads all three literal documents (lease, trigger-state, cross-fence); leaseNow is the trigger-state snapshot's server readTime. |

#### C9.1.7 Fencing (every scheduler-owned mutation after acquisition)

| Rule | Exact statement |
|---|---|
| Fenced classes | phase-0 source/retry/quarantine/high-water, wake/intent/task, refusal create/update/delete, alert, cursor create/update/delete, durable metric state, heartbeat, completion. |
| Fence read | First read literal lease document in same transaction; require exact equality with captured `{schemaVersion:1,runOrdinal,ownerToken,startedAt,expiresAt}` and `expiresAt >` that read's server `readTime`. |
| Version | Lease read version participates in the commit. |
| Mismatch | Mismatch or already-expired read writes nothing; run incomplete. |
| Queries | Read-only queries only nominate candidates; eventual write transaction performs the fence. |
| A before B | A lease read serializing before B's takeover may finish idempotently before B's replacement; B observes its result. |
| B before A | B's replacement serializing first conflicts A's read/version; retry sees tuple mismatch; A writes nothing. |
| No bound claim | No claim that a pre-expiry read imposes a commit-time bound; no mutation begins from a lease read at or after expiry. |
| Completion | Completion is fenced; failed completion commit leaves heartbeat running, run unsuccessful. |

#### C9.1.8 schedulerHealth

```text
schedulerHealth:{
  schemaVersion:1,
  activatedOrdinal,
  lastStartedOrdinal,
  lastCompletedOrdinal?,
  recentRuns:[
    {runOrdinal,scheduledAt,startedAt,state:"running"} |
    {runOrdinal,scheduledAt,startedAt,state:"completed",completedAt,
     thresholdWakeLatency:({count:0} |
       {count:<positive>,p50Seconds,p95Seconds,maxSeconds})}
  ],
  dueObservation?
}
```

| State | Event/condition | Next state | Writes |
|---|---|---|---|
| (none) | accepted acquisition | `running` | append `{runOrdinal,scheduledAt,startedAt,state:"running"}`; `lastStartedOrdinal = runOrdinal` |
| `running` | fenced completion transaction commits | `completed` | `completedAt`, `thresholdWakeLatency`, `lastCompletedOrdinal = runOrdinal` |
| `running` | any failure / incomplete evaluation | `running` | none |

| Rule | Exact statement |
|---|---|
| recentRuns | Unique, strictly ordinal-ascending, retains newest four accepted ordinals. |
| Deployment | Initialized fields written before enabling schedule. |
| Running members | Running heartbeats forbid `completedAt` and `thresholdWakeLatency`; completed require both. |
| Sample | `max(0,floor((completedAt-threshold_at)/1000))` whole seconds per threshold path whose wake transaction committed in that run. |
| Sample set | Computed in completion transaction from run-local successfully committed threshold paths and stored `threshold_at`; no commit → no samples, no metric state. |
| Quantiles | Sort ascending; `p50`/`p95` nearest-rank at `ceil(.50*n)` / `ceil(.95*n)`. |
| count:0 | Exact `{count:0}` forbids all three quantiles; positive safe count requires all three. |
| Meaning | Completed-evaluation delivery telemetry; not per-write commit timestamp; not proof no row remained unwoken. |

#### C9.1.9 Completion observables

| Observable | Exact value |
|---|---|
| Structured code | `DISPOSITION_SCHEDULER_COMPLETED` |
| Dynamic fields | `runOrdinal` only |
| Log-based metric | `phase2/disposition_scheduler_completed_count` |
| Emission gate | Only after fenced completion transaction commits. |
| Non-emitters | Duplicate/out-of-order delivery, lease refusal, running-only heartbeat, every incomplete evaluation. |
| Dead-man policy | No increment for ten consecutive minutes pages named owner S3. |
| Excluded input | Generic platform invocation success is not an input. |
| Pre-ship checklist | Log-based metric and alert-policy resource IDs plus successful test notification. |
| Non-claim | Firestore heartbeat data not claimed to detect simultaneous absence of function and its own observer. |
| Timing rationale | 570 seconds on-time run; 870 seconds after one killed run; capacity rationale only. |

#### C9.1.10 Due observation (threshold-lane start)

```text
two uncursored global observations over this exact candidate superset:
collectionGroup("tasks")
  .where("thresholdProjection.state", "==", "armed")
  .where("thresholdProjection.threshold_at", "<=", observationNow)

query 1: aggregate count (read first)
query 2: same predicates + orderBy(thresholdProjection.threshold_at ASC, documentId ASC) + limit(1) (read second)
```

```text
dueObservation:{
  schemaVersion:1,observedAt,countReadTime,oldestReadTime,
  armedDueCandidateCount,
  oldestCandidatePath?,oldestThresholdAt?,oldestDueAgeSeconds
}
oldestDueAgeSeconds = max(0,floor((observedAt-oldestThresholdAt)/1000))
```

| State | Event/condition | Next state | Writes |
|---|---|---|---|
| Observing | count 0, oldest absent | Observed | `dueObservation` with three oldest members absent, `oldestDueAgeSeconds = 0` |
| Observing | count > 0, oldest present | Observed | `dueObservation` with all three oldest members |
| Observing | count 0 / oldest present, or count > 0 / oldest absent | `OBSERVATION_RACE` | no due observation, alert, cursor, completion; no threshold candidate admitted; heartbeat running; no synthesized map; no unbounded retry |
| Observing | either query fails | abort | same as `OBSERVATION_RACE` |

| Rule | Exact statement |
|---|---|
| Read times | Separate read times; never represented as one atomic snapshot. |
| Superset | Malformed/stale projections may produce conservative false positives; every valid overdue threshold row is in the superset. |

#### C9.1.11 Phase-2b condition slots

```text
{schemaVersion:1,condition:"TWO_MISSED_COMPLETIONS",
 firstObservedAt,lastObservedAt,firstObservedOrdinal,lastObservedOrdinal,
 occurrenceCount,effectiveLastCompletedOrdinal,requiredCompletedOrdinal}

{schemaVersion:1,condition:"OLDEST_DUE_OVER_900_SECONDS",
 firstObservedAt,lastObservedAt,firstObservedOrdinal,lastObservedOrdinal,
 occurrenceCount,candidatePath,thresholdAt,ageSeconds,
 armedDueCandidateCount}

{schemaVersion:1,condition:"THRESHOLD_CAPACITY_EXCEEDED",
 firstObservedAt,lastObservedAt,firstObservedOrdinal,lastObservedOrdinal,
 occurrenceCount,armedDueCandidateCount,admissionCapacity}

{schemaVersion:1,condition:"THRESHOLD_SCAN_CAPACITY_EXCEEDED",
 firstObservedAt,lastObservedAt,firstObservedOrdinal,lastObservedOrdinal,
 occurrenceCount,thresholdCutoff,candidateCountLowerBound,admissionCapacity}

{schemaVersion:1,condition:"FAIRNESS_CAPACITY_EXCEEDED",lane,
 firstObservedAt,lastObservedAt,firstObservedOrdinal,lastObservedOrdinal,
 occurrenceCount,eligibleRefusalCount,refusalCapacity}
```

```text
alertId:
p2b1_two_missed_completions
p2b1_oldest_due_over_900_seconds
p2b1_threshold_capacity_exceeded
p2b1_threshold_scan_capacity_exceeded
"p2b1_fairness_capacity_exceeded_" + lane        (lane ∈ seven-token lane union)
slot bound: eleven = 4 global + 7 fairness
```

| State | Event/condition | Next state | Writes |
|---|---|---|---|
| Absent | condition observed at ordinal `o` | Present(1) | `firstObservedAt = lastObservedAt`, `firstObservedOrdinal = lastObservedOrdinal = o`, `occurrenceCount = 1`, payload |
| Present(n) | later accepted ordinal observes condition | Present(n+1) | keep both first members; replace every payload member; advance both last members; safe increment |
| Present(n) | byte-identical same-ordinal retry | Present(n) | none (no-op) |
| Present(n) | same-ordinal disagreement, wrong condition/lane at literal slot, nonmonotonic ordinal, unsafe count, twelfth slot | Invariant | none; evaluation incomplete |
| Present(n) | complete observation phase succeeds and proves condition absent | Absent | lease-fenced delete of slot |
| Present(n) | incomplete run | Present(n) | none (never clears unobserved condition) |
| Absent (after delete) | recurrence | Present(1) | count restarts at one |

| Rule | Exact statement |
|---|---|
| Condition event | Each create/update emits one fixed-code structured condition event after commit. |
| Paging | Log-based metric and Cloud Monitoring policy page named owner S3 on every active observation. |
| Checklist | Pre-ship checklist records four global + seven lane-slot tests, metric/policy resource IDs, successful notification. |
| TWO_MISSED_COMPLETIONS | At `missingBeforeThisRun >= 2`: `effectiveLastCompletedOrdinal = effectiveLast`, `requiredCompletedOrdinal = o - 2`, observed before candidate work. |
| OLDEST_DUE_OVER_900_SECONDS | Observed whenever `oldestDueAgeSeconds > 900`, independent of wake-latency samples. |
| THRESHOLD_CAPACITY_EXCEEDED | Active iff `armedDueCandidateCount > thresholdAdmissionCapacity`; run does not meet objective. |
| THRESHOLD_SCAN_CAPACITY_EXCEEDED | `candidateCountLowerBound = thresholdAdmissionCapacity + 1`; never reuses aggregate count as shared snapshot. |
| FAIRNESS_CAPACITY_EXCEEDED | `refusalCapacity` = applicable exceeded ceiling: `100` contiguous, `200` catch-up; never the observed count. |

#### C9.1.12 Catch-up and capacity

```text
catchUp = (lastCompletedOrdinal is absent)
       || (missingBeforeThisRun >= 1)
       || (eligibleThresholdRefusalCount > 0)
       || (oldestCandidatePath is present && oldestDueAgeSeconds > 300)
thresholdAdmissionCapacity = catchUp ? 400 : 200
contiguous                 == (catchUp == false)
thresholdRefusalCeiling    = thresholdAdmissionCapacity == 200 ? 100 : 200
phase0 selected events     = 100
ordinary lane admissions   = 50 total fresh-plus-refusal (10 reserved for eligible refusals)
threshold lane admissions   <= thresholdAdmissionCapacity
candidate concurrency      <= 10
phase order                = phase 0 → threshold → six ordinary lanes
```

| Rule | Exact statement |
|---|---|
| Evaluation point | `catchUp` defined after threshold observations and eligible-refusal aggregate are read. |
| Residency | No implementation may have eight 50-row pages resident at once; pages fetched and settled sequentially. |
| Admission vs cancellation | Admission deadlines may stop starting new waves; admitted transaction is awaited; no transaction cancellation or settle-time bound assumed. |

#### C9.1.13 Launch-capacity envelope (measured by H57)

- at most 200 threshold-superset candidates due at any contiguous evaluation cutoff
- at most 200 additional candidates become due in any half-open 300-second ordinal
- after one incomplete/missing evaluation, next cutoff contains at most 400
- each user has at most 500 armed projections
- all counted projections satisfy the frozen producer schema/index contract
- objective applies only to a completed evaluation with cutoff observation within its 200/400 ceiling and each valid due candidate settled to wake or definitive no-op
- refusal, timeout, failed query/write, or capacity alert makes that evaluation unsuccessful for the objective
- operational launch assumption, not a claim about arbitrary population

#### C9.1.14 Paging equations and admission deadlines (D2/D5)

| Lane | select_n | limit | Checkpoint | Cursor | Deadline (monotonic seconds from run start, checked before each concurrency-10 wave) |
|---|---|---|---|---|---|
| phase 0 | 100 | 101 | 100th examined cursor iff row 101 exists; else delete own cursor | persisted | 40 |
| threshold | 50 | 51 | none persisted | run-local only; `thresholdCutoff = observationNow` | 130 |
| ordinary lane 1..6 (frozen order) | 50 | 51 | 50th iff row 51 exists; else delete own cursor | persisted, one key per lane | 142, 154, 166, 178, 190, 202 |

| Rule | Exact statement |
|---|---|
| Missed deadline | Starts no new wave; awaits/bookkeeps admitted work. |
| Phase-0 unadmitted row | Lane performs no cursor create/update/delete for the page; next run re-queries; processed rows settle idempotently. |
| Ordinary unclassified row | Selected row neither admitted nor classified by a durable-refusal-backed branch → no cursor create/update/delete for the page. |
| Threshold incomplete | Run incomplete unless fixed-point pass finishes; next run starts uncursored. |
| Hard stop | Function timeout is the only hard runtime stop; killed run stays incomplete; work replays idempotently. |
| Fixtures | Stop after each possible admitted/classified prefix of waves; prove zero premature cursor movement and zero skipped row. |

#### C9.1.15 Threshold fixed-point scan

| State | Event/condition | Next state | Writes |
|---|---|---|---|
| Scanning (run-local cursor) | page settled, more pages | Scanning | candidate mutations (fenced) |
| Scanning | page exhausted | Uncursored pass | none |
| Uncursored pass | no eligible distinct path/fingerprint outside run-local settled/refusal-backed set | Fixed point | delete prior scan-capacity slot; threshold completion permitted |
| Scanning, capacity consumed | continue scanning without mutation | Scanning | none |
| Scanning, capacity consumed | first additional distinct eligible candidate observed | `THRESHOLD_SCAN_CAPACITY_EXCEEDED` | slot with `candidateCountLowerBound = thresholdAdmissionCapacity + 1`; no candidate/cursor/completion after; run unsuccessful |
| any | deadline/timeout | Incomplete | none; next run uncursored |

| Rule | Exact statement |
|---|---|
| Admitted zero | "admitted zero" is not equivalent to fixed-point success. |
| Duplicate suppression | Run-local admitted set prevents one path/fingerprint appearing twice across passes or in both sources. |

#### C9.1.16 Trigger-state cursor namespace and MIG-TRIGGER-V1

```text
permitted optional keys (exactly seven): event_envelope_prepass + one per ordinary lane (six)
forbidden: threshold_attention cursor; every key other than the seven v2 keys or exact Phase 1 residue
Phase 1 residue keys (any subset, first Phase 2 acquisition only): dateAfterAt, dateAfterPath, eventTaskAfterPath
present value shape: frozen exact cursor-map shape
absence of any/all keys: start-of-range
```

| Rule | Exact statement |
|---|---|
| Migration branch | Required whether residue keys alone, legacy lease alone, both, or neither appear. |
| Foreign key | Any other unknown trigger-state key or nonexact legacy-lease shape refuses with zero write. |
| Post-migration | After the one acquisition, every non-v2 member is forbidden; never deleted or ignored. |
| Replacement 5.2 text | Old count "eight" becomes "seven"; threshold-cursor bullet deleted. |

#### C9.1.17 Page, projection, and admission invariants (D2/D3/D5)

| Rule | Exact statement |
|---|---|
| Phase 0 fixtures | Exact-100/101: 100 ends with cursor absent; 101 persists the 100th before next page. |
| Ordinary fixtures | Exact-50/51 with analogous 50th cursor. |
| Threshold fixtures | Exact-50/51 proves run-local paging, second uncursored fixed-point pass, no threshold cursor read/write in trigger state. |
| select() mask | Exactly filter fields, order fields, `task_generation_epoch`, `task_instance_id`; phase 0 uses its separately frozen event identity. |
| Candidate transaction | Reads complete document by path; compares query-captured generation/instance/update identity before mutation. |
| Runtime control | Admission, never cancellation, controls runtime. |

#### C9.1.18 Durable refusal record (D4)

```text
users/{uid}/schedulerRefusals/{refusalId}

refusalId = "srf1_" + first40(SHA-256(TaskCanonicalV1({
  domain:"scheduler_refusal.v1",lane,candidate_path:candidatePath
})))

lane = threshold_attention|date_snoozed_deferred|date_inprogress_user_action|date_matching_waiting|event_snoozed_deferred|event_inprogress_user_action|event_matching_waiting

{
  schemaVersion:1,lane,candidatePath,candidateFingerprint,
  firstRefusedOrdinal,lastAttemptOrdinal,nextEligibleOrdinal,
  refusalCount,saturated,reasonCode,firstRefusedAt,lastRefusedAt
}

reasonCode = VALIDATION_REFUSAL|AUTHORITY_REFUSAL|IDENTITY_RACE|TRANSACTION_RETRY_EXHAUSTED

candidateFingerprint = SHA-256(TaskCanonicalV1({lane,candidate_path,document_update_time,selected_identity}))
  (no domain member; no canonical bytes change)
selected_identity = lane's complete D3 field-mask result with explicit missing tags
```

| State | Event/condition | Next state | Writes |
|---|---|---|---|
| Absent, or fingerprint/reason changed | refusal at `currentOrdinal` | Refused(1) | `firstRefusedOrdinal = lastAttemptOrdinal = currentOrdinal`, `firstRefusedAt = lastRefusedAt = runNow`, `refusalCount = 1`, `saturated = false`, `nextEligibleOrdinal = currentOrdinal + 1` |
| Refused(n) | same-fingerprint/same-reason refusal | Refused(min(8,n+1)) | keep `firstRefusedOrdinal`, `firstRefusedAt`; `lastAttemptOrdinal = currentOrdinal`; `lastRefusedAt = runNow`; `refusalCount = min(8,old.refusalCount + 1)`; `saturated = (refusalCount == 8)`; `nextEligibleOrdinal = currentOrdinal + min(2^(refusalCount-1),16)` |
| Refused(n) | retry success / definitive no-op | Deleted | atomic with result |
| Refused(n) | candidate missing/changed on retry | Deleted | obsolete authority removed |
| Refused(n) | stale fingerprint on fresh admission | Deleted | after full candidate reread; candidate may consume one fresh slot same transaction |
| Refused(n) | derived-ID/path/lane disagreement or invariant violation | Fail closed | no candidate mutation, no cursor advance |

```text
valid row invariants:
1 <= refusalCount <= 8
saturated iff refusalCount == 8
firstRefusedOrdinal <= lastAttemptOrdinal < nextEligibleOrdinal
firstRefusedAt <= lastRefusedAt
```

| Rule | Exact statement |
|---|---|
| Eviction | The bounded in-document refusal map and every eviction rule are withdrawn; saturation never permits eviction. |
| Phase 0 | Retains its own retry/quarantine mechanism; never creates refusal records. |
| Authority key | One server-only document per `(uid,lane,candidatePath)`. |
| H57 reporting | Total, eligible, saturated, oldest, and alerts by lane; no task payloads. |
| Spec 7.4 | Gains exactly the composite index used by the eligible retry query. |

#### C9.1.19 Eligible retry query and admission

```text
collectionGroup("schedulerRefusals")
  .where("lane","==",lane)
  .where("nextEligibleOrdinal","<=",currentOrdinal)
  .orderBy("nextEligibleOrdinal","asc")
  .orderBy("firstRefusedOrdinal","asc")
  .orderBy("lastAttemptOrdinal","asc")
  .orderBy(documentId(),"asc")

dedup key       = (lane,candidatePath,candidateFingerprint)
ordinary reserve = 10 of 50 for eligible refusals
threshold reserve = half of applicable ceiling (100 of 200 | 200 of 400)
refusal page     = run-local 50/51; no persisted refusal cursor
```

| Rule | Exact statement |
|---|---|
| Order | Refusal-first deduplicated union; obtain aggregate eligible count first, then ordered pages until lane ceiling collected. |
| No materialization | Never materialize the aggregate population. |
| Over ceiling | Count above 100-or-200 creates `FAIRNESS_CAPACITY_EXCEEDED`; evaluation unsuccessful for objective; bounded ordered prefix still processed. |
| Fresh candidate | Transaction reads deterministic refusal path before consuming a slot. |
| Same fingerprint | Excluded from fresh admission at every ordinal; eligible and selected consumes one retry slot; ineligible or beyond cap skipped, consumes no slot. |
| Disagreement | Refusal-ID/content disagreement fails closed. |
| Transfer | Unused reserved slots transfer to other source; total never exceeds lane ceiling; source-internal order unchanged. |
| Retry reread | Reread refusal and candidate: missing/changed deletes obsolete authority; success/definitive no-op deletes atomically; another listed refusal updates it. |

#### C9.1.20 Ordinary cursor-pass branches

| Branch | Condition | Task write | Refusal write | Kill before checkpoint leaves |
|---|---|---|---|---|
| (1) | successful mutation / definitive no-op | mutation (none for definitive no-op) | delete matching refusal | committed result |
| (2) | exact refusal create/update after rereading candidate identity | none | create/update | committed refusal |
| (3) | candidate absent | none | delete obsolete refusal | committed deletion |
| (4) | lease-fenced reread proves extant deterministic refusal with exact ID/content and same fingerprint (ineligible or eligible beyond selected retry prefix) | none | none | still-queryable refusal + replayed fresh row |
| (5) | the owner root carries `accountDeletion` when read before any refusal or reducer write (fresh admission, retry, or refusal bookkeeping; the threshold lane's run-local cursor included) | none | none; a deletion fence is never translated into a refusal | nothing committed; the cursor settles past the candidate with zero writes beneath the owner (run-local outcome `fenced`; no durable metric); not a C9.1.18 abort |

| Rule | Exact statement |
|---|---|
| Never branch (4) | Stale-fingerprint, malformed, wrong-ID, wrong-content refusal. |
| Abort | Refusal classification/bookkeeping/checkpoint failure aborts the lane before checkpoint; cursor stays behind candidate. |
| Authority | Surviving branch-(4) refusal is the independent retry authority after the fresh-query cursor passes. |

#### C9.1.21 OriginalEventBytesV1 (D6)

```text
finite double  -> 16 lowercase hex digits of DataView.setFloat64(0,value,false), bytes 0..7 in order (big-endian)
nonfinite      -> nan | inf | -inf
fixtures: 1.0 -> 3ff0000000000000 ; -0 -> 8000000000000000 ; least positive subnormal -> 0000000000000001

predicate order:
1. null|boolean|string|number
2. v instanceof Date
3. v instanceof Timestamp | GeoPoint | DocumentReference | VectorValue   (pinned @google-cloud/firestore constructor identities)
4. Buffer.isBuffer(v)
5. Array.isArray(v)
6. plain map iff Object.getPrototypeOf(v) === Object.prototype || Object.getPrototypeOf(v) === null
7. NON_PLAIN_OBJECT        (every remaining nonnull object)
8. UNSUPPORTED_RUNTIME_TYPE (otherwise)
```

| Rule | Exact statement |
|---|---|
| Absent branches | No server `Bytes` constructor branch; no generic Uint8Array branch; `PROTOTYPE_MISMATCH` does not exist. |
| Infrastructure | Malformed recognized instances and cycles are infrastructure invariants, not quarantine tokens. |

```text
encoding (UTF-8 text; originalBytesDigest = SHA-256 over the encoded bytes of the source's top-level field map
          with the scheduler retry member phase0ValidationFailure removed):
  null               -> n
  boolean            -> t | f
  string             -> s<UTF-8 byte length>:<UTF-8 bytes>
  number             -> d<16 hex | nan | inf | -inf>
  Date               -> D<16 hex of getTime()>
  Timestamp          -> T<seconds>.<nanoseconds, nine digits>
  GeoPoint           -> G<16 hex latitude>,<16 hex longitude>
  DocumentReference  -> R<path UTF-8 byte length>:<path bytes>
  VectorValue        -> V<count>[<16 hex per element, joined by ",">]
  Buffer             -> B<byte length>:<raw bytes>
  Array              -> A<count>[<element encodings joined by ",">]
  plain map          -> M<count>{<entries "s<len>:<key>=<value encoding>", keys in unsigned UTF-8 byte order, joined by ",">}
malformed recognized instance (non-integer or out-of-range Timestamp members, invalid Date, nonfinite GeoPoint or
Vector element, non-string reference path) and any cycle -> ORIGINAL_BYTES_INVARIANT (no write)
```

#### C9.1.22 SOURCE_UNENCODABLE quarantine (D7)

```text
unencodableSourceDigest = SHA-256(TaskCanonicalV1({
  domain:"unencodable_source.v1",source_path,reason_token,update_time
}))
quarantineId = "qevu1_" + first40(unencodableSourceDigest)
token = NON_PLAIN_OBJECT|UNSUPPORTED_RUNTIME_TYPE

record (normal quarantine collection):
{schemaVersion:1,sourcePath,sourceUpdateTime,unencodableSourceDigest,
 reason:{code:"SOURCE_UNENCODABLE",token,message},failureCount:1,
 firstFailedAt:runNow,lastFailedAt:runNow,quarantinedAt:runNow}

NON_PLAIN_OBJECT         -> Source contains a non-plain object.
UNSUPPORTED_RUNTIME_TYPE -> Source contains an unsupported runtime type.
record cap: 16,384 canonical bytes
```

| Rule | Exact statement |
|---|---|
| Forbidden member | `originalBytesDigest` forbidden. |
| Replay | Exact existence is replay; disagreement fails closed. |
| Source transaction | Same transaction: source retains producer fields, deletes any retry map, writes standard terminal/quarantined fields at same `runNow`. |
| Admission | MIG-EVENT gate enforces retry-or-terminal envelope; first-occurrence terminalization mechanically fittable. |
| Disjoint | Normal digest and migration-archive branches remain disjoint. |

#### C9.1.23 Storage formulas (D8, copied from Standard edition 2026-09-01)

```text
Bytes             = byte length
GeoPoint          = 16
DocumentReference = referenced document-name size (each collection/document component UTF-8 bytes + 1, plus 16)
Vector            = 8 * dimensionCount
index entry value contribution cap (ascending/descending/array/composite) = 1,500 bytes
geospatial-special (inapplicable, recorded only) = collection-name size + document-ID size + 128 per indexed point + 48
```

| Rule | Exact statement |
|---|---|
| Registry modes | Frozen spec-7.4 registry has no vector, text-search, or geospatial-special index mode; later special mode requires registry/hash/budget amendment. |
| Dual implementation | Production and the independent oracle separately implement the copied equations. |

```text
base equations (Standard edition 2026-09-01):
  string                 = UTF-8 bytes + 1
  boolean | null         = 1
  integer | double       = 8
  Timestamp              = 8
  map                    = Σ (field-name string size + value size)          (no map overhead)
  array                  = Σ element sizes
  document name          = Σ over every collection ID and document ID of (UTF-8 bytes + 1), plus 16
  document               = document name size + top-level map size + 32
  index entry            = document name size + Σ indexed value sizes (each capped at 1,500) + 32

index policy (frozen registry = firestore.indexes.json C7 result):
  every leaf field path of a document carries automatic COLLECTION-scope ascending and descending entries (two entries);
  an array leaf carries one array-contains entry per element instead; a map contributes only its leaf paths;
  a fieldOverrides row replaces the automatic set for that (collectionGroup, fieldPath) and for every leaf path beneath it exactly (empty list = exempt);
  each composite index whose collectionGroup matches and whose fields are all present yields one entry over those values.

FirestoreWriteBudgetV1(transition) = Σ over touched documents of
  (post document size when created or updated) + (pre document size when deleted)
  + Σ sizes of index entries present after and absent before + Σ sizes of entries present before and absent after
bounds: prospective document <= 1,048,576; every entry <= 7,680; entries per document <= 40,000;
        entry-byte sum per document <= 8,388,608; FirestoreWriteBudgetV1(transition) <= 8,388,608; safe arithmetic
```

#### C9.1.24 Raw Vector discriminator (pinned public-v1 Document)

```text
enters Vector validation iff map has exactly two fields:
  __type__ : {stringValue:"__vector__"}
  value    : {arrayValue:<A>}
A = {values:[{doubleValue:<finite binary64>},...]}   1..2,048 dimensions
zero dimensions: {} | {values:[]} only
stored bytes = 8 * count ; ordinary 1,500-byte index truncation
missing/malformed/surplus member -> ARCHIVE_CODEC_INVARIANT (blocks rollout/runtime mutation)
every other map (value alone, __type__ other, both without exact discriminator) -> ordinary map arithmetic
```

#### C9.1.25 RawPhase0SizingV1

| State | Event/condition | Next state | Writes |
|---|---|---|---|
| `SOURCE_UNENCODABLE` identified | fetch exact source via pinned public-v1 `getDocument`; retain raw Document/Value tree + updateTime | Raw held | none |
| Raw held | Admin transaction rereads source; identical path and updateTime | Terminalizing | field-path update/delete only; qevu record created separately |
| Raw held | drift | Raw held | none; restart with fresh raw read |
| Raw held | raw absence, path/updateTime mismatch after bounded retry, unknown Value oneof, malformed reserved Vector, raw sizing/codec disagreement | `POST_CUTOFF_SOURCE_SIZE_INVARIANT` | no source write |

| Rule | Exact statement |
|---|---|
| fitsPhase0TransitionRaw | Preserves every producer field byte-for-byte; removes only scheduler retry member; overlays only exact terminal scheduler fields; same document/index/transaction equations. |
| No decode | Terminalization never decodes or rewrites producer fields. |

#### C9.1.26 Ordinary qev1 code/message table (D9)

```text
REFERENCE_INVALID          -> Event source path is invalid.
ENVELOPE_INVALID           -> Event envelope must be a map.
EVENT_ID_INVALID           -> event_id must equal the document ID.
EVENT_NAME_INVALID         -> event_name must be nonblank.
CANONICAL_KEY_INVALID      -> canonical_key must be nonblank.
SOURCE_VERSION_INVALID     -> source_version must be a nonnegative safe integer.
OBSERVED_AT_INVALID        -> observed_at must be a valid timestamp.
SOURCE_EVIDENCE_ID_INVALID -> source_evidence_id must be nonblank.
EFFECT_INVALID             -> effect must be fire or retract.
PAYLOAD_INVALID            -> payload must be valid Firestore event data.
PAYLOAD_TOO_LARGE          -> Event payload cannot fit the Phase 2 high-water record.
PROCESSED_INVALID          -> Event must be pending and unprocessed.
```

- every message below 1,000 UTF-8 bytes; no truncation choice

```text
retry member (source document, attempts 1 and 2):
phase0ValidationFailure = {schemaVersion:1,originalBytesDigest,reasonCode,failureCount,firstFailedAt,lastFailedAt}
  attempt n = 1 + (existing retry member with the same originalBytesDigest and reasonCode ? failureCount : 0)
  different digest or code restarts at 1; a retry member of any other shape -> PHASE0_RETRY_MAP_INVARIANT (no write)

quarantineId = "qev1_" + first40(originalBytesDigest)
record (normal quarantine collection, attempt 3):
{schemaVersion:1,sourcePath,sourceUpdateTime,originalBytesDigest,
 reason:{code,message},failureCount:3,
 firstFailedAt:<retained from the retry member>,lastFailedAt:runNow,quarantinedAt:runNow}
record cap: 16,384 canonical bytes
replay: an existing record with equal sourcePath, sourceUpdateTime, originalBytesDigest, and reason is replay
        (its timestamps are retained); any other existing record fails closed
```

#### C9.1.27 fitsPhase0Transition and retry-or-terminal envelope

```text
fitsPhase0Transition(preSource,preHighWater?,postSource,postHighWater?,quarantine?)
inputs: D8, final normalized spec 7.4, FirestoreWriteBudgetV1
bounds:
  prospective document        <= 1,048,576 bytes
  entry                       <= 7,680
  per-document entry count    <= 40,000
  per-document entry-byte sum <= 8,388,608
  complete create/update/delete charge (incl. symmetric index-entry deltas) <= 8,388,608
  safe arithmetic
absent optional documents: exact create/delete semantics; byte-equal preexisting quarantine = zero write

R(code,count): S with only phase0ValidationFailure replaced by
  {schemaVersion:1,originalBytesDigest:<64 lowercase hex>,reasonCode:code,failureCount:count,
   firstFailedAt:<Firestore Timestamp>,lastFailedAt:<same-or-later Firestore Timestamp>}
  for each ordinary qev1 code, count ∈ {1,2}
Q(message): unrelated producer fields preserved; phase0ValidationFailure removed; scheduler fields =
  {processingState:"terminal",processed:true,processedAt:<Firestore Timestamp>,outcome:"quarantined",processingError:message}
qevu terminal prospects (two): fitsPhase0TransitionRaw over raw sidecar only

envelope: FirestoreDocumentStorageBytes(sourcePath,S) <= 1,047,552
      AND every S→R(code,count), every qev1 terminal, both raw qevu terminals (+ maximum exact quarantine create) fit
reserve = 1,024 bytes (proved by complete prospective transactions)
SOURCE_TOO_LARGE iff base comparison or any prospective fit check fails; base equality admitted only when all pass
```

| Rule | Exact statement |
|---|---|
| Timestamps | Timestamp storage size fixed; concrete values do not affect the bound. |
| Classification | `SOURCE_TOO_LARGE` is admission/audit for MIG-EVENT and future server producers, not ordinary qev1 retry after migration gate. |
| MIG-EVENT | Computes entire envelope from raw `Document` including exact vector rule. |
| Future producer | Applies same oracle before create; returns own authorized caller surface without writing when classification fires; Phase 2 adds no producer (publisher registry empty). |
| Mandatory | `fitsPhase0Transition` for every decoded retry/qev1 terminal, valid advance, stale/duplicate/version-conflict terminal; `fitsPhase0TransitionRaw` for qevu. |
| Size-skip | Stale/duplicate/version-conflict keep semantic size-skip but must fit concrete source-only terminal transition. |
| No shared code | Production and independent oracle share no implementation. |

#### C9.1.28 POST_CUTOFF_SOURCE_SIZE_INVARIANT

| Observable | Exact value |
|---|---|
| Trigger | Phase-0 runtime encounter after spec 3.8 has passed (also when earlier semantic classification such as `SOURCE_UNENCODABLE` was identified). |
| Writes | None: no retry map, quarantine, high-water, source, cursor, completion; heartbeat running. |
| Structured error fields | code, source path, base/oracle prospective maxima, run ordinal only. |
| Metric | `phase2/post_cutoff_source_size_invariant_count` |
| Policy | Page S3 on any positive value. |
| Checklist | Metric/policy resource IDs + successful test notification. |
| Forbidden | Raw source bytes in log and alert. |

#### C9.1.29 Validation precedence and PAYLOAD_TOO_LARGE

```text
REFERENCE_INVALID
→ SOURCE_UNENCODABLE
→ SOURCE_TOO_LARGE
→ ENVELOPE_INVALID
→ EVENT_ID_INVALID
→ EVENT_NAME_INVALID
→ CANONICAL_KEY_INVALID
→ SOURCE_VERSION_INVALID
→ OBSERVED_AT_INVALID
→ SOURCE_EVIDENCE_ID_INVALID
→ EFFECT_INVALID
→ PAYLOAD_INVALID
→ PAYLOAD_TOO_LARGE
→ PROCESSED_INVALID

PAYLOAD_TOO_LARGE iff fitsPhase0Transition(currentSource,currentHighWater?,advanceTerminalSource,prospectiveHighWater,absent) == false
  (equality at every document/index/complete 8,388,608-byte limit admitted)
```

| State | Event/condition | Next state | Writes |
|---|---|---|---|
| Validating | validators through `PAYLOAD_INVALID` pass; high-water classification `advance` | size predicate | exact prospective spec-5.2 event-state map, exact terminal source with retry-map deletion and `outcome:"advance"`, literal source/high-water paths, current high-water bytes when present |
| Validating | classification stale / duplicate / version-conflict | terminal outcome | terminalize event; high-water unchanged; semantic size predicate skipped |
| size predicate | true, attempt 1 or 2 | pending | exact retry map; source pending |
| size predicate | true, attempt 3 | quarantined | ordinary exact schema-v1 `qev1` digest record with table code/message; source terminalized with same message; retry map deleted; high-water unchanged |
| Validating | no earlier reason won | `PROCESSED_INVALID` check | — |

| Rule | Exact statement |
|---|---|
| Size vs unencodable | Size cannot precede an unencodable value. |
| Non-reasons | Stale, duplicate, version-conflict are valid terminal outcomes, not validation reason codes. |
| Boundary fixtures | Valid-oversize versus stale; never stale-and-invalid source. |

```text
spec-5.2 event-state map (users/{uid}/eventState/{canonicalEventStateId}):
{event_name,canonical_key,source_version,effect,event_id,observed_at,source_evidence_id,payload,fingerprint,advancedAt}
  observed_at = Timestamp of the canonical envelope's observed_at; fingerprint = SHA-256(TaskCanonicalV1(envelope));
  advancedAt = runNow
```

#### C9.1.30 Regeneration (D11) — PEEZY_STATE_REGEN_SPEC.md item 9 exact replacement

```text
9. **Next post-Phase-2 regeneration — H57 disposition operations (do not replace or renumber H56):** after fresh static evidence verifies the producer, add one split-disposition §1 row: `H57` producer source `SUPPORTED` · deployed/consumer `UNKNOWN`. The producer evidence must cover the persisted full-path phase-0 cursor; ordinary deterministic `qev1` quarantine after three identical deterministic validation failures; first-occurrence unencodable `qevu1`; migration `qev2` plus archive terminalization; broken and orphan archive manifest/chunk/byte counts; post-cutoff source-size invariant count/alert; scheduler heartbeats, ordinal gaps, due-candidate age and Phase-2b alerts; scheduler-refusal total, eligible, saturated and oldest counts by lane; `SCHEDULER_WRITE_BUDGET_INVARIANT` count/alert; account-deletion DELETING count/oldest age, retained DATA_DELETED and ACCOUNT_DELETED tombstone counts, and `account_deletion_capability_registry_full_count` plus its alert; `account_deletion_late_object_cleanup_count` plus its retry alert; `account_deletion_outbound_lease_live_count`, `account_deletion_outbound_lease_expired_count`, `account_deletion_outbound_lease_capacity_refusal_count`, and `account_deletion_outbound_lease_invariant_count`, `support_fcm_destination_capacity_count`, `support_fcm_token_schema_invariant_count`, `account_deletion_bucket_config_drift_count`, `account_deletion_storage_work_backlog_count`, `account_deletion_storage_work_oldest_age_seconds`, `account_deletion_storage_guard_overdue_count`, `account_deletion_storage_work_saturated_count`, `account_deletion_storage_work_invariant_count`, `account_deletion_storage_reconciler_completed_count`, `account_deletion_auth_work_backlog_count`, `account_deletion_auth_work_oldest_age_seconds`, `account_deletion_auth_guard_overdue_count`, `account_deletion_auth_work_saturated_count`, `account_deletion_auth_work_invariant_count`, `account_deletion_auth_reconciler_completed_count`, `account_deletion_legacy_candidate_count`, `account_deletion_legacy_deferred_count`, and `client_telemetry_relaunch_required_count`, with the lease/token/bucket/work/migration/telemetry invariant alert resources, both separate 10-minute reconciler dead-man resources, and successful test notifications; and `LOCAL_ACCOUNT_PURGE_WHOLE_STORE` diagnostics by store/source token. The outbound metrics contain only channel/fixed-condition tokens and bounded counts—never UID, delivery ID, destination, provider request ID, or payload. Static search must cover `functions/index.js` and its active backend graph, active `Peezy 4.0/**/*.swift`, `firestore.rules`, `firestore.indexes.json`, `storage.rules`, `firebase.json`, `.firebaserc`, `public/`, and repository ops/CI configuration. If it finds no active reachable reader, alert, export, admin surface, cleanup/TTL, or named operational owner for a produced artifact, that consumer remains `UNKNOWN`; name the negative search scope and list the unqueried live facts: deployed revision, stored quarantine/archive/refusal/alert documents, account-deletion markers/work/migration candidates, Cloud Logging and Monitoring/alert state, and out-of-repo operator/runbook practice. Capture producer-path hits and the quiet negative consumer search in the evidence log. Never copy raw archive, event, task, outbound, or provider bytes. A produced record or metric is not proof of consumption, and this regeneration instruction is hypothesis rather than evidence.
```

| Rule | Exact statement |
|---|---|
| Replacement mode | Replace item 9 in full; do not merge with old wording. |
| Zero occurrences | `after three identical deterministic validation failures` outside the quoted replacement; old unsplit `H57 quarantine consumer` heading. |
| Ownership | S3 owns implementation evidence, not an implied operational consumer. |
| Evidence log | Capture producer-path hits and the quiet negative consumer search in the evidence log. |
| 5.2 replacement | Includes the first-acquisition `MIG-TRIGGER-V1` branch: residue and/or legacy lease transactionally removed while v2 shape written; neither required present; every foreign unknown member refuses. |

#### C9.1.x Named falsifiers

| Test file | Named test / fixture family |
|---|---|
| (not named) | both literal lease paths; simultaneous state/scheduler-lease/cross-fence reads |
| (not named) | exact-legacy-lease migration at scheduler acquisition; malformed legacy refusal |
| (not named) | present valid or malformed migration cross-fence with zero scheduler mutation |
| (not named) | owner/other/anonymous get/list/create/update/delete denial at lease paths |
| (not named) | cursor namespace: all-absent, each singleton, all seven present |
| (not named) | residue: each residue shape alone, both together, neither; one foreign unknown key alongside valid residue → refusal; old threshold cursor / any unknown key rejected |
| (not named) | exact legacy versus malformed non-v2 lease at each of the three read sites |
| (not named) | initialization just before/on exact five-minute boundary; delayed enable; first delivery at `activatedOrdinal`, `+1`, `+2`; arithmetic overflow; activation/no run |
| (not named) | first, contiguous, one-gap, two-gap, three-gap ordinals |
| (not named) | duplicate, out-of-order, lease-refused deliveries with zero completion metric |
| (not named) | death before/after heartbeat, after candidate settlement, before completion, after completion commit/before metric emission |
| (not named) | lease expiry and atomic replacement; takeover immediately before every mutation-class commit |
| (not named) | A live pre-expiry read while B serializes takeover before A commit; retry after B takeover proving tuple mismatch/zero write; no mutation from expired read |
| (not named) | threshold row formerly behind a persisted cursor; insertion/movement behind run-local cursor caught by next pass |
| (not named) | aggregate count exactly 200/400 then late cutoff-eligible distinct candidate → scan-capacity slot, no checkpoint/completion, next-run replay |
| (not named) | malformed projection inclusion; eligible 20-minute-old row with no wake sample; independent observation read times |
| (not named) | every launch-envelope boundary; exact 200/201 and 400/401 aggregate capacity |
| (not named) | nearest-rank metrics including zero samples; sequential page residency |
| (not named) | ordinary final-checkpoint-before-completion; fixed-point-before-threshold-completion |
| (not named) | 10,000 persistent-condition ordinals retaining at most eleven slots; same-ordinal replay/disagreement; resolve/recur/count-overflow/takeover for every slot shape |
| (not named) | recorded/tested completion and condition metrics/policies; no-op platform-success masking test |
| (not named) | four global + seven lane-slot alert tests; successful notification |
| (not named) | phase 0 exact-100/101; ordinary exact-50/51; threshold exact-50/51 run-local + second uncursored pass + no trigger-state threshold cursor |
| (not named) | stop after each admitted/classified prefix of waves: zero premature cursor movement, zero skipped row |
| (not named) | refusals: 64/65/201/1,000 records, zero eviction, bounded 50/51 reads |
| (not named) | continuous new arrivals while fixed older refusal retried; count `7→8→8`; 16-ordinal saturated retry; fingerprint/reason reset |
| (not named) | same-fingerprint ineligible and eligible refusals visible in fresh query, never admitted fresh |
| (not named) | 51 early ineligible matching refusals then fresh rows: branch (4) advances, later fresh rows admitted |
| (not named) | eligible refusal beyond selected retry prefix reachable by independent query after cursor advance |
| (not named) | crash immediately before/after checkpoint for branch (4); stale refusal cleanup then one fresh admission |
| (not named) | retry/fresh duplicate across threshold passes; both source transfer directions; all four reason codes |
| (not named) | failure before bookkeeping; crash after bookkeeping; success/missing/change cleanup; hash collision |
| (not named) | exact 200/201 fairness alert behavior; rules/index parity; reset-created orphan deleted when missing task retried; recursive account deletion |
| (not named) | encoder: `1.0→3ff0000000000000`, `-0→8000000000000000`, subnormal `→0000000000000001` (production and oracle) |
| (not named) | raw-vector: both zero spellings; 1/2,048 dimensions; 2,049; discriminator missing/malformed/surplus; ordinary `{value:...}`; ordinary `{__type__:"other",value:...}`; near-budget terminal/index parity production vs oracle |
| (not named) | base source size 1,047,552/1,047,553; base-boundary source at retry count 1, 2, each terminal+quarantine transaction |
| (not named) | decoder-only unsupported runtime view over byte-identical raw Document: qevu field-mask terminalization at fit/equal/+1 without producer rewrite; raw read/updateTime drift |
| (not named) | base-admitted source rejected solely by prospective document/index/complete-transition check; every ordinary code/message in the maximum |
| (not named) | post-cutoff invariant: zero source/retry/quarantine/high-water/cursor/completion write, exact metric/alert |
| (not named) | valid-advance full-transition exact/equal/+1 at 8,388,608 incl. old high-water update with long shared field paths (removed+added index multiset charge) |
| (not named) | prospective high-water document, per-entry, total-index-byte, entry-count limits at equal/+1 |
| (not named) | `PAYLOAD_TOO_LARGE` attempt `1→2→qev1`; stale/duplicate/version-conflict source-only terminal transitions retaining size-skip |
| (not named) | production/oracle disagreement failure; exact fixed messages with no raw bytes |
| `functions/tests/dispositionTriggers.test.js` | branch (5): a deleting owner's candidate on the fresh, retry, threshold, and nested-event paths settles with zero writes beneath the owner and no refusal record (S3-CD5) |
| `functions/tests/dispositionTriggers.test.js` | "C9.3.11 interim (S3-CD8): policy-present rows produce zero writes in every lane" (S3-CD8) |

### C9.2 MIG-EVENT-V1 and the index delta (D10, MIG-EVENT-V1)

#### C9.2.1 Scope, query, and stream classification

```text
module:  functions/scripts/migrateOversizeEvents.js            (owner: S3)
API:     pinned public-v1 FirestoreClient.runQuery (streaming)
parent:  projects/peezy-1ecrdl/databases/(default)/documents
StructuredQuery:
  from:    [{collectionId:"events",allDescendants:true}]
  where:   {fieldFilter:{field:{fieldPath:"processingState"},op:"EQUAL",value:{stringValue:"pending"}}}
  orderBy: [{field:{fieldPath:"__name__"},direction:"ASCENDING"}]
  limit:   {value:100}                                          (google.protobuf.Int32Value wrapper)
  startAt: {before:false,values:[{referenceValue:<last complete document name>}]}   (only after a full 100-document page)
in-scope name: projects/peezy-1ecrdl/databases/(default)/documents/users/{nonblankUid}/events/{nonblankEventId}   (exactly one segment each)
reread:  getDocument(<literal full name>)  -> raw createTime, updateTime, complete fields
pin:     @google-cloud/firestore 7.11.6
         build/src/v1/firestore_client_config.json SHA-256 2ed7a9046d766121b7f308b22384b1a6caaf7c6eaed5d9ea553556af3c987e41
         BatchWrite.timeout_millis == 60000 ; Commit.timeout_millis == 60000
```

| Response shape | document | readTime | done | Effect |
|---|---|---|---|---|
| document | exactly one complete raw `Document` | one valid | absent or literal `true` | counts toward 100-page; `true` = final document + terminal marker |
| progress | none | one valid | absent | anywhere; not counted |
| done | none | absent or valid when present | literal `true` | terminal |
| (all three) | forbid `transaction`, nonzero `skippedResults`, `explainMetrics`, every unknown own property surfaced by the pinned binding | | | |

| Rule | Exact statement |
|---|---|
| limit wrapper | absent, numeric/unwrapped, nonsafe, nonpositive, or out-of-int32-range `limit` is fatal before query |
| paging | process raw documents sequentially; count only document responses toward the 100-document page; never materialize a page of payloads |
| presence | classify by protobuf field presence, never generated-object defaults |
| terminal | at most one true terminal marker; nothing may follow it; normal stream EOF also terminates |
| empty query | valid at normal EOF only after at least one valid readTime progress response |
| fatal | present `done:false`; empty member; missing/invalid document readTime; invalid present done-response readTime; nonzero `skippedResults` (positive or negative); forbidden/surfaced-unknown/mixed shape; stream error; duplicate/nonascending document name; non-reference cursor |
| unknown wire tags | pinned decoder discards before delivery; not claimed detectable |
| run report | records exact `@google-cloud/firestore` version and generated descriptor digest |
| out of scope | any other matching collection-group path is `OUT_OF_SCOPE_SOURCE` and blocks rollout |
| predicate | complete retry-or-terminal predicate computed from the response's raw protobuf `Value` tree |
| reread | immediately before deriving archive identity or any write, `getDocument` rereads the literal full name; only the reread's raw createTime/updateTime/fields enter C9.2.6 |
| reread drift | missing, no-longer-pending, or now-admitted reread: no archive write, restart classification on next confirmation pass; still-failing changed document uses only its new identity |
| forbidden APIs | no `DocumentSnapshot.data()`, no JSON, no private SDK member |
| two-pass | audit: second full uncursored pass after first complete zero-failing pass; apply: same confirmation while holding the fenced lease |
| C9.2.9 pass criterion | two consecutive complete passes with zero failing sources, zero out-of-scope sources, and the same total pending-source count; any insertion/change observed by the confirmation pass restarts the two-pass requirement |
| output | only document paths/IDs, digests, counts, enum outcomes, lease metadata; never raw source/archive/chunk bytes |

#### C9.2.2 Arming and deployment order

```text
arming triple (same invocation): --apply --project-id peezy-1ecrdl --confirm-project peezy-1ecrdl
```

| Rule | Exact statement |
|---|---|
| import | module is import-side-effect-free |
| default mode | audit/read-only; cannot acquire a lease or issue a write |
| write mode | requires literal arming triple AND no unknown argument AND public-v1 client resolves to project `peezy-1ecrdl` / database `(default)` AND `FIRESTORE_EMULATOR_HOST` absent AND normalized rules/index hashes match the accepted rollout tuple AND fenced lease acquired |
| fail closed | missing/mismatched confirmation, different resolved project/database, emulator variable, hash mismatch, unknown argument, or lease refusal exits nonzero before the first write |
| audit exit | audit mode exits zero only when the C9.2.9 pass criterion holds (two consecutive complete passes with zero failing sources, zero out-of-scope sources, and the same total pending-source count); any other outcome — a complete pass with failing or out-of-scope rows, an incomplete pass, or an insertion/change observed by the confirmation pass — ends the run nonzero; the C9.2.1 restart is a new invocation |
| drains | external rollout authorization gate proved by platform evidence; script neither infers nor claims to prove them from a caller-supplied file |
| production run report | exact command, resolved project/database, tuple hashes, captured platform drain evidence, owner token/generation, counts, result |

| Step | Action | Wait/condition |
|---|---|---|
| 1 | deploy + refreeze archive rules plus `eventArchiveChunks.payload` exemption | until index exemption effective |
| 2 | revoke invocation of `deleteAccount`; `Tzero` = proved end of final old execution; pin 7.11.6 + config SHA + both `timeout_millis == 60000` | through `Tzero + 60,000 ms` before any migration-lease/archive write; conservative (last deletion invocation began immediately before revocation): 120 seconds after revocation |
| 2' | `Tzero` unprovable: undeploy revision, prove zero instances | full RPC window; package/config mismatch blocks rollout |
| 3 | after settle window | two complete fresh user-root/archive absence/consistency passes |
| 4 | disable/pause scheduler delivery; revoke invocation of `evaluateDispositionTriggers`; undeploy every old pre-cross-fence revision/service; prove zero old instances and zero active executions; `TschedulerZero` = proved end of final old execution | through `TschedulerZero + 60,000 ms` |
| 4' | termination unprovable: after proved delivery revocation and zero old instances | full 270-second handler timeout plus 60,000 ms |
| 5 | acquire server-only `legacyOversizeMigrationV1` cross-fence; write archives | only after both drains |
| 6 | while retaining lease: migrate/reconcile, pass every C9.2.9 data/rules condition | |
| 7 | deploy new cross-fenced `evaluateDispositionTriggers` handler | schedule disabled |
| 8 | release only the matching migration lease; prove its document absent | |
| 9 | B1 scheduler-state initialization/validation; restore scheduler invocation; enable schedule at frozen boundary | |
| 10 | keep `deleteAccount` revoked | until the joined operational partial order (manifest §13 Resolution map and execution gate) permits single final restoration |

- A merely disabled schedule is insufficient (queued delivery may exist).
- Deletion/scheduler attempt during maintenance receives platform-unavailable/refused; may retry afterward.
- Queued old event reaching new handler is subject to new ordinal + migration-cross-fence transaction.
- Failure to prove either drain blocks migration.
- `functions/index.js` changes separately for the permanent account-deletion fence.

#### C9.2.3 Migration lease (cross-fence)

```text
path: phase1System/dispositionTriggerState/migrationLeases/legacyOversizeMigrationV1
{schemaVersion:1,ownerToken,fencingGeneration,startedAt,renewedAt,expiresAt}
ownerToken:        generated lowercase UUID
fencingGeneration: positive safe integer
times:             Firestore timestamps ; startedAt <= renewedAt ; expiresAt == renewedAt + 300 seconds
scheduler lease path:   phase1System/dispositionTriggerLease
legacy scheduler lease: {runId,acquiredAt,expiresAt}
leaseNow = shared server readTime of the transaction (never process wall time)
```

| State | Event/condition | Next state | Writes |
|---|---|---|---|
| migration absent, scheduler absent | acquire | generation 1 | create migration lease |
| migration absent, scheduler = exact legacy `{runId,acquiredAt,expiresAt}` | acquire | generation 1 | delete scheduler lease + create migration lease (same transaction) |
| scheduler = any other nonabsent non-v2 shape | acquire | refuse | none (zero archive/scheduler/migration mutation) |
| scheduler = valid nonexpired v2 | acquire | refuse | none |
| scheduler = valid expired v2, `leaseNow < schedulerLease.expiresAt + 60,000 ms` | acquire | refuse | none |
| scheduler = valid expired v2, `leaseNow >= schedulerLease.expiresAt + 60,000 ms` | acquire | eligible | proceed per migration-lease row |
| migration present, `expiresAt <= leaseNow` | acquire | prior generation + 1 (exactly once) | replace; overflow blocks |
| migration present, live other owner | acquire | refuse | none |
| migration present, matching owner, no takeover won | renew (even after nominal expiry) | same generation | preserve `startedAt`, set `renewedAt=leaseNow`, CAS on exact update time; does not reread/reacquire the scheduler lease (every scheduler acquisition refuses while this document exists) |
| migration present, matching tuple | release | absent | delete under last update-time precondition; stale release after takeover fails harmlessly |
| process death | lease expires | next owner increments generation | resume solely from durable archive/source state |

| Rule | Exact statement |
|---|---|
| transactions | lease operations use public-v1 transactions; acquisition reads both the migration and scheduler lease documents |
| serialization | scheduler-first leaves live/draining scheduler lease and migration refuses; migration-first leaves present cross-fence and scheduler refuses |
| fencing token | every manifest create/transition, chunk create/delete, source/quarantine terminal commit, orphan mark, manifest delete includes in the same atomic commit/transaction a matching `(ownerToken,fencingGeneration)` renewal under its update-time precondition |
| exact-existing compare | renew-only commit before continuing, or no subsequent mutation |

#### C9.2.4 FirestoreDocumentArchiveV1 codec

```text
big-endian: u32, i64, raw IEEE-754 f64 bits ; u8 = one byte ; LP(x) = u32(byteLength(x)) || x
ASCII("PZFDA") || u8(1)
|| LP(UTF8(fullyQualifiedDocumentName))
|| Timestamp(createTime)
|| Timestamp(updateTime)
|| Map(fields)
Timestamp = i64(seconds) || u32(nanoseconds)
Map = u32(entryCount) || each LP(unsigned-UTF8-sorted key) || Value
00                         null
01                         false
02                         true
03 || i64                  integer
04 || f64                  finite double, including signed zero
05                         canonical NaN
06                         +infinity
07                         -infinity
08 || Timestamp            timestamp
09 || LP(UTF8)             string
0A || LP(raw bytes)        bytes
0B || LP(UTF8 full path)   reference
0C || f64 || f64           geopoint latitude/longitude
0D || u32(count) || Value* array
0E || Map                  map, including the raw map representation of Vector
invariant: encode(decode(bytes)) == bytes
archiveDigest = lowercase SHA-256(all encoded bytes)
archiveId = "qev2_" + first40(SHA-256(TaskCanonicalV1({
  domain:"event_archive.v1",source_path,
  source_update_time:{seconds,nanoseconds},archive_digest
})))
S = frozen Firestore document-storage bytes ; K = encoded map keys ; V = encoded value nodes
F = sum UTF8.byteLength(referenceValue) over raw reference nodes ; N = archive bytes
N <= S + 4K + 13V + F + 8,192
```

| Rule | Exact statement |
|---|---|
| NaN | all Firestore NaNs normalize to tag 05 |
| Unicode | no normalization |
| `ARCHIVE_CODEC_INVARIANT` | unknown protobuf oneof, malformed timestamp/path/UTF-8, impossible length, or decoder residue; systemic; blocks entire migration |
| restoration | reproduces all stored fields and exposes original metadata; does not claim Firestore reassigns historical create/update timestamps |
| accumulation | K, V, F, S, N independently accumulated with checked arithmetic; no K/V-vs-S inequality assumed; F never inferred from S |
| oracle | independent oracle separately traverses and recomputes F and N |
| no S-derived max | no legal-document maximum derived from S |
| not OriginalEventBytesV1 | `OriginalEventBytesV1` (C9.1.21) remains runtime quarantine identity and is not the archive format; the archive preserves the complete legal stored document incl. int64 precision, nonfinite values, unknown outer fields, scheduler-owned retry fields |

#### C9.2.5 Paths, chunks, and manifest

```text
manifest: users/{uid}/eventArchive/{archiveId}
chunk:    users/{uid}/eventArchive/{archiveId}/eventArchiveChunks/{NN}     NN = two-digit decimal 00...48
CHUNK_PAYLOAD_MAX = 393,216 ; MAX_CHUNKS = 49 ; MAX_ARCHIVE_BYTES = 19,267,584
gate (before any manifest/chunk/source/quarantine mutation): 1 <= ceil(N / CHUNK_PAYLOAD_MAX) <= 49 ; chunkCount = that quotient
chunk:    {schemaVersion:1,archiveId,index,offset,length,payload:Bytes,payloadDigest}
          index numeric ; offset/range = mathematical slice boundaries ; nonfinal length = 393,216 ; final length = 1...393,216 ; payloadDigest hashes payload only
manifest: {schemaVersion:1,archiveId,codec:"FirestoreDocumentArchiveV1",
           sourcePath,sourceCreateTime,sourceUpdateTime,
           chunkPayloadMax:393216,chunkCount,totalBytes,archiveDigest,
           state,createdAt,
           sealedAt?,terminalizedAt?,orphanedAt?,orphanReason?}
orphanReason: "SOURCE_CHANGED|SOURCE_DELETED"
```

| state | sealedAt | terminalizedAt | orphanedAt | orphanReason |
|---|---|---|---|---|
| building | absent | absent | absent | absent |
| sealed | required | absent | absent | absent |
| terminalized | required | required | absent | absent |
| orphaned | absent | absent | required | required |

| Rule | Exact statement |
|---|---|
| `ARCHIVE_CHUNK_CAP_EXCEEDED` | `N > MAX_ARCHIVE_BYTES`, zero, unsafe arithmetic, unrepresentable quotient; fixed systemic; emit only code + source-path digest + measured N; no archive/source/quarantine mutation; release only matching lease if apply acquired it; blocks pre-ship migration/rollout; not a per-source skip/quarantine |
| audit gate | read-only audit evaluates the same gate for every enumerated source before apply is authorized |
| proceeding | requires separately reviewed addressing/cap amendment or proof every enumerated source fits; corpus accident never a general maximum |
| chunk semantics | no timestamps; create-only; one physical commit each; existing requires complete byte equality; no normal code updates a chunk |
| index exemption | only `eventArchiveChunks.payload` exempt from single-field indexing; generic `chunks` untouched |
| identity | manifest identity and `createdAt` never change |
| times | one `leaseNow` per fenced mutation; `createdAt=leaseNow` (create), `sealedAt=leaseNow` (seal), `orphanedAt=leaseNow` (orphan), `terminalizedAt=leaseNow` (terminal); chunks have no time member |
| replay | exact replay preserves every committed time; retry may obtain new `leaseNow` only until one attempt commits; lost response resumes from committed document and never rewrites its time |

#### C9.2.6 State machine and terminal CAS

| State | Event/condition | Next state | Writes |
|---|---|---|---|
| (pre-write) | raw-read source; capture create/update time; encode; derive identity/chunks; compute all budgets | absent-manifest classification | none |
| absent manifest | matching source version | building | renew fence + create manifest (transaction) |
| existing manifest, exact state | resume | same | none / renew-only |
| existing manifest, identity mismatch | — | `ARCHIVE_ID_COLLISION` | none |
| building | chunks ascending: create or exact-compare; reread all ascending, verify path/schema/range/per-chunk digest/reassembly/length/full digest | building (chunks complete) | per chunk: create + fence renewal (one commit each) |
| building | seal | sealed | renew fence + exact `building→sealed` (transaction) |
| sealed / terminalized | seal attempted | same | none (replay) |
| sealed, source pending, raw `updateTime == sourceUpdateTime`, quarantine absent, lease tuple matches | terminal commit | terminalized | exactly four writes (below) |
| terminalized + matching source stub/quarantine | terminal attempted | same | none (replay) |
| sealed, quarantine preexisting | terminal attempted | collision | none |
| any | commit conflict | fresh lease/source classification | none |

```text
terminal commit: one public-v1 Commit (not Admin transaction, not auto-retried closure)
pre-reads: transactional raw-read lease -> leaseNow, lease update time ; raw-read source, sealed manifest,
           phase1System/dispositionTriggerState/quarantinedEvents/{archiveId}
terminalizedAt = leaseNow
write 1: renew lease                   currentDocument.updateTime = <captured lease update time>
write 2: replace source with stub      currentDocument.updateTime = sourceUpdateTime
write 3: create quarantine             currentDocument.exists = false
write 4: replace manifest terminalized currentDocument.updateTime = sealedManifestUpdateTime
same terminalizedAt = manifest terminalizedAt = source processedAt = quarantine quarantinedAt
stub:
{processingState:"terminal",processed:true,processedAt:terminalizedAt,
 outcome:"quarantined",
 processingError:"Stored event exceeded the Phase 2 event-processing size limit.",
 archiveRef:{schemaVersion:1,archiveId,codec:"FirestoreDocumentArchiveV1",
             chunkCount,totalBytes,archiveDigest}}
quarantine (schema v2):
{schemaVersion:2,sourcePath,archiveDigest,
 reason:{code:"SOURCE_TOO_LARGE",
         message:"Stored event exceeded the Phase 2 event-processing size limit."},
 migrationKind:"LEGACY_OVERSIZE_ARCHIVE",sourceUpdateTime,
 archiveRef:{schemaVersion:1,archiveId,codec:"FirestoreDocumentArchiveV1",
             chunkCount,totalBytes,archiveDigest},
 quarantinedAt:terminalizedAt}
```

| Rule | Exact statement |
|---|---|
| full-document CAS | covers `phase0ValidationFailure` and every unknown outer member |
| atomicity | all four writes succeed or fail atomically; client does not retry the same commit blindly |
| pre-terminal quarantine | existing pre-terminalization quarantine is a collision even if superficially equal |

#### C9.2.7 Mechanical budgets

```text
every physical commit: FirestoreWriteBudgetV1 + post-manifest normalized index registry
ChunkCommitBudget(i)  <= 524,288
ChunkDeleteBudget(i)  <= 524,288
ManifestCommitBudget  <= 65,536
LeaseFenceWriteBudget <= 4,096
TaskCanonicalV1(stub) <= 16,384
TaskCanonicalV1(quarantine) <= 16,384
FirestoreWriteBudgetV1(absent -> stub) <= 32,768
FirestoreWriteBudgetV1(absent -> quarantine) <= 32,768
LegacyOversizeTerminalBudgetV1
 <= 8,388,608 + 32,768 + 32,768 + 65,536 + 4,096
 <= 8,523,776
Firestore request limit 10,485,760 ; headroom 1,961,984
production-connected transactions retain 8,388,608
```

| Rule | Exact statement |
|---|---|
| terminal charge | old-source removed index entries + prospective stub + new quarantine + terminalized manifest |
| lease renewal | chunk/manifest caps include paired renewal; terminal sum spells it separately |
| authorization | terminal cap only for this offline Admin migration and only for exact lease/source/quarantine/manifest shapes |
| abort | `8,523,777`, a fifth write, shape/cap/index violation, or unsafe arithmetic aborts before write |
| oracle domain | raw v1 Values (int64 extrema, nonfinite doubles); never the production semantic canonicalizer |

#### C9.2.8 Idempotence and orphan cleanup

| State | Event/condition | Next state | Writes |
|---|---|---|---|
| absent manifest | matching source version | building | create |
| building | resume | chunks/seal | chunk creates, seal |
| sealed | same pending update time | atomic terminal commit | four writes |
| terminalized | exact stub/quarantine | no-op | none |
| any | changed pending update time | new archive; old = orphan candidate | new archive writes |
| any unreferenced | absent source | orphan candidate | none |
| any | another terminal outcome/ref | owner conflict | none |
| any | source ref with missing/bad archive | `ARCHIVE_BROKEN` | none |
| sealed | any preexisting quarantine | collision | none |
| any | other ID/content mismatch | collision | none |
| orphan candidate | transaction rereads source/quarantine: neither references ID AND source lacks captured update time | orphaned | renew lease + mark `orphaned` |
| orphaned | cleanup | chunks deleted descending | one lease-renewal+chunk-delete commit each |
| orphaned, chunks gone | cleanup | manifest deleted | delete manifest with same fence |
| orphaned | missing suffix chunks | continue | valid cleanup progress |
| orphaned | mismatching extant chunk | fail closed | none |
| orphaned | crash/takeover | resume cleanup | |

| Rule | Exact statement |
|---|---|
| protection | referenced or terminalized archive is never cleaned |
| retention | indefinite until account deletion or separately authorized policy |
| rules | deny all client access to `/users/{uid}/eventArchive/{document=**}`, migration-lease path, all quarantine shapes |
| deletion | existing recursive user deletion removes archives/chunks; mutual exclusion via C9.2.2 drain; `functions/index.js` changes independently for the permanent account-deletion fence |

#### C9.2.9 Pre-ship gate

- Zero pending in-scope source failing the complete retry-or-terminal admission envelope or the exact archive-chunk gate
- Zero unresolved out-of-scope source
- Zero building/sealed/orphaned manifest
- Zero broken archive
- Every terminalized manifest paired with one exact source stub/quarantine and exact chunk reassembly/digest
- Every preexisting `quarantinedEvents` row complete-schema-valid with an exact parsable `sourcePath`
- account-deletion UID-range query/index oracle passes over the complete quarantine population
- Exact normalized rules/index bytes and refrozen SHA
- Two consecutive complete passes with zero failing sources, zero out-of-scope sources, and the same total pending-source count (C9.2.1)

| Rule | Exact statement |
|---|---|
| ordering | before runtime deploy, while matching migration lease held, every preceding data/rules condition passes; after deploy, release matching lease and prove document absent before scheduler re-enable |
| failure | blocks scheduler re-enable or restoration of `deleteAccount` |

#### C9.2.10 Exact index/rules delta

```text
base:   the literal below ; 4,432 UTF-8 bytes with one trailing LF ; SHA-256 a7a432ec8e0511176b890432c5e4cb4a07e59a6dba0c9d920948cc446f3a7bbb
append (preserve every existing entry and order):
indexes[3] = {
  "collectionGroup": "schedulerRefusals",
  "queryScope": "COLLECTION_GROUP",
  "fields": [
    {"fieldPath":"lane","order":"ASCENDING"},
    {"fieldPath":"nextEligibleOrdinal","order":"ASCENDING"},
    {"fieldPath":"firstRefusedOrdinal","order":"ASCENDING"},
    {"fieldPath":"lastAttemptOrdinal","order":"ASCENDING"}
  ]
}
fieldOverrides[28] = {"collectionGroup":"eventArchiveChunks","fieldPath":"payload","indexes":[]}
fieldOverrides[29] = {"collectionGroup":"tasks","fieldPath":"foreignRoots","indexes":[]}
fieldOverrides[30] = {"collectionGroup":"tasks","fieldPath":"evidence_reservation","indexes":[]}
fieldOverrides[31] = {"collectionGroup":"workflowSubmissions","fieldPath":"userId","indexes":[{"order":"ASCENDING","queryScope":"COLLECTION"}]}
fieldOverrides[32] = {"collectionGroup":"workflowSubmissions","fieldPath":"owner","indexes":[{"order":"ASCENDING","queryScope":"COLLECTION"}]}
fieldOverrides[33] = {"collectionGroup":"legacyResetMigrations","fieldPath":"*","indexes":[]}
fieldOverrides[34] = {"collectionGroup":"outboundLeases","fieldPath":"*","indexes":[]}
serialization: JSON.stringify(value,null,2) + "\n"
result: 4 indexes ; 35 fieldOverrides ; 5,872 UTF-8 bytes ; one trailing LF ; SHA-256 a6de8daf701a75ff3db025ca244dbf2218432c5c1a06b0992cd88358250d88e8
```

Frozen index base (byte-exact; the 4,432-byte file is this block plus one trailing LF):

```json
{
  "indexes": [
    {
      "collectionGroup": "tasks",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        {
          "fieldPath": "status",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "dispositionContract.next_trigger.kind",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "dispositionContract.next_trigger.fired",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "dispositionContract.next_trigger.at",
          "order": "ASCENDING"
        }
      ]
    },
    {
      "collectionGroup": "tasks",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        {
          "fieldPath": "status",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "dispositionContract.next_trigger.kind",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "dispositionContract.next_trigger.fired",
          "order": "ASCENDING"
        }
      ]
    },
    {
      "collectionGroup": "tasks",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        {
          "fieldPath": "thresholdProjection.state",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "thresholdProjection.threshold_at",
          "order": "ASCENDING"
        }
      ]
    }
  ],
  "fieldOverrides": [
    {
      "collectionGroup": "events",
      "fieldPath": "processingState",
      "indexes": [
        {
          "order": "ASCENDING",
          "queryScope": "COLLECTION_GROUP"
        }
      ]
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "activeHandoff",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "conditions",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "dispositionContract",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "flowAnswerIdentities",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "flowAnswers",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "flowPath",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "flowRows",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "interactionHistory",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "notes",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "planChangeCycle",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "planChangeHistory",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "planChangeLink",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "quotes",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "resolution",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "taskInteraction",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "taskInteractionState",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "thresholdProjection",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "wakeEvidence",
      "indexes": []
    },
    {
      "collectionGroup": "taskPlanOperations",
      "fieldPath": "*",
      "indexes": []
    },
    {
      "collectionGroup": "taskPlanOperations",
      "fieldPath": "kind",
      "indexes": [
        {
          "order": "ASCENDING",
          "queryScope": "COLLECTION"
        }
      ]
    },
    {
      "collectionGroup": "notificationIntents",
      "fieldPath": "*",
      "indexes": []
    },
    {
      "collectionGroup": "packingPlan",
      "fieldPath": "*",
      "indexes": []
    },
    {
      "collectionGroup": "readiness",
      "fieldPath": "*",
      "indexes": []
    },
    {
      "collectionGroup": "spawnTokens",
      "fieldPath": "*",
      "indexes": []
    },
    {
      "collectionGroup": "taskDeadlineEvidence",
      "fieldPath": "*",
      "indexes": []
    },
    {
      "collectionGroup": "workflowResponses",
      "fieldPath": "*",
      "indexes": []
    },
    {
      "collectionGroup": "workflowSubmissions",
      "fieldPath": "*",
      "indexes": []
    }
  ]
}
```

| Rule | Exact statement |
|---|---|
| tie break | Firestore document-name order remains the composite's implicit final tie break |
| no wildcard | no scheduler-refusal wildcard exemption added |
| workflow overrides | sole re-enabled fields from that group's existing wildcard exemption; exist only for account-deletion UID-range queries |
| wildcard exemptions | migration and outbound-lease wildcards prevent accidental indexing of server-only authority |
| derivation | production and oracle require frozen base tuple, apply eight appends in memory, require exact result tuple; every write-budget index delta refrozen against final registry; different base/output stops, never rebases |
| phase2System | `phase2System/accountDeletionStorageReconcilerV1`, `phase2System/accountDeletionAuthReconcilerV1`, `phase2System/accountDeletionLegacyMigrationV1`, `accountDeletionStorageWork/{workId}`, `accountDeletionAuthWork/{workId}`, `accountDeletionLegacyCandidates/{candidateId}` queried only by document ID; frozen base index tuple byte-identical |
| registry change | any registry/order/scope change forces new derivation; update production/oracle together |

| Rules deny (owner/other/anonymous get/list/create/update/delete) | Path |
|---|---|
| condition slots | every Phase-2b condition slot |
| archive | `/users/{uid}/eventArchive/{document=**}` (recursive) |
| scheduler refusals | every `schedulerRefusals` document |
| reset migrations | `/users/{uid}/legacyResetMigrations/{document=**}` (recursive) |
| outbound leases | `/users/{uid}/outboundLeases/{document=**}` (recursive) |
| reset records | canonical reset records/tombstones, attempted alias paths, fake old-location `LEGACY_RESET_MIGRATION` in `taskPlanOperations` |

| Rule | Exact statement |
|---|---|
| taskPlanOperations | `taskPlanOperations.kind` remains sole child re-enable; no migration authority |
| fcmTokens | `users/{uid}/fcmTokens/{token}` create/update only for matching auth, root-marker absence, exact token path grammar, replace-not-merge map with exactly `createdAt == request.time` and `platform == "ios"`; delete matching owner only; client read/list denied (Phase 2 change from the current owner-readable baseline); Admin cleanup revalidates root; missing/surplus/wrong-type/server-sentinel/path/cross-UID maps deny within one-root-access budget |
| budgets | account-deletion owner root mutation forbidden; every descendant + userKnowledge write requires marker absence; task access-call budgets 2/write and 16/20 for eight; every other single write within 10 after one root access |
| storage | creates/updates retain owner requirement; Phase 2 adds existing-root/no-marker predicates; not claimed as baseline |

#### C9.2.x Named falsifiers

| Test file | Named test / fixture family |
|---|---|
| migrateOversizeEvents fixtures (file not named) | import has no effect; default audit read-only; each executable arming predicate fails closed; only complete literal arming set reaches write seam |
| migrateOversizeEvents fixtures (file not named) | last deletion BatchWrite and last scheduler Commit at timeout-minus-epsilon; settle 60 seconds later; no archive write before both settle/confirmation gates |
| migrateOversizeEvents fixtures (file not named) | both scheduler/migration acquisition serialization orders; exact legacy scheduler-lease migration; malformed non-v2 refusal; queued delivery after schedule pause; scheduler Commit at expiry-minus-epsilon settling at plus 60 seconds; expired-plus-59,999 ms refusal vs plus-60,000 ms admission; malformed v2 scheduler/migration cross-fence fail-closed with zero mutation |
| codec fixtures (file not named) | >=1,000 repeated shortest-current-database reference values: former no-`F` inequality fails, `N <= S + 4K + 13V + F + 8,192` passes, exact round-trip and digest pass; exact-bound; arithmetic-overflow |
| chunk-cap fixtures (file not named) | `N == MAX_ARCHIVE_BYTES`; `N == MAX_ARCHIVE_BYTES + 1`; reference-heavy |
| timed-transition fixtures (file not named) | retry-before-commit and lost-response equality for every timed transition |
| mandatory migration fixtures (file not named) | every raw Value oneof; int64 extrema; big-endian vectors `1.0`=`3ff0000000000000`, `-0.0`=`8000000000000000`, least positive subnormal=`0000000000000001`, one geopoint pair; NaN forms; infinities; timestamp extrema; empty/max bytes/string; NUL/control Unicode; unusual valid field names; references; geopoints; nested arrays/maps/vector; encode/decode/re-encode; absent payload; 200-byte payload + maximum unknown outer field; nonfinite unknown outer value |
| mandatory migration fixtures (file not named) | exact query via pinned `StructuredQuery.fromObject` to injected `FirestoreClient.runQuery` spy observing `limit.value == 100`; rejection of absent/unwrapped/out-of-range wrappers; enumeration at 0/1/100/101 documents counting documents only; ordinary document+readTime; final document+readTime+`done:true`; midstream and final readTime-only progress; no-document `done:true` with absent and valid readTime; normal EOF with/without documents; empty EOF requiring prior progress readTime; bindings exposing defaults without presence; surfaced unknown own-property rejection; separately encoded unknown wire tag discarded without changing known fields; present `done:false`; empty response; missing/invalid required readTime; duplicate, nonascending, mixed/unknown, nonzero skipped-results, explain-metrics, transaction, post-terminal, stream-error responses; same-leaf `events` document at wrong ancestry |
| mandatory migration fixtures (file not named) | source deletion/change between query and getDocument; insertion caught by uncursored confirmation pass; stable two-pass pending count; chunk lengths at `P-1/P/P+1/2P` and maximum; every crash boundary; absent/live/expired lease; readTime clock; renewal; generation overflow; process death; two workers with takeover before every mutation and stale commit/release rejection; update-time-only retry-map change; unknown-field change; deletion; matching/mismatching terminal source; every collision/missing chunk; new-version orphan and cleanup crash/takeover; referenced archive protection; exact budget boundaries; generic `chunks` index unaffected; rules/account deletion; H57 without raw data |
| deletion fixtures (file not named) | nested recursive deletion after migration; attempted deletion at every archive/terminal boundary while invocation disabled |
| `functions/tests/dispositionTriggers.test.js` | two-pass audit exit code: a failing first pass is one pass, unstable, nonzero; a clean two-pass audit exits zero; an insertion between passes exits nonzero (S3-CD6) |

### C9.3 Notification intents, route inbox, and claimTaskIntent

#### C9.3.1 Notification intent document

```text
users/{uid}/notificationIntents/{intentId} {
  schema_version:1, audience:"user", kind:"task_resume",
  state:pending|consumed|cancelled,
  task_document_id, task_instance_id, interaction_epoch, interaction_revision,
  policy_fingerprint, route:{kind:row|outcome,session_id?},
  cause:{wake_evidence_id}, created_at, expires_at,
  consumed_at?, claim_operation_id?
}
```

```text
intent_id = "ni1_" + first40(SHA-256(canonical {uid,task_document_id,task_instance_id,interaction_epoch,policy_fingerprint,route,cause:{wake_evidence_id:wake_id}}))
wake_id   = "w1_"  + first40(SHA-256(canonical {uid,task_document_id,task_instance_id,interaction_epoch,policy_fingerprint,cause}))
wakeEvidence = {schema_version:1,task_instance_id,wake_id,cause,fired_at,resume_destination,urgency:"normal"|"urgent_recovery",urgency_basis?,intent_id}
wakeEvidence.cause = {kind:"TRIGGER",original_trigger,event_high_water?} | {kind:"THRESHOLD",threshold_id,deadline_evidence_id,threshold_at,consequence_class?,displaced_trigger?}
```

| Rule | Exact statement |
|---|---|
| Cause form | `intent.cause` is exactly `{wake_evidence_id:wakeEvidence.wake_id}`; never operation-based |
| Pointer equality | `wakeEvidence.intent_id` equals the intent document ID |
| Pair atomicity | Create, exact retry, fresh-command cancellation, claim consumption, reset cancellation preserve or remove the pair atomically |
| Pointer validation | Validators reject a missing, dangling, crossed-task, crossed-instance, or unequal pointer |
| Producer | No other intent producer is named in this phase; scheduler wake transaction is the producer |
| Expiry | Intent expiry is exactly 24 hours from server creation |
| One intent per wake | Every newly created valid-policy wake atomically creates its one intent; in-place normal→urgent upgrade retains the pointer and creates no second intent |
| Identity stability | Transaction retry produces the same IDs; reset/regeneration cannot collide even when every other byte recurs |
| Fresh command | A fresh successful command cancels obsolete pending intents and clears wake pointers; failed trigger replacement preserves both |
| Copied identity | The intent copies task instance/epoch/revision/fingerprint after the wake |

#### C9.3.2 claimTaskIntent wire

```text
request  = {action:"claimTaskIntent",intentId,claimOperationId}
response = {schemaVersion:1,kind:"task_route",claimOperationId,replayed,
            accountUid,intentId,taskDocumentId,taskInstanceId,taskGenerationEpoch,
            interactionEpoch,policyFingerprint,
            route:{kind:"row"|"outcome",sessionId?},expiresAt}
expiresAt = exact UTC "YYYY-MM-DDTHH:mm:ss.SSSZ" projection of intent expires_at (CallableTimestampWireV1; literal uppercase Z; exactly three fractional digits)
server read path = users/{auth.uid}/notificationIntents/{intentId}
```

| Rule | Exact statement |
|---|---|
| Envelope | Non-task-envelope exception; accepts exactly the three members; no action may combine members from two bases |
| Read scope | Callable reads only the exact authenticated path; no collection-group/global lookup; opaque route exposes no account identifier |
| Absent document | Returns `permission-denied/AUTH_FORBIDDEN` with zero operation or intent write; nondisclosing |
| Expiry wire | Never a Firestore Timestamp/map, offset form, seconds-only string, or additional precision |
| Route `sessionId` | `row` forbids `sessionId`; `outcome` requires it exactly for a returned handoff and forbids it for a direct waiting transition |
| Claim validation | Rejects if instance/epoch/fingerprint, optional returned session, wake cause, state, expiry, or — once C9.3.11 defines its referent — PC linkage no longer matches; until then the C9.3.11 interim claim rule applies; never downgrades an invalid outcome route |
| Scheduler revision | Scheduler-only revision is diagnostic; claim validates live instance/epoch/fingerprint/wake cause/state/session, so escalation does not stale a pending or claimed route |
| Stale normalization | All stale task/session/cause cases normalize to `INTENT_STALE` |

#### C9.3.3 INTENT_CLAIM operation record

```text
users/{uid}/taskPlanOperations/{recordId} (recordId == operation_id) = {
  schema_version:1, kind:"INTENT_CLAIM", state:"COMMITTED",
  account_uid, operation_id, action:"claimTaskIntent",
  request_fingerprint:"op1_"+request_sha256, request_sha256,
  task_identities:[], prior_snapshots:[],
  response, response_sha256, created_at, committed_at
}
```

| Rule | Exact statement |
|---|---|
| Kind | `INTENT_CLAIM` is required exactly for `claimTaskIntent` |
| Empty arrays | `task_identities` is empty only for INTENT_CLAIM; `prior_snapshots` is empty for claim |
| Response | Closed typed `task_route` with `replayed:false`, capped at 65,536 canonical bytes; `response_sha256` hashes that exact map |
| Replay | Returns stored response with only transport projection `replayed:true`; never rewrites the record |
| Times | `created_at == committed_at == server_write_time` |
| Size | Ordinary record at most 589,824 canonical bytes |
| Request hash | request_sha256 = SHA-256(strict request canonical bytes of the complete accepted {action:"claimTaskIntent",intentId,claimOperationId}); claimOperationId included, authenticated transport context omitted |
| Record reuse | Cross-kind reuse of claimOperationId, hash mismatch, missing/surplus members, altered response, or malformed timestamp fails with zero intent mutation; claimOperationId in the reserved rsa1_/rso1_/pcs1_ namespaces rejects |

#### C9.3.4 Command × prior state × result

| Command | Admissible prior | Result and cleanup |
|---|---|---|
| `claimTaskIntent` | pending, unexpired, intended UID, live epoch/session/cause | Intent `pending→consumed`, typed route returned; task unchanged; same claim op replays, another claimant fails |

#### C9.3.5 Claim error codes and client handling

| Reason (Firebase code) | `details` | Client action |
|---|---|---|
| `AUTH_FORBIDDEN` (`permission-denied`) | `{schemaVersion:1,reason}` | Return dispatched record to RECEIVED; copy `dispatchAccountUid/dispatchAuthEpochUUID` into `lastForbiddenAccountUid/lastForbiddenAuthEpochUUID`; clear dispatch/refresh fields; skip only that namespace; continue; namespace current at response arrival is irrelevant; a different current namespace may retry |
| `AUTH_REQUIRED` | `{schemaVersion:1,reason}` | CAS back to RECEIVED; redispatch under newer namespace/revision if present, else add `refreshNamespace`+`refreshLease` and invoke forced refresh |
| `INTENT_NOT_FOUND` | `{schemaVersion:1,reason}` | Not emitted by v1 claim; receiving it is a protocol-version violation handled like `AUTH_FORBIDDEN` |
| `INTENT_EXPIRED`, `INTENT_CANCELLED`, `INTENT_STALE`, `INTENT_ALREADY_CLAIMED`, `INTENT_INVALID`, `REQUEST_INVALID` | `{schemaVersion:1,reason}` | Conclusive; remove record with diagnostic; queue continues; local request validation prevents REQUEST_INVALID dispatch |
| `OPERATION_REUSED` | `{schemaVersion:1,reason}` | New lowercase UUID; return to RECEIVED with only `claimOperationId` replaced; collision diagnostic; retry |
| `unavailable`, `deadline-exceeded`, `internal`, `unknown`, transport loss, decode failure | n/a | Retain CLAIM_DISPATCHED; retry identical operation/bytes |
| `TASK_NOT_FOUND`, `RESET_ACTIVE`, `POLICY_INVALID`, `POLICY_MISMATCH`, `PLAN_GRAPH_CHANGED`, `STALE_STATE`, `TRIGGER_INVALID`, `EVIDENCE_UNKNOWN`, `COMMAND_NOT_ALLOWED`, `HANDOFF_MISMATCH`, `AUTH_EPOCH_MISMATCH`, `WORKFLOW_BINDING_INVALID` | n/a | Unreachable for claim; protocol-version violation; retain-but-skip for this build; diagnostic; no retry storm |

#### C9.3.6 Route inbox durable file

```text
file    = PeezyTaskRouteInbox-v1.json      (Application Support; protection completeUntilFirstUserAuthentication)
quarantine sibling = PeezyTaskRouteInbox-v1.quarantine-v1.json
DurableFileEnvelopeV1 = {schemaVersion:1,fileKind:"TASK_ROUTE_INBOX_V1",generationId,payload:{records:[AppRouteInbox record]},sha256}
sha256 = 64 lowercase hex over canonical UTF-8 {fileKind,generationId,payload,schemaVersion:1}
generationId = fresh lowercase RFC 4122 UUID per committed replacement; envelope bytes = canonical JSON, no trailing newline
```

| Rule | Exact statement |
|---|---|
| Owner | `AppRouteInbox` is one process-wide Swift `actor`; sole reader/modify/replacer; owns the complete route envelope; URL/push/auth/scene/presentation/acknowledgement/overflow/purge events call actor-isolated methods; one mutation at a time with atomic whole-value replacement, so concurrent ingress cannot lose a record |
| Startup accept | Only exact outer/member sets, fileKind TASK_ROUTE_INBOX_V1, canonical bytes, valid generation UUID, valid payload, and recomputed sha256 load; any other target is corrupt |
| Write protocol | Temp file in same directory, POSIX write loop, `fsync` file, atomic `rename`, `fsync` directory |
| Corrupt target | Never reset empty; rename to quarantine sibling, directory `fsync`, actor enters `CORRUPT_BLOCKED`; existing quarantine leaves both files and stays blocked |
| Capacity | Payload ordered by `receivedAtEpochMilliseconds`, capped at eight records |

#### C9.3.7 AppRouteInbox records and PersistedTaskRouteV1

```text
RECEIVED        = {intentId,claimOperationId,receivedAtEpochMilliseconds,expiresAtEpochMilliseconds,phase:"RECEIVED",
                   lastForbiddenAccountUid?,lastForbiddenAuthEpochUUID?,
                   refreshLease?:{attempt_id,started_at,expires_at},
                   refreshNamespace?:{accountUid,authEpochUUID,credentialRevision}}
CLAIM_DISPATCHED= {intentId,claimOperationId,receivedAtEpochMilliseconds,expiresAtEpochMilliseconds,phase:"CLAIM_DISPATCHED",
                   dispatchAccountUid,dispatchAuthEpochUUID,dispatchCredentialRevision,dispatchedAtEpochMilliseconds}
CLAIMED         = {intentId,claimOperationId,receivedAtEpochMilliseconds,expiresAtEpochMilliseconds,phase:"CLAIMED",
                   claimedAccountUid,claimedAuthEpochUUID,claimedRoute:PersistedTaskRouteV1}
PRESENTING      = {intentId,claimOperationId,receivedAtEpochMilliseconds,expiresAtEpochMilliseconds,phase:"PRESENTING",
                   claimedAccountUid,claimedAuthEpochUUID,claimedRoute:PersistedTaskRouteV1,presentationStartedAtEpochMilliseconds}
PersistedTaskRouteV1 = {schemaVersion:1,kind:"task_route",claimOperationId,replayed,
                        accountUid,intentId,taskDocumentId,taskInstanceId,taskGenerationEpoch,
                        interactionEpoch,policyFingerprint,
                        route:{kind:"row"|"outcome",sessionId?},expiresAtEpochMilliseconds}
```

| Rule | Exact statement |
|---|---|
| RECEIVED members | Forbids dispatch/claimed/route/presentation fields; last-forbidden pair both present or both absent; `refreshLease`/`refreshNamespace` both present or both absent and independent of last-forbidden |
| CLAIM_DISPATCHED members | Forbids last-forbidden, claimed, presentation, and refresh members |
| CLAIMED members | Requires account UID, claim-time auth epoch, `PersistedTaskRouteV1`; forbids dispatch/presentation/last-forbidden/refresh |
| PRESENTING members | Requires all four claimed/presentation values; same forbiddances as CLAIMED |
| Route derivation | `claimedRoute` derived from validated wire `task_route` with only `expiresAt` replaced by `expiresAtEpochMilliseconds` |
| Expiry storage | Never a date string or floating-point `Date`; all ordering/expiry/minimum/boundary comparisons use safe epoch-millisecond integers |
| Wire parse | Swift validates exact grammar and Gregorian value, parses once to safe epoch-millisecond integer, round-trips to the identical wire string before constructing `PersistedTaskRouteV1` |

#### C9.3.8 Ingress, URL grammar, TTL, capacity

| Rule | Exact statement |
|---|---|
| Push key | Notification payload key is exactly `peezy_task_intent_id` |
| URL grammar | scheme `peezy`, host `task`, path `/v1`, one query pair `intentId` = RFC 3986 percent-encoding of the opaque ID |
| URL rejection | Fragment, userinfo, alternate host/path, duplicate, or unknown keys fail |
| Local TTL | `expiresAtEpochMilliseconds = receivedAtEpochMilliseconds + 86,400,000`; overflow rejects |
| Claim expiry | Successful claim replaces record expiry with the lesser of local value and strictly parsed server receipt expiry |
| Duplicate intent | Same intent reuses its first claim operation/receipt time |
| Ninth receipt | First remove expired records not in dispatch/presentation processing; if still full, evict only the oldest plain RECEIVED with no live lease plus diagnostic; if all eight protected, reject receipt plus diagnostic |
| Protected | RECEIVED with live lease, and every CLAIM_DISPATCHED, CLAIMED, PRESENTING record |
| Nonexistent ID | Globally nonexistent opaque ID is fail-closed and locally retained only until 24-hour TTL; never produces a route |

#### C9.3.9 Phase transitions and refresh lease

| Condition | Result/Write |
|---|---|
| Immediately before awaiting claim | Clear expired/superseded refresh pair; durably write CLAIM_DISPATCHED with current signed-in UID/auth epoch/credential revision and epoch-millisecond time |
| Relaunch or ambiguous transport | Retry exact claim operation/bytes |
| Success or exact claim replay | CLAIM_DISPATCHED → CLAIMED durably |
| Immediately before automatic UI presentation | Durably store PRESENTING |
| Crash in CLAIMED | Replays/presents automatically only in same UID+auth epoch |
| Crash in PRESENTING | Never auto-presents; exposes "Open task" only in that namespace |
| Initially unauthenticated RECEIVED | Pauses |
| `AUTH_REQUIRED` CAS precondition | Record still CLAIM_DISPATCHED with same intent, claim operation, dispatch UID, dispatch auth epoch, dispatch credential revision; atomically return to RECEIVED, clear every dispatch/forbidden field, preserve claimOperationId |
| Different durable valid UID/epoch or higher credential revision exists | Immediately requeue and dispatch under that namespace |
| Otherwise | Add `refreshNamespace:{accountUid,authEpochUUID,credentialRevision}` for captured dispatch tuple and `refreshLease:{attempt_id,started_at,expires_at}`; then invoke forced refresh |
| Lease values | `attempt_id` fresh lowercase RFC 4122 UUID; `started_at`,`expires_at` safe epoch-ms from one actor clock read; `expires_at == started_at + 60,000` |
| Lease live | Current durable auth equals its namespace/revision and `now < expires_at`; survives process death; forbids every second forced refresh |
| `now >= expires_at` or durable different UID/epoch or higher revision | CAS-clear lease/context; expiry may acquire fresh attempt; namespace/revision change immediately redispatches |
| Corrupt lease | Missing half, invalid UUID/time/relation, lower same-namespace revision, or lease on another phase dispatches nothing |
| Refresh completion | Mutates route only if intent/claim, RECEIVED phase, lease `attempt_id`, refresh namespace still match; success clears lease and queues dispatch; failure leaves live lease until expiry; late completion is no-op |
| `HandoffSessionStore` CAS | Only if signed auth equals captured UID/epoch/revision; success writes `credentialRevision = captured + 1`; mismatch/failure writes nothing |
| Crash after lease persist, before refresh invocation | No revision change; expiry permits a fresh attempt |
| Refresh API success, crash before credential increment persists | Auth remains captured tuple; live lease suppresses overlap until expiry |
| Credential increment persisted, crash before inbox cleanup | Relaunch/observer delivery of the higher revision clears the old lease and redispatches immediately |
| CLAIMED/PRESENTING namespace mismatch | Retained but blocked until expiry; never presented against another account or regenerated task |
| TasksStore loaded in matching namespace | Conclusively missing/stale instance removes record with diagnostic |
| Before automatic presentation and before any opener | Recheck current UID/auth epoch, receipt account/task instance, TasksStore namespace/identity/epoch/fingerprint, optional session, active handoff namespace |

#### C9.3.10 Presentation and acknowledgement

| Condition | Result/Write |
|---|---|
| Row route acknowledgement | Removed only when matching task row/detail `onAppear` acknowledges same account, task instance, task ID, epoch, fingerprint |
| Outcome route acknowledgement | Additionally matches the optional returned session |
| Sheet dismissal after acknowledgement | No inbox work |
| Manual "Open task" from PRESENTING | Reuses stored receipt in exact namespace; waits for same acknowledgement; never calls claim again |
| Malformed phase/receipt pair | Removed with local diagnostic; never presented or reclaimed |
| Returned-session outcome, exact installation/auth-epoch match | Presents the outcome |
| Same installation, rotated auth epoch | Presents handoff-reconciliation surface; `HandoffSessionStore` performs AUTH_EPOCH_CHANGED cancellation |
| Different installation | Presents "Continue on the other device" plus explicit "Restart here"; only the latter performs takeover cancel |
| Both mismatch branches | Retain claimed receipt until reconciliation surface appears, then acknowledge/remove; no handoff open ack, return, outcome resolution, or outcome question |
| Direct-WAIT outcome | No handoff namespace; ordinary outcome route |

#### C9.3.11 Scheduler wake contract (intent-producing branches)

| Rule | Exact statement |
|---|---|
| Live policy state | The live policy state a task carries (`taskInteractionState`), the deadline-evidence and handoff shapes the firing branches read, and the PC-linkage referent the intent's `row` route is validated against are defined by S6 in this section before any policy-present branch below is coded; the shapes are open until then |
| Interim (before S6) | S3's fail-closed interim: a policy-present row (any `taskInteractionState`) reaching an ordinary or threshold reducer settles past the cursor with zero writes (no task byte, no refusal record, no intent; run-local outcome `policyPresent`, no durable metric), proved by `functions/tests/dispositionTriggers.test.js` "C9.3.11 interim (S3-CD8): policy-present rows produce zero writes in every lane"; scheduler wakes for policy-bearing tasks do not fire until S6 lands; policy-absent rows keep the H55 behavior |
| Interim claim | `claimTaskIntent` requires the present `taskInteractionState` to carry the intent's `interaction_epoch` and `policy_fingerprint` (absent or partial state is `INTENT_STALE`); PC linkage is validated once C9.3 defines its referent (C9.3.2) |

| Condition | Result/Write |
|---|---|
| `Snoozed + DEFERRED` trigger fires | Move fired trigger to wake evidence; clear active trigger; `Upcoming`; one row intent |
| `InProgress + USER_ACTION_TRACKED` or `matching_in_progress + WAITING_ON_EXTERNAL` fires | Retain disposition; fired trigger to wake evidence/history; active trigger := `{schema_version:1,kind:"ATTENTION_NOW",wake_id}`; one row or outcome intent |
| Display-fallback USER_ACTION | Retains exact `waiting_fallback_state`; always row |
| Policy-absent Snoozed/DEFERRED (H55 reducer) | No policy state, epoch/revision, wake evidence, history, or intent |
| Firing transaction, armed/due `thresholdProjection` | `urgent_recovery` plus exact basis/class; projection attended |
| Firing transaction otherwise | `normal`, no basis; missing/malformed/stale evidence is never inferred as urgent |
| Threshold scan reread | Requires U/A/W/D, valid current policy/instance, exact armed projection, matching single-outcome deadline evidence and client-denied authority source version, threshold_at <= runNow; otherwise no-op (stale projection refreshed only by its owning reducer) |
| Threshold scan, existing coherent normal TRIGGER wake | Change to `urgent_recovery`; write basis; retain cause/intent; projection `attended`; revision+1; `URGENCY_ESCALATION` row; no intent recreate/consume/update |
| Threshold scan, existing coherent urgent wake | Exact retry marks identical projection attended and returns |
| Threshold scan, no wake, U | Remains Upcoming; routes `row`; one threshold-cause urgent wake plus one intent |
| Threshold scan, no wake, D | Clears active trigger; Upcoming; routes `row` |
| Threshold scan, no wake, A/W | Retain disposition; active unfired trigger → `cause.displaced_trigger`; ATTENTION_NOW; route by returned-handoff/WAIT/row precedence |
| Threshold commit | New wake/intent and `thresholdProjection.state:"attended"` commit atomically |
| Malformed/different-instance/incompatible existing wake | Fail-closed, not overwritten |
| Race, any serialization | One wake, one intent, one attended projection; `cause.kind` records winner; threshold-first: ordinary scan sees ATTENTION_NOW/no active trigger or Upcoming and no-ops; ordinary-first: threshold transaction upgrades the normal wake |
| `ATTENTION_NOW` | Server-written pointer only; client cannot submit; next fresh disposition requires new date/event trigger |

#### C9.3.12 Route selection precedence

| Order | Condition | Stored route |
|---|---|---|
| 1 | External H54 `planChangeState == "pending_confirmation"` with coherent PC cycle, replacement link, current ordinal/source, retained snapshot | `row` (opens only "Finish plan update"; never waiting outcome) |
| 2 | DEFERRED | `row` |
| 3 | USER_ACTION carrying `waiting_fallback_state` | `row` |
| 4 | USER_ACTION/WAITING with matching `activeHandoff.state == returned` | `outcome` + session ID |
| 5 | WAITING without returned handoff | `outcome` without session (opens the current transition's outcome surface) |
| 6 | Every other USER_ACTION | `row` |

#### C9.3.13 Rules

| Rule | Exact statement |
|---|---|
| Client access | Rules deny every client read/write of notification intents; `claimTaskIntent` is the only client path |
| Absent deliverables | No sender, FCM call, collection query from Swift, delivery state, production delivery claim |
| Reset counts | Reset `deleted_counts.notification_intents` covers intent deletion |

#### C9.3.14 TasksStore urgent-recovery projection

| Eligibility | Requirement |
|---|---|
| Policy | Mapped policy is valid |
| Urgency | `wakeEvidence.urgency == "urgent_recovery"` |
| Basis | `urgency_basis` resolves byte-for-byte to retained current deadline evidence, policy threshold, optional consequence class/rank, and attended threshold projection |
| Instance | Task instance matches |
| Live state | A/W with `ATTENTION_NOW` pointing at that wake, or Upcoming with the exact threshold/DEFER wake history |
| Malformed/stale evidence, class, or rank | Excluded, never downgraded |

| Comparison key | Value |
|---|---|
| Classified | `(0,consequence_rank,threshold_at,threshold_id,task_document_id)` |
| Unclassified | `(1,threshold_at,threshold_id,task_document_id)` |
| String ties | Unsigned UTF-8 order |
| Production registry | `{}`; every production line uses deadline order until one reviewed Phase 3 source+policy change activates classes; no catalog percentage/label invents a rank |

| Lines | Group rendering |
|---|---|
| Zero | Group hidden |
| One | Same group header |
| Many | One "Needs attention now" group, one line per task |
| Line content | Policy threshold label/protected outcome; current owner/action |
| Consumers | Home and Tasks consume one shared projection byte-identically |

| Rule | Exact statement |
|---|---|
| Per-line routing | Each line routes independently by the C9.3.12 PC/returned-WAIT/row precedence |
| Group write | No group-level dismiss, completion, claim, or write |
| Line mutation | Opening/acknowledging one line changes only that task/intent; the listener recomputes the group |

#### C9.3.x Named falsifiers

| Test file | Named test / fixture family |
|---|---|
| functions/tests/notificationIntents.test.js | instance-bound IDs; one intent per wake; stale cancel; replay/other claimant; route-expiry wire; leap-day/epoch boundary/offset/lowercase z/fractional-digit/invalid-calendar/overflow/min-selection/equal±1ms parity |
| functions/tests/taskPlan.test.js | claim follow-on (S3); claim after PC→CF/undo/reset; fallback row precedence; PC precedence from WAITING with/without returned handoff; exact recovery presentation after relaunch |
| functions/tests/dispositionTriggers.test.js | seven scan/index races; threshold first-observation/active-later/U-A-W-D/returned-handoff-and-direct-WAIT routes; ordinary-before-threshold and threshold-before-ordinary; equal-time races; normal→urgent before/after claim with pending/consumed/cancelled intent; displaced-trigger retention; exact IDs/replay; class drift; fresh disposition clearing/rearming |
| functions/rules-tests/firestoreRules.test.js | all-client intent denial (get/list/create/update/delete) |
| Peezy 4.0Tests/TaskRouteTests.swift | exact 60-second refresh lease; three crash boundaries; UTC-wire→epoch-ms parity/min/expiry matrix (leap-day/epoch boundary/offset/lowercase z/fractional-digit/invalid-calendar/overflow/min-selection/equal±1ms); A-dispatch→B-current AUTH_REQUIRED; same-UID refresh without observer callback; repeated AUTH_REQUIRED no overlap; A→B/B→A; late completion after replacement; file write/fsync/rename/quarantine boundaries; outer/payload/hash byte tamper; existing quarantine; zero dispatch while blocked; item recovery; explicit discard; exact expiry reacquisition; failure then expiry; every lease/member/CAS boundary; simultaneous ingress; queue-behind; acknowledgement; account switch/reset boundaries; URL/push/account/scene/reset cases |
| (not named) | overflow during live refresh/in-flight claim; lost response; crash after CLAIM_DISPATCHED; relaunch replay; returned-session claim from opening installation, second installation, same installation after rotation |
| `functions/tests/notificationIntents.test.js` | claim under the C9.3.11 interim: absent or partial `taskInteractionState` → `INTENT_STALE`; terminal task → `INTENT_STALE` (S3-CD8) |
| (not named) | TasksStore urgent-recovery projection: empty production registry; injected two-rank mixed classified/unclassified ordering; equal ranks/times/IDs; zero/one/many; Home/Tasks parity; PC precedence; U/A/W/D line routes; one-line mutation leaving siblings; stale evidence removal |

### C9.4 Historical account migration, purge and sealer CLIs, and the client legacy-reset migration

#### C9.4.1 Historical account migration: registry, checkpoint, candidates, Auth checks, confirmation passes

```text
Script:      functions/scripts/purgeLegacyDeletedAccounts.js   (import-safe pure core; CLI only under require.main === module)
Checkpoint:  phase2System/accountDeletionLegacyMigrationV1      (apply-only; audit never creates it; no `mode` member)
Candidates:  accountDeletionLegacyCandidates/{candidateId}
candidateId = "adlc1_" + first40(lowercase SHA-256(TaskCanonicalV1({account_uid:uid})))
source_registry_sha256 = lowercase SHA-256(TaskCanonicalV1({domain:"account_deletion_legacy_sources.v1",rows:<complete displayed row maps in order>}))
```

```text
Checkpoint (unknown-rejecting map, canonical bytes <= 8192):
{schema_version:1,kind:"ACCOUNT_DELETION_LEGACY_MIGRATION",generation_id,
 project_id:"peezy-1ecrdl",database_id:"(default)",
 bucket_name:"peezy-1ecrdl.firebasestorage.app",
 status:"discovering"|"reducing"|"waiting_guards"|"confirming",
 pass_ordinal,source_ordinal,source_cursor,pass_candidate_count,
 reduction_round,reduction_cursor_id,reduction_deferred_count,
 confirmation_zero_passes,
 authority_generation_id,authority_sha256,implementation_sha256,
 source_registry_sha256,package_lock_sha256,script_sha256,
 drain_evidence_sha256,auth_freeze_evidence_sha256,
 auth_blocker_config_sha256,auth_blocker_prior_config_sha256,
 created_at,updated_at}

source_cursor = {kind:"start"} | {kind:"firestore_raw",page_token} | {kind:"singleton",done:true} | {kind:"storage",page_token}
page_token: opaque valid UTF-8 String, 1...4096 bytes; terminal = next source's {kind:"start"} (never an empty token)
generation_id: lowercase UUID; every *_sha256: exactly 64 lowercase hex; ordinals/counts: safe nonnegative integers
reduction_cursor_id: "" | valid candidateId; confirmation_zero_passes: 0...2; created_at <= updated_at (concrete server times)
```

| Member | Constraint |
|---|---|
| `source_ordinal` while `discovering`/`confirming` | within the registry (0...22) |
| `source_ordinal` while `reducing`/`waiting_guards` | equals registry length (23) and `source_cursor = {kind:"start"}` |
| `source_cursor` | must match the current literal source row kind |
| checkpoint creation | copies every displayed identity/digest from accepted CLI, Build-B authority, current script/core/source-registry/package/lock/rules artifact, drain, and creation-barrier evidence |
| resume | revalidates complete equality before first read and before every mutation; drift = `ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT` with zero writes |

```text
Candidate (canonical bytes <= 2048; three disjoint complete maps):
common   {schema_version:1,kind:"ACCOUNT_DELETION_LEGACY_CANDIDATE",candidate_id,account_uid,first_pass_ordinal,created_at,updated_at}
pending  + {disposition:"pending",last_check_result:"unexamined"|"ambiguous",last_checked_at}   // unexamined => null; ambiguous => concrete server Timestamp
excluded + {disposition:"excluded_live",exclusion_reason:"AUTH_PRESENT"|"ROOT_PRESENT",last_checked_at:<concrete server Timestamp>}
adopted  + {disposition:"adopted",last_checked_at:<concrete server Timestamp>,operation_id,proof_sha256,marker_started_at}
Validation: identity/UID/digest, time order, deterministic path must agree; collision, malformed row, unsafe counter, or checkpoint drift blocks
Rules: deny all client reads/writes on accountDeletionLegacyCandidates
```

```text
ACCOUNT_DELETION_LEGACY_SOURCES_V1 (23 rows; displayed order = execution order)
 0 {id:"users_missing_roots",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents",collection_id:"users",show_missing:true,extract:"document_id"}
 1 {id:"user_knowledge",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents",collection_id:"userKnowledge",show_missing:false,extract:"document_id"}
 2 {id:"support_threads",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents",collection_id:"supportThreads",show_missing:false,extract:"document_id"}
 3 {id:"concierge_requests_user",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents",collection_id:"conciergeRequests",show_missing:false,extract:"optional_string_field:userId"}
 4 {id:"task_flow_submissions_user",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents",collection_id:"taskFlowSubmissions",show_missing:false,extract:"optional_string_field:userId"}
 5 {id:"inventory_sessions_user",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents",collection_id:"inventorySessions",show_missing:false,extract:"optional_string_field:userId"}
 6 {id:"workflow_submissions_user",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents",collection_id:"workflowSubmissions",show_missing:false,extract:"optional_string_field:userId"}
 7 {id:"workflow_submissions_owner",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents",collection_id:"workflowSubmissions",show_missing:false,extract:"optional_string_field:owner"}
 8 {id:"subscriptions_user",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents",collection_id:"subscriptions",show_missing:false,extract:"optional_string_field:userId"}
 9 {id:"vendor_reviews_user",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents",collection_id:"vendorReviews",show_missing:false,extract:"optional_string_field:userId"}
10 {id:"estimate_calibration_user",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents",collection_id:"estimateCalibration",show_missing:false,extract:"optional_string_field:userId"}
11 {id:"inventory_packages_user",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents/admin/inventoryPackages",collection_id:"packages",show_missing:false,extract:"optional_string_field:userId"}
12 {id:"admin_notifications_user",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents",collection_id:"adminNotifications",show_missing:false,extract:"optional_string_field:userId"}
13 {id:"gift_codes_redeemer",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents",collection_id:"giftCodes",show_missing:false,extract:"optional_string_field:redeemedBy"}
14 {id:"event_quarantine_source",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents/phase1System/dispositionTriggerState",collection_id:"quarantinedEvents",show_missing:false,extract:"event_source_path_uid"}
15 {id:"disposition_trigger_state",kind:"singleton",path:"phase1System/dispositionTriggerState",extract:"trigger_state_path_uids"}
16 {id:"oldest_due_alert",kind:"singleton",path:"phase1System/dispositionTriggerState/phase2bAlerts/p2b1_oldest_due_over_900_seconds",extract:"optional_candidate_path_uid"}
17 {id:"deletion_storage_work",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents",collection_id:"accountDeletionStorageWork",show_missing:false,extract:"exact_storage_work_account_uid"}
18 {id:"deletion_auth_work",kind:"firestore_raw",parent:"projects/peezy-1ecrdl/databases/(default)/documents",collection_id:"accountDeletionAuthWork",show_missing:false,extract:"exact_auth_work_account_uid"}
19 {id:"inventory_storage_versions",kind:"storage",prefix:"inventory/",mode:"versions"}
20 {id:"inventory_storage_soft_deleted",kind:"storage",prefix:"inventory/",mode:"soft_deleted"}
21 {id:"users_storage_versions",kind:"storage",prefix:"users/",mode:"versions"}
22 {id:"users_storage_soft_deleted",kind:"storage",prefix:"users/",mode:"soft_deleted"}
```

```text
firestore_raw call:  FirestoreClient.listDocuments({parent,collectionId,pageSize,showMissing,pageToken?}, {autoPaginate:false})   // pinned public-v1; pageToken iff resuming
pageSize:            apply = exactly 100; audit = accepted --page-size value, else exactly 100
returned tuple:      exact length 3; Document[] / raw documents[] / raw nextPageToken / nextRequest agree in count, order, byte-exact names, request identity, terminal token
storage call:        bucket.getFiles({prefix,maxResults:pageSize,autoPaginate:false,versions:true,pageToken?})         // mode "versions"
                     bucket.getFiles({prefix,maxResults:pageSize,autoPaginate:false,softDeleted:true,pageToken?})      // mode "soft_deleted"
storage validation: bucket, tuple, raw/File identity, positive decimal-string generation, holds, token, nextQuery per the C3 pinned tuple discipline
storage object name: <prefix><uid>/<nonempty tail>  -> one canonical UID; malformed blocks
reduction query:     accountDeletionLegacyCandidates orderBy documentId asc, startAfter(reduction_cursor_id) iff nonempty, limit(1)
cleanup query:       document-ID-ordered pages of <= 100 excluded_live candidates per transaction; final limit(1) proves zero rows before checkpoint delete
```

| Extractor | Yields | Blocks on |
|---|---|---|
| `document_id` | one direct child's nonblank one-segment ID | tuple/parent/depth disagreement |
| `optional_string_field:<f>` | zero UIDs iff absent; else one canonical nonblank String without `/` | present non-canonical value |
| `event_source_path_uid` | UID from exact `users/{uid}/events/{eventId}` source path; accepts ID families `qev1_`, `qevu1_`, `qev2_`; runtime scrub semantics unchanged byte-for-byte | foreign quarantine ID family, malformed source path (record-body differences among the three families do not block) |
| `trigger_state_path_uids` | unsigned-UTF8-sorted unique uid set from the seven cursor-map `afterPath` values plus optional `dueObservation.oldestCandidatePath` | any present path failing its owning schema |
| `optional_candidate_path_uid` | uid from optional exact `candidatePath` | malformed path |
| `exact_storage_work_account_uid`, `exact_auth_work_account_uid` | uid from complete work schema with deterministic ID agreement | schema/ID disagreement |

| State | Event/condition | Next state | Writes |
|---|---|---|---|
| (none, audit) | audit run | (none) | zero server writes; streams one bounded page from source 0; interruption restarts at source 0; may run before the creation barrier |
| (none, apply) | accepted arming set + horizons/zero-match gates + barrier match | `discovering` (`source_ordinal:0`, `{kind:"start"}`) | checkpoint create |
| `discovering` | page settled (all extracted UID upserts settled) | `discovering` (cursor advanced) | candidate upsert (deterministic, idempotent); checkpoint page cursor |
| `discovering` | last source terminal | `reducing` (`reduction_cursor_id:""`) | checkpoint |
| `reducing` | candidate read | `reducing` | one checkpoint transaction rereads candidate and advances `reduction_cursor_id` to that ID before any Auth/provider/cleanup/guard await |
| `reducing`/`waiting_guards` | malformed candidate or checkpoint disagreement | stopped | `ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT`; never advances past unknown authority |
| `reducing` (pending/excluded) | Auth present, root absent or root is deletion marker | `reducing` | candidate := `excluded_live/AUTH_PRESENT` |
| `reducing` (pending/excluded) | present nondeletion `users/{uid}` root | `reducing` | candidate := `excluded_live/ROOT_PRESENT` |
| `reducing` (pending/excluded) | ambiguous/transport Auth | `reducing` | candidate stays exact `pending/ambiguous`; `reduction_deferred_count` +1 |
| `reducing` (pending) | Auth check 1 `auth/user-not-found` + root absent, then Auth check 2 `auth/user-not-found` | `reducing` | one transaction: recheck root absence; create DELETING-sweeping marker; one server-generated `adel1_` RFC-4122 lowercase UUID capability + fresh 32-byte random proof hash; exact Storage work row; replace candidate with `adopted` branch |
| `reducing` (adopted) | Auth check 3 after marker creation != canonical user-not-found | stopped | `LEGACY_ACCOUNT_AUTH_RACE`; marker/candidate retained; zero Auth deletion |
| `reducing` (adopted) | relaunch | `reducing` | drives marker only when `operation_id`, `proof_sha256`, `marker_started_at` all match byte-for-byte; pending+marker / adopted+absent-or-mismatching marker / foreign capability = invariant, no cleanup |
| `reducing` (adopted) | cleanup core through Firestore/external/global/two-empty-sweep | `reducing` | until `firestoreCleanupAt` durable; migration owns only fresh canonical-user-not-found `DATA_DELETED→AUTH_GUARDING`; Auth reconciler alone closes `AUTH_GUARDING→ACCOUNT_DELETED` |
| `reducing` | empty-after-nonempty | `reducing` | atomically clear cursor, `reduction_round` +1; empty-at-empty completes the sweep; no candidate can monopolize a sweep |
| `reducing` | complete sweep: zero pending/ambiguous and every adopted has `firestoreCleanupAt` | `waiting_guards` (`reduction_cursor_id:""`) | checkpoint |
| `waiting_guards` | candidate read | `waiting_guards` | identical advance-before-await cursor/wrap rule as `reducing` |
| `waiting_guards` (adopted) | exact ACCOUNT_DELETED tombstone | `waiting_guards` | fresh run of all 23 UID-specific adapters + global destination-zero proofs; delete candidate only after zero residue |
| `waiting_guards` (adopted) | any earlier root state | `waiting_guards` | candidate retained |
| `waiting_guards` | complete sweep with no adopted or pending candidate | `confirming` (`confirmation_zero_passes:0`) | checkpoint |
| `confirming` | pass from row 0 `{kind:"start"}`: zero new, zero pending/ambiguous, zero adopted, every excluded-live reason still true | `confirming` (count +1, max 2) | checkpoint |
| `confirming` | a UID with no candidate row and no residue-free ACCOUNT_DELETED tombstone (`NEW_UID`) | `reducing` (both cursors reset, count 0, `pass_ordinal` +1) | the same checkpoint transaction nominates the UID as a `pending/unexamined` candidate whose `first_pass_ordinal` equals the incremented `pass_ordinal`, before returning to reduction; an existing row at that path carrying another account's identity is `ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT` with zero writes |
| `confirming` | any other failure | `reducing` (both cursors reset, count 0) | checkpoint |
| `confirming` (count 2) | cleanup transaction: reread each nominated candidate + current Auth/root exclusion authority | `confirming` | delete only rows whose complete bytes and reason still match (<= 100 per transaction) |
| `confirming` (cleanup) | drifted row | `reducing` (count 0) | row retained |
| `confirming` (cleanup) | crash between committed pages | `confirming` | restart same bounded query |
| `confirming` (cleanup) | fresh `limit(1)` proves zero candidate rows | (deleted) | last transaction deletes checkpoint; malformed/inaccessible source or provider evidence blocks completion |

| Guard / argv | Exact literal | Refusal |
|---|---|---|
| apply arming (once-only set) | `--apply --project-id peezy-1ecrdl --confirm-project peezy-1ecrdl --database '(default)' --bucket peezy-1ecrdl.firebasestorage.app --drain-evidence-sha256 <64 lowercase hex> --bucket-config-sha256 <accepted digest> --firestore-config-sha256 <accepted digest> --auth-freeze-evidence-sha256 <64 lowercase hex>` | unknown, duplicate, missing, malformed flag → nonzero exit before any write |
| audit flags | `--project-id`, `--confirm-project`, `--database`, `--bucket` + optional `--page-size 1...100` | any other flag → nonzero exit |
| environment | emulator host present, credential-project mismatch, database/bucket mismatch, config/evidence drift, package-lock drift | nonzero exit before any write |
| pre-source-0 (apply) and pre-confirmation gate | accepted Storage/Firestore/Auth/Cloud-Audit/provider-copy arrays' legacy deletion/finite-retention horizons and post-cutoff global zero-match | inaccessible, nonzero, identity-unbound, or unbounded destination blocks the pass |
| barrier match | active blocker config etag + Admin policy digest re-read before every nomination, adoption, waiting-guard mutation, confirmation-page commit | drift = zero-write invariant |
| provider/Auth | never sends a provider request; never calls Firebase Auth delete; no local intent, completion presentation, provider disconnect, or client purge file | — |
| output | fixed codes, bounded counts, source ordinals, candidate/path digests only | raw UID, object name, document path, token, provider bytes never reach stdout/log |

| Rule | Exact statement |
|---|---|
| Pre-apply revocation | revoke every old `deleteAccount` and upload-capable revision; prove final execution; wait pinned 60-second Firestore RPC drain; wait full 604800-second resumable-upload horizon |
| Destination arrays | destination authority only; never a historical UID source |
| Row 0 | `showMissing:true` raw listing is the complete descendant catch-all (no collection-group guess) |
| Residency | at most one resident page; no unbounded RAM |
| Tombstones | permanent ACCOUNT_DELETED tombstones remain after completion; existing-tombstone candidate replays the same residual proof |
| Evidence | signed evidence digest records both confirmation pass digests |
| Barrier lifetime | active through the signed two-pass completion commit |

#### C9.4.2 The create blocker and `LegacyAuthCreationBarrierV1`

```text
export phase2LegacyCreateBlocker = beforeUserCreated({region:"us-central1"}, handler)   // pinned firebase-functions/v2/identity
handler accepts only: eventType "beforeCreate", project "peezy-1ecrdl", empty tenant
handler always throws: HttpsError("permission-denied","Account creation is temporarily unavailable.")   // before any user mutation
LegacyAuthCreationBarrierV1 = blocker + Admin Auth create/import/update deny; canonical digest enters the checkpoint
```

| Item | Exact content |
|---|---|
| Blocking config coverage | first creation via email/password, federated, phone, anonymous, custom-token |
| Blocker evidence | project/tenant, event type, function/revision, handler source hash, prior config complete bytes/hash, active config complete bytes/hash + etag, activation time, service identity, zero-create audit query |
| Admin freeze evidence | complete sorted principal×permission policy, etags, deny evidence, audit alert |
| Apply unavailable when | blocking functions unavailable or any creation path bypasses the blocker |
| Restoration | one etag-CAS from still-exact active config to recorded prior bytes; Admin grants restored only from recorded etags; blocker revision proven zero active instances; post-restore zero-unexpected-create audit query |
| Restore drift | creation stays blocked; owner paged; no guessing |
| Existing sign-in | not disabled; new user creation impossible |

#### C9.4.3 `purgeLegacyResolvedProviders.js`

```text
functions/scripts/purgeLegacyResolvedProviders.js   // import-side-effect-free
export auditAndPurgeLegacyResolvedProviders({db,apply,emit})   // injected Firestore adapter; no project/env/exit/argv authority
collection: providerDirectory; paging: limit(100), run-local unsigned full-document-path cursor, one resident page
pre-delete: bounded transaction rereads row; source:"seeded" preserved byte-for-byte; every non-seeded (absent/malformed/resolved) deleted
termination: two fresh complete passes observing zero non-seeded rows
resolveProvider.js: cacheResolved and its call from resolveProviderRequest deleted; loadDirectory() admits only complete exact source:"seeded" rows into directoryCache; cache initialized empty; no prewarm/copy
```

| Guard | Exact literal | Refusal |
|---|---|---|
| arming | `--apply --project-id peezy-1ecrdl --confirm-project peezy-1ecrdl --drain-evidence-sha256 <64-lowercase-hex>` | unknown/duplicate argument → nonzero |
| default | audit/read-only | — |
| client identity | public-v1 client project/database resolve exactly `peezy-1ecrdl/(default)` | mismatch → nonzero |
| emulator | `FIRESTORE_EMULATOR_HOST` absent | present → exit before core invocation or write |
| drain binding | final digest bound to owner-accepted platform drain artifact in run report | — |
| ordering | every production guard before pure core; no delete precedes all guards | any guard/read/transaction/delete failure → nonzero |
| output | counts, fixed guard/class tokens, lowercase SHA-256 document-path digests | never raw IDs/paths/document bytes |
| run report | exact command, resolved target, drain-artifact digest, per-class counts, two-pass result | — |

| Rollout step | Exact statement |
|---|---|
| 1 | revoke invocation to every `resolveProvider` revision before shifting cache-free bytes |
| 2 | prove final old execution termination `TproviderZero`; wait through `TproviderZero + Commit.timeout_millis(60,000)` |
| 2' | if termination unprovable: undeploy all revisions, prove zero instances/executions, wait same window |
| 3 | run separately authorized purge; accept two-pass report |
| 4 | force pre-purge cache-free instances to zero; deploy fresh instance set from identical accepted artifact digest; prove old-instance count zero |
| 5 | restore invocation only to fresh cache-free revision before account-deletion invocation is restored |
| invariant | no new Phase-2 writer may recreate a non-seeded provider row |

#### C9.4.4 The sealer and trust anchor

```text
functions/scripts/sealAccountDeletionProviderEvidence.js   // import-safe; sole producer of functions/accountDeletionProviderEvidenceV1.json
trust anchor: 32-byte Ed25519 public key (base64url) + its SHA-256 as literal reviewed constants in sealer AND functions/accountDeletionFence.js; no placeholder; one offline key created before Build A, private key never in the repository; evidence gathered and signed under separate operational authorization against Build A's implementation digest
externalEvidenceSigningKeySHA256 = SHA-256(decoded 32 key bytes) == compiled trust-anchor digest
signedAuthorityPayloadSHA256 = lowercase SHA-256(TaskCanonicalV1(authority map minus {signedAuthorityPayloadSHA256, externalEvidenceSignatureBase64URL, authoritySHA256}))
signed message = ASCII("peezy.account_deletion_provider_evidence.v1\0") || hexDecode(signedAuthorityPayloadSHA256) || hexDecode(externalEvidenceBundleSHA256) || hexDecode(implementationSHA256)
authoritySHA256 = SHA-256(TaskCanonicalV1(complete map minus {authoritySHA256}))
implementationSHA256 = lowercase SHA-256(TaskCanonicalV1({domain:"account_deletion_provider_implementation.v1",files}))   // files[] sorted unsigned UTF-8 by repo path; {path,sha256} raw bytes
implementation path set (base 22): functions/accountDeletionFence.js, functions/dispositionTriggers.js, functions/entitlement.js, functions/getWorkflowQualifying.js, functions/index.js, functions/notificationIntents.js, functions/notifySupport.js, functions/packageInventory.js, functions/package-lock.json, functions/package.json, functions/peezyChat.js, functions/processInventory.js, functions/researchTask.js, functions/resolveProvider.js, functions/scripts/sealAccountDeletionProviderEvidence.js, functions/spawnTasks.js, functions/submitCheckIn.js, functions/submitCheckInCore.js, functions/supportAdmin.js, functions/taskDisposition.js, functions/taskPlan.js, functions/validateSubscription.js
implementation path set (five additions, unsigned-path sort order): functions/scripts/purgeLegacyDeletedAccounts.js, functions/scripts/purgeLegacyResolvedProviders.js, firestore.indexes.json, firestore.rules, storage.rules
sole exclusion: functions/accountDeletionProviderEvidenceV1.json
```

```text
ProviderEvidenceAuthorityV1 (exact unknown-rejecting map; displayed member order):
{schemaVersion:1,kind:"ACCOUNT_DELETION_PROVIDER_EVIDENCE",generationId,projectId,databaseId,bucketName,region,
 implementationSHA256,packageLockSHA256,
 firestoreRulesSHA256,storageRulesSHA256,firestoreIndexesSHA256,firestoreRulesetId,firestoreReleaseId,storageRulesetId,storageReleaseId,
 bucketConfig,bucketConfigSHA256,firestoreConfig,firestoreConfigSHA256,
 storageDestinations,firestoreDestinations,authDestinations,cloudAuditDestinations,providerCopyDestinations,
 copyProducerDenySHA256,policyChecks,signatureAlgorithm:"ed25519",
 externalEvidenceBundleSHA256,externalEvidencePublicKeyBase64URL,externalEvidenceSigningKeySHA256,
 signedAuthorityPayloadSHA256,externalEvidenceSignatureBase64URL,activatedAt,authoritySHA256}
AcceptedArrayDigestV1 = {count,canonicalBytes,sha256}   // the five destination members; count safe 0...4096; canonicalBytes safe 0...67108864; exact digest
```

| Artifact constraint | Exact value |
|---|---|
| `firestoreRulesSHA256`, `storageRulesSHA256`, `firestoreIndexesSHA256` | raw accepted repository bytes; inside `signedAuthorityPayloadSHA256` |
| `firestoreRulesetId`, `firestoreReleaseId`, `storageRulesetId`, `storageReleaseId` | nonblank, at most 1,024 UTF-8 bytes each; exact deployed rulesets/releases; inside `signedAuthorityPayloadSHA256` |
| Seven-member rule | no authority lacking any of the seven is V1; fresh bounded activation/finalize checks require those deployed release IDs and content hashes; rules/index release mutation permissions are `DeletionCopyProducerDenyV1` producer entries |
| `policyChecks` | byte-equal to the deny subset |
| `bucketConfig`, `firestoreConfig` | the complete accepted maps |
| ordinary strings | at most 4,096 UTF-8 bytes |
| `externalEvidencePublicKeyBase64URL` | exact unpadded base64url of 32 bytes |
| `externalEvidenceSignatureBase64URL` | exact unpadded base64url of 64 bytes |
| `activatedAt` | canonical UTC instant |
| every digest | exactly 64 lowercase hex |
| complete artifact | at most 131,072 `TaskCanonicalV1` bytes |
| payload digest | runtime recomputes `signedAuthorityPayloadSHA256` before signature verification |
| rejection | missing, unknown, surplus, duplicate-key, wrong-order, over-cap, digest/count/identity/key/algorithm/payload mismatch, invalid Ed25519 signature, or mismatch to the signed external bundle blocks deletion/reconciler activation; changing any member while retaining the old signature is rejected |

```text
PROVIDER_POLICY_CHECK_ADAPTERS_V1 (literal two-row registry; production dispatch = closed switch over exactly these IDs)
 google_json_get_v1        exact GET, no body
 google_iam_get_policy_v1  exact POST, content type JSON, byte-exact body {"options":{"requestedPolicyVersion":3}}
transport (both rows): Node 22 https + pinned transitive google-auth-library 9.15.1 GoogleAuth({scopes:["https://www.googleapis.com/auth/cloud-platform.read-only"]}); headers obtained for the exact URL; send only those authorization headers + accept: application/json; zero redirects; zero retries; 3,000-ms socket/request deadline; raw response cap 1,048,576 bytes; status 200 + JSON media type; streaming duplicate-key/Unicode validator before parse; complete own-property plain-object graph
expectedPolicySHA256 = SHA-256(TaskCanonicalV1(completeResponseObject))
etag: only the selected closed etagSource; header lookup lowercase etag; body.etag / body.policy.etag require exact own String members; header/body surplus stays inside the selected complete response-object hash; SDK/provider error text never logged
static: registry IDs == switch cases == independent-oracle cases; any dynamic method name, host, body, retry, redirect, or third adapter fails
```

| Sealer once-only mode | Validates / does |
|---|---|
| bundle | complete signed evidence bundle, at most 67,108,864 bytes |
| arrays | five complete destination arrays; `DeletionCopyProducerDenyV1` |
| projections | current bucket/Firestore projections; project/database/bucket/region |
| digests | implementation and package-lock digests |
| write | creates absent JSON path without overwrite; read-verifies canonical bytes/hash/signature |
| refusal | nonzero `postCutoffMatchCount`, nonzero `backlogCount`, non-finite `retentionSeconds` → refuse before artifact creation |

| Build | Behavior |
|---|---|
| Build A | complete code + constants, no authority JSON; `deleteAccount`, both reconcilers, historical apply path return `PROVIDER_EVIDENCE_NOT_ACTIVATED` before any provider/Firestore mutation; unrelated exports load |
| Build B | adds only the immutable artifact; missing/malformed artifact, timeout, +1 check, config/policy/key/signature drift, generation disagreement → `ACCOUNT_DELETION_PROVIDER_EVIDENCE_INVARIANT`, no guard/final write, no Auth delete, `DELETION_RETRY_REQUIRED`; no placeholder build may initialize/enable a reconciler or restore deletion |
| replacement | new signed bundle + ordinary source-control replacement under break-glass order; no deployed function/runtime identity/migration/repair path creates/updates/deletes the artifact |
| import graph | artifact imported only by `accountDeletionFence.js`; packaged byte-for-byte in Build B; zero writers in deployed graph |
| migration binding | migration checkpoints bind `generationId` and `authoritySHA256` |
| Build-B binding | external deployment evidence (not an artifact member) binds `implementationSHA256` + `authoritySHA256` to the Build-B revision and image digest |
| Build B fence | per reconciler acquisition and finalize: validate loaded artifact, then only 1 bucket-config RPC + 1 Firestore-config RPC + all `policyChecks` RPCs; <= 14 observations, ordinal order, concurrency 4, 3,000 ms each -> 4 waves / 12-s hard local deadline; exact current maps/etags/digests must match the artifact; finalize adds <= one 10-s root/work/lease transaction + one 10-s Auth delete = 32 s of admitted awaits inside the 60-s callable, no new await after 42 s; reconciler same bound inside 270 s; destination arrays not re-enumerated (signed digests authoritative while copy-producer deny roots match) |

#### C9.4.5 Client per-UID legacy migration rows and `inspectLegacyTaskReset`

```text
LegacyResetMigrationV1 =
 {schemaVersion:1,uid,authEpochUUID,credentialRevision,
 legacyOperationId,migrationAlias,aliasCandidateOrdinal,requestFingerprint,
 legacyKeyGuard,initiatingAuthority?,
  phase:"prepared"|"dispatched"|"receipt"|"applying"|"blocked",
  requestCanonicalJSON,requestSHA256,receipt?,applicationId?,errorCode?,
  createdAt,updatedAt}
 |
 {schemaVersion:1,uid,authEpochUUID,credentialRevision,
  initiatingAuthority?,
  phase:"blocked",errorCode:"LEGACY_ALIAS_INVALID",
  legacyValueClass:"non_string"|"invalid_string",
  legacyValueUtf8Length?,legacyValueSHA256?,createdAt,updatedAt}

initiatingAuthority = absent | {kind:"reserved_gesture",gestureId,gestureGeneration,alias} | {kind:"reset_dispatched",expectedTaskGenerationEpoch,suggestedOperationId}
   // reserved member byte-matches the sole reserved gesture; reset_dispatched member byte-matches the same-UID reset_dispatched row with canonical ID and progress receipt both absent, created only after LEGACY_RESET_MIGRATION_REQUIRED; binding immutable through RECEIPT except the same-UID auth rebind (reserved member only)
legacyKeyGuard      = {kind:"absent"} | {kind:"valid_string",value} | {kind:"invalid_value",valueClass:"non_string"|"invalid_string",utf8Length?,sha256?}   // immutable; valid_string.value == the row's initial requested legacyOperationId
aliasCandidateOrdinal = 1|2|3|4   (required in every reconciliation-row phase incl. blocked; forbidden in invalid-alias member)
requestCanonicalJSON = UTF-8(TaskCanonicalV1({action:"reconcileLegacyTaskReset",legacyOperationId,migrationAlias}));  requestSHA256 = lowercase SHA-256(requestCanonicalJSON)
requestFingerprint   = "rlmreq1_" + SHA-256(TaskCanonicalV1({account_uid:uid,legacy_operation_id:legacyOperationId}))
migrationId          = "rlm1_" + first40(SHA-256(TaskCanonicalV1({account_uid:uid,legacy_operation_id:legacyOperationId})))
applicationId        = "rla1_"  + first40(SHA-256(TaskCanonicalV1({uid,migration_id:receipt.migrationId,outcome:receipt.outcome})))   // required for not_dispatched|finalized_compat; forbidden for upgraded|phase2_active
applicationId(clear) = "rlic1_" + first40(SHA-256(TaskCanonicalV1({uid,legacy_value_class,legacy_value_utf8_length?,legacy_value_sha256?,outcome:"legacy_value_changed"|"none"})))   // absent optionals omitted
server path: users/{uid}/legacyResetMigrations/{migrationId}
```

| State | Event/condition | Next state | Writes |
|---|---|---|---|
| (no row) | classify key once; draw ordinal-1 alias | `prepared` | durable PREPARED (background: no `initiatingAuthority`; user reserve: `ResetGestureV1` durably adopted first; ordinary reset: bind already-durable `reset_dispatched` row) |
| `prepared` | dispatch | `dispatched` | durable before await |
| `dispatched` | transport ambiguity | `dispatched` | none; retry same candidate, no ordinal consumed |
| `dispatched` | validated zero-write `LEGACY_RESET_ALIAS_OCCUPIED`, ordinal 1–3 | `prepared` | one fresh UUIDv4; ordinal +1; rewrite `migrationAlias`, `requestCanonicalJSON`, `requestSHA256`; atomic CAS |
| `dispatched` | validated `LEGACY_RESET_ALIAS_OCCUPIED`, ordinal 4 | `blocked/LEGACY_ALIAS_COLLISION_EXHAUSTED` | atomic |
| `dispatched` | collision detail legacy ID/alias != durable request | `dispatched` | none (protocol failure) |
| `dispatched(A)` | validated `LEGACY_RESET_MIGRATION_REQUIRED(B)`, `B != A` valid | `prepared(B)` | fresh alias, `aliasCandidateOrdinal:1`, recompute request bytes/hash; preserve `uid`, auth tuple, `legacyKeyGuard`, `initiatingAuthority`, `createdAt`; `updatedAt=writeTime`; no receipt/application/error |
| `dispatched(A)` | B invalid / `B == A` / row/request/response/auth CAS differs | `dispatched(A)` | none |
| `dispatched` | complete success from four-member union (`not_dispatched|finalized_compat|upgraded|phase2_active`) | `receipt` | durable; `replayed:false` requires `receipt.migrationAlias == migrationAlias`; forbids `errorCode` |
| `dispatched` | `AUTH_REQUIRED` | `dispatched` | none; surfaces pending |
| `dispatched` | `RESET_ACTIVE` | `dispatched` | none (protocol contradiction) |
| `dispatched` | `OPERATION_REUSED` | `blocked/OPERATION_REUSED` | no transition out |
| `dispatched` | `LEGACY_RESET_CORRUPT` (reconciliation row) | `blocked/LEGACY_RESET_CORRUPT` | Retry edge only |
| `dispatched` | `REQUEST_INVALID` after local canonical validation | `blocked/LEGACY_RESET_CORRUPT` | — |
| `dispatched` | `CLIENT_UPGRADE_REQUIRED` with retained legacy ID | reconciliation | never retried through raw legacy action |
| `receipt` | atomic envelope write | `applying` | always removes `initiatingAuthority`; retires/materializes referenced authority; stores `applicationId` (not_dispatched/finalized_compat); upgraded/phase2_active perform receipt-derived materialization without epoch read; not_dispatched/finalized_compat create no reset row and perform no epoch read/call and never preserve/rebind the invocation; upgraded adopts the migration-committed rotation; phase2_active adopts the existing canonical rotation with no server mutation |
| `applying` | compare-and-remove guarded UserDefaults key | `applying` | absent → success; `valid_string` exact Swift String match → remove; `invalid_string` exact length/digest match → remove; different value → remains; `non_string` → never auto-removed |
| `applying` | comparison + all state-derived effects done | (removed) | row removed |
| `blocked/LEGACY_RESET_CORRUPT` | explicit Retry | `prepared` | preserves uid, auth tuple, legacy ID, alias, ordinal, guard, initiating authority, request bytes/hash, `createdAt`; removes `errorCode`; `updatedAt=writeTime`; no call until durable; same immutable request only — never replaces requested A with an inspected B while A is unresolved |
| `blocked/LEGACY_ALIAS_COLLISION_EXHAUSTED` | later explicitly confirmed `reserve()` | `prepared` | new candidate, ordinal 1, recomputed request bytes/hash, retained or new consent; background/startup never resets |
| `blocked/OPERATION_REUSED` | any | `blocked/OPERATION_REUSED` | none |
| `blocked/LEGACY_ALIAS_INVALID` | `inspectLegacyTaskReset` → `legacy_active(B)` under reserved-gesture authority | `prepared(B)` | atomic replace with complete PREPARED(B), ordinal 1, carried initiating authority + invalid `legacyKeyGuard` |
| `blocked/LEGACY_ALIAS_INVALID` | inspect → `phase2_active(C)`, guard match/absent | (adopted `reset_dispatched` row) | compare-remove or explicit clear; CAS blocked envelope; create no-receipt/no-canonical `reset_dispatched` row for `(uid,expectedTaskGenerationEpoch)` with `createdAt=gesture.reservedAt`, `updatedAt=writeTime`; remove migration row, initiating authority, gesture; revalidate inspection authority first; uses only the stored reserved alias; guard absence = crash-resume after an earlier matching clear, not drift |
| `blocked/LEGACY_ALIAS_INVALID` | inspect → `phase2_active(C)` or `none`, guard drifted | (removed) | retire migration, initiating authority, gesture; key untouched; return `legacyRetryRequired` with `rlic1_`/`legacy_value_changed` ID |
| `blocked/LEGACY_ALIAS_INVALID` | inspect → `none`, guard match/absent, reserved-gesture consent, no destructive reset active | (removed) | compare-clear; one envelope CAS removes row, initiating authority, gesture; result `LEGACY_RESET_RETRY_REQUIRED` with `rlic1_`/`none` ID |
| `blocked/LEGACY_ALIAS_INVALID` | inspect-context `LEGACY_RESET_CORRUPT`, malformed/transport/unavailable inspection, background inspection without consent | `blocked/LEGACY_ALIAS_INVALID` | byte-identical; surfaces `RESET_MIGRATION_BLOCKED/LEGACY_ALIAS_INVALID`; may retry only inspect |
| any (signed-out / other UID current) | — | unchanged | no new dispatch or APPLYING; returned response may advance only the original-UID row to `receipt` after complete request/response/phase CAS validation, never mutating current-account authority; application waits until that UID is current; a response after rebase persists only against the rebased tuple |
| any (same UID, new auth epoch) | rebind | same phase | rebind only `authEpochUUID/credentialRevision`; old-epoch reserved gesture discarded and reserved initiating member cleared; materialized/reset-dispatched retained |
| any (same epoch) | current revision < stored | corrupt | — |
| any (same epoch) | current revision > stored | same phase | atomic rebase of row and matching gesture before dispatch or in the receipt-persisting envelope write |

```text
Inspect request:  {action:"inspectLegacyTaskReset"}                       // authenticated, read-only; offered only by LEGACY_ALIAS_INVALID
Inspect success:  {schemaVersion:1,kind:"legacy_reset_inspection",outcome:"none",accountUid}
                | {schemaVersion:1,kind:"legacy_reset_inspection",outcome:"legacy_active",accountUid,legacyOperationId}
                | {schemaVersion:1,kind:"legacy_reset_inspection",outcome:"phase2_active",accountUid,canonicalOperationId,expectedTaskGenerationEpoch}
Inspect error:    inspect-context LEGACY_RESET_CORRUPT (malformed/root disagreement); unknown/surplus members reject
phase2_active(C): require safe r = expectedTaskGenerationEpoch+1; validate C canonical formula/account/root-marker; never store C as caller alias; never call ResetEpochAuthorityProviding; relaunch retries ordinary resetAllTasks; no (e+1)→(e+2) rotation; no second alias

Local-only surfaces (never decoded as Firebase details):
{schemaVersion:1,kind:"RESET_MIGRATION_PENDING",uid,phase:"prepared"|"dispatched"|"receipt"|"applying"}
{schemaVersion:1,kind:"LEGACY_RESET_COMPLETED",uid,applicationId}
{schemaVersion:1,kind:"LEGACY_RESET_RETRY_REQUIRED",uid,applicationId}
{schemaVersion:1,reason:"RESET_MIGRATION_BLOCKED",uid,errorCode:"LEGACY_ALIAS_INVALID"|"LEGACY_RESET_CORRUPT"|"LEGACY_ALIAS_COLLISION_EXHAUSTED"|"OPERATION_REUSED"}
```

| Rule | Exact statement |
|---|---|
| Invalid-alias member | forbids `legacyOperationId`, `migrationAlias`, request members, receipt, application, other error codes; permits only absent or reserved-gesture initiating authority; `non_string` forbids both metadata members; `invalid_string` requires UTF-8 length + lowercase SHA-256, never the value |
| BLOCKED (reconciliation row) | `errorCode` exactly `LEGACY_RESET_CORRUPT|OPERATION_REUSED|LEGACY_ALIAS_COLLISION_EXHAUSTED`; forbids receipt/application |
| PREPARED/DISPATCHED | forbid receipt/application/error |
| APPLYING | forbids `initiatingAuthority`; retains same receipt |
| Absent initiating member at `receipt→applying` | legal only for background row with no gesture/reset row referencing it; removes none |
| Present-authority mismatch at `receipt→applying` | blocks with zero write; existing-row disagreement (upgraded/phase2_active) → B3, zero write |
| Materialization alias | background uses `receipt.migrationAlias`; reserved-gesture/reset-dispatched retain bound alias |
| Ordinal draw | every draw consumes its ordinal even on repeated UUID; no hidden resampling |
| Singleflight | one `inflightLegacyMigration` per UID |
| Startup | existing valid row resumes from immutable request/phase before key reread; key is compare/remove authority only in APPLYING |
| Crash after invalid inspection → PREPARED(B) | resumes B; cannot regress; carried guard decides cleanup |
| `.retakeAssessment` (finalized_compat) | eligible only when persisted receipt has outer `replayed:false`; posted at most once by the in-memory RECEIPT→APPLYING commit; `replayed:true` / loaded-APPLYING never posts |
| Not-dispatched result | user-initiated → `LEGACY_RESET_RETRY_REQUIRED` after application ID finished; background → no user result; finalized-compat → existing completed result |
| Blocked reserve | refuses with the blocked error/recovery; no destructive discard |
| Historical records | not resume authority without their alias |
| `phase2_active` coexistence | no pre-APPLYING migration row may coexist with adopted row; same-key unequal row or four-row capacity leaves migration/gesture blocked |

#### C9.4.6 Coordinator scope and trace

```text
File: Peezy 4.0/MainInterface/Models/RetakeAssessmentCoordinator.swift
retake() async throws -> Void   // shape preserved; registry reserve is the first async operation; no UserDefaults operation identity
ResetReserveOutcome / ResetInvocationOutcome switch:
  binding                      -> bind -> drive
  operation                    -> drive
  completed | legacyCompleted  -> return after already-frozen application
  migrationPending(payload)    -> throw Error.migrationPending(payload)     message "Your reset is safely queued. Reopen Settings to continue when you're online."
  legacyRetryRequired(payload) -> throw Error.legacyRetryRequired(payload)  message "No prior reset was committed. Start Reset Assessment again to begin a new reset."
same-process trace (exact, only legal complete trace):
  resetDispatch,inspect,deleteAssessments,inspect,deleteUserKnowledge,inspect,resetDose,inspect,finalize,notification
closure replacement: deleteAssessments/deleteUserKnowledge/resetDose accept ResetLocalCleanupAuthorityV1; dose calls only DailyDoseEngine.resetForRetake(authority:)
```

| Byte guard | Exact value |
|---|---|
| `Peezy 4.0/Menu/PeezySettingsView.swift` start marker / end | LF-terminated `    private func deleteAccount() {` … matching `    }`; next two lines exactly one blank LF and `    // MARK: - Helpers\n` |
| replacement | delegates to `Phase2ProductionRuntime.accountDeletionCoordinator`; no direct Functions/Auth/store/presentation call; no `httpsCallable("deleteAccount")`; preserves existing UI progress/error behavior; Settings never owns the post-sign-out UI |
| Coordinator slice start | 12-space `deleteAssessments: { userId in` … `resetDose` closure's 12-space `},` inclusive of final LF |
| Pre-edit following line / post-edit following line | `            operationStore: store,` / `            postNotification: {` |
| Fatal | zero/multiple markers, nonunique/unbalanced boundary, different adjacent lines, outside-slice byte change, retake-slice change, direct UID-only delete, retained `operationStore` line |

| Rule | Exact statement |
|---|---|
| Error payloads | complete typed local-only payload retained; non-destructive; flow through existing settings `catch` |
| Cleanup/TaskPlanService | never called outside `drive`; handle UID supplies all three cleanup calls; only actor-owned materialized registry alias/epoch reaches TaskPlanService |
| Closure authority | no closure accepts only UID or retains authority beyond one invocation |
| Committed inspection | short-circuits remaining trace suffix; posts no notification |
| Index / rules | exact 5,872-byte index registry; direct-client denial for every operation on `legacyResetMigrations` |

#### C9.4.x Named falsifiers

| Test file | Named test / fixture family |
|---|---|
| `functions/tests/accountDeletionFence.test.js` | historical migration: inventory-only orphan; swallowed `users/` Storage error; each omitted external/global family; each accepted provider-copy pointer; Auth-present/root-absent preservation; Auth-not-found/root-absent adoption; Auth ambiguity; all three Auth checks; root race; random failure; marker/work transaction loss; every sweep/guard/tombstone crash; provider/config drift; candidate collision; bounded paging/apply-cursor replay; audit interruption restarting at source zero with byte-exact zero writes; insertion between zero passes; restart with each identity/evidence/implementation/source-registry/package/lock digest changed; strict audit/apply argv; emulator rejection; redacted output; zero reachable Auth-delete/local-presentation/provider-send call sites |
| `functions/tests/accountDeletionFence.test.js` | excluded-live cleanup fixtures: exactly 0, 1, 100, 101, 500 candidates plus crash after every page boundary |
| `functions/tests/accountDeletionFence.test.js` | provider purge: import/default; page sizes 100/101; continuation; each missing/malformed arming member; wrong project/database; `FIRESTORE_EMULATOR_HOST` exiting before core invocation or write; unknown/duplicate argument; failure before/after nomination; old `.set()` at timeout-minus-epsilon settling at +60 s; static zero `providerDirectory` create/update calls; core called directly with mixed seeded/resolved/malformed rows (seeded rows remain and still qualify frozen WAIT authority; CLI arming path never used against the emulator); warm-cache fixture (resolved, malformed, missing-source rows not retained after purge + fresh-instance restoration); active-export high-confidence resolution with zero runtime Firestore writes |
| `functions/tests/accountDeletionFence.test.js` | sealer/authority: exact and every field/count/byte cap +1; Build-A absent behavior with unrelated exports live and zero mutation; Build-B absent failure; seal overwrite refusal; algorithm/key/domain/message/bundle/signature/hash mismatch; package/implementation drift; 1/12/13 policy checks; four-wave deadline; policy/config creation immediately before/after final read; lease takeover during observations; generation replacement; break-glass ordering; Build-A→Build-B binding; zero runtime authority writer; static module-graph (artifact imported only by `accountDeletionFence.js`, packaged byte-for-byte, no writer) |
| `functions/tests/accountDeletionFence.test.js` | `sealer refuses nonzero matches, backlog, and nonfinite retention` |
| `functions/tests/accountDeletionFence.test.js` | `PROVIDER_POLICY_CHECK_ADAPTERS_V1`: both rows; all four etag sources; malformed/duplicate/oversize JSON; status/media/redirect/auth/timeout; response-field drift; 1/12/13 checks; registry/switch/oracle disagreement |
| Node `--check` (§9.3 envelope) | `functions/scripts/purgeLegacyResolvedProviders.js`, `functions/scripts/purgeLegacyDeletedAccounts.js`, `functions/scripts/sealAccountDeletionProviderEvidence.js` |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | migration rows: every accepted/rejected legacy cross-product and member; server-only-authority-first replay; literal IDs/fingerprint; `taskPlanOperations/{migrationId}` decoy ignored; active upgrades from both states; old leased-worker conflict; insertion after tasks-deleted; all server/local crash boundaries; two devices with different aliases and one authority record/epoch rotation; valid existing record winning over occupied candidate; candidates 1–4 occupied with crash before/after every DISPATCHED→PREPARED CAS; exact exhausted block; no background cap reset; confirmed reserve resetting to ordinal 1; transport ambiguity retaining candidate; discovery without local key from durable reset-dispatched row; not-dispatched removing either initiating-authority shape; finalized between migration-required and reconciliation; finalized-compat with absent background / present user authority; A-absent/A-finalized beside active B redirect; crash before/after A→B redirect and repeated redirect; phase2-active response loss and crash; whitespace-changed valid-string key; non-string→non-string never auto-removed; raw fence reading new path before root/legacy mutation; account deletion removing collection and preventing recreation; finalized no rotation/delete; malformed key blocked; corrupt Retry to PREPARED; forbidden Retry for OPERATION_REUSED; account switch; reserve during every phase; coordinator call order; no path from UserDefaults to TaskPlanService |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | auth-tuple fixtures: refresh before dispatch and during reconciliation await; response after account switch; revision rollback; sign-out→same-UID/new-epoch at prepared, dispatched-ambiguous, receipt, applying |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | inspect fixtures: background invalid → confirmed reserve → durable gesture/authority; no migration-row coexistence; ordinary completion; kill before authority attachment / before key clear / after key clear / after adoption durability; capacity/conflict after clear; invalid→different-invalid and invalid→valid drift retiring authority; invalid→absent crash-resume; C finalizing between inspection and confirmation; response loss; first corrupt Retry success; repeated corruption reblocking; `OPERATION_REUSED` never transitioning; background inspection never clearing; crash after drift retirement leaving no row/gesture/clear |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | authority-consuming transitions: row/gesture/`initiatingAuthority` disappear atomically; no APPLYING row retains it; finalized-compat `replayed:false` posts once, `replayed:true` after loss posts zero, key reappearance/server replay posts zero; ordinary-reset kills before/after final-receipt durability, APPLYING durability, posting; `replayed:true` after server commit/response loss; loaded FINAL_RECEIPT/APPLYING; zero pre-durability or duplicate notification; upgraded-with-gesture fixture (root `e` → `r=e+1`; materialization adopts receipt epoch `e`; no epoch-authority read or pre-durability reset dispatch; every continuation addresses only canonical `r`, never `r→r+1`; kills before/after RECEIPT and `receipt→applying`; gesture survives RECEIPT; loaded APPLYING accepts only exact reset-row equality) |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | coordinator (D30/D14/B2): exact same-process trace recorder; preimage/replacement boundary mutation; direct UID-only delete; duplicate/remove/reorder every inspect or callback; every `ResetReserveOutcome` and `ResetInvocationOutcome`; every server code/details member, surplus/missing/wrong-code rejection, every local mapping |
| Production/oracle | exact 5,872-byte index registry; direct-client denial for every operation on `legacyResetMigrations` |
| `functions/tests/accountDeletionFence.test.js` | confirming NEW_UID nomination: the pending candidate and the failure transition commit together; `pass_ordinal` +1 (S3-CD7) |

### C9.5 Reset envelope and gesture binding, terminal-child reuse, superseded presentation (B2, D12–D15, D18–D21, D24)

#### C9.5.1 Terminal-child reuse (D12/D13)

| Rule | Exact statement |
|---|---|
| Removed comparisons | Only the three create-time-zero revision comparisons are removed |
| Policy child match | Existing policy child must match frozen stable identity/provenance/policy, task instance, and generation-epoch projection |
| Revisions | `flowWriteRevision`, `notesWriteRevision`, `quotesWriteRevision` and live progress/tail: structurally validated, never compared with create-time zero, preserved byte-for-byte |
| Legacy child | Retains frozen legacy immutable identity/provenance and policy-absence match unchanged |
| `terminal_spawn_closure` | Reconfirmation governed by the same rule |
| Identity | No reuse/reconfirmation branch reads a revision for identity |

#### C9.5.2 Sole owners and epoch authority (B2/D14/D15)

| Rule | Exact statement |
|---|---|
| Envelope owner | `ResetOperationRegistry` in `TaskPlanService.swift` is sole actor and sole reader/writer of `PeezyTaskPlanReset-v2.json` |
| No direct access | No view, coordinator, callback, migration helper, or façade accesses that file |
| Alias lookup | Never a collection query; normal reset resolves `(uid,expectedEpoch)` to the deterministic canonical path; D16/D17 withdrawn |
| Recovery writes | `DurableStoreRecoveryCoordinator` writes reset target only by invoking `ResetOperationRegistry`; never opens/replaces/unlinks the file |
| Daily-dose key | `LocalPrivacyPurgeCoordinator` enumerates/removes `peezy.{uid}.dailyDose.v2` only through `DailyDoseLocalStore` |
| Epoch seam | `ResetEpochAuthorityProviding.current(uid:expectedAuth:) async -> {uid,taskGenerationEpoch}`; production reads user-root authority via authenticated Firestore seam; validates UID, safe epoch, complete expected auth tuple |
| Bind sequence | Signed auth from `AuthAuthorityProviding` → await epoch seam → reread signed auth → envelope CAS |
| Epoch zero | Neither protocol may synthesize epoch zero from read failure |

#### C9.5.3 Envelope payload and gesture (D24)

```text
Payload = {records:[ResetOperationRegistryRecordV2] <= 4,
           legacyMigrations:[LegacyResetMigrationV1] <= 4,
           gesture?:ResetGestureV1}

ResetGestureV1 = {
  gestureId,uid,authEpochUUID,credentialRevision,
  phase:"reserved"|"bound",alias,expectedEpoch?,
  gestureGeneration,reservedAt,boundAt?
}

gestureId         = "rsg1_" + lowercase UUID
alias             = ResetAliasV1 (generated once)
gestureGeneration = lowercase RFC 4122 UUID == outer DurableFileEnvelopeV1.generationId of the atomic write that first stores the gesture; immutable per gesture
reserved: expectedEpoch forbidden, boundAt forbidden
bound:    expectedEpoch required, boundAt required
```

| Rule | Exact statement |
|---|---|
| Outer generation | Later whole-envelope writes get fresh outer generation IDs but preserve `gestureGeneration` |
| Continuation CAS | Every continuation CASes stored token plus gesture/auth identity |
| Bind failure | No bind-failure counter; transient failure leaves byte-identical reserved gesture |

#### C9.5.4 Local time and `writeTime`

| Rule | Exact statement |
|---|---|
| Clock | One injected `LocalDurableClock.now()`; canonical UTC RFC 3339 millisecond instant |
| Sample | Each atomic envelope replacement samples once immediately before encoding |
| `writeTime` | Later of sample and every valid `reservedAt\|boundAt\|createdAt\|updatedAt` on the gesture/row being advanced; compared by parsed instant; re-encoded canonical millisecond |
| Failure | Clock failure, nonrepresentable sample, or noncanonical stored time writes nothing and enters corruption recovery |
| Replay | Exact replay/no-write preserves every time byte |

| Transition | `reservedAt` | `boundAt` | `createdAt` | `updatedAt` |
|---|---|---|---|---|
| Reservation creation | `=writeTime` | forbidden | — | — |
| reserved→bound | preserved | `=writeTime` | — | — |
| bound→prepared (new reset row) | — | — | `=gesture.reservedAt` | `=writeTime` |
| Attach reserved-gesture `initiatingAuthority` to existing blocked invalid-alias migration | preserved if gesture already stored; `=writeTime` only if gesture created in same write | — | preserved (migration) | `=writeTime` (migration) |
| Fresh migration / background or receipt-derived reset row without gesture | — | — | `=writeTime` | `=writeTime` |
| Receipt-derived reset row with reserved gesture | — | — | `=gesture.reservedAt` | `=writeTime` |
| Direct `phase2_active` adoption from invalid-alias inspection (`reset_dispatched` row) | — | — | `=gesture.reservedAt` | `=writeTime` |
| Transformation of existing reset row | — | — | preserved | `=writeTime` |
| Later phase / redirect / auth-rebind transition | — | — | preserved | `=writeTime` |

#### C9.5.5 Record ordering, uniqueness, selection

| Array | Uniqueness | Order | Cap |
|---|---|---|---|
| `records` | exact `(uid,expectedTaskGenerationEpoch)`; recomputed `handleId` unique across array | `createdAt`, unsigned-UTF8 UID, numeric expected epoch | 4 |
| `legacyMigrations` | at most one row per UID; map UID must equal indexed identity | `createdAt`, unsigned-UTF8 UID | 4 |

| Rule | Exact statement |
|---|---|
| Duplicates | Duplicate `handleId`, duplicate UID, noncanonical order, or UID/index mismatch is structural corruption; no timestamp selects authority |
| Replaced sentence | Replaces frozen reset UID-only uniqueness sentence |
| Current-UID rows (load, signed-auth change, reserve) | 0 → reserve permitted; 1 → resume that row; ≥2 → blocked |
| Foreign UID / signed-out | Inert under retention/cap rules; never an epoch conflict |
| Reclassify | Owner reclassifies on every auth change |
| Conflict | Reserve writes no gesture/row, dispatches nothing, returns recovery surface; recoveries continue until ≤1 current-UID row |
| Recovered epochs | Representable, never chosen by timestamp or array order |
| Eviction | No active or receipt-bearing row evicted; completed rows removed only after idempotent applying completes |

#### C9.5.6 Auth normalization (load and every signed-auth change)

| Condition | Action |
|---|---|
| Signed-out, or `gesture.uid/authEpochUUID` mismatch | Atomically remove gesture; if it byte-matches a reserved-gesture `initiatingAuthority`, clear that member in same write; migration row and materialized/`reset_dispatched` rows intact |
| Mismatched bound gesture | Removed; never materialized under another auth tuple |
| Same-UID/same-epoch higher `credentialRevision` | May atomically rebase gesture and byte-matching reserved migration authority |
| Lower `credentialRevision` | Corruption; writes nothing |
| Crash/retry | Normalization repeats idempotently |
| Ordering | Runs before selection, materialization, reserve, bind, drive |

#### C9.5.7 Cross-member validity matrix (same UID)

| Gesture | Migration | Reset row | Verdict |
|---|---|---|---|
| reserved, byte-matches migration `reserved_gesture` initiating authority | present | — | legal |
| bound | present (any) | — | structural corruption |
| — | present, before APPLYING | present | legal only if row is exact `reset_dispatched` authority named by migration |
| — | APPLYING (no `initiatingAuthority`) | present | legal only if exact receipt-materialized/transformed row selected by migration outcome |
| present | absent | present | structural corruption; no reserve/bind/drive/materialization |
| any | any | rows for other UIDs | legal |
| every other combination | | | B3 corruption; zero selection/materialization/call |

`—` = member absent; `any` = member present or absent

#### C9.5.8 Reservation, handle, outcome unions

```text
Reservation          = {gestureId,gestureGeneration}            (from gesture that won the envelope CAS)
ResetOperationHandle = {uid,handleId}                            (never caller-supplied alias/epoch bytes)
handleId = "rho1_" + SHA-256(TaskCanonicalV1({uid,suggested_operation_id:row.suggestedOperationId,created_at:row.createdAt}))

ResetReserveOutcome    = binding(Reservation)
                       | operation(ResetOperationHandle)
                       | migrationPending(ResetMigrationPending)
                       | legacyCompleted(LegacyResetCompleted)
                       | legacyRetryRequired(LegacyResetRetryRequired)

ResetInvocationOutcome = completed(applicationId)
                       | migrationPending(ResetMigrationPending)
                       | legacyCompleted(LegacyResetCompleted)
                       | legacyRetryRequired(LegacyResetRetryRequired)

inflightReserve        = (authIdentity:{uid,authEpochUUID},credentialBaseline,authoritativeGestureId,task:Task<ResetReserveOutcome,Error>)
inflightBind           = (reservation:Reservation,authIdentity:{uid,authEpochUUID},credentialBaseline,task:Task<ResetOperationHandle,Error>)
inflightResetOperation = [ResetOperationHandle: (authIdentity:{uid,authEpochUUID},credentialBaseline,task:Task<ResetInvocationOutcome,Error>)]
```

| Rule | Exact statement |
|---|---|
| Handle stability | RESET_ACTIVE adoption may change expected epoch but preserves `suggestedOperationId`/`createdAt`, so handle is stable; differs for a later intentional reset |
| Errors | Registry-full, epoch-conflict, migration-full, blocked, auth, corruption throw only frozen exact errors |
| Slot lifecycle | Installed before first suspension; cleared in `defer` on every outcome |
| Join identity | UID + auth epoch; credential revision is monotonic CAS baseline |
| Join | Same identity and revision ≥ baseline joins (any proposed gesture ID); lower revision is corruption |
| Foreign caller | Different account / signed-out / different auth epoch waits for slot retirement, discards prior result/error, rereads auth, restarts |
| Post-task reread | Every joiner rereads signed auth; exposes outcome only when UID/epoch match and revision ≥ baseline |
| Losing ID | Neither persisted nor passed to bind |
| Consent | `RetakeAssessmentCoordinator.retake()` confirmation is explicit consent for that reserve; background/startup has none |

#### C9.5.9 `reserve(gestureId:) async throws -> ResetReserveOutcome`

| Step | Exact statement |
|---|---|
| 1 | Obtain signed-in auth before consulting in-memory slot |
| 2 | Inspect same-UID migration rows before loaded-bound materialization or any reset-row drive |
| 3 | Only with no same-UID migration: materialize loaded bound gesture; classify reset rows → `operation({uid,handleId:<recomputed>})` for one, `reset_epoch_conflict` blocked state for multiple |
| 4 | Only with neither: coalesced current-auth read; refuse without mutation when four-row cap occupied; atomically adopt exact current reservation or write one new `ResetGestureV1` before any legacy-reconciliation or server await |
| 5 | Return `binding(Reservation)` only after winning reserved gesture is durable |

| Sole blocked migration | Confirmed-reserve transition |
|---|---|
| `LEGACY_ALIAS_INVALID`, no initiating authority | Atomically adopt/write durable reserved gesture and attach exact `{kind:"reserved_gesture",gestureId,gestureGeneration,alias}`; no inspection/clear precedes |
| `LEGACY_ALIAS_INVALID`, authority byte-identical to stored reserved gesture | Resume inspection/clear under durable consent after crash |
| `LEGACY_ALIAS_INVALID`, authority present with no byte-identical gesture | Structural corruption |
| `LEGACY_RESET_CORRUPT` | Frozen same-request blocked→PREPARED Retry; retains/attaches only exact existing authority |
| `LEGACY_ALIAS_COLLISION_EXHAUSTED` | Adopt/validate exact durable gesture/authority, draw one new migration alias, `aliasCandidateOrdinal=1`, rewrite request bytes/hash, atomically enter PREPARED; never background/startup |
| `OPERATION_REUSED` | Never transitions |
| Any other blocked | `RESET_MIGRATION_BLOCKED` |
| More than one same-UID migration | Corruption |

| Rule | Exact statement |
|---|---|
| Precedence | After any narrow transition, no same-UID reset row is selected/bound/driven/reset/finalized until migration reaches frozen outcome |
| APPLYING boundary | Same auth-scoped reserve singleflight may return derived operation handle only after APPLYING materializes/transforms the row; before that only a migration outcome |
| Post-await CAS | Every post-await write CASes gesture identity, captured `gestureGeneration`, UID, auth epoch, current credential revision |
| Materialized record | Never discarded on UID/auth-epoch change |

#### C9.5.10 Migration outcome mapping (reserve and drive)

| Migration outcome | `ResetReserveOutcome` / `ResetInvocationOutcome` | Initiating authority |
|---|---|---|
| `upgraded` \| `phase2_active` | `operation(ResetOperationHandle)` (drive: requires materialized row, recomputes handle, continues reducer) | materialized |
| `not_dispatched` | `legacyRetryRequired` | retired |
| `finalized_compat` | `legacyCompleted` | retired on compatibility APPLYING |
| transient durable phase | `migrationPending` | retained |
| blocked (drive) | typed blocked error | — |
| promised row absent/multiple/mismatched (drive) | `RESET_OPERATION_STALE`, zero ordinary action | — |

| Rule | Exact statement |
|---|---|
| Retention | User-initiated migration retains initiating authority through RECEIPT unless auth normalization removes it |
| Second reset | No migration outcome binds or dispatches a second reset in the same invocation |
| Background | Background migration leaves `gesture` absent; the autonomous background caller may discard its internal result, but any concurrent or later user reserve joining it still maps through the nonoptional union |

#### C9.5.11 `bind(reservation: Reservation) async throws -> ResetOperationHandle`

| Rule | Exact statement |
|---|---|
| Entry | Read signed-in auth before consulting `inflightBind`; exact reservation + UID/epoch joins; revision ≥ baseline; lower is corruption |
| Stale | Same-ID/wrong-generation, different, unknown, or consumed reservation → `RESET_GESTURE_STALE` |
| Snapshot | One authenticated `{uid,authEpochUUID,credentialRevision,taskGenerationEpoch}` |
| Write 1 | CAS reserved gesture, reservation generation, UID, auth epoch; rebase newer same-epoch revision; `reserved→bound` storing `expectedEpoch`, `boundAt` |
| Write 2 (no intervening await) | CAS exact bound tuple; create UID/epoch `prepared` row from stored alias/epoch/auth; remove gesture |
| Return | Row-key handle only after prepared row durable |
| Crash between writes | Startup/exact retry materializes loaded bound gesture without rereading epoch |
| Late consumed call | Stale; never recaptures root epoch or mints another alias |
| Migration at entry or post-await CAS | Writes nothing; throws `RESET_GESTURE_STALE`; only reserve may resume/map |
| Auth change | UID/auth-epoch change writes nothing; no later caller receives prior account's handle |

#### C9.5.12 `drive(handle:callbacks:)`

| Rule | Exact statement |
|---|---|
| Entry | Fresh signed-in auth with `uid == handle.uid` before lookup/install |
| Join | Exact handle + UID/epoch, revision ≥ baseline; lower is corruption; mismatch waits, discards, rereads, restarts |
| Row requirement | No same-UID migration → exactly one row for `handle.uid`, handle ID recomputed byte-for-byte |
| Stale | Absent row, multiple same-UID rows, or handle mismatch → `RESET_OPERATION_STALE`, zero write/dispatch |
| Migration precedence | At entry and after every reducer suspension, join/resume per-UID migration singleflight; no ordinary reset/finalize/cleanup/callback until exhaustive result |
| Winner | Revalidates signed auth after every suspension and before every server call, protected callback, return |
| Drift | Different UID/epoch/signed-out preserves durable phase, no later call/callback, returns frozen auth-pending/error branch; higher same-epoch revision rebases and continues |
| Callbacks | Winner owns first callback bundle; joiners receive outcome only, never invoke their callbacks |
| Relaunch | In-memory singleflight lost; durable phase selects sole recovery action |

#### C9.5.13 Reset phase table

| Phase | Only recovery action |
|---|---|
| `prepared` | `retry_reset` — dispatch same reset request |
| `reset_dispatched` | `retry_reset` — retry same request |
| `reset_receipt/deleting` | `resume_server_deletion` |
| `reset_receipt/awaiting_local_reset` | `run_local_cleanup` — protected local cleanup |
| `finalize_dispatched` | `retry_finalize` |
| `final_receipt` | `apply_final` — enter applying |
| `applying` | `apply_final` — resume idempotent state-derived apply |
| receipt disagreement / corrupt envelope | B3 reconciliation; never dispatch |

| Transition | Support |
|---|---|
| `reset_receipt/awaiting_local_reset` → `final_receipt` | Exact `committed` inspection; one new atomic durable direct edge; final receipt stored |
| `final_receipt` → `applying` | Envelope transition committed by the reducer invocation that durably stored the first exact `reset_final` receipt with `replayed:false` |
| `applying` → row removed | Only after idempotent applying completes |
| every other edge | — |

#### C9.5.14 Generation-fenced local cleanup

```text
ResetLocalCleanupAuthorityV1 = {schemaVersion:1,accountUid,operationId,requestFingerprint,
  expectedTaskGenerationEpoch,taskGenerationEpoch,activeMoveEventId,deletedCount,
  deletedCounts:{tasks,notificationIntents,taskDeadlineEvidence,confirmationSnapshots}}
```

| Rule | Exact statement |
|---|---|
| Construction | Only `ResetOperationRegistry`, only from validated read-only `inspectCommittedOperation/RESET` with outcome `pending` and progress receipt `awaiting_local_reset`; ephemeral, nonpersisted |
| Equality | Inspection validated operation-record ↔ root-marker ↔ progress-receipt equality; every `reset_progress` member equals receipt byte-for-byte; `operationId`/`requestFingerprint` from validated row/inspection identity |
| Excluded | Marker state/cursor/lease/timestamp members not in authority |
| Retention | No view/coordinator/callback/caller constructs or retains authority across callbacks |

| Inspection result (reducer revalidates signed auth + exact registry row, then read-only RESET inspection, before each of three destructive callbacks and before finalize) | Action |
|---|---|
| exact `pending/awaiting_local_reset` | Derive fresh authority; invoke only next callback |
| exact `committed` | Atomic edge `reset_receipt/awaiting_local_reset → final_receipt`; store final receipt; skip remaining callbacks and finalize; replay application; zero notification |
| `absent`, malformed/OPERATION_REUSED, identity drift, active op with no exact marker, non-awaiting pending | Block, zero callback |
| Transport ambiguity | Preserve phase, zero callback |
| After callback error (incl. permission denial, contention) | Re-inspect: committed → adopt final, skip forever; byte-identical pending → retain phase, permit Retry; else block |
| `recoverEpoch(...,action:run_local_cleanup)` | Identical reducer, no alternate closure |

| Root `taskReset` marker predicate (each candidate transaction) | Exact |
|---|---|
| state | `awaiting_local_reset` |
| `targetIndex` | `4` |
| `pageAfterPath`, lease | absent |
| timestamps | concrete Firestore `createdAt`, `updatedAt`, `awaitingLocalResetAt`; `createdAt <= awaitingLocalResetAt <= updatedAt` |
| identity | account/operation/fingerprint, expected/result epochs, move-event ID, deleted total, deleted-count projection byte-equal to authority |
| stored epoch | `< authority.taskGenerationEpoch` deletable; `>=` preserved |
| missing stamp | legacy zero only for `expectedTaskGenerationEpoch == 0 && taskGenerationEpoch == 1`; else preserve, emit `RESET_LOCAL_GENERATION_INVALID`, block finalization |
| root dose deletion | changes only `dailyDose`; preserves marker |
| timestamp validation | From the marker itself; never compared to a differently shaped authority |
| marker change / absent / different op / missing, surplus, or wrong state-index-cursor-lease-time-order-identity-count content | retry + revalidate / write nothing / write nothing |
| Rules | Enforce marker shape/state/index/cursor/lease/time-order and generation relation; do not claim caller operation identity |

#### C9.5.15 Root epoch and stamps

| Rule | Exact statement |
|---|---|
| Effective root epoch | absent → 0; safe integer `0...9,007,199,254,740,991` → value; malformed → no write |
| Stamped values | `users/{uid}/user_assessments/{assessmentId}`, `userKnowledge/{uid}`, `users/{uid}.dailyDose` carry immutable safe integer `task_generation_epoch` = effective root epoch; created/updated only while `taskReset` absent |
| Daily dose map | `{schema_version:1,task_generation_epoch,date,taskIds}` |
| `AssessmentDataManager.saveAssessment()` | Reads root and creates auto-ID assessment in one transaction |
| `UserKnowledgeService.merge()` | Transactional root read; requires reset absence; preserves matching stamp or stamps current epoch; rejects malformed/different epoch |
| Unstamped assessment | Updatable only at root epoch exactly 0 with `taskReset` absent, preserving stamp absence; root epoch >0 denies; creates always stamp |
| Unstamped `userKnowledge` | Upgradable to stamp 0 at root epoch 0 in merge; later epoch rejects |
| Unstamped root dailyDose | Readable only at root epoch 0; next freeze replaces with stamped epoch-zero schema; later epoch cleanup-only under 0→1 bridge |
| Deletes | Every assessment delete / knowledge cleanup / `DailyDoseEngine.resetForRetake(authority:)` is one root-first transaction |

#### C9.5.16 `DailyDoseLocalStore`

```text
key   = peezy.{uid}.dailyDose.v2          (canonical-JSON Data, cap 1,024 bytes)
value = {schemaVersion:1,taskGenerationEpoch,revision,completedCount,lastDate,firstLaunchDate}
taskGenerationEpoch, revision : safe nonnegative
completedCount                : 0...1,000,000
lastDate, firstLaunchDate     : null | exact YYYY-MM-DD
```

| Rule | Exact statement |
|---|---|
| Owner | Sole process-wide actor inside `DailyDoseEngine.swift`; all `PeezyHomeViewModel` dose reads/writes go through it |
| Mutation | CAS exact epoch/revision; increments revision; unknown/surplus/malformed blocks and is never removed |
| Cleanup at result epoch `r` | older → exact empty epoch-r, revision+1 (`cleaned`); equal → preserve (`preserved`); newer → preserve and report drift (`localDoseDrift`); absent → empty epoch-r floor (`cleaned`); malformed → preserve every byte and every legacy key, block the reset's dose cleanup (`localDoseMalformed`), and mark the store for durable-store recovery (S4 classifies and presents it); a parse failure never destroys the last copy of user state |
| 0→1 bridge | Write v2 floor first, then remove all three legacy keys; crash with both → v2 authority |
| Later reset | Never infers a legacy key epoch; removes the three legacy keys only after an accepted cleanup transition (`cleaned`/`preserved`), never over a malformed or drifted store |
| Account deletion | Removes v2 key plus all legacy keys |

#### C9.5.17 `.retakeAssessment` notification

| Rule | Exact statement |
|---|---|
| Semantics | At-most-once, not exactly-once |
| Poster | Only the reducer invocation that stored first `reset_final` with `replayed:false` and commits `final_receipt→applying`; posts after APPLYING durability, at most once per process |
| Never posts | `replayed:true`; row loaded in `final_receipt`; row loaded in `applying` |
| Ordering | Never before final-receipt durability; no crash/replay/relaunch duplicates |

#### C9.5.18 Local errors and epoch-conflict recovery

```text
{schemaVersion:1,reason:"RESET_REGISTRY_FULL",capacity:4,occupants:[{uid,expectedTaskGenerationEpoch,phase,recoveryAction}]}
{schemaVersion:1,reason:"RESET_EPOCH_CONFLICT",uid,occupants:[{expectedTaskGenerationEpoch,phase,recoveryAction}]}
{schemaVersion:1,reason:"RESET_GESTURE_STALE",gestureId,gestureGeneration}
{schemaVersion:1,reason:"RESET_OPERATION_STALE",uid,handleId}
{schemaVersion:1,reason:"RECOVERY_ACTION_UNAVAILABLE",store:"reset"}
{schemaVersion:1,reason:"LEGACY_RESET_MIGRATION_REGISTRY_FULL",capacity:4,occupants:[{uid,phase,recoveryAction}]}
localDoseMalformed                       // C9.5.16: malformed v2 dose bytes; every byte and legacy key preserved; the reset's dose cleanup is blocked
localDoseDrift(currentEpoch)             // C9.5.16: the local dose store is at a newer epoch than the result epoch; preserved and reported

recoveryStateDigest = lowercase SHA-256(TaskCanonicalV1({schemaVersion:1,store:"reset",baseState:"reset_epoch_conflict",
  uid,authEpochUUID,credentialRevision,envelopeGeneration,envelopeSHA256,
  actionableExpectedTaskGenerationEpoch,occupants:[<complete ordered options>]}))
option = {expectedTaskGenerationEpoch,phase,recoveryAction}
recoverEpoch(recoveryStateDigest:expectedTaskGenerationEpoch:expectedPhase:action:) async -> RecoveryResult
```

| Reset phase | `recoveryAction` |
|---|---|
| `prepared`, `reset_dispatched` | `retry_reset` |
| `reset_receipt/deleting` | `resume_server_deletion` |
| `reset_receipt/awaiting_local_reset` | `run_local_cleanup` |
| `finalize_dispatched` | `retry_finalize` |
| `final_receipt`, `applying` | `apply_final` |

| Migration phase | `recoveryAction` |
|---|---|
| prepared, dispatched | `retry` |
| receipt, applying | `apply` |
| blocked | `resolve_blocked` |

| Rule | Exact statement |
|---|---|
| `RESET_REGISTRY_FULL` | Only when four slots occupied and current UID has zero rows; order `createdAt`, unsigned-UTF8 UID, numeric epoch; no bytes changed |
| `RESET_EPOCH_CONFLICT` | Every current-UID row, order `createdAt`, numeric epoch; no bytes changed; `phase` is stored six-phase vocabulary |
| Blocked state | ≥2 valid current-UID rows → `StartupBarrier.reset = blocked(reset_epoch_conflict)`; forbids selection/binding/drive/readiness; signed-out/foreign never enter |
| `actionableExpectedTaskGenerationEpoch` | Required; numerically smallest occupant epoch; later occupants displayed but disabled until every smaller-epoch row is conclusively removed/applied and the store is reclassified |
| Snapshot privacy | UID/auth private; public snapshot carries no account |
| Wiring | S1 `ResetEpochConflictRecovering`; S4 renders options, enables only actionable epoch; S7 wires `RetakeAssessmentCoordinator` protected callback bundle |
| Revalidation | Before each call and after every await: signed-auth triple, envelope generation/hash, ordered options, minimum epoch, selected row identity/phase/action, digest; drift → fresh blocked snapshot |
| Stale / absent / nonminimum (later-epoch) option | `RECOVERY_ACTION_UNAVAILABLE`, zero callback/server/write |
| Action | Only that row's ordinary reducer branch; store blocked throughout; completion runs full classifier → next-minimum conflict, `ready`, or higher-priority `BlockedSnapshot`; never fabricates conflict when another scene made store ready; no action touches another occupant; no callback runs outside the selected validated reducer |
| In-flight key | Complete digest + selected option; identical call coalesces; different call → `RECOVERY_BUSY` |
| Migration full | Before any migration row create with four other-UID rows; no eviction; user reserve retains durable gesture and surfaces recovery; background returns directly; occupants in creation-time then UID order |
| Stale errors | Never Firebase details; change no durable byte |

#### C9.5.19 Caps

| Member | Cap (canonical bytes) |
|---|---|
| active reset row | 10,240 |
| migration row | 10,240 |
| gesture | 2,048 |
| payload/outer metadata | 4,096 |
| server receipt per row | at most one, 8,192 |
| algebraic bound | `4*10,240 + 4*10,240 + 2,048 + 4,096 = 88,064` |
| envelope | 88,064 + B3 190-byte reserve ≤ 131,072 |

| Rule | Exact statement |
|---|---|
| Reachable maximum | Independently generated and round-tripped; headroom to algebraic bound proven |
| Exact/+1 | Only schema-reachable encodings; otherwise every field/count cap +1 without padding/surplus |
| Outer cap | Defense-in-depth, not independently reachable for reset |
| Final receipt | Writing it drops obsolete progress bytes atomically |
| Member-cap +1 | Preserves prior file |

#### C9.5.20 Superseded stored shapes (D18)

```text
SupersededContractV2 (fresh writes only) =
{schema_version:2,terminal_kind:"superseded",superseded_by,
 superseded_at,visible_status_copy:"Replaced",
 visible_status_detail:{kind:"DATE",at}}

Legacy v1 (decoder-only) =
{schema_version:1,terminal_kind:"superseded",superseded_by,visible_status_copy:"Replaced by an updated task"}

Malformed fallback = malformedPresent
```

| Rule | Exact statement |
|---|---|
| v2 `superseded_by` | Exactly replacement `task_instance_id` under H54; never a task document ID |
| v2 timestamps | `superseded_at` = confirming transaction's one concrete Firestore Timestamp; `visible_status_detail.at` same value |
| v2 malformed | Any hybrid/mismatch/missing/surplus; fresh v1/schema-less writes reject |
| v1 `superseded_by` | Committed nonblank task-document-ID grammar; opaque display data; never resolves as instance link |
| v1 malformed | Wrong copy/type, invalid ID, missing, surplus, schema-less, hybrid → `malformedPresent` |
| v1 fixture | One byte-exact fixture from committed mapper |

#### C9.5.21 Formatter and copy (D19)

```text
formatter: Gregorian calendar, Locale.autoupdatingCurrent, TimeZone.autoupdatingCurrent, .medium date style, no time
fresh v2 primary copy : "Replaced — {formatter(visible_status_detail.at)}"   (U+2014, one ASCII space each side, no suffix)
legacy v1 copy        : visible_status_copy verbatim (no separator, no date)
```

#### C9.5.22 Undo (D20)

| Rule | Exact statement |
|---|---|
| Clock | Every H54 attempt uses retry-scoped concrete `server_write_time` (§4.1) for authored timestamps and deadline comparisons; transaction retry obtains new injected-clock value |
| Exists | Exactly in first CF while unused and `server_write_time <= first_confirmation_undo_until` |
| Survives | Transport failure; TRIGGER_INVALID (frozen read-only restoration preflight/selector, retries) |
| Disappears | Success; `server_write_time > first_confirmation_undo_until`; authoritative instance/cycle/state change |
| Stale instance without descriptor | Dismisses |
| Never decides | Client/device wall time; `FieldValue.serverTimestamp()` |

#### C9.5.23 History presentation (D21)

| Action | Title |
|---|---|
| `supersede` | `Plan update started` |
| `replacement_outcome` | `Updated task outcome recorded` |
| `confirm_amendment` | `Plan update confirmed` |
| `undo_confirmation` | `Confirmation undone` |
| `reopen` | `Original task reopened` |

```text
ordinary line : "{title} · {formatter(occurred_at)}"
rollup        : firstDate = formatter(first_at); lastDate = formatter(last_at)
                firstDate == lastDate (byte-equal) → "Earlier plan changes ({count}) · {firstDate}"
                otherwise                          → "Earlier plan changes ({count}) · {firstDate}–{lastDate}"
```

| Rule | Exact statement |
|---|---|
| Gate | Applies only after exact policy-bearing `planChangeHistory` union validates |
| Legacy H54 | Policy-absent rows keep committed bytes/behavior (incl. `confirm\|reconfirm`, `at`); never rendered as policy-bearing rows |
| Order | Stored array in append order; present ordinary rows in exact reverse; exclude rollup from reversal; render sole rollup once as final row |
| Identity | Never render request/operation/submission/snapshot/evidence/task/instance/digest identity |

#### C9.5.x Named falsifiers

| Test file | Named test / fixture family |
|---|---|
| `functions/tests/taskPlan.test.js` | D12/D13: vary each revision independently/together; preserve live handoff/tail; drift every immutable branch member; no reuse/reconfirmation branch reads a revision for identity |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | Exact-byte time fixtures: new attachment, crash-resume attachment, direct phase2-active adoption |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | Auth normalization: reserved alone, reserved+migration, crash-loaded bound × A→signed-out, A→B, A→new-A-epoch; zero bind/dispatch/materialization |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | Reserve singleflight: hold A task across B / new A epoch; same-epoch credential refresh rebases once, same outcome to both |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | Bind singleflight: A completed-not-cleared bind across A→B, A→new-A-epoch; refresh during epoch await creates PREPARED once |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | Migration precedence: held Reservation and preexisting handle vs PREPARED, DISPATCHED, RECEIPT, APPLYING, BLOCKED at every suspension |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | Drive: hold A at every suspension across B / new auth epoch; stale winner makes no call/callback; same-epoch rebase continues |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | Every `ResetReserveOutcome`/`ResetInvocationOutcome`; concurrent reserve/bind; two scenes proposing different IDs during reserve and during bind, both receiving/using persisted winner Reservation; different/stale IDs not carrying that winner; transient failure/retry; retry-before-commit; lost response; handle stability across every fresh/transition branch; wrong generation; stale/absent handle; mutated token; outer-generation advance; equal/backward clock, clock failure; kill before/after reserved→bound and bound→prepared; loaded-bound zero epoch reread; two joiners one callback sequence; relaunch after singleflight loss; crash before/after migration dispatch/receipt/applying: upgraded/phase2_active materialize once, not_dispatched retires and requires new gesture, finalized_compat never starts second reset; coexistence with each migration phase; recovered/background migration beside bound gesture; every allowed/forbidden cross-member combination; background migration no gesture; no dispatch before prepared durability; every six-phase branch; every occupant/recoveryAction branch; four rows plus fifth UID; two and four same-UID rows → ordered `RESET_EPOCH_CONFLICT`; duplicate/permuted/UID-mismatched/equal-time migration order; four migration rows plus fifth user/background/bound-gesture attempt; account switch; no eviction; cap boundaries; winner cleanup before loser continuation → one epoch rotation |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | Epoch conflict: inverse-createdAt rows; later-epoch attempt unavailable/zero callback; conflict plus receipt mismatch; auth switch to foreign conflict; another scene resolves store during await; A→B and signed-in→signed-out with two A rows inert |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | Generation fence: device A paused before each inspection/callback and after query while B finalizes at epoch `r`; B reset `r→r+1`; assessment/knowledge/dose × older/equal/newer, unstamped 0→1, unstamped later, malformed, absent, marker absent, wrong operation, marker change; callback error then committed inspection; direct-edge crash before/after durability; pre-first-reset update/freeze/stamp, cutover, post-first-reset denial; every missing/surplus marker member; each marker timestamp/order boundary; marker drift before every candidate commit; A zero-deletes B's epoch-r bytes; under B r→r+1, A rejects B's marker, B may delete epoch-r, neither deletes epoch-r+1 |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | Daily-dose local: two scenes; stale-writer epoch/revision CAS; process reload; empty floor; bridge order/crash; malformed preservation; equal/newer preservation |
| `functions/rules-tests/firestoreRules.test.js` | Reject fresh missing/stale stamps, stamp change/removal, cleanup outside awaiting, cleanup of current/newer bytes, root cleanup changing anything except `dailyDose` |
| `Peezy 4.0Tests/TaskPlanDispositionTests.swift` | D15 deterministic UID/epoch point path, no alias collection scan |
| `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | reset dose cleanup over malformed and newer local bytes: `localDoseMalformed` / `localDoseDrift` thrown, v2 bytes and every legacy key preserved (S3-CD9) |
| `Peezy 4.0Tests/TaskSupersessionTests.swift` | D18 byte-exact v1 fixture; every malformed shape → `malformedPresent`; D19 golden strings with injected values incl. locale/time-zone day rollover; D20 undo eligibility; D21 golden POSIX/UTC: same-local-day/different-time, different-day, all branches, order |

### C9.6 Evidence roots, pointer registries, and H54 capacity escrow (D25–D27)

#### C9.6.1 Policy-bearing ordinary plan-history row (D25)

```text
{schema_version:1,revision,
 action:"supersede"|"replacement_outcome"|"confirm_amendment"|
        "undo_confirmation"|"reopen",
 request_identity:{kind:"OPERATION",operation_id}|
                  {kind:"WORKFLOW_SUBMISSION",submission_token},
 original_task_instance_id,replacement_task_instance_id?,snapshot_record_id,
 evidence_refs:[{task_document_id,task_instance_id,evidence_id}],occurred_at}
```

| Rule | Exact statement |
|---|---|
| `evidence_refs` presence | always present |
| `evidence_refs` order | stable creation order |
| `evidence_refs` uniqueness | unique complete triples |
| `evidence_refs` targets | only the row's original or its one replacement; at most one non-original instance per row |
| Policy-bearing `evidence_ids` | forbidden (no shipped writer) |
| Policy-absent legacy H54 rows | byte-compatible, unchanged |
| Rollup row | forbids refs; digests the new complete ordinary-row bytes |

#### C9.6.2 `foreignRoots` replacement-only root (D25)

```text
foreignRoots:{schema_version:1,original_task_document_id,
 original_task_instance_id,plan_change_revision,
 counts:{<evidence_id>:<positive_safe_integer>}}
```

| Rule | Exact statement |
|---|---|
| `counts` keys | 1…128 `ev1_` keys, each present in that replacement's evidence |
| `counts` values | 1…17 |
| `counts` order | canonical map order |
| Complete cap | 16,384 canonical bytes |
| Empty map | absent rather than empty |
| Placement | replacement task only; forbidden on original/unrelated tasks |
| Count formula for replacement evidence `e` | retained confirmation attempts with `source.evidence_id == e` + retained non-rollup history refs naming that replacement/`e` |
| Confirmation snapshot source | validation mirror of its one currently retained attempt; same logical claim; adds zero count |
| Unreferenced/old snapshot source | immutable audit bytes; not a live pointer, resolver input, or root |
| `confirmation_evidence_id` | original-owned |
| `replacement_evidence_copy.evidence_id` | verified copied data; never pointer/root/resolver/count |
| Snapshot exclusion | excluded from semantic/rollback snapshots; included in whole-task/budget |
| Writers | preserved by writers; Admin SDK transactions own all mutations |
| Index | wildcard-index-exempt |
| Rules | deny every client create/update/delete adding, changing, or removing `foreignRoots`; deny every other user's write |
| Swift exact-member decoder | validates the raw map; never product authority; exposed through neither product model nor UI |

#### C9.6.3 Pointer/root transaction order (D25)

- build prospective history and its fixed rollup
- derive original/replacement/cross claims
- read all affected peers
- recompute complete foreign counts
- build `R_original` from normal roots, original-owned refs, and confirmation IDs
- build `R_replacement` from normal roots plus foreign-root keys
- follow same-instance dependency closure
- run retention, D27, and budget
- commit all pointer/root/count changes atomically

| Rule | Exact statement |
|---|---|
| Touch set | one appended row / one rolled row touches at most original, current replacement, and one older replacement |
| Graph authority failure | malformed, missing, or mismatched peer, link, instance, revision, evidence identity/content, count content, or surplus graph member → `PLAN_GRAPH_CHANGED`, zero writes |
| Capacity failure | ordinary component overflow, escrow shortfall, actual Firestore-write-budget overflow → capacity errors and precedence in C9.6.14 (not `PLAN_GRAPH_CHANGED`) |
| Rollup decrement | only in the same transaction that removes the row |
| Reset equality break | permitted only while root fence blocks all writers and physical deletion proceeds |
| Reset finalize | requires all tasks/snapshots absent |

#### C9.6.4 `EVIDENCE_POINTER_PATHS_V1` (literal manual registry, not schema discovery) (D26)

```text
# same-instance live roots
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

# same-instance policy-absent legacy roots
planChangeHistory[policy-absent legacy ordinary].evidence_ids[]

# same-instance typed evidence-record edges, only in kind-permitted shapes
evidence_records[].source_ref when exact ev1_
evidence_records[].facts.source_evidence_id
evidence_records[].facts.trigger_evidence_id
evidence_records[].facts.opened_evidence_id
evidence_records[].facts.return_evidence_id
evidence_records[].facts.entry_evidence_id

# cross-instance H54 pointers
planChangeCycle.confirmation_attempts[].source.evidence_id
taskPlanOperations.CONFIRMATION_SNAPSHOT.source.evidence_id only while its
  snapshot_record_id is referenced by current planChangeCycle.confirmation_attempts[];
  this mirrors that attempt and adds zero foreignRoots count
planChangeHistory[ordinary].evidence_refs[].evidence_id when replacement-owned
```

#### C9.6.5 `EVIDENCE_NON_POINTER_PATHS_V1` (literal exclusion registry) (D26)

```text
# notification/wake linkage, never evidence lookup
wakeEvidence.intent_id
notificationIntents[TASK_RESUME].cause.wake_evidence_id

# handoff display/snapshot/operation identity
activeHandoff.prior_dynamic_snapshot_id
activeHandoff.adapter_operation_id
activeHandoff.restoration.operation_id
activeHandoff.presentation_snapshot.source_refs[]
taskInteractionState.pending_handoff.selection_operation_id

# H54 operation/snapshot/submission identity
planChangeCycle.pre_supersede_operation_id
planChangeCycle.confirmation_attempts[].snapshot_record_id
planChangeCycle.confirmation_attempts[].source.receipt_identity.operation_id
planChangeCycle.confirmation_attempts[].source.receipt_identity.submission_token
planChangeHistory[ordinary].request_identity.operation_id
planChangeHistory[ordinary].request_identity.submission_token
planChangeHistory[ordinary].snapshot_record_id
interactionHistory[ordinary].operation_id

# producer event/high-water identity outside task evidence_records
events.source_evidence_id
eventState.source_evidence_id
wakeEvidence.cause.event_high_water.source_evidence_id

# copied/self-contained or permanently empty audit/display values
evidence_records[].id # record identity validated from its preimage, never an edge
evidence_records[AMENDMENT_CONFIRMATION].facts.replacement_evidence_copy.evidence_id
users/{uid}/research/{taskId}.brief.sections[].items[].applicability_evidence_ids[] # required []
taskPlanOperations.CONFIRMATION_SNAPSHOT.source.evidence_id when no current
  planChangeCycle.confirmation_attempts[] references its snapshot_record_id
```

#### C9.6.6 Registry rules (D26)

| Rule | Exact statement |
|---|---|
| Traversal set | only paths in `EVIDENCE_POINTER_PATHS_V1` are traversed |
| Unlisted runtime path | ignored even when its string is exactly `ev1_`-shaped |
| Exclusion registry role | required regression-sentinel set, not an alternative traversal |
| Exclusion-path grammar | each remains subject to its own frozen grammar/prefix; `ev1_` spelling permitted only where that schema permits it; never triggers lookup, retention, dependency closure, resolver access, or `foreignRoots` count |
| Snapshot-embedded evidence | self-contained |
| Umbrella nouns | no "operation ID" / "presentation source" substitutes for either literal table |
| Home | `functions/taskInteraction.js` contains both exact tables |
| Tests | exercise entries; do not claim discovery |
| Registry test scope | enumerates every exact persisted task-plan operation request/response and workflow-submission response shape after decoding only fields the stored schema itself exposes; any evidence-ID-valued member absent from both tables fails |
| `requestCanonicalJSON` | immutable opaque string; never traversed as a hidden object |
| Review coupling | any persisted field capable of `ev1_` addition/removal/rename/ownership change updates the applicable registry, ownership/root rule, D27 calculator, and fixture in the same review |
| Unknown runtime fields | rejected by exact-member validators |

#### C9.6.7 `evidence_reservation` record (D27)

```text
evidence_reservation:{
 schema_version:1,reservation_id,task_generation_epoch,plan_change_revision,
 original_task_document_id,original_task_instance_id,
 replacement_task_document_id,replacement_task_instance_id,
 holder_role:"ORIGINAL"|"REPLACEMENT",
 phase:"first_pa"|"first_pc"|"first_cf_undoable"|"second_pa"|"second_pc",
 remaining:{evidence_record_count,evidence_record_bytes,
            foreign_root_entry_count,foreign_root_bytes,
            interaction_history_bytes,task_interaction_state_bytes,
            semantic_snapshot_bytes,task_document_bytes},
 release_after?
}
```

```text
reservation_id = "pcr1_" + first40(SHA-256(TaskCanonicalV1(
  {uid,task_generation_epoch,original_task_instance_id,
   replacement_task_instance_id,plan_change_revision})))
```

| Rule | Exact statement |
|---|---|
| Copies | one on original, one on replacement, written in the first-PA transaction of external supersede |
| Shared across copies | identity, phase, `release_after` |
| Differing across copies | `holder_role`, holder-specific `remaining` |
| Numbers | safe nonnegative |
| `release_after` | exists only in `first_cf_undoable`; equals first undo deadline |
| Complete map cap | ≤16,384 canonical bytes |
| Index | wildcard-exempt |
| Snapshots | excluded from semantic/rollback snapshots; included in creation hash and actual whole-task/budget |
| Swift | validates exact members; never product authority; exposed through neither product model nor UI |
| Rules | deny every client create/update/delete adding, changing, or removing `evidence_reservation`; deny every other user's write |
| Mutation owner | Admin SDK transactions only |
| Reinsertion prefix | exact 24-byte canonical member prefix `,"evidence_reservation":` |
| `M` | exhaustive maximum `TaskCanonicalV1` byte length of a schema-valid reservation map over every reachable holder/phase and maximum legal identity; production and independent oracle prove `M <= 16,384` |
| Admitted reserved task bound | `638,952 + 24 + M <= 655,360`; `M` alters neither component limit |
| Omitted-member ceiling | literal 638,952; never recomputed from a reachable map |
| Mandatory checks | omitted-member ceiling and actual complete-task cap 655,360 both checked |

#### C9.6.8 Exact cap vector (the eight escrow components; `remaining` has exactly these members)

| Component | Limit |
|---|---:|
| evidence records | 128 |
| evidence canonical bytes | 131,072 |
| foreign-root entries | 128 |
| foreign-root canonical bytes | 16,384 |
| interaction-history canonical bytes | 65,536 |
| taskInteractionState canonical bytes | 196,608 |
| semantic snapshot canonical bytes | 262,144 |
| task bytes with the `evidence_reservation` member wholly omitted | 638,952 |

| Other limit | Value |
|---|---:|
| reservation map (defensive; C9.6.7) | 16,384 |
| actual complete task (independent mandatory check; C9.6.7) | 655,360 |
| maximum `FirestoreWriteBudgetV1` over every remaining transition (C9.6.11) | 8,388,608 |
| post-retention ordinary interaction-history rows (rollup precondition; C9.6.9) | 32 |
| post-retention ordinary plan-history rows (rollup precondition; C9.6.9) | 15 |

#### C9.6.9 Remaining transition tree and `remaining_i`

```text
first_pa: first outcome -> first confirm -> expire
        | first outcome -> first confirm -> undo -> second outcome -> second confirm
        | initial-PA reopen
first_pc: first confirm -> expire
        | first confirm -> undo -> second outcome -> second confirm
first_cf_undoable: expire | undo -> second outcome -> second confirm
second_pa: second outcome -> second confirm
second_pc: second confirm
```

```text
remaining_i = max over reachable S in F(p) of max(0, U_i(S) - U_i(T))
```

| Rule | Exact statement |
|---|---|
| `U_i` | exact prospective use for holder `T`, phase `p`, component `i`, after mandatory retention |
| Reservation exclusion | reservation bytes excluded only for the final task-byte component |
| Rollup order | mandatory history rollup before every sizing step |
| Row count | not an escrow component (bounded by 32 / 15 post-retention rows) |
| Producers | each mutually exclusive handoff/wait/workflow producer sized with its exact frozen constructor separately; incompatible maxima never unioned |
| Included in `U_i(S)` | history/evidence rollups, D25 roots, restoration branches, both roles, snapshot/operation, terminal children, copies |
| Implementation | shared production and independent oracle implement the literal tree/constructors, not a schema registry |

#### C9.6.10 `EVIDENCE_RESERVATION_WRITERS_V1` (literal fresh-task-mutation registry)

```text
functions/taskDisposition.js =
 [assertAlreadyHandled,markNotApplicable:none,deferTask,markSelfHandling,
  markWaitingOnExternal,beginHandoff,acknowledgeHandoffOpened,
  recordHandoffReturned,continueHandoff,cancelHandoff,
  resolveHandoff:mutating,resolveWaiting:mutating,
  initializeFlowProgress,continueFlowProgress,clearFlowProgress,
  replaceTaskNotes,replaceTaskQuotes,
  mutateLegacyTask:applicable,persistLegacyPackingPlan:applicable]
functions/taskPlan.js =
 [supersede,confirmAmendment,undoConfirmation,reopen,
  resetAllTasks:root-fenced-delete-exception]
functions/getWorkflowQualifying.js =
 [submitWorkflowAnswers:COMPLETE,submitWorkflowAnswers:WAIT,
  submitWorkflowAnswers:WAIT_DISPLAY_FALLBACK]
functions/dispositionTriggers.js =
 [date_snoozed_deferred,event_snoozed_deferred,
  date_inprogress_user_action,event_inprogress_user_action,
  date_matching_waiting,event_matching_waiting,threshold_attention]
```

#### C9.6.11 Writer admission

| Writer | Condition | Result |
|---|---|---|
| any listed committing branch | before first write: shared admission/recompute seam reads both linked tasks and both reservation copies; builds complete two-holder prospective state; in C9.6.8 exact-cap-vector order `U_i(post) + remaining_i(post) <= limit_i` for every `i` | admitted; both copies atomically recomputed and replaced from that state and the same reachable tree, even when ordinary data changes on only one holder; both reservation writes charged in actual and every future `FirestoreWriteBudgetV1` |
| any listed committing branch | some component `U_i(post) + remaining_i(post) > limit_i` | capacity error per C9.6.14 (ordinary component overflow → `EVIDENCE_UNKNOWN`/`TASK_CAP_EXCEEDED`; escrow shortfall → `EVIDENCE_CAP_RESERVED`); zero writes |
| any listed committing branch | maximum `FirestoreWriteBudgetV1` over every remaining transition (original/replacement, at most one older replacement from rollup, ops/snapshots/children/index deltas) `> 8,388,608` | refused |
| any listed committing branch | actual transition | exact charge checked separately |
| any listed committing branch | present use decreases while reachable maximum unchanged | stored `remaining` increases accordingly |
| `markNotApplicable:present`, `markNotApplicable:unknown` | zero task mutation | bypass; neither copy changed |
| `resolveHandoff`, `resolveWaiting` descriptor-only branches | zero task mutation | bypass; neither copy changed |
| exact operation replay | replayed | bypass; neither copy changed |
| every other zero-task-mutation response | zero task mutation | bypass; neither copy changed |
| `mutateLegacyTask:applicable`, `persistLegacyPackingPlan:applicable` | target set contains either reservation holder | in registry; admission applies |
| `mutateLegacyTask:applicable`, `persistLegacyPackingPlan:applicable` | target set contains no reservation holder | not in registry for that call |
| shared spawn / terminal-child writes | invoked by a registered transaction | charged to the invoking registered transaction, never an unregistered child helper |
| `resetAllTasks:root-fenced-delete-exception` | root-fenced one-task deletion | removes one holder/copy; no ordinary admission mutation |
| new task writer/action | not in registry, shared-seam coverage, oracle, and fixture in one reviewed change | fails the gate |

#### C9.6.12 Reservation lifecycle

| State | Event/condition | Next state | Writes |
|---|---|---|---|
| (absent) | external supersede | `first_pa` | create both copies in first-PA transaction |
| `first_pa` | first outcome | `first_pc` | both copies |
| `first_pa` | untouched initial-PA reopen | (absent) | atomically remove both; D25 audit roots retained |
| `first_pc` | first confirmation | `first_cf_undoable` | both copies; same `release_after` |
| `first_cf_undoable` | timely undo (`server_write_time <= release_after`) | `second_pa` | both copies; `release_after` removed |
| `first_cf_undoable` | expired (`server_write_time > release_after`); next mutation touching either holder | (absent), then ordinary admission | validate both copies; atomically remove both before ordinary admission |
| `second_pa` | second outcome | `second_pc` | both copies |
| `second_pc` | second confirmation | (absent) | atomically remove both |
| any | admitted fresh mutation by a listed writer that is not one of the phase transitions above (C9.6.11) | same phase | both copies recomputed and replaced |
| any | exact replay | same phase | neither copy |
| any | reset one-task deletion | (absent for that holder) | removes its task/copy; root reset fence blocks writers; finalize requires all tasks absent |
| any | account deletion (mechanics: C3) | (absent) | no task/reservation writer may recreate a copy |

| Rule | Exact statement |
|---|---|
| One-sided absence | `PLAN_GRAPH_CHANGED`, zero writes, except while the root reset fence proves the peer task was physically deleted by the fenced reset sequence |
| Identity/phase mismatch, malformed vector, reservation on another lifecycle shape | `PLAN_GRAPH_CHANGED` |
| Expiry cleanup | never legalizes a one-sided reservation |
| Undo windows | no second undo window/time expiry |

#### C9.6.13 Named falsifiers

| Test file | Named test / fixture family |
|---|---|
| `functions/tests/taskInteraction.test.js` | C6.4 registry test: every exact persisted task-plan operation request/response and workflow-submission response shape enumerated; any evidence-ID-valued member absent from both tables fails |
| `functions/tests/taskInteraction.test.js` | C6.4: every listed positive and exclusion path; exact persisted `users/{uid}/research/{taskId}.brief.sections[].items[].applicability_evidence_ids[]` shape emitted by `functions/researchTask.js`; `interactionHistory[ordinary].operation_id`; `wakeEvidence.cause.event_high_water.source_evidence_id` holding an `ev1_`-shaped value with zero traversal/root/count; unrooted record whose own `evidence_records[].id` does not prevent rollup; unlisted runtime field holding a valid `ev1_` string with zero traversal |
| `functions/tests/taskInteraction.test.js` | D25/D26: policy-absent legacy evidence retention/rollup; dependency chains; mixed-owner rows; attempts/current-snapshot one-claim mirror; cycle replacement proving an old unreferenced snapshot no longer roots replacement evidence; original confirmation; copied tuple; 15→16 rollup against older replacement; last-claim removal; wrong/missing/third-instance/old-schema/forgery; reset kill; complete stored operation/response-shape enumeration; intentionally added schema field failing the review fixture until registry, ownership/root rule, D27 calculator, and fixture all change |
| `functions/tests/taskInteraction.test.js` | C6.5 registry/oracle: production dispatch coverage and independent oracle enumerate the same literal `EVIDENCE_RESERVATION_WRITERS_V1`; new writer/action without registry + shared-seam coverage + oracle + fixture fails the gate |
| `functions/tests/taskInteraction.test.js` | D27: production and independent oracle prove `M <= 16,384`; literal transition tree/constructors implemented by shared production and independent oracle; both-copy recompute on every admitted mutation; omitted-member 638,952 and complete-task 655,360 checks both enforced |
| `functions/rules-tests/firestoreRules.test.js` | client create/update/delete adding, changing, or removing `foreignRoots` or `evidence_reservation` denied; other-user write denied |

#### C9.6.14 Capacity errors and precedence

```text
ReservationAdmissionFailureV1 =
 {schemaVersion:1,
  kind:"ORDINARY_CAP"|"ESCROW_CAP"|"ACTUAL_WRITE_BUDGET",
  holderRole:"ORIGINAL"|"REPLACEMENT",
  taskDocumentId,taskInstanceId,
  component:"EVIDENCE_RECORD_COUNT"|"EVIDENCE_RECORD_BYTES"|
   "FOREIGN_ROOT_ENTRY_COUNT"|"FOREIGN_ROOT_BYTES"|
   "INTERACTION_HISTORY_BYTES"|"TASK_INTERACTION_STATE_BYTES"|
   "SEMANTIC_SNAPSHOT_BYTES"|"TASK_DOCUMENT_BYTES"|
   "FIRESTORE_TRANSACTION_BYTES",
  required,available}
```

| Internal kind | Failing component | Callable projection |
|---|---|---|
| `ORDINARY_CAP` | `EVIDENCE_RECORD_COUNT`, `EVIDENCE_RECORD_BYTES` | `failed-precondition/EVIDENCE_UNKNOWN`; no `details` (retained; the only ordinary-cap exception) |
| `ORDINARY_CAP` | any other stored component | `resource-exhausted/TASK_CAP_EXCEEDED` |
| `ESCROW_CAP` | any of the nine | `resource-exhausted/EVIDENCE_CAP_RESERVED` |
| `ACTUAL_WRITE_BUDGET` | `FIRESTORE_TRANSACTION_BYTES` | `failed-precondition/TERMINAL_WRITE_BUDGET_EXCEEDED` (unchanged); only when the request supplies its required operation ID or submission token |

```text
{schemaVersion:1,reason:"TASK_CAP_EXCEEDED",taskDocumentId,taskInstanceId,
 component:"FOREIGN_ROOT_ENTRY_COUNT"|"FOREIGN_ROOT_BYTES"|
 "INTERACTION_HISTORY_BYTES"|"TASK_INTERACTION_STATE_BYTES"|
 "SEMANTIC_SNAPSHOT_BYTES"|"TASK_DOCUMENT_BYTES",
 required,available}
```

```text
{schemaVersion:1,reason:"EVIDENCE_CAP_RESERVED",taskDocumentId,taskInstanceId,
 component:"EVIDENCE_RECORD_COUNT"|"EVIDENCE_RECORD_BYTES"|
 "FOREIGN_ROOT_ENTRY_COUNT"|"FOREIGN_ROOT_BYTES"|
 "INTERACTION_HISTORY_BYTES"|"TASK_INTERACTION_STATE_BYTES"|
 "SEMANTIC_SNAPSHOT_BYTES"|"TASK_DOCUMENT_BYTES"|
 "FIRESTORE_TRANSACTION_BYTES",required,available}
```

| `details` rule | Exact statement |
|---|---|
| Unshown members | forbidden |
| `TASK_CAP_EXCEEDED.required` / `.available` | `U_i(post)` / `limit_i`; both safe nonnegative integers |
| `TASK_CAP_EXCEEDED` component selection | first ordinary stored-component overflow in C9.6.8 order after the two evidence components |
| `EVIDENCE_CAP_RESERVED.required` / `.available`, stored component | `remaining_i(post)` / `limit_i - U_i(post)` |
| `EVIDENCE_CAP_RESERVED.required` / `.available`, `FIRESTORE_TRANSACTION_BYTES` | maximum exact future `FirestoreWriteBudgetV1` charge over the reachable tree / literal 8,388,608 |
| Escrow selection | component-major in the displayed error-union order; within each stored component ORIGINAL before REPLACEMENT; first failure wins; detail names that first failing holder's document/instance |
| `FIRESTORE_TRANSACTION_BYTES` evaluation | last; always names ORIGINAL; `required` is the complete two-holder transaction maximum |
| Internal value | never serialized directly; never decoded by Swift |
| Swift | validates every listed `TASK_CAP_EXCEEDED` component and the exact callable shapes; maps each to capacity recovery |
| Rejection writes | no task/history/evidence/op/snapshot/child/reservation byte |

| Callable precedence | Check | Result |
|---|---|---|
| 1 | request/auth/immutable graph authority | that check's own error (graph: `PLAN_GRAPH_CHANGED`) |
| 2 | ordinary component caps | `EVIDENCE_UNKNOWN` for the two evidence components, otherwise `TASK_CAP_EXCEEDED` |
| 3 | capacity escrow | `EVIDENCE_CAP_RESERVED` |
| 4 | actual transition `FirestoreWriteBudgetV1` | `TERMINAL_WRITE_BUDGET_EXCEEDED` |

| Scheduler candidate | Exact statement |
|---|---|
| Callable error channel | none |
| Precedence | request/auth/graph validation, ordinary cap, escrow cap, then actual budget/invariant |
| `ORDINARY_CAP` / `ESCROW_CAP` | zero task/wake/intent/reservation mutation; atomically create/update the candidate's D4 refusal with the same fingerprint and `reasonCode:"AUTHORITY_REFUSAL"`; only successful refusal bookkeeping permits the ordinary cursor to pass; threshold remains run-local |
| Actual mutation budget | exact `FirestoreWriteBudgetV1` over candidate, both reservation holders, at-most-one older rollup replacement, any operation/snapshot/terminal child, wake/intent, current/prospective refusal mutation or deletion, every current/prospective index-entry delta; production and independent literal-constructor oracle prove every admitted branch strictly below 8,388,608 |
| Over-bound result | systemic `SCHEDULER_WRITE_BUDGET_INVARIANT`: write no task, reservation, wake, intent, refusal, cursor, or completion; heartbeat state stays `running`; evaluation marked unsuccessful; structured error fields only `{code:"SCHEDULER_WRITE_BUDGET_INVARIANT",lane,runOrdinal}`; increment log-based metric `phase2/scheduler_write_budget_invariant_count`; page named owner S3 on any positive value; never a refusal; never projected as a callable error |
| Pre-ship checklist | records metric and alert-policy resource IDs plus a successful test notification |

### C9.7 Blocked-store recovery and readiness gating (B3, B4, D22, D23, D28)

#### C9.7.1 Durable envelope and store caps

```text
DurableFileEnvelopeV1 = {
 schemaVersion:1,fileKind,generationId,payload,
 recoveryReceipt?:{schemaVersion:1,quarantineSHA256,recoveredCount,droppedCount},
 sha256
}
sha256            = SHA-256(canonical envelope with only sha256 omitted; includes recoveryReceipt when present)
generationId      = fresh lowercase RFC 4122 UUID per committed replacement
envelope bytes    = canonical JSON, no trailing newline
quarantineSHA256  = lowercase SHA-256(complete quarantine file bytes)
recoveredCount, droppedCount = safe nonnegative integers
baseEnvelopeBytesWithoutRecoveryReceipt = complete canonical envelope, recoveryReceipt omitted, sha256 recomputed
Byte rule (every normal write and every recovery): baseEnvelopeBytesWithoutRecoveryReceipt + 190 <= storeCap
190 = byte length of ,"recoveryReceipt":{"droppedCount":9007199254740991,"quarantineSHA256":"<64 lowercase hex>","recoveredCount":9007199254740991,"schemaVersion":1}
```

| `fileKind` | `storeCap` (complete canonical outer-envelope bytes) | Physical read bound |
|---|---|---|
| `TASK_ROUTE_INBOX_V1` | 131,072 | cap + 1 |
| `HANDOFF_AUTHORITY_V1` (normal) | 524,288 | 68,157,441 |
| `HANDOFF_AUTHORITY_V1` (expanded predicates satisfied) | `expandedStoreCap = 68,157,440` (`128 * 524,288 + 2 * 524,288`) | 68,157,441 |
| `TASK_PLAN_RESET_V2` | 131,072 | cap + 1 |
| `WORKFLOW_REQUESTS_V2` | 16,777,216 | cap + 1 |

| Rule | Exact statement |
|---|---|
| Receipt preservation | Normal later writes preserve an existing `recoveryReceipt` byte-identically; receipt without quarantine is valid audit state |
| Receipt never evicts | Recovery never drops/evicts a valid item to fit its receipt |
| Cap independence | Every other store-specific member/count cap remains independently mandatory; only handoff ordinary/cancel/combined ceilings are overridden by the expanded regime |
| Parsed-without-predicates | A parsed handoff envelope without the exact expanded predicates faces the 524,288 normal cap |
| Hash preimage | `sha256` covers the canonical envelope with only `sha256` omitted, including `recoveryReceipt` when present |
| Startup accept | Only exact outer/member sets, matching `fileKind`, canonical bytes, valid generation UUID, valid payload, and recomputed `sha256` load; any other target is corrupt |

#### C9.7.2 Blocked-snapshot union

```text
BlockedSnapshot =
 {schemaVersion:1,store:"route"|"handoff"|"reset"|"workflow",state:"quarantined",recoveryStateDigest,
  targetPresent:false,targetDecodable:false,quarantinePresent:true,quarantineEnumerable,pendingRecordCount?,
  availableActions:["recover","discard_quarantine"]|["discard_quarantine"]}
 | {schemaVersion:1,store:"route"|"handoff"|"reset"|"workflow",state:"collision",recoveryStateDigest,
  targetPresent:true,targetDecodable:false,quarantinePresent:true,quarantineEnumerable,pendingRecordCount?,
  availableActions:["recover","discard_quarantine"]|["discard_quarantine"]}
 | {schemaVersion:1,store:"route"|"handoff"|"reset"|"workflow",state:"recovered_pending_cleanup",recoveryStateDigest,
  targetPresent:true,targetDecodable:true,quarantinePresent:true,quarantineEnumerable:true,
  availableActions:["retry_cleanup"]}
 | {schemaVersion:1,store:"route"|"handoff"|"reset"|"workflow",state:"quarantine_conflict",recoveryStateDigest,
  targetPresent:true,targetDecodable:true,quarantinePresent:true,quarantineEnumerable,pendingRecordCount?,
  availableActions:["merge","discard_quarantine"]|["discard_quarantine"]}
 | {schemaVersion:1,store:"route"|"handoff"|"reset"|"workflow",state:"receipt_mismatch",recoveryStateDigest,
  targetPresent:true,targetDecodable:true,quarantinePresent:false,quarantineEnumerable:false,mismatchIdentityDigest,
  availableActions:["reconcile"]}
 | {schemaVersion:1,store:"reset",state:"reset_epoch_conflict",recoveryStateDigest,actionableExpectedTaskGenerationEpoch,
  occupants:[{expectedTaskGenerationEpoch,phase,recoveryAction}],availableActions:["recover_epoch"]}
 | {schemaVersion:1,store:"handoff",state:"foreign_installation",recoveryStateDigest,
  targetPresent,targetEnumerable,targetPendingRecordCount?,quarantinePresent,quarantineEnumerable,quarantinePendingRecordCount?,
  availableActions:["reconcile"]}
 | {schemaVersion:1,store:"handoff",state:"foreign_resolution_required",recoveryStateDigest,resolutionDigest,
  targetPresent,targetEnumerable,targetPendingRecordCount?,quarantinePresent,quarantineEnumerable,quarantinePendingRecordCount?,
  decisionGroups:[{decisionDigest:<lowercase SHA-256>,actionLabel:<safe label>}],availableActions:["resolve"]}
 | {schemaVersion:1,store:"route"|"handoff"|"reset"|"workflow",state:"storage_io_unavailable",
  errorCode:"FILE_OPEN_FAILED"|"FILE_READ_FAILED"|"FILE_WRITE_FAILED"|"FILE_FSYNC_FAILED"|"FILE_RENAME_FAILED"|
            "DIRECTORY_FSYNC_FAILED"|"FILE_UNLINK_FAILED"|"FILE_PROTECTION_FAILED",availableActions:["retry"]}
 | {schemaVersion:1,store:"handoff",state:"installation_authority_unavailable",
  errorCode:"KEYCHAIN_LOAD_FAILED"|"KEYCHAIN_UPDATE_FAILED"|"KEYCHAIN_ADD_FAILED",availableActions:["retry"]}
 | {schemaVersion:1,store:"handoff",state:"installation_authority_invalid",
  errorCode:"KEYCHAIN_VALUE_INVALID",availableActions:["repair_installation_identity"]}
```

| Rule | Exact statement |
|---|---|
| `CORRUPT_BLOCKED` scope | Names only the structural quarantine/collision branches; storage, Keychain, foreign-installation, and receipt-authority failures keep their own typed states |
| `pendingRecordCount` | Present iff quarantine enumerable and state permits; forbidden in `recovered_pending_cleanup` and `receipt_mismatch` |
| `mismatchIdentityDigest` | Permitted only in `receipt_mismatch` |
| `resolutionDigest`, `decisionGroups` | Permitted only in `foreign_resolution_required`; `decisionGroups` nonempty, immutable, unique digests, unsigned-UTF8-sorted |
| Unavailable/invalid branches | Forbid every file-presence/decodability/count/identity/digest member; entry performs no synthetic replace, drop, or file mutation |
| `reset_epoch_conflict` | Forbids file-presence/decodability/count/mismatch/foreign members; two to four ordered occupants for one current UID; each option matches the row's stored phase and derived recovery action |
| Foreign invariants | At least one source present; every present source enumerable; `targetPresent == targetEnumerable`; `quarantinePresent == quarantineEnumerable`; each pending count present exactly when its source is present |
| `availableActions` | Required, ordered exactly as shown, no other value/order; part of `RecoveryObservedStateV1` and bound by the displayed digest/CAS |
| `recover`/`merge` presence | Only when complete candidate classifier, duplicate/conflict resolution, malformed-target zero-candidate/no-singleton predicate (when applicable), all count/member/byte caps, and every required named read-only proof admit it; enumerability alone is insufficient |
| Over-cap mapping | Over-cap target → `targetPresent:true,targetDecodable:false`; over-cap quarantine → `quarantinePresent:true,quarantineEnumerable:false`; no over-cap source contributes `pendingRecordCount` |
| Snapshot opacity | No raw installation UUID, OSStatus, path, account, payload, candidate identity, proof, or localized error enters any snapshot |
| Unknown/absent action | Returns local `{schemaVersion:1,reason:"RECOVERY_ACTION_UNAVAILABLE",store}` with zero server call/file write; stale `recoveryStateDigest` returns the refreshed snapshot, never this error |

#### C9.7.3 Blocked-state classification order

| Order | Step | Applies to |
|---|---|---|
| 1 | File open/read/protection unavailability → `storage_io_unavailable` | all stores |
| 2 | Keychain load/add authority (any file present) → `installation_authority_unavailable` / `installation_authority_invalid` wins before every structural action; zero file mutation | handoff |
| 3 | Valid matching-receipt cleanup (`recovered_pending_cleanup`) | all stores |
| 4 | `foreign_installation` precedence only under complete enumerability/validity predicate | handoff |
| 5 | Structural `quarantined` / `collision` / `quarantine_conflict` | all stores |
| 6 | First current-auth receipt-bearing row in frozen store order lacking/disagreeing with `ValidatedReceiptProvenanceV1` → `receipt_mismatch`; repeat until none | all stores |
| 7 | Fully valid, quarantine-absent, provenance-safe reset target only → current-UID `reset_epoch_conflict` | reset |
| 8 | `ready` | all stores |

| Persisted files | State |
|---|---|
| target absent; quarantine absent | ordinary empty (ready) |
| target malformed; quarantine absent | immediate target→fixed-quarantine rename, directory fsync → `quarantined` (subject to handoff Keychain ordering) |
| target absent; quarantine present | `quarantined` |
| target malformed; quarantine present | `collision` |
| target valid; enumerable quarantine; target receipt names its digest and `recoveredCount + droppedCount == rawPendingRecordCount` | `recovered_pending_cleanup` |
| target valid; quarantine present; no matching receipt (or digest match with unenumerable quarantine / unsafe count / overflow / count disagreement) | `quarantine_conflict` |
| target valid; quarantine absent; first current-auth receipt-bearing row lacks/disagrees with live provenance | `receipt_mismatch` |

| Rule | Exact statement |
|---|---|
| `foreign_installation` precedence | After Keychain success and any valid matching-receipt cleanup, entered **before** generic structural actions only when every remaining present source is enumerable, every candidate needed for recovery passes complete schema/immutable-identity validation with no duplicate/conflict group, and at least one valid installation singleton differs from the Keychain installation; covers quarantine-only and both-source layouts, never exposes generic Discard |
| Precedence fallback | Malformed/unextractable installation, unenumerable source, or any complete-schema/identity-invalid, duplicate, or conflicting candidate stays in the applicable generic structural state (`quarantined`/`collision`/`quarantine_conflict`): Recover/Merge absent, that state's whole-quarantine `discard_quarantine` available; other stores use the file-state table directly |

#### C9.7.4 Recovery actions

| Blocked state | Action | Precondition (CAS) | Effect | Crash semantics |
|---|---|---|---|---|
| `quarantined` | `recover` | `recoveryStateDigest` match pre-call and post-await; every candidate resolved; aggregate invariants; caps | Item-recover into one fresh envelope generation with receipt naming quarantine digest/counts; unlink quarantine | After rename before unlink → `recovered_pending_cleanup` |
| `quarantined` | `discard_quarantine` | digest match; quarantine `FileObservationV1` reread/identity match before unlink | Remove quarantine only, sync; no receipt; handoff last-file → empty-target-first | Handoff: before unlink → target+quarantine same installation, reclassify without rekey; after unlink → empty target retained |
| `collision` | `recover` | digest match; malformed target bounded-enumerable with raw candidate count exactly zero and no singleton authority member (`installation`, `auth`, route refresh authority, reset `gesture`) | Recover quarantine items treating target as nonauthority; physically replace target under whole-state CAS | As `quarantined` recover |
| `collision` | `discard_quarantine` | digest match; observation match | Remove quarantine only, sync; malformed target then follows normal rename → becomes next quarantine for separate decision | Two-step discard; second discard uses empty-target-first (handoff) |
| `recovered_pending_cleanup` | `retry_cleanup` | digest match; full target revalidation; quarantine digest reread | Quarantine unlink, directory fsync, then ready | Reclassifies from surviving directory state |
| `quarantine_conflict` | `merge` | digest match; recovery starts from fully validated live target; live rows/singletons never removed/changed except named reconciliation replacement | New generation based on live target plus valid quarantine rows; receipt; unlink | After rename before unlink → `recovered_pending_cleanup` |
| `quarantine_conflict` | `discard_quarantine` | digest match; observation match | Remove quarantine only | As above |
| `receipt_mismatch` | `reconcile(recoveryStateDigest:mismatchIdentityDigest:)` | Recompute auth, both digests, scope in-actor pre-call; post-await recompute auth, observed state, first mismatch before atomic replacement | `inspectCommittedOperation` only; `committed` → exact RECEIPT/APPLYING replacement + provenance install; `absent|pending` → exact pre-replay phase; transport error, malformed/noncanonical response, auth drift, or digest drift → writes nothing, target byte-identical and blocked, returns complete current classification | Crash after committed inspection before/during application loses provenance → reloads `receipt_mismatch`, repeats read-only inspection |
| `reset_epoch_conflict` | `recover_epoch` | `RecoveryAttemptKey{kind:"recover_epoch",recoveryStateDigest,expectedTaskGenerationEpoch,expectedPhase,action}` | Store-specific epoch option matching the row's phase/derived action | Reclassifies |
| `foreign_installation` | `reconcile` (Reconcile restored handoff data) | Keychain success; every remaining candidate settled by read-only canonical proof; post-await whole-state CAS | At most one current-installation generation, or `foreign_resolution_required`, or generic structural state with only `discard_quarantine`, or same `foreign_installation` snapshot with zero write | Offline/ambiguous → zero target/receipt write |
| `foreign_resolution_required` | `resolve` → `resolveForeign(recoveryStateDigest:resolutionDigest:choices:)` | Exact full ordered `choices` array; rerun proofs; recompute groups/labels/both digests; post-await whole-state CAS | Commit at most one envelope: Continue drops covered choice-eligible candidates; Restart creates one current-requester takeover PREFLIGHT | Process death before the single call/commit forgets choices, re-prompts complete list |
| `storage_io_unavailable` | `retry` | `RecoveryAttemptKey{kind:"unavailable",store,state,errorCode,action:"retry"}`; no state digest | Repeat only failed I/O step, then full fresh classification | Relaunch classifies surviving old/new directory state; never treats an unsatisfied in-process directory sync as acknowledged success |
| `installation_authority_unavailable` | `retry` | `{kind:"unavailable",...,action:"retry"}` | Repeat exact Keychain authority operation, then full reclassification; no file mutation | Resume from Keychain authority |
| `installation_authority_invalid` | `repair_installation_identity` | `{kind:"unavailable",...,action:"repair"}`; fresh UUID generated only inside winning shared task | `repairInvalid(candidate)`; no target/quarantine byte changes before repair succeeds | Concurrent valid winner adopted; all classification reruns |

| Unavailable `errorCode` | Retry behavior |
|---|---|
| `DIRECTORY_FSYNC_FAILED` | Unconditionally open and sync directory, then reclassify |
| `FILE_OPEN_FAILED` / `FILE_READ_FAILED` / `FILE_PROTECTION_FAILED` | Retry only read/classification |
| `FILE_WRITE_FAILED` / `FILE_FSYNC_FAILED` / `FILE_RENAME_FAILED` / `FILE_UNLINK_FAILED` | Abandon owner-private temp file; fully reclassify target plus quarantine; never repeat ambiguous mutation |
| `KEYCHAIN_LOAD_FAILED` / `KEYCHAIN_UPDATE_FAILED` / `KEYCHAIN_ADD_FAILED` | Complete exact authority operation, then fully reclassify |

#### C9.7.5 File replacement sequences

```text
Recover/Merge/foreign-with-quarantine: unique temp → complete write loop → file fsync → atomic rename over target → directory fsync → quarantine unlink → directory fsync
Target-only foreign reconciliation:     temp → write → file fsync → rename → directory fsync   (no unlink; no new/replacement receipt; prior receipt preserved byte-identically)
Handoff last-file Discard:              [Keychain/Firebase authority + whole-state CAS] → write canonical empty target (fresh generation, no receipt) via temp/write/fsync/rename/dir-fsync → reread+match original quarantine digest → unlink → directory fsync
Handoff canonical empty payload:        {installation:{installationId:<current Keychain>},auth:<resulting signedAuth>,sessions:{records:[]},reconciliationCancels:[]}
Durability barrier:                     write/fsync/rename complete selected target + directory fsync BEFORE quarantine cleanup, readiness, callback, opener, or any mutating replay
```

| Rule | Exact statement |
|---|---|
| Enumerable | Bounded bytes parse as one JSON object under a duplicate-member-rejecting parser; payload member and every required candidate collection are unambiguous arrays; optional reset gesture unambiguous; raw element counts and sum are safe integers |
| Unenumerable | Non-JSON bytes, duplicate member on any candidate path, missing/wrong-type collection, unsafe counting, readable over-cap file → Discard only |
| I/O failure vs malformed | Open/read/protection failure → `storage_io_unavailable`, never Discard |
| No silent double delete | No action deletes both copies silently; handoff Discard never leaves both durable files absent |
| Reentrancy | Once a synchronous replacement sequence begins, no actor reentrancy between write/fsync/rename/directory-fsync/unlink checks |
| Fresh auth epoch | Generated once after initial CAS, retained only in in-flight context, committed after final stable-input CAS |
| Crash after durability | Crash after target durability before readiness/replay → reload the retained/replacement phase; the request cannot be lost |
| Retained bytes | Every candidate counted recovered by byte-for-byte retention is written in its exact source bytes before readiness |

#### C9.7.6 Item recovery keys, classifier, counted universe, source accounting

| Store / record | Exact recovery key |
|---|---|
| route | intent ID |
| handoff ordinary | `(uid,installationId,authEpochUUID,taskInstanceId,sessionId)` |
| handoff reconciliation cancel | `(uid,taskInstanceId,sessionId,reasonCode,requesterNamespace.installationId,requesterNamespace.authEpochUUID)` |
| reset record | `(uid,expectedTaskGenerationEpoch)` |
| reset legacy migration | `uid` (at most one row per UID) |
| workflow | `(uid,taskInstanceId,taskGenerationEpoch,workflowId,flowAttemptGeneration)` |

| Store | Counted universe (`pendingRecordCount`) | Excluded |
|---|---|---|
| route | `records` elements | refresh singletons |
| handoff | session elements + reconciliation-cancel elements | `installation`, `auth` singletons |
| reset | record elements + legacy-migration elements + 1 when `gesture` present | — |
| workflow | active-record elements | `retiredDiagnostics` |

```text
Candidate classes:  recovered | dropped | unresolved
recovered = complete valid candidate inserted byte-for-byte | same-key byte-equal cross-source (no insertion) | retained gesture | exact row selected by named store-specific read-only proof | transformed to canonical RECEIPT/APPLYING row | reconstructed SERVER_SNAPSHOT | replaced by durably created current-requester PREFLIGHT
dropped   = handoff-only: digest-bound signed-out/different-UID auth purge | PREPARED ordinary handoff named no-dispatch proof | DISPATCHED single-snapshot operation-absent + session-absent/terminal proof | explicit Continue-other-device
unresolved = complete-schema/identity failure | duplicate key within one source | cross-source same-key unequal | aggregate failure of any store-level singleton, uniqueness, cross-member, phase/authority, count, or byte invariant incl. the C9.5.7 gesture/migration/reset-row matrix | unequal live/quarantine gesture | malformed/partial refresh pair
Invariant: recoveredCount + droppedCount == pendingRecordCount; no candidate contributes twice
SourceAccounting = {present:false,enumerable:false} | {present:true,enumerable:true,candidateCount,recoveredCount,droppedCount}   (recoveredCount + droppedCount == candidateCount)
ForeignReconciliationResult = {schemaVersion:1,kind:"foreign_installation_reconciliation",target:<SourceAccounting>,quarantine:<SourceAccounting>}
```

| Rule | Exact statement |
|---|---|
| Never dropped | Invalid, duplicate, conflicting, RECEIPT, APPLYING bytes; generic route/reset/workflow auth state; PREPARED reconciliation-cancel authority |
| Invalid candidate | Never classified dropped; no server seam is ever called for an invalid candidate |
| RECEIPT/APPLYING | Always recovered byte-for-byte and later rerun; never inferred applied from server terminal state; non-openable local application obligations |
| Route RECEIVED | Recovered byte-for-byte including complete `refreshLease/refreshNamespace`; ordinary `AppRouteInbox` clears only after durability/readiness under auth-revision/namespace or 60-second-expiry reducer |
| Reset gesture | One counted optional singleton; live gesture never replaced; no live gesture → every complete valid reserved/bound gesture recovered regardless of auth; owner applies reserved-auth purge / bound materialization only after durability, reset+handoff ready, auth revalidated; four-row cap prevents materialization → retain and expose B2 capacity recovery |
| Reset epochs | Complete valid rows for different epochs both retained subject to sort/count/byte caps; no recovery path mints an alias or epoch |
| Workflow diagnostics | Quarantine `retiredDiagnostics` omitted; live target diagnostics byte-identical |
| Sort | Resulting collections use frozen store sort order before hashing; source iteration never chooses bytes |
| Cap failure | Live-plus-recovered exceeding any member/count/base+190 cap → write nothing, remain blocked |
| Mutating calls | No mutating server call before recovered target durability and readiness; named read-only proofs may precede only for the exact valid identity they accept |
| Zero-server recovery | Complete schema-valid, identity-valid, unconflicted candidate selected byte-for-byte with zero server call |
| Foreign target counts | Returned but not persisted in `recoveryReceipt`; quarantine receipt names only its digest/counts |

#### C9.7.7 Expanded handoff regime

| Bound | Two-population recovery commit | Quarantine-only (incl. zero-population collision target) recovery | Every later expanded envelope |
|---|---|---|---|
| ordinary | ≤ 32 | ≤ 32 | ≤ 32 |
| reconciliation-cancel | ≤ 96 | ≤ 96 | ≤ 96 |
| combined | ≤ 64 | ≤ 128 | ≤ 128 |
| bytes | base + 190 ≤ 68,157,440 | same | same |
| per-record | each complete ordinary/cancel record ≤ 524,288 | same | same |

```text
Expanded validity: retains recoveryReceipt AND (current envelope OR exhaustive maximum prospective envelope across every legal remaining transition) exceeds ≥1 normal ceiling (ordinary≤16, cancellation≤16, base+190≤524,288)
Cancellation lineage identity: {uid,taskDocumentId,taskInstanceId,sessionId}
Projection: +≤1 current-requester reconciliation successor per retained ordinary whose identity has no retained cancellation lineage; PREPARED|DISPATCHED|RECEIPT|APPLYING cancel occupies the lineage
Return to normal: first later atomic write whose projection proves every remaining transition stays within 16/16/524,288; no special marker
Fresh begin/preparation while receipt persists: computes the exhaustive normal projection before any server call or opener; admitted only when every future transition remains 16/16/524,288; fresh work never re-enters or borrows the expanded cap; failure → frozen local handoff-capacity diagnostic, zero server/opener/file mutation
```

| Rule | Exact statement |
|---|---|
| Entry | Item-recovery write consuming a simultaneously present target and quarantine may enter; quarantine-only recovery enters only when the quarantine payload's complete candidates and member/count caps validate (duplicates/conflicts stay unresolved); selected output sorted under frozen store order before the expanded byte check, contains no candidate not counted from the quarantine, writes a fresh generation plus a new receipt naming that quarantine digest/count |
| Sole re-entry | Quarantine-only recovery is the sole re-entry path for an expanded target later quarantined by outer corruption; never trusts malformed outer hash or old receipt |
| Count-once | Replacement of one recovered ordinary by one current-requester PREFLIGHT counts once |
| Cancel projection | A reconciliation-cancel candidate never reconstructs as ordinary `SERVER_SNAPSHOT` |
| One-for-one | Conclusive no-commit may replace a lineage one-for-one in the same atomic write; never removes one and adds two |
| Settlement | RECEIPT/APPLYING lineage settles under its frozen reducer before any successor |
| Ambiguous authority | Blocks the lineage transition |
| Terminal rows | Applied/terminal rows are removed under frozen rules |
| PREFLIGHT creation | Only when complete canonical server snapshot proves sole frozen auth-rotation/takeover successor; obeys 32/96/128; no general begin/preparation |
| Projection timing | Lineage-aware closed projection (incl. maximum receipt/application bytes) computed before any mutating await and again before write |
| Invalid example | 32 ordinary + 96 unrelated cancellations is invalid (projection 160) |

#### C9.7.8 Receipt provenance and `inspectCommittedOperation`

```text
ReceiptProvenanceKey        = {family,authority,requestAuthority,identityDigest}
ValidatedReceiptProvenanceV1 = {family,authority,requestAuthority,identityDigest,receiptSHA256,uid,authEpochUUID,credentialRevision,envelopeGeneration,envelopeSHA256}
receiptSHA256 = lowercase SHA-256(UTF8(TaskCanonicalV1(<complete exact durable receipt map carried by that family row>)))
   hash scope: no outer callable wrapper, replay rewrite, response authority expansion, or omitted optional member is hashed
   legacy-migration response carrying a nested reset progress receipt: migration entry hashes the complete durable migration receipt; separate RESET entry hashes the complete exact nested progress-receipt map
Owner actor state: validatedReceiptProvenance: [ReceiptProvenanceKey:ValidatedReceiptProvenanceV1]   (process-local; cleared on disk load/relaunch and any signed-auth tuple change)
   entry exists only when the same actor fully validated the exact response against the exact request/identity/auth tuple and durably committed the named envelope; never encoded, inferred from a syntactically valid receipt, or reconstructed after load; a same-process first response may retain its entry and follow its frozen first-response behavior
Request  = {action:"inspectCommittedOperation",family,authority,requestAuthority,identityDigest}
Response = {schemaVersion:1,kind:"committed_operation_inspection",accountUid,family,authority,requestAuthority,identityDigest,outcome,receipt?}
   receipt required iff outcome == "committed"; WORKFLOW response authority = {submissionToken,workflowSubmissionId}; every other branch echoes request authority
Identity maps (mismatchIdentityDigest = identityDigest = lowercase SHA-256(TaskCanonicalV1(map))):
   {kind:"route",intentId}
   {kind:"handoff",action,uid,installationId,authEpochUUID,taskInstanceId,sessionId}
   {kind:"handoff_cancel",uid,taskInstanceId,sessionId,reasonCode,requesterInstallationId,requesterAuthEpochUUID}
   {kind:"reset",uid,expectedTaskGenerationEpoch}
   {kind:"legacy_reset_migration",uid}
   {kind:"workflow",uid,taskDocumentId,taskInstanceId,taskGenerationEpoch,workflowId,flowAttemptId,flowAttemptGeneration,submissionToken}
Exposed mismatch: unsigned-UTF8-smallest TaskCanonicalV1 encoding among actionable current-auth mismatches
```

| `family` | `authority` | `requestAuthority` | Read set / accepted stored shape | Outcomes | Pre-replay phase on `absent|pending` |
|---|---|---|---|---|---|
| `ROUTE_CLAIM` | `{operationId}` | `{requestSHA256}` | `users/{uid}/taskPlanOperations/{operationId}`; `INTENT_CLAIM/COMMITTED`, action `claimTaskIntent`, exact stored task-route response | `absent\|committed` | `CLAIM_DISPATCHED` |
| `HANDOFF` | `{operationId}` | `{requestSHA256}` | same path; `TASK_OPERATION/COMMITTED`, candidate's retained handoff action | `absent\|committed` | `DISPATCHED` |
| `HANDOFF_CANCEL` | `{operationId}` | `{requestSHA256}` | same path; `TASK_OPERATION/COMMITTED`, action `cancelHandoff` | `absent\|committed` | `DISPATCHED` |
| `RESET` | `{operationId}` | `{requestFingerprint}` | one read-only transaction/same-read-time snapshot of operation doc and root `users/{uid}`; `RESET_OPERATION` + total active marker equality, or finalized tombstone + marker absence | `absent\|pending\|committed` | `reset_dispatched` (no canonical/progress receipt) |
| `LEGACY_RESET_MIGRATION` | `{migrationId}` | `{requestFingerprint}` | `users/{uid}/legacyResetMigrations/{migrationId}`; permanent migration kind/owner/derived ID/fingerprint/identity/outcome | `absent\|committed` | `dispatched` |
| `WORKFLOW` | `{submissionToken}` | `{requestFingerprint}` | `workflowSubmissionId = "ws2_" + first40(SHA-256(TaskCanonicalV1({owner:uid,submissionToken})))`; root `workflowSubmissions/{workflowSubmissionId}` only | `absent\|committed` | `DISPATCHED` |

| Rule | Exact statement |
|---|---|
| RESET request authority | `"reset1_" + SHA-256(TaskCanonicalV1({kind:"reset",reason:"retake_assessment",expected_task_generation_epoch:e}))` |
| Migration request authority | exact alias-free `rlmreq1_` derivation over only UID and legacy operation ID |
| Workflow fingerprint | Recomputed from validated local `requestCanonicalJSON` under frozen workflow fingerprint rule; not complete-request SHA-256 |
| Provenance key authority | Always request-form `{submissionToken}`, never `{submissionToken,workflowSubmissionId}` |
| Replay flags | Route/handoff/cancel/workflow: exact stored response + outer `replayed:true`; RESET tombstone: `reset_final` + `replayed:true`; migration: reconstructed response + outer `replayed:true`, nested flags preserved |
| Pending | Active RESET (deleting/awaiting) is the sole pending member; returns no receipt |
| `absent\|pending` write | Clears only receipt/application members forbidden by the pre-replay phase; preserves immutable request/identity/creation bytes; no mutating server call until the target is durable and ready; a concurrent later commit is recovered by ordinary exact replay |
| Stored-record mismatch | Malformed/wrong owner/kind/action/path-ID/fingerprint/hash/identity/receipt → `failed-precondition/OPERATION_REUSED` naming `operationId` (non-WORKFLOW incl. migration) or `submissionToken` (WORKFLOW) |
| Invalid input | Top-level/type/member-set → `invalid-argument/{schemaVersion:1,reason:"REQUEST_INVALID",field:"request"}`; otherwise first invalid in order `action,family,authority,requestAuthority,identityDigest` names that field; branch-incompatible shape names that member; unknown/surplus names `request` |
| Unauthenticated | `unauthenticated/{schemaVersion:1,reason:"AUTH_REQUIRED"}` |
| Handler | Authenticates UID; performs exactly the row's read set; no create/update/delete; reconstructs identity map and requires digest equality; client digest never substitutes field validation |
| Sole mechanism | No direct client read of `taskPlanOperations`, `legacyResetMigrations`, `workflowSubmissions` |
| Provenance update | After each successful whole-envelope replacement: drop entries whose row/receipt/auth no longer match, update `envelopeGeneration/envelopeSHA256` in survivors, insert/replace the validated response |
| Loaded rows | Every current-auth receipt-bearing row loaded from disk (incl. RECEIPT/APPLYING from crash/launch/recovery/other process) is `receipt_mismatch` before any application/callback/opener/notification/accounting |
| Reconciliation path | Always loaded/replay local application path; never first-response notification/accounting/callback |
| Auth scope | Row actionable only while signed in to its UID; signed-out/different-UID rows inert under retention/auth-purge/cap rules; every auth change reclassifies |
| Migration replay | `committed` adopts returned stored alias rather than requiring local losing candidate |

#### C9.7.9 Signed-auth reconstruction and same-installation handoff rules

```text
Preserve stored SIGNED_OUT iff Firebase signed out AND stored installation == Keychain
Preserve stored SIGNED_IN  iff Firebase signed in to same UID AND stored installation == Keychain
Else reconstruct once:
  signed out → {state:"SIGNED_OUT",installationId:<Keychain>,epochUUID:<fresh lowercase UUID>}
  signed in  → {state:"SIGNED_IN",uid:<current>,installationId:<Keychain>,epochUUID:<fresh lowercase UUID>,credentialRevision:0}
No stored credential revision crosses a mismatch; no timestamp/ordinal precedence
```

| Rule | Exact statement |
|---|---|
| Retained/openable ordinary | `(uid,installationId,authEpochUUID)` equals resulting SIGNED_IN tuple and complete schema validates |
| Old-epoch same-UID/same-install | Never opened; complete canonical active-session proof replaces that one source candidate with exact current-requester `AUTH_EPOCH_CHANGED` PREFLIGHT; counts once; no takeover confirmation |
| Old cancellation | Conclusive no-commit retires it only in the same envelope write that creates its replacement |
| Requester-namespace row | Preserved byte-for-byte across its valid phase |
| Cancel namespace | Reconciliation-cancel rows validate the exact reason-paired stored/requester namespace invariants |
| Foreign-requester row | Never dropped offline; canonical authority must yield the generic committed-receipt/application or conclusive no-commit result; active different-installation cancellation still requiring takeover creates a current-requester record only after explicit Restart-here confirmation |
| Post-ready add | Only after durability/readiness may a retained ordinary cause the owner to add a separate reconciliation row under the expanded rule |

#### C9.7.10 Keychain installation identity

```text
Accessor: HandoffSessionStore via InstallationIdentityProviding (sole accessor)
Lookup: kSecClassGenericPassword; service "com.peezy.phase2.installation"; account "installation-id-v1"; kSecAttrSynchronizable:false; kSecAttrAccessGroup omitted; accessibility NOT a query discriminator
Valid item: generic-password data == one lowercase RFC 4122 UUID in UTF-8, no terminator/newline; returned accessibility == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly; else invalid
   load requests both data and attributes; add/update always write that accessibility; duplicate-add rereads with the logical lookup identity
load()                                -> absent | present(validUUID) | invalid | error
addIfAbsent(candidateValidUUID)       -> inserted(candidateValidUUID) | existing(validUUID) | invalid | error
rekeyEmptyContainer(candidateValidUUID) -> rekeyed(candidateValidUUID) | existingConcurrent(validUUID) | error(stage:"load"|"update"|"add")
repairInvalid(candidate)              -> existing(validUUID) | repaired(candidate) | added(candidate) | addExisting(validUUID) | stillInvalid | error(stage:"load"|"add")
No result carries raw Keychain bytes or OSStatus
```

| Files present | Keychain state | Operation | Result mapping |
|---|---|---|---|
| none | any (valid/invalid/absent) | fresh UUID → `rekeyEmptyContainer` before creating empty target: rereads logical identity in-actor; valid/invalid existing item updated to candidate + ThisDeviceOnly → `rekeyed`; absent → add → `rekeyed`; an initially invalid item never enters `installation_authority_invalid` here | `rekeyed` adopts; duplicate-add reread valid → `existingConcurrent`; invalid/absent → `error(stage:"add")`; query failure → `error(stage:"load")`; errors → `KEYCHAIN_LOAD_FAILED|KEYCHAIN_UPDATE_FAILED|KEYCHAIN_ADD_FAILED`, no target creation |
| ≥1 | valid | none (never overwritten) | classify; differing structurally decodable installation → `foreign_installation` |
| ≥1 | absent | fresh UUID → `addIfAbsent` before mutating either file | `inserted(candidate)` adopts; `existing(winner)` adopts winner; never derive candidate from file bytes |
| ≥1 | error | — | `installation_authority_unavailable` (Retry only) |
| ≥1 | invalid | `repairInvalid(fresh UUID)` on explicit Repair | valid reread → `existing` no write; invalid → update once → `repaired`; update not-found → add flow; absent → `added`; duplicate-add valid winner → `addExisting`; other update result → bounded reread: valid `existing`, invalid `stillInvalid`, absent → add branch, reread failure `error(stage:"load")`; add failure → reread: `addExisting`/`stillInvalid`/`error(stage:"add")`/`error(stage:"load")`; `stillInvalid` → `installation_authority_invalid` |

| Rule | Exact statement |
|---|---|
| Rollout premise | Keychain item committed before first handoff-envelope write; absent item beside any file is restore/reinstall/loss/fixture, never pre-Keychain upgrade |
| Crash after rekey | May rekey again before target creation (no durable authority yet) |
| Crash after Keychain success | Resumes from that authority |
| ThisDeviceOnly | Prevents backup migration; not proof that uninstall removed the item |
| Retention | Installation-level; not removed on sign-out or account deletion |

#### C9.7.11 Foreign installation reconciliation and resolution

```text
Order: digest-bound ordinary signed-out/different-UID auth purge (each removed valid candidate = dropped, zero server call)
       → every remaining ordinary/cancel candidate awaits canonical read-only server authority
       → RECEIPT/APPLYING candidates mandatorily selected byte-for-byte, excluded from decision groups
       → group proved-active choice-eligible candidates by {uid,taskDocumentId,taskInstanceId,sessionId}
Ordinary candidate, canonical server installationId == current Keychain → exact ordinary SERVER_SNAPSHOT from server authority (exact epoch resumes; old epoch → AUTH_EPOCH_CHANGED reconciliation)
Reconciliation-cancel candidate → retained | replaced by one current-requester cancel | dropped under conclusive rule (never becomes ordinary)
decisionDigest   = lowercase SHA-256(TaskCanonicalV1({server_session_identity:<complete typed identity>,server_proof_sha256:<digest of complete validated read-only proof>,candidate_identity_digests:[<sorted full lowercase SHA-256 of complete typed candidate identities>]}))
decisionGroups   = unique {decisionDigest,actionLabel} sorted by decisionDigest unsigned UTF-8; actionLabel = canonical server activeHandoff.presentation_snapshot.action_label (trimmed/bounded safe-label grammar)
resolutionDigest = lowercase SHA-256(TaskCanonicalV1({recovery_state_digest:recoveryStateDigest,decision_groups:decisionGroups}))
resolveForeign(recoveryStateDigest:resolutionDigest:choices:)   choices = [{decisionDigest,choice:"continue"|"restart"}] in displayed order
   (choice collection is purely local to S4: no owner call, server call, or file mutation before the single call)
choicesSHA256    = lowercase SHA-256(TaskCanonicalV1(choices))
```

| Rule | Exact statement |
|---|---|
| Group proof | All complete validated read-only proofs in one group byte-equal; disagreement, absent/invalid/disagreeing label → unresolved, no choice, no write |
| One choice per group | Each eligible candidate belongs to exactly one group; contradictory per-candidate choices structurally impossible |
| Continue | Drops every choice-eligible source candidate covered by the group; each counted dropped in its own source |
| Restart | Exactly one normal current-requester takeover PREFLIGHT for the group; replaces every covered candidate for output; each counted recovered in its own source |
| Choice validation | Missing, duplicate, surplus, reordered, malformed, unknown choice rejected before any proof or write |
| Drift | Any state/proof/label/digest drift → complete `ready|blocked` reclassification, zero mutating call/file write |
| Duplicate labels | S4 appends deterministic 1-based ordinal in displayed order without changing label bytes or digests |
| Escape | If no permitted result meets caps without dropping nondroppable RECEIPT/APPLYING and quarantine present → generic structural state with only `discard_quarantine`; target-only → same `foreign_installation` snapshot, zero write, no Discard |
| No foreign copy | Never copy a foreign candidate as current authority; branch on canonical server namespace, never the source file's installation singleton |
| No-commit drop (PREPARED ordinary) | Only by frozen local no-dispatch proof |
| No-commit drop (PREPARED cancel) | Never solely for no-dispatch; same-install old-auth → atomic `AUTH_EPOCH_CHANGED` PREFLIGHT replacement; different-install active → Continue/Restart |
| No-commit drop (DISPATCHED) | Only when one read-only Firestore transaction/same-read-time snapshot proves operation record absent/no-commit for exact immutable request AND session absent/terminal with no local receipt owed; snapshot + read time bound into proof digest; torn reads rejected |
| Dispatch | Actual cancel/takeover dispatch occurs later through the ordinary ready-store owner |

#### C9.7.12 Recovery observed state, results, attempt keys

```text
recoveryStateDigest   = lowercase SHA-256(TaskCanonicalV1(RecoveryObservedStateV1))
RecoveryObservedStateV1 = {schemaVersion:1,store,baseState,target,quarantine,availableActions,keychain?,firebase?,auth?,mismatchIdentityDigest?}
   baseState of foreign_resolution_required = "foreign_installation"
   keychain:{state:"valid",installationId}  and  firebase:{state:"signed_out"}|{state:"signed_in",uid}   — handoff only, after authority success
   auth:{state:"signed_in",uid,authEpochUUID,credentialRevision}   — receipt_mismatch only (from AuthAuthorityProviding; forbidden elsewhere; signed-out forbidden)
   only stable observed inputs enter the map; a newly generated replacement auth epoch is forbidden in it
FileObservationV1 = {present:false}
   | {present:true,classification:"valid"|"malformed",byteLength,bytesSHA256,generationId?,envelopeSHA256?}   (generation/envelope hash present iff valid)
   | {present:true,classification:"over_cap",byteLength,fileIdentityDigest}
fileIdentityDigest = lowercase SHA-256(TaskCanonicalV1({deviceDecimal,inodeDecimal,sizeDecimal,mtimeSecondsDecimal,mtimeNanosecondsDecimal,ctimeSecondsDecimal,ctimeNanosecondsDecimal}))   (base-10 strings from fstat on opened no-follow descriptor)
RecoveryResult = ready | blocked(BlockedSnapshot) | busy({schemaVersion:1,reason:"RECOVERY_BUSY",store}) | unavailable({schemaVersion:1,reason:"RECOVERY_ACTION_UNAVAILABLE",store})
RecoveryAttemptKey = {kind:"recover"|"merge"|"discard"|"cleanup",recoveryStateDigest}
   | {kind:"receipt_reconcile",recoveryStateDigest,mismatchIdentityDigest}
   | {kind:"foreign_reconcile",recoveryStateDigest}
   | {kind:"resolve_foreign",recoveryStateDigest,resolutionDigest,choicesSHA256}
   | {kind:"recover_epoch",recoveryStateDigest,expectedTaskGenerationEpoch,expectedPhase,action}
   | {kind:"unavailable",store,state,errorCode,action:"retry"|"repair"}
```

| Public action | Private key kind |
|---|---|
| Recover | `recover` |
| Merge | `merge` |
| Discard quarantine | `discard` |
| Retry cleanup | `cleanup` |
| receipt Reconcile | `receipt_reconcile` |
| foreign Reconcile | `foreign_reconcile` |
| Resolve | `resolve_foreign` |
| unavailable Retry | `unavailable/retry` |
| Repair installation identity | `unavailable/repair` |
| epoch option | `recover_epoch` |

| Rule | Exact statement |
|---|---|
| Whole-state CAS | Every digest-bearing action accepts and CASes the displayed digest; pre-call drift → complete reclassification (`ready` or `blocked(fresh)`), zero call/write; post-await recompute before any write/unlink; drift → same reclassification, no write/unlink, no further call |
| Never fabricate | Never fabricates a blocked snapshot for a ready store |
| Unlink precondition | Quarantine unlink requires original `FileObservationV1`: within-cap bytes reread and hashed; over-cap uses descriptor identity via new no-follow descriptor; drift aborts |
| Single slot | Each store owner has exactly one shared `(RecoveryAttemptKey,Task)` slot across structural, receipt, foreign, resolution, unavailable, and reset-epoch recovery; exact key equality coalesces; different key → `busy` before any callback/call/write |
| Stale token | Old Q1 Retry after another scene reaches Q2/ready returns the complete current classification; cannot reapply Q1 |
| Unavailable no-digest | Retry/Repair carry no state digest; no unavailable attempt mutates target/quarantine; subsequent mutation requires a newly returned token-bearing action |
| CAS layering | Whole-state CAS supplements every candidate/request/auth CAS |

#### C9.7.13 Readiness vector, required sets, dependency graph

```text
ReadinessVector = {route,handoff,reset,workflow}   each: loading | ready | blocked(BlockedSnapshot)
```

| Store | Required set (operation) | Gate projection |
|---|---|---|
| handoff | handoff operations | `{handoff}` |
| route | claim / refresh / returned-session presentation | `{route,handoff}` |
| reset | reserve / bind / dispatch / application | `{reset,handoff}` |
| workflow | prepare / dispatch / application | `{workflow,handoff}` |
| — | direct task callables touching no durable aggregate | `{}` |
| route | `AppRouteInbox.receive(intentId:source:)` ingress | route store ready only (handed immediately while other stores load/block) |

```text
Dependency graph (edge: operation → store must be ready)
  handoff ops        → handoff
  route ops          → route, handoff
  reset ops          → reset, handoff
  workflow ops       → workflow, handoff
  direct callables   → (none)
  route ingress      → route
  Google auth callback URL → bypasses readiness (bound only by GoogleIdentityAuthority slot)
  Only claim/refresh/presentation/callable/opener wait for readiness; ingress never waits on handoff/reset/workflow (needs only the route store loaded and not blocked)
```

| Rule | Exact statement |
|---|---|
| Recovery surface | Overlays blocked-store/deletion actions; mountable with all stores blocked; does not turn an empty-required-set callable into a four-store dependency |
| `AppRootView` | May render; each operation gated by its declared required set |
| Barrier publication | S7 constructs and publishes barrier, deletion gate, recovery surface in `PeezyV1App` before `AppRootView` is created |
| Integration order | S1 seams + `TaskPlanService` DTO/transport → S2 workflow/server → S3 scheduler/migration/deletion integration → S4 recovery UI + durable deletion orchestration → S5 handoff/auth conformance → S7 route/AppDelegate/root wiring |

#### C9.7.14 Seam protocols (`Peezy 4.0/Tasks/Durable/DurableStoreReadiness.swift`, no file I/O, all `Sendable`)

| Protocol / type | Exact signature or union |
|---|---|
| `StartupBarrier` | declared here; store/state vocabulary |
| `RouteIngressReceiving` | `receive(intentId:source:) async -> persisted\|duplicate\|rejected_blocked\|rejected_full\|invalid`; `source: notification_tap\|url` |
| `RouteIngressDiagnosticReporting` | `record(_:)` synchronous/nonthrowing; reason `INTENT_ID_TYPE_INVALID\|INTENT_ID_INVALID\|TASK_URL_INVALID\|RECEIVED_AT_EPOCH_INVALID\|ROUTE_INBOX_BLOCKED\|ROUTE_INBOX_FULL\|ROUTE_INBOX_RECEIVED_EVICTED`; production `os.Logger(subsystem:"peezy.Peezy-4-0",category:"route-ingress")` logs only the literal reason |
| `AuthAuthorityProviding` | `currentSignedAuth() async -> signedOut\|signedIn({uid,authEpochUUID,credentialRevision})`; `forceRefresh(expected:{uid,authEpochUUID,credentialRevision}) async -> committed({uid,authEpochUUID,credentialRevision})\|notCommitted`; `confirmAccountDeleted(expected:{uid,authEpochUUID}) async -> definitivelyDeleted\|notProven` |
| `CurrentFirebaseUIDProviding` | `currentFirebaseUID() -> String?` synchronous snapshot; navigation comparison only, never server/file/auth authority |
| `AccountDeletionProviderContextProviding` | `dispositions(expectedUID:) async -> {appleRevocation:"not_required"\|"manual_required",googleRevocation:"not_required"\|"sdk_disconnect_required"\|"manual_required",googleProviderUid?}` |
| `AccountDeletionCompletionPresenting` | governed by C2 |
| `AppleCredentialStateChecking` | `credentialState(forProviderUID:) async -> authorized\|revoked\|notFound\|transferred\|unresolved` (wraps only `ASAuthorizationAppleIDProvider.getCredentialState`; error/cancellation/`@unknown default` → unresolved) |
| `GoogleIdentityControlling` | `currentProviderUID() async -> String?`; `handle(_ url: URL) async -> handled\|notHandled`; `signIn() async -> signedIn(uid)\|cancelled\|failed(missingClientID\|missingPresenter\|sdkFailure\|missingToken\|firebaseFailure\|staleGeneration)`; `disconnect(expectedProviderUID:) async -> disconnected\|signedOut\|identityMismatch\|failed`; `signOutAll() async -> disconnected\|signedOut\|identityMismatch\|failed` |
| `FirestoreLocalCachePurging`, `NotificationIdentityPurging`, `RoomCaptureArtifactPurging`, `LocalPrivacyPurgeCoordinating` | declared; shapes owned elsewhere |
| `ClientTelemetryPrivacyPurging` | `purgeAll() async -> cleared\|relaunchRequired\|failed` (nonthrowing; `relaunchRequired\|failed` → `LOCAL_PRIVACY_PURGE_FAILED`, journal retained; only `cleared` passes barrier) |
| `ResetEpochAuthorityProviding` | B2's exact authenticated epoch-read shape |
| `ResetEpochConflictRecovering` | declared; shape owned by C9.5.18 |
| `InstallationIdentityProviding` | exactly C9.7.10 load / add-if-absent / empty-container-rekey / invalid-repair |
| `AccountDeletionRemoteProviding` | typed DTO/transport conformance owned by S1 `TaskPlanService.swift`; S2 owns JS callable |
| `RouteAccountDeletionPurging`, `HandoffAccountDeletionPurging`, `ResetAccountDeletionPurging`, `WorkflowAccountDeletionPurging` | four durable-store purge seams; `AppRouteInbox` sole conformer of `RouteAccountDeletionPurging` (serialized purge, no second route-envelope writer); `receive` serializes load with ingress and never synthesizes empty authority |

```text
GoogleIdentityAuthority slot = idle | signingIn(operationGeneration,callbackState:"awaitingCallback"|"callbackHandled") | disconnecting(operationGeneration,expectedProviderUID) | signingOut(operationGeneration)
signIn(): client ID + presenter obtained and Google Sign-In configured/started only inside one authority-owned MainActor operation; callback extracts tokens, builds the Firebase credential, completes Firebase sign-in, destroys intermediates in that same operation; only the final UID/fixed outcome crosses to the actor; the exclusive generation spans each complete callback await and postcondition — no other sign-in/disconnect/sign-out until retirement
Google callback scheme (byte-equal, case-sensitive): com.googleusercontent.apps.833904565407-m9jhkhdhvih0aeeknk4fpcfbnv3g4oso
ClientTelemetryPrivacyAuthority: one process-lifetime singleflight check on MainActor racing literal 10-second monotonic timeout; callback false → cleared; callback true → delete once → relaunchRequired; timeout/cancellation/invariant → failed; late/duplicate callback loses operation-generation CAS; after relaunchRequired every same-process call returns relaunchRequired with no further SDK check/delete; after cleared later same-process calls return cleared (static zero-record invariant); only a fresh process resets the singleflight
```

| Rule | Exact statement |
|---|---|
| `forceRefresh` `committed` | Legal only after same UID/epoch CAS durably wrote exactly `expected.credentialRevision + 1` as safe integer; failure/overflow/drift/CAS loss → `notCommitted`, no auth write; caller rereads `currentSignedAuth()` |
| `definitivelyDeleted` | Only when provider still holds exact cached user for `expected.uid`, epoch not replaced, forced token refresh fails with Firebase's exact user-not-found; everything else `notProven`; generic `signedOut` never deletion proof |
| Apple disposition | One valid `apple.com` provider entry → `manual_required`; complete list without → `not_required`; absent/ambiguous → `manual_required` |
| Google disposition | Exactly one valid `google.com` entry byte-matching stable provider snapshot from `GoogleIdentityAuthority` slot → `sdk_disconnect_required` + UID; none → `not_required`; presence without unique match → `manual_required`, no UID |
| Google `handle(url)` | Only exact `signingIn(g,awaitingCallback)` treats it as the same operation's event; handled → `callbackHandled`; notHandled leaves `awaitingCallback`; stale generation / callbackHandled / idle / disconnecting / signingOut → zero SDK call, `notHandled`; never queues a second slot |
| Google disconnect | Waits for signingIn settlement; requires stable provider ID byte-equal to expected; accepts `disconnected` only in same slot/generation with nil currentUser; otherwise `identityMismatch`/`failed`, Google ack absent |
| Google signOutAll | Same slot; `signedOut` only after nil currentUser; never claims remote revocation |
| No restore | Restore is not a shipped reachable operation |
| Value escape | Raw SDK/Firebase errors, tokens, credentials, GID/Firebase User objects, view controllers never escape the authority |
| Phase-2 exclusions | No silent-push source or background-fetch callback |

#### C9.7.15 Route ingress precedence (`AppRouteInbox.receive`)

| Order | Condition | Result / diagnostic | Bytes |
|---|---|---|---|
| 1–2 | already-blocked store; invalid intent String (relative order not frozen by source) | `ROUTE_INBOX_BLOCKED` → `rejected_blocked`; `INTENT_ID_INVALID` → `invalid` | none |
| 3 | duplicate lookup (before clock) | `duplicate`; zero clock read/write/purge/eviction | none |
| 4 | fresh valid intent samples injected clock once; sample must be safe nonnegative epoch-ms with safe `receivedAtEpochMilliseconds + 86_400_000`; that one sample governs receipt time, expiry comparison, purge, and eviction | else `RECEIVED_AT_EPOCH_INVALID` → `invalid` | none |
| 5 | ninth distinct valid intent: purge expired plain RECEIVED rows with no live `refreshLease/refreshNamespace` | — | replacement |
| 6 | still full: evict oldest plain RECEIVED with no live lease by `(receivedAtEpochMilliseconds asc, intentId unsigned-UTF8 asc)` | `ROUTE_INBOX_RECEIVED_EVICTED` only after durable commit → `persisted` | replacement |
| 7 | all eight protected (live-lease RECEIVED, CLAIM_DISPATCHED, CLAIMED, PRESENTING — protected even after TTL) | `ROUTE_INBOX_FULL` → `rejected_full` | none |
| 8 | any write/fsync/rename/directory-fsync failure | publish `storage_io_unavailable`; best-effort `ROUTE_INBOX_BLOCKED` → `rejected_blocked`; never `persisted\|duplicate\|rejected_full` for that attempt | old-or-new classified on Retry |

#### C9.7.16 Production runtime identity, `CompletionOnce`, notification tap, `onOpenURL`

```text
Phase2ProductionRuntime (eleven statics, literal order):
 routeInbox, ingressDiagnostic, googleIdentityAuthority, notificationIdentityAuthority, clientTelemetryPrivacyAuthority,
 roomCaptureArtifactOwner, firestoreRuntimeOwner, currentFirebaseUIDProvider, startupBarrier, accountDeletionCompletionPresentation, accountDeletionCoordinator
Singletons: one AppRouteInbox, one GoogleIdentityAuthority, one NotificationIdentityAuthority, one ClientTelemetryPrivacyAuthority, one RoomCaptureArtifactOwner,
 one FirestoreRuntimeOwner, one startup barrier/deletion gate, one completion presenter, one account-deletion coordinator; second instance of any forbidden
Coordinator inputs: transport + eight local-purge seams (route, handoff, reset, workflow, room capture, Firestore cache, notifications, Google) + client-telemetry barrier + provider-context seam + completion presenter + shared startupBarrier (Sendable deletion-gate-controlling seam)
Wiring: Google seam / provider-context seam / URL handler / auth model / Google purge seam ← the one googleIdentityAuthority; notification delegate adapters / registration path / startup-discovery hook / notification purge seam ← the one notificationIdentityAuthority;
 every deletion/auth-transition coordinator ← the one clientTelemetryPrivacyAuthority; PeezyV1App, every purge/store owner, auth/scene observers, presentation/opening consumers, every route ingress adapter, PeezySettingsView obtain the exact static instance; internal AppDelegate/test runtime initializer is the sole alternative initializer
final class CompletionOnce: @unchecked Sendable { NSLock-protected optional raw () -> Void; scheduled: Bool }
 finish(): main thread → take+nil under lock, release, invoke; else mark scheduled under lock, release, DispatchQueue.main.async captures only the Sendable box; later/reentrant finish() no-op; closure never invoked while lock held; private main-thread-asserting method likewise takes/nils under lock, releases, then invokes; no actor isolation assumed for the UNUserNotificationCenter delegate callback; no unstructured Task captures the raw UIKit closure
```

| Notification tap order | Condition | Behavior |
|---|---|---|
| 1 | `categoryIdentifier == "PEEZY_SUPPORT_REPLY_V1"` | One main-actor `Task` capturing only `CurrentFirebaseUIDProviding`, deletion-gate checker, `CompletionOnce`; reads UID snapshot, asks checker, `SupportChatNavigation.requestOpen()` at most once; `completion.finish()` exactly once; never reads `userInfo` |
| 2 | `peezy_task_intent_id` absent | Non-task; finish immediately |
| 3 | value is exact String | Handed unchanged to `receive(...,source:.notification_tap)`; task `Task` captures receiver, intent ID, `CompletionOnce`; `defer { completion.finish() }`; awaits nonthrowing receiver once; no catch/thrown branch |
| 4 | any other value type | Synchronously `INTENT_ID_TYPE_INVALID`; finish |

| `onOpenURL` order | Condition | Behavior |
|---|---|---|
| 1 | exact `peezy://task/v1?intentId=...` under one-query-pair grammar | One unstructured `Task` calling receiver with `.url` |
| 2 | scheme exactly lowercase `peezy`, grammar fails | Synchronously `TASK_URL_INVALID`; not offered to Google |
| 3 | non-`peezy` scheme byte-equal to Google callback scheme | One task: `await Phase2ProductionRuntime.googleIdentityAuthority.handle(url)`; result discarded |
| 4 | every other URL | Ignored; zero Google SDK call |

| Rule | Exact statement |
|---|---|
| AppDelegate | Never writes; binds immutable receiver/sink synchronously in `AppDelegate.override init()` before `super.init()`; `@UIApplicationDelegateAdaptor(AppDelegate.self)` passes no constructor arguments; internal test initializer is the sole alternative |
| Spoofed support | `userInfo.thread:"support"` without the fixed category follows ordinary task/non-task branch |
| APNs keys | Additional APNs/system keys do not invalidate a valid task payload |
| `.noData` | No branch calls a completion-handler variant with `.noData` |
| Dispatch before receipt | Receiver never dispatches the route before durable receipt |
| Diagnostic posture | Best-effort, not dispatch authority, never changes an envelope, may be lost on process death; diagnostic failure does not roll back durable receipt |
| `firestoreRuntimeOwner` | The single `FirestoreRuntimeOwner` type; no unnamed Firestore-runtime type satisfies the registry |

#### C9.7.x Named falsifiers

| Test file | Named test / fixture family |
|---|---|
| (not named in source range) | Base+190 exact/+1 for constructible-length stores; reachable constructive maximum round-trip with algebraic headroom; each member/count cap +1 without padding; receipt replacement shortest→longest, prior bytes preserved on rejection |
| (not named in source range) | Route eight-record constructive maximum round-trip; every member/count/cap boundary +1 |
| (not named in source range) | Expanded: full 128-row quarantine beside empty/no-singleton malformed collision target; outer-corrupt 32+64 then auth rotation to 32+96; outputs 0+64, 0+96, lineage-covered 32+96, invalid all-unrelated 32+96; each count and 68,157,440 exact/+1; each record at reachable maximum; required rotation from initial 32+32; existing lineage suppressing duplicate successor; conclusive no-commit one-for-one; RECEIPT/APPLYING settlement before successor; small row whose later receipt exceeds normal admission; no general preparation; bounded cap+1 streaming read; projected drain to 16/16/524,288; fresh begin from 15+16 rejected (17 cancels); 15+15 admitted only when 16+16 projection fits |
| (not named in source range) | Quarantine-only foreign singleton beside one invalid row → generic `quarantined` with Discard only |
| (not named in source range) | Target-only foreign replacement with prior-receipt preservation/absence and no unlink |
| (not named in source range) | Individually valid but aggregate-incompatible reset gesture/migration authority |
| (not named in source range) | Two-row provenance: A in APPLYING while B reconciled/applied; A's entry survives; readiness converges without ping-pong |
| (not named in source range) | `inspectCommittedOperation`: every table row; every replay projection with zero first-response side effect; RESET sole pending; literal root workflow path/derived ID/wrong owner; request-form vs expanded workflow authority; zero `taskPlanOperations` read for workflow; missing/wrong/surplus/cross-family values per field in precedence order |
| (not named in source range) | Pre-durability replacement/count-once vs post-ready add-and-retain |
| (not named in source range) | Receipt mismatch: mutate every identity-map member incl. handoff `action`; server/client digest equality; cross-action rejection; digest ordering; opacity; identical-action coalescing; different-action BUSY; stale pre-call no-call/no-write; target/quarantine/auth drift during await zero write; A→B and signed-out drift; stale action after ready; refreshed-snapshot return; A→B per multi-UID store |
| (not named in source range) | Classification: syntactically valid canonically contradictory receipt then crash; loaded RECEIPT/APPLYING every family; crash after inspection before apply; multiple ordered mismatches; same-process first-response provenance; provenance loss on auth/envelope drift; malformed target with Keychain invalid/error and zero Recover/Discard/write |
| (not named in source range) | Whole-state: Q1 → Q2 via another scene → stale Q1 Retry leaves Q2 bytes; exact Retry/Repair key coalescing; different key BUSY; every failure-specific no-blind-mutation branch |
| (not named in source range) | Disk-combination sweep: every disk combination; kill every file boundary; both collision actions and two-step discard incl. handoff empty-target-first; matching digest+count cleanup vs digest-only/count-mismatched/unenumerable conflict; live-row preservation; mixed valid/invalid/duplicate/unequal sums; malformed bytes vs I/O failure; cap+1 read from multi-gigabyte sparse over-cap file, replaced inode never unlinked; collision Recover unavailable on any candidate/singleton; sorted output; normal and expanded caps without opportunistic drop; expanded target outer-SHA corruption → quarantine → foreign Keychain → recovery under fresh expanded receipt; reserved/bound gesture and legacy rows; auth switch during generic recovery retains route/reset/workflow candidates; quarantine workflow diagnostics omitted, live retained; multiple mismatches ordered by canonical identity; exact ordinary/cancel keys and signed-out/signed-in reconstruction; directory-sync failure retry before readiness |
| (not named in source range) | Authority: valid unconflicted pre-await/dispatched/RECEIPT/APPLYING/bound copied with zero server call; malformed/duplicate/unequal authority → Recover unavailable; no generic server seam; kill after rename+dir-fsync before cleanup/readiness/replay; mutating replay only after readiness; op-first replay/no-create proof; absent/new ambiguity zero call/write; loaded APPLYING rerun; never inferring application from server terminal state; torn-read race rejected |
| (not named in source range) | Keychain: accessibility excluded from query, validated in result; add-before-file; missing-key restore with old ID never adopted; target-only/quarantine-only/both-source foreign; concurrent add winner; load/add errors; reinstall rekey before empty-target; both-files-absent update failure → `KEYCHAIN_UPDATE_FAILED` then Retry success; crash after rekey/before target; fresh-only invalid repair; update item-not-found; duplicate-add/reread; every repair error/reread result; zero file mutation before authority success |
| (not named in source range) | Foreign: per-source counts; receipt subsumption; active/terminal/no-commit/ambiguous ordinary; PREPARED ordinary no-dispatch vs PREPARED cancel retention/replacement; cancellation replacement consent; exact returned/persisted accounting; no Discard; signed-in B with old-UID A row → zero server call, dropped; full expanded target + foreign quarantine of APPLYING rows → only quarantine discard; target-only reachable maximum → zero-write same state; file installation B / Keychain A / server session A → SERVER_SNAPSHOT under A, no takeover cancel; same-install old-auth and different-server-install as separate fixtures |
| (not named in source range) | Multi-decision: same complete ordered group list; any UI collection order; one canonical ordered call; missing/surplus/reordered rejected; kill before call/commit re-prompts all; one proof drift zero write; opposite choices → different `choicesSHA256`, one wins, other `RECOVERY_BUSY`; byte-identical coalesce; same-server/two-local-namespace → one group, Continue drops both, Restart one PREFLIGHT both recovered, mixed impossible, proof disagreement unresolved; two distinct labels; duplicate labels stable ordinals; server label drift; forged foreign-local label never renders |
| (not named in source range) | Google/static: zero production GID type/token/credential return outside authority; every sign-in/failure/cancel/handle/current-UID outcome; callback/presenter/token lifetimes internal |
| (not named in source range) | Route/AppDelegate: support-category+task collision → support precedence; support in foreground/background/cold tap; spoofed `userInfo.thread` zero support open; valid/absent/non-string task payload; task URL and malformed Peezy URL before readiness; Google sign-in held at redirect; unrelated non-Peezy URL ignored; matching-scheme notHandled spoof preserves awaitingCallback then real handled redirect settles slot; post-handled URL zero SDK call; gate/disconnect racing after callback settlement; stale URL during disconnect/signOut/idle; `CompletionOnce` concurrent/double/reentrant finish main/background, cooperative cancellation, every receive result, every persist/reject/diagnostic branch, exactly-once main-thread, no raw-closure capture or invocation under lock; immediate non-task completion; receiver/sink bound before callback; adaptor default construction bound to `Phase2ProductionRuntime`; one inbox and coordinator identity across Settings/app/store owners; received-at safe boundary, max allowing `+86_400_000`, +1/unsafe-clock rejection; duplicate under throwing/invalid clock zero clock read; equal-millisecond inverse-lexical ingress → canonical order and tie-break; ninth receipt with expired purge, expired+live-lease protection, oldest-RECEIVED eviction with post-commit diagnostic, eight protected → FULL; every file-replacement failure boundary → rejected-blocked, callback once, old/new classification; kill after receipt/before readiness and disk replay; route blocked; every dependency edge mutation; direct WAIT with handoff blocked; storage/installation authority unavailable; async auth refresh success/failure/drift/overflow with exact durable revision |

## C10 Ownership and test envelope (D29, D31, D32)

### C10.1 Authorized server/data paths

| Source | Owner | Path | Status | Authorized scope (exact literal) |
|---|---|---|---|---|
| spec | S1 | `functions/taskInteraction.js` | new | both canonical domains, `CallableTimestampWireV1`, and `FirestoreWriteBudgetV1` registries |
| spec | S1 | `functions/seedTaskCatalog.js` | existing | — |
| spec | S1 | `functions/spawnTasks.js` | existing | — |
| spec | S1 | `firestore.rules` | existing | owner for owner projection, all-owner generation, direct task/packing/readiness denial, and the sole synthetic epoch-upgrade exception |
| spec | S2 | `functions/taskDisposition.js` | new | policy actions plus all §4.7 legacy/packing/support actions, receipt-disposition projection, restoration preflight/error descriptors, trusted-display/fallback reducer, timestamp/server-write-time enforcement |
| spec | S2 | `functions/dispositionContract.js` | existing | — |
| spec | S2 | `functions/taskPlan.js` | existing | base owner/H54 plus copied confirmation evidence and deterministic per-epoch reset/tombstone |
| spec | S2 | `functions/getWorkflowQualifying.js` | existing | — |
| spec | S3 | `functions/notificationIntents.js` | new | — |
| spec | S3 | `functions/dispositionTriggers.js` | existing | persisted ordered phase-0 cursor, three-identical-failure quarantine, valid-envelope high-water, plus seven scans including independent threshold scan; policy-present rows settle with zero writes (C9.3.11 interim) |
| S3-CD8 | S6 | `functions/dispositionTriggers.js` | existing | the C9.3.11 policy-present wake branches (wake evidence, `ATTENTION_NOW`, urgency upgrade, attended projection, intent production), effective when C9.3 defines the policy-state, deadline-evidence, and handoff shapes |
| S3-CD8 | S6 | C9.3 live policy-state, deadline-evidence, handoff, and PC-linkage shapes (`taskInteractionState`, the firing branches' evidence, and the intent's PC referent) | new | shapes open; S6 defines them in C9.3 before coding the policy-present branches and the claim's PC-linkage validation |
| spec | S3 | `functions/taskPlan.js` | existing | intent-claim/task-route expiry follow-on |
| spec | S3 | `firestore.indexes.json` | existing | exact §7.4 |
| spec | S3 | `firestore.rules` | existing | final scheduler/intent/quarantine-denial integration and whole-file re-review |
| spec | S9 | `functions/researchTask.js` | existing | — |
| manifest | S2 | `functions/taskPlan.js` | existing | exact legacy reconciliation action, cutoff, server-only `legacyResetMigrations` authority schema, legacy/Phase-2 bridge, complete `inspectCommittedOperation` authority-projection table and closed `changeTaskPlan` discriminator |
| manifest | S2 | `functions/taskDisposition.js` | new | frozen policy/action surface; `LEGACY_RESET_MIGRATION` is not a `taskPlanOperations` union member |
| manifest | S2 | `functions/index.js` | existing | `exports.changeTaskPlan = changeTaskPlan` export byte-identical for the inspection/reset action; no separate deployed export or additional Node file; §11's expressly listed new files and `functions/index.js` edits, including both deletion-reconciler exports, remain authorized independently |
| manifest | S2 | `docs/plans/PHASE2_EXECUTABLE_SPEC_v5.md` | existing | replacement text adds the exact request union to §4.1 and exact success/replay/error union to §§4.6/7 before implementation, so the inspection/reset action is not an out-of-registry escape |
| manifest | S3 | `functions/scripts/migrateOversizeEvents.js` | new | import-safe |
| manifest | S3 | `functions/notificationIntents.js` | new | — |
| manifest | S3 | `functions/dispositionTriggers.js` | existing | B1/D4/D7-D10 runtime pieces |
| manifest | S3 | `firestore.rules`, `firestore.indexes.json` | existing | final-integrated/refrozen |
| manifest | S2/S3 shared | `functions/accountDeletionFence.js` | new | import-safe; sole outbound-lease transaction and universal deletion/reconciler core owner; every listed provider caller and both deletion drivers use it |
| manifest | S2/S3 shared | `functions/scripts/purgeLegacyResolvedProviders.js` | new | import-safe |
| manifest | S2/S3 shared | `functions/scripts/purgeLegacyDeletedAccounts.js` | new | import-safe |
| manifest | S2/S3 shared | `functions/scripts/sealAccountDeletionProviderEvidence.js` | new | import-safe |
| manifest | S2/S3 shared | `functions/accountDeletionProviderEvidenceV1.json` | new | immutable build input |
| manifest | S2/S3 shared | `functions/index.js` | existing | sole deployed export site for both `reconcileAccountDeletionStorage` and `reconcileAccountDeletionAuth`; statically proves zero Storage-finalizer export |
| manifest | S2/S3 shared | `functions/index.js`, `functions/notifySupport.js`, `functions/resolveProvider.js`, `functions/taskPlan.js`, `functions/getWorkflowQualifying.js`, `functions/dispositionTriggers.js`, `functions/spawnTasks.js`, `functions/processInventory.js`, `functions/researchTask.js`, `functions/peezyChat.js`, `functions/packageInventory.js`, `functions/submitCheckIn.js`, `functions/submitCheckInCore.js`, `functions/entitlement.js`, `functions/validateSubscription.js`, `functions/supportAdmin.js` | existing | §11's literal fence-writer, outbound-provider, cleanup, cache-removal, scheduled Storage/Firestore/Auth guard, sealed-evidence, and historical-account-migration registries |
| manifest | S2/S3 shared | `functions/processInventory.js` | existing (baseline `d321547`) | only: shared-fence call on process success, process error, and `onInventoryRoomWritten`; every Anthropic call under the shared lease helper; no other edit |
| manifest | S2/S3 shared | `functions/package.json` | existing | adds direct exact dependency `"@google-cloud/firestore":"7.11.6"` with no range |
| manifest | S2/S3 shared | `functions/package-lock.json` | existing | regenerated from that exact manifest under the frozen Node/npm toolchain; must resolve already-transitive `@google-cloud/storage` to exact 7.18.0; may not float or be hand-edited; no new direct storage dependency is invented, and a different resolution stops the pinned tuple/generation seam |
| manifest | S2/S3 shared | `firestore.rules`, `storage.rules` | existing | client/upload fence |

- D10 archive safety still uses §3.1's explicit delete-invocation/RPC drain, while ordinary post-deployment account deletion uses the permanent universal fence. (manifest)

### C10.2 Authorized client paths

| Source | Owner | Path | Status | Authorized scope (exact literal) |
|---|---|---|---|---|
| spec | S1 | `Peezy 4.0/Assessment/AssessmentModels/TaskGenerationService.swift` | existing | — |
| spec | S1 | `Peezy 4.0/MainInterface/Models/SpawnService.swift` | existing | — |
| spec | S1 | `Peezy 4.0/MainInterface/Models/PeezyCard.swift` | existing | — |
| spec | S1 | `Peezy 4.0/Tasks/Store/PeezyCardFirestoreMapper.swift` | existing | — |
| spec | S1 | `Peezy 4.0/MainInterface/Models/TaskPlanService.swift` | existing | sole writer for all callable DTOs/transports |
| spec | S1 | `Peezy 4.0/Tasks/Disposition/TaskInteraction.swift` | new | — |
| spec | S1 | `Peezy 4.0/Tasks/Disposition/ConfirmedDispositionCommand.swift` | new | — |
| spec | S2 | `Peezy 4.0/MainInterface/Models/WorkflowService.swift` | existing | — |
| spec | S2 | `Peezy 4.0/Tasks/Task Cards/RentTruckFlow.swift` | existing | — |
| spec | S2 | `Peezy 4.0/Tasks/Task Cards/SetupInternetFlow.swift` | existing | — |
| spec | S2 | `Peezy 4.0/Tasks/Disposition/DispositionTriggerSelection.swift` | new | — |
| spec | S2 | `Peezy 4.0/Tasks/Disposition/TaskDispositionCoordinator.swift` | new | — |
| spec | S4 | `Peezy 4.0/MainInterface/Views/AppRootView.swift` | existing | — |
| spec | S4 | `Peezy 4.0/Tasks/Disposition/TaskDispositionSurface.swift` | new | — |
| spec | S4 | `Peezy 4.0/Tasks/Store/TasksStore.swift` | existing | — |
| spec | S4 | `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift` | existing | first pass |
| spec | S4 | `Peezy 4.0/Tasks/Views/TasksTabView.swift` | existing | — |
| spec | S4 | `Peezy 4.0/Tasks/Views/TasksList.swift` | existing | — |
| spec | S4 | `Peezy 4.0/Tasks/Views/TaskRow.swift` | existing | — |
| spec | S4 | `Peezy 4.0/Tasks/Views/TaskRowButtons.swift` | existing | — |
| spec | S4 | `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift` | existing | — |
| spec | S4 | `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift` | existing | — |
| spec | S5 | `Peezy 4.0/Tasks/Handoff/HandoffSession.swift` | new | — |
| spec | S5 | `Peezy 4.0/Tasks/Handoff/HandoffSessionStore.swift` | new | — |
| spec | S5 | `Peezy 4.0/Tasks/Handoff/TaskExternalActionButton.swift` | new | — |
| spec | S5 | `Peezy 4.0/Tasks/Handoff/ContextualOutcome.swift` | new | — |
| spec | S5 | `Peezy 4.0/MainInterface/Views/ProviderActionCard.swift` | existing | — |
| spec | S5 | `Peezy 4.0/MainInterface/Models/ProviderDirectoryService.swift` | existing | — |
| spec | S5 | `Peezy 4.0/MainInterface/Models/TaskFlowRouter.swift` | existing | — |
| spec | S5 | `Peezy 4.0/MainInterface/Models/TaskActionService.swift` | existing | — |
| spec | S5 | `Peezy 4.0/MainInterface/Models/SupportChatService.swift` | existing | — |
| spec | S5 | `Peezy 4.0/MainInterface/Views/SupportChatView.swift` | existing | — |
| spec | S5 | `Peezy 4.0/Tasks/FlowEngine/FlowProgressSession.swift` | existing | — |
| spec | S5 | `Peezy 4.0/Tasks/FlowEngine/FlowEngineView.swift` | existing | — |
| spec | S5 | `Peezy 4.0/Tasks/FlowEngine/FlowExitControl.swift` | existing | first pass |
| spec | S5 | `Peezy 4.0/Tasks/Task Cards/HandleAutoInsuranceFlow.swift` | existing | — |
| spec | S5 | `Peezy 4.0/Tasks/Task Cards/HandleHomeInsuranceFlow.swift` | existing | — |
| spec | S5 | `Peezy 4.0/Tasks/Task Cards/FindCleanersFlow.swift` | existing | — |
| spec | S5 | `Peezy 4.0/Tasks/Task Cards/SellItemsFlow.swift` | existing | — |
| spec | S5 | `Peezy 4.0/Tasks/Task Cards/RemoveItemsFlow.swift` | existing | — |
| spec | S5 | `Peezy 4.0/Tasks/Task Cards/SuppliesKitView.swift` | existing | — |
| spec | S6 | `Peezy 4.0/MainInterface/Models/MoversChainCoordinator.swift` | existing | — |
| spec | S6 | `Peezy 4.0/MainInterface/Models/MoversFlowViewModel.swift` | existing | — |
| spec | S6 | `Peezy 4.0/Tasks/Views/TaskDetailView.swift` | existing | — |
| spec | S6 | `Peezy 4.0/Tasks/Views/TaskContentSections.swift` | existing | — |
| spec | S6 | `Peezy 4.0/Tasks/Task Cards/MoversEquipView.swift` | existing | — |
| spec | S6 | `Peezy 4.0/Tasks/Task Cards/FindMoversFlow.swift` | existing | — |
| spec | S6 | `Peezy 4.0/Tasks/Task Cards/BookYourMoversView.swift` | existing | — |
| spec | S6 | `Peezy 4.0/Tasks/Task Cards/PackingReadinessView.swift` | existing | — |
| spec | S6 | `Peezy 4.0/Tasks/Task Cards/PackingSessionView.swift` | existing | — |
| spec | S7 | `Peezy 4.0/MainInterface/Routing/TaskRoute.swift` | new | — |
| spec | S7 | `Peezy 4.0/MainInterface/Routing/AppRouteInbox.swift` | new | — |
| spec | S7 | `Peezy 4.0/MainInterface/Models/PeezyV1App.swift` | existing | — |
| spec | S7 | `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift` | existing | route follow-on |
| spec | S7 | `Peezy-4-0-Info.plist` | existing | — |
| spec | S8 | `Peezy 4.0/Tasks/FlowEngine/FlowExitControl.swift` | existing | scene follow-on |
| spec | S9 | `Peezy 4.0/Tasks/Views/TaskResearchModule.swift` | existing | — |
| spec | S9 | `Peezy 4.0/Tasks/FlowEngine/PostFlowForkView.swift` | existing | — |
| manifest | S1 core/reset | `Peezy 4.0/Tasks/Durable/DurableStoreReadiness.swift` | new | — |
| manifest | S1 core/reset | `Peezy 4.0/MainInterface/Models/RetakeAssessmentCoordinator.swift` | existing | — |
| manifest | S1 core/reset | `Peezy 4.0/Menu/PeezySettingsView.swift` | existing | §6.6 remainder hash evaluated after normalizing its one exact runtime-provider line back to the frozen preimage; no other outside-deleteAccount byte changes |
| manifest | S1 core/reset | `Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift` | existing | — |
| manifest | S1 core/reset | `Peezy 4.0/MainInterface/Models/UserKnowledgeService.swift` | existing | — |
| manifest | S1 core/reset | `Peezy 4.0/MainInterface/Models/DailyDoseEngine.swift` | existing | — |
| manifest | S1 Firestore-runtime/gate closure | `Peezy 4.0/Assessment/AssessmentViews/Onboarding/GeneratingView.swift` | existing | — |
| manifest | S1 Firestore-runtime/gate closure | `Peezy 4.0/Inventory/Services/InventoryStorageService.swift` | existing | additionally only §11's media-transfer/buffer registry, cancellation, and generation guards |
| manifest | S1 Firestore-runtime/gate closure | `Peezy 4.0/MainInterface/Models/BoxReturnService.swift` | existing | — |
| manifest | S1 Firestore-runtime/gate closure | `Peezy 4.0/MainInterface/Models/CheckInService.swift` | existing | — |
| manifest | S1 Firestore-runtime/gate closure | `Peezy 4.0/MainInterface/Models/ISPPlanService.swift` | existing | — |
| manifest | S1 Firestore-runtime/gate closure | `Peezy 4.0/MainInterface/Models/IdentityService.swift` | existing | — |
| manifest | S1 Firestore-runtime/gate closure | `Peezy 4.0/MainInterface/Models/PeezyStackViewModel.swift` | existing | `PeezyStackViewModel→PeezyClient` §8.9.3 admission through runtime/lease authorities |
| manifest | S1 Firestore-runtime/gate closure | `Peezy 4.0/MainInterface/Models/SubscriptionManager.swift` | existing | `SubscriptionManager→SubscriptionAPIClient` §8.9.3 admission through runtime/lease authorities |
| manifest | S1 Firestore-runtime/gate closure | `Peezy 4.0/MainInterface/Models/Vendor.swift` | existing | — |
| manifest | S1 Firestore-runtime/gate closure | `Peezy 4.0/MainInterface/Views/Paywall/PaywallGateView.swift` | existing | only the §8.9.3 admission edit at its `redeemGiftCode` call site; product/UI semantics otherwise byte-identical |
| manifest | S1 Firestore-runtime/gate closure | `Peezy 4.0/Tasks/FlowEngine/FlowDefinition.swift` | existing | — |
| manifest | S1 Firestore-runtime/gate closure | `Peezy 4.0/Tasks/FlowEngine/InAppTaskFlows.swift` | existing | — |
| manifest | S1 Firestore-runtime/gate closure | `Peezy 4.0/Tasks/FlowEngine/MoveAnswersStore.swift` | existing | — |
| manifest | S1 Firestore-runtime/gate closure | `Peezy 4.0/Tasks/Task Cards/ScanInventoryFlow.swift` | existing | — |
| manifest | S4 recovery/privacy | `Peezy 4.0/Tasks/Durable/DurableStoreRecoveryCoordinator.swift` | new | — |
| manifest | S4 recovery/privacy | `Peezy 4.0/Tasks/Durable/DurableStoreRecoveryView.swift` | new | — |
| manifest | S4 recovery/privacy | `Peezy 4.0/Tasks/Durable/LocalPrivacyPurgeCoordinator.swift` | new | contains the Firestore runtime, completion-presentation owner, client-telemetry authority, and room/media/narration-transfer actor |
| manifest | S4 recovery/privacy | `Peezy 4.0/MainInterface/Models/AnalyticsEvents.swift` | existing | — |
| manifest | S4 recovery/privacy | `Peezy 4.0/Assessment/AssessmentModels/AssessmentCoordinator.swift` | existing | — |
| manifest | S4 recovery/privacy | `Peezy 4.0/Inventory/ViewModels/RoomCaptureViewModel.swift` | existing | — |
| manifest | S4 recovery/privacy | `Peezy 4.0/Inventory/Views/InventoryItemConfirmView.swift` | existing | additionally only §11's media-transfer/buffer registry, cancellation, and generation guards |
| manifest | S4 recovery/privacy (S1 first, per ledger) | `Peezy 4.0/Inventory/Models/InventorySessionManager.swift` | existing (baseline `d321547`) | migrates exactly six `Firestore.firestore()` occurrences to `FirestoreRuntimeOwner` and changes `pendingNarration` to hold actor-issued lease handles only; `InventorySessionManager→InventoryAPIClient` §8.9.3 admission limited to these call sites |
| manifest | S4 recovery/privacy | `Peezy 4.0/Inventory/Views/InventoryCameraView.swift` | existing (baseline `d321547`) | changes `pendingNarrationTranscript` to hold actor-issued lease handles only |
| manifest | S4 recovery/privacy | `Peezy 4.0/Inventory/Services/NarrationService.swift` | existing (baseline `d321547`) | changes `start` to require an actor lease |
| manifest | S5 provider identity | `Peezy 4.0/Auth/GoogleIdentityAuthority.swift` | new | sole location of any direct `GIDSignIn.sharedInstance` call |
| manifest | S5 provider identity | `Peezy 4.0/MainInterface/Models/NotificationIdentityAuthority.swift` | new | sole location of any `UNUserNotificationCenter`/`Messaging` deletion call |
| manifest | S5 provider identity | `Peezy 4.0/Auth/AuthViewModel.swift` | existing | only for the injected Apple checker/observer, routing every existing Google SDK operation (configuration/sign-in, current-provider-UID observation, callback settlement, disconnect, and sign-out) through the one `GoogleIdentityAuthority`, the auth-transition purge hook, and fixed diagnostics; no authorization-code/token persistence, auth UI change, or sign-in product-semantics redesign; also Keychain/auth/readiness/provider conformances with `HandoffSessionStore.swift` |

| Source | Preexisting path (not a new entry) | Broadening / constraint (exact literal) |
|---|---|---|
| manifest | `WorkflowService.swift`, `SupportChatService.swift`, `SuppliesKitView.swift`, `BookYourMoversView.swift` | not repeated as additions; existing authorization merely narrowed by the applicable §11 clauses |
| manifest | every preexisting §8.2 path containing a direct `Firestore.firestore()` acquisition | broadened for the mechanical runtime-provider substitution and operation-registration/cancellation guard—no product behavior edit |
| manifest | `Peezy 4.0/MainInterface/Models/PeezyV1App.swift` | broadened only for §8/§11's process-wide runtime identities, Google callback forwarding, notification-identity state machine, client-telemetry authority and preconfiguration, local-purge mount, and completion-presentation mount; S7 retains as sole ingress/barrier/recovery/privacy-purge mount |
| manifest | `Peezy 4.0/MainInterface/Views/AppRootView.swift` | broadened only for the completion surface |
| manifest | `Peezy-4-0-Info.plist` (S7) | adds only the three exact Boolean collection flags in §§11/11.1 |
| manifest | `Peezy 4.0.xcodeproj/project.pbxproj` | remains byte-identical |
| spec | `Peezy 4.0.xcodeproj/project.pbxproj` | not edited; synchronized app/test root groups auto-enumerate new Swift files; enumeration failure stops execution as a boundary contradiction |

- `rg` gate: zero production `Firestore.firestore()` occurrence outside `LocalPrivacyPurgeCoordinator.swift` and the one initialization line in `PeezyV1App.swift`; tests may inject Firestore.
- Retained services capture `FirestoreRuntimeGeneration`, all operations register/unregister, and stale-generation callbacks are discarded.
- For `SubscriptionManager→SubscriptionAPIClient`, `PeezyStackViewModel→PeezyClient`, and `InventorySessionManager→InventoryAPIClient`: static sole-caller graphs prove no transport edit is required; their fixtures cover every §8.9.3 consumer projection, held responses across generation change, and no stale application. (manifest)

### C10.3 Single-owner/ordered-integrator ledger

| Source | Overlap | Ordered writer/reviewer sequence |
|---|---|---|
| spec | `firestore.rules` | S1 owns policy/create and all H56/content carve-outs up front → S3 integrates scheduler/intent/system-quarantine denial and re-reviews full file; S5 consumes and verifies but does not write rules |
| spec | `functions/taskPlan.js` | S2 owns reducer/H54 → S3 adds intent claim and re-runs S2 tests |
| spec | `TaskPlanService.swift` | S1 is sole writer and defines all typed callable DTOs/transports up front; S2/S5/S7 consume them and may add tests only |
| spec | `PeezyMainContainer.swift` | S4 shared surface → S7 route follow-on |
| spec | `FlowExitControl.swift` | S5 exact-attempt lease/barrier → S8 scene lease follow-on |
| spec | `functions/rules-tests/firestoreRules.test.js` | S1 owns policy/create plus H56/content/reset-record cases → S3 adds intent and explicit system-quarantine get/list/create/update/delete denial and is final integrator; S5 re-runs but does not edit |
| spec | `functions/tests/taskPlan.test.js` | S2 reducer/H54 → S3 claim follow-on |
| spec | `DispositionContractTests.swift` | S1 projection/base contract → S2 command transport compatibility |
| spec | `TaskPlanDispositionTests.swift` | S2 command transport → S7 claim follow-on |
| spec | `ConversationFlowTests.swift` | S2 contributes workflow request/receipt cases first → S5 owns and integrates flow/handoff/legacy cases → S6 contributes clean-adapter cases → S5 performs final full-class review |
| spec | `TaskDispositionSurfaceTests.swift` | S4 owns tri-state/shared-surface matrix → S5 contributes workflow/handoff/support caller cases → S6 contributes bespoke adapter/packing/movers mounts → S4 performs final full-class review |
| spec | `LegacyTaskMutationFenceTests.swift` | S5 owns generic/server/local-adoption fence matrix → S6 contributes booking/readiness/packing/movers and H54_REOPENED cases → S5 performs final full-class review |
| spec | `PeezyNudgeAnswerTests.swift` | S1 contributes spawn expectation/token cases → S5 owns and integrates legacy claim/reset/non-adoption cases and final full-class review |
| spec | `HandoffSessionTests.swift`, `ContextualOutcomeTests.swift` | S5 owns core RED/GREEN → S6 adds clean-adapter mount cases and re-runs full classes |
| manifest | `functions/accountDeletionFence.js` | S2 creates the marker/capability/cleanup/two-reconciler and marker/work-guard core → S3 adds the sole outbound-lease owner, complete writer/provider registries, and global-scheduler, retained-copy, and historical-migration integration and performs final whole-file review |
| manifest | `functions/index.js` | S2 replaces `deleteAccount`, adds both scheduled reconciler exports, and proves zero Storage-finalizer export → S3 integrates fences for the three inline writers, moves/awaits support notification after its committed record, and performs final whole-file review |
| manifest | `functions/tests/accountDeletionFence.test.js` | S2 owns core/remote/zero-finalizer/two-reconciler/provider-cache/historical-migration cases → S3 adds outbound lease/payload/call-graph, registry/global-cleanup/retained-copy/export-graph cases and performs final full-file review |
| manifest | `firestore.rules`, `functions/rules-tests/firestoreRules.test.js` | Existing S1 owner pass remains first → S3 integrates account-deletion/system/query boundaries and performs final full-file review |
| manifest | `functions/package.json`, `functions/package-lock.json`, `storage.rules`, `functions/scripts/purgeLegacyResolvedProviders.js`, `functions/scripts/purgeLegacyDeletedAccounts.js`, `functions/scripts/sealAccountDeletionProviderEvidence.js`, `functions/accountDeletionProviderEvidenceV1.json` | S3 is sole writer; every other slice consumes/re-runs only |
| manifest | `functions/resolveProvider.js`, `functions/supportAdmin.js` | S2 is sole writer for cache removal and exact provider/lease integration; S3 verifies registry coverage without editing |
| manifest | `functions/notifySupport.js`, `functions/researchTask.js`, `functions/peezyChat.js`, `functions/packageInventory.js`, `functions/submitCheckIn.js`, `functions/submitCheckInCore.js`, `functions/entitlement.js`, `functions/validateSubscription.js`, `functions/processInventory.js` | S3 is sole Phase-2 writer and performs the final static writer/provider-registry review; in `functions/processInventory.js` it edits only process success/error and `onInventoryRoomWritten` shared-fence calls plus the Anthropic shared-lease call sites; no second slice edits these files |
| manifest | `Peezy 4.0/Inventory/Models/InventorySessionManager.swift` | S1 migrates exactly its six `Firestore.firestore()` occurrences to `FirestoreRuntimeOwner` → S4 changes only `pendingNarration` to hold actor-issued lease handles; no other edit is authorized |
| manifest | `Peezy 4.0/Inventory/Views/InventoryCameraView.swift`, `Peezy 4.0/Inventory/Services/NarrationService.swift` | S4 changes only `pendingNarrationTranscript` to hold actor-issued lease handles and `NarrationService.start` to require an actor lease; no other edit is authorized |
| manifest | every other `ACCOUNT_DELETION_FENCE_WRITERS_V1` path | its already-frozen S1/S2/S3/S9 owner adds that file's shared-fence call and no other slice edits it; S3 performs the cross-file static registry review without acquiring write ownership |
| spec, manifest | `Peezy 4.0Tests/AppRootAuthRaceTests.swift` | S4 owns the class (spec); Google callback-slot fixtures, the sole-`GIDSignIn.sharedInstance` call-site scan, and the sole-`UNUserNotificationCenter`/`Messaging` deletion-call-site scan: contributing slice not stated (manifest) |

| Source | Ordered slice ledger (exact literal) |
|---|---|
| manifest | S1 seams/reset stamps/runtime consumers → S2 workflow/server implementation → S3 scheduler/migration/deletion/outbound final integration → S4 recovery/privacy UI and orchestration → S5 identity/provider conformance → S7 app mount |
| spec | Integrate S1→S2→S4→S5 on the critical path; S3 follows S2; S7 row routing follows S4 and outcome routing follows S5; S6 follows S5; S8/S9 may be authored independently only with disjoint files |

- Research links belong only to S9.
- `TaskRowHeader.swift` is verification-only and unchanged.
- No slice may edit a path merely because a compiler or test names it.
- Existing files otherwise retain their frozen owners; final review does not authorize an extra write outside the named sequence.
- The `ACCOUNT_DELETION_FENCE_WRITERS_V1` rows above plus the every-other-path rule are the complete ownership assignment for the registry. (manifest)

### C10.4 Exact test files and ownership

| Source | Owner | Node/rules test file | Status | Owned coverage (exact literal) |
|---|---|---|---|---|
| spec | S1 | `functions/tests/taskCanonical.test.js` | new | exact timestamp-wire and fractional complete-request fixtures |
| spec | S1 | `functions/tests/taskInteraction.test.js` | new | — |
| spec | S1 | `functions/tests/taskInteractionProjection.test.js` | new | — |
| spec | S1 | `functions/tests/spawnTasks.test.js` | existing | — |
| spec | S1 | `functions/spawnTasks.test.js` | existing | — |
| spec | S1 | `functions/tests/taskCatalogMovers.test.js` | existing | — |
| spec | S1 | `functions/rules-tests/firestoreRules.test.js` | existing | owner projection/generation/direct-denial plus independent Firestore-budget oracle portions |
| spec | S2 | `functions/tests/dispositionContract.test.js` | existing | — |
| spec | S2 | `functions/tests/taskDisposition.test.js` | new | every policy-field and §4.7 legacy/packing/support action, six-value receipt disposition/presence, restoration preflight/error parity, trusted-display/fallback parity, concrete server-write-time behavior, and fractional fingerprint/replay |
| spec | S2 | `functions/tests/getWorkflowQualifying.test.js` | existing | — |
| spec | S2 | `functions/tests/taskPlan.test.js` | existing | first pass including original-bound copied confirmation evidence plus reset epoch aliases/tombstones/crash boundaries |
| spec | S2 | `functions/tests/callableAuth.test.js` | existing | policy/legacy workflow payload cases |
| spec | S3 | `functions/tests/dispositionTriggers.test.js` | existing | persisted prepass cursor, `OriginalEventBytesV1`, attempt `1→2→quarantine`, mandatory 100-poison-before-valid/full-seven-scan regression, high-water, and the seven scan/index races |
| spec | S3 | `functions/tests/notificationIntents.test.js` | new | — |
| spec | S3 | `functions/tests/taskPlan.test.js`, `functions/rules-tests/firestoreRules.test.js` | existing | the route-expiry, follow-on taskPlan, and rules-test portions |
| spec | S9 | `functions/tests/researchTask.test.js` | new | — |
| spec | verification-only unchanged | `functions/tests/accountabilityLadder.test.js`, `functions/tests/entitlement.test.js`, `functions/tests/packSimulation.test.js`, `functions/tests/processInventoryMerge.test.js`, `functions/tests/processInventoryModel.test.js`, `functions/tests/processInventoryPacking.test.js`, `functions/tests/seedCubeSheet.test.js`, `functions/tests/submitCheckIn.test.js`, `functions/tests/validateSubscription.test.js` | existing | — |
| manifest | S2 → S3 | `functions/tests/accountDeletionFence.test.js` | new | deletion fencing, provider-purge and historical-account-migration core/CLI guards, zero-finalizer/two-reconciler, package/lock/config/destination/evidence digests, and exact export/options coverage; plus (with `functions/rules-tests/firestoreRules.test.js`) the exact two-reconciler export graph, provider-call graph/constructors/lease semantics, external families, provider-purge pure core/CLI guards, zero-finalizer graph, Firestore module hash/constants, Storage 7.18.0 tuple/generation semantics, bucket metageneration/config digest and soft-delete/version/hold gates, Firestore Admin/Auth config/version observation, destination inventories, both reconciler state/work fences, historical migration, package/lock/config/evidence digests, and Rules boundaries |
| manifest | (slice not stated) | `functions/tests/taskPlan.test.js` | existing | every `inspectCommittedOperation` request/path/kind/state/fingerprint/identity/replay/error branch and action-registry/export coverage |
| manifest | S3 | `functions/tests/dispositionTriggers.test.js` | existing | Migration/codec fixtures; no new Node test file is implied |

| Source | Owner | Swift test file | Status | Suite(s) | Owned coverage (exact literal) |
|---|---|---|---|---|---|
| spec | S1 | `Peezy 4.0Tests/TaskCanonicalTests.swift` | new | `TaskCanonicalTests` | exact timestamp-wire and COMPLETE_BOOKING/REPLACE_QUOTES fractional parity |
| spec | S1 | `Peezy 4.0Tests/TaskInteractionTests.swift` | new | `TaskInteractionTests` | — |
| spec | S1 | `Peezy 4.0Tests/TaskInteractionProjectionTests.swift` | new | `TaskInteractionProjectionTests` | — |
| spec | S1 | `Peezy 4.0Tests/DispositionContractTests.swift` | existing | `DispositionContractTests` | first-pass |
| spec | S2 | `Peezy 4.0Tests/TaskPlanDispositionTests.swift` | new | `TaskPlanDispositionTests` | trusted-display/fallback, receipt disposition, restoration preflight, per-epoch reset alias/tombstone and six-phase local crash parity |
| spec | S2 | `Peezy 4.0Tests/DispositionTriggerSelectionTests.swift` | new | `DispositionTriggerSelectionTests` | — |
| spec | S2 | `Peezy 4.0Tests/TaskSupersessionTests.swift` | existing | `TaskSupersessionTests` | copied-evidence/reset and exact SUPERSEDED/RETIRED pairings |
| spec | S4 | `Peezy 4.0Tests/TaskDispositionSurfaceTests.swift` | new | `TaskDispositionSurfaceTests` | — |
| spec | S4 | `Peezy 4.0Tests/TaskRowLegacySnapshotTests.swift` | new | `TaskRowLegacySnapshotTests` | — |
| spec | S4 | `Peezy 4.0Tests/TasksStoreNamespaceTests.swift` | new | `TasksStoreNamespaceTests` | — |
| spec | S4 | `Peezy 4.0Tests/AppRootAuthRaceTests.swift` | new | `AppRootAuthRaceTests` | — |
| spec | S4 | `Peezy 4.0Tests/TaskGroupingTests.swift` | existing | `TaskGroupingTests` | — |
| spec | S5 | `Peezy 4.0Tests/HandoffSessionTests.swift` | new | `HandoffSessionTests` | ordinary/reconciliation restoration-preflight durability |
| spec | S5 | `Peezy 4.0Tests/ContextualOutcomeTests.swift` | new | `ContextualOutcomeTests` | — |
| spec | S5 | `Peezy 4.0Tests/LegacyTaskMutationFenceTests.swift` | new | `LegacyTaskMutationFenceTests` | fractional REPLACE_QUOTES replay |
| spec | S5 | `Peezy 4.0Tests/PeezyNudgeAnswerTests.swift` | existing | `PeezyNudgeAnswerTests` | — |
| spec | S5 | `Peezy 4.0Tests/ConversationFlowTests.swift` | existing | `ConversationFlowTests` | six-value workflow disposition consumption; S6 contributes its ordered adapter/packing/movers cases to the applicable classes |
| spec | S6 | `Peezy 4.0Tests/MoversChainCoordinatorTests.swift` | existing | `MoversChainCoordinatorTests`, `MoversChainHandshakeTests` | H56 queue and legacy generation-fence boundaries |
| spec | S7 | `Peezy 4.0Tests/TaskRouteTests.swift` | new | `TaskRouteTests` | exact 60-second refresh lease/three crash boundaries and task-route UTC-wire→epoch-millisecond parity/min/expiry matrix |
| spec | S8 | `Peezy 4.0Tests/FlowSceneFlushTests.swift` | new | `FlowSceneFlushTests` | — |
| spec | S9 | `Peezy 4.0Tests/ResearchPostureTests.swift` | new | `ResearchPostureTests` | — |
| manifest | S4 | `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | new | `DurableStoreRecoveryTests` | every client decoder, auth/drift, coalescing, loaded-application, and local account-purge branch; the presentation/purge/telemetry/narration actors |
| manifest | (slice not stated) | `Peezy 4.0Tests/AppRootAuthRaceTests.swift` | new | `AppRootAuthRaceTests` | auth-root replacement/presentation survival, both-manual nonconsuming links, notification-generation/auth races, Google callback-slot fixtures, the sole-`GIDSignIn.sharedInstance` call-site scan, and the sole-`UNUserNotificationCenter`/`Messaging` deletion-call-site scan |

| Source | Test file | Named test (exact literal) | Assertion (exact literal) |
|---|---|---|---|
| manifest | `functions/tests/accountDeletionFence.test.js` | `timeouts do not exceed 300 seconds` | source-scanning only `DELETION_PARTICIPATING_FUNCTIONS_V1` plus its Anthropic/Twilio/SMTP client timeout constants and failing above 300, while asserting non-participating `changeTaskPlan` remains 540 |
| manifest | `functions/tests/accountDeletionFence.test.js` | `active exports contain no dynamic server log sink` | — |
| manifest | `functions/tests/accountDeletionFence.test.js` | `Auth destination partition is completely falsifiable` | — |
| manifest | `functions/tests/accountDeletionFence.test.js` | `sealer refuses nonzero matches, backlog, and nonfinite retention` | — |
| manifest | `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | `UID-interpolated preference keys are registry-complete` | a source scan failing on any UID-interpolated `UserDefaults` or `CFPreferences` key outside the ten-key registry |
| manifest | `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | `Release call graph and adversarial NSError are sink-free` | — |
| manifest | `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | `Firebase Auth keychain item is absent after terminal detach` | — |

- No extra Swift test file or suite is added.
- No broad glob and no additional test file is authorized.

### C10.5 Explicit exclusions

| Source | Excluded / protected path or class | Status (exact literal) |
|---|---|---|
| spec | `functions/index.js` | unchanged |
| spec | `firebase.json` | unchanged |
| spec | `functions/package.json` | unchanged |
| spec | `functions/taskCatalogData.json` | unchanged |
| spec | `functions/flowDefinitionsData.json` | unchanged |
| spec | `public/admin/index.html` | unchanged |
| spec | all support server files | unchanged |
| spec | the Xcode project file | unchanged |
| spec | active catalog/flow data, router shadows, live config | unchanged |
| spec | `PEEZY_STATE.md` | unchanged |
| spec | Build 25 WIP | unchanged |
| spec | Main-root untracked `File.txt` | protected user data, not an authorized implementation path; sole permitted Phase 2 analogue is the guarded empty worktree-only prerequisite, never staged, manifested, reviewed as product code, patched, or copied from main |
| spec | seed/deploy/production call/write/send | not permitted |
| spec | `diagnose-and-generate.js`, `functions/testProfile/seedTestUser.js` | forbidden on a policy-activated target until a separately authorized Phase 3 preflight upgrades or retires them |
| spec | Scanner/Inventory mounts | excluded |
| spec | `TaskRowHeader.swift` | verification-only and unchanged |
| manifest | `functions/index.js`, `functions/package.json`, `functions/package-lock.json`, `functions/notifySupport.js`, `functions/supportAdmin.js`, and exact call sites in the four `d321547` files | no longer excluded |
| manifest | all support-server files other than the explicitly authorized `functions/notifySupport.js` and `functions/supportAdmin.js` | remain excluded |
| manifest | `functions/notifyAdmin.js` | remains excluded and deployment-inactive |
| manifest | `firebase.json`, `functions/taskCatalogData.json`, `functions/flowDefinitionsData.json`, `public/admin/index.html`, the Xcode project, active catalog/flow data, router shadows, live config, `PEEZY_STATE.md` | remain excluded |
| manifest | every Build 25 WIP byte outside the four exact per-file scopes | remains excluded |
| manifest | any unnamed support path | not authorized |
| manifest | the four `d321547` files (`functions/processInventory.js`, `Peezy 4.0/Inventory/Models/InventorySessionManager.swift`, `Peezy 4.0/Inventory/Views/InventoryCameraView.swift`, `Peezy 4.0/Inventory/Services/NarrationService.swift`) | No other byte in those four files is authorized for Phase 2 |

### C10.6 Literal totals

| Quantity | Source | Value (exact literal) |
|---|---|---|
| Authorized client paths (§8.2 entries) | spec | 58 entries, 56 unique paths (`PeezyMainContainer.swift` and `FlowExitControl.swift` each listed twice) |
| Client path additions | manifest | exactly 33 unique client paths; none duplicates a frozen §8.2 path |
| Authorized client paths after additions | manifest | 89 unique authorized client paths |
| Newly authorized direct-caller paths | manifest | 19 |
| Swift test files | spec | 21 unique files |
| Swift test files after additions | manifest | 22 unique Swift test files |
| Named suites | spec | 22 (expected set `E`; Movers contributes two suites) |
| Named suites after additions | manifest | 23 suites |
| Node `--test` envelope files | spec | 23-file Node envelope |
| Node `--test` envelope files after additions | manifest | 24 files |
| Node/rules test files across both commands | manifest | 25 unique Node/rules test files |
| Rules test files (separate emulator command) | spec, manifest | 1 (`functions/rules-tests/firestoreRules.test.js`) |
| `Firestore.firestore()` occurrences migrated in `InventorySessionManager.swift` | manifest | exactly six |
| Info.plist additions | manifest | the three exact Boolean collection flags |
| UID-interpolated preference key registry | manifest | ten-key registry |

### C10.7 Frozen toolchain

| Source | Tool | Frozen value |
|---|---|---|
| spec | Xcode | 26.6, build `17F113` |
| spec | simulator | iPhone 17 Pro, iOS 26.5, UDID `DC0CC10C-6DB0-496A-8B0E-51E60D958A27` |
| spec | Node | `/opt/homebrew/opt/node@24/bin/node`, `v24.19.0` |
| spec | Java | `/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`, OpenJDK `21.0.12.1` |
| spec | Firebase CLI | `/opt/homebrew/bin/firebase`, `15.6.0`; its `#!/usr/bin/env node` must resolve through the Node 24-first PATH below |
| spec | xcresulttool | Xcode 26.6 build `24757`, schema `0.1.0`; JSON is default and `--format json` is invalid |
| spec | Firestore emulator jar | `/Users/adampowell/.cache/firebase/emulators/cloud-firestore-emulator-v1.20.2.jar`, SHA-256 `4a117fc297b1441eac1b7756e80442e86ef88865b9e3caf6f59eabf83da574f8` |
| manifest | `functions/package.json` direct dependency | `"@google-cloud/firestore":"7.11.6"` |
| manifest | `functions/package-lock.json` transitive resolution | `@google-cloud/storage` exact 7.18.0 |

### C10.8 Simulator build and named-class test envelope

| Source | Envelope constraint (exact literal) |
|---|---|
| spec | Result path absent at spec freeze; execution first requires the absence check; it does not delete or overwrite an existing result |
| spec | There is no `-testPlan` |
| spec | `PEEZY_RUN_FIRESTORE_INTEGRATION` is unset |
| spec | UI tests are skipped |
| manifest | Insert `-only-testing:'Peezy 4.0Tests/DurableStoreRecoveryTests'` immediately after `DispositionTriggerSelectionTests` |
| manifest | Insert `DurableStoreRecoveryTests` at the same position in expected set `E` |

```bash
test ! -e '/tmp/peezy-phase2-v5-final-eedc6add.xcresult'

env -u PEEZY_RUN_FIRESTORE_INTEGRATION xcodebuild build \
  -project 'Peezy 4.0.xcodeproj' -scheme 'Peezy 4.0' \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=DC0CC10C-6DB0-496A-8B0E-51E60D958A27' \
  CODE_SIGNING_ALLOWED=NO

env -u PEEZY_RUN_FIRESTORE_INTEGRATION xcodebuild test \
  -project 'Peezy 4.0.xcodeproj' -scheme 'Peezy 4.0' \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=DC0CC10C-6DB0-496A-8B0E-51E60D958A27' \
  -only-testing:'Peezy 4.0Tests/ConversationFlowTests' \
  -only-testing:'Peezy 4.0Tests/DispositionContractTests' \
  -only-testing:'Peezy 4.0Tests/TaskGroupingTests' \
  -only-testing:'Peezy 4.0Tests/TaskSupersessionTests' \
  -only-testing:'Peezy 4.0Tests/TaskInteractionTests' \
  -only-testing:'Peezy 4.0Tests/TaskInteractionProjectionTests' \
  -only-testing:'Peezy 4.0Tests/TaskCanonicalTests' \
  -only-testing:'Peezy 4.0Tests/HandoffSessionTests' \
  -only-testing:'Peezy 4.0Tests/ContextualOutcomeTests' \
  -only-testing:'Peezy 4.0Tests/TaskPlanDispositionTests' \
  -only-testing:'Peezy 4.0Tests/DispositionTriggerSelectionTests' \
  -only-testing:'Peezy 4.0Tests/TaskDispositionSurfaceTests' \
  -only-testing:'Peezy 4.0Tests/TaskRowLegacySnapshotTests' \
  -only-testing:'Peezy 4.0Tests/TasksStoreNamespaceTests' \
  -only-testing:'Peezy 4.0Tests/AppRootAuthRaceTests' \
  -only-testing:'Peezy 4.0Tests/LegacyTaskMutationFenceTests' \
  -only-testing:'Peezy 4.0Tests/PeezyNudgeAnswerTests' \
  -only-testing:'Peezy 4.0Tests/TaskRouteTests' \
  -only-testing:'Peezy 4.0Tests/FlowSceneFlushTests' \
  -only-testing:'Peezy 4.0Tests/ResearchPostureTests' \
  -only-testing:'Peezy 4.0Tests/MoversChainCoordinatorTests' \
  -only-testing:'Peezy 4.0Tests/MoversChainHandshakeTests' \
  -skip-testing:'Peezy 4.0UITests' \
  -resultBundlePath '/tmp/peezy-phase2-v5-final-eedc6add.xcresult' \
  CODE_SIGNING_ALLOWED=NO
```

```bash
xcrun xcresulttool get test-results tests \
  --path '/tmp/peezy-phase2-v5-final-eedc6add.xcresult' --compact | \
/opt/homebrew/opt/node@24/bin/node -e '
const fs=require("node:fs");
const E=new Set(["ConversationFlowTests","DispositionContractTests","TaskGroupingTests","TaskSupersessionTests","TaskInteractionTests","TaskInteractionProjectionTests","TaskCanonicalTests","HandoffSessionTests","ContextualOutcomeTests","TaskPlanDispositionTests","DispositionTriggerSelectionTests","TaskDispositionSurfaceTests","TaskRowLegacySnapshotTests","TasksStoreNamespaceTests","AppRootAuthRaceTests","LegacyTaskMutationFenceTests","PeezyNudgeAnswerTests","TaskRouteTests","FlowSceneFlushTests","ResearchPostureTests","MoversChainCoordinatorTests","MoversChainHandshakeTests"]);
const J=JSON.parse(fs.readFileSync(0,"utf8"));
const seen=new Set(),count=new Map([...E].map(x=>[x,0])),units=[],uis=[],bad=[];
function walk(n,owner=null){
  if(!n||typeof n!=="object")return;
  if(n.nodeType==="Unit test bundle")units.push(n.name);
  if(n.nodeType==="UI test bundle")uis.push(n.name);
  if(n.nodeType==="Test Suite"){
    if(E.has(n.name)){owner=n.name;seen.add(n.name)}
    else if(/Tests$/.test(n.name||"")&&n.name!=="Peezy 4.0Tests")owner=null;
  }
  if(n.nodeType==="Test Case"){
    if(!owner)bad.push(`unexpected case ${n.name}`);else count.set(owner,count.get(owner)+1);
    if(n.result!=="Passed")bad.push(`${owner||"?"}/${n.name}:${n.result}`);
  }
  for(const c of n.children||[])walk(c,owner);
}
for(const n of J.testNodes||[])walk(n);
if(units.length!==1||units[0]!=="Peezy 4.0Tests")bad.push(`unit bundles=${JSON.stringify(units)}`);
if(uis.length)bad.push(`ui bundles=${JSON.stringify(uis)}`);
for(const x of E)if(!seen.has(x)||count.get(x)===0)bad.push(`missing/empty ${x}`);
if(seen.size!==E.size)bad.push(`suite set=${JSON.stringify([...seen].sort())}`);
if(bad.length){console.error(bad.join("\n"));process.exit(1)}
console.log(`PASS ${E.size} suites ${[...count.values()].reduce((a,b)=>a+b,0)} cases`);
'
```

Manifest-inserted lines (positions per the table above):

```text
  -only-testing:'Peezy 4.0Tests/DispositionTriggerSelectionTests' \
  -only-testing:'Peezy 4.0Tests/DurableStoreRecoveryTests' \
  -only-testing:'Peezy 4.0Tests/TaskDispositionSurfaceTests' \
```

```text
"DispositionTriggerSelectionTests","DurableStoreRecoveryTests","TaskDispositionSurfaceTests"
```

### C10.9 Offline Node and rules commands

```bash
env -u ADAM_NOTIFY_NUMBER -u ANTHROPIC_API_KEY -u GMAIL_APP_PASSWORD \
  -u SUPPORT_ADMIN_EMAILS -u SUPPORT_NOTIFY_EMAIL -u SUPPORT_NOTIFY_SMS \
  -u TWILIO_ACCOUNT_SID -u TWILIO_AUTH_TOKEN -u TWILIO_FROM_NUMBER \
  -u GOOGLE_APPLICATION_CREDENTIALS -u GCLOUD_PROJECT \
  -u GOOGLE_CLOUD_PROJECT -u FIREBASE_CONFIG -u FIRESTORE_EMULATOR_HOST \
  /opt/homebrew/opt/node@24/bin/node --test \
  functions/tests/accountabilityLadder.test.js \
  functions/tests/callableAuth.test.js \
  functions/tests/dispositionContract.test.js \
  functions/tests/dispositionTriggers.test.js \
  functions/tests/entitlement.test.js \
  functions/tests/getWorkflowQualifying.test.js \
  functions/tests/packSimulation.test.js \
  functions/tests/processInventoryMerge.test.js \
  functions/tests/processInventoryModel.test.js \
  functions/tests/processInventoryPacking.test.js \
  functions/tests/seedCubeSheet.test.js \
  functions/tests/spawnTasks.test.js \
  functions/tests/submitCheckIn.test.js \
  functions/tests/taskCanonical.test.js \
  functions/tests/taskCatalogMovers.test.js \
  functions/tests/taskPlan.test.js \
  functions/tests/validateSubscription.test.js \
  functions/spawnTasks.test.js \
  functions/tests/taskInteraction.test.js \
  functions/tests/taskInteractionProjection.test.js \
  functions/tests/taskDisposition.test.js \
  functions/tests/notificationIntents.test.js \
  functions/tests/researchTask.test.js
```

Manifest-inserted line (immediately before existing `functions/tests/accountabilityLadder.test.js`):

```text
  functions/tests/accountDeletionFence.test.js \
  functions/tests/accountabilityLadder.test.js \
```

| Source | Rules command | `--only` value |
|---|---|---|
| spec | `firebase emulators:exec` against the local demo emulator | `--only firestore` |
| manifest | `firebase emulators:exec` | `--only firestore,storage` |

| Source | Rules command block |
|---|---|
| spec | `--only firestore` |

```bash
env -u ADAM_NOTIFY_NUMBER -u ANTHROPIC_API_KEY -u GMAIL_APP_PASSWORD \
  -u SUPPORT_ADMIN_EMAILS -u SUPPORT_NOTIFY_EMAIL -u SUPPORT_NOTIFY_SMS \
  -u TWILIO_ACCOUNT_SID -u TWILIO_AUTH_TOKEN -u TWILIO_FROM_NUMBER \
  -u GOOGLE_APPLICATION_CREDENTIALS -u GCLOUD_PROJECT \
  -u GOOGLE_CLOUD_PROJECT -u FIREBASE_CONFIG -u FIRESTORE_EMULATOR_HOST \
  JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
  PATH=/opt/homebrew/opt/node@24/bin:/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:/usr/bin:/bin \
  FIREBASE_CLI_DISABLE_TELEMETRY=1 FIREBASE_CLI_DISABLE_UPDATE_CHECK=1 \
  /opt/homebrew/bin/firebase emulators:exec --only firestore \
  --project demo-peezy-phase1 \
  "/opt/homebrew/opt/node@24/bin/node --test functions/rules-tests/firestoreRules.test.js"
```

| Source | Rules command block |
|---|---|
| manifest | `--only firestore,storage` |

```bash
env -u ADAM_NOTIFY_NUMBER -u ANTHROPIC_API_KEY -u GMAIL_APP_PASSWORD \
  -u SUPPORT_ADMIN_EMAILS -u SUPPORT_NOTIFY_EMAIL -u SUPPORT_NOTIFY_SMS \
  -u TWILIO_ACCOUNT_SID -u TWILIO_AUTH_TOKEN -u TWILIO_FROM_NUMBER \
  -u GOOGLE_APPLICATION_CREDENTIALS -u GCLOUD_PROJECT \
  -u GOOGLE_CLOUD_PROJECT -u FIREBASE_CONFIG -u FIRESTORE_EMULATOR_HOST \
  JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
  PATH=/opt/homebrew/opt/node@24/bin:/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:/usr/bin:/bin \
  FIREBASE_CLI_DISABLE_TELEMETRY=1 FIREBASE_CLI_DISABLE_UPDATE_CHECK=1 \
  /opt/homebrew/bin/firebase emulators:exec --only firestore,storage \
  --project demo-peezy-phase1 \
  "/opt/homebrew/opt/node@24/bin/node --test functions/rules-tests/firestoreRules.test.js"
```

| Source | Static check | Exact literal |
|---|---|---|
| spec | Node 24 `--check` | once per touched `.js` path in §8 |
| manifest | Node `--check` additions | `functions/scripts/migrateOversizeEvents.js`, `functions/scripts/purgeLegacyResolvedProviders.js`, `functions/scripts/purgeLegacyDeletedAccounts.js`, `functions/scripts/sealAccountDeletionProviderEvidence.js` |
| spec | tracked diff check | `git diff --check` on the existing tracked paths enumerated there |
| spec | new-path diff check | `git diff --no-index --check /dev/null` with each new path supplied as the next literal argument |
| spec | manifest derivation | No glob or command substitution may derive the manifest, and no broad test glob may absorb protected Build 25 tests |

### C10.10 Worktree, review, and patch procedure

- This procedure is recorded but is not run at the spec gate. (spec)

| Source | Frozen value | Exact literal |
|---|---|---|
| spec | `phase2_base` | `b4b047d29bea6a1721729b69e0d01aa7a1dc9923` |
| spec | `phase2_main_root` | `'/Users/adampowell/Desktop/Peezy 4.0'` |
| spec | `phase2_main_file` | `'/Users/adampowell/Desktop/Peezy 4.0/File.txt'` |
| spec | main `File.txt` size / SHA-256 | exactly 2,124 bytes; `560eb90395307e7f69315225bd2ba7b7f9f9d8d9afa4ba509d90ebe7f1f46f47` |
| spec | `phase2_empty_hash` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| spec | `phase2_parent` | `"$(mktemp -d /tmp/peezy-phase2-v5.XXXXXX)"` |
| spec | `phase2_tree` | `"$phase2_parent/worktree"` |
| spec | `phase2_empty_file` | `"$phase2_tree/File.txt"` |
| spec | canonical patch location | `phase2_parent/PHASE2.patch` |

1. In main at absolute root `/Users/adampowell/Desktop/Peezy 4.0`: recheck branch/HEAD, every protected hash in §9.5, and absence of a Phase 2 worktree; freeze `phase2_base`, `phase2_main_root`, `phase2_main_file`; require the main file to remain a regular non-symlink of exactly 2,124 bytes with the SHA-256 above; `git cat-file -e "$phase2_base:File.txt"` must fail; the base `Peezy 4.0.xcodeproj/project.pbxproj` must contain the four existing `File.txt` reference/resource lines.
2. `phase2_parent="$(mktemp -d /tmp/peezy-phase2-v5.XXXXXX)"`; `phase2_tree="$phase2_parent/worktree"`; `git worktree add --detach "$phase2_tree" "$phase2_base"`; require worktree real path differs from `phase2_main_root`, HEAD equals `phase2_base`, initial tracked status clean, root `File.txt` absent; do not stage or commit.
3. Immediately after worktree creation and before any scaffold/build/test command: `phase2_empty_file="$phase2_tree/File.txt"`; reject unless that byte string equals the worktree root plus `/File.txt`, the real worktree remains outside main, and the path is absent; never read or copy `phase2_main_file` into the worktree.
4. Run the guard scaffold below as one fail-fast shell before creating the prerequisite; cleanup acts only when the target is the exact regular non-symlink zero-byte/hash value; EXIT handler promotes cleanup/main-guard failure to nonzero; normal cleanup clears traps only after both proofs succeed; no recursive removal, unresolved path, glob, or main-root removal.

```bash
set -euo pipefail
phase2_main_hash='560eb90395307e7f69315225bd2ba7b7f9f9d8d9afa4ba509d90ebe7f1f46f47'
phase2_empty_hash='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
phase2_main_real="$(cd "$phase2_main_root" && pwd -P)"
phase2_tree_real="$(cd "$phase2_tree" && pwd -P)"

sha256_phase2_path() {
  /usr/bin/shasum -a 256 -- "$1" | /usr/bin/awk '{print $1}'
}

assert_main_file_guard() {
  test "$phase2_main_file" = '/Users/adampowell/Desktop/Peezy 4.0/File.txt' &&
  test "$phase2_main_real" != "$phase2_tree_real" &&
  test -f "$phase2_main_file" &&
  test ! -L "$phase2_main_file" &&
  test "$(/usr/bin/stat -f %z "$phase2_main_file")" = '2124' &&
  test "$(sha256_phase2_path "$phase2_main_file")" = "$phase2_main_hash"
}

assert_empty_worktree_file_absent() {
  test "$phase2_empty_file" = "$phase2_tree/File.txt" &&
  test "$phase2_main_real" != "$phase2_tree_real" &&
  test ! -e "$phase2_empty_file" &&
  test ! -L "$phase2_empty_file" &&
  test -z "$(git -C "$phase2_tree" ls-files -- File.txt)" &&
  test -z "$(git -C "$phase2_tree" status --porcelain=v1 --untracked-files=all -- File.txt)"
}

assert_empty_worktree_file() {
  test "$phase2_empty_file" = "$phase2_tree/File.txt" &&
  test "$phase2_main_real" != "$phase2_tree_real" &&
  test -f "$phase2_empty_file" &&
  test ! -L "$phase2_empty_file" &&
  test "$(/usr/bin/stat -f %z "$phase2_empty_file")" = '0' &&
  test "$(sha256_phase2_path "$phase2_empty_file")" = "$phase2_empty_hash" &&
  test -z "$(git -C "$phase2_tree" ls-files -- File.txt)" &&
  test "$(git -C "$phase2_tree" status --porcelain=v1 --untracked-files=all -- File.txt)" = '?? File.txt'
}

cleanup_phase2_empty_file() {
  if test ! -e "$phase2_empty_file" && test ! -L "$phase2_empty_file"; then
    assert_empty_worktree_file_absent
    return
  fi
  assert_empty_worktree_file || return 70
  /bin/rm -f -- "$phase2_empty_file" || return 70
  assert_empty_worktree_file_absent
}

phase2_exit_cleanup() {
  phase2_exit_code=$?
  trap - EXIT HUP INT TERM
  cleanup_phase2_empty_file || exit 70
  assert_main_file_guard || exit 71
  exit "$phase2_exit_code"
}

assert_main_file_guard
assert_empty_worktree_file_absent
trap 'phase2_exit_cleanup' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
: > "$phase2_empty_file"
assert_empty_worktree_file
assert_main_file_guard
```

   - Final three assertions prove: regular non-symlink; size `0`; empty-file SHA-256; no index entry; path-limited porcelain status exactly `?? File.txt` before any later command.
5. Integrate S1→S2→S4→S5 on the critical path; S3 follows S2; S7 row routing follows S4 and outcome routing follows S5; S6 follows S5; S8/S9 may be authored independently only with disjoint files. Each slice is RED → GREEN → literal diff review. At worktree creation/scaffold completion, every slice checkpoint, and immediately before and after every build or test envelope, run both guards and require the only worktree status outside the current explicit Phase 2 path manifest to remain `?? File.txt`. Record base commit, dependency hashes, literal touched-path manifest, and cumulative patch SHA-256; a later edit invalidates that file's review and only its dependent review.
6. Run the exact build/XCTest/Node/rules envelopes, whole server/client diff reviews, authorized-path scan, diff checks, and protected-hash comparison in the integration worktree; no production-connected command. After the last successful verification run exactly `cleanup_phase2_empty_file && assert_empty_worktree_file_absent && assert_main_file_guard && trap - EXIT HUP INT TERM`; any failure stops patch creation. The empty prerequisite is never a touched/new-path manifest member.
7. Build the tracked patch with `git diff --binary --full-index "$phase2_base" --`, passing every existing tracked path as a separate literal argument in unsigned UTF-8 byte order. Append each new path, in the same order, by invoking `git diff --binary --no-index /dev/null` with that path as the next literal argument; exit 1 means differences, not failure. Store the canonical patch at `phase2_parent/PHASE2.patch`. Record a separate literal ordered path/SHA-256 manifest. Parse the completed patch with `git apply --numstat -z` and require its decoded paths to equal that manifest exactly; reject renames, surplus/duplicate paths, any root `File.txt`, or any path outside the authorized manifest. Reassert empty-file absence and main guard before and after patch creation.
8. Recheck dirty main HEAD and every protected hash. With main `File.txt` still at its protected hash, run `git apply --check` on the accepted canonical patch, reassert both File proofs, apply it once, reassert both again, and compare every Phase 2 path hash with the accepted integration manifest. The parsed applied path set must still exclude `File.txt`; no apply command may use `--include=File.txt` or an unrestricted worktree diff. No production-connected smoke test.
9. Reassert main's protected `File.txt`, the absent worktree prerequisite, all other protected hashes, and the exact applied path manifest. Stop before commit and show Phase-2-only plus total-working-tree diff stats separately. Do not remove or edit Build 25 WIP. Worktree retirement, if later authorized, must use Git's worktree command and may occur only after the explicit empty-file absence proof; this procedure never recursively deletes its parent.

### C10.11 D32 no-index normalizer

| Source | Caller requirement (exact literal) |
|---|---|
| manifest | Every new-file `git diff --no-index` first requires the literal manifest path to be an existing regular readable non-symlink |
| manifest | The caller sets `umask 077` before `mktemp -d`, requires that directory to remain owner-controlled mode 0700, and pre-creates two owner-controlled mode-0600, link-count-one capture files |
| manifest | Input/stdout/stderr must have pairwise-distinct device+inode identities before either capture is opened |
| manifest | The opened descriptors remain pinned through all post-run checks; a redirection failure is never normalized as diff status 1 |
| manifest | The caller pre-creates its literal empty mode-0600 `stdout` and `stderr` regular files, and passes that directory as argument five; cleanup remains narrow to that validated directory |
| manifest | The 0700 directory is the boundary against path substitution by other principals; same-UID hostile-process replacement is outside this build-script threat model, but every observable replacement before/after the run still fails closed |
| manifest | Patch mode success is status 0/1 + empty stderr; stdout is appended only after every post-run identity/mode check |
| manifest | Check mode additionally requires empty stdout |
| manifest | Tracked `git diff --check -- <literal paths>` is never normalized and requires raw zero plus empty outputs |
| manifest | `git apply --check`, `git cat-file`, and File.txt guards retain raw semantics |

| Return code | Condition (exact literal) |
|---|---|
| `72` | input not an existing regular readable non-symlink |
| `64` | mode not `check` or `patch` |
| `75` | capture-directory/capture-file/identity/FD-open/post-run identity or mode check failure |
| `73` | nonempty stderr after status 0/1 |
| `74` | check mode with nonempty stdout |
| `$phase2_diff_rc` | git status other than 0 or 1 |

```bash
phase2_no_index_diff() {
  phase2_diff_mode=$1
  phase2_diff_path=$2
  phase2_diff_stdout=$3
  phase2_diff_stderr=$4
  phase2_diff_capture_dir=$5

  test -f "$phase2_diff_path" &&
  test ! -L "$phase2_diff_path" &&
  test -r "$phase2_diff_path" || return 72

  { test "$phase2_diff_mode" = check || test "$phase2_diff_mode" = patch; } || return 64
  test -d "$phase2_diff_capture_dir" &&
  test ! -L "$phase2_diff_capture_dir" &&
  test -O "$phase2_diff_capture_dir" &&
  test "$(/usr/bin/stat -f '%Lp' "$phase2_diff_capture_dir")" = 700 &&
  test -r "$phase2_diff_capture_dir" &&
  test -w "$phase2_diff_capture_dir" &&
  test -x "$phase2_diff_capture_dir" || return 75
  test "$phase2_diff_stdout" = "$phase2_diff_capture_dir/stdout" &&
  test "$phase2_diff_stderr" = "$phase2_diff_capture_dir/stderr" &&
  test "$phase2_diff_stdout" != "$phase2_diff_stderr" &&
  test "$phase2_diff_path" != "$phase2_diff_stdout" &&
  test "$phase2_diff_path" != "$phase2_diff_stderr" || return 75
  test -f "$phase2_diff_stdout" && test ! -L "$phase2_diff_stdout" &&
  test -O "$phase2_diff_stdout" &&
  test "$(/usr/bin/stat -f '%l:%Lp' "$phase2_diff_stdout")" = 1:600 &&
  test -r "$phase2_diff_stdout" && test -w "$phase2_diff_stdout" &&
  test ! -s "$phase2_diff_stdout" || return 75
  test -f "$phase2_diff_stderr" && test ! -L "$phase2_diff_stderr" &&
  test -O "$phase2_diff_stderr" &&
  test "$(/usr/bin/stat -f '%l:%Lp' "$phase2_diff_stderr")" = 1:600 &&
  test -r "$phase2_diff_stderr" && test -w "$phase2_diff_stderr" &&
  test ! -s "$phase2_diff_stderr" || return 75

  phase2_diff_input_id=$(/usr/bin/stat -f '%d:%i' "$phase2_diff_path") || return 75
  phase2_diff_stdout_id=$(/usr/bin/stat -f '%d:%i' "$phase2_diff_stdout") || return 75
  phase2_diff_stderr_id=$(/usr/bin/stat -f '%d:%i' "$phase2_diff_stderr") || return 75
  phase2_diff_dir_id=$(/usr/bin/stat -f '%d:%i' "$phase2_diff_capture_dir") || return 75
  test "$phase2_diff_input_id" != "$phase2_diff_stdout_id" &&
  test "$phase2_diff_input_id" != "$phase2_diff_stderr_id" &&
  test "$phase2_diff_stdout_id" != "$phase2_diff_stderr_id" || return 75

  exec 3>"$phase2_diff_stdout" || return 75
  exec 4>"$phase2_diff_stderr" || { exec 3>&-; return 75; }
  test "$phase2_diff_stdout" -ef /dev/fd/3 &&
  test "$phase2_diff_stderr" -ef /dev/fd/4 || {
    exec 3>&-
    exec 4>&-
    return 75
  }

  if test "$phase2_diff_mode" = check; then
    if git diff --no-index --check /dev/null "$phase2_diff_path" \
      >&3 2>&4; then
      phase2_diff_rc=0
    else
      phase2_diff_rc=$?
    fi
  else
    if git diff --binary --no-index /dev/null "$phase2_diff_path" \
      >&3 2>&4; then
      phase2_diff_rc=0
    else
      phase2_diff_rc=$?
    fi
  fi

  test -f "$phase2_diff_path" && test ! -L "$phase2_diff_path" &&
  test -r "$phase2_diff_path" &&
  test "$(/usr/bin/stat -f '%d:%i' "$phase2_diff_path")" = "$phase2_diff_input_id" || {
    exec 3>&-
    exec 4>&-
    return 75
  }
  test -f "$phase2_diff_stdout" && test ! -L "$phase2_diff_stdout" &&
  test -O "$phase2_diff_stdout" &&
  test "$(/usr/bin/stat -f '%l:%Lp' "$phase2_diff_stdout")" = 1:600 &&
  test "$(/usr/bin/stat -f '%d:%i' "$phase2_diff_stdout")" = "$phase2_diff_stdout_id" &&
  test "$phase2_diff_stdout" -ef /dev/fd/3 &&
  test -r "$phase2_diff_stdout" || {
    exec 3>&-
    exec 4>&-
    return 75
  }
  test -f "$phase2_diff_stderr" && test ! -L "$phase2_diff_stderr" &&
  test -O "$phase2_diff_stderr" &&
  test "$(/usr/bin/stat -f '%l:%Lp' "$phase2_diff_stderr")" = 1:600 &&
  test "$(/usr/bin/stat -f '%d:%i' "$phase2_diff_stderr")" = "$phase2_diff_stderr_id" &&
  test "$phase2_diff_stderr" -ef /dev/fd/4 &&
  test -r "$phase2_diff_stderr" &&
  test "$(/usr/bin/stat -f '%d:%i' "$phase2_diff_capture_dir")" = "$phase2_diff_dir_id" &&
  test "$(/usr/bin/stat -f '%Lp' "$phase2_diff_capture_dir")" = 700 || {
    exec 3>&-
    exec 4>&-
    return 75
  }
  exec 3>&-
  exec 4>&-
  { test "$phase2_diff_rc" -eq 0 || test "$phase2_diff_rc" -eq 1; } || return "$phase2_diff_rc"
  test ! -s "$phase2_diff_stderr" || return 73
  if test "$phase2_diff_mode" = check; then
    test ! -s "$phase2_diff_stdout" || return 74
  fi
}
```

- Fatal classes: Missing/unreadable/directory/symlink input, hardlink/identity collision, capture replacement, mode-0755/0777 directory, non-0600 or multi-link capture, missing/nonempty/unwritable capture, FD-open failure, status ≥2, or any stderr.
- Fixture coverage: all input path classes, clean/bad new file, patch status1/output, stderr at 0/1, status2, missing/replaced/colliding captures, hardlink-to-input, stdout↔stderr hardlink, 0700/0755/0777 directories, 0600/non-0600 captures, stdout/stderr/input alias attempts, unwritable file/directory, FD-open failure, post-run input/capture symlink/mode/inode replacement, caller errexit initially on and off with its state unchanged, and tracked whitespace error.

### C10.12 Adopted amendment resolution register

| Source | Amendment file | Adjudication scope (exact literal) |
|---|---|---|
| spec | `PHASE2_AMENDMENT_1.md` | higher-authority owner adjudication for P1-A through P1-U |
| spec | `PHASE2_AMENDMENT_2.md` | higher-authority owner adjudication for second-pass findings 1 through 8 |
| spec | `PHASE2_AMENDMENT_3.md` | higher-authority owner adjudication for third-pass findings 1 through 9 |

- Register is normative, not a proposal; each registered ID appears exactly once and maps to its implemented specification sections plus literal source/test closure. (spec)

| ID | Adopted authority | Normative resolution | Literal source/test closure |
|---|---|---|---|
| S3-CD1 | Reconciled 12 rule (missing shape is a contract defect fixed in the contract) | C9.1.21 gains the OriginalEventBytesV1 encoding grammar and digest scope; the predicate order and double rule were the only members present. | `functions/dispositionTriggers.js`; `functions/tests/dispositionTriggers.test.js` encoder family |
| S3-CD2 | Reconciled 12 rule | C9.1.23 gains the Standard-edition base equations, the frozen-registry index policy, and the `FirestoreWriteBudgetV1(transition)` formula and bounds that C9.1.27 and C9.2.7 consume by name. | `functions/dispositionTriggers.js` production sizing and its independent oracle; `functions/tests/dispositionTriggers.test.js` |
| S3-CD3 | Reconciled 12 rule | C9.1.26 gains the `phase0ValidationFailure` attempt rule, the `qev1_` quarantine id, and the exact schema-v1 record with its replay rule. | `functions/dispositionTriggers.js`; `functions/tests/dispositionTriggers.test.js` attempt `1→2→qev1` family |
| S3-CD4 | Reconciled 12 rule | C9.1.29 gains the exact spec-5.2 event-state map that the size predicate and the advance write name. | `functions/dispositionTriggers.js`; retained high-water tests |
| S3-CD5 | S3 close-out review (Sol F1; owner direction 2026-09-06) | C9.1.20 gains branch (5): a deletion fence observed before any refusal or reducer write settles the cursor past the candidate with zero writes beneath the owner and is never a refusal. | `functions/dispositionTriggers.js`; `functions/tests/dispositionTriggers.test.js` fenced fresh/retry/threshold/nested-event family |
| S3-CD6 | S3 close-out review (Sol F8; owner direction) | C9.2.2 gains the audit exit rule: zero only when the C9.2.9 criterion holds; a complete pass with failing or out-of-scope rows exits nonzero. | `functions/scripts/migrateOversizeEvents.js`; `functions/tests/dispositionTriggers.test.js` two-pass audit exit-code test |
| S3-CD7 | S3 close-out review (Sol F10b; owner direction) | C9.4.1 `confirming`/NEW_UID nominates the UID as a `pending/unexamined` candidate (`pass_ordinal` +1; the row's `first_pass_ordinal` equals the incremented `pass_ordinal`) in the failure transaction before reducing. | `functions/scripts/purgeLegacyDeletedAccounts.js`; `functions/tests/accountDeletionFence.test.js` confirming NEW_UID nomination case |
| S3-CD8 | S3 close-out review (Sol F4/F12; owner direction) | C9.3.11 gains the live policy-state rule (shape S6's, open), the interim zero-write settle for policy-present rows, and the interim claim rule; C10.1 gains the S6 rows for the policy-present branches and the shapes. | `functions/dispositionTriggers.js`, `functions/notificationIntents.js`, `functions/taskPlan.js`; `functions/tests/dispositionTriggers.test.js` "C9.3.11 interim (S3-CD8)" zero-write test; `functions/tests/notificationIntents.test.js` absent/partial `taskInteractionState` → `INTENT_STALE` cases |
| S3-CD9 | S3 close-out review (Sol F15; owner direction) | C9.5.16 malformed dose store: every byte and every legacy key preserved, cleanup blocked, store marked for durable-store recovery (S4); later resets remove legacy keys only after an accepted cleanup. | `Peezy 4.0/MainInterface/Models/DailyDoseEngine.swift` (S1 core/reset path, S3 client-reset-driver edit per the S3 brief); `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` `dailyDoseLocalStorePreservesMalformedBytesAndBlocksMutation` and the reset malformed/drift cases |
| P1-A | Amendment §A | §4.5 freezes durable policy workflow request/receipt/application, conditional trigger, and policy-ineligible Supplies gate. | `WorkflowService.swift`, RentTruck/SetupInternet/Supplies and six §8.2 callers; `getWorkflowQualifying.test.js`, `callableAuth.test.js`, `ConversationFlowTests.swift`, `TaskDispositionSurfaceTests.swift`. |
| P1-B | Amendment §A | §§4.2/5.5 replace H56 with instance+attempt-generation+write-revision callable CAS, atomic proof clear, and content revisions. | `FlowProgressSession.swift`, TaskAction/FlowEngine/FlowExit, Movers model pair; `taskDisposition.test.js`, rules, `ConversationFlowTests.swift`, `MoversChainCoordinatorTests.swift`. |
| P1-C | Amendment §A | §§2.2/3.1/4.6/4.7/7 apply all-owner generation, root move-event authority, strict producer projection, server packing persistence/clear, and reset fencing. | TaskGeneration/TaskAction/Spawn/taskDisposition/rules; 53-task rules fixture plus legacy packing/reset fence matrices. |
| P1-D | Amendment §A | §§2.2/3.1 store terminal contradiction `none` only; `present` is resolver receipt and `unknown` is absence+failure. | `taskInteraction.js`, `taskDisposition.js`, mapper; taskInteraction/taskDisposition/rules/Swift projection fixtures. |
| P1-E | Amendment §A | §2.2 selector sources are exactly TASK/IDENTITY/USER_KNOWLEDGE with lossless update-time authority; no fictional source. | `taskInteraction.js`, taskDisposition evaluator, TaskInteraction decoder; canonical/source availability/privacy tests. |
| P1-F | Amendment §C | §4.6 binds generic spawn token/request/result to root generation and captured source instance with four closed stale/replay outcomes. | `SpawnService.swift`, `spawnTasks.js`, four §8.2 callers; both spawn test files and `LegacyTaskMutationFenceTests.swift`. |
| P1-G | Amendment §C option 1 | §4.7 routes every v5 legacy mutation through captured generation plus exact stored-string-or-explicit-null instance, including coherent contractless H54_REOPENED generic controls; named H54/workflow/spawn/scheduler surfaces validate the same tuple before replay, local adoption is identity-bound, packing auxiliaries/support marker are server-written, and fenced direct writes are denied. | TaskAction/TaskPlan/SupportChat/TasksStore/Home/router plus booking/readiness/packing views; taskDisposition/H54/workflow/spawn/scheduler/rules; `LegacyTaskMutationFenceTests.swift`, `PeezyNudgeAnswerTests.swift`, Node/rules matrices. |
| P1-H | Amendment §B + master A12-11 | §§2.2/3.1/4.2/5.1 freeze six facts, exactly two visible exits, local prefilled no-write Chat, one renewal, and mandatory reciprocal TRY_CHANNEL+nudge. | ContextualOutcome/DispositionSurface/SupportChatView; reciprocal full fixture; taskInteraction/taskDisposition plus ContextualOutcome/TaskDispositionSurface tests. |
| P1-I | Amendment §C | §§3.1/5.2 add indexed server threshold projection and independent scan with one wake/intent, replay, routing, and total trigger race. | `dispositionTriggers.js`, `notificationIntents.js`, indexes; dispositionTriggers/notificationIntents/rules and urgent-group Swift tests. |
| P1-J | Amendment §B + master A12-12 | §§2.2/3.1/5.2 add optional closed consequence class/rank and exact classified/unclassified hybrid sort; production registry is empty. | taskInteraction/trigger validator, mapper/grouping; injected registry ordering/drift tests and full absent-class fixture. |
| P1-K | Amendment §C | §§3.1/3.3/4.2 freeze `clearPackingPlan`, `packing1_` fingerprint, marker↔operation projection, one-step progress, terminal/error/adoption/replay. | TaskAction/taskDisposition/rules; taskDisposition and legacy-fence crash/loss/reset/count tests. |
| P1-L | Amendment §C | §§3.3/4.2/4.3 name all five field actions, exact alternative envelopes, revisions, typed receipts/conflicts, and replay/adoption. | TaskPlanService/TaskAction/taskDisposition/rules; taskDisposition, canonical fractional, ConversationFlow and content race tests. |
| P1-M | Amendment §C lowercase decision | §§3.3/4.4 freeze lowercase reset states and complete camelCase root-marker↔snake_case operation↔receipt projection. | TaskPlanService/taskPlan; taskPlan/TaskPlanDisposition phase, crash, replay, and surplus-member fixtures. |
| P1-N | Amendment §C | §3.3 freezes four one-file self-hashed envelopes, signed-out/in auth, exact excluded hash member, fixed quarantine, atomic replace, and CORRUPT_BLOCKED. | WorkflowService/HandoffSessionStore/AppRouteInbox/TaskPlanService; four actor crash/tamper/quarantine test suites. |
| P1-O | Amendment §C | §3.3 adds reconciliation-cancel record carrying stored/requester namespaces, immutable request/hash, PREPARED→APPLYING phases, and cleanup. | HandoffSessionStore/TaskPlanService; HandoffSessionTests crash/loss/auth-rotation/takeover matrix. |
| P1-P | Amendment §C as refined by the adopted third amendment | §3.3 AUTH_REQUIRED CAS returns matching dispatch to RECEIVED, persists one live 60-second refresh lease, forbids overlap, and resumes on lease expiry or durable namespace/revision change. | AppRouteInbox/HandoffSessionStore/PeezyV1App; TaskRouteTests A→B, three refresh crash boundaries, exact expiry, late completion, and same-UID no-second-callback cases. |
| P1-Q | Amendment §C | §5.7 qualifies TasksStore namespace/readiness/revision by UID+fresh listener token and guards every callback/mutation. | `TasksStore.swift`, Home/container consumers; `TasksStoreNamespaceTests.swift` late-A/stop-start/reuse cases. |
| P1-R | Amendment §C direct-file decision | §5.7 authorizes AppRoot and guards assessment/UserState async completions by current UID+load token before store start. | `AppRootView.swift`, `PeezyMainContainer.swift`; `AppRootAuthRaceTests.swift`. |
| P1-S | Amendment §C as refined by the adopted second amendment | §§4.6/7.4 precompute exact Firestore document and actual automatic/manual index-entry charges under the frozen registry, require total ≤8,388,608 with the adopted headroom, and return typed all-or-nothing failure. | spawn/taskDisposition/taskPlan/getWorkflow reducers; independent rules-emulator oracle, real-catalog first RED, nested map/array/exemption cases, exact at-/over-budget boundary and distribution tests. |
| P1-T | Amendment §C | §2.1 defines separate finite-binary64 `TaskCanonicalV1`, negative-zero/decimal/exponent normalization, and independent JS/Swift parity. | taskInteraction/TaskInteraction; `taskCanonical.test.js`, `TaskCanonicalTests.swift`, fractional task/content/budget fixtures. |
| P1-U | Amendment §C current-code option | §§2.2/4.4 require every a2 to carry normalized subject, institution ID/display, supersedes, and `spawnedFrom.id`; only move alias is conditional. | `taskPlan.js`, shared validator/mapper; taskPlan/taskInteraction/TaskSupersession omission/surplus/all-selector fixtures. |
| A2-1 | Amendment 2 finding 1 | §§3.1/4.2 freeze one total schema: `waiting_state.entered_at`; `pending_handoff.action_id` and server-authored `selected_at`; the alternative name is forbidden. | taskInteraction/taskDisposition validators and reducers, typed receipts/recovery/mappers; exact common/variant maps, replay/relaunch, omission/surplus/time-equality fixtures. |
| A2-2 | Amendment 2 finding 2 | §§2.1/3.3/4.7 bind COMPLETE_BOOKING, COMPLETE_PACKING_SESSION, and bulk packing complete requests to `TaskCanonicalV1`, including operation ID; freeze prefix, preimage bytes, SHA, and adjacent fractional fixtures. | taskInteraction/taskDisposition/TaskAction; `taskCanonical.test.js`, `taskDisposition.test.js`, `TaskCanonicalTests.swift`, exact fractional parity and changed-byte replay cases. |
| A2-3 | Amendment 2 finding 3 | §§2.1/4.1/4.2/4.7 make exact UTC-millisecond strings the sole callable timestamp wire; fingerprint strings unchanged, parse only after validation, reject sentinels, and author every commit-time field from one concrete per-attempt server time. | all Swift callable DTOs/transports and JS callable validators/reducers; exact accepted/rejected Swift/JS bytes, within-attempt equality, retry replacement, historical precision, replay fixtures. |
| A2-4 | Amendment 2 finding 4 | §§2.2/2.3/3.1/3.2/4.3/4.5/5.2 require waiting display from immutable policy or exact provider-directory evidence; missing authority makes WAIT ineligible and writes the same-trigger owned USER_ACTION fallback/evidence without opaque visible identifiers. | taskInteraction/taskDisposition/workflow/H54/scheduler plus rules verification and mapper/surfaces/Chat; policy/directory/spoof/missing/malformed/direct-write denial, direct/outcome/workflow/H54, evidence/replay/row-routing/no-Chat tests. |
| A2-5 | Amendment 2 finding 5 | §§3.3/4.4 freeze literal lowercase `reset_dispatched`; uppercase or mixed casing is invalid in durable recovery. | TaskPlanService/taskPlan exact-union validators; reset crash/relaunch/replay and invalid-casing fixtures. |
| A2-6 | Amendment 2 finding 6 | §§4.6/7.4 replace the flat allowance with `FirestoreWriteBudgetV1`, derived from exact document schemas and the frozen 4,432-byte index configuration; independent emulator boundaries must pass at budget and fail over it. | taskInteraction/taskDisposition/taskPlan plus exact `firestore.indexes.json`; taskCanonical/taskDisposition/rules tests for maps, arrays, exemptions, composites, old/new index deltas, creates/updates/deletes and total charge. |
| A2-7 | Amendment 2 finding 7 | §5.2 runs the bounded event-envelope validation/conflict-quarantine/high-water pass as phase 0 before all seven scheduler scans, with one `runNow`, deterministic IDs, query abort, candidate continuation, and same-run visibility. | dispositionTriggers and index/rules integration; exact query/order/101→100/concurrency-10, canonical IDs, duplicate/stale/conflict/quarantine/failure/high-water and seven-scan regression fixtures. |
| A2-8 | Amendment 2 finding 8 | §§8.5/9.4/9.5 protect main `File.txt`, create only the explicit empty worktree prerequisite after worktree creation and before builds, reverify both hashes at every checkpoint, trap exact-file cleanup, prove patch/manifest exclusion, and prove absence after cleanup. | future integration shell transcript and review manifest only; lifecycle interruption matrix, status/index/path parser assertions, main-hash invariance, patch/apply exclusion and final absence proofs. |
| A3-1 | Amendment 3 finding 1 | §5.2 adds a persisted full-path phase-0 cursor, stable complete-source digest, three-identical-failure bounded quarantine, nonblocking 100-poison progression, and H57 UNKNOWN-consumer regeneration requirement. | `dispositionTriggers.js`, rules; trigger/rules tests freeze cursor/wrap/crash, digest corpus, attempt reset, quarantine identity/cap/denial, valid #101 and all seven scans. |
| A3-2 | Amendment 3 finding 2 | §§2.1/3.3/4.7 bind legacy `REPLACE_QUOTES` complete accepted requests to `TaskCanonicalV1` and freeze fractional parity/replay bytes. | taskInteraction/taskDisposition plus TaskAction/movers adapters; taskCanonical/taskDisposition, `TaskCanonicalTests.swift`, legacy-fence and movers tests. |
| A3-3 | Amendment 3 finding 3 | §§2.3/3.1/3.3/4.4 create an original-instance confirmation record whose verified replacement evidence tuple/digest is copied by value in the same two-task transaction; no cross-task evidence resolver exists. | shared evidence constructor and `taskPlan.js`; task-plan/projection/supersession tests including concurrent replacement reset/recreation. |
| A3-4 | Amendment 3 finding 4 | §§3.2/3.3/4.4 make confirmed external originals `Dismissed + SUPERSEDED` keyed by replacement instance, reserve `RETIRED` for internal retirement, and freeze untouched-replacement reopen semantics. | disposition validator, `taskPlan.js`, mapper; disposition-contract/task-plan/TaskSupersession lifecycle pairing matrices. |
| A3-5 | Amendment 3 finding 5 | §§3.3/4.1/4.2/4.4/5.5 define read-only typed restoration preflight, fixed cancel/undo/reopen branches, descriptor-bearing mutation errors, fresh policy-bound trigger selection, durable ordinary/reconciliation recovery, and zero preflight flow lease/write. | taskPlan/taskDisposition plus TaskPlanService/HandoffSessionStore/trigger selector; cancel, both undo branches, reopen, drift, relaunch, and zero-write/lease fixtures. |
| A3-6 | Amendment 3 finding 6 | §§3.3/4.4 bind reset to a deterministic UID/result-epoch canonical record, disjoint bounded aliases, permanent reconstructable terminal tombstone, and crash-durable final-receipt application. | taskPlan/TaskPlanService/rules/budget; competing scenes, old-epoch alias, intentional next epoch, alias cap/collision, digest, and crash-after-first-final-receipt fixtures. |
| A3-7 | Amendment 3 finding 7 | §3.3 replaces the permanent attempted Boolean with an exact live 60-second refresh lease recovered by expiry or durable namespace/credential-revision change. | AppRouteInbox/HandoffSessionStore/PeezyV1App; crash-before-invocation, crash-before-auth-persistence, post-auth-persistence crash, no-overlap, expiry, and late-completion fixtures. |
| A3-8 | Amendment 3 finding 8 | §§3.3/4.2 freeze task-route expiry as exact UTC-millisecond response text and safe epoch-millisecond local persistence/comparison. | taskPlan claim plus TaskRoute/AppRouteInbox; JS/Swift wire/integer parity, strict rejection, replay, min, and equal±1ms boundary fixtures. |
| A3-9 | Amendment 3 finding 9 | §§4.2/4.5 freeze the six-value receipt disposition union, transaction-write presence rule, persisted string equality, and workflow trusted-WAIT/fallback consumption. | taskDisposition/workflow plus WorkflowService/TaskPlanService; six-value decode, lifecycle absence, replay/equality, and WAIT-ineligible→USER_ACTION_TRACKED fixtures. |

### C10.x Named falsifiers

| Decision | Test file | Named test / gate |
|---|---|---|
| D29 | Literal totals count gate (C10.6) | 22 unique Swift test files, 23 suites, 89 unique authorized client paths, 33 unique additions against a 56-unique-path base (manifest); 21 files, 22 suites, 58 entries/56 unique paths (spec) |
| D29 | expected set `E` (xcresulttool assertion script) | `missing/empty ${x}`; `suite set=${JSON.stringify([...seen].sort())}`; `unexpected case ${n.name}`; `unit bundles=${JSON.stringify(units)}`; `ui bundles=${JSON.stringify(uis)}`; `PASS ${E.size} suites ${[...count.values()].reduce((a,b)=>a+b,0)} cases` |
| D29 | `-only-testing:` list | `-only-testing:'Peezy 4.0Tests/DurableStoreRecoveryTests'` immediately after `DispositionTriggerSelectionTests`; `-skip-testing:'Peezy 4.0UITests'`; no `-testPlan` |
| D29 | Node `--test` file list | 24 files with `functions/tests/accountDeletionFence.test.js` immediately before `functions/tests/accountabilityLadder.test.js` (manifest); 23 files (spec); no broad glob |
| D29 | `rg` gate | zero production `Firestore.firestore()` outside `LocalPrivacyPurgeCoordinator.swift` and the one initialization line in `PeezyV1App.swift` |
| D29 | `Peezy 4.0Tests/AppRootAuthRaceTests.swift` | sole-`GIDSignIn.sharedInstance` call-site scan; sole-`UNUserNotificationCenter`/`Messaging` deletion-call-site scan |
| D29 | `Peezy 4.0Tests/DurableStoreRecoveryTests.swift` | `UID-interpolated preference keys are registry-complete`; `Release call graph and adversarial NSError are sink-free`; `Firebase Auth keychain item is absent after terminal detach` |
| D29 | `functions/tests/accountDeletionFence.test.js` | `timeouts do not exceed 300 seconds`; `active exports contain no dynamic server log sink`; `Auth destination partition is completely falsifiable`; `sealer refuses nonzero matches, backlog, and nonfinite retention`; zero Storage-finalizer export; two-reconciler export graph; package/lock/config/evidence digests |
| D29 | `functions/tests/taskPlan.test.js` | every `inspectCommittedOperation` request/path/kind/state/fingerprint/identity/replay/error branch and action-registry/export coverage |
| D29 | §8.9.3 admission caller fixtures | every §8.9.3 consumer projection; held responses across generation change; no stale application; static sole-caller graph proves no transport edit |
| D31 | Node `--check` | once per touched `.js` path; plus `functions/scripts/migrateOversizeEvents.js`, `functions/scripts/purgeLegacyResolvedProviders.js`, `functions/scripts/purgeLegacyDeletedAccounts.js`, `functions/scripts/sealAccountDeletionProviderEvidence.js` |
| D31 | `git diff --check` / `git diff --no-index --check /dev/null` | tracked paths enumerated literally; each new path as the next literal argument; no glob or command substitution derives the manifest |
| D31 | `git apply --numstat -z` | decoded paths equal the ordered path/SHA-256 manifest exactly; reject renames, surplus/duplicate paths, any root `File.txt`, any path outside the authorized manifest |
| D31 | guard scaffold | `assert_main_file_guard`, `assert_empty_worktree_file_absent`, `assert_empty_worktree_file`, `cleanup_phase2_empty_file` (exit 70), `phase2_exit_cleanup` (exit 70/71); status exactly `?? File.txt`; `git cat-file -e "$phase2_base:File.txt"` must fail |
| D31 | `functions/package.json`, `functions/package-lock.json` | `"@google-cloud/firestore":"7.11.6"` with no range; `@google-cloud/storage` exact 7.18.0; lock not hand-edited |
| D32 | `phase2_no_index_diff` shell fixture | return codes 72/64/75/73/74; all input path classes, clean/bad new file, patch status1/output, stderr at 0/1, status2, missing/replaced/colliding captures, hardlink-to-input, stdout↔stderr hardlink, 0700/0755/0777 directories, 0600/non-0600 captures, stdout/stderr/input alias attempts, unwritable file/directory, FD-open failure, post-run input/capture symlink/mode/inode replacement, caller errexit initially on and off with its state unchanged, tracked whitespace error |

## Open

1. `capability_invalid` token: v8 names no fixture that rejects `capability_invalid` outside the C2.6 exit or that proves relaunch-from-bytes selects `local_cleared` for that token specifically; §8.9.6 covers only "capability-invalid never-enrolled remote deletion" and the generic crash-at-every-phase family.
2. Different-UID `ACCOUNT_DELETION_BUSY` in non-guarding phases (C2.4): no fixture is named in §8.9.6; only same-UID guarding refusal and Option-B are assigned.
3. Conditional global `peezy.user.firstName` removal (deleting A never clears B's cache): no named fixture; the registry source scan covers only UID-interpolated keys.
4. `storage.rules` owner/existing-root/no-marker predicate: the rules run includes `storage` in `emulators:exec` but the only named rules test file is `firestoreRules.test.js`; no Storage Rules test is named.
5. `phase2LegacyCreateBlocker` (§11.4): listed in C6.3, but no test is named for its permission-denied throw or blocking-configuration coverage; §11.4 fixtures name only the migration core and CLI guards.
6. Provider-copy destination arrays (Gmail, Twilio, FCM, Anthropic, Analytics, Crashlytics, Cloud Audit): zero-match and retention are owner-sealed evidence; the only in-repo falsifier is the sealer refusal test. No test observes a destination.
