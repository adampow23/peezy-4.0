# PHASE2 AMENDMENT 4 — Owner adjudication of fourth-pass P1 findings 1–10

Reviewed tuple: `e02ef93867b744ec0ace9c0860ac309cb7e5fc14ee8c4762a265bd544ca2d2ab` / 462,684 bytes / 2,148 lines. The owner read this tuple in full before writing this amendment; findings 1–10 are each confirmed against the cited lines. Apply to `PHASE2_EXECUTABLE_SPEC_v5.md`, update §8.6 with exactly one A4-1…A4-10 mapping, retire the fourth-pass report in §10 with its tuple, then run the next read-only pass. No worktree until zero P0/P1 and hash adoption.

Two scope notes before the findings. **A4-8 is the only boundary change in this amendment**: it adds one new client surface plus its test class to §8.2/§8.4. Every other resolution closes inside the existing authorized paths. **A4-2/A4-3 are a redesign of §5.2's scan mechanics, not a patch** — the seven scans are restored to the same bounded-page pattern phase 0 already uses correctly.

---

## 1. Nonfinite and unencodable sources can never quarantine — adopt.

Confirmed: `payload` validation makes a nonfinite number deterministic `PAYLOAD_INVALID`, but `OriginalEventBytesV1` classifies a nonfinite number as an infrastructure failure, so the digest required for the retry map and the quarantine ID cannot be computed and the counter never increments. The A3-1 quarantine is unreachable for exactly the sources that need it.

The encoder domain is extended, and the residual class is reclassified deterministic:

- `OriginalEventBytesV1` gains three frozen nonfinite double tokens: `['d','nan']`, `['d','inf']`, `['d','-inf']`. These are the only non-hex `['d',…]` forms; the sixteen-hex-digit form remains mandatory for every finite double, including negative zero. All three tokens are reserved and a finite value may never encode to them.
- A genuinely unrecognized SDK runtime type is a deterministic property of the stored document, not a transport fault. It becomes new closed reason code `SOURCE_UNENCODABLE`, appended to the §5.2 reason-code union, with quarantine identity `originalBytesDigest = SHA-256(TaskCanonicalV1({domain:"unencodable_source.v1",source_path,encoder_reason}))` where `encoder_reason` is the fixed encoder-side token. This digest is never presented as an `OriginalEventBytesV1` digest and carries its own domain string so the two can never collide.
- Cycles remain impossible in Firestore-stored data and stay in the infrastructure class; transport, query, transaction, logging, cursor-checkpoint, and lease failures are unchanged.

Fixtures: NaN, `+Infinity`, `-Infinity`, and negative zero at top level, nested in a map, and nested in an array; each reaching `1→2→quarantine` with a stable digest across runs; a changed nonfinite value resetting the counter; `SOURCE_UNENCODABLE` identity stability and its distinct domain; and the reserved-token collision check.

## 2. `limit(1)` starvation on the seven scans — adopt the phase-0 pattern.

Confirmed and structural: each of the seven scans uses literal `limit(1)`, while cursor advancement is specified only "if a page has overflow." A one-result page can never exhibit overflow, so the cursor never advances within a nonempty page. Any head-of-query candidate that deterministically no-ops — a present-but-malformed policy is the exact case the spec itself names as "no-ops in every scan," and it continues to satisfy the status/kind/`fired == false` filters forever — permanently blocks every later task in that lane. This is a starvation defect, not an edge.

The seven scans adopt phase 0's bounded-page mechanics:

- Each scan query gains a Firestore `select()` field mask returning only the fields it filters and orders on, so a page never materializes task bodies. The candidate transaction continues to read the full task by path, exactly as today, so the 655,360-byte single-document proof is unchanged.
- Page shape is frozen at `limit(51)`, select the first 50, maximum concurrency 10, every candidate failure caught independently, all selected candidates settled before checkpoint — identical in structure to phase 0's `limit(101)`/100/10.
- **The cursor advances past every examined candidate, not every mutated one.** A no-op, a validation refusal, and a successful wake all advance identically. Checkpoint writes the 50th examined document's cursor iff the 51st result exists; otherwise it deletes only that scan's cursor and the lane wraps from the beginning on the next run, which is the existing end-of-range rule and is retained verbatim.
- A permanently no-op candidate is therefore re-examined once per wrap and blocks nothing. Phase 2 adds no second quarantine for tasks; the cheap re-examination is accepted and the condition is a named `H57` UNKNOWN-consumer row alongside A3-1's quarantine.

Fixtures: a head-of-lane malformed-policy task with 50 eligible tasks behind it, all 50 processed in one run; the same task still present and still no-op after the wrap; cursor advance on refusal; exact 50/51 boundary; empty page deleting only its own cursor; concurrency-10 independent failure; per-lane cursor isolation; and the existing maximum-task, query-retry, cursor-loss, and same-run high-water cases re-run under the new page shape.

## 3. Four candidates per lane per hour against immediate urgent recovery — adopt, resolved by finding 2.

Confirmed against the master's urgent-recovery requirement: one candidate per lane per 15-minute run is a global cap across all users, not a per-user cap, so urgent-recovery backlog grows without bound at any real user count. The A4-2 page shape raises the seventh scan's floor from 4 to 200 candidates per hour and removes the head-of-lane block that made the practical figure lower still. No separate change is adopted.

Two bounds are frozen with it, because throughput without bounds is the opposite defect: the seventh scan's per-run selected-candidate ceiling is the same 50, and a run that checkpoints a full page leaves the lane's cursor advanced so the next run resumes rather than restarts. Backlog drain is therefore linear and observable. A fixture seeds 500 armed threshold tasks and asserts complete drain across ten runs with no repeat wake, no skipped task, and one wake/intent/attended projection each.

## 4. Near-limit sources fail perpetually before quarantine — adopt.

Confirmed: phase 0 adds `phase0ValidationFailure` to the source document and, on the valid path, copies `payload` verbatim into the high-water map. A source admitted near the 1 MiB document limit can fail both writes as infrastructure failures forever, and the same document can make its own terminalization write unfittable.

- New deterministic reason code `SOURCE_TOO_LARGE`, appended to the §5.2 union. Phase 0 measures the decoded source under `FirestoreWriteBudgetV1` before any mutation and requires frozen headroom of 16,384 bytes above the larger of the retry-map write and the terminal write. Insufficient headroom is `SOURCE_TOO_LARGE`.
- New deterministic reason code `PAYLOAD_TOO_LARGE` for a payload whose copy into the high-water advance map would exceed that map's `FirestoreWriteBudgetV1` charge. The high-water write is never attempted speculatively.
- Both codes **quarantine on first occurrence**: the transaction writes the bounded quarantine record with `failureCount:3` directly and attempts terminalization in the same transaction. If the terminal write itself cannot fit, the quarantine record alone commits, the source is left `pending`, and the scan proceeds — idempotent by quarantine ID on every later wrap, blocking nothing. No oversize source is ever retried three times to reach a conclusion already known deterministically on the first read.
- `FirestoreWriteBudgetV1` is extended to cover the phase-0 source retry write, the phase-0 terminal write, the quarantine record create, and the high-water advance write. These join the §7.4 registry and the independent rules-emulator oracle.

Fixtures: a source at exactly the headroom boundary and one byte over; a payload at and over the high-water budget; first-occurrence quarantine with and without a fittable terminal write; idempotent re-quarantine across wraps; and non-blocking progression of the remaining page in every case.

## 5. Terminal-child replay contradicts reconfirmation of a progressed child — adopt: revisions are initialized, never matched.

Confirmed contradiction. §4.6's terminal child-reuse rule requires an existing policy child to match "all three root revisions," which for a created child are literal `0`, while the same section's mandatory RED case requires "undo→reconfirm after untouched/**already-progressed** child" to succeed. A child that has been worked has a nonzero `flowWriteRevision` and can never satisfy both.

The rule is corrected to the one §4.6 already states for generic t2 reuse, made universal:

- `flowWriteRevision`, `notesWriteRevision`, and `quotesWriteRevision` are **create-time initializers and are never members of any reuse, replay, or reconfirm match set** — not for generic t2 reuse, not for terminal `t3_` child reuse, not for the frozen `terminal_spawn_closure` reconfirm branch.
- The child match set is exactly the immutable set: document ID, catalog task ID, `task_instance_id`, `task_generation_epoch`, complete `spawnedFrom` provenance including the conditional move member, policy fingerprint, and — for the policy-absent branch — `legacy_immutable_projection_hash`. Any live progress must instead be structurally valid under §5.5 and is preserved byte-for-byte, never rewritten and never matched.
- The same correction applies to the sentence in §4.6 requiring an existing legacy child to match "its legacy immutable identity/provenance and policy absence": that set is already correct and gains no revision member.

Fixtures: reconfirm after a child reaches nonzero flow, notes, and quotes revisions independently and together; reconfirm after a child holds a live handoff/tail; collision still aborting on an immutable mismatch; and an explicit negative asserting that no reuse path reads a revision field.

## 6. Second destructive reset from a losing scene — adopt, without editing the coordinator.

Confirmed. §4.4's guarantee — "a losing scene retaining `e` always addresses the old active record or tombstone" — holds only if the scene actually retains `e`. The registry stores the captured epoch at `beginOrResume`, but the local record is removed once application completes, and `RetakeAssessmentCoordinator.swift:55` persists only an operation ID before an intervening await. A scene that resumes after reset 1 fully completes finds no record, captures the now-current root epoch `r`, and legitimately addresses record `r+1`. The spec then excludes the coordinator from modification, so the hole cannot be closed where it originates.

It does not need to be. The coordinator already persists the one durable value required — the operation ID — so the fix is closed on both sides of the wire without touching it:

- **Server, `functions/taskPlan.js` (S2):** `resetAllTasks` reads the caller alias against the complete permanent per-UID tombstone set before consulting root state. A caller alias already recorded in **any** prior epoch's tombstone `aliases[]` returns that tombstone's reconstructed final receipt with `replayed:true` and performs zero destructive mutation, regardless of the request's expected epoch. Tombstones are already permanent and already carry the alias list, so this adds a read, not a schema. An intentional later reset generates a new `ResetAliasV1` at `beginOrResume` and is unaffected.
- **Client, `TaskPlanService.swift` (S1):** `ResetOperationRegistry` retains a bounded per-UID completed-alias set that outlives record removal — exact `{alias,canonicalOperationId,taskGenerationEpoch,finalReceiptDigest,completedAt}`, capped at eight and evicted oldest-first, inside the existing `PeezyTaskPlanReset-v2.json` envelope. `beginOrResume` returns the completed entry rather than a fresh PREPARED when the supplied suggestion matches it, and never dispatches.
- **No edit to `RetakeAssessmentCoordinator.swift`** and no change to §8.2. The existing sentence asserting no coordinator edit is required is retained and is now true rather than assumed.

Fixtures: losing scene arriving after full completion and record removal, with and without the local completed-alias entry present; alias replay across app reinstall where only the server belt exists; intentional second reset with a fresh alias succeeding to epoch `r+1`; alias cap eviction followed by server-belt catch; and an assertion that no path can produce two rotations from one user gesture.

## 7. Supersede presentation contradicts the master — adopt, with a date field and an owned surface.

Confirmed on both halves. The frozen contract copy is the static string "Replaced by an updated task," while the master requires "Replaced — [date]," a brief undo, then history collapse; and no §8.2 owner holds a dated-undo or history-collapse surface, so under fail-closed neither exists.

- The `SUPERSEDED` contract becomes exact `{schema_version:1,terminal_kind:"superseded",superseded_by,superseded_at,visible_status_copy:"Replaced",visible_status_detail:{kind:"DATE",at:superseded_at}}`. `superseded_at` is server-authored from the confirming transaction's single concrete commit time under `CallableTimestampWireV1`. The visible string set stays contract-owned; the client holds exactly one frozen interpolation — `"{visible_status_copy} — {localized short date of visible_status_detail.at}"` — and renders `visible_status_copy` alone when the detail member is absent or malformed. No other contract gains a detail member in Phase 2.
- `RETIRED` is unchanged at "Plan updated"; internal retirement is not a user-facing replacement and takes no date.
- The undo affordance is specified into **S4**'s existing `TaskDispositionSurface.swift`: it renders on the superseded original exactly while `confirmation_undo_used == false` and `now < first_confirmation_undo_until`, invokes only `undoConfirmation`, disappears on success, expiry, or a `TRIGGER_INVALID` descriptor, and is never rendered from a stale snapshot. The five-minute window and its server authority are unchanged.
- History collapse is specified as presentation only: the surface shows the newest retained `planChangeHistory` rows and renders any `ROLLUP` row as one collapsed line carrying its count and time span. It never reads, expands, or re-derives rolled-up rows, and there is no client write.

Fixtures: exact contract bytes with and without the detail member; the single interpolation with a malformed/absent date falling back to the bare string; undo visible/expired/used/post-success; undo against a stale instance rejected with the descriptor; and rollup rendering with 0, 1, and repeated rollups.

## 8. `CORRUPT_BLOCKED` has no recovery owner — adopt, and extend the boundary by one surface.

Confirmed and the most consequential of the ten. §3.3 forbids every callable, opener, presentation, callback, and synthesized empty store until an explicit local recovery validates, item-recovers, or discards the quarantined envelope after showing its pending-record count — and no §8.2 path owns that recovery. A corrupt handoff, route, reset, or workflow envelope therefore wedges its subsystem permanently with no user-reachable exit.

**This is the one authorized boundary extension in Amendment 4.** §8.2 gains, under **S4**: new `Peezy 4.0/Tasks/Durable/DurableStoreRecoveryCoordinator.swift` and new `Peezy 4.0/Tasks/Durable/DurableStoreRecoveryView.swift`. §8.4 gains new `Peezy 4.0Tests/DurableStoreRecoveryTests.swift`, owned by S4. §8.3 records the ordered integration: S4 owns the coordinator and surface and integrates it at `AppRootView.swift`, which S4 already owns; **S7** is the ordered follow-on for route-ingress gating and contributes its cases without editing S4's files. No other path is added and no excluded path is opened.

Normative behavior:

- The coordinator is the single reader of all four actors' blocked state. It never touches files; each actor exposes an immutable blocked snapshot `{target,quarantinePresent,pendingRecordCount:Int?,decodable:Bool}` and performs any mutation itself.
- While any actor is blocked, the surface presents before any dispatch, opener, or automatic presentation for that subsystem, and states the pending-record count exactly when the quarantined envelope is decodable and states its absence when it is not. It never invents a count.
- Two actions only: **recover**, which asks the owning actor to validate and item-recover the quarantined envelope into a new generation, and **discard**, which requires an explicit confirmation naming the count and removes only the exact named target and quarantine files. Neither action is defaulted, automatic, timed, or reachable from a notification tap.
- Recovery failure re-enters blocked without overwriting either file. Partial item recovery reports items recovered and items dropped. An unblocked subsystem is unaffected; one blocked actor never gates another's dispatch.

Fixtures: each of the four targets blocked independently and together; decodable and undecodable quarantine; count exactness; recover-success, recover-failure, partial recovery, and explicit discard; zero dispatch while blocked and immediate dispatch after recovery; no auto-presentation from a route while blocked; and the existing crash-boundary matrix re-run with the surface mounted.

## 9. `set -e` aborts on `git diff` exit 1 — adopt a frozen normalizer.

Confirmed. §9.4 step 4's scaffold sets `set -euo pipefail`; §9.3 line 2006 requires `git diff --no-index --check /dev/null` per new path and §9.4 step 7 requires `git diff --binary --no-index /dev/null` per new path. Both return status 1 whenever a difference exists, which is the success case for a new file. Step 7's prose "exit 1 means differences, not failure" states the intent but freezes no conditional, so execution aborts at the first new path.

One helper is frozen and is the only permitted invocation form at every `git diff` site in §9.3 and §9.4:

```sh
phase2_git_diff() {
  set +e
  git "$@"
  phase2_rc=$?
  set -e
  if [ "$phase2_rc" -gt 1 ]; then
    return "$phase2_rc"
  fi
  return 0
}
```

Status 0 and 1 are success; 2 and above propagate as failure and stop the run. The helper is defined once in the step-4 scaffold, before any diff site. It applies to `--check` and `--binary` forms, tracked and `--no-index`, and to nothing else — `git apply --check`, `git cat-file -e`, and every guard assertion keep their exact current status semantics. Nothing in the helper touches the `File.txt` guards or the EXIT trap.

Fixtures, recorded as the future integration transcript's required assertions: a new path producing status 1 and continuing; a tracked path with no change producing 0; an induced status-2 failure stopping the run; and the complete manifest surviving one new path at first, middle, and last position.

## 10. Evidence root set omits H54 pointers — adopt, plus the invariant that prevents recurrence.

Confirmed. The §2.3 rooted closure enumerates milestone, trigger, deadline, waiting-entry, waiting-fallback, contradiction, external-submission, wake, resolution, active-handoff, and retained **interaction**-history evidence IDs. It does not name `confirmation_attempts[].source.evidence_id`, `confirmation_attempts[].confirmation_evidence_id`, the `evidence.amendment_confirmation.v1` record created by A3-3, or `evidence_ids` on retained `planChangeHistory` rows — a history that is separate from interaction history. Those records are therefore nonroot, are eligible for the evidence rollup, and can be rolled away while live pointers still reference them, breaking confirm, undo, reconfirm, and recap with `EVIDENCE_UNKNOWN`.

- The rooted set `R` is extended to include, with their complete typed dependency chains: every `source.evidence_id` and every `confirmation_evidence_id` on every retained `confirmation_attempts` entry; the `evidence.amendment_confirmation.v1` record on the original instance; and every member of `evidence_ids` on every retained non-rollup `planChangeHistory` row. `planChangeHistory`'s own 15-row-plus-rollup fit runs before the evidence fit, in the same order the interaction history already uses, and a rolled-up plan-change row ceases to root only after all prospective checks succeed.
- **The invariant, which is the actual fix.** Structural validation enumerates every persisted field whose value is an evidence ID — by schema, not by hand-maintained list — and asserts that each such live pointer resolves inside `R`. A future field that stores an evidence ID without a corresponding root entry fails validation at build time rather than silently at rollup time. This class of finding has now appeared twice; the enumeration closes it once.
- A rollup remains never a dependency edge and never a root. If the extended `R` plus the newest history rows cannot fit the 128-record/131,072-byte caps, that specific fresh mutation is rejected before writing, unchanged from the current rule.

Fixtures: thousands of successive mutations across a full H54 cycle with both attempts present, asserting every confirmation and plan-change pointer resolvable at every step; rollup pressure that would previously have consumed a confirmation record; undo and reconfirm after maximum rollup; the schema enumeration failing on an injected unrooted pointer field; and cap rejection with the extended root set.

---

## Process note recorded with this amendment

The reviewed tuple is 462,684 bytes against 311,917 at the first pass — 48% growth while the finding count went 21 → 8 → 9 → 10. Three of these ten (1, 4, 10) are consequences of Amendment 3's own additions. That is the condition the owner named last round as the trigger to stop amending blind, which is why this amendment follows a complete owner read of the frozen bytes rather than the findings alone.

Two of the ten (2, 5) are contract contradictions the earlier passes should have caught, and one (3) is a capacity defect against the master. All three are resolved here at the contract level rather than patched. If the fifth pass returns any finding that is architectural rather than fixture-grade, the correct next action is a scoped rewrite of the implicated section, not a fifth amendment.
