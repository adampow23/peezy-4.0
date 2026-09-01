"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { Timestamp } = require("firebase-admin/firestore");

const {
  canonicalAmendmentId,
  deleteResetPage,
  executeFinalizeReset,
  finishResetDeletion,
  handleTaskPlanRequest,
  validateTaskPlanRequest,
  operationFingerprint,
  resetFingerprint
} = require("../taskPlan");
const { buildUserActionContract, validateDispositionContract } = require("../dispositionContract");

const NOW = new Date("2026-08-27T12:00:00.000Z");

function futureTrigger(overrides = {}) {
  return {
    kind: "date",
    at: new Date("2026-09-10T12:00:00.000Z"),
    payload: { basis: "institution_promised_date", source_evidence_id: "ev-1" },
    fired: false,
    ...overrides
  };
}

function replacement(overrides = {}) {
  return {
    taskId: "AMEND_BANK",
    subject: { kind: "service", id: "row-bank" },
    institutionId: "mapkit:bank",
    institution: "Bank Co",
    amendmentAction: {
      nextTrigger: futureTrigger({ payload: { basis: "institution_promised_date", source_evidence_id: "amend-ev" } }),
      resumeDestination: "bank/amend"
    },
    verification: {
      nextTrigger: futureTrigger({ payload: { basis: "recipient_acceptance_date", source_evidence_id: "verify-ev" } }),
      resumeDestination: "bank/verify"
    },
    ...overrides
  };
}

function request(action, overrides = {}) {
  return {
    auth: { uid: "u1" },
    data: {
      action,
      taskId: "original",
      reason: "Changed plan",
      operationId: `${action}-operation`,
      ...overrides
    }
  };
}

function isDeleteValue(value) {
  return value?.constructor?.name === "DeleteTransform";
}

function cloneTestValue(value) {
  if (value === null || typeof value !== "object") return value;
  if (value instanceof Date) return new Date(value.getTime());
  if (typeof value.toDate === "function") return Timestamp.fromDate(value.toDate());
  if (Array.isArray(value)) return value.map(cloneTestValue);
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, cloneTestValue(item)]));
}

function firestoreRoundTrip(value) {
  if (value === null || typeof value !== "object") return value;
  if (value instanceof Date) return Timestamp.fromDate(value);
  if (typeof value.toDate === "function") return Timestamp.fromDate(value.toDate());
  if (Array.isArray(value)) return value.map(firestoreRoundTrip);
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, firestoreRoundTrip(item)]));
}

function roundTripDocuments(db) {
  for (const [path, data] of db.docs) db.docs.set(path, firestoreRoundTrip(data));
}

function applyUpdate(target, update) {
  const next = cloneTestValue(target || {});
  for (const [key, value] of Object.entries(update)) {
    const parts = key.split(".");
    let cursor = next;
    for (const part of parts.slice(0, -1)) {
      cursor[part] = cursor[part] && typeof cursor[part] === "object" ? cursor[part] : {};
      cursor = cursor[part];
    }
    const leaf = parts.at(-1);
    if (isDeleteValue(value)) delete cursor[leaf];
    else cursor[leaf] = cloneTestValue(value);
  }
  return next;
}

function fakeDb(initial = {}, { failCommit = false, failListCall = 0 } = {}) {
  const docs = new Map(Object.entries(initial).map(([path, data]) => [path, cloneTestValue(data)]));
  const writes = [];
  const reads = [];
  let auto = 0;
  let listCalls = 0;
  const collection = (path) => ({
    path,
    doc(id) {
      const docId = id ?? `auto-${++auto}`;
      const docPath = `${path}/${docId}`;
      return {
        id: docId,
        path: docPath,
        collection: (name) => collection(`${docPath}/${name}`)
      };
    },
    limit(count) {
      return { path: `${path}?limit=${count}`, collectionPath: path, limitCount: count };
    }
  });
  const snapshot = (ref) => {
    const data = docs.get(ref.path);
    reads.push(ref.path);
    return {
      exists: data !== undefined,
      data: () => data === undefined ? undefined : cloneTestValue(data),
      get: (field) => data?.[field],
      ref
    };
  };
  const db = {
    docs,
    reads,
    writes,
    collection,
    __phase1ListTaskRefs(userRef, limit) {
      listCalls += 1;
      if (failListCall === listCalls) throw new Error("injected crash after committed reset page");
      const prefix = `${userRef.path}/tasks/`;
      return [...docs.keys()]
        .filter((path) => path.startsWith(prefix) && !path.slice(prefix.length).includes("/"))
        .sort()
        .slice(0, limit)
        .map((path) => ({ id: path.split("/").at(-1), path }));
    },
    async runTransaction(callback) {
      const ops = [];
      const transaction = {
        get: async (ref) => {
          if (ref.collectionPath) {
            const prefix = `${ref.collectionPath}/`;
            const rows = [...docs.entries()]
              .filter(([path]) => path.startsWith(prefix) && !path.slice(prefix.length).includes("/"))
              .sort(([left], [right]) => left.localeCompare(right))
              .slice(0, ref.limitCount)
              .map(([path, data]) => ({
                ref: { id: path.split("/").at(-1), path },
                data: () => cloneTestValue(data)
              }));
            reads.push(ref.path);
            return { empty: rows.length === 0, docs: rows };
          }
          return snapshot(ref);
        },
        create: (ref, data) => ops.push({ type: "create", path: ref.path, data }),
        set: (ref, data, options) => ops.push({ type: "set", path: ref.path, data, options }),
        update: (ref, data) => ops.push({ type: "update", path: ref.path, data }),
        delete: (ref) => ops.push({ type: "delete", path: ref.path })
      };
      const result = await callback(transaction);
      if (failCommit && ops.length) throw new Error("injected commit failure");
      const next = new Map(docs);
      for (const op of ops) {
        if (op.type === "create" && next.has(op.path)) throw new Error(`already exists: ${op.path}`);
        if (op.type === "update" && !next.has(op.path)) throw new Error(`missing: ${op.path}`);
        if (op.type === "delete") next.delete(op.path);
        else if (op.type === "update" || op.options?.merge) {
          next.set(op.path, applyUpdate(next.get(op.path), op.data));
        } else {
          next.set(op.path, cloneTestValue(op.data));
        }
      }
      docs.clear();
      for (const [path, data] of next) docs.set(path, data);
      writes.push(...ops);
      return result;
    }
  };
  return db;
}

function userContract({ external = false } = {}) {
  return buildUserActionContract({}, {
    owner: "user:u1",
    nextAction: "Finish original",
    nextTrigger: futureTrigger(),
    resumeDestination: "original/finish",
    visibleStatusCopy: "Finish original",
    externalSubmission: external
  }, NOW);
}

test("task-plan module exposes the authenticated transactional seams", () => {
  assert.equal(typeof canonicalAmendmentId, "function");
  assert.equal(typeof handleTaskPlanRequest, "function");
  assert.equal(typeof validateTaskPlanRequest, "function");
});

test("auth and every malformed request fail before database creation", async (t) => {
  const cases = [
    { auth: null, data: request("supersede").data },
    request("unknown"),
    request("supersede", { operationId: "bad/id" }),
    request("supersede", { reason: " " }),
    request("supersede", { replacement: replacement({ institutionId: "" }) }),
    request("supersede", { replacement: replacement({ amendmentAction: { resumeDestination: "x" } }) }),
    request("resetAllTasks", { taskId: undefined, reason: "wrong" })
  ];
  for (const [index, value] of cases.entries()) {
    await t.test(`invalid ${index}`, async () => {
      let factoryCalls = 0;
      await assert.rejects(
        handleTaskPlanRequest(value, () => { factoryCalls += 1; return fakeDb(); }, NOW),
        (error) => ["unauthenticated", "invalid-argument"].includes(error.code)
      );
      assert.equal(factoryCalls, 0);
    });
  }
});

test("internal supersede, operation replay, drift, and reopen are closed and atomic", async () => {
  const db = fakeDb({
    "users/u1/tasks/original": {
      id: "original",
      taskId: "ORIGINAL",
      status: "InProgress",
      dispositionContract: userContract(),
      unrelated: "keep"
    }
  });
  const supersede = request("supersede");
  const retired = await handleTaskPlanRequest(supersede, () => db, NOW);
  assert.deepEqual(retired, {
    taskId: "original",
    status: "Dismissed",
    replacementTaskId: null,
    lifecycleState: "retired",
    revision: 1,
    replayed: false
  });
  const task = db.docs.get("users/u1/tasks/original");
  assert.equal(task.unrelated, "keep");
  assert.equal(task.planChangeState, "retired");
  assert.equal(task.dispositionContract.terminal_kind, "retired");
  assert.equal("superseded_by" in task.dispositionContract, false);
  assert.equal(validateDispositionContract(task.status, task.dispositionContract, NOW), true);

  db.docs.delete("users/u1/tasks/original");
  db.docs.set("users/u1", { taskReset: { state: "deleting", operationId: "another-reset" } });
  const replay = await handleTaskPlanRequest(supersede, () => db, NOW);
  assert.equal(replay.replayed, true);
  await assert.rejects(
    handleTaskPlanRequest(request("supersede", { reason: "Drift" }), () => db, NOW),
    (error) => error.code === "failed-precondition"
  );

  db.docs.delete("users/u1");
  db.docs.set("users/u1/tasks/original", task);
  const reopened = await handleTaskPlanRequest(request("reopen"), () => db, NOW);
  assert.equal(reopened.lifecycleState, "reopened");
  assert.equal(db.docs.get("users/u1/tasks/original").status, "InProgress");
  assert.deepEqual(db.docs.get("users/u1/tasks/original").dispositionContract, userContract());
});

test("pending reopen cancels only untouched amendment and a later cycle gets a distinct revision", async () => {
  const originalContract = userContract({ external: true });
  const db = fakeDb({
    "users/u1/tasks/original": {
      id: "original",
      taskId: "ORIGINAL",
      status: "InProgress",
      dispositionContract: originalContract
    },
    "taskCatalog/AMEND_BANK": { taskId: "AMEND_BANK", title: "Amend {institution}" },
    "users/u1/identity/identity": {}
  });
  const first = await handleTaskPlanRequest(
    request("supersede", { replacement: replacement(), operationId: "cycle-1" }),
    () => db,
    NOW
  );
  const firstPath = `users/u1/tasks/${first.replacementTaskId}`;
  roundTripDocuments(db);
  const reopened = await handleTaskPlanRequest(
    request("reopen", { operationId: "reopen-cycle-1" }),
    () => db,
    NOW
  );
  assert.equal(reopened.lifecycleState, "reopened");
  assert.deepEqual(db.docs.get("users/u1/tasks/original").dispositionContract, originalContract);
  assert.equal(db.docs.get(firstPath).status, "Dismissed");

  const second = await handleTaskPlanRequest(
    request("supersede", { replacement: replacement(), operationId: "cycle-2" }),
    () => db,
    NOW
  );
  assert.equal(second.revision, 2);
  assert.notEqual(second.replacementTaskId, first.replacementTaskId);
  assert.equal(db.docs.get(firstPath).status, "Dismissed");
});

test("pre-existing exact amendment with custom metadata fingerprints the accepted snapshot for reopen", async () => {
  const initial = {
    "users/u1/tasks/original": {
      id: "original", taskId: "ORIGINAL", status: "InProgress",
      dispositionContract: userContract({ external: true })
    },
    "taskCatalog/AMEND_BANK": { taskId: "AMEND_BANK", title: "Amend {institution}" },
    "users/u1/identity/identity": {}
  };
  const descriptor = replacement();
  const firstDb = fakeDb(initial);
  const first = await handleTaskPlanRequest(
    request("supersede", { replacement: descriptor, operationId: "build-reusable" }),
    () => firstDb,
    NOW
  );
  const amendmentPath = `users/u1/tasks/${first.replacementTaskId}`;
  const accepted = {
    ...cloneTestValue(firstDb.docs.get(amendmentPath)),
    customMetadata: { retained: true, value: 17 }
  };

  const reuseDb = fakeDb({ ...initial, [amendmentPath]: accepted });
  const reused = await handleTaskPlanRequest(
    request("supersede", { replacement: descriptor, operationId: "reuse-existing" }),
    () => reuseDb,
    NOW
  );
  assert.equal(reused.replacementTaskId, first.replacementTaskId);
  assert.deepEqual(reuseDb.docs.get(amendmentPath).customMetadata, {
    retained: true, value: 17
  });
  const reopened = await handleTaskPlanRequest(
    request("reopen", { operationId: "reopen-reused" }),
    () => reuseDb,
    NOW
  );
  assert.equal(reopened.lifecycleState, "reopened");
  assert.equal(reuseDb.docs.get(amendmentPath).status, "Dismissed");
  assert.deepEqual(reuseDb.docs.get(amendmentPath).customMetadata, {
    retained: true, value: 17
  });
});

test("pending reopen and confirmation undo reject independent amendment progress", async () => {
  const makeExternalDb = () => fakeDb({
    "users/u1/tasks/original": {
      id: "original",
      taskId: "ORIGINAL",
      status: "InProgress",
      dispositionContract: userContract({ external: true })
    },
    "taskCatalog/AMEND_BANK": { taskId: "AMEND_BANK", title: "Amend {institution}" },
    "users/u1/identity/identity": {}
  });
  const reopenDb = makeExternalDb();
  const pending = await handleTaskPlanRequest(
    request("supersede", { replacement: replacement(), operationId: "progress-cycle" }),
    () => reopenDb,
    NOW
  );
  reopenDb.docs.get(`users/u1/tasks/${pending.replacementTaskId}`).userProgress = true;
  await assert.rejects(
    handleTaskPlanRequest(request("reopen", { operationId: "progress-reopen" }), () => reopenDb, NOW),
    (error) => error.code === "failed-precondition"
  );

  const undoDb = makeExternalDb();
  const pendingConfirm = await handleTaskPlanRequest(
    request("supersede", { replacement: replacement(), operationId: "confirm-progress-cycle" }),
    () => undoDb,
    NOW
  );
  await handleTaskPlanRequest(
    request("confirmAmendment", { operationId: "confirm-progress" }),
    () => undoDb,
    new Date("2026-08-27T12:01:00.000Z")
  );
  undoDb.docs.get(`users/u1/tasks/${pendingConfirm.replacementTaskId}`).userProgress = true;
  await assert.rejects(
    handleTaskPlanRequest(
      request("undoConfirmation", { operationId: "undo-progress" }),
      () => undoDb,
      new Date("2026-08-27T12:02:00.000Z")
    ),
    (error) => error.code === "failed-precondition"
  );
});

test("external amendment, confirm, undo, and reconfirm keep coherent immutable history", async () => {
  const db = fakeDb({
    "users/u1/tasks/original": {
      id: "original",
      taskId: "ORIGINAL",
      status: "InProgress",
      dispositionContract: userContract({ external: true })
    },
    "taskCatalog/AMEND_BANK": {
      taskId: "AMEND_BANK",
      title: "Amend submission with {institution}",
      category: "finance",
      actionType: "workflow",
      taskType: "provide_info",
      urgencyPercentage: 50
    },
    "users/u1/identity/identity": { moveDate: "2026-10-01T00:00:00.000Z" }
  });
  const supersedeRequest = request("supersede", { replacement: replacement() });
  const pending = await handleTaskPlanRequest(supersedeRequest, () => db, NOW);
  const amendmentPath = `users/u1/tasks/${pending.replacementTaskId}`;
  const original = db.docs.get("users/u1/tasks/original");
  const amendment = db.docs.get(amendmentPath);
  assert.equal(original.status, "matching_in_progress");
  assert.equal(original.dispositionContract.disposition, "WAITING_ON_EXTERNAL");
  assert.equal(amendment.status, "InProgress");
  assert.equal(amendment.dispositionContract.disposition, "USER_ACTION_TRACKED");
  assert.equal(amendment.supersedes, "original");
  assert.equal(amendment.subject.id, "row-bank");
  assert.notDeepEqual(
    amendment.dispositionContract.next_trigger,
    original.dispositionContract.next_trigger
  );

  const confirmAt = new Date("2026-08-27T12:01:00.000Z");
  const confirmed = await handleTaskPlanRequest(request("confirmAmendment"), () => db, confirmAt);
  assert.equal(confirmed.lifecycleState, "confirmed");
  assert.equal(db.docs.get("users/u1/tasks/original").dispositionContract.terminal_kind, "superseded");
  assert.equal(db.docs.get(amendmentPath).status, "Completed");
  const deadline = db.docs.get("users/u1/tasks/original").firstConfirmationUndoUntil;
  roundTripDocuments(db);

  const undoAt = new Date("2026-08-27T12:02:00.000Z");
  const undone = await handleTaskPlanRequest(request("undoConfirmation"), () => db, undoAt);
  assert.equal(undone.lifecycleState, "pending_confirmation");
  assert.equal(db.docs.get("users/u1/tasks/original").dispositionContract.owner, "Bank Co");
  assert.equal(db.docs.get(amendmentPath).dispositionContract.next_action, "Check the amendment status with Bank Co");

  const reconfirmed = await handleTaskPlanRequest(
    request("confirmAmendment", { operationId: "reconfirm-operation" }),
    () => db,
    new Date("2026-08-27T12:03:00.000Z")
  );
  assert.equal(reconfirmed.lifecycleState, "confirmed");
  assert.deepEqual(db.docs.get("users/u1/tasks/original").firstConfirmationUndoUntil, deadline);
  assert.deepEqual(
    db.docs.get("users/u1/tasks/original").planChangeHistory.map((row) => row.action),
    ["supersede", "confirm", "undo_confirmation", "reconfirm"]
  );
  await assert.rejects(
    handleTaskPlanRequest(
      request("undoConfirmation", { operationId: "second-undo" }),
      () => db,
      new Date("2026-08-27T12:04:00.000Z")
    ),
    (error) => error.code === "failed-precondition"
  );
});

test("TaskPlanService-style ISO triggers persist as native Dates in both amendment contracts", async () => {
  const isoReplacement = replacement({
    amendmentAction: {
      nextTrigger: {
        kind: "date",
        at: "2026-09-10T12:00:00.000Z",
        payload: { basis: "institution_promised_date", source_evidence_id: "amend-iso" }
      },
      resumeDestination: "bank/amend"
    },
    verification: {
      nextTrigger: {
        kind: "date",
        at: "2026-09-11T12:00:00.000Z",
        payload: { basis: "recipient_acceptance_date", source_evidence_id: "verify-iso" }
      },
      resumeDestination: "bank/verify"
    }
  });
  const db = fakeDb({
    "users/u1/tasks/original": {
      id: "original", taskId: "ORIGINAL", status: "InProgress",
      dispositionContract: userContract({ external: true })
    },
    "taskCatalog/AMEND_BANK": { taskId: "AMEND_BANK", title: "Amend {institution}" },
    "users/u1/identity/identity": {}
  });
  const response = await handleTaskPlanRequest(
    request("supersede", { replacement: isoReplacement, operationId: "iso-contract" }),
    () => db,
    NOW
  );
  const originalAt = db.docs.get("users/u1/tasks/original")
    .dispositionContract.next_trigger.at;
  const amendmentAt = db.docs.get(`users/u1/tasks/${response.replacementTaskId}`)
    .dispositionContract.next_trigger.at;
  assert.equal(originalAt instanceof Date, true);
  assert.equal(amendmentAt instanceof Date, true);
  assert.equal(originalAt.toISOString(), "2026-09-11T12:00:00.000Z");
  assert.equal(amendmentAt.toISOString(), "2026-09-10T12:00:00.000Z");
});

test("amendment due date uses identity-first then user_assessments fallback exactly like spawn", async () => {
  const base = {
    "users/u1/tasks/original": {
      id: "original", taskId: "ORIGINAL", status: "InProgress",
      dispositionContract: userContract({ external: true })
    },
    "taskCatalog/AMEND_BANK": {
      taskId: "AMEND_BANK", title: "Amend {institution}", urgencyPercentage: 50
    }
  };
  const db = fakeDb({
    ...base,
    "users/u1/identity/identity": {},
    "users/u1/user_assessments/assessment-1": { moveDate: "2026-10-01T00:00:00.000Z" }
  });
  const response = await handleTaskPlanRequest(
    request("supersede", { replacement: replacement(), operationId: "assessment-fallback" }),
    () => db,
    NOW
  );
  assert.equal(
    db.docs.get(`users/u1/tasks/${response.replacementTaskId}`).dueDate.toISOString(),
    "2026-09-13T00:00:00.000Z"
  );

  const identityDb = fakeDb({
    ...base,
    "users/u1/identity/identity": { moveDate: "2026-09-20T00:00:00.000Z" },
    "users/u1/user_assessments/assessment-1": { moveDate: "2026-10-01T00:00:00.000Z" }
  });
  const identityResponse = await handleTaskPlanRequest(
    request("supersede", { replacement: replacement(), operationId: "identity-first" }),
    () => identityDb,
    NOW
  );
  assert.equal(
    identityDb.docs.get(`users/u1/tasks/${identityResponse.replacementTaskId}`).dueDate.toISOString(),
    "2026-09-08T00:00:00.000Z"
  );
});

test("reopen full-validates prior contract at current time and rejects expired evidence", async () => {
  const db = fakeDb({
    "users/u1/tasks/original": {
      id: "original", taskId: "ORIGINAL", status: "InProgress",
      dispositionContract: userContract()
    }
  });
  await handleTaskPlanRequest(
    request("supersede", { operationId: "expire-cycle" }),
    () => db,
    NOW
  );
  const before = cloneTestValue(db.docs.get("users/u1/tasks/original"));
  await assert.rejects(
    handleTaskPlanRequest(
      request("reopen", { operationId: "expired-reopen" }),
      () => db,
      new Date("2026-09-11T12:00:00.000Z")
    ),
    (error) => error.code === "failed-precondition" && /future/i.test(error.message)
  );
  assert.deepEqual(db.docs.get("users/u1/tasks/original"), before);
  assert.equal(db.docs.has("users/u1/taskPlanOperations/expired-reopen"), false);
});

test("external/internal replacement rules and amendment collisions fail without partial writes", async () => {
  const internalDb = fakeDb({
    "users/u1/tasks/original": {
      taskId: "ORIGINAL", status: "InProgress", dispositionContract: userContract()
    }
  });
  await assert.rejects(
    handleTaskPlanRequest(request("supersede", { replacement: replacement() }), () => internalDb, NOW),
    (error) => error.code === "failed-precondition"
  );
  assert.equal(internalDb.writes.length, 0);

  const externalDb = fakeDb({
    "users/u1/tasks/original": {
      taskId: "ORIGINAL", status: "InProgress", dispositionContract: userContract({ external: true })
    }
  });
  await assert.rejects(
    handleTaskPlanRequest(request("supersede"), () => externalDb, NOW),
    (error) => error.code === "failed-precondition"
  );
  assert.equal(externalDb.writes.length, 0);
});

test("commit failure aborts original, amendment, and operation writes", async () => {
  const initial = {
    "users/u1/tasks/original": {
      taskId: "ORIGINAL", status: "InProgress", dispositionContract: userContract({ external: true })
    },
    "taskCatalog/AMEND_BANK": { taskId: "AMEND_BANK", title: "Amend {institution}" },
    "users/u1/identity/identity": {}
  };
  const db = fakeDb(initial, { failCommit: true });
  await assert.rejects(
    handleTaskPlanRequest(request("supersede", { replacement: replacement() }), () => db, NOW),
    /injected commit failure/
  );
  assert.equal(db.docs.get("users/u1/tasks/original").status, "InProgress");
  assert.equal([...db.docs.keys()].some((path) => path.includes("/taskPlanOperations/")), false);
  assert.equal([...db.docs.keys()].some((path) => path.includes("/tasks/a2_")), false);
});

test("Retake reset deletes only tasks, checkpoints exact count, then finalizes once", async () => {
  const db = fakeDb({
    "users/u1/tasks/a": { id: "a" },
    "users/u1/tasks/b": { id: "b" },
    "users/u1/user_assessments/one": { keep: true },
    "users/u1/userKnowledge/knowledge": { keep: true }
  });
  const resetRequest = request("resetAllTasks", {
    taskId: undefined,
    reason: "retake_assessment",
    operationId: "retake-op"
  });
  const deleted = await handleTaskPlanRequest(resetRequest, () => db, NOW);
  assert.deepEqual(deleted, { reset: true, deletedCount: 2, replayed: false });
  assert.equal(db.docs.has("users/u1/tasks/a"), false);
  assert.equal(db.docs.has("users/u1/tasks/b"), false);
  assert.equal(db.docs.has("users/u1/user_assessments/one"), true);
  assert.equal(db.docs.has("users/u1/userKnowledge/knowledge"), true);
  assert.equal(db.docs.get("users/u1").taskReset.state, "awaiting_local_reset");

  const replay = await handleTaskPlanRequest(resetRequest, () => db, NOW);
  assert.deepEqual(replay, { reset: true, deletedCount: 2, replayed: true });
  const finalize = request("finalizeTaskReset", {
    taskId: undefined,
    reason: "retake_assessment",
    operationId: "retake-op"
  });
  const finalized = await handleTaskPlanRequest(finalize, () => db, NOW);
  assert.deepEqual(finalized, { reset: true, deletedCount: 2, replayed: false });
  assert.equal("taskReset" in db.docs.get("users/u1"), false);
  assert.deepEqual(await handleTaskPlanRequest(finalize, () => db, NOW), {
    reset: true, deletedCount: 2, replayed: true
  });
});

test("reset resumes after a crash beyond 400 rows with exact unique count", async () => {
  const tasks = Object.fromEntries(Array.from({ length: 405 }, (_, index) => {
    const id = `task-${String(index).padStart(3, "0")}`;
    return [`users/u1/tasks/${id}`, { id }];
  }));
  const db = fakeDb(tasks, { failListCall: 2 });
  const resetRequest = request("resetAllTasks", {
    taskId: undefined,
    reason: "retake_assessment",
    operationId: "paged-retake"
  });
  await assert.rejects(
    handleTaskPlanRequest(resetRequest, () => db, NOW),
    /injected crash after committed reset page/
  );
  assert.equal(db.docs.get("users/u1").taskReset.deletedCount, 400);
  assert.equal([...db.docs.keys()].filter((path) => path.startsWith("users/u1/tasks/")).length, 5);

  await assert.rejects(
    handleTaskPlanRequest(resetRequest, () => db, NOW),
    (error) => error.code === "unavailable"
  );
  const resumed = await handleTaskPlanRequest(
    resetRequest,
    () => db,
    new Date(NOW.getTime() + 10 * 60 * 1000 + 1)
  );
  assert.deepEqual(resumed, { reset: true, deletedCount: 405, replayed: false });
  assert.equal([...db.docs.keys()].some((path) => path.startsWith("users/u1/tasks/")), false);
});

test("reset lease excludes live workers, permits expiry takeover, and rejects a different operation", async () => {
  const resetRequest = request("resetAllTasks", {
    taskId: undefined,
    reason: "retake_assessment",
    operationId: "lease-retake"
  });
  const cleaned = validateTaskPlanRequest(resetRequest.data, NOW);
  const seeded = {
    "users/u1": {
      taskReset: {
        operationId: "lease-retake",
        state: "deleting",
        deletedCount: 0,
        workerLease: {
          workerId: "foreign-worker",
          expiresAt: new Date(NOW.getTime() + 5 * 60 * 1000)
        }
      }
    },
    "users/u1/taskPlanOperations/lease-retake": {
      kind: "reset",
      fingerprint: resetFingerprint(cleaned),
      state: "deleting",
      deletedCount: 0
    },
    "users/u1/tasks/remaining": { id: "remaining" }
  };
  const liveDb = fakeDb(seeded);
  await assert.rejects(
    handleTaskPlanRequest(resetRequest, () => liveDb, NOW),
    (error) => error.code === "unavailable"
  );
  assert.equal(liveDb.docs.has("users/u1/tasks/remaining"), true);

  liveDb.docs.get("users/u1").taskReset.workerLease.expiresAt =
    new Date(NOW.getTime() - 1);
  const takeover = await handleTaskPlanRequest(resetRequest, () => liveDb, NOW);
  assert.deepEqual(takeover, { reset: true, deletedCount: 1, replayed: false });

  const conflictDb = fakeDb(seeded);
  const different = request("resetAllTasks", {
    taskId: undefined,
    reason: "retake_assessment",
    operationId: "different-retake"
  });
  await assert.rejects(
    handleTaskPlanRequest(different, () => conflictDb, NOW),
    (error) => error.code === "failed-precondition"
  );
  assert.equal(conflictDb.docs.has("users/u1/tasks/remaining"), true);
});

test("empty reset transition checks lease owner and stale worker cannot delete after finalize", async () => {
  const cleanedReset = validateTaskPlanRequest({
    action: "resetAllTasks",
    reason: "retake_assessment",
    operationId: "owner-retake"
  }, NOW);
  const db = fakeDb({
    "users/u1": {
      taskReset: {
        operationId: "owner-retake",
        state: "deleting",
        deletedCount: 0,
        workerLease: {
          workerId: "owner-worker",
          expiresAt: new Date(NOW.getTime() + 10 * 60 * 1000)
        }
      }
    },
    "users/u1/taskPlanOperations/owner-retake": {
      kind: "reset",
      fingerprint: resetFingerprint(cleanedReset),
      state: "deleting",
      deletedCount: 0
    }
  });
  const userRef = db.collection("users").doc("u1");
  const opRef = userRef.collection("taskPlanOperations").doc("owner-retake");
  const beforeWrites = db.writes.length;
  await assert.rejects(
    finishResetDeletion(db, userRef, opRef, "owner-retake", "stale-worker", NOW),
    (error) => error.code === "failed-precondition"
  );
  assert.equal(db.writes.length, beforeWrites);

  const deleted = await finishResetDeletion(
    db, userRef, opRef, "owner-retake", "owner-worker", NOW
  );
  assert.deepEqual(deleted, { reset: true, deletedCount: 0, replayed: false });
  const cleanedFinalize = validateTaskPlanRequest({
    action: "finalizeTaskReset",
    reason: "retake_assessment",
    operationId: "owner-retake"
  }, NOW);
  await executeFinalizeReset(db, "u1", cleanedFinalize, NOW);

  const regeneratedRef = userRef.collection("tasks").doc("regenerated");
  db.docs.set(regeneratedRef.path, { id: "regenerated" });
  await assert.rejects(
    deleteResetPage(
      db, userRef, opRef, "owner-retake", "owner-worker", [regeneratedRef],
      new Date(NOW.getTime() + 1)
    ),
    (error) => error.code === "failed-precondition"
  );
  assert.deepEqual(db.docs.get(regeneratedRef.path), { id: "regenerated" });
});

test("operation fingerprints are stable and canonical amendment IDs separate revisions", () => {
  const cleaned = validateTaskPlanRequest(request("supersede", { replacement: replacement() }).data, NOW);
  assert.match(operationFingerprint(cleaned), /^op1_[0-9a-f]{64}$/);
  const first = canonicalAmendmentId("u1", "original", 1, cleaned.replacement);
  const second = canonicalAmendmentId("u1", "original", 2, cleaned.replacement);
  assert.match(first, /^a2_[0-9a-f]{40}$/);
  assert.notEqual(first, second);
  assert.equal(
    operationFingerprint({ action: "x", at: NOW }),
    operationFingerprint({ action: "x", at: Timestamp.fromDate(NOW) })
  );
});
