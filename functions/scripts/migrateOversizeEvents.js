"use strict";

/**
 * PHASE2_CONTRACT.md C9.2 — MIG-EVENT-V1: the offline legacy oversize-event migration (owner S3).
 *
 * Import is side-effect-free; the CLI runs only under `require.main === module`. Default mode is a read-only
 * two-pass audit over the pinned public-v1 FirestoreClient streaming runQuery. Write mode requires the literal
 * arming triple and every C9.2.2 predicate and is refused otherwise before the first write.
 */

const fs = require("node:fs");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { Timestamp } = require("firebase-admin/firestore");
const scheduler = require("../dispositionTriggers");
const fence = require("../accountDeletionFence");

const PINNED_FIRESTORE_VERSION = "7.11.6";
const PINNED_CLIENT_CONFIG_SHA256 = "2ed7a9046d766121b7f308b22384b1a6caaf7c6eaed5d9ea553556af3c987e41";
const PRODUCTION_PROJECT = "peezy-1ecrdl";
const PRODUCTION_DATABASE = "(default)";
const PAGE_SIZE = 100;
const CHUNK_PAYLOAD_MAX = 393216;
const MAX_CHUNKS = 49;
const MAX_ARCHIVE_BYTES = CHUNK_PAYLOAD_MAX * MAX_CHUNKS; // 19,267,584
const ARCHIVE_SLACK_BYTES = 8192;
/** The accepted rollout tuple: exact bytes of firestore.rules and the C7 index result; refrozen at S3 close-out. */
const ROLLOUT_TUPLE_V1 = Object.freeze({
  rulesSha256: "afeb8ae52a9ba616dfc605c63c050ecaf97f8f032d643be5bb5602a35f7d766b",
  indexesSha256: "a6de8daf701a75ff3db025ca244dbf2218432c5c1a06b0992cd88358250d88e8"
});
const KNOWN_RESPONSE_MEMBERS = Object.freeze(["document", "transaction", "readTime", "skippedResults", "explainMetrics", "done", "continuationSelector"]);
const KNOWN_ARGUMENTS = Object.freeze(["--apply", "--project-id", "--confirm-project", "--drain-evidence", "--emulator-audit"]);

class MigrationInvariant extends Error {
  constructor(code, detail) { super(detail ? `${code}: ${detail}` : code); this.code = code; this.detail = detail; }
}

function sha256Hex(bytes) { return createHash("sha256").update(bytes).digest("hex"); }
function first40(hex) { return hex.slice(0, 40); }
function utf8(text) { return Buffer.from(String(text), "utf8"); }
function checkedAdd(a, b) { const c = a + b; if (!Number.isSafeInteger(c)) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "arithmetic"); return c; }

// ---------------------------------------------------------------------------
// Arguments and arming (C9.2.2)
// ---------------------------------------------------------------------------

function parseArguments(argv) {
  const parsed = { apply: false, projectId: null, confirmProject: null, drainEvidence: null, emulatorAudit: false, unknown: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--apply") parsed.apply = true;
    else if (arg === "--emulator-audit") parsed.emulatorAudit = true;
    else if (arg === "--project-id" || arg === "--confirm-project" || arg === "--drain-evidence") {
      const value = argv[i + 1];
      if (typeof value !== "string" || value.startsWith("--")) { parsed.unknown = [...parsed.unknown, arg]; continue; }
      i += 1;
      if (arg === "--project-id") parsed.projectId = value;
      else if (arg === "--confirm-project") parsed.confirmProject = value;
      else parsed.drainEvidence = value;
    } else parsed.unknown = [...parsed.unknown, arg];
  }
  return parsed;
}

/** Every executable arming predicate; the first failing predicate names the refusal. */
function armingRefusal(parsed, deps, resolved) {
  if (parsed.unknown.length > 0) return "UNKNOWN_ARGUMENT";
  if (!parsed.apply) return "NOT_ARMED";
  if (parsed.projectId !== PRODUCTION_PROJECT) return "PROJECT_ID_MISMATCH";
  if (parsed.confirmProject !== PRODUCTION_PROJECT) return "CONFIRM_PROJECT_MISMATCH";
  if (deps.env.FIRESTORE_EMULATOR_HOST !== undefined) return "EMULATOR_HOST_PRESENT";
  if (!resolved || resolved.projectId !== PRODUCTION_PROJECT || resolved.databaseId !== PRODUCTION_DATABASE) return "RESOLVED_TARGET_MISMATCH";
  const tuple = rolloutTuple(deps);
  if (tuple.rulesSha256 !== ROLLOUT_TUPLE_V1.rulesSha256 || tuple.indexesSha256 !== ROLLOUT_TUPLE_V1.indexesSha256) return "ROLLOUT_TUPLE_MISMATCH";
  if (deps.pinnedConfigSha256() !== PINNED_CLIENT_CONFIG_SHA256 || deps.pinnedVersion() !== PINNED_FIRESTORE_VERSION) return "PIN_MISMATCH";
  return null;
}

function rolloutTuple(deps) {
  const root = deps.repositoryRoot;
  return {
    rulesSha256: sha256Hex(deps.readFile(path.join(root, "firestore.rules"))),
    indexesSha256: sha256Hex(deps.readFile(path.join(root, "firestore.indexes.json")))
  };
}

// ---------------------------------------------------------------------------
// Query and stream classification (C9.2.1)
// ---------------------------------------------------------------------------

function documentsParent(projectId) { return `projects/${projectId}/databases/${PRODUCTION_DATABASE}/documents`; }

function structuredQueryFor(protos, cursorName) {
  const object = {
    from: [{ collectionId: "events", allDescendants: true }],
    where: { fieldFilter: { field: { fieldPath: "processingState" }, op: "EQUAL", value: { stringValue: "pending" } } },
    orderBy: [{ field: { fieldPath: "__name__" }, direction: "ASCENDING" }],
    limit: { value: PAGE_SIZE }
  };
  if (cursorName !== null) object.startAt = { before: false, values: [{ referenceValue: cursorName }] };
  const query = protos.google.firestore.v1.StructuredQuery.fromObject(object);
  validateLimitWrapper(query.limit);
  return query;
}

function validateLimitWrapper(limit) {
  if (limit === null || limit === undefined || typeof limit !== "object") throw new MigrationInvariant("LIMIT_WRAPPER_INVALID", "absent");
  const value = limit.value;
  if (typeof value !== "number" || !Number.isSafeInteger(value)) throw new MigrationInvariant("LIMIT_WRAPPER_INVALID", "unwrapped");
  if (value <= 0 || value > 2147483647) throw new MigrationInvariant("LIMIT_WRAPPER_INVALID", "range");
  if (value !== PAGE_SIZE) throw new MigrationInvariant("LIMIT_WRAPPER_INVALID", "page");
}

function isTimestampLike(value) {
  if (value === null || typeof value !== "object") return false;
  const seconds = value.seconds;
  const text = typeof seconds === "object" && seconds !== null && typeof seconds.toString === "function" ? seconds.toString() : String(seconds);
  if (!/^-?\d+$/.test(text)) return false;
  const nanos = Number(value.nanos ?? 0);
  return Number.isInteger(nanos) && nanos >= 0 && nanos <= 999999999;
}

function timestampSeconds(value) {
  const seconds = value.seconds;
  const text = typeof seconds === "object" && seconds !== null && typeof seconds.toString === "function" ? seconds.toString() : String(seconds);
  if (!/^-?\d+$/.test(text)) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "timestamp seconds");
  return BigInt(text);
}

/**
 * Classifies one pinned-binding response. The binding surfaces generated defaults for scalars, so presence is read
 * from the message-typed members (document, readTime, explainMetrics), the transaction bytes, and `done === true`.
 */
function classifyResponse(response) {
  if (response === null || typeof response !== "object") throw new MigrationInvariant("STREAM_SHAPE_INVALID", "response");
  const unknown = Object.keys(response).filter((k) => !KNOWN_RESPONSE_MEMBERS.includes(k));
  if (unknown.length) throw new MigrationInvariant("STREAM_SHAPE_INVALID", `unknown member ${unknown[0]}`);
  if (response.transaction && response.transaction.length > 0) throw new MigrationInvariant("STREAM_SHAPE_INVALID", "transaction");
  if (response.skippedResults !== undefined && response.skippedResults !== null && Number(response.skippedResults) !== 0) throw new MigrationInvariant("STREAM_SHAPE_INVALID", "skippedResults");
  if (response.explainMetrics !== undefined && response.explainMetrics !== null) throw new MigrationInvariant("STREAM_SHAPE_INVALID", "explainMetrics");
  const done = response.done === true;
  const readTime = response.readTime === undefined || response.readTime === null ? null : response.readTime;
  if (readTime !== null && !isTimestampLike(readTime)) throw new MigrationInvariant("STREAM_SHAPE_INVALID", "readTime");
  const document = response.document === undefined || response.document === null ? null : response.document;
  if (document !== null) {
    if (typeof document.name !== "string" || !document.name || document.fields === null || typeof document.fields !== "object" || !isTimestampLike(document.createTime) || !isTimestampLike(document.updateTime)) throw new MigrationInvariant("STREAM_SHAPE_INVALID", "document");
    if (readTime === null) throw new MigrationInvariant("STREAM_SHAPE_INVALID", "document readTime");
    return { kind: "document", document, done };
  }
  if (done) return { kind: "done" };
  if (readTime === null) throw new MigrationInvariant("STREAM_SHAPE_INVALID", "empty member");
  return { kind: "progress" };
}

function inScopePath(name, projectId) {
  const prefix = `${documentsParent(projectId)}/`;
  if (!name.startsWith(prefix)) return null;
  const relative = name.slice(prefix.length);
  const parts = relative.split("/");
  if (parts.length !== 4 || parts[0] !== "users" || parts[2] !== "events" || !parts[1].trim() || !parts[3].trim() || parts[1].length === 0 || parts[3].length === 0) return null;
  return relative;
}

/**
 * One complete enumeration pass: pages of exactly 100 document responses, a reference cursor after every full page,
 * strictly ascending names, at most one terminal marker; every document is handed to `onDocument` sequentially.
 */
async function enumeratePending(client, protos, projectId, callOptions, onDocument) {
  let cursor = null;
  let total = 0;
  for (;;) {
    const query = structuredQueryFor(protos, cursor);
    const stream = client.runQuery({ parent: documentsParent(projectId), structuredQuery: query }, callOptions);
    let pageCount = 0;
    let lastName = cursor;
    let terminal = false;
    let progressSeen = false;
    for await (const response of stream) {
      if (terminal) throw new MigrationInvariant("STREAM_SHAPE_INVALID", "after terminal");
      const classified = classifyResponse(response);
      if (classified.kind === "progress") { progressSeen = true; continue; }
      if (classified.kind === "done") { terminal = true; continue; }
      const name = classified.document.name;
      if (lastName !== null && Buffer.compare(utf8(name), utf8(lastName)) <= 0) throw new MigrationInvariant("STREAM_SHAPE_INVALID", "name order");
      lastName = name;
      pageCount += 1;
      total += 1;
      await onDocument(classified.document);
      if (classified.done) terminal = true;
    }
    if (pageCount === 0 && cursor === null && !progressSeen && !terminal) throw new MigrationInvariant("STREAM_SHAPE_INVALID", "empty query without progress");
    if (pageCount < PAGE_SIZE) return total;
    cursor = lastName;
  }
}

// ---------------------------------------------------------------------------
// Pinned-binding Value tree → public-v1 JSON Values (for the frozen storage equations); no decoding of producer data
// ---------------------------------------------------------------------------

function rfc3339(value) {
  const seconds = timestampSeconds(value);
  const nanos = Number(value.nanos ?? 0);
  if (!Number.isInteger(nanos) || nanos < 0 || nanos > 999999999) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "timestamp nanos");
  const millis = Number(seconds) * 1000;
  const base = new Date(millis).toISOString().replace(/\.\d{3}Z$/, "");
  return `${base}.${String(nanos).padStart(9, "0")}Z`;
}

function toJsonValue(value) {
  if (value === null || typeof value !== "object") throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "value");
  const kind = value.valueType;
  switch (kind) {
    case "nullValue": return { nullValue: null };
    case "booleanValue": return { booleanValue: value.booleanValue === true };
    case "integerValue": { const text = typeof value.integerValue === "object" && value.integerValue !== null ? value.integerValue.toString() : String(value.integerValue); if (!/^-?\d+$/.test(text)) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "integer"); return { integerValue: text }; }
    case "doubleValue": { const d = value.doubleValue; if (typeof d !== "number") throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "double"); return { doubleValue: Number.isNaN(d) ? "NaN" : d === Infinity ? "Infinity" : d === -Infinity ? "-Infinity" : d }; }
    case "timestampValue": return { timestampValue: rfc3339(value.timestampValue) };
    case "stringValue": if (typeof value.stringValue !== "string") throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "string"); return { stringValue: value.stringValue };
    case "bytesValue": return { bytesValue: Buffer.from(value.bytesValue || []).toString("base64") };
    case "referenceValue": if (typeof value.referenceValue !== "string") throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "reference"); return { referenceValue: value.referenceValue };
    case "geoPointValue": return { geoPointValue: { latitude: value.geoPointValue.latitude, longitude: value.geoPointValue.longitude } };
    case "arrayValue": return { arrayValue: { values: ((value.arrayValue && value.arrayValue.values) || []).map(toJsonValue) } };
    case "mapValue": return { mapValue: { fields: Object.fromEntries(Object.entries((value.mapValue && value.mapValue.fields) || {}).map(([k, v]) => [k, toJsonValue(v)])) } };
    default: throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", `unknown oneof ${String(kind)}`);
  }
}

function toJsonFields(fields) {
  return Object.fromEntries(Object.entries(fields || {}).map(([k, v]) => [k, toJsonValue(v)]));
}

// ---------------------------------------------------------------------------
// FirestoreDocumentArchiveV1 (C9.2.4)
// ---------------------------------------------------------------------------

const TAG = Object.freeze({ NULL: 0x00, FALSE: 0x01, TRUE: 0x02, INTEGER: 0x03, DOUBLE: 0x04, NAN: 0x05, POS_INF: 0x06, NEG_INF: 0x07, TIMESTAMP: 0x08, STRING: 0x09, BYTES: 0x0a, REFERENCE: 0x0b, GEOPOINT: 0x0c, ARRAY: 0x0d, MAP: 0x0e });

function u32(n) { if (!Number.isSafeInteger(n) || n < 0 || n > 0xffffffff) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "u32"); const b = Buffer.alloc(4); b.writeUInt32BE(n, 0); return b; }
function i64(big) { if (typeof big !== "bigint" || big < -(2n ** 63n) || big > 2n ** 63n - 1n) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "i64"); const b = Buffer.alloc(8); b.writeBigInt64BE(big, 0); return b; }
function f64(value) { const b = Buffer.alloc(8); b.writeDoubleBE(value, 0); return b; }
function lp(bytes) { return Buffer.concat([u32(bytes.length), bytes]); }
function encodeTimestamp(value) {
  const nanos = Number(value.nanos ?? 0);
  if (!Number.isInteger(nanos) || nanos < 0 || nanos > 999999999) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "timestamp nanos");
  return Buffer.concat([i64(timestampSeconds(value)), u32(nanos)]);
}

/** Encodes one raw Value; `acc` accumulates K (map keys), V (value nodes), F (reference bytes) with checked arithmetic. */
function encodeValue(value, acc) {
  acc.V = checkedAdd(acc.V, 1);
  const kind = value && value.valueType;
  switch (kind) {
    case "nullValue": return Buffer.from([TAG.NULL]);
    case "booleanValue": return Buffer.from([value.booleanValue === true ? TAG.TRUE : TAG.FALSE]);
    case "integerValue": { const text = typeof value.integerValue === "object" && value.integerValue !== null ? value.integerValue.toString() : String(value.integerValue); if (!/^-?\d+$/.test(text)) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "integer"); return Buffer.concat([Buffer.from([TAG.INTEGER]), i64(BigInt(text))]); }
    case "doubleValue": { const d = value.doubleValue; if (typeof d !== "number") throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "double"); if (Number.isNaN(d)) return Buffer.from([TAG.NAN]); if (d === Infinity) return Buffer.from([TAG.POS_INF]); if (d === -Infinity) return Buffer.from([TAG.NEG_INF]); return Buffer.concat([Buffer.from([TAG.DOUBLE]), f64(d)]); }
    case "timestampValue": return Buffer.concat([Buffer.from([TAG.TIMESTAMP]), encodeTimestamp(value.timestampValue)]);
    case "stringValue": if (typeof value.stringValue !== "string") throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "string"); return Buffer.concat([Buffer.from([TAG.STRING]), lp(utf8(value.stringValue))]);
    case "bytesValue": return Buffer.concat([Buffer.from([TAG.BYTES]), lp(Buffer.from(value.bytesValue || []))]);
    case "referenceValue": { if (typeof value.referenceValue !== "string" || !value.referenceValue) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "reference"); const bytes = utf8(value.referenceValue); acc.F = checkedAdd(acc.F, bytes.length); return Buffer.concat([Buffer.from([TAG.REFERENCE]), lp(bytes)]); }
    case "geoPointValue": { const g = value.geoPointValue || {}; if (typeof g.latitude !== "number" || typeof g.longitude !== "number") throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "geopoint"); return Buffer.concat([Buffer.from([TAG.GEOPOINT]), f64(g.latitude), f64(g.longitude)]); }
    case "arrayValue": { const values = (value.arrayValue && value.arrayValue.values) || []; return Buffer.concat([Buffer.from([TAG.ARRAY]), u32(values.length), ...values.map((v) => encodeValue(v, acc))]); }
    case "mapValue": return Buffer.concat([Buffer.from([TAG.MAP]), encodeMap((value.mapValue && value.mapValue.fields) || {}, acc)]);
    default: throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", `unknown oneof ${String(kind)}`);
  }
}

function encodeMap(fields, acc) {
  const keys = Object.keys(fields).map((k) => ({ k, bytes: utf8(k) })).sort((a, b) => Buffer.compare(a.bytes, b.bytes));
  acc.K = checkedAdd(acc.K, keys.length);
  return Buffer.concat([u32(keys.length), ...keys.map(({ k, bytes }) => Buffer.concat([lp(bytes), encodeValue(fields[k], acc)]))]);
}

/** Encodes a complete raw Document; returns bytes, digest, and the K/V/F accounting. */
function encodeArchive(document) {
  if (!document || typeof document.name !== "string" || !document.name) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "name");
  const acc = { K: 0, V: 0, F: 0 };
  const bytes = Buffer.concat([
    Buffer.from("PZFDA", "ascii"), Buffer.from([1]),
    lp(utf8(document.name)),
    encodeTimestamp(document.createTime), encodeTimestamp(document.updateTime),
    encodeMap(document.fields || {}, acc)
  ]);
  return { bytes, archiveDigest: sha256Hex(bytes), K: acc.K, V: acc.V, F: acc.F, N: bytes.length };
}

class Reader {
  constructor(bytes) { this.bytes = bytes; this.at = 0; }
  take(n) { if (this.at + n > this.bytes.length) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "truncated"); const out = this.bytes.subarray(this.at, this.at + n); this.at += n; return out; }
  u8() { return this.take(1)[0]; }
  u32() { return this.take(4).readUInt32BE(0); }
  i64() { return this.take(8).readBigInt64BE(0); }
  f64() { return this.take(8).readDoubleBE(0); }
  lp() { return this.take(this.u32()); }
  timestamp() { return { seconds: this.i64().toString(), nanos: this.u32() }; }
}

function decodeValue(reader) {
  const tag = reader.u8();
  switch (tag) {
    case TAG.NULL: return { valueType: "nullValue", nullValue: "NULL_VALUE" };
    case TAG.FALSE: return { valueType: "booleanValue", booleanValue: false };
    case TAG.TRUE: return { valueType: "booleanValue", booleanValue: true };
    case TAG.INTEGER: return { valueType: "integerValue", integerValue: reader.i64().toString() };
    case TAG.DOUBLE: return { valueType: "doubleValue", doubleValue: reader.f64() };
    case TAG.NAN: return { valueType: "doubleValue", doubleValue: NaN };
    case TAG.POS_INF: return { valueType: "doubleValue", doubleValue: Infinity };
    case TAG.NEG_INF: return { valueType: "doubleValue", doubleValue: -Infinity };
    case TAG.TIMESTAMP: return { valueType: "timestampValue", timestampValue: reader.timestamp() };
    case TAG.STRING: { const bytes = reader.lp(); const text = bytes.toString("utf8"); if (!utf8(text).equals(bytes)) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "utf8"); return { valueType: "stringValue", stringValue: text }; }
    case TAG.BYTES: return { valueType: "bytesValue", bytesValue: Buffer.from(reader.lp()) };
    case TAG.REFERENCE: { const bytes = reader.lp(); const text = bytes.toString("utf8"); if (!utf8(text).equals(bytes) || !text) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "reference"); return { valueType: "referenceValue", referenceValue: text }; }
    case TAG.GEOPOINT: return { valueType: "geoPointValue", geoPointValue: { latitude: reader.f64(), longitude: reader.f64() } };
    case TAG.ARRAY: { const count = reader.u32(); const values = []; for (let i = 0; i < count; i += 1) values[values.length] = decodeValue(reader); return { valueType: "arrayValue", arrayValue: { values } }; }
    case TAG.MAP: return { valueType: "mapValue", mapValue: { fields: decodeMap(reader) } };
    default: throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", `tag ${tag}`);
  }
}

function decodeMap(reader) {
  const count = reader.u32();
  const fields = {};
  let previous = null;
  for (let i = 0; i < count; i += 1) {
    const keyBytes = Buffer.from(reader.lp());
    if (previous !== null && Buffer.compare(previous, keyBytes) >= 0) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "key order");
    previous = keyBytes;
    const key = keyBytes.toString("utf8");
    if (!utf8(key).equals(keyBytes)) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "key utf8");
    fields[key] = decodeValue(reader);
  }
  return fields;
}

function decodeArchive(bytes) {
  const reader = new Reader(bytes);
  if (!reader.take(5).equals(Buffer.from("PZFDA", "ascii")) || reader.u8() !== 1) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "magic");
  const nameBytes = reader.lp();
  const name = nameBytes.toString("utf8");
  if (!utf8(name).equals(nameBytes)) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "name utf8");
  const createTime = reader.timestamp();
  const updateTime = reader.timestamp();
  const fields = decodeMap(reader);
  if (reader.at !== bytes.length) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "residue");
  return { name, createTime, updateTime, fields };
}

function archiveIdFor(sourcePath, updateTime, archiveDigest) {
  const seconds = Number(timestampSeconds(updateTime));
  return `qev2_${first40(fence.sha256Hex(fence.TaskCanonicalV1({ domain: "event_archive.v1", source_path: sourcePath, source_update_time: { seconds, nanoseconds: Number(updateTime.nanos ?? 0) }, archive_digest: archiveDigest })))}`;
}

/** C9.2.5 chunk gate and C9.2.4 bound, computed with checked arithmetic; systemic codes never mutate. */
function archivePlan(document, sourcePath, storageBytes) {
  const encoded = encodeArchive(document);
  const bound = checkedAdd(checkedAdd(checkedAdd(checkedAdd(storageBytes, 4 * encoded.K), 13 * encoded.V), encoded.F), ARCHIVE_SLACK_BYTES);
  if (encoded.N > bound) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "bound");
  if (encoded.N <= 0 || encoded.N > MAX_ARCHIVE_BYTES) throw new MigrationInvariant("ARCHIVE_CHUNK_CAP_EXCEEDED", String(encoded.N));
  const chunkCount = Math.ceil(encoded.N / CHUNK_PAYLOAD_MAX);
  if (!Number.isSafeInteger(chunkCount) || chunkCount < 1 || chunkCount > MAX_CHUNKS) throw new MigrationInvariant("ARCHIVE_CHUNK_CAP_EXCEEDED", String(encoded.N));
  const archiveId = archiveIdFor(sourcePath, document.updateTime, encoded.archiveDigest);
  return { ...encoded, bound, chunkCount, archiveId };
}

// ---------------------------------------------------------------------------
// Classification and the two-pass audit
// ---------------------------------------------------------------------------

async function rereadDocument(client, name, callOptions) {
  try {
    const [document] = await client.getDocument({ name }, callOptions);
    return document || null;
  } catch (error) {
    if (error && (error.code === 5 || error.code === "NOT_FOUND")) return null;
    throw error;
  }
}

/** Classifies one enumerated document after the mandatory reread; returns an enum outcome and digests only. */
async function classifyDocument(client, callOptions, projectId, enumerated, now) {
  const sourcePath = inScopePath(enumerated.name, projectId);
  if (sourcePath === null) return { outcome: "OUT_OF_SCOPE_SOURCE", pathDigest: sha256Hex(utf8(enumerated.name)) };
  const document = await rereadDocument(client, enumerated.name, callOptions);
  if (document === null) return { outcome: "DRIFT_MISSING", sourcePath };
  const jsonFields = toJsonFields(document.fields);
  const state = jsonFields.processingState;
  if (!state || state.stringValue !== "pending") return { outcome: "DRIFT_NOT_PENDING", sourcePath };
  const updateTime = new Timestamp(Number(timestampSeconds(document.updateTime)), Number(document.updateTime.nanos ?? 0));
  const envelope = scheduler.phase0EnvelopeRaw(sourcePath, jsonFields, now, updateTime);
  if (envelope.admitted) return { outcome: "ADMITTED", sourcePath, baseBytes: envelope.baseBytes };
  const plan = archivePlan(document, sourcePath, envelope.baseBytes);
  return { outcome: "SOURCE_TOO_LARGE", sourcePath, baseBytes: envelope.baseBytes, prospectiveMaxBytes: envelope.prospectiveMaxBytes, archiveId: plan.archiveId, archiveDigest: plan.archiveDigest, totalBytes: plan.N, chunkCount: plan.chunkCount, updateTime: { seconds: Number(timestampSeconds(document.updateTime)), nanos: Number(document.updateTime.nanos ?? 0) } };
}

async function runPass(client, protos, projectId, callOptions, now) {
  const pass = { pendingCount: 0, admitted: 0, failing: [], outOfScope: [], drifted: [], systemic: null };
  try {
    pass.pendingCount = await enumeratePending(client, protos, projectId, callOptions, async (document) => {
      const result = await classifyDocument(client, callOptions, projectId, document, now);
      if (result.outcome === "ADMITTED") pass.admitted += 1;
      else if (result.outcome === "SOURCE_TOO_LARGE") pass.failing = [...pass.failing, result];
      else if (result.outcome === "OUT_OF_SCOPE_SOURCE") pass.outOfScope = [...pass.outOfScope, result];
      else pass.drifted = [...pass.drifted, result];
    });
    pass.complete = true;
  } catch (error) {
    if (error instanceof MigrationInvariant) { pass.complete = false; pass.systemic = { code: error.code, detail: error.detail }; }
    else throw error;
  }
  return pass;
}

function samePathSet(a, b) {
  const x = a.map((r) => r.sourcePath).sort();
  const y = b.map((r) => r.sourcePath).sort();
  return x.length === y.length && x.every((p, i) => p === y[i]);
}

/** Two consecutive complete passes with zero drift, the same pending count, and the same failing/out-of-scope sets. */
async function runAudit(client, protos, projectId, callOptions, now) {
  const first = await runPass(client, protos, projectId, callOptions, now);
  if (!first.complete) return { passes: [first], stable: false, preShipCriterion: false };
  const second = await runPass(client, protos, projectId, callOptions, now);
  const stable = first.complete && second.complete && first.drifted.length === 0 && second.drifted.length === 0
    && first.pendingCount === second.pendingCount && samePathSet(first.failing, second.failing) && samePathSet(first.outOfScope, second.outOfScope);
  const preShipCriterion = stable && second.failing.length === 0 && second.outOfScope.length === 0;
  return { passes: [first, second], stable, preShipCriterion };
}

// ---------------------------------------------------------------------------
// Report and entry point
// ---------------------------------------------------------------------------

function reportOf(parsed, deps, resolved, audit, refusal) {
  const tuple = rolloutTuple(deps);
  return {
    schemaVersion: 1, kind: "MIG_EVENT_V1_RUN_REPORT",
    mode: parsed.apply ? "apply" : "audit", command: (deps.argv || []).join(" "),
    resolvedProject: resolved ? resolved.projectId : null, resolvedDatabase: resolved ? resolved.databaseId : null,
    firestoreVersion: deps.pinnedVersion(), clientConfigSha256: deps.pinnedConfigSha256(),
    tuple, acceptedTuple: ROLLOUT_TUPLE_V1,
    drainEvidence: parsed.drainEvidence ? { path: parsed.drainEvidence, sha256: sha256Hex(deps.readFile(parsed.drainEvidence)) } : null,
    refusal,
    audit: audit ? {
      stable: audit.stable, preShipCriterion: audit.preShipCriterion,
      passes: audit.passes.map((p) => ({ complete: p.complete, pendingCount: p.pendingCount, admitted: p.admitted, failing: p.failing.map((f) => ({ sourcePath: f.sourcePath, archiveId: f.archiveId, archiveDigest: f.archiveDigest, totalBytes: f.totalBytes, chunkCount: f.chunkCount, baseBytes: f.baseBytes })), outOfScope: p.outOfScope.map((o) => ({ pathDigest: o.pathDigest })), drifted: p.drifted.map((d) => ({ sourcePath: d.sourcePath, outcome: d.outcome })), systemic: p.systemic }))
    } : null
  };
}

function defaultDependencies() {
  const firestore = require("@google-cloud/firestore");
  const protos = require("@google-cloud/firestore/build/protos/firestore_v1_proto_api.js");
  return {
    argv: process.argv.slice(2),
    env: process.env,
    now: () => Timestamp.now(),
    readFile: (file) => fs.readFileSync(file),
    repositoryRoot: path.resolve(__dirname, "../.."),
    pinnedVersion: () => require("@google-cloud/firestore/package.json").version,
    pinnedConfigSha256: () => sha256Hex(fs.readFileSync(path.join(path.dirname(require.resolve("@google-cloud/firestore")), "v1/firestore_client_config.json"))),
    protos,
    createClient: ({ projectId, emulatorHost }) => {
      if (emulatorHost) {
        const [host, port] = String(emulatorHost).split(":");
        const gax = require("google-gax");
        return { client: new firestore.v1.FirestoreClient({ projectId, servicePath: host, port: Number(port), sslCreds: gax.grpc.credentials.createInsecure() }), callOptions: { otherArgs: { headers: { Authorization: "Bearer owner" } } } };
      }
      return { client: new firestore.v1.FirestoreClient({ projectId }), callOptions: {} };
    },
    resolveTarget: async (client, projectId) => ({ projectId: await client.getProjectId(), databaseId: PRODUCTION_DATABASE, requested: projectId })
  };
}

/** The import-safe entry: returns { exitCode, report }. Write mode is refused before any write unless every predicate passes. */
async function run(argv, overrides = {}) {
  const deps = { ...defaultDependencies(), argv, ...overrides };
  const parsed = parseArguments(argv);
  if (parsed.unknown.length > 0) return { exitCode: 2, report: reportOf(parsed, deps, null, null, "UNKNOWN_ARGUMENT") };
  const projectId = parsed.projectId || (deps.env.FIRESTORE_EMULATOR_HOST ? (deps.env.GCLOUD_PROJECT || "demo-peezy-phase1") : PRODUCTION_PROJECT);
  const emulatorHost = deps.env.FIRESTORE_EMULATOR_HOST;
  if (parsed.apply && emulatorHost !== undefined) return { exitCode: 3, report: reportOf(parsed, deps, null, null, "EMULATOR_HOST_PRESENT") };
  const { client, callOptions } = deps.createClient({ projectId, emulatorHost });
  try {
    const resolved = await deps.resolveTarget(client, projectId);
    const now = deps.now();
    if (parsed.apply) {
      const refusal = armingRefusal(parsed, deps, resolved);
      if (refusal !== null) return { exitCode: 3, report: reportOf(parsed, deps, resolved, null, refusal) };
      // I11b: fenced lease acquisition and archive writes follow the confirmed audit; until then apply refuses at the write seam.
      const audit = await runAudit(client, deps.protos, projectId, callOptions, now);
      return { exitCode: 4, report: reportOf(parsed, deps, resolved, audit, "WRITE_SEAM_NOT_IMPLEMENTED") };
    }
    const audit = await runAudit(client, deps.protos, projectId, callOptions, now);
    return { exitCode: audit.stable ? 0 : 1, report: reportOf(parsed, deps, resolved, audit, null) };
  } finally {
    if (client && typeof client.close === "function") await client.close().catch(() => {});
  }
}

async function main() {
  const { exitCode, report } = await run(process.argv.slice(2));
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  process.exitCode = exitCode;
}

if (require.main === module) main().catch((error) => { process.stderr.write(`${error && error.code ? error.code : "MIGRATION_FAILED"}\n`); process.exitCode = 1; });

module.exports = {
  MigrationInvariant, PINNED_FIRESTORE_VERSION, PINNED_CLIENT_CONFIG_SHA256, PRODUCTION_PROJECT, PAGE_SIZE, CHUNK_PAYLOAD_MAX, MAX_CHUNKS, MAX_ARCHIVE_BYTES, ROLLOUT_TUPLE_V1, KNOWN_ARGUMENTS,
  parseArguments, armingRefusal, rolloutTuple, structuredQueryFor, validateLimitWrapper, classifyResponse, inScopePath, enumeratePending,
  toJsonValue, toJsonFields, rfc3339, encodeArchive, decodeArchive, encodeValue, archiveIdFor, archivePlan, classifyDocument, runPass, runAudit, reportOf, run, documentsParent
};
