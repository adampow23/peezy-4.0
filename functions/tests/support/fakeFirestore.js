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
  // S3 I9d: recognized SDK instances (GeoPoint, DocumentReference, VectorValue, Buffer) and any other non-plain object are carried by reference, as a fixture, never flattened.
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) return value;
  return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, clone(v)]));
}

function isDirectChild(path, collectionPath) {
  return path.startsWith(`${collectionPath}/`) && !path.slice(collectionPath.length + 1).includes("/");
}

function setNested(target, field, value) {
  const parts = field.split(".");
  let cursor = target;
  for (const part of parts.slice(0, -1)) { if (cursor[part] === undefined || cursor[part] === null || typeof cursor[part] !== "object") cursor[part] = {}; cursor = cursor[part]; }
  cursor[parts.at(-1)] = value;
}

function nested(data, field) {
  return String(field).split(".").reduce((value, key) => (value === null || value === undefined ? undefined : value[key]), data);
}

function comparable(value) {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (value && typeof value === "object" && typeof value.toMillis === "function") return value.toMillis();
  return value;
}

function compareValues(a, b) {
  const x = comparable(a), y = comparable(b);
  if (typeof x === "string" && typeof y === "string") return compareBytes(x, y);
  if (x === y) return 0;
  return x < y ? -1 : 1;
}

function compareBytes(a, b) {
  const left = Buffer.from(a, "utf8");
  const right = Buffer.from(b, "utf8");
  return Buffer.compare(left, right);
}

function fakeFirestore({ docs: initial = {}, clock } = {}) {
  const docs = new Map(Object.entries(initial).map(([path, data]) => [path, clone(data)]));
  const versions = new Map();
  const updateTimes = new Map(); // S3 I9b: per-document updateTime, advanced by every committed write
  const writes = [];
  const reads = [];
  let versionCounter = 0;
  const now = () => (clock ? clock.now() : Timestamp.now());
  const bump = (path) => { versions.set(path, ++versionCounter); updateTimes.set(path, now()); };
  for (const path of docs.keys()) bump(path);

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
      /** Direct child collections of this document (S3 I12c residue proof). */
      async listCollections() {
        const ids = new Set();
        for (const p of docs.keys()) if (p.startsWith(`${path}/`)) { const rest = p.slice(path.length + 1).split("/"); if (rest.length >= 2) ids.add(rest[0]); }
        return [...ids].sort(compareBytes).map((id) => collectionRef(`${path}/${id}`));
      },
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
      orderBy: (field, direction) => collectionRef(path, { ...spec, orderBys: [...(spec.orderBys || []), { field: String(field), direction: direction || "asc" }] }),
      startAfter: (...values) => collectionRef(path, { ...spec, startAfter: values.length === 1 && values[0] && typeof values[0] === "object" && values[0].ref
        ? { __snapshot: true, ref: values[0].ref, __data: values[0].data ? values[0].data() : undefined }
        : { __values: values } }),
      count: () => ({ __count: true, __query: spec, path, async get() { const r = runQuery(q); reads.push(`${path}?count`); return { readTime: now(), data: () => ({ count: r.size }) }; } }),
      select: (...fields) => collectionRef(path, { ...spec, select: fields.map(String) }),
      limit: (count) => collectionRef(path, { ...spec, limit: count }),
      where: (field, op, value) => collectionRef(path, { ...spec, where: [...(spec.where || []), [String(field), op, value]] }),
      async get() { reads.push(`${path}?`); return runQuery(q); },
      async listDocuments() {
        return [...docs.keys()].filter((p) => isDirectChild(p, path)).sort(compareBytes).map(docRef);
      }
    };
    return q;
  }

  function snapshot(ref, data = docs.get(ref.path), mask) {
    // A select() mask returns only the named (possibly dotted) fields, as Firestore does.
    const masked = mask && data !== undefined ? mask.reduce((acc, field) => { const v = nested(data, field); if (v !== undefined) setNested(acc, field, v); return acc; }, {}) : data;
    return {
      id: ref.id,
      ref,
      exists: data !== undefined,
      readTime: now(),
      updateTime: data === undefined ? undefined : updateTimes.get(ref.path),
      data: () => (masked === undefined ? undefined : clone(masked)),
      get: (field) => nested(masked, field)
    };
  }

  function runQuery(q) {
    const spec = q.__query;
    let rows = [...docs.entries()].filter(([p]) => (spec.group ? p.split("/").length % 2 === 0 && p.split("/").at(-2) === spec.group : isDirectChild(p, q.path)));
    for (const [field, op, value] of spec.where || []) {
      rows = rows.filter(([p, data]) => {
        const actual = field === "__name__" ? p.split("/").at(-1) : nested(data, field);
        if (op === "==") return comparable(actual) === comparable(value);
        if (op === "!=") return actual !== undefined && comparable(actual) !== comparable(value);
        if (op === "in") return Array.isArray(value) && value.some((v) => comparable(v) === comparable(actual));
        if (op === "array-contains") return Array.isArray(actual) && actual.some((v) => comparable(v) === comparable(value));
        // S3: range operators over strings (byte order), numbers, Timestamps, and Dates; absent fields never match.
        if ([">", ">=", "<", "<="].includes(op)) {
          if (actual === undefined || actual === null) return false;
          const c = compareValues(actual, value);
          return op === ">" ? c > 0 : op === ">=" ? c >= 0 : op === "<" ? c < 0 : c <= 0;
        }
        throw new Error(`fake query operator unsupported: ${op}`);
      });
    }
    const orders = spec.orderBys && spec.orderBys.length ? spec.orderBys : [{ field: "__name__", direction: "asc" }];
    // Firestore orders by every orderBy in turn, then by document id; a field orderBy excludes rows lacking the field.
    if (orders.some((o) => o.field !== "__name__")) rows = rows.filter(([, data]) => orders.every((o) => o.field === "__name__" || nested(data, o.field) !== undefined));
    const keyOf = ([p, data], o) => (o.field === "__name__" ? p.split("/").at(-1) : nested(data, o.field));
    rows.sort((ra, rb) => {
      for (const o of orders) {
        const c = compareValues(keyOf(ra, o), keyOf(rb, o));
        if (c !== 0) return o.direction === "desc" ? -c : c;
      }
      return compareBytes(ra[0].split("/").at(-1), rb[0].split("/").at(-1));
    });
    if (spec.startAfter !== undefined) {
      // A document snapshot cursor uses the row's own order keys; a scalar cursor applies to the first orderBy.
      const cursorKeys = spec.startAfter && spec.startAfter.__snapshot
        ? orders.map((o) => keyOf([spec.startAfter.ref.path, spec.startAfter.__data || {}], o))
        : (spec.startAfter && spec.startAfter.__values ? spec.startAfter.__values : [spec.startAfter]).map((v) => (v && typeof v === "object" && typeof v.path === "string" && !(v instanceof Timestamp) ? v.path.split("/").at(-1) : v));
      rows = rows.filter((row) => {
        for (let i = 0; i < cursorKeys.length; i += 1) {
          const c = compareValues(keyOf(row, orders[i]), cursorKeys[i]);
          const dir = orders[i].direction === "desc" ? -1 : 1;
          if (c * dir > 0) return true;
          if (c * dir < 0) return false;
        }
        return false;
      });
    }
    if (spec.limit !== undefined) rows = rows.slice(0, spec.limit);
    const list = rows.map(([p, data]) => snapshot(docRef(p), data, spec.select));
    return { empty: list.length === 0, size: list.length, docs: list, readTime: now(), forEach: (fn) => list.forEach(fn) };
  }

  function resolveSentinels(value) {
    if (value === null || typeof value !== "object") return value;
    if (value instanceof Timestamp || value instanceof Date) return value;
    if (value.methodName === "FieldValue.serverTimestamp") return now();
    if (value.methodName === "FieldValue.delete") return value;
    if (Array.isArray(value)) return value.map(resolveSentinels);
    // S3 I9d: recognized SDK instances and other non-plain objects pass through untouched (a Date used to flatten into {})
    const prototype = Object.getPrototypeOf(value);
    if (prototype !== Object.prototype && prototype !== null) return value;
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, resolveSentinels(v)]));
  }

  let batchCounter = 0;
  function applyOps(ops, readVersions) {
    const batch = ++batchCounter; // S3 I9c: every commit (transaction or single write) tags its writes with one batch id
    for (const op of ops) { if (op.data !== undefined) op.data = resolveSentinels(op.data); op.batch = batch; }
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
    __updateTimes: updateTimes,
    collection: (path) => collectionRef(path),
    collectionGroup: (id) => collectionRef(`__group__/x/${id}`, { group: id }),
    doc: (path) => docRef(path),
    async runTransaction(callback, { maxAttempts = 5 } = {}) {
      for (let attempt = 1; ; attempt += 1) {
        const ops = [];
        const readVersions = new Map();
        const transaction = {
          async get(target) {
            if (target.__count) { const result = runQuery({ __query: target.__query, path: target.path }); reads.push(`${target.path}?count`); return { readTime: now(), data: () => ({ count: result.size }) }; }
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
