"use strict";

const admin = require("firebase-admin");
const { createHash, randomUUID } = require("node:crypto");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const {
  buildUpcomingContract,
  dateFromValue,
  validateDispositionContract
} = require("./dispositionContract");

const LEASE_PATH = "phase1System/dispositionTriggerLease";
const STATE_PATH = "phase1System/dispositionTriggerState";
const LEASE_MS = 10 * 60 * 1000;
const WORK_LIMIT = 10;
const DATE_PAGE_SIZE = 200;
const EVENT_PAGE_SIZE = 100;

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

function validateEventEnvelope(data, documentId) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("Event envelope must be a map");
  }
  const eventId = trimmed(data.event_id);
  const eventName = trimmed(data.event_name);
  const canonicalKey = trimmed(data.canonical_key);
  const evidenceId = trimmed(data.source_evidence_id);
  if (!eventId || eventId !== documentId) throw new Error("event_id must equal the document ID");
  if (!eventName || !canonicalKey) throw new Error("Event name and canonical key are required");
  if (!Number.isSafeInteger(data.source_version) || data.source_version < 0) {
    throw new Error("source_version must be a nonnegative safe integer");
  }
  const observedAt = strictDate(data.observed_at);
  if (!observedAt) throw new Error("observed_at is required");
  if (!evidenceId) throw new Error("source_evidence_id is required");
  if (data.effect !== "fire" && data.effect !== "retract") {
    throw new Error("effect must be fire or retract");
  }
  const payload = data.payload === undefined ? {} : data.payload;
  if (!isSafeEnvelopeValue(payload)) throw new Error("payload must be Firestore-safe");
  if (data.processingState !== "pending" || data.processed !== false) {
    throw new Error("Event must be pending and unprocessed");
  }

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

function shouldWakeDateTask(data, now) {
  const trigger = data?.dispositionContract?.next_trigger;
  const at = dateFromValue(trigger?.at);
  return data?.status === "Snoozed" &&
    trigger?.kind === "date" &&
    trigger?.fired !== true &&
    at !== null && at.getTime() <= now.getTime();
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

async function acquireEvaluationLeaseInTransaction(db, runId, now) {
  const leaseRef = db.doc(LEASE_PATH);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(leaseRef);
    const lease = snapshot.exists ? snapshot.data() : null;
    if (leaseIsLive(lease, now) && lease.runId !== runId) return false;
    transaction.set(leaseRef, {
      runId,
      acquiredAt: now,
      expiresAt: new Date(now.getTime() + LEASE_MS)
    });
    return true;
  });
}

async function releaseEvaluationLeaseInTransaction(db, runId) {
  const leaseRef = db.doc(LEASE_PATH);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(leaseRef);
    if (!snapshot.exists || snapshot.data()?.runId !== runId) return false;
    transaction.delete(leaseRef);
    return true;
  });
}

async function updateCursorInTransaction(db, runId, now, update) {
  const leaseRef = db.doc(LEASE_PATH);
  const stateRef = db.doc(STATE_PATH);
  return db.runTransaction(async (transaction) => {
    const leaseSnapshot = await transaction.get(leaseRef);
    const stateSnapshot = await transaction.get(stateRef);
    const lease = leaseSnapshot.exists ? leaseSnapshot.data() : null;
    if (!leaseIsLive(lease, now) || lease.runId !== runId) {
      throw new Error("Disposition trigger lease is no longer owned");
    }
    const current = stateSnapshot.exists ? stateSnapshot.data() : {};
    transaction.set(stateRef, update(current), { merge: true });
    return true;
  });
}

function deleteField() {
  return admin.firestore.FieldValue.delete();
}

async function wakeDateTaskInTransaction(db, ref, now) {
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists || !shouldWakeDateTask(snapshot.data(), now)) return false;
    const data = snapshot.data();
    const contract = buildUpcomingContract(data.dispositionContract, "Ready to continue");
    validateDispositionContract("Upcoming", contract, now);
    transaction.update(ref, {
      status: "Upcoming",
      dispositionContract: contract,
      snoozedUntil: deleteField()
    });
    return true;
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

async function consumeEventEnvelopeInTransaction(db, eventRef, now) {
  return db.runTransaction(async (transaction) => {
    const eventSnapshot = await transaction.get(eventRef);
    if (!eventSnapshot.exists || eventSnapshot.data()?.processingState !== "pending") return "noop";

    let envelope;
    try {
      envelope = validateEventEnvelope(eventSnapshot.data(), eventRef.id);
    } catch (error) {
      transaction.update(eventRef, {
        processingState: "terminal",
        processed: true,
        processedAt: now,
        outcome: "quarantined",
        processingError: String(error?.message || error).slice(0, 1000)
      });
      return "quarantined";
    }

    const userId = eventUserId(eventRef);
    const stateId = canonicalEventStateId(envelope.event_name, envelope.canonical_key);
    const stateRef = db.doc(`users/${userId}/eventState/${stateId}`);
    const stateSnapshot = await transaction.get(stateRef);
    const highWater = stateSnapshot.exists ? stateSnapshot.data() : null;
    const outcome = classifyEnvelope(envelope, highWater);
    const fingerprint = fingerprintCanonicalEnvelope(envelope);

    if (outcome === "advance") {
      transaction.set(stateRef, {
        event_name: envelope.event_name,
        canonical_key: envelope.canonical_key,
        source_version: envelope.source_version,
        effect: envelope.effect,
        event_id: envelope.event_id,
        observed_at: new Date(envelope.observed_at),
        source_evidence_id: envelope.source_evidence_id,
        payload: envelope.payload,
        fingerprint,
        advancedAt: now
      });
    }
    transaction.update(eventRef, {
      processingState: "terminal",
      processed: true,
      processedAt: now,
      outcome
    });
    return outcome;
  });
}

async function reconcileEventTaskInTransaction(db, taskRef, now) {
  return db.runTransaction(async (transaction) => {
    const taskSnapshot = await transaction.get(taskRef);
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
    transaction.update(taskRef, {
      status: "Upcoming",
      dispositionContract: contract,
      snoozedUntil: deleteField()
    });
    return true;
  });
}

function documentIdField() {
  return admin.firestore.FieldPath.documentId();
}

async function readState(db) {
  const snapshot = await db.doc(STATE_PATH).get();
  return snapshot.exists ? snapshot.data() : {};
}

function logCandidateError(kind, ref, error) {
  console.error(`Disposition trigger ${kind} candidate failed`, {
    path: ref.path,
    error: String(error?.message || error)
  });
}

async function processDateTasks(db, now, runId) {
  const state = await readState(db);
  let query = db.collectionGroup("tasks")
    .where("status", "==", "Snoozed")
    .where("dispositionContract.next_trigger.kind", "==", "date")
    .where("dispositionContract.next_trigger.at", "<=", now)
    .orderBy("dispositionContract.next_trigger.at", "asc")
    .orderBy(documentIdField(), "asc")
    .limit(DATE_PAGE_SIZE + 1);
  if (state.dateAfterAt && trimmed(state.dateAfterPath)) {
    query = query.startAfter(state.dateAfterAt, db.doc(state.dateAfterPath));
  }
  const snapshot = await query.get();
  const candidates = snapshot.docs.slice(0, DATE_PAGE_SIZE);
  const results = await mapWithConcurrency(candidates, WORK_LIMIT, async (candidate) => {
    try {
      return await wakeDateTaskInTransaction(db, candidate.ref, now);
    } catch (error) {
      logCandidateError("date", candidate.ref, error);
      return false;
    }
  });
  const overflow = snapshot.docs.length > DATE_PAGE_SIZE;
  const last = candidates.at(-1);
  await updateCursorInTransaction(db, runId, now, () => overflow && last ? {
    dateAfterAt: last.get("dispositionContract.next_trigger.at"),
    dateAfterPath: last.ref.path
  } : {
    dateAfterAt: deleteField(),
    dateAfterPath: deleteField()
  });
  return { scanned: candidates.length, woke: results.filter(Boolean).length };
}

async function processEvents(db, now, runId) {
  const query = db.collectionGroup("events")
    .where("processingState", "==", "pending")
    .orderBy(documentIdField(), "asc")
    .limit(EVENT_PAGE_SIZE + 1);
  const snapshot = await query.get();
  const candidates = snapshot.docs.slice(0, EVENT_PAGE_SIZE);
  const outcomes = await mapWithConcurrency(candidates, WORK_LIMIT, async (candidate) => {
    try {
      return await consumeEventEnvelopeInTransaction(db, candidate.ref, now);
    } catch (error) {
      logCandidateError("event", candidate.ref, error);
      return "failed";
    }
  });
  return { scanned: candidates.length, outcomes };
}

async function processEventTasks(db, now, runId) {
  const state = await readState(db);
  let query = db.collectionGroup("tasks")
    .where("status", "==", "Snoozed")
    .where("dispositionContract.next_trigger.kind", "==", "event")
    .orderBy(documentIdField(), "asc")
    .limit(DATE_PAGE_SIZE + 1);
  if (trimmed(state.eventTaskAfterPath)) {
    query = query.startAfter(db.doc(state.eventTaskAfterPath));
  }
  const snapshot = await query.get();
  const candidates = snapshot.docs.slice(0, DATE_PAGE_SIZE);
  const results = await mapWithConcurrency(candidates, WORK_LIMIT, async (candidate) => {
    try {
      return await reconcileEventTaskInTransaction(db, candidate.ref, now);
    } catch (error) {
      logCandidateError("event-task", candidate.ref, error);
      return false;
    }
  });
  const overflow = snapshot.docs.length > DATE_PAGE_SIZE;
  const last = candidates.at(-1);
  await updateCursorInTransaction(db, runId, now, () => overflow && last ? {
    eventTaskAfterPath: last.ref.path
  } : {
    eventTaskAfterPath: deleteField()
  });
  return { scanned: candidates.length, woke: results.filter(Boolean).length };
}

async function runDispositionTriggerEvaluation(db, now = new Date()) {
  const runId = randomUUID();
  const acquired = await acquireEvaluationLeaseInTransaction(db, runId, now);
  if (!acquired) return { skipped: "lease-held" };
  try {
    const dates = await processDateTasks(db, now, runId);
    const events = await processEvents(db, now, runId);
    const eventTasks = await processEventTasks(db, now, runId);
    return { dates, events, eventTasks };
  } finally {
    await releaseEvaluationLeaseInTransaction(db, runId);
  }
}

function makeDispositionTriggerHandler({ dbFactory, nowFactory, evaluator }) {
  if (typeof dbFactory !== "function" || typeof nowFactory !== "function" || typeof evaluator !== "function") {
    throw new TypeError("Disposition trigger handler dependencies must be functions");
  }
  return async function dispositionTriggerHandler() {
    return evaluator(dbFactory(), nowFactory());
  };
}

const productionHandler = makeDispositionTriggerHandler({
  dbFactory: () => admin.firestore(),
  nowFactory: () => new Date(),
  evaluator: runDispositionTriggerEvaluation
});

const evaluateDispositionTriggers = onSchedule({
  region: "us-central1",
  schedule: "every 15 minutes",
  timeoutSeconds: 540,
  memory: "512MiB",
  maxInstances: 1,
  concurrency: 1,
  retryCount: 0
}, productionHandler);

module.exports = {
  acquireEvaluationLeaseInTransaction,
  canonicalEventEnvelope,
  canonicalEventStateId,
  consumeEventEnvelopeInTransaction,
  evaluateDispositionTriggers,
  makeDispositionTriggerHandler,
  mapWithConcurrency,
  reconcileEventTaskInTransaction,
  runDispositionTriggerEvaluation,
  validateEventEnvelope,
  wakeDateTaskInTransaction,
  __private: {
    classifyEnvelope,
    fingerprintCanonicalEnvelope,
    processDateTasks,
    processEvents,
    processEventTasks,
    releaseEvaluationLeaseInTransaction,
    shouldWakeDateTask,
    shouldWakeEventTask,
    updateCursorInTransaction
  }
};
