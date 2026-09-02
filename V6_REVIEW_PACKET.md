# V6 REVIEW PACKET — §13 item 7, two independent read-only passes

## Artifact identity (verify before any work; mismatch = stop)

```text
PHASE2_REPLACEMENT_MANIFEST_v6.md
bytes   509,128
lines   1,826
sha256  cd127b1bbffa42cc69f8d80a44e1da7d2db8458cef2e0c00c241ce9add00f4bf

Frozen spec under repair: docs/plans/PHASE2_EXECUTABLE_SPEC_v5.md
sha256  e02ef93867b744ec0ace9c0860ac309cb7e5fc14ee8c4762a265bd544ca2d2ab
```

Author of v6: Codex. Codex may not certify this artifact. Both passes run in fresh context.

## Rules for both passes

- Read-only. No file edits, no worktree, no emulator, nothing against any Firebase target.
- Findings only. No rewrites, no alternative architectures, no new subsystems, no "cleaner" suggestions.
- Every finding: `ID · P0/P1/P2 · manifest §/line · one-sentence claim · one-sentence evidence`.
- List every P0/P1. P2 capped at 10, editorial only.
- P0/P1 reopen the manifest as **v7 with a new hash**. Nothing is patched in place.
- Scope is locked. A finding must be a contradiction, a gap in a named contract, or an unfalsifiable promise — not an opinion.

## Pass A — codebase-aware migration/scheduler (Claude Code, repo read-only)

Verify against the current tree with file:line evidence:

1. §2.2–2.5 scheduler/refusal/codec contracts against `functions/dispositionTriggers.js` as it exists today: does any clause assume a function, export, or field that is absent and not listed as new in §12.2?
2. §3 MIG-EVENT-V1 and §6 MIG-RESET-V1: the legacy shapes each migration decodes — confirm the literal legacy authority in §6.1 matches committed bytes.
3. §5/§7/§8 client actors (`ResetGestureBinder`, `DurableStoreRecoveryCoordinator`, `DurableStoreReadiness`, `StartupBarrier`, `PeezyV1App` mount order) against current Swift files: any ownership claim that collides with an existing owner.
4. §12.2 path totals (91 client paths, 22 Swift test files, 23 suites, 24 Node tests + 1 rules test): recount from the manifest, then confirm every "existing" path exists and every "new" path does not.
5. §13 gate items 1–6 (set equality, fixture coverage, grep bans): rerun independently. Do not trust Codex's report.

## Pass B — schema/ownership/envelope/scope + proof-of-deletion contract (no repo needed)

Part 1 — the §13 item-7 schema/ownership pass on §§2, 5, 7, 8, 10, 11: exact-schema branches, disjoint unions, CAS/crash points, single-owner claims.

Part 2 — **derive the proof-of-deletion contract from v6.** This is an index, not new policy. It may add zero obligations. One row per store the product promise already covers:

| Store | Must be gone | Observed where / how | Evidence artifact | Named falsifier (file · test) | v6 authority § |
|---|---|---|---|---|---|

Stores that must each have a row (add any others v6 names; invent none):

- Firestore user root and every subcollection the fence covers
- Storage objects, retained copies, soft-delete/versioning residue
- Auth record and Auth retained-copy
- Local durable stores (task plan, journal, intents, route inbox)
- Quarantine
- Keychain / provider credentials
- SDK and provider caches (`provider-cache`)
- UserDefaults / preferences
- Pending and delivered notifications; FCM token
- Analytics, Crashlytics, Sessions/MetricKit
- Release logs (`print`/`os_log`/`Logger` sinks)
- Gmail / Twilio / Anthropic legacy destinations
- External indexes
- Backup/export destinations (BigQuery, linked projects) — only where v6 states they exist

Rules for the table:

- Every row must resolve to a v6 section and a named falsifier. A row with a section but no falsifier is **P1**. A row with a falsifier but no section is **P1**. A store in the promise with neither is **P0**.
- "Named falsifier" means a test that would go **red** on the broken implementation. A test that only asserts the deletion API was called is not a falsifier.
- The two-device crash-mid-purge path must appear as a falsifier row, not a prose claim.
- Do not add stores v6 does not cover. If you believe one is missing from the promise, that is a separate P1 finding, not a table row.

## Output

Each pass returns: the findings list, then (Pass B only) the contract table. No prose beyond that.

After both passes: zero P0/P1 → apply v6 to spec v5, regenerate registries, whole-spec review, refreeze, register version + hash in `PEEZY_STATE.md` §4, then S1 → S2 → S3 → S4 → S5 → S7 under emulator only. Each falsifier is shown red before its green counts.
