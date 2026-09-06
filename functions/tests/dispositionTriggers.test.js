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
