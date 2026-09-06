"use strict";

// PHASE2_CONTRACT.md C9.3 — notification intents and claimTaskIntent (S3 I10).

const assert = require("node:assert/strict");
const test = require("node:test");
const { Timestamp } = require("firebase-admin/firestore");
const intents = require("../notificationIntents");
const fence = require("../accountDeletionFence");
const { handleTaskPlanRequest } = require("../taskPlan");
const { fakeFirestore, FakeClock } = require("./support/fakeFirestore");

const UID = "u1";
const NOW = new Date("2026-09-06T12:00:00.000Z");
const CLAIM_OP = "11111111-1111-4111-8111-111111111111";
const cause = () => ({ kind: "TRIGGER", original_trigger: { kind: "date", at: Timestamp.fromMillis(0), fired: true } });
const baseTask = () => ({ status: "Upcoming", task_instance_id: "ti1", task_generation_epoch: 3, taskInteractionState: { interaction_epoch: 2, policy_fingerprint: "p".repeat(64) } });

/** Produces a wake + intent pair on a fresh fake and returns everything the claim needs. */
async function seeded({ route = { kind: "row" }, task = baseTask(), clockIso = "2026-09-06T11:00:00.000Z", extraDocs = {} } = {}) {
  const clock = new FakeClock(clockIso);
  const db = fakeFirestore({ docs: { [`users/${UID}`]: { name: "U" }, [`users/${UID}/tasks/t1`]: task, ...extraDocs }, clock });
  const taskRef = db.doc(`users/${UID}/tasks/t1`);
  const produced = await db.runTransaction(async (transaction) => intents.produceWake(transaction, db, {
    uid: UID, taskRef, task, cause: cause(), route, resumeDestination: "flow:due", urgency: "normal",
    interactionEpoch: 2, interactionRevision: 5, policyFingerprint: "p".repeat(64), now: clock.now()
  }));
  clock.millis = NOW.getTime();
  return { db, clock, taskRef, ...produced };
}

const claim = (db, overrides = {}, auth = { uid: UID }) => handleTaskPlanRequest({ auth, data: { action: "claimTaskIntent", intentId: overrides.intentId, claimOperationId: CLAIM_OP, ...overrides } }, () => db, NOW);

test("C9.3.1 identities are instance-bound and deterministic: wake_id and intent_id derive from the exact canonical maps; the intent cause is the wake pointer; a transaction retry produces the same IDs", async () => {
  const { intentId, wakeId, intent, wakeEvidence, db, taskRef } = await seeded();
  const wakeMap = { uid: UID, task_document_id: "t1", task_instance_id: "ti1", interaction_epoch: 2, policy_fingerprint: "p".repeat(64), cause: cause() };
  assert.equal(wakeId, `w1_${fence.first40(fence.sha256Hex(fence.TaskCanonicalV1(wakeMap)))}`);
  assert.equal(intentId, `ni1_${fence.first40(fence.sha256Hex(fence.TaskCanonicalV1({ uid: UID, task_document_id: "t1", task_instance_id: "ti1", interaction_epoch: 2, policy_fingerprint: "p".repeat(64), route: { kind: "row" }, cause: { wake_evidence_id: wakeId } })))}`);
  assert.deepEqual(intent.cause, { wake_evidence_id: wakeId });
  assert.equal(wakeEvidence.intent_id, intentId, "pointer equality");
  assert.equal(intent.expires_at.toMillis() - intent.created_at.toMillis(), 24 * 3600 * 1000, "expiry is exactly 24 hours from server creation");
  assert.deepEqual(Object.keys(db.__docs.get(`users/${UID}/notificationIntents/${intentId}`)).sort(), ["audience", "cause", "created_at", "expires_at", "interaction_epoch", "interaction_revision", "kind", "policy_fingerprint", "route", "schema_version", "state", "task_document_id", "task_instance_id"]);
  assert.equal(db.__docs.get(`users/${UID}/tasks/t1`).wakeEvidence.wake_id, wakeId);
  const other = intents.wakeIdFor({ ...{ uid: UID, taskDocumentId: "t1", taskInstanceId: "ti2", interactionEpoch: 2, policyFingerprint: "p".repeat(64), cause: cause() } });
  assert.notEqual(other, wakeId, "a different instance is a different wake");
  // exact retry: the same transaction body again yields identical IDs and bytes (no second intent)
  const again = await db.runTransaction(async (transaction) => intents.produceWake(transaction, db, { uid: UID, taskRef, task: db.__docs.get(`users/${UID}/tasks/t1`), cause: cause(), route: { kind: "row" }, resumeDestination: "flow:due", urgency: "normal", interactionEpoch: 2, interactionRevision: 5, policyFingerprint: "p".repeat(64), now: intent.created_at }));
  assert.deepEqual([again.intentId, again.wakeId], [intentId, wakeId]);
  assert.equal([...db.__docs.keys()].filter((p) => p.includes("/notificationIntents/")).length, 1, "one intent per wake");
  // in-place normal → urgent upgrade retains the pointer and creates no second intent
  await db.runTransaction(async (transaction) => intents.upgradeWakeUrgency(transaction, db, UID, taskRef, db.__docs.get(`users/${UID}/tasks/t1`), { deadline_evidence_id: "de1", threshold_id: "th1" }));
  const upgraded = db.__docs.get(`users/${UID}/tasks/t1`).wakeEvidence;
  assert.deepEqual([upgraded.urgency, upgraded.intent_id, upgraded.wake_id], ["urgent_recovery", intentId, wakeId]);
  assert.equal([...db.__docs.keys()].filter((p) => p.includes("/notificationIntents/")).length, 1);
  // C9.3.1 pair atomicity: a crossed pointer (this task pointing at another task's pending intent) refuses cancellation with zero writes
  const crossedWrites = db.__writes.length;
  db.__docs.set(`users/${UID}/tasks/t2`, { ...baseTask(), wakeEvidence: { ...db.__docs.get(`users/${UID}/tasks/t1`).wakeEvidence } });
  await assert.rejects(db.runTransaction(async (transaction) => intents.cancelPendingIntent(transaction, db, UID, db.doc(`users/${UID}/tasks/t2`), db.__docs.get(`users/${UID}/tasks/t2`))), /crossed task/);
  assert.equal(db.__writes.length, crossedWrites, "crossed pointer: no cancellation, no pointer clear");
  assert.equal(db.__docs.get(`users/${UID}/notificationIntents/${intentId}`).state, "pending");
  db.__docs.delete(`users/${UID}/tasks/t2`);
  // a fresh successful command cancels the pending intent and clears the pointer atomically
  await db.runTransaction(async (transaction) => intents.cancelPendingIntent(transaction, db, UID, taskRef, db.__docs.get(`users/${UID}/tasks/t1`)));
  assert.equal(db.__docs.get(`users/${UID}/notificationIntents/${intentId}`).state, "cancelled");
  assert.equal("wakeEvidence" in db.__docs.get(`users/${UID}/tasks/t1`), false);
  // C9.3.1 exact retry after consumption: replaying the producer never rewrites a consumed pair back to pending
  const consumedCtx = await seeded();
  await claim(consumedCtx.db, { intentId: consumedCtx.intentId });
  const consumedBefore = JSON.stringify(consumedCtx.db.__docs.get(`users/${UID}/notificationIntents/${consumedCtx.intentId}`));
  const replayWrites = consumedCtx.db.__writes.length;
  const replayed = await consumedCtx.db.runTransaction(async (transaction) => intents.produceWake(transaction, consumedCtx.db, { uid: UID, taskRef: consumedCtx.taskRef, task: consumedCtx.db.__docs.get(`users/${UID}/tasks/t1`), cause: cause(), route: { kind: "row" }, resumeDestination: "flow:due", urgency: "normal", interactionEpoch: 2, interactionRevision: 5, policyFingerprint: "p".repeat(64), now: consumedCtx.clock.now() }));
  assert.deepEqual([replayed.intentId, replayed.wakeId], [consumedCtx.intentId, consumedCtx.wakeId]);
  assert.equal(JSON.stringify(consumedCtx.db.__docs.get(`users/${UID}/notificationIntents/${consumedCtx.intentId}`)), consumedBefore, "the consumed intent is not overwritten");
  assert.equal(consumedCtx.db.__writes.length, replayWrites, "exact retry writes nothing");
  // an incompatible existing wake (different cause under the same pointer) fails closed
  consumedCtx.db.__docs.get(`users/${UID}/tasks/t1`).wakeEvidence.wake_id = "w1_" + "9".repeat(40);
  await assert.rejects(consumedCtx.db.runTransaction(async (transaction) => intents.produceWake(transaction, consumedCtx.db, { uid: UID, taskRef: consumedCtx.taskRef, task: consumedCtx.db.__docs.get(`users/${UID}/tasks/t1`), cause: cause(), route: { kind: "row" }, resumeDestination: "flow:due", urgency: "normal", interactionEpoch: 2, interactionRevision: 5, policyFingerprint: "p".repeat(64), now: consumedCtx.clock.now() })), /incompatible wake/);
  // C6.1: the task must be the fenced owner's own `users/{uid}/tasks/{id}`; another owner's task path is rejected before any write
  const foreignCtx = await seeded();
  foreignCtx.db.__docs.set("users/B/tasks/t1", { ...baseTask() });
  const foreignRef = foreignCtx.db.doc("users/B/tasks/t1");
  const foreignWrites = foreignCtx.db.__writes.length;
  await assert.rejects(foreignCtx.db.runTransaction(async (transaction) => intents.produceWake(transaction, foreignCtx.db, { uid: UID, taskRef: foreignRef, task: baseTask(), cause: cause(), route: { kind: "row" }, resumeDestination: "flow:due", urgency: "normal", interactionEpoch: 2, interactionRevision: 5, policyFingerprint: "p".repeat(64), now: foreignCtx.clock.now() })), /task owner/, "produceWake");
  await assert.rejects(foreignCtx.db.runTransaction(async (transaction) => intents.upgradeWakeUrgency(transaction, foreignCtx.db, UID, foreignRef, { ...baseTask(), wakeEvidence: foreignCtx.wakeEvidence }, { deadline_evidence_id: "de1", threshold_id: "th1" })), /task owner/, "upgradeWakeUrgency");
  await assert.rejects(foreignCtx.db.runTransaction(async (transaction) => intents.cancelPendingIntent(transaction, foreignCtx.db, UID, foreignRef, { ...baseTask(), wakeEvidence: foreignCtx.wakeEvidence })), /task owner/, "cancelPendingIntent");
  assert.equal(foreignCtx.db.__writes.length, foreignWrites, "a foreign task path writes nothing");
  // C9.3.1: an existing pair is preserved only when both documents are exact; a drifted intent member or surplus content fails closed
  for (const [label, mutate] of [
    ["intent fingerprint drift", (db, id) => { db.__docs.get(`users/${UID}/notificationIntents/${id}`).policy_fingerprint = "q".repeat(64); }],
    ["intent surplus member", (db, id) => { db.__docs.get(`users/${UID}/notificationIntents/${id}`).extra = 1; }],
    ["intent route drift", (db, id) => { db.__docs.get(`users/${UID}/notificationIntents/${id}`).route = { kind: "outcome" }; }],
    ["wake resume destination drift", (db) => { db.__docs.get(`users/${UID}/tasks/t1`).wakeEvidence.resume_destination = "flow:other"; }],
    ["wake fired_at malformed", (db) => { db.__docs.get(`users/${UID}/tasks/t1`).wakeEvidence.fired_at = "bad"; }],
    ["wake urgency malformed", (db) => { db.__docs.get(`users/${UID}/tasks/t1`).wakeEvidence.urgency = "bogus"; }],
    ["wake urgency basis without urgency", (db) => { db.__docs.get(`users/${UID}/tasks/t1`).wakeEvidence.urgency_basis = { deadline_evidence_id: "de1", threshold_id: "th1" }; }]
  ]) {
    const driftCtx = await seeded();
    mutate(driftCtx.db, driftCtx.intentId);
    const driftWrites = driftCtx.db.__writes.length;
    await assert.rejects(driftCtx.db.runTransaction(async (transaction) => intents.produceWake(transaction, driftCtx.db, { uid: UID, taskRef: driftCtx.taskRef, task: driftCtx.db.__docs.get(`users/${UID}/tasks/t1`), cause: cause(), route: { kind: "row" }, resumeDestination: "flow:due", urgency: "normal", interactionEpoch: 2, interactionRevision: 5, policyFingerprint: "p".repeat(64), now: driftCtx.clock.now() })), /incompatible wake/, label);
    assert.equal(driftCtx.db.__writes.length, driftWrites, `${label}: no write`);
  }
  // C6.1: every shared writer reads the owner root and refuses under a deletion marker with zero writes
  const fencedCtx = await seeded();
  const marker = { accountDeletion: { schemaVersion: 1, state: "DELETING", capabilities: [{ operationId: "adel1_00000000-0000-4000-8000-000000000001", proofSHA256: "a".repeat(64) }], startedAt: Timestamp.fromMillis(0), storageGuardAfter: Timestamp.fromMillis(604800000) } };
  fencedCtx.db.__docs.set(`users/${UID}`, marker);
  const fencedWrites = fencedCtx.db.__writes.length;
  const fencedTask = () => fencedCtx.db.__docs.get(`users/${UID}/tasks/t1`);
  const isFenced = (e) => e.code === "failed-precondition" && e.details.reason === "ACCOUNT_DELETION_FENCED";
  await assert.rejects(fencedCtx.db.runTransaction(async (transaction) => intents.produceWake(transaction, fencedCtx.db, { uid: UID, taskRef: fencedCtx.taskRef, task: { ...fencedTask(), wakeEvidence: undefined }, cause: cause(), route: { kind: "row" }, resumeDestination: "flow:due", urgency: "normal", interactionEpoch: 2, interactionRevision: 5, policyFingerprint: "p".repeat(64), now: fencedCtx.clock.now() })), isFenced, "produceWake");
  await assert.rejects(fencedCtx.db.runTransaction(async (transaction) => intents.upgradeWakeUrgency(transaction, fencedCtx.db, UID, fencedCtx.taskRef, fencedTask(), { deadline_evidence_id: "de1", threshold_id: "th1" })), isFenced, "upgradeWakeUrgency");
  await assert.rejects(fencedCtx.db.runTransaction(async (transaction) => intents.cancelPendingIntent(transaction, fencedCtx.db, UID, fencedCtx.taskRef, fencedTask())), isFenced, "cancelPendingIntent");
  assert.equal(fencedCtx.db.__writes.length, fencedWrites, "fenced writers write nothing");
  // producer rejects a malformed route, cause, or urgent wake without a basis
  for (const [label, params] of [["row with session", { route: { kind: "row", session_id: "s" } }], ["bad cause", { cause: { kind: "OTHER" } }], ["urgent without basis", { urgency: "urgent_recovery" }]]) {
    await assert.rejects(db.runTransaction(async (transaction) => intents.produceWake(transaction, db, { uid: UID, taskRef, task: baseTask(), cause: cause(), route: { kind: "row" }, resumeDestination: "flow:due", urgency: "normal", interactionEpoch: 2, interactionRevision: 5, policyFingerprint: "p".repeat(64), now: Timestamp.fromDate(NOW), ...params })), label);
  }
});

test("C9.3.1 pointer validation rejects a missing, dangling, crossed-task, crossed-instance, or unequal pointer", async () => {
  const { intent, intentId, db } = await seeded();
  const good = db.__docs.get(`users/${UID}/tasks/t1`);
  assert.ok(intents.validateWakePointer(good, "t1", intent, intentId));
  assert.throws(() => intents.validateWakePointer({ ...good, wakeEvidence: undefined }, "t1", intent, intentId), /missing/);
  assert.throws(() => intents.validateWakePointer({ ...good, wakeEvidence: { ...good.wakeEvidence, wake_id: "w1_" + "0".repeat(40) } }, "t1", intent, intentId), /dangling/);
  assert.throws(() => intents.validateWakePointer(good, "t2", intent, intentId), /crossed task/);
  assert.throws(() => intents.validateWakePointer({ ...good, task_instance_id: "ti9" }, "t1", intent, intentId), /crossed instance/);
  assert.throws(() => intents.validateWakePointer({ ...good, wakeEvidence: { ...good.wakeEvidence, intent_id: "ni1_" + "0".repeat(40) } }, "t1", intent, intentId), /unequal/);
});

test("C9.3.2–C9.3.4 claimTaskIntent consumes a pending intent and returns the exact typed route with the exact INTENT_CLAIM record; the same claim operation replays with replayed:true and an unchanged record; another claimant fails INTENT_ALREADY_CLAIMED; the task is unchanged", async () => {
  const { db, intentId, intent } = await seeded();
  const taskBefore = JSON.stringify(db.__docs.get(`users/${UID}/tasks/t1`));
  const response = await claim(db, { intentId });
  assert.deepEqual(Object.keys(response).sort(), ["accountUid", "claimOperationId", "expiresAt", "intentId", "interactionEpoch", "kind", "policyFingerprint", "replayed", "route", "schemaVersion", "taskDocumentId", "taskGenerationEpoch", "taskInstanceId"]);
  assert.deepEqual([response.schemaVersion, response.kind, response.claimOperationId, response.replayed, response.accountUid, response.intentId, response.taskDocumentId, response.taskInstanceId, response.taskGenerationEpoch, response.interactionEpoch, response.policyFingerprint, response.route], [1, "task_route", CLAIM_OP, false, UID, intentId, "t1", "ti1", 3, 2, "p".repeat(64), { kind: "row" }]);
  assert.equal(response.expiresAt, "2026-09-07T11:00:00.000Z", "exact UTC wire of expires_at");
  const consumed = db.__docs.get(`users/${UID}/notificationIntents/${intentId}`);
  assert.deepEqual([consumed.state, consumed.claim_operation_id, consumed.consumed_at instanceof Timestamp], ["consumed", CLAIM_OP, true]);
  assert.equal(JSON.stringify(db.__docs.get(`users/${UID}/tasks/t1`)), taskBefore, "task unchanged");
  const record = db.__docs.get(`users/${UID}/taskPlanOperations/${CLAIM_OP}`);
  assert.deepEqual(Object.keys(record).sort(), ["account_uid", "action", "committed_at", "created_at", "kind", "operation_id", "prior_snapshots", "request_fingerprint", "request_sha256", "response", "response_sha256", "schema_version", "state", "task_identities"]);
  const sha = fence.sha256Hex(fence.TaskCanonicalV1({ action: "claimTaskIntent", intentId, claimOperationId: CLAIM_OP }));
  assert.deepEqual([record.schema_version, record.kind, record.state, record.account_uid, record.operation_id, record.action, record.request_fingerprint, record.request_sha256, record.task_identities, record.prior_snapshots, record.response_sha256, record.created_at.toMillis() === record.committed_at.toMillis()], [1, "INTENT_CLAIM", "COMMITTED", UID, CLAIM_OP, "claimTaskIntent", `op1_${sha}`, sha, [], [], fence.sha256Hex(fence.TaskCanonicalV1(response)), true]);
  const intentWrite = db.__writes.findLast((w) => w.path.includes("/notificationIntents/"));
  const recordWrite = db.__writes.findLast((w) => w.path.includes("/taskPlanOperations/"));
  assert.equal(intentWrite.batch, recordWrite.batch, "consumption and record commit atomically");
  const recordBefore = JSON.stringify(record);
  const replay = await claim(db, { intentId });
  assert.deepEqual(replay, { ...response, replayed: true });
  assert.equal(JSON.stringify(db.__docs.get(`users/${UID}/taskPlanOperations/${CLAIM_OP}`)), recordBefore, "replay never rewrites the record");
  await assert.rejects(claim(db, { intentId, claimOperationId: "22222222-2222-4222-8222-222222222222" }), (e) => e.code === "failed-precondition" && e.details.reason === "INTENT_ALREADY_CLAIMED" && e.details.schemaVersion === 1);
  void intent;
});

test("C9.3.2/C9.3.5 an absent intent is permission-denied/AUTH_FORBIDDEN with zero writes; expired, cancelled, and every stale case (missing task, moved instance, dangling pointer, epoch/fingerprint drift, missing returned handoff) fail conclusively; unauthenticated is AUTH_REQUIRED; the callable reads only the authenticated path", async () => {
  let ctx = await seeded();
  const absent = `ni1_${"0".repeat(40)}`;
  const before = ctx.db.__writes.length;
  await assert.rejects(claim(ctx.db, { intentId: absent }), (e) => e.code === "permission-denied" && e.details.reason === "AUTH_FORBIDDEN");
  assert.equal(ctx.db.__writes.length, before, "zero operation or intent write");
  assert.ok(!ctx.db.__reads.some((r) => r.includes("?")), "no collection or collection-group lookup");
  await assert.rejects(claim(ctx.db, { intentId: ctx.intentId }, null), (e) => e.code === "unauthenticated" && e.details.reason === "AUTH_REQUIRED");
  // another user's uid never reaches this user's intent
  await assert.rejects(claim(ctx.db, { intentId: ctx.intentId }, { uid: "u2" }), (e) => e.code === "permission-denied" && e.details.reason === "AUTH_FORBIDDEN");
  // expired: exactly at expiry is expired
  ctx = await seeded({ clockIso: "2026-09-05T12:00:00.000Z" });
  await assert.rejects(claim(ctx.db, { intentId: ctx.intentId }), (e) => e.details.reason === "INTENT_EXPIRED");
  ctx = await seeded({ clockIso: "2026-09-05T12:00:00.001Z" });
  assert.equal((await claim(ctx.db, { intentId: ctx.intentId })).replayed, false, "one millisecond before expiry claims");
  // cancelled
  ctx = await seeded();
  ctx.db.__docs.get(`users/${UID}/notificationIntents/${ctx.intentId}`).state = "cancelled";
  await assert.rejects(claim(ctx.db, { intentId: ctx.intentId }), (e) => e.details.reason === "INTENT_CANCELLED");
  // stale cases
  const staleCases = [
    ["missing task", (db) => db.__docs.delete(`users/${UID}/tasks/t1`)],
    ["moved instance", (db) => { db.__docs.get(`users/${UID}/tasks/t1`).task_instance_id = "ti2"; }],
    ["dangling pointer", (db) => { db.__docs.get(`users/${UID}/tasks/t1`).wakeEvidence.wake_id = "w1_" + "1".repeat(40); }],
    ["cleared pointer", (db) => { delete db.__docs.get(`users/${UID}/tasks/t1`).wakeEvidence; }],
    ["epoch drift", (db) => { db.__docs.get(`users/${UID}/tasks/t1`).taskInteractionState = { interaction_epoch: 3, policy_fingerprint: "p".repeat(64) }; }],
    ["fingerprint drift", (db) => { db.__docs.get(`users/${UID}/tasks/t1`).taskInteractionState = { interaction_epoch: 2, policy_fingerprint: "q".repeat(64) }; }],
    ["cause drift under a retained wake_id", (db) => { db.__docs.get(`users/${UID}/tasks/t1`).wakeEvidence.cause = { kind: "THRESHOLD", threshold_id: "th9", deadline_evidence_id: "de9" }; }],
    ["absent live policy state", (db) => { delete db.__docs.get(`users/${UID}/tasks/t1`).taskInteractionState; }],
    ["terminal task status (Completed)", (db) => { db.__docs.get(`users/${UID}/tasks/t1`).status = "Completed"; }],
    ["terminal task status (Dismissed)", (db) => { db.__docs.get(`users/${UID}/tasks/t1`).status = "Dismissed"; }],
    ["policy state missing its fingerprint", (db) => { db.__docs.get(`users/${UID}/tasks/t1`).taskInteractionState = { interaction_epoch: 2 }; }]
  ];
  for (const [label, mutate] of staleCases) {
    ctx = await seeded();
    mutate(ctx.db);
    const writes = ctx.db.__writes.length;
    await assert.rejects(claim(ctx.db, { intentId: ctx.intentId }), (e) => e.code === "failed-precondition" && e.details.reason === "INTENT_STALE", label);
    assert.equal(ctx.db.__writes.length, writes, `${label}: no write`);
  }
  // outcome route with a returned session requires the matching returned handoff; a direct waiting transition carries no sessionId
  ctx = await seeded({ route: { kind: "outcome", session_id: "s1" }, task: { ...baseTask(), activeHandoff: { state: "returned", session_id: "s1" } } });
  assert.deepEqual((await claim(ctx.db, { intentId: ctx.intentId })).route, { kind: "outcome", sessionId: "s1" });
  ctx = await seeded({ route: { kind: "outcome", session_id: "s1" }, task: { ...baseTask(), activeHandoff: { state: "opened", session_id: "s1" } } });
  await assert.rejects(claim(ctx.db, { intentId: ctx.intentId }), (e) => e.details.reason === "INTENT_STALE");
  const waiting = { ...baseTask(), status: "matching_in_progress", dispositionContract: { disposition: "WAITING_ON_EXTERNAL" } };
  ctx = await seeded({ route: { kind: "outcome" }, task: waiting });
  assert.deepEqual((await claim(ctx.db, { intentId: ctx.intentId })).route, { kind: "outcome" });
  // C9.3.12 row 5: an outcome route without a session is the WAITING transition's outcome surface; any other state is stale
  ctx = await seeded({ route: { kind: "outcome" }, task: waiting });
  ctx.db.__docs.get(`users/${UID}/tasks/t1`).status = "InProgress";
  await assert.rejects(claim(ctx.db, { intentId: ctx.intentId }), (e) => e.details.reason === "INTENT_STALE", "direct outcome route on a non-WAITING task");
  ctx = await seeded({ route: { kind: "outcome" } });
  await assert.rejects(claim(ctx.db, { intentId: ctx.intentId }), (e) => e.details.reason === "INTENT_STALE", "direct outcome route on an Upcoming task");
  // the root fence: a deleting owner cannot claim
  ctx = await seeded();
  ctx.db.__docs.set(`users/${UID}`, { accountDeletion: { schemaVersion: 1, state: "DELETING", capabilities: [{ operationId: "adel1_00000000-0000-4000-8000-000000000001", proofSHA256: "a".repeat(64) }], startedAt: Timestamp.fromMillis(0), storageGuardAfter: Timestamp.fromMillis(604800000) } });
  await assert.rejects(claim(ctx.db, { intentId: ctx.intentId }), (e) => e.code === "failed-precondition" && e.details.reason === "ACCOUNT_DELETION_FENCED");
});

test("C9.3.2/C9.3.3 request validation and record reuse: surplus or missing members, a non-UUID or uppercase or reserved claimOperationId, a malformed intentId are REQUEST_INVALID before any read; cross-kind reuse, hash mismatch, altered response, or malformed timestamps are OPERATION_REUSED with zero intent mutation; a malformed intent is INTENT_INVALID", async () => {
  const ctx = await seeded();
  const bad = [
    { intentId: ctx.intentId, extra: 1 }, { intentId: undefined }, { intentId: "ni1_short" }, { intentId: ctx.intentId, claimOperationId: "not-a-uuid" },
    { intentId: ctx.intentId, claimOperationId: "AAAAAAAA-1111-4111-8111-111111111111" }, { intentId: ctx.intentId, claimOperationId: "rso1_" + "a".repeat(40) }, { intentId: ctx.intentId, claimOperationId: "pcs1_" + "a".repeat(40) }
  ];
  for (const overrides of bad) {
    let factoryCalls = 0;
    await assert.rejects(handleTaskPlanRequest({ auth: { uid: UID }, data: { action: "claimTaskIntent", claimOperationId: CLAIM_OP, ...overrides } }, () => { factoryCalls += 1; return ctx.db; }, NOW), (e) => e.code === "invalid-argument" && e.details.reason === "REQUEST_INVALID", JSON.stringify(overrides));
    assert.equal(factoryCalls, 0, "rejected before any database access");
  }
  // cross-kind reuse: a lifecycle record at the claim operation id
  ctx.db.__docs.set(`users/${UID}/taskPlanOperations/${CLAIM_OP}`, { kind: "operation", fingerprint: "x", response: {} });
  const intentBefore = JSON.stringify(ctx.db.__docs.get(`users/${UID}/notificationIntents/${ctx.intentId}`));
  await assert.rejects(claim(ctx.db, { intentId: ctx.intentId }), (e) => e.code === "failed-precondition" && e.details.reason === "OPERATION_REUSED" && e.details.operationId === CLAIM_OP);
  assert.equal(JSON.stringify(ctx.db.__docs.get(`users/${UID}/notificationIntents/${ctx.intentId}`)), intentBefore, "zero intent mutation");
  ctx.db.__docs.delete(`users/${UID}/taskPlanOperations/${CLAIM_OP}`);
  const response = await claim(ctx.db, { intentId: ctx.intentId });
  const path = `users/${UID}/taskPlanOperations/${CLAIM_OP}`;
  const good = JSON.parse(JSON.stringify(ctx.db.__docs.get(path)));
  const original = { ...ctx.db.__docs.get(path) };
  for (const [label, mutate] of [
    ["hash mismatch", (r) => { r.request_sha256 = "0".repeat(64); }],
    ["altered response", (r) => { r.response = { ...r.response, taskDocumentId: "t9" }; }],
    ["response account altered with a recomputed digest", (r) => { r.response = { ...r.response, accountUid: "u9" }; r.response_sha256 = fence.sha256Hex(fence.TaskCanonicalV1(r.response)); }],
    ["response surplus member with a recomputed digest", (r) => { r.response = { ...r.response, extra: 1 }; r.response_sha256 = fence.sha256Hex(fence.TaskCanonicalV1(r.response)); }],
    ["response route malformed with a recomputed digest", (r) => { r.response = { ...r.response, route: { kind: "row", sessionId: "s" } }; r.response_sha256 = fence.sha256Hex(fence.TaskCanonicalV1(r.response)); }],
    ["response expiry malformed with a recomputed digest", (r) => { r.response = { ...r.response, expiresAt: "2026-09-07" }; r.response_sha256 = fence.sha256Hex(fence.TaskCanonicalV1(r.response)); }],
    ["response expiry non-calendar with a recomputed digest", (r) => { r.response = { ...r.response, expiresAt: "2026-99-99T99:99:99.999Z" }; r.response_sha256 = fence.sha256Hex(fence.TaskCanonicalV1(r.response)); }],
    ["surplus member", (r) => { r.extra = 1; }],
    ["missing member", (r) => { delete r.prior_snapshots; }],
    ["malformed timestamp", (r) => { r.committed_at = "yesterday"; }],
    ["wrong kind", (r) => { r.kind = "TASK_OPERATION"; }]
  ]) {
    // each defect is applied to the committed record on its own (the previous case's defect must not carry over)
    const record = { ...original };
    mutate(record);
    ctx.db.__docs.set(path, record);
    await assert.rejects(claim(ctx.db, { intentId: ctx.intentId }), (e) => e.details.reason === "OPERATION_REUSED", label);
    ctx.db.__docs.set(path, { ...original });
    assert.deepEqual(await claim(ctx.db, { intentId: ctx.intentId }), { ...response, replayed: true }, `${label}: the untouched record still replays`);
  }
  void good; void response;
  // a malformed intent document is INTENT_INVALID
  const fresh = await seeded();
  fresh.db.__docs.get(`users/${UID}/notificationIntents/${fresh.intentId}`).audience = "system";
  await assert.rejects(claim(fresh.db, { intentId: fresh.intentId }), (e) => e.details.reason === "INTENT_INVALID");
});

test("C9.3.2 the route-expiry wire is the exact UTC millisecond text: leap day, epoch boundary, three fractional digits, uppercase Z; offsets, lowercase z, other precisions, invalid calendars, and years outside four digits never appear; equal ±1 ms parity holds", () => {
  const wire = (ms) => intents.timestampWire(Timestamp.fromMillis(ms));
  assert.equal(wire(Date.parse("2028-02-29T23:59:59.999Z")), "2028-02-29T23:59:59.999Z", "leap day");
  assert.equal(wire(0), "1970-01-01T00:00:00.000Z", "epoch boundary");
  assert.equal(wire(-1), "1969-12-31T23:59:59.999Z");
  assert.equal(wire(1), "1970-01-01T00:00:00.001Z");
  assert.equal(wire(Date.parse("2026-09-06T12:00:00.500Z")), "2026-09-06T12:00:00.500Z");
  const re = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
  assert.equal(wire(Date.parse("9999-12-31T23:59:59.999Z")), "9999-12-31T23:59:59.999Z", "maximum of the stored domain");
  for (const ms of [0, 1, 999, 1000, Date.parse("2000-02-29T00:00:00Z"), Date.parse("2100-12-31T23:59:59.999Z"), Date.parse("9999-12-31T23:59:59.998Z")]) {
    assert.match(wire(ms), re);
    assert.equal(Date.parse(wire(ms)), ms, "round-trips to the same millisecond");
    assert.notEqual(wire(ms + 1), wire(ms));
    assert.notEqual(wire(ms - 1), wire(ms));
  }
  // years outside 0001–9999 cannot exist as Firestore Timestamps, so the four-digit projection is total over the stored domain
  assert.throws(() => Timestamp.fromMillis(Date.parse("+010000-01-01T00:00:00.000Z")), /seconds/);
  assert.throws(() => Timestamp.fromMillis(Date.parse("-000001-01-01T00:00:00.000Z")), /seconds/);
  assert.equal(wire(Date.parse("0001-01-01T00:00:00.000Z")), "0001-01-01T00:00:00.000Z", "minimum selection");
  assert.throws(() => intents.timestampWire({ toMillis: () => Date.parse("+010000-01-01T00:00:00.000Z") }), /wire/, "a non-domain value never reaches the wire");
  for (const bad of ["2026-09-06T12:00:00Z", "2026-09-06T12:00:00.5Z", "2026-09-06T12:00:00.000+00:00", "2026-09-06T12:00:00.000z", "2026-09-06T12:00:00.0000Z", "2026-02-30T12:00:00.000Z", "2026-09-06 12:00:00.000Z"]) assert.equal(re.test(bad) && !Number.isNaN(Date.parse(bad)) && new Date(Date.parse(bad)).toISOString() === bad, false, bad);
});

test("C9.3.1 validateIntent enforces the exact document: members, constants, state union, route grammar, cause pointer form, 24-hour expiry, consumed members", async () => {
  const { intent } = await seeded();
  assert.ok(intents.validateIntent(intent));
  const missing = { ...intent }; delete missing.route;
  const cases = [
    ["surplus", { ...intent, extra: 1 }], ["missing", missing], ["audience", { ...intent, audience: "admin" }], ["state", { ...intent, state: "done" }],
    ["route", { ...intent, route: { kind: "row", session_id: "s" } }], ["cause form", { ...intent, cause: { operation_id: "x" } }], ["expiry", { ...intent, expires_at: Timestamp.fromMillis(intent.created_at.toMillis() + 1) }],
    ["consumed without members", { ...intent, state: "consumed" }], ["pending with claim member", { ...intent, claim_operation_id: CLAIM_OP }]
  ];
  for (const [label, value] of cases) assert.throws(() => intents.validateIntent(value), Error, label);
  assert.ok(intents.validateIntent({ ...intent, state: "consumed", consumed_at: Timestamp.fromMillis(1), claim_operation_id: CLAIM_OP }));
});
