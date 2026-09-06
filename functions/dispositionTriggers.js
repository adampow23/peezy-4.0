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
const STATE_KEYS = Object.freeze(["schedulerHealth", "dueObservation", ...CURSOR_KEYS]);
const PHASE0_DEADLINE = 40;
const PHASE0_SELECT = 100;
const ORDINARY_SELECT = 50;
const ALERT_SLOT_BOUND = 11;

class SchedulerInvariant extends Error {
  constructor(code, detail) { super(detail ? `${code}: ${detail}` : code); this.code = code; }
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

async function wakeDateTaskInTransaction(db, ref, rawNow, run = null) {
  const now = toDate(rawNow);
  return db.runTransaction(async (transaction) => {
    if (run) await requireSchedulerFence(transaction, db, run);
    const snapshot = await transaction.get(ref);
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

async function consumeEventEnvelopeInTransaction(db, eventRef, rawNow, run = null) {
  const now = toDate(rawNow);
  return db.runTransaction(async (transaction) => {
    if (run) await requireSchedulerFence(transaction, db, run);
    const eventSnapshot = await transaction.get(eventRef);
    if (!eventSnapshot.exists || eventSnapshot.data()?.processingState !== "pending") return "noop";
    await assertDeletionAbsent(transaction, db, [eventUserId(eventRef)]); // C6.1 root fence (every committing branch)

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

async function reconcileEventTaskInTransaction(db, taskRef, rawNow, run = null) {
  const now = toDate(rawNow);
  return db.runTransaction(async (transaction) => {
    if (run) await requireSchedulerFence(transaction, db, run);
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
    await assertDeletionAbsent(transaction, db, [userId]); // C6.1 root fence
    transaction.update(taskRef, {
      status: "Upcoming",
      dispositionContract: contract,
      snoozedUntil: deleteField()
    });
    return true;
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

/** C9.1.8 — exact schedulerHealth grammar. */
function validateHealth(health) {
  const invariant = (detail) => new SchedulerInvariant("SCHEDULER_HEALTH_INVARIANT", detail);
  if (health === null || typeof health !== "object" || Array.isArray(health)) throw invariant("map");
  const keys = Object.keys(health).sort();
  const allowed = ["activatedOrdinal", "lastCompletedOrdinal", "lastStartedOrdinal", "recentRuns", "schemaVersion"];
  if (!keys.every((k) => allowed.includes(k)) || !["activatedOrdinal", "lastStartedOrdinal", "recentRuns", "schemaVersion"].every((k) => keys.includes(k))) throw invariant("members");
  if (health.schemaVersion !== 1) throw invariant("schemaVersion");
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
      catchUp: health.lastCompletedOrdinal === undefined || missingBeforeThisRun >= 1
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
      catch (error) { return { ok: false, code: error && error.code }; }
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
  const settled = outcomes.every((o) => o !== undefined && o.ok);
  if (!settled) return { lane: PHASE0_CURSOR_KEY, examined: selected.length, settled: false };
  if (snapshot.docs.length > PHASE0_SELECT) await writeCursor(deps, run, PHASE0_CURSOR_KEY, { path: selected.at(-1).ref.path });
  else if (cursor) await writeCursor(deps, run, PHASE0_CURSOR_KEY, null);
  return { lane: PHASE0_CURSOR_KEY, examined: selected.length, settled: true, outcomes: outcomes.map((o) => o.value) };
}

/** Ordinary lanes: exact 50/51 pages over (status, kind, fired) with the date lanes bounded by runNow. */
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
  return query.limit(ORDINARY_SELECT + 1);
}

/** H55 branch (C9.3.11 policy-absent rows): Snoozed lanes wake through the Phase 1 reducers; other policy-absent rows are definitive no-ops. */
function ordinaryReducer(db, lane, candidate, run) {
  if (lane.status !== "Snoozed") return Promise.resolve(false);
  return lane.kind === "date"
    ? wakeDateTaskInTransaction(db, candidate.ref, run.runNow, run)
    : reconcileEventTaskInTransaction(db, candidate.ref, run.runNow, run);
}

async function runOrdinaryLane(deps, run, lane) {
  const { db } = deps;
  const snapshot = await ordinaryQuery(db, lane, run).get();
  const selected = snapshot.docs.slice(0, ORDINARY_SELECT);
  const outcomes = await runWaves(run, selected, lane.deadline, (candidate) => ordinaryReducer(db, lane, candidate, run));
  if (outcomes.some((o) => o !== undefined && !o.ok && o.code === "SCHEDULER_FENCE_LOST")) throw new SchedulerInvariant("SCHEDULER_FENCE_LOST");
  const settled = outcomes.every((o) => o !== undefined && o.ok);
  if (!settled) return { lane: lane.lane, examined: selected.length, settled: false, woke: outcomes.filter((o) => o && o.ok && o.value === true).length };
  const last = selected.at(-1);
  if (snapshot.docs.length > ORDINARY_SELECT && last) {
    const cursor = { path: last.ref.path };
    if (lane.kind === "date") cursor.at = last.get("dispositionContract.next_trigger.at");
    await writeCursor(deps, run, lane.lane, cursor);
  } else if (run.cursors[lane.lane]) {
    await writeCursor(deps, run, lane.lane, null);
  }
  return { lane: lane.lane, examined: selected.length, settled: true, woke: outcomes.filter((o) => o.value === true).length };
}

// ---------------------------------------------------------------------------
// C9.1.6 / C9.1.8 / C9.1.9 — completion
// ---------------------------------------------------------------------------

function nearestRank(samples, fraction) {
  const sorted = [...samples].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil(fraction * sorted.length) - 1)];
}

async function completeScheduler(deps, run, thresholdSamples) {
  return fenced(deps, run, async (transaction) => {
    const snapshot = await transaction.get(stateRef(deps.db));
    const health = validateHealth(snapshot.data().schedulerHealth);
    const completedAt = readTimeOf(snapshot, deps);
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
      await observeCondition(deps, run, "p2b1_two_missed_completions", "TWO_MISSED_COMPLETIONS", { effectiveLastCompletedOrdinal: run.effectiveLast, requiredCompletedOrdinal: run.runOrdinal - 2 });
    } else {
      await clearCondition(deps, run, "p2b1_two_missed_completions");
    }
    const phase0 = await runPhase0(deps, run);
    report.lanes = [...report.lanes, phase0];
    let allSettled = phase0.settled;
    for (const lane of ORDINARY_LANES) {
      const result = await runOrdinaryLane(deps, run, lane);
      report.lanes = [...report.lanes, result];
      if (!result.settled) allSettled = false;
    }
    if (!allSettled) return report;
    await completeScheduler(deps, run, []);
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

function productionDependencies() {
  return {
    db: admin.firestore(),
    log: (code, counts) => logger.info(code, counts || {}),
    metric: (metricName, value) => logger.info("phase2_metric", { metric: metricName, value })
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
