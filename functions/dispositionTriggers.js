"use strict";

const admin = require("firebase-admin");
const { createHash, randomUUID } = require("node:crypto");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const { assertDeletionAbsent } = require("./accountDeletionFence");
const {
  buildUpcomingContract,
  dateFromValue,
  validateDispositionContract
} = require("./dispositionContract");

const { Timestamp, FieldPath, FieldValue } = require("firebase-admin/firestore");
// C9.1.21 pinned @google-cloud/firestore constructor identities (the same module instance firebase-admin re-exports)
const { GeoPoint, DocumentReference, VectorValue } = require("@google-cloud/firestore");

// ---------------------------------------------------------------------------
// PHASE2_CONTRACT.md C9.1 — scheduler contract (D1–D9, B1, D11). S3.
// ---------------------------------------------------------------------------

const SCHEDULE_SECONDS = 300;
const LEASE_SECONDS = 270;
const LEASE_PATH = "phase1System/dispositionTriggerLease";
const STATE_PATH = "phase1System/dispositionTriggerState";
const CROSS_FENCE_PATH = "phase1System/dispositionTriggerState/migrationLeases/legacyOversizeMigrationV1";
const ALERTS_COLLECTION = "phase1System/dispositionTriggerState/phase2bAlerts";
const WORK_LIMIT = 10;
const RECENT_RUNS = 4;

/** C9.1.16 — exactly seven optional cursor keys; Phase 1 residue keys are migrated on the first acquisition. */
const PHASE0_CURSOR_KEY = "event_envelope_prepass";
const ORDINARY_LANES = Object.freeze([
  { lane: "date_snoozed_deferred", status: "Snoozed", kind: "date", deadline: 142 },
  { lane: "date_inprogress_user_action", status: "InProgress", kind: "date", deadline: 154 },
  { lane: "date_matching_waiting", status: "matching_in_progress", kind: "date", deadline: 166 },
  { lane: "event_snoozed_deferred", status: "Snoozed", kind: "event", deadline: 178 },
  { lane: "event_inprogress_user_action", status: "InProgress", kind: "event", deadline: 190 },
  { lane: "event_matching_waiting", status: "matching_in_progress", kind: "event", deadline: 202 }
]);
const CURSOR_KEYS = Object.freeze([PHASE0_CURSOR_KEY, ...ORDINARY_LANES.map((l) => l.lane)]);
const LEGACY_RESIDUE_KEYS = Object.freeze(["dateAfterAt", "dateAfterPath", "eventTaskAfterPath"]);
const STATE_KEYS = Object.freeze(["schedulerHealth", ...CURSOR_KEYS]);
const PHASE0_DEADLINE = 40;
const PHASE0_SELECT = 100;
const ORDINARY_SELECT = 50;
const ALERT_SLOT_BOUND = 11;
// C9.1.10 / C9.1.12 / C9.1.14 / C9.1.15 — threshold lane
const THRESHOLD_LANE = "threshold_attention";
const THRESHOLD_SELECT = 50;
const THRESHOLD_DEADLINE = 130;
const THRESHOLD_CAPACITY_CONTIGUOUS = 200;
const THRESHOLD_CAPACITY_CATCH_UP = 400;
const OLDEST_DUE_ALERT_SECONDS = 900;
const CATCH_UP_AGE_SECONDS = 300;
const THRESHOLD_MASK = Object.freeze(["thresholdProjection.state", "thresholdProjection.threshold_at", "task_generation_epoch", "task_instance_id"]);
const ALERT_TWO_MISSED = "p2b1_two_missed_completions";
const ALERT_OLDEST_DUE = "p2b1_oldest_due_over_900_seconds";
const ALERT_THRESHOLD_CAPACITY = "p2b1_threshold_capacity_exceeded";
const ALERT_THRESHOLD_SCAN = "p2b1_threshold_scan_capacity_exceeded";
// C9.1.18 / C9.1.19 — durable refusals and retry admission
const REFUSAL_REASONS = Object.freeze(["VALIDATION_REFUSAL", "AUTHORITY_REFUSAL", "IDENTITY_RACE", "TRANSACTION_RETRY_EXHAUSTED"]);
const REFUSAL_MAX_COUNT = 8;
const REFUSAL_MAX_BACKOFF = 16;
const ORDINARY_RETRY_RESERVE = 10;
const RETRY_SELECT = 50;
const ALERT_FAIRNESS_PREFIX = "p2b1_fairness_capacity_exceeded_";
const THRESHOLD_LANE_SPEC = Object.freeze({ lane: THRESHOLD_LANE, kind: "threshold", deadline: THRESHOLD_DEADLINE });

class SchedulerInvariant extends Error {
  constructor(code, detail) { super(detail ? `${code}: ${detail}` : code); this.code = code; }
}

// ---------------------------------------------------------------------------
// C9.1.21 / C9.1.22 / C9.1.26 — OriginalEventBytesV1, unencodable tokens, the qev1 code/message table
// ---------------------------------------------------------------------------

const QUARANTINE_COLLECTION = "phase1System/dispositionTriggerState/quarantinedEvents";
const QUARANTINE_RECORD_CAP = 16384;
const QEV1_MESSAGES = Object.freeze({
  REFERENCE_INVALID: "Event source path is invalid.",
  ENVELOPE_INVALID: "Event envelope must be a map.",
  EVENT_ID_INVALID: "event_id must equal the document ID.",
  EVENT_NAME_INVALID: "event_name must be nonblank.",
  CANONICAL_KEY_INVALID: "canonical_key must be nonblank.",
  SOURCE_VERSION_INVALID: "source_version must be a nonnegative safe integer.",
  OBSERVED_AT_INVALID: "observed_at must be a valid timestamp.",
  SOURCE_EVIDENCE_ID_INVALID: "source_evidence_id must be nonblank.",
  EFFECT_INVALID: "effect must be fire or retract.",
  PAYLOAD_INVALID: "payload must be valid Firestore event data.",
  PAYLOAD_TOO_LARGE: "Event payload cannot fit the Phase 2 high-water record.",
  PROCESSED_INVALID: "Event must be pending and unprocessed."
});
const QEV1_CODES = Object.freeze(Object.keys(QEV1_MESSAGES));
const UNENCODABLE_MESSAGES = Object.freeze({
  NON_PLAIN_OBJECT: "Source contains a non-plain object.",
  UNSUPPORTED_RUNTIME_TYPE: "Source contains an unsupported runtime type."
});

/** A qev1 validation failure: `code` is a table code and the message is the table message. */
class EnvelopeError extends Error {
  constructor(code) { super(QEV1_MESSAGES[code]); this.code = code; }
}

/** C9.1.22 token: the source cannot be encoded by OriginalEventBytesV1. */
class UnencodableSource extends Error {
  constructor(token) { super(UNENCODABLE_MESSAGES[token]); this.code = "SOURCE_UNENCODABLE"; this.token = token; }
}

function bytesInvariant(detail) { return new SchedulerInvariant("ORIGINAL_BYTES_INVARIANT", detail); }

function hexDouble(value) {
  if (Number.isNaN(value)) return "nan";
  if (value === Infinity) return "inf";
  if (value === -Infinity) return "-inf";
  const buffer = Buffer.alloc(8);
  buffer.writeDoubleBE(value, 0);
  return buffer.toString("hex");
}

function finiteHex(value, detail) {
  if (typeof value !== "number" || !Number.isFinite(value)) throw bytesInvariant(detail);
  return hexDouble(value);
}

function isPlainMap(value) {
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

/** C9.1.21 — OriginalEventBytesV1: returns the encoded bytes; predicate order 1..8 exactly. */
function encodeOriginalEventBytes(value, seen = new Set()) {
  const text = (s) => Buffer.from(s, "utf8");
  const join = (buffers) => Buffer.concat(buffers);
  if (value === null) return text("n");
  if (typeof value === "boolean") return text(value ? "t" : "f");
  if (typeof value === "string") { const bytes = text(value); return join([text(`s${bytes.length}:`), bytes]); }
  if (typeof value === "number") return text(`d${hexDouble(value)}`);
  if (value instanceof Date) return text(`D${finiteHex(value.getTime(), "Date")}`);
  if (value instanceof Timestamp) {
    const { seconds, nanoseconds } = value;
    if (!Number.isSafeInteger(seconds) || !Number.isInteger(nanoseconds) || nanoseconds < 0 || nanoseconds > 999999999) throw bytesInvariant("Timestamp");
    return text(`T${seconds}.${String(nanoseconds).padStart(9, "0")}`);
  }
  if (value instanceof GeoPoint) return text(`G${finiteHex(value.latitude, "GeoPoint")},${finiteHex(value.longitude, "GeoPoint")}`);
  if (value instanceof DocumentReference) {
    if (typeof value.path !== "string" || !value.path) throw bytesInvariant("DocumentReference");
    const bytes = text(value.path);
    return join([text(`R${bytes.length}:`), bytes]);
  }
  if (value instanceof VectorValue) {
    const elements = value.toArray();
    if (!Array.isArray(elements)) throw bytesInvariant("VectorValue");
    return text(`V${elements.length}[${elements.map((e) => finiteHex(e, "VectorValue")).join(",")}]`);
  }
  if (Buffer.isBuffer(value)) return join([text(`B${value.length}:`), value]);
  if (typeof value === "object") {
    if (seen.has(value)) throw bytesInvariant("cycle");
    if (Array.isArray(value)) {
      seen.add(value);
      const elements = value.map((item) => encodeOriginalEventBytes(item, seen));
      seen.delete(value);
      return join([text(`A${elements.length}[`), ...elements.flatMap((e, i) => (i === 0 ? [e] : [text(","), e])), text("]")]);
    }
    if (isPlainMap(value)) {
      seen.add(value);
      const keys = Object.keys(value).map((k) => ({ k, bytes: text(k) })).sort((a, b) => Buffer.compare(a.bytes, b.bytes));
      const entries = keys.map(({ k, bytes }) => join([text(`s${bytes.length}:`), bytes, text("="), encodeOriginalEventBytes(value[k], seen)]));
      seen.delete(value);
      return join([text(`M${entries.length}{`), ...entries.flatMap((e, i) => (i === 0 ? [e] : [text(","), e])), text("}")]);
    }
    throw new UnencodableSource("NON_PLAIN_OBJECT");
  }
  throw new UnencodableSource("UNSUPPORTED_RUNTIME_TYPE");
}

/** originalBytesDigest = SHA-256 over the source's top-level map with the retry member removed. */
function originalBytesDigest(data) {
  let subject = data;
  if (data !== null && typeof data === "object" && !Array.isArray(data) && isPlainMap(data) && "phase0ValidationFailure" in data) {
    subject = {};
    for (const key of Object.keys(data)) if (key !== "phase0ValidationFailure") subject[key] = data[key];
  }
  return createHash("sha256").update(encodeOriginalEventBytes(subject)).digest("hex");
}

function trimmed(value) {
  return typeof value === "string" ? value.trim() : "";
}

function canonicalize(value, seen = new Set()) {
  if (value === null || typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (value instanceof Date && Number.isFinite(value.getTime())) return value.toISOString();
  if (value && typeof value.toDate === "function") {
    const date = value.toDate();
    if (date instanceof Date && Number.isFinite(date.getTime())) return date.toISOString();
    throw new Error("Value is not canonical Firestore data");
  }
  if (!value || typeof value !== "object" || seen.has(value)) {
    throw new Error("Value is not canonical Firestore data");
  }
  seen.add(value);
  let result;
  if (Array.isArray(value)) {
    result = value.map((item) => canonicalize(item, seen));
  } else {
    result = {};
    for (const key of Object.keys(value).sort()) {
      if (!trimmed(key) || value[key] === undefined) {
        throw new Error("Value is not canonical Firestore data");
      }
      result[key] = canonicalize(value[key], seen);
    }
  }
  seen.delete(value);
  return result;
}

function canonicalJSON(value) {
  return JSON.stringify(canonicalize(value));
}

function isSafeEnvelopeValue(value, seen = new Set()) {
  if (value === null || typeof value === "string" || typeof value === "boolean") return true;
  if (typeof value === "number") return Number.isFinite(value);
  if (value instanceof Date) return Number.isFinite(value.getTime());
  if (value && typeof value.toDate === "function") {
    const date = value.toDate();
    return date instanceof Date && Number.isFinite(date.getTime());
  }
  if (!value || typeof value !== "object" || seen.has(value)) return false;
  if (!Array.isArray(value)) {
    const prototype = Object.getPrototypeOf(value);
    if (prototype !== Object.prototype && prototype !== null) return false;
  }
  seen.add(value);
  const valid = Array.isArray(value)
    ? value.every((item) => isSafeEnvelopeValue(item, seen))
    : Object.entries(value).every(([key, item]) => trimmed(key) && isSafeEnvelopeValue(item, seen));
  seen.delete(value);
  return valid;
}

function strictDate(value) {
  if (value instanceof Date && Number.isFinite(value.getTime())) return value;
  if (value && typeof value.toDate === "function") {
    const date = value.toDate();
    if (date instanceof Date && Number.isFinite(date.getTime())) return date;
  }
  return null;
}

function canonicalEventStateId(eventName, canonicalKey) {
  return createHash("sha256")
    .update(canonicalJSON([eventName, canonicalKey]))
    .digest("hex");
}

// ---------------------------------------------------------------------------
// C9.1.23 / C9.1.24 / C9.1.27 — D8 storage equations, the frozen index registry, FirestoreWriteBudgetV1, fitsPhase0Transition
// ---------------------------------------------------------------------------

/** The C7 index result (firestore.indexes.json), embedded because the deployed bundle carries no repository files. */
const PHASE0_INDEX_REGISTRY_V1 = Object.freeze({
  "indexes": [
    {
      "collectionGroup": "tasks",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        {
          "fieldPath": "status",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "dispositionContract.next_trigger.kind",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "dispositionContract.next_trigger.fired",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "dispositionContract.next_trigger.at",
          "order": "ASCENDING"
        }
      ]
    },
    {
      "collectionGroup": "tasks",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        {
          "fieldPath": "status",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "dispositionContract.next_trigger.kind",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "dispositionContract.next_trigger.fired",
          "order": "ASCENDING"
        }
      ]
    },
    {
      "collectionGroup": "tasks",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        {
          "fieldPath": "thresholdProjection.state",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "thresholdProjection.threshold_at",
          "order": "ASCENDING"
        }
      ]
    },
    {
      "collectionGroup": "schedulerRefusals",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        {
          "fieldPath": "lane",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "nextEligibleOrdinal",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "firstRefusedOrdinal",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "lastAttemptOrdinal",
          "order": "ASCENDING"
        }
      ]
    }
  ],
  "fieldOverrides": [
    {
      "collectionGroup": "events",
      "fieldPath": "processingState",
      "indexes": [
        {
          "order": "ASCENDING",
          "queryScope": "COLLECTION_GROUP"
        }
      ]
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "activeHandoff",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "conditions",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "dispositionContract",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "flowAnswerIdentities",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "flowAnswers",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "flowPath",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "flowRows",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "interactionHistory",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "notes",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "planChangeCycle",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "planChangeHistory",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "planChangeLink",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "quotes",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "resolution",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "taskInteraction",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "taskInteractionState",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "thresholdProjection",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "wakeEvidence",
      "indexes": []
    },
    {
      "collectionGroup": "taskPlanOperations",
      "fieldPath": "*",
      "indexes": []
    },
    {
      "collectionGroup": "taskPlanOperations",
      "fieldPath": "kind",
      "indexes": [
        {
          "order": "ASCENDING",
          "queryScope": "COLLECTION"
        }
      ]
    },
    {
      "collectionGroup": "notificationIntents",
      "fieldPath": "*",
      "indexes": []
    },
    {
      "collectionGroup": "packingPlan",
      "fieldPath": "*",
      "indexes": []
    },
    {
      "collectionGroup": "readiness",
      "fieldPath": "*",
      "indexes": []
    },
    {
      "collectionGroup": "spawnTokens",
      "fieldPath": "*",
      "indexes": []
    },
    {
      "collectionGroup": "taskDeadlineEvidence",
      "fieldPath": "*",
      "indexes": []
    },
    {
      "collectionGroup": "workflowResponses",
      "fieldPath": "*",
      "indexes": []
    },
    {
      "collectionGroup": "workflowSubmissions",
      "fieldPath": "*",
      "indexes": []
    },
    {
      "collectionGroup": "eventArchiveChunks",
      "fieldPath": "payload",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "foreignRoots",
      "indexes": []
    },
    {
      "collectionGroup": "tasks",
      "fieldPath": "evidence_reservation",
      "indexes": []
    },
    {
      "collectionGroup": "workflowSubmissions",
      "fieldPath": "userId",
      "indexes": [
        {
          "order": "ASCENDING",
          "queryScope": "COLLECTION"
        }
      ]
    },
    {
      "collectionGroup": "workflowSubmissions",
      "fieldPath": "owner",
      "indexes": [
        {
          "order": "ASCENDING",
          "queryScope": "COLLECTION"
        }
      ]
    },
    {
      "collectionGroup": "legacyResetMigrations",
      "fieldPath": "*",
      "indexes": []
    },
    {
      "collectionGroup": "outboundLeases",
      "fieldPath": "*",
      "indexes": []
    }
  ]
});

const STORAGE_BOUNDS = Object.freeze({ document: 1048576, entry: 7680, entriesPerDocument: 40000, entryBytesPerDocument: 8388608, transaction: 8388608 });
const PHASE0_SOURCE_ENVELOPE_BYTES = 1047552;
const INDEX_VALUE_CAP = 1500;
const RAW_SIZING_ATTEMPTS = 3;
const RAW_FETCH_TIMEOUT_MS = 30000;

function utf8Length(text) { return Buffer.byteLength(String(text), "utf8"); }

function documentNameSize(docPath) {
  const segments = String(docPath).split("/");
  if (segments.length < 2 || segments.length % 2 !== 0 || segments.some((s) => s.length === 0)) throw new SchedulerInvariant("STORAGE_PATH_INVARIANT", "document path");
  let total = 16;
  for (const segment of segments) total += utf8Length(segment) + 1;
  return total;
}

function collectionGroupOf(docPath) {
  const segments = String(docPath).split("/");
  return segments[segments.length - 2];
}

/** Semantic (Admin-decoded) value size. */
function storageValueSize(value) {
  if (value === null || typeof value === "boolean") return 1;
  if (typeof value === "number") return 8;
  if (typeof value === "string") return utf8Length(value) + 1;
  if (value instanceof Date || value instanceof Timestamp) return 8;
  if (value instanceof GeoPoint) return 16;
  if (value instanceof DocumentReference) return documentNameSize(value.path);
  if (value instanceof VectorValue) return 8 * value.toArray().length;
  if (Buffer.isBuffer(value)) return value.length;
  if (Array.isArray(value)) { let total = 0; for (const item of value) total += storageValueSize(item); return total; }
  if (typeof value === "object" && isPlainMap(value)) { let total = 0; for (const key of Object.keys(value)) total += utf8Length(key) + 1 + storageValueSize(value[key]); return total; }
  throw new SchedulerInvariant("STORAGE_VALUE_INVARIANT", typeof value);
}

/** Semantic leaves: [dottedPath, value]; a plain map contributes only its leaves; arrays, vectors, and scalars are leaves. */
function storageLeaves(data) {
  const out = [];
  const stack = [["", data]];
  while (stack.length) {
    const [prefix, map] = stack.pop();
    for (const key of Object.keys(map)) {
      const value = map[key];
      const dotted = prefix ? `${prefix}.${key}` : key;
      if (value !== null && typeof value === "object" && !Array.isArray(value) && !Buffer.isBuffer(value) && !(value instanceof Date) && !(value instanceof Timestamp) && !(value instanceof GeoPoint) && !(value instanceof DocumentReference) && !(value instanceof VectorValue) && isPlainMap(value)) {
        stack[stack.length] = [dotted, value];
      } else {
        out[out.length] = [dotted, value];
      }
    }
  }
  return out;
}

// ---- raw public-v1 Values ----

function rawInvariant(code, detail) { return new SchedulerInvariant(code, detail); }

/** C9.1.24 — the reserved Vector discriminator; null when the map is ordinary. */
function rawVectorDimensions(mapValue) {
  const fields = (mapValue && mapValue.fields) || {};
  const type = fields.__type__;
  if (!type || type.stringValue !== "__vector__") return null;
  const keys = Object.keys(fields);
  if (keys.length !== 2 || !("value" in fields)) throw rawInvariant("ARCHIVE_CODEC_INVARIANT", "vector members");
  const holder = fields.value;
  if (!holder || Object.keys(holder).length !== 1 || !("arrayValue" in holder)) throw rawInvariant("ARCHIVE_CODEC_INVARIANT", "vector value");
  const array = holder.arrayValue || {};
  const arrayKeys = Object.keys(array);
  if (arrayKeys.length > 1 || (arrayKeys.length === 1 && (arrayKeys[0] !== "values" || !Array.isArray(array.values)))) throw rawInvariant("ARCHIVE_CODEC_INVARIANT", "vector array");
  const values = array.values || [];
  if (values.length > 2048) throw rawInvariant("ARCHIVE_CODEC_INVARIANT", "vector dimensions");
  for (const element of values) {
    const elementKeys = Object.keys(element || {});
    if (elementKeys.length !== 1 || elementKeys[0] !== "doubleValue" || typeof element.doubleValue !== "number" || !Number.isFinite(element.doubleValue)) throw rawInvariant("ARCHIVE_CODEC_INVARIANT", "vector element");
  }
  return values.length;
}

function rawReferencePath(referenceValue) {
  const marker = "/documents/";
  const at = String(referenceValue).indexOf(marker);
  if (at < 0) throw rawInvariant("RAW_VALUE_UNKNOWN", "referenceValue");
  return String(referenceValue).slice(at + marker.length);
}

function rawValueSize(value) {
  if (value === null || typeof value !== "object") throw rawInvariant("RAW_VALUE_UNKNOWN", "value");
  const keys = Object.keys(value);
  if (keys.length !== 1) throw rawInvariant("RAW_VALUE_UNKNOWN", keys.join(","));
  const kind = keys[0];
  if (kind === "nullValue" || kind === "booleanValue") return 1;
  if (kind === "integerValue") { if (!/^-?\d+$/.test(String(value.integerValue))) throw rawInvariant("RAW_VALUE_UNKNOWN", "integerValue"); return 8; }
  if (kind === "doubleValue" || kind === "timestampValue") return 8;
  if (kind === "stringValue") return utf8Length(value.stringValue) + 1;
  if (kind === "bytesValue") return Buffer.from(String(value.bytesValue), "base64").length;
  if (kind === "referenceValue") return documentNameSize(rawReferencePath(value.referenceValue));
  if (kind === "geoPointValue") return 16;
  if (kind === "arrayValue") { let total = 0; for (const item of (value.arrayValue && value.arrayValue.values) || []) total += rawValueSize(item); return total; }
  if (kind === "mapValue") {
    const dimensions = rawVectorDimensions(value.mapValue);
    if (dimensions !== null) return 8 * dimensions;
    let total = 0;
    const fields = (value.mapValue && value.mapValue.fields) || {};
    for (const key of Object.keys(fields)) total += utf8Length(key) + 1 + rawValueSize(fields[key]);
    return total;
  }
  throw rawInvariant("RAW_VALUE_UNKNOWN", kind);
}

function rawLeaves(fields) {
  const out = [];
  const stack = [["", fields || {}]];
  while (stack.length) {
    const [prefix, map] = stack.pop();
    for (const key of Object.keys(map)) {
      const value = map[key];
      const dotted = prefix ? `${prefix}.${key}` : key;
      if (value && typeof value === "object" && "mapValue" in value && rawVectorDimensions(value.mapValue) === null) stack[stack.length] = [dotted, (value.mapValue && value.mapValue.fields) || {}];
      else out[out.length] = [dotted, value];
    }
  }
  return out;
}

// ---- index policy and budgets, generic over the two value domains ----

function makeSizer(domain) {
  const { leavesOf, sizeOf, elementsOf } = domain;
  const overrides = PHASE0_INDEX_REGISTRY_V1.fieldOverrides;
  const composites = PHASE0_INDEX_REGISTRY_V1.indexes;
  const cap = (n) => (n > INDEX_VALUE_CAP ? INDEX_VALUE_CAP : n);
  function documentSize(docPath, data) {
    let total = documentNameSize(docPath) + 32;
    for (const key of Object.keys(data || {})) total += utf8Length(key) + 1 + sizeOf(data[key]);
    return total;
  }
  function indexEntries(docPath, data) {
    const group = collectionGroupOf(docPath);
    const name = documentNameSize(docPath);
    const leaves = leavesOf(data || {});
    const entries = [];
    const present = new Map();
    for (const [dotted, value] of leaves) {
      present.set(dotted, value);
      const override = overrides.find((o) => o.collectionGroup === group && (o.fieldPath === dotted || o.fieldPath === "*" || dotted.startsWith(`${o.fieldPath}.`))) || null;
      const single = name + cap(sizeOf(value)) + 32;
      const elements = elementsOf(value);
      if (override !== null) {
        for (const index of override.indexes || []) {
          if (index.order) entries[entries.length] = single;
          else if (index.arrayConfig === "CONTAINS" && elements !== null) for (const e of elements) entries[entries.length] = name + cap(sizeOf(e)) + 32;
        }
      } else {
        entries[entries.length] = single;
        entries[entries.length] = single;
        if (elements !== null) for (const e of elements) entries[entries.length] = name + cap(sizeOf(e)) + 32;
      }
    }
    for (const index of composites) {
      if (index.collectionGroup !== group) continue;
      if (!index.fields.every((f) => present.has(f.fieldPath))) continue;
      let total = name + 32;
      for (const f of index.fields) total += cap(sizeOf(present.get(f.fieldPath)));
      entries[entries.length] = total;
    }
    return entries;
  }
  function documentBudget(docPath, data) {
    const entries = indexEntries(docPath, data);
    let entryBytes = 0;
    let maxEntry = 0;
    for (const e of entries) { entryBytes += e; if (e > maxEntry) maxEntry = e; }
    return { document: documentSize(docPath, data), entries, entryBytes, maxEntry };
  }
  /** Symmetric multiset delta: entries only in `a` plus entries only in `b` (sorted two-pointer walk). */
  function symmetricEntryDelta(a, b) {
    const x = [...a].sort((p, q) => p - q);
    const y = [...b].sort((p, q) => p - q);
    let i = 0; let j = 0; let delta = 0;
    while (i < x.length || j < y.length) {
      if (j >= y.length || (i < x.length && x[i] < y[j])) { delta += x[i]; i += 1; }
      else if (i >= x.length || y[j] < x[i]) { delta += y[j]; j += 1; }
      else { i += 1; j += 1; }
    }
    return delta;
  }
  function transitionBudget(documents) {
    let charge = 0;
    let fits = true;
    const perDocument = [];
    const empty = { document: 0, entries: [], entryBytes: 0, maxEntry: 0 };
    for (const { path: docPath, before, after } of documents) {
      const pre = before ? documentBudget(docPath, before) : empty;
      const post = after ? documentBudget(docPath, after) : empty;
      if (after) charge += post.document;
      else if (before) charge += pre.document;
      charge += symmetricEntryDelta(pre.entries, post.entries);
      if (after) {
        if (post.document > STORAGE_BOUNDS.document || post.maxEntry > STORAGE_BOUNDS.entry || post.entries.length > STORAGE_BOUNDS.entriesPerDocument || post.entryBytes > STORAGE_BOUNDS.entryBytesPerDocument) fits = false;
        perDocument[perDocument.length] = { path: docPath, document: post.document, entryCount: post.entries.length, entryBytes: post.entryBytes, maxEntry: post.maxEntry };
      }
      if (!Number.isSafeInteger(charge)) throw new SchedulerInvariant("STORAGE_ARITHMETIC_INVARIANT");
    }
    if (charge > STORAGE_BOUNDS.transaction) fits = false;
    return { charge, fits, perDocument };
  }
  return { documentSize, indexEntries, documentBudget, transitionBudget, documentNameSize, valueSize: sizeOf };
}

const storage = makeSizer({ leavesOf: storageLeaves, sizeOf: storageValueSize, elementsOf: (v) => (Array.isArray(v) ? v : null) });
const rawStorage = makeSizer({ leavesOf: rawLeaves, sizeOf: rawValueSize, elementsOf: (v) => (v && typeof v === "object" && "arrayValue" in v ? ((v.arrayValue && v.arrayValue.values) || []) : null) });

/** C9.1.27 — fitsPhase0Transition(preSource, preHighWater?, postSource, postHighWater?, quarantine?); each argument is {path, data} or null. */
function fitsPhase0Transition(preSource, preHighWater, postSource, postHighWater, quarantine) {
  const documents = [{ path: postSource ? postSource.path : preSource.path, before: preSource ? preSource.data : null, after: postSource ? postSource.data : null }];
  if (preHighWater || postHighWater) documents[documents.length] = { path: (postHighWater || preHighWater).path, before: preHighWater ? preHighWater.data : null, after: postHighWater ? postHighWater.data : null };
  if (quarantine && !(quarantine.existing && canonicalJSON(quarantine.existing) === canonicalJSON(quarantine.data))) documents[documents.length] = { path: quarantine.path, before: quarantine.existing || null, after: quarantine.data };
  return storage.transitionBudget(documents);
}

function withoutRetryMember(data) {
  const out = {};
  for (const key of Object.keys(data)) if (key !== "phase0ValidationFailure") out[key] = data[key];
  return out;
}

function terminalQuarantineData(data, now, message) {
  return { ...withoutRetryMember(data), processingState: "terminal", processed: true, processedAt: now, outcome: "quarantined", processingError: message };
}

/**
 * C9.1.27 retry-or-terminal envelope: the source is at most 1,047,552 bytes and every S→R(code,count), every qev1
 * terminal with its record, and both qevu terminals with their records fit; returns the admission and the maxima.
 */
function phase0Envelope(sourcePath, data, now, sourceUpdateTime) {
  const baseBytes = storage.documentSize(sourcePath, data);
  let prospectiveMaxBytes = 0;
  const source = { path: sourcePath, data };
  const consider = (budget) => { if (budget.charge > prospectiveMaxBytes) prospectiveMaxBytes = budget.charge; return budget.fits; };
  let admitted = baseBytes <= PHASE0_SOURCE_ENVELOPE_BYTES;
  const digest = "0".repeat(64);
  const stamp = isMillisTimestamp(sourceUpdateTime) ? sourceUpdateTime : now;
  for (const code of QEV1_CODES) {
    for (const count of [1, 2]) {
      const retryData = { ...withoutRetryMember(data), phase0ValidationFailure: { schemaVersion: 1, originalBytesDigest: digest, reasonCode: code, failureCount: count, firstFailedAt: now, lastFailedAt: now } };
      if (!consider(fitsPhase0Transition(source, null, { path: sourcePath, data: retryData }, null, null))) admitted = false;
    }
    const message = QEV1_MESSAGES[code];
    const record = { schemaVersion: 1, sourcePath, sourceUpdateTime: stamp, originalBytesDigest: digest, reason: { code, message }, failureCount: 3, firstFailedAt: now, lastFailedAt: now, quarantinedAt: now };
    if (!consider(fitsPhase0Transition(source, null, { path: sourcePath, data: terminalQuarantineData(data, now, message) }, null, { path: `${QUARANTINE_COLLECTION}/qev1_${digest.slice(0, 40)}`, data: record }))) admitted = false;
  }
  for (const token of Object.keys(UNENCODABLE_MESSAGES)) {
    const message = UNENCODABLE_MESSAGES[token];
    const record = { schemaVersion: 1, sourcePath, sourceUpdateTime: stamp, unencodableSourceDigest: digest, reason: { code: "SOURCE_UNENCODABLE", token, message }, failureCount: 1, firstFailedAt: now, lastFailedAt: now, quarantinedAt: now };
    if (!consider(fitsPhase0Transition(source, null, { path: sourcePath, data: terminalQuarantineData(data, now, message) }, null, { path: `${QUARANTINE_COLLECTION}/qevu1_${digest.slice(0, 40)}`, data: record }))) admitted = false;
  }
  return { admitted, baseBytes, prospectiveMaxBytes };
}

function toRawScalarFields(map) {
  const fields = {};
  for (const key of Object.keys(map)) {
    const value = map[key];
    if (value === null) fields[key] = { nullValue: null };
    else if (typeof value === "boolean") fields[key] = { booleanValue: value };
    else if (typeof value === "number") fields[key] = Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
    else if (typeof value === "string") fields[key] = { stringValue: value };
    else if (value instanceof Timestamp) fields[key] = { timestampValue: value.toDate().toISOString() };
    else if (typeof value === "object" && isPlainMap(value)) fields[key] = { mapValue: { fields: toRawScalarFields(value) } };
    else throw new SchedulerInvariant("STORAGE_VALUE_INVARIANT", "raw scalar");
  }
  return fields;
}

/** C9.1.25 — fitsPhase0TransitionRaw over the raw sidecar only: retry member removed, exact terminal fields overlaid, qevu record create. */
function fitsPhase0TransitionRaw(rawFields, sourcePath, record, message, now) {
  const after = {};
  for (const key of Object.keys(rawFields || {})) if (key !== "phase0ValidationFailure") after[key] = rawFields[key];
  Object.assign(after, toRawScalarFields({ processingState: "terminal", processed: true, processedAt: now, outcome: "quarantined", processingError: message }));
  return rawStorage.transitionBudget([{ path: sourcePath, before: rawFields, after }, { path: record.path, before: null, after: toRawScalarFields(record.data) }]);
}

/** C9.1.27 over the raw sidecar (MIG-EVENT-V1 admission): the same prospects as phase0Envelope, computed from raw Values only. */
function phase0EnvelopeRaw(sourcePath, rawFields, now, sourceUpdateTime) {
  const baseBytes = rawStorage.documentSize(sourcePath, rawFields);
  let prospectiveMaxBytes = 0;
  let admitted = baseBytes <= PHASE0_SOURCE_ENVELOPE_BYTES;
  const consider = (budget) => { if (budget.charge > prospectiveMaxBytes) prospectiveMaxBytes = budget.charge; return budget.fits; };
  const digest = "0".repeat(64);
  const stamp = isMillisTimestamp(sourceUpdateTime) ? sourceUpdateTime : now;
  const withoutRetry = {};
  for (const key of Object.keys(rawFields || {})) if (key !== "phase0ValidationFailure") withoutRetry[key] = rawFields[key];
  const terminal = (message) => ({ ...withoutRetry, ...toRawScalarFields({ processingState: "terminal", processed: true, processedAt: now, outcome: "quarantined", processingError: message }) });
  for (const code of QEV1_CODES) {
    for (const count of [1, 2]) {
      const retry = { ...withoutRetry, ...toRawScalarFields({ phase0ValidationFailure: { schemaVersion: 1, originalBytesDigest: digest, reasonCode: code, failureCount: count, firstFailedAt: now, lastFailedAt: now } }) };
      if (!consider(rawStorage.transitionBudget([{ path: sourcePath, before: rawFields, after: retry }]))) admitted = false;
    }
    const message = QEV1_MESSAGES[code];
    const record = toRawScalarFields({ schemaVersion: 1, sourcePath, sourceUpdateTime: stamp, originalBytesDigest: digest, reason: { code, message }, failureCount: 3, firstFailedAt: now, lastFailedAt: now, quarantinedAt: now });
    if (!consider(rawStorage.transitionBudget([{ path: sourcePath, before: rawFields, after: terminal(message) }, { path: `${QUARANTINE_COLLECTION}/qev1_${digest.slice(0, 40)}`, before: null, after: record }]))) admitted = false;
  }
  for (const token of Object.keys(UNENCODABLE_MESSAGES)) {
    const message = UNENCODABLE_MESSAGES[token];
    const record = toRawScalarFields({ schemaVersion: 1, sourcePath, sourceUpdateTime: stamp, unencodableSourceDigest: digest, reason: { code: "SOURCE_UNENCODABLE", token, message }, failureCount: 1, firstFailedAt: now, lastFailedAt: now, quarantinedAt: now });
    if (!consider(rawStorage.transitionBudget([{ path: sourcePath, before: rawFields, after: terminal(message) }, { path: `${QUARANTINE_COLLECTION}/qevu1_${digest.slice(0, 40)}`, before: null, after: record }]))) admitted = false;
  }
  return { admitted, baseBytes, prospectiveMaxBytes };
}

function postCutoff(fields) {
  const error = new SchedulerInvariant("POST_CUTOFF_SOURCE_SIZE_INVARIANT");
  error.fields = fields;
  return error;
}

/** RFC 3339 with up to nine fractional digits → {seconds, nanoseconds}. */
function parseRfc3339(text) {
  const match = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,9}))?Z$/.exec(String(text));
  if (!match) return null;
  const seconds = Math.floor(Date.parse(`${match[1]}Z`) / 1000);
  const nanoseconds = match[2] ? Number((match[2] + "000000000").slice(0, 9)) : 0;
  return Number.isSafeInteger(seconds) ? { seconds, nanoseconds } : null;
}

/** C9.1.29 — validators in the frozen precedence, each failing with its qev1 table code and message. */
function validateEventEnvelope(data, documentId) {
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new EnvelopeError("ENVELOPE_INVALID");
  const eventId = trimmed(data.event_id);
  const eventName = trimmed(data.event_name);
  const canonicalKey = trimmed(data.canonical_key);
  const evidenceId = trimmed(data.source_evidence_id);
  if (!eventId || eventId !== documentId) throw new EnvelopeError("EVENT_ID_INVALID");
  if (!eventName) throw new EnvelopeError("EVENT_NAME_INVALID");
  if (!canonicalKey) throw new EnvelopeError("CANONICAL_KEY_INVALID");
  if (!Number.isSafeInteger(data.source_version) || data.source_version < 0) throw new EnvelopeError("SOURCE_VERSION_INVALID");
  const observedAt = strictDate(data.observed_at);
  if (!observedAt) throw new EnvelopeError("OBSERVED_AT_INVALID");
  if (!evidenceId) throw new EnvelopeError("SOURCE_EVIDENCE_ID_INVALID");
  if (data.effect !== "fire" && data.effect !== "retract") throw new EnvelopeError("EFFECT_INVALID");
  const payload = data.payload === undefined ? {} : data.payload;
  if (!isSafeEnvelopeValue(payload)) throw new EnvelopeError("PAYLOAD_INVALID");
  if (data.processingState !== "pending" || data.processed !== false) throw new EnvelopeError("PROCESSED_INVALID");

  return canonicalize({
    event_id: eventId,
    event_name: eventName,
    canonical_key: canonicalKey,
    source_version: data.source_version,
    observed_at: observedAt,
    source_evidence_id: evidenceId,
    effect: data.effect,
    payload
  });
}

function canonicalEventEnvelope(data, documentId) {
  return validateEventEnvelope(data, documentId);
}

function fingerprintCanonicalEnvelope(envelope) {
  return createHash("sha256").update(canonicalJSON(envelope)).digest("hex");
}

function classifyEnvelope(envelope, highWater) {
  if (!highWater || !Number.isSafeInteger(highWater.source_version)) return "advance";
  if (envelope.source_version < highWater.source_version) return "stale";
  if (envelope.source_version > highWater.source_version) return "advance";
  return fingerprintCanonicalEnvelope(envelope) === highWater.fingerprint
    ? "duplicate"
    : "version_conflict";
}

/** Candidate-comparison time: the run's leaseNow Timestamp or a Date (Phase 1 callers). */
function toDate(now) {
  return now instanceof Date ? now : now.toDate();
}

function shouldWakeDateTask(data, now) {
  const trigger = data?.dispositionContract?.next_trigger;
  const at = dateFromValue(trigger?.at);
  return data?.status === "Snoozed" &&
    trigger?.kind === "date" &&
    trigger?.fired !== true &&
    at !== null && at.getTime() <= toDate(now).getTime();
}

function shouldWakeEventTask(data, highWater) {
  const trigger = data?.dispositionContract?.next_trigger;
  const boundary = Number.isSafeInteger(trigger?.after_source_version)
    ? trigger.after_source_version
    : -1;
  return data?.status === "Snoozed" &&
    trigger?.kind === "event" &&
    trigger?.fired !== true &&
    trimmed(trigger.event_name) === trimmed(highWater?.event_name) &&
    trimmed(trigger.canonical_key) === trimmed(highWater?.canonical_key) &&
    Number.isSafeInteger(highWater?.source_version) &&
    highWater.source_version > boundary &&
    highWater.effect === "fire";
}

async function mapWithConcurrency(items, limit, operation) {
  if (!Number.isSafeInteger(limit) || limit < 1) throw new Error("Concurrency limit must be positive");
  const output = new Array(items.length);
  let nextIndex = 0;
  async function worker() {
    while (true) {
      const index = nextIndex;
      nextIndex += 1;
      if (index >= items.length) return;
      output[index] = await operation(items[index], index);
    }
  }
  const count = Math.min(limit, items.length);
  await Promise.all(Array.from({ length: count }, () => worker()));
  return output;
}

function leaseIsLive(data, now) {
  const expiresAt = dateFromValue(data?.expiresAt);
  return Boolean(trimmed(data?.runId)) && expiresAt !== null && expiresAt.getTime() > now.getTime();
}

/** Transaction-form date wake over an already-read snapshot; the caller owns the transaction and any scheduler fence. */
async function wakeDateTaskTx(db, transaction, ref, snapshot, now) {
  if (!snapshot.exists || !shouldWakeDateTask(snapshot.data(), now)) return false;
  const data = snapshot.data();
  const contract = buildUpcomingContract(data.dispositionContract, "Ready to continue");
  validateDispositionContract("Upcoming", contract, now);
  await assertDeletionAbsent(transaction, db, [taskUserId(ref)]); // C6.1 root fence
  transaction.update(ref, {
    status: "Upcoming",
    dispositionContract: contract,
    snoozedUntil: deleteField()
  });
  return true;
}

async function wakeDateTaskInTransaction(db, ref, rawNow, run = null) {
  const now = toDate(rawNow);
  return db.runTransaction(async (transaction) => {
    if (run) await requireSchedulerFence(transaction, db, run);
    const snapshot = await transaction.get(ref);
    return wakeDateTaskTx(db, transaction, ref, snapshot, now);
  });
}

function eventUserId(ref) {
  const parts = ref.path.split("/");
  if (parts.length !== 4 || parts[0] !== "users" || parts[2] !== "events") {
    throw new Error("Event reference is outside users/{uid}/events");
  }
  return parts[1];
}

function taskUserId(ref) {
  const parts = ref.path.split("/");
  if (parts.length !== 4 || parts[0] !== "users" || parts[2] !== "tasks") {
    throw new Error("Task reference is outside users/{uid}/tasks");
  }
  return parts[1];
}

function toTimestamp(now) {
  return now instanceof Timestamp ? now : Timestamp.fromDate(toDate(now));
}

function quarantineRef(db, id) { return db.doc(`${QUARANTINE_COLLECTION}/${id}`); }

function assertRecordCap(record) {
  if (Buffer.byteLength(canonicalJSON(record), "utf8") > QUARANTINE_RECORD_CAP) throw new SchedulerInvariant("PHASE0_QUARANTINE_INVARIANT", "record cap");
}

/** Members compared for replay (the runNow-stamped timestamps are retained from the existing record). */
function sameQuarantineIdentity(existing, prospective, members) {
  return members.every((m) => canonicalJSON(existing[m] === undefined ? null : existing[m]) === canonicalJSON(prospective[m]));
}

/** C9.1.26 — the retry member is either absent or exactly R(code,count) with count in {1,2}; anything else fails closed. */
function validateRetryMember(value) {
  if (value === undefined) return null;
  const invariant = new SchedulerInvariant("PHASE0_RETRY_MAP_INVARIANT");
  if (value === null || typeof value !== "object" || Array.isArray(value)) throw invariant;
  if (Object.keys(value).sort().join(",") !== "failureCount,firstFailedAt,lastFailedAt,originalBytesDigest,reasonCode,schemaVersion") throw invariant;
  if (value.schemaVersion !== 1 || typeof value.originalBytesDigest !== "string" || !/^[0-9a-f]{64}$/.test(value.originalBytesDigest)) throw invariant;
  if (!QEV1_CODES.includes(value.reasonCode) || ![1, 2].includes(value.failureCount)) throw invariant;
  if (!isMillisTimestamp(value.firstFailedAt) || !isMillisTimestamp(value.lastFailedAt) || value.firstFailedAt.toMillis() > value.lastFailedAt.toMillis()) throw invariant;
  return value;
}

const TERMINAL_QUARANTINE = (now, message) => ({ processingState: "terminal", processed: true, processedAt: now, outcome: "quarantined", processingError: message, phase0ValidationFailure: FieldValue.delete() });

/** C9.1.26/C9.1.27 — attempts 1 and 2 write R(code,count); attempt 3 writes the qev1 record and Q(message). */
async function phase0Failure(transaction, db, ref, snapshot, retry, digest, code, now) {
  const same = retry !== null && retry.originalBytesDigest === digest && retry.reasonCode === code;
  const attempt = same ? retry.failureCount + 1 : 1;
  const firstFailedAt = same ? retry.firstFailedAt : now;
  if (attempt <= 2) {
    transaction.update(ref, { phase0ValidationFailure: { schemaVersion: 1, originalBytesDigest: digest, reasonCode: code, failureCount: attempt, firstFailedAt, lastFailedAt: now } });
    return "retry";
  }
  const message = QEV1_MESSAGES[code];
  const record = { schemaVersion: 1, sourcePath: ref.path, sourceUpdateTime: isMillisTimestamp(snapshot.updateTime) ? snapshot.updateTime : now, originalBytesDigest: digest, reason: { code, message }, failureCount: 3, firstFailedAt, lastFailedAt: now, quarantinedAt: now };
  const qref = quarantineRef(db, `qev1_${digest.slice(0, 40)}`);
  const existing = await transaction.get(qref);
  if (existing.exists) {
    if (!sameQuarantineIdentity(existing.data(), record, ["schemaVersion", "sourcePath", "originalBytesDigest", "reason", "failureCount"])) throw new SchedulerInvariant("PHASE0_QUARANTINE_INVARIANT", "qev1 disagreement");
  } else {
    assertRecordCap(record);
    transaction.create(qref, record);
  }
  transaction.update(ref, TERMINAL_QUARANTINE(now, message));
  return "quarantined";
}

function unencodableRecord(ref, updateTime, token, now) {
  const digest = createHash("sha256").update(canonicalJSON({ domain: "unencodable_source.v1", source_path: ref.path, reason_token: token, update_time: updateTime })).digest("hex");
  const data = { schemaVersion: 1, sourcePath: ref.path, sourceUpdateTime: updateTime, unencodableSourceDigest: digest, reason: { code: "SOURCE_UNENCODABLE", token, message: UNENCODABLE_MESSAGES[token] }, failureCount: 1, firstFailedAt: now, lastFailedAt: now, quarantinedAt: now };
  return { path: `${QUARANTINE_COLLECTION}/qevu1_${digest.slice(0, 40)}`, data };
}

/**
 * C9.1.22 / C9.1.25 RawPhase0SizingV1 — first-occurrence SOURCE_UNENCODABLE: the pinned public-v1 raw Document is
 * fetched and sized (fitsPhase0TransitionRaw); an Admin transaction then rereads the source and requires the
 * identical updateTime before the field-path terminalization and the qevu1 record create in the same transaction;
 * drift restarts with a fresh raw read (bounded); absence, an unknown Value, or an over-budget raw prospective is
 * POST_CUTOFF_SOURCE_SIZE_INVARIANT with no source write.
 */
async function terminalizeUnencodable(db, ref, token, now, run) {
  const fetchRawDocument = run && run.deps && typeof run.deps.fetchRawDocument === "function" ? run.deps.fetchRawDocument : null;
  if (fetchRawDocument === null) throw new SchedulerInvariant("RAW_DOCUMENT_UNAVAILABLE");
  for (let attempt = 1; attempt <= RAW_SIZING_ATTEMPTS; attempt += 1) {
    const fetched = await fetchRawDocument(ref.path);
    if (!fetched || fetched.found !== true || !fetched.document) throw postCutoff({ sourcePath: ref.path, baseBytes: 0, prospectiveMaxBytes: 0 });
    const rawUpdateTime = parseRfc3339(fetched.document.updateTime);
    if (rawUpdateTime === null) throw postCutoff({ sourcePath: ref.path, baseBytes: 0, prospectiveMaxBytes: 0 });
    const updateTime = new Timestamp(rawUpdateTime.seconds, rawUpdateTime.nanoseconds);
    const record = unencodableRecord(ref, updateTime, token, now);
    let budget;
    let baseBytes;
    try {
      baseBytes = rawStorage.documentSize(ref.path, fetched.document.fields);
      budget = fitsPhase0TransitionRaw(fetched.document.fields, ref.path, record, UNENCODABLE_MESSAGES[token], now);
    } catch (error) {
      if (error instanceof SchedulerInvariant && error.code === "ARCHIVE_CODEC_INVARIANT") throw error;
      if (error instanceof SchedulerInvariant) throw postCutoff({ sourcePath: ref.path, baseBytes: 0, prospectiveMaxBytes: 0 });
      throw error;
    }
    if (!budget.fits) throw postCutoff({ sourcePath: ref.path, baseBytes, prospectiveMaxBytes: budget.charge });
    const outcome = await db.runTransaction(async (transaction) => {
      if (run) await requireSchedulerFence(transaction, db, run);
      const snapshot = await transaction.get(ref);
      if (!snapshot.exists || snapshot.data()?.processingState !== "pending") return "noop";
      const current = snapshot.updateTime;
      if (!isMillisTimestamp(current) || current.seconds !== updateTime.seconds || current.nanoseconds !== updateTime.nanoseconds) return "drift";
      await assertDeletionAbsent(transaction, db, [eventUserId(ref)]); // C6.1 root fence
      const qref = db.doc(record.path);
      const existing = await transaction.get(qref);
      if (existing.exists) {
        if (!sameQuarantineIdentity(existing.data(), record.data, ["schemaVersion", "sourcePath", "sourceUpdateTime", "unencodableSourceDigest", "reason", "failureCount"])) throw new SchedulerInvariant("PHASE0_QUARANTINE_INVARIANT", "qevu1 disagreement");
      } else {
        assertRecordCap(record.data);
        transaction.create(qref, record.data);
      }
      transaction.update(ref, TERMINAL_QUARANTINE(now, UNENCODABLE_MESSAGES[token]));
      return "unencodable";
    });
    if (outcome !== "drift") return outcome;
  }
  throw postCutoff({ sourcePath: ref.path, baseBytes: 0, prospectiveMaxBytes: 0 });
}

/**
 * Phase 0 candidate transaction in the C9.1.29 precedence: REFERENCE_INVALID → SOURCE_UNENCODABLE → (size, I9d-2) →
 * envelope validators → classification → PAYLOAD_TOO_LARGE (I9d-2) → PROCESSED_INVALID; every committing branch is
 * root-fenced; a retry member of any other shape and a disagreeing quarantine record fail closed with no write.
 */
async function consumeEventEnvelopeInTransaction(db, eventRef, rawNow, run = null) {
  const now = toTimestamp(rawNow);
  const first = await db.runTransaction(async (transaction) => {
    if (run) await requireSchedulerFence(transaction, db, run);
    const eventSnapshot = await transaction.get(eventRef);
    if (!eventSnapshot.exists || eventSnapshot.data()?.processingState !== "pending") return "noop";
    const data = eventSnapshot.data();
    let userId = null;
    try { userId = eventUserId(eventRef); } catch (error) { userId = null; }
    if (userId !== null) await assertDeletionAbsent(transaction, db, [userId]); // C6.1 root fence (every committing branch)

    let digest;
    try {
      digest = originalBytesDigest(data);
    } catch (error) {
      if (error instanceof UnencodableSource) return { unencodable: error.token };
      throw error;
    }
    const retry = validateRetryMember(data.phase0ValidationFailure);
    // C9.1.27/C9.1.28 — the retry-or-terminal envelope precedes every validator; a failure after the cutoff is the invariant
    const sizing = phase0Envelope(eventRef.path, data, now, eventSnapshot.updateTime);
    if (!sizing.admitted) throw postCutoff({ sourcePath: eventRef.path, baseBytes: sizing.baseBytes, prospectiveMaxBytes: sizing.prospectiveMaxBytes });
    const fail = (code) => phase0Failure(transaction, db, eventRef, eventSnapshot, retry, digest, code, now);
    if (userId === null) return fail("REFERENCE_INVALID");

    let envelope;
    try {
      envelope = validateEventEnvelope(data, eventRef.id);
    } catch (error) {
      if (error instanceof EnvelopeError) return fail(error.code);
      throw error;
    }

    const stateId = canonicalEventStateId(envelope.event_name, envelope.canonical_key);
    const stateRef = db.doc(`users/${userId}/eventState/${stateId}`);
    const stateSnapshot = await transaction.get(stateRef);
    const highWater = stateSnapshot.exists ? stateSnapshot.data() : null;
    const outcome = classifyEnvelope(envelope, highWater);
    const fingerprint = fingerprintCanonicalEnvelope(envelope);
    const terminalSource = { ...withoutRetryMember(data), processingState: "terminal", processed: true, processedAt: now, outcome };

    if (outcome === "advance") {
      const stateData = {
        event_name: envelope.event_name,
        canonical_key: envelope.canonical_key,
        source_version: envelope.source_version,
        effect: envelope.effect,
        event_id: envelope.event_id,
        observed_at: Timestamp.fromDate(new Date(envelope.observed_at)),
        source_evidence_id: envelope.source_evidence_id,
        payload: envelope.payload,
        fingerprint,
        advancedAt: now
      };
      // C9.1.29 size predicate: the exact prospective event-state map and terminal source must fit; otherwise PAYLOAD_TOO_LARGE
      const fit = fitsPhase0Transition({ path: eventRef.path, data }, highWater === null ? null : { path: stateRef.path, data: highWater }, { path: eventRef.path, data: terminalSource }, { path: stateRef.path, data: stateData }, null);
      if (!fit.fits) return fail("PAYLOAD_TOO_LARGE");
      transaction.set(stateRef, stateData);
    } else if (!fitsPhase0Transition({ path: eventRef.path, data }, null, { path: eventRef.path, data: terminalSource }, null, null).fits) {
      throw postCutoff({ sourcePath: eventRef.path, baseBytes: storage.documentSize(eventRef.path, data), prospectiveMaxBytes: 0 });
    }
    transaction.update(eventRef, {
      processingState: "terminal",
      processed: true,
      processedAt: now,
      outcome,
      ...(retry !== null ? { phase0ValidationFailure: FieldValue.delete() } : {})
    });
    return outcome;
  });
  if (first !== null && typeof first === "object" && first.unencodable) return terminalizeUnencodable(db, eventRef, first.unencodable, now, run);
  return first;
}

/** Transaction-form event reconcile over an already-read task snapshot. */
async function reconcileEventTaskTx(db, transaction, taskRef, taskSnapshot, now) {
  if (!taskSnapshot.exists) return false;
  const data = taskSnapshot.data();
  const trigger = data?.dispositionContract?.next_trigger;
  if (data?.status !== "Snoozed" || trigger?.kind !== "event" || trigger?.fired === true) {
    return false;
  }
  const userId = taskUserId(taskRef);
  const stateId = canonicalEventStateId(trimmed(trigger.event_name), trimmed(trigger.canonical_key));
  const stateRef = db.doc(`users/${userId}/eventState/${stateId}`);
  const stateSnapshot = await transaction.get(stateRef);
  const highWater = stateSnapshot.exists ? stateSnapshot.data() : null;
  if (!shouldWakeEventTask(data, highWater)) return false;

  const contract = buildUpcomingContract(data.dispositionContract, "Ready to continue");
  validateDispositionContract("Upcoming", contract, now);
  await assertDeletionAbsent(transaction, db, [userId]); // C6.1 root fence
  transaction.update(taskRef, {
    status: "Upcoming",
    dispositionContract: contract,
    snoozedUntil: deleteField()
  });
  return true;
}

async function reconcileEventTaskInTransaction(db, taskRef, rawNow, run = null) {
  const now = toDate(rawNow);
  return db.runTransaction(async (transaction) => {
    if (run) await requireSchedulerFence(transaction, db, run);
    const taskSnapshot = await transaction.get(taskRef);
    return reconcileEventTaskTx(db, transaction, taskRef, taskSnapshot, now);
  });
}


function documentIdField() {
  return FieldPath.documentId();
}

function deleteField() {
  return FieldValue.delete();
}

function isMillisTimestamp(value) {
  return value instanceof Timestamp || (value && typeof value.toMillis === "function" && typeof value.seconds === "number");
}

function plusSeconds(timestamp, seconds) {
  return Timestamp.fromMillis(timestamp.toMillis() + seconds * 1000);
}

function readTimeOf(snapshot, deps) {
  const readTime = snapshot && snapshot.readTime;
  if (isMillisTimestamp(readTime)) return Timestamp.fromMillis(readTime.toMillis());
  if (deps && typeof deps.now === "function") return deps.now();
  throw new SchedulerInvariant("SCHEDULER_READ_TIME_UNAVAILABLE");
}

function safeOrdinal(value) {
  if (!Number.isSafeInteger(value) || value < 0) throw new SchedulerInvariant("SCHEDULER_ORDINAL_ARITHMETIC");
  return value;
}

/** C9.1.3 — runOrdinal from the delivered scheduleTime only; malformed input stops before any write. */
function parseScheduleEvent(event) {
  const raw = event && event.scheduleTime;
  if (typeof raw !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$/.test(raw)) return null;
  const millis = Date.parse(raw);
  if (!Number.isFinite(millis)) return null;
  const scheduledAt = Timestamp.fromMillis(millis);
  return { scheduledAt, runOrdinal: safeOrdinal(Math.floor(scheduledAt.seconds / SCHEDULE_SECONDS)) };
}

function ordinalOf(timestamp) {
  return safeOrdinal(Math.floor(timestamp.seconds / SCHEDULE_SECONDS));
}

function isLegacyLease(lease) {
  return lease !== null && typeof lease === "object" && !Array.isArray(lease) &&
    Object.keys(lease).sort().join(",") === "acquiredAt,expiresAt,runId";
}

function isV2Lease(lease) {
  return lease !== null && typeof lease === "object" && !Array.isArray(lease) &&
    Object.keys(lease).sort().join(",") === "expiresAt,ownerToken,runOrdinal,schemaVersion,startedAt" &&
    lease.schemaVersion === 1 && Number.isSafeInteger(lease.runOrdinal) && typeof lease.ownerToken === "string" &&
    isMillisTimestamp(lease.startedAt) && isMillisTimestamp(lease.expiresAt);
}

function sameLease(a, b) {
  return isV2Lease(a) && isV2Lease(b) && a.runOrdinal === b.runOrdinal && a.ownerToken === b.ownerToken &&
    a.startedAt.toMillis() === b.startedAt.toMillis() && a.expiresAt.toMillis() === b.expiresAt.toMillis();
}

/** C9.1.10 — exact dueObservation grammar (a member of schedulerHealth). */
function validateDueObservation(observation) {
  const invariant = (detail) => new SchedulerInvariant("SCHEDULER_HEALTH_INVARIANT", detail);
  if (observation === null || typeof observation !== "object" || Array.isArray(observation)) throw invariant("dueObservation");
  const keys = Object.keys(observation).sort().join(",");
  const base = "armedDueCandidateCount,countReadTime,observedAt,oldestDueAgeSeconds,oldestReadTime,schemaVersion";
  const withOldest = "armedDueCandidateCount,countReadTime,observedAt,oldestCandidatePath,oldestDueAgeSeconds,oldestReadTime,oldestThresholdAt,schemaVersion";
  if (keys !== base && keys !== withOldest) throw invariant("dueObservation members");
  if (observation.schemaVersion !== 1) throw invariant("dueObservation schemaVersion");
  for (const k of ["observedAt", "countReadTime", "oldestReadTime"]) if (!isMillisTimestamp(observation[k])) throw invariant(`dueObservation ${k}`);
  safeOrdinal(observation.armedDueCandidateCount); safeOrdinal(observation.oldestDueAgeSeconds);
  if (keys === withOldest) {
    if (observation.armedDueCandidateCount < 1 || typeof observation.oldestCandidatePath !== "string" || !observation.oldestCandidatePath || !isMillisTimestamp(observation.oldestThresholdAt)) throw invariant("dueObservation oldest");
  } else if (observation.armedDueCandidateCount !== 0 || observation.oldestDueAgeSeconds !== 0) throw invariant("dueObservation empty");
  return observation;
}

/** C9.1.8 — exact schedulerHealth grammar. */
function validateHealth(health) {
  const invariant = (detail) => new SchedulerInvariant("SCHEDULER_HEALTH_INVARIANT", detail);
  if (health === null || typeof health !== "object" || Array.isArray(health)) throw invariant("map");
  const keys = Object.keys(health).sort();
  const allowed = ["activatedOrdinal", "dueObservation", "lastCompletedOrdinal", "lastStartedOrdinal", "recentRuns", "schemaVersion"];
  if (!keys.every((k) => allowed.includes(k)) || !["activatedOrdinal", "lastStartedOrdinal", "recentRuns", "schemaVersion"].every((k) => keys.includes(k))) throw invariant("members");
  if (health.schemaVersion !== 1) throw invariant("schemaVersion");
  if (health.dueObservation !== undefined) validateDueObservation(health.dueObservation);
  safeOrdinal(health.activatedOrdinal); safeOrdinal(health.lastStartedOrdinal);
  if (health.lastCompletedOrdinal !== undefined) safeOrdinal(health.lastCompletedOrdinal);
  if (!Array.isArray(health.recentRuns) || health.recentRuns.length > RECENT_RUNS) throw invariant("recentRuns");
  let previous = -1;
  for (const run of health.recentRuns) {
    if (run === null || typeof run !== "object") throw invariant("run");
    safeOrdinal(run.runOrdinal);
    if (run.runOrdinal <= previous) throw invariant("order");
    previous = run.runOrdinal;
    if (!isMillisTimestamp(run.scheduledAt) || !isMillisTimestamp(run.startedAt)) throw invariant("run times");
    const runKeys = Object.keys(run).sort().join(",");
    if (run.state === "running") {
      if (runKeys !== "runOrdinal,scheduledAt,startedAt,state") throw invariant("running members");
    } else if (run.state === "completed") {
      if (runKeys !== "completedAt,runOrdinal,scheduledAt,startedAt,state,thresholdWakeLatency") throw invariant("completed members");
      if (!isMillisTimestamp(run.completedAt)) throw invariant("completedAt");
      const latency = run.thresholdWakeLatency;
      if (latency === null || typeof latency !== "object") throw invariant("latency");
      const latencyKeys = Object.keys(latency).sort().join(",");
      if (latency.count === 0) { if (latencyKeys !== "count") throw invariant("latency count:0"); }
      else if (!Number.isSafeInteger(latency.count) || latency.count < 1 || latencyKeys !== "count,maxSeconds,p50Seconds,p95Seconds") throw invariant("latency quantiles");
    } else throw invariant("state");
  }
  return health;
}

function stateRef(db) { return db.doc(STATE_PATH); }
function leaseRef(db) { return db.doc(LEASE_PATH); }
function crossFenceRef(db) { return db.doc(CROSS_FENCE_PATH); }
function alertRef(db, alertId) { return db.doc(`${ALERTS_COLLECTION}/${alertId}`); }

function emit(deps, code, counts) { if (typeof deps.log === "function") deps.log(code, counts || {}); }
function metric(deps, name, value) { if (typeof deps.metric === "function") deps.metric(name, value); }

// ---------------------------------------------------------------------------
// C9.1.5 — initialization tooling (schedule disabled)
// ---------------------------------------------------------------------------

async function initializeScheduler(deps) {
  const { db } = deps;
  return db.runTransaction(async (transaction) => {
    const [leaseSnapshot, stateSnapshot] = [await transaction.get(leaseRef(db)), await transaction.get(stateRef(db))];
    const state = stateSnapshot.exists ? stateSnapshot.data() : {};
    if (state.schedulerHealth !== undefined) throw new SchedulerInvariant("SCHEDULER_ROLLOUT_BLOCKED", "health present");
    const lease = leaseSnapshot.exists ? leaseSnapshot.data() : null;
    if (lease !== null && !isLegacyLease(lease)) throw new SchedulerInvariant("SCHEDULER_ROLLOUT_BLOCKED", "lease shape");
    const R = readTimeOf(stateSnapshot, deps);
    const activatedOrdinal = safeOrdinal(ordinalOf(R) + 1);
    const health = { schemaVersion: 1, activatedOrdinal, lastStartedOrdinal: activatedOrdinal - 1, recentRuns: [] };
    validateHealth(health);
    if (lease !== null) transaction.delete(leaseRef(db));
    transaction.set(stateRef(db), { schedulerHealth: health }, { merge: true });
    return { activatedOrdinal };
  });
}

// ---------------------------------------------------------------------------
// C9.1.6 — acquisition; C9.1.16 — MIG-TRIGGER-V1; C9.1.7 — fence
// ---------------------------------------------------------------------------

function ordinalFloorOf(health) {
  return Math.max(health.lastStartedOrdinal, health.lastCompletedOrdinal ?? (health.activatedOrdinal - 1));
}

async function acquireScheduler(deps, schedule) {
  const { db } = deps;
  const ownerToken = randomUUID().toLowerCase();
  return db.runTransaction(async (transaction) => {
    const leaseSnapshot = await transaction.get(leaseRef(db));
    const stateSnapshot = await transaction.get(stateRef(db));
    const crossFence = await transaction.get(crossFenceRef(db));
    if (crossFence.exists) return { refused: "CROSS_FENCE_PRESENT" };
    const state = stateSnapshot.exists ? stateSnapshot.data() : {};
    if (state.schedulerHealth === undefined) return { refused: "SCHEDULER_UNINITIALIZED" };
    const health = validateHealth(state.schedulerHealth);
    const floor = ordinalFloorOf(health);
    if (schedule.runOrdinal <= floor) return { refused: "ORDINAL_NOT_ABOVE_FLOOR" };
    const leaseNow = readTimeOf(stateSnapshot, deps);
    const lease = leaseSnapshot.exists ? leaseSnapshot.data() : null;
    let migrated = false;
    if (lease !== null) {
      if (isV2Lease(lease)) {
        if (lease.expiresAt.toMillis() > leaseNow.toMillis()) return { refused: "LEASE_HELD" };
      } else if (isLegacyLease(lease)) {
        migrated = true;
      } else {
        throw new SchedulerInvariant("SCHEDULER_LEASE_INVARIANT", "shape");
      }
    }
    const foreign = Object.keys(state).filter((k) => !STATE_KEYS.includes(k) && !LEGACY_RESIDUE_KEYS.includes(k));
    if (foreign.length) throw new SchedulerInvariant("SCHEDULER_STATE_INVARIANT", "foreign key");
    const residue = Object.keys(state).filter((k) => LEGACY_RESIDUE_KEYS.includes(k));
    for (const key of CURSOR_KEYS) {
      const cursor = state[key];
      if (cursor === undefined) continue;
      if (cursor === null || typeof cursor !== "object" || typeof cursor.path !== "string" || !cursor.path) throw new SchedulerInvariant("SCHEDULER_STATE_INVARIANT", "cursor shape");
    }
    if (residue.length) migrated = true;
    const nextLease = { schemaVersion: 1, runOrdinal: schedule.runOrdinal, ownerToken, startedAt: leaseNow, expiresAt: plusSeconds(leaseNow, LEASE_SECONDS) };
    const effectiveLast = health.lastCompletedOrdinal ?? (health.activatedOrdinal - 1);
    const missingBeforeThisRun = safeOrdinal(schedule.runOrdinal - effectiveLast - 1);
    const recentRuns = [...health.recentRuns, { runOrdinal: schedule.runOrdinal, scheduledAt: schedule.scheduledAt, startedAt: leaseNow, state: "running" }].slice(-RECENT_RUNS);
    const nextHealth = { ...health, lastStartedOrdinal: schedule.runOrdinal, recentRuns };
    validateHealth(nextHealth);
    const update = { schedulerHealth: nextHealth };
    for (const key of residue) update[key] = FieldValue.delete();
    transaction.set(leaseRef(db), nextLease);
    transaction.update(stateRef(db), update);
    return {
      lease: nextLease, runOrdinal: schedule.runOrdinal, scheduledAt: schedule.scheduledAt, leaseNow, runNow: leaseNow,
      effectiveLast, missingBeforeThisRun, migrated, cursors: Object.fromEntries(CURSOR_KEYS.filter((k) => state[k] !== undefined).map((k) => [k, state[k]])),
      lastCompletedAbsent: health.lastCompletedOrdinal === undefined
    };
  });
}

/** C9.1.7 — every scheduler-owned mutation first reads the lease and requires the captured tuple, unexpired at that read. */
async function requireSchedulerFence(transaction, db, run) {
  const snapshot = await transaction.get(leaseRef(db));
  const current = snapshot.exists ? snapshot.data() : null;
  if (!sameLease(current, run.lease)) throw new SchedulerInvariant("SCHEDULER_FENCE_LOST", "tuple");
  const readTime = readTimeOf(snapshot, run.deps);
  if (run.lease.expiresAt.toMillis() <= readTime.toMillis()) throw new SchedulerInvariant("SCHEDULER_FENCE_LOST", "expired");
  return readTime;
}

function fenced(deps, run, fn) {
  return deps.db.runTransaction(async (transaction) => {
    const readTime = await requireSchedulerFence(transaction, deps.db, run);
    return fn(transaction, readTime);
  });
}

async function releaseScheduler(deps, run) {
  const { db } = deps;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(leaseRef(db));
    if (snapshot.exists && sameLease(snapshot.data(), run.lease)) transaction.delete(leaseRef(db));
  });
}

// ---------------------------------------------------------------------------
// C9.1.11 — Phase-2b condition slots
// ---------------------------------------------------------------------------

function slotInvariant(detail) { return new SchedulerInvariant("SCHEDULER_ALERT_SLOT_INVARIANT", detail); }

async function observeCondition(deps, run, alertId, condition, payload, lane) {
  return fenced(deps, run, async (transaction, readTime) => {
    const ref = alertRef(deps.db, alertId);
    const snapshot = await transaction.get(ref);
    const at = run.runNow;
    if (!snapshot.exists) {
      const listing = await transaction.get(deps.db.collection(ALERTS_COLLECTION).orderBy(documentIdField()).limit(ALERT_SLOT_BOUND + 1));
      if (listing.size >= ALERT_SLOT_BOUND) throw slotInvariant("twelfth slot");
      const row = { schemaVersion: 1, condition, ...(lane ? { lane } : {}), firstObservedAt: at, lastObservedAt: at, firstObservedOrdinal: run.runOrdinal, lastObservedOrdinal: run.runOrdinal, occurrenceCount: 1, ...payload };
      transaction.set(ref, row);
      emit(deps, `PHASE2B_${condition}`, { occurrenceCount: 1 });
      return "created";
    }
    const current = snapshot.data();
    if (current.condition !== condition || (lane !== undefined && current.lane !== lane)) throw slotInvariant("condition");
    if (!Number.isSafeInteger(current.lastObservedOrdinal) || current.lastObservedOrdinal > run.runOrdinal) throw slotInvariant("ordinal");
    if (current.lastObservedOrdinal === run.runOrdinal) {
      const same = Object.entries(payload).every(([k, v]) => JSON.stringify(current[k]) === JSON.stringify(v));
      if (!same) throw slotInvariant("same-ordinal disagreement");
      return "unchanged";
    }
    const occurrenceCount = safeOrdinal(current.occurrenceCount + 1);
    transaction.update(ref, { ...payload, lastObservedAt: at, lastObservedOrdinal: run.runOrdinal, occurrenceCount });
    emit(deps, `PHASE2B_${condition}`, { occurrenceCount });
    return "updated";
  });
}

async function clearCondition(deps, run, alertId) {
  return fenced(deps, run, async (transaction) => {
    const ref = alertRef(deps.db, alertId);
    const snapshot = await transaction.get(ref);
    if (snapshot.exists) transaction.delete(ref);
  });
}

// ---------------------------------------------------------------------------
// C9.1.14 / C9.1.16 / C9.1.17 — paging, cursors, admission deadlines
// ---------------------------------------------------------------------------

function elapsedSeconds(run) {
  return run.deps.elapsedSeconds ? run.deps.elapsedSeconds() : (process.hrtime.bigint() - run.startedMonotonic) / 1_000_000_000n;
}

/** Runs `candidates` in concurrency-10 waves; stops starting waves after `deadline` seconds. Returns per-candidate outcomes. */
async function runWaves(run, candidates, deadline, operation) {
  const outcomes = new Array(candidates.length).fill(undefined);
  for (let start = 0; start < candidates.length; start += WORK_LIMIT) {
    if (Number(elapsedSeconds(run)) >= deadline) break;
    const wave = candidates.slice(start, start + WORK_LIMIT);
    const results = await Promise.all(wave.map(async (candidate) => {
      try { return { ok: true, value: await operation(candidate) }; }
      catch (error) { return { ok: false, code: error && error.code, fields: error && error.fields }; }
    }));
    results.forEach((r, i) => { outcomes[start + i] = r; });
  }
  return outcomes;
}

async function writeCursor(deps, run, key, cursor) {
  return fenced(deps, run, async (transaction) => {
    transaction.update(stateRef(deps.db), { [key]: cursor === null ? FieldValue.delete() : cursor });
  });
}

/** Phase 0: pending event envelopes, exact 100/101, persisted full-path cursor. */
async function runPhase0(deps, run) {
  const { db } = deps;
  let query = db.collectionGroup("events").where("processingState", "==", "pending").orderBy(documentIdField(), "asc");
  const cursor = run.cursors[PHASE0_CURSOR_KEY];
  if (cursor) query = query.startAfter(db.doc(cursor.path));
  const snapshot = await query.limit(PHASE0_SELECT + 1).get();
  const selected = snapshot.docs.slice(0, PHASE0_SELECT);
  const outcomes = await runWaves(run, selected, PHASE0_DEADLINE, (candidate) => consumeEventEnvelopeInTransaction(db, candidate.ref, run.runNow, run));
  if (outcomes.some((o) => o !== undefined && !o.ok && o.code === "SCHEDULER_FENCE_LOST")) throw new SchedulerInvariant("SCHEDULER_FENCE_LOST");
  const emitted = new Set();
  for (const o of outcomes) {
    if (o === undefined || o.ok || typeof o.code !== "string") continue;
    if (o.code === "POST_CUTOFF_SOURCE_SIZE_INVARIANT") {
      emit(deps, o.code, { ...(o.fields || {}), runOrdinal: run.runOrdinal });
      metric(deps, "phase2/post_cutoff_source_size_invariant_count", 1);
    } else if (!emitted.has(o.code)) { emitted.add(o.code); emit(deps, o.code); }
  }
  const settled = outcomes.every((o) => o !== undefined && o.ok);
  if (!settled) return { lane: PHASE0_CURSOR_KEY, examined: selected.length, settled: false };
  if (snapshot.docs.length > PHASE0_SELECT) await writeCursor(deps, run, PHASE0_CURSOR_KEY, { path: selected.at(-1).ref.path });
  else if (cursor) await writeCursor(deps, run, PHASE0_CURSOR_KEY, null);
  return { lane: PHASE0_CURSOR_KEY, examined: selected.length, settled: true, outcomes: outcomes.map((o) => o.value) };
}

/** Ordinary lanes: (status, kind, fired, [at]) under the lane's select mask; the caller applies the page limit. */
function ordinaryQuery(db, lane, run) {
  let query = db.collectionGroup("tasks")
    .where("status", "==", lane.status)
    .where("dispositionContract.next_trigger.kind", "==", lane.kind)
    .where("dispositionContract.next_trigger.fired", "==", false);
  if (lane.kind === "date") {
    query = query.where("dispositionContract.next_trigger.at", "<=", run.runNow).orderBy("dispositionContract.next_trigger.at", "asc").orderBy(documentIdField(), "asc");
  } else {
    query = query.orderBy(documentIdField(), "asc");
  }
  const cursor = run.cursors[lane.lane];
  if (cursor) query = lane.kind === "date" ? query.startAfter(cursor.at, db.doc(cursor.path)) : query.startAfter(db.doc(cursor.path));
  return query.select(...laneMask(lane));
}

/** H55 branch (C9.3.11 policy-absent rows): Snoozed lanes wake through the Phase 1 reducers; other policy-absent rows are definitive no-ops. */
function ordinaryReducerFor(lane, run) {
  return async (transaction, snapshot) => {
    if (lane.status !== "Snoozed") return { woke: false };
    const now = toDate(run.runNow);
    const woke = lane.kind === "date"
      ? await wakeDateTaskTx(run.deps.db, transaction, snapshot.ref, snapshot, now)
      : await reconcileEventTaskTx(run.deps.db, transaction, snapshot.ref, snapshot, now);
    return { woke };
  };
}

/**
 * C9.3.11 threshold-scan reread over the complete document: owner fence, exact armed projection due at runNow. The
 * intent-producing branches require the task's current policy state, deadline evidence, and the intent registry
 * (S6 / I10); with none of those surfaces present the row is a definitive no-op, and a stale or attended projection
 * is refreshed only by its owning reducer.
 */
function thresholdReducerFor(run) {
  return async (transaction, snapshot) => {
    await assertDeletionAbsent(transaction, run.deps.db, [taskUserId(snapshot.ref)]);
    const projection = snapshot.get("thresholdProjection");
    const at = projection && projection.threshold_at;
    if (!projection || projection.state !== "armed" || !isMillisTimestamp(at) || at.toMillis() > run.runNow.toMillis()) return { woke: false };
    return { woke: false, thresholdAt: at };
  };
}

// ---------------------------------------------------------------------------
// C9.1.10 / C9.1.12 — due observation and catch-up
// ---------------------------------------------------------------------------

/** The exact candidate superset: armed projections due at or before `cutoff`. */
function dueSupersetQuery(db, cutoff) {
  return db.collectionGroup("tasks")
    .where("thresholdProjection.state", "==", "armed")
    .where("thresholdProjection.threshold_at", "<=", cutoff);
}

/** C9.1.10 — count first, oldest second, separate read times; a disagreeing pair or a failed query stops the evaluation. */
async function observeDue(deps, run) {
  const { db } = deps;
  const observationNow = deps.now();
  let countSnapshot;
  let oldestSnapshot;
  let count;
  let oldest;
  try {
    countSnapshot = await dueSupersetQuery(db, observationNow).count().get();
    count = countSnapshot.data().count;
    oldestSnapshot = await dueSupersetQuery(db, observationNow)
      .orderBy("thresholdProjection.threshold_at", "asc").orderBy(documentIdField(), "asc").select(...THRESHOLD_MASK).limit(1).get();
    oldest = oldestSnapshot.docs[0];
  } catch (error) {
    throw new SchedulerInvariant("SCHEDULER_OBSERVATION_FAILED");
  }
  if (!Number.isSafeInteger(count) || (count === 0) !== (oldest === undefined)) throw new SchedulerInvariant("SCHEDULER_OBSERVATION_RACE");
  const observation = {
    schemaVersion: 1, observedAt: observationNow, countReadTime: readTimeOf(countSnapshot, deps), oldestReadTime: readTimeOf(oldestSnapshot, deps),
    armedDueCandidateCount: count, oldestDueAgeSeconds: 0
  };
  if (oldest !== undefined) {
    const at = oldest.get("thresholdProjection.threshold_at");
    if (!isMillisTimestamp(at)) throw new SchedulerInvariant("SCHEDULER_OBSERVATION_RACE");
    observation.oldestCandidatePath = oldest.ref.path;
    observation.oldestThresholdAt = at;
    observation.oldestDueAgeSeconds = Math.max(0, Math.floor((observationNow.toMillis() - at.toMillis()) / 1000));
  }
  validateDueObservation(observation);
  await fenced(deps, run, async (transaction) => {
    const snapshot = await transaction.get(stateRef(db));
    const health = validateHealth(snapshot.data().schedulerHealth);
    const next = validateHealth({ ...health, dueObservation: observation });
    transaction.update(stateRef(db), { schedulerHealth: next });
  });
  return observation;
}

/** C9.1.19 aggregate: eligible refusals for one lane at `ordinal` (never materialized). */
async function eligibleRefusalCount(db, lane, ordinal) {
  const snapshot = await db.collectionGroup("schedulerRefusals").where("lane", "==", lane).where("nextEligibleOrdinal", "<=", ordinal).count().get();
  return safeOrdinal(snapshot.data().count);
}

/** C9.1.12 — evaluated only after the observations and the eligible-refusal aggregate are read. */
function decideCatchUp(run, observation, eligibleThresholdRefusalCount) {
  const catchUp = run.lastCompletedAbsent || run.missingBeforeThisRun >= 1 || eligibleThresholdRefusalCount > 0
    || (observation.oldestCandidatePath !== undefined && observation.oldestDueAgeSeconds > CATCH_UP_AGE_SECONDS);
  const thresholdAdmissionCapacity = catchUp ? THRESHOLD_CAPACITY_CATCH_UP : THRESHOLD_CAPACITY_CONTIGUOUS;
  return { catchUp, thresholdAdmissionCapacity, thresholdRefusalCeiling: catchUp ? 200 : 100 };
}

// ---------------------------------------------------------------------------
// C9.1.18 / C9.1.19 / C9.1.20 — durable refusals, eligible retry admission, cursor-pass branches
// ---------------------------------------------------------------------------

class RefusalSignal extends Error {
  constructor(reasonCode) { super(reasonCode); this.refusalReason = reasonCode; }
}

function sha256Hex(text) { return createHash("sha256").update(text).digest("hex"); }

function refusalId(lane, candidatePath) {
  return `srf1_${sha256Hex(canonicalJSON({ domain: "scheduler_refusal.v1", lane, candidate_path: candidatePath })).slice(0, 40)}`;
}

function refusalRefFor(db, lane, candidatePath) {
  const parts = typeof candidatePath === "string" ? candidatePath.split("/") : [];
  if (parts.length !== 4 || parts[0] !== "users" || parts[2] !== "tasks" || !parts[1] || !parts[3]) throw new SchedulerInvariant("SCHEDULER_REFUSAL_INVARIANT", "candidatePath");
  return db.doc(`users/${parts[1]}/schedulerRefusals/${refusalId(lane.lane, candidatePath)}`);
}

/** C9.1.17 select() mask per lane: exactly filter fields, order fields, task_generation_epoch, task_instance_id. */
function laneMask(lane) {
  if (lane.kind === "threshold") return THRESHOLD_MASK;
  return ["status", "dispositionContract.next_trigger.kind", "dispositionContract.next_trigger.fired", ...(lane.kind === "date" ? ["dispositionContract.next_trigger.at"] : []), "task_generation_epoch", "task_instance_id"];
}

/** The lane's complete field-mask result with explicit missing tags. */
function selectedIdentity(lane, snapshot) {
  const identity = {};
  for (const field of laneMask(lane)) {
    const value = snapshot.get(field);
    identity[field] = value === undefined ? { missing: true } : value;
  }
  return identity;
}

function documentUpdateTime(snapshot) {
  const updateTime = snapshot.updateTime;
  return isMillisTimestamp(updateTime) ? { seconds: updateTime.seconds, nanos: updateTime.nanoseconds } : { missing: true };
}

/** C9.1.18 — SHA-256(TaskCanonicalV1({lane,candidate_path,document_update_time,selected_identity})); no domain member. */
function candidateFingerprint(lane, snapshot) {
  return sha256Hex(canonicalJSON({ lane: lane.lane, candidate_path: snapshot.ref.path, document_update_time: documentUpdateTime(snapshot), selected_identity: selectedIdentity(lane, snapshot) }));
}

/** C9.1.18 — exact record grammar and the valid-row invariants; any violation fails closed. */
function validateRefusal(record, lane, candidatePath, id) {
  const invariant = (detail) => new SchedulerInvariant("SCHEDULER_REFUSAL_INVARIANT", detail);
  if (record === null || typeof record !== "object" || Array.isArray(record)) throw invariant("map");
  const keys = Object.keys(record).sort().join(",");
  if (keys !== "candidateFingerprint,candidatePath,firstRefusedAt,firstRefusedOrdinal,lane,lastAttemptOrdinal,lastRefusedAt,nextEligibleOrdinal,reasonCode,refusalCount,saturated,schemaVersion") throw invariant("members");
  if (record.schemaVersion !== 1) throw invariant("schemaVersion");
  if (record.lane !== lane.lane || record.candidatePath !== candidatePath || id !== refusalId(lane.lane, candidatePath)) throw invariant("identity");
  if (typeof record.candidateFingerprint !== "string" || !/^[0-9a-f]{64}$/.test(record.candidateFingerprint)) throw invariant("fingerprint");
  if (!REFUSAL_REASONS.includes(record.reasonCode)) throw invariant("reasonCode");
  for (const k of ["firstRefusedOrdinal", "lastAttemptOrdinal", "nextEligibleOrdinal"]) if (!Number.isSafeInteger(record[k]) || record[k] < 0) throw invariant(k);
  if (!Number.isSafeInteger(record.refusalCount) || record.refusalCount < 1 || record.refusalCount > REFUSAL_MAX_COUNT) throw invariant("refusalCount");
  if (record.saturated !== (record.refusalCount === REFUSAL_MAX_COUNT)) throw invariant("saturated");
  if (!(record.firstRefusedOrdinal <= record.lastAttemptOrdinal && record.lastAttemptOrdinal < record.nextEligibleOrdinal)) throw invariant("ordinals");
  if (!isMillisTimestamp(record.firstRefusedAt) || !isMillisTimestamp(record.lastRefusedAt) || record.firstRefusedAt.toMillis() > record.lastRefusedAt.toMillis()) throw invariant("times");
  return record;
}

function refusalReasonOf(error) {
  if (error instanceof RefusalSignal) return error.refusalReason;
  if (error && error.details && error.details.reason === "ACCOUNT_DELETION_FENCED") return "AUTHORITY_REFUSAL";
  if (error && error.code === 10) return "TRANSACTION_RETRY_EXHAUSTED";
  return "VALIDATION_REFUSAL";
}

/** Branch (2): exact refusal create/update after rereading the candidate identity (its own fenced bookkeeping transaction). */
async function recordRefusal(deps, run, lane, ref, reasonCode) {
  const { db } = deps;
  const rref = refusalRefFor(db, lane, ref.path);
  return fenced(deps, run, async (transaction) => {
    const refusalSnapshot = await transaction.get(rref);
    const snapshot = await transaction.get(ref);
    const existing = refusalSnapshot.exists ? validateRefusal(refusalSnapshot.data(), lane, ref.path, rref.id) : null;
    if (!snapshot.exists) { if (existing) transaction.delete(rref); return { kind: "absent" }; }
    const fingerprint = candidateFingerprint(lane, snapshot);
    const ordinal = run.runOrdinal;
    const now = run.runNow;
    let next;
    if (existing && existing.candidateFingerprint === fingerprint && existing.reasonCode === reasonCode) {
      if (existing.lastAttemptOrdinal >= ordinal) throw new SchedulerInvariant("SCHEDULER_REFUSAL_INVARIANT", "nonmonotonic");
      const refusalCount = Math.min(REFUSAL_MAX_COUNT, existing.refusalCount + 1);
      next = { ...existing, lastAttemptOrdinal: ordinal, lastRefusedAt: now, refusalCount, saturated: refusalCount === REFUSAL_MAX_COUNT, nextEligibleOrdinal: ordinal + Math.min(2 ** (refusalCount - 1), REFUSAL_MAX_BACKOFF) };
    } else {
      next = { schemaVersion: 1, lane: lane.lane, candidatePath: ref.path, candidateFingerprint: fingerprint, firstRefusedOrdinal: ordinal, lastAttemptOrdinal: ordinal, nextEligibleOrdinal: ordinal + 1, refusalCount: 1, saturated: false, reasonCode, firstRefusedAt: now, lastRefusedAt: now };
    }
    validateRefusal(next, lane, ref.path, rref.id);
    transaction.set(rref, next);
    return { kind: "refused", reasonCode, refusalCount: next.refusalCount };
  });
}

/**
 * Fresh admission (C9.1.19/C9.1.20): fenced; reads the deterministic refusal path and the complete candidate; branch (3)
 * for an absent candidate, branch (4) for an extant same-fingerprint refusal, IDENTITY_RACE when the captured identity
 * moved, obsolete stale-fingerprint authority removed before the candidate consumes this fresh slot; any refusal
 * becomes branch (2) bookkeeping.
 */
async function admitFresh(deps, run, lane, candidate, reducer) {
  const { db } = deps;
  const rref = refusalRefFor(db, lane, candidate.ref.path);
  try {
    return await db.runTransaction(async (transaction) => {
      await requireSchedulerFence(transaction, db, run);
      const refusalSnapshot = await transaction.get(rref);
      const snapshot = await transaction.get(candidate.ref);
      const refusal = refusalSnapshot.exists ? validateRefusal(refusalSnapshot.data(), lane, candidate.ref.path, rref.id) : null;
      if (!snapshot.exists) { if (refusal) transaction.delete(rref); return { kind: "absent" }; }
      const current = candidateFingerprint(lane, snapshot);
      if (refusal && refusal.candidateFingerprint === current) return { kind: "extant" };
      if (current !== candidate.fingerprint) throw new RefusalSignal("IDENTITY_RACE");
      if (refusal) transaction.delete(rref);
      const result = await reducer(transaction, snapshot);
      return { kind: result && result.woke ? "woke" : "noop", thresholdAt: result ? result.thresholdAt : undefined };
    });
  } catch (error) {
    if (error instanceof SchedulerInvariant) throw error;
    return recordRefusal(deps, run, lane, candidate.ref, refusalReasonOf(error));
  }
}

function eligibleRetryQuery(db, lane, ordinal) {
  return db.collectionGroup("schedulerRefusals")
    .where("lane", "==", lane.lane)
    .where("nextEligibleOrdinal", "<=", ordinal)
    .orderBy("nextEligibleOrdinal", "asc").orderBy("firstRefusedOrdinal", "asc").orderBy("lastAttemptOrdinal", "asc").orderBy(documentIdField(), "asc");
}

/** Ordered eligible pages (run-local 50/51, no persisted cursor) until `wanted` deduplicated refusals are collected. */
async function collectRetries(db, lane, ordinal, wanted) {
  let collected = [];
  const seen = new Set();
  let cursor = null;
  while (collected.length < wanted) {
    let query = eligibleRetryQuery(db, lane, ordinal);
    if (cursor) query = query.startAfter(cursor.nextEligibleOrdinal, cursor.firstRefusedOrdinal, cursor.lastAttemptOrdinal, cursor.ref);
    const page = await query.limit(RETRY_SELECT + 1).get();
    const selected = page.docs.slice(0, RETRY_SELECT);
    for (const doc of selected) {
      const key = `${String(doc.get("candidatePath"))}\n${String(doc.get("candidateFingerprint"))}`;
      if (seen.has(key)) continue;
      seen.add(key);
      collected = [...collected, doc];
      if (collected.length >= wanted) break;
    }
    if (page.docs.length <= RETRY_SELECT || selected.length === 0) break;
    const last = selected.at(-1);
    cursor = { nextEligibleOrdinal: last.get("nextEligibleOrdinal"), firstRefusedOrdinal: last.get("firstRefusedOrdinal"), lastAttemptOrdinal: last.get("lastAttemptOrdinal"), ref: last.ref };
  }
  return collected;
}

/** Retry reread: refusal and candidate together; missing/changed deletes the obsolete authority; success or definitive no-op deletes atomically; another refusal updates it. */
async function retryRefusal(deps, run, lane, refusalDoc, reducer) {
  const { db } = deps;
  const candidatePath = refusalDoc.get("candidatePath");
  const rref = refusalRefFor(db, lane, candidatePath);
  if (rref.path !== refusalDoc.ref.path) throw new SchedulerInvariant("SCHEDULER_REFUSAL_INVARIANT", "derived path");
  const ref = db.doc(candidatePath);
  try {
    return await db.runTransaction(async (transaction) => {
      await requireSchedulerFence(transaction, db, run);
      const refusalSnapshot = await transaction.get(rref);
      if (!refusalSnapshot.exists) return { kind: "retry_missing" };
      const refusal = validateRefusal(refusalSnapshot.data(), lane, candidatePath, rref.id);
      const snapshot = await transaction.get(ref);
      if (!snapshot.exists) { transaction.delete(rref); return { kind: "absent" }; }
      if (candidateFingerprint(lane, snapshot) !== refusal.candidateFingerprint) { transaction.delete(rref); return { kind: "changed" }; }
      const result = await reducer(transaction, snapshot);
      transaction.delete(rref);
      return { kind: result && result.woke ? "woke" : "noop", thresholdAt: result ? result.thresholdAt : undefined };
    });
  } catch (error) {
    if (error instanceof SchedulerInvariant) throw error;
    return recordRefusal(deps, run, lane, ref, refusalReasonOf(error));
  }
}

/** C9.1.11 FAIRNESS_CAPACITY_EXCEEDED: eligible count above the applicable ceiling (100 contiguous, 200 catch-up); never the observed count. */
async function observeFairness(deps, run, laneToken, eligibleCount, result) {
  const alertId = ALERT_FAIRNESS_PREFIX + laneToken;
  if (eligibleCount > run.refusalCeiling) {
    await observeCondition(deps, run, alertId, "FAIRNESS_CAPACITY_EXCEEDED", { eligibleRefusalCount: eligibleCount, refusalCapacity: run.refusalCeiling }, laneToken);
    result.fairnessExceeded = true;
    run.objective = false;
  } else {
    await clearCondition(deps, run, alertId);
  }
}

/** Folds wave outcomes into the lane result and the run-local settled map; returns whether the page settled. */
function tally(outcomes, items, pathOf, settled, result, source) {
  let unsettled = false;
  let invariant = null;
  outcomes.forEach((outcome, index) => {
    if (outcome === undefined || !outcome.ok) { unsettled = true; if (outcome && outcome.code) invariant = outcome.code; return; }
    const path = pathOf(items[index]);
    const kind = outcome.value.kind;
    if (source === "retried") result.retried += 1;
    if (kind === "woke" || kind === "noop" || kind === "absent") {
      settled.set(path, null);
      if (kind === "woke") { result.woke += 1; if (outcome.value.thresholdAt) result.committed = [...result.committed, { path, thresholdAt: outcome.value.thresholdAt }]; }
      if (source === "fresh") result.admitted += 1;
    } else if (kind === "refused") { result.refused += 1; settled.set(path, null); }
    else if (kind === "extant") { result.extant += 1; settled.set(path, null); }
  });
  return { unsettled, invariant };
}

function laneResult(lane, eligibleRefusalCount, retryReserve) {
  return { lane: lane.lane, eligibleRefusalCount, retryReserve, retried: 0, admitted: 0, examined: 0, extant: 0, refused: 0, woke: 0, committed: [], settled: false };
}

function isSettled(settled, path, fingerprint) {
  if (!settled.has(path)) return false;
  const known = settled.get(path);
  return known === null || known === fingerprint;
}

/** Ordinary lane: retries first (reserve 10 of 50, both transfer directions), then the fresh page shrunk by the retries admitted; checkpoint on the last fresh row iff one more exists. */
async function runOrdinaryLane(deps, run, lane) {
  const { db } = deps;
  const ceiling = ORDINARY_SELECT;
  const eligible = await eligibleRefusalCount(db, lane.lane, run.runOrdinal);
  const result = laneResult(lane, eligible, ORDINARY_RETRY_RESERVE);
  await observeFairness(deps, run, lane.lane, eligible, result);
  const retries = await collectRetries(db, lane, run.runOrdinal, Math.min(eligible, ceiling));
  let retryShare = Math.min(ORDINARY_RETRY_RESERVE, retries.length);
  const freshLimit = ceiling - retryShare;
  const snapshot = await ordinaryQuery(db, lane, run).limit(freshLimit + 1).get();
  const selected = snapshot.docs.slice(0, freshLimit);
  result.examined = selected.length;
  if (selected.length < freshLimit) retryShare = Math.min(retries.length, ceiling - selected.length);
  const settled = new Map();
  const reducer = ordinaryReducerFor(lane, run);
  const retryItems = retries.slice(0, retryShare);
  const retryOutcomes = await runWaves(run, retryItems, lane.deadline, (doc) => retryRefusal(deps, run, lane, doc, reducer));
  if (retryOutcomes.some((o) => o !== undefined && !o.ok && o.code === "SCHEDULER_FENCE_LOST")) throw new SchedulerInvariant("SCHEDULER_FENCE_LOST");
  const retryTally = tally(retryOutcomes, retryItems, (doc) => doc.get("candidatePath"), settled, result, "retried");
  const candidates = selected.map((doc) => ({ ref: doc.ref, fingerprint: candidateFingerprint(lane, doc) })).filter((c) => !isSettled(settled, c.ref.path, c.fingerprint));
  const freshOutcomes = await runWaves(run, candidates, lane.deadline, (candidate) => admitFresh(deps, run, lane, candidate, reducer));
  if (freshOutcomes.some((o) => o !== undefined && !o.ok && o.code === "SCHEDULER_FENCE_LOST")) throw new SchedulerInvariant("SCHEDULER_FENCE_LOST");
  const freshTally = tally(freshOutcomes, candidates, (c) => c.ref.path, settled, result, "fresh");
  const invariant = retryTally.invariant || freshTally.invariant;
  if (invariant) emit(deps, invariant);
  if (retryTally.unsettled || freshTally.unsettled) return result;
  const last = selected.at(-1);
  if (snapshot.docs.length > freshLimit && last) {
    const cursor = { path: last.ref.path };
    if (lane.kind === "date") cursor.at = last.get("dispositionContract.next_trigger.at");
    await writeCursor(deps, run, lane.lane, cursor);
  } else if (run.cursors[lane.lane]) {
    await writeCursor(deps, run, lane.lane, null);
  }
  result.settled = true;
  return result;
}

/** C9.1.14 / C9.1.15 / C9.1.19 — threshold lane: retries from half the ceiling first, then run-local 50/51 paging to a fixed point; leftover capacity transfers back to retries. */
async function runThresholdLane(deps, run, observation, capacity, eligible) {
  const { db } = deps;
  const lane = THRESHOLD_LANE_SPEC;
  const cutoff = observation.observedAt;
  const reserve = capacity / 2;
  const result = laneResult(lane, eligible, reserve);
  result.passes = 0;
  result.pages = [];
  await observeFairness(deps, run, lane.lane, eligible, result);
  const settled = new Map();
  const reducer = thresholdReducerFor(run);
  const retries = await collectRetries(db, lane, run.runOrdinal, Math.min(eligible, capacity));
  const runRetries = async (items) => {
    const outcomes = await runWaves(run, items, lane.deadline, (doc) => retryRefusal(deps, run, lane, doc, reducer));
    if (outcomes.some((o) => o !== undefined && !o.ok && o.code === "SCHEDULER_FENCE_LOST")) throw new SchedulerInvariant("SCHEDULER_FENCE_LOST");
    const t = tally(outcomes, items, (doc) => doc.get("candidatePath"), settled, result, "retried");
    if (t.invariant) emit(deps, t.invariant);
    return !t.unsettled;
  };
  const firstShare = Math.min(reserve, retries.length);
  if (!(await runRetries(retries.slice(0, firstShare)))) return result;
  const consumed = () => result.retried + result.admitted + result.refused;
  const scanExceeded = async () => {
    await observeCondition(deps, run, ALERT_THRESHOLD_SCAN, "THRESHOLD_SCAN_CAPACITY_EXCEEDED", { thresholdCutoff: cutoff, candidateCountLowerBound: capacity + 1, admissionCapacity: capacity });
    result.scanCapacityExceeded = true;
    return result;
  };
  for (;;) {
    result.passes += 1;
    let cursor = null;
    let newInPass = 0;
    for (;;) {
      if (Number(elapsedSeconds(run)) >= THRESHOLD_DEADLINE) { result.deadline = true; return result; }
      let query = dueSupersetQuery(db, cutoff).orderBy("thresholdProjection.threshold_at", "asc").orderBy(documentIdField(), "asc").select(...THRESHOLD_MASK);
      if (cursor) query = query.startAfter(cursor.at, db.doc(cursor.path));
      const page = await query.limit(THRESHOLD_SELECT + 1).get();
      const selected = page.docs.slice(0, THRESHOLD_SELECT);
      result.pages = [...result.pages, selected.length];
      const fresh = selected.map((doc) => ({ ref: doc.ref, fingerprint: candidateFingerprint(lane, doc) })).filter((c) => !isSettled(settled, c.ref.path, c.fingerprint));
      const remaining = capacity - consumed();
      if (fresh.length > 0 && remaining <= 0) return scanExceeded();
      const admissible = fresh.slice(0, Math.max(0, remaining));
      const outcomes = await runWaves(run, admissible, THRESHOLD_DEADLINE, (candidate) => admitFresh(deps, run, lane, candidate, reducer));
      if (outcomes.some((o) => o !== undefined && !o.ok && o.code === "SCHEDULER_FENCE_LOST")) throw new SchedulerInvariant("SCHEDULER_FENCE_LOST");
      const before = result.admitted + result.refused + result.extant;
      const t = tally(outcomes, admissible, (c) => c.ref.path, settled, result, "fresh");
      if (t.invariant) emit(deps, t.invariant);
      if (t.unsettled) return result;
      newInPass += result.admitted + result.refused + result.extant - before;
      if (fresh.length > admissible.length) return scanExceeded();
      if (page.docs.length > THRESHOLD_SELECT) {
        const last = selected.at(-1);
        cursor = { at: last.get("thresholdProjection.threshold_at"), path: last.ref.path };
      } else break;
    }
    if (newInPass === 0) break;
  }
  const leftover = capacity - consumed();
  if (leftover > 0 && retries.length > firstShare) {
    if (!(await runRetries(retries.slice(firstShare, firstShare + leftover)))) return result;
  }
  await clearCondition(deps, run, ALERT_THRESHOLD_SCAN);
  result.settled = true;
  return result;
}

// ---------------------------------------------------------------------------
// C9.1.6 / C9.1.8 / C9.1.9 — completion
// ---------------------------------------------------------------------------

function nearestRank(samples, fraction) {
  const sorted = [...samples].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil(fraction * sorted.length) - 1)];
}

/** C9.1.8 — `committed` = run-local threshold paths whose wake transaction committed, with their stored threshold_at. */
async function completeScheduler(deps, run, committed) {
  return fenced(deps, run, async (transaction) => {
    const snapshot = await transaction.get(stateRef(deps.db));
    const health = validateHealth(snapshot.data().schedulerHealth);
    const completedAt = readTimeOf(snapshot, deps);
    const thresholdSamples = committed.map((c) => Math.max(0, Math.floor((completedAt.toMillis() - c.thresholdAt.toMillis()) / 1000)));
    const latency = thresholdSamples.length === 0 ? { count: 0 } : {
      count: thresholdSamples.length, p50Seconds: nearestRank(thresholdSamples, 0.5), p95Seconds: nearestRank(thresholdSamples, 0.95), maxSeconds: Math.max(...thresholdSamples)
    };
    const recentRuns = health.recentRuns.map((r) => (r.runOrdinal === run.runOrdinal && r.state === "running"
      ? { ...r, state: "completed", completedAt, thresholdWakeLatency: latency } : r));
    const next = { ...health, recentRuns, lastCompletedOrdinal: run.runOrdinal };
    validateHealth(next);
    transaction.update(stateRef(deps.db), { schedulerHealth: next });
    return completedAt;
  });
}

// ---------------------------------------------------------------------------
// Evaluation
// ---------------------------------------------------------------------------

async function runDispositionScheduler(event, deps) {
  const schedule = parseScheduleEvent(event);
  if (!schedule) { emit(deps, "SCHEDULER_EVENT_INVALID"); return { outcome: "invalid_event" }; }
  let acquired;
  try {
    acquired = await acquireScheduler(deps, schedule);
  } catch (error) {
    if (error instanceof SchedulerInvariant) { emit(deps, error.code); return { outcome: "blocked", code: error.code }; }
    throw error;
  }
  if (acquired.refused) { emit(deps, "SCHEDULER_ACQUISITION_REFUSED", {}); return { outcome: "refused", reason: acquired.refused }; }
  const run = { ...acquired, deps, startedMonotonic: process.hrtime.bigint() };
  const report = { outcome: "incomplete", runOrdinal: run.runOrdinal, lanes: [], migrated: run.migrated };
  try {
    if (run.missingBeforeThisRun >= 2) {
      await observeCondition(deps, run, ALERT_TWO_MISSED, "TWO_MISSED_COMPLETIONS", { effectiveLastCompletedOrdinal: run.effectiveLast, requiredCompletedOrdinal: run.runOrdinal - 2 });
    } else {
      await clearCondition(deps, run, ALERT_TWO_MISSED);
    }
    const phase0 = await runPhase0(deps, run);
    report.lanes = [...report.lanes, phase0];
    let allSettled = phase0.settled;
    // C9.1.10 / C9.1.12 — observations, eligible-refusal aggregate, then the catch-up decision
    const observation = await observeDue(deps, run);
    report.dueObservation = observation;
    report.eligibleThresholdRefusalCount = await eligibleRefusalCount(deps.db, THRESHOLD_LANE, run.runOrdinal);
    const { catchUp, thresholdAdmissionCapacity, thresholdRefusalCeiling } = decideCatchUp(run, observation, report.eligibleThresholdRefusalCount);
    report.catchUp = catchUp;
    report.thresholdAdmissionCapacity = thresholdAdmissionCapacity;
    report.thresholdRefusalCeiling = thresholdRefusalCeiling;
    run.refusalCeiling = thresholdRefusalCeiling;
    run.objective = true;
    report.objective = true;
    // C9.1.11 — global condition slots proved present or absent by this complete observation
    if (observation.oldestDueAgeSeconds > OLDEST_DUE_ALERT_SECONDS) {
      await observeCondition(deps, run, ALERT_OLDEST_DUE, "OLDEST_DUE_OVER_900_SECONDS", { candidatePath: observation.oldestCandidatePath, thresholdAt: observation.oldestThresholdAt, ageSeconds: observation.oldestDueAgeSeconds, armedDueCandidateCount: observation.armedDueCandidateCount });
    } else {
      await clearCondition(deps, run, ALERT_OLDEST_DUE);
    }
    if (observation.armedDueCandidateCount > thresholdAdmissionCapacity) {
      report.objective = false;
      await observeCondition(deps, run, ALERT_THRESHOLD_CAPACITY, "THRESHOLD_CAPACITY_EXCEEDED", { armedDueCandidateCount: observation.armedDueCandidateCount, admissionCapacity: thresholdAdmissionCapacity });
    } else {
      await clearCondition(deps, run, ALERT_THRESHOLD_CAPACITY);
    }
    const threshold = await runThresholdLane(deps, run, observation, thresholdAdmissionCapacity, report.eligibleThresholdRefusalCount);
    report.lanes = [...report.lanes, threshold];
    if (threshold.scanCapacityExceeded) { report.objective = false; return report; }
    if (!threshold.settled) { allSettled = false; report.objective = false; }
    for (const lane of ORDINARY_LANES) {
      const result = await runOrdinaryLane(deps, run, lane);
      report.lanes = [...report.lanes, result];
      if (!result.settled) allSettled = false;
    }
    report.objective = report.objective && run.objective;
    if (!allSettled) { report.objective = false; return report; }
    await completeScheduler(deps, run, threshold.committed);
    emit(deps, "DISPOSITION_SCHEDULER_COMPLETED", { runOrdinal: run.runOrdinal });
    metric(deps, "phase2/disposition_scheduler_completed_count", 1);
    report.outcome = "completed";
    return report;
  } catch (error) {
    if (error instanceof SchedulerInvariant) { emit(deps, error.code); report.code = error.code; return report; }
    emit(deps, "SCHEDULER_EVALUATION_FAILED");
    return report;
  } finally {
    await releaseScheduler(deps, run).catch(() => {});
  }
}

/** C9.1.25 — the pinned public-v1 getDocument over REST (emulator host when set); never decodes. */
async function fetchRawDocumentProduction(docPath) {
  const app = admin.app();
  const projectId = app.options.projectId || process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
  if (!projectId) throw new SchedulerInvariant("RAW_DOCUMENT_UNAVAILABLE", "project");
  const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
  const base = emulatorHost ? `http://${emulatorHost}/v1` : "https://firestore.googleapis.com/v1";
  const url = `${base}/projects/${projectId}/databases/(default)/documents/${docPath.split("/").map(encodeURIComponent).join("/")}`;
  const headers = {};
  if (emulatorHost) {
    headers.Authorization = "Bearer owner"; // the emulator's admin bypass; rules would otherwise apply to REST reads
  } else {
    const token = await app.options.credential.getAccessToken();
    headers.Authorization = `Bearer ${token.access_token}`;
  }
  const response = await fetch(url, { headers, signal: AbortSignal.timeout(RAW_FETCH_TIMEOUT_MS) });
  if (response.status === 404) return { found: false };
  if (!response.ok) throw new SchedulerInvariant("RAW_DOCUMENT_UNAVAILABLE", String(response.status));
  return { found: true, document: await response.json() };
}

function productionDependencies() {
  return {
    db: admin.firestore(),
    log: (code, counts) => logger.info(code, counts || {}),
    metric: (metricName, value) => logger.info("phase2_metric", { metric: metricName, value }),
    fetchRawDocument: fetchRawDocumentProduction
  };
}

/** C9.1.1 — the exact function configuration. */
const evaluateDispositionTriggers = onSchedule({
  region: "us-central1",
  schedule: "*/5 * * * *",
  timeZone: "Etc/UTC",
  timeoutSeconds: 270,
  memory: "512MiB",
  maxInstances: 1,
  concurrency: 1,
  retryCount: 0
}, (event) => runDispositionScheduler(event, productionDependencies()));

module.exports = {
  SchedulerInvariant,
  SCHEDULE_SECONDS, LEASE_SECONDS, LEASE_PATH, STATE_PATH, CROSS_FENCE_PATH, ALERTS_COLLECTION,
  ORDINARY_LANES, CURSOR_KEYS, LEGACY_RESIDUE_KEYS, PHASE0_SELECT, ORDINARY_SELECT,
  canonicalEventEnvelope,
  canonicalEventStateId,
  consumeEventEnvelopeInTransaction,
  evaluateDispositionTriggers,
  mapWithConcurrency,
  reconcileEventTaskInTransaction,
  validateEventEnvelope,
  wakeDateTaskInTransaction,
  parseScheduleEvent,
  initializeScheduler,
  acquireScheduler,
  requireSchedulerFence,
  releaseScheduler,
  observeCondition,
  clearCondition,
  completeScheduler,
  validateHealth,
  validateDueObservation,
  observeDue,
  decideCatchUp,
  runThresholdLane,
  refusalId,
  candidateFingerprint,
  validateRefusal,
  recordRefusal,
  collectRetries,
  laneMask,
  encodeOriginalEventBytes,
  originalBytesDigest,
  PHASE0_INDEX_REGISTRY_V1,
  STORAGE_BOUNDS,
  storage,
  rawStorage,
  fitsPhase0Transition,
  fitsPhase0TransitionRaw,
  phase0Envelope,
  phase0EnvelopeRaw,
  parseRfc3339,
  validateRetryMember,
  QEV1_MESSAGES,
  UNENCODABLE_MESSAGES,
  QUARANTINE_COLLECTION,
  ORDINARY_LANES,
  THRESHOLD_LANE_SPEC,
  THRESHOLD_LANE,
  THRESHOLD_MASK,
  runDispositionScheduler,
  productionDependencies,
  __private: {
    classifyEnvelope,
    fingerprintCanonicalEnvelope,
    shouldWakeDateTask,
    shouldWakeEventTask,
    ordinaryQuery,
    runPhase0,
    runOrdinaryLane,
    nearestRank
  }
};
