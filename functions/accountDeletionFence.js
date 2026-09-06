"use strict";

// Account-deletion fence core (PHASE2_CONTRACT.md C2.3, C3, C6; briefs/S2_BRIEF.md).
// Import-safe: no Firebase app initialization and no provider client at load time.
// Every Firestore, Auth, Storage, clock, and evidence dependency is injected.

const { createHash, createPublicKey, randomUUID, verify: cryptoVerify } = require("node:crypto");
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
function validateAccountDeletionMarker(marker, { authResidualRetentionSeconds } = {}) {
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
  if (m.authGuardAfter !== undefined && Number.isSafeInteger(authResidualRetentionSeconds) &&
      !sameInstant(m.authGuardAfter, plusSeconds(m.authAbsenceObservedAt, authResidualRetentionSeconds))) {
    throw malformedMarker("authGuardAfter relation");
  }
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
async function sweepStoragePrefix(deps, bucket, prefix, { limit, pages, admit }) {
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
      if (typeof admit === "function") await admit();
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

async function recordAuthFailure(deps, { uid, work, scheduleOrdinal, guard }) {
  await deps.db.runTransaction(async (transaction) => {
    if (typeof guard === "function") await guard(transaction);
    const ref = authWorkRef(deps, uid);
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return;
    const current = snapshot.data();
    if (TaskCanonicalV1(current) !== TaskCanonicalV1(work)) return;
    const readTime = readTimeOf(snapshot, deps);
    const failureCount = Math.min(current.failure_count + 1, FAILURE_COUNT_MAX);
    const baseOrdinal = Number.isSafeInteger(scheduleOrdinal) ? scheduleOrdinal : currentAuthOrdinal(readTime);
    const next = {
      ...current,
      failure_count: failureCount,
      next_eligible_run: baseOrdinal + Math.min(2 ** failureCount, 16),
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
async function runAuthPendingReducer(deps, { uid, marker, work, authority, scheduleOrdinal, guard }) {
  let absent = false;
  try {
    await withDeadline(deps.auth.getUser(uid), deps.timeouts.getUserMs, "ACCOUNT_DELETION_AUTH_TIMEOUT");
  } catch (error) {
    if (isUserNotFound(error)) absent = true;
    else return recordAuthFailure(deps, { uid, work, scheduleOrdinal, guard });
  }
  if (!absent) {
    try {
      await withDeadline(deps.auth.deleteUser(uid), deps.timeouts.deleteUserMs, "ACCOUNT_DELETION_AUTH_TIMEOUT");
      absent = true;
    } catch (error) {
      if (isUserNotFound(error)) absent = true;
      else return recordAuthFailure(deps, { uid, work, scheduleOrdinal, guard });
    }
  }
  const rootRef = deps.db.doc(`users/${uid}`);
  const workRef = authWorkRef(deps, uid);
  if (deps.hooks && typeof deps.hooks.beforeAuthTransition === "function") deps.hooks.beforeAuthTransition(uid);
  const transitioned = await deps.db.runTransaction(async (transaction) => {
    if (typeof guard === "function") await guard(transaction);
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
  await deps.evidenceFence(authority);
  const pending = await ensurePendingAuthWork(deps, ctx, marker, authority);
  if (pending.moved) return buildRootWire(pending.moved, { operationId: ctx.operationId, authorityKind: ctx.authorityKind, replayed: true });
  const outcome = await runAuthPendingReducer(deps, { uid: ctx.uid, marker: pending.marker, work: pending.work, authority });
  if (outcome.transitioned) return buildRootWire(outcome.marker, { operationId: ctx.operationId, authorityKind: ctx.authorityKind, replayed: false });
  if (outcome.moved) {
    // another device advanced the root during the Auth call: the validated root already carries the wire (C2.3, no retry)
    const snapshot = await ctx.rootRef.get();
    const current = validateAccountDeletionMarker(snapshot.exists ? snapshot.data()?.accountDeletion : undefined);
    if (current.phase === "AUTH_GUARDING" || current.phase === "ACCOUNT_DELETED") {
      return buildRootWire(current.marker, { operationId: ctx.operationId, authorityKind: ctx.authorityKind, replayed: true });
    }
  }
  throw deletionError("DELETION_RETRY_REQUIRED");
}

/**
 * Callable boundary (C3 logging closure): HttpsErrors pass through; anything else becomes a fixed
 * `internal` code with no details, and only that fixed code is logged.
 */
function withFixedErrorBoundary(code, handler, log) {
  const emitFixed = typeof log === "function" ? log : (name, counts) => require("firebase-functions/logger").info(name, counts || {});
  return async function boundedHandler(request) {
    try {
      return await handler(request);
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      emitFixed(code, {});
      throw new HttpsError("internal", code);
    }
  };
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
      const evidence = deps.evidence();
      const retention = evidence && evidence.ok === true ? evidence.authority.authResidualRetentionSeconds : undefined;
      validated = validateAccountDeletionMarker(rawMarker, { authResidualRetentionSeconds: retention });
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
    // C2.3: DELETING-guarding changes no byte; the nonmember stays request-scoped and receives the queued member.
    if (validated.phase === "DELETING_GUARDING") {
      return { kind: "present", marker: validated.marker, phase: validated.phase, authorityKind: classified.authorityKind };
    }
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
// Strict JSON (duplicate keys, trailing bytes, and invalid literals reject)
// ---------------------------------------------------------------------------

function parseStrictJSON(text) {
  let i = 0;
  const fail = (message) => { throw new Error(`strict JSON: ${message} at ${i}`); };
  const ws = () => { while (i < text.length && " \t\n\r".includes(text[i])) i += 1; };
  function string() {
    const start = i;
    i += 1;
    while (i < text.length) {
      if (text[i] === "\\") { i += 2; continue; }
      if (text[i] === '"') { i += 1; return JSON.parse(text.slice(start, i)); }
      i += 1;
    }
    return fail("unterminated string");
  }
  function number() {
    const match = /^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/.exec(text.slice(i, i + 64));
    if (!match) fail("number");
    i += match[0].length;
    return Number(match[0]);
  }
  function object() {
    i += 1;
    const out = {};
    ws();
    if (text[i] === "}") { i += 1; return out; }
    for (;;) {
      ws();
      if (text[i] !== '"') fail("key");
      const key = string();
      if (Object.prototype.hasOwnProperty.call(out, key)) fail("duplicate key");
      ws();
      if (text[i] !== ":") fail("colon");
      i += 1;
      Object.defineProperty(out, key, { value: value(), enumerable: true, writable: true, configurable: true });
      ws();
      if (text[i] === ",") { i += 1; continue; }
      if (text[i] === "}") { i += 1; return out; }
      fail("object");
    }
  }
  function array() {
    i += 1;
    const out = [];
    ws();
    if (text[i] === "]") { i += 1; return out; }
    for (;;) {
      out.push(value());
      ws();
      if (text[i] === ",") { i += 1; continue; }
      if (text[i] === "]") { i += 1; return out; }
      fail("array");
    }
  }
  function value() {
    ws();
    const c = text[i];
    if (c === "{") return object();
    if (c === "[") return array();
    if (c === '"') return string();
    if (text.startsWith("true", i)) { i += 4; return true; }
    if (text.startsWith("false", i)) { i += 5; return false; }
    if (text.startsWith("null", i)) { i += 4; return null; }
    return number();
  }
  const result = value();
  ws();
  if (i !== text.length) fail("trailing bytes");
  return result;
}

// ---------------------------------------------------------------------------
// Provider evidence authority (§11.2:1648–1658; §11.3:1698 partition)
// ---------------------------------------------------------------------------

/** Trust anchor: the literal lands in S3's sealer commit. null = Build A (not activated). */
const PROVIDER_EVIDENCE_TRUST_ANCHOR_V1 = Object.freeze({ publicKeyBase64URL: null, sha256: null });
const PROVIDER_EVIDENCE_NOT_ACTIVATED = Object.freeze({ ok: false, code: "PROVIDER_EVIDENCE_NOT_ACTIVATED" });
const PROVIDER_EVIDENCE_INVARIANT = "ACCOUNT_DELETION_PROVIDER_EVIDENCE_INVARIANT";
const AUTHORITY_BYTES_CAP = 131072;
const AUTHORITY_DOMAIN = "peezy.account_deletion_provider_evidence.v1\0";
const ED25519_SPKI_PREFIX = Buffer.from("302a300506032b6570032100", "hex");
const ACCEPTED_PROJECT_ID = "peezy-1ecrdl";
const ACCEPTED_DATABASE_NAME = "projects/peezy-1ecrdl/databases/(default)";
const POLICY_HOSTS = Object.freeze(["storage.googleapis.com", "firestore.googleapis.com", "cloudresourcemanager.googleapis.com", "orgpolicy.googleapis.com", "identitytoolkit.googleapis.com", "firebaserules.googleapis.com"]);
const POLICY_ADAPTERS = Object.freeze(["google_json_get_v1", "google_iam_get_policy_v1"]);
const ETAG_SOURCES = Object.freeze(["header", "body.etag", "body.policy.etag", "none"]);
const PROVIDER_RESPONSE_CAP = 1048576;
const WIRE_INSTANT_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

const AUTHORITY_KEYS = Object.freeze([
  "schemaVersion", "kind", "generationId", "projectId", "databaseId", "bucketName", "region",
  "implementationSHA256", "packageLockSHA256",
  "firestoreRulesSHA256", "storageRulesSHA256", "firestoreIndexesSHA256", "firestoreRulesetId", "firestoreReleaseId", "storageRulesetId", "storageReleaseId",
  "bucketConfig", "bucketConfigSHA256", "firestoreConfig", "firestoreConfigSHA256",
  "storageDestinations", "firestoreDestinations", "authDestinations", "cloudAuditDestinations", "providerCopyDestinations",
  "copyProducerDenySHA256", "policyChecks",
  "authResidualRetentionSeconds", "authResidualChecks",
  "signatureAlgorithm", "externalEvidenceBundleSHA256", "externalEvidencePublicKeyBase64URL", "externalEvidenceSigningKeySHA256",
  "signedAuthorityPayloadSHA256", "externalEvidenceSignatureBase64URL", "activatedAt", "authoritySHA256"
]);
const BUCKET_CONFIG_KEYS = Object.freeze(["schemaVersion", "name", "metageneration", "softDeletePolicy", "versioning", "retentionPolicy", "defaultEventBasedHold", "objectRetention", "lifecycle", "logging"]);
const BUCKET_CONFIG_SELECTED = Object.freeze(["softDeletePolicy", "versioning", "retentionPolicy", "defaultEventBasedHold", "objectRetention", "lifecycle", "logging"]);
const FIRESTORE_CONFIG_KEYS = Object.freeze(["schemaVersion", "name", "etag", "pointInTimeRecoveryEnablement", "versionRetentionPeriod"]);

function evidenceInvariant(detail) {
  return new InvariantError(PROVIDER_EVIDENCE_INVARIANT, detail);
}

function isHex64(value) { return typeof value === "string" && SHA256_HEX_RE.test(value); }
function isValidUTF8String(value) { return typeof value === "string" && Buffer.from(value, "utf8").toString("utf8") === value; }
function isOrdinaryString(value, max = 4096) { return isValidUTF8String(value) && Buffer.byteLength(value, "utf8") <= max; }
function isNonblankString(value, max = 4096) { return isOrdinaryString(value, max) && value.trim().length > 0; }
function isWireInstant(value) { return typeof value === "string" && WIRE_INSTANT_RE.test(value) && !Number.isNaN(Date.parse(value)) && new Date(value).toISOString() === value; }
function isBase64URL(value, bytes) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value)) return false;
  const decoded = Buffer.from(value, "base64url");
  return decoded.length === bytes && decoded.toString("base64url") === value;
}

function policyURLHost(url) {
  let parsed;
  try { parsed = new URL(url); } catch { return null; }
  if (parsed.protocol !== "https:" || parsed.username || parsed.password || parsed.hash || parsed.port !== "") return null;
  return POLICY_HOSTS.includes(parsed.hostname) ? parsed.hostname : null;
}

function validateArrayDigest(value, label) {
  if (!exactKeys(value, ["count", "canonicalBytes", "sha256"])) throw evidenceInvariant(`${label} members`);
  if (!Number.isSafeInteger(value.count) || value.count < 0 || value.count > 4096) throw evidenceInvariant(`${label} count`);
  if (!Number.isSafeInteger(value.canonicalBytes) || value.canonicalBytes < 0 || value.canonicalBytes > 67108864) throw evidenceInvariant(`${label} bytes`);
  if (!isHex64(value.sha256)) throw evidenceInvariant(`${label} sha256`);
}

function validatePolicyChecks(checks) {
  if (!Array.isArray(checks) || checks.length < 1 || checks.length > 12) throw evidenceInvariant("policyChecks length");
  checks.forEach((check, index) => {
    if (!exactKeys(check, ["ordinal", "domain", "resourceName", "adapterId", "resourceURL", "etagSource", "expectedEtag", "expectedPolicySHA256"])) throw evidenceInvariant("policy check members");
    if (check.ordinal !== index) throw evidenceInvariant("policy check ordinal");
    if (!isNonblankString(check.domain) || !isNonblankString(check.resourceName)) throw evidenceInvariant("policy check strings");
    if (!POLICY_ADAPTERS.includes(check.adapterId)) throw evidenceInvariant("policy check adapter");
    if (!isNonblankString(check.resourceURL) || policyURLHost(check.resourceURL) === null) throw evidenceInvariant("policy check url");
    if (!ETAG_SOURCES.includes(check.etagSource)) throw evidenceInvariant("policy check etagSource");
    if (check.etagSource === "none" ? check.expectedEtag !== "" : !isNonblankString(check.expectedEtag, 1024)) throw evidenceInvariant("policy check etag");
    if (!isHex64(check.expectedPolicySHA256)) throw evidenceInvariant("policy check digest");
  });
}

/** §11.3:1698 — the closed residual-check union and the complete destination partition (D3). */
function validateAuthResidualChecks(checks, { authResidualRetentionSeconds, destinationCount }) {
  if (!Number.isSafeInteger(authResidualRetentionSeconds) || authResidualRetentionSeconds < 0 || authResidualRetentionSeconds > 31536000) throw evidenceInvariant("retention");
  if (!Number.isSafeInteger(destinationCount) || destinationCount < 0) throw evidenceInvariant("destination count");
  if (!Array.isArray(checks) || checks.length < 1 || checks.length > 12) throw evidenceInvariant("residual checks length");
  const covered = new Set();
  let maxRetention = 0;
  checks.forEach((check, index) => {
    if (!isPlainMap(check) || check.ordinal !== index) throw evidenceInvariant("residual ordinal");
    const ordinals = check.destinationOrdinals;
    if (!Array.isArray(ordinals) || ordinals.length === 0) throw evidenceInvariant("destinationOrdinals");
    let previous = -1;
    for (const ordinal of ordinals) {
      if (!Number.isSafeInteger(ordinal) || ordinal <= previous || ordinal >= destinationCount || covered.has(ordinal)) throw evidenceInvariant("destination partition");
      covered.add(ordinal);
      previous = ordinal;
    }
    if (!Number.isSafeInteger(check.retentionSeconds) || check.retentionSeconds < 0 || check.retentionSeconds > authResidualRetentionSeconds) throw evidenceInvariant("check retention");
    maxRetention = Math.max(maxRetention, check.retentionSeconds);
    if (check.adapterId === "firebase_admin_get_user_v1") {
      if (!exactKeys(check, ["ordinal", "destinationOrdinals", "adapterId", "retentionSeconds"])) throw evidenceInvariant("firebase check members");
    } else if (check.adapterId === "google_authenticated_uid_zero_v1") {
      if (!exactKeys(check, ["ordinal", "destinationOrdinals", "adapterId", "resourceURLTemplate", "method", "bodyTemplate", "uidEncoding", "zeroCountField", "retentionSeconds"])) throw evidenceInvariant("query check members");
      if (!isOrdinaryString(check.resourceURLTemplate, 4096) || check.resourceURLTemplate.split("{{UID}}").length !== 2) throw evidenceInvariant("query template");
      if (policyURLHost(check.resourceURLTemplate.replace("{{UID}}", "x")) === null) throw evidenceInvariant("query host");
      if (check.method !== "GET" && check.method !== "POST") throw evidenceInvariant("query method");
      if (!isOrdinaryString(check.bodyTemplate, 16384)) throw evidenceInvariant("query body");
      if (check.method === "GET" && check.bodyTemplate !== "") throw evidenceInvariant("GET body");
      if (check.method === "POST" && check.bodyTemplate.split("{{UID}}").length > 2) throw evidenceInvariant("POST body template");
      if (check.uidEncoding !== "percent_utf8" && check.uidEncoding !== "taskcanonical_sha256_hex") throw evidenceInvariant("uidEncoding");
      if (check.zeroCountField !== "matchCount" && check.zeroCountField !== "totalSize") throw evidenceInvariant("zeroCountField");
    } else if (check.kind === "absence_retention") {
      if (!exactKeys(check, ["ordinal", "kind", "destinationOrdinals", "observedAbsentAt", "retentionSeconds"])) throw evidenceInvariant("absence check members");
      if (ordinals.length !== 1) throw evidenceInvariant("absence destinationOrdinals");
      if (!isWireInstant(check.observedAbsentAt)) throw evidenceInvariant("observedAbsentAt");
    } else {
      throw evidenceInvariant("uncheckable destination kind");
    }
  });
  if (covered.size !== destinationCount) throw evidenceInvariant("uncovered destination");
  if (maxRetention !== authResidualRetentionSeconds) throw evidenceInvariant("retention maximum");
}

/** CanonicalProviderJSONV1 copy: null/Boolean/valid String/finite Number/Array/plain own-property Object. */
function canonicalProviderJSON(value, depth = 0) {
  if (depth > MAX_DEPTH) throw new InvariantError("ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT", "depth");
  if (value === null || typeof value === "boolean") return value;
  if (typeof value === "string") { if (!isValidUTF8String(value)) throw new InvariantError("ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT", "string"); return value; }
  if (typeof value === "number") {
    if (!Number.isFinite(value) || Math.abs(value) > Number.MAX_SAFE_INTEGER) throw new InvariantError("ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT", "number");
    return Object.is(value, -0) ? 0 : value;
  }
  if (Array.isArray(value)) return value.map((item) => canonicalProviderJSON(item, depth + 1));
  if (!isPlainMap(value)) throw new InvariantError("ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT", "type");
  const out = {};
  for (const key of Object.keys(value).sort(compareUTF8)) {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor || descriptor.get || descriptor.set) throw new InvariantError("ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT", "accessor");
    if (descriptor.value === undefined) throw new InvariantError("ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT", "undefined");
    out[key] = canonicalProviderJSON(descriptor.value, depth + 1);
  }
  return out;
}

/** §11.2:1626 — BucketDeletionConfigV1 projected from validated bucket metadata. */
function projectBucketDeletionConfig(metadata) {
  const drift = (detail) => new InvariantError("ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT", detail);
  if (!isPlainMap(metadata)) throw drift("metadata");
  if (metadata.name !== ACCEPTED_BUCKET_NAME) throw drift("name");
  if (!isGenerationToken(metadata.metageneration)) throw drift("metageneration");
  const out = { schemaVersion: 1, name: metadata.name, metageneration: metadata.metageneration };
  for (const key of BUCKET_CONFIG_SELECTED) {
    const present = Object.prototype.hasOwnProperty.call(metadata, key) && metadata[key] !== undefined;
    if (!present) { out[key] = null; continue; }
    const value = metadata[key];
    if (key === "defaultEventBasedHold") {
      if (typeof value !== "boolean") throw drift("defaultEventBasedHold");
      out[key] = value;
    } else {
      if (!isPlainMap(value)) throw drift(key);
      out[key] = canonicalProviderJSON(value);
    }
  }
  if (canonicalByteLength(out) > 65536) throw drift("bytes");
  return out;
}

function validateBucketConfigMap(config) {
  if (!exactKeys(config, BUCKET_CONFIG_KEYS)) throw evidenceInvariant("bucketConfig members");
  if (config.schemaVersion !== 1 || config.name !== ACCEPTED_BUCKET_NAME || !isGenerationToken(config.metageneration)) throw evidenceInvariant("bucketConfig identity");
  for (const key of BUCKET_CONFIG_SELECTED) {
    const value = config[key];
    if (value === null) continue;
    if (key === "defaultEventBasedHold" ? typeof value !== "boolean" : !isPlainMap(value)) throw evidenceInvariant(`bucketConfig ${key}`);
  }
}

function validateFirestoreConfigMap(config) {
  if (!exactKeys(config, FIRESTORE_CONFIG_KEYS)) throw evidenceInvariant("firestoreConfig members");
  if (config.schemaVersion !== 1 || config.name !== ACCEPTED_DATABASE_NAME || !isNonblankString(config.etag, 1024)) throw evidenceInvariant("firestoreConfig identity");
  if (config.pointInTimeRecoveryEnablement !== "POINT_IN_TIME_RECOVERY_DISABLED") throw evidenceInvariant("pitr");
  if (!exactKeys(config.versionRetentionPeriod, ["seconds", "nanos"]) || config.versionRetentionPeriod.seconds !== "3600" || config.versionRetentionPeriod.nanos !== 0) throw evidenceInvariant("versionRetentionPeriod");
}

function authorityDigest(map, omit) {
  const copy = {};
  for (const key of Object.keys(map)) if (!omit.includes(key)) copy[key] = map[key];
  return sha256Hex(TaskCanonicalV1(copy));
}

function validateProviderEvidenceAuthority(a, trustAnchor) {
  if (!exactKeys(a, AUTHORITY_KEYS)) throw evidenceInvariant("members");
  if (a.schemaVersion !== 1 || a.kind !== "ACCOUNT_DELETION_PROVIDER_EVIDENCE") throw evidenceInvariant("kind");
  if (typeof a.generationId !== "string" || !LOWERCASE_UUID_RE.test(a.generationId)) throw evidenceInvariant("generationId");
  if (a.projectId !== ACCEPTED_PROJECT_ID || a.databaseId !== "(default)" || a.bucketName !== ACCEPTED_BUCKET_NAME || a.region !== "us-central1") throw evidenceInvariant("identity");
  for (const key of ["implementationSHA256", "packageLockSHA256", "firestoreRulesSHA256", "storageRulesSHA256", "firestoreIndexesSHA256", "copyProducerDenySHA256", "externalEvidenceBundleSHA256", "bucketConfigSHA256", "firestoreConfigSHA256"]) {
    if (!isHex64(a[key])) throw evidenceInvariant(key);
  }
  for (const key of ["firestoreRulesetId", "firestoreReleaseId", "storageRulesetId", "storageReleaseId"]) {
    if (!isNonblankString(a[key], 1024)) throw evidenceInvariant(key);
  }
  validateBucketConfigMap(a.bucketConfig);
  if (sha256Hex(TaskCanonicalV1(a.bucketConfig)) !== a.bucketConfigSHA256) throw evidenceInvariant("bucketConfigSHA256");
  validateFirestoreConfigMap(a.firestoreConfig);
  if (sha256Hex(TaskCanonicalV1(a.firestoreConfig)) !== a.firestoreConfigSHA256) throw evidenceInvariant("firestoreConfigSHA256");
  for (const key of ["storageDestinations", "firestoreDestinations", "authDestinations", "cloudAuditDestinations", "providerCopyDestinations"]) {
    validateArrayDigest(a[key], key);
  }
  validatePolicyChecks(a.policyChecks);
  validateAuthResidualChecks(a.authResidualChecks, { authResidualRetentionSeconds: a.authResidualRetentionSeconds, destinationCount: a.authDestinations.count });
  if (a.signatureAlgorithm !== "ed25519") throw evidenceInvariant("signatureAlgorithm");
  if (!isBase64URL(a.externalEvidencePublicKeyBase64URL, 32)) throw evidenceInvariant("public key");
  const keyBytes = Buffer.from(a.externalEvidencePublicKeyBase64URL, "base64url");
  if (a.externalEvidencePublicKeyBase64URL !== trustAnchor.publicKeyBase64URL) throw evidenceInvariant("trust anchor key");
  const keyDigest = createHash("sha256").update(keyBytes).digest("hex");
  if (a.externalEvidenceSigningKeySHA256 !== keyDigest || keyDigest !== trustAnchor.sha256) throw evidenceInvariant("trust anchor digest");
  if (!isWireInstant(a.activatedAt)) throw evidenceInvariant("activatedAt");
  if (!isHex64(a.signedAuthorityPayloadSHA256) || !isHex64(a.authoritySHA256) || !isBase64URL(a.externalEvidenceSignatureBase64URL, 64)) throw evidenceInvariant("signature members");
  const payload = authorityDigest(a, ["signedAuthorityPayloadSHA256", "externalEvidenceSignatureBase64URL", "authoritySHA256"]);
  if (payload !== a.signedAuthorityPayloadSHA256) throw evidenceInvariant("payload digest");
  const message = Buffer.concat([
    Buffer.from(AUTHORITY_DOMAIN, "ascii"),
    Buffer.from(payload, "hex"),
    Buffer.from(a.externalEvidenceBundleSHA256, "hex"),
    Buffer.from(a.implementationSHA256, "hex")
  ]);
  const publicKey = createPublicKey({ key: Buffer.concat([ED25519_SPKI_PREFIX, keyBytes]), format: "der", type: "spki" });
  if (!cryptoVerify(null, message, publicKey, Buffer.from(a.externalEvidenceSignatureBase64URL, "base64url"))) throw evidenceInvariant("signature");
  if (authorityDigest(a, ["authoritySHA256"]) !== a.authoritySHA256) throw evidenceInvariant("authoritySHA256");
}

/**
 * Loads `functions/accountDeletionProviderEvidenceV1.json` bytes. Absent bytes or an
 * unsupplied trust anchor is Build A (not activated); any defect is the fixed invariant.
 */
function loadProviderEvidenceAuthority(bytes, { trustAnchor } = {}) {
  if (bytes === undefined || bytes === null) return PROVIDER_EVIDENCE_NOT_ACTIVATED;
  if (!trustAnchor || typeof trustAnchor.publicKeyBase64URL !== "string" || typeof trustAnchor.sha256 !== "string") return PROVIDER_EVIDENCE_NOT_ACTIVATED;
  try {
    const text = Buffer.isBuffer(bytes) ? bytes.toString("utf8") : String(bytes);
    if (Buffer.byteLength(text, "utf8") > AUTHORITY_BYTES_CAP || !isValidUTF8String(text)) throw evidenceInvariant("bytes cap");
    const parsed = parseStrictJSON(text);
    validateProviderEvidenceAuthority(parsed, trustAnchor);
    if (TaskCanonicalV1(parsed) !== text) throw evidenceInvariant("non-canonical bytes");
    return { ok: true, authority: parsed };
  } catch (error) {
    return { ok: false, code: PROVIDER_EVIDENCE_INVARIANT };
  }
}

/** Fresh bucket observation must reproduce the accepted BucketDeletionConfigV1 bytes and digest. */
function verifyBucketConfiguration(tuple, authority) {
  const drift = (detail) => new InvariantError("ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT", detail);
  if (!Array.isArray(tuple) || tuple.length !== 2) throw drift("tuple");
  const [metadata, apiResponse] = tuple;
  if (apiResponse === null || typeof apiResponse !== "object" || apiResponse.statusCode !== 200) throw drift("response");
  const projection = projectBucketDeletionConfig(metadata);
  const bytes = TaskCanonicalV1(projection);
  if (bytes !== TaskCanonicalV1(authority.bucketConfig) || sha256Hex(bytes) !== authority.bucketConfigSHA256) throw drift("digest");
  return projection;
}

function protoSeconds(value) {
  if (typeof value === "number" && Number.isSafeInteger(value)) return value;
  if (typeof value === "string" && /^-?(0|[1-9][0-9]*)$/.test(value)) return Number(value);
  if (value && typeof value.toString === "function" && /^-?(0|[1-9][0-9]*)$/.test(value.toString())) return Number(value.toString());
  return null;
}

/** §11.2:1632 — FirestoreDeletionConfigV1 from the exact getDatabase three-tuple; returns the fresh earliestVersionTime. */
function verifyFirestoreConfiguration(tuple, authority) {
  if (!Array.isArray(tuple) || tuple.length !== 3) throw evidenceInvariant("database tuple");
  const [database, next, raw] = tuple;
  if (next !== null || raw !== null || !isPlainMap(database)) throw evidenceInvariant("database tuple members");
  const period = database.versionRetentionPeriod;
  if (!period || typeof period !== "object") throw evidenceInvariant("versionRetentionPeriod");
  const seconds = protoSeconds(period.seconds);
  const nanos = typeof period.nanos === "number" ? period.nanos : Number(period.nanos ?? 0);
  if (seconds === null || !Number.isSafeInteger(nanos)) throw evidenceInvariant("versionRetentionPeriod");
  const projection = {
    schemaVersion: 1,
    name: database.name,
    etag: database.etag,
    pointInTimeRecoveryEnablement: database.pointInTimeRecoveryEnablement,
    versionRetentionPeriod: { seconds: String(seconds), nanos }
  };
  if (typeof projection.name !== "string" || typeof projection.etag !== "string" || typeof projection.pointInTimeRecoveryEnablement !== "string") throw evidenceInvariant("database projection");
  const bytes = TaskCanonicalV1(projection);
  if (bytes !== TaskCanonicalV1(authority.firestoreConfig) || sha256Hex(bytes) !== authority.firestoreConfigSHA256) throw evidenceInvariant("database digest");
  const earliest = database.earliestVersionTime;
  if (!earliest || typeof earliest !== "object") throw evidenceInvariant("earliestVersionTime");
  const earliestSeconds = protoSeconds(earliest.seconds);
  const earliestNanos = typeof earliest.nanos === "number" ? earliest.nanos : Number(earliest.nanos ?? 0);
  if (earliestSeconds === null || !Number.isInteger(earliestNanos) || earliestNanos < 0 || earliestNanos > 999999999) throw evidenceInvariant("earliestVersionTime");
  return { projection, earliestVersionTime: Timestamp.fromMillis(earliestSeconds * 1000 + Math.floor(earliestNanos / 1_000_000)) };
}

function headerValue(headers, name) {
  if (!headers || typeof headers !== "object") return undefined;
  for (const key of Object.keys(headers)) if (key.toLowerCase() === name) return headers[key];
  return undefined;
}

function buildPolicyRequest(check, deps) {
  const base = { url: check.resourceURL, headers: { accept: "application/json" }, deadlineMs: deps.timeouts.providerMs, maxBytes: PROVIDER_RESPONSE_CAP, redirects: 0 };
  if (check.adapterId === "google_json_get_v1") return { ...base, method: "GET" };
  return { ...base, method: "POST", headers: { ...base.headers, "content-type": "application/json" }, body: '{"options":{"requestedPolicyVersion":3}}' };
}

async function runPolicyCheck(deps, check) {
  const request = buildPolicyRequest(check, deps);
  let response;
  try {
    response = await withDeadline(deps.providerHTTP.request(request), deps.timeouts.providerMs, PROVIDER_EVIDENCE_INVARIANT);
  } catch (error) {
    throw evidenceInvariant("policy transport");
  }
  if (!response || response.status !== 200) throw evidenceInvariant("policy status");
  const media = headerValue(response.headers, "content-type");
  if (typeof media !== "string" || !media.toLowerCase().startsWith("application/json")) throw evidenceInvariant("policy media");
  if (!Buffer.isBuffer(response.body) || response.body.length > PROVIDER_RESPONSE_CAP) throw evidenceInvariant("policy size");
  const text = response.body.toString("utf8");
  if (!isValidUTF8String(text)) throw evidenceInvariant("policy unicode");
  let parsed;
  try { parsed = parseStrictJSON(text); } catch { throw evidenceInvariant("policy json"); }
  if (!isPlainMap(parsed)) throw evidenceInvariant("policy object");
  let etag = "";
  if (check.etagSource === "header") etag = headerValue(response.headers, "etag");
  else if (check.etagSource === "body.etag") etag = parsed.etag;
  else if (check.etagSource === "body.policy.etag") etag = isPlainMap(parsed.policy) ? parsed.policy.etag : undefined;
  if (check.etagSource !== "none" && typeof etag !== "string") throw evidenceInvariant("policy etag missing");
  if (etag !== check.expectedEtag) throw evidenceInvariant("policy etag drift");
  if (sha256Hex(TaskCanonicalV1(parsed)) !== check.expectedPolicySHA256) throw evidenceInvariant("policy drift");
}

/** All policyChecks in ordinal order, at most four in flight, 3-second deadline each (§11.2:1646/1658). */
async function runPolicyChecks(deps, authority) {
  const checks = authority.policyChecks;
  let next = 0;
  const workers = Array.from({ length: Math.min(4, checks.length) }, async () => {
    while (next < checks.length) {
      const check = checks[next];
      next += 1;
      await runPolicyCheck(deps, check);
    }
  });
  await Promise.all(workers);
}

/**
 * The bounded fresh fence at reconciler acquisition and finalize: one bucket-config RPC, one
 * Firestore-config RPC, every policy check. Returns the fresh earliestVersionTime.
 */
async function runEvidenceFence(deps, authority) {
  let bucketTuple;
  try { bucketTuple = await deps.bucket.getMetadata(); } catch { throw new InvariantError("ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT", "call"); }
  verifyBucketConfiguration(bucketTuple, authority);
  let databaseTuple;
  try { databaseTuple = await deps.firestoreAdmin.getDatabase({ name: ACCEPTED_DATABASE_NAME }); } catch { throw evidenceInvariant("database call"); }
  const { earliestVersionTime } = verifyFirestoreConfiguration(databaseTuple, authority);
  await runPolicyChecks(deps, authority);
  return { earliestVersionTime };
}

/** Production transport: node https + GoogleAuth read-only scope, zero redirects, byte cap, deadline. */
function productionProviderHTTP() {
  const https = require("node:https");
  const { GoogleAuth } = require("google-auth-library");
  const auth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/cloud-platform.read-only"] });
  return {
    async request({ url, method, headers, body, deadlineMs, maxBytes }) {
      const client = await auth.getClient();
      const authHeaders = await client.getRequestHeaders(url);
      return new Promise((resolve, reject) => {
        const request = https.request(url, { method, headers: { ...authHeaders, ...headers } }, (response) => {
          const chunks = [];
          let size = 0;
          response.on("data", (chunk) => {
            size += chunk.length;
            if (size > maxBytes) { request.destroy(new Error("oversize")); return; }
            chunks.push(chunk);
          });
          response.on("end", () => resolve({ status: response.statusCode, headers: response.headers, body: Buffer.concat(chunks) }));
        });
        request.setTimeout(deadlineMs, () => request.destroy(new Error("timeout")));
        request.on("error", reject);
        if (body !== undefined) request.write(body);
        request.end();
      });
    }
  };
}

// ---------------------------------------------------------------------------
// Scheduled reconcilers (§11.3): state grammar, acquisition, cursor, reducers
// ---------------------------------------------------------------------------

const RECONCILER_LEASE_SECONDS = 270;
const RECONCILER_PAGE_SIZE = 50;
const STATE_KEYS = ["schema_version", "kind", "last_started_ordinal", "last_completed_ordinal", "cursor_id", "lease", "heartbeat"];
const RECONCILERS = Object.freeze({
  storage: Object.freeze({
    kind: "ACCOUNT_DELETION_STORAGE_RECONCILER", statePath: "phase2System/accountDeletionStorageReconcilerV1",
    workCollection: "accountDeletionStorageWork", workIdRe: /^adsw1_[0-9a-f]{40}$/, boundaryOffset: 0,
    invariant: "ACCOUNT_DELETION_STORAGE_RECONCILER_INVARIANT", workInvariant: "ACCOUNT_DELETION_STORAGE_WORK_INVARIANT",
    metric: "phase2/account_deletion_storage_reconciler_completed_count"
  }),
  auth: Object.freeze({
    kind: "ACCOUNT_DELETION_AUTH_RECONCILER", statePath: "phase2System/accountDeletionAuthReconcilerV1",
    workCollection: "accountDeletionAuthWork", workIdRe: /^adaw1_[0-9a-f]{40}$/, boundaryOffset: 120,
    invariant: "ACCOUNT_DELETION_AUTH_RECONCILER_INVARIANT", workInvariant: "ACCOUNT_DELETION_AUTH_WORK_INVARIANT",
    metric: "phase2/account_deletion_auth_reconciler_completed_count"
  })
});
/** Codes that leave the run `running` (no settlement, no completion metric). */
const SYSTEMIC_CODES = new Set([
  "ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT", PROVIDER_EVIDENCE_INVARIANT, "ACCOUNT_DELETION_RECONCILER_LEASE_LOST",
  "ACCOUNT_DELETION_STORAGE_RECONCILER_INVARIANT", "ACCOUNT_DELETION_AUTH_RECONCILER_INVARIANT", "ACCOUNT_DELETION_SCHEDULE_BOUNDARY_INVALID"
]);

function validateReconcilerState(state, which) {
  const spec = RECONCILERS[which];
  const invariant = (detail) => new InvariantError(spec.invariant, detail);
  if (!exactKeys(state, STATE_KEYS)) throw invariant("members");
  if (state.schema_version !== 1 || state.kind !== spec.kind) throw invariant("kind");
  if (!isSafeNonNegativeInteger(state.last_started_ordinal) || !isSafeNonNegativeInteger(state.last_completed_ordinal)) throw invariant("ordinals");
  if (state.last_completed_ordinal > state.last_started_ordinal) throw invariant("ordinal order");
  if (state.cursor_id !== "" && !(typeof state.cursor_id === "string" && spec.workIdRe.test(state.cursor_id))) throw invariant("cursor");
  const lease = state.lease;
  if (lease !== null) {
    if (!exactKeys(lease, ["owner_token", "schedule_ordinal", "scheduled_at", "started_at", "expires_at"])) throw invariant("lease members");
    if (typeof lease.owner_token !== "string" || !LOWERCASE_UUID_RE.test(lease.owner_token)) throw invariant("lease owner");
    if (!isSafeNonNegativeInteger(lease.schedule_ordinal) || lease.schedule_ordinal !== state.last_started_ordinal) throw invariant("lease ordinal");
    for (const key of ["scheduled_at", "started_at", "expires_at"]) if (!isMillisecondTimestamp(lease[key])) throw invariant(`lease ${key}`);
    if (millis(lease.scheduled_at) > millis(lease.started_at)) throw invariant("lease time order");
    if (!sameInstant(lease.expires_at, plusSeconds(lease.started_at, RECONCILER_LEASE_SECONDS))) throw invariant("lease expiry relation");
  }
  const heartbeat = state.heartbeat;
  if (heartbeat !== null) {
    const completed = heartbeat.status === "completed";
    if (heartbeat.status !== "running" && !completed) throw invariant("heartbeat status");
    if (!exactKeys(heartbeat, completed ? ["schedule_ordinal", "status", "started_at", "completed_at"] : ["schedule_ordinal", "status", "started_at"])) throw invariant("heartbeat members");
    if (!isSafeNonNegativeInteger(heartbeat.schedule_ordinal) || !isMillisecondTimestamp(heartbeat.started_at)) throw invariant("heartbeat values");
    if (completed) {
      if (!isMillisecondTimestamp(heartbeat.completed_at) || millis(heartbeat.completed_at) < millis(heartbeat.started_at)) throw invariant("completed_at");
      if (lease !== null) throw invariant("completed with lease");
    }
  }
  if (lease !== null && (heartbeat === null || heartbeat.status !== "running" || heartbeat.schedule_ordinal !== lease.schedule_ordinal)) throw invariant("lease without running heartbeat");
  return state;
}

const SCHEDULE_TIME_RE = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d{1,9})?Z$/;

function parseScheduleBoundary(event, offsetSeconds) {
  const invalid = () => new InvariantError("ACCOUNT_DELETION_SCHEDULE_BOUNDARY_INVALID");
  const raw = event && typeof event.scheduleTime === "string" ? event.scheduleTime : null;
  const match = raw === null ? null : SCHEDULE_TIME_RE.exec(raw);
  if (!match) throw invalid();
  if (match[2] && /[1-9]/.test(match[2])) throw invalid();
  const ms = Date.parse(`${match[1]}Z`);
  if (!Number.isFinite(ms) || new Date(ms).toISOString() !== `${match[1]}.000Z`) throw invalid();
  const epochSeconds = ms / 1000;
  if ((epochSeconds - offsetSeconds) % 300 !== 0 || epochSeconds < offsetSeconds) throw invalid();
  return { ordinal: (epochSeconds - offsetSeconds) / 300, scheduledAt: Timestamp.fromMillis(ms) };
}

function stateRefOf(deps, spec) {
  return deps.db.doc(spec.statePath);
}

/** Reads the state inside `transaction` and requires the run's live lease (owner, ordinal, unexpired). */
async function assertLeaseLive(transaction, deps, run) {
  const snapshot = await transaction.get(stateRefOf(deps, run.spec));
  if (!snapshot.exists) throw new InvariantError(run.spec.invariant, "absent");
  const state = validateReconcilerState(snapshot.data(), run.which);
  const readTime = readTimeOf(snapshot, deps);
  const lease = state.lease;
  if (lease === null || lease.owner_token !== run.lease.owner_token || lease.schedule_ordinal !== run.lease.schedule_ordinal || millis(lease.expires_at) <= millis(readTime)) {
    throw new InvariantError("ACCOUNT_DELETION_RECONCILER_LEASE_LOST");
  }
  return { state, readTime, snapshot };
}

function fencedTransaction(deps, run, fn) {
  return deps.db.runTransaction(async (transaction) => {
    const context = await assertLeaseLive(transaction, deps, run);
    return fn(transaction, context);
  });
}

function writeCursor(deps, run, cursorId) {
  return fencedTransaction(deps, run, async (transaction, { state }) => {
    const next = { ...state, cursor_id: cursorId };
    validateReconcilerState(next, run.which);
    transaction.set(stateRefOf(deps, run.spec), next);
  });
}

async function acquireReconciler(deps, which, boundary) {
  const spec = RECONCILERS[which];
  const ref = stateRefOf(deps, spec);
  return deps.db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw new InvariantError(spec.invariant, "absent");
    const state = validateReconcilerState(snapshot.data(), which);
    const readTime = readTimeOf(snapshot, deps);
    if (boundary.ordinal <= state.last_started_ordinal) return null;
    if (state.lease !== null && millis(state.lease.expires_at) > millis(readTime)) return null;
    const lease = { owner_token: randomUUID(), schedule_ordinal: boundary.ordinal, scheduled_at: boundary.scheduledAt, started_at: readTime, expires_at: plusSeconds(readTime, RECONCILER_LEASE_SECONDS) };
    const next = { ...state, last_started_ordinal: boundary.ordinal, lease, heartbeat: { schedule_ordinal: boundary.ordinal, status: "running", started_at: readTime } };
    validateReconcilerState(next, which);
    transaction.set(ref, next);
    return lease;
  });
}

async function settleReconciler(deps, run) {
  await fencedTransaction(deps, run, async (transaction, { state, readTime }) => {
    const next = {
      ...state,
      last_completed_ordinal: run.ordinal,
      lease: null,
      heartbeat: { schedule_ordinal: run.ordinal, status: "completed", started_at: state.heartbeat.started_at, completed_at: readTime }
    };
    validateReconcilerState(next, run.which);
    transaction.set(stateRefOf(deps, run.spec), next);
  });
  if (typeof deps.metric === "function") deps.metric(run.spec.metric, 1);
}

function validateWorkRow(which, id, data) {
  const spec = RECONCILERS[which];
  const row = which === "storage" ? validateStorageWork(data) : validateAuthWork(data);
  if (row.work_id !== id) throw new InvariantError(spec.workInvariant, "work_id");
  return row;
}

/** One acquired run: page, select (cursor before await), reduce at most one row. */
async function runReconcilerBody(deps, run) {
  const spec = run.spec;
  const page = await fencedTransaction(deps, run, async (transaction, { state }) => {
    let query = deps.db.collection(spec.workCollection).orderBy(FieldPath.documentId());
    if (state.cursor_id !== "") query = query.startAfter(state.cursor_id);
    const snapshot = await transaction.get(query.limit(RECONCILER_PAGE_SIZE));
    if (snapshot.docs.length > RECONCILER_PAGE_SIZE) throw new InvariantError(spec.invariant, "page");
    const seen = new Set();
    for (const row of snapshot.docs) {
      if (!spec.workIdRe.test(row.id)) throw new InvariantError(spec.invariant, "invalid work id");
      if (seen.has(row.id) || (state.cursor_id !== "" && compareUTF8(row.id, state.cursor_id) <= 0)) throw new InvariantError(spec.invariant, "query drift");
      seen.add(row.id);
    }
    return { cursor: state.cursor_id, rows: snapshot.docs.map((row) => ({ id: row.id, data: row.data() })) };
  });
  if (page.rows.length === 0) {
    if (page.cursor !== "") await writeCursor(deps, run, "");
    return;
  }
  let selected = null;
  for (const row of page.rows) {
    let work;
    try {
      work = validateWorkRow(run.which, row.id, row.data);
    } catch (error) {
      emit(deps, spec.workInvariant);
      await writeCursor(deps, run, row.id);
      continue;
    }
    if (work.next_eligible_run <= run.ordinal) { selected = { id: row.id, work }; break; }
  }
  if (selected === null) {
    await writeCursor(deps, run, page.rows[page.rows.length - 1].id);
    return;
  }
  await writeCursor(deps, run, selected.id);
  if (deps.hooks && typeof deps.hooks.beforeReducer === "function") deps.hooks.beforeReducer(selected.work.account_uid, selected.id);
  if (run.which === "storage") await reduceStorageRow(deps, run, selected);
  else await reduceAuthRow(deps, run, selected);
}

async function runReconciler(which, event, deps) {
  const spec = RECONCILERS[which];
  let boundary;
  try {
    boundary = parseScheduleBoundary(event, spec.boundaryOffset);
  } catch (error) {
    emit(deps, error.code);
    return;
  }
  const evidence = deps.evidence();
  if (!evidence || evidence.ok !== true) { emit(deps, (evidence && evidence.code) || "PROVIDER_EVIDENCE_NOT_ACTIVATED"); return; }
  let fenceResult;
  try {
    fenceResult = await deps.evidenceFence(evidence.authority);
  } catch (error) {
    emit(deps, error instanceof InvariantError ? error.code : PROVIDER_EVIDENCE_INVARIANT);
    return;
  }
  let lease;
  try {
    lease = await acquireReconciler(deps, which, boundary);
  } catch (error) {
    emit(deps, error instanceof InvariantError ? error.code : spec.invariant);
    return;
  }
  if (lease === null) return;
  const run = { which, spec, lease, ordinal: boundary.ordinal, authority: evidence.authority, fence: fenceResult };
  try {
    await runReconcilerBody(deps, run);
    await settleReconciler(deps, run);
  } catch (error) {
    emit(deps, error instanceof InvariantError ? error.code : spec.invariant);
  }
}

function runStorageReconciler(event, deps) { return runReconciler("storage", event, deps); }
function runAuthReconciler(event, deps) { return runReconciler("auth", event, deps); }

async function recordWorkBackoff(deps, run, { workRef, work, code }) {
  emit(deps, code);
  await fencedTransaction(deps, run, async (transaction, { readTime }) => {
    const snapshot = await transaction.get(workRef);
    if (!snapshot.exists || TaskCanonicalV1(snapshot.data()) !== TaskCanonicalV1(work)) return;
    const count = Math.min(work.failure_count + 1, FAILURE_COUNT_MAX);
    const next = { ...work, failure_count: count, next_eligible_run: run.ordinal + Math.min(2 ** count, 16), updated_at: readTime };
    if (run.which === "storage") validateStorageWork(next); else validateAuthWork(next);
    transaction.set(workRef, next);
  });
}

// ---- Storage row reducer (§11.3:1672–1682)

async function reduceStorageRow(deps, run, selected) {
  const uid = selected.work.account_uid;
  const rootRef = deps.db.doc(`users/${uid}`);
  const workRef = deps.db.doc(`accountDeletionStorageWork/${selected.id}`);
  const view = await fencedTransaction(deps, run, async (transaction) => {
    const rootSnapshot = await transaction.get(rootRef);
    const workSnapshot = await transaction.get(workRef);
    if (!workSnapshot.exists || TaskCanonicalV1(workSnapshot.data()) !== TaskCanonicalV1(selected.work)) return null;
    const root = rootSnapshot.exists ? rootSnapshot.data() : undefined;
    let validated;
    try { validated = validateAccountDeletionMarker(root?.accountDeletion); } catch { return null; }
    if (validated.phase !== "DELETING_SWEEPING" && validated.phase !== "DELETING_GUARDING") return null;
    try { validateStorageWork(selected.work, { uid, marker: validated.marker }); } catch { return null; }
    return { marker: validated.marker, phase: validated.phase };
  });
  if (view === null) { emit(deps, run.spec.workInvariant); return; }
  try {
    await verifyBucketGate(deps, deps.bucket);
    const admit = () => fencedTransaction(deps, run, async () => {});
    let progressed = false;
    let emptyBoth = true;
    for (const prefix of [`inventory/${uid}/`, `users/${uid}/`]) {
      const result = await sweepStoragePrefix(deps, deps.bucket, prefix, { limit: 20, pages: 1, admit });
      if (result.hit) { progressed = true; emptyBoth = false; break; }
      if (!result.empty) { emptyBoth = false; break; }
    }
    await fencedTransaction(deps, run, async (transaction, { readTime }) => {
      const rootSnapshot = await transaction.get(rootRef);
      const workSnapshot = await transaction.get(workRef);
      if (!workSnapshot.exists || TaskCanonicalV1(workSnapshot.data()) !== TaskCanonicalV1(selected.work)) throw new InvariantError(run.spec.workInvariant, "drift");
      const current = validateAccountDeletionMarker(rootSnapshot.data()?.accountDeletion).marker;
      if (TaskCanonicalV1(current) !== TaskCanonicalV1(view.marker)) throw new InvariantError("ACCOUNT_DELETION_MARKER_DRIFT");
      let marker = current;
      if (emptyBoth && view.phase === "DELETING_GUARDING") {
        if (marker.storageGuardCompletedAt === undefined && millis(readTime) > millis(marker.storageGuardAfter)) {
          marker = { ...marker, storageGuardCompletedAt: readTime };
        }
        if (marker.firestoreVersionGuardCompletedAt === undefined && run.fence && isTimestampLike(run.fence.earliestVersionTime) &&
            millis(run.fence.earliestVersionTime) > millis(marker.firestoreCleanupAt)) {
          marker = { ...marker, firestoreVersionGuardCompletedAt: readTime };
        }
        if (marker.storageGuardCompletedAt !== undefined && marker.firestoreVersionGuardCompletedAt !== undefined) {
          const leases = await transaction.get(leasesQuery(deps.db, uid));
          requireZeroLeaseDocuments(leases);
          const done = { ...marker, state: "DATA_DELETED", dataDeletedAt: readTime };
          validateAccountDeletionMarker(done);
          transaction.update(rootRef, { accountDeletion: done });
          transaction.delete(workRef);
          return;
        }
      }
      if (marker !== current) {
        validateAccountDeletionMarker(marker);
        transaction.update(rootRef, { accountDeletion: marker });
      }
      const next = { ...selected.work, failure_count: 0, next_eligible_run: run.ordinal + 1, updated_at: readTime };
      validateStorageWork(next, { uid, marker });
      transaction.set(workRef, next);
    });
    if (progressed) emit(deps, "ACCOUNT_DELETION_STORAGE_PROGRESS");
  } catch (error) {
    if (error instanceof InvariantError && SYSTEMIC_CODES.has(error.code)) throw error;
    const code = error instanceof InvariantError ? error.code : "ACCOUNT_DELETION_STORAGE_PROVIDER_FAILURE";
    await recordWorkBackoff(deps, run, { workRef, work: selected.work, code });
  }
}

// ---- Auth row reducer (§11.3:1700–1704)

function substituteUID(template, uid, encoding) {
  const value = encoding === "percent_utf8" ? encodeURIComponent(uid) : sha256Hex(TaskCanonicalV1({ account_uid: uid }));
  return template.split("{{UID}}").join(value);
}

/** Runs every residual check for `uid`; the Firebase branch is proved by the caller's fresh user-not-found. */
async function runResidualChecks(deps, authority, uid, readTime) {
  for (const check of authority.authResidualChecks) {
    if (check.adapterId === "firebase_admin_get_user_v1") continue;
    if (check.kind === "absence_retention") {
      if (Date.parse(check.observedAbsentAt) + check.retentionSeconds * 1000 > millis(readTime)) throw new InvariantError("ACCOUNT_DELETION_RESIDUAL_RETENTION_PENDING");
      continue;
    }
    const request = {
      url: substituteUID(check.resourceURLTemplate, uid, check.uidEncoding), method: check.method,
      headers: check.method === "POST" ? { accept: "application/json", "content-type": "application/json" } : { accept: "application/json" },
      deadlineMs: deps.timeouts.providerMs, maxBytes: PROVIDER_RESPONSE_CAP, redirects: 0
    };
    if (check.method === "POST") request.body = substituteUID(check.bodyTemplate, uid, check.uidEncoding);
    let response;
    try {
      response = await withDeadline(deps.providerHTTP.request(request), deps.timeouts.providerMs, "ACCOUNT_DELETION_RESIDUAL_TRANSPORT");
    } catch { throw new InvariantError("ACCOUNT_DELETION_RESIDUAL_TRANSPORT"); }
    if (!response || response.status !== 200) throw new InvariantError("ACCOUNT_DELETION_RESIDUAL_MALFORMED", "status");
    const media = headerValue(response.headers, "content-type");
    if (typeof media !== "string" || !media.toLowerCase().startsWith("application/json")) throw new InvariantError("ACCOUNT_DELETION_RESIDUAL_MALFORMED", "media");
    if (!Buffer.isBuffer(response.body) || response.body.length > PROVIDER_RESPONSE_CAP) throw new InvariantError("ACCOUNT_DELETION_RESIDUAL_MALFORMED", "size");
    let parsed;
    try { parsed = parseStrictJSON(response.body.toString("utf8")); } catch { throw new InvariantError("ACCOUNT_DELETION_RESIDUAL_MALFORMED", "json"); }
    if (!isPlainMap(parsed)) throw new InvariantError("ACCOUNT_DELETION_RESIDUAL_MALFORMED", "object");
    const count = parsed[check.zeroCountField];
    if (!Number.isSafeInteger(count)) throw new InvariantError("ACCOUNT_DELETION_RESIDUAL_MALFORMED", "count");
    if (count !== 0) throw new InvariantError("ACCOUNT_DELETION_RESIDUAL_NONZERO");
  }
}

async function reduceAuthRow(deps, run, selected) {
  const uid = selected.work.account_uid;
  const authority = run.authority;
  const rootRef = deps.db.doc(`users/${uid}`);
  const workRef = deps.db.doc(`accountDeletionAuthWork/${selected.id}`);
  const guard = (transaction) => assertLeaseLive(transaction, deps, run);
  const view = await fencedTransaction(deps, run, async (transaction, { readTime }) => {
    const rootSnapshot = await transaction.get(rootRef);
    const workSnapshot = await transaction.get(workRef);
    if (!workSnapshot.exists || TaskCanonicalV1(workSnapshot.data()) !== TaskCanonicalV1(selected.work)) return null;
    let validated;
    try { validated = validateAccountDeletionMarker(rootSnapshot.data()?.accountDeletion); } catch { return null; }
    return { marker: validated.marker, phase: validated.phase, readTime };
  });
  if (view === null) { emit(deps, run.spec.workInvariant); return; }
  const work = selected.work;
  if (work.authority_generation_id !== authority.generationId || work.authority_sha256 !== authority.authoritySHA256) {
    emit(deps, run.spec.workInvariant);
    return;
  }
  if (work.state === "delete_pending") {
    if (view.phase !== "DATA_DELETED" || !sameInstant(work.data_deleted_at, view.marker.dataDeletedAt)) { emit(deps, run.spec.workInvariant); return; }
    await runAuthPendingReducer(deps, { uid, marker: view.marker, work, authority, scheduleOrdinal: run.ordinal, guard });
    return;
  }
  // guarding
  if (view.phase !== "AUTH_GUARDING" || !sameInstant(view.marker.authGuardAfter, work.auth_guard_after)) { emit(deps, run.spec.workInvariant); return; }
  try { validateAuthWork(work, { uid, authResidualRetentionSeconds: authority.authResidualRetentionSeconds }); } catch { emit(deps, run.spec.workInvariant); return; }
  if (millis(view.readTime) <= millis(work.auth_guard_after)) {
    await fencedTransaction(deps, run, async (transaction, { readTime }) => {
      const snapshot = await transaction.get(workRef);
      if (!snapshot.exists || TaskCanonicalV1(snapshot.data()) !== TaskCanonicalV1(work)) return;
      const next = { ...work, next_eligible_run: firstAuthOrdinalAfter(work.auth_guard_after), updated_at: readTime };
      validateAuthWork(next, { uid });
      transaction.set(workRef, next);
    });
    return;
  }
  try {
    let absent = false;
    try {
      await withDeadline(deps.auth.getUser(uid), deps.timeouts.getUserMs, "ACCOUNT_DELETION_AUTH_TIMEOUT");
    } catch (error) {
      if (isUserNotFound(error)) absent = true;
      else throw new InvariantError("ACCOUNT_DELETION_AUTH_TRANSPORT");
    }
    if (!absent) throw new InvariantError("ACCOUNT_DELETION_AUTH_PRESENT");
    await runResidualChecks(deps, authority, uid, view.readTime);
    await fencedTransaction(deps, run, async (transaction, { readTime }) => {
      const rootSnapshot = await transaction.get(rootRef);
      const workSnapshot = await transaction.get(workRef);
      if (!workSnapshot.exists || TaskCanonicalV1(workSnapshot.data()) !== TaskCanonicalV1(work)) throw new InvariantError(run.spec.workInvariant, "drift");
      const current = validateAccountDeletionMarker(rootSnapshot.data()?.accountDeletion).marker;
      if (TaskCanonicalV1(current) !== TaskCanonicalV1(view.marker)) throw new InvariantError("ACCOUNT_DELETION_MARKER_DRIFT");
      if (millis(readTime) <= millis(current.authGuardAfter)) throw new InvariantError("ACCOUNT_DELETION_RESIDUAL_RETENTION_PENDING");
      const done = { ...current, state: "ACCOUNT_DELETED", authGuardCompletedAt: readTime, accountDeletedAt: readTime };
      validateAccountDeletionMarker(done);
      transaction.update(rootRef, { accountDeletion: done });
      transaction.delete(workRef);
    });
    emit(deps, "ACCOUNT_DELETION_ACCOUNT_DELETED");
  } catch (error) {
    if (error instanceof InvariantError && SYSTEMIC_CODES.has(error.code)) throw error;
    const code = error instanceof InvariantError ? error.code : "ACCOUNT_DELETION_AUTH_PROVIDER_FAILURE";
    await recordWorkBackoff(deps, run, { workRef, work, code });
  }
}

// ---- Historical migration entry (§11.3:1704, §11.4) — the core the S3 CLI drives

async function createMigrationMarker(deps, { uid }) {
  if (!isUID(uid)) throw new Error("createMigrationMarker: invalid uid");
  const operationId = `adel1_${randomUUID()}`;
  const proofNonce = Buffer.from(randomUUID().replace(/-/g, "") + randomUUID().replace(/-/g, ""), "hex").toString("base64url");
  const data = { uid, operationId, proofNonce };
  const ctx = { uid, operationId, rootRef: deps.db.doc(`users/${uid}`) };
  const marker = await deps.db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ctx.rootRef);
    const root = snapshot.exists ? snapshot.data() : undefined;
    if (root && root.accountDeletion !== undefined) throw new InvariantError("ACCOUNT_DELETION_MARKER_PRESENT");
    await pruneLeasesForBegin(transaction, deps, ctx);
    return createMarkerAndWork(transaction, deps, ctx, snapshot, data);
  });
  return { operationId, proofSHA256: marker.capabilities[0].proofSHA256 };
}

/** After data-final: a fresh canonical user-not-found enters guarding without an Auth delete. */
async function enterHistoricalGuarding(deps, { uid }) {
  const authority = requireEvidence(deps);
  const rootRef = deps.db.doc(`users/${uid}`);
  const marker = await deps.db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(rootRef);
    const validated = validateAccountDeletionMarker(snapshot.data()?.accountDeletion);
    if (validated.phase !== "DATA_DELETED") throw new InvariantError("ACCOUNT_DELETION_MARKER_MALFORMED", "phase");
    return validated.marker;
  });
  try {
    await withDeadline(deps.auth.getUser(uid), deps.timeouts.getUserMs, "ACCOUNT_DELETION_AUTH_TIMEOUT");
    throw new InvariantError("LEGACY_ACCOUNT_AUTH_RACE");
  } catch (error) {
    if (!isUserNotFound(error)) throw error instanceof InvariantError ? error : new InvariantError("LEGACY_ACCOUNT_AUTH_RACE");
  }
  const workRef = authWorkRef(deps, uid);
  const guarding = await deps.db.runTransaction(async (transaction) => {
    const rootSnapshot = await transaction.get(rootRef);
    const current = validateAccountDeletionMarker(rootSnapshot.data()?.accountDeletion).marker;
    if (TaskCanonicalV1(current) !== TaskCanonicalV1(marker)) throw new InvariantError("ACCOUNT_DELETION_MARKER_DRIFT");
    const workSnapshot = await transaction.get(workRef);
    if (workSnapshot.exists) throw new InvariantError("ACCOUNT_DELETION_AUTH_WORK_INVARIANT", "present");
    const readTime = readTimeOf(rootSnapshot, deps);
    const authGuardAfter = plusSeconds(readTime, authority.authResidualRetentionSeconds);
    const next = { ...current, state: "AUTH_GUARDING", authAbsenceObservedAt: readTime, authGuardAfter };
    validateAccountDeletionMarker(next);
    const work = {
      schema_version: 1, kind: "ACCOUNT_DELETION_AUTH_WORK", work_id: authWorkId(uid), account_uid: uid, state: "guarding",
      data_deleted_at: current.dataDeletedAt, authority_generation_id: authority.generationId, authority_sha256: authority.authoritySHA256,
      failure_count: 0, next_eligible_run: firstAuthOrdinalAfter(authGuardAfter), created_at: readTime, updated_at: readTime,
      auth_absence_observed_at: readTime, auth_guard_after: authGuardAfter
    };
    validateAuthWork(work, { uid, authResidualRetentionSeconds: authority.authResidualRetentionSeconds });
    transaction.update(rootRef, { accountDeletion: next });
    transaction.create(workRef, work);
    return next;
  });
  return { transitioned: true, marker: guarding };
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
    metric: (name, value) => logger.info("phase2_metric", { metric: name, value }),
    firestore: { client: new v1.FirestoreClient(), documentsRoot: `projects/${projectId}/databases/(default)/documents` },
    firestoreAdmin: new v1.FirestoreAdminClient(),
    providerHTTP: productionProviderHTTP(),
    evidence: () => loadedEvidence(),
    evidenceFence: (authority) => runEvidenceFence(productionCache, authority),
    verifyBucketConfiguration: (tuple) => {
      const evidence = loadedEvidence();
      if (!evidence.ok) throw new InvariantError("ACCOUNT_DELETION_BUCKET_CONFIG_DRIFT", "no accepted configuration");
      verifyBucketConfiguration(tuple, evidence.authority);
    },
    budget: { sweeps: 4, storagePages: 4, deadlineMs: 42_000 },
    timeouts: { getUserMs: 3000, deleteUserMs: 10000, providerMs: 3000 },
    hooks: {}
  };
  return productionCache;
}

let evidenceCache = null;

/** Reads the sole runtime authority once; absent file or unsupplied trust anchor is Build A. */
function loadedEvidence() {
  if (evidenceCache) return evidenceCache;
  const fs = require("node:fs");
  const path = require("node:path");
  const artifactPath = path.join(__dirname, "accountDeletionProviderEvidenceV1.json");
  const bytes = fs.existsSync(artifactPath) ? fs.readFileSync(artifactPath) : undefined;
  evidenceCache = loadProviderEvidenceAuthority(bytes, { trustAnchor: PROVIDER_EVIDENCE_TRUST_ANCHOR_V1 });
  return evidenceCache;
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
  // provider evidence authority and the bounded fence
  PROVIDER_EVIDENCE_TRUST_ANCHOR_V1, parseStrictJSON, loadProviderEvidenceAuthority, validateAuthResidualChecks,
  projectBucketDeletionConfig, verifyBucketConfiguration, verifyFirestoreConfiguration, runPolicyChecks, runEvidenceFence,
  // reconcilers and the historical entry
  validateReconcilerState, parseScheduleBoundary, runStorageReconciler, runAuthReconciler, runResidualChecks,
  createMigrationMarker, enterHistoricalGuarding,
  // misc
  withDeadline, readTimeOf, requireEvidence, emit, productionDependencies, loadedEvidence, withFixedErrorBoundary
};
