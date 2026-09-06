"use strict";

/** S3 I9d-2 test support: Admin-decoded data → pinned public-v1 Document JSON (fixture codec, not an oracle). */

const { Timestamp, GeoPoint, DocumentReference, VectorValue } = require("@google-cloud/firestore");

const PROJECT = "demo-peezy-phase1";
const ROOT = `projects/${PROJECT}/databases/(default)/documents`;

function rfc3339(timestamp) {
  const iso = new Date(timestamp.seconds * 1000).toISOString().replace(".000Z", "");
  return `${iso}.${String(timestamp.nanoseconds).padStart(9, "0")}Z`;
}

function toRawValue(value) {
  if (value === null) return { nullValue: null };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    if (Number.isNaN(value)) return { doubleValue: "NaN" };
    if (value === Infinity) return { doubleValue: "Infinity" };
    if (value === -Infinity) return { doubleValue: "-Infinity" };
    return Number.isInteger(value) && Number.isSafeInteger(value) && !Object.is(value, -0) ? { integerValue: String(value) } : { doubleValue: value };
  }
  if (typeof value === "bigint") return { integerValue: value.toString() };
  if (typeof value === "string") return { stringValue: value };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (value instanceof Timestamp) return { timestampValue: rfc3339(value) };
  if (value instanceof GeoPoint) return { geoPointValue: { latitude: value.latitude, longitude: value.longitude } };
  if (value instanceof DocumentReference) return { referenceValue: `${ROOT}/${value.path}` };
  if (value instanceof VectorValue) return { mapValue: { fields: { __type__: { stringValue: "__vector__" }, value: { arrayValue: { values: value.toArray().map((d) => ({ doubleValue: d })) } } } } };
  if (Buffer.isBuffer(value)) return { bytesValue: value.toString("base64") };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(toRawValue) } };
  if (typeof value === "object") return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, toRawValue(v)])) } };
  throw new Error(`rawDocument: unsupported fixture value ${typeof value}`);
}

function toRawFields(data) {
  return Object.fromEntries(Object.entries(data).map(([k, v]) => [k, toRawValue(v)]));
}

function toRawDocument(docPath, data, updateTime = Timestamp.fromMillis(0)) {
  return { name: `${ROOT}/${docPath}`, fields: toRawFields(data), createTime: rfc3339(updateTime), updateTime: rfc3339(updateTime) };
}

/** A `fetchRawDocument` dependency over the shared fake. */
function rawFetcherFor(db) {
  return async (docPath) => {
    if (!db.__docs.has(docPath)) return { found: false };
    return { found: true, document: toRawDocument(docPath, db.__docs.get(docPath), db.__updateTimes.get(docPath)) };
  };
}

module.exports = { ROOT, PROJECT, toRawValue, toRawFields, toRawDocument, rawFetcherFor, rfc3339 };
