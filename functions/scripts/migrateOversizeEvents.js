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
  rulesSha256: "0d2717756505dca107fd3fffbac1e869e43380326400633c1c63fab5804777e9",
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

/**
 * C9.2.1 two-pass: the second full uncursored pass runs only after a complete zero-failing first pass (zero failing,
 * zero out-of-scope, zero drift); stable = both complete passes agree on the pending count with zero drift; the
 * C9.2.9 criterion additionally needs zero failing/out-of-scope rows in the confirmation pass.
 */
async function runAudit(client, protos, projectId, callOptions, now) {
  const first = await runPass(client, protos, projectId, callOptions, now);
  if (!first.complete || first.failing.length > 0 || first.outOfScope.length > 0 || first.drifted.length > 0) return { passes: [first], stable: false, preShipCriterion: false };
  const second = await runPass(client, protos, projectId, callOptions, now);
  const stable = first.complete && second.complete && first.drifted.length === 0 && second.drifted.length === 0
    && first.pendingCount === second.pendingCount && samePathSet(first.failing, second.failing) && samePathSet(first.outOfScope, second.outOfScope);
  const preShipCriterion = stable && second.failing.length === 0 && second.outOfScope.length === 0;
  return { passes: [first, second], stable, preShipCriterion };
}

// ---------------------------------------------------------------------------
// C9.2.3 migration lease (cross-fence) over public-v1 transactions
// ---------------------------------------------------------------------------

const MIGRATION_LEASE_PATH = "phase1System/dispositionTriggerState/migrationLeases/legacyOversizeMigrationV1";
const SCHEDULER_LEASE_PATH = "phase1System/dispositionTriggerLease";
const QUARANTINE_PATH = "phase1System/dispositionTriggerState/quarantinedEvents";
const LEASE_SECONDS = 300;
const SCHEDULER_GRACE_MS = 60000;
const BUDGET = Object.freeze({ chunkCommit: 524288, manifestCommit: 65536, leaseFence: 4096, canonicalRecord: 16384, stubOrQuarantine: 32768, terminal: 8523776 });
const STUB_MESSAGE = "Stored event exceeded the Phase 2 event-processing size limit.";

function fullName(projectId, relative) { return `${documentsParent(projectId)}/${relative}`; }
function tsFromMillis(millis) { return { seconds: String(Math.floor(millis / 1000)), nanos: (millis - Math.floor(millis / 1000) * 1000) * 1000000 }; }
function tsMillis(value) { return Number(timestampSeconds(value)) * 1000 + Math.floor(Number(value.nanos ?? 0) / 1000000); }
function tsPlusSeconds(value, seconds) { return { seconds: (timestampSeconds(value) + BigInt(seconds)).toString(), nanos: Number(value.nanos ?? 0) }; }
function tsEqual(a, b) { return a && b && timestampSeconds(a) === timestampSeconds(b) && Number(a.nanos ?? 0) === Number(b.nanos ?? 0); }

/** Scheduler-owned records (lease, manifest, chunk, stub, quarantine) written by this script: plain JS -> binding Values. */
function ownValue(value) {
  if (value === null) return { valueType: "nullValue", nullValue: "NULL_VALUE" };
  if (typeof value === "boolean") return { valueType: "booleanValue", booleanValue: value };
  if (typeof value === "number") { if (!Number.isSafeInteger(value)) throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "own number"); return { valueType: "integerValue", integerValue: String(value) }; }
  if (typeof value === "string") return { valueType: "stringValue", stringValue: value };
  if (Buffer.isBuffer(value)) return { valueType: "bytesValue", bytesValue: value };
  if (value && value.__ts) return { valueType: "timestampValue", timestampValue: value.__ts };
  if (value && typeof value === "object" && !Array.isArray(value)) return { valueType: "mapValue", mapValue: { fields: ownFields(value) } };
  throw new MigrationInvariant("ARCHIVE_CODEC_INVARIANT", "own value");
}
function ownFields(map) { return Object.fromEntries(Object.entries(map).map(([k, v]) => [k, ownValue(v)])); }
function T(value) { return { __ts: value }; }

/** Transactional read of literal names: returns { readTime, found: Map(name -> document|null), transaction }. */
async function transactionalRead(client, projectId, names, callOptions) {
  const database = `projects/${projectId}/databases/${PRODUCTION_DATABASE}`;
  const [begun] = await client.beginTransaction({ database, options: { readWrite: {} } }, callOptions);
  const transaction = begun.transaction;
  const found = new Map();
  let readTime = null;
  try {
    for await (const response of client.batchGetDocuments({ database, documents: names, transaction }, callOptions)) {
      if (response.readTime && !isTimestampLike(response.readTime)) throw new MigrationInvariant("STREAM_SHAPE_INVALID", "batchGet readTime");
      if (readTime === null && response.readTime) readTime = response.readTime;
      if (response.found) found.set(response.found.name, response.found);
      else if (response.missing) found.set(response.missing, null);
      else throw new MigrationInvariant("STREAM_SHAPE_INVALID", "batchGet member");
    }
    if (readTime === null) throw new MigrationInvariant("STREAM_SHAPE_INVALID", "batchGet without readTime");
    for (const name of names) if (!found.has(name)) throw new MigrationInvariant("STREAM_SHAPE_INVALID", `batchGet missing ${name}`);
  } catch (error) {
    await client.rollback({ database, transaction }, callOptions).catch(() => {});
    throw error;
  }
  return { readTime, found, transaction, database };
}

async function commitWrites(client, read, writes, callOptions) {
  if (writes.length > 4) throw new MigrationInvariant("MIGRATION_WRITE_INVARIANT", "fifth write");
  const [result] = await client.commit({ database: read.database, writes, transaction: read.transaction }, callOptions);
  return result;
}

function isLegacySchedulerLease(fields) {
  const keys = Object.keys(fields || {}).sort().join(",");
  return keys === "acquiredAt,expiresAt,runId" && fields.runId.valueType === "stringValue" && fields.acquiredAt.valueType === "timestampValue" && fields.expiresAt.valueType === "timestampValue";
}

const SCHEDULER_OWNER_TOKEN_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const SCHEDULER_LEASE_SECONDS = 270;

function isV2SchedulerLease(fields) {
  const keys = Object.keys(fields || {}).sort().join(",");
  if (keys !== "expiresAt,ownerToken,runOrdinal,schemaVersion,startedAt" || fields.schemaVersion.valueType !== "integerValue" || fields.schemaVersion.integerValue !== "1"
    || fields.ownerToken.valueType !== "stringValue" || fields.runOrdinal.valueType !== "integerValue" || fields.startedAt.valueType !== "timestampValue" || fields.expiresAt.valueType !== "timestampValue") return false;
  // C9.1.3/C9.1.4 grammar: lowercase UUID owner token, nonnegative safe ordinal, expiresAt exactly 270 s after startedAt
  const ordinal = Number(fields.runOrdinal.integerValue);
  return SCHEDULER_OWNER_TOKEN_RE.test(fields.ownerToken.stringValue) && Number.isSafeInteger(ordinal) && ordinal >= 0
    && tsMillis(fields.expiresAt.timestampValue) === tsMillis(fields.startedAt.timestampValue) + SCHEDULER_LEASE_SECONDS * 1000;
}

function leaseRecord(ownerToken, generation, startedAt, leaseNow) {
  return { schemaVersion: 1, ownerToken, fencingGeneration: generation, startedAt: T(startedAt), renewedAt: T(leaseNow), expiresAt: T(tsPlusSeconds(leaseNow, LEASE_SECONDS)) };
}

function readLease(document) {
  const f = document.fields || {};
  const keys = Object.keys(f).sort().join(",");
  if (keys !== "expiresAt,fencingGeneration,ownerToken,renewedAt,schemaVersion,startedAt") throw new MigrationInvariant("MIGRATION_LEASE_INVARIANT", "members");
  if (f.schemaVersion.integerValue !== "1" || f.ownerToken.valueType !== "stringValue" || f.fencingGeneration.valueType !== "integerValue") throw new MigrationInvariant("MIGRATION_LEASE_INVARIANT", "shape");
  const generation = Number(f.fencingGeneration.integerValue);
  if (!Number.isSafeInteger(generation) || generation < 1) throw new MigrationInvariant("MIGRATION_LEASE_INVARIANT", "generation");
  return { ownerToken: f.ownerToken.stringValue, fencingGeneration: generation, startedAt: f.startedAt.timestampValue, renewedAt: f.renewedAt.timestampValue, expiresAt: f.expiresAt.timestampValue, updateTime: document.updateTime };
}

/** Acquisition: reads both lease documents in one transaction; refuses per the C9.2.3 table with zero writes. */
async function acquireMigrationLease(client, projectId, callOptions, ownerToken) {
  const leaseName = fullName(projectId, MIGRATION_LEASE_PATH);
  const schedulerName = fullName(projectId, SCHEDULER_LEASE_PATH);
  const read = await transactionalRead(client, projectId, [leaseName, schedulerName], callOptions);
  const leaseNow = read.readTime;
  const scheduler = read.found.get(schedulerName);
  const migration = read.found.get(leaseName);
  const refuse = async (reason) => { await client.rollback({ database: read.database, transaction: read.transaction }, callOptions).catch(() => {}); return { acquired: false, refusal: reason }; };
  let deleteScheduler = null;
  if (scheduler !== null) {
    if (isLegacySchedulerLease(scheduler.fields)) deleteScheduler = scheduler;
    else if (isV2SchedulerLease(scheduler.fields)) {
      const expiresAt = scheduler.fields.expiresAt.timestampValue;
      if (tsMillis(expiresAt) > tsMillis(leaseNow)) return refuse("SCHEDULER_LEASE_LIVE");
      if (tsMillis(leaseNow) < tsMillis(expiresAt) + SCHEDULER_GRACE_MS) return refuse("SCHEDULER_LEASE_DRAINING");
    } else return refuse("SCHEDULER_LEASE_SHAPE");
  }
  let generation = 1;
  let precondition = { exists: false };
  if (migration !== null) {
    const current = readLease(migration);
    if (tsMillis(current.expiresAt) > tsMillis(leaseNow)) return refuse("MIGRATION_LEASE_LIVE");
    generation = current.fencingGeneration + 1;
    if (!Number.isSafeInteger(generation)) return refuse("GENERATION_OVERFLOW");
    precondition = { updateTime: migration.updateTime };
  }
  const record = leaseRecord(ownerToken, generation, leaseNow, leaseNow);
  const writes = [{ update: { name: leaseName, fields: ownFields(record) }, currentDocument: precondition }];
  if (deleteScheduler) writes[writes.length] = { delete: schedulerName, currentDocument: { updateTime: deleteScheduler.updateTime } };
  const result = await commitWrites(client, read, writes, callOptions);
  return { acquired: true, lease: { name: leaseName, ownerToken, fencingGeneration: generation, startedAt: leaseNow, updateTime: result.writeResults[0].updateTime }, migratedSchedulerLease: deleteScheduler !== null };
}

/** The fencing renewal write that every mutation commit carries first; requires the exact captured lease update time. */
function renewalWrite(lease, leaseDocument, leaseNow) {
  const current = readLease(leaseDocument);
  if (current.ownerToken !== lease.ownerToken || current.fencingGeneration !== lease.fencingGeneration) throw new MigrationInvariant("MIGRATION_LEASE_LOST", "tuple");
  if (!tsEqual(leaseDocument.updateTime, lease.updateTime)) throw new MigrationInvariant("MIGRATION_LEASE_LOST", "updateTime");
  const record = leaseRecord(lease.ownerToken, lease.fencingGeneration, current.startedAt, leaseNow);
  return { update: { name: lease.name, fields: ownFields(record) }, currentDocument: { updateTime: leaseDocument.updateTime } };
}

/** Fenced mutation: read the lease plus `names` in one transaction, build writes, commit with the renewal first, capture the new lease update time. */
async function fencedCommit(client, projectId, callOptions, lease, names, build) {
  const read = await transactionalRead(client, projectId, [lease.name, ...names], callOptions);
  const leaseDocument = read.found.get(lease.name);
  if (leaseDocument === null) { await client.rollback({ database: read.database, transaction: read.transaction }, callOptions).catch(() => {}); throw new MigrationInvariant("MIGRATION_LEASE_LOST", "absent"); }
  let renewal;
  try { renewal = renewalWrite(lease, leaseDocument, read.readTime); } catch (error) { await client.rollback({ database: read.database, transaction: read.transaction }, callOptions).catch(() => {}); throw error; }
  const outcome = build(read.readTime, (name) => read.found.get(name));
  if (outcome === null || outcome.writes.length === 0) { await client.rollback({ database: read.database, transaction: read.transaction }, callOptions).catch(() => {}); return { committed: false, outcome }; }
  const result = await commitWrites(client, read, [renewal, ...outcome.writes], callOptions);
  lease.updateTime = result.writeResults[0].updateTime;
  return { committed: true, outcome, commitTime: result.commitTime, writeResults: result.writeResults };
}

async function releaseMigrationLease(client, projectId, callOptions, lease) {
  const read = await transactionalRead(client, projectId, [lease.name], callOptions);
  const document = read.found.get(lease.name);
  if (document === null) { await client.rollback({ database: read.database, transaction: read.transaction }, callOptions).catch(() => {}); return { released: false, absent: true }; }
  const current = readLease(document);
  if (current.ownerToken !== lease.ownerToken || current.fencingGeneration !== lease.fencingGeneration) { await client.rollback({ database: read.database, transaction: read.transaction }, callOptions).catch(() => {}); return { released: false, absent: false }; }
  await commitWrites(client, read, [{ delete: lease.name, currentDocument: { updateTime: document.updateTime } }], callOptions);
  const proof = await transactionalRead(client, projectId, [lease.name], callOptions);
  await client.rollback({ database: proof.database, transaction: proof.transaction }, callOptions).catch(() => {});
  return { released: true, absent: proof.found.get(lease.name) === null };
}

// ---------------------------------------------------------------------------
// C9.2.5 / C9.2.6 / C9.2.8 archive writes, terminal commit, orphan cleanup
// ---------------------------------------------------------------------------

function manifestPath(uid, archiveId) { return `users/${uid}/eventArchive/${archiveId}`; }
function chunkPath(uid, archiveId, index) { return `${manifestPath(uid, archiveId)}/eventArchiveChunks/${String(index).padStart(2, "0")}`; }
function uidOf(sourcePath) { return sourcePath.split("/")[1]; }

function chunkSlices(bytes) {
  const slices = [];
  for (let offset = 0, index = 0; offset < bytes.length; offset += CHUNK_PAYLOAD_MAX, index += 1) {
    const payload = bytes.subarray(offset, Math.min(offset + CHUNK_PAYLOAD_MAX, bytes.length));
    slices[slices.length] = { index, offset, length: payload.length, payload: Buffer.from(payload), payloadDigest: sha256Hex(payload) };
  }
  return slices;
}

function manifestRecord(plan, sourcePath, document, leaseNow) {
  return {
    schemaVersion: 1, archiveId: plan.archiveId, codec: "FirestoreDocumentArchiveV1",
    sourcePath, sourceCreateTime: T(document.createTime), sourceUpdateTime: T(document.updateTime),
    chunkPayloadMax: CHUNK_PAYLOAD_MAX, chunkCount: plan.chunkCount, totalBytes: plan.N, archiveDigest: plan.archiveDigest,
    state: "building", createdAt: T(leaseNow)
  };
}

function manifestView(document) {
  const f = document.fields || {};
  const get = (k) => (f[k] ? (f[k].stringValue ?? f[k].integerValue ?? f[k].timestampValue) : undefined);
  return { archiveId: get("archiveId"), codec: get("codec"), sourcePath: get("sourcePath"), sourceUpdateTime: f.sourceUpdateTime && f.sourceUpdateTime.timestampValue, chunkCount: Number(get("chunkCount")), totalBytes: Number(get("totalBytes")), archiveDigest: get("archiveDigest"), state: get("state"), updateTime: document.updateTime, fields: f };
}

function budgetOf(projectId, docPath, before, after) {
  const beforeJson = before ? toJsonFields(before.fields) : null;
  const afterJson = after ? toJsonFields(after) : null;
  return scheduler.rawStorage.transitionBudget([{ path: docPath, before: beforeJson, after: afterJson }]);
}

function assertBudget(charge, cap, label) {
  if (!Number.isSafeInteger(charge) || charge > cap) throw new MigrationInvariant("MIGRATION_BUDGET_INVARIANT", `${label} ${charge} > ${cap}`);
}

/** Creates or resumes the manifest; ARCHIVE_ID_COLLISION on identity mismatch; exact-state resume writes nothing. */
async function ensureManifest(client, projectId, callOptions, lease, plan, sourcePath, document) {
  const uid = uidOf(sourcePath);
  const name = fullName(projectId, manifestPath(uid, plan.archiveId));
  const result = await fencedCommit(client, projectId, callOptions, lease, [name], (leaseNow, get) => {
    const existing = get(name);
    if (existing !== null) {
      const view = manifestView(existing);
      if (view.archiveId !== plan.archiveId || view.sourcePath !== sourcePath || view.archiveDigest !== plan.archiveDigest || view.totalBytes !== plan.N || view.chunkCount !== plan.chunkCount || !tsEqual(view.sourceUpdateTime, document.updateTime)) throw new MigrationInvariant("ARCHIVE_ID_COLLISION", plan.archiveId);
      return { writes: [], state: view.state, resumed: true };
    }
    const record = manifestRecord(plan, sourcePath, document, leaseNow);
    const fields = ownFields(record);
    assertBudget(budgetOf(projectId, manifestPath(uid, plan.archiveId), null, fields).charge, BUDGET.manifestCommit, "manifest");
    return { writes: [{ update: { name, fields }, currentDocument: { exists: false } }], state: "building", resumed: false };
  });
  return { name, state: result.outcome.state, resumed: result.outcome.resumed };
}

/** Chunks ascending: create or exact-compare, one fenced commit each; then reread ascending and verify reassembly. */
async function writeChunks(client, projectId, callOptions, lease, plan, sourcePath) {
  const uid = uidOf(sourcePath);
  const slices = chunkSlices(plan.bytes);
  if (slices.length !== plan.chunkCount) throw new MigrationInvariant("ARCHIVE_CHUNK_CAP_EXCEEDED", String(plan.N));
  let created = 0;
  for (const slice of slices) {
    const name = fullName(projectId, chunkPath(uid, plan.archiveId, slice.index));
    const record = { schemaVersion: 1, archiveId: plan.archiveId, index: slice.index, offset: slice.offset, length: slice.length, payload: slice.payload, payloadDigest: slice.payloadDigest };
    const result = await fencedCommit(client, projectId, callOptions, lease, [name], (leaseNow, get) => {
      const existing = get(name);
      const fields = ownFields(record);
      if (existing !== null) {
        const e = existing.fields || {};
        const same = e.archiveId && e.archiveId.stringValue === plan.archiveId && e.index && Number(e.index.integerValue) === slice.index && e.offset && Number(e.offset.integerValue) === slice.offset && e.length && Number(e.length.integerValue) === slice.length && e.payloadDigest && e.payloadDigest.stringValue === slice.payloadDigest && e.payload && Buffer.from(e.payload.bytesValue || []).equals(slice.payload);
        if (!same) throw new MigrationInvariant("ARCHIVE_CHUNK_MISMATCH", String(slice.index));
        return { writes: [] };
      }
      assertBudget(budgetOf(projectId, chunkPath(uid, plan.archiveId, slice.index), null, fields).charge, BUDGET.chunkCommit, "chunk");
      return { writes: [{ update: { name, fields }, currentDocument: { exists: false } }] };
    });
    if (result.committed) created += 1;
  }
  // reread ascending: path, schema, range, per-chunk digest, reassembly length and full digest
  const parts = [];
  for (const slice of slices) {
    const [chunk] = await client.getDocument({ name: fullName(projectId, chunkPath(uid, plan.archiveId, slice.index)) }, callOptions);
    const e = chunk.fields || {};
    const payload = Buffer.from((e.payload && e.payload.bytesValue) || []);
    if (Number(e.offset.integerValue) !== slice.offset || Number(e.length.integerValue) !== payload.length || sha256Hex(payload) !== e.payloadDigest.stringValue || e.archiveId.stringValue !== plan.archiveId) throw new MigrationInvariant("ARCHIVE_BROKEN", String(slice.index));
    parts[parts.length] = payload;
  }
  const reassembled = Buffer.concat(parts);
  if (reassembled.length !== plan.N || sha256Hex(reassembled) !== plan.archiveDigest) throw new MigrationInvariant("ARCHIVE_BROKEN", "reassembly");
  return { created, verified: slices.length };
}

async function sealManifest(client, projectId, callOptions, lease, plan, sourcePath) {
  const name = fullName(projectId, manifestPath(uidOf(sourcePath), plan.archiveId));
  const result = await fencedCommit(client, projectId, callOptions, lease, [name], (leaseNow, get) => {
    const existing = get(name);
    if (existing === null) throw new MigrationInvariant("ARCHIVE_BROKEN", "manifest missing at seal");
    const view = manifestView(existing);
    if (view.state === "sealed" || view.state === "terminalized") return { writes: [], state: view.state };
    if (view.state !== "building") throw new MigrationInvariant("ARCHIVE_BROKEN", `seal from ${view.state}`);
    const fields = { ...existing.fields, state: ownValue("sealed"), sealedAt: ownValue(T(leaseNow)) };
    assertBudget(budgetOf(projectId, manifestPath(uidOf(sourcePath), plan.archiveId), existing, fields).charge, BUDGET.manifestCommit, "seal");
    return { writes: [{ update: { name, fields }, currentDocument: { updateTime: existing.updateTime } }], state: "sealed" };
  });
  return result.outcome.state;
}

function stubFields(plan, terminalizedAt) {
  const archiveRef = { schemaVersion: 1, archiveId: plan.archiveId, codec: "FirestoreDocumentArchiveV1", chunkCount: plan.chunkCount, totalBytes: plan.N, archiveDigest: plan.archiveDigest };
  return ownFields({ processingState: "terminal", processed: true, processedAt: T(terminalizedAt), outcome: "quarantined", processingError: STUB_MESSAGE, archiveRef });
}

function quarantineFields(plan, sourcePath, sourceUpdateTime, terminalizedAt) {
  const archiveRef = { schemaVersion: 1, archiveId: plan.archiveId, codec: "FirestoreDocumentArchiveV1", chunkCount: plan.chunkCount, totalBytes: plan.N, archiveDigest: plan.archiveDigest };
  return ownFields({ schemaVersion: 2, sourcePath, archiveDigest: plan.archiveDigest, reason: { code: "SOURCE_TOO_LARGE", message: STUB_MESSAGE }, migrationKind: "LEGACY_OVERSIZE_ARCHIVE", sourceUpdateTime: T(sourceUpdateTime), archiveRef, quarantinedAt: T(terminalizedAt) });
}

/** The terminal commit: exactly four writes in one public-v1 Commit under the captured preconditions. */
async function terminalCommit(client, projectId, callOptions, lease, plan, sourcePath) {
  const uid = uidOf(sourcePath);
  const sourceName = fullName(projectId, sourcePath);
  const manifestName = fullName(projectId, manifestPath(uid, plan.archiveId));
  const quarantineName = fullName(projectId, `${QUARANTINE_PATH}/${plan.archiveId}`);
  const result = await fencedCommit(client, projectId, callOptions, lease, [sourceName, manifestName, quarantineName], (leaseNow, get) => {
    const source = get(sourceName);
    const manifest = get(manifestName);
    const quarantine = get(quarantineName);
    if (manifest === null) throw new MigrationInvariant("ARCHIVE_BROKEN", "manifest missing at terminal");
    const view = manifestView(manifest);
    if (view.state === "terminalized") {
      const stub = source && source.fields && source.fields.archiveRef && source.fields.archiveRef.mapValue && source.fields.archiveRef.mapValue.fields.archiveId && source.fields.archiveRef.mapValue.fields.archiveId.stringValue === plan.archiveId;
      if (stub && quarantine !== null) return { writes: [], state: "terminalized", replay: true };
      throw new MigrationInvariant("ARCHIVE_BROKEN", "terminalized without stub/quarantine");
    }
    if (view.state !== "sealed") throw new MigrationInvariant("ARCHIVE_BROKEN", `terminal from ${view.state}`);
    if (quarantine !== null) throw new MigrationInvariant("ARCHIVE_ID_COLLISION", "quarantine preexisting");
    if (source === null) return { writes: [], state: "sealed", sourceMissing: true };
    const state = source.fields && source.fields.processingState;
    if (!state || state.stringValue !== "pending" || !tsEqual(source.updateTime, view.sourceUpdateTime)) return { writes: [], state: "sealed", sourceChanged: true };
    const stub = stubFields(plan, leaseNow);
    const record = quarantineFields(plan, sourcePath, view.sourceUpdateTime, leaseNow);
    const terminalManifest = { ...manifest.fields, state: ownValue("terminalized"), terminalizedAt: ownValue(T(leaseNow)) };
    const stubBudget = budgetOf(projectId, sourcePath, source, stub);
    const quarantineBudget = budgetOf(projectId, `${QUARANTINE_PATH}/${plan.archiveId}`, null, record);
    const manifestBudget = budgetOf(projectId, manifestPath(uid, plan.archiveId), manifest, terminalManifest);
    assertBudget(quarantineBudget.charge, BUDGET.stubOrQuarantine, "quarantine");
    assertBudget(Buffer.byteLength(fence.TaskCanonicalV1(toJsonFields(record)), "utf8"), BUDGET.canonicalRecord, "quarantine canonical");
    assertBudget(stubBudget.charge + quarantineBudget.charge + manifestBudget.charge + BUDGET.leaseFence, BUDGET.terminal, "terminal");
    return {
      writes: [
        { update: { name: sourceName, fields: stub }, currentDocument: { updateTime: source.updateTime } },
        { update: { name: quarantineName, fields: record }, currentDocument: { exists: false } },
        { update: { name: manifestName, fields: terminalManifest }, currentDocument: { updateTime: manifest.updateTime } }
      ],
      state: "terminalized", replay: false
    };
  });
  return { committed: result.committed, ...result.outcome };
}

/** One failing source end to end: manifest -> chunks -> seal -> terminal; returns the enum outcome. */
async function migrateSource(client, projectId, callOptions, lease, failing, now) {
  const [document] = await client.getDocument({ name: fullName(projectId, failing.sourcePath) }, callOptions).catch((error) => { if (error && (error.code === 5 || error.code === "NOT_FOUND")) return [null]; throw error; });
  if (document === null) return { sourcePath: failing.sourcePath, outcome: "DRIFT_MISSING" };
  const state = document.fields.processingState;
  if (!state || state.stringValue !== "pending") return { sourcePath: failing.sourcePath, outcome: "DRIFT_NOT_PENDING" };
  const jsonFields = toJsonFields(document.fields);
  const updateTime = new Timestamp(Number(timestampSeconds(document.updateTime)), Number(document.updateTime.nanos ?? 0));
  const envelope = scheduler.phase0EnvelopeRaw(failing.sourcePath, jsonFields, now, updateTime);
  if (envelope.admitted) return { sourcePath: failing.sourcePath, outcome: "DRIFT_ADMITTED" };
  const plan = archivePlan(document, failing.sourcePath, envelope.baseBytes);
  const manifest = await ensureManifest(client, projectId, callOptions, lease, plan, failing.sourcePath, document);
  if (manifest.state === "terminalized") { const t = await terminalCommit(client, projectId, callOptions, lease, plan, failing.sourcePath); return { sourcePath: failing.sourcePath, archiveId: plan.archiveId, outcome: t.replay ? "TERMINALIZED_REPLAY" : "TERMINALIZED" }; }
  if (manifest.state === "orphaned") throw new MigrationInvariant("ARCHIVE_ID_COLLISION", "orphaned manifest");
  const chunks = await writeChunks(client, projectId, callOptions, lease, plan, failing.sourcePath);
  const sealed = await sealManifest(client, projectId, callOptions, lease, plan, failing.sourcePath);
  if (sealed !== "sealed" && sealed !== "terminalized") throw new MigrationInvariant("ARCHIVE_BROKEN", sealed);
  const terminal = await terminalCommit(client, projectId, callOptions, lease, plan, failing.sourcePath);
  if (terminal.sourceMissing || terminal.sourceChanged) return { sourcePath: failing.sourcePath, archiveId: plan.archiveId, outcome: terminal.sourceMissing ? "DRIFT_MISSING" : "DRIFT_CHANGED", orphanCandidate: true, chunksCreated: chunks.created };
  return { sourcePath: failing.sourcePath, archiveId: plan.archiveId, outcome: terminal.replay ? "TERMINALIZED_REPLAY" : "TERMINALIZED", chunksCreated: chunks.created };
}

/** Enumerates every manifest through the pinned query; returns views with names. */
async function enumerateManifests(client, protos, projectId, callOptions) {
  const query = protos.google.firestore.v1.StructuredQuery.fromObject({ from: [{ collectionId: "eventArchive", allDescendants: true }], orderBy: [{ field: { fieldPath: "__name__" }, direction: "ASCENDING" }], limit: { value: PAGE_SIZE } });
  validateLimitWrapper(query.limit);
  let cursor = null;
  let manifests = [];
  for (;;) {
    const q = cursor === null ? query : protos.google.firestore.v1.StructuredQuery.fromObject({ ...protos.google.firestore.v1.StructuredQuery.toObject(query), startAt: { before: false, values: [{ referenceValue: cursor }] } });
    let count = 0;
    let last = null;
    for await (const response of client.runQuery({ parent: documentsParent(projectId), structuredQuery: q }, callOptions)) {
      const classified = classifyResponse(response);
      if (classified.kind !== "document") continue;
      const relative = classified.document.name.slice(documentsParent(projectId).length + 1);
      if (relative.split("/").length === 4) { manifests = [...manifests, { name: classified.document.name, relative, ...manifestView(classified.document) }]; }
      count += 1;
      last = classified.document.name;
    }
    if (count < PAGE_SIZE) return manifests;
    cursor = last;
  }
}

/** C9.2.8 orphan cleanup for non-terminalized manifests whose source no longer references them; lease-fenced throughout. */
async function cleanupOrphans(client, protos, projectId, callOptions, lease) {
  const manifests = await enumerateManifests(client, protos, projectId, callOptions);
  let results = [];
  for (const manifest of manifests) {
    if (manifest.state === "terminalized") continue;
    const uid = manifest.relative.split("/")[1];
    const sourceName = fullName(projectId, manifest.sourcePath);
    const quarantineName = fullName(projectId, `${QUARANTINE_PATH}/${manifest.archiveId}`);
    if (manifest.state !== "orphaned") {
      const marked = await fencedCommit(client, projectId, callOptions, lease, [manifest.name, sourceName, quarantineName], (leaseNow, get) => {
        const current = get(manifest.name);
        if (current === null) return { writes: [], gone: true };
        const source = get(sourceName);
        const quarantine = get(quarantineName);
        const referenced = quarantine !== null || (source !== null && source.fields.archiveRef && source.fields.archiveRef.mapValue.fields.archiveId.stringValue === manifest.archiveId);
        const sameUpdateTime = source !== null && tsEqual(source.updateTime, manifest.sourceUpdateTime);
        if (referenced || sameUpdateTime) return { writes: [], protected: true };
        const reason = source === null ? "SOURCE_DELETED" : "SOURCE_CHANGED";
        const fields = { ...current.fields, state: ownValue("orphaned"), orphanedAt: ownValue(T(leaseNow)), orphanReason: ownValue(reason) };
        delete fields.sealedAt;
        return { writes: [{ update: { name: manifest.name, fields }, currentDocument: { updateTime: current.updateTime } }], reason };
      });
      if (!marked.committed) { results = [...results, { archiveId: manifest.archiveId, outcome: marked.outcome && marked.outcome.protected ? "PROTECTED" : "GONE" }]; continue; }
    }
    for (let index = manifest.chunkCount - 1; index >= 0; index -= 1) {
      const name = fullName(projectId, chunkPath(uid, manifest.archiveId, index));
      await fencedCommit(client, projectId, callOptions, lease, [name], (leaseNow, get) => {
        const chunk = get(name);
        if (chunk === null) return { writes: [] };
        if (!chunk.fields.archiveId || chunk.fields.archiveId.stringValue !== manifest.archiveId) throw new MigrationInvariant("ARCHIVE_BROKEN", "orphan chunk mismatch");
        return { writes: [{ delete: name, currentDocument: { updateTime: chunk.updateTime } }] };
      });
    }
    await fencedCommit(client, projectId, callOptions, lease, [manifest.name], (leaseNow, get) => {
      const current = get(manifest.name);
      if (current === null) return { writes: [] };
      return { writes: [{ delete: manifest.name, currentDocument: { updateTime: current.updateTime } }] };
    });
    results = [...results, { archiveId: manifest.archiveId, outcome: "CLEANED" }];
  }
  return results;
}

/** C9.2.9 data conditions checked while the lease is held (rules/index tuple is checked at arming). */
async function preShipGate(client, protos, projectId, callOptions, now) {
  const audit = await runAudit(client, protos, projectId, callOptions, now);
  const manifests = await enumerateManifests(client, protos, projectId, callOptions);
  const nonTerminal = manifests.filter((m) => m.state !== "terminalized").length;
  let broken = 0;
  for (const manifest of manifests.filter((m) => m.state === "terminalized")) {
    const uid = manifest.relative.split("/")[1];
    const [source] = await client.getDocument({ name: fullName(projectId, manifest.sourcePath) }, callOptions).catch(() => [null]);
    const [quarantine] = await client.getDocument({ name: fullName(projectId, `${QUARANTINE_PATH}/${manifest.archiveId}`) }, callOptions).catch(() => [null]);
    const stubOk = source && source.fields.archiveRef && source.fields.archiveRef.mapValue.fields.archiveId.stringValue === manifest.archiveId && source.fields.processingState.stringValue === "terminal";
    let digestOk = false;
    if (stubOk && quarantine) {
      const parts = [];
      for (let i = 0; i < manifest.chunkCount; i += 1) {
        const [chunk] = await client.getDocument({ name: fullName(projectId, chunkPath(uid, manifest.archiveId, i)) }, callOptions).catch(() => [null]);
        if (!chunk) { parts.length = 0; break; }
        parts[parts.length] = Buffer.from(chunk.fields.payload.bytesValue || []);
      }
      const bytes = Buffer.concat(parts);
      digestOk = bytes.length === manifest.totalBytes && sha256Hex(bytes) === manifest.archiveDigest;
    }
    if (!stubOk || !quarantine || !digestOk) broken += 1;
  }
  const quarantineQuery = protos.google.firestore.v1.StructuredQuery.fromObject({ from: [{ collectionId: "quarantinedEvents", allDescendants: true }], orderBy: [{ field: { fieldPath: "__name__" }, direction: "ASCENDING" }], limit: { value: PAGE_SIZE } });
  let malformedQuarantine = 0;
  for await (const response of client.runQuery({ parent: documentsParent(projectId), structuredQuery: quarantineQuery }, callOptions)) {
    const classified = classifyResponse(response);
    if (classified.kind !== "document") continue;
    const sourcePath = classified.document.fields.sourcePath && classified.document.fields.sourcePath.stringValue;
    if (typeof sourcePath !== "string" || sourcePath.split("/").length !== 4 || !sourcePath.startsWith("users/") || sourcePath.split("/")[2] !== "events") malformedQuarantine += 1;
  }
  const passed = audit.preShipCriterion && nonTerminal === 0 && broken === 0 && malformedQuarantine === 0;
  return { passed, audit: { stable: audit.stable, preShipCriterion: audit.preShipCriterion, pendingCount: audit.passes.at(-1) ? audit.passes.at(-1).pendingCount : null }, manifests: manifests.length, nonTerminal, broken, malformedQuarantine };
}

/** Apply mode under the fenced lease: confirmed audit -> migrate every failing source -> orphan cleanup -> pre-ship gate -> release. */
async function runApply(client, protos, projectId, callOptions, now, deps) {
  const ownerToken = deps.ownerToken ? deps.ownerToken() : require("node:crypto").randomUUID().toLowerCase();
  const acquisition = await acquireMigrationLease(client, projectId, callOptions, ownerToken);
  if (!acquisition.acquired) return { refusal: `LEASE_REFUSED_${acquisition.refusal}`, lease: null };
  const lease = acquisition.lease;
  const summary = { refusal: null, lease: { ownerToken, fencingGeneration: lease.fencingGeneration, migratedSchedulerLease: acquisition.migratedSchedulerLease }, migrated: [], cleanup: [], gate: null, release: null };
  try {
    const audit = await runAudit(client, protos, projectId, callOptions, now);
    const confirmation = audit.passes.at(-1);
    summary.audit = { stable: audit.stable, preShipCriterion: audit.preShipCriterion, failing: confirmation ? confirmation.failing.length : null };
    // the confirmation under the lease: a complete pass with zero drift (a zero-failing pass is confirmed by its second pass)
    if (!confirmation.complete || confirmation.drifted.length > 0 || (confirmation.failing.length === 0 && confirmation.outOfScope.length === 0 && !audit.stable)) { summary.refusal = "AUDIT_UNSTABLE"; return summary; }
    if (confirmation.outOfScope.length > 0) { summary.refusal = "OUT_OF_SCOPE_SOURCE"; return summary; }
    for (const failing of confirmation.failing) summary.migrated = [...summary.migrated, await migrateSource(client, projectId, callOptions, lease, failing, now)];
    summary.cleanup = await cleanupOrphans(client, protos, projectId, callOptions, lease);
    summary.gate = await preShipGate(client, protos, projectId, callOptions, now);
    summary.refusal = summary.gate.passed ? null : "PRE_SHIP_GATE_FAILED";
    return summary;
  } finally {
    // the same object is returned above, so the release recorded here is visible to the caller
    summary.release = await releaseMigrationLease(client, projectId, callOptions, lease).catch((error) => ({ released: false, error: error && error.code }));
  }
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
      const applied = await runApply(client, deps.protos, projectId, callOptions, now, deps);
      const report = reportOf(parsed, deps, resolved, null, applied.refusal);
      report.apply = applied;
      return { exitCode: applied.refusal === null ? 0 : 4, report };
    }
    const audit = await runAudit(client, deps.protos, projectId, callOptions, now);
    // C9.2.2 audit exit: zero only when the C9.2.9 criterion holds (a complete zero-failing, zero-out-of-scope pass confirmed by its second pass)
    return { exitCode: audit.preShipCriterion ? 0 : 1, report: reportOf(parsed, deps, resolved, audit, null) };
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
  toJsonValue, toJsonFields, rfc3339, encodeArchive, decodeArchive, encodeValue, archiveIdFor, archivePlan, classifyDocument, runPass, runAudit, reportOf, run, documentsParent,
  MIGRATION_LEASE_PATH, SCHEDULER_LEASE_PATH, QUARANTINE_PATH, LEASE_SECONDS, BUDGET, STUB_MESSAGE,
  acquireMigrationLease, releaseMigrationLease, fencedCommit, renewalWrite, ensureManifest, writeChunks, sealManifest, terminalCommit, migrateSource, cleanupOrphans, preShipGate, runApply, chunkSlices, manifestPath, chunkPath, ownFields, transactionalRead
};
