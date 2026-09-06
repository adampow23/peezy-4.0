"use strict";

/**
 * PHASE2_CONTRACT.md C9.3 — notification intents and claimTaskIntent (S3 I10).
 *
 * The scheduler wake transaction is the only intent producer (`produceWake`); the claim callable is the only client
 * path (`executeClaimTaskIntent`). Rules deny every client read or write of `users/{uid}/notificationIntents`.
 */

const { HttpsError } = require("firebase-functions/v2/https");
const { Timestamp, FieldValue } = require("firebase-admin/firestore");
const fence = require("./accountDeletionFence");

const INTENT_TTL_MS = 24 * 60 * 60 * 1000;
const RESPONSE_CAP_BYTES = 65536;
const RECORD_CAP_BYTES = 589824;
const INTENT_ID_RE = /^ni1_[0-9a-f]{40}$/;
const WAKE_ID_RE = /^w1_[0-9a-f]{40}$/;
const RESERVED_CLAIM_ID_RE = /^(rsa1_|rso1_|pcs1_)/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const WIRE_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const INTENT_STATES = Object.freeze(["pending", "consumed", "cancelled"]);
const INTENT_MEMBERS = "audience,cause,created_at,expires_at,interaction_epoch,interaction_revision,kind,policy_fingerprint,route,schema_version,state,task_document_id,task_instance_id";
const OPTIONAL_INTENT_MEMBERS = Object.freeze(["consumed_at", "claim_operation_id"]);

function canonical(map) { return fence.TaskCanonicalV1(map); }
function first40(map) { return fence.first40(fence.sha256Hex(canonical(map))); }
function isNonBlankString(value) { return typeof value === "string" && value.length > 0; }
function isSafeNonNegative(value) { return Number.isSafeInteger(value) && value >= 0; }
function isTimestamp(value) { return value instanceof Timestamp; }

function failedPrecondition(reason, extra) {
  return new HttpsError("failed-precondition", reason, { schemaVersion: 1, reason, ...(extra || {}) });
}
function requestInvalid(reason = "REQUEST_INVALID") {
  return new HttpsError("invalid-argument", reason, { schemaVersion: 1, reason: "REQUEST_INVALID" });
}

// ---------------------------------------------------------------------------
// C9.3.1 identities, shapes, validators
// ---------------------------------------------------------------------------

function validateRoute(route) {
  if (route === null || typeof route !== "object" || Array.isArray(route)) throw new Error("route");
  const keys = Object.keys(route).sort().join(",");
  if (route.kind === "row") { if (keys !== "kind") throw new Error("route row members"); return { kind: "row" }; }
  if (route.kind === "outcome") {
    if (keys === "kind") return { kind: "outcome" };
    if (keys === "kind,session_id" && isNonBlankString(route.session_id)) return { kind: "outcome", session_id: route.session_id };
    throw new Error("route outcome members");
  }
  throw new Error("route kind");
}

function validateCause(cause) {
  if (cause === null || typeof cause !== "object" || Array.isArray(cause)) throw new Error("cause");
  const keys = Object.keys(cause).sort();
  if (cause.kind === "TRIGGER") {
    if (!keys.every((k) => ["kind", "original_trigger", "event_high_water"].includes(k)) || cause.original_trigger === undefined) throw new Error("cause trigger members");
    return cause;
  }
  if (cause.kind === "THRESHOLD") {
    if (!keys.every((k) => ["kind", "threshold_id", "deadline_evidence_id", "threshold_at", "consequence_class", "displaced_trigger"].includes(k))) throw new Error("cause threshold members");
    if (!isNonBlankString(cause.threshold_id) || !isNonBlankString(cause.deadline_evidence_id) || !isTimestamp(cause.threshold_at)) throw new Error("cause threshold values");
    return cause;
  }
  throw new Error("cause kind");
}

/** C6.1: a shared writer mutates only `users/{uid}/tasks/{id}` beneath the owner root it fences. */
function requireTaskOwner(uid, taskRef) {
  const parts = taskRef && typeof taskRef.path === "string" ? taskRef.path.split("/") : [];
  if (parts.length !== 4 || parts[0] !== "users" || parts[1] !== uid || parts[2] !== "tasks" || !isNonBlankString(parts[3])) throw new Error("task owner");
}

function wakeIdFor({ uid, taskDocumentId, taskInstanceId, interactionEpoch, policyFingerprint, cause }) {
  return `w1_${first40({ uid, task_document_id: taskDocumentId, task_instance_id: taskInstanceId, interaction_epoch: interactionEpoch, policy_fingerprint: policyFingerprint, cause })}`;
}

function intentIdFor({ uid, taskDocumentId, taskInstanceId, interactionEpoch, policyFingerprint, route, wakeId }) {
  return `ni1_${first40({ uid, task_document_id: taskDocumentId, task_instance_id: taskInstanceId, interaction_epoch: interactionEpoch, policy_fingerprint: policyFingerprint, route, cause: { wake_evidence_id: wakeId } })}`;
}

function intentRefFor(db, uid, intentId) { return db.doc(`users/${uid}/notificationIntents/${intentId}`); }

/** Exact C9.3.1 intent document; throws `Error(detail)` on any defect. */
function validateIntent(data) {
  if (data === null || typeof data !== "object" || Array.isArray(data)) throw new Error("map");
  const keys = Object.keys(data);
  const required = keys.filter((k) => !OPTIONAL_INTENT_MEMBERS.includes(k)).sort().join(",");
  if (required !== INTENT_MEMBERS) throw new Error("members");
  if (data.schema_version !== 1 || data.audience !== "user" || data.kind !== "task_resume") throw new Error("constants");
  if (!INTENT_STATES.includes(data.state)) throw new Error("state");
  if (!isNonBlankString(data.task_document_id) || !isNonBlankString(data.task_instance_id) || !isNonBlankString(data.policy_fingerprint)) throw new Error("identity");
  if (!isSafeNonNegative(data.interaction_epoch) || !isSafeNonNegative(data.interaction_revision)) throw new Error("epoch");
  validateRoute(data.route);
  if (data.cause === null || typeof data.cause !== "object" || Object.keys(data.cause).join(",") !== "wake_evidence_id" || !WAKE_ID_RE.test(String(data.cause.wake_evidence_id))) throw new Error("cause");
  if (!isTimestamp(data.created_at) || !isTimestamp(data.expires_at)) throw new Error("times");
  if (data.expires_at.toMillis() !== data.created_at.toMillis() + INTENT_TTL_MS) throw new Error("expiry");
  if (data.state === "consumed") {
    if (!isTimestamp(data.consumed_at) || !isNonBlankString(data.claim_operation_id)) throw new Error("consumed members");
  } else if (data.consumed_at !== undefined || data.claim_operation_id !== undefined) throw new Error("surplus consumed members");
  return data;
}

function validateIntentIdentity(uid, intentId, data) {
  const expected = intentIdFor({ uid, taskDocumentId: data.task_document_id, taskInstanceId: data.task_instance_id, interactionEpoch: data.interaction_epoch, policyFingerprint: data.policy_fingerprint, route: data.route, wakeId: data.cause.wake_evidence_id });
  if (expected !== intentId) throw new Error("intent id");
}

const WAKE_MEMBERS = "cause,fired_at,intent_id,resume_destination,schema_version,task_instance_id,wake_id";

/** C9.3.1 wake evidence grammar: exact members, timestamp, urgency enum, and a basis exactly when urgent. */
function validateWakeEvidence(wake) {
  if (wake === null || typeof wake !== "object" || Array.isArray(wake)) throw new Error("wake shape");
  const keys = Object.keys(wake).filter((k) => k !== "urgency" && k !== "urgency_basis").sort().join(",");
  if (keys !== WAKE_MEMBERS) throw new Error("wake members");
  if (wake.schema_version !== 1 || !WAKE_ID_RE.test(String(wake.wake_id)) || !INTENT_ID_RE.test(String(wake.intent_id))) throw new Error("wake identity");
  if (!isNonBlankString(wake.task_instance_id) || !isNonBlankString(wake.resume_destination) || !isTimestamp(wake.fired_at)) throw new Error("wake values");
  if (!["normal", "urgent_recovery"].includes(wake.urgency)) throw new Error("wake urgency");
  const basis = wake.urgency_basis;
  if (wake.urgency === "urgent_recovery" ? basis === null || typeof basis !== "object" || Array.isArray(basis) : basis !== undefined) throw new Error("wake urgency basis");
  validateCause(wake.cause);
  return wake;
}

/** C9.3.1 pointer validation: missing, dangling, crossed-task, crossed-instance, or unequal pointers reject. */
function validateWakePointer(task, taskDocumentId, intent, intentId) {
  const wake = task && task.wakeEvidence;
  if (!wake || typeof wake !== "object") throw new Error("pointer missing");
  if (wake.schema_version !== 1 || wake.intent_id !== intentId) throw new Error("pointer unequal");
  if (wake.wake_id !== intent.cause.wake_evidence_id) throw new Error("pointer dangling");
  if (intent.task_document_id !== taskDocumentId) throw new Error("pointer crossed task");
  if (wake.task_instance_id !== intent.task_instance_id || task.task_instance_id !== intent.task_instance_id) throw new Error("pointer crossed instance");
  return wake;
}

// ---------------------------------------------------------------------------
// Producer (scheduler wake transaction) and fresh-command cancellation
// ---------------------------------------------------------------------------

/**
 * Creates the wake evidence on the task and its one intent atomically within the caller's transaction.
 * Identity is deterministic, so a transaction retry produces the same IDs and bytes.
 */
async function produceWake(transaction, db, params) {
  const { uid, taskRef, task, cause, route, resumeDestination, urgency, urgencyBasis, interactionEpoch, interactionRevision, policyFingerprint, now } = params;
  if (!isNonBlankString(uid) || !taskRef || !task || !isTimestamp(now)) throw new Error("produceWake params");
  requireTaskOwner(uid, taskRef);
  if (!isNonBlankString(task.task_instance_id)) throw new Error("task instance");
  if (!["normal", "urgent_recovery"].includes(urgency)) throw new Error("urgency");
  if (urgency === "urgent_recovery" && !urgencyBasis) throw new Error("urgency basis");
  if (!isNonBlankString(resumeDestination) || !isNonBlankString(policyFingerprint) || !isSafeNonNegative(interactionEpoch) || !isSafeNonNegative(interactionRevision)) throw new Error("wake params");
  const cleanRoute = validateRoute(route);
  const cleanCause = validateCause(cause);
  const taskDocumentId = taskRef.id;
  const wakeId = wakeIdFor({ uid, taskDocumentId, taskInstanceId: task.task_instance_id, interactionEpoch, policyFingerprint, cause: cleanCause });
  const intentId = intentIdFor({ uid, taskDocumentId, taskInstanceId: task.task_instance_id, interactionEpoch, policyFingerprint, route: cleanRoute, wakeId });
  const wakeEvidence = { schema_version: 1, task_instance_id: task.task_instance_id, wake_id: wakeId, cause: cleanCause, fired_at: now, resume_destination: resumeDestination, urgency, ...(urgencyBasis ? { urgency_basis: urgencyBasis } : {}), intent_id: intentId };
  const intent = {
    schema_version: 1, audience: "user", kind: "task_resume", state: "pending",
    task_document_id: taskDocumentId, task_instance_id: task.task_instance_id, interaction_epoch: interactionEpoch, interaction_revision: interactionRevision,
    policy_fingerprint: policyFingerprint, route: cleanRoute, cause: { wake_evidence_id: wakeId }, created_at: now, expires_at: Timestamp.fromMillis(now.toMillis() + INTENT_TTL_MS)
  };
  validateIntent(intent);
  const intentRef = intentRefFor(db, uid, intentId);
  await fence.assertDeletionAbsent(transaction, db, [uid]); // C6.1: the shared child fences its own owner root
  // C9.3.1 exact retry: an existing pair with the same identities is returned untouched (a consumed or cancelled
  // intent is never rewritten to pending); any other existing wake under this pointer fails closed, never overwritten
  if (task.wakeEvidence !== undefined) {
    const existingSnapshot = await transaction.get(intentRef);
    const existing = existingSnapshot.exists ? existingSnapshot.data() : null;
    const wake = task.wakeEvidence;
    // both documents must validate and carry exactly this pair's identity and content; only lifecycle members may differ
    const lifecycle = ({ state, created_at, expires_at, consumed_at, claim_operation_id, ...rest }) => rest;
    const stable = ({ fired_at, urgency, urgency_basis, ...rest }) => rest;
    let same = false;
    try {
      validateIntent(existing);
      validateIntentIdentity(uid, intentId, existing);
      validateWakeEvidence(wake);
      same = wake !== null && typeof wake === "object" && !Array.isArray(wake)
        && canonical(stable(wake)) === canonical(stable(wakeEvidence))
        && canonical(lifecycle(existing)) === canonical(lifecycle(intent));
    } catch (error) { same = false; }
    if (!same) throw new Error("incompatible wake");
    return { wakeId, intentId, wakeEvidence: wake, intent: existing };
  }
  transaction.update(taskRef, { wakeEvidence });
  transaction.create(intentRef, intent);
  return { wakeId, intentId, wakeEvidence, intent };
}

/** In-place normal → urgent_recovery upgrade: retains the pointer, creates no second intent. */
async function upgradeWakeUrgency(transaction, db, uid, taskRef, task, urgencyBasis) {
  const wake = task && task.wakeEvidence;
  if (!wake || wake.schema_version !== 1 || !WAKE_ID_RE.test(String(wake.wake_id))) throw new Error("wake missing");
  if (!urgencyBasis) throw new Error("urgency basis");
  requireTaskOwner(uid, taskRef);
  await fence.assertDeletionAbsent(transaction, db, [uid]); // C6.1
  const next = { ...wake, urgency: "urgent_recovery", urgency_basis: urgencyBasis };
  transaction.update(taskRef, { wakeEvidence: next });
  return next;
}

/** Fresh successful command: cancels the task's pending intent and clears the wake pointer atomically. */
async function cancelPendingIntent(transaction, db, uid, taskRef, task) {
  const wake = task && task.wakeEvidence;
  if (!wake || typeof wake !== "object" || !isNonBlankString(wake.intent_id)) return null;
  requireTaskOwner(uid, taskRef);
  const ref = intentRefFor(db, uid, wake.intent_id);
  const snapshot = await transaction.get(ref);
  await fence.assertDeletionAbsent(transaction, db, [uid]); // C6.1
  // C9.3.1 pair atomicity: only the task's own exact pair is cancelled; a missing, dangling, crossed, or unequal pointer rejects
  if (!snapshot.exists) throw new Error("pointer dangling");
  validateWakePointer(task, taskRef.id, snapshot.data(), wake.intent_id);
  if (snapshot.data().state === "pending") transaction.update(ref, { state: "cancelled" });
  transaction.update(taskRef, { wakeEvidence: FieldValue.delete() });
  return wake.intent_id;
}

// ---------------------------------------------------------------------------
// C9.3.2 – C9.3.5 claimTaskIntent
// ---------------------------------------------------------------------------

/** CallableTimestampWireV1: exact UTC "YYYY-MM-DDTHH:mm:ss.SSSZ"; anything outside the four-digit-year projection is invalid. */
function timestampWire(timestamp) {
  const text = new Date(timestamp.toMillis()).toISOString();
  if (!WIRE_RE.test(text)) throw new Error("wire");
  return text;
}

function validateClaimRequest(input) {
  if (input === null || typeof input !== "object" || Array.isArray(input)) throw requestInvalid();
  if (Object.keys(input).sort().join(",") !== "action,claimOperationId,intentId") throw requestInvalid();
  if (input.action !== "claimTaskIntent") throw requestInvalid();
  if (!INTENT_ID_RE.test(String(input.intentId))) throw requestInvalid();
  const claimOperationId = input.claimOperationId;
  if (typeof claimOperationId !== "string" || !UUID_RE.test(claimOperationId) || RESERVED_CLAIM_ID_RE.test(claimOperationId)) throw requestInvalid();
  return { action: "claimTaskIntent", intentId: input.intentId, claimOperationId };
}

function requestSha256(request) {
  return fence.sha256Hex(canonical({ action: "claimTaskIntent", intentId: request.intentId, claimOperationId: request.claimOperationId }));
}

const RECORD_MEMBERS = "account_uid,action,committed_at,created_at,kind,operation_id,prior_snapshots,request_fingerprint,request_sha256,response,response_sha256,schema_version,state,task_identities";

/** Exact INTENT_CLAIM record; any defect is OPERATION_REUSED with zero intent mutation. */
function validateClaimRecord(record, uid, request) {
  const reject = () => failedPrecondition("OPERATION_REUSED", { operationId: request.claimOperationId });
  if (record === null || typeof record !== "object" || Array.isArray(record)) throw reject();
  if (Object.keys(record).sort().join(",") !== RECORD_MEMBERS) throw reject();
  const sha = requestSha256(request);
  if (record.schema_version !== 1 || record.kind !== "INTENT_CLAIM" || record.state !== "COMMITTED" || record.account_uid !== uid || record.operation_id !== request.claimOperationId || record.action !== "claimTaskIntent") throw reject();
  if (record.request_sha256 !== sha || record.request_fingerprint !== `op1_${sha}`) throw reject();
  if (!Array.isArray(record.task_identities) || record.task_identities.length !== 0 || !Array.isArray(record.prior_snapshots) || record.prior_snapshots.length !== 0) throw reject();
  if (!isClaimResponse(record.response, uid, request)) throw reject();
  if (record.response_sha256 !== fence.sha256Hex(canonical(record.response))) throw reject();
  if (!isTimestamp(record.created_at) || !isTimestamp(record.committed_at) || record.created_at.toMillis() !== record.committed_at.toMillis()) throw reject();
  return record;
}

const RESPONSE_MEMBERS = "accountUid,claimOperationId,expiresAt,intentId,interactionEpoch,kind,policyFingerprint,replayed,route,schemaVersion,taskDocumentId,taskGenerationEpoch,taskInstanceId";

/** C9.3.3: the stored `task_route` response is the closed typed wire; any other shape, value, or size is a reuse defect. */
function isClaimResponse(response, uid, request) {
  if (response === null || typeof response !== "object" || Array.isArray(response)) return false;
  if (Object.keys(response).sort().join(",") !== RESPONSE_MEMBERS) return false;
  if (response.schemaVersion !== 1 || response.kind !== "task_route" || response.replayed !== false) return false;
  if (response.accountUid !== uid || response.claimOperationId !== request.claimOperationId || response.intentId !== request.intentId) return false;
  if (!isNonBlankString(response.taskDocumentId) || !isNonBlankString(response.taskInstanceId) || !isNonBlankString(response.policyFingerprint)) return false;
  if (!(response.taskGenerationEpoch === null || Number.isSafeInteger(response.taskGenerationEpoch)) || !isSafeNonNegative(response.interactionEpoch)) return false;
  const route = response.route;
  if (route === null || typeof route !== "object" || Array.isArray(route)) return false;
  const routeKeys = Object.keys(route).sort().join(",");
  if (!((route.kind === "row" && routeKeys === "kind") || (route.kind === "outcome" && (routeKeys === "kind" || (routeKeys === "kind,sessionId" && isNonBlankString(route.sessionId)))))) return false;
  if (typeof response.expiresAt !== "string" || !WIRE_RE.test(response.expiresAt)) return false;
  const parsed = Date.parse(response.expiresAt);
  if (!Number.isFinite(parsed) || new Date(parsed).toISOString() !== response.expiresAt) return false;
  return Buffer.byteLength(canonical(response), "utf8") <= RESPONSE_CAP_BYTES;
}

function claimStaleness(intent, task, taskDocumentId, intentId, uid) {
  try { validateWakePointer(task, taskDocumentId, intent, intentId); } catch (error) { return "INTENT_STALE"; }
  // live wake cause: the retained wake_id must still derive from the cause the task carries
  try {
    const liveWakeId = wakeIdFor({ uid, taskDocumentId, taskInstanceId: intent.task_instance_id, interactionEpoch: intent.interaction_epoch, policyFingerprint: intent.policy_fingerprint, cause: validateCause(task.wakeEvidence.cause) });
    if (liveWakeId !== task.wakeEvidence.wake_id) return "INTENT_STALE";
  } catch (error) { return "INTENT_STALE"; }
  // C9.3.2: a terminal task (Completed/Dismissed) no longer carries the live state any route was stored for
  if (task.status === "Completed" || task.status === "Dismissed") return "INTENT_STALE";
  // C9.3.2: the live policy state must be present and match the intent's epoch and fingerprint (an intent exists only for a valid-policy wake)
  const state = task.taskInteractionState;
  if (!state || typeof state !== "object" || Array.isArray(state)) return "INTENT_STALE";
  if (state.interaction_epoch !== intent.interaction_epoch || state.policy_fingerprint !== intent.policy_fingerprint) return "INTENT_STALE";
  if (intent.route.kind === "outcome" && intent.route.session_id !== undefined) {
    const handoff = task.activeHandoff;
    if (!handoff || typeof handoff !== "object" || handoff.state !== "returned" || handoff.session_id !== intent.route.session_id) return "INTENT_STALE";
  }
  // C9.3.12 row 5: an outcome route without a session opens the WAITING transition's outcome surface; any other live state is stale
  if (intent.route.kind === "outcome" && intent.route.session_id === undefined) {
    const contract = task.dispositionContract;
    if (task.status !== "matching_in_progress" || !contract || typeof contract !== "object" || contract.disposition !== "WAITING_ON_EXTERNAL") return "INTENT_STALE";
  }
  return null;
}

/**
 * claimTaskIntent: reads only users/{auth.uid}/notificationIntents/{intentId}; an absent document is
 * permission-denied/AUTH_FORBIDDEN with zero writes; the same claim operation replays its stored response;
 * every stale case normalizes to INTENT_STALE; the intent moves pending → consumed atomically with the record.
 */
async function executeClaimTaskIntent(db, uid, request, now) {
  const intentRef = intentRefFor(db, uid, request.intentId);
  const opRef = db.doc(`users/${uid}/taskPlanOperations/${request.claimOperationId}`);
  const nowMillis = now instanceof Date ? now.getTime() : now.toMillis();
  return db.runTransaction(async (transaction) => {
    const opSnapshot = await transaction.get(opRef);
    if (opSnapshot.exists) {
      const record = validateClaimRecord(opSnapshot.data(), uid, request);
      return { ...record.response, replayed: true };
    }
    const intentSnapshot = await transaction.get(intentRef);
    if (!intentSnapshot.exists) throw new HttpsError("permission-denied", "AUTH_FORBIDDEN", { schemaVersion: 1, reason: "AUTH_FORBIDDEN" });
    let intent;
    try {
      intent = validateIntent(intentSnapshot.data());
      validateIntentIdentity(uid, request.intentId, intent);
    } catch (error) {
      throw failedPrecondition("INTENT_INVALID");
    }
    if (intent.state === "consumed") throw failedPrecondition("INTENT_ALREADY_CLAIMED");
    if (intent.state === "cancelled") throw failedPrecondition("INTENT_CANCELLED");
    if (intent.expires_at.toMillis() <= nowMillis) throw failedPrecondition("INTENT_EXPIRED");
    const taskRef = db.doc(`users/${uid}/tasks/${intent.task_document_id}`);
    const taskSnapshot = await transaction.get(taskRef);
    if (!taskSnapshot.exists) throw failedPrecondition("INTENT_STALE");
    const task = taskSnapshot.data();
    const stale = claimStaleness(intent, task, intent.task_document_id, request.intentId, uid);
    if (stale) throw failedPrecondition(stale);
    await fence.assertDeletionAbsent(transaction, db, [uid]); // C6.1 root fence (committing branch)
    let expiresAt;
    try { expiresAt = timestampWire(intent.expires_at); } catch (error) { throw failedPrecondition("INTENT_INVALID"); }
    const route = intent.route.kind === "row" ? { kind: "row" } : { kind: "outcome", ...(intent.route.session_id !== undefined ? { sessionId: intent.route.session_id } : {}) };
    const response = {
      schemaVersion: 1, kind: "task_route", claimOperationId: request.claimOperationId, replayed: false,
      accountUid: uid, intentId: request.intentId, taskDocumentId: intent.task_document_id, taskInstanceId: intent.task_instance_id,
      taskGenerationEpoch: task.task_generation_epoch ?? null, interactionEpoch: intent.interaction_epoch, policyFingerprint: intent.policy_fingerprint,
      route, expiresAt
    };
    const responseBytes = canonical(response);
    if (Buffer.byteLength(responseBytes, "utf8") > RESPONSE_CAP_BYTES) throw failedPrecondition("INTENT_INVALID");
    const sha = requestSha256(request);
    const record = {
      schema_version: 1, kind: "INTENT_CLAIM", state: "COMMITTED",
      account_uid: uid, operation_id: request.claimOperationId, action: "claimTaskIntent",
      request_fingerprint: `op1_${sha}`, request_sha256: sha,
      task_identities: [], prior_snapshots: [],
      response, response_sha256: fence.sha256Hex(responseBytes),
      created_at: FieldValue.serverTimestamp(), committed_at: FieldValue.serverTimestamp()
    };
    if (Buffer.byteLength(canonical({ ...record, created_at: Timestamp.fromMillis(nowMillis), committed_at: Timestamp.fromMillis(nowMillis) }), "utf8") > RECORD_CAP_BYTES) throw failedPrecondition("INTENT_INVALID");
    transaction.create(opRef, record);
    transaction.update(intentRef, { state: "consumed", consumed_at: FieldValue.serverTimestamp(), claim_operation_id: request.claimOperationId });
    return response;
  });
}

module.exports = {
  INTENT_TTL_MS, RESPONSE_CAP_BYTES, RECORD_CAP_BYTES, INTENT_ID_RE, WAKE_ID_RE,
  wakeIdFor, intentIdFor, intentRefFor, validateRoute, validateCause, validateIntent, validateIntentIdentity, validateWakePointer,
  produceWake, upgradeWakeUrgency, cancelPendingIntent,
  timestampWire, validateClaimRequest, requestSha256, validateClaimRecord, executeClaimTaskIntent
};
