"use strict";

/**
 * S3 I9d-2 — independent oracle for PHASE2_CONTRACT.md C9.1.23 (D8 storage equations, the frozen index policy,
 * FirestoreWriteBudgetV1) and C9.1.24 (raw Vector discriminator), implemented over raw public-v1 Documents/Values
 * only. It imports nothing from dispositionTriggers.js and shares no code with the production sizer.
 */

const fs = require("node:fs");
const path = require("node:path");

const REGISTRY = JSON.parse(fs.readFileSync(path.resolve(__dirname, "../../../firestore.indexes.json"), "utf8"));
const VALUE_CAP = 1500;
const ENTRY_OVERHEAD = 32;
const DOCUMENT_OVERHEAD = 32;
const NAME_OVERHEAD = 16;
const BOUNDS = Object.freeze({ document: 1048576, entry: 7680, entriesPerDocument: 40000, entryBytesPerDocument: 8388608, transaction: 8388608 });

class OracleInvariant extends Error {
  constructor(code, detail) { super(detail ? `${code}: ${detail}` : code); this.code = code; }
}

function utf8(s) { return Buffer.byteLength(String(s), "utf8"); }

function nameSize(docPath) {
  const segments = docPath.split("/");
  if (segments.length % 2 !== 0 || segments.some((s) => s.length === 0)) throw new OracleInvariant("ORACLE_PATH", docPath);
  return segments.reduce((sum, s) => sum + utf8(s) + 1, 0) + NAME_OVERHEAD;
}

function relativePath(referenceValue) {
  const marker = "/documents/";
  const at = referenceValue.indexOf(marker);
  if (at < 0) throw new OracleInvariant("ORACLE_REFERENCE", referenceValue);
  return referenceValue.slice(at + marker.length);
}

/** C9.1.24 — exactly two fields, `__type__` stringValue "__vector__" and `value` arrayValue of finite doubleValues. */
function vectorDimensions(mapValue) {
  const fields = mapValue.fields || {};
  const keys = Object.keys(fields);
  if (!keys.includes("__type__") || !(fields.__type__ && fields.__type__.stringValue === "__vector__")) return null;
  if (keys.length !== 2 || !keys.includes("value")) throw new OracleInvariant("ARCHIVE_CODEC_INVARIANT", "vector members");
  const value = fields.value;
  if (!value || !("arrayValue" in value) || Object.keys(value).length !== 1) throw new OracleInvariant("ARCHIVE_CODEC_INVARIANT", "vector value");
  const array = value.arrayValue;
  const arrayKeys = Object.keys(array || {});
  if (!(arrayKeys.length === 0 || (arrayKeys.length === 1 && arrayKeys[0] === "values" && Array.isArray(array.values)))) throw new OracleInvariant("ARCHIVE_CODEC_INVARIANT", "vector array");
  const values = array.values || [];
  if (values.length > 2048) throw new OracleInvariant("ARCHIVE_CODEC_INVARIANT", "vector dimensions");
  for (const element of values) {
    const k = Object.keys(element);
    if (k.length !== 1 || k[0] !== "doubleValue" || typeof element.doubleValue !== "number" || !Number.isFinite(element.doubleValue)) throw new OracleInvariant("ARCHIVE_CODEC_INVARIANT", "vector element");
  }
  return values.length;
}

function valueSize(value) {
  const keys = Object.keys(value);
  if (keys.length !== 1) throw new OracleInvariant("ORACLE_VALUE_ONEOF", keys.join(","));
  const kind = keys[0];
  switch (kind) {
    case "nullValue": return 1;
    case "booleanValue": return 1;
    case "integerValue": if (!/^-?\d+$/.test(String(value.integerValue))) throw new OracleInvariant("ORACLE_VALUE_INT", String(value.integerValue)); return 8;
    case "doubleValue": return 8;
    case "timestampValue": return 8;
    case "stringValue": return utf8(value.stringValue) + 1;
    case "bytesValue": return Buffer.from(value.bytesValue, "base64").length;
    case "referenceValue": return nameSize(relativePath(value.referenceValue));
    case "geoPointValue": return 16;
    case "arrayValue": return (value.arrayValue.values || []).reduce((sum, v) => sum + valueSize(v), 0);
    case "mapValue": {
      const dimensions = vectorDimensions(value.mapValue);
      if (dimensions !== null) return 8 * dimensions;
      return Object.entries(value.mapValue.fields || {}).reduce((sum, [k, v]) => sum + utf8(k) + 1 + valueSize(v), 0);
    }
    default: throw new OracleInvariant("ORACLE_VALUE_ONEOF", kind);
  }
}

function documentSize(docPath, fields) {
  return nameSize(docPath) + Object.entries(fields || {}).reduce((sum, [k, v]) => sum + utf8(k) + 1 + valueSize(v), 0) + DOCUMENT_OVERHEAD;
}

/** Leaves of a raw field map: [dottedPath, Value]; a map contributes only its leaves (a vector map is a leaf). */
function leaves(fields, prefix = "") {
  let out = [];
  for (const [key, value] of Object.entries(fields || {})) {
    const dotted = prefix ? `${prefix}.${key}` : key;
    if ("mapValue" in value && vectorDimensions(value.mapValue) === null) out = [...out, ...leaves(value.mapValue.fields || {}, dotted)];
    else out = [...out, [dotted, value]];
  }
  return out;
}

function overrideFor(collectionGroup, fieldPath) {
  return REGISTRY.fieldOverrides.find((o) => o.collectionGroup === collectionGroup && (o.fieldPath === fieldPath || o.fieldPath === "*" || fieldPath.startsWith(`${o.fieldPath}.`))) || null;
}

function capped(size) { return Math.min(size, VALUE_CAP); }

/** Every index entry size for a document under the frozen registry. */
function indexEntries(docPath, fields) {
  const segments = docPath.split("/");
  const collectionGroup = segments[segments.length - 2];
  const name = nameSize(docPath);
  let entries = [];
  for (const [dotted, value] of leaves(fields)) {
    const override = overrideFor(collectionGroup, dotted);
    const elements = "arrayValue" in value ? (value.arrayValue.values || []) : null;
    const single = name + capped(valueSize(value)) + ENTRY_OVERHEAD;
    if (override) {
      for (const index of override.indexes || []) {
        if (index.order) entries = [...entries, single];
        else if (index.arrayConfig === "CONTAINS" && elements) entries = [...entries, ...elements.map((e) => name + capped(valueSize(e)) + ENTRY_OVERHEAD)];
      }
    } else {
      entries = [...entries, single, single];
      if (elements) entries = [...entries, ...elements.map((e) => name + capped(valueSize(e)) + ENTRY_OVERHEAD)];
    }
  }
  const leafMap = new Map(leaves(fields));
  for (const index of REGISTRY.indexes) {
    if (index.collectionGroup !== collectionGroup) continue;
    if (!index.fields.every((f) => leafMap.has(f.fieldPath))) continue;
    entries = [...entries, name + index.fields.reduce((sum, f) => sum + capped(valueSize(leafMap.get(f.fieldPath))), 0) + ENTRY_OVERHEAD];
  }
  return entries;
}

function documentBudget(docPath, fields) {
  const entries = indexEntries(docPath, fields);
  return { document: documentSize(docPath, fields), entries, entryBytes: entries.reduce((a, b) => a + b, 0), maxEntry: entries.reduce((a, b) => Math.max(a, b), 0) };
}

/** Multiset difference of entry sizes (present in `after`, absent in `before`) — symmetric deltas are added by the caller. */
function entryDelta(before, after) {
  const counts = new Map();
  for (const e of before) counts.set(e, (counts.get(e) || 0) + 1);
  let delta = 0;
  for (const e of after) {
    const c = counts.get(e) || 0;
    if (c > 0) counts.set(e, c - 1); else delta += e;
  }
  return delta;
}

/**
 * FirestoreWriteBudgetV1 over a transition: `documents` = [{ path, before: fields|null, after: fields|null }].
 * Returns the charge and the per-document checks; `fits` is false on any exceeded bound.
 */
function transitionBudget(documents) {
  let charge = 0;
  let fits = true;
  const perDocument = [];
  for (const { path: docPath, before, after } of documents) {
    const pre = before ? documentBudget(docPath, before) : { document: 0, entries: [] };
    const post = after ? documentBudget(docPath, after) : { document: 0, entries: [] };
    if (after) charge += post.document;
    if (before && !after) charge += pre.document;
    charge += entryDelta(pre.entries, post.entries) + entryDelta(post.entries, pre.entries);
    if (after) {
      const ok = post.document <= BOUNDS.document && post.maxEntry <= BOUNDS.entry && post.entries.length <= BOUNDS.entriesPerDocument && post.entryBytes <= BOUNDS.entryBytesPerDocument;
      if (!ok) fits = false;
      perDocument.push({ path: docPath, ...post });
    }
    if (!Number.isSafeInteger(charge)) throw new OracleInvariant("ORACLE_ARITHMETIC");
  }
  if (charge > BOUNDS.transaction) fits = false;
  return { charge, fits, perDocument };
}

module.exports = { BOUNDS, OracleInvariant, nameSize, valueSize, documentSize, indexEntries, documentBudget, transitionBudget, vectorDimensions, entryDelta };
