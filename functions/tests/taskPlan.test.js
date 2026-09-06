"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { Timestamp } = require("firebase-admin/firestore");

// The legacy reset families run under the compat protocol mode (v9 §6.4:697).
process.env.PHASE2_RESET_PROTOCOL_MODE = "compat";

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

// ===========================================================================
// S2 (briefs/S2_BRIEF.md) — Phase 2 reset protocol, closed discriminator, root fence.
// These families use the shared in-memory Firestore; the legacy tests above keep their own.
// ===========================================================================

const { execFileSync } = require("node:child_process");
const path = require("node:path");
const { randomUUID: uuid } = require("node:crypto");
const { fakeFirestore: sharedFirestore, FakeClock } = require("./support/fakeFirestore");
const fence = require("../accountDeletionFence");

const {
  RESET_PROTOCOL_MODES,
  resetCanonicalId,
  resetRequestFingerprint,
  activeMoveEventIdFor,
  projectResetMarker,
  reconstructFinalReceipt
} = require("../taskPlan");

const P2_UID = "u2";
const P2_NOW = new Date("2026-09-06T12:00:00.000Z");

function p2Request(data, uid = P2_UID) {
  return { auth: { uid }, data };
}

function alias() { return `rsa1_${uuid()}`; }

// `mode: null` means the deployment environment carries no PHASE2_RESET_PROTOCOL_MODE.
async function p2Call(db, data, { now = P2_NOW, mode = "compat", uid = P2_UID } = {}) {
  return handleTaskPlanRequest(p2Request(data, uid), () => db, now, { resetProtocolMode: mode === null ? undefined : mode });
}

function expectTaskPlanError(fn, code, details) {
  return assert.rejects(fn, (error) => {
    assert.equal(error.code, code, `${error.code}: ${error.message} ${JSON.stringify(error.details)}`);
    if (details !== undefined) assert.deepEqual(error.details, details);
    return true;
  });
}

test("closed discriminator: reserved rsa1_/rso1_/rlm1_ IDs reject on every client surface, legacy raw validation is unchanged, and Phase 2 reset requests are exact", async () => {
  const db = sharedFirestore({ docs: { "users/u2": { taskGenerationEpoch: 0 }, "users/u2/tasks/t": { status: "Upcoming" } } });
  for (const action of ["supersede", "confirmAmendment", "undoConfirmation", "reopen"]) {
    for (const reserved of [`rsa1_${uuid()}`, `rso1_${"a".repeat(40)}`, `rlm1_${"b".repeat(40)}`]) {
      await expectTaskPlanError(() => p2Call(db, { action, taskId: "t", operationId: reserved, reason: "r" }), "invalid-argument", { schemaVersion: 1, reason: "REQUEST_INVALID", field: "operationId" });
    }
  }
  for (const reserved of [` rlm1_${"b".repeat(40)} `, `rso1_${"a".repeat(40)}`]) {
    await expectTaskPlanError(() => p2Call(db, { action: "resetAllTasks", operationId: reserved, reason: "retake_assessment" }), "invalid-argument", { schemaVersion: 1, reason: "REQUEST_INVALID", field: "operationId" });
    await expectTaskPlanError(() => p2Call(db, { action: "finalizeTaskReset", operationId: reserved, reason: "retake_assessment" }), "invalid-argument", { schemaVersion: 1, reason: "REQUEST_INVALID", field: "operationId" });
  }
  // legacy raw validation behavior is retained: a message-only invalid-argument without the Phase 2 details map
  await assert.rejects(p2Call(db, { action: "resetAllTasks", operationId: "legacy-op", reason: "other" }), (e) => e.code === "invalid-argument" && e.details === undefined);
  // Phase 2 reset requests: exact members
  const good = { action: "resetAllTasks", operationId: alias(), reason: "retake_assessment", expectedTaskGenerationEpoch: 0 };
  const bad = [
    [{ ...good, extra: 1 }, "request"],
    [{ ...good, operationId: "legacy-op" }, "operationId"],
    [{ ...good, reason: "other" }, "reason"],
    [{ ...good, expectedTaskGenerationEpoch: -1 }, "expectedTaskGenerationEpoch"],
    [{ ...good, expectedTaskGenerationEpoch: 1.5 }, "expectedTaskGenerationEpoch"],
    [{ ...good, expectedTaskGenerationEpoch: Number.MAX_SAFE_INTEGER }, "expectedTaskGenerationEpoch"],
    [{ ...good, taskId: "t" }, "request"]
  ];
  for (const [data, field] of bad) {
    await expectTaskPlanError(() => p2Call(db, data), "invalid-argument", { schemaVersion: 1, reason: "REQUEST_INVALID", field });
  }
  assert.equal(db.__writes.length, 0);
  assert.deepEqual(RESET_PROTOCOL_MODES, ["compat", "phase2_required"]);
});

test("PHASE2_RESET_PROTOCOL_MODE: absent makes every reset handler platform-unavailable, unknown fails module initialization, compat admits raw legacy resets, and required refuses fresh raw resets while an existing exact legacy operation may finish", async () => {
  const node = process.execPath;
  const modulePath = path.join(__dirname, "..", "taskPlan.js");
  assert.throws(() => execFileSync(node, ["-e", `process.env.PHASE2_RESET_PROTOCOL_MODE='weird'; require(${JSON.stringify(modulePath)})`], { stdio: "pipe" }), /PHASE2_RESET_PROTOCOL_MODE/);
  // a deployed function (FUNCTION_TARGET / K_SERVICE set) fails module initialization when the value is missing
  assert.throws(() => execFileSync(node, ["-e", `delete process.env.PHASE2_RESET_PROTOCOL_MODE; process.env.FUNCTION_TARGET='changeTaskPlan'; require(${JSON.stringify(modulePath)})`], { stdio: "pipe" }), /PHASE2_RESET_PROTOCOL_MODE/);
  execFileSync(node, ["-e", `process.env.PHASE2_RESET_PROTOCOL_MODE='compat'; process.env.FUNCTION_TARGET='changeTaskPlan'; require(${JSON.stringify(modulePath)})`], { stdio: "pipe" });
  // outside a deployment (local tooling, tests) absence loads the module and makes every reset handler platform-unavailable
  execFileSync(node, ["-e", `delete process.env.PHASE2_RESET_PROTOCOL_MODE; delete process.env.FUNCTION_TARGET; delete process.env.K_SERVICE; require(${JSON.stringify(modulePath)})`], { stdio: "pipe" });

  const legacyRequest = { action: "resetAllTasks", operationId: "legacy-op", reason: "retake_assessment" };
  const fresh = () => sharedFirestore({ docs: { "users/u2": { taskGenerationEpoch: 0 }, "users/u2/tasks/t": { status: "Upcoming" } } });
  const absent = fresh();
  await assert.rejects(p2Call(absent, legacyRequest, { mode: null }), (e) => e.code === "unavailable" && e.details === undefined);
  await assert.rejects(p2Call(absent, { action: "finalizeTaskReset", operationId: "legacy-op", reason: "retake_assessment" }, { mode: null }), (e) => e.code === "unavailable");
  assert.equal(absent.__writes.length, 0);

  const compat = fresh();
  assert.deepEqual(await p2Call(compat, legacyRequest, { mode: "compat" }), { reset: true, deletedCount: 1, replayed: false });
  assert.equal(compat.__docs.get("users/u2").taskReset.state, "awaiting_local_reset");

  const required = fresh();
  await expectTaskPlanError(() => p2Call(required, legacyRequest, { mode: "phase2_required" }), "failed-precondition", { schemaVersion: 1, reason: "CLIENT_UPGRADE_REQUIRED", requiredProtocol: "phase2" });
  assert.equal(required.__writes.length, 0);
  // an existing exact legacy pair may finish under required mode
  const inFlight = sharedFirestore({ docs: {
    "users/u2": { taskGenerationEpoch: 0, taskReset: { operationId: "legacy-op", state: "deleting", deletedCount: 0, workerLease: null, startedAt: Timestamp.fromDate(P2_NOW) } },
    "users/u2/taskPlanOperations/legacy-op": { kind: "reset", fingerprint: resetFingerprint({ reason: "retake_assessment" }), deletedCount: 0, state: "deleting", at: Timestamp.fromDate(P2_NOW) },
    "users/u2/tasks/t": { status: "Upcoming" }
  } });
  assert.deepEqual(await p2Call(inFlight, legacyRequest, { mode: "phase2_required" }), { reset: true, deletedCount: 1, replayed: false });
  assert.deepEqual(await p2Call(inFlight, { action: "finalizeTaskReset", operationId: "legacy-op", reason: "retake_assessment" }, { mode: "phase2_required" }), { reset: true, deletedCount: 1, replayed: false });
});

function phase2Seed(extra = {}) {
  return sharedFirestore({ docs: {
    "users/u2": { name: "A", taskGenerationEpoch: 3 },
    "users/u2/tasks/t1": { status: "Upcoming" },
    "users/u2/tasks/t2": { status: "Done" },
    "users/u2/notificationIntents/n1": { kind: "TASK_RESUME" },
    "users/u2/taskDeadlineEvidence/d1": { at: 1 },
    "users/u2/taskPlanOperations/pcs1_snapshot": { kind: "CONFIRMATION_SNAPSHOT", snapshot: {} },
    "users/u2/taskPlanOperations/op1_ordinary": { kind: "TASK_OPERATION", state: "COMMITTED" },
    "users/u2/taskPlanOperations/legacy-old": { kind: "operation", fingerprint: "x" },
    "users/u2/taskPlanOperations/pcs1_lower": { kind: "confirmation_snapshot" },
    "users/u2/user_assessments/a": { keep: true },
    "users/u3/tasks/t": { keep: true },
    ...extra
  } });
}

test("Phase 2 resetAllTasks: deterministic rso1_ record and Reconciled 9 marker, four-target deletion with exact counts, epoch rotation, and reset_progress receipts", async () => {
  const db = phase2Seed();
  const first = alias();
  const e = 3;
  const canonical = resetCanonicalId(P2_UID, e + 1);
  assert.equal(canonical, `rso1_${fence.first40(fence.sha256Hex(fence.TaskCanonicalV1({ account_uid: P2_UID, task_generation_epoch: 4 })))}`);
  const fingerprint = resetRequestFingerprint(e);
  assert.equal(fingerprint, `reset1_${fence.sha256Hex(fence.TaskCanonicalV1({ kind: "reset", reason: "retake_assessment", expected_task_generation_epoch: 3 }))}`);
  assert.equal(activeMoveEventIdFor(P2_UID, 4, canonical), `me1_${fence.first40(fence.sha256Hex(fence.TaskCanonicalV1({ uid: P2_UID, new_task_generation_epoch: 4, reset_operation_id: canonical })))}`);

  const progress = await p2Call(db, { action: "resetAllTasks", operationId: first, reason: "retake_assessment", expectedTaskGenerationEpoch: e });
  assert.deepEqual(progress, {
    schemaVersion: 1, kind: "reset_progress", operationId: canonical, replayed: false, accountUid: P2_UID,
    expectedTaskGenerationEpoch: 3, taskGenerationEpoch: 4, activeMoveEventId: activeMoveEventIdFor(P2_UID, 4, canonical),
    deletedCount: 5, deletedCounts: { tasks: 2, notificationIntents: 1, taskDeadlineEvidence: 1, confirmationSnapshots: 1 },
    state: "awaiting_local_reset"
  });
  const root = db.__docs.get("users/u2");
  assert.equal(root.taskGenerationEpoch, 4);
  assert.equal(root.activeMoveEventId, progress.activeMoveEventId);
  assert.equal(root.name, "A");
  const record = db.__docs.get(`users/u2/taskPlanOperations/${canonical}`);
  assert.deepEqual(Object.keys(record).sort(), ["account_uid", "active_move_event_id", "aliases", "awaiting_local_reset_at", "created_at", "deleted_count", "deleted_counts", "expected_task_generation_epoch", "kind", "operation_id", "reason", "request_fingerprint", "schema_version", "state", "target_index", "task_generation_epoch", "updated_at"]);
  assert.deepEqual([record.schema_version, record.kind, record.state, record.account_uid, record.operation_id, record.aliases, record.reason, record.request_fingerprint, record.expected_task_generation_epoch, record.task_generation_epoch, record.target_index, record.deleted_count], [1, "RESET_OPERATION", "awaiting_local_reset", P2_UID, canonical, [first], "retake_assessment", fingerprint, 3, 4, 4, 5]);
  assert.deepEqual(record.deleted_counts, { tasks: 2, notification_intents: 1, task_deadline_evidence: 1, confirmation_snapshots: 1 });
  const marker = root.taskReset;
  assert.deepEqual(marker, projectResetMarker(record));
  assert.deepEqual(Object.keys(marker).sort(), ["activeMoveEventId", "awaitingLocalResetAt", "createdAt", "deletedCount", "deletedCounts", "expectedTaskGenerationEpoch", "kind", "operationId", "requestFingerprint", "schemaVersion", "state", "targetIndex", "taskGenerationEpoch", "updatedAt"]);
  assert.equal(marker.kind, "reset");
  assert.equal(marker.targetIndex, 4);
  assert.ok(marker.createdAt.toMillis() <= marker.awaitingLocalResetAt.toMillis() && marker.awaitingLocalResetAt.toMillis() <= marker.updatedAt.toMillis());
  // only the four targets are gone; ordinary/legacy/lowercase records, the reset record, assessments, and other users survive
  const remaining = [...db.__docs.keys()].filter((p) => p.startsWith("users/u2/")).sort();
  assert.deepEqual(remaining, [`users/u2/taskPlanOperations/${canonical}`, "users/u2/taskPlanOperations/legacy-old", "users/u2/taskPlanOperations/op1_ordinary", "users/u2/taskPlanOperations/pcs1_lower", "users/u2/user_assessments/a"].sort());
  assert.ok(db.__docs.has("users/u3/tasks/t"));

  // replay with the same alias: byte-identical progress with replayed:true; a second alias appends in first-seen order
  assert.deepEqual(await p2Call(db, { action: "resetAllTasks", operationId: first, reason: "retake_assessment", expectedTaskGenerationEpoch: e }), { ...progress, replayed: true });
  const second = alias();
  assert.deepEqual(await p2Call(db, { action: "resetAllTasks", operationId: second, reason: "retake_assessment", expectedTaskGenerationEpoch: e }), { ...progress, replayed: true });
  assert.deepEqual(db.__docs.get(`users/u2/taskPlanOperations/${canonical}`).aliases, [first, second]);
  // aliases cap at 16; the 17th resolves without being persisted
  for (let i = 0; i < 14; i += 1) await p2Call(db, { action: "resetAllTasks", operationId: alias(), reason: "retake_assessment", expectedTaskGenerationEpoch: e });
  assert.equal(db.__docs.get(`users/u2/taskPlanOperations/${canonical}`).aliases.length, 16);
  const seventeenth = alias();
  assert.equal((await p2Call(db, { action: "resetAllTasks", operationId: seventeenth, reason: "retake_assessment", expectedTaskGenerationEpoch: e })).operationId, canonical);
  assert.equal(db.__docs.get(`users/u2/taskPlanOperations/${canonical}`).aliases.length, 16);
  // an occupied alias path fails closed
  const occupied = alias();
  db.__docs.set(`users/u2/taskPlanOperations/${occupied}`, { kind: "operation" });
  await expectTaskPlanError(() => p2Call(db, { action: "resetAllTasks", operationId: occupied, reason: "retake_assessment", expectedTaskGenerationEpoch: e }), "failed-precondition", { schemaVersion: 1, reason: "OPERATION_REUSED", operationId: occupied });
  // a losing scene retaining e addresses the same record even though the root is now 4; the next intentional reset addresses r+1
  assert.equal((await p2Call(db, { action: "resetAllTasks", operationId: alias(), reason: "retake_assessment", expectedTaskGenerationEpoch: 3 })).operationId, canonical);
});

test("Phase 2 reset refusals: STALE_STATE for a root epoch other than e, RESET_ACTIVE for a live marker of another record, LEGACY_RESET_MIGRATION_REQUIRED beside a legacy marker, malformed canonical path fails closed", async () => {
  const stale = phase2Seed();
  await expectTaskPlanError(() => p2Call(stale, { action: "resetAllTasks", operationId: alias(), reason: "retake_assessment", expectedTaskGenerationEpoch: 2 }), "failed-precondition", { schemaVersion: 1, reason: "STALE_STATE" });
  assert.equal(stale.__writes.length, 0);
  await expectTaskPlanError(() => p2Call(stale, { action: "finalizeTaskReset", operationId: alias(), reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }), "failed-precondition", { schemaVersion: 1, reason: "STALE_STATE" });

  const active = phase2Seed();
  const first = alias();
  await p2Call(active, { action: "resetAllTasks", operationId: first, reason: "retake_assessment", expectedTaskGenerationEpoch: 3 });
  const canonical = resetCanonicalId(P2_UID, 4);
  await expectTaskPlanError(() => p2Call(active, { action: "resetAllTasks", operationId: alias(), reason: "retake_assessment", expectedTaskGenerationEpoch: 4 }), "failed-precondition", { schemaVersion: 1, reason: "RESET_ACTIVE", operationId: canonical, expectedTaskGenerationEpoch: 3 });

  const legacy = phase2Seed({ "users/u2": { taskGenerationEpoch: 3, taskReset: { operationId: "legacy-op", state: "deleting", deletedCount: 0, workerLease: null, startedAt: Timestamp.fromDate(P2_NOW) } } });
  await expectTaskPlanError(() => p2Call(legacy, { action: "resetAllTasks", operationId: alias(), reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }), "failed-precondition", { schemaVersion: 1, reason: "LEGACY_RESET_MIGRATION_REQUIRED", legacyOperationId: "legacy-op" });
  assert.equal(legacy.__writes.length, 0);
  // a legacy-looking but non-exact marker fails closed instead of redirecting
  const looseLegacy = phase2Seed({ "users/u2": { taskGenerationEpoch: 3, taskReset: { operationId: "legacy-op", state: "deleting", deletedCount: 0, workerLease: { workerId: "not-a-uuid" }, startedAt: Timestamp.fromDate(P2_NOW) } } });
  await expectTaskPlanError(() => p2Call(looseLegacy, { action: "resetAllTasks", operationId: alias(), reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }), "failed-precondition", { schemaVersion: 1, reason: "OPERATION_REUSED", operationId: resetCanonicalId(P2_UID, 4) });

  // a record whose members are well-formed but whose identity formulas disagree with its own epoch fails closed
  const fresh = phase2Seed();
  await p2Call(fresh, { action: "resetAllTasks", operationId: alias(), reason: "retake_assessment", expectedTaskGenerationEpoch: 3 });
  const stored = fresh.__docs.get(`users/u2/taskPlanOperations/${resetCanonicalId(P2_UID, 4)}`);
  stored.request_fingerprint = resetRequestFingerprint(2);
  fresh.__docs.get("users/u2").taskReset = projectResetMarker(stored);
  await expectTaskPlanError(() => p2Call(fresh, { action: "resetAllTasks", operationId: alias(), reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }), "failed-precondition", { schemaVersion: 1, reason: "OPERATION_REUSED", operationId: resetCanonicalId(P2_UID, 4) });
  const malformed = phase2Seed({ [`users/u2/taskPlanOperations/${resetCanonicalId(P2_UID, 4)}`]: { kind: "RESET_OPERATION", state: "deleting" } });
  await expectTaskPlanError(() => p2Call(malformed, { action: "resetAllTasks", operationId: alias(), reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }), "failed-precondition", { schemaVersion: 1, reason: "OPERATION_REUSED", operationId: resetCanonicalId(P2_UID, 4) });
  assert.equal(malformed.__writes.length, 0);
  // marker absent beside an active record is malformed (fails closed with zero writes)
  const orphan = phase2Seed();
  await p2Call(orphan, { action: "resetAllTasks", operationId: alias(), reason: "retake_assessment", expectedTaskGenerationEpoch: 3 });
  delete orphan.__docs.get("users/u2").taskReset;
  const before = orphan.__writes.length;
  await expectTaskPlanError(() => p2Call(orphan, { action: "resetAllTasks", operationId: alias(), reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }), "failed-precondition", { schemaVersion: 1, reason: "OPERATION_REUSED", operationId: resetCanonicalId(P2_UID, 4) });
  assert.equal(orphan.__writes.length, before);
});

test("Phase 2 finalizeTaskReset: tombstone replaces the active record and deletes the marker before the first final receipt; replays verify the digest; drift fails closed", async () => {
  const db = phase2Seed();
  const first = alias();
  const canonical = resetCanonicalId(P2_UID, 4);
  await expectTaskPlanError(() => p2Call(db, { action: "finalizeTaskReset", operationId: first, reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }), "failed-precondition", { schemaVersion: 1, reason: "STALE_STATE" });
  const progress = await p2Call(db, { action: "resetAllTasks", operationId: first, reason: "retake_assessment", expectedTaskGenerationEpoch: 3 });
  const later = new Date(P2_NOW.getTime() + 60_000);
  const final = await p2Call(db, { action: "finalizeTaskReset", operationId: first, reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }, { now: later });
  assert.deepEqual(final, {
    schemaVersion: 1, kind: "reset_final", operationId: canonical, replayed: false, accountUid: P2_UID,
    expectedTaskGenerationEpoch: 3, taskGenerationEpoch: 4, activeMoveEventId: progress.activeMoveEventId,
    deletedCount: 5, deletedCounts: progress.deletedCounts, state: "finalized"
  });
  assert.equal("taskReset" in db.__docs.get("users/u2"), false);
  const tombstone = db.__docs.get(`users/u2/taskPlanOperations/${canonical}`);
  assert.deepEqual(Object.keys(tombstone).sort(), ["account_uid", "active_move_event_id", "aliases", "created_at", "deleted_count", "deleted_counts", "expected_task_generation_epoch", "final_receipt_digest", "finalized_at", "kind", "operation_id", "reason", "request_fingerprint", "schema_version", "state", "task_generation_epoch"]);
  assert.equal(tombstone.state, "finalized");
  assert.equal(tombstone.final_receipt_digest, fence.sha256Hex(fence.TaskCanonicalV1(final)));
  assert.equal(tombstone.finalized_at.toMillis(), later.getTime());
  assert.deepEqual(reconstructFinalReceipt(tombstone), final);
  // replays through either action: same bytes with replayed:true; a new alias appends on the tombstone without touching other members
  assert.deepEqual(await p2Call(db, { action: "finalizeTaskReset", operationId: first, reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }), { ...final, replayed: true });
  const other = alias();
  assert.deepEqual(await p2Call(db, { action: "resetAllTasks", operationId: other, reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }), { ...final, replayed: true });
  const after = db.__docs.get(`users/u2/taskPlanOperations/${canonical}`);
  assert.deepEqual(after.aliases, [first, other]);
  assert.deepEqual({ ...after, aliases: null }, { ...tombstone, aliases: null });
  // digest tamper fails closed
  after.final_receipt_digest = fence.sha256Hex("tampered");
  await expectTaskPlanError(() => p2Call(db, { action: "finalizeTaskReset", operationId: first, reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }), "failed-precondition", { schemaVersion: 1, reason: "OPERATION_REUSED", operationId: canonical });
  // finalize before ready: an active deleting record is STALE_STATE with zero destructive mutation
  const deleting = phase2Seed();
  const a2 = alias();
  await p2Call(deleting, { action: "resetAllTasks", operationId: a2, reason: "retake_assessment", expectedTaskGenerationEpoch: 3 });
  const rec = deleting.__docs.get(`users/u2/taskPlanOperations/${resetCanonicalId(P2_UID, 4)}`);
  rec.state = "deleting"; rec.target_index = 2; delete rec.awaiting_local_reset_at;
  deleting.__docs.get("users/u2").taskReset = projectResetMarker(rec);
  const writes = deleting.__writes.length;
  await expectTaskPlanError(() => p2Call(deleting, { action: "finalizeTaskReset", operationId: a2, reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }), "failed-precondition", { schemaVersion: 1, reason: "STALE_STATE" });
  assert.equal(deleting.__writes.length, writes);
});

test("Phase 2 reset resumes across a lost response: a deleting record with a cursor continues from the same target, counts never double, and a live foreign lease is unavailable", async () => {
  const clock = new FakeClock("2026-09-06T12:00:00.000Z");
  const db = phase2Seed();
  const first = alias();
  const canonical = resetCanonicalId(P2_UID, 4);
  // crash after the first deleted document: simulate by driving with a budget of one document
  await assert.rejects(handleTaskPlanRequest(p2Request({ action: "resetAllTasks", operationId: first, reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }), () => db, P2_NOW, { resetProtocolMode: "compat", resetDocumentBudget: 1 }), (e) => e.code === "unavailable");
  const partial = db.__docs.get(`users/u2/taskPlanOperations/${canonical}`);
  assert.equal(partial.state, "deleting");
  assert.equal(partial.deleted_count, 1);
  assert.equal(partial.target_index, 0);
  assert.ok(partial.lease && partial.lease.owner_token && partial.lease.expires_at);
  assert.deepEqual(db.__docs.get("users/u2").taskReset, projectResetMarker(partial));
  // a live foreign lease refuses; after expiry the resume proceeds and the total is exact
  await assert.rejects(p2Call(db, { action: "resetAllTasks", operationId: first, reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }), (e) => e.code === "unavailable");
  const resumed = await p2Call(db, { action: "resetAllTasks", operationId: first, reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }, { now: new Date(P2_NOW.getTime() + 10 * 60_000 + 1) });
  assert.equal(resumed.state, "awaiting_local_reset");
  assert.deepEqual(resumed.deletedCounts, { tasks: 2, notificationIntents: 1, taskDeadlineEvidence: 1, confirmationSnapshots: 1 });
  assert.equal(resumed.deletedCount, 5);
  void clock;
});

test("root fence: every committing branch of taskPlan.js reads the owner root and refuses when accountDeletion is present", async () => {
  const marker = { schemaVersion: 1, state: "DELETING", capabilities: [{ operationId: `adel1_${uuid()}`, proofSHA256: "a".repeat(64) }], startedAt: Timestamp.fromDate(P2_NOW), storageGuardAfter: Timestamp.fromMillis(P2_NOW.getTime() + 604800_000) };
  const fenced = () => sharedFirestore({ docs: { "users/u2": { taskGenerationEpoch: 3, accountDeletion: marker }, "users/u2/tasks/t": { status: "Upcoming" } } });
  const requests = [
    { action: "supersede", taskId: "t", operationId: "op-1", reason: "r" },
    { action: "reopen", taskId: "t", operationId: "op-2", reason: "r" },
    { action: "resetAllTasks", operationId: "legacy-op", reason: "retake_assessment" },
    { action: "finalizeTaskReset", operationId: "legacy-op", reason: "retake_assessment" },
    { action: "resetAllTasks", operationId: alias(), reason: "retake_assessment", expectedTaskGenerationEpoch: 3 },
    { action: "finalizeTaskReset", operationId: alias(), reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }
  ];
  for (const data of requests) {
    const db = fenced();
    await expectTaskPlanError(() => p2Call(db, data), "failed-precondition", { schemaVersion: 1, reason: "ACCOUNT_DELETION_FENCED" });
    assert.equal(db.__writes.length, 0, data.action);
  }
});

// ===========================================================================
// S2 I4b — raw legacy fence, reconcileLegacyTaskReset, inspectCommittedOperation (C2.8)
// ===========================================================================

const { migrationIdFor, migrationFingerprintFor, LEGACY_RESET_FINGERPRINT } = require("../taskPlan");

const LEGACY_ID = "20000000-0000-4000-8000-000000000001";
const RULE_OWNER = "phase2-rule-owner";

function legacyOp(state, deletedCount, at = Timestamp.fromDate(P2_NOW)) {
  const base = { kind: "reset", fingerprint: LEGACY_RESET_FINGERPRINT, deletedCount, state, at };
  if (state === "tasks_deleted" || state === "finalized") base.tasks_deleted = { reset: true, deletedCount, replayed: false };
  if (state === "finalized") { base.finalized = { reset: true, deletedCount, replayed: false }; base.finalizedAt = at; }
  return base;
}

function legacyMarker(operationId, state, deletedCount, startedAt = Timestamp.fromDate(P2_NOW)) {
  return { operationId, state, deletedCount, workerLease: null, startedAt };
}

function migrationPath(uid, legacyOperationId) { return `users/${uid}/legacyResetMigrations/${migrationIdFor(uid, legacyOperationId)}`; }

test("legacy migration derivations equal the C7 parity fixture and the accepted legacy fingerprint literal", () => {
  assert.equal(migrationIdFor(RULE_OWNER, LEGACY_ID), "rlm1_0a4d53a438873090f69e4255426310b0feb4cfd6");
  assert.equal(migrationFingerprintFor(RULE_OWNER, LEGACY_ID), "rlmreq1_0a4d53a438873090f69e4255426310b0feb4cfd63eabd6ce68c851ce827ad8e1");
  assert.equal(LEGACY_RESET_FINGERPRINT, "reset1_862fe3fc8a08ce3eced6f25dfd2a8765b408e8386fa28f081f393d36f04e94a1");
  assert.equal(resetFingerprint({ reason: "retake_assessment" }), LEGACY_RESET_FINGERPRINT);
});

test("raw legacy fence: the permanent migration record is read before any root or legacy-operation write; finalized_compat replays the old wire; other outcomes require the Phase 2 client; malformed records are OPERATION_REUSED", async () => {
  const legacyRequest = { action: "resetAllTasks", operationId: "legacy-op", reason: "retake_assessment" };
  const finalizeRequest = { action: "finalizeTaskReset", operationId: " legacy-op ", reason: "retake_assessment" }; // ECMAScript-trimmed raw ID fences the normalized operation
  const migrationId = migrationIdFor(P2_UID, "legacy-op");
  const base = { schema_version: 1, kind: "LEGACY_RESET_MIGRATION", account_uid: P2_UID, migration_id: migrationId, legacy_operation_id: "legacy-op", migration_alias: alias(), request_fingerprint: migrationFingerprintFor(P2_UID, "legacy-op"), created_at: Timestamp.fromDate(P2_NOW) };
  const compat = { ...base, outcome: "finalized_compat", source_state: "finalized", legacy_final_receipt: { schemaVersion: 1, kind: "legacy_reset_final", operationId: "legacy-op", replayed: false, accountUid: P2_UID, deletedCount: 2, state: "finalized" } };
  const compatDb = sharedFirestore({ docs: { "users/u2": { taskGenerationEpoch: 0 }, [migrationPath(P2_UID, "legacy-op")]: compat, "users/u2/taskPlanOperations/legacy-op": legacyOp("finalized", 2), "users/u2/tasks/t": {} } });
  assert.deepEqual(await p2Call(compatDb, legacyRequest), { reset: true, deletedCount: 2, replayed: true });
  assert.deepEqual(await p2Call(compatDb, finalizeRequest), { reset: true, deletedCount: 2, replayed: true });
  assert.equal(compatDb.__writes.length, 0);
  assert.ok(compatDb.__docs.has("users/u2/tasks/t"), "no task was deleted behind the fence");
  for (const outcome of ["not_dispatched", "upgraded", "phase2_active"]) {
    const record = { ...base, outcome };
    if (outcome !== "not_dispatched") Object.assign(record, { expected_task_generation_epoch: 0, task_generation_epoch: 1, canonical_operation_id: resetCanonicalId(P2_UID, 1), active_move_event_id: activeMoveEventIdFor(P2_UID, 1, resetCanonicalId(P2_UID, 1)), progress_receipt: { schemaVersion: 1, kind: "reset_progress", operationId: resetCanonicalId(P2_UID, 1), replayed: outcome === "phase2_active", accountUid: P2_UID, expectedTaskGenerationEpoch: 0, taskGenerationEpoch: 1, activeMoveEventId: activeMoveEventIdFor(P2_UID, 1, resetCanonicalId(P2_UID, 1)), deletedCount: 0, deletedCounts: { tasks: 0, notificationIntents: 0, taskDeadlineEvidence: 0, confirmationSnapshots: 0 }, state: "deleting" } });
    if (outcome === "upgraded") record.source_state = "deleting";
    const db = sharedFirestore({ docs: { "users/u2": { taskGenerationEpoch: 1 }, [migrationPath(P2_UID, "legacy-op")]: record, "users/u2/tasks/t": {} } });
    await expectTaskPlanError(() => p2Call(db, legacyRequest), "failed-precondition", { schemaVersion: 1, reason: "CLIENT_UPGRADE_REQUIRED", requiredProtocol: "phase2" });
    await expectTaskPlanError(() => p2Call(db, finalizeRequest), "failed-precondition", { schemaVersion: 1, reason: "CLIENT_UPGRADE_REQUIRED", requiredProtocol: "phase2" });
    assert.equal(db.__writes.length, 0, outcome);
  }
  const malformedDb = sharedFirestore({ docs: { "users/u2": { taskGenerationEpoch: 0 }, [migrationPath(P2_UID, "legacy-op")]: { ...base, outcome: "finalized_compat", request_fingerprint: "rlmreq1_" + "0".repeat(64) } } });
  await expectTaskPlanError(() => p2Call(malformedDb, legacyRequest), "failed-precondition", { schemaVersion: 1, reason: "OPERATION_REUSED", operationId: migrationId });
  assert.equal(malformedDb.__writes.length, 0);
  // absent record: the raw path proceeds exactly as before
  const plain = sharedFirestore({ docs: { "users/u2": { taskGenerationEpoch: 0 }, "users/u2/tasks/t": {} } });
  assert.deepEqual(await p2Call(plain, legacyRequest), { reset: true, deletedCount: 1, replayed: false });
});

test("reconcileLegacyTaskReset: request precedence, derivations, and every classification outcome with exact records, receipts, and errors", async () => {
  const aliasA = alias();
  const req = (legacyOperationId = "legacy-op", migrationAlias = aliasA) => ({ action: "reconcileLegacyTaskReset", legacyOperationId, migrationAlias });
  const empty = () => sharedFirestore({ docs: { "users/u2": { taskGenerationEpoch: 2 } } });

  // validation precedence and reserved legacyOperationId
  const bad = [
    [{ ...req(), extra: 1 }, "request"],
    [{ action: "reconcileLegacyTaskReset", migrationAlias: aliasA }, "request"],
    [req("a/b"), "legacyOperationId"],
    [req(`rlm1_${"c".repeat(40)}`), "legacyOperationId"],
    [req("legacy-op", "not-an-alias"), "migrationAlias"],
    [req("legacy-op", `rsa1_${uuid().toUpperCase()}`), "migrationAlias"]
  ];
  for (const [data, field] of bad) {
    await expectTaskPlanError(() => p2Call(empty(), data), "invalid-argument", { schemaVersion: 1, reason: "REQUEST_INVALID", field });
  }
  await expectTaskPlanError(() => handleTaskPlanRequest({ data: req() }, () => empty(), P2_NOW, { resetProtocolMode: "compat" }), "unauthenticated", { schemaVersion: 1, reason: "AUTH_REQUIRED" });

  // not_dispatched
  const nd = empty();
  const migrationId = migrationIdFor(P2_UID, "legacy-op");
  const ndResponse = await p2Call(nd, req());
  assert.deepEqual(ndResponse, { schemaVersion: 1, kind: "legacy_reset_reconciliation", outcome: "not_dispatched", migrationId, legacyOperationId: "legacy-op", migrationAlias: aliasA, accountUid: P2_UID, replayed: false });
  const ndRecord = nd.__docs.get(migrationPath(P2_UID, "legacy-op"));
  assert.deepEqual({ ...ndRecord, created_at: null }, { schema_version: 1, kind: "LEGACY_RESET_MIGRATION", account_uid: P2_UID, migration_id: migrationId, legacy_operation_id: "legacy-op", migration_alias: aliasA, request_fingerprint: migrationFingerprintFor(P2_UID, "legacy-op"), outcome: "not_dispatched", created_at: null });
  assert.equal(ndRecord.created_at.toMillis(), P2_NOW.getTime());
  // replay returns the stored alias even when the candidate differs; only the outer replayed changes
  const replay = await p2Call(nd, req("legacy-op", alias()));
  assert.deepEqual(replay, { ...ndResponse, replayed: true });
  // a present mismatching record is OPERATION_REUSED naming the migration id
  nd.__docs.get(migrationPath(P2_UID, "legacy-op")).account_uid = "uid-other";
  await expectTaskPlanError(() => p2Call(nd, req()), "failed-precondition", { schemaVersion: 1, reason: "OPERATION_REUSED", operationId: migrationId });

  // finalized_compat
  const fc = sharedFirestore({ docs: { "users/u2": { taskGenerationEpoch: 2 }, "users/u2/taskPlanOperations/legacy-op": legacyOp("finalized", 3) } });
  const fcResponse = await p2Call(fc, req());
  assert.deepEqual(fcResponse, { schemaVersion: 1, kind: "legacy_reset_reconciliation", outcome: "finalized_compat", migrationId, legacyOperationId: "legacy-op", migrationAlias: aliasA, accountUid: P2_UID, sourceState: "finalized", replayed: false, legacyFinalReceipt: { schemaVersion: 1, kind: "legacy_reset_final", operationId: "legacy-op", replayed: false, accountUid: P2_UID, deletedCount: 3, state: "finalized" } });
  assert.equal(fc.__docs.get("users/u2").taskGenerationEpoch, 2, "finalized legacy never rotates the epoch");
  assert.deepEqual(await p2Call(fc, req()), { ...fcResponse, replayed: true });

  // alias occupied: zero write
  const occ = sharedFirestore({ docs: { "users/u2": { taskGenerationEpoch: 2 }, [`users/u2/taskPlanOperations/${aliasA}`]: { kind: "operation" } } });
  await expectTaskPlanError(() => p2Call(occ, req()), "failed-precondition", { schemaVersion: 1, reason: "LEGACY_RESET_ALIAS_OCCUPIED", legacyOperationId: "legacy-op", migrationAlias: aliasA });
  assert.equal(occ.__writes.length, 0);

  // upgraded (L-deleting / M-deleting): canonical record with the legacy count, marker replaced, epoch rotated, migration record with inner replayed:false
  const at = Timestamp.fromMillis(P2_NOW.getTime() - 60_000);
  const up = sharedFirestore({ docs: {
    "users/u2": { taskGenerationEpoch: 2, taskReset: legacyMarker("legacy-op", "deleting", 7, at) },
    "users/u2/taskPlanOperations/legacy-op": legacyOp("deleting", 7, at),
    "users/u2/tasks/late": {}
  } });
  const canonical = resetCanonicalId(P2_UID, 3);
  const upResponse = await p2Call(up, req());
  const expectedProgress = { schemaVersion: 1, kind: "reset_progress", operationId: canonical, replayed: false, accountUid: P2_UID, expectedTaskGenerationEpoch: 2, taskGenerationEpoch: 3, activeMoveEventId: activeMoveEventIdFor(P2_UID, 3, canonical), deletedCount: 7, deletedCounts: { tasks: 7, notificationIntents: 0, taskDeadlineEvidence: 0, confirmationSnapshots: 0 }, state: "deleting" };
  assert.deepEqual(upResponse, { schemaVersion: 1, kind: "legacy_reset_reconciliation", outcome: "upgraded", migrationId, legacyOperationId: "legacy-op", migrationAlias: aliasA, accountUid: P2_UID, sourceState: "deleting", replayed: false, progressReceipt: expectedProgress });
  const upRoot = up.__docs.get("users/u2");
  assert.equal(upRoot.taskGenerationEpoch, 3);
  assert.equal(upRoot.activeMoveEventId, expectedProgress.activeMoveEventId);
  const upRecord = up.__docs.get(`users/u2/taskPlanOperations/${canonical}`);
  assert.deepEqual([upRecord.state, upRecord.target_index, upRecord.aliases, upRecord.deleted_count, upRecord.deleted_counts.tasks, upRecord.page_after_path, upRecord.lease, upRecord.awaiting_local_reset_at], ["deleting", 0, [aliasA], 7, 7, undefined, undefined, undefined]);
  assert.ok(upRecord.created_at.isEqual(at) && upRecord.updated_at.toMillis() === P2_NOW.getTime());
  assert.deepEqual(upRoot.taskReset, projectResetMarker(upRecord));
  assert.deepEqual(up.__docs.get("users/u2/taskPlanOperations/legacy-op"), legacyOp("deleting", 7, at), "the original legacy operation stays byte-identical");
  const upMigration = up.__docs.get(migrationPath(P2_UID, "legacy-op"));
  assert.deepEqual(upMigration.progress_receipt, expectedProgress);
  assert.equal(upMigration.source_state, "deleting");
  assert.equal(upMigration.canonical_operation_id, canonical);
  // replay of the upgrade keeps the inner replayed:false and flips only the outer
  assert.deepEqual(await p2Call(up, req()), { ...upResponse, replayed: true });
  // the imported reset then drives through the ordinary four-target reducer from target zero
  const resumed = await p2Call(up, { action: "resetAllTasks", operationId: aliasA, reason: "retake_assessment", expectedTaskGenerationEpoch: 2 });
  assert.equal(resumed.state, "awaiting_local_reset");
  assert.equal(resumed.deletedCount, 8, "late task counted once on top of the imported legacy count");

  // phase2_active (A absent beside an active Phase 2 marker C): record carries C's progress with inner replayed:true
  const pa = phase2Seed();
  const aliasC = alias();
  await p2Call(pa, { action: "resetAllTasks", operationId: aliasC, reason: "retake_assessment", expectedTaskGenerationEpoch: 3 });
  const paResponse = await p2Call(pa, req("some-legacy-id", alias()));
  assert.equal(paResponse.outcome, "phase2_active");
  assert.equal(paResponse.progressReceipt.replayed, true);
  assert.equal(paResponse.progressReceipt.operationId, resetCanonicalId(P2_UID, 4));
  assert.deepEqual(pa.__docs.get(`users/u2/taskPlanOperations/${resetCanonicalId(P2_UID, 4)}`).aliases, [aliasC], "C is untouched");
  // a requested alias that is itself current Phase-2 authority, and the canonical id itself, use the same phase2_active branch (§6.1:600)
  assert.equal((await p2Call(pa, req(aliasC, alias()))).outcome, "phase2_active");
  assert.equal((await p2Call(pa, req(resetCanonicalId(P2_UID, 4), alias()))).outcome, "phase2_active");
  // a legacy-active requested record beside C is corruption with its own record class
  const besideC = phase2Seed({ "users/u2/taskPlanOperations/legacy-op": legacyOp("deleting", 1) });
  await p2Call(besideC, { action: "resetAllTasks", operationId: alias(), reason: "retake_assessment", expectedTaskGenerationEpoch: 3 });
  await expectTaskPlanError(() => p2Call(besideC, req("legacy-op", alias())), "failed-precondition", { schemaVersion: 1, reason: "LEGACY_RESET_CORRUPT", context: "reconcile", legacyOperationId: "legacy-op", recordClass: "deleting", markerClass: "phase2" });

  // LEGACY_RESET_MIGRATION_REQUIRED: the active legacy marker belongs to B
  const bDb = sharedFirestore({ docs: { "users/u2": { taskGenerationEpoch: 2, taskReset: legacyMarker("op-B", "deleting", 1) }, "users/u2/taskPlanOperations/op-B": legacyOp("deleting", 1) } });
  await expectTaskPlanError(() => p2Call(bDb, req("op-A")), "failed-precondition", { schemaVersion: 1, reason: "LEGACY_RESET_MIGRATION_REQUIRED", legacyOperationId: "op-B" });
  assert.equal(bDb.__writes.length, 0);

  // LEGACY_RESET_CORRUPT with recordClass/markerClass
  const corrupt = [
    ["deleting op without marker", { "users/u2": { taskGenerationEpoch: 2 }, "users/u2/taskPlanOperations/legacy-op": legacyOp("deleting", 1) }, { recordClass: "deleting", markerClass: "absent" }],
    ["malformed marker", { "users/u2": { taskGenerationEpoch: 2, taskReset: { operationId: "legacy-op", state: "weird" } } }, { recordClass: "absent", markerClass: "malformed" }],
    ["count mismatch", { "users/u2": { taskGenerationEpoch: 2, taskReset: legacyMarker("legacy-op", "deleting", 2) }, "users/u2/taskPlanOperations/legacy-op": legacyOp("deleting", 1) }, { recordClass: "deleting", markerClass: "deleting" }],
    ["awaiting marker with deleting op", { "users/u2": { taskGenerationEpoch: 2, taskReset: legacyMarker("legacy-op", "awaiting_local_reset", 1) }, "users/u2/taskPlanOperations/legacy-op": legacyOp("deleting", 1) }, { recordClass: "deleting", markerClass: "awaiting_local_reset" }],
    ["occupied canonical path", { "users/u2": { taskGenerationEpoch: 2, taskReset: legacyMarker("legacy-op", "deleting", 1) }, "users/u2/taskPlanOperations/legacy-op": legacyOp("deleting", 1), [`users/u2/taskPlanOperations/${resetCanonicalId(P2_UID, 3)}`]: { kind: "RESET_OPERATION" } }, { recordClass: "phase2", markerClass: "deleting" }]
  ];
  for (const [label, docs, classes] of corrupt) {
    const db = sharedFirestore({ docs });
    await expectTaskPlanError(() => p2Call(db, req()), "failed-precondition", { schemaVersion: 1, reason: "LEGACY_RESET_CORRUPT", context: "reconcile", legacyOperationId: "legacy-op", ...classes });
    assert.equal(db.__writes.length, 0, label);
  }
});

test("inspectCommittedOperation: request precedence, every family row, replay projections, RESET as the sole pending member, and OPERATION_REUSED for malformed or foreign authority with zero writes", async () => {
  const inspect = (family, authority, requestAuthority, identityDigest) => ({ action: "inspectCommittedOperation", family, authority, requestAuthority, identityDigest });
  const digestOf = (map) => fence.sha256Hex(fence.TaskCanonicalV1(map));
  const db = phase2Seed();
  // precedence
  const good = inspect("RESET", { operationId: resetCanonicalId(P2_UID, 4) }, { requestFingerprint: resetRequestFingerprint(3) }, digestOf({ kind: "reset", uid: P2_UID, expectedTaskGenerationEpoch: 3 }));
  const bad = [
    [{ ...good, extra: 1 }, "request"],
    [{ action: "inspectCommittedOperation", family: "RESET" }, "request"],
    [{ ...good, family: "OTHER" }, "family"],
    [{ ...good, authority: { migrationId: "x" } }, "authority"],
    [{ ...good, authority: { operationId: "legacy" } }, "authority"],
    [{ ...good, requestAuthority: { requestSHA256: "a".repeat(64) } }, "requestAuthority"],
    [{ ...good, identityDigest: "zz" }, "identityDigest"]
  ];
  for (const [data, field] of bad) {
    await expectTaskPlanError(() => p2Call(db, data), "invalid-argument", { schemaVersion: 1, reason: "REQUEST_INVALID", field });
  }
  await expectTaskPlanError(() => handleTaskPlanRequest({ data: good }, () => db, P2_NOW, { resetProtocolMode: "compat" }), "unauthenticated", { schemaVersion: 1, reason: "AUTH_REQUIRED" });

  // RESET: absent → pending → committed
  const canonical = resetCanonicalId(P2_UID, 4);
  assert.deepEqual(await p2Call(db, good), { schemaVersion: 1, kind: "committed_operation_inspection", accountUid: P2_UID, family: "RESET", authority: { operationId: canonical }, requestAuthority: { requestFingerprint: resetRequestFingerprint(3) }, identityDigest: good.identityDigest, outcome: "absent" });
  const a1 = alias();
  await assert.rejects(handleTaskPlanRequest(p2Request({ action: "resetAllTasks", operationId: a1, reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }), () => db, P2_NOW, { resetProtocolMode: "compat", resetDocumentBudget: 1 }));
  const pending = await p2Call(db, good);
  assert.equal(pending.outcome, "pending");
  assert.equal("receipt" in pending, false);
  await p2Call(db, { action: "resetAllTasks", operationId: a1, reason: "retake_assessment", expectedTaskGenerationEpoch: 3 }, { now: new Date(P2_NOW.getTime() + 11 * 60_000) });
  const final = await p2Call(db, { action: "finalizeTaskReset", operationId: a1, reason: "retake_assessment", expectedTaskGenerationEpoch: 3 });
  const committed = await p2Call(db, good);
  assert.equal(committed.outcome, "committed");
  assert.deepEqual(committed.receipt, { ...final, replayed: true });
  const writesBefore = db.__writes.length;
  await expectTaskPlanError(() => p2Call(db, { ...good, identityDigest: digestOf({ kind: "reset", uid: P2_UID, expectedTaskGenerationEpoch: 9 }) }), "failed-precondition", { schemaVersion: 1, reason: "OPERATION_REUSED", operationId: canonical });
  await expectTaskPlanError(() => p2Call(db, { ...good, requestAuthority: { requestFingerprint: resetRequestFingerprint(9) } }), "failed-precondition", { schemaVersion: 1, reason: "OPERATION_REUSED", operationId: canonical });
  assert.equal((await p2Call(db, good, { uid: "u9" })).outcome, "absent", "another UID reads only its own path");
  assert.equal(db.__writes.length, writesBefore);

  // LEGACY_RESET_MIGRATION: absent then committed with the reconstructed §6.2 response, outer replayed:true
  const mid = migrationIdFor(P2_UID, "legacy-op");
  const legacyInspect = inspect("LEGACY_RESET_MIGRATION", { migrationId: mid }, { requestFingerprint: migrationFingerprintFor(P2_UID, "legacy-op") }, digestOf({ kind: "legacy_reset_migration", uid: P2_UID }));
  const ldb = sharedFirestore({ docs: { "users/u2": { taskGenerationEpoch: 2 } } });
  assert.equal((await p2Call(ldb, legacyInspect)).outcome, "absent");
  const reconciliation = await p2Call(ldb, { action: "reconcileLegacyTaskReset", legacyOperationId: "legacy-op", migrationAlias: alias() });
  const lcommitted = await p2Call(ldb, legacyInspect);
  assert.equal(lcommitted.outcome, "committed");
  assert.deepEqual(lcommitted.receipt, { ...reconciliation, replayed: true });
  await expectTaskPlanError(() => p2Call(ldb, { ...legacyInspect, identityDigest: digestOf({ kind: "legacy_reset_migration", uid: "other" }) }), "failed-precondition", { schemaVersion: 1, reason: "OPERATION_REUSED", operationId: mid });

  // ROUTE_CLAIM / HANDOFF / HANDOFF_CANCEL: generic ordinary records with their documented identity members
  const sha = "b".repeat(64);
  const ordinary = (kind, action, response, taskInstanceId = "inst-1") => ({ schema_version: 1, kind, state: "COMMITTED", account_uid: P2_UID, operation_id: "op-x", action, request_fingerprint: `op1_${sha}`, request_sha256: sha, task_identities: kind === "INTENT_CLAIM" ? [] : [{ role: "TARGET", task_document_id: "t1", task_generation_epoch: 3, task_instance_id: taskInstanceId }], prior_snapshots: [], response, response_sha256: fence.sha256Hex(fence.TaskCanonicalV1(response)), created_at: Timestamp.fromDate(P2_NOW), committed_at: Timestamp.fromDate(P2_NOW) });
  const rows = [
    ["ROUTE_CLAIM", ordinary("INTENT_CLAIM", "claimTaskIntent", { intentId: "int-1", replayed: false }), { kind: "route", intentId: "int-1" }],
    ["HANDOFF", ordinary("TASK_OPERATION", "beginHandoff", { installationId: "i-1", authEpochUUID: "e-1", sessionId: "s-1", replayed: false }), { kind: "handoff", action: "beginHandoff", uid: P2_UID, installationId: "i-1", authEpochUUID: "e-1", taskInstanceId: "inst-1", sessionId: "s-1" }],
    ["HANDOFF_CANCEL", ordinary("TASK_OPERATION", "cancelHandoff", { sessionId: "s-1", reasonCode: "USER", requesterInstallationId: "i-2", requesterAuthEpochUUID: "e-2", replayed: false }), { kind: "handoff_cancel", uid: P2_UID, taskInstanceId: "inst-1", sessionId: "s-1", reasonCode: "USER", requesterInstallationId: "i-2", requesterAuthEpochUUID: "e-2" }]
  ];
  for (const [family, record, identity] of rows) {
    const request = inspect(family, { operationId: "op-x" }, { requestSHA256: sha }, digestOf(identity));
    const absentDb = sharedFirestore({ docs: { "users/u2": {} } });
    assert.equal((await p2Call(absentDb, request)).outcome, "absent", family);
    const presentDb = sharedFirestore({ docs: { "users/u2": {}, "users/u2/taskPlanOperations/op-x": record } });
    const result = await p2Call(presentDb, request);
    assert.equal(result.outcome, "committed", family);
    assert.deepEqual(result.receipt, { ...record.response, replayed: true }, family);
    assert.deepEqual(result.authority, { operationId: "op-x" });
    await expectTaskPlanError(() => p2Call(presentDb, { ...request, requestAuthority: { requestSHA256: "c".repeat(64) } }), "failed-precondition", { schemaVersion: 1, reason: "OPERATION_REUSED", operationId: "op-x" });
    const wrongAction = sharedFirestore({ docs: { "users/u2": {}, "users/u2/taskPlanOperations/op-x": { ...record, action: "somethingElse" } } });
    await expectTaskPlanError(() => p2Call(wrongAction, request), "failed-precondition", { schemaVersion: 1, reason: "OPERATION_REUSED", operationId: "op-x" });
    assert.equal(presentDb.__writes.length, 0);
  }

  // WORKFLOW: derived root path, request-form versus expanded authority, zero taskPlanOperations read
  const token = `workflow-v2-${"d".repeat(64)}`;
  const wsId = `ws2_${fence.first40(fence.sha256Hex(fence.TaskCanonicalV1({ owner: P2_UID, submissionToken: token })))}`;
  const fingerprint = "e".repeat(64);
  const submission = { schema_version: 1, kind: "WORKFLOW_SUBMISSION", owner: P2_UID, submission_token: token, request_fingerprint: fingerprint, task_document_id: "t1", task_instance_id: "inst-1", task_generation_epoch: 3, workflow_id: "wf-1", flow_attempt_id: "fa-1", flow_attempt_generation: 2, workflow_outcome: { outcome: "COMPLETE", replayed: false } };
  const wIdentity = { kind: "workflow", uid: P2_UID, taskDocumentId: "t1", taskInstanceId: "inst-1", taskGenerationEpoch: 3, workflowId: "wf-1", flowAttemptId: "fa-1", flowAttemptGeneration: 2, submissionToken: token };
  const wRequest = inspect("WORKFLOW", { submissionToken: token }, { requestFingerprint: fingerprint }, digestOf(wIdentity));
  const wdb = sharedFirestore({ docs: { "users/u2": {}, [`workflowSubmissions/${wsId}`]: submission, "users/u2/taskPlanOperations/decoy": { kind: "TASK_OPERATION" } } });
  const wResult = await p2Call(wdb, wRequest);
  assert.equal(wResult.outcome, "committed");
  assert.deepEqual(wResult.authority, { submissionToken: token, workflowSubmissionId: wsId });
  assert.deepEqual(wResult.receipt, { outcome: "COMPLETE", replayed: true });
  assert.ok(wdb.__reads.every((p) => !p.includes("/taskPlanOperations/")), "zero taskPlanOperations read for workflow");
  const wrongOwner = sharedFirestore({ docs: { "users/u2": {}, [`workflowSubmissions/${wsId}`]: { ...submission, owner: "u9" } } });
  await expectTaskPlanError(() => p2Call(wrongOwner, wRequest), "failed-precondition", { schemaVersion: 1, reason: "OPERATION_REUSED", submissionToken: token });
  assert.equal((await p2Call(sharedFirestore({ docs: { "users/u2": {} } }), wRequest)).outcome, "absent");
});

// ---------------------------------------------------------------------------
// S3 — frozen reset/inspection/reconciliation wires shared with the Swift decoder mirrors
// (Peezy 4.0Tests/DurableStoreRecoveryTests.swift reads functions/tests/fixtures/resetWiresV1.json).
// Every wire below is produced by the real handler on the shared fake Firestore; the committed
// fixture is asserted byte-equal (FREEZE_RESET_WIRES=1 rewrites it).
// ---------------------------------------------------------------------------

test("frozen reset wires: the committed fixture equals what the handler produces for progress, final, inspection, reconciliation, the marker, and the error table", async () => {
  const fs = require("node:fs");
  const fixturePath = path.join(__dirname, "fixtures", "resetWiresV1.json");
  const uid = RULE_OWNER;
  const aliasP = "rsa1_11111111-1111-4111-8111-111111111111";
  const iso = (value) => (value instanceof Timestamp ? value.toDate().toISOString() : value);
  const plain = (value) => JSON.parse(JSON.stringify(value, (key, v) => (v && typeof v === "object" && typeof v.toDate === "function" ? v.toDate().toISOString() : v)));

  const db = sharedFirestore({ docs: {
    [`users/${uid}`]: { name: "R", taskGenerationEpoch: 1 },
    [`users/${uid}/tasks/a`]: { status: "Upcoming" }, [`users/${uid}/tasks/b`]: { status: "Done" },
    [`users/${uid}/notificationIntents/n`]: { kind: "TASK_RESUME" },
    [`users/${uid}/taskPlanOperations/pcs1_snap`]: { kind: "CONFIRMATION_SNAPSHOT" }
  } });
  const call = (data) => p2Call(db, data, { uid });
  const progress = await call({ action: "resetAllTasks", operationId: aliasP, reason: "retake_assessment", expectedTaskGenerationEpoch: 1 });
  const canonical = resetCanonicalId(uid, 2);
  const marker = plain((await db.doc(`users/${uid}`).get()).data().taskReset);
  const inspection = (data) => call({ action: "inspectCommittedOperation", family: "RESET", identityDigest: fence.sha256Hex(fence.TaskCanonicalV1({ kind: "reset", uid, expectedTaskGenerationEpoch: 1 })), ...data });
  const pending = await inspection({ authority: { operationId: canonical }, requestAuthority: { requestFingerprint: resetRequestFingerprint(1) } });
  const absent = await call({ action: "inspectCommittedOperation", family: "RESET", authority: { operationId: resetCanonicalId(uid, 3) }, requestAuthority: { requestFingerprint: resetRequestFingerprint(2) }, identityDigest: fence.sha256Hex(fence.TaskCanonicalV1({ kind: "reset", uid, expectedTaskGenerationEpoch: 2 })) });
  const final = await call({ action: "finalizeTaskReset", operationId: aliasP, reason: "retake_assessment", expectedTaskGenerationEpoch: 1 });
  const replayedFinal = await call({ action: "finalizeTaskReset", operationId: aliasP, reason: "retake_assessment", expectedTaskGenerationEpoch: 1 });
  const committed = await inspection({ authority: { operationId: canonical }, requestAuthority: { requestFingerprint: resetRequestFingerprint(1) } });

  const reconcile = async (docs, legacyOperationId, migrationAlias) => {
    const rdb = sharedFirestore({ docs });
    return p2Call(rdb, { action: "reconcileLegacyTaskReset", legacyOperationId, migrationAlias }, { uid });
  };
  const aliasM = "rsa1_22222222-2222-4222-8222-222222222222";
  const notDispatched = await reconcile({ [`users/${uid}`]: { taskGenerationEpoch: 1 } }, LEGACY_ID, aliasM);
  const finalizedCompat = await reconcile({ [`users/${uid}`]: { taskGenerationEpoch: 1 }, [`users/${uid}/taskPlanOperations/${LEGACY_ID}`]: legacyOp("finalized", 3) }, LEGACY_ID, aliasM);
  const upgraded = await reconcile({ [`users/${uid}`]: { taskGenerationEpoch: 1, taskReset: legacyMarker(LEGACY_ID, "deleting", 3) }, [`users/${uid}/taskPlanOperations/${LEGACY_ID}`]: legacyOp("deleting", 3), [`users/${uid}/tasks/left`]: { status: "Upcoming" } }, LEGACY_ID, aliasM);
  const activeDb = sharedFirestore({ docs: { [`users/${uid}`]: { taskGenerationEpoch: 1 }, [`users/${uid}/tasks/a`]: { status: "Upcoming" } } });
  await p2Call(activeDb, { action: "resetAllTasks", operationId: aliasP, reason: "retake_assessment", expectedTaskGenerationEpoch: 1 }, { uid });
  const phase2Active = await p2Call(activeDb, { action: "reconcileLegacyTaskReset", legacyOperationId: LEGACY_ID, migrationAlias: aliasM }, { uid });

  const produced = {
    schemaVersion: 1,
    note: "Produced by functions/taskPlan.js handleTaskPlanRequest on the shared fake Firestore for uid phase2-rule-owner at expected epoch 1. Marker instants are ISO strings of the millisecond Timestamps.",
    uid, expectedTaskGenerationEpoch: 1, canonicalOperationId: canonical, requestFingerprint: resetRequestFingerprint(1),
    identityDigest: fence.sha256Hex(fence.TaskCanonicalV1({ kind: "reset", uid, expectedTaskGenerationEpoch: 1 })),
    progressAwaiting: progress,
    progressDeleting: { ...progress, state: "deleting", deletedCount: 1, deletedCounts: { tasks: 1, notificationIntents: 0, taskDeadlineEvidence: 0, confirmationSnapshots: 0 } },
    final, replayedFinal, marker,
    inspection: { pending, absent, committed },
    reconciliation: { notDispatched, finalizedCompat, upgraded, phase2Active },
    parity: { uid: RULE_OWNER, legacyOperationId: LEGACY_ID, migrationId: migrationIdFor(RULE_OWNER, LEGACY_ID), requestFingerprint: migrationFingerprintFor(RULE_OWNER, LEGACY_ID) },
    errors: [
      { code: "unauthenticated", details: { schemaVersion: 1, reason: "AUTH_REQUIRED" } },
      { code: "invalid-argument", details: { schemaVersion: 1, reason: "REQUEST_INVALID", field: "migrationAlias" } },
      { code: "failed-precondition", details: { schemaVersion: 1, reason: "OPERATION_REUSED", operationId: canonical } },
      { code: "failed-precondition", details: { schemaVersion: 1, reason: "LEGACY_RESET_CORRUPT", context: "reconcile", legacyOperationId: LEGACY_ID, recordClass: "deleting", markerClass: "absent" } },
      { code: "failed-precondition", details: { schemaVersion: 1, reason: "LEGACY_RESET_CORRUPT", context: "inspect", recordClass: "phase2", markerClass: "malformed" } },
      { code: "failed-precondition", details: { schemaVersion: 1, reason: "LEGACY_RESET_MIGRATION_REQUIRED", legacyOperationId: LEGACY_ID } },
      { code: "failed-precondition", details: { schemaVersion: 1, reason: "LEGACY_RESET_ALIAS_OCCUPIED", legacyOperationId: LEGACY_ID, migrationAlias: aliasM } },
      { code: "failed-precondition", details: { schemaVersion: 1, reason: "CLIENT_UPGRADE_REQUIRED", requiredProtocol: "phase2" } },
      { code: "failed-precondition", details: { schemaVersion: 1, reason: "STALE_STATE" } },
      { code: "failed-precondition", details: { schemaVersion: 1, reason: "RESET_ACTIVE", operationId: canonical, expectedTaskGenerationEpoch: 1 } }
    ]
  };
  assert.equal(progress.state, "awaiting_local_reset");
  assert.equal(final.replayed, false);
  assert.equal(replayedFinal.replayed, true);
  assert.equal(pending.outcome, "pending"); assert.equal(absent.outcome, "absent"); assert.equal(committed.outcome, "committed");
  assert.deepEqual(committed.receipt, { ...final, replayed: true });
  assert.deepEqual([notDispatched.outcome, finalizedCompat.outcome, upgraded.outcome, phase2Active.outcome], ["not_dispatched", "finalized_compat", "upgraded", "phase2_active"]);
  const bytes = JSON.stringify(produced, null, 2) + "\n";
  if (process.env.FREEZE_RESET_WIRES === "1" || !fs.existsSync(fixturePath)) fs.writeFileSync(fixturePath, bytes);
  assert.equal(fs.readFileSync(fixturePath, "utf8"), bytes, "committed fixture equals the live wires (FREEZE_RESET_WIRES=1 to rewrite)");
});
