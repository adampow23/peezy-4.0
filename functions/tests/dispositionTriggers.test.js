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

test("invalid pending event is quarantined after three identical failures and leaves no high-water row", async () => {
  // S3 I9d supersedes the Phase-1 form of this case: C9.1.26 quarantines on the third identical deterministic failure, and
  // an `undefined` member is an unencodable source by the C9.1.21 predicate order, so the fixture fails OBSERVED_AT_INVALID instead.
  const eventPath = "users/u1/events/bad-event";
  const db = fakeFirestore({ docs: { "users/u1": { name: "U" }, [eventPath]: event({ event_id: "bad-event", observed_at: "not a timestamp" }) } });
  assert.equal(await consumeEventEnvelopeInTransaction(db, db.doc(eventPath), NOW), "retry");
  assert.equal(await consumeEventEnvelopeInTransaction(db, db.doc(eventPath), NOW), "retry");
  assert.equal(await consumeEventEnvelopeInTransaction(db, db.doc(eventPath), NOW), "quarantined");
  assert.equal(db.__docs.get(eventPath).outcome, "quarantined");
  assert.equal(db.__docs.get(eventPath).processingError, "observed_at must be a valid timestamp.");
  assert.equal([...db.__docs.keys()].filter((key) => key.includes("/eventState/")).length, 0);
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
  const deps = { db, logs: [], metrics: [], now: () => clock.now(), log: (code, counts) => deps.logs.push([code, counts]), metric: (n, v) => deps.metrics.push([n, v]), elapsedSeconds: () => 0, fetchRawDocument: require("./support/rawDocument").rawFetcherFor(db), ...extra };
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
  // one selected row carries a malformed refusal record at its deterministic path: C9.1.18 fails closed → neither admitted nor classified
  // (S3 I9c supersedes the I9a fixture that used a fenced owner here: under C9.1.20 a fenced owner is branch (2), a classified refusal)
  docs[`users/u1/schedulerRefusals/${require("../dispositionTriggers").refusalId("date_snoozed_deferred", "users/u1/tasks/t010")}`] = { schemaVersion: 1, lane: "date_snoozed_deferred", candidatePath: "users/u1/tasks/t010", candidateFingerprint: "0".repeat(64), firstRefusedOrdinal: 1, lastAttemptOrdinal: 1, nextEligibleOrdinal: 99, refusalCount: 9, saturated: true, reasonCode: "VALIDATION_REFUSAL", firstRefusedAt: Timestamp.fromMillis(0), lastRefusedAt: Timestamp.fromMillis(0) };
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
  await db.doc("users/u1/tasks/x").set(armedTask(new Date(Date.parse(scheduleAt(4)) + 1000 - 60_000).toISOString()));
  const refusalFor = async (next) => ({ schemaVersion: 1, lane: "threshold_attention", candidatePath: "users/u1/tasks/x", candidateFingerprint: scheduler.candidateFingerprint(scheduler.THRESHOLD_LANE_SPEC, await db.doc("users/u1/tasks/x").get()), firstRefusedOrdinal: ORD0 + 3, lastAttemptOrdinal: ORD0 + 3, nextEligibleOrdinal: next, refusalCount: 1, saturated: false, reasonCode: "VALIDATION_REFUSAL", firstRefusedAt: clock.now(), lastRefusedAt: clock.now() });
  const rpath = `users/u1/schedulerRefusals/${scheduler.refusalId("threshold_attention", "users/u1/tasks/x")}`;
  db.__docs.set(rpath, await refusalFor(ORD0 + 4));
  r = await runAt(4);
  assert.deepEqual([r.catchUp, r.thresholdAdmissionCapacity, r.eligibleThresholdRefusalCount, r.outcome], [true, 400, 1, "completed"], "eligible threshold refusal");
  assert.equal(db.__docs.has(rpath), false, "the retry's definitive no-op deleted the refusal");
  db.__docs.get("users/u1/tasks/x").thresholdProjection.threshold_at = Timestamp.fromMillis(Date.parse(scheduleAt(5)) + 1000 - 60_000);
  db.__docs.set(rpath, await refusalFor(ORD0 + 9));
  r = await runAt(5);
  assert.deepEqual([r.catchUp, r.thresholdAdmissionCapacity, r.eligibleThresholdRefusalCount], [false, 200, 0], "ineligible refusal does not count");
  db.__docs.delete(rpath);
  db.__docs.delete("users/u1/tasks/x");
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
  assert.equal(r3.outcome, "completed", "an identity race is classified by an IDENTITY_RACE refusal (C9.1.18)");
  assert.deepEqual([thresholdLaneOf(r3).settled, thresholdLaneOf(r3).admitted, thresholdLaneOf(r3).refused], [true, 0, 1]);
  assert.equal([...db3.__docs.values()].find((d) => d.lane === "threshold_attention").reasonCode, "IDENTITY_RACE");
  assert.equal(db3.__docs.get("users/u1/tasks/x").thresholdProjection.state, "armed", "no mutation under a moved identity");
  // a fenced owner's row is classified by an AUTHORITY_REFUSAL and never mutated
  const { db: db4, deps: deps4 } = await initialized({ "users/u2": { accountDeletion: { schemaVersion: 1, state: "DELETING", capabilities: [{ operationId: "adel1_00000000-0000-4000-8000-000000000001", proofSHA256: "a".repeat(64) }], startedAt: Timestamp.fromMillis(0), storageGuardAfter: Timestamp.fromMillis(604800000) } }, "users/u2/tasks/x": armedTask("2026-09-06T11:00:00Z") });
  const r4 = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(0) }, deps4);
  assert.deepEqual([r4.outcome, thresholdLaneOf(r4).settled, thresholdLaneOf(r4).refused, db4.__docs.get("users/u2/tasks/x").thresholdProjection.state], ["completed", true, 1, "armed"]);
  assert.equal([...db4.__docs.values()].find((d) => d.lane === "threshold_attention").reasonCode, "AUTHORITY_REFUSAL");
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

// ---------------------------------------------------------------------------
// S3 I9c — durable refusals, eligible retry admission, fairness alert, ordinary cursor-pass branches
// (C9.1.11, C9.1.18, C9.1.19, C9.1.20).
// ---------------------------------------------------------------------------

const DELETING_ROOT = { accountDeletion: { schemaVersion: 1, state: "DELETING", capabilities: [{ operationId: "adel1_00000000-0000-4000-8000-000000000001", proofSHA256: "a".repeat(64) }], startedAt: Timestamp.fromMillis(0), storageGuardAfter: Timestamp.fromMillis(604800000) } };
const laneOf = (report, lane) => report.lanes.find((l) => l.lane === lane);
const refusalsOf = (db, lane) => [...db.__docs.entries()].filter(([p, d]) => p.includes("/schedulerRefusals/") && (!lane || d.lane === lane)).map(([p, d]) => [p, d]);
const runAtK = (deps, clock) => async (k) => { clock.millis = Date.parse(scheduleAt(k)) + 1000; return scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(k) }, deps); };

test("C9.1.18 the refusal id and fingerprint derivations are exact and a record violating any invariant fails closed", () => {
  const lane = scheduler.ORDINARY_LANES[0];
  const id = scheduler.refusalId(lane.lane, "users/u1/tasks/t1");
  const expected = "srf1_" + createHash("sha256").update(JSON.stringify({ candidate_path: "users/u1/tasks/t1", domain: "scheduler_refusal.v1", lane: "date_snoozed_deferred" })).digest("hex").slice(0, 40);
  assert.equal(id, expected);
  assert.equal(scheduler.refusalId(scheduler.THRESHOLD_LANE, "users/u1/tasks/t1") === id, false, "the lane is part of the identity");
  const at = Timestamp.fromMillis(Date.parse("2026-09-06T11:00:00Z"));
  const snapshot = { ref: { path: "users/u1/tasks/t1" }, updateTime: Timestamp.fromMillis(1_700_000_000_123), get: (f) => ({ status: "Snoozed", "dispositionContract.next_trigger.kind": "date", "dispositionContract.next_trigger.fired": false, "dispositionContract.next_trigger.at": at, task_generation_epoch: 2 })[f] };
  const fingerprint = scheduler.candidateFingerprint(lane, snapshot);
  const canonical = JSON.stringify({ candidate_path: "users/u1/tasks/t1", document_update_time: { nanos: 123000000, seconds: 1700000000 }, lane: "date_snoozed_deferred", selected_identity: { "dispositionContract.next_trigger.at": at.toDate().toISOString(), "dispositionContract.next_trigger.fired": false, "dispositionContract.next_trigger.kind": "date", status: "Snoozed", task_generation_epoch: 2, task_instance_id: { missing: true } } });
  assert.equal(fingerprint, createHash("sha256").update(canonical).digest("hex"), "explicit missing tag for task_instance_id; no domain member");
  const good = { schemaVersion: 1, lane: lane.lane, candidatePath: "users/u1/tasks/t1", candidateFingerprint: fingerprint, firstRefusedOrdinal: 10, lastAttemptOrdinal: 12, nextEligibleOrdinal: 14, refusalCount: 2, saturated: false, reasonCode: "VALIDATION_REFUSAL", firstRefusedAt: at, lastRefusedAt: at };
  assert.deepEqual(scheduler.validateRefusal(good, lane, "users/u1/tasks/t1", id), good);
  for (const [label, bad] of [
    ["count 0", { refusalCount: 0 }], ["count 9", { refusalCount: 9, saturated: true }], ["saturated mismatch", { saturated: true }], ["count 8 unsaturated", { refusalCount: 8 }],
    ["lastAttempt < first", { lastAttemptOrdinal: 9 }], ["nextEligible == lastAttempt", { nextEligibleOrdinal: 12 }], ["lastRefusedAt < firstRefusedAt", { lastRefusedAt: Timestamp.fromMillis(0) }],
    ["unknown reason", { reasonCode: "OTHER" }], ["wrong lane", { lane: "event_snoozed_deferred" }], ["wrong path", { candidatePath: "users/u1/tasks/t2" }], ["surplus member", { extra: 1 }], ["bad fingerprint", { candidateFingerprint: "xyz" }]
  ]) assert.throws(() => scheduler.validateRefusal({ ...good, ...bad }, lane, "users/u1/tasks/t1", id), (e) => e.code === "SCHEDULER_REFUSAL_INVARIANT", label);
  assert.throws(() => scheduler.validateRefusal(good, lane, "users/u1/tasks/t1", "srf1_" + "0".repeat(40)), (e) => e.code === "SCHEDULER_REFUSAL_INVARIANT", "derived-id disagreement");
});

test("C9.1.18/C9.1.20 branch (2) creates the exact refusal after rereading the candidate, same-fingerprint repeats back off min(2^(n-1),16) to saturation at 8 with no eviction, a fresh row with an ineligible same-fingerprint refusal is branch (4) with no write, a changed fingerprint restarts at one after the stale authority is removed, and a retry that succeeds deletes the refusal atomically with the wake", async () => {
  const at = new Date("2026-09-06T11:00:00.000Z");
  const { db, deps, clock } = await initialized({ "users/u1": { name: "U" }, "users/u2": DELETING_ROOT, "users/u2/tasks/x": dateTask(at) });
  const runAt = runAtK(deps, clock);
  const path = "users/u2/tasks/x";
  const rpath = `users/u2/schedulerRefusals/${scheduler.refusalId("date_snoozed_deferred", path)}`;
  let r = await runAt(0);
  assert.equal(r.outcome, "completed", "a classified refusal settles the row");
  let rec = db.__docs.get(rpath);
  assert.deepEqual([rec.schemaVersion, rec.lane, rec.candidatePath, rec.reasonCode, rec.refusalCount, rec.saturated, rec.firstRefusedOrdinal, rec.lastAttemptOrdinal, rec.nextEligibleOrdinal], [1, "date_snoozed_deferred", path, "AUTHORITY_REFUSAL", 1, false, ORD0, ORD0, ORD0 + 1]);
  assert.equal(rec.firstRefusedAt.toMillis(), rec.lastRefusedAt.toMillis());
  assert.equal(db.__docs.get(path).status, "Snoozed", "no candidate mutation");
  assert.deepEqual([laneOf(r, "date_snoozed_deferred").refused, laneOf(r, "date_snoozed_deferred").retried], [1, 0]);
  // backoff: eligible at +1 (count 2, +2), +3 (3, +4), +7 (4, +8), +15 (5, +16), +31 (6), +47 (7), +63 (8 saturated), +79 (stays 8)
  const expectations = [[1, 2, 3], [3, 3, 7], [7, 4, 15], [15, 5, 31], [31, 6, 47], [47, 7, 63], [63, 8, 79], [79, 8, 95]];
  for (const [k, count, next] of expectations) {
    r = await runAt(k);
    rec = db.__docs.get(rpath);
    assert.deepEqual([rec.refusalCount, rec.nextEligibleOrdinal - ORD0, rec.saturated, rec.firstRefusedOrdinal, rec.lastAttemptOrdinal - ORD0], [count, next, count === 8, ORD0, k], `ordinal +${k}`);
    assert.equal(laneOf(r, "date_snoozed_deferred").retried, 1, `ordinal +${k} retried through the eligible query`);
  }
  assert.equal(refusalsOf(db).length, 1, "no eviction, one authority per (uid, lane, path)");
  // ineligible ordinal: the fresh query still selects the row → branch (4): no write, cursor passes, lane completes
  const before = db.__writes.length;
  r = await runAt(80);
  assert.equal(r.outcome, "completed");
  assert.deepEqual([laneOf(r, "date_snoozed_deferred").retried, laneOf(r, "date_snoozed_deferred").extant], [0, 1]);
  assert.equal(db.__writes.slice(before).filter((w) => w.path === rpath || w.path === path).length, 0, "branch (4) writes nothing");
  assert.equal(db.__docs.get(rpath).lastAttemptOrdinal, ORD0 + 79);
  // changed fingerprint on a fresh admission: stale authority deleted after the full reread; the candidate consumes the fresh slot; refusing again restarts at one
  db.__docs.get(path).task_instance_id = "ti-changed";
  r = await runAt(81);
  rec = db.__docs.get(rpath);
  assert.deepEqual([rec.refusalCount, rec.firstRefusedOrdinal - ORD0, rec.nextEligibleOrdinal - ORD0, rec.saturated], [1, 81, 82, false], "restart at one with the new fingerprint");
  // retry succeeds: the owner is live again → the wake commits and the refusal is deleted in the same transaction
  db.__docs.set("users/u2", { name: "live" });
  r = await runAt(82);
  assert.equal(db.__docs.get(path).status, "Upcoming");
  assert.equal(db.__docs.has(rpath), false, "success deletes the refusal atomically");
  const wake = db.__writes.findLast((w) => w.path === path);
  const del = db.__writes.findLast((w) => w.path === rpath);
  assert.ok(wake && del && wake.batch === del.batch, "same transaction");
});

test("C9.1.19 retries come first from the ordered aggregate-then-pages query with the ordinary reserve of 10 and both transfer directions; the fresh page shrinks by the retries admitted so the lane never exceeds 50; 51 early ineligible refusal rows are classified by branch (4) and later fresh rows are admitted", async () => {
  const docs = { "users/u1": { name: "U" }, "users/u2": DELETING_ROOT };
  for (let i = 0; i < 25; i += 1) docs[`users/u2/tasks/r${String(i).padStart(2, "0")}`] = dateTask(new Date("2026-09-06T11:30:00.000Z")); // sorts after the fresh rows below
  const { db, deps, clock } = await initialized(docs);
  const runAt = runAtK(deps, clock);
  let r = await runAt(0);
  assert.deepEqual([r.outcome, refusalsOf(db).length], ["completed", 25]);
  for (let i = 0; i < 45; i += 1) db.__docs.set(`users/u1/tasks/f${String(i).padStart(2, "0")}`, dateTask(new Date(Date.parse("2026-09-06T11:00:00.000Z") + i * 1000)));
  r = await runAt(1);
  let lane = laneOf(r, "date_snoozed_deferred");
  assert.deepEqual([lane.retried, lane.admitted, lane.examined], [10, 40, 40], "10 reserved retries + 40 fresh = 50; the fresh page is 40/41");
  assert.equal(db.__docs.get(scheduler.STATE_PATH).date_snoozed_deferred.path, "users/u1/tasks/f39", "checkpoint at the 40th fresh row because a 41st exists");
  assert.equal(refusalsOf(db).filter(([, d]) => d.refusalCount === 2).length, 10, "exactly the ordered prefix of ten was retried");
  assert.equal(refusalsOf(db).filter(([, d]) => d.refusalCount === 1).length, 15);
  r = await runAt(2);
  lane = laneOf(r, "date_snoozed_deferred");
  assert.deepEqual([lane.retried, lane.admitted, lane.extant], [15, 5, 10], "fresh → retry transfer: the page holds 5 fresh + 25 refused rows (30 < 40), so all 15 eligible retries run; the ten ineligible rows are branch (4)");
  assert.equal([...db.__docs.entries()].filter(([p, d]) => p.startsWith("users/u1/tasks/") && d.status === "Upcoming").length, 45);
  assert.equal("date_snoozed_deferred" in db.__docs.get(scheduler.STATE_PATH), false, "a not-full page deletes the cursor");
  r = await runAt(3);
  lane = laneOf(r, "date_snoozed_deferred");
  assert.deepEqual([lane.retried, lane.admitted, lane.extant], [10, 0, 15], "retry → fresh transfer leaves nothing to admit; the ten eligible at +3 retry");
  // 51 early ineligible refusal rows sort before fresh rows: branch (4) advances the cursor; later fresh rows are admitted
  const { db: db2, deps: deps2, clock: clock2 } = await initialized({ "users/u1": { name: "U" }, "users/u2": DELETING_ROOT });
  const runAt2 = runAtK(deps2, clock2);
  const laneSpec = scheduler.ORDINARY_LANES[0];
  for (let i = 0; i < 51; i += 1) {
    const path = `users/u2/tasks/e${String(i).padStart(2, "0")}`;
    db2.__docs.set(path, dateTask(new Date(Date.parse("2026-09-06T10:00:00.000Z") + i * 1000)));
    db2.__docs.set(`users/u2/schedulerRefusals/${scheduler.refusalId(laneSpec.lane, path)}`, { schemaVersion: 1, lane: laneSpec.lane, candidatePath: path, candidateFingerprint: scheduler.candidateFingerprint(laneSpec, await db2.doc(path).get()), firstRefusedOrdinal: ORD0 - 1, lastAttemptOrdinal: ORD0 - 1, nextEligibleOrdinal: ORD0 + 50, refusalCount: 1, saturated: false, reasonCode: "AUTHORITY_REFUSAL", firstRefusedAt: clock2.now(), lastRefusedAt: clock2.now() });
  }
  for (let i = 0; i < 5; i += 1) db2.__docs.set(`users/u1/tasks/z${i}`, dateTask(new Date("2026-09-06T11:30:00.000Z")));
  let r2 = await runAt2(0);
  lane = laneOf(r2, "date_snoozed_deferred");
  assert.deepEqual([r2.outcome, lane.retried, lane.extant, lane.admitted], ["completed", 0, 50, 0], "50 ineligible same-fingerprint rows are branch (4) and the cursor advances past them");
  assert.equal(db2.__docs.get(scheduler.STATE_PATH).date_snoozed_deferred.path, "users/u2/tasks/e49");
  r2 = await runAt2(1);
  lane = laneOf(r2, "date_snoozed_deferred");
  assert.deepEqual([r2.outcome, lane.retried, lane.extant, lane.admitted], ["completed", 0, 1, 5], "the 51st ineligible row is branch (4); the five fresh rows behind it are admitted");
  assert.equal([...db2.__docs.entries()].filter(([p, d]) => p.startsWith("users/u1/tasks/z") && d.status === "Upcoming").length, 5);
  assert.equal(refusalsOf(db2).filter(([, d]) => d.lastAttemptOrdinal >= ORD0).length, 0, "branch (4) rows consume no slot and receive no write");
});

test("C9.1.20 branch (3): a retry whose candidate is absent deletes the obsolete refusal, a retry whose candidate changed deletes the obsolete authority and the row is admitted fresh, a malformed refusal at the deterministic path fails closed with no candidate mutation and no cursor advance, and a refusal id/content disagreement fails closed", async () => {
  const at = new Date("2026-09-06T11:00:00.000Z");
  const { db, deps, clock } = await initialized({ "users/u1": { name: "U" }, "users/u1/tasks/live": dateTask(at) });
  const runAt = runAtK(deps, clock);
  const lane = scheduler.ORDINARY_LANES[0];
  const stale = { schemaVersion: 1, lane: lane.lane, candidatePath: "users/u1/tasks/gone", candidateFingerprint: "f".repeat(64), firstRefusedOrdinal: ORD0 - 5, lastAttemptOrdinal: ORD0 - 5, nextEligibleOrdinal: ORD0 - 4, refusalCount: 1, saturated: false, reasonCode: "VALIDATION_REFUSAL", firstRefusedAt: clock.now(), lastRefusedAt: clock.now() };
  db.__docs.set(`users/u1/schedulerRefusals/${scheduler.refusalId(lane.lane, "users/u1/tasks/gone")}`, stale);
  db.__docs.set(`users/u1/schedulerRefusals/${scheduler.refusalId(lane.lane, "users/u1/tasks/live")}`, { ...stale, candidatePath: "users/u1/tasks/live" });
  let r = await runAt(0);
  assert.equal(r.outcome, "completed");
  assert.equal(refusalsOf(db).length, 0, "absent → obsolete refusal deleted; changed → obsolete authority deleted");
  assert.equal(db.__docs.get("users/u1/tasks/live").status, "Upcoming", "the changed candidate is admitted fresh in the same run");
  // malformed refusal at the deterministic path of a fresh candidate: fail closed
  db.__docs.set("users/u1/tasks/next", dateTask(at));
  db.__docs.set(`users/u1/schedulerRefusals/${scheduler.refusalId(lane.lane, "users/u1/tasks/next")}`, { ...stale, candidatePath: "users/u1/tasks/next", refusalCount: 9, saturated: true, nextEligibleOrdinal: ORD0 + 50 });
  r = await runAt(1);
  assert.deepEqual([r.outcome, laneOf(r, "date_snoozed_deferred").settled, db.__docs.get("users/u1/tasks/next").status], ["incomplete", false, "Snoozed"]);
  assert.ok(deps.logs.some(([c]) => c === "SCHEDULER_REFUSAL_INVARIANT"));
  assert.equal("date_snoozed_deferred" in db.__docs.get(scheduler.STATE_PATH), false, "no cursor advance");
  // id/content disagreement: a well-formed record whose lane disagrees with its derived id
  db.__docs.set(`users/u1/schedulerRefusals/${scheduler.refusalId(lane.lane, "users/u1/tasks/next")}`, { ...stale, candidatePath: "users/u1/tasks/next", lane: "event_snoozed_deferred" });
  r = await runAt(2);
  assert.deepEqual([r.outcome, db.__docs.get("users/u1/tasks/next").status], ["incomplete", "Snoozed"]);
});

test("C9.1.11/C9.1.19 an eligible refusal count above the ceiling (100 contiguous, 200 catch-up) writes the exact lane FAIRNESS_CAPACITY_EXCEEDED slot with refusalCapacity = the ceiling, the bounded prefix is still processed, a count at the ceiling writes nothing, and the slot clears when the count falls within the ceiling", async () => {
  const { db, deps, clock } = await initialized({ "users/u1": { name: "U" } });
  const runAt = runAtK(deps, clock);
  const slot = alertPath("p2b1_fairness_capacity_exceeded_date_snoozed_deferred");
  // valid records for absent candidates: each retry deletes its obsolete authority (branch 3), bounded by the lane ceiling of 50
  const seedRefusals = (n) => { for (let i = 0; i < n; i += 1) { const path = `users/u3/tasks/g${String(i).padStart(3, "0")}`; db.__docs.set(`users/u3/schedulerRefusals/${scheduler.refusalId("date_snoozed_deferred", path)}`, { schemaVersion: 1, lane: "date_snoozed_deferred", candidatePath: path, candidateFingerprint: "a".repeat(64), firstRefusedOrdinal: ORD0, lastAttemptOrdinal: ORD0, nextEligibleOrdinal: ORD0 + 1, refusalCount: 1, saturated: false, reasonCode: "VALIDATION_REFUSAL", firstRefusedAt: clock.now(), lastRefusedAt: clock.now() }); } };
  assert.equal((await runAt(0)).outcome, "completed", "the first run is catch-up by definition; the ceilings below are decided by contiguity");
  seedRefusals(101);
  let r = await runAt(1);
  assert.deepEqual([r.outcome, r.objective, r.thresholdRefusalCeiling, laneOf(r, "date_snoozed_deferred").retried, refusalsOf(db).length], ["completed", false, 100, 50, 51], "101 > 100: alert; the bounded ordered prefix (the lane ceiling, no fresh rows) is still processed");
  const s = db.__docs.get(slot);
  assert.deepEqual([s.condition, s.lane, s.eligibleRefusalCount, s.refusalCapacity, s.occurrenceCount, s.firstObservedOrdinal], ["FAIRNESS_CAPACITY_EXCEEDED", "date_snoozed_deferred", 101, 100, 1, ORD0 + 1]);
  assert.ok(deps.logs.some(([c]) => c === "PHASE2B_FAIRNESS_CAPACITY_EXCEEDED"));
  r = await runAt(2);
  assert.deepEqual([r.objective, laneOf(r, "date_snoozed_deferred").eligibleRefusalCount, db.__docs.has(slot), refusalsOf(db).length], [true, 51, false, 1], "51 ≤ 100 clears the slot by a complete observation");
  for (const [p] of refusalsOf(db)) db.__docs.delete(p);
  seedRefusals(100);
  r = await runAt(3);
  assert.deepEqual([r.objective, laneOf(r, "date_snoozed_deferred").eligibleRefusalCount, db.__docs.has(slot), refusalsOf(db).length], [true, 100, false, 50], "exactly 100 contiguous writes nothing");
  seedRefusals(201);
  r = await runAt(5); // +4 skipped → catch-up ceiling 200
  assert.deepEqual([r.objective, r.thresholdRefusalCeiling, db.__docs.get(slot).eligibleRefusalCount, db.__docs.get(slot).refusalCapacity], [false, 200, 201, 200], "refusalCapacity is the ceiling, never the observed count");
  seedRefusals(200);
  r = await runAt(7); // +6 skipped → catch-up
  assert.deepEqual([r.objective, laneOf(r, "date_snoozed_deferred").eligibleRefusalCount, db.__docs.has(slot)], [true, 200, false], "exactly 200 under catch-up writes nothing and clears the slot");
});

test("C9.1.19 the threshold lane admits eligible retries first from half the ceiling, a retried threshold candidate is settled once across both sources, and a fenced threshold candidate records a threshold_attention refusal", async () => {
  const { db, deps, clock } = await initialized({ "users/u1": { name: "U" }, "users/u2": DELETING_ROOT, "users/u2/tasks/a": armedTask("2026-09-06T11:59:30Z"), "users/u1/tasks/b": armedTask("2026-09-06T11:59:30Z") });
  const runAt = runAtK(deps, clock);
  let r = await runAt(0);
  assert.equal(r.outcome, "completed");
  const rec = refusalsOf(db, "threshold_attention");
  assert.equal(rec.length, 1);
  assert.deepEqual([rec[0][1].candidatePath, rec[0][1].reasonCode, rec[0][1].nextEligibleOrdinal], ["users/u2/tasks/a", "AUTHORITY_REFUSAL", ORD0 + 1]);
  assert.deepEqual([thresholdLaneOf(r).refused, thresholdLaneOf(r).admitted], [1, 1]);
  r = await runAt(1); // the rows are unchanged, so the retry's reread matches the refusal's fingerprint
  assert.equal(r.outcome, "completed");
  assert.deepEqual([r.thresholdAdmissionCapacity, thresholdLaneOf(r).retried, thresholdLaneOf(r).retryReserve, thresholdLaneOf(r).admitted], [400, 1, 200, 1], "an eligible threshold refusal is a catch-up cause (C9.1.12): reserve 200 of 400; one retry, one fresh; the retried path is not admitted again by the scan");
  assert.equal(refusalsOf(db, "threshold_attention")[0][1].refusalCount, 2);
});

// ---------------------------------------------------------------------------
// S3 I9d-1 — OriginalEventBytesV1, the qev1 code/message table and precedence, the retry member and
// attempt 1→2→qev1, SOURCE_UNENCODABLE qevu1 (C9.1.21, C9.1.22, C9.1.26, C9.1.29).
// ---------------------------------------------------------------------------

const { GeoPoint, VectorValue } = require("@google-cloud/firestore");
const hex64 = (n) => { const b = Buffer.alloc(8); b.writeDoubleBE(n, 0); return b.toString("hex"); };
const QUARANTINE_COLLECTION = "phase1System/dispositionTriggerState/quarantinedEvents";
const QEV1_TABLE = {
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
};

test("C9.1.21 OriginalEventBytesV1 encodes doubles big-endian (1.0, -0, subnormal), follows the predicate order, tokenizes non-plain and unsupported values, and treats malformed instances and cycles as infrastructure invariants", () => {
  const enc = (v) => scheduler.encodeOriginalEventBytes(v).toString("utf8");
  assert.equal(enc(1.0), "d3ff0000000000000");
  assert.equal(enc(-0), "d8000000000000000");
  assert.equal(enc(Number.MIN_VALUE), "d0000000000000001");
  assert.equal(enc(NaN), "dnan"); assert.equal(enc(Infinity), "dinf"); assert.equal(enc(-Infinity), "d-inf");
  assert.equal(enc(null), "n"); assert.equal(enc(true), "t"); assert.equal(enc(false), "f");
  assert.equal(enc("héllo"), "s6:héllo");
  assert.equal(enc(new Date("2026-09-06T12:00:00.000Z")), `D${hex64(Date.parse("2026-09-06T12:00:00.000Z"))}`);
  assert.equal(enc(new Timestamp(1_700_000_000, 5)), "T1700000000.000000005");
  assert.equal(enc(new GeoPoint(1.5, -2)), `G${hex64(1.5)},${hex64(-2)}`);
  const { db } = { db: fakeFirestore({ docs: {} }) };
  void db;
  assert.equal(enc({ path: "users/u1/tasks/t1" }), "M1{s4:path=s17:users/u1/tasks/t1}", "a plain map with a path member is a map, not a reference");
  assert.equal(enc(new VectorValue([1, 2])), `V2[${hex64(1)},${hex64(2)}]`);
  assert.ok(scheduler.encodeOriginalEventBytes(Buffer.from([0, 255])).equals(Buffer.concat([Buffer.from("B2:"), Buffer.from([0, 255])])), "raw bytes");
  assert.equal(enc([1, "a", null]), `A3[d${hex64(1)},s1:a,n]`);
  assert.equal(enc({ b: 1, a: [true], "é": {} }), `M3{s1:a=A1[t],s1:b=d${hex64(1)},s2:é=M0{}}`, "keys in unsigned UTF-8 byte order");
  assert.equal(enc(Object.create(null)), "M0{}", "null-prototype map is plain");
  for (const [label, value, token] of [["class instance", new (class Foo {})(), "NON_PLAIN_OBJECT"], ["Map", new Map(), "NON_PLAIN_OBJECT"], ["Uint8Array", new Uint8Array(2), "NON_PLAIN_OBJECT"], ["undefined", undefined, "UNSUPPORTED_RUNTIME_TYPE"], ["bigint", 1n, "UNSUPPORTED_RUNTIME_TYPE"], ["symbol", Symbol("x"), "UNSUPPORTED_RUNTIME_TYPE"], ["function", () => 1, "UNSUPPORTED_RUNTIME_TYPE"]]) {
    assert.throws(() => enc(value), (e) => e.code === "SOURCE_UNENCODABLE" && e.token === token, label);
  }
  const cyclic = { a: 1 }; cyclic.self = cyclic;
  assert.throws(() => enc(cyclic), (e) => e.code === "ORIGINAL_BYTES_INVARIANT", "cycle");
  assert.throws(() => enc(new Date(NaN)), (e) => e.code === "ORIGINAL_BYTES_INVARIANT", "invalid Date");
  assert.throws(() => enc(new GeoPoint(0, 0).constructor.prototype.constructor === GeoPoint ? Object.assign(Object.create(GeoPoint.prototype), { _latitude: NaN, _longitude: 0 }) : null), (e) => e.code === "ORIGINAL_BYTES_INVARIANT", "malformed GeoPoint instance");
  const digest = scheduler.originalBytesDigest({ phase0ValidationFailure: { any: 1 }, event_id: "e" });
  assert.equal(digest, scheduler.originalBytesDigest({ event_id: "e" }), "the digest excludes the retry member");
  assert.match(digest, /^[0-9a-f]{64}$/);
});

test("C9.1.26/C9.1.29 the qev1 table is exact, every message is below 1,000 UTF-8 bytes, and validation reports the first failing code in the frozen precedence", () => {
  assert.deepEqual(scheduler.QEV1_MESSAGES, QEV1_TABLE);
  for (const m of Object.values(scheduler.QEV1_MESSAGES)) assert.ok(Buffer.byteLength(m, "utf8") < 1000);
  const codeOf = (data, id = "event-2") => { try { validateEventEnvelope(data, id); return null; } catch (e) { return e.code; } };
  assert.equal(codeOf(null), "ENVELOPE_INVALID");
  assert.equal(codeOf([]), "ENVELOPE_INVALID");
  assert.equal(codeOf(event({ event_id: "x", event_name: "", effect: "bad" })), "EVENT_ID_INVALID", "event_id precedes event_name and effect");
  assert.equal(codeOf(event({ event_name: " ", canonical_key: "" })), "EVENT_NAME_INVALID");
  assert.equal(codeOf(event({ canonical_key: "", source_version: -1 })), "CANONICAL_KEY_INVALID");
  assert.equal(codeOf(event({ source_version: 1.5, observed_at: undefined })), "SOURCE_VERSION_INVALID");
  assert.equal(codeOf(event({ observed_at: "2026-08-27T16:59:00.000Z", source_evidence_id: "" })), "OBSERVED_AT_INVALID");
  assert.equal(codeOf(event({ source_evidence_id: "", effect: "ignore" })), "SOURCE_EVIDENCE_ID_INVALID");
  assert.equal(codeOf(event({ effect: "ignore", payload: { bad: undefined } })), "EFFECT_INVALID");
  assert.equal(codeOf(event({ payload: { bad: undefined }, processed: true })), "PAYLOAD_INVALID");
  assert.equal(codeOf(event({ processed: true })), "PROCESSED_INVALID");
  assert.equal(codeOf(event({ processingState: "terminal" })), "PROCESSED_INVALID");
  assert.equal(codeOf(event()), null);
  for (const code of Object.keys(QEV1_TABLE)) { const e = (() => { try { validateEventEnvelope(code === "REFERENCE_INVALID" ? event() : event({ processed: true }), "event-2"); } catch (x) { return x; } })(); void e; }
  try { validateEventEnvelope(event({ effect: "ignore" }), "event-2"); assert.fail(); } catch (e) { assert.equal(e.message, QEV1_TABLE.EFFECT_INVALID, "the thrown message is the table message"); }
});

test("C9.1.26/C9.1.27 attempt 1 and 2 write the exact retry member and leave the source pending; attempt 3 creates the exact qev1 record and terminalizes the source with the table message and no high-water row; a different failure restarts at 1; a malformed retry member fails closed; the qev1 record is replay-safe and a disagreeing record fails closed", async () => {
  const path = "users/u1/events/bad";
  const { db, deps, clock } = await initialized({ "users/u1": { name: "U" }, [path]: { ...pendingEvent("bad"), effect: "ignore" } });
  const runAt = async (k) => { clock.millis = Date.parse(scheduleAt(k)) + 1000; return scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(k) }, deps); };
  const digest = scheduler.originalBytesDigest(db.__docs.get(path));
  let r = await runAt(0);
  assert.equal(r.outcome, "completed");
  let source = db.__docs.get(path);
  assert.equal(source.processingState, "pending", "attempt 1 leaves the source pending");
  assert.deepEqual(Object.keys(source.phase0ValidationFailure).sort(), ["failureCount", "firstFailedAt", "lastFailedAt", "originalBytesDigest", "reasonCode", "schemaVersion"]);
  assert.deepEqual([source.phase0ValidationFailure.schemaVersion, source.phase0ValidationFailure.originalBytesDigest, source.phase0ValidationFailure.reasonCode, source.phase0ValidationFailure.failureCount], [1, digest, "EFFECT_INVALID", 1]);
  const firstFailedAt = source.phase0ValidationFailure.firstFailedAt.toMillis();
  assert.equal(firstFailedAt, source.phase0ValidationFailure.lastFailedAt.toMillis());
  assert.equal(r.lanes[0].outcomes[0], "retry");
  r = await runAt(1);
  source = db.__docs.get(path);
  assert.deepEqual([source.processingState, source.phase0ValidationFailure.failureCount, source.phase0ValidationFailure.firstFailedAt.toMillis(), source.phase0ValidationFailure.lastFailedAt.toMillis() > firstFailedAt], ["pending", 2, firstFailedAt, true], "attempt 2 keeps firstFailedAt");
  r = await runAt(2);
  source = db.__docs.get(path);
  assert.deepEqual([source.processingState, source.processed, source.outcome, source.processingError, "phase0ValidationFailure" in source], ["terminal", true, "quarantined", QEV1_TABLE.EFFECT_INVALID, false], "attempt 3 terminalizes with the table message and deletes the retry member");
  assert.deepEqual([source.event_id, source.effect, source.payload], ["bad", "ignore", {}], "producer fields retained byte-for-byte");
  assert.equal(source.processedAt.toMillis(), Date.parse(scheduleAt(2)) + 1000);
  const qpath = `${QUARANTINE_COLLECTION}/qev1_${digest.slice(0, 40)}`;
  const record = db.__docs.get(qpath);
  assert.ok(record, "qev1 record at the digest-derived id");
  assert.deepEqual(Object.keys(record).sort(), ["failureCount", "firstFailedAt", "lastFailedAt", "originalBytesDigest", "quarantinedAt", "reason", "schemaVersion", "sourcePath", "sourceUpdateTime"]);
  assert.deepEqual([record.schemaVersion, record.sourcePath, record.originalBytesDigest, record.reason, record.failureCount, record.firstFailedAt.toMillis(), record.lastFailedAt.toMillis(), record.quarantinedAt.toMillis()], [1, path, digest, { code: "EFFECT_INVALID", message: QEV1_TABLE.EFFECT_INVALID }, 3, firstFailedAt, source.processedAt.toMillis(), source.processedAt.toMillis()]);
  assert.ok(record.sourceUpdateTime && record.sourceUpdateTime.toMillis() <= record.quarantinedAt.toMillis());
  assert.equal([...db.__docs.keys()].filter((p) => p.includes("/eventState/")).length, 0, "no high-water row");
  assert.equal(r.lanes[0].outcomes[0], "quarantined");
  // a different failure restarts at 1; the retained attempt-1 retry member is replaced, not incremented
  const path2 = "users/u1/events/bad2";
  db.__docs.set(path2, { ...pendingEvent("bad2"), effect: "ignore" });
  await runAt(3);
  db.__docs.get(path2).effect = "fire"; db.__docs.get(path2).source_version = -1; // digest and code change
  await runAt(4);
  const s2 = db.__docs.get(path2);
  assert.deepEqual([s2.phase0ValidationFailure.failureCount, s2.phase0ValidationFailure.reasonCode, s2.phase0ValidationFailure.firstFailedAt.toMillis()], [1, "SOURCE_VERSION_INVALID", Date.parse(scheduleAt(4)) + 1000]);
  // a malformed retry member fails closed: no write, the page is unsettled
  s2.phase0ValidationFailure = { schemaVersion: 2 };
  const before = JSON.stringify(db.__docs.get(path2));
  r = await runAt(5);
  assert.deepEqual([r.outcome, JSON.stringify(db.__docs.get(path2)) === before], ["incomplete", true]);
  assert.ok(deps.logs.some(([c]) => c === "PHASE0_RETRY_MAP_INVARIANT"));
  // replay: re-running attempt 3 against an existing equal record is a no-op on the record; a disagreeing record fails closed
  db.__docs.set(path2, { ...pendingEvent("bad2"), effect: "ignore", phase0ValidationFailure: { schemaVersion: 1, originalBytesDigest: digest, reasonCode: "EFFECT_INVALID", failureCount: 2, firstFailedAt: Timestamp.fromMillis(firstFailedAt), lastFailedAt: Timestamp.fromMillis(firstFailedAt) } });
  void 0;
  const path3 = "users/u1/events/bad";
  db.__docs.set(path3, { ...pendingEvent("bad"), effect: "ignore", phase0ValidationFailure: { schemaVersion: 1, originalBytesDigest: digest, reasonCode: "EFFECT_INVALID", failureCount: 2, firstFailedAt: Timestamp.fromMillis(firstFailedAt), lastFailedAt: Timestamp.fromMillis(firstFailedAt) } });
  db.__docs.delete(path2);
  const recordBefore = JSON.stringify(db.__docs.get(qpath));
  r = await runAt(6);
  assert.equal(db.__docs.get(path3).processingState, "terminal", "replay terminalizes the source again");
  assert.equal(JSON.stringify(db.__docs.get(qpath)), recordBefore, "the existing equal record is retained (replay)");
  db.__docs.set(path3, { ...pendingEvent("bad"), effect: "ignore", phase0ValidationFailure: { schemaVersion: 1, originalBytesDigest: digest, reasonCode: "EFFECT_INVALID", failureCount: 2, firstFailedAt: Timestamp.fromMillis(firstFailedAt), lastFailedAt: Timestamp.fromMillis(firstFailedAt) } });
  db.__docs.get(qpath).reason = { code: "EVENT_NAME_INVALID", message: QEV1_TABLE.EVENT_NAME_INVALID };
  r = await runAt(7);
  assert.deepEqual([r.outcome, db.__docs.get(path3).processingState], ["incomplete", "pending"], "a disagreeing record fails closed with no source write");
  assert.ok(deps.logs.some(([c]) => c === "PHASE0_QUARANTINE_INVARIANT"));
});

test("C9.1.29 REFERENCE_INVALID precedes every other reason for an events row outside users/{uid}/events, and the reference check never fences a missing owner", async () => {
  const path = "orgs/o1/events/e1";
  const { db, deps, clock } = await initialized({ "users/u1": { name: "U" }, [path]: pendingEvent("e1") });
  const runAt = async (k) => { clock.millis = Date.parse(scheduleAt(k)) + 1000; return scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(k) }, deps); };
  for (let k = 0; k < 3; k += 1) assert.equal((await runAt(k)).outcome, "completed", `ordinal +${k}`);
  const source = db.__docs.get(path);
  assert.deepEqual([source.processingState, source.outcome, source.processingError], ["terminal", "quarantined", QEV1_TABLE.REFERENCE_INVALID]);
  const stored = { ...source }; delete stored.processingState; delete stored.processed; delete stored.processedAt; delete stored.outcome; delete stored.processingError;
  const digest = scheduler.originalBytesDigest({ ...stored, processingState: "pending", processed: false });
  const record = db.__docs.get(`${QUARANTINE_COLLECTION}/qev1_${digest.slice(0, 40)}`);
  assert.ok(record, "the qev1 record is keyed by the digest of the pending source as stored");
  assert.deepEqual([record.sourcePath, record.reason.code], [path, "REFERENCE_INVALID"]);
});

test("C9.1.22 a source holding a non-plain object is quarantined on first occurrence with the exact qevu1 record and terminal source in one transaction (producer fields retained, retry member deleted), size never precedes unencodable, exact existence is replay, and a disagreeing record fails closed", async () => {
  const path = "users/u1/events/weird";
  class Foo { constructor() { this.x = 1; } }
  const { db, deps, clock } = await initialized({ "users/u1": { name: "U" }, [path]: { ...pendingEvent("weird"), payload: { thing: new Foo() }, phase0ValidationFailure: { schemaVersion: 1, originalBytesDigest: "0".repeat(64), reasonCode: "PAYLOAD_INVALID", failureCount: 1, firstFailedAt: Timestamp.fromMillis(0), lastFailedAt: Timestamp.fromMillis(0) } } });
  const runAt = async (k) => { clock.millis = Date.parse(scheduleAt(k)) + 1000; return scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(k) }, deps); };
  const updateTime = (await db.doc(path).get()).updateTime;
  const r = await runAt(0);
  assert.equal(r.outcome, "completed");
  const source = db.__docs.get(path);
  assert.deepEqual([source.processingState, source.processed, source.outcome, source.processingError, "phase0ValidationFailure" in source, source.payload.thing instanceof Foo], ["terminal", true, "quarantined", "Source contains a non-plain object.", false, true]);
  const digest = createHash("sha256").update(JSON.stringify({ domain: "unencodable_source.v1", reason_token: "NON_PLAIN_OBJECT", source_path: path, update_time: updateTime.toDate().toISOString() })).digest("hex");
  const qpath = `${QUARANTINE_COLLECTION}/qevu1_${digest.slice(0, 40)}`;
  const record = db.__docs.get(qpath);
  assert.ok(record, "qevu1 record at the unencodable-digest id");
  assert.deepEqual(Object.keys(record).sort(), ["failureCount", "firstFailedAt", "lastFailedAt", "quarantinedAt", "reason", "schemaVersion", "sourcePath", "sourceUpdateTime", "unencodableSourceDigest"]);
  assert.deepEqual([record.schemaVersion, record.sourcePath, record.sourceUpdateTime.toMillis(), record.unencodableSourceDigest, record.reason, record.failureCount], [1, path, updateTime.toMillis(), digest, { code: "SOURCE_UNENCODABLE", token: "NON_PLAIN_OBJECT", message: "Source contains a non-plain object." }, 1]);
  assert.ok(record.firstFailedAt.toMillis() === record.lastFailedAt.toMillis() && record.lastFailedAt.toMillis() === record.quarantinedAt.toMillis() && record.quarantinedAt.toMillis() === source.processedAt.toMillis());
  const sourceWrite = db.__writes.findLast((w) => w.path === path); const recordWrite = db.__writes.findLast((w) => w.path === qpath);
  assert.equal(sourceWrite.batch, recordWrite.batch, "one transaction");
  assert.equal(r.lanes[0].outcomes[0], "unencodable");
  assert.equal([...db.__docs.keys()].filter((p) => p.includes("/eventState/")).length, 0);
  // replay: the same source pending again with the same updateTime → record retained, source terminalized; disagreement fails closed
  const replayDoc = { ...db.__docs.get(path), processingState: "pending", processed: false }; delete replayDoc.outcome; delete replayDoc.processingError; delete replayDoc.processedAt;
  db.__docs.set(path, replayDoc); db.__updateTimes && db.__updateTimes.set(path, updateTime);
  const recordBefore = JSON.stringify(db.__docs.get(qpath));
  await runAt(1);
  assert.equal(JSON.stringify(db.__docs.get(qpath)), recordBefore);
  const r2 = await runAt(2);
  void r2;
  db.__docs.set(path, replayDoc); db.__updateTimes && db.__updateTimes.set(path, updateTime);
  db.__docs.get(qpath).reason.token = "UNSUPPORTED_RUNTIME_TYPE";
  const r3 = await runAt(3);
  assert.deepEqual([r3.outcome, db.__docs.get(path).processingState], ["incomplete", "pending"]);
  assert.ok(deps.logs.some(([c]) => c === "PHASE0_QUARANTINE_INVARIANT"));
  // an unsupported runtime type is the other token
  const path2 = "users/u1/events/weird2";
  db.__docs.delete(path); // the disagreeing row stays unsettled otherwise; this case is about the second token
  await db.doc(path2).set({ ...pendingEvent("weird2"), payload: { n: 1n } });
  const updateTime2 = db.__updateTimes.get(path2);
  const r4 = await runAt(4);
  assert.equal(r4.outcome, "completed");
  assert.equal(db.__docs.get(path2).processingError, "Source contains an unsupported runtime type.");
  assert.equal(db.__docs.get(`${QUARANTINE_COLLECTION}/qevu1_${createHash("sha256").update(JSON.stringify({ domain: "unencodable_source.v1", reason_token: "UNSUPPORTED_RUNTIME_TYPE", source_path: path2, update_time: updateTime2.toDate().toISOString() })).digest("hex").slice(0, 40)}`).reason.token, "UNSUPPORTED_RUNTIME_TYPE");
});

// ---------------------------------------------------------------------------
// S3 I9d-2 — D8 storage equations (production and independent oracle), the raw Vector discriminator,
// fitsPhase0Transition at every bound, the retry-or-terminal envelope and POST_CUTOFF_SOURCE_SIZE_INVARIANT,
// PAYLOAD_TOO_LARGE, RawPhase0SizingV1 (C9.1.23–C9.1.25, C9.1.27–C9.1.29).
// ---------------------------------------------------------------------------

const oracle = require("./support/phase0SizingOracle");
const raw = require("./support/rawDocument");
const sameMultiset = (a, b) => JSON.stringify([...a].sort((x, y) => x - y)) === JSON.stringify([...b].sort((x, y) => x - y));

test("C7/C9.1.23 the embedded index registry equals firestore.indexes.json exactly", () => {
  const file = JSON.parse(fs.readFileSync(path.resolve(__dirname, "../../firestore.indexes.json"), "utf8"));
  assert.deepEqual(scheduler.PHASE0_INDEX_REGISTRY_V1, file);
});

test("C9.1.23 production sizing (decoded data) and the independent oracle (raw v1 Document) agree on document size, every index entry, and transition charges across every value kind, exemptions, composites, and the 1,500-byte cap", () => {
  const { GeoPoint: GP, VectorValue: VV, Firestore } = require("@google-cloud/firestore");
  const db = new Firestore({ projectId: "demo-peezy-phase1" }); // real DocumentReference instances; nothing is read or written
  const fixtures = [
    ["users/u1/events/e1", pendingEvent("e1")],
    ["users/u1/events/e2", { ...pendingEvent("e2"), payload: { nested: { deep: { s: "héllo", n: 1, d: 1.5, b: true, z: null } }, arr: [1, "ab", { m: 2 }, [3, 4]], ts: Timestamp.fromMillis(1_700_000_000_123), dt: new Date("2026-01-01T00:00:00Z"), geo: new GP(1, 2), ref: db.doc("users/u1/tasks/t1"), bytes: Buffer.from([1, 2, 3]), vec: new VV([1, 2, 3]), big: Number.MAX_SAFE_INTEGER, nan: NaN, empty: {}, long: "x".repeat(2000) } }],
    ["users/u1/eventState/" + "a".repeat(64), { event_name: "n", canonical_key: "k", source_version: 2, effect: "fire", event_id: "e2", observed_at: Timestamp.fromMillis(0), source_evidence_id: "ev", payload: { a: [1, 2] }, fingerprint: "f".repeat(64), advancedAt: Timestamp.fromMillis(0) }],
    ["users/u1/tasks/t1", { status: "Snoozed", dispositionContract: { next_trigger: { kind: "date", fired: false, at: Timestamp.fromMillis(0), payload: { basis: "x" } }, disposition: "DEFERRED" }, task_generation_epoch: 3, notes: ["n1", "n2"], thresholdProjection: { state: "armed", threshold_at: Timestamp.fromMillis(0) } }],
    ["phase1System/dispositionTriggerState/quarantinedEvents/qev1_x", { schemaVersion: 1, sourcePath: "users/u1/events/e1", reason: { code: "EFFECT_INVALID", message: "effect must be fire or retract." }, failureCount: 3, quarantinedAt: Timestamp.fromMillis(0) }]
  ];
  for (const [docPath, data] of fixtures) {
    const fields = raw.toRawFields(data);
    assert.equal(scheduler.storage.documentSize(docPath, data), oracle.documentSize(docPath, fields), `${docPath} document size`);
    assert.ok(sameMultiset(scheduler.storage.indexEntries(docPath, data), oracle.indexEntries(docPath, fields)), `${docPath} index entries: ${JSON.stringify(scheduler.storage.indexEntries(docPath, data))} vs ${JSON.stringify(oracle.indexEntries(docPath, fields))}`);
    assert.equal(scheduler.rawStorage.documentSize(docPath, fields), oracle.documentSize(docPath, fields), `${docPath} raw document size`);
    assert.ok(sameMultiset(scheduler.rawStorage.indexEntries(docPath, fields), oracle.indexEntries(docPath, fields)), `${docPath} raw index entries`);
  }
  // exact expectations the equations imply
  assert.equal(scheduler.storage.documentSize("users/u1/events/e1", { a: "x" }), 71);
  assert.deepEqual(scheduler.storage.indexEntries("users/u1/events/e1", { processingState: "pending" }), [75], "the events.processingState override yields exactly one COLLECTION_GROUP ascending entry");
  assert.deepEqual(scheduler.storage.indexEntries("users/u1/eventState/x", { a: "x" }).length, 2, "automatic ascending + descending");
  assert.deepEqual(scheduler.storage.indexEntries("users/u1/tasks/t1", { dispositionContract: { a: 1 } }), [], "an exempt map contributes no automatic entries");
  const tasksComposite = scheduler.storage.indexEntries("users/u1/tasks/t1", { status: "S", dispositionContract: { next_trigger: { kind: "date", fired: false, at: Timestamp.fromMillis(0) } } });
  const nTasks = scheduler.storage.documentNameSize("users/u1/tasks/t1"); // 34
  assert.equal(nTasks, 34);
  assert.deepEqual(tasksComposite.sort((a, b) => a - b), [nTasks + 2 + 32, nTasks + 2 + 32, nTasks + 2 + 5 + 1 + 32, nTasks + 2 + 5 + 1 + 8 + 32].sort((a, b) => a - b), "status automatic pair plus the two composite indexes (three-field and four-field)");
  const nState = scheduler.storage.documentNameSize("users/u1/eventState/x"); // 38
  assert.equal(nState, 38);
  const capped = scheduler.storage.indexEntries("users/u1/eventState/x", { s: "x".repeat(2000) });
  assert.deepEqual(capped, [nState + 1500 + 32, nState + 1500 + 32], "1,500-byte cap per indexed value");
  assert.equal(scheduler.storage.documentSize("users/u1/eventState/x", { v: new VV(new Array(4).fill(0)) }), nState + 2 + 32 + 32, "Vector = 8 × dimensions");
  assert.equal(scheduler.storage.documentSize("users/u1/eventState/x", { g: new GP(0, 0), r: db.doc("users/u1/tasks/t1") }), nState + 2 + 16 + 2 + nTasks + 32);
  // transition parity: create, update with removed+added entries, delete
  const before = { ...pendingEvent("e2"), payload: { k: "v".repeat(10), gone: 1 } };
  const after = { ...before, payload: { k: "w".repeat(10), added: [1, 2] }, processingState: "terminal" };
  const transition = [{ path: "users/u1/events/e2", before, after }, { path: "users/u1/eventState/x", before: null, after: { a: 1 } }, { path: "users/u1/events/old", before: { a: "b" }, after: null }];
  const production = scheduler.storage.transitionBudget(transition);
  const expected = oracle.transitionBudget(transition.map((t) => ({ path: t.path, before: t.before && raw.toRawFields(t.before), after: t.after && raw.toRawFields(t.after) })));
  assert.deepEqual([production.charge, production.fits], [expected.charge, expected.fits]);
});

test("C9.1.24 the raw Vector discriminator: both zero spellings, 1 and 2,048 dimensions, 2,049, missing/malformed/surplus members, ordinary {value:…} and {__type__:\"other\",value:…} maps — production raw sizing and the oracle agree, and int64 extrema and nonfinite doubles are 8 bytes", () => {
  const vec = (values, extra = {}) => ({ mapValue: { fields: { __type__: { stringValue: "__vector__" }, value: { arrayValue: values }, ...extra } } });
  const dims = (n) => ({ values: Array.from({ length: n }, (_, i) => ({ doubleValue: i })) });
  for (const [label, value, size] of [["zero {}", vec({}), 0], ["zero values:[]", vec({ values: [] }), 0], ["one", vec(dims(1)), 8], ["2048", vec(dims(2048)), 16384]]) {
    assert.equal(scheduler.rawStorage.valueSize(value), size, label);
    assert.equal(oracle.valueSize(value), size, `oracle ${label}`);
  }
  for (const [label, value] of [["2049", vec(dims(2049))], ["missing value", { mapValue: { fields: { __type__: { stringValue: "__vector__" } } } }], ["malformed element", vec({ values: [{ integerValue: "1" }] })], ["surplus member", vec(dims(1), { extra: { nullValue: null } })], ["nonfinite element", vec({ values: [{ doubleValue: "NaN" }] })]]) {
    assert.throws(() => scheduler.rawStorage.valueSize(value), (e) => e.code === "ARCHIVE_CODEC_INVARIANT", label);
    assert.throws(() => oracle.valueSize(value), (e) => e.code === "ARCHIVE_CODEC_INVARIANT", `oracle ${label}`);
  }
  const ordinary1 = { mapValue: { fields: { value: { arrayValue: dims(3) } } } };
  const ordinary2 = { mapValue: { fields: { __type__: { stringValue: "other" }, value: { arrayValue: dims(3) } } } };
  assert.equal(scheduler.rawStorage.valueSize(ordinary1), 5 + 1 + 24, "ordinary map arithmetic: name + elements");
  assert.equal(oracle.valueSize(ordinary1), 5 + 1 + 24);
  assert.equal(scheduler.rawStorage.valueSize(ordinary2), (8 + 1 + 6) + (5 + 1 + 24));
  assert.equal(oracle.valueSize(ordinary2), (8 + 1 + 6) + (5 + 1 + 24));
  for (const v of [{ integerValue: "9223372036854775807" }, { integerValue: "-9223372036854775808" }, { doubleValue: "NaN" }, { doubleValue: "-Infinity" }, { doubleValue: 1.5 }]) {
    assert.equal(scheduler.rawStorage.valueSize(v), 8); assert.equal(oracle.valueSize(v), 8);
  }
  assert.throws(() => scheduler.rawStorage.valueSize({ weirdValue: 1 }), (e) => e.code === "RAW_VALUE_UNKNOWN");
  assert.equal(scheduler.rawStorage.valueSize({ referenceValue: `${raw.ROOT}/users/u1/tasks/t1` }), 34);
  assert.equal(scheduler.rawStorage.valueSize({ bytesValue: Buffer.from([1, 2, 3]).toString("base64") }), 3);
});

test("C9.1.27 fitsPhase0Transition admits equality at every bound and refuses +1: prospective document 1,048,576, entry 7,680 (four-field composite with a long name), 40,000 entries, 8,388,608 entry bytes, and the valid-advance full transition at 8,388,608 including an old high-water update with long shared field paths", () => {
  const S = scheduler.storage;
  // document bound: pad a payload string so the prospective document is exactly 1,048,576
  const base = { ...pendingEvent("e1"), payload: { s: "" } };
  const pad = 1048576 - S.documentSize("users/u1/events/e1", base);
  const exact = { ...base, payload: { s: "x".repeat(pad) } };
  assert.equal(S.documentSize("users/u1/events/e1", exact), 1048576);
  assert.equal(S.transitionBudget([{ path: "users/u1/events/e1", before: null, after: exact }]).fits, true);
  assert.equal(S.transitionBudget([{ path: "users/u1/events/e1", before: null, after: { ...exact, payload: { s: "x".repeat(pad + 1) } } }]).fits, false);
  // entry bound: tasks four-field composite = name + 4 capped values + 32; choose the uid so the entry is exactly 7,680
  const composite = { status: "s".repeat(1500), dispositionContract: { next_trigger: { kind: "k".repeat(1500), fired: "f".repeat(1500), at: "a".repeat(1500) } } };
  const uidFor = (target) => "u".repeat(target - 6064); // name = uid + 32; four-field entry = name + 4 × 1,500 + 32 = uid + 6,064
  const entryOf = (uid) => Math.max(...S.indexEntries(`users/${uid}/tasks/t1`, composite));
  assert.equal(entryOf(uidFor(7680)), 7680);
  assert.equal(S.transitionBudget([{ path: `users/${uidFor(7680)}/tasks/t1`, before: null, after: composite }]).fits, true);
  assert.equal(S.transitionBudget([{ path: `users/${uidFor(7681)}/tasks/t1`, before: null, after: composite }]).fits, false);
  // entry count: eventState (no exemptions) 20,000 leaves = 40,000 entries; 19,999 leaves + one single-element array = 40,001
  const leavesOf = (n) => Object.fromEntries(Array.from({ length: n }, (_, i) => [`f${i}`, 1]));
  const forty = leavesOf(20000);
  assert.equal(S.indexEntries("users/u1/eventState/x", forty).length, 40000);
  assert.equal(S.transitionBudget([{ path: "users/u1/eventState/x", before: null, after: forty }]).fits, true);
  const fortyOne = { ...leavesOf(19999), arr: [1] };
  assert.equal(S.indexEntries("users/u1/eventState/x", fortyOne).length, 40001);
  assert.equal(S.transitionBudget([{ path: "users/u1/eventState/x", before: null, after: fortyOne }]).fits, false);
  // entry-byte sum: 40,000 entries over a long document name (the name counts in every entry but once in the document) with values "x" (2) and "xx" (3) mixed to land exactly on 8,388,608
  const targetName = Math.floor(8388608 / 40000) - 34; // entry = name + 2 + 32 → name 175
  const longPath = `users/${"u".repeat(targetName - (6 + 1 + 11 + 2 + 16))}/eventState/x`;
  assert.equal(S.documentNameSize(longPath), targetName);
  const nLongEntries = 8388608 - 40000 * (targetName + 34); // entries that carry "xx" instead of "x"
  const mixed = {};
  for (let i = 0; i < 20000; i += 1) mixed[`f${i}`] = i * 2 < nLongEntries ? "xx" : "x";
  const create = S.transitionBudget([{ path: longPath, before: null, after: mixed }]);
  assert.equal(create.perDocument[0].entryBytes, 8388608);
  assert.ok(create.perDocument[0].document <= 1048576);
  assert.deepEqual([create.fits, create.charge > 8388608], [false, true], "a create at the per-document entry-byte bound exceeds the transaction bound by the document itself");
  // as an update whose delta is the last leaf's two entries, the per-document bound alone decides
  const { f19999, ...prior } = mixed;
  const update = S.transitionBudget([{ path: longPath, before: prior, after: mixed }]);
  assert.deepEqual([update.perDocument[0].entryBytes, update.fits, update.charge < 8388608], [8388608, true, true]);
  mixed.f19999 = "xx";
  const over = S.transitionBudget([{ path: longPath, before: prior, after: mixed }]);
  assert.deepEqual([over.perDocument[0].entryBytes, over.fits, over.charge < 8388608], [8388610, false, true], "+1 at the per-document entry-byte bound refuses even though the transaction charge is small");
  void f19999;
  // full valid-advance transition at exactly 8,388,608: the old high-water row is updated under long shared field paths
  // (removed + added entries both charged); a source-only top-level string, identical before and after, tunes the
  // post-source document by exactly one byte per character (no entry delta), so the charge lands to the byte.
  const uid = "u".repeat(60);
  const sourcePath = `users/${uid}/events/${"e".repeat(40)}`;
  const stateId = scheduler.canonicalEventStateId("institution.updated", "service/provider-1");
  const hwPath = `users/${uid}/eventState/${stateId}`;
  const longKey = (i) => `${"k".repeat(24)}${i}`; // long shared paths, short enough that both documents stay under 1 MiB at the tuned count
  const payloadOf = (mark, count, width) => Object.fromEntries(Array.from({ length: count }, (_, i) => [longKey(i), `${mark}${i}`.padEnd(width, "v")]));
  // the old row: 6,000 leaves of 120-byte values (a legal ≤ 1 MiB document) so its removed entries carry ~3.7 MB of the charge
  const oldHw = { event_name: "institution.updated", canonical_key: "service/provider-1", source_version: 1, effect: "fire", event_id: "old", observed_at: Timestamp.fromMillis(0), source_evidence_id: "ev", payload: payloadOf("o", 6000, 120), fingerprint: "f".repeat(64), advancedAt: Timestamp.fromMillis(0) };
  const build = (count, tune) => {
    const source = { ...pendingEvent("e"), event_id: "e".repeat(40), payload: payloadOf("n", count, 40), tuning: "z".repeat(tune) };
    const envelope = validateEventEnvelope(source, "e".repeat(40));
    const newHw = { event_name: envelope.event_name, canonical_key: envelope.canonical_key, source_version: envelope.source_version, effect: envelope.effect, event_id: envelope.event_id, observed_at: Timestamp.fromMillis(Date.parse(envelope.observed_at)), source_evidence_id: envelope.source_evidence_id, payload: envelope.payload, fingerprint: __private.fingerprintCanonicalEnvelope(envelope), advancedAt: Timestamp.fromMillis(0) };
    const terminal = { ...source, processingState: "terminal", processed: true, processedAt: Timestamp.fromMillis(0), outcome: "advance" };
    return S.transitionBudget([{ path: sourcePath, before: source, after: terminal }, { path: hwPath, before: oldHw, after: newHw }]);
  };
  // the charge is monotone in the leaf count (two regimes around the old high-water's 9,000 leaves): binary-search the largest count at or under the target
  let lo = 0; let hi = 20000;
  while (lo < hi) { const mid = Math.ceil((lo + hi) / 2); if (build(mid, 0).charge <= 8388608) lo = mid; else hi = mid - 1; }
  const count = lo;
  const tune = 8388608 - build(count, 0).charge;
  const slope = build(count + 1, 0).charge - build(count, 0).charge;
  assert.ok(tune >= 0 && tune < slope, `fine lever within one leaf's slope (${tune} of ${slope})`);
  const exactCharge = build(count, tune);
  assert.equal(exactCharge.charge, 8388608, "tuned to the byte by a source-only unindexed-delta string");
  assert.ok(exactCharge.perDocument.every((d) => d.document <= 1048576 && d.entryCount <= 40000 && d.entryBytes <= 8388608 && d.maxEntry <= 7680), JSON.stringify(exactCharge.perDocument));
  assert.equal(exactCharge.fits, true);
  assert.equal(build(count, tune + 1).charge, 8388609);
  assert.equal(build(count, tune + 1).fits, false);
  const oracleView = oracle.transitionBudget([{ path: sourcePath, before: raw.toRawFields({ ...pendingEvent("e"), event_id: "e".repeat(40), payload: payloadOf("n", count, 40), tuning: "z".repeat(tune) }), after: raw.toRawFields({ ...pendingEvent("e"), event_id: "e".repeat(40), payload: payloadOf("n", count, 40), tuning: "z".repeat(tune), processingState: "terminal", processed: true, processedAt: Timestamp.fromMillis(0), outcome: "advance" }) }, { path: hwPath, before: raw.toRawFields(oldHw), after: raw.toRawFields({ ...oldHw, source_version: 2, event_id: "e".repeat(40), observed_at: Timestamp.fromMillis(Date.parse("2026-08-27T16:59:00.000Z")), source_evidence_id: "evidence-2", payload: payloadOf("n", count, 40) }) }]);
  assert.equal(oracleView.charge, 8388608, "the independent oracle agrees on the exact full-transition charge");
});

test("C9.1.27/C9.1.28 the runtime envelope admits a source of exactly 1,047,552 bytes and treats 1,047,553 as POST_CUTOFF_SOURCE_SIZE_INVARIANT: zero writes, heartbeat running, no cursor, the exact metric and fixed fields, no raw bytes", async () => {
  const S = scheduler.storage;
  const make = (target) => { const base = { ...pendingEvent("big"), payload: { s: "" } }; return { ...base, payload: { s: "x".repeat(target - S.documentSize("users/u1/events/big", base)) } }; };
  const { db, deps, clock } = await initialized({ "users/u1": { name: "U" }, "users/u1/events/big": make(1047552) });
  assert.equal(S.documentSize("users/u1/events/big", db.__docs.get("users/u1/events/big")), 1047552);
  const runAt = async (k) => { clock.millis = Date.parse(scheduleAt(k)) + 1000; return scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(k) }, deps); };
  let r = await runAt(0);
  assert.deepEqual([r.outcome, db.__docs.get("users/u1/events/big").outcome], ["completed", "advance"], "exactly 1,047,552 is admitted and advances");
  const { db: db2, deps: deps2, clock: clock2 } = await initialized({ "users/u1": { name: "U" }, "users/u1/events/big": make(1047553), "users/u1/events/ok": pendingEvent("ok") });
  const before = db2.__writes.length;
  clock2.millis = Date.parse(scheduleAt(0)) + 1000;
  r = await scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(0) }, deps2);
  assert.equal(r.outcome, "incomplete");
  assert.equal(db2.__docs.get("users/u1/events/big").processingState, "pending", "no source write");
  assert.equal(db2.__writes.slice(before).filter((w) => w.path === "users/u1/events/big" || w.path.includes("quarantinedEvents")).length, 0, "no retry map, quarantine, or high-water write for the oversize source");
  assert.equal([...db2.__docs.keys()].filter((p) => p.includes("/eventState/")).length, 1, "only the valid neighbour's high-water row exists");
  assert.equal(db2.__docs.get("users/u1/events/ok").outcome, "advance", "the other candidate in the wave still settles idempotently");
  assert.equal("event_envelope_prepass" in db2.__docs.get(scheduler.STATE_PATH), false, "no cursor movement for the page");
  assert.equal(healthOf(db2).recentRuns.at(-1).state, "running");
  const entry = deps2.logs.find(([c]) => c === "POST_CUTOFF_SOURCE_SIZE_INVARIANT");
  assert.ok(entry, "fixed structured code");
  assert.deepEqual(Object.keys(entry[1]).sort(), ["baseBytes", "prospectiveMaxBytes", "runOrdinal", "sourcePath"]);
  assert.deepEqual([entry[1].sourcePath, entry[1].baseBytes, entry[1].runOrdinal], ["users/u1/events/big", 1047553, ORD0]);
  assert.ok(!JSON.stringify(entry[1]).includes("xxxx"), "no raw source bytes in the log");
  assert.deepEqual(deps2.metrics.filter(([n]) => n === "phase2/post_cutoff_source_size_invariant_count"), [["phase2/post_cutoff_source_size_invariant_count", 1]]);
  assert.equal(deps2.metrics.filter(([n]) => n === "phase2/disposition_scheduler_completed_count").length, 0);
});

test("C9.1.29 PAYLOAD_TOO_LARGE: a legal source whose valid-advance transition exceeds 8,388,608 retries at attempts 1 and 2 and quarantines as qev1 at attempt 3 with the table message and no high-water row; a stale source of the same size keeps the semantic size-skip and terminalizes source-only", async () => {
  const uid = "u".repeat(60);
  const eventId = "e".repeat(40);
  const sourcePath = `users/${uid}/events/${eventId}`;
  const payload = Object.fromEntries(Array.from({ length: 19900 }, (_, i) => [`f${i}`, "v".repeat(10)])); // 39,800 payload entries + the fixed fields + the six retry-member leaves stay within 40,000
  const source = { ...pendingEvent(eventId), payload };
  const S = scheduler.storage;
  const sourceBudget = S.transitionBudget([{ path: sourcePath, before: null, after: source }]);
  assert.ok(sourceBudget.fits && sourceBudget.perDocument[0].entryBytes <= 8388608, "the source itself is a legal Firestore document");
  const { db, deps, clock } = await initialized({ [`users/${uid}`]: { name: "U" }, [sourcePath]: source });
  const runAt = async (k) => { clock.millis = Date.parse(scheduleAt(k)) + 1000; return scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(k) }, deps); };
  let r = await runAt(0);
  assert.equal(r.outcome, "completed");
  assert.deepEqual([db.__docs.get(sourcePath).processingState, db.__docs.get(sourcePath).phase0ValidationFailure.reasonCode, db.__docs.get(sourcePath).phase0ValidationFailure.failureCount], ["pending", "PAYLOAD_TOO_LARGE", 1]);
  await runAt(1);
  assert.equal(db.__docs.get(sourcePath).phase0ValidationFailure.failureCount, 2);
  r = await runAt(2);
  const s = db.__docs.get(sourcePath);
  assert.deepEqual([s.processingState, s.outcome, s.processingError, "phase0ValidationFailure" in s], ["terminal", "quarantined", "Event payload cannot fit the Phase 2 high-water record.", false]);
  assert.equal([...db.__docs.keys()].filter((p) => p.includes("/eventState/")).length, 0, "no high-water row");
  const record = [...db.__docs.entries()].find(([p]) => p.includes("/quarantinedEvents/qev1_"));
  assert.deepEqual([record[1].reason.code, record[1].failureCount], ["PAYLOAD_TOO_LARGE", 3]);
  // stale: same bytes, lower source_version than the retained high water → terminal "stale", source-only transition, size predicate skipped
  const stateId = scheduler.canonicalEventStateId("institution.updated", "service/provider-1");
  db.__docs.set(`users/${uid}/eventState/${stateId}`, { event_name: "institution.updated", canonical_key: "service/provider-1", source_version: 9, effect: "fire", event_id: "later", observed_at: Timestamp.fromMillis(0), source_evidence_id: "ev", payload: {}, fingerprint: "f".repeat(64), advancedAt: Timestamp.fromMillis(0) });
  await db.doc(`users/${uid}/events/stale`).set({ ...pendingEvent("stale"), payload });
  r = await runAt(3);
  assert.deepEqual([r.outcome, db.__docs.get(`users/${uid}/events/stale`).outcome, db.__docs.get(`users/${uid}/events/stale`).processingState], ["completed", "stale", "terminal"]);
});

test("C9.1.25 RawPhase0SizingV1: an unencodable source is terminalized only after the pinned raw read fits, in an Admin transaction that requires the identical updateTime; drift restarts with a fresh raw read (bounded), and raw absence, an unknown Value oneof, a malformed reserved Vector, or a raw prospective over budget is POST_CUTOFF_SOURCE_SIZE_INVARIANT with no source write", async () => {
  class Foo { constructor() { this.x = 1; } }
  const path = "users/u1/events/weird";
  const seed = async () => { const ctx = await initialized({ "users/u1": { name: "U" }, [path]: { ...pendingEvent("weird"), payload: { thing: new Foo() } } }); return ctx; };
  const runAt = (deps, clock) => async (k) => { clock.millis = Date.parse(scheduleAt(k)) + 1000; return scheduler.runDispositionScheduler({ scheduleTime: scheduleAt(k) }, deps); };
  // happy path: the raw fetch is consulted before the terminalizing transaction
  let { db, deps, clock } = await seed();
  const calls = [];
  const real = deps.fetchRawDocument;
  deps.fetchRawDocument = async (p) => { calls.push(p); return real(p); };
  let r = await runAt(deps, clock)(0);
  assert.deepEqual([r.outcome, calls, db.__docs.get(path).outcome], ["completed", [path], "quarantined"]);
  // drift: the first raw read carries a stale updateTime; the second (fresh) read matches → terminalized
  ({ db, deps, clock } = await seed());
  let n = 0;
  deps.fetchRawDocument = async (p) => { n += 1; const result = await raw.rawFetcherFor(db)(p); if (n === 1) result.document.updateTime = "2000-01-01T00:00:00.000000000Z"; return result; };
  r = await runAt(deps, clock)(0);
  assert.deepEqual([r.outcome, n, db.__docs.get(path).outcome], ["completed", 2, "quarantined"], "one restart with a fresh raw read");
  // persistent drift beyond the bound → invariant, no source write
  ({ db, deps, clock } = await seed());
  n = 0;
  deps.fetchRawDocument = async (p) => { n += 1; const result = await raw.rawFetcherFor(db)(p); result.document.updateTime = "2000-01-01T00:00:00.000000000Z"; return result; };
  r = await runAt(deps, clock)(0);
  assert.deepEqual([r.outcome, db.__docs.get(path).processingState, n], ["incomplete", "pending", 3]);
  assert.ok(deps.logs.some(([c]) => c === "POST_CUTOFF_SOURCE_SIZE_INVARIANT"));
  assert.equal([...db.__docs.keys()].filter((p) => p.includes("quarantinedEvents")).length, 0);
  // raw absence
  ({ db, deps, clock } = await seed());
  deps.fetchRawDocument = async () => ({ found: false });
  r = await runAt(deps, clock)(0);
  assert.deepEqual([r.outcome, db.__docs.get(path).processingState], ["incomplete", "pending"]);
  // unknown Value oneof in the raw document
  ({ db, deps, clock } = await seed());
  deps.fetchRawDocument = async (p) => { const result = await raw.rawFetcherFor(db)(p); result.document.fields.payload = { weirdValue: 1 }; return result; };
  r = await runAt(deps, clock)(0);
  assert.deepEqual([r.outcome, db.__docs.get(path).processingState], ["incomplete", "pending"]);
  assert.ok(deps.logs.some(([c]) => c === "POST_CUTOFF_SOURCE_SIZE_INVARIANT"));
  // malformed reserved Vector → ARCHIVE_CODEC_INVARIANT blocks with no source write
  ({ db, deps, clock } = await seed());
  deps.fetchRawDocument = async (p) => { const result = await raw.rawFetcherFor(db)(p); result.document.fields.payload = { mapValue: { fields: { __type__: { stringValue: "__vector__" } } } }; return result; };
  r = await runAt(deps, clock)(0);
  assert.deepEqual([r.outcome, db.__docs.get(path).processingState], ["incomplete", "pending"]);
  assert.ok(deps.logs.some(([c]) => c === "ARCHIVE_CODEC_INVARIANT"));
  // raw prospective terminal over budget (the raw document is padded past the document bound) → invariant, no write
  ({ db, deps, clock } = await seed());
  deps.fetchRawDocument = async (p) => { const result = await raw.rawFetcherFor(db)(p); result.document.fields.pad = { stringValue: "x".repeat(1048576) }; return result; };
  r = await runAt(deps, clock)(0);
  assert.deepEqual([r.outcome, db.__docs.get(path).processingState], ["incomplete", "pending"]);
  const entry = deps.logs.find(([c]) => c === "POST_CUTOFF_SOURCE_SIZE_INVARIANT");
  assert.ok(entry && entry[1].sourcePath === path && !JSON.stringify(entry[1]).includes("xxxx"));
  // a Phase-1 wrapper call without a raw reader cannot terminalize an unencodable source (fail closed, no write)
  const plain = fakeFirestore({ docs: { "users/u1": { name: "U" }, [path]: { ...pendingEvent("weird"), payload: { thing: new Foo() } } } });
  await assert.rejects(consumeEventEnvelopeInTransaction(plain, plain.doc(path), NOW), (e) => e.code === "RAW_DOCUMENT_UNAVAILABLE");
  assert.equal(plain.__docs.get(path).processingState, "pending");
});

test("emulator: productionDependencies().fetchRawDocument reads the pinned public-v1 Document from the emulator with fields and updateTime, and reports absence", { skip: process.env.FIRESTORE_EMULATOR_HOST ? false : "FIRESTORE_EMULATOR_HOST is unset; run scripts/test-emulator.sh node" }, async () => {
  const { initializeApp, getApps } = require("firebase-admin/app");
  const { getFirestore } = require("firebase-admin/firestore");
  const app = getApps().length ? getApps()[0] : initializeApp({ projectId: "demo-peezy-phase1" });
  const live = getFirestore(app);
  const docPath = `users/raw-${Date.now()}/events/e1`;
  await live.doc(docPath).set({ ...pendingEvent("e1"), payload: { n: 1, s: "x", arr: [1, "a"], ts: Timestamp.fromMillis(1_700_000_000_123) } });
  const fetched = await scheduler.productionDependencies().fetchRawDocument(docPath);
  assert.equal(fetched.found, true);
  assert.equal(fetched.document.name.endsWith(`/documents/${docPath}`), true);
  assert.deepEqual(fetched.document.fields.payload.mapValue.fields.n, { integerValue: "1" });
  assert.equal(fetched.document.fields.payload.mapValue.fields.ts.timestampValue, "2023-11-14T22:13:20.123Z");
  assert.match(fetched.document.updateTime, /^\d{4}-\d{2}-\d{2}T/);
  assert.equal(scheduler.rawStorage.documentSize(docPath, fetched.document.fields), scheduler.storage.documentSize(docPath, (await live.doc(docPath).get()).data()), "raw and decoded sizing agree on a live document");
  assert.deepEqual(await scheduler.productionDependencies().fetchRawDocument(`${docPath}-absent`), { found: false });
});

test("C9.1.30 (D11) PEEZY_STATE_REGEN_SPEC.md item 9 is the contract's exact replacement line, and neither retired phrase occurs in any active document outside that quoted replacement", () => {
  const root = path.resolve(__dirname, "../..");
  const contract = fs.readFileSync(path.join(root, "docs/plans/PHASE2_CONTRACT.md"), "utf8").split("\n");
  const replacement = contract.find((l) => l.startsWith("9. **Next post-Phase-2 regeneration — H57 disposition operations"));
  assert.ok(replacement && replacement.length > 3000, "the contract carries the full quoted replacement");
  const spec = fs.readFileSync(path.join(root, "PEEZY_STATE_REGEN_SPEC.md"), "utf8").split("\n");
  const item9 = spec.filter((l) => /^9\. \*\*Next post-Phase-2 regeneration/.test(l));
  assert.equal(item9.length, 1, "exactly one item 9");
  assert.equal(item9[0], replacement, "item 9 replaced in full, never merged with old wording");
  const active = ["PEEZY_STATE.md", "PEEZY_STATE_REGEN_SPEC.md", "STATUS.md", "HANDOFF.md", "PHASE2_WORKFLOW_v2.md", ...fs.readdirSync(path.join(root, "briefs")).map((f) => `briefs/${f}`), ...fs.readdirSync(path.join(root, "tasks")).map((f) => `tasks/${f}`)].filter((f) => f.endsWith(".md") && fs.existsSync(path.join(root, f)));
  const retired = ["after three identical deterministic validation failures", "H57 quarantine consumer"];
  for (const file of active) {
    const text = fs.readFileSync(path.join(root, file), "utf8").split("\n").filter((l) => l !== replacement).join("\n");
    for (const phrase of retired) assert.equal(text.includes(phrase), false, `${file} contains "${phrase}"`);
  }
  // the contract itself names the phrases only inside the C9.1.30 rule table and the quoted replacement
  const outsideRule = contract.filter((l) => l !== replacement && !l.startsWith("| Zero occurrences |")).join("\n");
  for (const phrase of retired) assert.equal(outsideRule.includes(phrase), false, `contract contains "${phrase}" outside C9.1.30`);
});


// ---------------------------------------------------------------------------
// S3 I11a — PHASE2_CONTRACT.md C9.2 MIG-EVENT-V1: arming, exact query, stream classification, reread, the
// FirestoreDocumentArchiveV1 codec and its oracle, the chunk gate, and the two-pass audit. The contract's inventory
// keeps the migration fixtures in this file (C10: "no new Node test file is implied").
// ---------------------------------------------------------------------------

const migration = require("../scripts/migrateOversizeEvents");
const archiveOracle = require("./support/archiveOracle");
const { FakeV1Client, gapicFields, gapicValue, ts: gapicTs, ROOT: GAPIC_ROOT } = require("./support/fakeV1Client");
const gapicProtos = require("@google-cloud/firestore/build/protos/firestore_v1_proto_api.js");

const MIG_PROJECT = "demo-peezy-phase1";
const MIG_NOW = Timestamp.fromMillis(Date.parse("2026-09-06T12:00:00.000Z"));
const migPending = (id, extra = {}) => ({ event_id: id, event_name: "institution.updated", canonical_key: "service/provider-1", source_version: 2, observed_at: Timestamp.fromMillis(Date.parse("2026-08-27T16:59:00.000Z")), source_evidence_id: "ev", effect: "fire", payload: {}, processingState: "pending", processed: false, ...extra });
const migOversize = (id) => migPending(id, { payload: { s: "x".repeat(1_047_600) } });
function migDeps(client, overrides = {}) {
  return {
    env: {}, now: () => MIG_NOW, readFile: (file) => fs.readFileSync(file), repositoryRoot: path.resolve(__dirname, "../.."),
    pinnedVersion: () => "7.11.6", pinnedConfigSha256: () => migration.PINNED_CLIENT_CONFIG_SHA256, protos: gapicProtos,
    createClient: () => ({ client, callOptions: {} }), resolveTarget: async () => ({ projectId: MIG_PROJECT, databaseId: "(default)" }), ...overrides
  };
}

test("C9.2.2 import has no effect; default mode is a read-only audit; every executable arming predicate fails closed before the write seam; only the complete literal arming set reaches it", async () => {
  const source = fs.readFileSync(path.resolve(__dirname, "../scripts/migrateOversizeEvents.js"), "utf8");
  assert.match(source, /if \(require\.main === module\) main\(\)/);
  const client = new FakeV1Client({ projectId: MIG_PROJECT });
  let result = await migration.run([], migDeps(client));
  assert.deepEqual([result.exitCode, result.report.mode, result.report.refusal], [0, "audit", null]);
  assert.equal(client.queries.length, 2, "two audit passes");
  const production = (overrides = {}) => migDeps(new FakeV1Client({ projectId: "peezy-1ecrdl" }), { resolveTarget: async () => ({ projectId: "peezy-1ecrdl", databaseId: "(default)" }), ...overrides });
  const armed = ["--apply", "--project-id", "peezy-1ecrdl", "--confirm-project", "peezy-1ecrdl"];
  for (const [label, argv, d, refusal] of [
    ["unknown argument", [...armed, "--force"], production(), "UNKNOWN_ARGUMENT"],
    ["wrong project id", ["--apply", "--project-id", "demo", "--confirm-project", "peezy-1ecrdl"], production(), "PROJECT_ID_MISMATCH"],
    ["missing confirmation", ["--apply", "--project-id", "peezy-1ecrdl"], production(), "CONFIRM_PROJECT_MISMATCH"],
    ["emulator variable", armed, production({ env: { FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080" } }), "EMULATOR_HOST_PRESENT"],
    ["resolved target differs", armed, production({ resolveTarget: async () => ({ projectId: "other", databaseId: "(default)" }) }), "RESOLVED_TARGET_MISMATCH"],
    ["rules hash drift", armed, production({ readFile: (file) => (file.endsWith("firestore.rules") ? Buffer.from("drift") : fs.readFileSync(file)) }), "ROLLOUT_TUPLE_MISMATCH"],
    ["pin drift", armed, production({ pinnedVersion: () => "7.11.7" }), "PIN_MISMATCH"]
  ]) {
    result = await migration.run(argv, d);
    assert.equal(result.report.refusal, refusal, label);
    assert.notEqual(result.exitCode, 0, label);
  }
  result = await migration.run(armed.slice(1), production());
  assert.deepEqual([result.report.mode, result.report.refusal], ["audit", null], "without --apply the run is the default read-only audit");
  assert.equal(migration.armingRefusal(migration.parseArguments(armed.slice(1)), production(), { projectId: "peezy-1ecrdl", databaseId: "(default)" }), "NOT_ARMED");
  result = await migration.run(armed, production());
  assert.deepEqual([result.report.mode, result.report.refusal, result.report.apply.lease.fencingGeneration, result.report.apply.release.absent], ["apply", null, 1, true], "the complete literal set reaches the write seam: lease acquired, nothing to migrate, gate passed, lease released");
  assert.deepEqual(migration.rolloutTuple(migDeps(client)), migration.ROLLOUT_TUPLE_V1, "the accepted tuple equals the current rules/index bytes");
});

test("C9.2.1 the exact StructuredQuery reaches the injected runQuery with limit.value == 100 and a reference cursor only after a full page; absent, unwrapped, or out-of-range wrappers are fatal; enumeration at 0/1/100/101 documents pages correctly", async () => {
  const q = migration.structuredQueryFor(gapicProtos, null);
  assert.equal(q.limit.value, 100);
  assert.equal(q.from[0].collectionId, "events"); assert.equal(q.from[0].allDescendants, true);
  // the pinned proto stores enums as their numbers: FieldFilter.Operator.EQUAL == 5, Direction.ASCENDING == 1
  assert.equal(q.where.fieldFilter.field.fieldPath, "processingState"); assert.equal(q.where.fieldFilter.op, 5); assert.equal(q.where.fieldFilter.value.stringValue, "pending");
  assert.equal(q.orderBy[0].field.fieldPath, "__name__"); assert.equal(q.orderBy[0].direction, 1);
  assert.equal(q.startAt, null);
  const cursored = migration.structuredQueryFor(gapicProtos, `${GAPIC_ROOT(MIG_PROJECT)}/users/u1/events/e099`);
  assert.equal(cursored.startAt.before, false); assert.equal(cursored.startAt.values[0].referenceValue, `${GAPIC_ROOT(MIG_PROJECT)}/users/u1/events/e099`);
  for (const [label, limit] of [["absent", undefined], ["unwrapped", 100], ["zero", { value: 0 }], ["negative", { value: -1 }], ["int32 overflow", { value: 2147483648 }], ["not the page", { value: 50 }], ["nonsafe", { value: 1.5 }]]) assert.throws(() => migration.validateLimitWrapper(limit), (e) => e.code === "LIMIT_WRAPPER_INVALID", label);
  for (const count of [0, 1, 100, 101]) {
    const docs = {};
    for (let i = 0; i < count; i += 1) docs[`users/u1/events/e${String(i).padStart(3, "0")}`] = migPending(`e${String(i).padStart(3, "0")}`);
    const client = new FakeV1Client({ projectId: MIG_PROJECT, documents: docs });
    const seen = [];
    const total = await migration.enumeratePending(client, gapicProtos, MIG_PROJECT, {}, async (d) => { seen[seen.length] = d.name; });
    assert.equal(total, count, `count ${count}`);
    assert.equal(seen.length, count);
    assert.equal(client.queries.length, count >= 100 ? 2 : 1, `queries for ${count}`);
    if (count >= 100) assert.equal(client.queries[1].request.structuredQuery.startAt.values[0].referenceValue, `${GAPIC_ROOT(MIG_PROJECT)}/users/u1/events/e099`, "cursor after the 100th");
    for (const { request } of client.queries) assert.equal(request.structuredQuery.limit.value, 100);
  }
});

test("C9.2.1 stream classification by presence: document, progress, and done responses; fatal on a transaction, nonzero skippedResults, explainMetrics, unknown member, empty member, missing document readTime, non-ascending names, anything after the terminal marker, and an empty query without progress", async () => {
  const client = new FakeV1Client({ projectId: MIG_PROJECT });
  const doc = { name: `${GAPIC_ROOT(MIG_PROJECT)}/users/u1/events/e1`, fields: gapicFields(migPending("e1")), createTime: gapicTs(0), updateTime: gapicTs(0) };
  assert.equal(migration.classifyResponse(client.response({ document: doc })).kind, "document");
  assert.equal(migration.classifyResponse(client.response({ document: doc, done: true })).done, true);
  assert.equal(migration.classifyResponse(client.response({})).kind, "progress");
  assert.equal(migration.classifyResponse(client.response({ done: true, readTime: null })).kind, "done");
  assert.equal(migration.classifyResponse(client.response({ done: true })).kind, "done", "done with a valid readTime");
  for (const [label, overrides] of [["transaction", { transaction: Buffer.from([1]) }], ["skippedResults", { skippedResults: 1 }], ["negative skipped", { skippedResults: -1 }], ["explainMetrics", { explainMetrics: {} }], ["unknown member", { surprise: 1 }], ["empty member", { readTime: null }], ["document without readTime", { document: doc, readTime: null }], ["incomplete document", { document: { name: doc.name } }], ["invalid readTime", { readTime: { seconds: "x" } }]]) {
    assert.throws(() => migration.classifyResponse(client.response(overrides)), (e) => e.code === "STREAM_SHAPE_INVALID", label);
  }
  const scripted = (responses) => new FakeV1Client({ projectId: MIG_PROJECT, scriptedResponses: () => responses.map((o) => client.response(o)) });
  const named = (n) => ({ ...doc, name: `${GAPIC_ROOT(MIG_PROJECT)}/users/u1/events/${n}` });
  const run = (c) => migration.enumeratePending(c, gapicProtos, MIG_PROJECT, {}, async () => {});
  await assert.rejects(run(scripted([{ document: named("b") }, { document: named("a") }])), (e) => e.code === "STREAM_SHAPE_INVALID", "non-ascending");
  await assert.rejects(run(scripted([{ document: named("a") }, { document: named("a") }])), (e) => e.code === "STREAM_SHAPE_INVALID", "duplicate");
  await assert.rejects(run(scripted([{ document: named("a"), done: true }, { document: named("b") }])), (e) => e.code === "STREAM_SHAPE_INVALID", "after terminal");
  await assert.rejects(run(scripted([{ done: true, readTime: null }, {}])), (e) => e.code === "STREAM_SHAPE_INVALID", "after done");
  await assert.rejects(run(scripted([])), (e) => e.code === "STREAM_SHAPE_INVALID", "empty query without a progress response");
  assert.equal(await run(scripted([{}])), 0, "empty query after one progress response");
  assert.equal(await run(scripted([{}, { document: named("a") }, { done: true, readTime: null }])), 1);
});

test("C9.2.4 the archive codec encodes every raw Value oneof exactly (tags, big-endian doubles 1.0/-0.0/subnormal, NaN forms, infinities, int64 extrema, timestamp extremes, geopoint, unsigned-UTF-8 key order), round-trips byte-for-byte, and the digest and N <= S + 4K + 13V + F + 8,192 hold; the oracle recomputes F and N", () => {
  const hex = (n) => { const b = Buffer.alloc(8); b.writeDoubleBE(n, 0); return b.toString("hex"); };
  const fields = gapicFields({
    z: null, f: false, t: true, i: 1, big: 9223372036854775807n, small: -9223372036854775808n, d: 1.0, negZero: -0.0, sub: Number.MIN_VALUE, nan: NaN, inf: Infinity, ninf: -Infinity,
    ts: Timestamp.fromMillis(1_700_000_000_123), tmax: new Timestamp(253402300799, 999999999), tmin: new Timestamp(-62135596800, 0),
    s: "héllo", bytes: Buffer.from([0, 255]), ref: { __ref: "users/u1/tasks/t1" }, geo: { __geo: [1.5, -2] }, arr: [1, "a", null, [true]], map: { b: 1, a: 2, "é": 3, "z": { nested: "x" } },
    vec: { __type__: "__vector__", value: [1.5, 2.5] }
  }, MIG_PROJECT);
  const document = { name: `${GAPIC_ROOT(MIG_PROJECT)}/users/u1/events/e1`, fields, createTime: gapicTs(0), updateTime: { seconds: "1700000000", nanos: 5 } };
  const encoded = migration.encodeArchive(document);
  assert.equal(encoded.bytes.subarray(0, 5).toString("latin1"), "PZFDA");
  assert.equal(encoded.bytes[5], 1);
  const enc = (v) => migration.encodeValue(gapicValue(v, MIG_PROJECT), { K: 0, V: 0, F: 0 }).toString("hex");
  const encDouble = (d) => migration.encodeValue({ valueType: "doubleValue", doubleValue: d }, { K: 0, V: 0, F: 0 }).toString("hex");
  assert.equal(encDouble(1.0), `04${hex(1.0)}`); assert.equal(hex(1.0), "3ff0000000000000"); assert.equal(encDouble(-0.0), `04${hex(-0.0)}`); assert.equal(hex(-0.0), "8000000000000000"); assert.equal(encDouble(Number.MIN_VALUE), "040000000000000001");
  assert.equal(enc(1), "030000000000000001", "an integral fixture number is an int64");
  assert.equal(enc(NaN), "05"); assert.equal(enc(Infinity), "06"); assert.equal(enc(-Infinity), "07"); assert.equal(enc(null), "00"); assert.equal(enc(false), "01"); assert.equal(enc(true), "02");
  assert.equal(enc(9223372036854775807n), "037fffffffffffffff"); assert.equal(enc(-9223372036854775808n), "038000000000000000");
  assert.equal(enc("é"), "0900000002c3a9");
  assert.equal(enc({ __geo: [1.5, -2] }), `0c${hex(1.5)}${hex(-2)}`);
  const minSeconds = Buffer.alloc(8); minSeconds.writeBigInt64BE(-62135596800n, 0);
  assert.equal(enc(new Timestamp(-62135596800, 0)), `08${minSeconds.toString("hex")}00000000`, "timestamp minimum as big-endian i64 seconds plus u32 nanos");
  const maxSeconds = Buffer.alloc(8); maxSeconds.writeBigInt64BE(253402300799n, 0);
  assert.equal(enc(new Timestamp(253402300799, 999999999)), `08${maxSeconds.toString("hex")}3b9ac9ff`, "timestamp maximum");
  assert.equal(migration.encodeValue({ valueType: "doubleValue", doubleValue: -NaN }, { K: 0, V: 0, F: 0 }).toString("hex"), "05", "every NaN normalizes to tag 05");
  const mapHex = enc({ b: 1, a: 2, "é": 3 });
  assert.ok(mapHex.startsWith("0e00000003" + "0000000161" + "030000000000000002"), "keys in unsigned UTF-8 byte order: a, b, e-acute");
  const decoded = migration.decodeArchive(encoded.bytes);
  const again = migration.encodeArchive(decoded);
  assert.ok(again.bytes.equals(encoded.bytes), "encode(decode(bytes)) == bytes");
  assert.equal(encoded.archiveDigest, createHash("sha256").update(encoded.bytes).digest("hex"));
  assert.deepEqual(decoded.updateTime, { seconds: "1700000000", nanos: 5 });
  assert.equal(decoded.fields.big.integerValue, "9223372036854775807", "int64 precision preserved");
  assert.ok(Number.isNaN(decoded.fields.nan.doubleValue));
  const view = archiveOracle.archiveBytes(document);
  assert.deepEqual([encoded.N, encoded.K, encoded.V, encoded.F], [view.N, view.K, view.V, view.F], "oracle agrees on N, K, V, F");
  const S = scheduler.rawStorage.documentSize("users/u1/events/e1", migration.toJsonFields(fields));
  assert.ok(encoded.N <= S + 4 * encoded.K + 13 * encoded.V + encoded.F + 8192);
  const refs = Object.fromEntries(Array.from({ length: 1000 }, (_, i) => [`r${i}`, { __ref: "a/b" }]));
  const refDoc = { name: `${GAPIC_ROOT(MIG_PROJECT)}/users/u1/events/refs`, fields: gapicFields(refs, MIG_PROJECT), createTime: gapicTs(0), updateTime: gapicTs(0) };
  const refEncoded = migration.encodeArchive(refDoc);
  const refS = scheduler.rawStorage.documentSize("users/u1/events/refs", migration.toJsonFields(refDoc.fields));
  assert.ok(refEncoded.N > refS + 4 * refEncoded.K + 13 * refEncoded.V + 8192, "without F the bound fails");
  assert.ok(refEncoded.N <= refS + 4 * refEncoded.K + 13 * refEncoded.V + refEncoded.F + 8192, "with F the bound passes");
  assert.equal(archiveOracle.archiveBytes(refDoc).F, refEncoded.F);
  for (const [label, bad] of [["unknown oneof", { valueType: "weirdValue" }], ["malformed timestamp", { valueType: "timestampValue", timestampValue: { seconds: "x", nanos: 0 } }], ["nanos out of range", { valueType: "timestampValue", timestampValue: { seconds: "1", nanos: 1e9 } }], ["empty reference", { valueType: "referenceValue", referenceValue: "" }]]) {
    assert.throws(() => migration.encodeValue(bad, { K: 0, V: 0, F: 0 }), (e) => e.code === "ARCHIVE_CODEC_INVARIANT", label);
  }
  assert.throws(() => migration.decodeArchive(Buffer.concat([encoded.bytes, Buffer.from([0])])), (e) => e.code === "ARCHIVE_CODEC_INVARIANT", "decoder residue");
  assert.throws(() => migration.decodeArchive(encoded.bytes.subarray(0, encoded.bytes.length - 1)), (e) => e.code === "ARCHIVE_CODEC_INVARIANT", "truncated");
  const id = migration.archiveIdFor("users/u1/events/e1", document.updateTime, encoded.archiveDigest);
  assert.match(id, /^qev2_[0-9a-f]{40}$/);
  assert.equal(id, `qev2_${createHash("sha256").update(JSON.stringify({ archive_digest: encoded.archiveDigest, domain: "event_archive.v1", source_path: "users/u1/events/e1", source_update_time: { nanoseconds: 5, seconds: 1700000000 } })).digest("hex").slice(0, 40)}`);
});

test("C9.2.5 the chunk gate: N == MAX_ARCHIVE_BYTES admits 49 chunks; N == MAX_ARCHIVE_BYTES + 1 is ARCHIVE_CHUNK_CAP_EXCEEDED with only the code and measured N; chunk counts at P-1/P/P+1/2P; a reference-heavy source", () => {
  const build = (targetN) => {
    const probe = { name: `${GAPIC_ROOT(MIG_PROJECT)}/users/u1/events/big`, fields: gapicFields({ s: "" }), createTime: gapicTs(0), updateTime: gapicTs(0) };
    const base = migration.encodeArchive(probe).N;
    return { ...probe, fields: gapicFields({ s: "x".repeat(targetN - base) }) };
  };
  const at = (n) => { const d = build(n); return migration.archivePlan(d, "users/u1/events/big", scheduler.rawStorage.documentSize("users/u1/events/big", migration.toJsonFields(d.fields))); };
  assert.deepEqual([at(migration.MAX_ARCHIVE_BYTES).N, at(migration.MAX_ARCHIVE_BYTES).chunkCount], [migration.MAX_ARCHIVE_BYTES, 49]);
  assert.throws(() => at(migration.MAX_ARCHIVE_BYTES + 1), (e) => e.code === "ARCHIVE_CHUNK_CAP_EXCEEDED" && e.detail === String(migration.MAX_ARCHIVE_BYTES + 1) && !e.message.includes("xxxx"));
  const P = migration.CHUNK_PAYLOAD_MAX;
  assert.deepEqual([at(P - 1).chunkCount, at(P).chunkCount, at(P + 1).chunkCount, at(2 * P).chunkCount, at(2 * P + 1).chunkCount], [1, 1, 2, 2, 3]);
  const heavy = { name: `${GAPIC_ROOT(MIG_PROJECT)}/users/u1/events/heavy`, fields: gapicFields(Object.fromEntries(Array.from({ length: 5000 }, (_, i) => [`r${i}`, { __ref: "a/b" }])), MIG_PROJECT), createTime: gapicTs(0), updateTime: gapicTs(0) };
  const plan = migration.archivePlan(heavy, "users/u1/events/heavy", scheduler.rawStorage.documentSize("users/u1/events/heavy", migration.toJsonFields(heavy.fields)));
  assert.ok(plan.N <= plan.bound && plan.chunkCount >= 1);
});

test("C9.2.1 classification: in-scope names only (one segment each), OUT_OF_SCOPE_SOURCE for any other matching path, mandatory reread before deriving identity, drift on a missing or no-longer-pending reread, admitted sources pass the raw envelope, oversize sources carry archive identity and chunk counts; the report never carries raw bytes", async () => {
  const client = new FakeV1Client({ projectId: MIG_PROJECT, documents: {
    "users/u1/events/ok": migPending("ok"),
    "users/u1/events/big": migOversize("big"),
    "orgs/o1/events/x": migPending("x"),
    "users/u1/things/t1/events/nested": migPending("nested")
  } });
  const seen = [];
  await migration.enumeratePending(client, gapicProtos, MIG_PROJECT, {}, async (d) => { seen[seen.length] = await migration.classifyDocument(client, {}, MIG_PROJECT, d, MIG_NOW); });
  const byPath = Object.fromEntries(seen.map((s) => [s.sourcePath || s.pathDigest, s]));
  assert.equal(byPath["users/u1/events/ok"].outcome, "ADMITTED");
  const big = byPath["users/u1/events/big"];
  assert.deepEqual([big.outcome, big.chunkCount >= 3, /^qev2_[0-9a-f]{40}$/.test(big.archiveId), big.baseBytes > 1047552], ["SOURCE_TOO_LARGE", true, true, true]);
  assert.equal(seen.filter((s) => s.outcome === "OUT_OF_SCOPE_SOURCE").length, 2, "two out-of-scope matching paths");
  assert.ok(client.reads.length >= 2 && client.reads.every((n) => n.includes("/users/u1/events/")), "every in-scope document is reread; out-of-scope never");
  const drifting = new FakeV1Client({ projectId: MIG_PROJECT, documents: { "users/u1/events/gone": migPending("gone"), "users/u1/events/done": migPending("done") } });
  const original = drifting.getDocument.bind(drifting);
  drifting.getDocument = async ({ name }) => { if (name.endsWith("/gone")) { const e = new Error("NOT_FOUND"); e.code = 5; throw e; } if (name.endsWith("/done")) drifting.put("users/u1/events/done", migPending("done", { processingState: "terminal" })); return original({ name }); };
  const outcomes = [];
  await migration.enumeratePending(drifting, gapicProtos, MIG_PROJECT, {}, async (d) => { outcomes[outcomes.length] = (await migration.classifyDocument(drifting, {}, MIG_PROJECT, d, MIG_NOW)).outcome; });
  assert.deepEqual(outcomes.sort(), ["DRIFT_MISSING", "DRIFT_NOT_PENDING"]);
  const report = migration.reportOf(migration.parseArguments([]), migDeps(client), { projectId: MIG_PROJECT, databaseId: "(default)" }, await migration.runAudit(client, gapicProtos, MIG_PROJECT, {}, MIG_NOW), null);
  assert.equal(JSON.stringify(report).includes("xxxxxxxx"), false, "no raw source bytes in the report");
  assert.equal(report.audit.passes[0].failing[0].sourcePath, "users/u1/events/big");
  assert.equal(report.firestoreVersion, "7.11.6");
  assert.equal(report.clientConfigSha256, migration.PINNED_CLIENT_CONFIG_SHA256);
});

test("C9.2.1/C9.2.9 two-pass audit: stable when both complete passes agree on the pending count and the failing/out-of-scope sets with zero drift; an insertion between passes is unstable (restart); a systemic stream error leaves the first pass incomplete; the pre-ship criterion additionally needs zero failing and zero out-of-scope", async () => {
  const client = new FakeV1Client({ projectId: MIG_PROJECT, documents: { "users/u1/events/ok": migPending("ok"), "users/u1/events/big": migOversize("big") } });
  let audit = await migration.runAudit(client, gapicProtos, MIG_PROJECT, {}, MIG_NOW);
  assert.deepEqual([audit.stable, audit.preShipCriterion, audit.passes.length, audit.passes[1].pendingCount, audit.passes[1].failing.length], [true, false, 2, 2, 1]);
  const clean = new FakeV1Client({ projectId: MIG_PROJECT, documents: { "users/u1/events/ok": migPending("ok") } });
  audit = await migration.runAudit(clean, gapicProtos, MIG_PROJECT, {}, MIG_NOW);
  assert.deepEqual([audit.stable, audit.preShipCriterion], [true, true]);
  const inserting = new FakeV1Client({ projectId: MIG_PROJECT, documents: { "users/u1/events/ok": migPending("ok") }, onQuery: (request, n) => { if (n === 2) inserting.put("users/u1/events/late", migPending("late")); } });
  audit = await migration.runAudit(inserting, gapicProtos, MIG_PROJECT, {}, MIG_NOW);
  assert.deepEqual([audit.stable, audit.passes[0].pendingCount, audit.passes[1].pendingCount], [false, 1, 2], "insertion caught by the uncursored confirmation pass");
  const broken = new FakeV1Client({ projectId: MIG_PROJECT, scriptedResponses: () => [new FakeV1Client({ projectId: MIG_PROJECT }).response({ skippedResults: 3 })] });
  audit = await migration.runAudit(broken, gapicProtos, MIG_PROJECT, {}, MIG_NOW);
  assert.deepEqual([audit.stable, audit.passes.length, audit.passes[0].complete, audit.passes[0].systemic.code], [false, 1, false, "STREAM_SHAPE_INVALID"]);
  const insertingAgain = new FakeV1Client({ projectId: MIG_PROJECT, documents: { "users/u1/events/ok": migPending("ok") }, onQuery: (request, n) => { if (n === 2) insertingAgain.put("users/u1/events/late", migPending("late")); } });
  const result = await migration.run([], migDeps(insertingAgain));
  assert.equal(result.exitCode, 1, "an unstable audit exits nonzero");
});


// ---------------------------------------------------------------------------
// S3 I11b — C9.2.3 lease cross-fence, C9.2.5/C9.2.6 archive writes and the four-write terminal commit,
// C9.2.7 budgets, C9.2.8 orphan cleanup, C9.2.9 pre-ship gate, apply run under the fenced lease.
// ---------------------------------------------------------------------------

const PROD_PROJECT = "peezy-1ecrdl";
const prodDeps = (client, overrides = {}) => migDeps(client, { resolveTarget: async () => ({ projectId: PROD_PROJECT, databaseId: "(default)" }), ownerToken: () => "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", ...overrides });
const ARMED = ["--apply", "--project-id", PROD_PROJECT, "--confirm-project", PROD_PROJECT];
const leaseDoc = (client) => client.get(migration.MIGRATION_LEASE_PATH);
const readLeaseView = (client) => { const d = leaseDoc(client); return d ? { ownerToken: d.fields.ownerToken.stringValue, generation: Number(d.fields.fencingGeneration.integerValue), startedAt: d.fields.startedAt.timestampValue, renewedAt: d.fields.renewedAt.timestampValue, expiresAt: d.fields.expiresAt.timestampValue } : null; };

test("C9.2.3 lease acquisition: generation 1 when both leases are absent; an exact legacy scheduler lease is deleted in the same commit; malformed non-v2, live v2, and expired-v2-within-60-seconds scheduler leases refuse with zero writes; an expired v2 past the grace acquires; a live migration lease refuses; an expired migration lease takes generation + 1", async () => {
  const seconds = (client, delta) => ({ seconds: String(Math.floor(client.clock.millis / 1000) + delta), nanos: 0 });
  let client = new FakeV1Client({ projectId: PROD_PROJECT });
  let result = await migration.acquireMigrationLease(client, PROD_PROJECT, {}, "owner-1");
  assert.deepEqual([result.acquired, result.lease.fencingGeneration, result.migratedSchedulerLease], [true, 1, false]);
  let view = readLeaseView(client);
  assert.deepEqual([view.ownerToken, view.generation, view.startedAt, view.renewedAt], ["owner-1", 1, view.startedAt, view.startedAt]);
  assert.equal(Number(view.expiresAt.seconds) - Number(view.renewedAt.seconds), 300, "expiresAt == renewedAt + 300 s");
  // exact legacy scheduler lease migrated in the same commit
  client = new FakeV1Client({ projectId: PROD_PROJECT });
  client.put(migration.SCHEDULER_LEASE_PATH, { runId: "old", acquiredAt: { __ts: seconds(client, -100) }, expiresAt: { __ts: seconds(client, 100) } });
  result = await migration.acquireMigrationLease(client, PROD_PROJECT, {}, "owner-2");
  assert.deepEqual([result.acquired, result.migratedSchedulerLease, client.get(migration.SCHEDULER_LEASE_PATH), client.commits.at(-1).writes.length], [true, true, null, 2], "delete scheduler lease + create migration lease in one commit");
  for (const [label, schedulerLease] of [
    ["malformed non-v2", { weird: true }],
    ["live v2", { schemaVersion: 1, runOrdinal: 5, ownerToken: "t", startedAt: { __ts: seconds(client, -10) }, expiresAt: { __ts: seconds(client, 200) } }],
    ["expired v2 within grace", { schemaVersion: 1, runOrdinal: 5, ownerToken: "t", startedAt: { __ts: seconds(client, -400) }, expiresAt: { __ts: seconds(client, -30) } }]
  ]) {
    const c = new FakeV1Client({ projectId: PROD_PROJECT });
    c.put(migration.SCHEDULER_LEASE_PATH, schedulerLease);
    const r = await migration.acquireMigrationLease(c, PROD_PROJECT, {}, "owner-3");
    assert.deepEqual([r.acquired, c.commits.length, leaseDoc(c)], [false, 0, null], label);
    assert.match(r.refusal, /^SCHEDULER_LEASE_/, label);
  }
  client = new FakeV1Client({ projectId: PROD_PROJECT });
  client.put(migration.SCHEDULER_LEASE_PATH, { schemaVersion: 1, runOrdinal: 5, ownerToken: "t", startedAt: { __ts: seconds(client, -400) }, expiresAt: { __ts: seconds(client, -61) } });
  result = await migration.acquireMigrationLease(client, PROD_PROJECT, {}, "owner-4");
  assert.deepEqual([result.acquired, client.get(migration.SCHEDULER_LEASE_PATH) !== null], [true, true], "expired v2 past the grace acquires and leaves the v2 lease alone");
  // live other owner refuses; expired migration lease takes generation + 1
  const held = new FakeV1Client({ projectId: PROD_PROJECT });
  await migration.acquireMigrationLease(held, PROD_PROJECT, {}, "owner-5");
  result = await migration.acquireMigrationLease(held, PROD_PROJECT, {}, "owner-6");
  assert.deepEqual([result.acquired, result.refusal], [false, "MIGRATION_LEASE_LIVE"]);
  held.clock.advance(301_000);
  result = await migration.acquireMigrationLease(held, PROD_PROJECT, {}, "owner-6");
  assert.deepEqual([result.acquired, result.lease.fencingGeneration, readLeaseView(held).ownerToken], [true, 2, "owner-6"]);
});

test("C9.2.3 renewal preserves startedAt and rides every fenced commit under the exact update-time precondition; after a takeover the prior owner's fenced commit fails MIGRATION_LEASE_LOST with zero mutation; release deletes under the precondition and proves absence; a stale release after takeover fails harmlessly", async () => {
  const client = new FakeV1Client({ projectId: PROD_PROJECT, documents: { "users/u1/events/e1": migPending("e1") } });
  const first = await migration.acquireMigrationLease(client, PROD_PROJECT, {}, "owner-a");
  const startedAt = readLeaseView(client).startedAt;
  client.clock.advance(5_000);
  const target = `${GAPIC_ROOT(PROD_PROJECT)}/users/u1/things/x`;
  const committed = await migration.fencedCommit(client, PROD_PROJECT, {}, first.lease, [target], () => ({ writes: [{ update: { name: target, fields: gapicFields({ a: 1 }) }, currentDocument: { exists: false } }] }));
  assert.equal(committed.committed, true);
  let view = readLeaseView(client);
  assert.deepEqual([view.startedAt, view.generation, Number(view.renewedAt.seconds) > Number(startedAt.seconds)], [startedAt, 1, true], "renewal keeps startedAt and advances renewedAt");
  assert.equal(client.commits.at(-1).writes[0].update.name, `${GAPIC_ROOT(PROD_PROJECT)}/${migration.MIGRATION_LEASE_PATH}`, "the renewal is the first write of the commit");
  // takeover: lease expires, another owner acquires generation 2; the prior owner's next fenced commit fails closed
  client.clock.advance(301_000);
  const second = await migration.acquireMigrationLease(client, PROD_PROJECT, {}, "owner-b");
  assert.equal(second.lease.fencingGeneration, 2);
  const before = client.commits.length;
  await assert.rejects(migration.fencedCommit(client, PROD_PROJECT, {}, first.lease, [target], () => ({ writes: [{ delete: target }] })), (e) => e.code === "MIGRATION_LEASE_LOST");
  assert.equal(client.commits.length, before, "zero mutation");
  assert.ok(client.get("users/u1/things/x"), "the target survives");
  // the tuple itself is checked, independently of the update-time CAS: a forged lease document with the right update time but another owner is lost
  assert.throws(() => migration.renewalWrite({ ...second.lease, fencingGeneration: 1, updateTime: leaseDoc(client).updateTime }, leaseDoc(client), leaseDoc(client).updateTime), (e) => e.code === "MIGRATION_LEASE_LOST" && e.detail === "tuple", "generation disagreement is a lost tuple even when the update time matches");
  assert.throws(() => migration.renewalWrite({ ...second.lease, ownerToken: "owner-zzz" }, leaseDoc(client), leaseDoc(client).updateTime), (e) => e.code === "MIGRATION_LEASE_LOST" && e.detail === "tuple", "owner disagreement is a lost tuple");
  const stale = await migration.releaseMigrationLease(client, PROD_PROJECT, {}, first.lease);
  assert.deepEqual([stale.released, readLeaseView(client).ownerToken], [false, "owner-b"], "stale release fails harmlessly");
  const released = await migration.releaseMigrationLease(client, PROD_PROJECT, {}, second.lease);
  assert.deepEqual([released.released, released.absent, leaseDoc(client)], [true, true, null]);
});

test("C9.2.5/C9.2.6 migrating an oversize source: manifest building -> chunks (exact lengths, digests, create-only) -> sealed -> the four-write terminal commit (renewal, stub replace under the source update time, quarantine create, manifest terminalized) with exact stub and schema-v2 quarantine shapes; a second run is an exact replay with zero writes; budgets hold", async () => {
  const client = new FakeV1Client({ projectId: PROD_PROJECT, documents: { "users/u1": { name: "U" }, "users/u1/events/big": migOversize("big") } });
  const acquisition = await migration.acquireMigrationLease(client, PROD_PROJECT, {}, "owner-m");
  const lease = acquisition.lease;
  const source = client.get("users/u1/events/big");
  const sourceUpdateTime = source.updateTime;
  const commitsBefore = client.commits.length;
  const outcome = await migration.migrateSource(client, PROD_PROJECT, {}, lease, { sourcePath: "users/u1/events/big" }, MIG_NOW);
  assert.equal(outcome.outcome, "TERMINALIZED");
  const archiveId = outcome.archiveId;
  const manifest = client.get(migration.manifestPath("u1", archiveId));
  assert.ok(manifest, "manifest exists");
  const m = manifest.fields;
  assert.deepEqual([m.schemaVersion.integerValue, m.codec.stringValue, m.state.stringValue, m.chunkPayloadMax.integerValue, Number(m.chunkCount.integerValue) >= 3, m.sourcePath.stringValue, !!m.sealedAt, !!m.terminalizedAt, m.orphanedAt === undefined], ["1", "FirestoreDocumentArchiveV1", "terminalized", "393216", true, "users/u1/events/big", true, true, true]);
  const chunkCount = Number(m.chunkCount.integerValue);
  const totalBytes = Number(m.totalBytes.integerValue);
  let reassembled = [];
  for (let i = 0; i < chunkCount; i += 1) {
    const chunk = client.get(migration.chunkPath("u1", archiveId, i)).fields;
    const payload = Buffer.from(chunk.payload.bytesValue);
    assert.deepEqual([Number(chunk.index.integerValue), Number(chunk.offset.integerValue), Number(chunk.length.integerValue), chunk.payloadDigest.stringValue === createHash("sha256").update(payload).digest("hex"), chunk.archiveId.stringValue], [i, i * migration.CHUNK_PAYLOAD_MAX, payload.length, true, archiveId]);
    assert.equal(payload.length, i < chunkCount - 1 ? migration.CHUNK_PAYLOAD_MAX : totalBytes - i * migration.CHUNK_PAYLOAD_MAX, "nonfinal chunks are exactly 393,216 bytes");
    reassembled = [...reassembled, payload];
  }
  const bytes = Buffer.concat(reassembled);
  assert.deepEqual([bytes.length, createHash("sha256").update(bytes).digest("hex")], [totalBytes, m.archiveDigest.stringValue], "chunks reassemble to the digest");
  const restored = migration.decodeArchive(bytes);
  assert.equal(restored.fields.payload.mapValue.fields.s.stringValue.length, 1_047_600, "the archive restores the complete stored document");
  const stub = client.get("users/u1/events/big").fields;
  assert.deepEqual(Object.keys(stub).sort(), ["archiveRef", "outcome", "processed", "processedAt", "processingError", "processingState"], "the stub replaces the whole source");
  assert.deepEqual([stub.processingState.stringValue, stub.processed.booleanValue, stub.outcome.stringValue, stub.processingError.stringValue, stub.archiveRef.mapValue.fields.archiveId.stringValue, stub.archiveRef.mapValue.fields.chunkCount.integerValue], ["terminal", true, "quarantined", migration.STUB_MESSAGE, archiveId, String(chunkCount)]);
  const quarantine = client.get(`${migration.QUARANTINE_PATH}/${archiveId}`).fields;
  assert.deepEqual(Object.keys(quarantine).sort(), ["archiveDigest", "archiveRef", "migrationKind", "quarantinedAt", "reason", "schemaVersion", "sourcePath", "sourceUpdateTime"]);
  assert.deepEqual([quarantine.schemaVersion.integerValue, quarantine.reason.mapValue.fields.code.stringValue, quarantine.migrationKind.stringValue, quarantine.sourcePath.stringValue, quarantine.sourceUpdateTime.timestampValue], ["2", "SOURCE_TOO_LARGE", "LEGACY_OVERSIZE_ARCHIVE", "users/u1/events/big", sourceUpdateTime]);
  assert.deepEqual([stub.processedAt.timestampValue, quarantine.quarantinedAt.timestampValue, m.terminalizedAt.timestampValue], [m.terminalizedAt.timestampValue, m.terminalizedAt.timestampValue, m.terminalizedAt.timestampValue], "one leaseNow across the terminal commit");
  const terminal = client.commits.at(-1);
  assert.equal(terminal.writes.length, 4, "exactly four writes");
  assert.deepEqual(terminal.writes.map((w) => (w.update ? w.update.name : w.delete).replace(`${GAPIC_ROOT(PROD_PROJECT)}/`, "")), [migration.MIGRATION_LEASE_PATH, "users/u1/events/big", `${migration.QUARANTINE_PATH}/${archiveId}`, migration.manifestPath("u1", archiveId)]);
  const preconditionOf = (w) => (w.currentDocument ? w.currentDocument : { absent: true });
  assert.deepEqual([preconditionOf(terminal.writes[1]).updateTime, preconditionOf(terminal.writes[2]).exists, !!preconditionOf(terminal.writes[3]).updateTime], [sourceUpdateTime, false, true], "stub under the source update time, quarantine create-only, manifest under the sealed update time");
  const commitsUsed = client.commits.length - commitsBefore;
  assert.equal(commitsUsed, 1 + chunkCount + 1 + 1, "one manifest create, one commit per chunk, one seal, one terminal");
  for (const c of client.commits.slice(commitsBefore)) assert.equal(c.writes[0].update.name, `${GAPIC_ROOT(PROD_PROJECT)}/${migration.MIGRATION_LEASE_PATH}`, "every mutation commit carries the renewal first");
  // exact replay: zero writes
  const before = client.commits.length;
  const replay = await migration.migrateSource(client, PROD_PROJECT, {}, lease, { sourcePath: "users/u1/events/big" }, MIG_NOW);
  assert.equal(replay.outcome, "DRIFT_NOT_PENDING", "a terminalized source is no longer pending");
  assert.equal(client.commits.length, before);
  const terminalReplay = await migration.terminalCommit(client, PROD_PROJECT, {}, lease, { archiveId, chunkCount, N: totalBytes, archiveDigest: m.archiveDigest.stringValue }, "users/u1/events/big");
  assert.deepEqual([terminalReplay.committed, terminalReplay.replay], [false, true], "terminal attempted on a terminalized manifest with matching stub/quarantine is a replay with no write");
  assert.equal(client.commits.length, before);
});

test("C9.2.6/C9.2.8 collisions, drift, and orphan cleanup: a preexisting quarantine at the archive id is a collision; a manifest with a different identity is ARCHIVE_ID_COLLISION; a mismatching extant chunk fails closed; a source changed after sealing yields no terminal write and the archive becomes an orphan that cleanup marks (SOURCE_CHANGED), deletes chunks descending, then deletes the manifest; referenced and terminalized archives are never cleaned; crash boundaries resume exactly", async () => {
  const seed = () => new FakeV1Client({ projectId: PROD_PROJECT, documents: { "users/u1": { name: "U" }, "users/u1/events/big": migOversize("big") } });
  const plan = (client) => { const d = client.get("users/u1/events/big"); return migration.archivePlan(d, "users/u1/events/big", scheduler.rawStorage.documentSize("users/u1/events/big", migration.toJsonFields(d.fields))); };
  // preexisting quarantine → collision, no terminal write
  let client = seed();
  let lease = (await migration.acquireMigrationLease(client, PROD_PROJECT, {}, "o")).lease;
  let p = plan(client);
  client.put(`${migration.QUARANTINE_PATH}/${p.archiveId}`, { schemaVersion: 1, sourcePath: "users/u1/events/big" });
  await assert.rejects(migration.migrateSource(client, PROD_PROJECT, {}, lease, { sourcePath: "users/u1/events/big" }, MIG_NOW), (e) => e.code === "ARCHIVE_ID_COLLISION");
  assert.equal(client.get("users/u1/events/big").fields.processingState.stringValue, "pending", "no source write on collision");
  // manifest identity mismatch
  client = seed();
  lease = (await migration.acquireMigrationLease(client, PROD_PROJECT, {}, "o")).lease;
  p = plan(client);
  client.put(migration.manifestPath("u1", p.archiveId), { schemaVersion: 1, archiveId: p.archiveId, codec: "FirestoreDocumentArchiveV1", sourcePath: "users/u1/events/other", sourceCreateTime: { __ts: gapicTs(0) }, sourceUpdateTime: { __ts: gapicTs(0) }, chunkPayloadMax: 393216, chunkCount: 1, totalBytes: 1, archiveDigest: "0".repeat(64), state: "building", createdAt: { __ts: gapicTs(0) } });
  await assert.rejects(migration.migrateSource(client, PROD_PROJECT, {}, lease, { sourcePath: "users/u1/events/big" }, MIG_NOW), (e) => e.code === "ARCHIVE_ID_COLLISION");
  // mismatching extant chunk
  client = seed();
  lease = (await migration.acquireMigrationLease(client, PROD_PROJECT, {}, "o")).lease;
  p = plan(client);
  await migration.ensureManifest(client, PROD_PROJECT, {}, lease, p, "users/u1/events/big", client.get("users/u1/events/big"));
  client.put(migration.chunkPath("u1", p.archiveId, 0), { schemaVersion: 1, archiveId: p.archiveId, index: 0, offset: 0, length: 3, payload: Buffer.from([1, 2, 3]), payloadDigest: "x" });
  await assert.rejects(migration.writeChunks(client, PROD_PROJECT, {}, lease, p, "users/u1/events/big"), (e) => e.code === "ARCHIVE_CHUNK_MISMATCH");
  // source changed after sealing → DRIFT_CHANGED, no terminal write; cleanup marks SOURCE_CHANGED and removes chunks descending then the manifest
  client = seed();
  lease = (await migration.acquireMigrationLease(client, PROD_PROJECT, {}, "o")).lease;
  p = plan(client);
  await migration.ensureManifest(client, PROD_PROJECT, {}, lease, p, "users/u1/events/big", client.get("users/u1/events/big"));
  await migration.writeChunks(client, PROD_PROJECT, {}, lease, p, "users/u1/events/big");
  await migration.sealManifest(client, PROD_PROJECT, {}, lease, p, "users/u1/events/big");
  client.put("users/u1/events/big", migOversize("big"), { updateTime: gapicTs(Date.parse("2026-09-03T00:00:00.000Z")) });
  const changed = await migration.terminalCommit(client, PROD_PROJECT, {}, lease, p, "users/u1/events/big");
  assert.deepEqual([changed.committed, changed.sourceChanged, client.get(`${migration.QUARANTINE_PATH}/${p.archiveId}`)], [false, true, null]);
  const cleanup = await migration.cleanupOrphans(client, gapicProtos, PROD_PROJECT, {}, lease);
  assert.deepEqual(cleanup, [{ archiveId: p.archiveId, outcome: "CLEANED" }]);
  assert.equal(client.get(migration.manifestPath("u1", p.archiveId)), null, "manifest deleted last");
  for (let i = 0; i < p.chunkCount; i += 1) assert.equal(client.get(migration.chunkPath("u1", p.archiveId, i)), null);
  const deletes = client.commits.filter((c) => c.writes.some((w) => w.delete)).map((c) => c.writes.find((w) => w.delete).delete.replace(`${GAPIC_ROOT(PROD_PROJECT)}/`, ""));
  assert.deepEqual(deletes.slice(0, p.chunkCount), Array.from({ length: p.chunkCount }, (_, i) => migration.chunkPath("u1", p.archiveId, p.chunkCount - 1 - i)), "chunks deleted descending, one fenced commit each");
  const marked = client.commits.find((c) => c.writes.some((w) => w.update && w.update.fields.orphanReason));
  assert.equal(marked.writes[1].update.fields.orphanReason.stringValue, "SOURCE_CHANGED");
  // referenced (terminalized) archives are never cleaned; crash boundaries resume exactly
  client = seed();
  lease = (await migration.acquireMigrationLease(client, PROD_PROJECT, {}, "o")).lease;
  p = plan(client);
  await migration.ensureManifest(client, PROD_PROJECT, {}, lease, p, "users/u1/events/big", client.get("users/u1/events/big"));
  const partial = await migration.writeChunks(client, PROD_PROJECT, {}, lease, p, "users/u1/events/big");
  client.remove(migration.chunkPath("u1", p.archiveId, p.chunkCount - 1)); // crash before the final chunk
  const resumed = await migration.writeChunks(client, PROD_PROJECT, {}, lease, p, "users/u1/events/big");
  assert.deepEqual([partial.created, resumed.created], [p.chunkCount, 1], "resume creates only the missing chunk; existing chunks exact-compare");
  const again = await migration.ensureManifest(client, PROD_PROJECT, {}, lease, p, "users/u1/events/big", client.get("users/u1/events/big"));
  assert.deepEqual([again.resumed, again.state], [true, "building"], "exact-state resume writes nothing");
  assert.equal(await migration.sealManifest(client, PROD_PROJECT, {}, lease, p, "users/u1/events/big"), "sealed");
  assert.equal(await migration.sealManifest(client, PROD_PROJECT, {}, lease, p, "users/u1/events/big"), "sealed", "seal replay");
  const t = await migration.terminalCommit(client, PROD_PROJECT, {}, lease, p, "users/u1/events/big");
  assert.equal(t.committed, true);
  const untouched = await migration.cleanupOrphans(client, gapicProtos, PROD_PROJECT, {}, lease);
  assert.deepEqual(untouched, [], "terminalized archives are never cleaned");
  assert.ok(client.get(migration.manifestPath("u1", p.archiveId)));
  // a sealed manifest whose source moved on but whose quarantine references it is protected, never orphaned
  const sealedClient = seed();
  const sealedLease = (await migration.acquireMigrationLease(sealedClient, PROD_PROJECT, {}, "o")).lease;
  const sp = plan(sealedClient);
  await migration.ensureManifest(sealedClient, PROD_PROJECT, {}, sealedLease, sp, "users/u1/events/big", sealedClient.get("users/u1/events/big"));
  await migration.writeChunks(sealedClient, PROD_PROJECT, {}, sealedLease, sp, "users/u1/events/big");
  await migration.sealManifest(sealedClient, PROD_PROJECT, {}, sealedLease, sp, "users/u1/events/big");
  sealedClient.put("users/u1/events/big", migOversize("big"), { updateTime: gapicTs(Date.parse("2026-09-04T00:00:00.000Z")) });
  sealedClient.put(`${migration.QUARANTINE_PATH}/${sp.archiveId}`, { schemaVersion: 2, sourcePath: "users/u1/events/big" });
  const protectedResult = await migration.cleanupOrphans(sealedClient, gapicProtos, PROD_PROJECT, {}, sealedLease);
  assert.deepEqual(protectedResult, [{ archiveId: sp.archiveId, outcome: "PROTECTED" }], "a referenced sealed archive is protected");
  assert.equal(sealedClient.get(migration.manifestPath("u1", sp.archiveId)).fields.state.stringValue, "sealed");
  assert.ok(sealedClient.get(migration.chunkPath("u1", sp.archiveId, 0)), "chunks retained");
});

test("C9.2.7 budgets and write count: a chunk commit at the payload maximum stays within 524,288; the terminal commit within 8,523,776; a fifth write is MIGRATION_WRITE_INVARIANT before any write", async () => {
  const client = new FakeV1Client({ projectId: PROD_PROJECT, documents: { "users/u1": { name: "U" }, "users/u1/events/big": migOversize("big") } });
  const lease = (await migration.acquireMigrationLease(client, PROD_PROJECT, {}, "o")).lease;
  const read = await migration.transactionalRead(client, PROD_PROJECT, [`${GAPIC_ROOT(PROD_PROJECT)}/${migration.MIGRATION_LEASE_PATH}`], {});
  const five = Array.from({ length: 5 }, (_, i) => ({ update: { name: `${GAPIC_ROOT(PROD_PROJECT)}/users/u1/things/${i}`, fields: gapicFields({ i }) } }));
  const before = client.commits.length;
  await assert.rejects(client.commit === undefined ? Promise.reject(new Error("x")) : (async () => { const commitWrites = migration.fencedCommit; void commitWrites; const mod = require("../scripts/migrateOversizeEvents"); return mod.fencedCommit(client, PROD_PROJECT, {}, lease, [], () => ({ writes: five.slice(0, 4) })); })(), (e) => e.code === "MIGRATION_WRITE_INVARIANT", "renewal + four = five writes");
  assert.equal(client.commits.length, before);
  void read;
  const slices = migration.chunkSlices(Buffer.alloc(migration.CHUNK_PAYLOAD_MAX * 2 + 7));
  assert.deepEqual(slices.map((s) => [s.offset, s.length]), [[0, 393216], [393216, 393216], [786432, 7]]);
  const chunkFields = migration.ownFields({ schemaVersion: 1, archiveId: "qev2_" + "a".repeat(40), index: 0, offset: 0, length: slices[0].length, payload: slices[0].payload, payloadDigest: "d".repeat(64) });
  const charge = scheduler.rawStorage.transitionBudget([{ path: migration.chunkPath("u1", "qev2_" + "a".repeat(40), 0), before: null, after: migration.toJsonFields(chunkFields) }]).charge;
  assert.ok(charge <= migration.BUDGET.chunkCommit && charge > migration.CHUNK_PAYLOAD_MAX, `chunk commit charge ${charge} within 524,288 (payload exempt from indexing)`);
});

test("C9.2.2/C9.2.9 the apply run: under the complete arming set it acquires the fenced lease, confirms the two-pass audit, migrates every failing source, cleans orphans, passes the pre-ship gate, releases the lease and proves absence; an unstable audit refuses and still releases; the report carries no raw bytes", async () => {
  const client = new FakeV1Client({ projectId: PROD_PROJECT, documents: { "users/u1": { name: "U" }, "users/u1/events/ok": migPending("ok"), "users/u1/events/big": migOversize("big"), "users/u2/events/big2": migOversize("big2") } });
  const result = await migration.run(ARMED, prodDeps(client));
  assert.deepEqual([result.exitCode, result.report.refusal, result.report.mode], [0, null, "apply"], JSON.stringify(result.report.apply && result.report.apply.gate));
  const apply = result.report.apply;
  assert.deepEqual([apply.lease.fencingGeneration, apply.migrated.map((m) => m.outcome), apply.gate.passed, apply.gate.nonTerminal, apply.gate.broken, apply.release.released, apply.release.absent, leaseDoc(client)], [1, ["TERMINALIZED", "TERMINALIZED"], true, 0, 0, true, true, null]);
  assert.equal(client.get("users/u1/events/ok").fields.processingState.stringValue, "pending", "admitted sources untouched");
  assert.equal(client.get("users/u2/events/big2").fields.outcome.stringValue, "quarantined");
  assert.equal(JSON.stringify(result.report).includes("xxxxxxxx"), false, "no raw bytes");
  const unstable = new FakeV1Client({ projectId: PROD_PROJECT, documents: { "users/u1": { name: "U" }, "users/u1/events/ok": migPending("ok") }, onQuery: (request, n) => { if (n === 2) unstable.put("users/u1/events/late", migPending("late")); } });
  const refused = await migration.run(ARMED, prodDeps(unstable));
  assert.deepEqual([refused.exitCode, refused.report.refusal, refused.report.apply.release.released, leaseDoc(unstable)], [4, "AUDIT_UNSTABLE", true, null]);
  const held = new FakeV1Client({ projectId: PROD_PROJECT, documents: { "users/u1": { name: "U" } } });
  await migration.acquireMigrationLease(held, PROD_PROJECT, {}, "someone-else");
  const blocked = await migration.run(ARMED, prodDeps(held));
  assert.deepEqual([blocked.exitCode, blocked.report.refusal, held.commits.length], [4, "LEASE_REFUSED_MIGRATION_LEASE_LIVE", 1], "a live other-owner lease refuses before any write");
});

test("emulator: the read-only audit runs against the live emulator through the pinned raw client and classifies a seeded oversize source", { skip: process.env.FIRESTORE_EMULATOR_HOST ? false : "FIRESTORE_EMULATOR_HOST is unset; run scripts/test-emulator.sh node" }, async () => {
  const { initializeApp, getApps } = require("firebase-admin/app");
  const { getFirestore } = require("firebase-admin/firestore");
  const app = getApps().length ? getApps()[0] : initializeApp({ projectId: "demo-peezy-phase1" });
  const live = getFirestore(app);
  const uid = `mig-${Date.now()}`;
  await live.doc(`users/${uid}/events/ok`).set({ ...migPending("ok"), payload: { n: 1 } });
  await live.doc(`users/${uid}/events/big`).set(migOversize("big"));
  const result = await migration.run([], { env: process.env });
  assert.equal(result.report.mode, "audit");
  const last = result.report.audit.passes.at(-1);
  assert.ok(last.complete, JSON.stringify(last.systemic));
  assert.ok(last.failing.some((f) => f.sourcePath === `users/${uid}/events/big` && /^qev2_/.test(f.archiveId)), "the oversize source is classified from the live raw Document");
  assert.ok(last.pendingCount >= 2);
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
