# READ-ONLY ADVERSARIAL REVIEW — PHASE2_AMENDMENT_4

You are reviewing an **owner adjudication document before it is applied** to a frozen executable specification. This is a pre-application gate, not a review of the specification itself. Your job is to find every way this amendment fails to close its findings, contradicts the spec it will be applied to, introduces a new defect, or cannot be implemented against the actual codebase.

Make no edit to any file. Produce findings only.

---

## 1. Why this gate exists

The specification has been through four read-only adversarial passes: 21 → 8 → 9 → 10 P1 findings, zero P0 throughout. Three of the ten findings in the fourth pass were caused by the third amendment's own additions. Amendments are generating roughly a third of the next round's findings, so amendments are now reviewed before application rather than after.

Your findings are cheapest here. A defect you catch in this document costs one edit. The same defect caught after application costs a full apply-and-review cycle.

## 2. Authority

In descending order. Lower authority never overrides higher.

1. `PEEZY_STATE.md` — project state, outranks all documentation and all memory.
2. `INSTITUTION_FLOWS_MASTER_v3.md` — the locked product contract the software must satisfy.
3. Committed source at `b4b047d29bea6a1721729b69e0d01aa7a1dc9923` on `main`.
4. `PHASE2_PLAN.md` as amended by `PHASE2_AMENDMENT_1.md` through `PHASE2_AMENDMENT_3.md`.
5. `PHASE2_EXECUTABLE_SPEC_v5.md` at the frozen tuple below.
6. `PHASE2_AMENDMENT_4.md` — **the document under review. It has no authority yet.**

## 3. Frozen artifacts

Verify these before beginning. A mismatch means you were given the wrong bytes; stop and say so rather than reviewing.

| Artifact | SHA-256 | Size |
|---|---|---|
| `PHASE2_EXECUTABLE_SPEC_v5.md` | `e02ef93867b744ec0ace9c0860ac309cb7e5fc14ee8c4762a265bd544ca2d2ab` | 462,684 bytes / 2,148 lines |

`PHASE2_AMENDMENT_4.md` is the document under review and is not hash-pinned.

## 4. The ten findings this amendment must close

Reproduced verbatim so this packet is self-contained. Do not assume any other version of them.

1. Nonfinite payload values are deterministic `PAYLOAD_INVALID`, but their digest encoding is classified as infrastructure failure, so NaN/±Infinity can never reach the three-failure quarantine. (spec:1276, spec:1278)
2. Each scheduler query uses `limit(1)`, while cursor advancement requires detecting overflow — which a one-result query cannot observe. A stable first no-op/error can starve later tasks. (spec:1286, spec:1290)
3. One global candidate per lane per 15-minute run limits throughput to four tasks/hour, leaving urgent-recovery backlog unbounded against the master's immediate-recovery requirement. (spec:1286, master:51)
4. Phase-0 accepts near-limit source documents but adds retry/terminal fields and may copy the full payload into high-water state without reserving document/index headroom. Such sources can fail perpetually before quarantine or advancement. (spec:1276, spec:1280, spec:1284)
5. Terminal-child replay requires all three revisions to match their initial zero values, but reconfirmation must preserve a child that has already progressed. The two contracts cannot both be implemented. (spec:1145, spec:1147, spec:1159)
6. A losing reset scene can reach `TaskPlanService` after the first reset completes, capture the new epoch, and start a second destructive reset. The current coordinator persists only an operation ID before an intervening await, while the spec excludes it from modification. (spec:1073, spec:1079, coordinator:55)
7. Confirmed-amendment presentation freezes "Replaced by an updated task," but higher authority requires "Replaced — [date]," brief undo, then history collapse. The dated undo/history UI has no exact mapper or surface contract. (master:103, spec:448, spec:580)
8. `CORRUPT_BLOCKED` requires explicit recovery or confirmed discard, but no authorized UI path owns that recovery surface, pending-count presentation, or confirmation behavior. Corrupt route/handoff/reset/workflow stores can remain permanently wedged. (spec:760, spec:1435)
9. The future worktree shell enables `set -e`, yet mandatory `git diff --no-index` checks and new-file patch generation return status 1 when differences exist. No frozen conditional normalizes that success case, so execution stops at the first new file. (spec:2006, spec:2018, spec:2089)
10. The evidence-compaction root set omits H54 confirmation-attempt and retained plan-change-history evidence IDs. Those records can be rolled away while live pointers remain, blocking undo/reconfirm/recap. (spec:260, spec:540, spec:553)

## 5. What to ask of every resolution A4-1 … A4-10

Answer all six for each. Silence on a question is not a pass.

1. **Closure.** Does the resolution actually close the finding, or only the example the finding used? Name the residual case if one survives.
2. **Contradiction.** Does it contradict any other frozen text in the spec — a schema, a cap, an ordering rule, a test list, a §8 ownership row, a §8.6 register entry? Cite spec line numbers.
3. **New defect.** Does it introduce a race, starvation, unbounded growth, a fail-open path, a lost write, a wedge, or an evidence/identity ambiguity that did not exist before? This is the highest-value question — three of the last ten findings were amendment-induced.
4. **Implementability.** Can it be built against the committed source at `b4b047d`? Name the file and line that makes it possible or impossible.
5. **Determinism and fail-closed.** Does every new value, code, digest, cap, and page bound have exactly one frozen definition, and does every unlisted case fail closed?
6. **Test adequacy.** Do the named fixtures actually discriminate the resolution from the defect, or would they pass against the broken behavior too?

## 6. Load-bearing assumptions — verify these against the codebase first

These are the points where the amendment's author had incomplete information. If any is false, the resolution built on it fails. Report each as `CONFIRMED` or `CONTRADICTED` with file:line evidence.

- **LB-1 (A4-6).** `RetakeAssessmentCoordinator.swift` durably persists a reset operation ID *before* the intervening await, and that same identifier is what reaches `TaskPlanService.beginOrResume` as `suggestedOperationId` on a resumed scene. The entire finding-6 resolution depends on this. If the persisted value is not stable across the await, across relaunch, and across the completion of a prior reset, the fix does not close the ABA and the coordinator must enter scope after all.
- **LB-2 (A4-2).** The Firebase Admin SDK version pinned in `functions/package.json` supports `Query.select()` field masks on `collectionGroup` queries, and a `select()` projection query is compatible with the composite indexes frozen in §7.4 and `firestore.indexes.json`. If `select()` forces an index change, the amendment's index registry claim is wrong.
- **LB-3 (A4-2/A4-3).** Page size 50 with concurrency 10 fits the deployed function's memory and the scheduler's timeout budget, given that each candidate transaction may read a task up to 655,360 bytes. Name the configured memory/timeout for `evaluateDispositionTriggers`.
- **LB-4 (A4-6).** The reset tombstone already retains a per-UID `aliases[]` list that is permanent and readable before root-state consultation, so the server-side alias check adds a read and no schema change. Confirm against `functions/taskPlan.js`.
- **LB-5 (A4-6).** The `PeezyTaskPlanReset-v2.json` envelope has capacity for a bounded eight-entry completed-alias set within its per-store cap.
- **LB-6 (A4-7).** Adding `superseded_at` and `visible_status_detail` to the `SUPERSEDED` contract does not break the existing shared mapper or `dispositionContract.js` validators for clients that do not know the members, and does not exceed any frozen contract cap.
- **LB-7 (A4-8).** No existing view or coordinator already owns corrupt-store presentation under another name, and mounting the new surface at `AppRootView.swift` genuinely precedes every dispatch path for all four durable actors — route, handoff, reset, workflow.
- **LB-8 (A4-10).** The schema enumeration of evidence-ID-valued fields is mechanically derivable from the frozen schemas rather than requiring a hand-maintained list. If it cannot be derived, say so — the invariant is the point of the resolution.

## 7. Additional scrutiny on the two structural items

**A4-2/A4-3 — scheduler scan redesign.** This is not a patch; it changes the mechanics of all seven scans. Check specifically: does advancing the cursor past *examined* rather than *mutated* candidates ever skip a task that should have fired and never return to it? Does the wrap rule still guarantee eventual examination of every eligible task? Do the seven per-lane cursors remain independent? Does a page of 50 change any transaction-size, index-entry, or write-budget proof in §4.6/§7.4? Does the threshold lane's drain rate now satisfy the master's urgent-recovery requirement, or only improve it?

**A4-8 — the boundary extension.** This adds two client files and one test class to §8.2/§8.3/§8.4. Check that the addition is minimal and necessary, that S4 ownership does not collide with S5's handoff actor or S7's route ingress, that the ordered-integrator ledger stays acyclic, and that no excluded path is opened as a side effect. If a smaller closure exists inside the current boundary, name it.

## 8. Severity

- **P0** — the amendment, if applied, would produce data loss, a destructive double-mutation, a security or rules regression, a permanently wedged subsystem, or a violation of the institution master's product contract.
- **P1** — a finding is not actually closed; a contradiction with frozen spec text; a new race, starvation, or unbounded growth; an unimplementable resolution; an undefined or non-deterministic value; a fixture that cannot discriminate.
- **P2** — clarity, redundancy, or naming. Report separately and briefly; P2 does not block.

## 9. Output format

Lead with the counts:

```
P0: <n>   P1: <n>   P2: <n>
LB-1..LB-8: <CONFIRMED|CONTRADICTED each>
```

Then one block per finding:

```
[P0|P1|P2] <A4-n or NEW> — <one-line title>
Evidence: <file:line, plural>
Problem: <two or three sentences, concrete>
Consequence if applied: <what breaks, for whom>
Suggested closure: <one or two sentences; optional>
```

Then, only if you have zero P0 and zero P1, state exactly: `AMENDMENT 4 IS SAFE TO APPLY AS WRITTEN.`

## 10. Prohibitions

- Do not edit, stage, commit, build, run tests, seed, deploy, call a production service, or touch Build 25 WIP.
- Do not re-review the executable spec at large. Findings outside the ten resolutions are in scope **only** where the amendment creates or worsens them; mark those `NEW`.
- Do not restate agreement, summarize the amendment back, or rank the findings by how well written they are. Findings only.
- Do not propose a rewrite of the amendment. Propose closures at the point of defect.
- If you cannot verify something because you lack the file or the access, say `UNVERIFIED` and name what you needed. Do not guess and do not treat absence of evidence as confirmation.
