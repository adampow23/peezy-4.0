"use strict";

/**
 * S3 I11 test support: an injected stand-in for the pinned public-v1 FirestoreClient over binding-shaped raw
 * Documents (valueType-discriminated Values, longs as strings, generated defaults on every response), with
 * read-write transactions, batchGetDocuments read times, and commit preconditions (exists / updateTime).
 */

const { Timestamp } = require("firebase-admin/firestore");
const { randomUUID } = require("node:crypto");

const ROOT = (projectId) => `projects/${projectId}/databases/(default)/documents`;

function ts(millis, nanos) {
  const seconds = Math.floor(millis / 1000);
  return { seconds: String(seconds), nanos: nanos === undefined ? (millis - seconds * 1000) * 1_000_000 : nanos };
}

function sameTime(a, b) {
  return a && b && String(a.seconds) === String(b.seconds) && Number(a.nanos ?? 0) === Number(b.nanos ?? 0);
}

/** Plain JS fixture data -> binding-shaped Values. */
function gapicValue(value, projectId = "demo-peezy-phase1") {
  if (value === null) return { valueType: "nullValue", nullValue: "NULL_VALUE" };
  if (typeof value === "boolean") return { valueType: "booleanValue", booleanValue: value };
  if (typeof value === "bigint") return { valueType: "integerValue", integerValue: value.toString() };
  if (typeof value === "number") {
    if (Number.isInteger(value) && Number.isSafeInteger(value) && !Object.is(value, -0)) return { valueType: "integerValue", integerValue: String(value) };
    return { valueType: "doubleValue", doubleValue: value };
  }
  if (typeof value === "string") return { valueType: "stringValue", stringValue: value };
  if (value instanceof Timestamp) return { valueType: "timestampValue", timestampValue: { seconds: String(value.seconds), nanos: value.nanoseconds } };
  if (value instanceof Date) return gapicValue(Timestamp.fromDate(value), projectId);
  if (Buffer.isBuffer(value)) return { valueType: "bytesValue", bytesValue: Buffer.from(value) };
  if (value && value.__geo) return { valueType: "geoPointValue", geoPointValue: { latitude: value.__geo[0], longitude: value.__geo[1] } };
  if (value && value.__ref) return { valueType: "referenceValue", referenceValue: `${ROOT(projectId)}/${value.__ref}` };
  if (value && value.__ts) return { valueType: "timestampValue", timestampValue: value.__ts };
  if (Array.isArray(value)) return { valueType: "arrayValue", arrayValue: { values: value.map((v) => gapicValue(v, projectId)) } };
  if (typeof value === "object") return { valueType: "mapValue", mapValue: { fields: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, gapicValue(v, projectId)])) } };
  throw new Error(`gapicValue: unsupported ${typeof value}`);
}

function gapicFields(data, projectId) {
  return Object.fromEntries(Object.entries(data).map(([k, v]) => [k, gapicValue(v, projectId)]));
}

function preconditionError(message) {
  const error = new Error(`FAILED_PRECONDITION: ${message}`);
  error.code = 9;
  return error;
}

class FakeV1Client {
  constructor({ projectId = "demo-peezy-phase1", documents = {}, scriptedResponses = null, onQuery = null, clock = null } = {}) {
    this.projectId = projectId;
    this.documents = new Map();
    this.clock = clock || { millis: Date.parse("2026-09-06T12:00:00.000Z"), advance(ms) { this.millis += ms; } };
    for (const [relative, data] of Object.entries(documents)) this.put(relative, data);
    this.scriptedResponses = scriptedResponses;
    this.onQuery = onQuery;
    this.queries = [];
    this.reads = [];
    this.commits = [];
    this.transactions = new Map();
    this.closed = false;
  }

  now() { return ts(this.clock.millis); }

  /** Stores a binding-shaped document from JS data (or raw fields when `__rawFields` is given). */
  put(relative, data, times = {}) {
    const name = `${ROOT(this.projectId)}/${relative}`;
    const createTime = times.createTime || ts(Date.parse("2026-09-01T00:00:00.000Z"));
    const updateTime = times.updateTime || ts(Date.parse("2026-09-02T00:00:00.000Z"));
    const fields = data && data.__rawFields ? data.__rawFields : gapicFields(data, this.projectId);
    this.documents.set(name, { name, fields, createTime, updateTime });
    return name;
  }

  remove(relative) { this.documents.delete(`${ROOT(this.projectId)}/${relative}`); }
  get(relative) { return this.documents.get(`${ROOT(this.projectId)}/${relative}`) || null; }

  async getProjectId() { return this.projectId; }
  async close() { this.closed = true; }

  response(overrides) {
    return { document: null, transaction: Buffer.alloc(0), readTime: ts(Date.now()), skippedResults: 0, explainMetrics: null, done: false, continuationSelector: null, ...overrides };
  }

  runQuery(request, options) {
    this.queries = [...this.queries, { request, options }];
    if (this.onQuery) this.onQuery(request, this.queries.length);
    const self = this;
    async function* generate() {
      if (self.scriptedResponses) { for (const r of self.scriptedResponses(request, self.queries.length)) yield r; return; }
      const query = request.structuredQuery;
      const limit = query.limit && query.limit.value;
      const from = query.from[0];
      const wanted = [...self.documents.values()].filter((d) => {
        const rel = d.name.slice(ROOT(self.projectId).length + 1).split("/");
        const inGroup = from.allDescendants ? rel.length % 2 === 0 && rel[rel.length - 2] === from.collectionId : rel.length === 2 && rel[0] === from.collectionId;
        const filter = query.where && query.where.fieldFilter;
        const matches = !filter || (d.fields[filter.field.fieldPath] && d.fields[filter.field.fieldPath].stringValue === filter.value.stringValue);
        return inGroup && matches;
      }).sort((a, b) => Buffer.compare(Buffer.from(a.name), Buffer.from(b.name)));
      const start = query.startAt && query.startAt.values && query.startAt.values[0] && query.startAt.values[0].referenceValue;
      const after = start ? wanted.filter((d) => Buffer.compare(Buffer.from(d.name), Buffer.from(start)) > 0) : wanted;
      const page = after.slice(0, limit);
      yield self.response({});
      for (let i = 0; i < page.length; i += 1) yield self.response({ document: page[i], done: i === page.length - 1 && after.length <= limit });
      if (page.length === 0) yield self.response({ done: true, readTime: null });
    }
    return generate();
  }

  async getDocument({ name }) {
    this.reads = [...this.reads, name];
    const document = this.documents.get(name);
    if (!document) { const error = new Error(`NOT_FOUND: ${name}`); error.code = 5; throw error; }
    return [document];
  }

  async beginTransaction() {
    const id = Buffer.from(randomUUID());
    this.transactions.set(id.toString("hex"), { readTime: this.now(), reads: new Map() });
    return [{ transaction: id }];
  }

  async rollback({ transaction }) { this.transactions.delete(Buffer.from(transaction).toString("hex")); return [{}]; }

  batchGetDocuments({ documents, transaction }) {
    const state = transaction ? this.transactions.get(Buffer.from(transaction).toString("hex")) : null;
    const readTime = state ? state.readTime : this.now();
    const self = this;
    async function* generate() {
      for (const name of documents) {
        self.reads = [...self.reads, name];
        const document = self.documents.get(name);
        if (state) state.reads.set(name, document ? document.updateTime : null);
        yield document ? { found: document, missing: null, transaction: Buffer.alloc(0), readTime } : { found: null, missing: name, transaction: Buffer.alloc(0), readTime };
      }
    }
    return generate();
  }

  /** Applies every write atomically after checking every precondition; bumps updateTime to a fresh commit time. */
  async commit({ writes, transaction }) {
    if (transaction) {
      const key = Buffer.from(transaction).toString("hex");
      if (!this.transactions.has(key)) throw preconditionError("unknown transaction");
      const state = this.transactions.get(key);
      for (const [name, seen] of state.reads) {
        const current = this.documents.get(name);
        if ((current ? current.updateTime : null) !== seen && !sameTime(current && current.updateTime, seen)) throw preconditionError(`contention on ${name}`);
      }
      this.transactions.delete(key);
    }
    for (const write of writes) {
      const name = write.update ? write.update.name : write.delete;
      const current = this.documents.get(name);
      const precondition = write.currentDocument;
      if (precondition) {
        if (precondition.exists === false && current) throw preconditionError(`${name} exists`);
        if (precondition.exists === true && !current) throw preconditionError(`${name} missing`);
        if (precondition.updateTime && (!current || !sameTime(current.updateTime, precondition.updateTime))) throw preconditionError(`${name} updateTime`);
      }
      if (write.delete && !current && !precondition) { /* deleting a missing document is a no-op */ }
    }
    this.clock.advance(1);
    const commitTime = this.now();
    const writeResults = [];
    for (const write of writes) {
      if (write.update) {
        const existing = this.documents.get(write.update.name);
        this.documents.set(write.update.name, { name: write.update.name, fields: write.update.fields, createTime: existing ? existing.createTime : commitTime, updateTime: commitTime });
        writeResults[writeResults.length] = { updateTime: commitTime, transformResults: [] };
      } else {
        this.documents.delete(write.delete);
        writeResults[writeResults.length] = { updateTime: null, transformResults: [] };
      }
    }
    this.commits = [...this.commits, { writes, commitTime }];
    return [{ writeResults, commitTime }];
  }
}

module.exports = { FakeV1Client, gapicValue, gapicFields, ts, ROOT, sameTime };
