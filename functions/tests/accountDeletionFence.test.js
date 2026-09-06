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
  if (value.methodName === "FieldValue.delete") return value;
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
      if (value && typeof value === "object" && value.methodName === "FieldValue.delete") delete target[last];
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
    listCollectionIdsTuple(parentPath, request = { pageSize: 100 }) {
      const prefix = `${parentPath}/`;
      const ids = new Set();
      for (const p of docs.keys()) {
        if (!p.startsWith(prefix)) continue;
        ids.add(p.slice(prefix.length).split("/")[0]);
      }
      const sorted = [...ids].sort(compareBytes);
      const page = sorted.slice(0, request.pageSize);
      const token = sorted.length > page.length ? "more" : "";
      const nextRequest = token ? { parent: request.parent, pageSize: request.pageSize, pageToken: token } : null;
      return [page, nextRequest, { collectionIds: [...page], nextPageToken: token }];
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

test("enrollment: a second capability appends and resorts with every other marker byte preserved; a collision is invalid; the 65th is authenticatedOverflow with zero marker write; resume never enrolls", async () => {
  const clock = new FakeClock();
  const ids = Array.from({ length: 66 }, () => freshOperationId()).sort();
  const nonces = ids.map(() => freshProofNonce());
  const seeded = guardingMarker([capability(UID, ids[1], nonces[1])]);
  const db = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: seeded } }, clock });
  const deps = makeDeps({ db, clock });

  await expectDeletionError(() => call(deps, "begin", { operationId: ids[0], proofNonce: nonces[0] }), "unavailable", RETRY);
  const appended = markerOf(db);
  assert.deepEqual(appended.capabilities.map((c) => c.operationId), [ids[0], ids[1]]);
  assert.deepEqual({ ...appended, capabilities: null }, { ...seeded, capabilities: null });
  assert.deepEqual(Object.keys(appended), Object.keys(seeded));

  await expectDeletionError(() => call(deps, "discover", { operationId: ids[1], proofNonce: freshProofNonce() }), "permission-denied", CAP_INVALID);
  await expectDeletionError(() => call(deps, "resume", { operationId: ids[2], proofNonce: nonces[2], authUid: null }), "permission-denied", CAP_INVALID);
  assert.deepEqual(markerOf(db).capabilities.map((c) => c.operationId), [ids[0], ids[1]]);

  const full = guardingMarker(ids.slice(0, 64).map((id, i) => capability(UID, id, nonces[i])));
  const fullDb = fakeFirestore({ docs: { "users/uid-A": { accountDeletion: full } }, clock });
  const fullDeps = makeDeps({ db: fullDb, clock });
  await expectDeletionError(() => call(fullDeps, "begin", { operationId: ids[64], proofNonce: nonces[64] }), "unavailable", RETRY);
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

test("DELETING-guarding: every action throws the queued member and changes no byte beyond enrollment", async () => {
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
  assert.match(source, /const \{ handleAccountDeletionRequest, productionDependencies \} = require\('\.\/accountDeletionFence'\);/);
  assert.match(source, /exports\.deleteAccount = onCall\(\s*\{ region: 'us-central1', timeoutSeconds: 60, memory: '512MiB' \},\s*\(request\) => handleAccountDeletionRequest\(request, productionDependencies\(\)\)\s*\);/);
  assert.ok(source.includes("exports.changeTaskPlan = changeTaskPlan;"));
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

module.exports = { fakeFirestore, FakeClock, capability, sweepingMarker, guardingMarker, dataDeletedMarker, authGuardingMarker, accountDeletedMarker, freshOperationId, freshProofNonce, ts, UID, STARTED, GUARD_AFTER };
