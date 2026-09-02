# V9 DIFF REVIEW — PHASE2_REPLACEMENT_MANIFEST_v9.md (diff-scoped, read-only)

Two rounds on one persistent Codex thread (`01a0636e-610d-7fa3-b25e-1db1b9d66c33`), reviewer GPT-5.6-sol via codex-cli 0.147.0, sandbox read-only both rounds. Round 1 reviewed sha256 `88f4769c73906320b601753e65cf0a832ab05939b23f1c85ab2e578fb8584715` → ITERATE; the arbiter revised; round 2 reviewed sha256 `a064bc6803f2ac416e1e1d35cb7462a24d0f94d6d95697dd056ee896b1344fc9` → APPROVE. Both reviewer texts follow verbatim; Claude's material is confined to the appendices.

---

# Round 1 (reviewer text, verbatim)

# V9 DIFF REVIEW — PHASE2_REPLACEMENT_MANIFEST_v9.md (diff-scoped, read-only)

Artifact: `PHASE2_REPLACEMENT_MANIFEST_v9.md` · SHA-256 `88f4769c73906320b601753e65cf0a832ab05939b23f1c85ab2e578fb8584715` (verified before review) · 559,168 bytes · 2,136 lines · untracked working-tree file.

Preimage: `PHASE2_REPLACEMENT_MANIFEST_v8.md` · SHA-256 `12ea8ee1b1fcd43dc88a993ebc4b6706a4b3d8f2ed93ebd09a59d2399262a251` (verified in the worktree and from commit `31fe35225987dbefe52bc7bf8934672cd0bad2f7`) · 537,714 bytes · 2,117 lines. The v8→v9 `git diff --no-index --unified=0` has 37 hunks; 69 v9 lines contain `[v9: …]` syntax.

Instruction used: `V9_INSTRUCTION.md` · SHA-256 `ca01f7f11f7cd9a06f54285372ee23dd45f752d097c695f2f4b2361cd506de1f`. Reviews used: `V8_DIFF_REVIEW.md` · SHA-256 `d1f08f426ad6359a9bbb415a60b057eac2a4798868105c75f964f079b7ef914a`; `V7_DIFF_REVIEW.md` · SHA-256 `03e5c2ed8bb37b1f0b4d979f3cb62399abbd0bcb987e2b852a1fe24c991bf3f2`.

Frozen spec: `docs/plans/PHASE2_EXECUTABLE_SPEC_v5.md` · SHA-256 `e02ef93867b744ec0ace9c0860ac309cb7e5fc14ee8c4762a265bd544ca2d2ab` (verified). Master: `docs/plans/files/INSTITUTION_FLOWS_MASTER_v3.md` · SHA-256 `80e6dbd361c2d85706f538bea96558a61904346536dcb8e069435488bf6bbb8a` (verified in the worktree and at commit `7546a0f0b7731ee8def18c76a220fea375238f8e`). v7 SHA-256 `d7c83fccc577264702e3b26905ab9e82d5fa36a33c9b1a87f6b59d32e5a0351` was verified.

Scope: every named file was readable. No file or worktree was modified or created. No build, `xcodebuild` command, Swift/Node test, npm script, Firebase, or gcloud command was run. Implementation inspection, hashing, JSON normalization, grep, diff, and git inspection were read-only.

Result summary: **3 CLOSED · 1 NOT CLOSED · 12 REGRESSED** across the 16 requested IDs. **5 new P1 finding IDs (11 outside-§8.9 P1 hits) · 1 new P2.** Under §13 item 7 (“Any P0/P1 reopens this manifest”), v9 is not ready.

---

## 1. Per-finding verification (16 IDs)

| ID | Result | v9 §:line | Verification |
|---|---|---|---|
| V8-01 | REGRESSED | §8.9.1:1027, 1031, 1036, 1042; §8.9.4:1074; §8.9.5:1082; §14.1:2100; §14.3:2124 | The three-way persisted discriminator and exact nonstaged byte contract are present, but the changed remote-unverified text orders presentation before the linked handoff while §8.9.4 requires publication only after that handoff clears; §14 also re-enumerates the phases outside the sole authority. |
| V8-02 | REGRESSED | §6.6:770; §8.9.3:1058; §8.9.4:1074; §14.1:2101 | The §6.6 order and “after the gate clears” clause were replaced by pointers and §8.9 has the intended order, but §14.1 restates that gate/presentation order outside §8.9. |
| V8-03 | CLOSED | §11.3:1692; §11.3:1704 | Every absence-retention check now has exactly one `destinationOrdinals` member, the exact-partition rule covers both branch kinds, and the fixture rejects absent, empty, or multi-member arrays. |
| V8-04 | REGRESSED | §8:1001; §8.9.3:1058; §14.1:2103 | The original opener predicate and enumeration were pointered, but §14.1 restates the clear/nonclear opener rule outside §8.9. |
| V8-05 | REGRESSED | §8:1005; §8.9.3:1058–1060; §11.5:1803; §12.2:1866; §14.1:2104 | The named §8 and §12.2 predicates were moved, but §11.5 retains staged-detach client behavior and §14.1 restates required-set and consumer gate behavior. |
| V8-06 | REGRESSED | §8:973; §8.9.3:1058–1060; §11:1529; §11.1:1608; §14.1:2105 | The original Firestore and telemetry gate clauses were pointered, but §14.1 restates Firestore admission and failure-to-nonclear behavior outside §8.9. |
| V8-07 | REGRESSED | §8.9.1:1036; §11:1437, 1541; §11.5:1792, 1794, 1796; §14.1:2106 | The no-finalize/unlink/clear tail moved into §8.9.1, but §11:1541 still says the failure “retains durable state,” and §14.1 restates the full rule. |
| V7-02 | REGRESSED | §8.9.1:1021–1040; §8.9.4:1074; §8.9.5:1082; §14.1:2107 | The prepared-root and nonstaged contracts are now byte-complete, but the restored remote path has conflicting presentation/handoff order and §14.1 re-enumerates the route outside §8.9. |
| V7-03 | REGRESSED | §6.6:770; §8.9.1:1036, 1044; §8.9.4:1070–1076; §8.9.5:1082; §14.1:2108 | `capability_invalid` distinguishes the local-cleared predecessor and §6.6 no longer reverses gate/presentation order, but §14.1 restates both rules outside §8.9. |
| V7-11 | REGRESSED | §8.9:1011; §11:1541; §11.5:1803; §14.1:2100–2109; §14.3:2124 | The original enumerations were swept, but substantive phase, gate, finalize, and presentation rules remain or were reintroduced outside the declared sole authority. |
| V7-12 | CLOSED | §11.3:1692, 1704 | The absence-retention shape, exact partition, retention/ordinal rules, and named server fixtures are mutually consistent. |
| V9 Item 1 | REGRESSED | §8.9.1:1036, 1042; §8.9.4:1074; §8.9.5:1082; §8.9.6:1086 | The requested discriminator, schema, terminal mappings, and crash fixture exist, but the remote-unverified terminal order is contradictory. |
| V9 Item 2 | REGRESSED | §6.6:770; §8.9.3:1058; §8.9.4:1074; §14.1:2101 | The §6.6 edit is correct, but the supposedly sole-authority timing rule is restated in §14.1. |
| V9 Item 3 | CLOSED | §11.3:1692, 1704 | The partition sentence, exact branch shape, and falsifiability fixture were updated exactly as instructed. |
| V9 Item 4 | REGRESSED | §8:1001, 1005; §11:1529, 1541; §11.5:1803; §14.1:2100–2108; §14.3:2124 | The four named sites were edited, but the whole-file sweep is incomplete and the report recreates comparable lifecycle authority. |
| V9 Item 5 | NOT CLOSED | §14.1:2100–2111; §14.3:2124; §14.4:2132 | V7-02, V7-03, V7-11, and Item 1 are not all closed in the final text, yet §14.4 records no Rule 8 stop. |

V8-08’s withdrawn §12.2 state enumeration was nonetheless removed: §12.2:1866 now retains path authorization and pointers without enumerating gate states. V8-09’s exact former §14.4 constraint paragraph was removed and ledger row 64 passes, but comparable phase/gate restatements were recreated in §14.1 and §14.3, so the Rule 4 sweep did not resolve that defect class globally.

None of the v8-CLOSED items—V7-01, V7-04 through V7-10, V7-13, or V7-14—regressed in their substantive byte contracts.

---

## 2. Supersession check (64 ledger rows) and outside-§8.9 sweep

### 2.1 Ledger grep and relocation results

For unescaped keys, the literal count had to be exactly one. For rows 14 and 63, the GFM `\|` escapes were removed before searching the raw key; both raw keys had count zero as required.

**Mechanical grep result: 63 PASS · 1 FAIL.**  
Failing key, verbatim: `relocated` — count 2 at §8.9.7:1096 and §8.9.7:1107.

| # | Grep rule | Pointer/rewrite and target |
|---:|---|---|
| 1 | PASS | PASS |
| 2 | PASS | PASS |
| 3 | PASS | PASS |
| 4 | PASS | PASS |
| 5 | PASS | PASS |
| 6 | PASS | PASS |
| 7 | PASS | PASS |
| 8 | **FAIL** | PASS |
| 9 | PASS | PASS |
| 10 | PASS | PASS |
| 11 | PASS | PASS |
| 12 | PASS | PASS |
| 13 | PASS | PASS |
| 14 | PASS | PASS |
| 15 | PASS | PASS |
| 16 | PASS | PASS |
| 17 | PASS | PASS |
| 18 | PASS | PASS |
| 19 | PASS | PASS |
| 20 | PASS | PASS |
| 21 | PASS | PASS |
| 22 | PASS | PASS |
| 23 | PASS | PASS |
| 24 | PASS | PASS |
| 25 | PASS | PASS |
| 26 | PASS | PASS |
| 27 | PASS | PASS |
| 28 | PASS | PASS |
| 29 | PASS | PASS |
| 30 | PASS | PASS |
| 31 | PASS | PASS |
| 32 | PASS | PASS |
| 33 | PASS | PASS |
| 34 | PASS | PASS |
| 35 | PASS | PASS |
| 36 | PASS | PASS |
| 37 | PASS | PASS |
| 38 | PASS | PASS |
| 39 | PASS | PASS |
| 40 | PASS | PASS |
| 41 | PASS | PASS |
| 42 | PASS | PASS |
| 43 | PASS | PASS |
| 44 | PASS | PASS |
| 45 | PASS | PASS |
| 46 | PASS | PASS |
| 47 | PASS | PASS |
| 48 | PASS | PASS |
| 49 | PASS | PASS |
| 50 | PASS | In-place rewrite PASS |
| 51 | PASS | In-place rewrite PASS |
| 52 | PASS | In-place rewrite PASS |
| 53 | PASS | In-place rewrite PASS |
| 54 | PASS | PASS |
| 55 | PASS | PASS |
| 56 | PASS | **Pointer-only FAIL; target PASS** |
| 57 | PASS | PASS |
| 58 | PASS | In-place non-lifecycle rewrite PASS |
| 59 | PASS | PASS |
| 60 | PASS | PASS |
| 61 | PASS | PASS |
| 62 | PASS | **Pointer-only FAIL; target FAIL** |
| 63 | PASS | PASS |
| 64 | PASS | Regenerated-location PASS |

Row 56 fails the semantic pointer check because §11:1541 still states, “Synchronize/removal/reread failure retains durable state.” The exact key evades the ledger grep only because v8’s trailing “and performs no finalize, unlink, or clear” was removed. Section §8.9.1:1036 carries the full replacement rule, so the relocation is duplicative rather than lossy.

Row 62 fails both checks. Section §11.5:1803 retains “Device B resumes every staged detach owner/barrier (§11)” instead of leaving only a pointer. Its declared replacement target, §8.9.3, contains guarding scope and Option-B handoff but does not state the deleted Device-B staged-detach resume rule. Removing the surviving clause would therefore make the relocation lossy.

### 2.2 Outside-§8.9 lifecycle-authority sweep

The following sentences remain comparable to the §12.2, §14.4, and §11.5 material Rule 4 required removed. Each is a P1 under the requested sweep standard.

| Finding | v9 §:line | Residual rule |
|---|---|---|
| V9-01 · P1 | §11:1541 | “Synchronize/removal/reread failure retains durable state.” |
| V9-02 · P1 | §11.5:1803 | “Device B resumes every staged detach owner/barrier (§11).” |
| V9-03 · P1 | §14.1:2100 | Enumerates all three nonstaged `detachReason` values and maps them to `local_cleared`, remote-unconfirmed, and `completed`. |
| V9-03 · P1 | §14.1:2101 | “The gate clears only after the terminal presentation action is consumed.” |
| V9-03 · P1 | §14.1:2103 | Restates that the support opener runs only under `clear`. |
| V9-03 · P1 | §14.1:2104 | Restates required-set composition, the empty-required-set rule, and immediate-admission/late-result behavior for four consumers. |
| V9-03 · P1 | §14.1:2105 | Restates Firestore admission-before-ack and failure-to-nonclear behavior. |
| V9-03 · P1 | §14.1:2106 | Restates phase retention and no-finalize/unlink/gate-clear behavior after owner/barrier failure. |
| V9-03 · P1 | §14.1:2107 | Re-enumerates `prepared→data_confirmed→purging→local_detaching`. |
| V9-03 · P1 | §14.1:2108 | Restates the `capability_invalid→local_cleared` predecessor and presentation-before-gate-clear requirement. |
| V9-03 · P1 | §14.3:2124 | Re-enumerates the three-way nonstaged terminal discriminator and terminal results. |

These sentences directly contradict §8.9:1011’s assertion that no such phase or gate-state enumeration exists outside §8.9. Section §14.1:2109 then asserts that none remains, and §14.1:2111 calls §8.9 the “sole remaining authority,” despite the adjacent report rows.

No comparable closed-state enumeration survives at §12.2:1866, and the former §14.4 enumeration is gone. Comparable material nevertheless survives at §11.5:1803 and was newly introduced at §14.1/§14.3.

---

## 3. §8.9 internal consistency

### 3.1 Complete transition walk

| Transition / producing wire or event | Exact resulting durable bytes | Terminal presentation/status | Named fixture |
|---|---|---|---|
| `prepared → data_confirmed`; exact data-final/auth-guarding/account-deleted wire (§8.9.2:1048–1050), reducer §8.9.1:1040 | §8.9.1:1034 | Nonterminal (§8.9.1:1034) | §8.9.6:1086, 1088 |
| `data_confirmed → purging`; same validated wire/local reducer (§8.9.1:1040; §8.9.2:1048–1050) | §8.9.1:1034 | Nonterminal (§8.9.1:1034) | §8.9.6:1086, 1088 |
| `purging → local_detaching`; staged root or ACCOUNT_DELETED authority (§8.9.1:1040; §8.9.2:1048–1050) | §8.9.1:1036 | Nonterminal (§8.9.1:1036) | §8.9.6:1086, 1088 |
| `prepared/confirmed_begin → local_detaching(remote_unverified)`; `notProven` observation (§8.9.5:1082) | §8.9.1:1036 | Nonterminal source of remote-unconfirmed terminal (§8.9.1:1036, 1042) | §8.9.6:1086 |
| `prepared/capability-invalid → local_detaching(capability_invalid)`; `definitivelyDeleted` observation (§8.9.5:1082) | §8.9.1:1036 | Nonterminal (§8.9.1:1036) | §8.9.6:1086 |
| `local_detaching(staged DATA_DELETED) → auth_finalize_dispatched`; data-final wire (§8.9.2:1048) | §8.9.1:1038 | Nonterminal (§8.9.1:1038) | §8.9.6:1086, 1088 |
| `local_detaching(staged AUTH_GUARDING) → guarding`; auth-guarding wire (§8.9.2:1048) | §8.9.1:1038 | Interim guarding presentation (§8.9.4:1070) | §8.9.6:1086, 1088 |
| `local_detaching(auth_deleted) → completed`; ACCOUNT_DELETED wire/root (§8.9.2:1048, 1050) | §8.9.1:1038 | Completed presentation (§8.9.4:1070–1076) | §8.9.6:1086, 1088 |
| `local_detaching(remote_unverified) → remote-unconfirmed terminal`; `notProven` entry (§8.9.5:1082) | Source discriminator/ack shape §8.9.1:1036; terminal file §8.9.4:1072 | §8.9.4:1070–1076, with contradictory ordering at §8.9.1:1036, 1042 versus §8.9.4:1074 | §8.9.6:1086 |
| `local_detaching(capability_invalid) → local_cleared`; `definitivelyDeleted` entry (§8.9.5:1082) | §8.9.1:1038 | Local-cleared presentation (§8.9.4:1070–1076) | §8.9.6:1086 |
| `auth_finalize_dispatched → guarding`; finalize returns guarding wire (§8.9.2:1050) | §8.9.1:1038 | Interim guarding presentation (§8.9.4:1070) | §8.9.6:1086, 1088 |
| `auth_finalize_dispatched → completed`; ACCOUNT_DELETED wire (§8.9.2:1050) | §8.9.1:1038 | Completed presentation (§8.9.4:1070–1076) | §8.9.6:1086, 1088 |
| `guarding → completed`; ACCOUNT_DELETED wire/root (§8.9.2:1048, 1050) | §8.9.1:1038 | Completed presentation (§8.9.4:1070–1076) | §8.9.6:1086, 1088 |

No durable intent byte state still has two required terminal successors after crash/relaunch. The three nonstaged variants are now discriminated by persisted `detachReason`, and ordinary server-dependent states re-observe a named server wire rather than selecting between prior events from missing bytes.

There is, however, an independent ordering contradiction. Sections §8.9.1:1036 and 1042 describe the remote-unconfirmed presentation as preceding the linked all-scope handoff. Section §8.9.4:1074 says remote-unconfirmed “is published only after its existing linked handoff has cleared.” Both publication orders cannot be implemented.

### 3.2 Restored §8.9.5 entry rules

The restored `confirmAccountDeleted` call condition at §8.9.5:1082 agrees with the seam at §8:979: the call requires the exact cached expected user, and `definitivelyDeleted` remains limited to the matching cached user/epoch plus exact forced-refresh user-not-found result.

The restored `notProven` confirmed-begin entry is also consistent with §8.9.1:1034, 1036 and §8.9.2:1048–1052: it starts from a `prepared/confirmed_begin` intent, persists the exact nonstaged `remote_unverified` reason before purge, and makes no claim that `notProven` is deletion proof or a server completion wire.

The restored rules do not create the presentation/handoff contradiction; that contradiction is between the terminal ordering sentences at §8.9.1:1036/1042 and §8.9.4:1074.

---

## 4. V8-03 partition consistency

Section §11.3:1692 is internally consistent:

- Every branch now has a nonempty `destinationOrdinals` array.
- Arrays are pairwise disjoint and their union is the complete accepted ordinal set.
- The absence-retention branch has exactly one ordinal, matching its single accepted destination.
- Ordinals remain contiguous from zero.
- Each check’s retention remains the maximum of its covered destinations; for a one-destination absence check this equals that destination’s retention.
- `authResidualRetentionSeconds` remains the maximum across the accepted destination array.
- `Auth destination partition is completely falsifiable` rejects missing, overlapping, and uncheckable kinds and now also rejects absent, empty, or multi-member absence-retention arrays.

The server fixture list at §11.3:1704 covers `1/12/13 residual checks` and “each destination partition defect.” No contradiction or unreachable accepted destination remains.

---

## 5. §12.2 recount and §13 gate items 1–6

### 5.1 Authorized client paths

| Quantity | Reproduced count |
|---|---:|
| Frozen §8.2 entries | 58 |
| Frozen §8.2 unique paths | 56 |
| Frozen duplicates | `PeezyMainContainer.swift`; `FlowExitControl.swift` |
| v9 §12.2 addition entries | 33 |
| Unique additions | 33 |
| Additions overlapping frozen paths | 0 |
| Union entries before deduplication | 91 |
| Exact unique authorized client paths | **89** |

The literal recount agrees with §12.2:1872 and §14.2:2117. The v8→v9 diff adds or removes no authorized path.

### 5.2 §13 items 1–6

| Item | Result | Independent evidence | Comparison with §14.3 |
|---|---|---|---|
| 1. ID set/path closure | PASS | §13:2038–2073 has 36 rows, 36 unique IDs, exact expected-set equality, 17 distinct single-section authority cells, and 21 distinct referenced paths; D32 points only to §12.5/§9.4. | Matches §14.3:2123. |
| 2. Schema/crash fixtures | PASS | The nonstaged `local_detaching` schema is exact (§8.9.1:1036), all three nonstaged paths have crash/relaunch fixtures (§8.9.6:1086), and absence-retention rejection is named (§11.3:1692). | Matches §14.3:2124 on fixture coverage; that report row separately violates Rule 4 by restating lifecycle states. |
| 3. Codec/decoder pins | PASS | Lock resolves Firestore 7.11.6, Storage 7.18.0, and `google-auth-library` 9.15.1. Installed `firestore_client_config.json` hashes `2ed7a9046d766121b7f308b22384b1a6caaf7c6eaed5d9ea553556af3c987e41`; Commit/BatchWrite are both 60,000 ms. Canonical hashing reproduces `rlm1_0a4d53a438873090f69e4255426310b0feb4cfd6`, `rlmreq1_0a4d53a438873090f69e4255426310b0feb4cfd63eabd6ce68c851ce827ad8e1`, and `reset1_862fe3fc8a08ce3eced6f25dfd2a8765b408e8386fa28f081f393d36f04e94a1`. | Matches §14.3:2125. |
| 4. §7.4 registry | PASS | Frozen normalization: 4,432 bytes, SHA-256 `a7a432ec…7bbb`, 3 indexes/28 overrides. After eight appends: 5,872 bytes, SHA-256 `a6de8daf…8e8`, 4 indexes/35 overrides. | Matches §14.3:2126. |
| 5. Mechanical counts | PASS | 89 client paths; 22 Swift files; amended `-only-testing` and `E` are exactly equal 23-member sets; 24 main Node files; 25 unique Node/rules files. | Matches §14.3:2127. |
| 6. Grep bans | PASS | Master timing clauses are present at master lines 51 and 436; retired migration mechanisms occur only in negative/decoy/gate/report text; the policy-absent positive path occurs once at §10:1253; D4 hits are withdrawal/no-eviction assertions and permitted route eviction. | The conclusion matches §14.3:2128. Its rationale that “§§2–7 are byte-identical to v8” is factually inaccurate because §6.6:770 changed, but targeted searches still pass. |

All six underlying gates pass. Overall readiness nevertheless fails §13 item 7 because this review has P1 findings.

---

## 6. Scope and marker discipline

### 6.1 Git and implementation scope

Branch is `main`, ahead of `origin/main` by 14 commits.

No tracked implementation file is modified. The only tracked modification is `tasks/todo.md`. The four d321547 files are byte-identical to commit `d321547`; the read-only four-path git diff is empty.

| File | Current SHA-256 |
|---|---|
| `functions/processInventory.js` | `169461aa049e443beee2c0cc943bfe5dcdce35a4b4751d80f636cd58a9123f19` |
| `Peezy 4.0/Inventory/Models/InventorySessionManager.swift` | `97ad2e231a4171e26432d5b98195322e1fadc9a789b9763209e889f40d244c71` |
| `Peezy 4.0/Inventory/Views/InventoryCameraView.swift` | `5f4f76957ec41e32b8b779643349dc049b2914e7eafe2f51f2a88930b42ff52d` |
| `Peezy 4.0/Inventory/Services/NarrationService.swift` | `5fcffe128c3acbe01d43ce29e67e9aa3fdcbc33becc91d6432c04876f4236276` |

The requested assertion that the only working-tree entries are `tasks/todo.md` and untracked v9 is false. Git also reports these preexisting untracked paths:

- `AMENDMENT_4_REVIEW_PROMPT.md`
- `File.txt`
- `PHASE2_AMENDMENT_1.md` through `PHASE2_AMENDMENT_4.md`
- `PHASE2_BUILD.md`
- `PHASE2_PLAN.md`
- `PHASE2_REPLACEMENT_MANIFEST.md`
- `Peezy 4.0/PHASE2_PLAN.md`
- `V9_INSTRUCTION.md`
- `docs/plans/PHASE2_PLAN_v5_PROPOSED.md`

None is an implementation `.swift` or `.js` modification, but the expected complete worktree inventory does not match.

### 6.2 Diff-origin scope

All 37 hunk origins fall within §14.5:2136’s declared v8 line set. No v8→v9 change exists outside that set.

### 6.3 Marker IDs and hunk coverage

The marker-ID check fails on two syntactic occurrences:

- §8.9.7:1149 uses `[v9: V8-04…V8-07]`, a range token rather than the literal permitted IDs.
- §14.5:2136 contains the placeholder `[v9: …]`.

Every other marker names only V8-01 through V8-07, V7-02, V7-03, V7-11, or V7-12.

The stricter requested “every changed hunk carries a marker” check also fails: 31 of 37 hunks contain a `[v9: …]` attribution. The six unmarked hunks originate at v8 lines:

- 1 — document title
- 1027 — changed remote-unverified phase-order entry
- 1031 — changed local-cleared phase-order entry
- 2073 — §14 heading
- 2077 — §14.1 heading
- 2079 — §14.1 table header

The two phase-order hunks are normative state-machine fragments, not merely headings.

---

## 7. Rule 8 assessment

Restoring the two deleted-v7 rules into §8.9 is within V9 Rules 2 and 8:

- The exact cached-user call condition at §8.9.5:1082 already exists as the seam contract at §8:979 and restores the producer for V8-01’s capability-invalid path.
- The confirmed-begin `notProven` entry at §8.9.5:1082 restores the preexisting producer for the retained remote-unverified terminal required by Item 1.
- Neither adds a new phase, wire, presentation shape, or terminal result.

No restored sentence is itself a new design decision beyond V9 Item 1.

The separate “no Rule 8 stop occurred” conclusion at §14.4:2132 is nevertheless invalid. V9 Item 5 required a stop if V7-03, V7-11, V7-12, Item 1, or Item 6 remained open. V7-11 and Item 1 remain open in the final text, principally because §14.1/§14.3 recreate Rule 4 authority and the remote terminal order is contradictory. The final text therefore reached Item 5’s explicit stop condition but recorded no stop.

---

## 8. New findings

### P1

- **V9-01 · §8.9:1011 vs §11:1541** · Rule 4 requires phase and finalize behavior outside §8.9 to be deleted and pointered, but §11 still states that preference synchronization/removal/reread failure “retains durable state.” The ledger’s shorter grep key passes only because the no-finalize/unlink/clear tail was removed.

- **V9-02 · §8.9:1011 vs §11.5:1803 and §8.9.7:1161** · The §11.5 row still states that Device B resumes every staged detach owner/barrier. Ledger row 62 points only to §8.9.3, which defines guarding scope and Option-B handoff but does not carry that staged-detach resume rule. This is both surviving outside authority and a lossy declared relocation.

- **V9-03 · §8.9:1011 vs §14.1:2100–2108, §14.3:2124** · The v9 execution report recreates exact phase mappings, phase order, gate-clear timing, opener scope, required-set composition, consumer admission, Firestore gate behavior, failure retention, and local-cleared predecessor rules outside §8.9. Section §14.1:2109 then asserts that none remains. This violates Rules 4 and 5; all 9 individual report hits are listed in §2.2.

- **V9-04 · §8.9.1:1036, 1042 vs §8.9.4:1074** · The remote-unverified transition requires “remote-unconfirmed presentation → linked all-scope handoff,” while §8.9.4 requires the same presentation to be published only after the linked handoff clears. The terminal ordering is contradictory.

- **V9-05 · §14.1:2100–2111, §14.3:2124 vs §14.4:2132** · Item 5 required a Rule 8 stop if the carried findings were not all closed. The final report itself leaves V7-11 and Item 1 open but states that no stop occurred.

### P2

- **V9-06 · §8.9.7:1096, 1107** · Ledger row 8’s unescaped key `relocated` occurs twice rather than exactly once, so the regenerated ledger fails its own Rule 5 grep contract. This is a mechanical ledger-key collision; it does not by itself establish surviving old lifecycle behavior.

---

## 9. Verified with no finding

- All named evidence files were readable and their supplied hashes were verified.
- The v8 preimage and master hashes match their committed blobs.
- The V8-03/V7-12 Auth-destination partition is closed and falsifiable.
- No durable intent byte state still selects between two required terminal successors after relaunch.
- The restored §8.9.5 entry conditions agree with the existing Auth seam.
- The literal authorized-client union is exactly 89 paths.
- §13 gate items 1–6 pass on their underlying evidence.
- All v8→v9 hunk origins fall inside §14.5’s declared line set.
- No tracked implementation file changed, and all four d321547 files match their commit bytes.
- V7-01, V7-04 through V7-10, V7-13, and V7-14 retain their v8-closed substantive behavior.
- `PEEZY_STATE.md` still registering v8 rather than v9 is expected and is not a finding.


VERDICT (round 1): ITERATE

---

# Round 2 (reviewer text, verbatim; same thread, after arbiter revisions)

# V9 DIFF REVIEW — PHASE2_REPLACEMENT_MANIFEST_v9.md (diff-scoped, read-only) — round 2

Artifact: `PHASE2_REPLACEMENT_MANIFEST_v9.md` · SHA-256 `a064bc6803f2ac416e1e1d35cb7462a24d0f94d6d95697dd056ee896b1344fc9` (verified before review) · 558,899 bytes · 2,136 lines · untracked working-tree file.

Preimage: `PHASE2_REPLACEMENT_MANIFEST_v8.md` · SHA-256 `12ea8ee1b1fcd43dc88a993ebc4b6706a4b3d8f2ed93ebd09a59d2399262a251` (verified in the worktree and at commit `31fe35225987dbefe52bc7bf8934672cd0bad2f7`) · 537,714 bytes · 2,117 lines.

The v8→v9 `git diff --no-index --unified=0` has 37 hunks. There are 71 lines containing `[v9: …]` markers.

Evidence used:

- `V9_INSTRUCTION.md` · SHA-256 `ca01f7f11f7cd9a06f54285372ee23dd45f752d097c695f2f4b2361cd506de1f`
- Round-1 report in `V9_DIFF_REVIEW-log.md` · SHA-256 `75c0b5f9c6bb09f2a91639363c33fb47948ba8e522707acb318ca4956a450417`
- `V8_DIFF_REVIEW.md` · SHA-256 `d1f08f426ad6359a9bbb415a60b057eac2a4798868105c75f964f079b7ef914a`
- `V7_DIFF_REVIEW.md` · SHA-256 `03e5c2ed8bb37b1f0b4d979f3cb62399abbd0bcb987e2b852a1fe24c991bf3f2`
- `PHASE2_REPLACEMENT_MANIFEST_v7.md` · SHA-256 `d7c83fccc577264702e3b26905ab9e82d5fa36a33c9b1a87f6b59d32e5a0351a`
- Frozen spec `PHASE2_EXECUTABLE_SPEC_v5.md` · SHA-256 `e02ef93867b744ec0ace9c0860ac309cb7e5fc14ee8c4762a265bd544ca2d2ab`
- Master `INSTITUTION_FLOWS_MASTER_v3.md` · SHA-256 `80e6dbd361c2d85706f538bea96558a61904346536dcb8e069435488bf6bbb8a`, verified both in the worktree and at commit `7546a0f0b7731ee8def18c76a220fea375238f8e`

Scope: every named evidence file was readable. No file or worktree was modified or created. No build, `xcodebuild`, Swift/Node test, npm script, Firebase command, or gcloud command was run. Inspection was limited to permitted hashing, grep/awk/jq, JSON normalization, diff, and read-only git operations.

Result summary: **16 CLOSED · 0 NOT CLOSED · 0 REGRESSED** across the requested 16 IDs. All six round-1 findings are **ADDRESSED**. **0 new P1 · 0 new P2.** Section 13 item 7 does not reopen this manifest.

---

## 1. Round-1 finding disposition

| Finding | Result | v9 §:line | Verification |
|---|---|---|---|
| V9-01 | ADDRESSED | §11:1541; §8.9.1:1036; §8.9.7:1155 | Section 11 now classifies the condition only as a preference-barrier failure and points to §8.9.1; the former outside statement that it “retains durable state” is absent. |
| V9-02 | ADDRESSED | §11.5:1803; §8.9.1:1036, 1042; §8.9.3:1058, 1064; §8.9.6:1086; §8.9.7:1161 | The Device-B staged-resume clause is gone; the table cell contains pointers, and row 62’s three targets collectively state resume, gate/handoff, and crash/relaunch coverage without loss. |
| V9-03 | ADDRESSED | §14.1:2100–2111; §14.3:2123–2128 | Section 14 now identifies edits and authority locations without reproducing phase values, phase mappings, transition order, gate-state values, opener predicates, admission rules, or failure consequences. |
| V9-04 | ADDRESSED | §8.9.1:1036, 1042; §8.9.4:1072, 1074 | All four sentences now define one order: derive the completion file, perform and clear the linked all-scope handoff, publish the remote-unconfirmed presentation, then allow its acknowledgement. |
| V9-05 | ADDRESSED | §14.4:2132 | It was derivative of V9-01 through V9-04; those findings are closed, all Item 5 prerequisites are closed, and no Rule 8 stop condition remains. |
| V9-06 | ADDRESSED | §8.9.7:1096, 1107 | “relocated verbatim” is explicitly plain text rather than a code-font grep key; all actual ledger keys satisfy their count rules. |

---

## 2. Updated 16-ID verification

| ID | Result | v9 §:line | Verification |
|---|---|---|---|
| V8-01 | CLOSED | §8.9.1:1027, 1031, 1036, 1042; §8.9.5:1082; §8.9.6:1086 | The exact three-token discriminator, forbidden-member closure, ack-prefix rule, terminal mapping, entry events, and crash-at-every-phase fixtures are present and mutually consistent. |
| V8-02 | CLOSED | §6.6:770; §8.9.3:1058; §8.9.4:1074 | The §6.6 ordering and “after the gate clears” text are gone; pointers lead to the sole presentation/gate authority. |
| V8-03 | CLOSED | §11.3:1692, 1704 | Every check kind participates in one exact ordinal partition, absence-retention has one ordinal, and the named test rejects every malformed array and partition defect. |
| V8-04 | CLOSED | §8:1001; §8.9.3:1058; §8.9.7:1147 | The outside opener predicate/enumeration is replaced by a pointer; the complete rule exists only in §8.9.3. |
| V8-05 | CLOSED | §8:1005; §8.9.3:1058–1060; §11.5:1803; §12.2:1866 | Required-set composition, empty-set behavior, consumer admission, guarding, and late-result behavior are consolidated in §8.9.3 without a surviving outside enumeration. |
| V8-06 | CLOSED | §8:973; §8.9.3:1058–1060; §11:1529; §11.1:1608 | The Firestore and telemetry gate consequences are pointered; §8.9.3 carries the complete admission and failure-retention rules. |
| V8-07 | CLOSED | §8.9.1:1036; §11:1437, 1541; §11.5:1792, 1794, 1796, 1803 | Client phase/finalize consequences, barrier placement, presentation behavior, and crash resume are removed from the outside locations and retained losslessly in §8.9. |
| V7-02 | CLOSED | §8.9.1:1021–1042; §8.9.5:1082 | Every staged and nonstaged route has an exact byte contract and deterministic successor from durable bytes or a named server wire. |
| V7-03 | CLOSED | §6.6:770; §8.9.1:1036, 1044; §8.9.4:1070–1076; §8.9.5:1082 | `capability_invalid` durably distinguishes the local-cleared predecessor, and no outside sentence reverses presentation/gate timing. |
| V7-11 | CLOSED | §8.9:1011; §8.9.3:1056–1060; §8.9.7:1100–1165 | The Rule 4 sweep leaves §8.9 as the sole substantive client lifecycle/gate/presentation authority. |
| V7-12 | CLOSED | §11.3:1692, 1704 | Absence-retention shape, ordinal partition, retention rules, and server fixtures are consistent and falsifiable. |
| V9 Item 1 | CLOSED | §8.9.1:1027–1042; §8.9.5:1082; §8.9.6:1086 | The decided persisted discriminator and all three nonstaged terminal routes are complete and crash-deterministic. |
| V9 Item 2 | CLOSED | §6.6:770; §8.9.3:1058; §8.9.4:1074 | Gate-clear timing is stated solely in §8.9 and the superseded §6.6 clause is absent. |
| V9 Item 3 | CLOSED | §11.3:1692, 1704 | The required one-member absence-retention ordinal array, union partition, and fixture extension are all present. |
| V9 Item 4 | CLOSED | §8:973, 1001, 1005; §11:1529, 1541; §11.5:1792–1803; §12.2:1866; §8.9.7:1146–1163 | The named sites and whole-file sweep leave pointers rather than competing lifecycle authority. |
| V9 Item 5 | CLOSED | §14.1:2107–2113; §14.4:2132 | V7-03, V7-11, V7-12, V9 Item 1, and the V8 Item 6 cluster all remain closed, so no separate Item 5 edit or Rule 8 stop was required. |

The withdrawn V8-08 material is nonetheless resolved: §12.2:1866 retains the path authorization but removes the gate-state enumeration and points to §8.9.3. V8-09 is likewise resolved: §14.4:2132 records the prior decision without restating the Option-A constraints, and ledger row 64 passes.

No v8-CLOSED item—V7-01, V7-04 through V7-10, V7-13, or V7-14—regressed.

---

## 3. Supersession check and outside-§8.9 sweep

### 3.1 Mechanical ledger result

The regenerated ledger contains 281 actual grep keys across 64 rows.

- Every unescaped key occurs on exactly one line.
- The escaped raw keys in rows 14 and 63 occur zero times after removing GFM `\|` escaping.
- Failing keys: **none**.
- Result: **64 PASS · 0 FAIL**.

| # | Keys | Grep | Pointer/rewrite target |
|---:|---:|---|---|
| 1 | 2 | PASS | PASS |
| 2 | 9 | PASS | PASS |
| 3 | 2 | PASS | PASS |
| 4 | 3 | PASS | PASS |
| 5 | 5 | PASS | PASS |
| 6 | 7 | PASS | PASS |
| 7 | 9 | PASS | PASS |
| 8 | 31 | PASS | PASS |
| 9 | 1 | PASS | PASS |
| 10 | 2 | PASS | PASS |
| 11 | 1 | PASS | PASS |
| 12 | 12 | PASS | PASS |
| 13 | 5 | PASS | PASS |
| 14 | 18 | PASS | PASS |
| 15 | 10 | PASS | PASS |
| 16 | 9 | PASS | PASS |
| 17 | 9 | PASS | PASS |
| 18 | 1 | PASS | PASS |
| 19 | 6 | PASS | PASS |
| 20 | 8 | PASS | PASS |
| 21 | 7 | PASS | PASS |
| 22 | 19 | PASS | PASS |
| 23 | 4 | PASS | PASS |
| 24 | 1 | PASS | PASS |
| 25 | 1 | PASS | PASS |
| 26 | 1 | PASS | PASS |
| 27 | 3 | PASS | PASS |
| 28 | 4 | PASS | PASS |
| 29 | 1 | PASS | PASS |
| 30 | 1 | PASS | PASS |
| 31 | 1 | PASS | PASS |
| 32 | 1 | PASS | PASS |
| 33 | 5 | PASS | PASS |
| 34 | 17 | PASS | PASS |
| 35 | 13 | PASS | PASS |
| 36 | 1 | PASS | PASS |
| 37 | 2 | PASS | PASS |
| 38 | 1 | PASS | PASS |
| 39 | 5 | PASS | PASS |
| 40 | 3 | PASS | PASS |
| 41 | 5 | PASS | PASS |
| 42 | 2 | PASS | PASS |
| 43 | 2 | PASS | PASS |
| 44 | 1 | PASS | PASS |
| 45 | 1 | PASS | PASS |
| 46 | 2 | PASS | PASS |
| 47 | 1 | PASS | PASS |
| 48 | 1 | PASS | PASS |
| 49 | 2 | PASS | PASS |
| 50 | 1 | PASS | In-place rewrite PASS |
| 51 | 2 | PASS | In-place rewrite PASS |
| 52 | 1 | PASS | In-place rewrite PASS |
| 53 | 2 | PASS | In-place rewrite PASS |
| 54 | 1 | PASS | PASS |
| 55 | 2 | PASS | PASS |
| 56 | 1 | PASS | PASS |
| 57 | 1 | PASS | PASS |
| 58 | 2 | PASS | In-place non-lifecycle rewrite PASS |
| 59 | 1 | PASS | PASS |
| 60 | 1 | PASS | PASS |
| 61 | 1 | PASS | PASS |
| 62 | 1 | PASS | PASS |
| 63 | 3 | PASS | PASS |
| 64 | 3 | PASS | Regenerated-report location PASS |

For all 58 Rule 4 pointer rows outside §8.9, the deleted rule is absent from its original location and only a pointer remains for that rule. Every target carries the deleted behavior; no relocation is lossy. In particular, row 62’s targets provide:

- launch and matching-journal resume at §8.9.1:1042;
- full staged/nonstaged detach work at §8.9.1:1036;
- guarding and Option-B handoff scope at §8.9.3:1058, 1064;
- crash/relaunch at every relevant phase at §8.9.6:1086.

### 3.2 Outside-§8.9 lifecycle-authority sweep

No sentence outside §8.9 remains that substantively specifies:

- a client deletion phase or phase transition;
- a deletion-gate scope rule;
- finalize behavior on the client;
- completed, guarding, local-cleared, or remote-unconfirmed presentation behavior;
- an enumeration of gate, phase, or projection states.

The former §11:1541 failure consequence is now a barrier classification plus pointer. The former §11.5:1803 Device-B behavior is now pointer-only. Section 12.2:1866 has no gate-state enumeration. Section 14 describes which text was deleted and cites its authority without reproducing its values or behavior. Nothing comparable to the removed §11.5, §12.2, or former §14.4 restatements survives.

---

## 4. §8.9 internal consistency and ordering walk

### 4.1 Transition matrix

| Transition / producing wire or event | Exact resulting durable bytes | Terminal presentation | Named fixture |
|---|---|---|---|
| `prepared → data_confirmed`; validated data-final, AUTH_GUARDING, or ACCOUNT_DELETED wire (§8.9.1:1040; §8.9.2:1048–1050) | §8.9.1:1034 | Nonterminal — §8.9.1:1034 | §8.9.6:1086, 1088 |
| `data_confirmed → purging`; local reducer after the validated authority (§8.9.1:1040) | §8.9.1:1034 | Nonterminal — §8.9.1:1034 | §8.9.6:1086, 1088 |
| `purging → local_detaching`; validated staged root or ACCOUNT_DELETED authority (§8.9.1:1040; §8.9.2:1048–1050) | §8.9.1:1036 | Nonterminal — §8.9.1:1036 | §8.9.6:1086, 1088 |
| `prepared/confirmed_begin → local_detaching(remote_unverified)`; `notProven` local observation (§8.9.5:1082) | §8.9.1:1036 | Source of remote-unconfirmed terminal — §8.9.4:1070 | §8.9.6:1086 |
| capability-invalid `prepared → local_detaching(capability_invalid)`; exact `definitivelyDeleted` observation (§8.9.5:1082) | §8.9.1:1036 | Nonterminal — §8.9.1:1036 | §8.9.6:1086 |
| `local_detaching(staged DATA_DELETED) → auth_finalize_dispatched`; DATA_DELETED wire (§8.9.2:1048) | §8.9.1:1038 | Nonterminal — §8.9.1:1038 | §8.9.6:1086, 1088 |
| `local_detaching(staged AUTH_GUARDING) → guarding`; AUTH_GUARDING wire (§8.9.2:1048) | §8.9.1:1038 | Guarding — §8.9.4:1070 | §8.9.6:1086, 1088 |
| `local_detaching(auth_deleted) → completed`; ACCOUNT_DELETED wire/root (§8.9.2:1048, 1050) | §8.9.1:1038 | Completed — §8.9.4:1070–1076 | §8.9.6:1086, 1088 |
| `local_detaching(remote_unverified) → remote-unconfirmed terminal`; persisted reason plus `notProven` entry (§8.9.1:1036; §8.9.5:1082) | Source intent §8.9.1:1036; exact terminal file §8.9.4:1072 | Remote-unconfirmed — §8.9.4:1070, 1074, 1076 | §8.9.6:1086 |
| `local_detaching(capability_invalid) → local_cleared`; exact local observation (§8.9.5:1082) | §8.9.1:1038 | Local-cleared — §8.9.4:1070–1076 | §8.9.6:1086 |
| `auth_finalize_dispatched → guarding`; finalize guarding wire (§8.9.2:1050) | §8.9.1:1038 | Guarding — §8.9.4:1070 | §8.9.6:1086, 1088 |
| `auth_finalize_dispatched → completed`; ACCOUNT_DELETED wire (§8.9.2:1050) | §8.9.1:1038 | Completed — §8.9.4:1070–1076 | §8.9.6:1086, 1088 |
| `guarding → completed`; ACCOUNT_DELETED wire/root (§8.9.2:1048, 1050) | §8.9.1:1038 | Completed — §8.9.4:1070–1076 | §8.9.6:1086, 1088 |

No cell is missing.

### 4.2 Remote-unverified ordering

One implementable order remains:

1. Finish the eight-owner detach work and both barriers while the intent remains `local_detaching(detachReason:"remote_unverified")` (§8.9.1:1036).
2. Derive the exact completion file before the handoff (§8.9.1:1042; §8.9.4:1072).
3. Perform and clear the linked all-scope handoff (§8.9.1:1042).
4. Publish the remote-unconfirmed presentation only after that handoff clears (§8.9.1:1042; §8.9.4:1074).
5. Acknowledgement consumes only the completion file (§8.9.4:1074).

The earlier presentation-before-handoff contradiction is gone.

No durable intent byte state has two required successors after crash or relaunch. Each nonstaged `local_detaching` intent carries exactly one persisted discriminator:

- `auth_deleted` → `completed`
- `remote_unverified` → remote-unconfirmed terminal
- `capability_invalid` → `local_cleared`

### 4.3 Restored entry conditions

The `confirmAccountDeleted` condition at §8.9.5:1082 agrees with the seam at §8:979: both require the exact cached expected Firebase user, matching epoch, and the exact forced-refresh user-not-found condition before `definitivelyDeleted` is legal.

The `notProven` confirmed-begin entry agrees with §8.9.1:1034, 1036 and §8.9.2:1048–1052. It starts from a durable `prepared/confirmed_begin` intent, persists `remote_unverified` before purge, and does not claim server completion or deletion proof.

No contradiction was found among the restored entry rules, durable schema, server-wire union, or seam definition.

---

## 5. V8-03 partition consistency

Section §11.3:1692 is mutually consistent:

- Every `authResidualChecks` member carries a nonempty `destinationOrdinals`.
- The arrays are pairwise disjoint.
- Their union is exactly the accepted Auth-destination ordinal set.
- Every accepted ordinal appears in exactly one count or absence-retention check.
- The absence-retention branch has exactly one ordinal and therefore exactly one covered destination.
- Its retention is the maximum of its one covered destination and remains bounded by the authority maximum.
- Ordinals remain contiguous from zero.
- The named `Auth destination partition is completely falsifiable` test rejects missing, overlapping, uncheckable, absent-array, empty-array, and multi-member absence-retention cases.

Section §11.3:1704 covers `1/12/13 residual checks` and “each destination partition defect.” No unreachable or unfalsifiable accepted branch remains.

---

## 6. §12.2 recount and §13 gate items 1–6

### 6.1 Authorized client paths

| Quantity | Reproduced count |
|---|---:|
| Frozen §8.2 entries | 58 |
| Frozen §8.2 unique paths | 56 |
| Frozen duplicate paths | `PeezyMainContainer.swift`, `FlowExitControl.swift` |
| Literal §12.2 additions | 33 |
| Unique additions | 33 |
| Addition/base overlap | 0 |
| Unique union | **89** |

The result agrees with §12.2:1872 and §14.2:2117. The v8→v9 diff changes no authorized path.

### 6.2 §13 gate items

| Item | Result | Independent evidence | §14.3 comparison |
|---|---|---|---|
| 1. ID set and path closure | PASS | The §13 register has 36 rows and 36 unique IDs; exact expected-set errors are zero; authority cells resolve to 17 distinct sections; 21 distinct paths and the two identifier-only code spans are accounted for. | Matches §14.3:2123. |
| 2. Schema/crash coverage | PASS | The changed nonstaged schema is exact at §8.9.1:1036, every nonstaged route has crash/relaunch coverage at §8.9.6:1086, and the changed absence-retention rejection is exact at §11.3:1692. | Matches §14.3:2124. |
| 3. Pins and canonical fixtures | PASS | Package lock resolves Firestore 7.11.6, Storage 7.18.0, and `google-auth-library` 9.15.1. Installed client config hashes `2ed7a9046d766121b7f308b22384b1a6caaf7c6eaed5d9ea553556af3c987e41`; Commit and BatchWrite are both 60,000 ms. Pure canonical hashing reproduced all three `rlm1_`, `rlmreq1_`, and `reset1_` literals. | Matches §14.3:2125. |
| 4. Index registry | PASS | Frozen normalization is 4,432 bytes, `a7a432ec…7bbb`, 3 indexes/28 overrides. Applying the eight exact appends gives 5,872 bytes, `a6de8daf…d88e8`, 4 indexes/35 overrides. | Matches §14.3:2126. |
| 5. Mechanical counts | PASS | 89 client paths; 22 Swift test files; 23 named suites with the same insertion in `-only-testing` and set `E`; 24 main Node files; 25 unique Node/rules files. | Matches §14.3:2127. |
| 6. Grep bans | PASS | Master lines 51 and 436 carry both timing clauses. The only §§2–7 v9 change is the §6.6:770 pointer edit. Retired migration-authority hits remain negative/decoy/gate text; policy-absent `evidence_ids` has one positive registry path at §10:1253; D4 eviction hits remain withdrawal/no-eviction assertions or the permitted route-inbox eviction. | Matches §14.3:2128. |

All six gates pass independently.

---

## 7. Scope and marker discipline

### 7.1 Git and implementation scope

Branch: `main`, 14 commits ahead of `origin/main`.

The only tracked working-tree modification is `tasks/todo.md`. No tracked implementation file is modified. The artifact under review is untracked.

The four Build 25 baseline files produce an empty read-only diff against `d321547`:

| File | Current SHA-256 |
|---|---|
| `functions/processInventory.js` | `169461aa049e443beee2c0cc943bfe5dcdce35a4b4751d80f636cd58a9123f19` |
| `Peezy 4.0/Inventory/Models/InventorySessionManager.swift` | `97ad2e231a4171e26432d5b98195322e1fadc9a789b9763209e889f40d244c71` |
| `Peezy 4.0/Inventory/Views/InventoryCameraView.swift` | `5f4f76957ec41e32b8b779643349dc049b2914e7eafe2f51f2a88930b42ff52d` |
| `Peezy 4.0/Inventory/Services/NarrationService.swift` | `5fcffe128c3acbe01d43ce29e67e9aa3fdcbc33becc91d6432c04876f4236276` |

The additional untracked paths identified in round 1 are noted as preexisting under the stated arbiter position and are not classified as v9 changes or defects.

### 7.2 Diff-origin scope

All 37 v8→v9 hunk origins fall within the exact v8 line set declared at §14.5:2136. No change occurs outside that set.

### 7.3 Markers

All 71 `[v9: …]` marker lines use only:

- V8-01 through V8-07
- V7-02
- V7-03
- V7-11
- V7-12

The former range token in ledger row 50 is expanded. The §14.5 placeholder is gone. The phase-order edits at §8.9.1:1027 and 1031 now carry markers.

Of the 37 diff hunks, 33 contain marker-bearing changed sentences. The four unmarked additions are the document title, §14 heading, §14.1 heading, and §14.1 table header. Under the stated arbiter position, these are headings rather than changed sentences and are not Rule 3 violations.

---

## 8. Rule 8 assessment

Section §14.4:2132’s “no Rule 8 stop” claim is accurate for the final text.

Restoring the two deleted-v7 rules remains within V9 Rules 2 and 8:

- The nonstaged member closure at §8.9.1:1036 is necessary to implement V9 Item 1’s decided persisted discriminator.
- The `confirmAccountDeleted` and confirmed-begin `notProven` entries at §8.9.5:1082 restore the existing producers for the decided `capability_invalid` and retained `remote_unverified` routes.
- They add no phase, wire, presentation map, or terminal result.

The remote-order correction is also not a new design decision: §8.9.1:1036, 1042 now defer to and agree with the unchanged exact derivation/publication contract at §8.9.4:1072, 1074. It resolves a contradictory description without introducing a new terminal or byte shape.

No v9 sentence was found that makes a design decision beyond the written V9 instruction and its referenced existing authority.

---

## 9. New findings

### P1

None.

### P2

None.

---

## 10. Verified with no finding

- The revised artifact SHA-256 matches the supplied value.
- All named evidence files were readable.
- The preimage and master hashes match their committed blobs.
- All six round-1 findings are addressed.
- All 16 carried IDs are closed.
- All 64 ledger rows and all 281 actual keys pass.
- No pointer target is lossy.
- The outside-§8.9 lifecycle-authority sweep has zero P1 hits.
- Remote-unverified has one implementable derivation/handoff/publication order.
- No durable intent byte state has two required post-relaunch successors.
- The restored §8.9.5 entries agree with the Auth seam and server-wire contract.
- The V8-03 partition remains complete and falsifiable.
- The literal authorized-client union is exactly 89 paths.
- Section 13 gate items 1–6 pass.
- No implementation file changed, and all four d321547 files match their baseline.
- Every diff origin is within §14.5’s declared scope.
- Marker IDs and changed-sentence coverage satisfy Rules 2 and 3.
- V8-08 and V8-09 are resolved by the Rule 4 sweep.
- No previously closed V7 item regressed.
- `PEEZY_STATE.md` still registering v8 rather than v9 remains expected and is not a finding.


VERDICT (round 2, of record): APPROVE

---

## Appendix A — Provenance and arbiter verification (Claude; not part of the reviewer's text)

Builder/arbiter: Claude (Fable 5.1) executed `V9_INSTRUCTION.md` (sha256 `ca01f7f11f7cd9a06f54285372ee23dd45f752d097c695f2f4b2361cd506de1f`) against v8 (sha256 `12ea8ee1…2251`, verified before the copy). Reviewer: GPT-5.6-sol, read-only every round (`-s read-only` on round 1, `-c sandbox_mode="read-only"` on the resume). Round 1: 2026-09-02 13:42–14:00 CDT. Round 2: 14:06–14:17 CDT. Transcript: `~/Downloads/peezy-reports/V9_DIFF_REVIEW-log.md`. Tooling used for the mechanical parts (edit script, ledger generator with grep-key selection, §7.4 normalizer, path/test counters, both prompts): `~/Downloads/peezy-reports/v9-tools/`. No repository file other than `PHASE2_REPLACEMENT_MANIFEST_v9.md` (new, uncommitted) and `tasks/todo.md` was written; nothing under `~/Downloads/peezy-reports` is inside the repo.

Round-1 findings and arbiter disposition:
- V9-04 (remote-unverified presentation/handoff order) — accepted; it was arbiter wording in §8.9.1 that sharpened an ambiguity into a contradiction with §8.9.4:1072/1074. Fixed by deferring the order to §8.9.4.
- V9-01, V9-02 — accepted under the "replace wins" standard; §11:1541 and §11.5:1803 now carry pointers only, and row 62's target set was corrected to §8.9.1/§8.9.3/§8.9.6 (the Device-B resume rule lives at §8.9.1:1036/1042 and §8.9.6:1086).
- V9-03 — accepted; the v9 execution report is now meta-only (locations and edit descriptions, no rule restatement), the same standard applied to the deleted v8 §14.4.
- V9-05 — derivative; closed by the above.
- V9-06 and the marker nits (range token, literal placeholder, unmarked phase-order lines) — accepted and fixed.
- Pushback logged and accepted by the reviewer in round 2: the pre-existing untracked worktree paths predate the session (round-1 prompt error, not a v9 defect); the document title and §14 headings remain unmarked because they are headings, consistent with v8.

Independently reproduced by Claude before accepting either report:
- v8 sha256 before copy; v7 `d7c83fcc…`; spec v5 `e02ef938…`; master `80e6dbd3…` at 7546a0f.
- §13 gate items: item 1 (36 rows/36 IDs/exact set), item 3 (lock 7.11.6/7.18.0; `firestore_client_config.json` `2ed7a904…`; Commit/BatchWrite 60,000 ms; `rlm1_`, `rlmreq1_`, `reset1_` reproduced from sorted compact canonical JSON), item 4 (4,432 B/`a7a432ec…` → 5,872 B/`a6de8daf…`, 3/28 → 4/35), item 5 (89/22/23=23/24/25), item 6 (greps).
- §8.9.7 ledger: 64 rows, 281 keys; every unescaped key count 1, every `\|`-escaped key count 0, verified by script after each regeneration.
- v8→v9 diff: 37 hunks, all within the §14.5 line set; 71 marker lines using only V8-01…V8-07, V7-02, V7-03, V7-11, V7-12.
- `git diff d321547 --` over the four Build 25 files is empty; the only tracked modification is `tasks/todo.md`.

## Appendix B — V9_INSTRUCTION required outputs 1–7

1. `PHASE2_REPLACEMENT_MANIFEST_v9.md` · sha256 `a064bc6803f2ac416e1e1d35cb7462a24d0f94d6d95697dd056ee896b1344fc9` · 558,899 bytes · 2,136 lines · uncommitted (v8 remains at 31fe352).
2. Regenerated supersession ledger: v9 §8.9.7 (lines 1094–1165), 64 rows — 45 carried v7 origins re-verified against the final text plus 19 v9 rows — with 281 per-sentence grep keys and a stated grep rule; reviewer result 64 PASS / 0 FAIL, no lossy pointer target.
3. Resolution table: v9 §14.1. V8-01 → §8.9.1:1027, 1031, 1036, 1042; §8.9.5:1082; §8.9.6:1086. V8-02 → §6.6:770 → §8.9.1:1044, §8.9.3:1058, §8.9.4:1074. V8-03 → §11.3:1692. V8-04 → §8:1001 → §8.9.3:1058. V8-05 → §8:1005 → §8.9.3:1058–1060; §12.2:1866; §11.5:1803. V8-06 → §11:1529 → §8.9.3:1058–1060; §8:973; §11.1:1608. V8-07 → §11:1541 → §8.9.1:1036; §11:1437; §11.5:1792, 1794, 1796, 1803. V7-02 → §8.9.1:1021–1040; §8.9.5:1082 (CLOSED). V7-03 → §8.9.1:1036, 1044; §8.9.4:1070–1076; §8.9.5:1082; §6.6:770 (CLOSED). V7-11 → §8.9:1011; §8.9.3:1056–1060; §8.9.7 rows 46–64 (CLOSED). V7-12 → §11.3:1692 (CLOSED). Reviewer: all 16 IDs CLOSED.
4. Recounted totals (v9 §14.2): 58 entries/56 unique frozen §8.2 paths + 33 unique additions = 89 unique authorized client paths; 21 + 1 = 22 Swift test files; 22 + 1 = 23 suites with `-only-testing` = set `E`; 23 + 1 = 24 main Node files, 25 with rules; 19 direct Firestore-caller authorizations. v9 adds or removes none.
5. §13 gate items 1–6 (v9 §14.3): PASS, PASS, PASS, PASS, PASS, PASS — reproduced independently by the reviewer in both rounds.
6. Rule 8 stop: none. The two restored v7 sentences (v7 §11:1311 nonstaged member closure → §8.9.1:1036; v7 §8:991 `confirmAccountDeleted`/`notProven` entry → §8.9.5:1082) were judged recovery of deleted text, not design, by both arbiter and reviewer.
7. No implementation file was modified; no test file or suite was created; the four d321547 files are byte-identical to commit d321547.

## Appendix C — ADR (kept here because the manifest is a frozen-hash artifact; adding it to v9 would change the approved bytes)

- Decision: adopt v9 (sha256 `a064bc68…44fc9`) as the candidate replacement manifest superseding v8; §8.9 is the sole authority for client deletion phases, transitions, gate scope, finalize behavior, presentation, and state enumerations; the capability-invalid exit persists the new exact token `capability_invalid`.
- Drivers: V8-01…V8-07 (V8_DIFF_REVIEW.md), the v8 Rule 4 / Item 1d contradiction, and §13 item 7 ("any P1 reopens").
- Alternatives considered: (a) keep v8 Item 1d "update every closed enumeration" — rejected, it is the dual-authority failure mode that produced V8-04/05/06/07; (b) close the nonstaged `local_detaching` member set de novo — rejected in favor of restoring the deleted v7 §11:1311 sentence (no new design); (c) discriminate the two `remote_unverified` paths with a journal member instead of a new token — foreclosed by V9 Item 1 (decided); (d) keep the v8 execution report beside a v9 one — rejected because §14.4 restated lifecycle constraints; the report is regenerated per version and kept meta-only.
- Why chosen: every edit is instruction-decided or a lossless relocation; every deletion is grep-falsifiable; the reviewer reproduced gates 1–6 and found no two-successor durable state.
- Consequences: v8 line cites in older reviews are historical only (v9 shifts §11+ by 19 lines); PEEZY_STATE §4's frozen-artifact register still names v8 and must be updated to v9 by the owner; §13 item 7 still requires the two independent whole-manifest adversarial passes (codebase-aware migration/scheduler; schema/ownership/envelope/scope) and item 8 the whole-spec review before tuple/hash adoption — this diff-scoped review is not either of those passes.
- Follow-ups: commit v9 with its hash in the message (as v6–v8 were); register v9 in PEEZY_STATE §4; run the §13 item 7 passes; only then apply v9 to `PHASE2_EXECUTABLE_SPEC_v5.md` per §13 item 8.
