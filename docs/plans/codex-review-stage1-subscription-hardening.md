# Plan: Stage-1 Subscription Hardening (rules + validateSubscription) — Rev 5

Work in ~/Desktop/Peezy 4.0. Implement Stage-1 hardening. **No client changes** — Build 23 is in App Store review; the deployed client (SubscriptionAPIClient.swift) sends an unauthenticated POST and **ignores the response body entirely** (only the HTTP status code is checked, fire-and-forget from SubscriptionManager.syncToServer).

## Scope & threat model (Stage-1)

Baseline reality: the endpoint is **already deployed and wide open** — it trusts every client field, including `expirationDate`/`isActive`, for any caller-chosen uid, and the rules let any signed-in user write their own `subscription` field. Stage-1 hardens a live hole; it is not the introduction of a new entitlement source.

Attacker capabilities **after** Stage-1 (unauthenticated caller, any known uid):

| Capability | Status after Stage-1 |
|---|---|
| Write `users/{uid}.subscription` via client SDK | **Closed** (rules) |
| Shorten/remove any user's entitlement | **Closed** (no-downgrade guard; gift maps never replaced) |
| Clobber a gift entitlement's `source` | **Closed** (gift identity fields are never replaced; only the expiry can be raised) |
| Hijack an existing user↔transaction binding | **Closed** (403 on owner mismatch) |
| Dictate expiry / active flag | **Closed** (server computes) |
| Unbounded `subscriptions` doc creation | **Monitored** (alert-only threshold at 100 bindings/uid; a hard cap would hand an unauthenticated attacker a DoS primitive against victims, so enforcement waits for Stage-2 auth) |
| Self-grant (or grant a victim) up to one product period via a fabricated fresh transaction ID | **OPEN — accepted residual.** Consumed by `requireMovePass` (peezyChat, processInventory, researchTask), so this is a real paid-feature bypass until Stage-2. Unfixable without a token-sending client (Build 23 is frozen in review) or App Store Server API credentials (not provisioned; `functions/.env` hook-blocked). |

Lengthening a victim's server-side record is the only cross-user mutation that survives; it grants the victim free access (revenue loss, no victim harm) and is detectable via binding-creation logs.

## Stage-2 commitments (separate change, after Build 23 ships)

1. Client sends Firebase ID token (+ App Check); server derives uid from the verified token, 401 on mismatch.
2. Server verifies transactions via App Store Server API (Get Transaction Info, JWS verification via `@apple/app-store-server-library`); all fields derived from Apple's signed payload; `appAccountToken` set at purchase for cryptographic user binding.
3. Renewal truth from Apple's `expiresDate`/status (trials, grace, billing retry, revocation).
4. Legacy `subscriptions/*` reverification against Apple; quarantine unverifiable records.
5. **Compatibility sequencing**: dual-accept window — deploy token-capable client, keep accepting unauthenticated syncs while measuring Build-23 traffic decay, then enforce auth with a dated sunset. No flag-day rejection of installed clients.
6. `deleteAccount` tombstones the departing uid's `subscriptions` bindings and sweeps any `users/{uid}` doc recreated by an in-flight sync that raced the deletion (Stage-1 heals the recreation path's 403 server-side, see 2d, and accepts the race as an orphan-data residual; the cleanup belongs with the deletion function).

## 1 — firestore.rules

Root `users/{userId}` match only. Owner read unchanged (the frozen SubscriptionManager reads `users/{uid}.subscription` for gift-code entitlement — reads must keep working). Subcollection rules untouched. Verified safe: every client root-doc write is merge-based and never touches `subscription` (DailyDoseEngine.swift:35 `merge: true`; BoxReturnService kitCalibration merge; all other writers target subcollections), so no legitimate write is denied by the new rule.

**Before** (firestore.rules:5-8):

```
    // User document — only the owning user can read/write
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
```

**After**:

```
    // User document — owner-readable. The subscription entitlement field is
    // backend-owned (validateSubscription / gift redemption, Admin SDK):
    // owner writes may never create, modify, or remove it. Root-doc delete
    // is server-side only (deleteAccount, Admin SDK).
    match /users/{userId} {
      allow read: if request.auth != null && request.auth.uid == userId;
      allow create: if request.auth != null && request.auth.uid == userId
        && !request.resource.data.keys().hasAny(['subscription']);
      allow update: if request.auth != null && request.auth.uid == userId
        && !request.resource.data.diff(resource.data).affectedKeys().hasAny(['subscription']);
      allow delete: if false;
    }
```

Decisions made explicit:
- `write` is split into `create`/`update`/`delete`. **`delete: if false` is deliberate**: account deletion is server-side Admin SDK (`deleteAccount` → `recursiveDelete`, functions/index.js:218), which bypasses rules; no client code deletes the root doc.
- `affectedKeys()` counts field *removal* as affected, so a client overwrite-without-merge that would drop `subscription` is denied — intended protection; no current client code does it.

## 2 — functions/validateSubscription.js

Keep endpoint shape (same URL, method, request fields, response JSON keys — `{success, subscription: {productId, expirationDate, isActive}}` on 200; `{error}` on failure). Restructure internals: extract a **pure decision core** (new file `functions/subscriptionDecision.js`, exports `decide(input, ctx)` — no I/O, fully unit-testable with a fixed clock); `validateSubscription.js` becomes the thin I/O wrapper (parse → auth-user check → one Firestore transaction driven by the decision core → single structured log → response).

a. **Input validation (strict, before any I/O).** Body must be a JSON object. `userId`, `originalTransactionId`, `transactionId` non-empty strings matching `^[A-Za-z0-9._-]{1,128}$` (no path separators). `productId` must be in the allowlist `peezy.plus.move` | `peezy.plus.weekly` | `peezy.plus.annual`. Else **400, no writes**. `environment` sanitized to a string ≤ 32 chars, `isUpgraded` coerced boolean — stored, never trusted. Client-sent `expirationDate` is **ignored** (never stored as truth, never echoed).

b. **Server computes expiry — never trust client `expirationDate`/`isActive`.** UTC calendar arithmetic reusing the exact `addCalendarMonths` semantics already in entitlement.js:24 (end-of-month clamped): move = purchaseDate + 6 calendar months; weekly = purchaseDate + 7 days; annual = purchaseDate + **12 calendar months** (leap-year correct). `isActive` = computed expiry > now, computed at response time — an expired purchase syncs as `isActive: false`.

c. **purchaseDate sanity.** Must parse as ISO-8601 (the client sends `ISO8601DateFormatter` output) and be ≤ now+5min — else **400, no writes**. **No lower bound — user-approved amendment of the original "≥ now−7days" spec**: a legitimate late first sync (e.g. an annual purchase whose fire-and-forget initial sync failed) must still create its binding months later; accepting an old purchaseDate can never yield a later expiry than a fresh fabrication, and mostly-elapsed or expired purchases simply sync with their true remaining window (`isActive` may be false).

d. **One Firestore transaction (not a batch — conditional reads require a transaction).** All reads before any writes, per Firestore transaction semantics:
   - Read `subscriptions/{originalTransactionId}` and `users/{userId}` inside the transaction.
   - **Owner mismatch (fail-closed)**: binding exists with a different userId → the transaction aborts, then `admin.auth().getUser(boundUid)` runs outside it. Rebinding to the requesting uid is allowed **only** when that exact lookup returned `auth/user-not-found`; the transaction then re-runs and re-reads the binding — if the owner uid read in the second transaction is not the same uid that was just verified deleted, abort with **500, no writes** (owner changed mid-flight). Any other Auth error on the boundUid lookup (quota, transient, permission) → **500, no writes** (`auth_error`). Verified-deleted → rebind (heals the account-delete→recreate→restore-purchases path: `deleteAccount` recursive-deletes `users/{uid}` but leaves `subscriptions/*` orphaned, which would otherwise 403 forever; log `rebound_after_deletion`). Bound uid still exists → **403, no writes** (`binding_conflict`).
   - **New binding** → create `subscriptions/{originalTransactionId}` (with `createdAt`) + write `users/{userId}.subscription` atomically. **Alert-only threshold**: count existing bindings for this userId (aggregate count in-transaction); ≥ 100 → still write, but add `binding_cap_alert` to the log line's flags. A hard cap is deliberately NOT enforced on any path — it would hand an unauthenticated attacker a DoS primitive (fill a victim's slots, block their real purchase) and the rebinding path would bypass it anyway; hard enforcement arrives with Stage-2 auth.
   - **Same-user re-sync, same `transactionId`** → idempotent refresh: the stored `(productId, purchaseDate)` tuple is immutable — expiry recomputed from **stored** productId + purchaseDate (not the incoming values, not extended); incoming productId mismatch is logged (`product_mismatch`) and ignored. If the stored purchaseDate is missing/unparseable (legacy rows from the old open endpoint), repair it from the incoming sanity-checked purchaseDate; if that also fails, 400 (`invalid_purchase_date`, log `legacy_repair_failed`).
   - **Same-user re-sync, NEW `transactionId`** (StoreKit renewal: same originalID, new id — the deployed client sends exactly this): advance only if incoming purchaseDate > stored purchaseDate AND ≤ now+5min → update binding's transactionId/productId/purchaseDate, recompute expiry. **Deliberately no −7day lower bound here**: a lapsed annual renewal synced 30 days late must still grant the remaining 11 months, and the attack bound is unchanged — max fake expiry ≈ now + one product period, identical to the new-binding bound now that both paths share the same ≤ now+5min rule. A new transactionId with purchaseDate ≤ stored is an out-of-order replay: 200, no binding mutation, log `replayed_transaction`.
   - **Gift preservation (identity-preserving, date-extending)**: if `users/{userId}.subscription.source == 'giftCode'`, this endpoint never replaces the gift map's identity fields — `source`, `productId`, and the rest of the gift metadata stay untouched, because the frozen client requires `source` for gift recognition (SubscriptionManager.swift:327-337). But the date must not strand a genuine purchaser after the gift lapses: `requireMovePass` reads only `subscription.expirationDate` (entitlement.js:39-46), so set `expirationDate = max(giftExpiry, computedPurchaseExpiry)` (plus `updatedAt`), leaving everything else as-is. Binding still recorded; respond 200 with the effective entitlement; log `gift_preserved`, adding the `gift_extended` flag when the date was raised. Lengthen-only, so this stays inside the already-accepted residual class.
   - **No-downgrade guard (non-gift)**: if the existing `users/{userId}.subscription` has a parseable `expirationDate` strictly later than the newly computed one, keep it untouched, still upsert the binding, respond 200 with the *effective* entitlement values, log `skipped_downgrade`.

e. **User existence: Firebase Auth, not Firestore doc.** `admin.auth().getUser(userId)` must succeed → else **404, no writes** (`unknown_user`). *Deliberate change from the original "users/{userId} doc must exist":* verified in code that nothing guarantees the root doc exists at purchase time — signUp creates only the Auth user, and the paywall fires in CompletionFlowView before Home's DailyDoseEngine ever writes the root doc — so doc-existence would strand real first purchases. The users write stays set-merge (creates the doc if absent). **Error mapping**: only `auth/user-not-found` → 404; any other Auth failure (quota, permission, transient) → 500 with generic body. The uid-existence oracle this creates is accepted: Firebase uids are 28-char random strings, enumeration is impractical, and the log stream surfaces probing. The Auth check runs before the transaction (Auth is not Firestore and cannot join it); the delete/recreate race — an in-flight request that passed the Auth check just before `recursiveDelete` can recreate `users/{uid}` afterward — is an accepted **orphan-data residual**: no automatic sweep exists to clean it, and Stage-2 item 6's post-deletion cleanup/tombstone covers it.

f. **Structured logs, no PII beyond uid.** Exactly one structured line per request, emitted **after** the transaction completes (never inside the retryable callback, so retries cannot multiply log lines): `{event: 'validateSubscription', outcome, reason, flags?, uid, otxHash, productId}` where `otxHash` is an 8-char SHA-256 prefix of `originalTransactionId` (a persistent purchase identifier stays out of logs; the hash still correlates repeat abuse). `outcome` ∈ `rejected` | `synced` | `noop`. `reason` is one primary code chosen by deterministic precedence: any rejection code > `rebound_after_deletion` > `gift_preserved` > `skipped_downgrade` > `replayed_transaction` > `renewed` > `created` > `refreshed`. Secondary observations go in a bounded `flags` array (≤ 4): `product_mismatch`, `binding_cap_alert`, `legacy_repaired`, `gift_extended`. Rejection codes: `invalid_input`, `invalid_product`, `invalid_purchase_date`, `future_purchase_date`, `binding_conflict`, `unknown_user`, `auth_error`, `legacy_repair_failed`. The 500 handler returns stable `{error: 'Sync failed'}` — no `error.message` leakage.

## Acceptance criteria (executable)

New `functions/tests/validateSubscription.test.js` (same harness as the existing functions/tests suite), fixed clock, two layers:

**Decision core** (pure, one test per path):
1. Non-allowlisted productId → reject, zero writes.
2. Unparseable / future (> now+5min) purchaseDate → reject, zero writes.
3. New binding with a months-old purchaseDate (failed original sync) → accepted; expiry = purchaseDate + period; `isActive` reflects the remaining window (the no-lower-bound case, user-approved).
4. Binding held by different, still-existing uid → 403 path, zero writes.
5. Binding held by a verified-deleted uid → rebind to requester (`rebound_after_deletion`).
6. Owner uid read in the second transaction differs from the verified-deleted uid → 500, zero writes (fail-closed rebind).
7. New binding → both writes present; expiry = purchaseDate + correct period for all three products, incl. end-of-month clamp (Aug 31 + 6mo) and leap-year annual.
8. New binding for a uid at the 100-binding alert threshold → write still happens; log flags include `binding_cap_alert`.
9. Same user, same transactionId → idempotent; expiry from stored (productId, purchaseDate); incoming productId mismatch → `product_mismatch` flag, incoming values ignored.
10. Same user, new transactionId, newer purchaseDate ≤ now+5min → advance (renewal).
11. Same user, new transactionId, purchaseDate > stored but 30 days old → advance (late lapsed renewal).
12. Same user, new transactionId, purchaseDate ≤ stored → no mutation (`replayed_transaction`).
13. Gift handling, three cases: gift with later expiry + purchase sync → gift map byte-for-byte untouched (`gift_preserved`); purchase whose computed expiry exceeds the gift's → only `expirationDate`/`updatedAt` raised, `source`/`productId`/metadata unchanged (`gift_extended` flag); purchase synced after the gift expired → date raised so `requireMovePass` passes again.
14. Combined outcome: same-transactionId product mismatch against a gift user → primary reason `gift_preserved`, flags contain `product_mismatch` (precedence asserted).
15. Non-gift existing entitlement with later expiry → preserved (`skipped_downgrade`).
16. Expired purchase re-sync → `isActive: false`.
17. Legacy binding with unparseable stored purchaseDate → repaired from valid incoming; reject if incoming also invalid.
18. Response JSON has exactly the legacy keys on 200; `{error}` only on failures.

**Wrapper** (stubbed Firestore transaction + stubbed Auth):
19. Every reject path performs zero Firestore writes (transaction never receives a set/update).
20. All writes for a new binding land in one transaction object (atomicity).
21. `auth/user-not-found` on the target uid → 404; simulated Auth quota error on the target uid → 500 generic body.
22. Transient Auth error on the bound-owner lookup during rebind → 500 (`auth_error`), zero writes.
23. Method ≠ POST → 405; non-object body → 400.
24. Exactly one log line per request under a transaction that retries (stub forces one retry).

## VERIFY (Stage-1 exit — no commit, no deploy)

- `node --check` on all touched/new function files.
- `functions/tests/validateSubscription.test.js` green (full suite run).
- Rules compile: firebase-tools dry-run compile (or Rules REST API compile check via functions/serviceAccountKey.json, read-only).
- Report: full rules before/after (above, confirmed against the final file) + function diff summary. **Do not commit or deploy.**

## Deploy gate (documented now, NOT executed in Stage-1)

1. Reconcile checked-in vs **deployed** rules via the Rules REST API (read-only, serviceAccountKey.json — firebase-tools 15.6.0 cannot read deployed rules). The stale "NOT DEPLOYED" identity-rules comment at firestore.rules:51-53 must be resolved in that same reconciliation.
2. **Emulator rules tests** (`@firebase/rules-unit-testing`) before the rules deploy: owner read allowed; create with/without `subscription`; update touching/not touching `subscription` (including removal-via-overwrite); delete denied; a subcollection write unaffected; unauthenticated denied everywhere.
3. **Data snapshot before deploy — two artifacts**: (a) `gcloud firestore export gs://[PROJECT_ID].appspot.com/backups/pre-stage1-<date> --collection-ids=subscriptions,users` as the disaster-recovery fallback (managed exports import into a Firestore database, not the emulator — they are NOT the per-doc restoration source); (b) an Admin-SDK JSON snapshot (`functions/scripts/snapshotSubscriptions.js`, authored at gate time: dumps `subscriptions/*` and each `users/{uid}.subscription` field to a local JSON file). **Restoration procedure (rehearse once at gate time against the emulator)**: `functions/scripts/restoreSubscriptions.js` reads the JSON snapshot and writes affected doc(s) back per-document, then diffs the restored docs against the snapshot to confirm equality. Whole-database `gcloud firestore import` is the fallback only.
4. Deploy order: rules first (closes the client-write gap immediately, zero client impact), then `functions:validateSubscription`.
5. Post-deploy watch with thresholds: 5xx rate > 1% sustained, or a spike in `binding_conflict`/`binding_cap_alert`/`invalid_*` (probing or a broken client assumption) → roll back the function (git revision), restore any clobbered docs from the export via the rehearsed procedure.

## Reviewer pushback (cumulative)

**Rev 5 (Round 4 findings — all three adopted):**
- **R4 #1 (gift outage)** — adopted: gift handling is identity-preserving but date-extending (`expirationDate = max(giftExpiry, computedPurchaseExpiry)`); verified `requireMovePass` reads only the expiry (entitlement.js:39-46). Pinned by test 13's three cases.
- **R4 #2 (restoration format)** — adopted: per-doc restoration now sources from an Admin-SDK JSON snapshot (managed `gcloud` exports cannot import into the emulator); the managed export remains the whole-database fallback.
- **R4 #3 (stale ADR wording)** — adopted: "per-uid binding cap" → "per-uid binding-count alert" plus updated gift language.

**Rev 4 (Round 3 findings — all seven adopted):**
- **R3 #1 (cap DoS)** — threshold is alert-only; a hard cap would be an attacker's DoS primitive against victims and the rebind path would bypass it; hard enforcement deferred to Stage-2 auth.
- **R3 #2 (fail-closed rebind)** — adopted verbatim: rebind only when `getUser(boundUid)` returned `auth/user-not-found` for the exact owner uid reread in the second transaction; owner change or any other Auth error → 500, no writes.
- **R3 #3 (drop −7d lower bound on new bindings)** — adopted **by explicit user decision** (amends original spec item 2c): the upper bound plus computed expiry give identical security, and late first syncs (failed fire-and-forget) heal instead of stranding. Pinned by test 3.
- **R3 #4** — the deletion race is documented as an accepted orphan-data residual (no sweep exists); Stage-2 item 6 extended with the post-deletion cleanup.
- **R3 #5** — tests 6, 8, 14, 22 added; concurrent 99→100 enforcement tests are moot with an alert-only threshold.
- **R3 #6** — outcome/reason/flags log schema with deterministic precedence; the combined case is pinned by test 14.
- **R3 #7** — named export path, rehearsed emulator-based restoration script with post-restore diff, production import as fallback only.

**Rev 3 (Round 2 findings):**

- **F1/F2 (R2 #1, #2 — auth + Apple verification) — still Stage-2, with the residual now stated honestly.** The threat model no longer claims "self-grant only": the fabricated-ID residual is labeled a real paid-feature bypass (requireMovePass consumers named). The reviewer's alternative — rules-only Stage-1 — is rejected because the endpoint is live and wide open **today**: shipping the function hardening strictly reduces what an attacker can do (no more shortening, gift-clobbering, hijacking, or client-dictated expiry) while changing nothing for legitimate clients. Declining to harden a live endpoint because perfect verification isn't yet possible leaves the larger hole open longer.
- **R2 #5 (renewal lower bound) — rejected with a user-harm case**: requiring purchaseDate ≥ now−7d on renewal advancement would deny a lapsed annual subscriber their remaining 11 months if the app first syncs 30 days after renewal. The upper bound (≤ now+5min) plus monotonicity (> stored) caps a forger at now + one product period — exactly the new-binding bound — so the lower bound adds no security, only breakage. Test #9 pins this behavior. The productId half of R2 #5 is adopted (immutable stored tuple).
- **R2 #6 (emulator tests now) — split**: wrapper-level atomicity/no-write/retry tests added to Stage-1 (tests 16–20); emulator rules tests are now an explicit, enumerated deploy-gate step (the Rev 2 inconsistency is fixed) rather than Stage-1 scope, because Stage-1 does not deploy and the 8-line rules diff is hand-reviewed + compile-checked.
- **R2 #7 (rate limiting)** — binding-cardinality cap adopted (100/uid, in-transaction count). True request-rate limiting needs App Check or a gateway — Stage-2 with auth.
- **R2 #4 (deleteAccount cleanup)** — the 403-after-recreation regression is healed inside this endpoint (rebind when the bound uid is deleted) without expanding scope into `deleteAccount`; tombstoning orphaned bindings at deletion time is Stage-2 item 6.

## ADR

- **Decision**: Split the root users rule to make `subscription` backend-owned, and harden validateSubscription server-side (allowlist, server-computed expiry, sanity windows, transactional first-writer binding with deleted-owner rebinding and renewal advancement, per-uid binding-count alert, identity-preserving gift handling with date extension, no-downgrade guard, Auth-existence check with strict error mapping, single structured log per request) — without touching the deployed client or its endpoint contract.
- **Drivers**: Build 23 frozen in App Store review; open rules gap allows self-granted entitlements today; live endpoint currently trusts every client field for any uid.
- **Alternatives considered**: (1) Full Apple App Store Server API verification now — rejected for Stage-1: credentials not provisioned, secrets file hook-blocked; committed as Stage-2. (2) Require ID-token auth now — rejected: needs a client change Build 23 cannot ship. (3) Rules-only Stage-1 — rejected: leaves the live endpoint's worst behaviors (entitlement shortening, gift clobbering, client-dictated expiry) open. (4) Immutable entitlement records with derived max — rejected: frozen SubscriptionManager reads the current data model.
- **Why chosen**: Largest attack-surface reduction achievable with zero client impact and no new external dependencies; every remaining hole is named, bounded, and staged.
- **Consequences**: Fabricated fresh transaction IDs can still grant up to one product period (a real requireMovePass bypass) until Stage-2; renewals and late first syncs advance on sanity-bounded client assertion rather than Apple truth; `subscriptions` growth is unbounded but alerted at 100 docs/uid (a hard cap without auth would be a DoS primitive).
- **Follow-ups**: Stage-2 items 1–6; deploy-gate reconciliation of the stale NOT-DEPLOYED rules comment; deploy-gate data export + emulator rules suite.
