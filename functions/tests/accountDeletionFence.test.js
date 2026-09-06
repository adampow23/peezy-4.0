"use strict";

// S2 (briefs/S2_BRIEF.md): core / remote / zero-finalizer / two-reconciler /
// provider-cache / historical-migration cases. S3 extends this file.
// Offline matrix runs against the in-memory Firestore below; the emulator-backed
// subset runs only when FIRESTORE_EMULATOR_HOST is set.

const assert = require("node:assert/strict");
const test = require("node:test");
const { createHash, randomBytes, randomUUID } = require("node:crypto");
const { Timestamp, FieldPath } = require("firebase-admin/firestore");

const fence = require("../accountDeletionFence");

const { fakeFirestore, FakeClock, compareBytes } = require("./support/fakeFirestore");

function sha256(text) { return createHash("sha256").update(text, "utf8").digest("hex"); }
function b64url(bytes) { return Buffer.from(bytes).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""); }
function freshOperationId() { return `adel1_${randomUUID().toLowerCase()}`; }
function freshProofNonce() { return b64url(randomBytes(32)); }
function ts(iso) { return Timestamp.fromMillis(Date.parse(iso)); }

const UID = "uid-A";
const STARTED = "2026-09-01T00:00:00.000Z";
const GUARD_AFTER = "2026-09-08T00:00:00.000Z"; // STARTED + 604800 s

function capability(uid, operationId, proofNonce) {
  return { operationId, proofSHA256: fence.capabilityProofSHA256({ uid, operationId, proofNonce }) };
}

function sweepingMarker(caps) {
  return { schemaVersion: 1, state: "DELETING", capabilities: caps, startedAt: ts(STARTED), storageGuardAfter: ts(GUARD_AFTER) };
}

function guardingMarker(caps, extra = {}) {
  return { ...sweepingMarker(caps), firestoreCleanupAt: ts("2026-09-01T01:00:00.000Z"), ...extra };
}

function dataDeletedMarker(caps) {
  return {
    ...guardingMarker(caps),
    storageGuardCompletedAt: ts("2026-09-08T00:05:00.000Z"),
    firestoreVersionGuardCompletedAt: ts("2026-09-01T02:00:00.000Z"),
    state: "DATA_DELETED",
    dataDeletedAt: ts("2026-09-08T00:10:00.000Z")
  };
}

function authGuardingMarker(caps) {
  return { ...dataDeletedMarker(caps), state: "AUTH_GUARDING", authAbsenceObservedAt: ts("2026-09-08T00:11:00.000Z"), authGuardAfter: ts("2026-09-09T00:11:00.000Z") };
}

function accountDeletedMarker(caps) {
  return { ...authGuardingMarker(caps), state: "ACCOUNT_DELETED", authGuardCompletedAt: ts("2026-09-09T00:12:00.000Z"), accountDeletedAt: ts("2026-09-09T00:12:00.000Z") };
}

function expectDeletionError(fn, code, details) {
  return assert.rejects(fn, (error) => {
    assert.equal(error.code, code, `code ${error.code} (${JSON.stringify(error.details)})`);
    assert.deepEqual(error.details, details);
    return true;
  });
}

// ---------------------------------------------------------------------------
// I1 — canonical bytes and capability proof
// ---------------------------------------------------------------------------

test("TaskCanonicalV1 is sorted compact JSON and the capability proof hashes it", () => {
  assert.equal(fence.TaskCanonicalV1({ b: [1, { z: "x", a: null }], a: "é" }), '{"a":"é","b":[1,{"a":null,"z":"x"}]}');
  assert.throws(() => fence.TaskCanonicalV1({ a: undefined }), /undefined/);
  assert.equal(fence.TaskCanonicalV1({ a: 1.5, b: -0, c: 1e21, d: 1e-7 }), '{"a":1.5,"b":0,"c":1e+21,"d":1e-7}');
  assert.throws(() => fence.TaskCanonicalV1({ a: Number.NaN }), /finite/);
  assert.throws(() => fence.TaskCanonicalV1({ a: Number.POSITIVE_INFINITY }), /finite/);
  assert.throws(() => fence.TaskCanonicalV1({ $a: 1 }), /key/);
  assert.throws(() => fence.TaskCanonicalV1({ "": 1 }), /key/);
  assert.equal(fence.TaskCanonicalV1({ t: Timestamp.fromMillis(1_500) }), '{"t":{"$firestoreTimestamp":{"nanoseconds":500000000,"seconds":1}}}');
  assert.equal(fence.TaskCanonicalV1({ t: new Date(1_500) }), '{"t":{"$firestoreTimestamp":{"nanoseconds":500000000,"seconds":1}}}');
  const proof = fence.capabilityProofSHA256({ uid: UID, operationId: "adel1_x", proofNonce: "n" });
  assert.equal(proof, sha256('{"operation_id":"adel1_x","proof_nonce":"n","uid":"uid-A"}'));
  assert.equal(fence.first40(proof).length, 40);
});

// ---------------------------------------------------------------------------
// I1 — request union and error union
// ---------------------------------------------------------------------------

test("request union accepts exactly the four actions with exact members", () => {
  const operationId = freshOperationId();
  const proofNonce = freshProofNonce();
  for (const action of ["discover", "begin", "resume", "finalize"]) {
    const cleaned = fence.validateAccountDeletionRequest({ schemaVersion: 1, action, uid: UID, operationId, proofNonce });
    assert.deepEqual(cleaned, { action, uid: UID, operationId, proofNonce });
  }
});

test("request union names the first invalid field in exact precedence and surplus members name request", () => {
  const good = { schemaVersion: 1, action: "begin", uid: UID, operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const cases = [
    [null, "request"],
    [[], "request"],
    [{ ...good, extra: 1 }, "request"],
    [{ ...good, schemaVersion: 2 }, "request"],
    [(() => { const c = { ...good }; delete c.schemaVersion; return c; })(), "request"],
    [{ ...good, action: "delete" }, "action"],
    [{ ...good, action: 7 }, "action"],
    [{ ...good, uid: "" }, "uid"],
    [{ ...good, uid: "a/b" }, "uid"],
    [(() => { const c = { ...good }; delete c.uid; return c; })(), "uid"],
    [{ ...good, operationId: "adel1_NOTUUID" }, "operationId"],
    [{ ...good, operationId: `adel1_${randomUUID().toUpperCase()}` }, "operationId"],
    [{ ...good, proofNonce: `${good.proofNonce}=` }, "proofNonce"],
    [{ ...good, proofNonce: b64url(randomBytes(31)) }, "proofNonce"],
    [{ ...good, proofNonce: good.proofNonce.replace(/./, "+") }, "proofNonce"],
    [{ ...good, action: "nope", uid: "" }, "action"],
    [{ ...good, uid: "", operationId: "x" }, "uid"]
  ];
  for (const [data, field] of cases) {
    assert.throws(() => fence.validateAccountDeletionRequest(data), (error) => {
      assert.equal(error.code, "invalid-argument", JSON.stringify(data));
      assert.deepEqual(error.details, { schemaVersion: 1, reason: "REQUEST_INVALID", field });
      return true;
    }, JSON.stringify(data));
  }
});

test("error union is thrown with exact codes and details and nothing else", () => {
  const cases = [
    ["REQUEST_INVALID", { field: "uid" }, "invalid-argument", { schemaVersion: 1, reason: "REQUEST_INVALID", field: "uid" }],
    ["AUTH_REQUIRED", undefined, "unauthenticated", { schemaVersion: 1, reason: "AUTH_REQUIRED" }],
    ["DELETION_CAPABILITY_INVALID", undefined, "permission-denied", { schemaVersion: 1, reason: "DELETION_CAPABILITY_INVALID" }],
    ["DELETION_RETRY_REQUIRED", undefined, "unavailable", { schemaVersion: 1, reason: "DELETION_RETRY_REQUIRED" }]
  ];
  for (const [reason, extra, code, details] of cases) {
    const error = fence.deletionError(reason, extra);
    assert.equal(error.code, code);
    assert.deepEqual(error.details, details);
    assert.equal(Object.keys(error.details).length, Object.keys(details).length);
  }
  assert.throws(() => fence.deletionError("INTERNAL_SOMETHING"), /reason/);
  assert.throws(() => fence.deletionError("AUTH_REQUIRED", { uid: UID }), /detail/);
});

// ---------------------------------------------------------------------------
// I1 — marker grammar (C3)
// ---------------------------------------------------------------------------

test("marker grammar accepts each of the five exact branches and reports the phase", () => {
  const caps = [capability(UID, freshOperationId(), freshProofNonce())];
  assert.equal(fence.validateAccountDeletionMarker(sweepingMarker(caps)).phase, "DELETING_SWEEPING");
  assert.equal(fence.validateAccountDeletionMarker(guardingMarker(caps)).phase, "DELETING_GUARDING");
  assert.equal(fence.validateAccountDeletionMarker(guardingMarker(caps, { storageGuardCompletedAt: ts("2026-09-08T00:00:01.000Z") })).phase, "DELETING_GUARDING");
  assert.equal(fence.validateAccountDeletionMarker(guardingMarker(caps, { firestoreVersionGuardCompletedAt: ts("2026-09-01T01:00:00.000Z") })).phase, "DELETING_GUARDING");
  assert.equal(fence.validateAccountDeletionMarker(dataDeletedMarker(caps)).phase, "DATA_DELETED");
  assert.equal(fence.validateAccountDeletionMarker(authGuardingMarker(caps)).phase, "AUTH_GUARDING");
  assert.equal(fence.validateAccountDeletionMarker(accountDeletedMarker(caps)).phase, "ACCOUNT_DELETED");
});

test("marker grammar rejects unknown, missing, surplus, wrong-phase, and time-order content", () => {
  const caps = [capability(UID, freshOperationId(), freshProofNonce())];
  const bad = [
    ["state unknown", { ...sweepingMarker(caps), state: "PENDING" }],
    ["schema", { ...sweepingMarker(caps), schemaVersion: 2 }],
    ["missing guardAfter", (() => { const m = sweepingMarker(caps); delete m.storageGuardAfter; return m; })()],
    ["guardAfter relation", { ...sweepingMarker(caps), storageGuardAfter: ts("2026-09-08T00:00:00.001Z") }],
    ["surplus", { ...sweepingMarker(caps), note: "x" }],
    ["sweeping with completion", { ...sweepingMarker(caps), storageGuardCompletedAt: ts("2026-09-09T00:00:00.000Z") }],
    ["guarding storage completion not after guardAfter", guardingMarker(caps, { storageGuardCompletedAt: ts(GUARD_AFTER) })],
    ["guarding version completion before cleanupAt", guardingMarker(caps, { firestoreVersionGuardCompletedAt: ts("2026-09-01T00:59:59.999Z") })],
    ["guarding with dataDeletedAt", guardingMarker(caps, { dataDeletedAt: ts("2026-09-09T00:00:00.000Z") })],
    ["DATA_DELETED missing completion", (() => { const m = dataDeletedMarker(caps); delete m.storageGuardCompletedAt; return m; })()],
    ["DATA_DELETED dataDeletedAt before completion", { ...dataDeletedMarker(caps), dataDeletedAt: ts("2026-09-08T00:04:59.999Z") }],
    ["AUTH_GUARDING missing deadline", (() => { const m = authGuardingMarker(caps); delete m.authGuardAfter; return m; })()],
    ["AUTH_GUARDING deadline before observation", { ...authGuardingMarker(caps), authGuardAfter: ts("2026-09-08T00:10:59.999Z") }],
    ["ACCOUNT_DELETED guardCompleted not after guardAfter", { ...accountDeletedMarker(caps), authGuardCompletedAt: ts("2026-09-09T00:11:00.000Z") }],
    ["ACCOUNT_DELETED accountDeletedAt before guardCompleted", { ...accountDeletedMarker(caps), accountDeletedAt: ts("2026-09-09T00:11:59.999Z") }],
    ["time not Timestamp", { ...sweepingMarker(caps), startedAt: STARTED }],
    ["null", null],
    ["array", []]
  ];
  for (const [label, marker] of bad) {
    assert.throws(() => fence.validateAccountDeletionMarker(marker), (error) => {
      assert.equal(error.code, "ACCOUNT_DELETION_MARKER_MALFORMED", label);
      return true;
    }, label);
  }
});

test("capabilities array is sorted, unique, 1…64, and within 16,384 canonical bytes", () => {
  const ids = Array.from({ length: 65 }, () => freshOperationId()).sort();
  const caps = ids.map((id) => capability(UID, id, freshProofNonce()));
  fence.validateAccountDeletionMarker(sweepingMarker(caps.slice(0, 64)));
  const rejects = [
    ["65", caps],
    ["empty", []],
    ["reordered", [caps[1], caps[0]]],
    ["duplicate", [caps[0], caps[0]]],
    ["same id different proof", [caps[0], { ...caps[0], proofSHA256: sha256("other") }].sort((a, b) => a.operationId < b.operationId ? -1 : 1)],
    ["surplus member", [{ ...caps[0], extra: 1 }]],
    ["proof not hex", [{ ...caps[0], proofSHA256: "zz" }]],
    ["bad operation id", [{ ...caps[0], operationId: "adel1_x" }]]
  ];
  for (const [label, value] of rejects) {
    assert.throws(() => fence.validateAccountDeletionMarker(sweepingMarker(value)), (e) => e.code === "ACCOUNT_DELETION_MARKER_MALFORMED", label);
  }
  assert.ok(Buffer.byteLength(fence.TaskCanonicalV1(caps.slice(0, 64)), "utf8") <= 16384);
});

test("capability classification: member is zero-write, append resorts and preserves bytes, overflow at 64, collision invalid", () => {
  const ids = Array.from({ length: 64 }, () => freshOperationId()).sort();
  const nonces = ids.map(() => freshProofNonce());
  const caps = ids.map((id, i) => capability(UID, id, nonces[i]));
  const marker = sweepingMarker(caps.slice(0, 3));

  const member = fence.classifyCapability(marker, { uid: UID, operationId: ids[1], proofNonce: nonces[1] });
  assert.equal(member.authorityKind, "member");
  assert.equal(member.changed, false);
  assert.deepEqual(member.marker, marker);

  const appended = fence.classifyCapability(marker, { uid: UID, operationId: ids[3], proofNonce: nonces[3] });
  assert.equal(appended.authorityKind, "member");
  assert.equal(appended.changed, true);
  assert.deepEqual(appended.marker.capabilities.map((c) => c.operationId), [ids[0], ids[1], ids[2], ids[3]]);
  assert.deepEqual(marker.capabilities.map((c) => c.operationId), [ids[0], ids[1], ids[2]]);
  assert.equal(appended.marker.startedAt.toMillis(), marker.startedAt.toMillis());
  assert.equal(appended.marker.state, "DELETING");
  assert.deepEqual(Object.keys(appended.marker), Object.keys(marker));

  const full = sweepingMarker(caps);
  const overflow = fence.classifyCapability(full, { uid: UID, operationId: freshOperationId(), proofNonce: freshProofNonce() });
  assert.equal(overflow.authorityKind, "authenticatedOverflow");
  assert.equal(overflow.changed, false);
  assert.deepEqual(overflow.marker, full);

  assert.throws(() => fence.classifyCapability(marker, { uid: UID, operationId: ids[1], proofNonce: freshProofNonce() }), (e) => e.code === "permission-denied" && e.details.reason === "DELETION_CAPABILITY_INVALID");
  // proof is uid-bound: the same operation/nonce under another uid is a collision
  assert.throws(() => fence.classifyCapability(marker, { uid: "uid-B", operationId: ids[1], proofNonce: nonces[1] }), (e) => e.details.reason === "DELETION_CAPABILITY_INVALID");
});

// ---------------------------------------------------------------------------
// I1 — work rows
// ---------------------------------------------------------------------------

test("work row IDs are deterministic and rows validate exactly", () => {
  const expected = `adsw1_${sha256('{"account_uid":"uid-A"}').slice(0, 40)}`;
  assert.equal(fence.storageWorkId(UID), expected);
  assert.equal(fence.authWorkId(UID), `adaw1_${sha256('{"account_uid":"uid-A"}').slice(0, 40)}`);

  const row = {
    schema_version: 1, kind: "ACCOUNT_DELETION_STORAGE_WORK", work_id: expected, account_uid: UID,
    marker_started_at: ts(STARTED), storage_guard_after: ts(GUARD_AFTER), failure_count: 0, next_eligible_run: 0,
    created_at: ts(STARTED), updated_at: ts(STARTED)
  };
  assert.deepEqual(fence.validateStorageWork(row, { uid: UID, marker: sweepingMarker([capability(UID, freshOperationId(), freshProofNonce())]) }), row);
  const rejects = [
    ["count 9", { ...row, failure_count: 9 }],
    ["count -1", { ...row, failure_count: -1 }],
    ["fractional ordinal", { ...row, next_eligible_run: 1.5 }],
    ["wrong id", { ...row, work_id: "adsw1_x" }],
    ["updated before created", { ...row, updated_at: ts("2026-08-31T23:59:59.999Z") }],
    ["marker disagreement", { ...row, marker_started_at: ts(GUARD_AFTER) }],
    ["surplus", { ...row, extra: 1 }],
    ["wrong uid", { ...row, account_uid: "uid-B" }]
  ];
  for (const [label, value] of rejects) {
    assert.throws(() => fence.validateStorageWork(value, { uid: UID, marker: sweepingMarker([capability(UID, freshOperationId(), freshProofNonce())]) }), (e) => e.code === "ACCOUNT_DELETION_STORAGE_WORK_INVARIANT", label);
  }

  const pending = {
    schema_version: 1, kind: "ACCOUNT_DELETION_AUTH_WORK", work_id: fence.authWorkId(UID), account_uid: UID,
    state: "delete_pending", data_deleted_at: ts("2026-09-08T00:10:00.000Z"), authority_generation_id: randomUUID(),
    authority_sha256: sha256("authority"), failure_count: 0, next_eligible_run: 0, created_at: ts("2026-09-08T00:10:00.000Z"), updated_at: ts("2026-09-08T00:10:00.000Z")
  };
  assert.deepEqual(fence.validateAuthWork(pending, { uid: UID }), pending);
  const guarding = { ...pending, state: "guarding", auth_absence_observed_at: ts("2026-09-08T00:11:00.000Z"), auth_guard_after: ts("2026-09-09T00:11:00.000Z") };
  assert.deepEqual(fence.validateAuthWork(guarding, { uid: UID, authResidualRetentionSeconds: 86400 }), guarding);
  assert.throws(() => fence.validateAuthWork({ ...guarding, auth_guard_after: ts("2026-09-09T00:11:01.000Z") }, { uid: UID, authResidualRetentionSeconds: 86400 }), (e) => e.code === "ACCOUNT_DELETION_AUTH_WORK_INVARIANT");
  assert.throws(() => fence.validateAuthWork({ ...pending, auth_guard_after: ts("2026-09-09T00:11:00.000Z") }, { uid: UID }), (e) => e.code === "ACCOUNT_DELETION_AUTH_WORK_INVARIANT");
});

// ---------------------------------------------------------------------------
// I1 — wires
// ---------------------------------------------------------------------------

test("wires carry exactly their member sets with millisecond RFC 3339 strings copied from the root", () => {
  const operationId = freshOperationId();
  const caps = [capability(UID, operationId, freshProofNonce())];
  assert.equal(fence.wireTime(Timestamp.fromMillis(Date.parse("2026-09-08T00:10:00.123Z"))), "2026-09-08T00:10:00.123Z");
  assert.throws(() => fence.wireTime(new Timestamp(1, 500)), /millisecond/);

  assert.deepEqual(fence.absentWire(operationId), { schemaVersion: 1, kind: "account_deletion_discovery", state: "absent", operationId });

  const dataFinal = fence.buildRootWire(dataDeletedMarker(caps), { operationId, authorityKind: "member", replayed: true });
  assert.deepEqual(dataFinal, {
    schemaVersion: 1, kind: "account_deletion_data_final", operationId, authorityKind: "member",
    startedAt: STARTED, dataDeletedAt: "2026-09-08T00:10:00.000Z", replayed: true
  });
  const guarding = fence.buildRootWire(authGuardingMarker(caps), { operationId, authorityKind: "authenticatedOverflow", replayed: false });
  assert.deepEqual(guarding, {
    schemaVersion: 1, kind: "account_deletion_auth_guarding", operationId, authorityKind: "authenticatedOverflow",
    startedAt: STARTED, dataDeletedAt: "2026-09-08T00:10:00.000Z", authAbsenceObservedAt: "2026-09-08T00:11:00.000Z",
    authGuardAfter: "2026-09-09T00:11:00.000Z", replayed: false
  });
  const deleted = fence.buildRootWire(accountDeletedMarker(caps), { operationId, authorityKind: "member", replayed: true });
  assert.deepEqual(deleted, {
    schemaVersion: 1, kind: "account_deletion_account_deleted", operationId, authorityKind: "member",
    startedAt: STARTED, dataDeletedAt: "2026-09-08T00:10:00.000Z", authAbsenceObservedAt: "2026-09-08T00:11:00.000Z",
    authGuardAfter: "2026-09-09T00:11:00.000Z", authGuardCompletedAt: "2026-09-09T00:12:00.000Z", accountDeletedAt: "2026-09-09T00:12:00.000Z", replayed: true
  });
  assert.throws(() => fence.buildRootWire(sweepingMarker(caps), { operationId, authorityKind: "member", replayed: true }), /DELETING/);
});

// ---------------------------------------------------------------------------
// I1 — root fence and registry
// ---------------------------------------------------------------------------

test("assertDeletionAbsent reads every owner root in unsigned-UTF8 order and refuses a present marker", async () => {
  const caps = [capability(UID, freshOperationId(), freshProofNonce())];
  const db = fakeFirestore({ docs: { "users/uid-A": { name: "a" }, "users/uid-B": { accountDeletion: sweepingMarker(caps) }, "users/é": {} } });
  await db.runTransaction(async (transaction) => {
    await fence.assertDeletionAbsent(transaction, db, ["é", "uid-A", "uid-A"]);
  });
  assert.deepEqual(db.__reads, ["users/uid-A", "users/é"]);
  await assert.rejects(
    db.runTransaction((transaction) => fence.assertDeletionAbsent(transaction, db, ["uid-B", "uid-A"])),
    (e) => e.code === "failed-precondition" && e.details.reason === "ACCOUNT_DELETION_FENCED" && Object.keys(e.details).length === 2
  );
  // a malformed marker is still a fence: the root is never treated as absent
  const malformed = fakeFirestore({ docs: { "users/uid-C": { accountDeletion: { state: "DELETING" } } } });
  await assert.rejects(malformed.runTransaction((t) => fence.assertDeletionAbsent(t, malformed, ["uid-C"])), (e) => e.details.reason === "ACCOUNT_DELETION_FENCED");
  await assert.rejects(db.runTransaction((t) => fence.assertDeletionAbsent(t, db, [])), /uid/);
});

test("fence-writer registry is the literal C6.1 map with its explicit exclusions", () => {
  const registry = fence.ACCOUNT_DELETION_FENCE_WRITERS_V1;
  assert.deepEqual(registry["functions/index.js"], ["requestConcierge", "submitTaskFlow", "submitSupportMessage"]);
  assert.deepEqual(registry["functions/supportAdmin.js"], ["adminGetThread", "adminReplySupport", "adminMarkSeen", "adminSetThreadStatus"]);
  assert.ok(registry["functions/taskPlan.js"].includes("*"));
  assert.ok(registry["functions/getWorkflowQualifying.js"].includes("submitWorkflowAnswers"));
  assert.ok(registry["functions/processInventory.js"].includes("onInventoryRoomWritten"));
  for (const path of ["functions/taskDisposition.js", "functions/dispositionTriggers.js", "functions/notificationIntents.js", "functions/spawnTasks.js", "functions/researchTask.js", "functions/peezyChat.js", "functions/packageInventory.js", "functions/submitCheckIn.js", "functions/submitCheckInCore.js", "functions/entitlement.js", "functions/validateSubscription.js"]) {
    assert.ok(Array.isArray(registry[path]), path);
  }
  assert.deepEqual(fence.ACCOUNT_DELETION_COORDINATOR_EXCEPTIONS_V1, ["deleteAccount", "reconcileAccountDeletionStorage", "reconcileAccountDeletionAuth"]);
  assert.deepEqual(fence.DELETION_PARTICIPATING_FUNCTIONS_V1, [
    "requestConcierge", "submitTaskFlow", "submitSupportMessage", "deleteAccount",
    "reconcileAccountDeletionStorage", "reconcileAccountDeletionAuth", "phase2LegacyCreateBlocker",
    "submitWorkflowAnswers", "evaluateDispositionTriggers", "spawnTasks", "processInventory",
    "onInventoryRoomWritten", "researchTask", "peezyChat", "packageInventory", "submitCheckIn",
    "redeemGiftCode", "validateSubscription", "adminGetThread", "adminReplySupport", "adminMarkSeen",
    "adminSetThreadStatus", "resolveProvider"
  ]);
  assert.equal(fence.ACCOUNT_DELETION_FIRESTORE_PAGE_SIZE, 100);
  assert.deepEqual(fence.ACCOUNT_DELETION_EXTERNAL_FAMILIES_V1.map((f) => f.collection + (f.field ? `.${f.field}` : "")), [
    "userKnowledge", "supportThreads", "conciergeRequests.userId", "taskFlowSubmissions.userId", "inventorySessions.userId",
    "workflowSubmissions.userId", "workflowSubmissions.owner", "subscriptions.userId", "vendorReviews.userId",
    "estimateCalibration.userId", "admin/inventoryPackages/packages.userId", "adminNotifications.userId", "giftCodes.redeemedBy"
  ]);
});

// ---------------------------------------------------------------------------
// I1 — outbound lease helper
// ---------------------------------------------------------------------------

test("outbound lease is an exact marker-fenced document that expires 600 seconds after creation and is released after the call", async () => {
  const clock = new FakeClock();
  const db = fakeFirestore({ docs: { "users/uid-A": { name: "a" } }, clock });
  const sent = [];
  const result = await fence.withOutboundLease({ db, now: () => clock.now() }, { uid: UID, channel: "fcm" }, async (lease) => {
    assert.match(lease.leaseId, /^uol1_[0-9a-f-]{36}$/);
    const stored = db.__docs.get(`users/uid-A/outboundLeases/${lease.leaseId}`);
    assert.deepEqual(stored, {
      schema_version: 1, kind: "USER_OUTBOUND_LEASE", account_uid: UID, delivery_id: lease.leaseId, channel: "fcm",
      state: "sending", created_at: clock.now(), expires_at: Timestamp.fromMillis(clock.millis + 600_000)
    });
    assert.ok(Buffer.byteLength(fence.TaskCanonicalV1(stored), "utf8") <= 1024);
    sent.push(lease.leaseId);
    return "ok";
  });
  assert.equal(result, "ok");
  assert.equal([...db.__docs.keys()].filter((p) => p.includes("/outboundLeases/")).length, 0);
  assert.equal(sent.length, 1);
});

test("outbound lease refuses an unknown channel, a present deletion marker, and a 65th live lease; expired leases are pruned first", async () => {
  const clock = new FakeClock();
  const caps = [capability(UID, freshOperationId(), freshProofNonce())];
  await assert.rejects(fence.withOutboundLease({ db: fakeFirestore({ docs: { "users/uid-A": {} }, clock }), now: () => clock.now() }, { uid: UID, channel: "sms" }, async () => {}), /channel/);
  const fenced = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: sweepingMarker(caps) } }, clock });
  let called = false;
  await assert.rejects(fence.withOutboundLease({ db: fenced, now: () => clock.now() }, { uid: UID, channel: "anthropic" }, async () => { called = true; }), (e) => e.details.reason === "ACCOUNT_DELETION_FENCED");
  assert.equal(called, false);

  const live = {};
  for (let i = 0; i < 64; i += 1) {
    const id = `uol1_${randomUUID()}`;
    live[`users/uid-A/outboundLeases/${id}`] = { schema_version: 1, kind: "USER_OUTBOUND_LEASE", account_uid: UID, delivery_id: id, channel: "support_email", state: "sending", created_at: clock.now(), expires_at: Timestamp.fromMillis(clock.millis + 600_000) };
  }
  const saturated = fakeFirestore({ docs: { "users/uid-A": {}, ...live }, clock });
  await assert.rejects(fence.withOutboundLease({ db: saturated, now: () => clock.now() }, { uid: UID, channel: "fcm" }, async () => {}), (e) => e.code === "OUTBOUND_LEASE_CAPACITY");

  clock.advance(600_001);
  const pruned = fakeFirestore({ docs: { "users/uid-A": {}, ...live }, clock });
  await fence.withOutboundLease({ db: pruned, now: () => clock.now() }, { uid: UID, channel: "fcm" }, async () => {});
  assert.equal([...pruned.__docs.keys()].filter((p) => p.includes("/outboundLeases/")).length, 0);
});

// ---------------------------------------------------------------------------
// I2 — deleteAccount reducers and the application sweep (C2.3, C3, §11)
// ---------------------------------------------------------------------------

const RETRY = { schemaVersion: 1, reason: "DELETION_RETRY_REQUIRED" };
const CAP_INVALID = { schemaVersion: 1, reason: "DELETION_CAPABILITY_INVALID" };

function fakeAuth(script = {}) {
  const calls = [];
  const notFound = () => { const e = new Error("no user"); e.code = "auth/user-not-found"; return e; };
  return {
    calls,
    async getUser(uid) {
      calls.push(["getUser", uid]);
      const behavior = script.getUser ? script.getUser(uid, calls) : "absent";
      if (behavior === "absent") throw notFound();
      if (behavior === "present") return { uid };
      if (behavior === "hang") return new Promise(() => {});
      throw behavior;
    },
    async deleteUser(uid) {
      calls.push(["deleteUser", uid]);
      const behavior = script.deleteUser ? script.deleteUser(uid, calls) : "ok";
      if (behavior === "ok") return undefined;
      if (behavior === "absent") throw notFound();
      if (behavior === "hang") return new Promise(() => {});
      throw behavior;
    }
  };
}

function fakeBucket({ objects = [], softDeleted = [], name = "peezy-1ecrdl.firebasestorage.app", metageneration = "3", statusCode = 200, deleteBehavior, metadataTuple } = {}) {
  const calls = [];
  const live = objects.map((o) => ({ generation: "1", ...o }));
  const soft = softDeleted.map((o) => ({ generation: "1", ...o }));
  const raw = (o) => {
    const item = { bucket: name, name: o.name, generation: o.generation };
    for (const key of ["timeDeleted", "temporaryHold", "eventBasedHold"]) if (o[key] !== undefined) item[key] = o[key];
    return item;
  };
  return {
    name, calls, live, soft,
    async getMetadata() {
      calls.push(["getMetadata"]);
      return metadataTuple || [{ name, metageneration }, { statusCode }];
    },
    async getFiles(query) {
      calls.push(["getFiles", { ...query }]);
      const source = query.softDeleted ? soft : live;
      const matching = source.filter((o) => o.name.startsWith(query.prefix)).sort((a, b) => (a.name < b.name ? -1 : 1));
      const page = matching.slice(0, query.maxResults);
      const response = {};
      if (page.length) response.items = page.map(raw);
      let nextQuery = null;
      if (matching.length > page.length) {
        response.nextPageToken = `tok-${page.length}`;
        nextQuery = { ...query, pageToken: response.nextPageToken };
      }
      const files = page.map((o) => ({ name: o.name, bucket: { name }, metadata: raw(o), generation: Number(o.generation) }));
      return [files, nextQuery, response];
    },
    file(objectName, options) {
      return {
        async delete() {
          calls.push(["delete", objectName, options]);
          if (deleteBehavior) { const injected = deleteBehavior(objectName, calls); if (injected) throw injected; }
          const index = live.findIndex((o) => o.name === objectName);
          if (index < 0) { const e = new Error("not found"); e.code = 404; throw e; }
          const expected = options?.preconditionOpts?.ifGenerationMatch;
          if (typeof expected !== "string" || expected !== live[index].generation) { const e = new Error("precondition failed"); e.code = 412; throw e; }
          live.splice(index, 1);
        }
      };
    }
  };
}

function testEvidence(overrides = {}) {
  return {
    ok: true,
    authority: {
      generationId: "11111111-1111-4111-8111-111111111111",
      authoritySHA256: sha256("authority"),
      authResidualRetentionSeconds: 86400,
      authResidualChecks: residualChecks(),
      ...overrides
    }
  };
}

const DOCUMENTS_ROOT = "projects/demo-peezy-phase1/databases/(default)/documents";

function makeDeps({ db, clock, auth = fakeAuth(), bucket = fakeBucket(), evidence = testEvidence(), listCollectionIds, verifyBucketConfiguration, budget, hooks, timeouts, evidenceFence } = {}) {
  const logs = [];
  const firestoreClient = {
    async listCollectionIds(request, options) {
      assert.deepEqual(options, { autoPaginate: false });
      assert.deepEqual(Object.keys(request).sort(), ["pageSize", "parent"]);
      assert.equal(request.pageSize, 100);
      assert.ok(request.parent.startsWith(`${DOCUMENTS_ROOT}/`));
      if (listCollectionIds) return listCollectionIds(request);
      return db.listCollectionIdsTuple(request.parent.slice(DOCUMENTS_ROOT.length + 1), request);
    }
  };
  return {
    db, auth, bucket, logs, hooks: hooks || {},
    evidence: () => evidence,
    now: () => clock.now(),
    log: (code, counts) => logs.push([code, counts]),
    firestore: { client: firestoreClient, documentsRoot: DOCUMENTS_ROOT },
    verifyBucketConfiguration: verifyBucketConfiguration || (() => {}),
    evidenceFence: evidenceFence || (async () => ({ earliestVersionTime: clock.now() })),
    budget: { sweeps: 4, storagePages: 4, deadlineMs: 42_000, ...budget },
    timeouts: { getUserMs: 3000, deleteUserMs: 10000, ...timeouts }
  };
}

async function call(deps, action, { uid = UID, operationId, proofNonce, authUid = uid } = {}) {
  const request = { data: { schemaVersion: 1, action, uid, operationId, proofNonce } };
  if (authUid) request.auth = { uid: authUid };
  return fence.handleAccountDeletionRequest(request, deps);
}

function markerOf(db, uid = UID) {
  return db.__docs.get(`users/${uid}`)?.accountDeletion;
}

async function driveToGuarding(deps, credentials, limit = 12) {
  for (let i = 0; i < limit; i += 1) {
    await expectDeletionError(() => call(deps, "resume", credentials), "unavailable", RETRY);
    const marker = markerOf(deps.db);
    if (marker && fence.validateAccountDeletionMarker(marker).phase === "DELETING_GUARDING") return marker;
  }
  throw new Error("guarding not reached");
}

test("discover with no marker returns the absent wire and writes nothing; auth is required and must match; evidence gates every mutation", async () => {
  const clock = new FakeClock();
  const db = fakeFirestore({ docs: { "users/uid-A": { name: "A" } }, clock });
  const deps = makeDeps({ db, clock });
  const operationId = freshOperationId();
  const proofNonce = freshProofNonce();
  assert.deepEqual(await call(deps, "discover", { operationId, proofNonce }), fence.absentWire(operationId));
  assert.equal(db.__writes.length, 0);
  await expectDeletionError(() => call(deps, "discover", { operationId, proofNonce, authUid: null }), "unauthenticated", { schemaVersion: 1, reason: "AUTH_REQUIRED" });
  await expectDeletionError(() => call(deps, "begin", { operationId, proofNonce, authUid: null }), "unauthenticated", { schemaVersion: 1, reason: "AUTH_REQUIRED" });
  await expectDeletionError(() => call(deps, "discover", { operationId, proofNonce, authUid: "uid-B" }), "permission-denied", CAP_INVALID);
  await expectDeletionError(() => call(deps, "resume", { operationId, proofNonce, authUid: null }), "permission-denied", CAP_INVALID);
  await expectDeletionError(() => call(deps, "finalize", { operationId, proofNonce }), "permission-denied", CAP_INVALID);
  await expectDeletionError(() => call(deps, "discover", { operationId: "adel1_x", proofNonce }), "invalid-argument", { schemaVersion: 1, reason: "REQUEST_INVALID", field: "operationId" });
  assert.equal(db.__writes.length, 0);

  const inactive = makeDeps({ db, clock, evidence: { ok: false, code: "PROVIDER_EVIDENCE_NOT_ACTIVATED" } });
  assert.deepEqual(await call(inactive, "discover", { operationId, proofNonce }), fence.absentWire(operationId));
  await expectDeletionError(() => call(inactive, "begin", { operationId, proofNonce }), "unavailable", RETRY);
  assert.equal(db.__writes.length, 0);
  assert.ok(inactive.logs.some(([code]) => code === "PROVIDER_EVIDENCE_NOT_ACTIVATED"));
});

test("begin on marker absence creates DELETING-sweeping plus its storage work row, scrubs the root to the marker, and two empty sweeps reach guarding", async () => {
  const clock = new FakeClock("2026-09-01T00:00:00.000Z");
  const db = fakeFirestore({ docs: { "users/uid-A": { name: "A", email: "a@example.com" } }, clock });
  const deps = makeDeps({ db, clock });
  const operationId = freshOperationId();
  const proofNonce = freshProofNonce();
  await expectDeletionError(() => call(deps, "begin", { operationId, proofNonce }), "unavailable", RETRY);
  const root = db.__docs.get("users/uid-A");
  assert.deepEqual(Object.keys(root), ["accountDeletion"]);
  const marker = root.accountDeletion;
  assert.equal(fence.validateAccountDeletionMarker(marker).phase, "DELETING_GUARDING");
  assert.deepEqual(marker.capabilities, [capability(UID, operationId, proofNonce)]);
  assert.equal(marker.startedAt.toMillis(), Date.parse("2026-09-01T00:00:00.000Z"));
  assert.equal(marker.storageGuardAfter.toMillis(), Date.parse("2026-09-08T00:00:00.000Z"));
  assert.equal(marker.firestoreCleanupAt.toMillis(), Date.parse("2026-09-01T00:00:00.000Z"));
  const work = db.__docs.get(`accountDeletionStorageWork/${fence.storageWorkId(UID)}`);
  fence.validateStorageWork(work, { uid: UID, marker });
  assert.equal(work.failure_count, 0);
  assert.equal(work.next_eligible_run, 0);
  assert.ok(work.created_at.isEqual(marker.startedAt) && work.updated_at.isEqual(marker.startedAt));
  // the first mutation was the marker+work creation in one transaction
  const first = db.__writes.slice(0, 2).map((w) => [w.type, w.path]).sort();
  assert.deepEqual(first, [["create", `accountDeletionStorageWork/${fence.storageWorkId(UID)}`], ["set", "users/uid-A"]]);
  // begin again is a member replay: guarding → queued member, zero byte change
  const before = JSON.stringify([...db.__docs.entries()]);
  await expectDeletionError(() => call(deps, "begin", { operationId, proofNonce }), "unavailable", RETRY);
  assert.equal(JSON.stringify([...db.__docs.entries()]), before);
});

test("begin prunes expired leases in its creating transaction and refuses a live or malformed lease without creating a marker", async () => {
  const clock = new FakeClock();
  const operationId = freshOperationId();
  const proofNonce = freshProofNonce();
  const lease = (created) => ({ schema_version: 1, kind: "USER_OUTBOUND_LEASE", account_uid: UID, delivery_id: "d", channel: "fcm", state: "sending", created_at: Timestamp.fromMillis(created), expires_at: Timestamp.fromMillis(created + 600_000) });
  const liveId = `uol1_${randomUUID()}`;
  const live = fakeFirestore({ docs: { "users/uid-A": {}, [`users/uid-A/outboundLeases/${liveId}`]: lease(clock.millis - 1000) }, clock });
  await expectDeletionError(() => call(makeDeps({ db: live, clock }), "begin", { operationId, proofNonce }), "unavailable", RETRY);
  assert.equal(markerOf(live), undefined);
  assert.ok(live.__docs.has(`users/uid-A/outboundLeases/${liveId}`));

  const expiredId = `uol1_${randomUUID()}`;
  const expired = fakeFirestore({ docs: { "users/uid-A": {}, [`users/uid-A/outboundLeases/${expiredId}`]: lease(clock.millis - 600_001) }, clock });
  await expectDeletionError(() => call(makeDeps({ db: expired, clock }), "begin", { operationId, proofNonce }), "unavailable", RETRY);
  assert.ok(markerOf(expired));
  assert.equal(expired.__docs.has(`users/uid-A/outboundLeases/${expiredId}`), false);

  const malformed = fakeFirestore({ docs: { "users/uid-A": {}, [`users/uid-A/outboundLeases/uol1_${randomUUID()}`]: { junk: true } }, clock });
  const deps = makeDeps({ db: malformed, clock });
  await expectDeletionError(() => call(deps, "begin", { operationId, proofNonce }), "unavailable", RETRY);
  assert.equal(markerOf(malformed), undefined);
  assert.ok(deps.logs.some(([code]) => code === "OUTBOUND_LEASE_INVARIANT"));
});

test("enrollment: a second capability appends and resorts with every other marker byte preserved; a collision is invalid; the 65th is authenticatedOverflow with zero marker write; resume never enrolls; DELETING-guarding changes no byte", async () => {
  const clock = new FakeClock();
  const ids = Array.from({ length: 66 }, () => freshOperationId()).sort();
  const nonces = ids.map(() => freshProofNonce());
  const seeded = dataDeletedMarker([capability(UID, ids[1], nonces[1])]);
  const db = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: seeded } }, clock });
  const deps = makeDeps({ db, clock });

  const wire = await call(deps, "begin", { operationId: ids[0], proofNonce: nonces[0] });
  assert.equal(wire.kind, "account_deletion_data_final");
  const appended = markerOf(db);
  assert.deepEqual(appended.capabilities.map((c) => c.operationId), [ids[0], ids[1]]);
  assert.deepEqual({ ...appended, capabilities: null }, { ...seeded, capabilities: null });
  assert.deepEqual(Object.keys(appended), Object.keys(seeded));

  await expectDeletionError(() => call(deps, "discover", { operationId: ids[1], proofNonce: freshProofNonce() }), "permission-denied", CAP_INVALID);
  await expectDeletionError(() => call(deps, "resume", { operationId: ids[2], proofNonce: nonces[2], authUid: null }), "permission-denied", CAP_INVALID);
  assert.deepEqual(markerOf(db).capabilities.map((c) => c.operationId), [ids[0], ids[1]]);

  // DELETING-guarding: a nonmember discover/begin throws the queued member and writes nothing (C2.3)
  const guarding = guardingMarker([capability(UID, ids[1], nonces[1])]);
  const guardingDb = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: guarding } }, clock });
  await expectDeletionError(() => call(makeDeps({ db: guardingDb, clock }), "begin", { operationId: ids[0], proofNonce: nonces[0] }), "unavailable", RETRY);
  assert.deepEqual(markerOf(guardingDb), guarding);
  assert.equal(guardingDb.__writes.length, 0);

  const full = dataDeletedMarker(ids.slice(0, 64).map((id, i) => capability(UID, id, nonces[i])));
  const fullDb = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: full } }, clock });
  const fullDeps = makeDeps({ db: fullDb, clock });
  assert.equal((await call(fullDeps, "begin", { operationId: ids[64], proofNonce: nonces[64] })).authorityKind, "authenticatedOverflow");
  assert.deepEqual(markerOf(fullDb), full);
  assert.equal(fullDb.__writes.length, 0);
  await expectDeletionError(() => call(fullDeps, "resume", { operationId: ids[64], proofNonce: nonces[64], authUid: null }), "permission-denied", CAP_INVALID);
  // a malformed marker is nondisclosing capability-invalid for every action
  const broken = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: { ...full, storageGuardAfter: ts("2026-09-08T00:00:00.001Z") } } }, clock });
  await expectDeletionError(() => call(makeDeps({ db: broken, clock }), "discover", { operationId: ids[0], proofNonce: nonces[0] }), "permission-denied", CAP_INVALID);
  assert.equal(broken.__writes.length, 0);
});

test("Firestore 0/1/100/101 and two universal empty sweeps", async () => {
  for (const count of [0, 1, 100, 101]) {
    const clock = new FakeClock();
    const docs = { "users/uid-A": { name: "A" }, "users/uid-B/tasks/t": { keep: true } };
    for (let i = 0; i < count; i += 1) {
      docs[`users/uid-A/c${String(i).padStart(3, "0")}/d`] = { i };
      docs[`users/uid-A/c${String(i).padStart(3, "0")}/d/nested/x`] = { i };
    }
    docs["users/uid-A/orphan/missing/deep/leaf"] = { orphan: true };
    const db = fakeFirestore({ docs, clock });
    const deps = makeDeps({ db, clock, budget: { sweeps: 3 } });
    const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
    await expectDeletionError(() => call(deps, "begin", credentials), "unavailable", RETRY);
    await driveToGuarding(deps, credentials);
    assert.equal([...db.__docs.keys()].filter((p) => p.startsWith("users/uid-A/")).length, 0, `count ${count}`);
    assert.ok(db.__docs.has("users/uid-B/tasks/t"));
    assert.deepEqual(Object.keys(db.__docs.get("users/uid-A")), ["accountDeletion"]);
  }
  // a malformed listCollectionIds tuple fails the sweep with zero nomination
  const clock = new FakeClock();
  const db = fakeFirestore({ docs: { "users/uid-A": {}, "users/uid-A/tasks/t": {} }, clock });
  const tuples = [
    [["tasks"], null],
    [["tasks"], null, { collectionIds: ["tasks"] }],
    [["tasks"], null, { collectionIds: ["other"], nextPageToken: "" }],
    [["tasks"], null, { collectionIds: ["tasks"], nextPageToken: "more" }],
    [["a/b"], null, { collectionIds: ["a/b"], nextPageToken: "" }],
    [["tasks", "tasks"], null, { collectionIds: ["tasks", "tasks"], nextPageToken: "" }]
  ];
  for (const tuple of tuples) {
    const deps = makeDeps({ db, clock, listCollectionIds: () => tuple });
    const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
    await expectDeletionError(() => call(deps, "begin", credentials), "unavailable", RETRY);
    assert.ok(db.__docs.has("users/uid-A/tasks/t"), JSON.stringify(tuple));
    assert.equal(fence.validateAccountDeletionMarker(markerOf(db)).phase, "DELETING_SWEEPING");
    assert.ok(deps.logs.some(([code]) => code === "ACCOUNT_DELETION_LIST_COLLECTIONS_INVARIANT"));
    db.__docs.get("users/uid-A").accountDeletion = undefined; delete db.__docs.get("users/uid-A").accountDeletion;
    db.__docs.delete(`accountDeletionStorageWork/${fence.storageWorkId(UID)}`);
  }
});

test("a lease observed after DELETING is OUTBOUND_LEASE_INVARIANT: the sweep blocks, the lease survives byte-for-byte, and guarding is never entered", async () => {
  const clock = new FakeClock();
  const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const leaseId = `uol1_${randomUUID()}`;
  const lease = { schema_version: 1, kind: "USER_OUTBOUND_LEASE", account_uid: UID, delivery_id: "d", channel: "anthropic", state: "sending", created_at: clock.now(), expires_at: Timestamp.fromMillis(clock.millis + 600_000) };
  const db = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: sweepingMarker([capability(UID, credentials.operationId, credentials.proofNonce)]) }, [`users/uid-A/outboundLeases/${leaseId}`]: lease }, clock });
  const deps = makeDeps({ db, clock });
  for (let i = 0; i < 3; i += 1) await expectDeletionError(() => call(deps, "resume", credentials), "unavailable", RETRY);
  assert.deepEqual(db.__docs.get(`users/uid-A/outboundLeases/${leaseId}`), lease);
  assert.equal(fence.validateAccountDeletionMarker(markerOf(db)).phase, "DELETING_SWEEPING");
  assert.ok(deps.logs.some(([code]) => code === "OUTBOUND_LEASE_INVARIANT"));
  assert.equal(db.__writes.filter((w) => w.path.includes("/outboundLeases/")).length, 0);
});

test("external families: pages nominate, rereads authorize, drift skips, the workflow union dedups, gift codes are scrubbed, and vendor strikes sourced by the review are removed", async () => {
  const clock = new FakeClock();
  const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const strike = (source) => ({ date: clock.now(), source, severity: "high", status: "confirmed", note: "x" });
  const docs = {
    "users/uid-A": { accountDeletion: sweepingMarker([capability(UID, credentials.operationId, credentials.proofNonce)]) },
    "userKnowledge/uid-A": { facts: 1 }, "userKnowledge/uid-B": { facts: 2 },
    "supportThreads/uid-A": { status: "open" }, "supportThreads/uid-A/messages/m1": { text: "hi" }, "supportThreads/uid-B": { status: "open" },
    "conciergeRequests/r1": { userId: UID }, "conciergeRequests/r2": { userId: "uid-B" }, "conciergeRequests/drift": { userId: UID },
    "taskFlowSubmissions/t1": { userId: UID },
    "inventorySessions/i1": { userId: UID },
    "workflowSubmissions/w1": { userId: UID, owner: UID }, "workflowSubmissions/w2": { owner: UID }, "workflowSubmissions/w3": { userId: "uid-B", owner: "uid-B" },
    "subscriptions/s1": { userId: UID },
    "vendorReviews/rv1": { userId: UID, vendorId: "v1" }, "vendorReviews/rv2": { userId: "uid-B", vendorId: "v1" }, "vendorReviews/rv3": { userId: UID, vendorId: "v-missing" },
    "vendors/v1": { active: false, accountability: { strikes: [strike("rv1"), strike("rv1"), strike("rv2")] } },
    "estimateCalibration/e1": { userId: UID },
    "admin/inventoryPackages/packages/p1": { userId: UID },
    "adminNotifications/n1": { userId: UID },
    "giftCodes/g1": { redeemedBy: UID, status: "consumed", redeemedAt: clock.now() }, "giftCodes/g2": { redeemedBy: "uid-B", status: "consumed" }
  };
  const db = fakeFirestore({ docs, clock });
  const deps = makeDeps({ db, clock, budget: { sweeps: 6 }, hooks: {
    beforeFamilyReread: (family, path) => {
      if (path === "conciergeRequests/drift") db.__docs.get(path).userId = "uid-B";
    }
  } });
  await driveToGuarding(deps, credentials);
  const remaining = [...db.__docs.keys()].sort();
  for (const gone of ["userKnowledge/uid-A", "supportThreads/uid-A", "supportThreads/uid-A/messages/m1", "conciergeRequests/r1", "taskFlowSubmissions/t1", "inventorySessions/i1", "workflowSubmissions/w1", "workflowSubmissions/w2", "subscriptions/s1", "vendorReviews/rv1", "vendorReviews/rv3", "estimateCalibration/e1", "admin/inventoryPackages/packages/p1", "adminNotifications/n1"]) {
    assert.equal(remaining.includes(gone), false, gone);
  }
  for (const kept of ["userKnowledge/uid-B", "supportThreads/uid-B", "conciergeRequests/r2", "conciergeRequests/drift", "workflowSubmissions/w3", "vendorReviews/rv2", "giftCodes/g2", "vendors/v1"]) {
    assert.ok(remaining.includes(kept), kept);
  }
  assert.deepEqual(db.__docs.get("giftCodes/g1"), { status: "consumed", redeemedAt: clock.now() });
  const vendor = db.__docs.get("vendors/v1");
  assert.deepEqual(vendor.accountability.strikes.map((s) => s.source), ["rv2"]);
  assert.equal(vendor.active, false);
  assert.equal(db.__docs.get("conciergeRequests/drift").userId, "uid-B");
});

test("Storage 0/1/100/101 retained-copy and guard boundary", async () => {
  for (const count of [0, 1, 100, 101]) {
    const clock = new FakeClock();
    const objects = [];
    for (let i = 0; i < count; i += 1) {
      objects.push({ name: `inventory/uid-A/frame-${String(i).padStart(3, "0")}.jpg`, generation: String(1000 + i) });
      objects.push({ name: `users/uid-A/file-${String(i).padStart(3, "0")}.bin`, generation: String(2000 + i) });
    }
    objects.push({ name: "inventory/uid-B/keep.jpg", generation: "7" }, { name: "users/uid-B/keep.bin", generation: "8" }, { name: "inventory/uid-AA/keep.jpg", generation: "9" });
    const bucket = fakeBucket({ objects });
    const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
    const db = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: sweepingMarker([capability(UID, credentials.operationId, credentials.proofNonce)]) } }, clock });
    const deps = makeDeps({ db, clock, bucket, budget: { sweeps: 4, storagePages: 8 } });
    await driveToGuarding(deps, credentials);
    assert.deepEqual(bucket.live.map((o) => o.name).sort(), ["inventory/uid-AA/keep.jpg", "inventory/uid-B/keep.jpg", "users/uid-B/keep.bin"], `count ${count}`);
    const deletes = bucket.calls.filter(([kind]) => kind === "delete");
    assert.equal(deletes.length, count * 2);
    for (const [, objectName, options] of deletes) {
      assert.deepEqual(Object.keys(options), ["preconditionOpts"]);
      assert.equal(typeof options.preconditionOpts.ifGenerationMatch, "string");
      assert.ok(objectName.startsWith("inventory/uid-A/") || objectName.startsWith("users/uid-A/"));
    }
    const lists = bucket.calls.filter(([kind]) => kind === "getFiles").map(([, q]) => q);
    assert.ok(lists.every((q) => q.autoPaginate === false && q.pageToken === undefined && (q.versions === true || q.softDeleted === true)));
    assert.ok(lists.some((q) => q.softDeleted === true && q.maxResults === 1 && q.prefix === "inventory/uid-A/"));
    assert.ok(lists.some((q) => q.softDeleted === true && q.maxResults === 1 && q.prefix === "users/uid-A/"));
    assert.ok(lists.filter((q) => q.versions === true).every((q) => q.maxResults === 100));
    assert.equal(bucket.calls[0][0], "getMetadata");
  }

  const blockers = [
    ["soft-deleted item", fakeBucket({ softDeleted: [{ name: "users/uid-A/old.bin", timeDeleted: "2026-09-01T00:00:00.000Z" }] }), "ACCOUNT_DELETION_SOFT_DELETED_OBJECT_PRESENT"],
    ["held object", fakeBucket({ objects: [{ name: "inventory/uid-A/held.jpg", temporaryHold: true }] }), "ACCOUNT_DELETION_NONCURRENT_GENERATION_PRESENT"],
    ["noncurrent generation", fakeBucket({ objects: [{ name: "inventory/uid-A/nc.jpg", timeDeleted: "2026-09-01T00:00:00.000Z" }] }), "ACCOUNT_DELETION_NONCURRENT_GENERATION_PRESENT"],
    ["metadata tuple", fakeBucket({ objects: [{ name: "inventory/uid-A/x.jpg" }], metadataTuple: [{ name: "peezy-1ecrdl.firebasestorage.app", metageneration: "3" }] }), "ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT"],
    ["non-200", fakeBucket({ objects: [{ name: "inventory/uid-A/x.jpg" }], statusCode: 500 }), "ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT"]
  ];
  for (const [label, bucket, code] of blockers) {
    const clock = new FakeClock();
    const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
    const db = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: sweepingMarker([capability(UID, credentials.operationId, credentials.proofNonce)]) } }, clock });
    const deps = makeDeps({ db, clock, bucket });
    await expectDeletionError(() => call(deps, "resume", credentials), "unavailable", RETRY);
    assert.equal(fence.validateAccountDeletionMarker(markerOf(db)).phase, "DELETING_SWEEPING", label);
    assert.ok(deps.logs.some(([c]) => c === code), `${label}: ${JSON.stringify(deps.logs)}`);
    assert.equal(bucket.calls.filter(([kind]) => kind === "delete").length, 0, label);
  }

  // config drift check runs before any listing; 404 is idempotent absence; 412 restarts from an absent token
  const clock = new FakeClock();
  const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const driftDb = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: sweepingMarker([capability(UID, credentials.operationId, credentials.proofNonce)]) } }, clock });
  const driftBucket = fakeBucket({ objects: [{ name: "users/uid-A/a.bin" }] });
  const drift = makeDeps({ db: driftDb, clock, bucket: driftBucket, verifyBucketConfiguration: () => { throw new fence.InvariantError("ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT"); } });
  await expectDeletionError(() => call(drift, "resume", credentials), "unavailable", RETRY);
  assert.deepEqual(driftBucket.calls.map(([k]) => k), ["getMetadata"]);

  let injected = 0;
  const raceBucket = fakeBucket({ objects: [{ name: "users/uid-A/a.bin" }, { name: "users/uid-A/b.bin" }], deleteBehavior: (name) => {
    if (name === "users/uid-A/a.bin" && injected === 0) { injected += 1; const e = new Error("gone"); e.code = 404; return e; }
    if (name === "users/uid-A/b.bin" && injected === 1) { injected += 1; const e = new Error("stale"); e.code = 412; return e; }
    return null;
  } });
  const raceDb = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: sweepingMarker([capability(UID, credentials.operationId, credentials.proofNonce)]) } }, clock });
  const race = makeDeps({ db: raceDb, clock, bucket: raceBucket, budget: { sweeps: 4, storagePages: 8 } });
  await driveToGuarding(race, credentials);
  assert.deepEqual(raceBucket.live, []);
});

test("DELETING-guarding: every action throws the queued member and changes no byte", async () => {
  const clock = new FakeClock();
  const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const marker = guardingMarker([capability(UID, credentials.operationId, credentials.proofNonce)]);
  const db = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: marker }, "users/uid-A/late/doc": { late: true } }, clock });
  const deps = makeDeps({ db, clock });
  for (const action of ["discover", "begin", "resume", "finalize"]) {
    await expectDeletionError(() => call(deps, action, credentials), "unavailable", RETRY);
  }
  assert.equal(db.__writes.length, 0);
  assert.ok(db.__docs.has("users/uid-A/late/doc"));
  assert.equal(deps.auth.calls.length, 0);
});

test("DATA_DELETED: discover/begin/resume return the data-final wire with replayed:true and values copied from the root; nothing is written", async () => {
  const clock = new FakeClock();
  const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const marker = dataDeletedMarker([capability(UID, credentials.operationId, credentials.proofNonce)]);
  const db = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: marker } }, clock });
  const deps = makeDeps({ db, clock });
  for (const action of ["discover", "begin", "resume"]) {
    assert.deepEqual(await call(deps, action, { ...credentials, authUid: action === "resume" ? null : UID }), {
      schemaVersion: 1, kind: "account_deletion_data_final", operationId: credentials.operationId, authorityKind: "member",
      startedAt: STARTED, dataDeletedAt: "2026-09-08T00:10:00.000Z", replayed: true
    });
  }
  assert.equal(db.__writes.length, 0);
  // a second device enrolls and receives its own operationId; overflow at 64 is authenticatedOverflow
  const other = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const wire = await call(deps, "discover", other);
  assert.equal(wire.operationId, other.operationId);
  assert.equal(wire.authorityKind, "member");
  assert.equal(markerOf(db).capabilities.length, 2);
});

test("finalize at DATA_DELETED: evidence, zero leases, absent storage work, pending auth work, Auth reducer, then AUTH_GUARDING with replayed:false; replays are replayed:true", async () => {
  const clock = new FakeClock("2026-09-08T00:20:00.000Z");
  const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const marker = dataDeletedMarker([capability(UID, credentials.operationId, credentials.proofNonce)]);
  const db = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: marker } }, clock });
  const auth = fakeAuth();
  const deps = makeDeps({ db, clock, auth });
  const wire = await call(deps, "finalize", { ...credentials, authUid: null });
  assert.deepEqual(wire, {
    schemaVersion: 1, kind: "account_deletion_auth_guarding", operationId: credentials.operationId, authorityKind: "member",
    startedAt: STARTED, dataDeletedAt: "2026-09-08T00:10:00.000Z", authAbsenceObservedAt: "2026-09-08T00:20:00.000Z",
    authGuardAfter: "2026-09-09T00:20:00.000Z", replayed: false
  });
  assert.deepEqual(auth.calls, [["getUser", UID]]);
  const after = markerOf(db);
  assert.equal(fence.validateAccountDeletionMarker(after).phase, "AUTH_GUARDING");
  assert.deepEqual({ ...after, state: null, authAbsenceObservedAt: null, authGuardAfter: null }, { ...marker, state: null, authAbsenceObservedAt: null, authGuardAfter: null });
  const work = db.__docs.get(`accountDeletionAuthWork/${fence.authWorkId(UID)}`);
  fence.validateAuthWork(work, { uid: UID, authResidualRetentionSeconds: 86400 });
  assert.equal(work.state, "guarding");
  assert.equal(work.failure_count, 0);
  assert.equal(work.next_eligible_run, fence.firstAuthOrdinalAfter(after.authGuardAfter));
  assert.ok(work.data_deleted_at.isEqual(marker.dataDeletedAt));
  assert.equal(work.authority_generation_id, "11111111-1111-4111-8111-111111111111");

  // replay: finalize and every other action now return the guarding wire replayed:true, no Auth call
  const replay = await call(deps, "finalize", credentials);
  assert.deepEqual(replay, { ...wire, replayed: true });
  assert.deepEqual(await call(deps, "discover", credentials), { ...wire, replayed: true });
  assert.deepEqual(auth.calls, [["getUser", UID]]);
});

test("finalize Auth reducer: a present user is deleted once; transport, timeout, and unknown failures retain pending with backoff and throw the retry member; user-not-found never retries", async () => {
  const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const seed = () => ({ "users/uid-A": { accountDeletion: dataDeletedMarker([capability(UID, credentials.operationId, credentials.proofNonce)]) } });

  const clockA = new FakeClock("2026-09-08T00:20:00.000Z");
  const presentDb = fakeFirestore({ docs: seed(), clock: clockA });
  const present = fakeAuth({ getUser: () => "present" });
  const wire = await call(makeDeps({ db: presentDb, clock: clockA, auth: present }), "finalize", credentials);
  assert.equal(wire.kind, "account_deletion_auth_guarding");
  assert.equal(wire.replayed, false);
  assert.deepEqual(present.calls, [["getUser", UID], ["deleteUser", UID]]);

  const transport = new Error("socket hang up"); transport.code = "ECONNRESET";
  const failures = [
    ["deleteUser transport", fakeAuth({ getUser: () => "present", deleteUser: () => transport })],
    ["getUser transport", fakeAuth({ getUser: () => transport })],
    ["deleteUser hang", fakeAuth({ getUser: () => "present", deleteUser: () => "hang" })],
    ["getUser hang", fakeAuth({ getUser: () => "hang" })]
  ];
  for (const [label, auth] of failures) {
    const clock = new FakeClock("2026-09-08T00:20:00.000Z");
    const db = fakeFirestore({ docs: seed(), clock });
    const deps = makeDeps({ db, clock, auth, timeouts: { getUserMs: 5, deleteUserMs: 5 } });
    await expectDeletionError(() => call(deps, "finalize", credentials), "unavailable", RETRY);
    assert.equal(fence.validateAccountDeletionMarker(markerOf(db)).phase, "DATA_DELETED", label);
    const work = db.__docs.get(`accountDeletionAuthWork/${fence.authWorkId(UID)}`);
    fence.validateAuthWork(work, { uid: UID });
    assert.equal(work.state, "delete_pending", label);
    assert.equal(work.failure_count, 1, label);
    assert.ok(work.next_eligible_run > 0, label);
    // a later successful finalize adopts the pending row and transitions
    const success = fakeAuth();
    const wire2 = await call(makeDeps({ db, clock, auth: success }), "finalize", credentials);
    assert.equal(wire2.replayed, false, label);
    assert.equal(db.__docs.get(`accountDeletionAuthWork/${fence.authWorkId(UID)}`).state, "guarding", label);
  }

  // preconditions: a live lease or a lingering storage work row blocks finalize before any Auth call
  const clock = new FakeClock("2026-09-08T00:20:00.000Z");
  const leaseDb = fakeFirestore({ docs: { ...seed(), [`users/uid-A/outboundLeases/uol1_${randomUUID()}`]: { schema_version: 1, kind: "USER_OUTBOUND_LEASE", account_uid: UID, delivery_id: "d", channel: "fcm", state: "sending", created_at: clock.now(), expires_at: Timestamp.fromMillis(clock.millis + 600_000) } }, clock });
  const leaseAuth = fakeAuth();
  await expectDeletionError(() => call(makeDeps({ db: leaseDb, clock, auth: leaseAuth }), "finalize", credentials), "unavailable", RETRY);
  assert.equal(leaseAuth.calls.length, 0);
  const workDb = fakeFirestore({ docs: { ...seed(), [`accountDeletionStorageWork/${fence.storageWorkId(UID)}`]: { stale: true } }, clock });
  const workAuth = fakeAuth();
  const workDeps = makeDeps({ db: workDb, clock, auth: workAuth });
  await expectDeletionError(() => call(workDeps, "finalize", credentials), "unavailable", RETRY);
  assert.equal(workAuth.calls.length, 0);
  assert.ok(workDeps.logs.some(([c]) => c === "ACCOUNT_DELETION_STORAGE_WORK_INVARIANT"));
  // evidence not activated refuses before any Auth call or write
  const inactiveDb = fakeFirestore({ docs: seed(), clock });
  const inactiveAuth = fakeAuth();
  await expectDeletionError(() => call(makeDeps({ db: inactiveDb, clock, auth: inactiveAuth, evidence: { ok: false, code: "PROVIDER_EVIDENCE_NOT_ACTIVATED" } }), "finalize", credentials), "unavailable", RETRY);
  assert.equal(inactiveAuth.calls.length + inactiveDb.__writes.length, 0);
});

test("finalize race: when another device transitions the root during the Auth call, finalize returns the guarding wire with replayed:true instead of retrying", async () => {
  const clock = new FakeClock("2026-09-08T00:20:00.000Z");
  const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const caps = [capability(UID, credentials.operationId, credentials.proofNonce)];
  const db = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: dataDeletedMarker(caps) } }, clock });
  const racedMarker = authGuardingMarker(caps);
  const deps = makeDeps({ db, clock, hooks: { beforeAuthTransition: () => { db.__docs.get("users/uid-A").accountDeletion = racedMarker; } } });
  const wire = await call(deps, "finalize", credentials);
  assert.equal(wire.kind, "account_deletion_auth_guarding");
  assert.equal(wire.replayed, true);
  assert.equal(wire.authGuardAfter, "2026-09-09T00:11:00.000Z");
});

test("marker validation enforces authGuardAfter == authAbsenceObservedAt + retention when the authority is known, and the callable applies it to guarding and deleted wires", async () => {
  const clock = new FakeClock();
  const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const caps = [capability(UID, credentials.operationId, credentials.proofNonce)];
  const marker = authGuardingMarker(caps); // deadline = observed + 86400 s
  fence.validateAccountDeletionMarker(marker, { authResidualRetentionSeconds: 86400 });
  assert.throws(() => fence.validateAccountDeletionMarker(marker, { authResidualRetentionSeconds: 3600 }), (e) => e.code === "ACCOUNT_DELETION_MARKER_MALFORMED");
  const db = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: marker } }, clock });
  const drift = makeDeps({ db, clock, evidence: testEvidence({ authResidualRetentionSeconds: 3600 }) });
  await expectDeletionError(() => call(drift, "discover", credentials), "permission-denied", CAP_INVALID);
  assert.equal(db.__writes.length, 0);
});

test("callable error boundary maps a non-HttpsError to a fixed internal code and never logs the error object", async () => {
  const logs = [];
  const boundary = fence.withFixedErrorBoundary("SUPPORT_ADMIN_INTERNAL_FAILURE", async (request) => {
    if (request.data === "https") throw fence.deletionError("AUTH_REQUIRED");
    throw new Error("users/uid-A/secret path leaked");
  }, (code, counts) => logs.push([code, counts]));
  await assert.rejects(boundary({ data: "https" }), (e) => e.code === "unauthenticated" && e.details.reason === "AUTH_REQUIRED");
  await assert.rejects(boundary({ data: "other" }), (e) => e.code === "internal" && e.message === "SUPPORT_ADMIN_INTERNAL_FAILURE" && e.details === undefined);
  assert.deepEqual(logs, [["SUPPORT_ADMIN_INTERNAL_FAILURE", {}]]);
});

test("finalize authority: a member may be unauthenticated; a nonmember needs the authenticated matching UID with a full registry (authenticatedOverflow) and never writes the marker", async () => {
  const clock = new FakeClock("2026-09-08T00:20:00.000Z");
  const ids = Array.from({ length: 65 }, () => freshOperationId()).sort();
  const nonces = ids.map(() => freshProofNonce());
  const full = dataDeletedMarker(ids.slice(0, 64).map((id, i) => capability(UID, id, nonces[i])));
  const db = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: full } }, clock });
  const deps = makeDeps({ db, clock });
  await expectDeletionError(() => call(deps, "finalize", { operationId: ids[64], proofNonce: nonces[64], authUid: null }), "permission-denied", CAP_INVALID);
  await expectDeletionError(() => call(deps, "finalize", { operationId: ids[64], proofNonce: nonces[64], authUid: "uid-B" }), "permission-denied", CAP_INVALID);
  const wire = await call(deps, "finalize", { operationId: ids[64], proofNonce: nonces[64] });
  assert.equal(wire.authorityKind, "authenticatedOverflow");
  assert.equal(wire.replayed, false);
  assert.equal(markerOf(db).capabilities.length, 64);
  // a nonmember with a non-full registry is never overflow, even when authenticated
  const partial = dataDeletedMarker([capability(UID, ids[0], nonces[0])]);
  const partialDb = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: partial } }, clock });
  await expectDeletionError(() => call(makeDeps({ db: partialDb, clock }), "finalize", { operationId: ids[1], proofNonce: nonces[1] }), "permission-denied", CAP_INVALID);
});

test("AUTH_GUARDING and ACCOUNT_DELETED: every action returns the root wire with replayed:true; no completed result exists before ACCOUNT_DELETED", async () => {
  const clock = new FakeClock();
  const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const caps = [capability(UID, credentials.operationId, credentials.proofNonce)];
  const guardingDb = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: authGuardingMarker(caps) } }, clock });
  const guardingAuth = fakeAuth();
  const guarding = makeDeps({ db: guardingDb, clock, auth: guardingAuth });
  for (const action of ["discover", "begin", "resume", "finalize"]) {
    const wire = await call(guarding, action, credentials);
    assert.equal(wire.kind, "account_deletion_auth_guarding", action);
    assert.equal(wire.replayed, true, action);
    assert.equal(wire.authGuardAfter, "2026-09-09T00:11:00.000Z");
  }
  assert.equal(guardingDb.__writes.length + guardingAuth.calls.length, 0);

  const deletedDb = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: accountDeletedMarker(caps) } }, clock });
  const deleted = makeDeps({ db: deletedDb, clock });
  for (const action of ["discover", "begin", "resume", "finalize"]) {
    const wire = await call(deleted, action, credentials);
    assert.equal(wire.kind, "account_deletion_account_deleted", action);
    assert.equal(wire.replayed, true, action);
    assert.equal(wire.accountDeletedAt, "2026-09-09T00:12:00.000Z");
  }
  assert.equal(deletedDb.__writes.length, 0);
});

test("two-device roots: device B enrolls against A's marker, both observe the same root, and a lost finalize response replays byte-identically", async () => {
  const clock = new FakeClock("2026-09-08T00:20:00.000Z");
  const a = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const b = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const db = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: dataDeletedMarker([capability(UID, a.operationId, a.proofNonce)]) } }, clock });
  const auth = fakeAuth();
  const deps = makeDeps({ db, clock, auth });
  const bWire = await call(deps, "begin", b);
  assert.equal(bWire.kind, "account_deletion_data_final");
  assert.equal(bWire.operationId, b.operationId);
  assert.equal(markerOf(db).capabilities.length, 2);
  const first = await call(deps, "finalize", a);
  assert.equal(first.replayed, false);
  const lost = await call(deps, "finalize", a);
  assert.deepEqual(lost, { ...first, replayed: true });
  const bView = await call(deps, "resume", { ...b, authUid: null });
  assert.deepEqual(bView, { ...first, operationId: b.operationId, replayed: true });
  assert.deepEqual(auth.calls, [["getUser", UID]]);
});


test("index.js exports deleteAccount as the fence callable with the pinned options, keeps changeTaskPlan byte-identical, and ships no Storage finalizer", () => {
  const fs = require("node:fs");
  const path = require("node:path");
  const source = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
  assert.match(source, /const \{ handleAccountDeletionRequest, productionDependencies, runStorageReconciler, runAuthReconciler \} = require\('\.\/accountDeletionFence'\);/);
  assert.match(source, /exports\.deleteAccount = onCall\(\s*\{ region: 'us-central1', timeoutSeconds: 60, memory: '512MiB' \},\s*\(request\) => handleAccountDeletionRequest\(request, productionDependencies\(\)\)\s*\);/);
  assert.ok(source.includes("exports.changeTaskPlan = changeTaskPlan;"));
  assert.match(source, /const \{ onSchedule \} = require\('firebase-functions\/v2\/scheduler'\);/);
  assert.match(source, /exports\.reconcileAccountDeletionStorage = onSchedule\(\s*\{ schedule: '\*\/5 \* \* \* \*', timeZone: 'UTC', region: 'us-central1', timeoutSeconds: 270, memory: '512MiB', maxInstances: 1, retryCount: 0 \},\s*\(event\) => runStorageReconciler\(event, productionDependencies\(\)\)\s*\);/);
  assert.match(source, /exports\.reconcileAccountDeletionAuth = onSchedule\(\s*\{ schedule: '2-57\/5 \* \* \* \*', timeZone: 'UTC', region: 'us-central1', timeoutSeconds: 270, memory: '512MiB', maxInstances: 1, retryCount: 0 \},\s*\(event\) => runAuthReconciler\(event, productionDependencies\(\)\)\s*\);/);
  for (const forbidden of ["recursiveDelete", "deleteUser(", "onObjectFinalized", "firebase-functions/v2/storage", "onInventoryObjectFinalized", "handleInventoryObjectFinalized", "admin.storage()"]) {
    assert.equal(source.includes(forbidden), false, forbidden);
  }
  const fenceSource = fs.readFileSync(path.join(__dirname, "..", "accountDeletionFence.js"), "utf8");
  for (const forbidden of ["onObjectFinalized", "firebase-functions/v2/storage"]) {
    assert.equal(fenceSource.includes(forbidden), false, forbidden);
  }
});
// ---------------------------------------------------------------------------
// I3a — provider evidence authority, config projections, policy checks (§11.2), partition (§11.3)
// ---------------------------------------------------------------------------

const { generateKeyPairSync, sign: edSign } = require("node:crypto");

function b64urlOf(buffer) { return Buffer.from(buffer).toString("base64url"); }

function makeTrustAnchor() {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  const raw = publicKey.export({ type: "spki", format: "der" }).subarray(-32);
  return { publicKeyBase64URL: b64urlOf(raw), sha256: sha256Bytes(raw), privateKey };
}

function sha256Bytes(buffer) { return createHash("sha256").update(buffer).digest("hex"); }

const ACCEPTED_BUCKET_CONFIG = {
  schemaVersion: 1, name: "peezy-1ecrdl.firebasestorage.app", metageneration: "3",
  softDeletePolicy: { retentionDurationSeconds: "0" }, versioning: { enabled: false }, retentionPolicy: null,
  defaultEventBasedHold: false, objectRetention: null, lifecycle: { rule: [] }, logging: null
};

const ACCEPTED_FIRESTORE_CONFIG = {
  schemaVersion: 1, name: "projects/peezy-1ecrdl/databases/(default)", etag: "etag-1",
  pointInTimeRecoveryEnablement: "POINT_IN_TIME_RECOVERY_DISABLED", versionRetentionPeriod: { seconds: "3600", nanos: 0 }
};

function digestMember(count = 0) {
  return { count, canonicalBytes: count === 0 ? 2 : 100 * count, sha256: sha256(`array-${count}`) };
}

function policyCheck(ordinal, overrides = {}) {
  return {
    ordinal, domain: "storage_bucket", resourceName: `resource-${ordinal}`, adapterId: "google_json_get_v1",
    resourceURL: `https://storage.googleapis.com/storage/v1/b/peezy-1ecrdl.firebasestorage.app/policy${ordinal}`,
    etagSource: "header", expectedEtag: `etag-${ordinal}`, expectedPolicySHA256: sha256(fence.TaskCanonicalV1({ ok: ordinal })),
    ...overrides
  };
}

function residualChecks() {
  return [
    { ordinal: 0, destinationOrdinals: [0], adapterId: "firebase_admin_get_user_v1", retentionSeconds: 0 },
    { ordinal: 1, destinationOrdinals: [1, 2], adapterId: "google_authenticated_uid_zero_v1", resourceURLTemplate: "https://identitytoolkit.googleapis.com/v1/projects/peezy-1ecrdl/accounts:query?uid={{UID}}", method: "GET", bodyTemplate: "", uidEncoding: "percent_utf8", zeroCountField: "matchCount", retentionSeconds: 3600 },
    { ordinal: 2, kind: "absence_retention", destinationOrdinals: [3], observedAbsentAt: "2026-08-01T00:00:00.000Z", retentionSeconds: 86400 }
  ];
}

function sealAuthority(anchor, overrides = {}, { sign = true } = {}) {
  const base = {
    schemaVersion: 1, kind: "ACCOUNT_DELETION_PROVIDER_EVIDENCE",
    generationId: "11111111-1111-4111-8111-111111111111", projectId: "peezy-1ecrdl", databaseId: "(default)",
    bucketName: "peezy-1ecrdl.firebasestorage.app", region: "us-central1",
    implementationSHA256: sha256("implementation"), packageLockSHA256: sha256("lock"),
    firestoreRulesSHA256: sha256("rules"), storageRulesSHA256: sha256("storage-rules"), firestoreIndexesSHA256: sha256("indexes"),
    firestoreRulesetId: "ruleset-1", firestoreReleaseId: "release-1", storageRulesetId: "ruleset-2", storageReleaseId: "release-2",
    bucketConfig: ACCEPTED_BUCKET_CONFIG, bucketConfigSHA256: sha256(fence.TaskCanonicalV1(ACCEPTED_BUCKET_CONFIG)),
    firestoreConfig: ACCEPTED_FIRESTORE_CONFIG, firestoreConfigSHA256: sha256(fence.TaskCanonicalV1(ACCEPTED_FIRESTORE_CONFIG)),
    storageDestinations: digestMember(0), firestoreDestinations: digestMember(0), authDestinations: digestMember(4),
    cloudAuditDestinations: digestMember(0), providerCopyDestinations: digestMember(0),
    copyProducerDenySHA256: sha256("deny"), policyChecks: [policyCheck(0), policyCheck(1, { adapterId: "google_iam_get_policy_v1", etagSource: "body.etag", resourceURL: "https://cloudresourcemanager.googleapis.com/v3/projects/peezy-1ecrdl:getIamPolicy" })],
    authResidualRetentionSeconds: 86400, authResidualChecks: residualChecks(),
    signatureAlgorithm: "ed25519", externalEvidenceBundleSHA256: sha256("bundle"),
    externalEvidencePublicKeyBase64URL: anchor.publicKeyBase64URL, externalEvidenceSigningKeySHA256: anchor.sha256,
    activatedAt: "2026-09-06T00:00:00.000Z",
    ...overrides
  };
  const unsigned = { ...base };
  delete unsigned.signedAuthorityPayloadSHA256; delete unsigned.externalEvidenceSignatureBase64URL; delete unsigned.authoritySHA256;
  const payload = sha256(fence.TaskCanonicalV1(unsigned));
  const message = Buffer.concat([
    Buffer.from("peezy.account_deletion_provider_evidence.v1\0", "ascii"),
    Buffer.from(payload, "hex"), Buffer.from(base.externalEvidenceBundleSHA256, "hex"), Buffer.from(base.implementationSHA256, "hex")
  ]);
  const signature = sign ? b64urlOf(edSign(null, message, anchor.privateKey)) : b64urlOf(Buffer.alloc(64));
  const withSignature = { ...base, signedAuthorityPayloadSHA256: overrides.signedAuthorityPayloadSHA256 ?? payload, externalEvidenceSignatureBase64URL: overrides.externalEvidenceSignatureBase64URL ?? signature };
  const authoritySHA256 = overrides.authoritySHA256 ?? sha256(fence.TaskCanonicalV1(withSignature));
  return { ...withSignature, authoritySHA256 };
}

function artifactBytes(authority) { return Buffer.from(fence.TaskCanonicalV1(authority), "utf8"); }

test("provider evidence authority: an exact sealed artifact activates; every member, digest, key, signature, and byte mismatch is the fixed invariant; absence is not activated", () => {
  const anchor = makeTrustAnchor();
  const authority = sealAuthority(anchor);
  const loaded = fence.loadProviderEvidenceAuthority(artifactBytes(authority), { trustAnchor: anchor });
  assert.equal(loaded.ok, true);
  assert.deepEqual(loaded.authority, authority);
  assert.deepEqual(fence.loadProviderEvidenceAuthority(undefined, { trustAnchor: anchor }), { ok: false, code: "PROVIDER_EVIDENCE_NOT_ACTIVATED" });
  assert.deepEqual(fence.loadProviderEvidenceAuthority(artifactBytes(authority), { trustAnchor: { publicKeyBase64URL: null, sha256: null } }), { ok: false, code: "PROVIDER_EVIDENCE_NOT_ACTIVATED" });

  const other = makeTrustAnchor();
  const rejects = [
    ["non-canonical bytes", Buffer.from(JSON.stringify(authority, null, 2))],
    ["duplicate key", Buffer.from(fence.TaskCanonicalV1(authority).replace('"region":"us-central1"', '"region":"us-central1","region":"us-central1"'))],
    ["surplus member", artifactBytes(sealAuthority(anchor, { extra: 1 }))],
    ["missing member", artifactBytes((() => { const a = sealAuthority(anchor); delete a.storageReleaseId; return a; })())],
    ["wrong project", artifactBytes(sealAuthority(anchor, { projectId: "other" }))],
    ["bad signature", artifactBytes(sealAuthority(anchor, {}, { sign: false }))],
    ["foreign key", artifactBytes(sealAuthority(other))],
    ["key digest mismatch", artifactBytes(sealAuthority(anchor, { externalEvidenceSigningKeySHA256: sha256("nope") }))],
    ["payload digest mismatch", artifactBytes(sealAuthority(anchor, { signedAuthorityPayloadSHA256: sha256("nope") }))],
    ["authority digest mismatch", artifactBytes(sealAuthority(anchor, { authoritySHA256: sha256("nope") }))],
    ["bucket digest mismatch", artifactBytes(sealAuthority(anchor, { bucketConfigSHA256: sha256("nope") }))],
    ["firestore digest mismatch", artifactBytes(sealAuthority(anchor, { firestoreConfigSHA256: sha256("nope") }))],
    ["retention over cap", artifactBytes(sealAuthority(anchor, { authResidualRetentionSeconds: 31536001 }))],
    ["retention not the max", artifactBytes(sealAuthority(anchor, { authResidualRetentionSeconds: 90000 }))],
    ["13 policy checks", artifactBytes(sealAuthority(anchor, { policyChecks: Array.from({ length: 13 }, (_, i) => policyCheck(i)) }))],
    ["zero policy checks", artifactBytes(sealAuthority(anchor, { policyChecks: [] }))],
    ["policy ordinal gap", artifactBytes(sealAuthority(anchor, { policyChecks: [policyCheck(0), policyCheck(2)] }))],
    ["policy host", artifactBytes(sealAuthority(anchor, { policyChecks: [policyCheck(0, { resourceURL: "https://evil.example.com/x" })] }))],
    ["policy etag empty with header", artifactBytes(sealAuthority(anchor, { policyChecks: [policyCheck(0, { expectedEtag: "" })] }))],
    ["destination count 4097", artifactBytes(sealAuthority(anchor, { storageDestinations: digestMember(4097) }))],
    ["algorithm", artifactBytes(sealAuthority(anchor, { signatureAlgorithm: "rsa" }))],
    ["activatedAt", artifactBytes(sealAuthority(anchor, { activatedAt: "2026-09-06T00:00:00Z" }))],
    ["generation id", artifactBytes(sealAuthority(anchor, { generationId: "not-a-uuid" }))],
    ["mutated after signing", Buffer.from(fence.TaskCanonicalV1({ ...authority, region: "us-east1" }))]
  ];
  for (const [label, bytes] of rejects) {
    assert.deepEqual(fence.loadProviderEvidenceAuthority(bytes, { trustAnchor: anchor }), { ok: false, code: "ACCOUNT_DELETION_PROVIDER_EVIDENCE_INVARIANT" }, label);
  }
  assert.deepEqual(fence.PROVIDER_EVIDENCE_TRUST_ANCHOR_V1, { publicKeyBase64URL: null, sha256: null });
});

test("bucket configuration projection: absent members project to null, present maps are copied and key-sorted, and any drift from the accepted map is ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT", () => {
  const anchor = makeTrustAnchor();
  const authority = sealAuthority(anchor);
  const metadata = {
    name: "peezy-1ecrdl.firebasestorage.app", metageneration: "3", id: "ignored", location: "US",
    softDeletePolicy: { retentionDurationSeconds: "0" }, versioning: { enabled: false }, defaultEventBasedHold: false, lifecycle: { rule: [] }
  };
  assert.deepEqual(fence.projectBucketDeletionConfig(metadata), ACCEPTED_BUCKET_CONFIG);
  fence.verifyBucketConfiguration([metadata, { statusCode: 200 }], authority);
  const drifts = [
    ["versioning enabled", { ...metadata, versioning: { enabled: true } }],
    ["retention policy present", { ...metadata, retentionPolicy: { retentionPeriod: "1" } }],
    ["hold true", { ...metadata, defaultEventBasedHold: true }],
    ["hold non-boolean", { ...metadata, defaultEventBasedHold: "false" }],
    ["logging present", { ...metadata, logging: { logBucket: "x" } }],
    ["metageneration", { ...metadata, metageneration: "4" }],
    ["name", { ...metadata, name: "other" }],
    ["versioning non-object", { ...metadata, versioning: "off" }],
    ["nested nonfinite", { ...metadata, lifecycle: { rule: [Number.NaN] } }]
  ];
  for (const [label, drifted] of drifts) {
    assert.throws(() => fence.verifyBucketConfiguration([drifted, { statusCode: 200 }], authority), (e) => e.code === "ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT", label);
  }
  // key order of the provider object never changes the digest
  const reordered = { lifecycle: { rule: [] }, defaultEventBasedHold: false, versioning: { enabled: false }, softDeletePolicy: { retentionDurationSeconds: "0" }, metageneration: "3", name: metadata.name };
  fence.verifyBucketConfiguration([reordered, { statusCode: 200 }], authority);
});

test("Firestore configuration tuple: exact three-tuple with null next/raw, exact projection digest, and a millisecond earliestVersionTime", () => {
  const anchor = makeTrustAnchor();
  const authority = sealAuthority(anchor);
  const database = {
    name: "projects/peezy-1ecrdl/databases/(default)", etag: "etag-1", pointInTimeRecoveryEnablement: "POINT_IN_TIME_RECOVERY_DISABLED",
    versionRetentionPeriod: { seconds: "3600", nanos: 0 }, earliestVersionTime: { seconds: "1788700800", nanos: 123456789 }, locationId: "nam5"
  };
  const observed = fence.verifyFirestoreConfiguration([database, null, null], authority);
  assert.equal(observed.earliestVersionTime.toMillis(), 1788700800123);
  const rejects = [
    ["two-tuple", [database, null]],
    ["four-tuple", [database, null, null, null]],
    ["nonnull next", [database, {}, null]],
    ["nonnull raw", [database, null, {}]],
    ["etag drift", [{ ...database, etag: "etag-2" }, null, null]],
    ["pitr enabled", [{ ...database, pointInTimeRecoveryEnablement: "POINT_IN_TIME_RECOVERY_ENABLED" }, null, null]],
    ["retention drift", [{ ...database, versionRetentionPeriod: { seconds: "7200", nanos: 0 } }, null, null]],
    ["name drift", [{ ...database, name: "projects/other/databases/(default)" }, null, null]],
    ["missing earliestVersionTime", [(() => { const d = { ...database }; delete d.earliestVersionTime; return d; })(), null, null]]
  ];
  for (const [label, tuple] of rejects) {
    assert.throws(() => fence.verifyFirestoreConfiguration(tuple, authority), (e) => e.code === "ACCOUNT_DELETION_PROVIDER_EVIDENCE_INVARIANT", label);
  }
});

function fakeProviderHTTP(script) {
  const requests = [];
  return {
    requests,
    async request(options) {
      requests.push(options);
      const response = await script(options, requests.length);
      if (response instanceof Error) throw response;
      if (response === "hang") return new Promise(() => {});
      return response;
    }
  };
}

function jsonResponse(object, { status = 200, etag, contentType = "application/json; charset=utf-8" } = {}) {
  const headers = { "content-type": contentType };
  if (etag !== undefined) headers.etag = etag;
  return { status, headers, body: Buffer.from(JSON.stringify(object)) };
}

test("policy checks: both adapters send exact requests, honor the four etag sources, run in ordinal order at most four in flight, and every drift/timeout/oversize/duplicate/media/status defect is the fixed invariant", async () => {
  const anchor = makeTrustAnchor();
  const checks = [
    policyCheck(0, { etagSource: "header", expectedEtag: "h0", expectedPolicySHA256: sha256(fence.TaskCanonicalV1({ b: 1, a: [1, 2] })) }),
    policyCheck(1, { adapterId: "google_iam_get_policy_v1", etagSource: "body.etag", expectedEtag: "b1", resourceURL: "https://cloudresourcemanager.googleapis.com/v3/projects/peezy-1ecrdl:getIamPolicy", expectedPolicySHA256: sha256(fence.TaskCanonicalV1({ etag: "b1", bindings: [] })) }),
    policyCheck(2, { etagSource: "body.policy.etag", expectedEtag: "p2", resourceURL: "https://firebaserules.googleapis.com/v1/projects/peezy-1ecrdl/releases/x", expectedPolicySHA256: sha256(fence.TaskCanonicalV1({ policy: { etag: "p2" } })) }),
    policyCheck(3, { etagSource: "none", expectedEtag: "", resourceURL: "https://identitytoolkit.googleapis.com/admin/v2/projects/peezy-1ecrdl/config", expectedPolicySHA256: sha256(fence.TaskCanonicalV1({ signIn: {} })) }),
    policyCheck(4, { etagSource: "header", expectedEtag: "h4", resourceURL: "https://orgpolicy.googleapis.com/v2/projects/peezy-1ecrdl/policies/x", expectedPolicySHA256: sha256(fence.TaskCanonicalV1({ spec: {} })) })
  ];
  const authority = sealAuthority(anchor, { policyChecks: checks });
  const bodies = [{ b: 1, a: [1, 2] }, { etag: "b1", bindings: [] }, { policy: { etag: "p2" } }, { signIn: {} }, { spec: {} }];
  let inFlight = 0;
  let peak = 0;
  const http = fakeProviderHTTP((options) => {
    const index = checks.findIndex((c) => c.resourceURL === options.url);
    inFlight += 1; peak = Math.max(peak, inFlight);
    const etag = ["h0", undefined, undefined, undefined, "h4"][index];
    return new Promise((resolve) => setTimeout(() => { inFlight -= 1; resolve(jsonResponse(bodies[index], { etag })); }, 2));
  });
  await fence.runPolicyChecks({ providerHTTP: http, timeouts: { providerMs: 3000 } }, authority);
  assert.equal(http.requests.length, 5);
  assert.ok(peak <= 4);
  const get = http.requests.find((r) => r.url === checks[0].resourceURL);
  assert.equal(get.method, "GET");
  assert.equal(get.body, undefined);
  assert.deepEqual(Object.keys(get.headers).sort(), ["accept"]);
  assert.equal(get.headers.accept, "application/json");
  assert.equal(get.maxBytes, 1048576);
  assert.equal(get.redirects, 0);
  const post = http.requests.find((r) => r.url === checks[1].resourceURL);
  assert.equal(post.method, "POST");
  assert.equal(post.body, '{"options":{"requestedPolicyVersion":3}}');
  assert.equal(post.headers["content-type"], "application/json");
  // ordinal order of admission
  assert.deepEqual(http.requests.map((r) => checks.findIndex((c) => c.resourceURL === r.url)), [0, 1, 2, 3, 4]);

  const defects = [
    ["status", () => jsonResponse({ b: 1, a: [1, 2] }, { status: 403, etag: "h0" })],
    ["media", () => jsonResponse({ b: 1, a: [1, 2] }, { etag: "h0", contentType: "text/plain" })],
    ["etag drift", () => jsonResponse({ b: 1, a: [1, 2] }, { etag: "h9" })],
    ["policy drift", () => jsonResponse({ b: 2, a: [1, 2] }, { etag: "h0" })],
    ["duplicate key", () => ({ status: 200, headers: { "content-type": "application/json", etag: "h0" }, body: Buffer.from('{"b":1,"b":1,"a":[1,2]}') })],
    ["oversize", () => ({ status: 200, headers: { "content-type": "application/json", etag: "h0" }, body: Buffer.alloc(1048577, 32) })],
    ["transport", () => new Error("ECONNRESET")],
    ["timeout", () => "hang"],
    ["non-object", () => ({ status: 200, headers: { "content-type": "application/json", etag: "h0" }, body: Buffer.from("[1]") })]
  ];
  for (const [label, respond] of defects) {
    const single = sealAuthority(anchor, { policyChecks: [checks[0]] });
    const failing = fakeProviderHTTP(() => respond());
    await assert.rejects(fence.runPolicyChecks({ providerHTTP: failing, timeouts: { providerMs: 5 } }, single), (e) => e.code === "ACCOUNT_DELETION_PROVIDER_EVIDENCE_INVARIANT", label);
  }
});

test("Auth destination partition is completely falsifiable", () => {
  const ok = residualChecks();
  fence.validateAuthResidualChecks(ok, { authResidualRetentionSeconds: 86400, destinationCount: 4 });
  const twelve = Array.from({ length: 12 }, (_, i) => ({ ordinal: i, kind: "absence_retention", destinationOrdinals: [i], observedAbsentAt: "2026-08-01T00:00:00.000Z", retentionSeconds: 10 }));
  fence.validateAuthResidualChecks(twelve, { authResidualRetentionSeconds: 10, destinationCount: 12 });
  const defects = [
    ["13 checks", Array.from({ length: 13 }, (_, i) => ({ ordinal: i, kind: "absence_retention", destinationOrdinals: [i], observedAbsentAt: "2026-08-01T00:00:00.000Z", retentionSeconds: 10 })), { authResidualRetentionSeconds: 10, destinationCount: 13 }],
    ["zero checks", [], { authResidualRetentionSeconds: 0, destinationCount: 0 }],
    ["uncovered destination", ok, { authResidualRetentionSeconds: 86400, destinationCount: 5 }],
    ["ordinal beyond destinations", ok, { authResidualRetentionSeconds: 86400, destinationCount: 3 }],
    ["overlap", [ok[0], { ...ok[1], destinationOrdinals: [0, 1, 2] }, ok[2]], { authResidualRetentionSeconds: 86400, destinationCount: 4 }],
    ["absence with two ordinals", [ok[0], ok[1], { ...ok[2], destinationOrdinals: [3, 4] }], { authResidualRetentionSeconds: 86400, destinationCount: 5 }],
    ["absence with empty ordinals", [ok[0], ok[1], { ...ok[2], destinationOrdinals: [] }], { authResidualRetentionSeconds: 86400, destinationCount: 4 }],
    ["absence missing ordinals", [ok[0], ok[1], (() => { const c = { ...ok[2] }; delete c.destinationOrdinals; return c; })()], { authResidualRetentionSeconds: 86400, destinationCount: 4 }],
    ["non-contiguous ordinals", [ok[0], { ...ok[1], ordinal: 5 }, ok[2]], { authResidualRetentionSeconds: 86400, destinationCount: 4 }],
    ["unsorted destinationOrdinals", [ok[0], { ...ok[1], destinationOrdinals: [2, 1] }, ok[2]], { authResidualRetentionSeconds: 86400, destinationCount: 4 }],
    ["unknown adapter", [{ ...ok[0], adapterId: "custom_v1" }, ok[1], ok[2]], { authResidualRetentionSeconds: 86400, destinationCount: 4 }],
    ["retention above authority max", [ok[0], { ...ok[1], retentionSeconds: 90000 }, ok[2]], { authResidualRetentionSeconds: 86400, destinationCount: 4 }],
    ["template without UID", [ok[0], { ...ok[1], resourceURLTemplate: "https://identitytoolkit.googleapis.com/v1/x" }, ok[2]], { authResidualRetentionSeconds: 86400, destinationCount: 4 }],
    ["template host", [ok[0], { ...ok[1], resourceURLTemplate: "https://example.com/{{UID}}" }, ok[2]], { authResidualRetentionSeconds: 86400, destinationCount: 4 }],
    ["GET with body", [ok[0], { ...ok[1], bodyTemplate: "{\"uid\":\"{{UID}}\"}" }, ok[2]], { authResidualRetentionSeconds: 86400, destinationCount: 4 }],
    ["surplus member", [{ ...ok[0], extra: 1 }, ok[1], ok[2]], { authResidualRetentionSeconds: 86400, destinationCount: 4 }],
    ["uncheckable kind", [ok[0], ok[1], { ...ok[2], kind: "manual" }], { authResidualRetentionSeconds: 86400, destinationCount: 4 }]
  ];
  for (const [label, checks, options] of defects) {
    assert.throws(() => fence.validateAuthResidualChecks(checks, options), (e) => e.code === "ACCOUNT_DELETION_PROVIDER_EVIDENCE_INVARIANT", label);
  }
});

test("the bounded evidence fence runs the bucket RPC, the Firestore RPC, and every policy check; finalize refuses on any invariant with no Auth call and no write", async () => {
  const anchor = makeTrustAnchor();
  const authority = sealAuthority(anchor, { policyChecks: [policyCheck(0, { expectedPolicySHA256: sha256(fence.TaskCanonicalV1({ ok: true })) })] });
  const metadata = { name: "peezy-1ecrdl.firebasestorage.app", metageneration: "3", softDeletePolicy: { retentionDurationSeconds: "0" }, versioning: { enabled: false }, defaultEventBasedHold: false, lifecycle: { rule: [] } };
  const database = { name: "projects/peezy-1ecrdl/databases/(default)", etag: "etag-1", pointInTimeRecoveryEnablement: "POINT_IN_TIME_RECOVERY_DISABLED", versionRetentionPeriod: { seconds: "3600", nanos: 0 }, earliestVersionTime: { seconds: "1788700800", nanos: 0 } };
  const bucket = fakeBucket({ metadataTuple: [metadata, { statusCode: 200 }] });
  const http = fakeProviderHTTP(() => jsonResponse({ ok: true }, { etag: "etag-0" }));
  const deps = { bucket, providerHTTP: http, firestoreAdmin: { getDatabase: async (request) => { assert.deepEqual(request, { name: "projects/peezy-1ecrdl/databases/(default)" }); return [database, null, null]; } }, timeouts: { providerMs: 3000 } };
  const observed = await fence.runEvidenceFence(deps, authority);
  assert.equal(observed.earliestVersionTime.toMillis(), 1788700800000);
  assert.deepEqual(bucket.calls, [["getMetadata"]]);
  assert.equal(http.requests.length, 1);

  const clock = new FakeClock("2026-09-08T00:20:00.000Z");
  const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const db = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: dataDeletedMarker([capability(UID, credentials.operationId, credentials.proofNonce)]) } }, clock });
  const auth = fakeAuth();
  const failing = makeDeps({ db, clock, auth, evidenceFence: async () => { throw new fence.InvariantError("ACCOUNT_DELETION_PROVIDER_EVIDENCE_INVARIANT"); } });
  await expectDeletionError(() => call(failing, "finalize", credentials), "unavailable", RETRY);
  assert.equal(auth.calls.length + db.__writes.length, 0);
  assert.ok(failing.logs.some(([c]) => c === "ACCOUNT_DELETION_PROVIDER_EVIDENCE_INVARIANT"));
  assert.equal(fence.validateAccountDeletionMarker(markerOf(db)).phase, "DATA_DELETED");
});

// ---------------------------------------------------------------------------
// I3b — the two scheduled reconcilers (§11.3) and their index exports
// ---------------------------------------------------------------------------

const STORAGE_STATE_PATH = "phase2System/accountDeletionStorageReconcilerV1";
const AUTH_STATE_PATH = "phase2System/accountDeletionAuthReconcilerV1";

function reconcilerState(kind, overrides = {}) {
  return { schema_version: 1, kind, last_started_ordinal: 100, last_completed_ordinal: 100, cursor_id: "", lease: null, heartbeat: null, ...overrides };
}

function storageWorkRow(uid, marker, overrides = {}) {
  return {
    schema_version: 1, kind: "ACCOUNT_DELETION_STORAGE_WORK", work_id: fence.storageWorkId(uid), account_uid: uid,
    marker_started_at: marker.startedAt, storage_guard_after: marker.storageGuardAfter, failure_count: 0, next_eligible_run: 0,
    created_at: marker.startedAt, updated_at: marker.startedAt, ...overrides
  };
}

function authWorkRow(uid, marker, overrides = {}) {
  return {
    schema_version: 1, kind: "ACCOUNT_DELETION_AUTH_WORK", work_id: fence.authWorkId(uid), account_uid: uid, state: "delete_pending",
    data_deleted_at: marker.dataDeletedAt, authority_generation_id: "11111111-1111-4111-8111-111111111111", authority_sha256: sha256("authority"),
    failure_count: 0, next_eligible_run: 0, created_at: marker.dataDeletedAt, updated_at: marker.dataDeletedAt, ...overrides
  };
}

function scheduleEvent(iso) { return { scheduleTime: iso, jobName: "test" }; }

function reconcilerDeps(options) {
  const deps = makeDeps(options);
  deps.metrics = [];
  deps.metric = (name, value) => deps.metrics.push([name, value]);
  return deps;
}

test("reconciler state grammar: exact members and lease/heartbeat relations; absent or malformed state is the fixed invariant and is never synthesized", async () => {
  const clock = new FakeClock("2026-09-06T12:00:00.000Z");
  const good = reconcilerState("ACCOUNT_DELETION_STORAGE_RECONCILER");
  fence.validateReconcilerState(good, "storage");
  const lease = { owner_token: randomUUID(), schedule_ordinal: 101, scheduled_at: clock.now(), started_at: clock.now(), expires_at: Timestamp.fromMillis(clock.millis + 270_000) };
  fence.validateReconcilerState({ ...good, last_started_ordinal: 101, lease, heartbeat: { schedule_ordinal: 101, status: "running", started_at: clock.now() } }, "storage");
  fence.validateReconcilerState({ ...good, last_started_ordinal: 101, last_completed_ordinal: 101, heartbeat: { schedule_ordinal: 101, status: "completed", started_at: clock.now(), completed_at: clock.now() } }, "storage");
  const bad = [
    ["kind", { ...good, kind: "ACCOUNT_DELETION_AUTH_RECONCILER" }],
    ["surplus", { ...good, extra: 1 }],
    ["completed beyond started", { ...good, last_completed_ordinal: 101 }],
    ["cursor grammar", { ...good, cursor_id: "adsw1_x" }],
    ["lease expiry relation", { ...good, last_started_ordinal: 101, lease: { ...lease, expires_at: clock.now() }, heartbeat: { schedule_ordinal: 101, status: "running", started_at: clock.now() } }],
    ["running with completed_at", { ...good, last_started_ordinal: 101, lease, heartbeat: { schedule_ordinal: 101, status: "running", started_at: clock.now(), completed_at: clock.now() } }],
    ["completed with lease", { ...good, last_started_ordinal: 101, last_completed_ordinal: 101, lease, heartbeat: { schedule_ordinal: 101, status: "completed", started_at: clock.now(), completed_at: clock.now() } }],
    ["completed without completed_at", { ...good, last_started_ordinal: 101, last_completed_ordinal: 101, heartbeat: { schedule_ordinal: 101, status: "completed", started_at: clock.now() } }],
    ["owner token", { ...good, last_started_ordinal: 101, lease: { ...lease, owner_token: "nope" }, heartbeat: { schedule_ordinal: 101, status: "running", started_at: clock.now() } }]
  ];
  for (const [label, state] of bad) {
    assert.throws(() => fence.validateReconcilerState(state, "storage"), (e) => e.code === "ACCOUNT_DELETION_STORAGE_RECONCILER_INVARIANT", label);
  }
  for (const seed of [{}, { [STORAGE_STATE_PATH]: { junk: true } }]) {
    const db = fakeFirestore({ docs: seed, clock });
    const deps = reconcilerDeps({ db, clock });
    await fence.runStorageReconciler(scheduleEvent("2026-09-06T12:00:00Z"), deps);
    assert.equal(db.__writes.length, 0);
    assert.ok(deps.logs.some(([c]) => c === "ACCOUNT_DELETION_STORAGE_RECONCILER_INVARIANT"));
  }
});

test("schedule boundaries and acquisition: exact 300 s boundaries (auth: +120 s) derive ordinals; stale, duplicate, or non-boundary deliveries mutate nothing; expired leases are replaced and live foreign leases refused; completion settles the heartbeat and metric", async () => {
  const clock = new FakeClock("2026-09-06T12:00:00.000Z");
  const boundary = "2026-09-06T12:00:00Z";
  const ordinal = Math.floor(Date.parse(boundary) / 1000 / 300);
  const db = fakeFirestore({ docs: { [STORAGE_STATE_PATH]: reconcilerState("ACCOUNT_DELETION_STORAGE_RECONCILER", { last_started_ordinal: ordinal - 1, last_completed_ordinal: ordinal - 1 }) }, clock });
  const deps = reconcilerDeps({ db, clock });
  for (const bad of ["2026-09-06T12:01:00Z", "2026-09-06T12:00:00.500Z", "not-a-time", undefined]) {
    await fence.runStorageReconciler(scheduleEvent(bad), deps);
    assert.equal(db.__writes.length, 0, String(bad));
    assert.ok(deps.logs.some(([c]) => c === "ACCOUNT_DELETION_SCHEDULE_BOUNDARY_INVALID"));
  }
  await fence.runStorageReconciler(scheduleEvent(boundary), deps);
  const settled = db.__docs.get(STORAGE_STATE_PATH);
  assert.equal(settled.last_started_ordinal, ordinal);
  assert.equal(settled.last_completed_ordinal, ordinal);
  assert.equal(settled.lease, null);
  assert.deepEqual({ ...settled.heartbeat, started_at: null, completed_at: null }, { schedule_ordinal: ordinal, status: "completed", started_at: null, completed_at: null });
  assert.equal(settled.cursor_id, "");
  assert.deepEqual(deps.metrics, [["phase2/account_deletion_storage_reconciler_completed_count", 1]]);
  // duplicate and stale deliveries are zero-mutation
  const before = JSON.stringify(db.__docs.get(STORAGE_STATE_PATH));
  await fence.runStorageReconciler(scheduleEvent(boundary), deps);
  await fence.runStorageReconciler(scheduleEvent("2026-09-06T11:55:00Z"), deps);
  assert.equal(JSON.stringify(db.__docs.get(STORAGE_STATE_PATH)), before);

  // a live foreign lease refuses; an expired one is replaced
  const foreign = { owner_token: randomUUID(), schedule_ordinal: ordinal + 1, scheduled_at: clock.now(), started_at: clock.now(), expires_at: Timestamp.fromMillis(clock.millis + 270_000) };
  const liveDb = fakeFirestore({ docs: { [STORAGE_STATE_PATH]: reconcilerState("ACCOUNT_DELETION_STORAGE_RECONCILER", { last_started_ordinal: ordinal + 1, last_completed_ordinal: ordinal, lease: foreign, heartbeat: { schedule_ordinal: ordinal + 1, status: "running", started_at: clock.now() } }) }, clock });
  const liveDeps = reconcilerDeps({ db: liveDb, clock });
  clock.millis = Date.parse("2026-09-06T12:03:00.000Z");
  await fence.runStorageReconciler(scheduleEvent("2026-09-06T12:10:00Z"), liveDeps);
  assert.equal(liveDb.__writes.length, 0);
  clock.millis = Date.parse("2026-09-06T12:10:00.000Z");
  await fence.runStorageReconciler(scheduleEvent("2026-09-06T12:10:00Z"), liveDeps);
  assert.equal(liveDb.__docs.get(STORAGE_STATE_PATH).last_started_ordinal, ordinal + 2);
  assert.equal(liveDb.__docs.get(STORAGE_STATE_PATH).lease, null);

  // the auth schedule accepts only boundary + 120 s
  const authOrdinal = fence.authScheduleOrdinal(Math.floor(Date.parse("2026-09-06T12:02:00Z") / 1000));
  const authDb = fakeFirestore({ docs: { [AUTH_STATE_PATH]: reconcilerState("ACCOUNT_DELETION_AUTH_RECONCILER", { last_started_ordinal: authOrdinal - 1, last_completed_ordinal: authOrdinal - 1 }) }, clock });
  const authDeps = reconcilerDeps({ db: authDb, clock });
  await fence.runAuthReconciler(scheduleEvent("2026-09-06T12:00:00Z"), authDeps);
  assert.equal(authDb.__writes.length, 0);
  clock.millis = Date.parse("2026-09-06T12:02:00.000Z");
  await fence.runAuthReconciler(scheduleEvent("2026-09-06T12:02:00Z"), authDeps);
  assert.equal(authDb.__docs.get(AUTH_STATE_PATH).last_completed_ordinal, authOrdinal);
  assert.deepEqual(authDeps.metrics, [["phase2/account_deletion_auth_reconciler_completed_count", 1]]);

  // evidence not activated or a failing fence performs zero mutation
  clock.millis = Date.parse("2026-09-06T12:15:00.000Z");
  const inactive = reconcilerDeps({ db: fakeFirestore({ docs: { [STORAGE_STATE_PATH]: reconcilerState("ACCOUNT_DELETION_STORAGE_RECONCILER") }, clock }), clock, evidence: { ok: false, code: "PROVIDER_EVIDENCE_NOT_ACTIVATED" } });
  await fence.runStorageReconciler(scheduleEvent("2026-09-06T12:15:00Z"), inactive);
  assert.equal(inactive.db.__writes.length, 0);
  const drifting = reconcilerDeps({ db: fakeFirestore({ docs: { [STORAGE_STATE_PATH]: reconcilerState("ACCOUNT_DELETION_STORAGE_RECONCILER") }, clock }), clock, evidenceFence: async () => { throw new fence.InvariantError("ACCOUNT_DELETION_PROVIDER_EVIDENCE_INVARIANT"); } });
  await fence.runStorageReconciler(scheduleEvent("2026-09-06T12:15:00Z"), drifting);
  assert.equal(drifting.db.__writes.length, 0);
});

test("cursor advances before the provider await, never skips a later eligible row, wraps on an empty page, and steps past malformed rows with the fixed invariant", async () => {
  const clock = new FakeClock("2026-09-01T00:00:00.000Z");
  const ordinal = Math.floor(Date.parse("2026-09-01T00:00:00Z") / 1000 / 300);
  const users = ["uid-1", "uid-2", "uid-3"];
  const docs = { [STORAGE_STATE_PATH]: reconcilerState("ACCOUNT_DELETION_STORAGE_RECONCILER", { last_started_ordinal: ordinal - 1, last_completed_ordinal: ordinal - 1 }) };
  const markers = {};
  for (const uid of users) {
    const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
    markers[uid] = guardingMarker([capability(uid, credentials.operationId, credentials.proofNonce)]);
    docs[`users/${uid}`] = { accountDeletion: markers[uid] };
    docs[`accountDeletionStorageWork/${fence.storageWorkId(uid)}`] = storageWorkRow(uid, markers[uid], { next_eligible_run: uid === "uid-2" ? ordinal + 5 : 0 });
  }
  const malformedId = `adsw1_${"f".repeat(40)}`;
  docs[`accountDeletionStorageWork/${malformedId}`] = { junk: true };
  const ids = users.map((uid) => fence.storageWorkId(uid)).sort();
  const db = fakeFirestore({ docs, clock });
  const bucket = fakeBucket({ objects: users.map((uid) => ({ name: `users/${uid}/a.bin` })) });
  const visited = [];
  const deps = reconcilerDeps({ db, clock, bucket, hooks: { beforeReducer: (uid) => visited.push([uid, db.__docs.get(STORAGE_STATE_PATH).cursor_id]) } });
  const eligible = ids.filter((id) => id !== fence.storageWorkId("uid-2"));

  await fence.runStorageReconciler(scheduleEvent("2026-09-01T00:00:00Z"), deps);
  assert.equal(visited.length, 1);
  assert.equal(visited[0][1], fence.storageWorkId(visited[0][0]), "cursor advanced to the selected row before the await");
  assert.equal(visited[0][1], eligible[0]);
  assert.equal(db.__docs.get(STORAGE_STATE_PATH).cursor_id, eligible[0]);

  clock.millis = Date.parse("2026-09-01T00:05:00.000Z");
  await fence.runStorageReconciler(scheduleEvent("2026-09-01T00:05:00Z"), deps);
  assert.equal(visited.length, 2);
  assert.equal(visited[1][1], eligible[1]);

  clock.millis = Date.parse("2026-09-01T00:10:00.000Z");
  await fence.runStorageReconciler(scheduleEvent("2026-09-01T00:10:00Z"), deps);
  clock.millis = Date.parse("2026-09-01T00:15:00.000Z");
  await fence.runStorageReconciler(scheduleEvent("2026-09-01T00:15:00Z"), deps);
  const state = db.__docs.get(STORAGE_STATE_PATH);
  assert.equal(state.cursor_id, "", "empty page after the last row wraps the cursor");
  assert.equal(visited.length, 2, "the ineligible row was never reduced");
  assert.ok(deps.logs.some(([c]) => c === "ACCOUNT_DELETION_STORAGE_WORK_INVARIANT"));
  assert.deepEqual(db.__docs.get(`accountDeletionStorageWork/${malformedId}`), { junk: true });
  assert.ok(ids.every((id) => compareBytes(id, malformedId) < 0), "the malformed row sorts last");
  assert.equal(bucket.live.length, 1, "the deferred row's object survives");
  for (const uid of ["uid-1", "uid-3"]) {
    const work = db.__docs.get(`accountDeletionStorageWork/${fence.storageWorkId(uid)}`);
    assert.equal(work.failure_count, 0);
    assert.ok(work.next_eligible_run > ordinal);
  }
});

test("Storage reconciler: 20/21 objects per run, guard boundary exact/equal/+1, firestore version guard exact/equal/+1, atomic DATA_DELETED with work deletion, soft-deleted backoff, saturation at 8/16", async () => {
  const uid = "uid-A";
  const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const startedAt = "2026-09-01T00:00:00.000Z";
  const marker = { ...guardingMarker([capability(uid, credentials.operationId, credentials.proofNonce)]) };
  const seed = (extraDocs = {}, ordinalIso = "2026-09-08T00:00:00Z") => {
    const ordinal = Math.floor(Date.parse(ordinalIso) / 1000 / 300);
    return {
      [STORAGE_STATE_PATH]: reconcilerState("ACCOUNT_DELETION_STORAGE_RECONCILER", { last_started_ordinal: ordinal - 1, last_completed_ordinal: ordinal - 1 }),
      [`users/${uid}`]: { accountDeletion: marker },
      [`accountDeletionStorageWork/${fence.storageWorkId(uid)}`]: storageWorkRow(uid, marker),
      ...extraDocs
    };
  };

  // 21 objects: first run deletes 20, second the last one
  {
    const clock = new FakeClock("2026-09-02T00:00:00.000Z");
    const bucket = fakeBucket({ objects: Array.from({ length: 21 }, (_, i) => ({ name: `inventory/${uid}/f${String(i).padStart(2, "0")}.jpg`, generation: String(10 + i) })) });
    const db = fakeFirestore({ docs: seed({}, "2026-09-02T00:00:00Z"), clock });
    const deps = reconcilerDeps({ db, clock, bucket });
    await fence.runStorageReconciler(scheduleEvent("2026-09-02T00:00:00Z"), deps);
    assert.equal(bucket.live.length, 1);
    assert.ok(bucket.calls.filter(([k]) => k === "getFiles").every(([, q]) => q.maxResults === 20 || q.maxResults === 1));
    clock.millis = Date.parse("2026-09-02T00:05:00.000Z");
    await fence.runStorageReconciler(scheduleEvent("2026-09-02T00:05:00Z"), deps);
    assert.equal(bucket.live.length, 1, "the run after a selection continues past the cursor and wraps");
    assert.equal(db.__docs.get(STORAGE_STATE_PATH).cursor_id, "");
    clock.millis = Date.parse("2026-09-02T00:10:00.000Z");
    await fence.runStorageReconciler(scheduleEvent("2026-09-02T00:10:00Z"), deps);
    assert.equal(bucket.live.length, 0);
    assert.equal(fence.validateAccountDeletionMarker(markerOf(db, uid)).phase, "DELETING_GUARDING");
    assert.equal(markerOf(db, uid).storageGuardCompletedAt, undefined, "the storage guard has not passed");
  }

  // guard boundary: read time at storageGuardAfter refuses, one tick later completes
  for (const [label, iso, expectCompletion] of [["exact", GUARD_AFTER, false], ["+1 ms", "2026-09-08T00:00:00.001Z", true]]) {
    const clock = new FakeClock(iso);
    const db = fakeFirestore({ docs: seed({}, "2026-09-08T00:00:00Z"), clock });
    const deps = reconcilerDeps({ db, clock, evidenceFence: async () => ({ earliestVersionTime: ts("2026-09-01T00:30:00.000Z") }) });
    await fence.runStorageReconciler(scheduleEvent("2026-09-08T00:00:00Z"), deps);
    const after = markerOf(db, uid);
    assert.equal(after.storageGuardCompletedAt !== undefined, expectCompletion, label);
    if (expectCompletion) assert.equal(after.storageGuardCompletedAt.toMillis(), Date.parse(iso));
    assert.equal(after.firestoreVersionGuardCompletedAt, undefined, "version guard requires earliestVersionTime after cleanup");
  }

  // firestore version guard: earliestVersionTime equal to firestoreCleanupAt refuses; strictly later completes; both → DATA_DELETED atomically with work deletion
  const cleanup = marker.firestoreCleanupAt;
  for (const [label, earliest, expectDone] of [["equal", cleanup, false], ["+1 ms", Timestamp.fromMillis(cleanup.toMillis() + 1), true]]) {
    const clock = new FakeClock("2026-09-08T00:05:00.000Z");
    const db = fakeFirestore({ docs: seed({}, "2026-09-08T00:05:00Z"), clock });
    const deps = reconcilerDeps({ db, clock, evidenceFence: async () => ({ earliestVersionTime: earliest }) });
    await fence.runStorageReconciler(scheduleEvent("2026-09-08T00:05:00Z"), deps);
    const after = markerOf(db, uid);
    if (!expectDone) {
      assert.equal(after.state, "DELETING", label);
      assert.ok(after.storageGuardCompletedAt);
      assert.equal(after.firestoreVersionGuardCompletedAt, undefined, label);
      assert.ok(db.__docs.has(`accountDeletionStorageWork/${fence.storageWorkId(uid)}`));
    } else {
      assert.equal(fence.validateAccountDeletionMarker(after).phase, "DATA_DELETED", label);
      assert.equal(after.dataDeletedAt.toMillis(), clock.millis);
      assert.equal(db.__docs.has(`accountDeletionStorageWork/${fence.storageWorkId(uid)}`), false, "work row deleted with DATA_DELETED");
      assert.ok(deps.metrics.some(([n]) => n === "phase2/account_deletion_storage_reconciler_completed_count"));
    }
  }

  // a lease observed at the final transaction blocks DATA_DELETED and survives
  {
    const clock = new FakeClock("2026-09-08T00:05:00.000Z");
    const leaseId = `uol1_${randomUUID()}`;
    const lease = { schema_version: 1, kind: "USER_OUTBOUND_LEASE", account_uid: uid, delivery_id: "d", channel: "fcm", state: "sending", created_at: clock.now(), expires_at: Timestamp.fromMillis(clock.millis + 600_000) };
    const db = fakeFirestore({ docs: seed({ [`users/${uid}/outboundLeases/${leaseId}`]: lease }, "2026-09-08T00:05:00Z"), clock });
    const deps = reconcilerDeps({ db, clock, evidenceFence: async () => ({ earliestVersionTime: Timestamp.fromMillis(cleanup.toMillis() + 1) }) });
    await fence.runStorageReconciler(scheduleEvent("2026-09-08T00:05:00Z"), deps);
    assert.equal(markerOf(db, uid).state, "DELETING");
    assert.deepEqual(db.__docs.get(`users/${uid}/outboundLeases/${leaseId}`), lease);
    assert.ok(deps.logs.some(([c]) => c === "OUTBOUND_LEASE_INVARIANT"));
  }

  // soft-deleted object: fenced backoff, saturation at 8 / +16
  {
    const clock = new FakeClock("2026-09-08T00:05:00.000Z");
    const bucket = fakeBucket({ softDeleted: [{ name: `users/${uid}/old.bin`, timeDeleted: "2026-09-01T00:00:00.000Z" }] });
    const db = fakeFirestore({ docs: seed({}, "2026-09-08T00:05:00Z"), clock });
    const deps = reconcilerDeps({ db, clock, bucket });
    let ordinal = Math.floor(Date.parse("2026-09-08T00:05:00Z") / 1000 / 300);
    const expected = [];
    for (let run = 1; run <= 10; run += 1) {
      const iso = new Date(ordinal * 300 * 1000).toISOString().replace(".000Z", "Z");
      clock.millis = ordinal * 300 * 1000;
      db.__docs.get(`accountDeletionStorageWork/${fence.storageWorkId(uid)}`).next_eligible_run = 0;
      db.__docs.get(STORAGE_STATE_PATH).cursor_id = "";
      await fence.runStorageReconciler(scheduleEvent(iso), deps);
      const work = db.__docs.get(`accountDeletionStorageWork/${fence.storageWorkId(uid)}`);
      const count = Math.min(run, 8);
      expected.push([count, ordinal + Math.min(2 ** count, 16)]);
      assert.deepEqual([work.failure_count, work.next_eligible_run], expected.at(-1), `run ${run}`);
      assert.equal(db.__docs.get(STORAGE_STATE_PATH).last_completed_ordinal, ordinal, "a fenced backoff write settles the run");
      ordinal += 1;
    }
    assert.ok(deps.logs.some(([c]) => c === "ACCOUNT_DELETION_SOFT_DELETED_OBJECT_PRESENT"));
    assert.equal(markerOf(db, uid).state, "DELETING");
  }

  // lease loss: a stale owner after takeover cannot mutate state, work, root, or completion
  {
    const clock = new FakeClock("2026-09-08T00:05:00.000Z");
    const db = fakeFirestore({ docs: seed({}, "2026-09-08T00:05:00Z"), clock });
    const bucket = fakeBucket({ objects: [{ name: `users/${uid}/a.bin` }] });
    const deps = reconcilerDeps({ db, clock, bucket, hooks: { beforeReducer: () => {
      const state = db.__docs.get(STORAGE_STATE_PATH);
      state.lease = { ...state.lease, owner_token: randomUUID() };
    } } });
    await fence.runStorageReconciler(scheduleEvent("2026-09-08T00:05:00Z"), deps);
    const state = db.__docs.get(STORAGE_STATE_PATH);
    assert.equal(state.heartbeat.status, "running", "lease loss leaves running");
    assert.equal(state.last_completed_ordinal, Math.floor(Date.parse("2026-09-08T00:05:00Z") / 1000 / 300) - 1);
    assert.equal(bucket.live.length, 1, "no provider delete without a live lease");
    assert.equal(deps.metrics.length, 0);
    assert.ok(deps.logs.some(([c]) => c === "ACCOUNT_DELETION_RECONCILER_LEASE_LOST"));
  }
});

test("Auth reconciler: pending rows transition at one read time (not-found or accepted delete); guarding rows wait for the deadline, then require fresh not-found, zero residual checks, and unchanged authority to write ACCOUNT_DELETED and delete the work; residual guard exact/equal/+1", async () => {
  const uid = "uid-A";
  const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const caps = [capability(uid, credentials.operationId, credentials.proofNonce)];
  const pendingMarker = dataDeletedMarker(caps);
  const authOrdinalOf = (iso) => fence.authScheduleOrdinal(Math.floor(Date.parse(iso) / 1000));
  const seed = (marker, work, iso, extra = {}) => ({
    [AUTH_STATE_PATH]: reconcilerState("ACCOUNT_DELETION_AUTH_RECONCILER", { last_started_ordinal: authOrdinalOf(iso) - 1, last_completed_ordinal: authOrdinalOf(iso) - 1 }),
    [`users/${uid}`]: { accountDeletion: marker },
    [`accountDeletionAuthWork/${fence.authWorkId(uid)}`]: work,
    ...extra
  });

  // pending → guarding (user-not-found)
  {
    const iso = "2026-09-08T00:12:00Z";
    const clock = new FakeClock("2026-09-08T00:12:00.000Z");
    const db = fakeFirestore({ docs: seed(pendingMarker, authWorkRow(uid, pendingMarker), iso), clock });
    const auth = fakeAuth();
    const deps = reconcilerDeps({ db, clock, auth });
    await fence.runAuthReconciler(scheduleEvent(iso), deps);
    const after = markerOf(db, uid);
    assert.equal(fence.validateAccountDeletionMarker(after).phase, "AUTH_GUARDING");
    assert.equal(after.authAbsenceObservedAt.toMillis(), clock.millis);
    assert.equal(after.authGuardAfter.toMillis(), clock.millis + 86400_000);
    const work = db.__docs.get(`accountDeletionAuthWork/${fence.authWorkId(uid)}`);
    assert.equal(work.state, "guarding");
    assert.equal(work.next_eligible_run, fence.firstAuthOrdinalAfter(after.authGuardAfter));
    assert.deepEqual(auth.calls, [["getUser", uid]]);
  }

  // pending with a present user: one accepted deleteUser
  {
    const iso = "2026-09-08T00:12:00Z";
    const clock = new FakeClock("2026-09-08T00:12:00.000Z");
    const db = fakeFirestore({ docs: seed(pendingMarker, authWorkRow(uid, pendingMarker), iso), clock });
    const auth = fakeAuth({ getUser: () => "present" });
    await fence.runAuthReconciler(scheduleEvent(iso), reconcilerDeps({ db, clock, auth }));
    assert.deepEqual(auth.calls, [["getUser", uid], ["deleteUser", uid]]);
    assert.equal(markerOf(db, uid).state, "AUTH_GUARDING");
  }

  // pending transport failure: fenced backoff keyed by the schedule ordinal, run settles
  {
    const iso = "2026-09-08T00:12:00Z";
    const clock = new FakeClock("2026-09-08T00:12:00.000Z");
    const db = fakeFirestore({ docs: seed(pendingMarker, authWorkRow(uid, pendingMarker), iso), clock });
    const transport = new Error("ECONNRESET"); transport.code = "ECONNRESET";
    const deps = reconcilerDeps({ db, clock, auth: fakeAuth({ getUser: () => transport }) });
    await fence.runAuthReconciler(scheduleEvent(iso), deps);
    const work = db.__docs.get(`accountDeletionAuthWork/${fence.authWorkId(uid)}`);
    assert.equal(work.state, "delete_pending");
    assert.deepEqual([work.failure_count, work.next_eligible_run], [1, authOrdinalOf(iso) + 2]);
    assert.equal(db.__docs.get(AUTH_STATE_PATH).last_completed_ordinal, authOrdinalOf(iso));
    assert.equal(markerOf(db, uid).state, "DATA_DELETED");
  }

  // guarding: deadline exact/equal → only next_eligible_run advances; +1 → completion
  const guardingMarkerA = authGuardingMarker(caps); // authGuardAfter 2026-09-09T00:11:00.000Z
  const guardingWork = (extra = {}) => authWorkRow(uid, guardingMarkerA, { state: "guarding", auth_absence_observed_at: guardingMarkerA.authAbsenceObservedAt, auth_guard_after: guardingMarkerA.authGuardAfter, next_eligible_run: 0, created_at: guardingMarkerA.dataDeletedAt, updated_at: guardingMarkerA.authAbsenceObservedAt, ...extra });
  {
    const iso = "2026-09-09T00:07:00Z"; // boundary + 120 s before the deadline
    const clock = new FakeClock("2026-09-09T00:11:00.000Z"); // read time exactly at the deadline
    const db = fakeFirestore({ docs: seed(guardingMarkerA, guardingWork(), iso), clock });
    const auth = fakeAuth();
    const deps = reconcilerDeps({ db, clock, auth });
    await fence.runAuthReconciler(scheduleEvent(iso), deps);
    const work = db.__docs.get(`accountDeletionAuthWork/${fence.authWorkId(uid)}`);
    assert.equal(work.state, "guarding");
    assert.equal(work.next_eligible_run, fence.firstAuthOrdinalAfter(guardingMarkerA.authGuardAfter));
    assert.equal(auth.calls.length, 0, "no provider call at or before the deadline");
    assert.equal(markerOf(db, uid).state, "AUTH_GUARDING");
  }
  {
    const iso = "2026-09-09T00:07:00Z";
    const clock = new FakeClock("2026-09-09T00:11:00.001Z");
    const db = fakeFirestore({ docs: seed(guardingMarkerA, guardingWork(), iso), clock });
    const auth = fakeAuth();
    const http = fakeProviderHTTP((options) => {
      assert.ok(options.url.includes(encodeURIComponent(uid)) || options.url.includes(uid));
      return jsonResponse({ matchCount: 0 });
    });
    const deps = reconcilerDeps({ db, clock, auth });
    deps.providerHTTP = http;
    deps.timeouts.providerMs = 3000;
    await fence.runAuthReconciler(scheduleEvent(iso), deps);
    const after = markerOf(db, uid);
    assert.equal(fence.validateAccountDeletionMarker(after).phase, "ACCOUNT_DELETED", JSON.stringify(deps.logs));
    assert.equal(after.authGuardCompletedAt.toMillis(), clock.millis);
    assert.equal(after.accountDeletedAt.toMillis(), clock.millis);
    assert.equal(db.__docs.has(`accountDeletionAuthWork/${fence.authWorkId(uid)}`), false);
    assert.deepEqual(auth.calls, [["getUser", uid]]);
    assert.equal(http.requests.length, 1, "one residual query per google_authenticated_uid_zero_v1 check");
    assert.ok(deps.metrics.some(([n]) => n === "phase2/account_deletion_auth_reconciler_completed_count"));
  }
  // Auth present, nonzero residual, or authority drift retains guarding with backoff and never claims completion
  const retainers = [
    ["auth present", fakeAuth({ getUser: () => "present" }), () => jsonResponse({ matchCount: 0 }), {}],
    ["nonzero residual", fakeAuth(), () => jsonResponse({ matchCount: 1 }), {}],
    ["malformed residual", fakeAuth(), () => jsonResponse({ totalSize: 0 }), {}],
    ["authority drift", fakeAuth(), () => jsonResponse({ matchCount: 0 }), { authority_sha256: sha256("other") }]
  ];
  for (const [label, auth, respond, workOverrides] of retainers) {
    const iso = "2026-09-09T00:07:00Z";
    const clock = new FakeClock("2026-09-09T00:11:00.001Z");
    const db = fakeFirestore({ docs: seed(guardingMarkerA, guardingWork(workOverrides), iso), clock });
    const deps = reconcilerDeps({ db, clock, auth });
    deps.providerHTTP = fakeProviderHTTP(() => respond());
    deps.timeouts.providerMs = 3000;
    await fence.runAuthReconciler(scheduleEvent(iso), deps);
    assert.equal(markerOf(db, uid).state, "AUTH_GUARDING", label);
    const work = db.__docs.get(`accountDeletionAuthWork/${fence.authWorkId(uid)}`);
    assert.equal(work.state, "guarding", label);
    if (label !== "authority drift") {
      assert.equal(work.failure_count, 1, label);
      assert.equal(work.next_eligible_run, authOrdinalOf(iso) + 2, label);
    } else {
      assert.deepEqual(work, guardingWork(workOverrides), "invariant rows are never rewritten");
    }
  }
});

test("historical entry: a migration-only marker carries one server-generated capability, and the guarding branch is entered without an Auth delete", async () => {
  const clock = new FakeClock("2026-09-01T00:00:00.000Z");
  const db = fakeFirestore({ docs: {}, clock });
  const deps = reconcilerDeps({ db, clock });
  const created = await fence.createMigrationMarker(deps, { uid: "uid-H" });
  assert.match(created.operationId, /^adel1_[0-9a-f-]{36}$/);
  assert.equal(created.proofSHA256.length, 64);
  const marker = markerOf(db, "uid-H");
  assert.equal(fence.validateAccountDeletionMarker(marker).phase, "DELETING_SWEEPING");
  assert.deepEqual(marker.capabilities, [{ operationId: created.operationId, proofSHA256: created.proofSHA256 }]);
  fence.validateStorageWork(db.__docs.get(`accountDeletionStorageWork/${fence.storageWorkId("uid-H")}`), { uid: "uid-H", marker });
  assert.deepEqual(Object.keys(db.__docs.get("users/uid-H")), ["accountDeletion"]);
  await assert.rejects(fence.createMigrationMarker(deps, { uid: "uid-H" }), (e) => e.code === "ACCOUNT_DELETION_MARKER_PRESENT");

  const dataMarker = dataDeletedMarker([capability("uid-H", created.operationId, "n")]);
  clock.millis = Date.parse("2026-09-08T00:20:00.000Z");
  const hdb = fakeFirestore({ docs: { "users/uid-H": { accountDeletion: dataMarker } }, clock });
  const auth = fakeAuth();
  const hdeps = reconcilerDeps({ db: hdb, clock, auth });
  const outcome = await fence.enterHistoricalGuarding(hdeps, { uid: "uid-H" });
  assert.equal(outcome.transitioned, true);
  assert.equal(fence.validateAccountDeletionMarker(markerOf(hdb, "uid-H")).phase, "AUTH_GUARDING");
  assert.deepEqual(auth.calls, [["getUser", "uid-H"]]);
  const present = fakeAuth({ getUser: () => "present" });
  const pdb = fakeFirestore({ docs: { "users/uid-H": { accountDeletion: dataMarker } }, clock });
  await assert.rejects(fence.enterHistoricalGuarding(reconcilerDeps({ db: pdb, clock, auth: present }), { uid: "uid-H" }), (e) => e.code === "LEGACY_ACCOUNT_AUTH_RACE");
  assert.deepEqual(present.calls, [["getUser", "uid-H"]]);
  assert.equal(markerOf(pdb, "uid-H").state, "DATA_DELETED");
});

// ---------------------------------------------------------------------------
// I5 — provider cache (resolveProvider.js), support-reply FCM surface and writing tails
// (supportAdmin.js), submitWorkflowAnswers fence (getWorkflowQualifying.js)
// ---------------------------------------------------------------------------

const fs = require("node:fs");
const path = require("node:path");
const admin = require("firebase-admin");
const { FieldValue: AdminFieldValue, FieldPath: AdminFieldPath, Timestamp: AdminTimestamp } = require("firebase-admin/firestore");

let activeDb = null;
let activeMessaging = null;
const firestoreStub = () => activeDb;
firestoreStub.FieldValue = AdminFieldValue;
firestoreStub.FieldPath = AdminFieldPath;
firestoreStub.Timestamp = AdminTimestamp;
Object.defineProperty(admin, "firestore", { configurable: true, value: firestoreStub });
Object.defineProperty(admin, "messaging", { configurable: true, value: () => activeMessaging });
process.env.SUPPORT_ADMIN_EMAILS = "admin@example.com";

const resolveProviderModule = require("../resolveProvider");
const supportAdmin = require("../supportAdmin");
const { executeWorkflowAnswers } = require("../getWorkflowQualifying");

function fakeMessaging(script = () => ({ success: true })) {
  const calls = [];
  return {
    calls,
    async sendEachForMulticast(message) {
      calls.push(message);
      const responses = message.tokens.map((token) => {
        const outcome = script(token);
        if (outcome.success) return { success: true, messageId: `m-${token}` };
        return { success: false, error: { code: outcome.code, message: "x" } };
      });
      return { successCount: responses.filter((r) => r.success).length, failureCount: responses.filter((r) => !r.success).length, responses };
    }
  };
}

const ADMIN_REQUEST = (data) => ({ auth: { uid: "admin-1", token: { email: "admin@example.com" } }, data });

test("provider cache graph: cacheResolved is gone, high-confidence resolutions write nothing, loadDirectory admits only exact seeded rows, and the Anthropic search runs under the outbound lease", async () => {
  const source = fs.readFileSync(path.join(__dirname, "..", "resolveProvider.js"), "utf8");
  assert.equal(source.includes("cacheResolved"), false);
  assert.equal(source.includes("resolvedAt"), false);
  assert.equal(resolveProviderModule._test.cacheResolved, undefined);
  const { resolveProviderRequest, loadDirectory, resetDirectoryCache, safePayload } = resolveProviderModule._test;

  const clock = new FakeClock();
  const seeded = { providerId: "seeded1", name: "Comcast", aliases: ["xfinity"], category: "internet", method: "link", source: "seeded", cancelUrl: "https://www.xfinity.com/cancel", citations: [], requirements: [] };
  const db = fakeFirestore({ docs: {
    "users/uid-A": { name: "A" },
    "providerDirectory/seeded1": seeded,
    "providerDirectory/resolved1": { ...seeded, providerId: "resolved1", name: "Resolved Co", source: "resolved" },
    "providerDirectory/nosource": { ...seeded, providerId: "nosource", name: "No Source", source: undefined },
    "providerDirectory/wrongsource": { ...seeded, providerId: "wrongsource", name: "Wrong", source: "SEEDED" }
  }, clock });
  resetDirectoryCache();
  const providers = await loadDirectory({ db });
  assert.deepEqual(providers.map((p) => p.providerId), ["seeded1"]);
  assert.deepEqual(await loadDirectory({ db }), providers, "the process-global cache retains only admitted rows");

  const searched = { name: "Foo Energy", url: "https://foo.example/cancel", phone: null, method: "link", confidence: "high", citations: [{ title: "Cancel", url: "https://foo.example/cancel" }], requirements: [] };
  let searches = 0;
  const result = await resolveProviderRequest("Foo Energy", "utilities", "cancel", { db, uid: "uid-A", now: () => clock.now(), lookup: async () => null, search: async () => { searches += 1; return searched; } });
  assert.deepEqual(result, safePayload(searched, "Foo Energy"));
  assert.equal(searches, 1);
  assert.equal(db.__writes.some((w) => w.path.startsWith("providerDirectory/")), false, "no Firestore mutation from a resolution");
  const leaseWrites = db.__writes.filter((w) => w.path.startsWith("users/uid-A/outboundLeases/uol1_"));
  assert.deepEqual(leaseWrites.map((w) => w.type), ["create", "delete"]);
  assert.equal(leaseWrites[0].data.channel, "anthropic");
  assert.equal([...db.__docs.keys()].filter((p) => p.includes("/outboundLeases/")).length, 0);

  // a deleting account never reaches the provider
  const fenced = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: sweepingMarker([capability(UID, freshOperationId(), freshProofNonce())]) } }, clock });
  let fencedSearches = 0;
  const fencedResult = await resolveProviderRequest("Foo Energy", "utilities", "cancel", { db: fenced, uid: "uid-A", now: () => clock.now(), lookup: async () => null, search: async () => { fencedSearches += 1; return searched; } });
  assert.equal(fencedSearches, 0);
  assert.equal(fencedResult.method, "concierge");
  assert.equal(fenced.__writes.length, 0);
});

test("support-reply FCM surface: exact C6.8 payload, limit(501) with FCM_DESTINATION_CAPACITY, the frozen 19-code union, token deletion only for the two codes, lease-dominated send, and fixed-code logging", async () => {
  const errorModule = require(path.join(__dirname, "..", "node_modules", "firebase-admin", "lib", "utils", "error.js"));
  const sdkCodes = Object.values(errorModule.MessagingClientErrorCode).map((v) => `messaging/${v.code}`).sort();
  assert.equal(sdkCodes.length, 19);
  assert.deepEqual([...supportAdmin._test.FCM_ACCEPTED_FAILURE_CODES_V1].sort(), sdkCodes);
  assert.equal(supportAdmin._test.FCM_DESTINATION_CAPACITY, 501);
  assert.deepEqual(supportAdmin._test.FCM_TOKEN_DELETION_CODES_V1, ["messaging/invalid-registration-token", "messaging/registration-token-not-registered"]);
  const source = fs.readFileSync(path.join(__dirname, "..", "supportAdmin.js"), "utf8");
  assert.equal(/console\.(log|error|warn|info)/.test(source), false, "no dynamic server log sink");

  const clock = new FakeClock();
  const tokens = { "users/uid-A/fcmTokens/tok-ok": { createdAt: clock.now(), platform: "ios" }, "users/uid-A/fcmTokens/tok-gone": { createdAt: clock.now(), platform: "ios" }, "users/uid-A/fcmTokens/tok-invalid": { createdAt: clock.now(), platform: "ios" }, "users/uid-A/fcmTokens/tok-internal": { createdAt: clock.now(), platform: "ios" }, "users/uid-A/fcmTokens/tok-weird": { createdAt: clock.now(), platform: "ios" } };
  const db = fakeFirestore({ docs: { "users/uid-A": { name: "A" }, ...tokens }, clock });
  const messaging = fakeMessaging((token) => ({
    "tok-ok": { success: true }, "tok-gone": { success: false, code: "messaging/registration-token-not-registered" },
    "tok-invalid": { success: false, code: "messaging/invalid-registration-token" }, "tok-internal": { success: false, code: "messaging/internal-error" },
    "tok-weird": { success: false, code: "messaging/not-a-real-code" }
  }[token]));
  const logs = [];
  await supportAdmin._test.sendSupportReplyPush("uid-A", { db, messaging, now: () => clock.now(), log: (code, counts) => logs.push([code, counts]) });
  assert.equal(messaging.calls.length, 1);
  const message = messaging.calls[0];
  assert.deepEqual([...message.tokens].sort(), ["tok-gone", "tok-internal", "tok-invalid", "tok-ok", "tok-weird"]);
  assert.deepEqual({ ...message, tokens: null }, {
    tokens: null,
    notification: { title: "Peezy", body: "You have a new support reply." },
    data: { thread: "support" },
    android: { ttl: 0 },
    apns: { headers: { "apns-expiration": "0" }, payload: { aps: { sound: "default", badge: 1, category: "PEEZY_SUPPORT_REPLY_V1" } } }
  });
  assert.deepEqual([...db.__docs.keys()].filter((p) => p.startsWith("users/uid-A/fcmTokens/")).sort(), ["users/uid-A/fcmTokens/tok-internal", "users/uid-A/fcmTokens/tok-ok", "users/uid-A/fcmTokens/tok-weird"]);
  const leaseWrites = db.__writes.filter((w) => w.path.startsWith("users/uid-A/outboundLeases/uol1_"));
  assert.deepEqual(leaseWrites.map((w) => [w.type, w.data?.channel]), [["create", "fcm"], ["delete", undefined]]);
  assert.ok(logs.some(([code]) => code === "FCM_UNKNOWN_FAILURE_CODE"));
  assert.ok(logs.every(([code, counts]) => typeof code === "string" && !JSON.stringify(counts).includes("uid-A") && !JSON.stringify(counts).includes("tok-")));

  // 501 rows: capacity invariant, nothing sent
  const many = {};
  for (let i = 0; i < 501; i += 1) many[`users/uid-B/fcmTokens/t${String(i).padStart(3, "0")}`] = { createdAt: clock.now(), platform: "ios" };
  const capDb = fakeFirestore({ docs: { "users/uid-B": {}, ...many }, clock });
  const capMessaging = fakeMessaging();
  const capLogs = [];
  await supportAdmin._test.sendSupportReplyPush("uid-B", { db: capDb, messaging: capMessaging, now: () => clock.now(), log: (code) => capLogs.push(code) });
  assert.equal(capMessaging.calls.length, 0);
  assert.ok(capLogs.includes("FCM_DESTINATION_CAPACITY"));

  // a deleting account: the lease refuses and nothing is sent
  const fencedDb = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: sweepingMarker([capability(UID, freshOperationId(), freshProofNonce())]) }, ...tokens }, clock });
  const fencedMessaging = fakeMessaging();
  await supportAdmin._test.sendSupportReplyPush("uid-A", { db: fencedDb, messaging: fencedMessaging, now: () => clock.now(), log: () => {} });
  assert.equal(fencedMessaging.calls.length, 0);
  assert.equal(fencedDb.__writes.length, 0);
});

test("supportAdmin writing tails are root-fenced: adminGetThread, adminReplySupport, adminMarkSeen, and adminSetThreadStatus refuse a deleting account with zero writes and otherwise commit their records", async () => {
  const clock = new FakeClock();
  const marker = sweepingMarker([capability(UID, freshOperationId(), freshProofNonce())]);
  const fencedDocs = () => ({ "users/uid-A": { accountDeletion: marker }, "supportThreads/uid-A": { uid: "uid-A", status: "open" }, "users/uid-A/supportChat/m1": { text: "hi", sender: "user", timestamp: clock.now() } });
  const calls = [
    ["adminGetThread", { uid: "uid-A" }],
    ["adminReplySupport", { uid: "uid-A", text: "hello" }],
    ["adminMarkSeen", { uid: "uid-A" }],
    ["adminSetThreadStatus", { uid: "uid-A", status: "resolved" }]
  ];
  for (const [name, data] of calls) {
    activeDb = fakeFirestore({ docs: fencedDocs(), clock });
    activeMessaging = fakeMessaging();
    await assert.rejects(supportAdmin[name].run(ADMIN_REQUEST(data)), (e) => e.code === "failed-precondition" && e.details?.reason === "ACCOUNT_DELETION_FENCED", name);
    assert.equal(activeDb.__writes.length, 0, name);
    assert.equal(activeMessaging.calls.length, 0, name);
  }
  // unfenced commits
  activeDb = fakeFirestore({ docs: { "users/uid-A": { name: "A" }, "supportThreads/uid-A": { uid: "uid-A", status: "open", unreadForAdmin: 2 }, "users/uid-A/fcmTokens/tok": { createdAt: clock.now(), platform: "ios" } }, clock });
  activeMessaging = fakeMessaging();
  const reply = await supportAdmin.adminReplySupport.run(ADMIN_REQUEST({ uid: "uid-A", text: "hello" }));
  assert.equal(reply.success, true);
  const message = activeDb.__docs.get(`users/uid-A/supportChat/${reply.messageId}`);
  assert.deepEqual({ ...message, timestamp: null }, { text: "hello", sender: "support", timestamp: null, read: false });
  assert.equal(activeDb.__docs.get("supportThreads/uid-A").lastSender, "support");
  assert.equal(activeDb.__docs.get("supportThreads/uid-A").unreadForAdmin, 0);
  assert.equal(activeMessaging.calls.length, 1);
  await supportAdmin.adminMarkSeen.run(ADMIN_REQUEST({ uid: "uid-A" }));
  assert.ok(activeDb.__docs.get("users/uid-A/supportChat/_meta").adminSeenAt);
  await supportAdmin.adminSetThreadStatus.run(ADMIN_REQUEST({ uid: "uid-A", status: "resolved" }));
  assert.equal(activeDb.__docs.get("supportThreads/uid-A").status, "resolved");
  const thread = await supportAdmin.adminGetThread.run(ADMIN_REQUEST({ uid: "uid-A" }));
  assert.equal(thread.uid, "uid-A");
  assert.equal(thread.status, "resolved");
  activeDb = null;
  activeMessaging = null;
});

test("submitWorkflowAnswers is root-fenced: a deleting account refuses before any write", async () => {
  const clock = new FakeClock();
  const marker = sweepingMarker([capability(UID, freshOperationId(), freshProofNonce())]);
  const db = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: marker }, "users/uid-A/tasks/cancel_utilities": { status: "Upcoming" } }, clock });
  await assert.rejects(executeWorkflowAnswers(db, "uid-A", "cancel_utilities", {}, new Date(clock.millis), () => clock.now()), (e) => e.code === "failed-precondition" && e.details?.reason === "ACCOUNT_DELETION_FENCED");
  assert.equal(db.__writes.length, 0);
  const open = fakeFirestore({ docs: { "users/uid-A": { name: "A" }, "users/uid-A/tasks/cancel_utilities": { status: "Upcoming" } }, clock });
  const result = await executeWorkflowAnswers(open, "uid-A", "cancel_utilities", {}, new Date(clock.millis), () => clock.now());
  assert.equal(result.success, true);
});

// ---------------------------------------------------------------------------
// I6 — C7 pin gates and the emulator-backed subset (Decision 8; skipped offline)
// ---------------------------------------------------------------------------

test("C7 pins: recursive-delete.js and firestore_client_config.json hashes and constants, transitive package versions, and the pinned function deadlines", () => {
  const root = path.join(__dirname, "..");
  const fileHash = (p) => createHash("sha256").update(fs.readFileSync(p)).digest("hex");
  const firestorePkg = path.join(root, "node_modules", "@google-cloud", "firestore");
  assert.equal(fileHash(path.join(firestorePkg, "build", "src", "recursive-delete.js")), "2a17d8fb6d975cdf3863c3826783f061a728a8a710fa7a3f81b10d0e7c407270");
  assert.equal(fileHash(path.join(firestorePkg, "build", "src", "v1", "firestore_client_config.json")), "2ed7a9046d766121b7f308b22384b1a6caaf7c6eaed5d9ea553556af3c987e41");
  const recursive = require(path.join(firestorePkg, "build", "src", "recursive-delete.js"));
  assert.equal(recursive.RECURSIVE_DELETE_MAX_PENDING_OPS, 5000);
  assert.equal(recursive.RECURSIVE_DELETE_MIN_PENDING_OPS, 1000);
  const config = JSON.parse(fs.readFileSync(path.join(firestorePkg, "build", "src", "v1", "firestore_client_config.json"), "utf8"));
  const methods = config.interfaces["google.firestore.v1.Firestore"].methods;
  assert.equal(methods.Commit.timeout_millis, 60000);
  assert.equal(methods.BatchWrite.timeout_millis, 60000);
  const version = (name) => JSON.parse(fs.readFileSync(path.join(root, "node_modules", ...name.split("/"), "package.json"), "utf8")).version;
  assert.deepEqual({ firestore: version("@google-cloud/firestore"), storage: version("@google-cloud/storage"), gax: version("google-gax"), auth: version("google-auth-library"), admin: version("firebase-admin") },
    { firestore: "7.11.6", storage: "7.18.0", gax: "4.6.1", auth: "9.15.1", admin: "13.6.0" });
  const index = fs.readFileSync(path.join(root, "index.js"), "utf8");
  assert.match(index, /exports\.deleteAccount = onCall\(\s*\{ region: 'us-central1', timeoutSeconds: 60, memory: '512MiB' \}/);
  assert.equal((index.match(/timeoutSeconds: 270/g) || []).length, 2, "both reconcilers carry the 270 s deadline");
  const taskPlan = fs.readFileSync(path.join(root, "taskPlan.js"), "utf8");
  assert.match(taskPlan, /const changeTaskPlan = onCall\(\s*\{ region: "us-central1", timeoutSeconds: 540, memory: "512MiB" \}/);
});

const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST;
const emulatorSkip = EMULATOR_HOST ? false : "FIRESTORE_EMULATOR_HOST is unset; run scripts/test-emulator.sh node";

function emulatorDeps({ db, auth, client, extra = {} }) {
  const deps = {
    db, auth, bucket: fakeBucket(), logs: [], hooks: {}, metrics: [],
    evidence: () => testEvidence(),
    evidenceFence: async () => ({ earliestVersionTime: Timestamp.fromMillis(Date.now()) }),
    now: () => Timestamp.fromMillis(Date.now()),
    log: (code, counts) => deps.logs.push([code, counts]),
    metric: (name, value) => deps.metrics.push([name, value]),
    firestore: { client, documentsRoot: "projects/demo-peezy-phase1/databases/(default)/documents" },
    verifyBucketConfiguration: () => {},
    budget: { sweeps: 4, storagePages: 4, deadlineMs: 42_000 },
    timeouts: { getUserMs: 3000, deleteUserMs: 10000, providerMs: 3000 },
    ...extra
  };
  return deps;
}

function emulatorHandles() {
  const { initializeApp, getApps } = require("firebase-admin/app");
  const { getFirestore } = require("firebase-admin/firestore");
  const { getAuth } = require("firebase-admin/auth");
  const grpc = require("@grpc/grpc-js");
  const { v1 } = require("@google-cloud/firestore");
  const app = getApps().length ? getApps()[0] : initializeApp({ projectId: "demo-peezy-phase1" });
  const [host, port] = EMULATOR_HOST.split(":");
  const raw = new v1.FirestoreClient({ servicePath: host, port: Number(port), sslCreds: grpc.credentials.createInsecure() });
  // The emulator requires the owner bearer for metadata RPCs (production credentials supply it).
  const client = { listCollectionIds: (request, options) => raw.listCollectionIds(request, { ...options, otherArgs: { headers: { authorization: "Bearer owner" } } }) };
  return { db: getFirestore(app), auth: getAuth(app), client };
}

function lastBoundaryIso(offsetSeconds) {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const epoch = Math.floor((nowSeconds - offsetSeconds) / 300) * 300 + offsetSeconds;
  return new Date(epoch * 1000).toISOString().replace(".000Z", "Z");
}

test("emulator: begin, sweeps, and guarding on real Firestore — listCollectionIds tuple, recursiveDelete, orphaned descendants, external families, other users untouched", { skip: emulatorSkip }, async () => {
  const { db, auth, client } = emulatorHandles();
  const uid = `emu-${randomUUID().slice(0, 8)}`;
  await db.doc(`users/${uid}`).set({ name: "E", email: "e@example.com" });
  await db.doc(`users/${uid}/tasks/t1`).set({ status: "Upcoming" });
  await db.doc(`users/${uid}/tasks/t1/nested/x`).set({ deep: true });
  await db.doc(`users/${uid}/orphan/missing/deep/leaf`).set({ orphan: true });
  await db.doc(`userKnowledge/${uid}`).set({ facts: 1 });
  await db.doc(`conciergeRequests/${uid}-r1`).set({ userId: uid });
  await db.doc(`users/other-${uid}/tasks/t`).set({ keep: true });
  const deps = emulatorDeps({ db, auth, client });
  const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const request = (action) => ({ data: { schemaVersion: 1, action, uid, ...credentials }, auth: { uid } });
  await expectDeletionError(() => fence.handleAccountDeletionRequest(request("begin"), deps), "unavailable", RETRY);
  let marker;
  for (let i = 0; i < 6; i += 1) {
    await expectDeletionError(() => fence.handleAccountDeletionRequest(request("resume"), deps), "unavailable", RETRY);
    marker = (await db.doc(`users/${uid}`).get()).data().accountDeletion;
    if (fence.validateAccountDeletionMarker(marker).phase === "DELETING_GUARDING") break;
  }
  assert.equal(fence.validateAccountDeletionMarker(marker).phase, "DELETING_GUARDING", JSON.stringify(deps.logs));
  const [ids] = await client.listCollectionIds({ parent: `${deps.firestore.documentsRoot}/users/${uid}`, pageSize: 100 }, { autoPaginate: false });
  assert.deepEqual([...ids], []);
  assert.equal((await db.doc(`userKnowledge/${uid}`).get()).exists, false);
  assert.equal((await db.doc(`conciergeRequests/${uid}-r1`).get()).exists, false);
  assert.equal((await db.doc(`users/other-${uid}/tasks/t`).get()).exists, true);
  assert.deepEqual(Object.keys((await db.doc(`users/${uid}`).get()).data()), ["accountDeletion"]);
  fence.validateStorageWork((await db.doc(`accountDeletionStorageWork/${fence.storageWorkId(uid)}`).get()).data(), { uid, marker });
  assert.equal(marker.capabilities[0].operationId, credentials.operationId);
});

test("emulator: Storage reconciler → DATA_DELETED, finalize → AUTH_GUARDING through the Auth emulator, Auth reconciler → ACCOUNT_DELETED", { skip: emulatorSkip }, async () => {
  const { db, auth, client } = emulatorHandles();
  const uid = `emu-${randomUUID().slice(0, 8)}`;
  const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
  const startedAt = Timestamp.fromMillis(Date.now() - 12 * 86400_000);
  const guardAfter = Timestamp.fromMillis(startedAt.toMillis() + 604800_000);
  const cleanupAt = Timestamp.fromMillis(startedAt.toMillis() + 3600_000);
  const marker = { schemaVersion: 1, state: "DELETING", capabilities: [capability(uid, credentials.operationId, credentials.proofNonce)], startedAt, storageGuardAfter: guardAfter, firestoreCleanupAt: cleanupAt };
  fence.validateAccountDeletionMarker(marker);
  await db.doc(`users/${uid}`).set({ accountDeletion: marker });
  await db.doc(`accountDeletionStorageWork/${fence.storageWorkId(uid)}`).set({ schema_version: 1, kind: "ACCOUNT_DELETION_STORAGE_WORK", work_id: fence.storageWorkId(uid), account_uid: uid, marker_started_at: startedAt, storage_guard_after: guardAfter, failure_count: 0, next_eligible_run: 0, created_at: startedAt, updated_at: startedAt });
  const storageIso = lastBoundaryIso(0);
  const storageOrdinal = Math.floor(Date.parse(storageIso) / 1000 / 300);
  await db.doc("phase2System/accountDeletionStorageReconcilerV1").set({ schema_version: 1, kind: "ACCOUNT_DELETION_STORAGE_RECONCILER", last_started_ordinal: storageOrdinal - 12, last_completed_ordinal: storageOrdinal - 12, cursor_id: "", lease: null, heartbeat: null });
  const deps = emulatorDeps({ db, auth, client });
  // other rows may sit in the shared work collection from earlier tests in this run; walk past boundaries until this uid's row is reduced
  for (let i = 0; i < 12; i += 1) {
    const state = (await db.doc("phase2System/accountDeletionStorageReconcilerV1").get()).data();
    const iso = new Date((state.last_started_ordinal + 1) * 300 * 1000).toISOString().replace(".000Z", "Z");
    if (Date.parse(iso) > Date.now()) break;
    await fence.runStorageReconciler({ scheduleTime: iso }, deps);
    const current = (await db.doc(`users/${uid}`).get()).data().accountDeletion;
    if (fence.validateAccountDeletionMarker(current).phase === "DATA_DELETED") break;
  }
  const dataDeleted = (await db.doc(`users/${uid}`).get()).data().accountDeletion;
  assert.equal(fence.validateAccountDeletionMarker(dataDeleted).phase, "DATA_DELETED", JSON.stringify(deps.logs));
  assert.equal((await db.doc(`accountDeletionStorageWork/${fence.storageWorkId(uid)}`).get()).exists, false);

  await auth.createUser({ uid });
  const wire = await fence.handleAccountDeletionRequest({ data: { schemaVersion: 1, action: "finalize", uid, ...credentials } }, deps);
  assert.equal(wire.kind, "account_deletion_auth_guarding");
  assert.equal(wire.replayed, false);
  await assert.rejects(auth.getUser(uid), (e) => fence.isUserNotFound(e));
  const guarding = (await db.doc(`users/${uid}`).get()).data().accountDeletion;
  assert.equal(fence.validateAccountDeletionMarker(guarding).phase, "AUTH_GUARDING");
  const work = (await db.doc(`accountDeletionAuthWork/${fence.authWorkId(uid)}`).get()).data();
  assert.equal(work.state, "guarding");

  // rewind the whole time chain consistently so the guard deadline (retention 86400 s) is already past:
  // completions and data-final four days ago (after storageGuardAfter = startedAt + 7 d), absence two days ago, deadline one day ago
  const fourDaysAgo = Timestamp.fromMillis(Date.now() - 4 * 86400_000);
  const observed = Timestamp.fromMillis(Date.now() - 2 * 86400_000);
  const pastGuard = Timestamp.fromMillis(observed.toMillis() + 86400_000);
  const rewound = { ...guarding, storageGuardCompletedAt: fourDaysAgo, firestoreVersionGuardCompletedAt: fourDaysAgo, dataDeletedAt: fourDaysAgo, authAbsenceObservedAt: observed, authGuardAfter: pastGuard };
  fence.validateAccountDeletionMarker(rewound);
  await db.doc(`users/${uid}`).update({ accountDeletion: rewound });
  await db.doc(`accountDeletionAuthWork/${fence.authWorkId(uid)}`).set({ ...work, data_deleted_at: fourDaysAgo, auth_absence_observed_at: observed, auth_guard_after: pastGuard, next_eligible_run: 0, created_at: fourDaysAgo, updated_at: observed });
  const authIso = lastBoundaryIso(120);
  const authOrdinal = fence.authScheduleOrdinal(Math.floor(Date.parse(authIso) / 1000));
  await db.doc("phase2System/accountDeletionAuthReconcilerV1").set({ schema_version: 1, kind: "ACCOUNT_DELETION_AUTH_RECONCILER", last_started_ordinal: authOrdinal - 12, last_completed_ordinal: authOrdinal - 12, cursor_id: "", lease: null, heartbeat: null });
  const authDeps = emulatorDeps({ db, auth, client, extra: { providerHTTP: fakeProviderHTTP(() => jsonResponse({ matchCount: 0 })) } });
  for (let i = 0; i < 12; i += 1) {
    const state = (await db.doc("phase2System/accountDeletionAuthReconcilerV1").get()).data();
    const iso = new Date(((state.last_started_ordinal + 1) * 300 + 120) * 1000).toISOString().replace(".000Z", "Z");
    if (Date.parse(iso) > Date.now()) break;
    await fence.runAuthReconciler({ scheduleTime: iso }, authDeps);
    const current = (await db.doc(`users/${uid}`).get()).data().accountDeletion;
    if (fence.validateAccountDeletionMarker(current).phase === "ACCOUNT_DELETED") break;
  }
  const deleted = (await db.doc(`users/${uid}`).get()).data().accountDeletion;
  assert.equal(fence.validateAccountDeletionMarker(deleted).phase, "ACCOUNT_DELETED", JSON.stringify(authDeps.logs));
  assert.equal((await db.doc(`accountDeletionAuthWork/${fence.authWorkId(uid)}`).get()).exists, false);
  const replay = await fence.handleAccountDeletionRequest({ data: { schemaVersion: 1, action: "resume", uid, ...credentials } }, deps);
  assert.equal(replay.kind, "account_deletion_account_deleted");
  assert.equal(replay.replayed, true);
});

test("emulator: Phase 2 reset protocol on real Firestore — rso1_ record, Reconciled 9 marker, four-target deletion, tombstone finalize, inspection", { skip: emulatorSkip }, async () => {
  const { db } = emulatorHandles();
  const { handleTaskPlanRequest, resetCanonicalId, resetRequestFingerprint, projectResetMarker } = require("../taskPlan");
  const uid = `emu-${randomUUID().slice(0, 8)}`;
  await db.doc(`users/${uid}`).set({ name: "R", taskGenerationEpoch: 1 });
  await db.doc(`users/${uid}/tasks/a`).set({ status: "Upcoming" });
  await db.doc(`users/${uid}/tasks/b`).set({ status: "Done" });
  await db.doc(`users/${uid}/notificationIntents/n`).set({ kind: "TASK_RESUME" });
  await db.doc(`users/${uid}/taskPlanOperations/pcs1_snap`).set({ kind: "CONFIRMATION_SNAPSHOT" });
  await db.doc(`users/${uid}/taskPlanOperations/op1_keep`).set({ kind: "TASK_OPERATION", state: "COMMITTED" });
  const aliasId = `rsa1_${randomUUID()}`;
  const call = (data) => handleTaskPlanRequest({ auth: { uid }, data }, () => db, new Date(), { resetProtocolMode: "compat" });
  const progress = await call({ action: "resetAllTasks", operationId: aliasId, reason: "retake_assessment", expectedTaskGenerationEpoch: 1 });
  const canonical = resetCanonicalId(uid, 2);
  assert.equal(progress.operationId, canonical);
  assert.equal(progress.state, "awaiting_local_reset");
  assert.deepEqual(progress.deletedCounts, { tasks: 2, notificationIntents: 1, taskDeadlineEvidence: 0, confirmationSnapshots: 1 });
  const root = (await db.doc(`users/${uid}`).get()).data();
  assert.equal(root.taskGenerationEpoch, 2);
  const record = (await db.doc(`users/${uid}/taskPlanOperations/${canonical}`).get()).data();
  assert.deepEqual(fence.TaskCanonicalV1(root.taskReset), fence.TaskCanonicalV1(projectResetMarker(record)));
  assert.equal((await db.doc(`users/${uid}/taskPlanOperations/op1_keep`).get()).exists, true);
  const inspection = await call({ action: "inspectCommittedOperation", family: "RESET", authority: { operationId: canonical }, requestAuthority: { requestFingerprint: resetRequestFingerprint(1) }, identityDigest: fence.sha256Hex(fence.TaskCanonicalV1({ kind: "reset", uid, expectedTaskGenerationEpoch: 1 })) });
  assert.equal(inspection.outcome, "pending");
  const final = await call({ action: "finalizeTaskReset", operationId: aliasId, reason: "retake_assessment", expectedTaskGenerationEpoch: 1 });
  assert.equal(final.kind, "reset_final");
  assert.equal("taskReset" in (await db.doc(`users/${uid}`).get()).data(), false);
  const committed = await call({ action: "inspectCommittedOperation", family: "RESET", authority: { operationId: canonical }, requestAuthority: { requestFingerprint: resetRequestFingerprint(1) }, identityDigest: fence.sha256Hex(fence.TaskCanonicalV1({ kind: "reset", uid, expectedTaskGenerationEpoch: 1 })) });
  assert.equal(committed.outcome, "committed");
  assert.deepEqual(committed.receipt, { ...final, replayed: true });
});

// ---------------------------------------------------------------------------
// S3 I1a — C6.1 fence integration: index.js inline writers, spawnTasks.js,
// dispositionTriggers.js committing transactions (briefs/S3_BRIEF.md)
// ---------------------------------------------------------------------------

// Provider boundaries for the handler-level families: the Anthropic SDK and nodemailer are replaced
// at the module boundary before index.js loads; Auth and Storage are stubbed on the admin namespace.
const Module = require("node:module");
const providerCalls = { anthropic: [], mail: [], sms: [] };
let anthropicScript = () => ({ content: [{ type: "text", text: "Hello" }], stop_reason: "end_turn", usage: { input_tokens: 1, output_tokens: 1 } });
// Every provider stub records the outbound-lease rows that exist in the active Firestore at send time.
const leaseSnapshot = () => [...(activeDb ? activeDb.__docs.entries() : [])].filter(([p]) => p.includes("/outboundLeases/")).map(([p, d]) => ({ path: p, ...d }));
class FakeAnthropic {
  constructor(options) { this.options = options; this.messages = { create: async (request) => { providerCalls.anthropic.push({ request, leases: leaseSnapshot() }); return anthropicScript(request); } }; }
}
const fakeMailer = { createTransport: () => ({ sendMail: async (message) => { providerCalls.mail.push({ message, leases: leaseSnapshot() }); return { accepted: [message.to] }; } }) };
const fakeTwilio = () => ({ messages: { create: async (message) => { providerCalls.sms.push({ message, leases: leaseSnapshot() }); return { sid: "SM1" }; } } });
let storageFiles = [];
const originalModuleLoad = Module._load;
Module._load = function loadWithProviderStubs(request, parent, isMain) {
  if (request === "@anthropic-ai/sdk") return FakeAnthropic;
  if (request === "nodemailer") return fakeMailer;
  if (request === "twilio") return fakeTwilio;
  return originalModuleLoad.call(this, request, parent, isMain);
};
process.env.ANTHROPIC_API_KEY = "test-key";
process.env.GMAIL_APP_PASSWORD = "test-password";
delete process.env.SUPPORT_NOTIFY_EMAIL; delete process.env.SUPPORT_NOTIFY_SMS; delete process.env.ADAM_NOTIFY_NUMBER;
Object.defineProperty(admin, "auth", { configurable: true, value: () => ({ getUser: async (uid) => ({ uid, email: "user@example.com" }) }) });
Object.defineProperty(admin, "storage", { configurable: true, value: () => ({ bucket: () => ({ getFiles: async () => [storageFiles] }) }) });

const indexExports = require("../index");
const { executeSpawn } = require("../spawnTasks");
const dispositionTriggers = require("../dispositionTriggers");

const USER_REQUEST = (uid, data) => ({ auth: { uid }, data });
const FENCED = { schemaVersion: 1, reason: "ACCOUNT_DELETION_FENCED" };

function markerOnly(db, uid) {
  return Object.keys(db.__docs.get(`users/${uid}`) || {});
}

test("index.js inline writers are root-fenced: requestConcierge, submitTaskFlow, and submitSupportMessage refuse a deleting account with zero writes and otherwise commit their records inside a transaction", async () => {
  const caps = [capability("uid-D", freshOperationId(), freshProofNonce())];
  for (const marker of [sweepingMarker(caps), guardingMarker(caps), dataDeletedMarker(caps), authGuardingMarker(caps), accountDeletedMarker(caps), { state: "junk" }]) {
    activeDb = fakeFirestore({ docs: { "users/uid-D": { name: "D", accountDeletion: marker }, "users/uid-D/supportChat/m1": { sender: "user", text: "hi" } } });
    const db = activeDb;
    const before = db.__writes.length;
    await expectDeletionError(() => indexExports.requestConcierge.run(USER_REQUEST("uid-D", { taskId: "BOX_RETURN" })), "failed-precondition", FENCED);
    await expectDeletionError(() => indexExports.submitTaskFlow.run(USER_REQUEST("uid-D", { taskId: "COMPARE_QUOTES", confirmedFields: {} })), "failed-precondition", FENCED);
    await expectDeletionError(() => indexExports.submitSupportMessage.run(USER_REQUEST("uid-D", { text: "help" })), "failed-precondition", FENCED);
    assert.equal(db.__writes.length, before, JSON.stringify(marker));
    assert.deepEqual(markerOnly(db, "uid-D"), ["name", "accountDeletion"]);
  }

  activeDb = fakeFirestore({ docs: { "users/uid-E": { name: "E" }, "users/uid-E/supportChat/m1": { sender: "user", text: "first" }, "users/uid-E/user_assessments/a1": { userName: "  Eve " } } });
  const db = activeDb;
  await indexExports.requestConcierge.run(USER_REQUEST("uid-E", { taskId: "BOX_RETURN", taskTitle: "Return boxes", userId: "forged" }));
  const concierge = [...db.__docs.entries()].filter(([p]) => p.startsWith("conciergeRequests/"));
  assert.equal(concierge.length, 1);
  assert.equal(concierge[0][1].userId, "uid-E");
  assert.equal(concierge[0][1].status, "pending");
  assert.ok(db.__reads.includes("users/uid-E"), "the committing transaction reads the owner root");

  await indexExports.submitTaskFlow.run(USER_REQUEST("uid-E", { taskId: "COMPARE_QUOTES", taskTitle: "Compare", confirmedFields: { choice: "first" } }));
  const flows = [...db.__docs.entries()].filter(([p]) => p.startsWith("taskFlowSubmissions/"));
  assert.equal(flows.length, 1);
  assert.equal(flows[0][1].userId, "uid-E");
  assert.deepEqual(flows[0][1].confirmedFields, { choice: "first" });

  const result = await indexExports.submitSupportMessage.run(USER_REQUEST("uid-E", { text: "  help me  ", taskContext: { userTaskId: "t", catalogTaskId: "c", title: "Title" } }));
  assert.deepEqual(result, { success: true });
  const ack = db.__docs.get("users/uid-E/supportChat/first-message-auto-acknowledgment");
  assert.equal(ack.sender, "support");
  assert.equal(ack.isAutoResponse, true);
  const thread = db.__docs.get("supportThreads/uid-E");
  assert.equal(thread.uid, "uid-E");
  assert.equal(thread.lastMessageText, "help me");
  assert.equal(thread.lastSender, "user");
  assert.equal(thread.userName, "Eve");
  assert.deepEqual(thread.taskContext, { userTaskId: "t", catalogTaskId: "c", title: "Title" });
  // A replayed first message keeps the existing acknowledgment byte-for-byte and still commits the thread.
  const ackBefore = JSON.stringify(ack);
  await indexExports.submitSupportMessage.run(USER_REQUEST("uid-E", { text: "again" }));
  assert.equal(JSON.stringify(db.__docs.get("users/uid-E/supportChat/first-message-auto-acknowledgment")), ackBefore);
  assert.equal(db.__docs.get("supportThreads/uid-E").lastMessageText, "again");
});

test("index.js submitSupportMessage awaits the support notification only after its committed record", async () => {
  const source = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
  const handler = source.slice(source.indexOf("exports.submitSupportMessage"), source.indexOf("exports.deleteAccount"));
  assert.equal(handler.includes("void notifySupport"), false, "the notification is no longer fire-and-forget");
  const commitIndex = handler.indexOf("runTransaction");
  const notifyIndex = handler.indexOf("await notifySupport");
  assert.ok(commitIndex > 0 && notifyIndex > commitIndex, "notifySupport is awaited after the committing transaction");
  assert.equal(/console\./.test(handler), false, "no console sink remains in submitSupportMessage");
  assert.equal(/error\.message|\.reason\.message/.test(handler), false, "no Error-derived value is logged");
});

test("spawnTasks refuses a deleting account inside its committing transaction with zero writes and otherwise creates its tasks", async () => {
  const row = { taskId: "FORWARD_MAIL", title: "Forward your mail", actionCategory: "notify", category: "admin", actionType: "workflow", taskType: "survey", conditions: {}, desc: "File the USPS change of address.", estHours: 1, tips: "Do it online.", urgencyPercentage: 90, whyNeeded: "Mail follows you." };
  const request = { token: "task-1-spawn", source: { kind: "conversation", taskId: "MOVERS" }, spawns: [{ taskId: "FORWARD_MAIL" }] };
  const caps = [capability("uid-F", freshOperationId(), freshProofNonce())];
  const fenced = fakeFirestore({ docs: { "taskCatalog/FORWARD_MAIL": row, "users/uid-F": { name: "F", accountDeletion: sweepingMarker(caps) }, "users/uid-F/identity/identity": {} } });
  await expectDeletionError(() => executeSpawn(fenced, "uid-F", request, new Date("2026-08-08T15:00:00Z")), "failed-precondition", FENCED);
  assert.equal(fenced.__writes.length, 0);

  const open = fakeFirestore({ docs: { "taskCatalog/FORWARD_MAIL": row, "users/uid-G": { name: "G" }, "users/uid-G/identity/identity": {} } });
  const result = await executeSpawn(open, "uid-G", request, new Date("2026-08-08T15:00:00Z"));
  assert.equal(result.created.length, 1);
  assert.equal([...open.__docs.keys()].filter((p) => p.startsWith("users/uid-G/tasks/")).length, 1);
  assert.equal(open.__docs.has("users/uid-G/spawnTokens/task-1-spawn"), true);
});

test("dispositionTriggers committing transactions are root-fenced: date wake, event consume and quarantine, and event-task wake refuse a deleting owner with zero writes", async () => {
  const caps = [capability("u1", freshOperationId(), freshProofNonce())];
  const NOW = new Date("2026-08-27T17:00:00.000Z");
  const dueTask = { status: "Snoozed", snoozedUntil: new Date("2026-08-27T16:00:00.000Z"), dispositionContract: { profile_version: 3, disposition: "DEFERRED", owner: "user:u1", next_action: "Wait", next_trigger: { kind: "date", at: new Date("2026-08-27T16:00:00.000Z"), payload: { basis: "institution_promised_date", source_evidence_id: "e1" } }, resume_destination: "flow:due", visible_status_copy: "Waiting" } };
  const pendingEvent = { event_id: "event-2", event_name: "institution.updated", canonical_key: "service/provider-1", source_version: 2, observed_at: new Date("2026-08-27T16:59:00.000Z"), source_evidence_id: "evidence-2", effect: "fire", payload: { nested: [true, 2, { note: "ready" }] }, processingState: "pending", processed: false };
  const malformedEvent = { processingState: "pending", processed: false, event_name: 7 };
  const eventTask = { status: "Snoozed", snoozedUntil: new Date("2026-09-01T00:00:00.000Z"), dispositionContract: { profile_version: 3, disposition: "DEFERRED", owner: "user:u1", next_action: "Wait", next_trigger: { kind: "event", event_name: "institution.updated", canonical_key: "service/provider-1", after_source_version: 1, payload: { source_evidence_id: "evidence-1" } }, resume_destination: "flow:event", visible_status_copy: "Waiting" } };
  const stateId = dispositionTriggers.canonicalEventStateId("institution.updated", "service/provider-1");
  const highWater = { event_name: "institution.updated", canonical_key: "service/provider-1", source_version: 2, effect: "fire", event_id: "event-2", observed_at: new Date("2026-08-27T16:59:00.000Z"), source_evidence_id: "evidence-2", payload: {}, fingerprint: "f", advancedAt: NOW };
  const docs = { "users/u1": { accountDeletion: sweepingMarker(caps) }, "users/u1/tasks/due": dueTask, "users/u1/events/event-2": pendingEvent, "users/u1/events/bad": malformedEvent, "users/u1/tasks/event-task": eventTask, [`users/u1/eventState/${stateId}`]: highWater };
  const db = fakeFirestore({ docs });
  await expectDeletionError(() => dispositionTriggers.wakeDateTaskInTransaction(db, db.doc("users/u1/tasks/due"), NOW), "failed-precondition", FENCED);
  await expectDeletionError(() => dispositionTriggers.consumeEventEnvelopeInTransaction(db, db.doc("users/u1/events/event-2"), NOW), "failed-precondition", FENCED);
  await expectDeletionError(() => dispositionTriggers.consumeEventEnvelopeInTransaction(db, db.doc("users/u1/events/bad"), NOW), "failed-precondition", FENCED);
  await expectDeletionError(() => dispositionTriggers.reconcileEventTaskInTransaction(db, db.doc("users/u1/tasks/event-task"), NOW), "failed-precondition", FENCED);
  assert.equal(db.__writes.length, 0);

  const openDocs = { ...docs, "users/u1": { name: "U" } };
  const open = fakeFirestore({ docs: openDocs });
  assert.equal(await dispositionTriggers.wakeDateTaskInTransaction(open, open.doc("users/u1/tasks/due"), NOW), true);
  assert.equal(await dispositionTriggers.consumeEventEnvelopeInTransaction(open, open.doc("users/u1/events/bad"), NOW), "quarantined");
  assert.equal(await dispositionTriggers.reconcileEventTaskInTransaction(open, open.doc("users/u1/tasks/event-task"), NOW), true);
  assert.equal(open.__docs.get("users/u1/tasks/due").status, "Upcoming");
  assert.equal(open.__docs.get("users/u1/tasks/event-task").status, "Upcoming");
  const source = fs.readFileSync(path.join(__dirname, "..", "dispositionTriggers.js"), "utf8");
  assert.equal(/console\./.test(source), false, "no console sink remains in dispositionTriggers.js");
});

// ---------------------------------------------------------------------------
// S3 I1b — C6.1 fence integration: entitlement.js, validateSubscription.js,
// submitCheckIn.js + submitCheckInCore.js
// ---------------------------------------------------------------------------

const { createValidationHandler } = require("../validateSubscription");
const { writeReviewAndAccountability } = require("../submitCheckInCore");

function httpResponse() {
  const res = { statusCode: null, body: null };
  res.status = (code) => { res.statusCode = code; return res; };
  res.json = (body) => { res.body = body; return res; };
  return res;
}

const SUBSCRIPTION_BODY = (overrides = {}) => ({
  userId: "user_123", productId: "peezy.plus.move", originalTransactionId: "original.123", transactionId: "transaction.123",
  purchaseDate: "2026-08-16T11:00:00.000Z", expirationDate: "2099-01-01T00:00:00.000Z", environment: "Sandbox", isUpgraded: false, ...overrides
}); // a later purchase date than the stored binding makes the decision "renewed" (it writes)

test("redeemGiftCode refuses a deleting account inside its committing transaction with zero writes and otherwise redeems", async () => {
  const caps = [capability("uid-H", freshOperationId(), freshProofNonce())];
  activeDb = fakeFirestore({ docs: { "users/uid-H": { name: "H", accountDeletion: accountDeletedMarker(caps) }, "giftCodes/PEEZY-ABCD-EFGH": { status: "unredeemed" } } });
  await expectDeletionError(() => indexExports.redeemGiftCode.run(USER_REQUEST("uid-H", { code: "peezy-abcd-efgh" })), "failed-precondition", FENCED);
  assert.equal(activeDb.__writes.length, 0);
  assert.equal(activeDb.__docs.get("giftCodes/PEEZY-ABCD-EFGH").status, "unredeemed");

  activeDb = fakeFirestore({ docs: { "users/uid-I": { name: "I" }, "giftCodes/PEEZY-ABCD-EFGH": { status: "unredeemed" } } });
  const result = await indexExports.redeemGiftCode.run(USER_REQUEST("uid-I", { code: "PEEZY-ABCD-EFGH" }));
  assert.equal(result.success, true);
  assert.equal(activeDb.__docs.get("giftCodes/PEEZY-ABCD-EFGH").status, "redeemed");
  assert.equal(activeDb.__docs.get("giftCodes/PEEZY-ABCD-EFGH").redeemedBy, "uid-I");
  assert.equal(activeDb.__docs.get("users/uid-I").subscription.productId, "peezy.plus.move");
  assert.equal(activeDb.__docs.get("users/uid-I").name, "I");
});

test("validateSubscription fences the prospective owner root and the binding's current owner root before its writes; a fenced root commits nothing", async () => {
  const caps = [capability("user_123", freshOperationId(), freshProofNonce())];
  const auth = { async getUser(uid) { if (uid === "gone_user") { const e = new Error("not found"); e.code = "auth/user-not-found"; throw e; } return { uid }; } };
  const handle = (db, body) => {
    const handler = createValidationHandler({ db, auth, now: () => new Date("2026-08-16T12:00:00.000Z"), serverTimestamp: () => new Date("2026-08-16T12:00:00.000Z"), logger: () => {} });
    const res = httpResponse();
    return handler({ method: "POST", body }, res).then(() => res);
  };

  // Prospective owner under deletion: the decision would write, so it is fenced and nothing commits.
  const fencedProspective = fakeFirestore({ docs: { "users/user_123": { accountDeletion: sweepingMarker(caps) } , "subscriptions/original.123": { userId: "user_123", productId: "peezy.plus.move", originalTransactionId: "original.123", transactionId: "transaction.100", purchaseDate: "2026-08-15T11:00:00.000Z", expirationDate: "2027-02-15T11:00:00.000Z", environment: "Sandbox", isUpgraded: false, status: "active" } } });
  const res1 = await handle(fencedProspective, SUBSCRIPTION_BODY());
  assert.equal(res1.statusCode, 500);
  assert.equal(fencedProspective.__writes.length, 0);
  assert.ok(fencedProspective.__reads.includes("users/user_123"));

  // Binding held by a verified-deleted Auth user whose root is the permanent tombstone: rebinding is a
  // write against that current owner root too, so it is fenced and nothing commits.
  const goneCaps = [capability("gone_user", freshOperationId(), freshProofNonce())];
  const fencedCurrent = fakeFirestore({ docs: { "users/user_123": { name: "U" }, "users/gone_user": { accountDeletion: accountDeletedMarker(goneCaps) }, "subscriptions/original.123": { userId: "gone_user", productId: "peezy.plus.move", originalTransactionId: "original.123", transactionId: "transaction.100", purchaseDate: "2026-08-15T11:00:00.000Z", expirationDate: "2027-02-15T11:00:00.000Z", environment: "Sandbox", isUpgraded: false, status: "active" } } });
  const res2 = await handle(fencedCurrent, SUBSCRIPTION_BODY());
  assert.equal(res2.statusCode, 500);
  assert.equal(fencedCurrent.__writes.length, 0);
  assert.ok(fencedCurrent.__reads.includes("users/gone_user"));

  // Open roots commit the binding and the user subscription.
  const open = fakeFirestore({ docs: { "users/user_123": { name: "U" }, "subscriptions/original.123": { userId: "user_123", productId: "peezy.plus.move", originalTransactionId: "original.123", transactionId: "transaction.100", purchaseDate: "2026-08-15T11:00:00.000Z", expirationDate: "2027-02-15T11:00:00.000Z", environment: "Sandbox", isUpgraded: false, status: "active" } } });
  const res3 = await handle(open, SUBSCRIPTION_BODY());
  assert.equal(res3.statusCode, 200, JSON.stringify(res3.body));
  assert.ok(open.__writes.length > 0);
  assert.equal(open.__docs.get("users/user_123").subscription.transactionId, "transaction.123");
});

test("check-in review transaction is root-fenced through submitCheckInCore and the submitCheckIn callable; a fenced owner commits nothing", async () => {
  const caps = [capability("uid-J", freshOperationId(), freshProofNonce())];
  const vendor = { vendorId: "v1", name: "Movers" };
  const review = { vendorId: "v1", userId: "uid-J", answers: { damage: "yes" }, flags: ["damage"], submittedAt: new Date("2026-09-01T00:00:00.000Z") };
  const fenced = fakeFirestore({ docs: { "users/uid-J": { accountDeletion: dataDeletedMarker(caps) }, "vendors/v1": { active: true, accountability: { strikes: [] } } } });
  await expectDeletionError(() => writeReviewAndAccountability(fenced, fenced.doc("vendorReviews/r1"), fenced.doc("estimateCalibration/c1"), vendor, review, { reviewId: "r1", userId: "uid-J" }, new Date("2026-09-01T00:00:00.000Z")), "failed-precondition", FENCED);
  assert.equal(fenced.__writes.length, 0);

  const open = fakeFirestore({ docs: { "users/uid-K": { name: "K" }, "vendors/v1": { active: true, accountability: { strikes: [] } } } });
  await writeReviewAndAccountability(open, open.doc("vendorReviews/r1"), null, vendor, { ...review, userId: "uid-K" }, null, new Date("2026-09-01T00:00:00.000Z"));
  assert.equal(open.__docs.get("vendorReviews/r1").userId, "uid-K");
  assert.ok(open.__docs.get("vendors/v1").accountability.strikes.length >= 1);

  activeDb = fakeFirestore({ docs: { "users/uid-J": { accountDeletion: dataDeletedMarker(caps) } } });
  await expectDeletionError(() => indexExports.submitCheckIn.run(USER_REQUEST("uid-J", { answers: { arrivedInWindow: true, crewWorkedSteadily: true, costMoreThanQuoted: false, damaged: true } })), "failed-precondition", FENCED);
  assert.equal(activeDb.__writes.length, 0);
});

// ---------------------------------------------------------------------------
// S3 I1c — C6.1 fence integration: peezyChat.js, researchTask.js, packageInventory.js,
// processInventory.js (process success, process error, onInventoryRoomWritten)
// ---------------------------------------------------------------------------

const AI_CONFIG = { researchModel: "claude-test", chatModel: "claude-test", inventoryModel: "claude-test", resolverModel: "claude-test", maxSearchesPerBrief: 2, briefMaxTokens: 1000 };
const MOVE_PASS = { productId: "peezy.plus.move", expirationDate: "2099-01-01T00:00:00.000Z", isActive: true };
const PACKING_CONFIG = Object.fromEntries(require("../seedCubeSheet").buildConfigDocuments().map((document) => [document.path, document.data]));

function providerDb(uid, marker, extra = {}) {
  const root = { name: "P", subscription: MOVE_PASS };
  if (marker) root.accountDeletion = marker;
  return fakeFirestore({ docs: { [`users/${uid}`]: root, "appConfig/ai": AI_CONFIG, ...PACKING_CONFIG, ...extra } });
}

test("peezyChat is root-fenced: a deleting account is refused at the user-message write with zero writes and zero provider calls; an open account commits both messages", async () => {
  const caps = [capability("uid-L", freshOperationId(), freshProofNonce())];
  providerCalls.anthropic.length = 0;
  activeDb = providerDb("uid-L", sweepingMarker(caps));
  await expectDeletionError(() => indexExports.peezyChat.run(USER_REQUEST("uid-L", { surface: "support", message: "hi" })), "failed-precondition", FENCED);
  assert.equal(activeDb.__writes.length, 0);
  assert.equal(providerCalls.anthropic.length, 0);

  activeDb = providerDb("uid-M", null);
  const reply = await indexExports.peezyChat.run(USER_REQUEST("uid-M", { surface: "support", message: "hi" }));
  assert.equal(reply.text, "Hello");
  const messages = [...activeDb.__docs.entries()].filter(([p]) => p.startsWith("users/uid-M/chats/support/messages/")).map(([, d]) => d.sender).sort();
  assert.deepEqual(messages, ["assistant", "user"]);
  assert.equal(providerCalls.anthropic.length, 1);
});

test("researchTask is root-fenced: a deleting account is refused at the generating write with zero writes; an open account commits generating and failed records through the fence", async () => {
  const caps = [capability("uid-N", freshOperationId(), freshProofNonce())];
  activeDb = providerDb("uid-N", guardingMarker(caps));
  await expectDeletionError(() => indexExports.researchTask.run(USER_REQUEST("uid-N", { taskId: "TASK_X", flowAnswers: { provider: ["Acme"] } })), "failed-precondition", FENCED);
  assert.equal(activeDb.__writes.length, 0);

  activeDb = providerDb("uid-O", null); // no catalog row: the context loader fails after the generating record commits
  await assert.rejects(() => indexExports.researchTask.run(USER_REQUEST("uid-O", { taskId: "TASK_X", flowAnswers: { provider: ["Acme"] } })), (e) => e.code === "not-found");
  const research = activeDb.__docs.get("users/uid-O/research/TASK_X");
  assert.equal(research.status, "failed");
  assert.equal(research.entityNameUsed, null);
  assert.ok(activeDb.__writes.length >= 2);
});

test("packageInventory is root-fenced: a deleting account is refused at the package record with zero writes; an open account commits the package", async () => {
  const caps = [capability("uid-P", freshOperationId(), freshProofNonce())];
  providerCalls.mail.length = 0;
  activeDb = providerDb("uid-P", dataDeletedMarker(caps), { "users/uid-P/user_assessments/a": { userName: "Pat" }, "users/uid-P/inventory/kitchen": { name: "Kitchen", items: [] } });
  await expectDeletionError(() => indexExports.packageInventory.run(USER_REQUEST("uid-P", {})), "failed-precondition", FENCED);
  assert.equal(activeDb.__writes.length, 0);

  providerCalls.mail.length = 0;
  activeDb = providerDb("uid-Q", null, { "users/uid-Q/user_assessments/a": { userName: "Quinn" }, "users/uid-Q/inventory/kitchen": { name: "Kitchen", items: [] } });
  const result = await indexExports.packageInventory.run(USER_REQUEST("uid-Q", {}));
  assert.equal(result.success, true);
  const packages = [...activeDb.__docs.entries()].filter(([p]) => p.startsWith("admin/inventoryPackages/packages/"));
  assert.equal(packages.length, 1);
  assert.equal(packages[0][1].userId, "uid-Q");
  assert.equal(providerCalls.mail.length, 1);
});

test("processInventory is root-fenced at process error and onInventoryRoomWritten: a deleting owner commits nothing; an open owner commits the error status and the packing aggregate", async () => {
  const caps = [capability("uid-R", freshOperationId(), freshProofNonce())];
  activeDb = providerDb("uid-R", sweepingMarker(caps), { "users/uid-R/inventorySessions/s1": { status: "processing" } });
  await expectDeletionError(() => indexExports.processInventory.run(USER_REQUEST("uid-R", { userId: "uid-R", sessionId: "s1", roomName: "Kitchen", frameCount: 0 })), "failed-precondition", FENCED);
  assert.equal(activeDb.__writes.length, 0);

  activeDb = providerDb("uid-S", null, { "users/uid-S/inventorySessions/s1": { status: "processing" } });
  await assert.rejects(() => indexExports.processInventory.run(USER_REQUEST("uid-S", { userId: "uid-S", sessionId: "s1", roomName: "Kitchen", frameCount: 0 })), (e) => e.code === "internal");
  assert.equal(activeDb.__docs.get("users/uid-S/inventorySessions/s1").status, "error");

  const roomEvent = (db, uid) => ({ params: { userId: uid, roomId: "kitchen" }, time: "2026-09-06T00:00:00.000Z", data: { after: { exists: true, ref: db.doc(`users/${uid}/inventory/kitchen`), data: () => ({ name: "Kitchen" }) } } });
  activeDb = providerDb("uid-R", sweepingMarker(caps), { "users/uid-R/inventory/kitchen": { name: "Kitchen" } });
  await expectDeletionError(() => indexExports.onInventoryRoomWritten.run(roomEvent(activeDb, "uid-R")), "failed-precondition", FENCED);
  assert.equal(activeDb.__writes.length, 0);

  activeDb = providerDb("uid-S", null, { "users/uid-S/inventory/kitchen": { name: "Kitchen" } });
  await indexExports.onInventoryRoomWritten.run(roomEvent(activeDb, "uid-S"));
  assert.ok([...activeDb.__docs.keys()].some((p) => p.startsWith("users/uid-S/packingAggregate/")), JSON.stringify([...activeDb.__docs.keys()]));

  const source = fs.readFileSync(path.join(__dirname, "..", "processInventory.js"), "utf8");
  const success = source.slice(source.indexOf("// 9. Critical room write"), source.indexOf("// 10. Best-effort cleanup"));
  assert.ok(success.includes("assertDeletionAbsent"), "the process-success write is fenced");
});

// ---------------------------------------------------------------------------
// S3 I2 — C6.2 outbound leases: support email/SMS, inventory email, check-in SMS,
// Anthropic messages.create in processInventory/researchTask/peezyChat
// ---------------------------------------------------------------------------

const { notifySupport } = require("../notifySupport");
const LEASE_KEYS_EXPECTED = ["path", "schema_version", "kind", "account_uid", "delivery_id", "channel", "state", "created_at", "expires_at"];

function assertOneLease(record, uid, channel) {
  const matching = record.leases.filter((lease) => lease.channel === channel);
  assert.equal(matching.length, 1, `exactly one live ${channel} lease at send time`);
  const lease = matching[0];
  assert.deepEqual(Object.keys(lease).sort(), [...LEASE_KEYS_EXPECTED].sort());
  assert.match(lease.path, new RegExp(`^users/${uid}/outboundLeases/uol1_[0-9a-f-]{36}$`));
  assert.equal(lease.schema_version, 1);
  assert.equal(lease.kind, "USER_OUTBOUND_LEASE");
  assert.equal(lease.account_uid, uid);
  assert.equal(lease.channel, channel);
  assert.equal(lease.state, "sending");
  assert.equal(fence.millis(lease.expires_at) - fence.millis(lease.created_at), 600_000);
}

function withEnv(values, fn) {
  const saved = Object.fromEntries(Object.keys(values).map((k) => [k, process.env[k]]));
  for (const [k, v] of Object.entries(values)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; }
  return Promise.resolve().then(fn).finally(() => { for (const [k, v] of Object.entries(saved)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; } });
}

const TWILIO_ENV = { TWILIO_ACCOUNT_SID: "AC1", TWILIO_AUTH_TOKEN: "tok", TWILIO_FROM_NUMBER: "+15550000000" };
const leaseDeps = (db) => ({ db, now: () => AdminTimestamp.fromMillis(Date.now()) });

test("support email and SMS run under one support_email and one support_sms lease keyed by the sender; a fenced sender sends nothing and every lease is released", async () => {
  await withEnv({ ...TWILIO_ENV, SUPPORT_NOTIFY_EMAIL: "founder@example.com", SUPPORT_NOTIFY_SMS: "+15551112222" }, async () => {
    providerCalls.mail.length = 0; providerCalls.sms.length = 0;
    activeDb = fakeFirestore({ docs: { "users/uid-T": { name: "T" } } });
    await indexExports.submitSupportMessage.run(USER_REQUEST("uid-T", { text: "help" }));
    assert.equal(providerCalls.mail.length, 1);
    assert.equal(providerCalls.sms.length, 1);
    assertOneLease(providerCalls.mail[0], "uid-T", "support_email");
    assertOneLease(providerCalls.sms[0], "uid-T", "support_sms");
    assert.equal(leaseSnapshot().length, 0, "leases are released after the send");

    providerCalls.mail.length = 0; providerCalls.sms.length = 0;
    const caps = [capability("uid-U", freshOperationId(), freshProofNonce())];
    activeDb = fakeFirestore({ docs: { "users/uid-U": { name: "U", accountDeletion: sweepingMarker(caps) } } });
    await notifySupport({ uid: "uid-U", textPreview: "x", taskTitle: "" }, leaseDeps(activeDb));
    assert.equal(providerCalls.mail.length, 0);
    assert.equal(providerCalls.sms.length, 0);
    assert.equal(activeDb.__writes.length, 0);
  });
});

test("inventory email runs under an inventory_email lease that precedes the package record; a fenced account sends nothing", async () => {
  providerCalls.mail.length = 0;
  activeDb = providerDb("uid-V", null, { "users/uid-V/user_assessments/a": { userName: "Val" }, "users/uid-V/inventory/kitchen": { name: "Kitchen", items: [] } });
  await indexExports.packageInventory.run(USER_REQUEST("uid-V", {}));
  assert.equal(providerCalls.mail.length, 1);
  assertOneLease(providerCalls.mail[0], "uid-V", "inventory_email");
  assert.equal(leaseSnapshot().length, 0);

  providerCalls.mail.length = 0;
  const caps = [capability("uid-W", freshOperationId(), freshProofNonce())];
  activeDb = providerDb("uid-W", dataDeletedMarker(caps), { "users/uid-W/user_assessments/a": { userName: "Wes" } });
  await expectDeletionError(() => indexExports.packageInventory.run(USER_REQUEST("uid-W", {})), "failed-precondition", FENCED);
  assert.equal(providerCalls.mail.length, 0);
  assert.equal(activeDb.__writes.length, 0);
});

test("check-in flags send one SMS per flag, each under its own checkin_sms lease; a fenced account sends nothing", async () => {
  await withEnv({ ...TWILIO_ENV, ADAM_NOTIFY_NUMBER: "+15553334444" }, async () => {
    providerCalls.sms.length = 0;
    activeDb = providerDb("uid-X", null);
    const answers = { arrivedInWindow: true, crewWorkedSteadily: true, costMoreThanQuoted: true, damaged: true };
    const result = await indexExports.submitCheckIn.run(USER_REQUEST("uid-X", { answers }));
    assert.equal(result.flags.length, 2);
    assert.equal(providerCalls.sms.length, 2);
    for (const call of providerCalls.sms) assertOneLease(call, "uid-X", "checkin_sms");
    assert.equal(leaseSnapshot().length, 0);

    providerCalls.sms.length = 0;
    const caps = [capability("uid-Y", freshOperationId(), freshProofNonce())];
    activeDb = providerDb("uid-Y", sweepingMarker(caps));
    await expectDeletionError(() => indexExports.submitCheckIn.run(USER_REQUEST("uid-Y", { answers })), "failed-precondition", FENCED);
    assert.equal(providerCalls.sms.length, 0);
  });
});

test("every Anthropic messages.create in peezyChat, researchTask, and processInventory runs under an anthropic lease keyed by the authenticated uid", async () => {
  providerCalls.anthropic.length = 0;
  activeDb = providerDb("uid-Z", null);
  await indexExports.peezyChat.run(USER_REQUEST("uid-Z", { surface: "support", message: "hi" }));
  assert.equal(providerCalls.anthropic.length, 1);
  assertOneLease(providerCalls.anthropic[0], "uid-Z", "anthropic");
  assert.equal(leaseSnapshot().length, 0);

  providerCalls.anthropic.length = 0;
  activeDb = providerDb("uid-Z", null, { "taskCatalog/TASK_R": { title: "Research me", researchEnabled: true, researchScope: "reasoning" } });
  const previousScript = anthropicScript;
  anthropicScript = () => ({ content: [{ type: "text", text: "not json" }], stop_reason: "end_turn", usage: {} });
  try {
    await assert.rejects(() => indexExports.researchTask.run(USER_REQUEST("uid-Z", { taskId: "TASK_R", flowAnswers: { provider: ["Acme"] } })));
    assert.ok(providerCalls.anthropic.length >= 1, "the research turn reached the provider");
    for (const call of providerCalls.anthropic) assertOneLease(call, "uid-Z", "anthropic");
    assert.equal(leaseSnapshot().length, 0);

    providerCalls.anthropic.length = 0;
    storageFiles = [{ name: "inventory/uid-Z/s1/frame_0.jpg", download: async () => [Buffer.from("jpeg")], delete: async () => {} }];
    activeDb = providerDb("uid-Z", null, { "users/uid-Z/inventorySessions/s1": { status: "processing" } });
    await assert.rejects(() => indexExports.processInventory.run(USER_REQUEST("uid-Z", { userId: "uid-Z", sessionId: "s1", roomName: "Kitchen", frameCount: 1 })));
    assert.equal(providerCalls.anthropic.length, 1);
    assertOneLease(providerCalls.anthropic[0], "uid-Z", "anthropic");
    assert.equal(leaseSnapshot().length, 0);
  } finally {
    anthropicScript = previousScript;
    storageFiles = [];
  }
});

test("C6.2 call graph: every provider send in the registry files sits inside withOutboundLease, and the registry names exactly the active callers", () => {
  const sendPattern = /\.messages\.create\(|\.sendMail\(|sendEachForMulticast\(/g;
  for (const entry of fence.USER_OUTBOUND_PROVIDERS_V1) {
    const file = entry.via || entry.file;
    if (file === "functions/index.js") continue;
    const source = fs.readFileSync(path.join(__dirname, "..", file.replace(/^functions\//, "")), "utf8");
    assert.ok(source.includes("withOutboundLease"), `${file} imports the lease helper`);
    // resolveProvider.js leases its search dynamically (the leased callback invokes the turn helper);
    // S2's provider-cache family proves that behaviorally. The lexical rule covers S3's seven sites.
    if (file === "functions/resolveProvider.js") continue;
    let match;
    let sends = 0;
    while ((match = sendPattern.exec(source)) !== null) {
      sends += 1;
      const before = source.slice(0, match.index);
      const leaseIndex = before.lastIndexOf("withOutboundLease(");
      const boundary = Math.max(before.lastIndexOf("\nasync function "), before.lastIndexOf("\nfunction "), before.lastIndexOf("\nconst "), before.lastIndexOf("\nexports."));
      assert.ok(leaseIndex > boundary, `${file}: send at ${match.index} is outside withOutboundLease`);
    }
    assert.ok(sends >= 1, `${file} has a provider send`);
  }
  const registryFiles = fence.USER_OUTBOUND_PROVIDERS_V1.map((e) => e.via || e.file).sort();
  assert.deepEqual([...new Set(registryFiles)], ["functions/notifySupport.js", "functions/packageInventory.js", "functions/peezyChat.js", "functions/processInventory.js", "functions/researchTask.js", "functions/resolveProvider.js", "functions/submitCheckIn.js", "functions/supportAdmin.js"]);
});

// ---------------------------------------------------------------------------
// S3 I3 — fence module: C3 global-scheduler cleanup step, C6.1 registry coverage,
// phase2LegacyCreateBlocker (Decision 4)
// ---------------------------------------------------------------------------

const { execFileSync } = require("node:child_process");
const QUARANTINE = "phase1System/dispositionTriggerState/quarantinedEvents";

test("global scheduler cleanup: 0/1/100/101 quarantine rows whose reread sourcePath names the UID are deleted inside the application sweep; other users' rows and out-of-range paths survive", async () => {
  for (const count of [0, 1, 100, 101]) {
    const clock = new FakeClock();
    const docs = { "users/uid-A": { name: "A" }, [`${QUARANTINE}/other`]: { sourcePath: "users/uid-B/events/e1" }, [`${QUARANTINE}/prefix`]: { sourcePath: "users/uid-AB/events/e1" }, [`${QUARANTINE}/tasks`]: { sourcePath: "users/uid-A/tasks/t1" }, "phase1System/dispositionTriggerState": { dateAfterPath: "x" } };
    for (let i = 0; i < count; i += 1) docs[`${QUARANTINE}/q${String(i).padStart(3, "0")}`] = { sourcePath: `users/uid-A/events/e${i}`, reason: "drift" };
    const db = fakeFirestore({ docs, clock });
    const deps = makeDeps({ db, clock, budget: { sweeps: 3 } });
    const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
    await expectDeletionError(() => call(deps, "begin", credentials), "unavailable", RETRY);
    await driveToGuarding(deps, credentials);
    const remaining = [...db.__docs.keys()].filter((p) => p.startsWith(`${QUARANTINE}/`)).sort();
    assert.deepEqual(remaining, [`${QUARANTINE}/other`, `${QUARANTINE}/prefix`, `${QUARANTINE}/tasks`], `count ${count}`);
    assert.ok(db.__docs.has("phase1System/dispositionTriggerState"));
    assert.ok(db.__reads.filter((r) => r.startsWith(`${QUARANTINE}/q`)).length >= count, "every nominated row is reread before deletion");
  }
});

test("global scheduler cleanup: a malformed in-range sourcePath is ACCOUNT_DELETION_GLOBAL_PATH_MALFORMED, the sweep blocks with the row intact, and guarding is never entered", async () => {
  for (const bad of ["users/uid-A/events/", "users/uid-A/events/e/extra", "users/uid-A/events//"]) {
    const clock = new FakeClock();
    const credentials = { operationId: freshOperationId(), proofNonce: freshProofNonce() };
    const db = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: sweepingMarker([capability(UID, credentials.operationId, credentials.proofNonce)]) }, [`${QUARANTINE}/good`]: { sourcePath: "users/uid-A/events/e1" }, [`${QUARANTINE}/bad`]: { sourcePath: bad } }, clock });
    const deps = makeDeps({ db, clock, budget: { sweeps: 3 } });
    for (let i = 0; i < 3; i += 1) await expectDeletionError(() => call(deps, "resume", credentials), "unavailable", RETRY);
    assert.ok(db.__docs.has(`${QUARANTINE}/bad`), bad);
    assert.equal(fence.validateAccountDeletionMarker(markerOf(db)).phase, "DELETING_SWEEPING", bad);
    assert.ok(deps.logs.some(([code]) => code === "ACCOUNT_DELETION_GLOBAL_PATH_MALFORMED"), bad);
  }
});

test("C6.1 registry coverage: every existing registered file calls the root fence, absent files are the two recorded pending entries, and no active export file writes user state outside the registry", () => {
  const PENDING = ["functions/taskDisposition.js", "functions/notificationIntents.js"]; // S6 / Reconciled 12
  const root = path.join(__dirname, "..");
  for (const file of Object.keys(fence.ACCOUNT_DELETION_FENCE_WRITERS_V1)) {
    const local = path.join(root, file.replace(/^functions\//, ""));
    if (!fs.existsSync(local)) { assert.ok(PENDING.includes(file), `${file} is absent and not recorded pending`); continue; }
    const source = fs.readFileSync(local, "utf8");
    assert.ok(/require\(["']\.\/accountDeletionFence["']\)/.test(source), `${file} requires the fence module`);
    const callsFence = (text) => text.includes("assertDeletionAbsent(") || text.includes('"ACCOUNT_DELETION_FENCED"') || text.includes("'ACCOUNT_DELETION_FENCED'");
    // A registered file whose committing transaction lives in another registered file (submitCheckIn.js →
    // submitCheckInCore.js) is covered through that shared child.
    const delegates = [...source.matchAll(/require\(["']\.\/([^"']+)["']\)/g)].map((m) => `functions/${m[1]}${m[1].endsWith(".js") ? "" : ".js"}`)
      .filter((f) => f in fence.ACCOUNT_DELETION_FENCE_WRITERS_V1 && fs.existsSync(path.join(root, f.replace(/^functions\//, ""))))
      .map((f) => fs.readFileSync(path.join(root, f.replace(/^functions\//, "")), "utf8"));
    assert.ok(callsFence(source) || delegates.some(callsFence), `${file} calls the root fence`);
  }
  // Active export graph: every file reachable from index.js that performs a Firestore write is a
  // registered writer, the fence core, or resolveProvider (whose only writes are fence-owned leases).
  const seen = new Set();
  const queue = ["index.js"];
  while (queue.length) {
    const file = queue.shift();
    if (seen.has(file)) continue;
    seen.add(file);
    const source = fs.readFileSync(path.join(root, file), "utf8");
    for (const match of source.matchAll(/require\(["']\.\/([^"']+)["']\)/g)) queue.push(match[1].endsWith(".js") || match[1].endsWith(".json") ? match[1] : `${match[1]}.js`);
  }
  const writePattern = /transaction\.(set|update|create|delete)\(|\b(ref|[A-Za-z]+Ref)\.(set|update|delete|create|add)\(|\.batch\(\)|recursiveDelete\(/;
  const allowed = new Set([...Object.keys(fence.ACCOUNT_DELETION_FENCE_WRITERS_V1).map((f) => f.replace(/^functions\//, "")), "accountDeletionFence.js"]);
  for (const file of [...seen].filter((f) => f.endsWith(".js"))) {
    const source = fs.readFileSync(path.join(root, file), "utf8");
    if (!writePattern.test(source)) continue;
    assert.ok(allowed.has(file), `${file} writes Firestore but is not a registered fence writer`);
  }
});

test("phase2LegacyCreateBlocker: accepts only beforeCreate for project peezy-1ecrdl with an empty tenant, always throws the exact permission-denied error, and index.js exports it only when PHASE2_LEGACY_CREATE_BLOCKER=armed", () => {
  const accepted = { eventType: "providers/cloud.auth/eventTypes/user.beforeCreate:password", resource: { service: "identitytoolkit.googleapis.com", name: "projects/peezy-1ecrdl" }, data: { uid: "u1" } };
  assert.equal(fence.classifyLegacyCreateBlockerEvent(accepted), "accepted");
  assert.equal(fence.classifyLegacyCreateBlockerEvent({ ...accepted, eventType: "providers/cloud.auth/eventTypes/user.beforeCreate" }), "accepted");
  assert.equal(fence.classifyLegacyCreateBlockerEvent({ ...accepted, eventType: "providers/cloud.auth/eventTypes/user.beforeSignIn:password" }), "event_type");
  assert.equal(fence.classifyLegacyCreateBlockerEvent({ ...accepted, resource: { service: "identitytoolkit.googleapis.com", name: "projects/other" } }), "project");
  assert.equal(fence.classifyLegacyCreateBlockerEvent({ ...accepted, resource: { service: "identitytoolkit.googleapis.com", name: "projects/peezy-1ecrdl/tenants/t1" } }), "tenant");
  assert.equal(fence.classifyLegacyCreateBlockerEvent({ ...accepted, data: { uid: "u1", tenantId: "t1" } }), "tenant");
  assert.equal(fence.classifyLegacyCreateBlockerEvent({ ...accepted, data: { uid: "u1", tenantId: null } }), "accepted");
  for (const event of [accepted, { ...accepted, eventType: "providers/cloud.auth/eventTypes/user.beforeSignIn" }, undefined]) {
    const logs = [];
    assert.throws(() => fence.phase2LegacyCreateBlocker(event, { log: (code, counts) => logs.push([code, counts]) }), (error) => {
      assert.equal(error.code, "permission-denied");
      assert.equal(error.message, "Account creation is temporarily unavailable.");
      assert.equal(error.details, undefined);
      return true;
    });
    assert.equal(logs.some(([code]) => code === "LEGACY_CREATE_BLOCKER_EVENT_REJECTED"), event !== accepted);
  }
  assert.equal(indexExports.phase2LegacyCreateBlocker, undefined, "unarmed: no export");
  const armed = execFileSync(process.execPath, ["-e", "const i = require('./index'); const e = i.phase2LegacyCreateBlocker; console.log(JSON.stringify({ type: typeof e, eventType: e && e.__endpoint && e.__endpoint.blockingTrigger && e.__endpoint.blockingTrigger.eventType, region: e && e.__endpoint && e.__endpoint.region }));"], { cwd: path.join(__dirname, ".."), env: { ...process.env, PHASE2_LEGACY_CREATE_BLOCKER: "armed" }, encoding: "utf8" });
  assert.deepEqual(JSON.parse(armed.trim().split("\n").at(-1)), { type: "function", eventType: "providers/cloud.auth/eventTypes/user.beforeCreate", region: ["us-central1"] });
  const unarmedOther = execFileSync(process.execPath, ["-e", "console.log(typeof require('./index').phase2LegacyCreateBlocker)"], { cwd: path.join(__dirname, ".."), env: { ...process.env, PHASE2_LEGACY_CREATE_BLOCKER: "yes" }, encoding: "utf8" });
  assert.equal(unarmedOther.trim().split("\n").at(-1), "undefined", "any value other than armed leaves the export absent");
});

// ---------------------------------------------------------------------------
// S3 I4 — C7: exact direct @google-cloud/firestore dependency and the regenerated lock
// ---------------------------------------------------------------------------

test("package.json pins @google-cloud/firestore 7.11.6 as an exact direct dependency under Node 24 and the lock resolves every C7 version unchanged", () => {
  const root = path.join(__dirname, "..");
  const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
  assert.equal(pkg.dependencies["@google-cloud/firestore"], "7.11.6", "exact, not a caret range");
  assert.deepEqual(pkg.engines, { node: "24" });
  const lock = JSON.parse(fs.readFileSync(path.join(root, "package-lock.json"), "utf8"));
  assert.equal(lock.lockfileVersion, 3);
  assert.equal(lock.packages[""].dependencies["@google-cloud/firestore"], "7.11.6");
  assert.deepEqual(lock.packages[""].engines, { node: "24" });
  const locked = (name) => lock.packages[`node_modules/${name}`].version;
  assert.deepEqual(
    { firestore: locked("@google-cloud/firestore"), storage: locked("@google-cloud/storage"), gax: locked("google-gax"), auth: locked("google-auth-library"), admin: locked("firebase-admin") },
    { firestore: "7.11.6", storage: "7.18.0", gax: "4.6.1", auth: "9.15.1", admin: "13.6.0" }
  );
  assert.equal(Object.keys(lock.packages).filter((p) => p.endsWith("node_modules/@google-cloud/firestore")).length, 1, "one deduplicated firestore package");
});

module.exports = { fakeFirestore, FakeClock, capability, sweepingMarker, guardingMarker, dataDeletedMarker, authGuardingMarker, accountDeletedMarker, freshOperationId, freshProofNonce, ts, UID, STARTED, GUARD_AFTER };

// ---------------------------------------------------------------------------
// S3 — shared fake Firestore query semantics (retro rule: extend once, before the next Node RED)
// ---------------------------------------------------------------------------

test("fake Firestore query semantics: collection groups, range/in/array-contains operators, multi-field order with cursors, and count", async () => {
  const db = fakeFirestore({ docs: {
    "users/a/tasks/t1": { status: "Snoozed", at: Timestamp.fromMillis(1000), tags: ["x"], trigger: { kind: "date" } },
    "users/a/tasks/t2": { status: "Snoozed", at: Timestamp.fromMillis(3000), tags: ["y"], trigger: { kind: "event" } },
    "users/b/tasks/t3": { status: "Upcoming", at: Timestamp.fromMillis(2000), tags: ["x", "y"], trigger: { kind: "date" } },
    "users/b/tasks/t4": { status: "Snoozed", tags: [], trigger: { kind: "date" } },
    "users/a/events/e1": { processingState: "pending" }
  } });
  const snoozed = await db.collectionGroup("tasks").where("status", "==", "Snoozed").orderBy("at", "asc").get();
  assert.deepEqual(snoozed.docs.map((d) => d.ref.path), ["users/a/tasks/t1", "users/a/tasks/t2"], "field order excludes rows lacking the field");
  const nestedRange = await db.collectionGroup("tasks").where("trigger.kind", "==", "date").where("at", "<=", Timestamp.fromMillis(2000)).orderBy("at").get();
  assert.deepEqual(nestedRange.docs.map((d) => d.id), ["t1", "t3"]);
  const after = await db.collectionGroup("tasks").orderBy("at", "asc").startAfter(snoozed.docs[0]).limit(1).get();
  assert.deepEqual(after.docs.map((d) => d.id), ["t3"], "snapshot cursor resumes by the row's order keys");
  const desc = await db.collectionGroup("tasks").orderBy("at", "desc").orderBy(FieldPath.documentId(), "asc").get();
  assert.deepEqual(desc.docs.map((d) => d.id), ["t2", "t3", "t1"]);
  const inQuery = await db.collectionGroup("tasks").where("status", "in", ["Upcoming", "Missing"]).get();
  assert.deepEqual(inQuery.docs.map((d) => d.id), ["t3"]);
  const contains = await db.collectionGroup("tasks").where("tags", "array-contains", "y").orderBy(FieldPath.documentId()).get();
  assert.deepEqual(contains.docs.map((d) => d.id), ["t2", "t3"]);
  const count = await db.collection("users/a/tasks").where("status", "==", "Snoozed").count().get();
  assert.equal(count.data().count, 2);
  const inTransaction = await db.runTransaction(async (transaction) => (await transaction.get(db.collectionGroup("tasks").where("status", "==", "Snoozed").count())).data().count);
  assert.equal(inTransaction, 3);
  const scalarCursor = await db.collection("users/a/tasks").orderBy(FieldPath.documentId()).startAfter("t1").get();
  assert.deepEqual(scalarCursor.docs.map((d) => d.id), ["t2"]);
});
