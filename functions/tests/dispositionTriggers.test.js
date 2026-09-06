"use strict";

const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const {
  canonicalEventEnvelope,
  canonicalEventStateId,
  acquireEvaluationLeaseInTransaction,
  consumeEventEnvelopeInTransaction,
  validateEventEnvelope,
  mapWithConcurrency,
  makeDispositionTriggerHandler,
  reconcileEventTaskInTransaction,
  runDispositionTriggerEvaluation,
  wakeDateTaskInTransaction,
  evaluateDispositionTriggers,
  __private
} = require("../dispositionTriggers");
const scheduler = require("../dispositionTriggers");
const { fakeFirestore, FakeClock } = require("./support/fakeFirestore");
const { Timestamp } = require("firebase-admin/firestore");

const NOW = new Date("2026-08-27T17:00:00.000Z");

function fakeTransactionDb(initial = {}) {
  const documents = new Map(Object.entries(initial));
  function ref(documentPath) {
    return {
      path: documentPath,
      id: documentPath.split("/").at(-1),
      async get() {
        return snapshot(documents.get(documentPath));
      }
    };
  }
  function snapshot(data) {
    return {
      exists: data !== undefined,
      data: () => data,
      get(fieldPath) {
        return fieldPath.split(".").reduce((value, key) => value?.[key], data);
      }
    };
  }
  function cleanedUpdate(current, update) {
    const next = { ...(current || {}) };
    for (const [key, value] of Object.entries(update)) {
      if (value?.constructor?.name === "DeleteTransform") delete next[key];
      else next[key] = value;
    }
    return next;
  }
  return {
    documents,
    doc: ref,
    async runTransaction(operation) {
      const writes = [];
      const transaction = {
        async get(reference) {
          return snapshot(documents.get(reference.path));
        },
        set(reference, data, options) {
          writes.push({ kind: "set", reference, data, options });
        },
        update(reference, data) {
          writes.push({ kind: "update", reference, data });
        },
        delete(reference) {
          writes.push({ kind: "delete", reference });
        }
      };
      const result = await operation(transaction);
      for (const write of writes) {
        if (write.kind === "delete") documents.delete(write.reference.path);
        else if (write.kind === "update" || write.options?.merge) {
          documents.set(write.reference.path, cleanedUpdate(documents.get(write.reference.path), write.data));
        } else {
          documents.set(write.reference.path, write.data);
        }
      }
      return result;
    }
  };
}

function queryAwareDb(initial = {}) {
  const db = fakeTransactionDb(initial);
  db.queryLog = [];

  function nestedValue(data, fieldPath) {
    return fieldPath.split(".").reduce((value, key) => value?.[key], data);
  }

  function comparable(value) {
    if (value instanceof Date) return value.getTime();
    if (value && typeof value.toDate === "function") return value.toDate().getTime();
    return value;
  }

  function compare(left, right) {
    const a = comparable(left);
    const b = comparable(right);
    if (a === b) return 0;
    return a < b ? -1 : 1;
  }

  function querySnapshot(documentPath, data) {
    const reference = db.doc(documentPath);
    return {
      ref: reference,
      id: reference.id,
      data: () => data,
      get(fieldPath) {
        return nestedValue(data, fieldPath);
      }
    };
  }

  db.collectionGroup = (group) => {
    const clauses = { group, wheres: [], orders: [], limit: null, startAfter: [] };
    const query = {
      where(field, operator, value) {
        clauses.wheres.push([field, operator, value]);
        return query;
      },
      orderBy(field, direction) {
        clauses.orders.push([typeof field === "string" ? field : "__name__", direction]);
        return query;
      },
      limit(value) {
        clauses.limit = value;
        return query;
      },
      startAfter(...values) {
        clauses.startAfter = values;
        return query;
      },
      async get() {
        const trace = {
          group,
          wheres: clauses.wheres.map(([field, operator, value]) => [field, operator, value]),
          orders: clauses.orders.map((row) => [...row]),
          limit: clauses.limit,
          startAfter: clauses.startAfter.map((value) => value?.path || value)
        };
        db.queryLog.push(trace);
        let rows = [...db.documents.entries()]
          .filter(([documentPath]) => {
            const parts = documentPath.split("/");
            return parts.length === 4 && parts[2] === group;
          })
          .map(([documentPath, data]) => querySnapshot(documentPath, data));
        for (const [field, operator, expected] of clauses.wheres) {
          rows = rows.filter((row) => {
            const actual = nestedValue(row.data(), field);
            if (operator === "==") return compare(actual, expected) === 0;
            if (operator === "<=") return compare(actual, expected) <= 0;
            throw new Error(`Unsupported fake query operator ${operator}`);
          });
        }
        rows.sort((left, right) => {
          for (const [field, direction] of clauses.orders) {
            const comparison = field === "__name__"
              ? compare(left.ref.path, right.ref.path)
              : compare(nestedValue(left.data(), field), nestedValue(right.data(), field));
            if (comparison !== 0) return direction === "desc" ? -comparison : comparison;
          }
          return 0;
        });
        if (clauses.startAfter.length > 0) {
          rows = rows.filter((row) => {
            const rowTuple = clauses.orders.map(([field]) => field === "__name__"
              ? row.ref.path
              : nestedValue(row.data(), field));
            const cursorTuple = clauses.startAfter.map((value) => value?.path || value);
            for (let index = 0; index < cursorTuple.length; index += 1) {
              const result = compare(rowTuple[index], cursorTuple[index]);
              if (result !== 0) return result > 0;
            }
            return false;
          });
        }
        if (clauses.limit !== null) rows = rows.slice(0, clauses.limit);
        return { docs: rows };
      }
    };
    return query;
  };
  return db;
}

function deferredDate(at, fired = false) {
  return {
    status: "Snoozed",
    snoozedUntil: at,
    dispositionContract: {
      disposition: "DEFERRED",
      owner: "user:test",
      next_action: "Wait",
      next_trigger: {
        kind: "date",
        at,
        fired,
        payload: { basis: "institution_promised_date", source_evidence_id: "evidence-date" }
      },
      resume_destination: "flow:date",
      visible_status_copy: "Waiting"
    }
  };
}

function deferredEvent(canonicalKey = "service/provider-1") {
  return {
    status: "Snoozed",
    snoozedUntil: new Date("2026-09-01T00:00:00.000Z"),
    dispositionContract: {
      disposition: "DEFERRED",
      owner: "user:test",
      next_action: "Wait",
      next_trigger: {
        kind: "event",
        event_name: "institution.updated",
        canonical_key: canonicalKey,
        after_source_version: 1,
        fired: false,
        payload: { source_evidence_id: "evidence-event" }
      },
      resume_destination: "flow:event",
      visible_status_copy: "Waiting"
    }
  };
}

function event(overrides = {}) {
  return {
    event_id: "event-2",
    event_name: "institution.updated",
    canonical_key: "service/provider-1",
    source_version: 2,
    observed_at: new Date("2026-08-27T16:59:00.000Z"),
    source_evidence_id: "evidence-2",
    effect: "fire",
    payload: { nested: [true, 2, { note: "ready" }] },
    processingState: "pending",
    processed: false,
    ...overrides
  };
}

test("canonical event state IDs are delimiter-safe and deterministic", () => {
  const left = canonicalEventStateId("a|b", "c");
  const right = canonicalEventStateId("a", "b|c");
  assert.notEqual(left, right);
  assert.match(left, /^[a-f0-9]{64}$/);
  assert.equal(left, createHash("sha256").update('["a|b","c"]').digest("hex"));
});

test("event envelopes normalize time and include every semantic field", () => {
  const canonical = canonicalEventEnvelope(event(), "event-2");
  assert.deepEqual(canonical, {
    event_id: "event-2",
    event_name: "institution.updated",
    canonical_key: "service/provider-1",
    source_version: 2,
    observed_at: "2026-08-27T16:59:00.000Z",
    source_evidence_id: "evidence-2",
    effect: "fire",
    payload: { nested: [true, 2, { note: "ready" }] }
  });
  assert.deepEqual(validateEventEnvelope(event(), "event-2"), canonical);
});

test("invalid or incomplete event envelopes fail closed", () => {
  const invalid = [
    [event({ event_name: "" }), "event-2"],
    [event({ canonical_key: "" }), "event-2"],
    [event({ source_version: -1 }), "event-2"],
    [event({ source_version: 1.5 }), "event-2"],
    [event({ observed_at: undefined }), "event-2"],
    [event({ observed_at: "2026-08-27T16:59:00.000Z" }), "event-2"],
    [event({ source_evidence_id: "" }), "event-2"],
    [event({ effect: "ignore" }), "event-2"],
    [event({ payload: { bad: undefined } }), "event-2"],
    [event({ processed: true }), "event-2"],
    [event({ event_id: "different" }), "event-2"]
  ];
  for (const [value, id] of invalid) {
    assert.throws(() => validateEventEnvelope(value, id));
  }
});

test("same-version arbitration distinguishes exact replay from every drift", () => {
  const base = canonicalEventEnvelope(event(), "event-2");
  const fingerprint = __private.fingerprintCanonicalEnvelope(base);
  const highWater = { source_version: 2, fingerprint };

  assert.equal(__private.classifyEnvelope(base, highWater), "duplicate");
  assert.equal(
    __private.classifyEnvelope(canonicalEventEnvelope(event({ effect: "retract" }), "event-2"), highWater),
    "version_conflict"
  );
  assert.equal(
    __private.classifyEnvelope(canonicalEventEnvelope(event({ payload: { changed: true } }), "event-2"), highWater),
    "version_conflict"
  );
  assert.equal(
    __private.classifyEnvelope(canonicalEventEnvelope(event({ source_evidence_id: "other" }), "event-2"), highWater),
    "version_conflict"
  );
  assert.equal(
    __private.classifyEnvelope(canonicalEventEnvelope(event({ event_id: "event-other" }), "event-other"), highWater),
    "version_conflict"
  );
  assert.equal(
    __private.classifyEnvelope(canonicalEventEnvelope(event({ event_id: "event-1", source_version: 1 }), "event-1"), highWater),
    "stale"
  );
  assert.equal(
    __private.classifyEnvelope(canonicalEventEnvelope(event({ event_id: "event-3", source_version: 3 }), "event-3"), highWater),
    "advance"
  );
});

test("event reconciliation requires a newer fire for the exact trigger key", () => {
  const task = {
    status: "Snoozed",
    dispositionContract: {
      disposition: "DEFERRED",
      next_trigger: {
        kind: "event",
        event_name: "institution.updated",
        canonical_key: "service/provider-1",
        after_source_version: 2,
        fired: false
      }
    }
  };
  assert.equal(__private.shouldWakeEventTask(task, {
    event_name: "institution.updated",
    canonical_key: "service/provider-1",
    source_version: 3,
    effect: "fire"
  }), true);
  assert.equal(__private.shouldWakeEventTask(task, {
    event_name: "institution.updated",
    canonical_key: "service/provider-1",
    source_version: 3,
    effect: "retract"
  }), false);
  assert.equal(__private.shouldWakeEventTask(task, {
    event_name: "institution.updated",
    canonical_key: "other",
    source_version: 3,
    effect: "fire"
  }), false);
  assert.equal(__private.shouldWakeEventTask(task, {
    event_name: "institution.updated",
    canonical_key: "service/provider-1",
    source_version: 2,
    effect: "fire"
  }), false);
});

test("date eligibility includes missing fired and rejects future or consumed rows", () => {
  const due = {
    status: "Snoozed",
    dispositionContract: {
      disposition: "DEFERRED",
      next_trigger: { kind: "date", at: new Date("2026-08-27T16:00:00.000Z") }
    }
  };
  assert.equal(__private.shouldWakeDateTask(due, NOW), true);
  assert.equal(__private.shouldWakeDateTask({
    ...due,
    dispositionContract: {
      ...due.dispositionContract,
      next_trigger: { ...due.dispositionContract.next_trigger, fired: true }
    }
  }, NOW), false);
  assert.equal(__private.shouldWakeDateTask({
    ...due,
    dispositionContract: {
      ...due.dispositionContract,
      next_trigger: { ...due.dispositionContract.next_trigger, at: new Date("2026-08-27T18:00:00.000Z") }
    }
  }, NOW), false);
});

test("due date transaction wakes exactly once and clears deferred state", async () => {
  const taskPath = "users/u1/tasks/due";
  const db = fakeTransactionDb({
    [taskPath]: {
      status: "Snoozed",
      snoozedUntil: new Date("2026-08-27T16:00:00.000Z"),
      dispositionContract: {
        profile_version: 3,
        disposition: "DEFERRED",
        owner: "user:u1",
        next_action: "Wait",
        next_trigger: {
          kind: "date",
          at: new Date("2026-08-27T16:00:00.000Z"),
          payload: { basis: "institution_promised_date", source_evidence_id: "e1" }
        },
        resume_destination: "flow:due",
        visible_status_copy: "Waiting"
      }
    }
  });
  assert.equal(await wakeDateTaskInTransaction(db, db.doc(taskPath), NOW), true);
  assert.deepEqual(db.documents.get(taskPath), {
    status: "Upcoming",
    dispositionContract: {
      profile_version: 3,
      visible_status_copy: "Ready to continue"
    }
  });
  assert.equal(await wakeDateTaskInTransaction(db, db.doc(taskPath), NOW), false);
});

test("event ingestion advances high water, terminalizes drift, and later wakes matching task", async () => {
  const eventPath = "users/u1/events/event-2";
  const taskPath = "users/u1/tasks/event-task";
  const stateId = canonicalEventStateId("institution.updated", "service/provider-1");
  const statePath = `users/u1/eventState/${stateId}`;
  const db = fakeTransactionDb({
    [eventPath]: event(),
    [taskPath]: {
      status: "Snoozed",
      snoozedUntil: new Date("2026-09-01T00:00:00.000Z"),
      dispositionContract: {
        disposition: "DEFERRED",
        owner: "user:u1",
        next_action: "Wait",
        next_trigger: {
          kind: "event",
          event_name: "institution.updated",
          canonical_key: "service/provider-1",
          after_source_version: 1,
          payload: { source_evidence_id: "evidence-1" }
        },
        resume_destination: "flow:event",
        visible_status_copy: "Waiting"
      }
    }
  });
  assert.equal(await consumeEventEnvelopeInTransaction(db, db.doc(eventPath), NOW), "advance");
  assert.equal(db.documents.get(eventPath).outcome, "advance");
  assert.equal(db.documents.get(eventPath).processingState, "terminal");
  assert.equal(db.documents.get(statePath).source_version, 2);
  assert.equal(await reconcileEventTaskInTransaction(db, db.doc(taskPath), NOW), true);
  assert.deepEqual(db.documents.get(taskPath), {
    status: "Upcoming",
    dispositionContract: { visible_status_copy: "Ready to continue" }
  });
  assert.equal(await reconcileEventTaskInTransaction(db, db.doc(taskPath), NOW), false);

  const conflictPath = "users/u1/events/event-conflict";
  db.documents.set(conflictPath, event({ event_id: "event-conflict", payload: { changed: true } }));
  assert.equal(await consumeEventEnvelopeInTransaction(db, db.doc(conflictPath), NOW), "version_conflict");
  assert.equal(db.documents.get(conflictPath).processingState, "terminal");
  assert.equal(db.documents.get(statePath).event_id, "event-2");
});

test("retractions advance high water without waking", async () => {
  const eventPath = "users/u1/events/event-3";
  const taskPath = "users/u1/tasks/event-task";
  const db = fakeTransactionDb({
    [eventPath]: event({ event_id: "event-3", source_version: 3, effect: "retract" }),
    [taskPath]: {
      status: "Snoozed",
      dispositionContract: {
        disposition: "DEFERRED",
        owner: "user:u1",
        next_action: "Wait",
        next_trigger: {
          kind: "event", event_name: "institution.updated",
          canonical_key: "service/provider-1", after_source_version: 1,
          payload: { source_evidence_id: "evidence-1" }
        },
        resume_destination: "flow:event",
        visible_status_copy: "Waiting"
      }
    }
  });
  assert.equal(await consumeEventEnvelopeInTransaction(db, db.doc(eventPath), NOW), "advance");
  assert.equal(await reconcileEventTaskInTransaction(db, db.doc(taskPath), NOW), false);
  assert.equal(db.documents.get(taskPath).status, "Snoozed");
});

test("invalid pending event is quarantined and leaves no high-water row", async () => {
  const eventPath = "users/u1/events/bad-event";
  const db = fakeTransactionDb({
    [eventPath]: event({ event_id: "bad-event", observed_at: undefined })
  });
  assert.equal(await consumeEventEnvelopeInTransaction(db, db.doc(eventPath), NOW), "quarantined");
  assert.equal(db.documents.get(eventPath).outcome, "quarantined");
  assert.equal([...db.documents.keys()].filter((key) => key.includes("/eventState/")).length, 0);
});

test("bounded mapper never exceeds the requested work cap", async () => {
  let active = 0;
  let maximum = 0;
  const output = await mapWithConcurrency(Array.from({ length: 31 }, (_, index) => index), 10, async (item) => {
    active += 1;
    maximum = Math.max(maximum, active);
    await new Promise((resolve) => setImmediate(resolve));
    active -= 1;
    return item * 2;
  });
  assert.equal(maximum, 10);
  assert.deepEqual(output, Array.from({ length: 31 }, (_, index) => index * 2));
});

test("module has no notification dependency", () => {
  const source = fs.readFileSync(path.resolve(__dirname, "../dispositionTriggers.js"), "utf8");
  assert.doesNotMatch(source, /notify|messaging|push/i);
});

// ---------------------------------------------------------------------------
// S3 I9a — PHASE2_CONTRACT.md C9.1 scheduler mechanics. The ten Phase-1 cases this section
// replaces (runId lease, 200-row pages, old export options, old index file) are superseded by
// the contract; each property they proved has a C9.1 equivalent below.
// ---------------------------------------------------------------------------

const T0 = "2026-09-06T12:00:00Z"; // an exact 300 s boundary
const ORD0 = Math.floor(Date.parse(T0) / 1000 / 300);
const scheduleAt = (k) => new Date(Date.parse(T0) + k * 300_000).toISOString().replace(".000Z", "Z");
function schedDeps(db, clock, extra = {}) {
  const deps = { db, logs: [], metrics: [], now: () => clock.now(), log: (code, counts) => deps.logs.push([code, counts]), metric: (n, v) => deps.metrics.push([n, v]), elapsedSeconds: () => 0, ...extra };
  return deps;
}
const healthOf = (db) => db.__docs.get(scheduler.STATE_PATH).schedulerHealth;
const dateTask = (at) => ({ status: "Snoozed", snoozedUntil: at, dispositionContract: { profile_version: 3, disposition: "DEFERRED", owner: "user:u1", next_action: "Wait", next_trigger: { kind: "date", fired: false, at, payload: { basis: "institution_promised_date", source_evidence_id: "e1" } }, resume_destination: "flow:due", visible_status_copy: "Waiting" } });
const pendingEvent = (id) => ({ event_id: id, event_name: "institution.updated", canonical_key: "service/provider-1", source_version: 2, observed_at: new Date("2026-08-27T16:59:00.000Z"), source_evidence_id: "evidence-2", effect: "fire", payload: {}, processingState: "pending", processed: false });

async function initialized(docs = {}, clockIso = "2026-09-06T11:57:00.000Z") {
  const clock = new FakeClock(clockIso); // initialization just before the boundary → activatedOrdinal = ORD0
  const db = fakeFirestore({ docs, clock });
  const deps = schedDeps(db, clock);
  await scheduler.initializeScheduler(deps);
  clock.millis = Date.parse(T0) + 1000;
  return { db, clock, deps };
}

test("C9.1.1 scheduler configuration is exact", () => {
  const endpoint = evaluateDispositionTriggers.__endpoint;
  assert.deepEqual(endpoint.region, ["us-central1"]);
  assert.equal(endpoint.scheduleTrigger.schedule, "*/5 * * * *");
  assert.equal(endpoint.scheduleTrigger.timeZone, "Etc/UTC");
  assert.equal(endpoint.timeoutSeconds, 270);
  assert.equal(endpoint.availableMemoryMb, 512);
  assert.equal(endpoint.maxInstances, 1);
  assert.equal(endpoint.concurrency, 1);
  assert.equal(endpoint.scheduleTrigger.retryConfig.retryCount, 0);
});

test("C9.1.3 scheduleTime alone selects the ordinal; a missing or malformed scheduleTime stops before any write", async () => {
  assert.equal(scheduler.parseScheduleEvent({ scheduleTime: scheduleAt(0) }).runOrdinal, ORD0);
  assert.equal(scheduler.parseScheduleEvent({ scheduleTime: "2026-09-06T12:00:00.123456789Z" }).runOrdinal, ORD0);
  for (const bad of [undefined, {}, { scheduleTime: "" }, { scheduleTime: "2026-09-06 12:00:00" }, { scheduleTime: "2026-09-06T12:00:00+00:00" }, { scheduleTime: 1 }]) {
    assert.equal(scheduler.parseScheduleEvent(bad), null, JSON.stringify(bad));
  }
  const { db, deps } = await initialized();
  const before = db.__writes.length;
  assert.deepEqual(await scheduler.runDispositionScheduler({ scheduleTime: "nope" }, deps), { outcome: "invalid_event" });
  assert.equal(db.__writes.length, before);
  assert.ok(deps.logs.some(([c]) => c === "SCHEDULER_EVENT_INVALID"));
});

test("C9.1.5 initialization writes the exact health map, migrates an exact legacy lease in the same transaction, and blocks on any other lease shape or a present health map", async () => {
  const clock = new FakeClock("2026-09-06T11:57:00.000Z");
  const db = fakeFirestore({ docs: { [scheduler.LEASE_PATH]: { runId: "old", acquiredAt: new Date(), expiresAt: new Date() } }, clock });
  const result = await scheduler.initializeScheduler(schedDeps(db, clock));
  assert.equal(result.activatedOrdinal, ORD0);
  assert.deepEqual(healthOf(db), { schemaVersion: 1, activatedOrdinal: ORD0, lastStartedOrdinal: ORD0 - 1, recentRuns: [] });
  assert.equal(db.__docs.has(scheduler.LEASE_PATH), false, "legacy lease deleted in the initializing transaction");
  await assert.rejects(scheduler.initializeScheduler(schedDeps(db, clock)), (e) => e.code === "SCHEDULER_ROLLOUT_BLOCKED");
  const foreign = fakeFirestore({ docs: { [scheduler.LEASE_PATH]: { weird: true } }, clock });
  await assert.rejects(scheduler.initializeScheduler(schedDeps(foreign, clock)), (e) => e.code === "SCHEDULER_ROLLOUT_BLOCKED");
  assert.equal(foreign.__writes.length, 0);
});

test("C9.1.6/C9.1.16 acquisition refuses the cross-fence, the ordinal floor, and a held v2 lease with zero writes; replaces an expired lease; migrates the exact legacy lease and residue keys atomically; blocks foreign keys", async () => {
  const { db, deps, clock } = await initialized();
  // cross-fence present → refused, nothing written
  await db.doc(scheduler.CROSS_FENCE_PATH).set({ any: 1 });
  let before = db.__writes.length;
  assert.deepEqual(await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(0) }, deps), { outcome: "refused", reason: "CROSS_FENCE_PRESENT" });
  assert.equal(db.__writes.length, before);
  await db.doc(scheduler.CROSS_FENCE_PATH).delete();
  // ordinal at or below the floor (activatedOrdinal - 1) → refused
  before = db.__writes.length;
  assert.deepEqual(await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(-1) }, deps), { outcome: "refused", reason: "ORDINAL_NOT_ABOVE_FLOOR" });
  assert.equal(db.__writes.length, before);
  // held v2 lease (other owner, unexpired) → refused
  const foreignLease = { schemaVersion: 1, runOrdinal: ORD0, ownerToken: "other", startedAt: clock.now(), expiresAt: Timestamp.fromMillis(clock.millis + 100_000) };
  await db.doc(scheduler.LEASE_PATH).set(foreignLease);
  before = db.__writes.length;
  assert.deepEqual(await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(0) }, deps), { outcome: "refused", reason: "LEASE_HELD" });
  assert.equal(db.__writes.length, before);
  assert.deepEqual(db.__docs.get(scheduler.LEASE_PATH), foreignLease);
  // expired v2 lease → replaced atomically with the running heartbeat
  clock.millis += 200_000;
  const run = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(0) }, deps);
  assert.equal(run.outcome, "completed");
  assert.equal(healthOf(db).lastStartedOrdinal, ORD0);
  assert.equal(healthOf(db).recentRuns.at(-1).state, "completed");
  assert.equal(db.__docs.has(scheduler.LEASE_PATH), false, "owner released its lease");
  // MIG-TRIGGER-V1: legacy lease + residue keys removed in the acquiring transaction
  await db.doc(scheduler.LEASE_PATH).set({ runId: "legacy", acquiredAt: new Date(), expiresAt: new Date() });
  await db.doc(scheduler.STATE_PATH).update({ dateAfterAt: new Date(), dateAfterPath: "users/u1/tasks/x", eventTaskAfterPath: "users/u1/tasks/y" });
  const migratedRun = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(1) }, deps);
  assert.equal(migratedRun.migrated, true);
  const state = db.__docs.get(scheduler.STATE_PATH);
  assert.ok(!("dateAfterAt" in state) && !("dateAfterPath" in state) && !("eventTaskAfterPath" in state));
  // foreign trigger-state key → blocked, zero write
  await db.doc(scheduler.STATE_PATH).update({ threshold_attention: { path: "x" } });
  before = db.__writes.length;
  const blocked = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(2) }, deps);
  assert.equal(blocked.outcome, "blocked");
  assert.equal(blocked.code, "SCHEDULER_STATE_INVARIANT");
  assert.equal(db.__writes.length, before);
});

test("C9.1.7 every scheduler mutation is fenced: a takeover before a candidate commit writes nothing, and a lease read at or after expiry mutates nothing", async () => {
  const taskPath = "users/u1/tasks/due";
  const { db, deps, clock } = await initialized({ "users/u1": { name: "U" }, [taskPath]: dateTask(new Date("2026-09-06T11:00:00.000Z")) });
  const acquired = await scheduler.acquireScheduler(deps, scheduler.parseScheduleEvent({ scheduleTime: scheduleAt(0) }));
  const run = { ...acquired, deps };
  // takeover: another owner replaces the lease before the candidate commits
  await db.doc(scheduler.LEASE_PATH).set({ ...acquired.lease, ownerToken: "taker" });
  const before = db.__writes.length;
  await assert.rejects(wakeDateTaskInTransaction(db, db.doc(taskPath), run.runNow, run), (e) => e.code === "SCHEDULER_FENCE_LOST");
  assert.equal(db.__writes.length, before);
  assert.equal(db.__docs.get(taskPath).status, "Snoozed");
  // restore the owner's tuple, expire it: a read at/after expiry mutates nothing
  await db.doc(scheduler.LEASE_PATH).set(acquired.lease);
  clock.millis = acquired.lease.expiresAt.toMillis();
  await assert.rejects(wakeDateTaskInTransaction(db, db.doc(taskPath), run.runNow, run), (e) => e.code === "SCHEDULER_FENCE_LOST");
  assert.equal(db.__docs.get(taskPath).status, "Snoozed");
  // live tuple: the candidate commits
  clock.millis = acquired.lease.startedAt.toMillis() + 1000;
  assert.equal(await wakeDateTaskInTransaction(db, db.doc(taskPath), run.runNow, run), true);
  assert.equal(db.__docs.get(taskPath).status, "Upcoming");
});

test("C9.1.14/C9.1.17 phase 0 pages exactly 100/101 with a persisted full-path cursor and ordinary lanes page exactly 50/51; a not-full page deletes the lane's cursor", async () => {
  const docs = { "users/u1": { name: "U" } };
  for (let i = 0; i < 101; i += 1) docs[`users/u1/events/e${String(i).padStart(3, "0")}`] = pendingEvent(`e${String(i).padStart(3, "0")}`);
  for (let i = 0; i < 51; i += 1) docs[`users/u1/tasks/t${String(i).padStart(3, "0")}`] = dateTask(new Date(Date.parse("2026-09-06T11:00:00.000Z") + i * 1000));
  const { db, deps } = await initialized(docs);
  const first = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(0) }, deps);
  assert.equal(first.outcome, "completed");
  const phase0 = first.lanes.find((l) => l.lane === "event_envelope_prepass");
  assert.equal(phase0.examined, 100);
  assert.equal(db.__docs.get(scheduler.STATE_PATH).event_envelope_prepass.path, "users/u1/events/e099", "the 100th examined path persists iff row 101 exists");
  const dateLane = first.lanes.find((l) => l.lane === "date_snoozed_deferred");
  assert.equal(dateLane.examined, 50);
  assert.equal(db.__docs.get(scheduler.STATE_PATH).date_snoozed_deferred.path, "users/u1/tasks/t049");
  assert.equal([...db.__docs.entries()].filter(([p, d]) => p.startsWith("users/u1/tasks/") && d.status === "Upcoming").length, 50);
  const second = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(1) }, deps);
  assert.equal(second.outcome, "completed");
  assert.equal(second.lanes.find((l) => l.lane === "event_envelope_prepass").examined, 1);
  assert.equal(second.lanes.find((l) => l.lane === "date_snoozed_deferred").examined, 1);
  const state = db.__docs.get(scheduler.STATE_PATH);
  assert.equal("event_envelope_prepass" in state, false, "not-full page deletes the phase-0 cursor");
  assert.equal("date_snoozed_deferred" in state, false, "not-full page deletes the lane cursor");
  assert.equal([...db.__docs.entries()].filter(([p, d]) => p.startsWith("users/u1/tasks/") && d.status === "Upcoming").length, 51);
  assert.equal([...db.__docs.entries()].filter(([p, d]) => p.startsWith("users/u1/events/") && d.processingState === "terminal").length, 101);
  assert.equal(Object.keys(state).filter((k) => !["schedulerHealth"].includes(k)).length, 0, "exactly the seven cursor keys are ever present; none remain here");
});

test("C9.1.14 an unsettled page leaves the cursor untouched and the run incomplete; a missed admission deadline starts no wave and completes nothing", async () => {
  const docs = { "users/u1": { name: "U" } };
  for (let i = 0; i < 51; i += 1) docs[`users/u1/tasks/t${String(i).padStart(3, "0")}`] = dateTask(new Date(Date.parse("2026-09-06T11:00:00.000Z") + i * 1000));
  // one selected row belongs to an account under deletion: its reducer refuses (ACCOUNT_DELETION_FENCED) → neither admitted nor classified
  docs["users/u2"] = { accountDeletion: { schemaVersion: 1, state: "DELETING", capabilities: [{ operationId: "adel1_00000000-0000-4000-8000-000000000001", proofSHA256: "a".repeat(64) }], startedAt: Timestamp.fromMillis(0), storageGuardAfter: Timestamp.fromMillis(604800000) } };
  docs["users/u2/tasks/t010"] = docs["users/u1/tasks/t010"]; delete docs["users/u1/tasks/t010"];
  const { db, deps } = await initialized(docs);
  const run = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(0) }, deps);
  assert.equal(run.outcome, "incomplete");
  assert.equal("date_snoozed_deferred" in db.__docs.get(scheduler.STATE_PATH), false, "no cursor create for an unsettled page");
  assert.equal(healthOf(db).recentRuns.at(-1).state, "running");
  assert.equal(healthOf(db).lastCompletedOrdinal, undefined);
  assert.equal(deps.metrics.length, 0, "incomplete evaluations emit no completion metric");
  const late = schedDeps(db, deps.now === undefined ? null : { now: deps.now }, {});
  const { db: db2, deps: deps2 } = await initialized({ "users/u1": { name: "U" }, "users/u1/tasks/a": dateTask(new Date("2026-09-06T11:00:00.000Z")) });
  deps2.elapsedSeconds = () => 300;
  const timedOut = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(0) }, deps2);
  assert.equal(timedOut.outcome, "incomplete");
  assert.equal(db2.__docs.get("users/u1/tasks/a").status, "Snoozed", "no wave started after the deadline");
  void late;
});

test("C9.1.8/C9.1.9 completion turns the running heartbeat into completed with count:0 latency and the exact observable and metric; recentRuns keeps the newest four; duplicate and out-of-order deliveries emit nothing", async () => {
  const { db, deps } = await initialized({ "users/u1": { name: "U" } });
  for (let k = 0; k < 5; k += 1) {
    const run = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(k) }, deps);
    assert.equal(run.outcome, "completed", `ordinal +${k}`);
  }
  const health = scheduler.validateHealth(healthOf(db));
  assert.deepEqual(health.recentRuns.map((r) => r.runOrdinal), [ORD0 + 1, ORD0 + 2, ORD0 + 3, ORD0 + 4]);
  assert.ok(health.recentRuns.every((r) => r.state === "completed" && r.completedAt && JSON.stringify(r.thresholdWakeLatency) === '{"count":0}'));
  assert.equal(health.lastCompletedOrdinal, ORD0 + 4);
  assert.equal(deps.logs.filter(([c]) => c === "DISPOSITION_SCHEDULER_COMPLETED").length, 5);
  assert.deepEqual(deps.logs.filter(([c]) => c === "DISPOSITION_SCHEDULER_COMPLETED").at(-1), ["DISPOSITION_SCHEDULER_COMPLETED", { runOrdinal: ORD0 + 4 }]);
  assert.equal(deps.metrics.filter(([n]) => n === "phase2/disposition_scheduler_completed_count").length, 5);
  const before = deps.metrics.length;
  assert.equal((await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(4) }, deps)).outcome, "refused", "duplicate");
  assert.equal((await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(2) }, deps)).outcome, "refused", "out of order");
  assert.equal(deps.metrics.length, before);
  assert.deepEqual(scheduler.__private.nearestRank([5, 1, 3, 2, 4], 0.5), 3);
  assert.deepEqual(scheduler.__private.nearestRank([5, 1, 3, 2, 4], 0.95), 5);
});

test("C9.1.11 two missed completions create the condition slot before candidate work, a later ordinal advances it, 0/1 missing clears it, a same-ordinal replay is a no-op, and a same-ordinal disagreement is an invariant", async () => {
  const { db, deps } = await initialized({ "users/u1": { name: "U" } });
  const slot = `${scheduler.ALERTS_COLLECTION}/p2b1_two_missed_completions`;
  assert.equal((await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(0) }, deps)).outcome, "completed");
  assert.equal((await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(3) }, deps)).outcome, "completed"); // ordinals +1 and +2 missing
  const first = db.__docs.get(slot);
  assert.equal(first.condition, "TWO_MISSED_COMPLETIONS");
  assert.deepEqual([first.occurrenceCount, first.firstObservedOrdinal, first.lastObservedOrdinal, first.effectiveLastCompletedOrdinal, first.requiredCompletedOrdinal], [1, ORD0 + 3, ORD0 + 3, ORD0, ORD0 + 1]);
  assert.ok(deps.logs.some(([c]) => c === "PHASE2B_TWO_MISSED_COMPLETIONS"));
  assert.equal((await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(6) }, deps)).outcome, "completed");
  const second = db.__docs.get(slot);
  assert.deepEqual([second.occurrenceCount, second.firstObservedOrdinal, second.lastObservedOrdinal, second.requiredCompletedOrdinal], [2, ORD0 + 3, ORD0 + 6, ORD0 + 4]);
  assert.equal((await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(7) }, deps)).outcome, "completed");
  assert.equal(db.__docs.has(slot), false, "a complete observation proving the condition absent deletes the slot");
  // same-ordinal replay is a no-op; disagreement is an invariant with zero writes
  const acquired = await scheduler.acquireScheduler(deps, scheduler.parseScheduleEvent({ scheduleTime: scheduleAt(10) }));
  const run = { ...acquired, deps };
  assert.equal(await scheduler.observeCondition(deps, run, "p2b1_two_missed_completions", "TWO_MISSED_COMPLETIONS", { effectiveLastCompletedOrdinal: 1, requiredCompletedOrdinal: 2 }), "created");
  assert.equal(await scheduler.observeCondition(deps, run, "p2b1_two_missed_completions", "TWO_MISSED_COMPLETIONS", { effectiveLastCompletedOrdinal: 1, requiredCompletedOrdinal: 2 }), "unchanged");
  const before = db.__writes.length;
  await assert.rejects(scheduler.observeCondition(deps, run, "p2b1_two_missed_completions", "TWO_MISSED_COMPLETIONS", { effectiveLastCompletedOrdinal: 9, requiredCompletedOrdinal: 2 }), (e) => e.code === "SCHEDULER_ALERT_SLOT_INVARIANT");
  assert.equal(db.__writes.length, before);
});

// ---------------------------------------------------------------------------
// S3 I9b — due observation, catch-up capacity, threshold fixed-point scan, threshold alerts,
// wake-latency samples (C9.1.8, C9.1.10–C9.1.15, C9.1.17).
// ---------------------------------------------------------------------------

const armedTask = (thresholdAt, extra = {}) => ({ status: "Upcoming", task_generation_epoch: 3, task_instance_id: "ti1", thresholdProjection: { state: "armed", threshold_at: Timestamp.fromMillis(Date.parse(thresholdAt)), threshold_id: "th1", deadline_evidence_id: "de1" }, ...extra });
const alertPath = (id) => `${scheduler.ALERTS_COLLECTION}/${id}`;
const thresholdLaneOf = (report) => report.lanes.find((l) => l.lane === "threshold_attention");
/** Wraps a db so every collectionGroup("tasks") aggregate count resolves through `countOf(real)`; other behaviour is untouched. */
function withCountOverride(db, countOf) {
  const wrapQuery = (q) => new Proxy(q, {
    get(target, key) {
      if (key === "count") return () => { const real = target.count(); return { async get() { const s = await real.get(); return { readTime: s.readTime, data: () => ({ count: countOf(s.data().count) }) }; } }; };
      const value = target[key];
      if (["where", "orderBy", "limit", "select", "startAfter"].includes(key)) return (...args) => wrapQuery(value.apply(target, args));
      return typeof value === "function" ? value.bind(target) : value;
    }
  });
  return new Proxy(db, { get(target, key) { if (key === "collectionGroup") return (id) => (id === "tasks" ? wrapQuery(target.collectionGroup(id)) : target.collectionGroup(id)); const v = target[key]; return typeof v === "function" ? v.bind(target) : v; } });
}

test("C9.1.10 due observation reads the count then the oldest row with separate read times and writes the exact dueObservation into schedulerHealth; a disagreeing pair or a failed query is an observation race that writes no observation, alert, cursor, or completion", async () => {
  const { db, deps, clock } = await initialized({ "users/u1": { name: "U" } });
  assert.equal((await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(0) }, deps)).outcome, "completed");
  let observation = scheduler.validateHealth(healthOf(db)).dueObservation;
  assert.deepEqual(Object.keys(observation).sort(), ["armedDueCandidateCount", "countReadTime", "observedAt", "oldestDueAgeSeconds", "oldestReadTime", "schemaVersion"]);
  assert.deepEqual([observation.armedDueCandidateCount, observation.oldestDueAgeSeconds], [0, 0]);
  await db.doc("users/u1/tasks/a").set(armedTask("2026-09-06T11:40:00Z"));
  await db.doc("users/u1/tasks/b").set(armedTask("2026-09-06T11:50:00Z"));
  await db.doc("users/u1/tasks/c").set(armedTask("2026-09-06T11:55:00Z"));
  await db.doc("users/u1/tasks/future").set(armedTask("2026-09-07T11:55:00Z"));
  await db.doc("users/u1/tasks/attended").set({ ...armedTask("2026-09-06T11:00:00Z"), thresholdProjection: { state: "attended", threshold_at: Timestamp.fromMillis(Date.parse("2026-09-06T11:00:00Z")) } });
  clock.millis = Date.parse(scheduleAt(1)) + 1000;
  const report = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(1) }, deps);
  assert.equal(report.outcome, "completed");
  observation = scheduler.validateHealth(healthOf(db)).dueObservation;
  assert.deepEqual([observation.armedDueCandidateCount, observation.oldestCandidatePath, observation.oldestThresholdAt.toMillis()], [3, "users/u1/tasks/a", Date.parse("2026-09-06T11:40:00Z")]);
  assert.equal(observation.oldestDueAgeSeconds, Math.floor((observation.observedAt.toMillis() - Date.parse("2026-09-06T11:40:00Z")) / 1000));
  assert.ok(observation.countReadTime && observation.oldestReadTime, "two separate read times, never one snapshot");
  const countIndex = db.__reads.findIndex((r) => r === "__group__/x/tasks?count");
  assert.ok(countIndex >= 0 && db.__reads.slice(countIndex + 1).includes("__group__/x/tasks?"), "count read first, oldest second");
  assert.equal(report.thresholdAdmissionCapacity, 400, "the oldest row is 1,501 s overdue → catch-up");
  assert.equal("dueObservation" in db.__docs.get(scheduler.STATE_PATH), false, "dueObservation lives inside schedulerHealth, never as a trigger-state key");
  for (const [label, countOf] of [["count 0 / oldest present", () => 0], ["query failure", () => { throw new Error("unavailable"); }]]) {
    const raced = schedDeps(withCountOverride(db, countOf), clock);
    clock.millis += 300_000;
    const beforeHealth = JSON.stringify(healthOf(db));
    const alertsBefore = JSON.stringify([...db.__docs.entries()].filter(([p]) => p.startsWith(scheduler.ALERTS_COLLECTION)));
    const before = db.__writes.length;
    const result = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(2 + (label.length % 2)) }, raced);
    assert.equal(result.outcome, "incomplete", label);
    assert.ok(raced.logs.some(([c]) => c === (label === "query failure" ? "SCHEDULER_OBSERVATION_FAILED" : "SCHEDULER_OBSERVATION_RACE")), label);
    const health = healthOf(db);
    assert.equal(JSON.stringify(health.dueObservation), JSON.parse(beforeHealth).dueObservation && JSON.stringify(JSON.parse(beforeHealth).dueObservation), `${label}: observation unchanged`);
    assert.equal(health.recentRuns.at(-1).state, "running", label);
    assert.equal(JSON.stringify([...db.__docs.entries()].filter(([p]) => p.startsWith(scheduler.ALERTS_COLLECTION))), alertsBefore, `${label}: no alert written or cleared (the earlier run's oldest-due slot stays)`);
    assert.equal(raced.metrics.length, 0, label);
    assert.equal(db.__writes.slice(before).filter((w) => w.path.startsWith("users/")).length, 0, `${label}: no candidate mutation`);
  }
  // count > 0 / oldest absent is the mirror race
  await db.doc("users/u1/tasks/a").delete(); await db.doc("users/u1/tasks/b").delete(); await db.doc("users/u1/tasks/c").delete();
  clock.millis += 300_000;
  const mirror = schedDeps(withCountOverride(db, () => 5), clock);
  assert.equal((await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(5) }, mirror)).outcome, "incomplete");
  assert.ok(mirror.logs.some(([c]) => c === "SCHEDULER_OBSERVATION_RACE"));
  // grammar: an observation with a partial oldest triple is an invariant; a threshold cursor key in trigger state blocks acquisition
  const good = scheduler.validateHealth(healthOf(db));
  assert.equal(good.dueObservation.armedDueCandidateCount, 3, "the last accepted observation is the ordinal +1 one");
  const { oldestThresholdAt, ...partial } = good.dueObservation;
  assert.throws(() => scheduler.validateHealth({ ...good, dueObservation: partial }), (e) => e.code === "SCHEDULER_HEALTH_INVARIANT", "a partial oldest triple");
  assert.throws(() => scheduler.validateHealth({ ...good, dueObservation: { ...good.dueObservation, oldestThresholdAt, armedDueCandidateCount: 0 } }), (e) => e.code === "SCHEDULER_HEALTH_INVARIANT", "count 0 with oldest members");
  await db.doc(scheduler.STATE_PATH).update({ threshold_attention: { path: "users/u1/tasks/a" } });
  clock.millis += 300_000;
  assert.equal((await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(6) }, deps)).code, "SCHEDULER_STATE_INVARIANT");
});

test("C9.1.12 catchUp is decided after the observations and the eligible-refusal aggregate: an absent lastCompletedOrdinal, a missing ordinal, an eligible threshold refusal, or a candidate overdue by more than 300 seconds admit 400; otherwise 200", async () => {
  const { db, deps, clock } = await initialized({ "users/u1": { name: "U" } });
  const runAt = async (k) => { clock.millis = Date.parse(scheduleAt(k)) + 1000; return scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(k) }, deps); };
  let r = await runAt(0);
  assert.deepEqual([r.outcome, r.catchUp, r.thresholdAdmissionCapacity], ["completed", true, 400], "lastCompletedOrdinal absent");
  r = await runAt(1);
  assert.deepEqual([r.catchUp, r.thresholdAdmissionCapacity], [false, 200], "contiguous");
  r = await runAt(3);
  assert.deepEqual([r.catchUp, r.thresholdAdmissionCapacity], [true, 400], "one missing ordinal");
  await db.doc("users/u1/schedulerRefusals/srf1_x").set({ schemaVersion: 1, lane: "threshold_attention", candidatePath: "users/u1/tasks/x", candidateFingerprint: "f", firstRefusedOrdinal: ORD0 + 3, lastAttemptOrdinal: ORD0 + 3, nextEligibleOrdinal: ORD0 + 4, refusalCount: 1, saturated: false, reasonCode: "VALIDATION_REFUSAL", firstRefusedAt: clock.now(), lastRefusedAt: clock.now() });
  r = await runAt(4);
  assert.deepEqual([r.catchUp, r.thresholdAdmissionCapacity, r.eligibleThresholdRefusalCount], [true, 400, 1], "eligible threshold refusal");
  await db.doc("users/u1/schedulerRefusals/srf1_x").update({ nextEligibleOrdinal: ORD0 + 9 });
  r = await runAt(5);
  assert.deepEqual([r.catchUp, r.thresholdAdmissionCapacity, r.eligibleThresholdRefusalCount], [false, 200, 0], "ineligible refusal does not count");
  await db.doc("users/u1/schedulerRefusals/srf1_x").delete();
  clock.millis = Date.parse(scheduleAt(6)) + 1000;
  await db.doc("users/u1/tasks/old").set(armedTask(new Date(clock.millis - 300_000).toISOString()));
  r = await runAt(6);
  assert.deepEqual([r.catchUp, r.thresholdAdmissionCapacity, healthOf(db).dueObservation.oldestDueAgeSeconds], [false, 200, 300], "exactly 300 seconds is not catch-up");
  await db.doc("users/u1/tasks/old").set(armedTask(new Date(Date.parse(scheduleAt(7)) + 1000 - 301_000).toISOString()));
  r = await runAt(7);
  assert.deepEqual([r.catchUp, r.thresholdAdmissionCapacity, healthOf(db).dueObservation.oldestDueAgeSeconds], [true, 400, 301], "301 seconds is catch-up");
});

test("C9.1.11 OLDEST_DUE_OVER_900_SECONDS is observed at 901 seconds and not at 900 with the exact payload and clears when a complete observation proves it absent; THRESHOLD_CAPACITY_EXCEEDED is active at exactly 201 contiguous and 401 catch-up, never at 200/400", async () => {
  const { db, deps, clock } = await initialized({ "users/u1": { name: "U" } });
  const runAt = async (k) => { clock.millis = Date.parse(scheduleAt(k)) + 1000; return scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(k) }, deps); };
  assert.equal((await runAt(0)).outcome, "completed");
  const oldest = alertPath("p2b1_oldest_due_over_900_seconds");
  await db.doc("users/u1/tasks/a").set(armedTask(new Date(Date.parse(scheduleAt(1)) + 1000 - 900_000).toISOString()));
  assert.equal((await runAt(1)).outcome, "completed");
  assert.equal(db.__docs.has(oldest), false, "900 seconds is not over 900");
  await db.doc("users/u1/tasks/a").set(armedTask(new Date(Date.parse(scheduleAt(2)) + 1000 - 901_000).toISOString()));
  const r2 = await runAt(2);
  assert.equal(r2.outcome, "completed", "the alert does not stop the evaluation");
  const slot = db.__docs.get(oldest);
  assert.deepEqual([slot.condition, slot.occurrenceCount, slot.candidatePath, slot.thresholdAt.toMillis(), slot.ageSeconds, slot.armedDueCandidateCount, slot.firstObservedOrdinal], ["OLDEST_DUE_OVER_900_SECONDS", 1, "users/u1/tasks/a", Date.parse(scheduleAt(2)) + 1000 - 901_000, 901, 1, ORD0 + 2]);
  assert.ok(deps.logs.some(([c, counts]) => c === "PHASE2B_OLDEST_DUE_OVER_900_SECONDS" && counts.occurrenceCount === 1));
  assert.equal((await runAt(3)).outcome, "completed");
  assert.equal(db.__docs.get(oldest).occurrenceCount, 2, "a still-armed row is observed again on the next ordinal");
  await db.doc("users/u1/tasks/a").delete();
  assert.equal((await runAt(4)).outcome, "completed");
  assert.equal(db.__docs.has(oldest), false, "complete observation proving the condition absent deletes the slot");
  // capacity: 200 contiguous rows fit; the 201st exceeds; under catch-up 400 fit and 401 exceed
  const capacity = alertPath("p2b1_threshold_capacity_exceeded");
  // rows are stamped 60 s before each run so that contiguity is decided by the ordinals alone (a row over 300 s overdue is itself a catch-up cause)
  const stamp = (n, k) => { for (let i = 0; i < n; i += 1) db.__docs.set(`users/u1/tasks/c${String(i).padStart(3, "0")}`, armedTask(new Date(Date.parse(scheduleAt(k)) + 1000 - 60_000).toISOString())); };
  stamp(200, 5);
  let r = await runAt(5);
  assert.deepEqual([r.outcome, r.thresholdAdmissionCapacity, db.__docs.has(capacity), r.objective], ["completed", 200, false, true], "exactly 200 fits contiguous");
  assert.equal(thresholdLaneOf(r).admitted, 200);
  stamp(201, 6);
  r = await runAt(6);
  assert.equal(r.objective, false, "201 > 200: the run does not meet the objective");
  const cap = db.__docs.get(capacity);
  assert.deepEqual([cap.condition, cap.armedDueCandidateCount, cap.admissionCapacity, cap.occurrenceCount], ["THRESHOLD_CAPACITY_EXCEEDED", 201, 200, 1]);
  assert.equal(r.outcome, "incomplete", "the scan meets its 201st distinct candidate with capacity consumed");
  stamp(201, 7);
  r = await runAt(7); // previous ordinal incomplete → catch-up 400
  assert.deepEqual([r.outcome, r.thresholdAdmissionCapacity, db.__docs.has(capacity)], ["completed", 400, false], "201 fits catch-up and the capacity slot clears");
  stamp(400, 9);
  r = await runAt(9); // ordinal 8 skipped → catch-up
  assert.deepEqual([r.outcome, r.thresholdAdmissionCapacity, db.__docs.has(capacity)], ["completed", 400, false], "exactly 400 fits catch-up");
  stamp(401, 11);
  r = await runAt(11);
  assert.deepEqual([r.objective, db.__docs.get(capacity).armedDueCandidateCount, db.__docs.get(capacity).admissionCapacity], [false, 401, 400]);
});

test("C9.1.14/C9.1.15/C9.1.17 the threshold lane pages exactly 50/51 run-locally with no trigger-state cursor, admits each distinct candidate once under the select mask and a captured identity, a row inserted behind the run-local cursor is caught by the uncursored pass, and a policy-absent armed row is a definitive no-op that is never mutated", async () => {
  const docs = { "users/u1": { name: "U" } };
  for (let i = 0; i < 51; i += 1) docs[`users/u1/tasks/t${String(i).padStart(3, "0")}`] = armedTask(new Date(Date.parse("2026-09-06T11:00:00Z") + i * 1000).toISOString());
  const { db, deps } = await initialized(docs);
  const before = JSON.stringify([...db.__docs.entries()].filter(([p]) => p.startsWith("users/u1/tasks/")));
  const r = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(0) }, deps);
  assert.equal(r.outcome, "completed");
  const lane = thresholdLaneOf(r);
  assert.deepEqual([lane.admitted, lane.passes, lane.pages], [51, 2, [50, 1, 50, 1]], "50/51 pages, a second uncursored pass reaches the fixed point");
  assert.equal(JSON.stringify([...db.__docs.entries()].filter(([p]) => p.startsWith("users/u1/tasks/"))), before, "policy-absent rows are definitive no-ops: no task byte changes");
  assert.equal(db.__writes.some((w) => w.path === scheduler.STATE_PATH && w.data && "threshold_attention" in w.data), false, "no threshold cursor write");
  assert.deepEqual(Object.keys(db.__docs.get(scheduler.STATE_PATH)), ["schedulerHealth"], "no threshold cursor in trigger state");
  assert.ok(db.__reads.filter((x) => x === "users/u1/tasks/t000").length === 1, "each candidate reread exactly once by path");
  // a row inserted behind the run-local cursor (earlier threshold_at than the first page's last row) is caught by the next pass
  const { db: db2, deps: deps2 } = await initialized(docs);
  let waves = 0;
  deps2.elapsedSeconds = () => { waves += 1; if (waves === 6) db2.__docs.set("users/u1/tasks/late", armedTask("2026-09-06T10:59:00Z")); return 0; };
  const r2 = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(0) }, deps2);
  assert.equal(r2.outcome, "completed");
  assert.deepEqual([thresholdLaneOf(r2).admitted, thresholdLaneOf(r2).passes], [52, 3], "the late row is admitted by the uncursored pass; a third pass proves the fixed point");
  // identity race: a candidate whose captured identity changed before its transaction is neither admitted nor mutated; the page is unsettled
  const { db: db3, deps: deps3 } = await initialized({ "users/u1": { name: "U" }, "users/u1/tasks/x": armedTask("2026-09-06T11:00:00Z") });
  let calls = 0;
  deps3.elapsedSeconds = () => { calls += 1; if (calls === 2) db3.__docs.get("users/u1/tasks/x").task_instance_id = "ti2"; return 0; };
  const r3 = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(0) }, deps3);
  assert.equal(r3.outcome, "incomplete");
  assert.deepEqual([thresholdLaneOf(r3).settled, thresholdLaneOf(r3).admitted], [false, 0]);
  // a fenced owner's row is neither admitted nor classified
  const { db: db4, deps: deps4 } = await initialized({ "users/u2": { accountDeletion: { schemaVersion: 1, state: "DELETING", capabilities: [{ operationId: "adel1_00000000-0000-4000-8000-000000000001", proofSHA256: "a".repeat(64) }], startedAt: Timestamp.fromMillis(0), storageGuardAfter: Timestamp.fromMillis(604800000) } }, "users/u2/tasks/x": armedTask("2026-09-06T11:00:00Z") });
  const r4 = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(0) }, deps4);
  assert.deepEqual([r4.outcome, thresholdLaneOf(r4).settled, db4.__docs.get("users/u2/tasks/x").thresholdProjection.state], ["incomplete", false, "armed"]);
  // a missed threshold deadline starts no wave and leaves the run incomplete with nothing persisted
  const { db: db5, deps: deps5 } = await initialized({ "users/u1": { name: "U" }, "users/u1/tasks/x": armedTask("2026-09-06T11:00:00Z") });
  deps5.elapsedSeconds = () => 130;
  const r5 = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(0) }, deps5);
  assert.deepEqual([r5.outcome, thresholdLaneOf(r5).settled, thresholdLaneOf(r5).admitted], ["incomplete", false, 0]);
  assert.deepEqual(Object.keys(db5.__docs.get(scheduler.STATE_PATH)), ["schedulerHealth"]);
});

test("C9.1.15 with capacity consumed the scan continues without mutation and the first additional distinct eligible candidate writes the exact THRESHOLD_SCAN_CAPACITY_EXCEEDED slot (aggregate count exactly 200, then a late cutoff-eligible row) with no checkpoint or completion; the next run replays and the fixed point deletes the slot", async () => {
  const { db, deps, clock } = await initialized({ "users/u1": { name: "U" } });
  assert.equal((await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(0) }, deps)).outcome, "completed");
  const base = Date.parse(scheduleAt(1)) + 1000 - 250_000; // every row within 300 s of the run: contiguous
  for (let i = 0; i < 200; i += 1) db.__docs.set(`users/u1/tasks/t${String(i).padStart(3, "0")}`, armedTask(new Date(base + i * 1000).toISOString()));
  clock.millis = Date.parse(scheduleAt(1)) + 1000;
  let waves = 0;
  deps.elapsedSeconds = () => { waves += 1; if (waves === 8) db.__docs.set("users/u1/tasks/late", armedTask(new Date(base - 1000).toISOString())); return 0; };
  const r = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(1) }, deps);
  assert.deepEqual([r.outcome, r.objective, r.thresholdAdmissionCapacity, thresholdLaneOf(r).admitted, thresholdLaneOf(r).scanCapacityExceeded], ["incomplete", false, 200, 200, true]);
  const slot = db.__docs.get(alertPath("p2b1_threshold_scan_capacity_exceeded"));
  assert.deepEqual([slot.condition, slot.candidateCountLowerBound, slot.admissionCapacity, slot.occurrenceCount, slot.thresholdCutoff.toMillis()], ["THRESHOLD_SCAN_CAPACITY_EXCEEDED", 201, 200, 1, healthOf(db).dueObservation.observedAt.toMillis()]);
  assert.equal(db.__docs.has(alertPath("p2b1_threshold_capacity_exceeded")), false, "the aggregate count was exactly 200: no capacity alert");
  assert.equal(healthOf(db).recentRuns.at(-1).state, "running");
  assert.equal(deps.metrics.length, 1, "no completion metric for this run (only the first run's)");
  assert.ok(r.lanes.every((l) => l.lane === "threshold_attention" || l.lane === "event_envelope_prepass"), "no ordinary lane runs after the scan alert");
  deps.elapsedSeconds = () => 0;
  clock.millis = Date.parse(scheduleAt(2)) + 1000;
  const replay = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(2) }, deps);
  assert.deepEqual([replay.outcome, replay.thresholdAdmissionCapacity, thresholdLaneOf(replay).admitted], ["completed", 400, 201]);
  assert.equal(db.__docs.has(alertPath("p2b1_threshold_scan_capacity_exceeded")), false, "fixed point deletes the prior scan-capacity slot");
});

test("C9.1.8 completion computes wake-latency samples from the run's committed threshold paths at the completion read time with nearest-rank quantiles; no committed path is exactly {count:0}", async () => {
  const { db, deps, clock } = await initialized({ "users/u1": { name: "U" } });
  const acquired = await scheduler.acquireScheduler(deps, scheduler.parseScheduleEvent({ scheduleTime: scheduleAt(0) }));
  const run = { ...acquired, deps };
  const at = (s) => Timestamp.fromMillis(clock.millis - s * 1000);
  const completedAt = await scheduler.completeScheduler(deps, run, [{ path: "users/u1/tasks/a", thresholdAt: at(10) }, { path: "users/u1/tasks/b", thresholdAt: at(1) }, { path: "users/u1/tasks/c", thresholdAt: at(7) }, { path: "users/u1/tasks/d", thresholdAt: at(-5) }, { path: "users/u1/tasks/e", thresholdAt: at(3.7) }]);
  assert.equal(completedAt.toMillis(), clock.millis);
  const latency = scheduler.validateHealth(healthOf(db)).recentRuns.at(-1).thresholdWakeLatency;
  assert.deepEqual(latency, { count: 5, p50Seconds: 3, p95Seconds: 10, maxSeconds: 10 });
  await scheduler.releaseScheduler(deps, run);
  const acquired2 = await scheduler.acquireScheduler(deps, scheduler.parseScheduleEvent({ scheduleTime: scheduleAt(1) }));
  await scheduler.completeScheduler(deps, { ...acquired2, deps }, []);
  assert.deepEqual(scheduler.validateHealth(healthOf(db)).recentRuns.at(-1).thresholdWakeLatency, { count: 0 });
});

test("timeouts do not exceed 300 seconds", () => {
  const root = path.resolve(__dirname, "..");
  const read = (f) => fs.readFileSync(path.join(root, f), "utf8");
  const participating = ["index.js", "dispositionTriggers.js", "getWorkflowQualifying.js", "spawnTasks.js", "processInventory.js", "researchTask.js", "peezyChat.js", "packageInventory.js", "submitCheckIn.js", "entitlement.js", "validateSubscription.js", "supportAdmin.js", "resolveProvider.js"];
  for (const file of participating) {
    for (const match of read(file).matchAll(/timeoutSeconds:\s*(\d+)/g)) assert.ok(Number(match[1]) <= 300, `${file} timeoutSeconds ${match[1]}`);
  }
  assert.match(read("taskPlan.js"), /timeoutSeconds: 540/, "changeTaskPlan is expressly non-participating and stays at 540");
  for (const file of ["peezyChat.js", "researchTask.js", "processInventory.js"]) {
    const source = read(file);
    const construction = source.match(/new Anthropic\(\{[^}]*\}\)/);
    assert.ok(construction && /timeout:\s*([A-Z_]+)/.test(construction[0]), `${file} Anthropic client carries a timeout`);
    const constant = construction[0].match(/timeout:\s*([A-Z_]+)/)[1];
    const value = Number(source.match(new RegExp(`const ${constant} = (\\d+)`))[1]);
    assert.ok(value <= 300_000, `${file} ${constant} ${value}`);
  }
  for (const file of ["notifySupport.js", "packageInventory.js"]) {
    const source = read(file);
    assert.match(source, /socketTimeout: SMTP_TIMEOUT_MS/);
    assert.ok(Number(source.match(/const SMTP_TIMEOUT_MS = (\d+)/)[1]) <= 300_000);
  }
  for (const file of ["notifySupport.js", "submitCheckIn.js"]) {
    const source = read(file);
    assert.match(source, /twilio\(accountSid, authToken, \{ timeout: SMS_TIMEOUT_MS \}\)/);
    assert.ok(Number(source.match(/const SMS_TIMEOUT_MS = (\d+)/)[1]) <= 300_000);
  }
});

test("C7 firestore.indexes.json equals the frozen base plus the eight appends", () => {
  const { createHash } = require("node:crypto");
  const root = path.resolve(__dirname, "../..");
  const bytes = fs.readFileSync(path.join(root, "firestore.indexes.json"));
  assert.equal(bytes.length, 5872);
  assert.equal(createHash("sha256").update(bytes).digest("hex"), "a6de8daf701a75ff3db025ca244dbf2218432c5c1a06b0992cd88358250d88e8");
  const parsed = JSON.parse(bytes.toString("utf8"));
  assert.equal(parsed.indexes.length, 4);
  assert.equal(parsed.fieldOverrides.length, 35);
  assert.deepEqual(parsed.indexes[3].fields.map((f) => f.fieldPath), ["lane", "nextEligibleOrdinal", "firstRefusedOrdinal", "lastAttemptOrdinal"]);
  const base = { indexes: parsed.indexes.slice(0, 3), fieldOverrides: parsed.fieldOverrides.slice(0, 28) };
  const baseBytes = Buffer.from(JSON.stringify(base, null, 2) + "\n");
  assert.equal(baseBytes.length, 4432);
  assert.equal(createHash("sha256").update(baseBytes).digest("hex"), "a7a432ec8e0511176b890432c5e4cb4a07e59a6dba0c9d920948cc446f3a7bbb");
});
