"use strict";

// Account-deletion fence core (PHASE2_CONTRACT.md C2.3, C3, C6; briefs/S2_BRIEF.md).
// Import-safe: no Firebase app initialization and no provider client at load time.
// Every Firestore, Auth, Storage, clock, and evidence dependency is injected.

const { createHash, randomUUID } = require("node:crypto");
const { HttpsError } = require("firebase-functions/v2/https");
const { Timestamp, FieldPath } = require("firebase-admin/firestore");

// ---------------------------------------------------------------------------
// Constants (C3, C6)
// ---------------------------------------------------------------------------

const STORAGE_GUARD_SECONDS = 604800;
const OUTBOUND_LEASE_TTL_SECONDS = 600;
const OUTBOUND_LEASE_LIMIT = 64;
const OUTBOUND_LEASE_QUERY_LIMIT = 65;
const OUTBOUND_LEASE_BYTES_CAP = 1024;
const CAPABILITY_LIMIT = 64;
const CAPABILITY_BYTES_CAP = 16384;
const WORK_ROW_BYTES_CAP = 2048;
const FAILURE_COUNT_MAX = 8;
const ACCOUNT_DELETION_FIRESTORE_PAGE_SIZE = 100;
const OUTBOUND_CHANNELS = Object.freeze(["fcm", "support_email", "support_sms", "inventory_email", "checkin_sms", "anthropic"]);

/** C6.1 — file → registered writers. "*" means every committing branch/shared child. */
const ACCOUNT_DELETION_FENCE_WRITERS_V1 = Object.freeze({
  "functions/index.js": ["requestConcierge", "submitTaskFlow", "submitSupportMessage"],
  "functions/taskDisposition.js": ["*"],
  "functions/taskPlan.js": ["*", "legacyResetMigrations:create"],
  "functions/getWorkflowQualifying.js": ["submitWorkflowAnswers"],
  "functions/dispositionTriggers.js": ["*"],
  "functions/notificationIntents.js": ["*"],
  "functions/spawnTasks.js": ["*"],
  "functions/processInventory.js": ["processSuccess", "processError", "onInventoryRoomWritten"],
  "functions/researchTask.js": ["*"],
  "functions/peezyChat.js": ["*"],
  "functions/packageInventory.js": ["*"],
  "functions/submitCheckIn.js": ["*"],
  "functions/submitCheckInCore.js": ["*"],
  "functions/entitlement.js": ["*"],
  "functions/validateSubscription.js": ["*"],
  "functions/supportAdmin.js": ["adminGetThread", "adminReplySupport", "adminMarkSeen", "adminSetThreadStatus"]
});

/** C6.1 — marker/cleanup coordinator exceptions (they write the marker; they are not fenced by it). */
const ACCOUNT_DELETION_COORDINATOR_EXCEPTIONS_V1 = Object.freeze(["deleteAccount", "reconcileAccountDeletionStorage", "reconcileAccountDeletionAuth"]);

/** C6.1 — explicit no-user-write / deletion-only exclusions. */
const ACCOUNT_DELETION_FENCE_EXCLUSIONS_V1 = Object.freeze([
  "scheduler lease/heartbeat-only writes",
  "generation-preconditioned Storage deletion",
  "support invalid-token deletion",
  "getWorkflowQualifying read-only branch",
  "healthCheck",
  "adminListThreads",
  "requireMovePass"
]);

/** C6.2 — active provider callers; every entry is dominated by withOutboundLease. */
const USER_OUTBOUND_PROVIDERS_V1 = Object.freeze([
  { file: "functions/index.js", caller: "submitSupportMessage", via: "functions/notifySupport.js", channels: ["support_email", "support_sms"] },
  { file: "functions/supportAdmin.js", caller: "adminReplySupport", channels: ["fcm"] },
  { file: "functions/packageInventory.js", caller: "packageInventory", channels: ["inventory_email"] },
  { file: "functions/submitCheckIn.js", caller: "submitCheckIn", channels: ["checkin_sms"] },
  { file: "functions/processInventory.js", caller: "client.messages.create", channels: ["anthropic"] },
  { file: "functions/researchTask.js", caller: "client.messages.create", channels: ["anthropic"] },
  { file: "functions/peezyChat.js", caller: "client.messages.create", channels: ["anthropic"] },
  { file: "functions/resolveProvider.js", caller: "client.messages.create", channels: ["anthropic"] }
]);

/** C6.3 — deployed-function projection. `changeTaskPlan` is expressly non-participating. */
const DELETION_PARTICIPATING_FUNCTIONS_V1 = Object.freeze([
  "requestConcierge", "submitTaskFlow", "submitSupportMessage", "deleteAccount",
  "reconcileAccountDeletionStorage", "reconcileAccountDeletionAuth", "phase2LegacyCreateBlocker",
  "submitWorkflowAnswers", "evaluateDispositionTriggers", "spawnTasks", "processInventory",
  "onInventoryRoomWritten", "researchTask", "peezyChat", "packageInventory", "submitCheckIn",
  "redeemGiftCode", "validateSubscription", "adminGetThread", "adminReplySupport", "adminMarkSeen",
  "adminSetThreadStatus", "resolveProvider"
]);

/** C6.7 — external indexed families in literal sweep order. */
const ACCOUNT_DELETION_EXTERNAL_FAMILIES_V1 = Object.freeze([
  { collection: "userKnowledge", mode: "direct" },
  { collection: "supportThreads", mode: "direct" },
  { collection: "conciergeRequests", field: "userId", mode: "query" },
  { collection: "taskFlowSubmissions", field: "userId", mode: "query" },
  { collection: "inventorySessions", field: "userId", mode: "query" },
  { collection: "workflowSubmissions", field: "userId", mode: "query", union: "workflowSubmissions" },
  { collection: "workflowSubmissions", field: "owner", mode: "query", union: "workflowSubmissions" },
  { collection: "subscriptions", field: "userId", mode: "query" },
  { collection: "vendorReviews", field: "userId", mode: "query", strike: "vendors" },
  { collection: "estimateCalibration", field: "userId", mode: "query" },
  { collection: "admin/inventoryPackages/packages", field: "userId", mode: "query" },
  { collection: "adminNotifications", field: "userId", mode: "query" },
  { collection: "giftCodes", field: "redeemedBy", mode: "scrub" }
]);

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

class InvariantError extends Error {
  constructor(code, detail) {
    super(detail ? `${code}: ${detail}` : code);
    this.code = code;
  }
}

const REASON_CODES = Object.freeze({
  REQUEST_INVALID: "invalid-argument",
  AUTH_REQUIRED: "unauthenticated",
  DELETION_CAPABILITY_INVALID: "permission-denied",
  DELETION_RETRY_REQUIRED: "unavailable",
  ACCOUNT_DELETION_FENCED: "failed-precondition"
});

/** C2.3 thrown union: exact `details`, never a returned map, never UID/path/state detail. */
function deletionError(reason, extra) {
  const code = REASON_CODES[reason];
  if (!code) throw new Error(`deletionError: unknown reason ${reason}`);
  const details = { schemaVersion: 1, reason };
  if (reason === "REQUEST_INVALID") {
    if (!extra || typeof extra.field !== "string" || !extra.field || Object.keys(extra).length !== 1) {
      throw new Error("deletionError: REQUEST_INVALID requires exactly a field detail");
    }
    details.field = extra.field;
  } else if (extra !== undefined) {
    throw new Error(`deletionError: ${reason} admits no extra detail`);
  }
  return new HttpsError(code, reason, details);
}

// ---------------------------------------------------------------------------
// TaskCanonicalV1 (spec v5 §2.1:13 with §2.1's ordering/escaping/NFC rules)
// ---------------------------------------------------------------------------

const MAX_DEPTH = 16;

function compareUTF8(a, b) {
  return Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
}

function isTimestampLike(value) {
  return value instanceof Timestamp ||
    (value !== null && typeof value === "object" && typeof value.toMillis === "function" &&
      Number.isInteger(value.seconds) && Number.isInteger(value.nanoseconds));
}

function quoteString(text) {
  if (text.normalize("NFC") !== text) throw new Error("TaskCanonicalV1: string is not NFC");
  if (Buffer.from(text, "utf8").toString("utf8") !== text) throw new Error("TaskCanonicalV1: invalid Unicode");
  let out = '"';
  for (const ch of text) {
    const cp = ch.codePointAt(0);
    if (ch === '"') out += '\\"';
    else if (ch === "\\") out += "\\\\";
    else if (cp < 0x20) out += `\\u00${cp.toString(16).padStart(2, "0")}`;
    else out += ch;
  }
  return `${out}"`;
}

function encodeCanonical(value, depth, seen) {
  if (value === null) return "null";
  if (value === true) return "true";
  if (value === false) return "false";
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error("TaskCanonicalV1: number must be finite");
    return Object.is(value, -0) ? "0" : String(value);
  }
  if (typeof value === "string") return quoteString(value);
  if (typeof value === "undefined") throw new Error("TaskCanonicalV1: undefined is not canonical");
  if (typeof value !== "object") throw new Error(`TaskCanonicalV1: ${typeof value} is not canonical`);
  if (isTimestampLike(value)) {
    return `{"$firestoreTimestamp":{"nanoseconds":${value.nanoseconds},"seconds":${value.seconds}}}`;
  }
  if (value instanceof Date) {
    const ms = value.getTime();
    if (!Number.isFinite(ms)) throw new Error("TaskCanonicalV1: invalid Date");
    const seconds = Math.floor(ms / 1000);
    const nanoseconds = (ms - seconds * 1000) * 1_000_000;
    return `{"$firestoreTimestamp":{"nanoseconds":${nanoseconds},"seconds":${seconds}}}`;
  }
  if (Buffer.isBuffer(value) || ArrayBuffer.isView(value)) throw new Error("TaskCanonicalV1: binary is not canonical");
  if (depth >= MAX_DEPTH) throw new Error("TaskCanonicalV1: nesting depth exceeds 16");
  if (seen.has(value)) throw new Error("TaskCanonicalV1: cycle");
  seen.add(value);
  let out;
  if (Array.isArray(value)) {
    out = `[${value.map((item) => encodeCanonical(item, depth + 1, seen)).join(",")}]`;
  } else {
    const proto = Object.getPrototypeOf(value);
    if (proto !== Object.prototype && proto !== null) throw new Error("TaskCanonicalV1: only plain maps are canonical");
    const keys = Object.keys(value);
    for (const key of keys) {
      if (key === "" || key.startsWith("$")) throw new Error(`TaskCanonicalV1: invalid map key ${JSON.stringify(key)}`);
      if (key.normalize("NFC") !== key) throw new Error("TaskCanonicalV1: map key is not NFC");
    }
    keys.sort(compareUTF8);
    out = `{${keys.map((key) => `${quoteString(key)}:${encodeCanonical(value[key], depth + 1, seen)}`).join(",")}}`;
  }
  seen.delete(value);
  return out;
}

function TaskCanonicalV1(value) {
  return encodeCanonical(value, 0, new Set());
}

function canonicalByteLength(value) {
  return Buffer.byteLength(TaskCanonicalV1(value), "utf8");
}

function sha256Hex(text) {
  return createHash("sha256").update(text, "utf8").digest("hex");
}

function first40(hex) {
  return hex.slice(0, 40);
}

/** C2.1: proofSHA256 = sha256(TaskCanonicalV1({uid,operation_id,proof_nonce})). */
function capabilityProofSHA256({ uid, operationId, proofNonce }) {
  return sha256Hex(TaskCanonicalV1({ uid, operation_id: operationId, proof_nonce: proofNonce }));
}

// ---------------------------------------------------------------------------
// Grammar helpers
// ---------------------------------------------------------------------------

const RFC4122_UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}";
const OPERATION_ID_RE = new RegExp(`^adel1_${RFC4122_UUID}$`);
const LOWERCASE_UUID_RE = new RegExp(`^${RFC4122_UUID}$`);
const LEASE_ID_RE = new RegExp(`^uol1_${RFC4122_UUID}$`);
const SHA256_HEX_RE = /^[0-9a-f]{64}$/;
const BASE64URL_43_RE = /^[A-Za-z0-9_-]{43}$/;
const CONTROL_RE = /[\u0000-\u001f]/;

function isOperationId(value) {
  return typeof value === "string" && OPERATION_ID_RE.test(value);
}

function isProofNonce(value) {
  if (typeof value !== "string" || !BASE64URL_43_RE.test(value)) return false;
  const bytes = Buffer.from(value, "base64url");
  return bytes.length === 32 && bytes.toString("base64url") === value;
}

function isUID(value) {
  return typeof value === "string" && value.length > 0 && Buffer.byteLength(value, "utf8") <= 128 &&
    !value.includes("/") && value !== "." && value !== ".." && !CONTROL_RE.test(value) && value.trim() === value;
}

function isPlainMap(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) &&
    (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
}

function isMillisecondTimestamp(value) {
  return isTimestampLike(value) && value.nanoseconds % 1_000_000 === 0;
}

function sameInstant(a, b) {
  return a.seconds === b.seconds && a.nanoseconds === b.nanoseconds;
}

function millis(value) {
  return value.seconds * 1000 + Math.floor(value.nanoseconds / 1_000_000);
}

function plusSeconds(value, seconds) {
  return Timestamp.fromMillis(millis(value) + seconds * 1000);
}

function isSafeNonNegativeInteger(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

function exactKeys(value, required, optional = []) {
  if (!isPlainMap(value)) return false;
  const keys = Object.keys(value);
  const allowed = new Set([...required, ...optional]);
  if (keys.some((key) => !allowed.has(key))) return false;
  return required.every((key) => Object.prototype.hasOwnProperty.call(value, key));
}

// ---------------------------------------------------------------------------
// Request union (C2.3; §11:1435/1437)
// ---------------------------------------------------------------------------

const REQUEST_KEYS = ["schemaVersion", "action", "uid", "operationId", "proofNonce"];
const ACTIONS = new Set(["discover", "begin", "resume", "finalize"]);

function validateAccountDeletionRequest(data) {
  const invalid = (field) => deletionError("REQUEST_INVALID", { field });
  if (!isPlainMap(data)) throw invalid("request");
  const keys = Object.keys(data);
  if (keys.some((key) => !REQUEST_KEYS.includes(key))) throw invalid("request");
  if (data.schemaVersion !== 1) throw invalid("request");
  if (typeof data.action !== "string" || !ACTIONS.has(data.action)) throw invalid("action");
  if (!isUID(data.uid)) throw invalid("uid");
  if (!isOperationId(data.operationId)) throw invalid("operationId");
  if (!isProofNonce(data.proofNonce)) throw invalid("proofNonce");
  return { action: data.action, uid: data.uid, operationId: data.operationId, proofNonce: data.proofNonce };
}

// ---------------------------------------------------------------------------
// Root marker grammar (C3; §11.3:1664, §11.3:1698)
// ---------------------------------------------------------------------------

const MARKER_BASE = ["schemaVersion", "state", "capabilities", "startedAt", "storageGuardAfter"];
const GUARDING_OPTIONAL = ["storageGuardCompletedAt", "firestoreVersionGuardCompletedAt"];
const DATA_DELETED_KEYS = [...MARKER_BASE, "firestoreCleanupAt", ...GUARDING_OPTIONAL, "dataDeletedAt"];
const AUTH_GUARDING_KEYS = [...DATA_DELETED_KEYS, "authAbsenceObservedAt", "authGuardAfter"];
const ACCOUNT_DELETED_KEYS = [...AUTH_GUARDING_KEYS, "authGuardCompletedAt", "accountDeletedAt"];

function malformedMarker(detail) {
  return new InvariantError("ACCOUNT_DELETION_MARKER_MALFORMED", detail);
}

function validateCapabilities(capabilities) {
  if (!Array.isArray(capabilities) || capabilities.length < 1 || capabilities.length > CAPABILITY_LIMIT) {
    throw malformedMarker("capabilities length");
  }
  let previous = null;
  for (const item of capabilities) {
    if (!exactKeys(item, ["operationId", "proofSHA256"])) throw malformedMarker("capability members");
    if (!isOperationId(item.operationId)) throw malformedMarker("capability operationId");
    if (typeof item.proofSHA256 !== "string" || !SHA256_HEX_RE.test(item.proofSHA256)) throw malformedMarker("capability proof");
    if (previous !== null && compareUTF8(previous, item.operationId) >= 0) throw malformedMarker("capabilities order");
    previous = item.operationId;
  }
  if (canonicalByteLength(capabilities) > CAPABILITY_BYTES_CAP) throw malformedMarker("capabilities bytes");
}

function requireTimes(marker, keys) {
  for (const key of keys) {
    if (!isMillisecondTimestamp(marker[key])) throw malformedMarker(`${key} must be a millisecond Timestamp`);
  }
}

/**
 * Validates one root `accountDeletion` map and returns `{phase, marker}` where phase is
 * DELETING_SWEEPING | DELETING_GUARDING | DATA_DELETED | AUTH_GUARDING | ACCOUNT_DELETED.
 */
function validateAccountDeletionMarker(marker) {
  if (!isPlainMap(marker)) throw malformedMarker("marker must be a map");
  if (marker.schemaVersion !== 1) throw malformedMarker("schemaVersion");
  const state = marker.state;
  let phase;
  if (state === "DELETING") {
    const sweeping = exactKeys(marker, MARKER_BASE);
    const guarding = exactKeys(marker, [...MARKER_BASE, "firestoreCleanupAt"], GUARDING_OPTIONAL);
    if (!sweeping && !guarding) throw malformedMarker("DELETING members");
    phase = sweeping ? "DELETING_SWEEPING" : "DELETING_GUARDING";
  } else if (state === "DATA_DELETED") {
    if (!exactKeys(marker, DATA_DELETED_KEYS)) throw malformedMarker("DATA_DELETED members");
    phase = "DATA_DELETED";
  } else if (state === "AUTH_GUARDING") {
    if (!exactKeys(marker, AUTH_GUARDING_KEYS)) throw malformedMarker("AUTH_GUARDING members");
    phase = "AUTH_GUARDING";
  } else if (state === "ACCOUNT_DELETED") {
    if (!exactKeys(marker, ACCOUNT_DELETED_KEYS)) throw malformedMarker("ACCOUNT_DELETED members");
    phase = "ACCOUNT_DELETED";
  } else {
    throw malformedMarker("state");
  }
  validateCapabilities(marker.capabilities);
  requireTimes(marker, Object.keys(marker).filter((key) => !["schemaVersion", "state", "capabilities"].includes(key)));

  const m = marker;
  if (!sameInstant(m.storageGuardAfter, plusSeconds(m.startedAt, STORAGE_GUARD_SECONDS))) throw malformedMarker("storageGuardAfter relation");
  if (m.firestoreCleanupAt !== undefined && millis(m.firestoreCleanupAt) < millis(m.startedAt)) throw malformedMarker("firestoreCleanupAt order");
  if (m.storageGuardCompletedAt !== undefined && millis(m.storageGuardCompletedAt) <= millis(m.storageGuardAfter)) throw malformedMarker("storageGuardCompletedAt order");
  if (m.firestoreVersionGuardCompletedAt !== undefined && millis(m.firestoreVersionGuardCompletedAt) < millis(m.firestoreCleanupAt)) throw malformedMarker("firestoreVersionGuardCompletedAt order");
  if (m.dataDeletedAt !== undefined) {
    const floor = Math.max(millis(m.storageGuardCompletedAt), millis(m.firestoreVersionGuardCompletedAt));
    if (millis(m.dataDeletedAt) < floor) throw malformedMarker("dataDeletedAt order");
  }
  if (m.authAbsenceObservedAt !== undefined && millis(m.authAbsenceObservedAt) < millis(m.dataDeletedAt)) throw malformedMarker("authAbsenceObservedAt order");
  if (m.authGuardAfter !== undefined && millis(m.authGuardAfter) < millis(m.authAbsenceObservedAt)) throw malformedMarker("authGuardAfter order");
  if (m.authGuardCompletedAt !== undefined && millis(m.authGuardCompletedAt) <= millis(m.authGuardAfter)) throw malformedMarker("authGuardCompletedAt order");
  if (m.accountDeletedAt !== undefined && millis(m.accountDeletedAt) < millis(m.authGuardCompletedAt)) throw malformedMarker("accountDeletedAt order");
  return { phase, marker };
}

/**
 * §11:1435 — classifies the supplied capability against a validated marker.
 * member (zero write) | member after append (changed:true, resorted, every other byte preserved)
 * | authenticatedOverflow at 64 (zero write). Same operationId with a different proof is
 * DELETION_CAPABILITY_INVALID.
 */
function classifyCapability(marker, { uid, operationId, proofNonce }) {
  validateAccountDeletionMarker(marker);
  const proofSHA256 = capabilityProofSHA256({ uid, operationId, proofNonce });
  const existing = marker.capabilities.find((item) => item.operationId === operationId);
  if (existing) {
    if (existing.proofSHA256 !== proofSHA256) throw deletionError("DELETION_CAPABILITY_INVALID");
    return { authorityKind: "member", marker, changed: false };
  }
  if (marker.capabilities.length >= CAPABILITY_LIMIT) {
    return { authorityKind: "authenticatedOverflow", marker, changed: false };
  }
  const capabilities = [...marker.capabilities, { operationId, proofSHA256 }]
    .sort((a, b) => compareUTF8(a.operationId, b.operationId));
  const appended = { ...marker, capabilities };
  validateAccountDeletionMarker(appended);
  return { authorityKind: "member", marker: appended, changed: true };
}

// ---------------------------------------------------------------------------
// Work rows (C3; §11.3:1666, §11.3:1694)
// ---------------------------------------------------------------------------

function workId(prefix, uid) {
  return `${prefix}${first40(sha256Hex(TaskCanonicalV1({ account_uid: uid })))}`;
}

function storageWorkId(uid) { return workId("adsw1_", uid); }
function authWorkId(uid) { return workId("adaw1_", uid); }

const STORAGE_WORK_KEYS = ["schema_version", "kind", "work_id", "account_uid", "marker_started_at", "storage_guard_after", "failure_count", "next_eligible_run", "created_at", "updated_at"];

function validateStorageWork(row, { uid, marker } = {}) {
  const invariant = (detail) => new InvariantError("ACCOUNT_DELETION_STORAGE_WORK_INVARIANT", detail);
  if (!exactKeys(row, STORAGE_WORK_KEYS)) throw invariant("members");
  if (row.schema_version !== 1 || row.kind !== "ACCOUNT_DELETION_STORAGE_WORK") throw invariant("kind");
  if (typeof row.account_uid !== "string" || (uid !== undefined && row.account_uid !== uid)) throw invariant("account_uid");
  if (row.work_id !== storageWorkId(row.account_uid)) throw invariant("work_id");
  for (const key of ["marker_started_at", "storage_guard_after", "created_at", "updated_at"]) {
    if (!isMillisecondTimestamp(row[key])) throw invariant(key);
  }
  if (!Number.isInteger(row.failure_count) || row.failure_count < 0 || row.failure_count > FAILURE_COUNT_MAX) throw invariant("failure_count");
  if (!isSafeNonNegativeInteger(row.next_eligible_run)) throw invariant("next_eligible_run");
  if (!sameInstant(row.storage_guard_after, plusSeconds(row.marker_started_at, STORAGE_GUARD_SECONDS))) throw invariant("storage_guard_after relation");
  if (millis(row.updated_at) < millis(row.created_at)) throw invariant("updated_at order");
  if (marker) {
    if (!sameInstant(row.marker_started_at, marker.startedAt) || !sameInstant(row.storage_guard_after, marker.storageGuardAfter)) throw invariant("marker disagreement");
  }
  if (canonicalByteLength(row) > WORK_ROW_BYTES_CAP) throw invariant("bytes");
  return row;
}

const AUTH_WORK_PENDING_KEYS = ["schema_version", "kind", "work_id", "account_uid", "state", "data_deleted_at", "authority_generation_id", "authority_sha256", "failure_count", "next_eligible_run", "created_at", "updated_at"];
const AUTH_WORK_GUARDING_KEYS = [...AUTH_WORK_PENDING_KEYS, "auth_absence_observed_at", "auth_guard_after"];

function validateAuthWork(row, { uid, authResidualRetentionSeconds } = {}) {
  const invariant = (detail) => new InvariantError("ACCOUNT_DELETION_AUTH_WORK_INVARIANT", detail);
  if (!isPlainMap(row)) throw invariant("map");
  const guarding = row.state === "guarding";
  if (row.state !== "delete_pending" && !guarding) throw invariant("state");
  if (!exactKeys(row, guarding ? AUTH_WORK_GUARDING_KEYS : AUTH_WORK_PENDING_KEYS)) throw invariant("members");
  if (row.schema_version !== 1 || row.kind !== "ACCOUNT_DELETION_AUTH_WORK") throw invariant("kind");
  if (typeof row.account_uid !== "string" || (uid !== undefined && row.account_uid !== uid)) throw invariant("account_uid");
  if (row.work_id !== authWorkId(row.account_uid)) throw invariant("work_id");
  if (typeof row.authority_generation_id !== "string" || !LOWERCASE_UUID_RE.test(row.authority_generation_id)) throw invariant("authority_generation_id");
  if (typeof row.authority_sha256 !== "string" || !SHA256_HEX_RE.test(row.authority_sha256)) throw invariant("authority_sha256");
  for (const key of ["data_deleted_at", "created_at", "updated_at", ...(guarding ? ["auth_absence_observed_at", "auth_guard_after"] : [])]) {
    if (!isMillisecondTimestamp(row[key])) throw invariant(key);
  }
  if (!Number.isInteger(row.failure_count) || row.failure_count < 0 || row.failure_count > FAILURE_COUNT_MAX) throw invariant("failure_count");
  if (!isSafeNonNegativeInteger(row.next_eligible_run)) throw invariant("next_eligible_run");
  if (millis(row.created_at) < millis(row.data_deleted_at)) throw invariant("created_at order");
  if (millis(row.updated_at) < millis(row.created_at)) throw invariant("updated_at order");
  if (guarding) {
    if (millis(row.auth_absence_observed_at) < millis(row.data_deleted_at)) throw invariant("auth_absence_observed_at order");
    if (millis(row.auth_guard_after) < millis(row.auth_absence_observed_at)) throw invariant("auth_guard_after order");
    if (authResidualRetentionSeconds !== undefined &&
        !sameInstant(row.auth_guard_after, plusSeconds(row.auth_absence_observed_at, authResidualRetentionSeconds))) {
      throw invariant("auth_guard_after relation");
    }
  }
  if (canonicalByteLength(row) > WORK_ROW_BYTES_CAP) throw invariant("bytes");
  return row;
}

// ---------------------------------------------------------------------------
// Wires (C2.3)
// ---------------------------------------------------------------------------

function wireTime(value) {
  if (!isMillisecondTimestamp(value)) throw new Error("wireTime: value must be a millisecond-aligned Timestamp");
  return new Date(millis(value)).toISOString();
}

function absentWire(operationId) {
  return { schemaVersion: 1, kind: "account_deletion_discovery", state: "absent", operationId };
}

/** Builds the data-final / auth-guarding / account-deleted wire from a validated root marker. */
function buildRootWire(marker, { operationId, authorityKind, replayed }) {
  const { phase } = validateAccountDeletionMarker(marker);
  if (authorityKind !== "member" && authorityKind !== "authenticatedOverflow") throw new Error("buildRootWire: authorityKind");
  if (typeof replayed !== "boolean") throw new Error("buildRootWire: replayed");
  if (phase === "DELETING_SWEEPING" || phase === "DELETING_GUARDING") {
    throw new Error(`buildRootWire: DELETING has no root wire (${phase})`);
  }
  const base = {
    schemaVersion: 1, kind: null, operationId, authorityKind,
    startedAt: wireTime(marker.startedAt), dataDeletedAt: wireTime(marker.dataDeletedAt)
  };
  if (phase === "DATA_DELETED") {
    return { ...base, kind: "account_deletion_data_final", replayed };
  }
  if (phase === "AUTH_GUARDING") {
    return {
      ...base, kind: "account_deletion_auth_guarding",
      authAbsenceObservedAt: wireTime(marker.authAbsenceObservedAt), authGuardAfter: wireTime(marker.authGuardAfter), replayed
    };
  }
  return {
    ...base, kind: "account_deletion_account_deleted",
    authAbsenceObservedAt: wireTime(marker.authAbsenceObservedAt), authGuardAfter: wireTime(marker.authGuardAfter),
    authGuardCompletedAt: wireTime(marker.authGuardCompletedAt), accountDeletedAt: wireTime(marker.accountDeletedAt), replayed
  };
}

// ---------------------------------------------------------------------------
// Root fence (C6.1; §11:1475)
// ---------------------------------------------------------------------------

/**
 * Reads every named owner root in unsigned-UTF8 order inside the caller's transaction
 * and requires `accountDeletion` absent. A present (even malformed) marker fences.
 */
async function assertDeletionAbsent(transaction, db, uids) {
  const unique = [...new Set(uids)].sort(compareUTF8);
  if (unique.length === 0) throw new Error("assertDeletionAbsent: at least one uid is required");
  for (const uid of unique) {
    if (!isUID(uid)) throw new Error("assertDeletionAbsent: invalid uid");
    const snapshot = await transaction.get(db.doc(`users/${uid}`));
    const data = snapshot.exists ? snapshot.data() : undefined;
    if (data && data.accountDeletion !== undefined) throw deletionError("ACCOUNT_DELETION_FENCED");
  }
}

// ---------------------------------------------------------------------------
// Outbound lease helper (C3; §11:1411–1415)
// ---------------------------------------------------------------------------

const LEASE_KEYS = ["schema_version", "kind", "account_uid", "delivery_id", "channel", "state", "created_at", "expires_at"];

function validateOutboundLease(row, { uid, leaseId }) {
  const invariant = (detail) => new InvariantError("OUTBOUND_LEASE_INVARIANT", detail);
  if (!exactKeys(row, LEASE_KEYS)) throw invariant("members");
  if (row.schema_version !== 1 || row.kind !== "USER_OUTBOUND_LEASE" || row.state !== "sending") throw invariant("kind/state");
  if (row.account_uid !== uid) throw invariant("account_uid");
  if (typeof row.delivery_id !== "string" || !row.delivery_id) throw invariant("delivery_id");
  if (!OUTBOUND_CHANNELS.includes(row.channel)) throw invariant("channel");
  if (!LEASE_ID_RE.test(leaseId)) throw invariant("lease id");
  if (!isMillisecondTimestamp(row.created_at) || !isMillisecondTimestamp(row.expires_at)) throw invariant("times");
  if (!sameInstant(row.expires_at, plusSeconds(row.created_at, OUTBOUND_LEASE_TTL_SECONDS))) throw invariant("expires_at relation");
  if (canonicalByteLength(row) > OUTBOUND_LEASE_BYTES_CAP) throw invariant("bytes");
  return row;
}

/**
 * Creates one exact `USER_OUTBOUND_LEASE` under the root fence, runs `fn({leaseId, deliveryId})`,
 * and deletes the lease afterwards. Expired leases are pruned in the creating transaction;
 * 64 live leases refuse with OUTBOUND_LEASE_CAPACITY.
 */
async function withOutboundLease(deps, { uid, channel, deliveryId }, fn) {
  if (!OUTBOUND_CHANNELS.includes(channel)) throw new Error(`withOutboundLease: channel unsupported: ${channel}`);
  if (!isUID(uid)) throw new Error("withOutboundLease: invalid uid");
  const { db, now } = deps;
  const leaseId = `uol1_${randomUUID()}`;
  const ref = db.doc(`users/${uid}/outboundLeases/${leaseId}`);
  await db.runTransaction(async (transaction) => {
    await assertDeletionAbsent(transaction, db, [uid]);
    const current = now();
    if (!isMillisecondTimestamp(current)) throw new Error("withOutboundLease: clock must produce millisecond Timestamps");
    const snapshot = await transaction.get(db.collection(`users/${uid}/outboundLeases`).orderBy(FieldPath.documentId()).limit(OUTBOUND_LEASE_QUERY_LIMIT));
    let live = 0;
    for (const row of snapshot.docs) {
      const lease = validateOutboundLease(row.data(), { uid, leaseId: row.id });
      if (millis(lease.expires_at) <= millis(current)) transaction.delete(row.ref);
      else live += 1;
    }
    if (live >= OUTBOUND_LEASE_LIMIT) throw new InvariantError("OUTBOUND_LEASE_CAPACITY");
    const lease = {
      schema_version: 1, kind: "USER_OUTBOUND_LEASE", account_uid: uid, delivery_id: deliveryId ?? leaseId,
      channel, state: "sending", created_at: current, expires_at: plusSeconds(current, OUTBOUND_LEASE_TTL_SECONDS)
    };
    validateOutboundLease(lease, { uid, leaseId });
    transaction.create(ref, lease);
  });
  try {
    return await fn({ leaseId, deliveryId: deliveryId ?? leaseId });
  } finally {
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      if (snapshot.exists) transaction.delete(ref);
    });
  }
}

module.exports = {
  // constants and registries
  STORAGE_GUARD_SECONDS, OUTBOUND_LEASE_TTL_SECONDS, OUTBOUND_LEASE_LIMIT, OUTBOUND_LEASE_QUERY_LIMIT,
  CAPABILITY_LIMIT, CAPABILITY_BYTES_CAP, WORK_ROW_BYTES_CAP, FAILURE_COUNT_MAX, ACCOUNT_DELETION_FIRESTORE_PAGE_SIZE,
  OUTBOUND_CHANNELS, ACCOUNT_DELETION_FENCE_WRITERS_V1, ACCOUNT_DELETION_COORDINATOR_EXCEPTIONS_V1,
  ACCOUNT_DELETION_FENCE_EXCLUSIONS_V1, USER_OUTBOUND_PROVIDERS_V1, DELETION_PARTICIPATING_FUNCTIONS_V1,
  ACCOUNT_DELETION_EXTERNAL_FAMILIES_V1,
  // errors
  InvariantError, deletionError,
  // canonical
  TaskCanonicalV1, canonicalByteLength, sha256Hex, first40, capabilityProofSHA256, compareUTF8,
  // grammar
  isOperationId, isProofNonce, isUID, isMillisecondTimestamp, millis, plusSeconds, sameInstant,
  // request / marker / capability
  validateAccountDeletionRequest, validateAccountDeletionMarker, validateCapabilities, classifyCapability,
  // work rows
  storageWorkId, authWorkId, validateStorageWork, validateAuthWork,
  // wires
  wireTime, absentWire, buildRootWire,
  // fence and lease
  assertDeletionAbsent, validateOutboundLease, withOutboundLease
};
