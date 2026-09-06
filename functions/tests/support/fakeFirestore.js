"use strict";

// Shared in-memory Firestore for the S2 Node suites (documents, transactions with
// read-version CAS, queries, recursiveDelete, listCollectionIds tuple). Timestamps are
// real Admin `Timestamp` values so production code sees the same types as the emulator.
// Test support only: not a test file and not part of the §9.3 envelope.

const { randomUUID } = require("node:crypto");
const { Timestamp } = require("firebase-admin/firestore");

function clone(value) {
  if (value === null || typeof value !== "object") return value;
  if (value instanceof Timestamp) return new Timestamp(value.seconds, value.nanoseconds);
  if (value instanceof Date) return Timestamp.fromDate(value);
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
    if (spec.orderBy && spec.orderBy !== "__name__") {
      // S3: field ordering (Timestamp/Date/number/string), ties by document id.
      const key = (data) => { const v = data[spec.orderBy]; return v instanceof Timestamp ? v.toMillis() : v instanceof Date ? v.getTime() : v; };
      rows.sort(([pa, a], [pb, b]) => { const ka = key(a), kb = key(b); if (ka < kb) return -1; if (ka > kb) return 1; return compareBytes(pa.split("/").at(-1), pb.split("/").at(-1)); });
    } else {
      rows.sort(([a], [b]) => compareBytes(a.split("/").at(-1), b.split("/").at(-1)));
    }
    if (spec.direction === "desc") rows.reverse();
    if (spec.startAfter !== undefined && spec.startAfter !== "") {
      rows = rows.filter(([p]) => compareBytes(p.split("/").at(-1), spec.startAfter) > 0);
    }
    if (spec.limit !== undefined) rows = rows.slice(0, spec.limit);
    const list = rows.map(([p, data]) => snapshot(docRef(p), data));
    return { empty: list.length === 0, size: list.length, docs: list, readTime: now(), forEach: (fn) => list.forEach(fn) };
  }

  function resolveSentinels(value) {
    if (value === null || typeof value !== "object") return value;
    if (value instanceof Timestamp) return value;
    if (value.methodName === "FieldValue.serverTimestamp") return now();
    if (value.methodName === "FieldValue.delete") return value;
    if (Array.isArray(value)) return value.map(resolveSentinels);
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, resolveSentinels(v)]));
  }

  function applyOps(ops, readVersions) {
    for (const op of ops) if (op.data !== undefined) op.data = resolveSentinels(op.data);
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
      else if (op.type === "set" && op.options?.merge) docs.set(op.path, deepMerge(docs.get(op.path) || {}, op.data));
      else docs.set(op.path, clone(op.data));
      bump(op.path);
      writes.push(op);
    }
  }

  // Firestore set(..., {merge:true}) merges nested maps recursively; arrays and sentinels replace.
  function deepMerge(existing, data) {
    const next = clone(existing || {});
    for (const [key, value] of Object.entries(data)) {
      if (value && typeof value === "object" && value.methodName === "FieldValue.delete") { delete next[key]; continue; }
      const isMap = value !== null && typeof value === "object" && !Array.isArray(value) && !(value instanceof Timestamp) && value.methodName === undefined;
      const existingMap = next[key] !== null && typeof next[key] === "object" && !Array.isArray(next[key]) && !(next[key] instanceof Timestamp);
      next[key] = isMap && existingMap ? deepMerge(next[key], value) : clone(value);
    }
    return next;
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


module.exports = { fakeFirestore, FakeClock, clone, compareBytes };
