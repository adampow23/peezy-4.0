# V8 DIFF REVIEW — PHASE2_REPLACEMENT_MANIFEST_v8.md (diff-scoped, read-only)

Artifact: `PHASE2_REPLACEMENT_MANIFEST_v8.md` · sha256 `12ea8ee1b1fcd43dc88a993ebc4b6706a4b3d8f2ed93ebd09a59d2399262a251` (verified before review) · 537,714 bytes · 2,117 lines · committed as `31fe35225987dbefe52bc7bf8934672cd0bad2f7` (“Add PHASE2_REPLACEMENT_MANIFEST_v8 (sha256 12ea8ee1)”).

Preimage: `PHASE2_REPLACEMENT_MANIFEST_v7.md` · sha256 `d7c83fccc577264702e3b26905ab9e82d5fa36a33c9b1a87f6b59d32e5a0351a` (verified) · committed as `6bfb6e8349ba7424d5ce8df91d90613759f6c2fa`. The v7→v8 `git diff --no-index --unified=0` has 74 hunks; 135 v8 lines contain `[v8: …]`.

Instruction used: `V8_INSTRUCTION.md` · sha256 `01c6a0d40c66b43176faf6eba76599e6239052d5168bbf5651c57a55c9ec1b2f`. Prior review used: `~/Downloads/peezy-reports/V7_DIFF_REVIEW.md` · sha256 `03e5c2ed8bb37b1f0b4d979f3cb62399abbd0bcb987e2b852a1fe24c991bf3f2`.

Frozen spec: `docs/plans/PHASE2_EXECUTABLE_SPEC_v5.md` · sha256 `e02ef93867b744ec0ace9c0860ac309cb7e5fc14ee8c4762a265bd544ca2d2ab` (verified). Master: `docs/plans/files/INSTITUTION_FLOWS_MASTER_v3.md` · sha256 `80e6dbd361c2d85706f538bea96558a61904346536dcb8e069435488bf6bbb8a` (verified), committed at `7546a0f0b7731ee8def18c76a220fea375238f8e`. `PEEZY_STATE.md` contains the v8 hash and “under diff-scoped review” status at line 119.

Scope: all named files were readable. No file or worktree was modified or created. No build, Swift/Node test, npm script, Firebase, or gcloud command was invoked. Implementation inspection was read-only.

Result summary: **15 CLOSED · 1 NOT CLOSED · 5 REGRESSED** across the 21 requested IDs. **9 new P1 · 0 new P2.** Under §13 item 7 (“Any P0/P1 reopens this manifest”), v8 is not ready.

---

## 1. Per-finding verification (21 IDs)

| ID | Result | v8 §:line | Verification |
|---|---|---|---|
| V7-01 | CLOSED | §8.9.2:1048–1050; §8.9.6:1088 | Finalize at DATA_DELETED now returns fresh AUTH_GUARDING, AUTH_GUARDING replays that wire, ACCOUNT_DELETED returns its exact wire, and retry is limited to transport/unknown branches. |
| V7-02 | NOT CLOSED | §8.9.1:1017, 1036, 1040 | Prepared roots now traverse data-confirmed, purging, and local-detaching, but the resulting `local_detaching` byte contract is incomplete, so the Option-A route is not fully specified (V8-01). |
| V7-03 | REGRESSED | §8.9.1:1036, 1042; §8.9.4:1070–1074; §8.9.5:1082; §6.6:770 | `local_cleared` and its presentation exist, but its durable predecessor is indistinguishable from the legacy remote-unconfirmed branch, and §6.6 still places terminal presentation after gate clear (V8-01, V8-02). |
| V7-04 | CLOSED | §8.9.2:1052; §8.9.4:1068; §8.9.6:1088 | DELETING-sweeping retains enrollment/sweep mutations, while only DELETING-guarding is the queued no-write branch. |
| V7-05 | CLOSED | §12.2:1816, 1818, 1830–1853; §13:2069 | All four d321547 files have exact per-call-site scopes, exclusions and ownership are reconciled, and the client total is correctly updated to 89. |
| V7-06 | CLOSED | §1:30; §12.1:1796 | The master is pinned to commit `7546a0f` and verified hash `80e6…b8a`; committed A12-11/A12-12 and regeneration item 9 make both edits resolvable. |
| V7-07 | CLOSED | §2.2:59, 61, 142; §3.1:308, 310 | Exact legacy leases migrate transactionally at initialization, scheduler acquisition, and MIG-EVENT acquisition; every other non-v2 shape blocks. |
| V7-08 | CLOSED | §11:1426–1454; §12.3:1859 | The literal participant list and narrow timeout scan are present, and `changeTaskPlan` is expressly held at 540 seconds outside the scan. |
| V7-09 | CLOSED | §8.9.3:1064; §8.9.6:1086 | The Option-B unlink→empty-slot crash is named and relaunch cleanly permits the new UID to restart deletion. |
| V7-10 | CLOSED | §12.2:1816 | `taskDisposition.js` and `notificationIntents.js` are labeled new and no longer appear in the existing-path sublist. |
| V7-11 | REGRESSED | §8.9.3:1056–1064 vs §8:1001, 1005; §11:1510; §12.2:1847; §14.4:2113 | The closed projections are updated, but multiple substantive gate-scope rules remain outside the section declared sole authority (V8-04 through V8-06, V8-08, V8-09). |
| V7-12 | REGRESSED | §11.3:1673 | The requested absence-retention shape is present, but it has no `destinationOrdinals` while the adjacent exact-partition rule requires those arrays to cover every accepted destination ordinal (V8-03). |
| V7-13 | CLOSED | §7:965 | Over-cap observations use `targetPresent` and `quarantinePresent`; the nonexistent `present` member is gone. |
| V7-14 | CLOSED | §8:997; §11:1510 | `Phase2ProductionRuntime.firestoreRuntimeOwner` names the declared process-wide `FirestoreRuntimeOwner` actor. |
| Item 1 | REGRESSED | §8.9:1009–1146 vs §6.6:770; §8:1001, 1005; §11:1510, 1522; §12.2:1847; §14.4:2113 | The replacement section exists, but its schema is incomplete and it is not the sole remaining authority for client phases, gate scope, finalize behavior, or terminal presentation. |
| Item 2 | CLOSED | §2.2:59, 61, 142; §3.1:308, 310 | Exact legacy lease migration and malformed-shape refusal are specified at all three required read sites with fixtures. |
| Item 3 | CLOSED | §11:1426–1454; §12.3:1859 | `DELETION_PARTICIPATING_FUNCTIONS_V1`, the narrow source scan, reached provider timeouts, and the unchanged 540-second nonparticipant are all explicit. |
| Item 4 | CLOSED | §12.2:1816, 1818, 1830–1853; §13:2069 | The d321547 files are authorized only for the exact requested edits, the obsolete exclusion language is absent, totals are updated, and the Firestore scan is mechanically satisfiable. |
| Item 5 | CLOSED | §1:30; §12.1:1796 | The fixed master commit/hash replaces the moving HEAD pin, and both committed authority-document targets exist. |
| Item 6 | REGRESSED | §12.2:1816; §11.3:1673; §7:965; §8:997; §11:1510 | V7-10, V7-13, and V7-14 are closed, but the V7-12 shape contradicts the unchanged partition requirement (V8-03). |
| Item 7 | CLOSED | §11.5:1772, 1775, 1784 | The Auth, Keychain, and two-device rows reference the new wires, completed/local-cleared states, guarding scope, and Option-B crash fixture while declaring zero added obligations. |

---

## 2. Supersession check (45 ledger entries)

Method: each ledger-described v7 sentence was checked against the v7→v8 diff and searched across v8 outside the authorized §8.9 replacement. Exact shapes repeated inside §8.9 are replacement authority, not surviving original-location authority. “Pointer-only” permits unaffected material on the same physical line, but not a paraphrased continuation of the superseded rule.

**42 entries pass; 3 fail.**

| # | Superseded v7 §:line | v8 original-location anchor | (a) Removed outside §8.9 | (b) Pointer-only | Verification |
|---:|---|---|---|---|---|
| 1 | §8:975 | §8:975 | PASS | PASS | Both selected clauses became sole-authority pointers to §8.9.3/§8.9.4. |
| 2 | §8:977 | §8:977 | PASS | PASS | Entire old wire/reducer line is replaced by one pointer. |
| 3 | §8:981 | §8:981 | PASS | PASS | Old queued projection remains only in §8.9.4. |
| 4 | §8:983 | §8:983 | PASS | PASS | Old guarding/completion presentation text is replaced by one pointer. |
| 5 | §8:985 | §8:985 | PASS | PASS | Sentences 2–6 are removed; the unaffected required-set sentence remains beside the pointer. |
| 6 | §8:987 | §8:987 | PASS | PASS | Signed-out/A→B lifecycle text is replaced by one pointer. |
| 7 | §8:989 | §8:989 | PASS | PASS | BUSY/handoff/recovery text is replaced by one pointer. |
| 8 | §8:991 | §8:991 | PASS | PASS | The old monolithic reducer is replaced by one §8.9.1–§8.9.6 pointer. |
| 9 | §8:995 | §8:995 | PASS | PASS | Only the runtime-identity fixture was replaced; unaffected ownership text remains. |
| 10 | §8:999 | §8:1001 | **FAIL** | **FAIL** | The opener rule survives with an expanded enumeration instead of being replaced solely by a pointer (V8-04). |
| 11 | §8:1005 | §8:1007 | PASS | PASS | Deletion lifecycle fixture clauses are removed and consolidated by pointer. |
| 12 | §11:1275 | §11:1416 | PASS | PASS | Client capability, result, and recovery clauses became §8.9 pointers. |
| 13 | §11:1307 | §11:1478 | PASS | PASS | Client data-final, purge, finalize-result, and residue clauses became pointers. |
| 14 | §11:1311 | §11:1482 | PASS | PASS | Old intent schema and phase cross-products are removed. |
| 15 | §11:1313 | §11:1484 | PASS | PASS | Completion-file variants and publication behavior became one pointer. |
| 16 | §11:1315 | §11:1486 | PASS | PASS | Snapshot/action semantics became one pointer. |
| 17 | §11:1317 | §11:1488 | PASS | PASS | Old surface rendering and fixtures became one pointer. |
| 18 | §11:1319 | §11:1490 | PASS | PASS | Local-purge schema remains; only its superseded fixture sentence became a pointer. |
| 19 | §11:1321 | §11:1492 | PASS | PASS | Singleflight and launch order are replaced by one pointer. |
| 20 | §11:1323 | §11:1494 | PASS | PASS | Terminal handoff, unlink, and gate order are replaced by one pointer. |
| 21 | §11:1325 | §11:1496 | PASS | PASS | Ack replay, all-scope completion, and recovery are replaced by one pointer. |
| 22 | §11:1327 | §11:1498 | PASS | PASS | Intent classification/startup reducer text is replaced by one pointer. |
| 23 | §11:1329 | §11:1500 | PASS | PASS | Selected client phase-routing clauses are replaced; unrelated store-purge mechanics remain. |
| 24 | §11:1331 | §11:1502 | PASS | PASS | Fresh-capture gate admission is reduced to a sole-authority pointer. |
| 25 | §11:1333 | §11:1504 | PASS | PASS | Narration gate behavior is reduced to a sole-authority pointer. |
| 26 | §11:1335 | §11:1506 | PASS | PASS | Narration callback/transfer fixtures are consolidated by pointer. |
| 27 | §11:1337 | §11:1508 | PASS | PASS | Admission and media fixtures are replaced by §8.9 pointers. |
| 28 | §11:1339 | §11:1510 | **FAIL** | **FAIL** | “Gates all Firestore acquisition before its ack” remains as a paraphrased substantive rule (V8-06). |
| 29 | §11:1341 | §11:1512 | PASS | PASS | Registration gate scope is replaced by a sole-authority pointer. |
| 30 | §11:1343 | §11:1514 | PASS | PASS | Notification-tap gate behavior is replaced by a pointer. |
| 31 | §11:1347 | §11:1518 | PASS | PASS | Messaging/Installations fixtures are consolidated by pointer. |
| 32 | §11:1349 | §11:1520 | PASS | PASS | Google interleaving fixtures are consolidated by pointer. |
| 33 | §11:1351 | §11:1522 | **FAIL** | **FAIL** | The failure rule still says no client finalize/unlink/clear rather than leaving only a pointer (V8-07). |
| 34 | §11:1355 | §11:1526 | PASS | PASS | Old finalize/guarding/terminal/gate/crash authority is replaced by one pointer. |
| 35 | §11:1357 | §11:1528 | PASS | PASS | Provider-specific completion behavior is replaced by one pointer. |
| 36 | §11:1361 | §11:1532 | PASS | PASS | Server fixtures remain; client lifecycle fixtures are removed and consolidated. |
| 37 | §11.1:1414 | §11.1:1585 | PASS | PASS | Client phase boundaries are reduced to a §8.9 pointer. |
| 38 | §11.1:1418 | §11.1:1589 | PASS | PASS | Telemetry fixture ownership is consolidated by pointer. |
| 39 | §11.3:1482 | §11.3:1653 | PASS | PASS | Old sweeping/client queued/startup text is replaced; corrected server behavior remains. |
| 40 | §11.3:1498 | §11.3:1669 | PASS | PASS | Guarding gate/presentation/handoff text is replaced by one pointer. |
| 41 | §11.3:1500 | §11.3:1671 | PASS | PASS | Client DATA_DELETED/finalize behavior is replaced by one pointer. |
| 42 | §11.3:1506 | §11.3:1677 | PASS | PASS | Server root schema remains; client wires and presentation became pointers. |
| 43 | §11.3:1512 | §11.3:1683 | PASS | PASS | Server reconciler behavior remains; client finalize/detach behavior became a pointer. |
| 44 | §11.3:1514 | §11.3:1685 | PASS | PASS | Only the client completion fixture clause was consolidated. |
| 45 | §11.3:1516 | §11.3:1687 | PASS | PASS | Guarding client fixtures are replaced by one pointer. |

### Outside-§8.9 lifecycle-authority sweep

Section §8.9:1011 declares §8.9 the sole authority. These substantive rules remain outside it; each is a P1:

| Finding | v8 §:line | Residual normative text |
|---|---|---|
| V8-02 | §6.6:770 | “The replacement … follows §11's durable-intent→server-data-authority→eight-owner-ack→preferences barrier→client-telemetry barrier→Auth finalization→durable terminal presentation→conditional-sign-out→all-scope-purge order.” It also says the presentation owner projects the terminal result “after the gate clears.” |
| V8-04 | §8:1001 | “Calls `SupportChatNavigation.requestOpen()` exactly once only when the gate is `clear`; `loading\|blocked\|active-*\|guarding-*\|local_cleared` call no opener.” |
| V8-05 | §8:1005 | “Each operation is gated by its declared required set plus the deletion gate.” |
| V8-06 | §11:1510 | “`FirestoreLocalCachePurging` gates all Firestore acquisition before its ack under §8.9.3.” |
| V8-07 | §11:1522 | “Synchronize/removal/reread failure retains durable state and performs no finalize, unlink, or clear.” |
| V8-08 | §12.2:1847 | “`PaywallGateView.swift` is authorized only to gate `redeemGiftCode` immediately before dispatch and discard a late result after gate-generation change.” |
| V8-09 | §14.4:2113 | The supposedly exact constraints restate local-detaching transitions and require that “the second UID signs in and dispatches while the first UID guards.” |

---

## 3. §8.9 internal consistency

The transition walk includes every sequential graph edge and every direct edge from `local_detaching`. For nonterminal phases, the presentation cell cites the phase declaration establishing that it is nonterminal. One required durable-byte cell is missing.

| Transition | Producing wire/local event in §8.9.2/§8.9.5 | Durable resulting-phase bytes | Presentation/terminal status | Named fixture |
|---|---|---|---|---|
| `prepared → data_confirmed` | §8.9.2:1048; reducer §8.9.1:1040 | §8.9.1:1034 | §8.9.1:1034 (nonterminal) | §8.9.6:1086 |
| `data_confirmed → purging` | §8.9.2:1048; reducer §8.9.1:1040 | §8.9.1:1034 | §8.9.1:1034 (nonterminal) | §8.9.6:1086 |
| `purging → local_detaching` | §8.9.2:1048; reducer §8.9.1:1040 | **MISSING** | §8.9.1:1036 (nonterminal) | §8.9.6:1086 |
| `local_detaching → auth_finalize_dispatched` | §8.9.2:1048; reducer §8.9.1:1040 | §8.9.1:1038 | §8.9.1:1038 (nonterminal) | §8.9.6:1086, 1088 |
| `auth_finalize_dispatched → guarding` | §8.9.2:1050 | §8.9.1:1038 | §8.9.4:1070 | §8.9.6:1088 |
| `auth_finalize_dispatched → completed` | §8.9.2:1050 | §8.9.1:1038 | §8.9.4:1070–1074 | §8.9.6:1088 |
| `local_detaching → guarding` | §8.9.2:1048; reducer §8.9.1:1040 | §8.9.1:1038 | §8.9.4:1070 | §8.9.6:1086, 1088 |
| `local_detaching → completed` | §8.9.2:1048; reducer §8.9.1:1040 | §8.9.1:1038 | §8.9.4:1070–1074 | §8.9.6:1086, 1088 |
| `guarding → completed` | §8.9.2:1050 | §8.9.1:1038 | §8.9.4:1070–1074 | §8.9.6:1086, 1088 |
| `local_detaching → local_cleared` | §8.9.5:1082 | §8.9.1:1038 | §8.9.4:1070–1074 | §8.9.6:1086 |

The missing byte contract is P1 V8-01. The exact payload declares optional cross-branch members and rejects wrong-phase combinations (§8.9.1:1017), but §8.9.1:1036 does not close the required/forbidden members or permitted ack prefixes for nonstaged `local_detaching`. It also sends the same durable `local_detaching(reason:"remote_unverified")` to two different results: remote-unconfirmed for the non-capability-invalid branch (§8.9.1:1042) and `local_cleared` for the capability-invalid branch (§8.9.5:1082). Consequently, the crash-at-every-phase fixture (§8.9.6:1086) has no durable discriminator from which to select the terminal result.

---

## 4. §12.2 recount and §13 gate items 1–6

### §12.2 authorized client-path recount

Method reproduced from the v7 review: extract literal backticked `.swift`, `.plist`, and `.pbxproj` paths from frozen spec v5 §8.2 rows (§8.2:1762–1769), then union them with literal backticked `Peezy 4.0/…` paths in the four v8 addition bullets (§12.2:1838–1841).

| Quantity | Count/evidence |
|---|---|
| Frozen §8.2 entries / unique | 58 / 56 |
| Frozen duplicates | `PeezyMainContainer.swift`; `FlowExitControl.swift` |
| v7 addition entries / unique | 30 / 30 |
| v8 addition entries / unique | 33 / 33 |
| Additions overlapping frozen paths | 0 |
| v7→v8 removals | 0 |
| Exact v7→v8 additions | `InventorySessionManager.swift`, `InventoryCameraView.swift`, `NarrationService.swift` |
| Arithmetic | v7 `86 = 56 + 30`; v8 `89 = 56 + 33 = 86 + 3 − 0` |
| Result | **89 unique authorized client paths — reproduced** |

### §13 gate items 1–6, independent rerun

| Item | Result | Evidence |
|---|---|---|
| 1. ID set / path closure | PASS | §13:2019–2054 contains 36 rows, 36 unique IDs, exact equality with D1–D15, D18–D32, B1–B4, MIG-EVENT-V1, MIG-RESET-V1, single valid authority cells, and 21 distinct referenced paths; D32 points only to §12.5/§9.4 authority. |
| 2. Schema/crash fixtures | **FAIL** | Fixture names are extensive (§8.9.6:1086–1092), but the nonstaged `local_detaching` byte shape and crash-replay discriminator are missing (§8.9.1:1017, 1036, 1042; §8.9.5:1082), so the named crash boundary cannot be falsified deterministically (V8-01). |
| 3. Codec/decoder pins | PASS | Lock resolves Firestore 7.11.6 and Storage 7.18.0; installed client config hashes `2ed7a9046d766121b7f308b22384b1a6caaf7c6eaed5d9ea553556af3c987e41`, with Commit/BatchWrite 60,000 ms. Canonical no-LF hashes reproduce `0a4d53a4…827ad8e1` and `862fe3fc…f04e94a1`; retired migration mechanisms occur only in negative/decoy/gate text (§2.5:202; §6.2:622, 774; §13:2062). |
| 4. §7.4 registry | PASS | Frozen JSON normalizes to 4,432 bytes / `a7a432ec8e0511176b890432c5e4cb4a07e59a6dba0c9d920948cc446f3a7bbb`, with 3 indexes and 28 overrides. Applying the eight §12.4 appends normalizes to 5,872 bytes / `a6de8daf701a75ff3db025ca244dbf2218432c5c1a06b0992cd88358250d88e8`, with 4 indexes and 35 overrides. |
| 5. Mechanical counts | PASS | Client paths 89; Swift test files 21→22; named `-only-testing` and expected set `E` both 22→23 with equal sets; Node main envelope 23→24; Node plus rules 25 unique files. |
| 6. Grep bans | PASS | Master timing clauses are present at master lines 51 and 436 for replacement; A12-11/A12-12 and regen item 9 are committed. No active alias/codec authority regression was found. Policy-bearing ordinary `evidence_ids` is absent; the one positive policy-absent registry path is §10:1234. D4 hits are the permitted withdrawal, per-row saturation, and no-eviction assertions (§2.4:154–198), not the retired bounded-map/eviction design. |

---

## 5. d321547 files and the rg gate

`git show --stat d321547` identifies exactly:

- `functions/processInventory.js`
- `Peezy 4.0/Inventory/Models/InventorySessionManager.swift`
- `Peezy 4.0/Inventory/Views/InventoryCameraView.swift`
- `Peezy 4.0/Inventory/Services/NarrationService.swift`

A read-only diff from `d321547` over those four paths is empty. Current hashes equal the corresponding commit blobs:

| File | SHA-256 | Authorized Phase 2 change |
|---|---|---|
| `functions/processInventory.js` | `169461aa049e443beee2c0cc943bfe5dcdce35a4b4751d80f636cd58a9123f19` | Shared-fence calls on process success/error and `onInventoryRoomWritten`; every Anthropic call under the shared lease helper; nothing else (§12.2:1816, 1830, 1845). |
| `InventorySessionManager.swift` | `97ad2e231a4171e26432d5b98195322e1fadc9a789b9763209e889f40d244c71` | Exactly six Firestore acquisitions migrate to `FirestoreRuntimeOwner`; only `pendingNarration` additionally changes to an actor-issued lease handle (§12.2:1831, 1845, 1847). |
| `InventoryCameraView.swift` | `5f4f76957ec41e32b8b779643349dc049b2914e7eafe2f51f2a88930b42ff52d` | Only `pendingNarrationTranscript` changes to an actor-issued lease handle (§12.2:1832, 1845). |
| `NarrationService.swift` | `5fcffe128c3acbe01d43ce29e67e9aa3fdcbc33becc91d6432c04876f4236276` | Only `start` changes to require an actor lease (§12.2:1832, 1845). |

The exact strings “receive no Phase 2 edit” and “verification-only” have zero occurrences in v8. Labels and ownership rows are updated at §12.2:1816, 1818, 1830–1832, and totals at §12.2:1836–1853.

The two §11 registry paragraphs are byte-identical between v7 §11:1281/1283 and v8 §11:1422/1424; hashing those extracted lines in each artifact produced the same SHA-256 `a96c140d74a3042eb2d15ef472125123bb59a9c0d4305b43b1f08c739c1cf42c`.

### Production `Firestore.firestore()` scan

The scan found **77 occurrences in 36 production Swift files**. All 36 files are inside the 89-path authorized union; none is outside. The 19 direct-caller files among the v8 additions reproduce §12.2:1847. `LocalPrivacyPurgeCoordinator.swift` is a new authorized path and does not yet exist; `PeezyV1App.swift` contains the one designated initialization occurrence.

| Production file | Occurrences | Authorized union |
|---|---:|---|
| `Peezy 4.0/Assessment/AssessmentModels/AssessmentDataManager.swift` | 1 | Inside |
| `Peezy 4.0/Assessment/AssessmentModels/TaskGenerationService.swift` | 2 | Inside |
| `Peezy 4.0/Assessment/AssessmentViews/Onboarding/GeneratingView.swift` | 1 | Inside |
| `Peezy 4.0/Inventory/Models/InventorySessionManager.swift` | 6 | Inside; newly restored exact scope |
| `Peezy 4.0/Inventory/Services/InventoryStorageService.swift` | 2 | Inside |
| `Peezy 4.0/MainInterface/Models/BoxReturnService.swift` | 1 | Inside |
| `Peezy 4.0/MainInterface/Models/CheckInService.swift` | 1 | Inside |
| `Peezy 4.0/MainInterface/Models/DailyDoseEngine.swift` | 3 | Inside |
| `Peezy 4.0/MainInterface/Models/ISPPlanService.swift` | 1 | Inside |
| `Peezy 4.0/MainInterface/Models/IdentityService.swift` | 1 | Inside |
| `Peezy 4.0/MainInterface/Models/MoversFlowViewModel.swift` | 2 | Inside |
| `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift` | 1 | Inside |
| `Peezy 4.0/MainInterface/Models/PeezyStackViewModel.swift` | 1 | Inside |
| `Peezy 4.0/MainInterface/Models/PeezyV1App.swift` | 1 | Inside; designated retained initialization |
| `Peezy 4.0/MainInterface/Models/ProviderDirectoryService.swift` | 1 | Inside |
| `Peezy 4.0/MainInterface/Models/RetakeAssessmentCoordinator.swift` | 2 | Inside |
| `Peezy 4.0/MainInterface/Models/SubscriptionManager.swift` | 1 | Inside |
| `Peezy 4.0/MainInterface/Models/SupportChatService.swift` | 1 | Inside |
| `Peezy 4.0/MainInterface/Models/TaskActionService.swift` | 30 | Inside |
| `Peezy 4.0/MainInterface/Models/UserKnowledgeService.swift` | 1 | Inside |
| `Peezy 4.0/MainInterface/Models/Vendor.swift` | 1 | Inside |
| `Peezy 4.0/MainInterface/Views/AppRootView.swift` | 1 | Inside |
| `Peezy 4.0/MainInterface/Views/SupportChatView.swift` | 1 | Inside |
| `Peezy 4.0/Menu/PeezySettingsView.swift` | 1 | Inside |
| `Peezy 4.0/Tasks/FlowEngine/FlowDefinition.swift` | 1 | Inside |
| `Peezy 4.0/Tasks/FlowEngine/FlowEngineView.swift` | 1 | Inside |
| `Peezy 4.0/Tasks/FlowEngine/InAppTaskFlows.swift` | 1 | Inside |
| `Peezy 4.0/Tasks/FlowEngine/MoveAnswersStore.swift` | 1 | Inside |
| `Peezy 4.0/Tasks/Store/TasksStore.swift` | 1 | Inside |
| `Peezy 4.0/Tasks/Task Cards/BookYourMoversView.swift` | 1 | Inside |
| `Peezy 4.0/Tasks/Task Cards/PackingSessionView.swift` | 1 | Inside |
| `Peezy 4.0/Tasks/Task Cards/ScanInventoryFlow.swift` | 1 | Inside |
| `Peezy 4.0/Tasks/Task Cards/SuppliesKitView.swift` | 1 | Inside |
| `Peezy 4.0/Tasks/Views/TaskContentSections.swift` | 1 | Inside |
| `Peezy 4.0/Tasks/Views/TaskDetailView.swift` | 1 | Inside |
| `Peezy 4.0/Tasks/Views/TaskResearchModule.swift` | 2 | Inside |

Outside authorized union: **0 files / 0 occurrences**. The former gate is therefore mechanically satisfiable after the explicitly authorized substitutions.

---

## 6. New findings

### P1

- **V8-01 · §8.9.1:1017, 1036, 1042; §8.9.5:1082; §8.9.6:1086** · The Option-A `local_detaching` durable shape is not closed. Section 1017 requires rejection of every wrong-phase/cross-branch combination, but §8.9.1:1036 does not define the required/forbidden optional members or permitted ack prefixes for a nonstaged variant. More critically, both the existing non-capability-invalid path (§8.9.1:1042) and the new capability-invalid path (§8.9.5:1082) persist `local_detaching(reason:"remote_unverified")` but require different terminal results. After a crash, no specified durable byte distinguishes remote-unconfirmed from `local_cleared`, making the §8.9.6:1086 crash-at-every-phase fixture unfalsifiable.

- **V8-02 · §6.6:770 vs §8.9.1:1044 and §8.9.3:1058** · Section 6.6 still requires the process-wide presentation owner to project the terminal result “after the gate clears.” Section 8.9 instead requires a completed/local-cleared intent to keep the gate nonclear while presentation is published and permits `clear` only after the presentation action is consumed. Both orders cannot be implemented.

- **V8-03 · §11.3:1673** · `authResidualChecks` requires its `destinationOrdinals` arrays to form an exact partition of every accepted destination ordinal, but the exact absence-retention branch is `{ordinal,kind:"absence_retention",observedAbsentAt,retentionSeconds}` and has no `destinationOrdinals`. A destination required to use that branch cannot be represented in the mandated partition, so the sealed authority is unreachable for that accepted destination class.

- **V8-04 · §8.9:1011 vs §8:1001** · Section 8.9 declares itself the sole gate-scope authority, but §8:1001 still directly defines support-opener behavior for `clear`, loading, blocked, active, guarding, and local-cleared states. This is also the failed §8:999 supersession entry.

- **V8-05 · §8.9:1011 vs §8:1005** · Section 8:1005 still normatively states that every operation is gated by its required set plus the deletion gate and separately describes the clear-gate exception, leaving a second gate-scope authority outside §8.9.

- **V8-06 · §8.9:1011 vs §11:1510** · Section 11 retains the substantive rule that `FirestoreLocalCachePurging` gates all Firestore acquisition before its ack. Adding “under §8.9.3” did not replace the old rule with a pointer; it patched the superseded sentence and leaves a second gate-scope authority.

- **V8-07 · §8.9:1011 vs §11:1522** · Section 11 still states that preference synchronization/removal/reread failure performs no finalize, unlink, or clear. That is client finalize and phase-transition behavior outside the declared sole authority and is the failed §11:1351 supersession entry.

- **V8-08 · §8.9:1011 vs §12.2:1847** · Section 12.2 still defines the Paywall callable’s immediate deletion-gate admission and late-result behavior and enumerates the closed gate projections. This is a substantive consumer gate-scope rule outside §8.9, not merely path authorization.

- **V8-09 · §8.9:1011 vs §14.4:2113** · The execution report calls its restated lifecycle constraints “exact,” including `local_detaching` transition behavior and second-UID dispatch during guarding. That creates another normative lifecycle/gate authority outside §8.9.

### P2

None.

---

## 7. Verified with no finding

- The artifact, preimage, frozen-spec, master, instruction, and prior-review hashes were all independently readable and verified.
- V7-01, V7-04 through V7-10, V7-13, V7-14, and Items 2–5 and 7 are closed.
- Forty-two of the 45 supersession-ledger entries fully removed the old authority and left only the intended pointer at the corresponding v8 location.
- The v8 client-path count is exactly 89, with the three d321547 Swift paths as the only v7→v8 additions and no removals.
- The four d321547 implementation files remain byte-identical to commit `d321547`.
- The §11 writer/provider registry lines are byte-identical between v7 and v8.
- All 36 current production Swift files containing `Firestore.firestore()` are authorized; no production occurrence lies outside the union.
- §13 gate items 1 and 3–6 independently pass. Item 2 fails only for the durable-state issue identified as V8-01.
- The state document records the exact v8 hash as under diff-scoped review.

VERDICT: ITERATE
---

## 8. Round 2 — arbiter challenge and reviewer response

### 8.1 V8-05 — general deletion-gate statement

No behavioral contradiction exists between “each operation is gated by its declared required set plus the deletion gate” (§8:1005) and the global `active|blocked` scope (§8.9.3:1058). The only conflict is with §8.9’s normative declaration that it is the “sole authority” for gate scope (§8.9:1011). Because §8:1005 independently imposes a gate-scope requirement instead of merely pointing to §8.9.3, V8-05 remains a formal authority contradiction; the owner’s outside-§8.9 sweep rule corroborates that classification but is not its sole basis.

**NARROW** — V8-05 is a P1 only for the normative sole-authority contradiction between §8.9:1011 and §8:1005, not for any inconsistency with the gate behavior specified at §8.9.3:1058.

### 8.2 V8-08 — Paywall authorization and fixture enumeration

The `PaywallGateView.swift` clause is part of the literal per-file authorization boundary: it limits the permitted edit to immediate admission and late-result rejection (§12.2:1847). Its state enumeration is fixture coverage and exactly matches the closed consumer projection in §8.9.3:1056. V8_INSTRUCTION Item 1d:70 expressly required every such enumeration to include guarding and `local_cleared`. Neither sentence claims to replace §8.9.3 as the lifecycle authority, and no behavioral conflict exists with the global and UID-specific rules at §8.9.3:1058.

**WITHDRAW** — V8-08 does not contradict §8.9:1011, 1056, or 1058 because §12.2:1847 authorizes a call-site edit and enumerates required fixture coverage rather than establishing a competing deletion lifecycle.

### 8.3 V8-09 — §14.4 execution-report disposition

A full-text search found no sentence declaring §14 normative; the only explicit characterization is the heading “v8 execution report” (§14:2073). Section 14.4 records the owner’s Option A decision (§14.4:2113). Its staging constraints agree with §8.9.1:1036, and its second-UID statement agrees with the guarding rule permitting another UID to sign in and dispatch after the non-UID barriers clear (§8.9.3:1058). No inconsistent transition, gate scope, or presentation requirement was found.

**WITHDRAW** — V8-09 is an execution-record restatement at §14:2073 and §14.4:2113 that is consistent with §8.9.1:1036 and §8.9.3:1058, not a contradictory normative authority.

### 8.4 V8-04, V8-06, and V8-07 — retained text versus the supersession ledger

These contradictions remain regardless of the generating instruction because v8’s ledger declares the described sentences deleted while v8 retains sentences falling squarely within those descriptions:

| Finding | Ledger description | Retained v8 sentence | Result |
|---|---|---|---|
| V8-04 / #10 | “the sentence enumerating `loading, blocked, active-*` opener states and the sentence's matching fixture enumeration” (§8.9.7:1109) | “`loading\|blocked\|active-same-UID\|active-other-UID\|active-with-nil-current-UID\|guarding-same-UID\|guarding-other-UID\|local_cleared` call no opener” (§8:1001). | The retained sentence is the same support-opener state predicate, expanded with the new states rather than deleted. |
| V8-06 / #28 | “the Firestore gate sentence, the terminate/clear/recreate failure sentence's old gate/completion clause, and the Firestore fixture sentence” (§8.9.7:1127) | “`FirestoreLocalCachePurging` gates all Firestore acquisition before its ack under §8.9.3” and failure “leaves the purge journal and global gate blocked” (§11:1510). | The first retained sentence is expressly the Firestore gate sentence; the second retains the named failure-to-gate consequence. |
| V8-07 / #33 | “the phase/finalize/unlink/gate-clear sentences and their client fixtures” (§8.9.7:1132) | “Synchronize/removal/reread failure retains durable state and performs no finalize, unlink, or clear” (§11:1522). | The retained sentence explicitly specifies the ledger’s named finalize, unlink, and gate-clear behavior. |

Instruction-level root cause: V8_INSTRUCTION Rule 4:22 and Item 1:30–32 require deletion and pointer replacement, while Item 1d:70 requires the named §8:999 enumeration to be updated, creating a direct update-versus-delete conflict for #10; #28 and #33 have no corresponding exception and violate the unambiguous deletion requirement.

**SUSTAIN** — The deletion assertions at §8.9.7:1096, 1109, 1127, and 1132 contradict the retained normative sentences at §8:1001, §11:1510, and §11:1522.

### 8.5 V8-01 — durable discriminator self-check

I searched all of §8.9 (§8.9:1009–1146) and §11 through §11.5 (§11:1297–1788), case-insensitively, for `remote_unverified`, `definitivelyDeleted`, `capability-invalid`, `cached expected`, `expected user`, `local_detaching`, `purpose`, `authorityKind`, `providerContext`, `terminalDeletionLink`, `authEpochUUID`, `credentialRevision`, `journal`, `persist`, `durable`, `detachReason`, `stagedRoot`, `observation`, `absence`, and `notProven`.

No durable discriminator was found:

- The exact intent payload has no capability-invalid observation or cached-user-state member (§8.9.1:1017).
- `purpose` is specified for `prepared`, not as a retained capability-invalid discriminator (§8.9.1:1034), while the nonstaged `local_detaching` contract specifies only `detachReason:"auth_deleted"|"remote_unverified"` (§8.9.1:1036).
- The UID purge journal persists operation/proof, provider context, acknowledgements, and timestamps, but no capability-invalid, `definitivelyDeleted`, or terminal-selection member (§11:1490).
- The completion file is derived only upon entry to a terminal result, so it cannot resolve a relaunch that occurs during `local_detaching` (§8.9.4:1072).
- Section 8.9.5 refers to an “exact cached expected user” observation but never specifies that observation as persisted (§8.9.5:1082).

Consequently, the durable `local_detaching(reason:"remote_unverified")` state still has two required successors: remote-unconfirmed on the non-capability-invalid path (§8.9.1:1042) and `local_cleared` on the capability-invalid path (§8.9.5:1082). A relaunch at that phase cannot select between them, leaving the crash/relaunch fixture (§8.9.6:1086) unfalsifiable.

**SUSTAIN** — No persisted discriminator exists in the exact intent (§8.9.1:1017, 1036) or purge-journal schema (§11:1490) to distinguish the conflicting terminal routes at §8.9.1:1042 and §8.9.5:1082 after the required crash boundary at §8.9.6:1086.

### 8.6 V7-02 disposition after the V8-01 self-check

| ID | Result | v8 §:line | Revised verification |
|---|---|---|---|
| V7-02 | NOT CLOSED | §8.9.1:1017, 1036, 1040, 1042; §8.9.5:1082; §8.9.6:1086 | Prepared roots now traverse `data_confirmed`, `purging`, and `local_detaching`, but the durable nonstaged `local_detaching` contract still lacks the discriminator required for deterministic crash replay, so Item 1a is not fully closed. |

**SUSTAIN** — V7-02 remains NOT CLOSED because the route added at §8.9.1:1040 reaches the underdetermined durable state at §8.9.1:1017, 1036 whose two successors at §8.9.1:1042 and §8.9.5:1082 make the §8.9.6:1086 relaunch fixture unfalsifiable.

Revised Result summary: **15 CLOSED / 1 NOT CLOSED / 5 REGRESSED** across the 21 IDs; **7 new P1 / 0 new P2**.

Remaining P1 IDs: **V8-01, V8-02, V8-03, V8-04, V8-05, V8-06, V8-07**.

VERDICT: ITERATE
---

## Appendix A — Provenance and arbiter verification (Claude; not part of the reviewer's text)

Reviewer: GPT-5.6-sol via codex-cli 0.147.0, sandbox read-only both rounds, single persistent thread `01a06211-2e69-7e41-b076-a4831fdd517d`. Round 1 (full verification) 2026-09-02 ~07:21–07:45 CDT; round 2 (arbiter challenge, same thread) ~07:53–08:05 CDT. Transcript: `~/Downloads/peezy-reports/V8_DIFF_REVIEW-log.md`. No repository file was created or modified by this review; the only writes are this report and its log, both outside the repo per PEEZY_STATE §4. No revision of v8 was made or proposed (owner constraint), so the loop stopped after the challenge round rather than at the round cap.

Verdict of record: **ITERATE**. Final tally: 15 CLOSED / 1 NOT CLOSED / 5 REGRESSED across the 21 IDs; **7 new P1** (V8-01, V8-02, V8-03, V8-04, V8-05, V8-06, V8-07), 0 P2. V8-08 and V8-09 were withdrawn in round 2; V8-05 was narrowed to the sole-authority conflict with §8.9:1011 only. Under §13 item 7, v8 reopens.

Independently reproduced by Claude before accepting the report:
- v8 sha256 `12ea8ee1…` (before round 1); v7 `d7c83fcc…`; master `80e6dbd3…` equals `git show 7546a0f:docs/plans/files/INSTITUTION_FLOWS_MASTER_v3.md`; spec v5 `e02ef938…`.
- 135 `[v8:` lines; 74 hunks under `--unified=0` (19 under default context).
- Every §:line anchor quoted in §6 (V8-01 … V8-09) and the three failed ledger rows (#10, #28, #33) exist in v8 at the cited lines with the quoted text.
- §11 registry lines v7 1281/1283 and v8 1422/1424 hash identically (`a96c140d…`).
- Production Swift `Firestore.firestore()` scan: 36 files, InventorySessionManager.swift = 6, TaskActionService.swift = 30; matches §5.
- "receive no Phase 2 edit" and "verification-only": 0 occurrences in v8.
- `git show --stat d321547` names exactly the four files in §5; v8 L1845 carries the call-site authorization and L2117 the byte-identical statement.
- §14 heading at L2073 is "v8 execution report"; §14.4 at L2111 is "Rule 8 decision packet disposition" (basis for the V8-09 withdrawal).
- V8_INSTRUCTION.md line 22 (Rule 4, "Replace, don't patch") and line 70 (Item 1d, "Update every closed enumeration … and any other") both exist; this is the instruction-level root cause of ledger failure #10 / V8-04.

Arbiter notes on the seven remaining P1s:
- V8-01, V8-02, V8-03 stand on their own text: an unfalsifiable crash-replay fixture (no persisted discriminator between §8.9.1:1042 and §8.9.5:1082), a presentation-order contradiction (§6.6:770 vs §8.9.1:1044/§8.9.3:1058), and a partition rule that the new `absence_retention` branch cannot satisfy (§11.3:1673).
- V8-04, V8-06, V8-07 are ledger failures: §8.9.7 declares a sentence deleted, the sentence survives in place with a `[v8:` marker. V8-04 stems from the Item 1d vs Rule 4 conflict in the instruction; #28 and #33 have no such excuse.
- V8-05 is formal only: §8:1005 does not conflict with §8.9.3 behavior, it conflicts with §8.9:1011's "sole authority" claim. It is a P1 under the owner's sweep rule and Sol's narrowed reading; the owner may reasonably resolve it by narrowing §8.9:1011 rather than deleting §8:1005.
