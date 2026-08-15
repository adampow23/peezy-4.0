# Plan Review Log: Stage-1 Subscription Hardening (rules + validateSubscription)

MAX_ROUNDS=3, BUDGET=6 chain rounds, strict=false, reviewer model=gpt-5.6-sol, codex-cli 0.147.0.

## Round 1 — Codex (thread 01a0066f-eb85-79f2-8057-204204a39af0)

1. [CRITICAL] The endpoint trusts a caller-supplied `userId`; the client sends no Firebase ID token, so anyone can grant or corrupt entitlements for any known UID ([client](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/SubscriptionAPIClient.swift:20>), [function](</Users/adampowell/Desktop/Peezy 4.0/functions/validateSubscription.js:27>)).  
Fix: Relax “no client changes,” send and verify a Firebase ID token, derive the UID from it, and reject missing/mismatched authentication with 401 ([Firebase guidance](https://firebase.google.com/docs/auth/admin/verify-id-tokens)).

2. [CRITICAL] Product/date allowlists and first-writer binding do not prove a purchase exists or belongs to the claimant; fabricated IDs still unlock paid server features.  
Fix: Simpler alternative (steelman): retain the request/response shape but call Apple Get Transaction Info, verify its signed JWS, derive every transaction field from it, and bind new purchases through signed `appAccountToken` ([Apple API](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-info), [signed fields](https://developer.apple.com/documentation/appstoreserverapi/jwstransactiondecodedpayload)).

3. [HIGH] Recomputing from the binding’s stored purchase date freezes weekly/annual subscriptions at their first period; later StoreKit renewal transactions have a new `transactionId` under the same `originalTransactionId` and can never advance access.  
Fix: Bind ownership by original ID, deduplicate by transaction ID, and permit only Apple-verified newer renewals to advance the entitlement.

4. [HIGH] `annual = +365 days` is wrong across leap years, and synthetic weekly/annual dates ignore Apple’s actual expiry, trials, revocations, upgrades, billing retry, and grace status.  
Fix: Use Apple’s verified `expiresDate` and status for auto-renewables; use a precisely specified UTC Gregorian six-calendar-month algorithm only for the non-renewing Move Pass.

5. [HIGH] Existing `subscriptions` records were created by the currently unauthenticated, unverified endpoint, yet the plan promotes their stored `userId` and `purchaseDate` to authoritative binding data.  
Fix: Before rollout, reverify existing transaction IDs against Apple, quarantine malformed/unverifiable records, and document a legacy migration/conflict policy.

6. [HIGH] Both gift redemption and StoreKit sync overwrite the single `users/{uid}.subscription` field, so concurrent or stale syncs can shorten or replace a stronger valid entitlement ([gift write](</Users/adampowell/Desktop/Peezy 4.0/functions/entitlement.js:91>)).  
Fix: Store immutable entitlement records and derive the effective maximum valid entitlement transactionally, with explicit gift-versus-purchase precedence.

7. [HIGH] Requiring the root user document can strand a paid user: account creation does not create it, assessment writes only subcollections, and failed sync is fire-and-forget with no durable retry ([signup](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Auth/AuthViewModel.swift:172>), [assessment](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift:278>)).  
Fix: Verify Firebase Auth user existence and create/merge the root document after purchase verification, or add a guaranteed pre-purchase root-document invariant plus durable resync.

8. [HIGH] `node --check` and rules compilation test syntax only; none of the security, atomicity, date, logging, or response deliverables has executable acceptance coverage.  
Fix: Add fixed-clock function tests and Firestore-emulator tests covering every status/no-write path, auth/ownership, replay/renewal/concurrency, expiry edge cases, exact response/log schemas, and rules read/create/update/delete/subcollection behavior.

9. [HIGH] Production mitigation and rollout are absent: there is no live-rules reconciliation, entitlement backup, staging/canary, monitoring threshold, or rollback procedure, despite a stale “NOT DEPLOYED” warning in the rules file ([rules](</Users/adampowell/Desktop/Peezy 4.0/firestore.rules:51>)).  
Fix: Reconcile against deployed rules, export entitlement data, rehearse in emulator/staging, define rollback artifacts and alerts, then deploy the rules gate before the verified endpoint in a controlled window.

10. [MEDIUM] “Transaction/batch” is internally incorrect: a batch cannot perform the conditional reads, and checking user existence outside the transaction introduces a delete/recreate race.  
Fix: Require one Firestore transaction that reads both the binding and user document before any writes and test competing claims plus concurrent deletion ([Firestore semantics](https://firebase.google.com/docs/firestore/manage-data/transactions)).

11. [MEDIUM] Input and response contracts remain underspecified: null bodies, non-string or path-invalid IDs, permissive date parsing, client-controlled `environment`/`isUpgraded`, expired weekly purchases marked active, and internal error-message leakage are unresolved.  
Fix: Specify a strict bounded schema, canonical date representation, server-derived fields and `isActive`, stable JSON responses for every status, and structured reason-code logs using only the verified UID.

12. [MEDIUM] Splitting `allow write` without specifying `delete` silently changes behavior; preserving delete lets owners erase protected billing state, while omitting it may break an assumed workflow.  
Fix: Explicitly set owner root-document delete to false, confirm Admin SDK account deletion still works, and include that decision in emulator acceptance tests.

VERDICT: ITERATE
### Response (Rev 2, builder)

Adopted:
- F3: renewal advancement rule — same user + new transactionId + purchaseDate > stored and ≤ now+5min advances expiry; replays (purchaseDate ≤ stored) are 200/no-op. Verified the deployed client syncs renewals exactly this way (SubscriptionManager.syncToServer sends originalID + new id per transaction).
- F4 (arithmetic half): annual = +12 calendar months, move = +6 calendar months via entitlement.js addCalendarMonths semantics (end-of-month clamp, UTC).
- F5 (partial): legacy-binding repair path + no-downgrade guard; full Apple reverification staged to Stage-2.
- F6: no-downgrade guard — never overwrite a users.subscription with a strictly-later expirationDate (protects gift entitlements; entitlement.js:91 write verified).
- F7: replaced Firestore doc-existence with admin.auth().getUser(); verified in code that signUp creates no root doc and purchase happens pre-Home (CompletionFlowView), so doc-existence would strand first purchases.
- F8 (partial): pure decision core (functions/subscriptionDecision.js) + fixed-clock test suite, one test per decision path; emulator rules tests moved to the deploy gate.
- F10: single Firestore transaction, all reads before writes; batch language removed. Auth check stays outside the txn (Auth is not Firestore) with the race documented as accepted.
- F11: strict input schema, ID regex, ignored client expirationDate, computed isActive (expired sync → isActive:false), stable error JSON without error.message, structured reason-code logs.
- F12: explicit `allow delete: if false` with rationale (deleteAccount is Admin SDK server-side).

Rejected / deferred (with reason):
- F1, F2: require a client that can send tokens (Build 23 frozen in App Store review) or App Store Server API credentials (not provisioned; functions/.env hook-blocked). Deferred to a committed Stage-2 section; residual risk now stated explicitly in the threat model instead of implied.
- F4 (Apple-truth half), F9 (rollout rehearsal): Stage-1 is no-deploy by explicit user mandate; deploy gate section documents reconciliation, ordering, rollback, and monitoring for the deploying session.
- F6 (immutable-records data model): frozen COMPLIANCE SubscriptionManager reads users/{uid}.subscription directly; a data-model change is client-affecting and out of Stage-1 scope.

## Round 2 — Codex (resumed thread 01a0066f-eb85-79f2-8057-204204a39af0)

1. [CRITICAL] Prior F1 remains unresolved, and the new threat model is false: because `userId` is caller-selected, an attacker can mutate any known user—not merely self-grant—and a later fabricated entitlement can replace a victim’s gift `source`, which the client requires to recognize gift access ([plan](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-stage1-subscription-hardening.md:14>), [client check](</Users/adampowell/Desktop/Peezy 4.0/Peezy 4.0/MainInterface/Models/SubscriptionManager.swift:327>)).  
Fix: Require and verify a Firebase ID token before deploying the function change, or restrict Stage 1 to the rules fix and explicitly defer entitlement writes until an authenticated client ships.

2. [CRITICAL] Prior F2 is documented but not mitigated: fabricated transaction IDs still create authoritative records consumed by `requireMovePass`, so this remains a direct paid-feature bypass.  
Fix: Provision App Store Server credentials and verify Apple-signed transaction data before treating the endpoint as an entitlement source ([Apple verification endpoint](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-info)).

3. [HIGH] The no-downgrade guard protects only strictly later existing expirations; an attacker can submit a later fake annual entitlement, overwrite a valid gift map, remove `source: giftCode`, and deny the victim client-side access despite lengthening the date.  
Fix: Never replace a gift entitlement from this endpoint; preserve its complete map until an authenticated, Apple-verified purchase explicitly supersedes it.

4. [HIGH] Transaction binding introduces an account-deletion regression: `deleteAccount` removes `users/{uid}` but not top-level `subscriptions`, so restored purchases under a recreated UID receive 403, while a concurrent unauthenticated sync can resurrect the deleted user document ([deletion flow](</Users/adampowell/Desktop/Peezy 4.0/functions/index.js:215>)).  
Fix: Expand scope to clean or tombstone subscription bindings during deletion and test deletion, concurrent sync, recreation, and purchase restoration.

5. [HIGH] Renewal/idempotency invariants remain incomplete: same-transaction refresh specifies stored `purchaseDate` but not stored `productId`, and new transaction IDs require only the upper time bound despite claiming the same seven-day window as new bindings.  
Fix: Treat `(transactionId, productId, purchaseDate)` as an immutable tuple and require every new transaction ID to fall within `[now−7 days, now+5 minutes]`.

6. [HIGH] Prior F8 is still only partially addressed: pure-core tests cannot prove wrapper atomicity or rule behavior, and the claimed deploy-gate rules tests do not actually appear in the deploy-gate steps.  
Fix: Add endpoint transaction tests plus Firestore-emulator rules tests now, covering authenticated/unauthenticated create, update, removal, delete, subcollections, transaction retries, and zero partial writes ([Firebase recommendation](https://firebase.google.com/docs/firestore/security/test-rules-emulator)).

7. [HIGH] The unauthenticated endpoint permits unbounded storage and billing abuse: repeated fresh IDs for one valid UID create unlimited `subscriptions` documents even when the no-downgrade guard preserves the user entitlement.  
Fix: Require authentication/App Check and enforce request-rate and per-user binding-cardinality limits before creating a binding.

8. [MEDIUM] “No PII beyond uid” contradicts logging raw `originalTransactionId`, a persistent purchase identifier; transaction retries could also emit more than the promised one log line per request.  
Fix: Hash or omit transaction identifiers and emit one bounded structured event outside the retryable transaction callback.

9. [MEDIUM] `admin.auth().getUser()` failure handling is underspecified: only `auth/user-not-found` merits 404, while permission, quota, and service failures must be 500; distinct unauthenticated responses also create a UID-existence oracle.  
Fix: Map only user-not-found internally, return a generic external failure, and test transient Auth errors separately.

10. [HIGH] Prior F9 remains incomplete: Git rollback restores code but cannot repair overwritten entitlement data, and the deploy gate still lacks a data snapshot, staging/canary pass, measurable thresholds, and restoration procedure.  
Fix: Export both subscription collections, rehearse the exact rollout in staging/emulators, define success/5xx thresholds, and document data restoration before production deployment.

11. [MEDIUM] Stage 2 has no compatibility sequence: immediately requiring tokens would reject still-installed Build 23 clients and stop renewal synchronization.  
Fix: Version the endpoint or deploy token-capable clients first, measure adoption, then enforce authentication with a dated legacy sunset.

VERDICT: ITERATE
### Response (Rev 3, builder)

Adopted:
- R2 #3 (gift clobber): gift preservation is now absolute — the endpoint never replaces any part of a source=='giftCode' map regardless of computed expiry (`gift_preserved`); verified the frozen client requires source for gift recognition (SubscriptionManager.swift:327-337).
- R2 #4 (deletion regression): verified deleteAccount recursiveDeletes users/{uid} only (index.js:218), leaving bindings orphaned. Healed in-endpoint: owner-mismatch now checks whether the bound uid still exists in Auth; deleted → rebind allowed (`rebound_after_deletion`); tombstoning at deletion time is Stage-2 item 6.
- R2 #5a (immutable tuple): same-transactionId refresh recomputes from stored (productId, purchaseDate); incoming productId mismatch logged and ignored.
- R2 #6 (partial): wrapper-level tests added (stubbed txn + Auth) — zero-writes-on-reject, single-transaction atomicity, 404/500 Auth mapping, one-log-under-retry. Emulator rules tests now an explicit enumerated deploy-gate step (Rev 2 inconsistency fixed).
- R2 #7 (partial): per-uid binding cap (100, in-transaction aggregate count, 429 `binding_cap`); DoS-by-cap trade-off documented.
- R2 #8: single structured log emitted outside the retryable callback; originalTransactionId logged as 8-char SHA-256 prefix.
- R2 #9: only auth/user-not-found → 404; other Auth errors → 500 generic; uid-oracle accepted (28-char random uids) and documented.
- R2 #10 (partial): deploy gate now includes gcloud firestore export of both collections pre-deploy, restoration path, and concrete watch thresholds (5xx > 1%, reason-code spikes).
- R2 #11: Stage-2 gains an explicit compatibility sequence (dual-accept window, adoption measurement, dated sunset).
- R2 #1 (threat-model half): "self-grant only" claim removed; capability matrix added; fabricated-ID residual explicitly labeled a requireMovePass paid-feature bypass with named consumers.

Rejected / deferred (with reason):
- R2 #1/#2 (auth + Apple verification as Stage-1 blockers): unchanged constraints — Build 23 cannot send tokens, no App Store Server API credentials provisioned, functions/.env hook-blocked. Rules-only alternative rejected: the endpoint is live and wide open today; the function hardening strictly reduces attacker capability with zero legitimate-client impact.
- R2 #5b (renewal lower bound now−7d): rejected with a user-harm case — a lapsed annual renewal synced 30 days late must still grant the remaining ~11 months; upper bound + monotonicity already caps a forger at now + one product period (identical to the new-binding bound), so the lower bound adds breakage without security. Pinned by test #9.
- R2 #6 (full emulator suite in Stage-1): Stage-1 does not deploy; suite is a mandatory enumerated deploy-gate step instead.
- R2 #7 (request-rate limiting): needs App Check/gateway — Stage-2 with auth.

## Round 3 — Codex (resumed thread 01a0066f-eb85-79f2-8057-204204a39af0)

1. [HIGH] The hard 100-binding cap is unsafe and ineffective: an attacker can fill a victim’s slots and block legitimate new purchases, while deleted-owner rebinding bypasses the “new binding” cap entirely; this contradicts the claims that growth is bounded and surviving cross-user effects cause no victim harm ([plan](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-stage1-subscription-hardening.md:79>)).  
Fix: Make the Stage‑1 threshold alert-only, or enforce it on every ownership-changing path with an explicit recovery mechanism and cap-exhaustion tests.

2. [HIGH] Deleted-owner rebinding is not fail-closed: error mapping is specified for the target UID lookup but not `getUser(boundUid)`, and the out-of-transaction result is not explicitly tied to the same bound UID reread during the second transaction.  
Fix: Rebind only when the exact reread owner UID produced `auth/user-not-found`; return 500 for every other Auth error or owner change, with transient-error and concurrent-rebind tests.

3. [MEDIUM] The seven-day lower bound for new bindings has the same user-harm/no-security problem Rev 3 correctly identifies for renewals: an older legitimate first sync with remaining annual or Move Pass access is rejected even though accepting it cannot exceed the existing upper expiry bound.  
Fix: For new bindings require valid ISO date and `purchaseDate ≤ now+5min`, then derive activity from computed expiry instead of imposing a seven-day lower bound.

4. [MEDIUM] The account-deletion race is inaccurately called “self-healing”: no subsequent deletion sweep exists, so an in-flight request that passed Auth before deletion can recreate `users/{uid}` permanently after `recursiveDelete` ([deletion flow](</Users/adampowell/Desktop/Peezy 4.0/functions/index.js:215>)).  
Fix: Document this as an orphan-data residual and require a post-Auth-delete cleanup/tombstone in Stage 2 rather than claiming automatic healing.

5. [MEDIUM] Acceptance coverage omits the new control’s highest-risk cases: concurrent cap enforcement, cap behavior during rebinding, and transient bound-owner Auth failures.  
Fix: Add tests for simultaneous 99→100 creations, cap-exhausted rebinds, bulk orphan rebinds, Auth quota failure, and owner changes between the two transactions.

6. [LOW] “Exactly one log reason” is ambiguous when multiple outcomes apply—for example, a same-transaction product mismatch against an existing gift requires both `product_mismatch` and `gift_preserved`.  
Fix: Define deterministic primary-reason precedence plus a bounded `flags` array, and assert the combined case.

7. [MEDIUM] The rollback procedure promises “targeted import of affected docs,” but no executable extraction/restoration command or validation step is specified.  
Fix: Name the export bucket and provide a rehearsed per-document restoration script or temporary-project extraction procedure with a post-restore comparison.

VERDICT: ITERATE
### Status after Round 3

Round cap (3) exhausted without APPROVE. Severity trajectory: R1 = 2 CRITICAL / 7 HIGH / 3 MEDIUM; R2 = 2 CRITICAL / 6 HIGH / 3 MEDIUM; R3 = 0 CRITICAL / 2 HIGH / 4 MEDIUM / 1 LOW — all R3 findings target mechanisms Rev 3 itself introduced (binding cap, deleted-owner rebinding), and the staged residual-risk approach is no longer contested. Builder assessment: all 7 findings are cheap plan edits (cap → alert-only; fail-closed rebind spec; deletion-race reworded as residual; added tests; log precedence; named restoration procedure). R3 #3 would amend the original user spec (drop the −7d lower bound on NEW bindings) — escalated to the user rather than decided by the builder. Awaiting user decision: accept as-is / one more round / abandon. Chain budget spent: 3 of 6.

### Response (Rev 4, builder — user opted for a fourth round; user approved dropping the −7d lower bound)

All seven Round-3 findings adopted:
- R3 #1: binding threshold is alert-only (`binding_cap_alert` flag, write proceeds); hard cap rejected as a DoS primitive; enforcement deferred to Stage-2 auth.
- R3 #2: fail-closed rebind — rebind only on auth/user-not-found for the exact owner uid reread in the second transaction; owner change or any other Auth error → 500, no writes.
- R3 #3: −7d lower bound on NEW bindings removed by explicit user decision (AskUserQuestion; amends original spec 2c). Late first syncs heal; security unchanged (≤ now+5min bound holds everywhere).
- R3 #4: "self-healing" claim removed; deletion race documented as accepted orphan-data residual; Stage-2 item 6 extended with post-deletion sweep.
- R3 #5: tests added — fail-closed owner change (6), alert threshold (8), combined log outcome (14), transient bound-owner Auth failure (22).
- R3 #6: log schema is outcome/reason/flags with deterministic precedence; combined case pinned by test 14.
- R3 #7: export command named (gs://[PROJECT_ID].appspot.com/backups/pre-stage1-<date>), emulator-rehearsed restoration script with post-restore diff, production import as fallback only.

## Round 4 — Codex (resumed thread 01a0066f-eb85-79f2-8057-204204a39af0)

1. [HIGH] Absolute gift-map preservation creates a paid-user outage: a purchase made while a gift exists updates only the binding, so when the gift expires `requireMovePass` still reads the expired gift date and denies server features despite the valid StoreKit purchase ([plan](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-stage1-subscription-hardening.md:82>), [guard](</Users/adampowell/Desktop/Peezy 4.0/functions/entitlement.js:39>)).  
Fix: Preserve `source: giftCode` and gift metadata, but set `expirationDate` to `max(giftExpiry, computedPurchaseExpiry)` and recompute `isActive`; test purchases during and after gift expiry.

2. [MEDIUM] The restoration rehearsal remains non-executable as written: Firebase Emulator Suite imports its own `emulators:export` format, whereas `gcloud firestore export` produces a managed export intended for import into a Firestore database, not directly into the emulator ([emulator format](https://firebase.google.com/docs/emulator-suite/connect_firestore), [managed export](https://docs.cloud.google.com/firestore/native/docs/manage-data/export-import)).  
Fix: Rehearse by importing the managed export into a temporary Firestore database/project, or create a parallel Admin-SDK JSON snapshot designed for per-document emulator restoration.

3. [LOW] The current ADR still says “per-uid binding cap” even though Rev 4 correctly replaced enforcement with an alert-only threshold ([ADR](</Users/adampowell/Desktop/Peezy 4.0/docs/plans/codex-review-stage1-subscription-hardening.md:157>)).  
Fix: Replace the stale cap language with “per-uid binding-count alert.”

VERDICT: ITERATE
### Response (Rev 5, builder)

All three Round-4 findings adopted:
- R4 #1: gift handling is now identity-preserving but date-extending — source/productId/metadata untouched, expirationDate = max(giftExpiry, computedPurchaseExpiry). Verified requireMovePass reads only subscription.expirationDate (entitlement.js:39-46), confirming the outage scenario. Test 13 pins all three gift cases.
- R4 #2: per-doc restoration re-sourced to an Admin-SDK JSON snapshot (snapshotSubscriptions.js); managed gcloud export retained as whole-database fallback only (it cannot import into the emulator).
- R4 #3: ADR wording updated (binding-count alert; identity-preserving gift handling).

Extended round cap (4) exhausted without APPROVE; findings trajectory 12 → 11 → 7 → 3 with zero contested items remaining. Chain budget spent: 4 of 6. Awaiting user decision on a final conversion round.

## Round 5 — Codex (resumed thread 01a0066f-eb85-79f2-8057-204204a39af0)

No new findings. Rev 5 closes all three Round 4 findings: gift expiry extension is correctly specified and tested, per-document restoration uses the Admin-SDK JSON snapshot, and the ADR wording is consistent. The Stage-1 plan is internally consistent, executable, and strictly risk-reducing within the accepted constraints.

VERDICT: APPROVE
## Final summary

Consensus reached at Round 5 (user-extended cap; original cap 3). Verdict trajectory:

| Round | Verdict | Findings |
|---|---|---|
| 1 | ITERATE | 12 (2 CRITICAL / 7 HIGH / 3 MEDIUM) |
| 2 | ITERATE | 11 (2 CRITICAL / 6 HIGH / 3 MEDIUM) |
| 3 | ITERATE | 7 (2 HIGH / 4 MEDIUM / 1 LOW) |
| 4 | ITERATE | 3 (1 HIGH / 1 MEDIUM / 1 LOW) |
| 5 | APPROVE | 0 |

Chain budget spent: 5 of 6 (1 remaining for codex-execute). Approved plan: docs/plans/codex-review-stage1-subscription-hardening.md (Rev 5, carries ADR). User decisions on record: extend to round 4; drop the −7d lower bound on new bindings (amending original spec 2c); extend to round 5.

## Execution record (Stage-1, Sol worker)

Worker: gpt-5.6-sol, codex thread 01a00691-b038-78a1-95b3-5fd38d8d1b79 (workspace-write, single item, 1 round — chain budget now 6/6 spent; final Sol review skipped for budget, replaced by orchestrator verification).
Base: a7ab11b. Files: firestore.rules (rules split, exact plan After block), functions/validateSubscription.js (thin DI wrapper), functions/subscriptionDecision.js (new pure core), functions/tests/validateSubscription.test.js (new, 24 tests).
Orchestrator-verified evidence (not worker-claimed): node --check SYNTAX-OK; node --test 24/24 pass; firebase deploy --only firestore:rules --dry-run → "compiled successfully / Dry run complete"; full diff read; scope confirmed clean (untracked seedAppReviewGiftCode.js byte-identical to pre-run backup). Known cosmetic nit: infra transaction failures log reason "auth_error" (response body remains the correct generic "Sync failed"). Not committed, not deployed.
