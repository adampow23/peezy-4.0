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

test("lease excludes a live peer, permits expiry takeover, and stale release is harmless", async () => {
  const db = fakeTransactionDb();
  assert.equal(await acquireEvaluationLeaseInTransaction(db, "run-1", NOW), true);
  assert.equal(await acquireEvaluationLeaseInTransaction(db, "run-2", new Date(NOW.getTime() + 1)), false);
  const takeoverAt = new Date(NOW.getTime() + 10 * 60 * 1000 + 1);
  assert.equal(await acquireEvaluationLeaseInTransaction(db, "run-2", takeoverAt), true);
  assert.equal(await __private.releaseEvaluationLeaseInTransaction(db, "run-1"), false);
  assert.equal(db.documents.get("phase1System/dispositionTriggerLease").runId, "run-2");
  assert.equal(await __private.releaseEvaluationLeaseInTransaction(db, "run-2"), true);
  assert.equal(db.documents.has("phase1System/dispositionTriggerLease"), false);
});

test("date scan executes the exact 201 query and reaches row 201 across a restart", async () => {
  const dueAt = new Date("2026-08-27T16:00:00.000Z");
  const documents = {
    "phase1System/dispositionTriggerLease": {
      runId: "run-date-1",
      expiresAt: new Date(NOW.getTime() + 60_000)
    }
  };
  for (let index = 0; index < 200; index += 1) {
    const uid = `u${String(index).padStart(3, "0")}`;
    documents[`users/${uid}/tasks/shared-leaf`] = deferredDate(dueAt, true);
  }
  const validPath = "users/z-user/tasks/shared-leaf";
  documents[validPath] = deferredDate(dueAt, false);
  const db = queryAwareDb(documents);

  const first = await __private.processDateTasks(db, NOW, "run-date-1");
  assert.deepEqual(first, { scanned: 200, woke: 0 });
  assert.deepEqual(db.queryLog[0], {
    group: "tasks",
    wheres: [
      ["status", "==", "Snoozed"],
      ["dispositionContract.next_trigger.kind", "==", "date"],
      ["dispositionContract.next_trigger.at", "<=", NOW]
    ],
    orders: [
      ["dispositionContract.next_trigger.at", "asc"],
      ["__name__", "asc"]
    ],
    limit: 201,
    startAfter: []
  });
  const saved = db.documents.get("phase1System/dispositionTriggerState");
  assert.equal(saved.dateAfterPath, "users/u199/tasks/shared-leaf");
  assert.equal(saved.dateAfterAt, dueAt);

  db.documents.set("phase1System/dispositionTriggerLease", {
    runId: "run-date-2",
    expiresAt: new Date(NOW.getTime() + 60_000)
  });
  const second = await __private.processDateTasks(db, NOW, "run-date-2");
  assert.deepEqual(second, { scanned: 1, woke: 1 });
  assert.deepEqual(db.queryLog[1].startAfter, [dueAt, "users/u199/tasks/shared-leaf"]);
  assert.equal(db.documents.get(validPath).status, "Upcoming");
  assert.equal("dateAfterPath" in db.documents.get("phase1System/dispositionTriggerState"), false);

  db.documents.set("phase1System/dispositionTriggerLease", {
    runId: "run-date-3",
    expiresAt: new Date(NOW.getTime() + 60_000)
  });
  const wrapped = await __private.processDateTasks(db, NOW, "run-date-3");
  assert.deepEqual(wrapped, { scanned: 200, woke: 0 });
  assert.deepEqual(db.queryLog[2].startAfter, []);
});

test("event scan terminalizes 100 poison rows so row 101 advances next run", async () => {
  const documents = {};
  for (let index = 0; index < 100; index += 1) {
    const uid = `u${String(index).padStart(3, "0")}`;
    documents[`users/${uid}/events/shared-leaf`] = event({
      event_id: "shared-leaf",
      observed_at: undefined
    });
  }
  const validPath = "users/z-user/events/valid-event";
  documents[validPath] = event({ event_id: "valid-event" });
  const db = queryAwareDb(documents);

  const first = await __private.processEvents(db, NOW, "unused-run");
  assert.equal(first.scanned, 100);
  assert.deepEqual(new Set(first.outcomes), new Set(["quarantined"]));
  assert.deepEqual(db.queryLog[0], {
    group: "events",
    wheres: [["processingState", "==", "pending"]],
    orders: [["__name__", "asc"]],
    limit: 101,
    startAfter: []
  });
  assert.equal([...db.documents.values()].filter((data) => data.outcome === "quarantined").length, 100);
  assert.equal(db.documents.get(validPath).processingState, "pending");

  const second = await __private.processEvents(db, NOW, "unused-run");
  assert.equal(second.scanned, 1);
  assert.deepEqual(second.outcomes, ["advance"]);
  assert.equal(db.documents.get(validPath).processingState, "terminal");
  const stateId = canonicalEventStateId("institution.updated", "service/provider-1");
  assert.equal(db.documents.get(`users/z-user/eventState/${stateId}`).event_id, "valid-event");
});

test("more than 100 mixed terminal outcomes leave the query before a following valid event", async () => {
  const documents = {};
  const expectedOutcomes = { stale: 0, duplicate: 0, version_conflict: 0 };
  for (let index = 0; index < 120; index += 1) {
    const uid = `u${String(index).padStart(3, "0")}`;
    const eventId = `event-${String(index).padStart(3, "0")}`;
    const canonicalKey = `service/provider-${index}`;
    const mode = ["stale", "duplicate", "version_conflict"][index % 3];
    const data = event({
      event_id: eventId,
      canonical_key: canonicalKey,
      source_version: mode === "stale" ? 1 : 2
    });
    documents[`users/${uid}/events/${eventId}`] = data;
    const stateId = canonicalEventStateId("institution.updated", canonicalKey);
    documents[`users/${uid}/eventState/${stateId}`] = {
      event_name: "institution.updated",
      canonical_key: canonicalKey,
      source_version: 2,
      effect: "fire",
      fingerprint: mode === "duplicate"
        ? __private.fingerprintCanonicalEnvelope(canonicalEventEnvelope(data, eventId))
        : "0".repeat(64)
    };
    expectedOutcomes[mode] += 1;
  }
  const validPath = "users/z-user/events/valid-after-terminal-pages";
  documents[validPath] = event({
    event_id: "valid-after-terminal-pages",
    canonical_key: "service/final",
    source_version: 7
  });
  const db = queryAwareDb(documents);

  const first = await __private.processEvents(db, NOW, "unused-run");
  assert.equal(first.scanned, 100);
  assert.deepEqual(new Set(first.outcomes), new Set(["stale", "duplicate", "version_conflict"]));
  assert.equal(db.documents.get(validPath).processingState, "pending");

  const second = await __private.processEvents(db, NOW, "unused-run");
  assert.equal(second.scanned, 21);
  assert.equal(second.outcomes.at(-1), "advance");
  assert.equal(db.documents.get(validPath).processingState, "terminal");
  const actualOutcomes = { stale: 0, duplicate: 0, version_conflict: 0 };
  for (const data of db.documents.values()) {
    if (Object.hasOwn(actualOutcomes, data.outcome)) actualOutcomes[data.outcome] += 1;
  }
  assert.deepEqual(actualOutcomes, expectedOutcomes);
  assert.equal(
    [...db.documents.values()].filter((data) => data.processingState === "pending").length,
    0
  );
  assert.deepEqual(db.queryLog.map((query) => query.limit), [101, 101]);
});

test("event-task scan uses full paths and reaches row 201 behind duplicate leaf poison", async () => {
  const documents = {
    "phase1System/dispositionTriggerLease": {
      runId: "run-event-1",
      expiresAt: new Date(NOW.getTime() + 60_000)
    }
  };
  for (let index = 0; index < 200; index += 1) {
    const uid = `u${String(index).padStart(3, "0")}`;
    documents[`users/${uid}/tasks/shared-leaf`] = deferredEvent("never-matches");
  }
  const validPath = "users/z-user/tasks/shared-leaf";
  documents[validPath] = deferredEvent();
  const stateId = canonicalEventStateId("institution.updated", "service/provider-1");
  documents[`users/z-user/eventState/${stateId}`] = {
    event_name: "institution.updated",
    canonical_key: "service/provider-1",
    source_version: 2,
    effect: "fire"
  };
  const db = queryAwareDb(documents);

  const first = await __private.processEventTasks(db, NOW, "run-event-1");
  assert.deepEqual(first, { scanned: 200, woke: 0 });
  assert.deepEqual(db.queryLog[0], {
    group: "tasks",
    wheres: [
      ["status", "==", "Snoozed"],
      ["dispositionContract.next_trigger.kind", "==", "event"]
    ],
    orders: [["__name__", "asc"]],
    limit: 201,
    startAfter: []
  });
  assert.equal(
    db.documents.get("phase1System/dispositionTriggerState").eventTaskAfterPath,
    "users/u199/tasks/shared-leaf"
  );

  db.documents.set("phase1System/dispositionTriggerLease", {
    runId: "run-event-2",
    expiresAt: new Date(NOW.getTime() + 60_000)
  });
  const second = await __private.processEventTasks(db, NOW, "run-event-2");
  assert.deepEqual(second, { scanned: 1, woke: 1 });
  assert.deepEqual(db.queryLog[1].startAfter, ["users/u199/tasks/shared-leaf"]);
  assert.equal(db.documents.get(validPath).status, "Upcoming");
  assert.equal("eventTaskAfterPath" in db.documents.get("phase1System/dispositionTriggerState"), false);

  const wrappedPath = "users/a-new/tasks/shared-leaf";
  db.documents.set(wrappedPath, deferredEvent());
  db.documents.set(`users/a-new/eventState/${stateId}`, {
    event_name: "institution.updated",
    canonical_key: "service/provider-1",
    source_version: 2,
    effect: "fire"
  });
  db.documents.set("phase1System/dispositionTriggerLease", {
    runId: "run-event-3",
    expiresAt: new Date(NOW.getTime() + 60_000)
  });
  const wrapped = await __private.processEventTasks(db, NOW, "run-event-3");
  assert.deepEqual(wrapped, { scanned: 200, woke: 1 });
  assert.deepEqual(db.queryLog[2].startAfter, []);
  assert.equal(db.documents.get(wrappedPath).status, "Upcoming");
});

test("cursor writes reject a non-owner runId even when the query is empty", async () => {
  const db = queryAwareDb({
    "phase1System/dispositionTriggerLease": {
      runId: "live-owner",
      expiresAt: new Date(NOW.getTime() + 60_000)
    }
  });
  await assert.rejects(
    __private.processDateTasks(db, NOW, "stale-owner"),
    /lease is no longer owned/
  );
  await assert.rejects(
    __private.processEventTasks(db, NOW, "stale-owner"),
    /lease is no longer owned/
  );
  assert.equal(db.documents.has("phase1System/dispositionTriggerState"), false);
});

test("full evaluator executes all scans, reconciles same-run events, and releases its lease", async () => {
  const duePath = "users/a-user/tasks/date-task";
  const eventTaskPath = "users/a-user/tasks/event-task";
  const eventPath = "users/a-user/events/event-2";
  const db = queryAwareDb({
    [duePath]: deferredDate(new Date("2026-08-27T16:00:00.000Z")),
    [eventTaskPath]: deferredEvent(),
    [eventPath]: event()
  });
  const result = await runDispositionTriggerEvaluation(db, NOW);
  assert.deepEqual(result.dates, { scanned: 1, woke: 1 });
  assert.equal(result.events.scanned, 1);
  assert.deepEqual(result.events.outcomes, ["advance"]);
  assert.deepEqual(result.eventTasks, { scanned: 1, woke: 1 });
  assert.equal(db.documents.get(duePath).status, "Upcoming");
  assert.equal(db.documents.get(eventTaskPath).status, "Upcoming");
  assert.equal(db.documents.get(eventPath).processingState, "terminal");
  assert.equal(db.documents.has("phase1System/dispositionTriggerLease"), false);
  assert.deepEqual(db.queryLog.map((query) => [query.group, query.limit]), [
    ["tasks", 201],
    ["events", 101],
    ["tasks", 201]
  ]);
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

test("factory handler invokes only its injected evaluator", async () => {
  const calls = [];
  const db = { marker: "fake" };
  const handler = makeDispositionTriggerHandler({
    dbFactory: () => db,
    nowFactory: () => NOW,
    evaluator: async (actualDb, actualNow) => {
      calls.push([actualDb, actualNow]);
      return { processed: 1 };
    }
  });
  assert.deepEqual(await handler(), { processed: 1 });
  assert.deepEqual(calls, [[db, NOW]]);
});

test("production export is a v2 scheduler endpoint with locked metadata", () => {
  assert.equal(typeof evaluateDispositionTriggers, "function");
  assert.equal(typeof evaluateDispositionTriggers.run, "function");
  const endpoint = evaluateDispositionTriggers.__endpoint;
  assert.equal(endpoint.platform, "gcfv2");
  assert.equal(endpoint.scheduleTrigger.schedule, "every 15 minutes");
  assert.deepEqual(endpoint.region, ["us-central1"]);
  assert.equal(endpoint.timeoutSeconds, 540);
  assert.equal(endpoint.availableMemoryMb, 512);
  assert.equal(endpoint.maxInstances, 1);
  assert.equal(endpoint.concurrency, 1);
  assert.equal(endpoint.scheduleTrigger.retryConfig.retryCount, 0);
});

test("index and Firebase config exactly declare scheduler query indexes", () => {
  const root = path.resolve(__dirname, "../..");
  const indexes = JSON.parse(fs.readFileSync(path.join(root, "firestore.indexes.json"), "utf8"));
  assert.deepEqual(indexes, {
    indexes: [
      {
        collectionGroup: "tasks",
        queryScope: "COLLECTION_GROUP",
        fields: [
          { fieldPath: "status", order: "ASCENDING" },
          { fieldPath: "dispositionContract.next_trigger.kind", order: "ASCENDING" },
          { fieldPath: "dispositionContract.next_trigger.at", order: "ASCENDING" }
        ]
      },
      {
        collectionGroup: "tasks",
        queryScope: "COLLECTION_GROUP",
        fields: [
          { fieldPath: "status", order: "ASCENDING" },
          { fieldPath: "dispositionContract.next_trigger.kind", order: "ASCENDING" }
        ]
      }
    ],
    fieldOverrides: [
      {
        collectionGroup: "events",
        fieldPath: "processingState",
        indexes: [{ order: "ASCENDING", queryScope: "COLLECTION_GROUP" }]
      }
    ]
  });
  const firebase = JSON.parse(fs.readFileSync(path.join(root, "firebase.json"), "utf8"));
  assert.equal(firebase.firestore.rules, "firestore.rules");
  assert.equal(firebase.firestore.indexes, "firestore.indexes.json");
});

test("module has no notification dependency", () => {
  const source = fs.readFileSync(path.resolve(__dirname, "../dispositionTriggers.js"), "utf8");
  assert.doesNotMatch(source, /notify|messaging|push/i);
});
