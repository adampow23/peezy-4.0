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

// ---------------------------------------------------------------------------
// In-memory Firestore (documents, transactions with read-version CAS, queries,
// recursiveDelete, listCollectionIds tuple). Timestamps are real Admin
// `Timestamp` values so production code sees the same types as the emulator.
// ---------------------------------------------------------------------------

function clone(value) {
  if (value === null || typeof value !== "object") return value;
  if (value instanceof Timestamp) return new Timestamp(value.seconds, value.nanoseconds);
  if (Array.isArray(value)) return value.map(clone);
  return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, clone(v)]));
}

function isDirectChild(path, collectionPath) {
  return path.startsWith(`${collectionPath}/`) && !path.slice(collectionPath.length + 1).includes("/");
}

function compareBytes(a, b) {
  const left = Buffer.from(a, "utf8");
  const right = Buffer.from(b, "utf8");
  return Buffer.compare(left, right);
}

function fakeFirestore({ docs: initial = {}, clock } = {}) {
  const docs = new Map(Object.entries(initial).map(([path, data]) => [path, clone(data)]));
  const versions = new Map();
  const writes = [];
  const reads = [];
  let versionCounter = 0;
  const bump = (path) => versions.set(path, ++versionCounter);
  for (const path of docs.keys()) bump(path);
  const now = () => (clock ? clock.now() : Timestamp.now());

  function docRef(path) {
    const segments = path.split("/");
    if (segments.length % 2 !== 0) throw new Error(`document path must have an even number of segments: ${path}`);
    const ref = {
      id: segments.at(-1),
      path,
      parent: null,
      collection: (name) => collectionRef(`${path}/${name}`),
      async get() { reads.push(path); return snapshot(ref); },
      async set(data, options) { commitOps([{ type: "set", path, data, options }]); },
      async update(data) { commitOps([{ type: "update", path, data }]); },
      async delete() { commitOps([{ type: "delete", path }]); },
      async create(data) { commitOps([{ type: "create", path, data }]); },
      isEqual: (other) => other && other.path === path
    };
    Object.defineProperty(ref, "parent", { get: () => collectionRef(segments.slice(0, -1).join("/")) });
    return ref;
  }

  function collectionRef(path, spec = {}) {
    const segments = path.split("/");
    if (segments.length % 2 !== 1) throw new Error(`collection path must have an odd number of segments: ${path}`);
    const q = {
      path,
      id: segments.at(-1),
      __query: spec,
      doc: (id) => docRef(`${path}/${id ?? randomUUID()}`),
      orderBy: (field, direction) => collectionRef(path, { ...spec, orderBy: String(field), direction: direction || "asc" }),
      startAfter: (value) => collectionRef(path, { ...spec, startAfter: value }),
      limit: (count) => collectionRef(path, { ...spec, limit: count }),
      where: (field, op, value) => collectionRef(path, { ...spec, where: [...(spec.where || []), [String(field), op, value]] }),
      async get() { reads.push(`${path}?`); return runQuery(q); },
      async listDocuments() {
        return [...docs.keys()].filter((p) => isDirectChild(p, path)).sort(compareBytes).map(docRef);
      }
    };
    return q;
  }

  function snapshot(ref, data = docs.get(ref.path)) {
    return {
      id: ref.id,
      ref,
      exists: data !== undefined,
      readTime: now(),
      data: () => (data === undefined ? undefined : clone(data)),
      get: (field) => data?.[field]
    };
  }

  function runQuery(q) {
    const spec = q.__query;
    let rows = [...docs.entries()].filter(([p]) => isDirectChild(p, q.path));
    for (const [field, op, value] of spec.where || []) {
      rows = rows.filter(([, data]) => {
        const actual = field === "__name__" ? undefined : data[field];
        if (op === "==") return actual === value;
        throw new Error(`fake query operator unsupported: ${op}`);
      });
    }
    if (spec.orderBy && spec.orderBy !== "__name__") throw new Error("fake orderBy supports only documentId()");
    rows.sort(([a], [b]) => compareBytes(a.split("/").at(-1), b.split("/").at(-1)));
    if (spec.direction === "desc") rows.reverse();
    if (spec.startAfter !== undefined && spec.startAfter !== "") {
      rows = rows.filter(([p]) => compareBytes(p.split("/").at(-1), spec.startAfter) > 0);
    }
    if (spec.limit !== undefined) rows = rows.slice(0, spec.limit);
    const list = rows.map(([p, data]) => snapshot(docRef(p), data));
    return { empty: list.length === 0, size: list.length, docs: list, readTime: now() };
  }

  function applyOps(ops, readVersions) {
    for (const [path, version] of readVersions || []) {
      if ((versions.get(path) || 0) !== version) {
        const error = new Error(`contention on ${path}`);
        error.code = 10;
        throw error;
      }
    }
    for (const op of ops) {
      if (op.type === "create" && docs.has(op.path)) { const e = new Error(`already exists: ${op.path}`); e.code = 6; throw e; }
      if (op.type === "update" && !docs.has(op.path)) { const e = new Error(`missing: ${op.path}`); e.code = 5; throw e; }
    }
    for (const op of ops) {
      if (op.type === "delete") docs.delete(op.path);
      else if (op.type === "update") docs.set(op.path, applyUpdate(docs.get(op.path), op.data));
      else if (op.type === "set" && op.options?.merge) docs.set(op.path, applyUpdate(docs.get(op.path) || {}, op.data));
      else docs.set(op.path, clone(op.data));
      bump(op.path);
      writes.push(op);
    }
  }

  function applyUpdate(existing, data) {
    const next = clone(existing || {});
    for (const [key, value] of Object.entries(data)) {
      const parts = key.split(".");
      let target = next;
      for (const part of parts.slice(0, -1)) {
        if (typeof target[part] !== "object" || target[part] === null) target[part] = {};
        target = target[part];
      }
      const last = parts.at(-1);
      if (value && value.__delete) delete target[last];
      else target[last] = clone(value);
    }
    return next;
  }

  function commitOps(ops) { applyOps(ops, []); }

  const db = {
    __docs: docs,
    __writes: writes,
    __reads: reads,
    collection: (path) => collectionRef(path),
    doc: (path) => docRef(path),
    async runTransaction(callback, { maxAttempts = 5 } = {}) {
      for (let attempt = 1; ; attempt += 1) {
        const ops = [];
        const readVersions = new Map();
        const transaction = {
          async get(target) {
            if (target.__query) {
              const result = runQuery(target);
              for (const row of result.docs) readVersions.set(row.ref.path, versions.get(row.ref.path) || 0);
              reads.push(`${target.path}?`);
              return result;
            }
            reads.push(target.path);
            readVersions.set(target.path, versions.get(target.path) || 0);
            return snapshot(target);
          },
          create: (ref, data) => { ops.push({ type: "create", path: ref.path, data: clone(data) }); return transaction; },
          set: (ref, data, options) => { ops.push({ type: "set", path: ref.path, data: clone(data), options }); return transaction; },
          update: (ref, data) => { ops.push({ type: "update", path: ref.path, data: clone(data) }); return transaction; },
          delete: (ref) => { ops.push({ type: "delete", path: ref.path }); return transaction; }
        };
        const result = await callback(transaction);
        try {
          applyOps(ops, readVersions);
          return result;
        } catch (error) {
          if (error.code === 10 && attempt < maxAttempts) continue;
          throw error;
        }
      }
    },
    async recursiveDelete(ref) {
      const prefix = `${ref.path}/`;
      const targets = [...docs.keys()].filter((p) => p === ref.path || p.startsWith(prefix));
      for (const p of targets) { docs.delete(p); bump(p); writes.push({ type: "delete", path: p, recursive: true }); }
    },
    listCollectionIdsTuple(parentPath) {
      const prefix = `${parentPath}/`;
      const ids = new Set();
      for (const p of docs.keys()) {
        if (!p.startsWith(prefix)) continue;
        ids.add(p.slice(prefix.length).split("/")[0]);
      }
      const sorted = [...ids].sort(compareBytes);
      return [sorted, null, { collectionIds: [...sorted], nextPageToken: "" }];
    }
  };
  return db;
}

class FakeClock {
  constructor(iso = "2026-09-06T12:00:00.000Z") { this.millis = Date.parse(iso); }
  now() { return Timestamp.fromMillis(this.millis); }
  advance(ms) { this.millis += ms; return this.now(); }
  iso() { return new Date(this.millis).toISOString(); }
}

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

module.exports = { fakeFirestore, FakeClock, capability, sweepingMarker, guardingMarker, dataDeletedMarker, authGuardingMarker, accountDeletedMarker, freshOperationId, freshProofNonce, ts, UID, STARTED, GUARD_AFTER };
