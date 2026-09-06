"use strict";

// Account-deletion fence core (PHASE2_CONTRACT.md C2.3, C3, C6; briefs/S2_BRIEF.md).
// Import-safe: no Firebase app initialization and no provider client at load time.
// Every Firestore, Auth, Storage, clock, and evidence dependency is injected.

const { createHash, randomUUID } = require("node:crypto");
const { HttpsError } = require("firebase-functions/v2/https");
const { Timestamp, FieldPath, FieldValue } = require("firebase-admin/firestore");
const { accountabilityTransition, normalizeStrikes } = require("./accountabilityLadder");

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

// ---------------------------------------------------------------------------
// Logging, deadlines, read time, schedule ordinals
// ---------------------------------------------------------------------------

/** Fixed event codes and bounded counts only — never a UID, path, payload, or Error. */
function emit(deps, code, counts) {
  if (typeof deps.log === "function") deps.log(code, counts || {});
}

function withDeadline(promise, ms, code) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new InvariantError(code, "deadline")), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

/** Server read time of a transaction snapshot, truncated to milliseconds; falls back to the injected clock. */
function readTimeOf(snapshot, deps) {
  const readTime = snapshot && snapshot.readTime;
  if (isTimestampLike(readTime)) return Timestamp.fromMillis(millis(readTime));
  return deps.now();
}

// Storage reconciler: schedule every 5 minutes on the boundary → ordinal floor(epochSeconds / 300).
function storageScheduleOrdinal(epochSeconds) {
  if (!Number.isSafeInteger(epochSeconds) || epochSeconds % 300 !== 0) throw new InvariantError("ACCOUNT_DELETION_SCHEDULE_BOUNDARY_INVALID");
  return epochSeconds / 300;
}

// Auth reconciler: schedule 2-57/5 (boundary + 120 s) → ordinal floor((epochSeconds - 120) / 300).
function authScheduleOrdinal(epochSeconds) {
  if (!Number.isSafeInteger(epochSeconds) || epochSeconds % 300 !== 120) throw new InvariantError("ACCOUNT_DELETION_SCHEDULE_BOUNDARY_INVALID");
  return (epochSeconds - 120) / 300;
}

function firstStorageOrdinalAfter(timestamp) {
  return Math.floor(Math.floor(millis(timestamp) / 1000) / 300) + 1;
}

function firstAuthOrdinalAfter(timestamp) {
  return Math.floor((Math.floor(millis(timestamp) / 1000) - 120) / 300) + 1;
}

/** The auth-schedule ordinal of the most recent boundary at or before `timestamp`. */
function currentAuthOrdinal(timestamp) {
  return Math.floor((Math.floor(millis(timestamp) / 1000) - 120) / 300);
}

function isUserNotFound(error) {
  return Boolean(error) && (error.code === "auth/user-not-found" || error.errorInfo?.code === "auth/user-not-found");
}

function requireEvidence(deps) {
  const evidence = deps.evidence();
  if (!evidence || evidence.ok !== true) {
    emit(deps, (evidence && evidence.code) || "PROVIDER_EVIDENCE_NOT_ACTIVATED");
    throw deletionError("DELETION_RETRY_REQUIRED");
  }
  return evidence.authority;
}

function leasesQuery(db, uid) {
  return db.collection(`users/${uid}/outboundLeases`).orderBy(FieldPath.documentId()).limit(OUTBOUND_LEASE_QUERY_LIMIT);
}

/** §11.3: the reserved lease collection must be exact zero for progress; any document is the fixed invariant. */
function requireZeroLeaseDocuments(snapshot) {
  if (!snapshot.empty) throw new InvariantError("OUTBOUND_LEASE_INVARIANT", "present");
}

// ---------------------------------------------------------------------------
// Firestore descendant discovery (§11:1483) and deletion (§11:1485)
// ---------------------------------------------------------------------------

const COLLECTION_ID_MAX_BYTES = 1500;
const PAGE_TOKEN_MAX_BYTES = 4096;

function isCollectionId(value) {
  return typeof value === "string" && value.length > 0 && Buffer.byteLength(value, "utf8") <= COLLECTION_ID_MAX_BYTES &&
    value !== "." && value !== ".." && !value.includes("/");
}

/** Validates the pinned public-v1 listCollectionIds tuple and returns its page of IDs. */
async function listDirectCollections(deps, documentPath) {
  const invariant = (detail) => new InvariantError("ACCOUNT_DELETION_LIST_COLLECTIONS_INVARIANT", detail);
  const parent = `${deps.firestore.documentsRoot}/${documentPath}`;
  const request = { parent, pageSize: 100 };
  let tuple;
  try {
    tuple = await deps.firestore.client.listCollectionIds(request, { autoPaginate: false });
  } catch (error) {
    throw invariant("call");
  }
  if (!Array.isArray(tuple) || tuple.length !== 3) throw invariant("tuple");
  const [pageIds, nextRequest, raw] = tuple;
  if (!Array.isArray(pageIds) || pageIds.length > 100 || !isPlainMap(raw) || !Array.isArray(raw.collectionIds)) throw invariant("shape");
  if (raw.collectionIds.length !== pageIds.length) throw invariant("length");
  const seen = new Set();
  for (let i = 0; i < pageIds.length; i += 1) {
    const id = pageIds[i];
    if (!isCollectionId(id) || raw.collectionIds[i] !== id || seen.has(id)) throw invariant("id");
    seen.add(id);
  }
  const token = raw.nextPageToken;
  if (typeof token !== "string" || Buffer.byteLength(token, "utf8") > PAGE_TOKEN_MAX_BYTES) throw invariant("token");
  if (token === "") {
    if (nextRequest !== null) throw invariant("nextRequest");
  } else {
    if (!isPlainMap(nextRequest) || Object.keys(nextRequest).length !== 3 || nextRequest.parent !== parent ||
        nextRequest.pageSize !== 100 || nextRequest.pageToken !== token) throw invariant("nextRequest");
  }
  return pageIds;
}

async function requireZeroLeases(deps, uid) {
  await deps.db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(leasesQuery(deps.db, uid));
    requireZeroLeaseDocuments(snapshot);
  });
}

/** One pass over the user root's direct subcollections; returns true when anything was deleted. */
async function sweepDescendants(deps, ctx) {
  let hit = false;
  for (let page = 0; page < 10; page += 1) {
    const ids = await listDirectCollections(deps, `users/${ctx.uid}`);
    let deleted = false;
    for (const id of ids) {
      if (id === "outboundLeases") {
        await requireZeroLeases(deps, ctx.uid);
        continue;
      }
      await deps.db.recursiveDelete(deps.db.collection(`users/${ctx.uid}/${id}`));
      deleted = true;
      hit = true;
    }
    if (!deleted) break;
  }
  return hit;
}

/** The root document keeps only the marker (the minimal tombstone). */
async function scrubRoot(deps, ctx) {
  return deps.db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ctx.rootRef);
    const root = snapshot.exists ? snapshot.data() : undefined;
    if (!root || root.accountDeletion === undefined) throw new InvariantError("ACCOUNT_DELETION_MARKER_MALFORMED", "root");
    if (Object.keys(root).length === 1) return false;
    transaction.set(ctx.rootRef, { accountDeletion: root.accountDeletion });
    return true;
  });
}

// ---------------------------------------------------------------------------
// External families (C6.7; §11:1479)
// ---------------------------------------------------------------------------

async function deleteDirectFamily(deps, ctx, documentPath) {
  const ref = deps.db.doc(documentPath);
  const snapshot = await ref.get();
  const collections = await listDirectCollections(deps, documentPath);
  if (!snapshot.exists && collections.length === 0) return false;
  await deps.db.recursiveDelete(ref);
  return true;
}

async function authorizeFamilyRow(deps, ctx, family, ref) {
  if (deps.hooks && typeof deps.hooks.beforeFamilyReread === "function") deps.hooks.beforeFamilyReread(family.collection, ref.path);
  return deps.db.runTransaction(async (transaction) => {
    const rootSnapshot = await transaction.get(ctx.rootRef);
    const marker = rootSnapshot.exists ? rootSnapshot.data()?.accountDeletion : undefined;
    if (marker === undefined) throw new InvariantError("ACCOUNT_DELETION_MARKER_MALFORMED", "root");
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return false;
    const row = snapshot.data();
    const owned = family.union
      ? row.userId === ctx.uid || row.owner === ctx.uid
      : row[family.field] === ctx.uid;
    if (!owned) return false;
    if (family.mode === "scrub") {
      transaction.update(ref, { [family.field]: FieldValue.delete() });
      return true;
    }
    if (family.strike) {
      const vendorId = typeof row.vendorId === "string" && row.vendorId ? row.vendorId : null;
      if (vendorId) {
        const vendorRef = deps.db.doc(`${family.strike}/${vendorId}`);
        const vendorSnapshot = await transaction.get(vendorRef);
        if (vendorSnapshot.exists) {
          const vendor = vendorSnapshot.data();
          const remaining = normalizeStrikes(vendor.accountability?.strikes).filter((strike) => strike.source !== snapshot.id);
          const transition = accountabilityTransition(remaining, vendor.active !== false);
          transaction.update(vendorRef, { "accountability.strikes": transition.strikes, active: transition.active });
        }
      }
    }
    transaction.delete(ref);
    return true;
  });
}

async function sweepQueryFamily(deps, ctx, family, seenPaths) {
  let hit = false;
  let cursor = null;
  for (let page = 0; page < 10; page += 1) {
    let query = deps.db.collection(family.collection).where(family.field, "==", ctx.uid).orderBy(FieldPath.documentId());
    if (cursor !== null) query = query.startAfter(cursor);
    const snapshot = await query.limit(ACCOUNT_DELETION_FIRESTORE_PAGE_SIZE).get();
    const rows = snapshot.docs.filter((row) => !seenPaths.has(row.ref.path));
    for (let start = 0; start < rows.length; start += 10) {
      const chunk = rows.slice(start, start + 10);
      const results = await Promise.all(chunk.map((row) => authorizeFamilyRow(deps, ctx, family, row.ref)));
      if (results.some(Boolean)) hit = true;
    }
    for (const row of snapshot.docs) seenPaths.add(row.ref.path);
    if (snapshot.docs.length < ACCOUNT_DELETION_FIRESTORE_PAGE_SIZE) break;
    cursor = snapshot.docs[snapshot.docs.length - 1].id;
  }
  return hit;
}

async function sweepExternalFamilies(deps, ctx) {
  let hit = false;
  const unions = new Map();
  for (const family of ACCOUNT_DELETION_EXTERNAL_FAMILIES_V1) {
    if (family.mode === "direct") {
      if (await deleteDirectFamily(deps, ctx, `${family.collection}/${ctx.uid}`)) hit = true;
      continue;
    }
    let seenPaths = new Set();
    if (family.union) {
      if (!unions.has(family.union)) unions.set(family.union, new Set());
      seenPaths = unions.get(family.union);
    }
    if (await sweepQueryFamily(deps, ctx, family, seenPaths)) hit = true;
  }
  return hit;
}

// ---------------------------------------------------------------------------
// Storage (§11:1489–1493)
// ---------------------------------------------------------------------------

const ACCEPTED_BUCKET_NAME = "peezy-1ecrdl.firebasestorage.app";
const INT64_MAX = 9223372036854775807n;

function isGenerationToken(value) {
  if (typeof value !== "string" || !/^[1-9][0-9]*$/.test(value)) return false;
  try { return BigInt(value) <= INT64_MAX; } catch { return false; }
}

async function verifyBucketGate(deps, bucket) {
  const drift = (detail) => new InvariantError("ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT", detail);
  let tuple;
  try { tuple = await bucket.getMetadata(); } catch { throw drift("call"); }
  if (!Array.isArray(tuple) || tuple.length !== 2) throw drift("tuple");
  const [metadata, apiResponse] = tuple;
  if (!isPlainMap(metadata) || metadata.name !== ACCEPTED_BUCKET_NAME || !isGenerationToken(metadata.metageneration)) throw drift("metadata");
  if (apiResponse === null || typeof apiResponse !== "object" || apiResponse.statusCode !== 200) throw drift("response");
  deps.verifyBucketConfiguration(tuple);
  return tuple;
}

/** Validates one getFiles three-tuple for `prefix`; returns [{name, generation}] (zero-length for the terminal observation). */
function validateFilesTuple(tuple, { prefix, limit, mode }) {
  const invariant = (detail) => new InvariantError("ACCOUNT_DELETION_STORAGE_TUPLE_INVARIANT", detail);
  if (!Array.isArray(tuple) || tuple.length !== 3) throw invariant("tuple");
  const [files, nextQuery, raw] = tuple;
  if (!Array.isArray(files) || files.length > limit || raw === null || typeof raw !== "object") throw invariant("shape");
  const items = raw.items;
  if (files.length === 0) {
    if (items !== undefined) throw invariant("items");
  } else {
    if (!Array.isArray(items) || items.length !== files.length) throw invariant("items");
  }
  const out = [];
  for (let i = 0; i < files.length; i += 1) {
    const file = files[i];
    const item = items[i];
    if (!file || !isPlainMap(item)) throw invariant("pair");
    const name = item.name;
    if (typeof name !== "string" || !name.startsWith(prefix) || name.length === prefix.length) throw invariant("name");
    if (file.name !== name || item.bucket !== ACCEPTED_BUCKET_NAME || file.bucket?.name !== ACCEPTED_BUCKET_NAME) throw invariant("identity");
    if (!isGenerationToken(item.generation) || file.metadata?.generation !== item.generation) throw invariant("generation");
    if (mode === "versions") {
      if (item.timeDeleted !== undefined || file.metadata?.timeDeleted !== undefined) throw new InvariantError("ACCOUNT_DELETION_NONCURRENT_GENERATION_PRESENT", "timeDeleted");
      for (const hold of ["temporaryHold", "eventBasedHold"]) {
        if ((item[hold] !== undefined && item[hold] !== false) || (file.metadata?.[hold] !== undefined && file.metadata[hold] !== false)) {
          throw new InvariantError("ACCOUNT_DELETION_NONCURRENT_GENERATION_PRESENT", hold);
        }
      }
    }
    out.push({ name, generation: item.generation });
  }
  const token = raw.nextPageToken;
  if (token !== undefined) {
    if (typeof token !== "string" || token.length === 0 || Buffer.byteLength(token, "utf8") > PAGE_TOKEN_MAX_BYTES) throw invariant("token");
    if (!isPlainMap(nextQuery) || nextQuery.pageToken !== token || nextQuery.prefix !== prefix) throw invariant("nextQuery");
  } else if (nextQuery !== null) {
    throw invariant("nextQuery");
  }
  return { files: out, terminal: token === undefined };
}

async function deleteObject(bucket, { name, generation }) {
  try {
    await bucket.file(name, { preconditionOpts: { ifGenerationMatch: generation } }).delete();
    return "deleted";
  } catch (error) {
    if (error && error.code === 404) return "absent";
    if (error && error.code === 412) return "restart";
    throw new InvariantError("ACCOUNT_DELETION_STORAGE_DELETE_FAILED");
  }
}

/** Sweeps one prefix: returns {hit, empty}; throws the fixed invariants. */
async function sweepStoragePrefix(deps, bucket, prefix, { limit, pages }) {
  let hit = false;
  for (let page = 0; page < pages; page += 1) {
    const listing = await bucket.getFiles({ prefix, maxResults: limit, autoPaginate: false, versions: true });
    const { files, terminal } = validateFilesTuple(listing, { prefix, limit, mode: "versions" });
    if (files.length === 0) {
      if (!terminal) throw new InvariantError("ACCOUNT_DELETION_STORAGE_TUPLE_INVARIANT", "empty with token");
      const probe = await bucket.getFiles({ prefix, maxResults: 1, autoPaginate: false, softDeleted: true });
      const probed = validateFilesTuple(probe, { prefix, limit: 1, mode: "softDeleted" });
      if (probed.files.length !== 0 || !probed.terminal) throw new InvariantError("ACCOUNT_DELETION_SOFT_DELETED_OBJECT_PRESENT");
      return { hit, empty: true };
    }
    hit = true;
    for (let start = 0; start < files.length; start += 10) {
      const chunk = files.slice(start, start + 10);
      await Promise.all(chunk.map((file) => deleteObject(bucket, file)));
    }
    // discard the tuple and restart the prefix from an absent token
  }
  return { hit, empty: false };
}

async function sweepStorage(deps, ctx, { limit }) {
  const bucket = deps.bucket;
  await verifyBucketGate(deps, bucket);
  let hit = false;
  let empty = true;
  for (const prefix of [`inventory/${ctx.uid}/`, `users/${ctx.uid}/`]) {
    const result = await sweepStoragePrefix(deps, bucket, prefix, { limit, pages: deps.budget.storagePages });
    if (result.hit) hit = true;
    if (!result.empty) empty = false;
  }
  return { hit, empty };
}

// ---------------------------------------------------------------------------
// Application sweep and the sweeping → guarding transition (§11:1497)
// ---------------------------------------------------------------------------

async function runApplicationSweep(deps, ctx) {
  let hit = false;
  if (await scrubRoot(deps, ctx)) hit = true;
  if (await sweepDescendants(deps, ctx)) hit = true;
  if (await sweepExternalFamilies(deps, ctx)) hit = true;
  const storage = await sweepStorage(deps, ctx, { limit: 100 });
  if (storage.hit || !storage.empty) hit = true;
  return { empty: !hit };
}

async function transitionSweepingToGuarding(deps, ctx) {
  await deps.db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ctx.rootRef);
    const root = snapshot.exists ? snapshot.data() : undefined;
    const { phase, marker } = validateAccountDeletionMarker(root?.accountDeletion);
    if (phase !== "DELETING_SWEEPING") return;
    if (Object.keys(root).length !== 1) throw new InvariantError("ACCOUNT_DELETION_MARKER_MALFORMED", "root");
    const leases = await transaction.get(leasesQuery(deps.db, ctx.uid));
    requireZeroLeaseDocuments(leases);
    const readTime = readTimeOf(snapshot, deps);
    const guarding = { ...marker, firestoreCleanupAt: readTime };
    validateAccountDeletionMarker(guarding);
    transaction.update(ctx.rootRef, { accountDeletion: guarding });
  });
}

function elapsedExceeded(deps, ctx) {
  return Date.now() - ctx.startedMs > deps.budget.deadlineMs;
}

async function runSweepingReducer(deps, ctx) {
  requireEvidence(deps);
  let emptyStreak = 0;
  for (let pass = 0; pass < deps.budget.sweeps; pass += 1) {
    if (elapsedExceeded(deps, ctx)) return;
    const outcome = await runApplicationSweep(deps, ctx);
    if (!outcome.empty) {
      emptyStreak = 0;
      continue;
    }
    emptyStreak += 1;
    if (emptyStreak === 2) {
      await transitionSweepingToGuarding(deps, ctx);
      return;
    }
  }
}

// ---------------------------------------------------------------------------
// Begin: root-plus-lease marker creation (§11:1415, §11:1435, §11.3:1666)
// ---------------------------------------------------------------------------

function createMarkerAndWork(transaction, deps, ctx, snapshot, data) {
  const readTime = readTimeOf(snapshot, deps);
  const marker = {
    schemaVersion: 1,
    state: "DELETING",
    capabilities: [{ operationId: data.operationId, proofSHA256: capabilityProofSHA256(data) }],
    startedAt: readTime,
    storageGuardAfter: plusSeconds(readTime, STORAGE_GUARD_SECONDS)
  };
  validateAccountDeletionMarker(marker);
  const work = {
    schema_version: 1,
    kind: "ACCOUNT_DELETION_STORAGE_WORK",
    work_id: storageWorkId(ctx.uid),
    account_uid: ctx.uid,
    marker_started_at: marker.startedAt,
    storage_guard_after: marker.storageGuardAfter,
    failure_count: 0,
    next_eligible_run: 0,
    created_at: readTime,
    updated_at: readTime
  };
  validateStorageWork(work, { uid: ctx.uid, marker });
  transaction.set(ctx.rootRef, { accountDeletion: marker });
  transaction.create(deps.db.doc(`accountDeletionStorageWork/${work.work_id}`), work);
  return marker;
}

async function pruneLeasesForBegin(transaction, deps, ctx) {
  const snapshot = await transaction.get(leasesQuery(deps.db, ctx.uid));
  const current = deps.now();
  for (const row of snapshot.docs) {
    const lease = validateOutboundLease(row.data(), { uid: ctx.uid, leaseId: row.id });
    if (millis(lease.expires_at) <= millis(current)) transaction.delete(row.ref);
    else throw new InvariantError("OUTBOUND_LEASE_LIVE");
  }
}

// ---------------------------------------------------------------------------
// Finalize: Auth work row and the Auth reducer (§11:1497, §11.3:1694–1700)
// ---------------------------------------------------------------------------

function authWorkRef(deps, uid) {
  return deps.db.doc(`accountDeletionAuthWork/${authWorkId(uid)}`);
}

async function ensurePendingAuthWork(deps, ctx, expectedMarker, authority) {
  return deps.db.runTransaction(async (transaction) => {
    const rootSnapshot = await transaction.get(ctx.rootRef);
    const root = rootSnapshot.exists ? rootSnapshot.data() : undefined;
    const { phase, marker } = validateAccountDeletionMarker(root?.accountDeletion);
    if (phase !== "DATA_DELETED") return { moved: marker };
    if (TaskCanonicalV1(marker) !== TaskCanonicalV1(expectedMarker)) throw new InvariantError("ACCOUNT_DELETION_MARKER_DRIFT");
    const leases = await transaction.get(leasesQuery(deps.db, ctx.uid));
    requireZeroLeaseDocuments(leases);
    const storageWork = await transaction.get(deps.db.doc(`accountDeletionStorageWork/${storageWorkId(ctx.uid)}`));
    if (storageWork.exists) throw new InvariantError("ACCOUNT_DELETION_STORAGE_WORK_INVARIANT", "present after DATA_DELETED");
    const workSnapshot = await transaction.get(authWorkRef(deps, ctx.uid));
    const readTime = readTimeOf(rootSnapshot, deps);
    if (workSnapshot.exists) {
      const row = validateAuthWork(workSnapshot.data(), { uid: ctx.uid });
      if (row.state !== "delete_pending" || !sameInstant(row.data_deleted_at, marker.dataDeletedAt) ||
          row.authority_generation_id !== authority.generationId || row.authority_sha256 !== authority.authoritySHA256) {
        throw new InvariantError("ACCOUNT_DELETION_AUTH_WORK_INVARIANT", "disagreement");
      }
      return { marker, work: row };
    }
    const work = {
      schema_version: 1,
      kind: "ACCOUNT_DELETION_AUTH_WORK",
      work_id: authWorkId(ctx.uid),
      account_uid: ctx.uid,
      state: "delete_pending",
      data_deleted_at: marker.dataDeletedAt,
      authority_generation_id: authority.generationId,
      authority_sha256: authority.authoritySHA256,
      failure_count: 0,
      next_eligible_run: 0,
      created_at: readTime,
      updated_at: readTime
    };
    validateAuthWork(work, { uid: ctx.uid });
    transaction.create(authWorkRef(deps, ctx.uid), work);
    return { marker, work };
  });
}

async function recordAuthFailure(deps, { uid, work }) {
  await deps.db.runTransaction(async (transaction) => {
    const ref = authWorkRef(deps, uid);
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return;
    const current = snapshot.data();
    if (TaskCanonicalV1(current) !== TaskCanonicalV1(work)) return;
    const readTime = readTimeOf(snapshot, deps);
    const failureCount = Math.min(current.failure_count + 1, FAILURE_COUNT_MAX);
    const next = {
      ...current,
      failure_count: failureCount,
      next_eligible_run: currentAuthOrdinal(readTime) + Math.min(2 ** failureCount, 16),
      updated_at: readTime
    };
    validateAuthWork(next, { uid });
    transaction.set(ref, next);
  });
  emit(deps, "ACCOUNT_DELETION_AUTH_RETRY");
  return { transitioned: false };
}

/**
 * Pending-row Auth reducer: user-not-found or an accepted deleteUser transitions
 * DATA_DELETED → AUTH_GUARDING and pending → guarding at one read time.
 * Transport, timeout, or unknown failure retains pending under fenced backoff.
 */
async function runAuthPendingReducer(deps, { uid, marker, work, authority }) {
  let absent = false;
  try {
    await withDeadline(deps.auth.getUser(uid), deps.timeouts.getUserMs, "ACCOUNT_DELETION_AUTH_TIMEOUT");
  } catch (error) {
    if (isUserNotFound(error)) absent = true;
    else return recordAuthFailure(deps, { uid, work });
  }
  if (!absent) {
    try {
      await withDeadline(deps.auth.deleteUser(uid), deps.timeouts.deleteUserMs, "ACCOUNT_DELETION_AUTH_TIMEOUT");
      absent = true;
    } catch (error) {
      if (isUserNotFound(error)) absent = true;
      else return recordAuthFailure(deps, { uid, work });
    }
  }
  const rootRef = deps.db.doc(`users/${uid}`);
  const workRef = authWorkRef(deps, uid);
  const transitioned = await deps.db.runTransaction(async (transaction) => {
    const rootSnapshot = await transaction.get(rootRef);
    const root = rootSnapshot.exists ? rootSnapshot.data() : undefined;
    const current = validateAccountDeletionMarker(root?.accountDeletion);
    if (current.phase !== "DATA_DELETED") return null;
    if (TaskCanonicalV1(current.marker) !== TaskCanonicalV1(marker)) throw new InvariantError("ACCOUNT_DELETION_MARKER_DRIFT");
    const workSnapshot = await transaction.get(workRef);
    if (!workSnapshot.exists || TaskCanonicalV1(workSnapshot.data()) !== TaskCanonicalV1(work)) throw new InvariantError("ACCOUNT_DELETION_AUTH_WORK_INVARIANT", "drift");
    const readTime = readTimeOf(rootSnapshot, deps);
    const authGuardAfter = plusSeconds(readTime, authority.authResidualRetentionSeconds);
    const guarding = { ...marker, state: "AUTH_GUARDING", authAbsenceObservedAt: readTime, authGuardAfter };
    validateAccountDeletionMarker(guarding);
    const guardingWork = {
      ...work,
      state: "guarding",
      auth_absence_observed_at: readTime,
      auth_guard_after: authGuardAfter,
      failure_count: 0,
      next_eligible_run: firstAuthOrdinalAfter(authGuardAfter),
      updated_at: readTime
    };
    validateAuthWork(guardingWork, { uid, authResidualRetentionSeconds: authority.authResidualRetentionSeconds });
    transaction.update(rootRef, { accountDeletion: guarding });
    transaction.set(workRef, guardingWork);
    return guarding;
  });
  if (transitioned === null) return { transitioned: false, moved: true };
  return { transitioned: true, marker: transitioned };
}

async function runFinalize(deps, ctx, marker) {
  const authority = requireEvidence(deps);
  const pending = await ensurePendingAuthWork(deps, ctx, marker, authority);
  if (pending.moved) return buildRootWire(pending.moved, { operationId: ctx.operationId, authorityKind: ctx.authorityKind, replayed: true });
  const outcome = await runAuthPendingReducer(deps, { uid: ctx.uid, marker: pending.marker, work: pending.work, authority });
  if (outcome.transitioned) return buildRootWire(outcome.marker, { operationId: ctx.operationId, authorityKind: ctx.authorityKind, replayed: false });
  throw deletionError("DELETION_RETRY_REQUIRED");
}

// ---------------------------------------------------------------------------
// The callable (C2.3; §11:1435, §11:1437)
// ---------------------------------------------------------------------------

async function classifyRequest(deps, ctx, data, authenticated) {
  return deps.db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ctx.rootRef);
    const root = snapshot.exists ? snapshot.data() : undefined;
    const rawMarker = root?.accountDeletion;
    if (rawMarker === undefined) {
      if (data.action === "discover") return { kind: "absent" };
      if (data.action !== "begin") throw deletionError("DELETION_CAPABILITY_INVALID");
      requireEvidence(deps);
      await pruneLeasesForBegin(transaction, deps, ctx);
      const marker = createMarkerAndWork(transaction, deps, ctx, snapshot, data);
      return { kind: "present", marker, phase: "DELETING_SWEEPING", authorityKind: "member" };
    }
    let validated;
    try {
      validated = validateAccountDeletionMarker(rawMarker);
    } catch (error) {
      if (error instanceof InvariantError) {
        emit(deps, error.code);
        throw deletionError("DELETION_CAPABILITY_INVALID");
      }
      throw error;
    }
    const proofSHA256 = capabilityProofSHA256(data);
    const existing = validated.marker.capabilities.find((item) => item.operationId === data.operationId);
    if (existing) {
      if (existing.proofSHA256 !== proofSHA256) throw deletionError("DELETION_CAPABILITY_INVALID");
      return { kind: "present", marker: validated.marker, phase: validated.phase, authorityKind: "member" };
    }
    if (data.action === "resume" || !authenticated) throw deletionError("DELETION_CAPABILITY_INVALID");
    if (data.action === "finalize") {
      if (validated.marker.capabilities.length < CAPABILITY_LIMIT) throw deletionError("DELETION_CAPABILITY_INVALID");
      return { kind: "present", marker: validated.marker, phase: validated.phase, authorityKind: "authenticatedOverflow" };
    }
    const classified = classifyCapability(validated.marker, data);
    if (classified.changed) {
      requireEvidence(deps);
      transaction.update(ctx.rootRef, { accountDeletion: classified.marker });
    }
    return { kind: "present", marker: classified.marker, phase: validated.phase, authorityKind: classified.authorityKind };
  });
}

/**
 * `deleteAccount` request handler. `request` is the callable request (`data`, `auth`);
 * `deps` carries db/auth/bucket/firestore client/clock/evidence/log/budget/timeouts/hooks.
 */
async function handleAccountDeletionRequest(request, deps) {
  const data = validateAccountDeletionRequest(request ? request.data : undefined);
  const authUid = request && request.auth ? request.auth.uid : undefined;
  const authenticated = typeof authUid === "string" && authUid === data.uid;
  if (data.action === "discover" || data.action === "begin") {
    if (typeof authUid !== "string" || authUid.length === 0) throw deletionError("AUTH_REQUIRED");
    if (!authenticated) throw deletionError("DELETION_CAPABILITY_INVALID");
  }
  const ctx = { uid: data.uid, operationId: data.operationId, rootRef: deps.db.doc(`users/${data.uid}`), startedMs: Date.now() };
  try {
    const classified = await classifyRequest(deps, ctx, data, authenticated);
    if (classified.kind === "absent") return absentWire(data.operationId);
    ctx.authorityKind = classified.authorityKind;
    const wireArgs = { operationId: data.operationId, authorityKind: classified.authorityKind, replayed: true };
    switch (classified.phase) {
      case "DELETING_SWEEPING":
        if (data.action === "finalize") throw deletionError("DELETION_RETRY_REQUIRED");
        await runSweepingReducer(deps, ctx);
        throw deletionError("DELETION_RETRY_REQUIRED");
      case "DELETING_GUARDING":
        throw deletionError("DELETION_RETRY_REQUIRED");
      case "DATA_DELETED":
        if (data.action !== "finalize") return buildRootWire(classified.marker, wireArgs);
        return await runFinalize(deps, ctx, classified.marker);
      case "AUTH_GUARDING":
      case "ACCOUNT_DELETED":
        return buildRootWire(classified.marker, wireArgs);
      default:
        throw new InvariantError("ACCOUNT_DELETION_MARKER_MALFORMED", "phase");
    }
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    if (error instanceof InvariantError) {
      emit(deps, error.code);
      throw deletionError("DELETION_RETRY_REQUIRED");
    }
    emit(deps, "ACCOUNT_DELETION_UNEXPECTED_FAILURE");
    throw deletionError("DELETION_RETRY_REQUIRED");
  }
}

// ---------------------------------------------------------------------------
// Production dependencies (lazy; the only place Firebase Admin is touched)
// ---------------------------------------------------------------------------

let productionCache = null;

function productionDependencies() {
  if (productionCache) return productionCache;
  const admin = require("firebase-admin");
  const logger = require("firebase-functions/logger");
  const { v1 } = require("@google-cloud/firestore");
  if (!admin.apps.length) admin.initializeApp();
  const db = admin.firestore();
  const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || admin.app().options.projectId || "peezy-1ecrdl";
  productionCache = {
    db,
    auth: admin.auth(),
    bucket: admin.storage().bucket(),
    now: () => Timestamp.fromMillis(Date.now()),
    log: (code, counts) => logger.info(code, counts || {}),
    firestore: { client: new v1.FirestoreClient(), documentsRoot: `projects/${projectId}/databases/(default)/documents` },
    // I3 replaces these two with the provider-evidence authority loader (§11.2).
    evidence: () => ({ ok: false, code: "PROVIDER_EVIDENCE_NOT_ACTIVATED" }),
    verifyBucketConfiguration: () => { throw new InvariantError("ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT", "no accepted configuration"); },
    budget: { sweeps: 4, storagePages: 4, deadlineMs: 42_000 },
    timeouts: { getUserMs: 3000, deleteUserMs: 10000 },
    hooks: {}
  };
  return productionCache;
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
  assertDeletionAbsent, validateOutboundLease, withOutboundLease,
  // callable and sweep
  handleAccountDeletionRequest, runApplicationSweep, runSweepingReducer, transitionSweepingToGuarding,
  listDirectCollections, validateFilesTuple, sweepStoragePrefix, verifyBucketGate, requireZeroLeases,
  // auth reducer and schedule ordinals
  runAuthPendingReducer, ensurePendingAuthWork, recordAuthFailure, isUserNotFound,
  storageScheduleOrdinal, authScheduleOrdinal, firstStorageOrdinalAfter, firstAuthOrdinalAfter, currentAuthOrdinal,
  // misc
  withDeadline, readTimeOf, requireEvidence, emit, productionDependencies
};
