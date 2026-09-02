# PHASE 2 CONTRACT

Extracted 2026-09-02 from `PHASE2_REPLACEMENT_MANIFEST_v8.md` (sha256 `12ea8ee1b1fcd43dc88a993ebc4b6706a4b3d8f2ed93ebd09a59d2399262a251`). This file states only what must be true for implementation: schemas, transitions, gates, registries, pins, and the test that falsifies each. Procedure, supersession ledgers, slice ownership, and review rules stay in the manifest. Where this file and v8 disagree, the "Reconciled" list at the end names the sentence that lost. `§n` cites v8; `Cn` cites this file. "Exact" means unknown, missing, null-for-optional, or surplus members reject.

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
- Guarding wire exact `{schemaVersion:1,kind:"account_deletion_auth_guarding",operationId,authorityKind,startedAt,dataDeletedAt,authAbsenceObservedAt,authGuardAfter,replayed}`. Deleted wire exact `{schemaVersion:1,kind:"account_deletion_account_deleted",operationId,authorityKind,startedAt,dataDeletedAt,authAbsenceObservedAt,authGuardAfter,authGuardCompletedAt,accountDeletedAt,replayed}`. Every value is copied from the validated root; Auth state alone never synthesizes a branch.
- Finalize: at DATA_DELETED performs the bounded evidence fence and Auth deletion, creates/adopts the Auth work row, returns the guarding wire with `replayed:false`; at AUTH_GUARDING returns it with `replayed:true`; at ACCOUNT_DELETED returns the deleted wire. Only transport or unknown errors retry; user-not-found never yields `DELETION_RETRY_REQUIRED`.
- Thrown union: `REQUEST_INVALID(field)`, `AUTH_REQUIRED`, `DELETION_CAPABILITY_INVALID`, `DELETION_RETRY_REQUIRED`; any unknown code, detail, or member is protocol ambiguity and retains durable bytes.
- DELETING-sweeping: discover/begin/resume may mutate only capability enrollment and the two-empty-sweep → guarding transition. DELETING-guarding: they return exact `{schemaVersion:1,reason:"DELETION_RETRY_REQUIRED"}`, change no byte, and the client stays `prepared` projecting the queued presentation. Startup and Retry reuse the same durable capability until DATA_DELETED or a later root wire.

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

## C3 Server deletion root, work rows, and residual checks (§11, §11.3)

- Root `users/{uid}.accountDeletion` branches, all with `schemaVersion:1`, the exact sorted `capabilities` array (1…64, unique `operationId`, unsigned-UTF8 order, ≤16,384 canonical bytes), and `startedAt`: DELETING-sweeping `{state:"DELETING",capabilities,startedAt,storageGuardAfter}`; DELETING-guarding adds `firestoreCleanupAt` and optionally `storageGuardCompletedAt` (strictly after `storageGuardAfter`) and/or `firestoreVersionGuardCompletedAt` (≥ `firestoreCleanupAt`); DATA_DELETED adds both completions plus `dataDeletedAt`; AUTH_GUARDING adds `authAbsenceObservedAt,authGuardAfter`; ACCOUNT_DELETED adds `authGuardCompletedAt,accountDeletedAt`. `storageGuardAfter == startedAt + 604800 s`; `authGuardAfter == authAbsenceObservedAt + authResidualRetentionSeconds`; `authGuardCompletedAt > authGuardAfter`; `accountDeletedAt >= authGuardCompletedAt`. The ACCOUNT_DELETED tombstone is permanent and retains the UID as document ID plus capability-proof hashes; that retention is an explicit limit of the promise.
- Two consecutive empty application sweeps write only DELETING-sweeping→DELETING-guarding. Only the scheduled Storage guard writes DATA_DELETED, and only after `storageGuardCompletedAt`, `firestoreVersionGuardCompletedAt` (fresh `earliestVersionTime` strictly later than `firestoreCleanupAt`), zero `outboundLeases`, and zero soft-deleted/noncurrent generations. Data authority never deletes Auth.
- Work rows: `accountDeletionStorageWork/{"adsw1_"+first40(sha256(TaskCanonicalV1({account_uid:uid})))}` exists from marker creation until DATA_DELETED; `accountDeletionAuthWork/{"adaw1_"+…}` has branches `delete_pending` and `guarding` (`auth_guard_after == auth_absence_observed_at + authResidualRetentionSeconds`); each ≤2,048 canonical bytes, `failure_count` 0…8, client access denied.
- Reconcilers: `reconcileAccountDeletionStorage` = `onSchedule({schedule:"*/5 * * * *",timeZone:"UTC",region:"us-central1",timeoutSeconds:270,memory:"512MiB",maxInstances:1,retryCount:0})`, state `phase2System/accountDeletionStorageReconcilerV1`; `reconcileAccountDeletionAuth` = same with `schedule:"2-57/5 * * * *"`, state `phase2System/accountDeletionAuthReconcilerV1`. Every mutation fences its live lease tuple; one eligible row per run; cursor advances before any provider await; backoff `failure_count=min(old+1,8)`, `next_eligible_run=ordinal+min(2^count,16)`.
- Auth reducer: pending → 3-second `auth().getUser(uid)`; user-not-found or an accepted `deleteUser` transitions DATA_DELETED→AUTH_GUARDING and pending→guarding at one server read time; guarding after the deadline requires fresh user-not-found, every `authResidualChecks` query zero, and an unchanged authority fence, then writes ACCOUNT_DELETED and deletes the work row.
- Residual checks (D3): `authResidualRetentionSeconds` 0…31536000 equals the maximum `retentionSeconds` across the accepted `AuthDeletionDestinationV1` array. `authResidualChecks` is a sorted 1…12-member closed union with contiguous ordinals: Firebase `{ordinal,destinationOrdinals,adapterId:"firebase_admin_get_user_v1",retentionSeconds}` covering every `auth_user` destination; provider query `{ordinal,destinationOrdinals,adapterId:"google_authenticated_uid_zero_v1",resourceURLTemplate,method:"GET"|"POST",bodyTemplate,uidEncoding:"percent_utf8"|"taskcanonical_sha256_hex",zeroCountField:"matchCount"|"totalSize",retentionSeconds}`; absence-plus-retention `{ordinal,kind:"absence_retention",destinationOrdinals,observedAbsentAt,retentionSeconds}` where `destinationOrdinals` has exactly one member. Every `destinationOrdinals` array is nonempty, sorted, and disjoint from every other check's, and every accepted Auth-destination ordinal appears in exactly one check, whether a count check or an `absence_retention` check. A destination kind admitting none of the three checks cannot be sealed.
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

`functions/index.js` requestConcierge, submitTaskFlow, submitSupportMessage (with `deleteAccount`, `reconcileAccountDeletionStorage`, `reconcileAccountDeletionAuth` as marker/cleanup coordinator exceptions); every committing branch/shared child in `functions/taskDisposition.js`, `functions/taskPlan.js` (`inspectCommittedOperation` read-only; includes `users/{uid}/legacyResetMigrations/{migrationId}` creation), `functions/getWorkflowQualifying.js` submitWorkflowAnswers, `functions/dispositionTriggers.js`, `functions/notificationIntents.js`, `functions/spawnTasks.js`; process success/error plus `onInventoryRoomWritten` in `functions/processInventory.js`; `functions/researchTask.js`; `functions/peezyChat.js`; `functions/packageInventory.js`; `functions/submitCheckIn.js` plus `functions/submitCheckInCore.js`; `functions/entitlement.js`; `functions/validateSubscription.js`; writing tails of supportAdmin adminGetThread, adminReplySupport, adminMarkSeen, adminSetThreadStatus. Explicit exclusions: scheduler lease/heartbeat-only writes, generation-preconditioned Storage deletion, support invalid-token deletion, getWorkflowQualifying read-only branch, healthCheck, adminListThreads, requireMovePass; scripts, `functions/notifyAdmin.js`, and test-profile utilities are deployment-inactive. Before each registered write the transaction reads every current and prospective owner root in unsigned-UTF8 order and requires `accountDeletion` absent. Note: the four `d321547` files are authorized only for `processInventory.js` fence/lease call sites, six `Firestore.firestore()` substitutions plus `pendingNarration` in `InventorySessionManager.swift`, `pendingNarrationTranscript` in `InventoryCameraView.swift`, and `NarrationService.start`.

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
| Transitive packages | `@google-cloud/storage` 7.18.0; google-gax 4.6.1; `google-auth-library` 9.15.1; `firebase-admin` 13.6.0; Firebase iOS SDK 12.7.0; Node 22 |
| `Peezy 4.0/Menu/PeezySettingsView.swift` pre-edit | whole file `419055c9eb0e756daf70f68aeb37d5761888460a65f4c129243fe3f28a4c34d5`; `retakeAssessment()` lines 662–679 `348ec7db63aeecb76e7012d4fac91e41b60df78562a32b9528a5e40553a5a2e2` (unchanged after patch); `deleteAccount()` lines 681–712 `8f86efa8523960588cfe8a17d6351645cba50bb14f4258a77a4dc8ccf98a5bbf`; file minus that slice `ef856d3bf2f89b79d4340e5b4afe8e3844b13bb6167854486d5919d83b37e4cc` (identical after patch) |
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

## Open

1. `capability_invalid` token: v8 names no fixture that rejects `capability_invalid` outside the C2.6 exit or that proves relaunch-from-bytes selects `local_cleared` for that token specifically; §8.9.6 covers only "capability-invalid never-enrolled remote deletion" and the generic crash-at-every-phase family.
2. Different-UID `ACCOUNT_DELETION_BUSY` in non-guarding phases (C2.4): no fixture is named in §8.9.6; only same-UID guarding refusal and Option-B are assigned.
3. Conditional global `peezy.user.firstName` removal (deleting A never clears B's cache): no named fixture; the registry source scan covers only UID-interpolated keys.
4. `storage.rules` owner/existing-root/no-marker predicate: the rules run includes `storage` in `emulators:exec` but the only named rules test file is `firestoreRules.test.js`; no Storage Rules test is named.
5. `phase2LegacyCreateBlocker` (§11.4): listed in C6.3, but no test is named for its permission-denied throw or blocking-configuration coverage; §11.4 fixtures name only the migration core and CLI guards.
6. Provider-copy destination arrays (Gmail, Twilio, FCM, Anthropic, Analytics, Crashlytics, Cloud Audit): zero-match and retention are owner-sealed evidence; the only in-repo falsifier is the sealer refusal test. No test observes a destination.
