# PHASE 2 — Audited replacement blueprint (v5, adopted)

Status: **OWNER-ADOPTED REPLACEMENT FOR v4 (2026-09-01).** The owner adopted this blueprint as the sole root Phase 2 plan, including its expanded file/server boundary, support deferral, and §5.1 spec-authoring gate. Adoption authorizes only the documentation and read-only review work in §5.1 until the owner separately adopts a zero-P0/P1 executable-spec hash. It does not authorize a Phase 2 worktree, implementation, seed, deploy, production-connected test, StoreKit action, remote write, FCM send, or claim of production behavior.

Frozen audit baseline:

| Input | Frozen value |
|---|---|
| Git baseline | `b4b047d29bea6a1721729b69e0d01aa7a1dc9923` |
| `PEEZY_STATE.md` | `d0262ff30773e7c778952d6207683d564bde2175` |
| Locked institution master | `ef98d2aa52ea0401706b743d69713ef3526c46f8` |
| Phase 2 v4 plan | `28e4c38a9f8e9efbd8c51958805e4a59756fc2da` |
| v4 gate/inventory report | `98b101c36ae2308e77472d42ab1cb350e2634ed0` |

Authority remains: `PEEZY_STATE.md` → locked `INSTITUTION_FLOWS_MASTER_v3.md` → live code at the frozen baseline → this plan. The current `PHASE2_BUILD.md` bytes are an immutable hashed audit annex; v5 must never overwrite that user artifact. If v5 is adopted, its execution report is a new `docs/plans/PHASE2_BUILD_v5.md` that references the annex hash and does not change the protected root-document manifest.

## 1. Audit verdict

v4 should not be repaired by adding one more action and rerunning the same gate. Its repeated stops are symptoms of a larger problem: the plan freezes implementation scope before it defines the policy, evidence, and producer for every state the UI promises.

| v4 problem | Evidence | v5 correction and reason |
|---|---|---|
| The repository has a root v4 plan and a different nested v1 plan, so “the Phase 2 plan” is not a unique artifact. | `PHASE2_PLAN.md:1`; `Peezy 4.0/PHASE2_PLAN.md:1` | An adopted executable spec must declare the root plan as sole authority by path and hash. The nested user draft remains byte-untouched unless the owner separately authorizes moving or deleting it. |
| The plan added one missing edge per round, then claimed complete coverage. | `PHASE2_PLAN.md:3-7`; `PHASE2_BUILD.md:27-40` | Freeze the complete semantic command/outcome matrix before implementation. The client sends semantic outcomes; the server selects the status/contract pair. |
| “Get help from a person” has no task transition, accepted work record, backed SLA, or graph resolution. | `PHASE2_BUILD.md:436-493`; `functions/index.js:105-205`; `SupportChatService.swift:103-188` | Remove `SUPPORT_ACTIVE` from Phase 2 and require a separately approved support/operations phase. Opening Chat alone preserves the prior owned disposition. |
| A4 requires persistence before an external CTA, but v4 has no truthful pre-open writer. `markSelfHandling` means “outside Peezy,” not “following Peezy’s route.” | Master `:64-76`; v4 `:28-29` | Add a distinct `beginHandoff` semantic command and await it before opening the external app. |
| “Sent” and “Got what I needed” cannot be mapped by label; completion depends on required milestones. The current contract retains only `profile_version`. | Master `:38-55`; `functions/dispositionContract.js:86-91` | Add a pinned, versioned outcome/completion policy and server-owned milestone state. `resolveHandoff` applies policy and completes only when every required milestone is closed. |
| The row model lacks contradiction evidence, eligible events, legal-deadline evidence, amendment anchors, wake evidence, and outcome policy. | `PeezyCard.swift:45-143,146-232`; mapper `:112-138` | Add one immutable `taskInteraction` capability policy plus separate server-owned dynamic evidence. Unknown or incomplete policy fails closed. |
| Phase 3 cannot be “data plus flows” because all task producers use fixed projections and v4 forbids changing them. | `TaskGenerationService.swift:234-278,354-388`; `spawnTasks.js:295-328`; `seedTaskCatalog.js:101-168` | Phase 2 installs the validator and every propagation seam without changing active catalog data or running a seed. Phase 3 supplies data and performs the separately approved backfill/regeneration. |
| `assignOwner` accepts a label while household rosters, membership, visibility, and sharing are deferred. | v4 `:28,48`; Master `:93-105` | Remove it from Phase 2. The capability stays hidden until a canonical household-member authority and task-share policy exist. Free text is not ownership. |
| The v3/v4 global move-date estimate is not valid evidence for every task and can violate the legal-trigger rule. | Master `:50-51,78` | Trigger candidates are policy-driven. A move anchor appears only when that exact task policy declares it consequential and supplies the protected-outcome derivation. |
| H55 only wakes `Snoozed/DEFERRED` and then removes the trigger, so waiting/user-action triggers never fire and urgent grouping loses its evidence. | `dispositionTriggers.js:146-168,237-250,320-345` | Split firing behavior by disposition and persist server-owned `wakeEvidence`; a new disposition clears it. Urgent recovery requires a declared hard/safe threshold. |
| The plan offers an event that no A11 publisher emits. No production code currently writes `users/{uid}/events`. | Master `:139-164`; `dispositionTriggers.js:269-345` | Event choices are hidden unless the pinned task policy names an actual A11 event publisher/key. The client submits an eligible-event ID; the server resolves the canonical tuple/high-water mark. |
| “Known closed” CTA behavior has no verified hours/timezone producer. | `ProviderDirectoryService.swift:13-53` | The shared component supports optional verified hours, but never claims an office is closed without that data. |
| `TaskRowHeader` is listed as unfinished even though contracted rows already render `visibleStatusCopy`. | `TaskRowHeader.swift:66-114` | Remove that implementation item; retain regression coverage only. |
| Notification intents are inert under the no-deploy/no-FCM constraint, while v4 couples them to the core UI. | State H17/H43/H45; v4 `:32,46` | Keep a server-only idempotent outbox as an independent source slice and typed route contract. No sender, client query, or delivery claim is in Phase 2. |
| “Zero loss,” real cold-start push, kill/relaunch, backed SLA, legal correctness, and pixel identity cannot be proved by the named unit/no-UI envelope. | v4 `:52-61`; gate report `:529-617` | Divide acceptance into local automated, manual OS, and operational/deployed-unknown evidence. Source completion does not claim the latter two. |

## 2. Revised outcome and definition of done

Phase 2 is complete when the source contains locally verified, fail-closed shared infrastructure for policy-backed dispositions, row surfaces, external handoffs/outcomes, trigger firing/evidence, typed task-intent routes, bounded scene flushing, notification outbox records, and truthful research posture.

Phase 2 does **not** activate these capabilities on existing tasks. A genuinely pre-policy task with no `taskInteraction` stays on today’s legacy path. Non-policy-eligible synthetic packing/readiness tasks also remain legacy by design. Any task on which `taskInteraction` is present but partial, malformed, unknown-version, or fingerprint-invalid is read-only/passive and never falls back to client-writable legacy actions. After an eligible catalog row gains a policy, rules require every owner-created task for that row to copy it exactly; omission is denied. This is the safety boundary that lets source work finish without a seed or a speculative mapping.

Phase 3 may be data plus entry flows only for the capabilities implemented here. It must still perform a separately approved Admin backfill/reset/regeneration for existing task documents because task generation is intentionally add-only. Household roster ownership, unsupported A11 publishers, and any capability explicitly deferred below remain later code, not “data only.”

No Phase 2 completion claim includes a deployed function/rule/index, an FCM/APNs delivery, an operational support response, live legal/research correctness, or OS-guaranteed persistence.

## 3. Architecture constraints for the executable-spec freeze

### 3.1 Immutable policy: `taskInteraction`

`taskInteraction` is an optional catalog-owned map copied by canonical Firestore-value equality onto the user task at creation. It contains policy and capability metadata only. v1 freezes these enums instead of leaving generic `enum`/`effect` placeholders:

```text
taskInteraction {
  schema_version: 1,
  policy_version: integer,
  policy_fingerprint: string,
  capabilities: [ALREADY_HANDLED|NOT_APPLICABLE|DEFER|SELF_HANDLE|
                 WAIT_EXTERNAL|HANDOFF],
  case_key_policy: { subject_kind, subject_id_field, institution_id_field?, task_type },
  milestone_profiles: [{ id, resolver_id, milestone_ids[], companion_ids[] }],
  milestones: [{ id, label, subject_scope, evidence_rule_id }],
  waiting_transitions: [{ code, owner_rule, expectation_template_id,
                          trigger_policy_id, external_submission_effect,
                          evidence_rule_id }],
  handoffs: [{ id, kind: CALL|PORTAL|WEB|MAIL|MAP|SHARE,
               presentation_mode: EXTERNAL_APP|IN_APP_SHEET|SHARE_SHEET,
               expected_action, outcome_policy_id, trigger_policy_id }],
  outcome_policies: [{ id, prompt_kind: CALL|PORTAL|WRITTEN_NOTICE|WAITING|GENERIC,
                       outcomes: [{ id, label,
                         effect: COMPLETE_MILESTONES|WAIT_EXTERNAL|
                                 CONTINUE_USER_ACTION|DEFER|REQUIRES_RESOLVER,
                         milestone_ids?, transition_code?, resolver_id? }] }],
  trigger_policies: [{ id, allowed_sources, safe_threshold?, hard_threshold?,
                       move_anchor_derivation?, eligible_event_ids[] }],
  eligible_events: [{ id, event_name, canonical_key, publisher, evidence_rule }],
  completion_policy: { kind: ALL_PROFILE_REQUIRED_MILESTONES },
  not_applicable_policy?: { reason_codes[], contradiction_evaluator_id,
                             resolver_id },
  deadline_policy?: { evidence_rule_id, display_rule },
  plan_change_policy?: { replacement_policy_ids[], amendment_profile_id }
}
```

Rules:

- Capabilities derive from a complete typed policy; independent booleans never enable UI.
- Unknown schema/enum, fingerprint mismatch, partial policy, or missing required policy disables that capability.
- `policy_fingerprint` is `p2i1_` plus 64 lowercase hexadecimal characters: SHA-256 over the UTF-8 canonical JSON policy with the `policy_fingerprint` member omitted. It is never self-referential.
- Canonicalization recursively sorts UTF-8 map keys, preserves array order, normalizes timestamps to UTC ISO-8601 with exactly milliseconds, rejects blank keys, duplicate IDs, undefined, binary values, nonfinite/unsafe numbers, numeric type ambiguity, and strings over the fixture bounds, and preserves string/Boolean/null value types. The complete policy is capped at 64 KiB canonical UTF-8. Shared JS/Swift fixtures must produce the same bytes and hash. “Byte-identical” is not claimed for Firestore serialization.
- Every referenced milestone/profile/transition/handoff/outcome/trigger/evidence/resolver ID must resolve exactly once inside the policy or a frozen server registry named by the executable spec. Unknown and dangling references invalidate the whole capability; clients never invent a transition or evidence rule.
- After creation, the task’s immutable, self-consistent policy copy is the pinned authority. A later catalog reseed must not silently invalidate an in-flight task. Fresh semantic operations validate the pinned canonical bytes/fingerprint and version; a deliberate migration must name the prior/new fingerprints and supersede or reconcile state explicitly.
- Owner task creation must copy the exact catalog map whenever that eligible catalog row has one; an old/malicious client may not omit it. Later client add/change/remove is denied. Rules compare the requested map with `taskCatalog/{taskId}`. To stay below Firestore's multi-document rule-access budget, `TaskGenerationService` changes from its current up-to-499 transaction to resumable, idempotent chunks of at most **8** creates; even without cache credit, one user-root reset check plus one catalog read per row is at most 16 document accesses. A 53-row emulator fixture, a reset between chunks, retry, and partial-failure recovery are mandatory RED cases. Admin-created spawned tasks use the same canonical validator. Only eligible catalog tasks that predate that row's policy activation may remain absent/legacy; explicitly noneligible synthetic tasks are the separate exception above.
- A policy-bearing owner create additionally requires canonical `documentId == id == taskId`, immutable bounded identity/provenance fields, and an eligible catalog row. Subject-aware/reserved/spawned identities remain server-created. Copying a valid policy onto an arbitrary duplicate document is denied.
- Catalog rows whose owner-created documents synthesize assessment-derived `flowRows` are not policy-eligible in Phase 2: rules cannot prove those derived bytes without moving their producer server-side. The seeder validator rejects `taskInteraction` on a `rowGeneration` row, and Phase 3 may not activate it there. Those rows remain on the legacy path until a separately scoped authoritative row-materialization design; this is an explicit exception to the “Phase 3 is data-only” claim.
- Admin/test generators bypass rules, so Phase 3 activation must first retire or update root/functions `diagnose-and-generate.js` and `functions/testProfile/seedTestUser.js`; running them against an activated target is forbidden until they use the canonical validator. Phase 2 does not authorize or execute them.
- Phase 2 changes the seeder projection/validator but does not modify `taskCatalogData.json` and does not run the seeder.

### 3.2 Mutable state and evidence

Mutable data does not live inside `taskInteraction`:

```text
taskInteractionState {
  policy_version,
  policy_fingerprint,
  interaction_epoch,
  interaction_revision,
  case_key: { move_event_id?, subject_kind, subject_id,
              institution_or_account_id?, task_type },
  milestone_profile: { id, resolver_id, resolved_from_evidence_ids[] },
  required_milestones: [{ id, subject_key,
                          state: OPEN|COMPLETED|NOT_REQUIRED,
                          evidence_id?, not_required_reason?, not_required_source? }],
  companion_milestones: [{ id, subject_key, state, evidence_id? }],
  contradiction: { state: none|present|unknown, evidence_ids[] },
  deadline_evidence?,
  amendment_anchor?,
  evidence_records: [{ id, kind, producer, source_ref?, source_version,
                       observed_at, facts }]
}

activeHandoff {
  schema_version, session_id, interaction_epoch,
  state: prepared|open_requested|opened|returned|resolved|cancelled,
  action_id, handoff_kind, expected_action, outcome_policy_id,
  started_at, state_updated_at, resume_destination,
  prior_dynamic_snapshot_id, presentation_snapshot
}

wakeEvidence {
  schema_version, wake_id, original_trigger, fired_at, event_high_water?,
  resume_destination, urgency: normal|urgent_recovery, intent_id?
}

resolution {
  reason_code, policy_version, evidence_version?, resolved_at
}

interactionHistory[] {
  operation_id, interaction_epoch, revision_before, revision_after,
  command, redacted_effect, evidence_ids[], external_submission?, occurred_at
}
```

Absent `interaction_epoch` and `interaction_revision` mean zero. `interaction_epoch` is the stable semantic-thread identity. It advances when the semantic thread is replaced or restored: every fresh disposition, `beginHandoff`, `cancelHandoff`, outcome resolution, H54 transition, and policy migration. Open acknowledgement/return and scheduler wakes do not advance it. `interaction_revision` is the optimistic state version and increments on every successful semantic command or scheduler mutation. Unsubmitted client drafts bind to epoch + revision + policy fingerprint and invalidate on any change. An active handoff binds to session ID + its opening epoch + policy fingerprint, so an unrelated scheduler revision cannot strand a legitimate return. Intents record their creation revision but are accepted only when their epoch/session/cause is still live.

The first fresh server command resolves the case key and milestone profile from the pinned policy and policy-named evidence before applying an effect. `NOT_REQUIRED` is valid only with a policy reason and source evidence; companions are separately keyed and never block `ALL_PROFILE_REQUIRED_MILESTONES`. Every evidence ID must resolve to the bounded embedded record with the same policy/case/subject, and each producer is frozen in the producer matrix. Raw identity, account, credential, and answer payloads remain in their existing protected source; the evidence record stores only bounded facts/digests needed by the reducer.

`interactionHistory` is server-only, redacted, and bounded to the latest 32 transitions plus one roll-up record. It is sufficient to produce A4's “since you were gone” recap and count A2 waiting cycles so the second failure changes channel; it is not a second mutable state machine.

Exact rollback/replay snapshots live only in the existing server-only `users/{uid}/taskPlanOperations/{operationId}` record, bounded to the interaction fields named here and stripped of raw flow answers/secrets. `prior_dynamic_snapshot_id` references that operation. The task's redacted history is not expected to reconstruct an exact rollback by itself.

The `not_applicable_policy` names a server-side contradiction evaluator. On a fresh `markNotApplicable`, the transaction reads exactly the policy-declared identity, assessment, roster, and evidence sources and writes `none`, `present`, or `unknown` with a source-versioned evidence record. `none` permits the one-tap A8 assertion; `present` returns the resolver; `unknown` performs no task mutation and fails closed. A client cannot self-certify `none`. Phase 3 may precompute the same evaluator output, but absence is never silently treated as evidence.

`presentation_snapshot` is user-context, not server authority. It may contain the provider display name, origin-labeled phone/URL, source references, script, and display deadline; an untrusted client value is never upgraded to “verified,” used by a server transition, or treated as provider provenance. It must not duplicate credentials, account numbers, authorization secrets, or raw identity/answer payloads. A relaunch may reuse a user-confirmed action while preserving its source label; verified-hours behavior stays hidden unless an existing trusted producer supplies a versioned hours record. Flow answers remain in H56’s existing persistence under the narrow rules contract in §3.5.

### 3.3 Semantic command surface

Disposition work should be a sibling reducer/module routed by the existing authenticated `changeTaskPlan` callable, leaving H54’s plan-change verbs intact. Every fresh command carries expected epoch/revision plus policy version/fingerprint, is op-first idempotent, transactional, history-bounded, and rejects policy-less legacy tasks. An exact replay is returned before temporal/state revalidation; a reused operation ID with a different fingerprint fails. Handoff follow-ups match session + epoch and read the current revision transactionally rather than rejecting scheduler-only revision drift.

| Command | Server-owned result | Required authority/evidence |
|---|---|---|
| `assertAlreadyHandled` | Close all profile-required milestones from the explicit whole-case assertion; `Completed + COMPLETED` | Capability plus explicit confirmation; not a contextual-outcome shortcut. |
| `markNotApplicable(reasonCode)` | `Dismissed + NOT_APPLICABLE` plus `resolution` | Direct only when contradiction state is exact `none`; `unknown` fails closed; `present` requires the policy resolver. |
| `deferTask(confirmedTrigger)` | `Snoozed + DEFERRED` | Complete future date or policy-eligible event; explicit confirmation. |
| `markSelfHandling(nextAction, confirmedTrigger)` | `InProgress + USER_ACTION_TRACKED`, owner `user:{uid}` | Complete policy-valid trigger and bounded action; this retains the v3 mandatory-trigger amendment. |
| `markWaitingOnExternal(transitionCode, reportedExpectation?, confirmedTrigger)` | `matching_in_progress + WAITING_ON_EXTERNAL` | Server derives/validates owner and expectation from the pinned transition policy plus bounded reported facts; complete promise/acceptance/threshold trigger; retain exact prior `external_submission`, or establish it only through an outcome policy with handoff evidence. |
| `beginHandoff(session, confirmedTrigger)` | `InProgress + USER_ACTION_TRACKED` plus `activeHandoff.state = open_requested` | Declared handoff/action/policy, presentation snapshot, exact prior dynamic snapshot, and confirmed fallback trigger. The external app opens only after success. |
| `acknowledgeHandoffOpened(sessionId)` | `activeHandoff.state = opened` | OS opener acceptance callback for the matching session/epoch; op-first and idempotent. |
| `recordHandoffReturned(sessionId, returnEvidence)` | `activeHandoff.state = returned` | Matching handoff-kind evidence: external scene round-trip or presented-controller completion/dismissal. Ordinary scene activation is not enough. |
| `continueHandoff(sessionId, confirmedTrigger?)` | restored `prepared` session advances to `open_requested` | Matching prepared session; a fired/expired fallback makes a newly confirmed trigger mandatory. |
| `cancelHandoff(sessionId, reasonCode, confirmedTrigger?)` | exact prior semantic fields restored; concurrency tokens advance; handoff retained as `cancelled` history | Permitted from `prepared` or `open_requested`, never after a recorded outcome. If scheduler drift made the restored nonterminal trigger fired/expired, a newly confirmed trigger is mandatory and wake evidence is preserved until the replacement succeeds. |
| `resolveHandoff(sessionId, outcomeCode, inputs, confirmedTrigger?)` | Outcome policy updates milestones and selects COMPLETED, WAITING, USER_ACTION, DEFERRED, or failure resolver | Matching active session/epoch/fingerprint and server-evaluated policy. The client never chooses the persisted status. |
| `resolveWaiting(outcomeCode, inputs, confirmedTrigger?)` | Policy applies “It happened,” renewal, alternate-channel, or failure effects to the current WAITING case | Matching WAITING epoch/transition/history. A renewal requires a newly confirmed trigger; the second failed cycle must select the policy-declared different channel. It never reuses a resolved handoff session. |
| `claimTaskIntent(intentId, claimOperationId)` | Atomically `pending → consumed` and returns the validated typed route | Authenticated intended UID, unexpired live epoch/session/cause. Exact claimant replay returns the same route after a crash; another claimant/device fails. |
| Existing H54 commands | Exact transitions in the table below | Every path is reducer-owned; there is no remaining “snapshot or clear” implementation choice. |

There is no standalone label-driven `markCompleted` outcome command. “Sent” and “Got what I needed” are semantic outcome codes evaluated against the pinned policy and milestone state.

`external_submission == true` is monotonic evidence across every nonterminal builder, scheduler wake, fresh disposition, and H54 transition. Builders must carry it from the base contract automatically; no client flag can clear it. Only an evidence-backed outcome may establish it. A terminal reducer moves the fact and its evidence into immutable resolution/history rather than silently discarding it.

Common fresh-command cleanup is also frozen: `assertAlreadyHandled`, `markNotApplicable`, `deferTask`, `markSelfHandling`, and `markWaitingOnExternal` cancel any live handoff, clear stale wake pointers, cancel live task intents, clear an obsolete resolution, and increment epoch/revision. They preserve policy-valid case/profile evidence and monotonic external-submission evidence; the reducer then applies command-specific milestone effects. `beginHandoff` performs the same wake/intent/resolution cleanup but preserves milestone/contradiction/deadline/amendment evidence and stores the exact prior dynamic snapshot. `resolveHandoff` preserves unrelated evidence, applies only the named outcome effect, and closes/cancels intents that target the resolved session.

H54 integration is normative:

| H54 action | Original task | Replacement/amendment | Handoff, wake, intents, revisions |
|---|---|---|---|
| Internal `supersede` | Snapshot all dynamic state to bounded immutable history, terminalize as retired/superseded, and record resolution. | None. | Cancel active handoff and live intents; clear wake; increment epoch and revision. |
| External `supersede` | Snapshot state; preserve `external_submission`; remain `WAITING_ON_EXTERNAL` while the accepted artifact is still in force. | Create the policy-declared amendment case/profile with open required milestones and its own epoch/revision. | Cancel original handoff/intents, clear wake, and increment both original and replacement revisions. |
| `confirmAmendment` | Terminalize only after the replacement completion policy accepts evidence that the institution confirmed the amendment; archive the old external-submission evidence. | Apply the confirmation effect to required milestones; it may complete only if all profile-required milestones close. | Clear handoffs/wakes, cancel stale intents, increment both epochs/revisions, and retain immutable confirmation snapshots. |
| `undoConfirmation` | Restore the exact pre-confirm dynamic snapshot. | Restore the exact pre-confirm amendment snapshot. | Increment both epochs/revisions; never resurrect an `opened` handoff or an old intent. A previously active handoff restores as `prepared` with a fresh session ID rebased to the new epoch, then Continue-or-Cancel. Any expired/fired trigger must be replaced by a newly confirmed trigger in the undo request. |
| `reopen` | Restore prior disposition, profile, milestones, and resolution snapshot. | Remove only an untouched pending amendment under existing H54 rules. | Clear handoff/wake, cancel intents, increment epoch/revision. An expired/fired prior trigger makes `confirmedTrigger` mandatory; no old trigger is reused. |
| `resetAllTasks` / `finalizeTaskReset` | Existing leased/paged task deletion semantics remain. | All task-derived interaction state and per-user notification intents are included in the resumable cleanup/checkpoint count. | No active handoff is restored. Operation replay and exact unique deletion count remain authoritative. |

### 3.4 Trigger and wake rules

Separate trigger validation into:

1. structural stored-trigger validation, which permits a fresh date/event trigger or a server-only `ATTENTION_NOW` reference to `wakeEvidence`;
2. fresh-write validation, requiring a future date, `fired == false`, and complete evidence;
3. op-first replay, so an exact retry remains valid after the date passes;
4. fresh validation when a prior contract is deliberately reopened.

Fresh trigger wire values are discriminated and server-resolved:

```text
confirmedTrigger :=
  { kind: date, source: PROMISED_DATE|ACCEPTANCE_DATE,
    at, user_report: { operation_id, reported_at, bounded_facts } }
| { kind: date, source: SAFE_THRESHOLD|LABELED_ESTIMATE,
    at, derivation_id, derivation_inputs, user_confirmed_at }
| { kind: date, source: USER_PICKED,
    at, threshold_id, user_confirmed_at }
| { kind: event, eligible_event_id, user_confirmed_at }
```

The server writes the evidence record and canonical stored trigger; caller-supplied `source_evidence_id`, publisher/key, bound, protected-outcome label, or derivation source is never trusted as authority. A promised/acceptance report is fingerprinted with the operation. A threshold/estimate is recomputed through the pinned derivation registry. `USER_PICKED` is invalid without a policy-resolved safe `threshold_id` and must fall on/before that threshold; when no safe threshold exists, the distinct policy-declared `LABELED_ESTIMATE` path is the only final fallback. An event ID resolves the pinned A11 publisher/key and current high-water mark transactionally.

Candidate order is policy-specific:

1. institution-promised date;
2. recipient acceptance date;
3. server-authored safe threshold;
4. user-picked date bounded by that threshold;
5. a labeled estimate only when the exact trigger policy declares it and supplies the protected-outcome derivation.

A move date is never a universal fallback. No server default, generic interval, or trigger retention across scheduler wakes is permitted. Date-bearing commands require a nonoptional confirmed-trigger type on the client; cancellation or stale epoch/revision performs zero calls.

For events, the client sends an eligible-event ID only. The transaction resolves the canonical event name/key, source evidence, and current `after_source_version`. Event UI is hidden when there is no declared publisher.

Scheduler behavior:

- `DEFERRED`: reactivate to `Upcoming`, move the fired trigger into `wakeEvidence`, clear the active trigger, and create one deterministic `task_resume` intent.
- `USER_ACTION_TRACKED` / `WAITING_ON_EXTERNAL`: retain disposition, move the fired date/event completely into `wakeEvidence`/history, replace the contract trigger with server-only `{kind: ATTENTION_NOW, wake_id}`, and create one idempotent task-resume intent. `ATTENTION_NOW` is structural due-now state, never a fresh-write option or default; the next disposition still requires a newly confirmed date/event trigger.
- A fresh disposition clears stale wake/intent pointers.
- `urgent_recovery` is legal only when the pinned state contains a server-authored hard/safe threshold. Otherwise render normal attention, not an invented emergency.

All date scans add `where("dispositionContract.next_trigger.fired", "==", false)` and use a separate persisted cursor per exact disposition/status. All event scans also filter `fired == false` and keep separate cursors, so one status cannot skip another. `firestore.indexes.json` is therefore authorized to replace both current composites with status + trigger kind + fired + trigger time (date) and status + trigger kind + fired (event). Index deployment/readiness remains operationally unknown, but the source and emulator query shapes are Phase 2 work. No fired date/event remains in the active contract after a wake; only the `ATTENTION_NOW` pointer and bounded historical evidence remain.

### 3.5 Handoff and outcome client state

Use three separate state machines:

- `TaskDispositionCoordinator`: owns row sheets/drafts and immutable confirmed commands, keyed by Firestore document ID, interaction epoch/revision, and policy fingerprint.
- `HandoffSessionStore`: owns prepared/open-requested/opened/returned/resolved/cancelled restoration and its presentation snapshot, namespaced by UID plus auth epoch.
- `FlowExitCoordinator`: keeps H56 submission/terminal barriers and its persistence queue; it is not reused for task disposition or handoff state.

The handoff event order is:

```text
local session prepared with immutable operation ID
→ awaited server beginHandoff success
→ server state open_requested
→ external opener completion callback
→ acknowledge opened, or cancel and restore on rejection
→ handoff-kind return evidence
→ policy-keyed outcome question
→ awaited resolveHandoff
```

Server failure never opens the external target. An ambiguous transport retry reuses the byte-equivalent request and operation ID. A revision/fingerprint change invalidates an unsubmitted draft; a handoff survives scheduler-only revision drift while its epoch/session remain live. Concurrent `beginHandoff` calls are rejected. Termination in `open_requested` restores a Continue/Cancel choice and never assumes the action happened. A restored server `prepared` session uses `continueHandoff` or `cancelHandoff`; it is never stuck between states. A server-active/local-absent session is reconstructed from the redacted snapshot; local-prepared/server-absent is discarded; session mismatch, account switch, already-resolved, opener-rejected, and crash-before-open have named reconciliation tests. H54 cancels a live session under §3.3; scheduler wakes do not cancel it.

Return evidence is frozen by adapter kind:

- `CALL`, external `WEB`, `PORTAL`, and `MAP`: accepted `openURL`, then an observed inactive/background transition followed by active.
- in-app Safari `WEB`/`PORTAL`: successful controller presentation acknowledges opened; explicit dismissal records returned; failed presentation cancels.
- `SHARE` and embedded `MAIL`: replace `ShareLink`/implicit presentation with an explicit presenter; successful presentation acknowledges opened; completion/dismissal records returned; cancellation restores prior state without an outcome question unless the policy explicitly treats cancellation as an outcome.

No adapter waits for a scene cycle it cannot emit. Tests use separate fake external-opener, sheet-controller, and share-completion drivers.

Before `beginHandoff` from a flow, the client awaits H56's exact-attempt queue drain and proves the persisted tail. After a contract exists, rules provide two narrow client-owned carve-outs while status/contract/policy/server fields remain immutable:

- flow progress may change only `stage`, `flowPath`, `flowAnswers`, `flowAnswerIdentities`, and `flowAttemptId`. When the stored attempt exists, ordinary writes must retain that same nonblank ID. When it is absent, one initialization write may establish a nonblank ID only if it differs from preserved `lastClearedFlowAttemptId`; later writes must retain it. One atomic terminal-clear operation carries the caller's `expectedFlowAttemptId`, deletes exactly `flowPath`, `flowAnswers`, `flowAnswerIdentities`, and `flowAttemptId`, and sets `lastClearedFlowAttemptId = expectedFlowAttemptId`. Rules require that proof to equal the pre-write `resource.data.flowAttemptId`; a stale attempt therefore cannot clear a newer one or recreate a just-cleared attempt. The client invokes it only after H56's terminal barrier;
- task-detail content may change only bounded `notes` or schema/size-validated `quotes`, independently of the flow attempt.

Rules require owner/auth and exact `affectedKeys().hasOnly(...)` for each disjoint case; `lastClearedFlowAttemptId` can change only in that full-clear shape. RED cases cover queued-write→begin, begin→clear, return→continue, exact full clear, stale/partial/mismatched clear, clear A→delayed A initialization denied, clear A→new B initialization accepted, B continuation accepted, stale A after B denied, notes/quotes bounds, attempt mismatch, and every failure ordering.

### 3.6 Support boundary

`SUPPORT_ACTIVE` is removed from this Phase 2 execution boundary. The repository has neither an approved coverage/SLA registry nor a complete request-specific resolution graph, and pretending otherwise would make source completion depend on human operations. “Get help from a person” may open existing Chat with task context while preserving the already-owned handoff/disposition; it must not show `SUPPORT_ACTIVE`, a reply-by promise, or “help requested.” A separate owner-approved Support phase must define atomic request/message/thread/outbox IDs, SLA/escalation, admin completion/spawn effects, generic-close rejection, retention/account-deletion, rules, and offline admin tests before activating A6.

### 3.7 Notification outbox and routes

Use one server-only per-user outbox:

```text
users/{uid}/notificationIntents/{deterministicIntentId} {
  schema_version: 1,
  audience: user,
  kind: task_resume,
  state: pending|consumed|cancelled,
  task_document_id,
  interaction_epoch,
  interaction_revision,
  policy_fingerprint,
  route: { kind: row|outcome, session_id? },
  cause: { operation_id?, wake_evidence_id? },
  created_at,
  expires_at,
  consumed_at?,
  claim_operation_id?
}
```

Admin writes need no client grant. Rules deny every client read/write; the existing authenticated `changeTaskPlan` callable owns claim/consume. Phase 2 adds no sender, collection query, FCM call, or delivery status.

The external grammar carries only an opaque intent ID: `peezy://task/v1?intentId=<percent-encoded>`. The deterministic ID includes the intended UID and cause in its server hash, so the same task document ID in another account cannot collide. After authentication, `AppRouteInbox` calls `claimTaskIntent` with a locally persisted claim operation ID; the server transaction validates the current UID, expiry, live epoch/session/cause, atomically marks `pending → consumed`, and returns the typed route. Exact replay by the same claim operation returns the same route after a crash; a second claimant/device fails, giving server-global consume-once semantics. Unknown/missing/duplicate query keys fail closed. A cold unauthenticated tap stores only opaque intent/claim IDs with a TTL; wrong-account claim does not consume, account switch retries, sign-out clears in-memory presentation, and expiry/cancel/stale epoch fails closed. The inbox waits for `TasksStore`, presents the returned route once, then clears its durable local claim. Existing Google Sign-In and support-thread routing remain unchanged. Flow-step routing stays hidden until a stable step identifier/resume policy exists.

### 3.8 Research posture migration

Section items become dual-shape:

```text
item := string
      | { text,
          posture: RULE_VERIFIED|ACCOUNT_OR_DECISION_VERIFIED|LABELED,
          source_refs: [{ source_id, claim_locator?, claim_digest? }],
          applicability_predicate_ids: [],
          applicability_evidence_ids: [],
          verified_as_of: YYYY-MM-DD|null }
```

- Legacy cached string items remain strings and are not rewritten on a non-force cache hit.
- The current model-generated path may persist only `LABELED`. A model response that self-assigns either verified posture is deterministically downgraded to `LABELED` (or rejected if the shape is unsafe), because URL survival does not prove official authority or applicability.
- Future `RULE_VERIFIED` requires a trusted official-host classifier, claim-level locator/digest, every policy-required applicability predicate, and policy-versioned evidence. Future `ACCOUNT_OR_DECISION_VERIFIED` requires trusted account/decision evidence. Those producers are outside this phase; the decoder reserves the shape without displaying an unearned label.
- `verified_as_of` means the date the trusted verifier checked the claim, not publication/effective/generated date, and is null for model-generated `LABELED` items.
- Sources have stable IDs rather than positional indexes. If URL guarding removes a referenced source, regenerate or explicitly downgrade and remove the reference; never shift or leave a dangling ID.
- A malformed new item fails locally at the item level where safe; it must not silently relabel a verified claim.

## 4. Explicitly deferred or capability-gated

These capabilities are outside the adopted Phase 2 definition and therefore cannot become execution-time surprises:

- Household assignment and “Edit this list”: hidden until canonical roster membership and task-sharing/visibility authority exist. When implemented, `assignOwner` still requires a newly confirmed complete trigger; it gains no server default or retained wake trigger.
- Policy activation for catalog `rowGeneration`/client-derived `flowRows`: deferred until an authoritative server/rules-verifiable materializer exists; the seeder rejects the combination meanwhile.
- Category-wide defer: hidden until bounded atomic batch semantics exist.
- Generic “Change plan” alternative selection: hidden unless a task policy supplies allowable replacements; existing H54 confirm/undo/reopen may render when their state exists.
- Event picker: hidden without a real A11 publisher/key.
- Urgent-recovery consolidation: hidden without server-authored hard/safe threshold evidence.
- Time-aware closed-office primary CTA: fallback CTA remains available unless verified hours/timezone exist.
- Support activation: ordinary Chat remains available without changing the task state; `SUPPORT_ACTIVE` requires a later support/operations plan.
- FCM/APNs sender, deployment, live index/rules verification, live seed/backfill, and production notification delivery.
- Router-shadow retirement, active catalog/flow data, wallet/ledger, fulfillment delegation, and entitlement/deploy blockers.
- Admin/test task generators: forbidden on an activated target until the Phase 3 preflight retires or upgrades the explicitly inventoried scripts.

## 5. Pre-execution freeze and ordered slices

### 5.1 Contract package — plan authoring, not an execution slice

The current proposal is not itself the executable spec. After the owner approves its direction and expanded boundary, but before any code worktree or RED test, produce `docs/plans/PHASE2_EXECUTABLE_SPEC_v5.md` containing all of the following with zero placeholders:

1. canonical valid/invalid policy fixtures and JS/Swift hashes;
2. complete command × prior-state × result/cleanup table, including every H54 and handoff race;
3. outcome → milestone effect → completion result table;
4. field/evidence producer → storage → mapper → consumer → legacy default → test table;
5. exact rules access-call budget and 53-task chunk/retry/reset fixture;
6. literal source/test path manifest with one owner and ordered integrator for each overlap;
7. exact simulator UDID, Node 24 path, commands, result-bundle assertions, and patch procedure;
8. governing, inventory-annex, protected-WIP, fixture, and executable-spec hashes.

Run one read-only adversarial review of that package. Mutation stops on the first blocker, but the read-only pass finishes and reports **all** independently discovered P0/P1 findings together. Code execution begins only after zero P0/P1, zero `TBD`/`CONTRADICTED`, and explicit owner adoption of the resulting executable-spec hash. This moves design convergence ahead of implementation instead of pausing every workstream for the next missing edge.

### 5.2 Execution slices

| Slice | Scope and dependency | Local completion boundary |
|---|---|---|
| S1 — policy propagation | Strict JS validator/canonicalizer; seeder projection (no seed); shared Swift catalog→task projection for both owner-generation loops; 8-row resumable chunks; spawn copy; mapper/model; base rules immutability. | Policy-less tasks unchanged; malformed-present tasks passive; exact catalog copy accepted; omission/duplicate/forged/mutated copy denied; 53-row/reset/retry and spawn fixtures green. |
| S2 — disposition kernel and remaining producers | Structural/fresh trigger split; op-first replay; milestone/outcome/waiting reducer; H54 snapshot/restore plus amendment-policy copy; workflow terminal/waiting writer integration. | Complete outcome/writer/cleanup matrix and every workflow/amendment producer green in offline Node/rules/Swift transport tests. |
| S3 — wake, outbox, and intent claim | Per-status/kind scheduler scans with `fired == false`, separate cursors, index source, wake evidence, deterministic intent creation/cancellation, and server-global `claimTaskIntent`; no sender. | Fake scheduler/query/outbox/claim tests prove one wake/intent, no cursor poisoning, claim replay/exclusion, and stale cancellation. |
| S4 — row vertical | Pure `TaskDispositionCoordinator` and one shared `TaskDispositionSurface`, first on Tasks then reused by Home from the live `TasksStore`. | Policy gates, WAITING line/exits, date trigger flow, legacy model bytes, and Home/Tasks revision parity green. No `TaskRowHeader` code change. |
| S5 — ProviderAction handoff | H56 pre-drain/rules carve-out, `HandoffSessionStore`, begin/open-ack/cancel/return/resolve, contextual outcomes; first mount at `ProviderActionCard`, generic flows, and insurance reuse. | Every opener/crash/reconciliation branch is green; persist precedes open; contracted flow progress/clear remains legal; scheduler revision drift does not strand a live session. |
| S6 — clean CTA adapters | Task detail/content maps and movers share only. Settings/legal/system-remediation, PostFlowFork/research links, and every protected Inventory mount are excluded. | Every listed clean adapter is explicitly tracked or excluded; no deferred/protected site is a completion requirement. |
| S7 — typed routes | Opaque intent route to row first and outcome after S5; existing support-thread and Google routes preserved; flow-step hidden without stable policy. | Pure parse/auth/readiness/account-switch/consume-once/expiry/missing-target cases green; existing fallbacks unchanged. |
| S8 — scene flush | `FlowExitCoordinator` bounded background drain at `OutermostTaskFlowContainer`; no global registry. | Queue-backed tail only; barrier/external-pending/no-work/expiry/failure branches green. Claim is bounded best effort, not zero-loss. |
| S9 — research posture | Server dual-shape normalization/guard/persistence and Swift item decoder/renderer; model output is LABELED-only. This slice solely owns research links. | Legacy/mixed/new/malformed/stable-source-ID/removal/downgrade cases green; no generated verified claim. |

S1→S2→S4→S5 is the critical path. S3 follows S2. S7 row routing follows S4 and outcome routing follows S5. S8 and the server half of S9 may be authored in parallel only when their literal file ownership is disjoint; all changes integrate sequentially in one worktree. Phase 2 means S1–S9, not a movable “Core plus optional support” target.

## 6. Authorized source boundary

The old W0 boundary is replaced because it forbids the propagation and evidence paths required for its own Phase 3 promise.

Literal server/data ownership (new paths are marked **new**):

| Owner | Paths |
|---|---|
| S1 | **new** `functions/taskInteraction.js`; `functions/seedTaskCatalog.js`; `functions/spawnTasks.js`; `firestore.rules` (first owner) |
| S2 | **new** `functions/taskDisposition.js`; `functions/dispositionContract.js`; `functions/taskPlan.js` (first owner); `functions/getWorkflowQualifying.js` |
| S3 | **new** `functions/notificationIntents.js`; `functions/dispositionTriggers.js`; `functions/taskPlan.js` (ordered follow-on for intent claim); `firestore.indexes.json`; `firestore.rules` (ordered follow-on integrator after S1) |
| S9 | `functions/researchTask.js` |

Literal client ownership:

| Owner | Paths |
|---|---|
| S1 | `Peezy 4.0/Assessment/AssessmentModels/TaskGenerationService.swift`; `Peezy 4.0/MainInterface/Models/PeezyCard.swift`; `Peezy 4.0/Tasks/Store/PeezyCardFirestoreMapper.swift`; `Peezy 4.0/MainInterface/Models/TaskPlanService.swift`; **new** `Peezy 4.0/Tasks/Disposition/TaskInteraction.swift`; **new** `Peezy 4.0/Tasks/Disposition/ConfirmedDispositionCommand.swift` |
| S2 | **new** `Peezy 4.0/Tasks/Disposition/DispositionTriggerSelection.swift`; **new** `Peezy 4.0/Tasks/Disposition/TaskDispositionCoordinator.swift` |
| S4 | **new** `Peezy 4.0/Tasks/Disposition/TaskDispositionSurface.swift`; `Peezy 4.0/Tasks/Store/TasksStore.swift`; `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift` (first owner); `Peezy 4.0/Tasks/Views/TasksTabView.swift`; `Peezy 4.0/Tasks/Views/TasksList.swift`; `Peezy 4.0/Tasks/Views/TaskRow.swift`; `Peezy 4.0/Tasks/Views/TaskRowButtons.swift`; `Peezy 4.0/MainInterface/Views/PeezyHomeView.swift`; `Peezy 4.0/MainInterface/Models/PeezyHomeViewModel.swift` |
| S5 | **new** `Peezy 4.0/Tasks/Handoff/HandoffSession.swift`; **new** `Peezy 4.0/Tasks/Handoff/HandoffSessionStore.swift`; **new** `Peezy 4.0/Tasks/Handoff/TaskExternalActionButton.swift`; **new** `Peezy 4.0/Tasks/Handoff/ContextualOutcome.swift`; `Peezy 4.0/MainInterface/Views/ProviderActionCard.swift`; `Peezy 4.0/MainInterface/Models/ProviderDirectoryService.swift`; `Peezy 4.0/MainInterface/Models/TaskFlowRouter.swift`; `Peezy 4.0/MainInterface/Models/TaskActionService.swift`; `Peezy 4.0/Tasks/FlowEngine/FlowEngineView.swift`; `Peezy 4.0/Tasks/FlowEngine/FlowExitControl.swift` (first owner); `Peezy 4.0/Tasks/Task Cards/HandleAutoInsuranceFlow.swift`; `Peezy 4.0/Tasks/Task Cards/HandleHomeInsuranceFlow.swift`; `Peezy 4.0/Tasks/Task Cards/FindCleanersFlow.swift`; `Peezy 4.0/Tasks/Task Cards/SellItemsFlow.swift`; `Peezy 4.0/Tasks/Task Cards/RemoveItemsFlow.swift` |
| S6 | `Peezy 4.0/Tasks/Views/TaskDetailView.swift`; `Peezy 4.0/Tasks/Views/TaskContentSections.swift`; `Peezy 4.0/Tasks/Task Cards/MoversEquipView.swift`; `Peezy 4.0/Tasks/Task Cards/FindMoversFlow.swift` |
| S7 | **new** `Peezy 4.0/MainInterface/Routing/TaskRoute.swift`; **new** `Peezy 4.0/MainInterface/Routing/AppRouteInbox.swift`; `Peezy 4.0/MainInterface/Models/PeezyV1App.swift`; `Peezy 4.0/MainInterface/Views/PeezyMainContainer.swift` (ordered follow-on after S4); `Peezy-4-0-Info.plist` |
| S8 | `Peezy 4.0/Tasks/FlowEngine/FlowExitControl.swift` (ordered follow-on after S5) |
| S9 | `Peezy 4.0/Tasks/Views/TaskResearchModule.swift`; `Peezy 4.0/Tasks/FlowEngine/PostFlowForkView.swift` |

Literal Node/rules test manifest:

- Existing Phase-1 envelope: `functions/tests/accountabilityLadder.test.js`, `functions/tests/callableAuth.test.js`, `functions/tests/dispositionContract.test.js`, `functions/tests/dispositionTriggers.test.js`, `functions/tests/entitlement.test.js`, `functions/tests/getWorkflowQualifying.test.js`, `functions/tests/packSimulation.test.js`, `functions/tests/processInventoryMerge.test.js`, `functions/tests/processInventoryModel.test.js`, `functions/tests/processInventoryPacking.test.js`, `functions/tests/seedCubeSheet.test.js`, `functions/tests/spawnTasks.test.js`, `functions/tests/submitCheckIn.test.js`, `functions/tests/taskCatalogMovers.test.js`, `functions/tests/taskPlan.test.js`, `functions/tests/validateSubscription.test.js`, `functions/spawnTasks.test.js`, and the separately invoked `functions/rules-tests/firestoreRules.test.js`.
- **New:** `functions/tests/taskInteraction.test.js`, `functions/tests/taskInteractionProjection.test.js`, `functions/tests/taskDisposition.test.js`, `functions/tests/notificationIntents.test.js`, and `functions/tests/researchTask.test.js`.

Literal Swift test files are existing `Peezy 4.0Tests/ConversationFlowTests.swift`, `Peezy 4.0Tests/DispositionContractTests.swift`, `Peezy 4.0Tests/TaskGroupingTests.swift`, and `Peezy 4.0Tests/TaskSupersessionTests.swift`, plus **new** `Peezy 4.0Tests/TaskInteractionTests.swift`, `Peezy 4.0Tests/TaskInteractionProjectionTests.swift`, `Peezy 4.0Tests/HandoffSessionTests.swift`, `Peezy 4.0Tests/ContextualOutcomeTests.swift`, `Peezy 4.0Tests/TaskPlanDispositionTests.swift`, `Peezy 4.0Tests/DispositionTriggerSelectionTests.swift`, `Peezy 4.0Tests/TaskDispositionSurfaceTests.swift`, `Peezy 4.0Tests/TaskRowLegacySnapshotTests.swift`, `Peezy 4.0Tests/TaskRouteTests.swift`, `Peezy 4.0Tests/FlowSceneFlushTests.swift`, and `Peezy 4.0Tests/ResearchPostureTests.swift`.

No other path is implicitly authorized. In particular, `functions/index.js` reuses the existing `changeTaskPlan` export and stays unchanged; `firebase.json`, `functions/package.json`, `functions/taskCatalogData.json`, `functions/flowDefinitionsData.json`, `public/admin/index.html`, support server files, and `Peezy 4.0.xcodeproj/project.pbxproj` stay unchanged. The synchronized source/test roots must auto-enumerate the new Swift files; if they do not, that is a pre-execution boundary contradiction, not permission to edit the project file.

Protected Build 25 WIP is immutable, including every dirty/untracked Inventory path, `functions/processInventory.js`, its narration test, `ARCHIVE_MANIFEST.md`, and `PEEZY_STATE_REGEN_SPEC.md`. The scanner handoff mount is outside S6 and outside Phase 2; it cannot fail S6. Entitlement/billing, catalog/flow data, router shadows, live config, and `PEEZY_STATE.md` remain unchanged.

## 7. Audit/review/execution protocol

### 7.1 One plan-authoring GO gate

Before an execution worktree exists, complete §5.1 and record:

- governing hashes, HEAD, branch, protected dirty/untracked hashes;
- the final outcome→policy→status/contract→writer→evidence→rules→test matrix;
- every new field’s producer→storage→mapper→consumer→legacy default→test matrix;
- exact slice file ownership and exact test manifest;
- executable-spec hash.

GO requires no `TBD`, `CONTRADICTED`, unowned state, missing producer/writer, or unresolved P0/P1. Inventory additions that fit a frozen capability and file boundary are appended to the annex and do not stop execution.

### 7.2 Review exit rule

The architecture/spec review runs once to zero P0/P1. Each slice then follows RED → GREEN → diff review. P2/P3 observations are fixed when local and low-risk or recorded as bounded debt; they do not create another global plan round. A reviewer finding reopens only its affected slice unless it contradicts a frozen cross-slice contract.

### 7.3 Worktrees and integration

1. Freeze the dirty-main protected hashes.
2. Create exactly one detached integration worktree from `b4b047d`. Slices integrate there in dependency order; parallel reviewers do not write to the shared tree.
3. Before each slice, record the base commit, cumulative accepted-patch hash, and hashes of every dependency path. After RED/GREEN/review, freeze its literal path manifest and cumulative checkpoint hash.
4. Do not stage or commit. Generate the tracked portion with `git diff --binary --full-index b4b047d -- <literal tracked manifest>`. For every new untracked path, append `git diff --binary --no-index /dev/null '<literal path>'` in sorted manifest order (exit 1 means “differences,” not failure). The canonical patch is the ordered concatenation; record its SHA-256 and a separate path/hash manifest so new files cannot disappear from the review.
5. At each checkpoint run authorized-path checks, `git diff --check` for tracked paths plus `git diff --no-index --check /dev/null '<new path>'` for every untracked create, slice tests, and independent diff review against the cumulative tree. Any later edit to an accepted file invalidates that file's review hash and triggers cumulative re-review of that file and its dependents.
6. After the integration build, exact XCTest/Node/rules envelopes, and server/client whole-diff reviews pass, create one final canonical patch using the same tracked-plus-no-index procedure.
7. Recheck main HEAD and every protected hash, run `git apply --check`, apply the patch once to dirty main, and verify Phase-2 path hashes equal the accepted integration manifest. A dirty-main smoke build is optional and non-gating because it includes unrelated Build 25 WIP. Stop before commit with Phase-2-only and total-working-tree diff stats shown separately.

### 7.4 Narrow stop conditions

Stop mutation only for:

- a contradiction with the governing state/master;
- a required field/state with no writer/producer inside the frozen architecture;
- a required unauthorized/protected-WIP/config path;
- an unresolved P0/P1 review finding;
- a RED test that is not behavior-specific;
- an in-scope regression/build/static failure that cannot be repaired without scope expansion;
- patch conflict, baseline drift, or protected-hash drift.

After mutation stops, finish all safe read-only matrix/diff checks and report every independently discovered P0/P1 blocker in that pass, not only the first edge. Do not stop for an inventory addition that fits the frozen model, a P2/P3 review note, an intentionally absent capability, or an operational/manual claim that is explicitly classified as unverified.

## 8. Verification envelope

### Local automated

- The executable spec resolves one available simulator UDID once and substitutes that literal into both commands below; there is no “latest simulator” drift. The integration-worktree commands are:

```sh
env -u PEEZY_RUN_FIRESTORE_INTEGRATION xcodebuild build \
  -project 'Peezy 4.0.xcodeproj' -scheme 'Peezy 4.0' \
  -configuration Debug -destination 'platform=iOS Simulator,id=<FROZEN_UDID>' \
  CODE_SIGNING_ALLOWED=NO

env -u PEEZY_RUN_FIRESTORE_INTEGRATION xcodebuild test \
  -project 'Peezy 4.0.xcodeproj' -scheme 'Peezy 4.0' \
  -configuration Debug -destination 'platform=iOS Simulator,id=<FROZEN_UDID>' \
  -only-testing:'Peezy 4.0Tests/ConversationFlowTests' \
  -only-testing:'Peezy 4.0Tests/DispositionContractTests' \
  -only-testing:'Peezy 4.0Tests/TaskGroupingTests' \
  -only-testing:'Peezy 4.0Tests/TaskSupersessionTests' \
  -only-testing:'Peezy 4.0Tests/TaskInteractionTests' \
  -only-testing:'Peezy 4.0Tests/TaskInteractionProjectionTests' \
  -only-testing:'Peezy 4.0Tests/HandoffSessionTests' \
  -only-testing:'Peezy 4.0Tests/ContextualOutcomeTests' \
  -only-testing:'Peezy 4.0Tests/TaskPlanDispositionTests' \
  -only-testing:'Peezy 4.0Tests/DispositionTriggerSelectionTests' \
  -only-testing:'Peezy 4.0Tests/TaskDispositionSurfaceTests' \
  -only-testing:'Peezy 4.0Tests/TaskRowLegacySnapshotTests' \
  -only-testing:'Peezy 4.0Tests/TaskRouteTests' \
  -only-testing:'Peezy 4.0Tests/FlowSceneFlushTests' \
  -only-testing:'Peezy 4.0Tests/ResearchPostureTests' \
  -skip-testing:'Peezy 4.0UITests' \
  -resultBundlePath '/tmp/peezy-phase2-v5.xcresult' \
  CODE_SIGNING_ALLOWED=NO
```

- Exact named XCTest classes, no `-testPlan`, UI skipped, and `PEEZY_RUN_FIRESTORE_INTEGRATION` unset:
  - `ConversationFlowTests`
  - `DispositionContractTests`
  - `TaskGroupingTests`
  - `TaskSupersessionTests`
  - `TaskInteractionTests`
  - `TaskInteractionProjectionTests`
  - `HandoffSessionTests`
  - `ContextualOutcomeTests`
  - `TaskPlanDispositionTests`
  - `DispositionTriggerSelectionTests`
  - `TaskDispositionSurfaceTests`
  - `TaskRowLegacySnapshotTests`
  - `TaskRouteTests`
  - `FlowSceneFlushTests`
  - `ResearchPostureTests`
- Inspect the `.xcresult`: exactly the selected unit suites, no UI/integration suite, no failure, and no unexpected skip.
- Inspect with `xcrun xcresulttool get test-results tests --path '/tmp/peezy-phase2-v5.xcresult' --format json`; the executable spec freezes an assertion script/expected class set and requires zero failed/skipped leaves and no other class.
- Run this exact offline Node manifest; never use a broad glob that can absorb dirty Build 25 tests:

```sh
env -u GOOGLE_APPLICATION_CREDENTIALS -u GCLOUD_PROJECT \
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

- Run rules only in the local emulator under the demo project:

```sh
env -u GOOGLE_APPLICATION_CREDENTIALS -u GCLOUD_PROJECT \
  -u GOOGLE_CLOUD_PROJECT -u FIREBASE_CONFIG \
  JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
  PATH=/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/bin:/usr/bin:/bin \
  FIREBASE_CLI_DISABLE_TELEMETRY=1 FIREBASE_CLI_DISABLE_UPDATE_CHECK=1 \
  /opt/homebrew/bin/firebase emulators:exec --only firestore --project demo-peezy-phase1 \
  "/opt/homebrew/opt/node@24/bin/node --test functions/rules-tests/firestoreRules.test.js"
```

- Run `node --check` on every touched JS file, `git diff --check`, the literal unauthorized-path scan, protected-hash comparison, server/client whole-diff reviews, and accepted integration-manifest hash comparison after application to main. The isolated integration build/tests—not a dirty-main build—are the gate.

### Manual OS evidence — not a commit gate

- Real call/Safari/Maps/share return, process kill/relaunch, next-day resume, cold/live custom URL, VoiceOver discovery, and pixel/layout review.
- OS background assertion denial/expiration and force-quit behavior. The source claim is only a bounded best-effort queue drain while background time remains.

### Operational/deployed unknown — not claimed by source completion

- Live Functions/rules/index/scheduler revision and one nonproduction wake cycle.
- FCM/APNs delivery and real cold-start notification routing.
- Human support policy/coverage/SLA/admin work belongs to the separately authorized support phase.
- Real institutional hours, legal deadlines/safe thresholds, research applicability, and source correctness.
- Phase 3 catalog data, backup/dry-run/approval, seed/backfill/regeneration, and post-migration validation.

## 9. Acceptance by slice

Phase 2 is accepted locally when:

- Old/policy-less tasks decode and behave as before; malformed/unknown-present policy is passive and cannot fall back to legacy writes.
- Every policy-bearing task producer copies the canonical policy; 8-row generation chunks survive reset/retry/partial failure; rules prevent omission, duplicate identity, and later client mutation.
- Every semantic outcome has one server-selected, coherent status/contract/milestone result; operation replay remains exact after trigger time passes.
- WAITING “It happened” and renewal/failure exits use the current waiting policy/history, require a fresh trigger when still unresolved, and change channel on the second failed cycle without reusing a handoff session.
- A contracted external action cannot open until `beginHandoff` succeeds; opener rejection restores the exact prior state; restoration/reconciliation reproduces the origin-labeled action/outcome context without treating scheduler revision drift as a new session.
- H56 queued progress drains before handoff; exact flow progress/full-clear and bounded notes/quotes remain writable without weakening status/contract/policy ownership.
- The same live `TasksStore` revision drives the shared Home/Tasks disposition surface; no row performs its own repository fetch.
- Trigger selection obeys the frozen hierarchy; each exact scheduler scan excludes fired triggers, preserves bounded wake history, and creates/cancels one deterministic outbox intent.
- Opaque intent routes bind the intended account plus epoch/session/fingerprint, handle cold auth/account switch/expiry, wait for readiness, and consume once; existing Google/support behavior is unchanged.
- Scene flush respects both H56 barriers and is described only as bounded best effort.
- Legacy research strings and mixed new items decode/render safely; model-generated items never display a verified posture.
- All local automated checks pass, every touched file has been diff-reviewed, and protected Build 25 hashes are identical.

`SUPPORT_ACTIVE` is not part of Phase 2 acceptance. Existing Chat remains usable and never claims task support acceptance.

## 10. Build report format

The v5 report is the new `docs/plans/PHASE2_BUILD_v5.md`; the immutable v4 `PHASE2_BUILD.md` remains the inventory annex. The new report should be short and auditable:

1. GO/STOP gate table.
2. Frozen hashes, protected baseline, and executable-spec hash.
3. Traceability-matrix and inventory-annex hashes.
4. Slice ledger: dependencies, RED, GREEN, files, patch hash, reviewer result, integration checkpoint.
5. Final build/XCTest/Node/rules evidence.
6. Authorized-path, diff, patch-to-main, and protected-hash integrity.
7. Manual/operational/deployed-unknown debt and explicitly deferred support capability.
8. Commit gate with Phase-2-only and total dirty-tree stats.

A STOP report records the first point at which mutation stopped, then all independently found P0/P1 blockers from the completed read-only pass, the minimal coherent amendment set, integrity result, and report stat. It does not force one amendment per run or regenerate another multi-hundred-line speculative inventory report.
