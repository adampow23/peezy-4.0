"use strict";

const { randomUUID, createHash } = require("node:crypto");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {
  buildCompletedContract,
  buildTerminalContract,
  buildUserActionContract,
  buildWaitingOnExternalContract,
  validateDispositionContract,
  validateTrigger
} = require("./dispositionContract");
const {
  buildTaskDoc,
  canonicalJSON,
  dateFromValue,
  isValidDocumentId,
  resolveDueDate,
  spawnTitle,
  validateRequest: validateSpawnRequest
} = require("./spawnTasks");

if (!admin.apps.length) admin.initializeApp();

const ACTIONS = new Set([
  "supersede", "confirmAmendment", "undoConfirmation", "reopen",
  "resetAllTasks", "finalizeTaskReset"
]);
const RESET_REASON = "retake_assessment";
const MAX_HISTORY = 50;
const LEASE_MS = 10 * 60 * 1000;
const PAGE_SIZE = 400;

class TaskPlanValidationError extends Error {}

function sha256(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function cloneFirestoreData(value) {
  if (value === null || typeof value !== "object") return value;
  const date = dateFromValue(value);
  if (date) return new Date(date.getTime());
  if (Array.isArray(value)) return value.map(cloneFirestoreData);
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, cloneFirestoreData(item)]));
}

function normalizeFingerprintValue(value) {
  if (value === null || typeof value !== "object") return value;
  const date = dateFromValue(value);
  if (date) return { __type: "firestore_timestamp", iso: date.toISOString() };
  if (Array.isArray(value)) return value.map(normalizeFingerprintValue);
  return Object.fromEntries(
    Object.entries(value).map(([key, item]) => [key, normalizeFingerprintValue(item)])
  );
}

function canonicalTaskPlanJSON(value) {
  return canonicalJSON(normalizeFingerprintValue(value));
}

function failValidation(message) {
  throw new TaskPlanValidationError(message);
}

function failPrecondition(message) {
  throw new HttpsError("failed-precondition", message);
}

function cleanDocId(value, field) {
  if (typeof value !== "string" || !value.trim() || !isValidDocumentId(value.trim())) {
    failValidation(`${field} must be a valid Firestore document ID`);
  }
  return value.trim();
}

function cleanReason(value) {
  if (typeof value !== "string" || !value.trim() || Buffer.byteLength(value.trim(), "utf8") > 1000) {
    failValidation("reason must be nonempty and at most 1000 bytes");
  }
  return value.trim();
}

function cleanDescriptor(value, field, now) {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      typeof value.resumeDestination !== "string" || !value.resumeDestination.trim() ||
      !value.nextTrigger) {
    failValidation(`${field} requires nextTrigger and resumeDestination`);
  }
  try {
    validateTrigger(value.nextTrigger, now);
  } catch (error) {
    failValidation(`${field}: ${error.message}`);
  }
  return {
    nextTrigger: cloneFirestoreData(value.nextTrigger),
    resumeDestination: value.resumeDestination.trim()
  };
}

function cleanReplacement(value, now) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    failValidation("replacement must be a map");
  }
  let cleanedSpawn;
  try {
    cleanedSpawn = validateSpawnRequest({
      token: "replacement-validation",
      source: { kind: "conversation", id: "task-plan" },
      spawns: [{
        taskId: value.taskId,
        subject: value.subject,
        institutionId: value.institutionId,
        institution: value.institution,
        titleParams: { institution: value.institution }
      }]
    }).spawns[0];
  } catch (error) {
    failValidation(`replacement identity is invalid: ${error.message}`);
  }
  if (!value.amendmentAction || !value.verification) {
    failValidation("replacement requires amendmentAction and verification");
  }
  return {
    taskId: cleanedSpawn.taskId,
    subject: cleanedSpawn.subject,
    institutionId: cleanedSpawn.institutionId,
    institution: cleanedSpawn.institution,
    amendmentAction: cleanDescriptor(value.amendmentAction, "amendmentAction", now),
    verification: cleanDescriptor(value.verification, "verification", now)
  };
}

function validateTaskPlanRequest(data, now = new Date()) {
  const input = data || {};
  if (!ACTIONS.has(input.action)) failValidation("action is not supported");
  const operationId = cleanDocId(input.operationId, "operationId");
  const reason = cleanReason(input.reason);
  const reset = input.action === "resetAllTasks" || input.action === "finalizeTaskReset";
  if (reset) {
    if (reason !== RESET_REASON) failValidation("Reset reason must be retake_assessment");
    if (input.taskId !== undefined || input.replacement !== undefined) {
      failValidation("Reset actions do not accept taskId or replacement");
    }
    return { action: input.action, operationId, reason };
  }
  const cleaned = {
    action: input.action,
    taskId: cleanDocId(input.taskId, "taskId"),
    operationId,
    reason
  };
  if (input.replacement !== undefined) cleaned.replacement = cleanReplacement(input.replacement, now);
  if (input.action !== "supersede" && input.replacement !== undefined) {
    failValidation("Only supersede accepts replacement");
  }
  return cleaned;
}

function operationFingerprint(request) {
  return `op1_${sha256(canonicalTaskPlanJSON(request))}`;
}

function resetFingerprint(request) {
  return `reset1_${sha256(canonicalTaskPlanJSON({ kind: "reset", reason: request.reason }))}`;
}

function canonicalAmendmentId(uid, originalTaskId, revision, replacement) {
  return `a2_${sha256(canonicalTaskPlanJSON({
    uid,
    originalTaskId,
    revision,
    subject: replacement.subject,
    institutionId: replacement.institutionId,
    taskId: replacement.taskId
  })).slice(0, 40)}`;
}

function appendHistory(task, record) {
  const history = Array.isArray(task.planChangeHistory) ? task.planChangeHistory : [];
  if (history.length >= MAX_HISTORY) failPrecondition("Plan-change history is full");
  return [...history, record];
}

function resetIsActive(root) {
  const state = root?.taskReset?.state;
  return state === "deleting" || state === "awaiting_local_reset";
}

function responseReplay(response) {
  return { ...response, replayed: true };
}

function exactReplay(operation, fingerprint) {
  if (!operation) return null;
  if (operation.kind !== "operation" || operation.fingerprint !== fingerprint) {
    failPrecondition("Operation ID was already used for a different request");
  }
  return responseReplay(operation.response);
}

function cycleRecord(task) {
  const history = Array.isArray(task.planChangeHistory) ? task.planChangeHistory : [];
  return [...history].reverse().find((row) =>
    row.action === "supersede" && row.revision === task.planChangeRevision
  );
}

function actionContract(uid, institution, descriptor, now) {
  return buildUserActionContract({}, {
    owner: `user:${uid}`,
    nextAction: `Submit the amendment to ${institution}`,
    nextTrigger: cloneFirestoreData(descriptor.nextTrigger),
    resumeDestination: descriptor.resumeDestination,
    visibleStatusCopy: `Amendment ready to submit to ${institution}`
  }, now);
}

function verificationActionContract(uid, institution, descriptor, now) {
  return buildUserActionContract({}, {
    owner: `user:${uid}`,
    nextAction: `Check the amendment status with ${institution}`,
    nextTrigger: cloneFirestoreData(descriptor.nextTrigger),
    resumeDestination: descriptor.resumeDestination,
    visibleStatusCopy: `Verify whether ${institution} kept the amendment`
  }, now);
}

function waitingContract(base, institution, descriptor, now, undo = false) {
  return buildWaitingOnExternalContract(base, {
    owner: institution,
    nextAction: undo
      ? "Confirm whether the amendment remained in effect"
      : "Review and apply the requested amendment",
    nextTrigger: cloneFirestoreData(descriptor.nextTrigger),
    resumeDestination: descriptor.resumeDestination,
    visibleStatusCopy: undo
      ? `Confirm whether ${institution} kept the amendment`
      : `Your existing submission is still active; confirm the amendment with ${institution}.`,
    externalSubmission: true
  }, now);
}

function documentFingerprint(task, excluded = []) {
  const omitted = new Set(excluded);
  return sha256(canonicalTaskPlanJSON(Object.fromEntries(
    Object.entries(task || {}).filter(([key]) => !omitted.has(key))
  )));
}

function operationRef(userRef, operationId) {
  return userRef.collection("taskPlanOperations").doc(operationId);
}

function deleteValue() {
  return admin.firestore.FieldValue.delete();
}

async function executeLifecycle(db, uid, request, now) {
  const userRef = db.collection("users").doc(uid);
  const taskRef = userRef.collection("tasks").doc(request.taskId);
  const opRef = operationRef(userRef, request.operationId);
  const fingerprint = operationFingerprint(request);

  return db.runTransaction(async (transaction) => {
    const opSnapshot = await transaction.get(opRef);
    if (opSnapshot.exists) return exactReplay(opSnapshot.data(), fingerprint);

    const rootSnapshot = await transaction.get(userRef);
    const root = rootSnapshot.data() || {};
    if (resetIsActive(root)) failPrecondition("Task reset is active");
    const taskSnapshot = await transaction.get(taskRef);
    if (!taskSnapshot.exists) throw new HttpsError("not-found", "Task was not found");
    const task = taskSnapshot.data() || {};
    if (task.dispositionContract !== undefined) {
      validateDispositionContract(task.status, task.dispositionContract, now);
    }

    const state = task.planChangeState;
    const revision = Number.isSafeInteger(task.planChangeRevision) ? task.planChangeRevision : 0;
    let amendmentRef = null;
    let amendmentSnapshot = null;
    let catalogSnapshot = null;
    let identitySnapshot = null;
    let assessmentSnapshot = null;

    if (request.action === "supersede" && task.dispositionContract?.external_submission === true) {
      if (!request.replacement) failPrecondition("External submissions require a replacement");
      if (request.replacement.taskId === task.taskId) failPrecondition("Replacement catalog task must differ");
      const nextRevision = revision + 1;
      amendmentRef = userRef.collection("tasks").doc(
        canonicalAmendmentId(uid, request.taskId, nextRevision, request.replacement)
      );
      catalogSnapshot = await transaction.get(db.collection("taskCatalog").doc(request.replacement.taskId));
      identitySnapshot = await transaction.get(userRef.collection("identity").doc("identity"));
      assessmentSnapshot = await transaction.get(userRef.collection("user_assessments").limit(1));
      amendmentSnapshot = await transaction.get(amendmentRef);
    } else if (["confirmAmendment", "undoConfirmation"].includes(request.action) ||
        (request.action === "reopen" && state === "pending_amendment")) {
      if (!task.pendingAmendmentTaskId) failPrecondition("Pending amendment pointer is missing");
      amendmentRef = userRef.collection("tasks").doc(task.pendingAmendmentTaskId);
      amendmentSnapshot = await transaction.get(amendmentRef);
    }

    const at = now;
    let response;
    if (request.action === "supersede") {
      if (![undefined, null, "reopened"].includes(state)) {
        failPrecondition("Task cannot be superseded from its current state");
      }
      const external = task.dispositionContract?.external_submission === true;
      if (!external && request.replacement) failPrecondition("Internal supersede forbids replacement");
      const nextRevision = revision + 1;
      const record = {
        action: "supersede",
        reason: request.reason,
        at,
        revision: nextRevision,
        priorStatus: task.status,
        ...(task.dispositionContract === undefined ? {} : {
          priorDispositionContract: cloneFirestoreData(task.dispositionContract)
        })
      };
      if (!external) {
        const contract = buildTerminalContract(task.dispositionContract || {}, "retired", "Retired");
        validateDispositionContract("Dismissed", contract, now);
        transaction.update(taskRef, {
          status: "Dismissed",
          dispositionContract: contract,
          planChangeRevision: nextRevision,
          planChangeState: "retired",
          planChangeHistory: appendHistory(task, { ...record, replacementTaskId: null }),
          pendingAmendmentTaskId: deleteValue()
        });
        response = {
          taskId: request.taskId,
          status: "Dismissed",
          replacementTaskId: null,
          lifecycleState: "retired",
          revision: nextRevision,
          replayed: false
        };
      } else {
        if (!catalogSnapshot.exists) throw new HttpsError("not-found", "Replacement catalog row was not found");
        const replacement = request.replacement;
        const originalContract = waitingContract(
          task.dispositionContract,
          replacement.institution,
          replacement.verification,
          now
        );
        const amendmentContract = actionContract(
          uid, replacement.institution, replacement.amendmentAction, now
        );
        const catalog = catalogSnapshot.data() || {};
        const identityMoveDate = dateFromValue(identitySnapshot.data()?.moveDate);
        const assessment = assessmentSnapshot.empty
          ? {}
          : (assessmentSnapshot.docs[0]?.data() || {});
        const dueDate = resolveDueDate(
          catalog,
          identityMoveDate || dateFromValue(assessment.moveDate),
          now
        );
        const title = spawnTitle(catalog, { institution: replacement.institution });
        const amendmentDoc = {
          ...buildTaskDoc({
            row: catalog,
            docId: amendmentRef.id,
            userId: uid,
            title,
            dueDate,
            source: { kind: "conversation", id: request.taskId },
            now,
            spawn: replacement
          }),
          status: "InProgress",
          supersedes: request.taskId,
          planChangeRevision: nextRevision,
          dispositionContract: amendmentContract
        };
        let acceptedAmendmentDoc = amendmentDoc;
        if (amendmentSnapshot.exists) {
          const existing = amendmentSnapshot.data() || {};
          const reusable = existing.id === amendmentRef.id && existing.userId === uid &&
            existing.taskId === replacement.taskId && existing.supersedes === request.taskId &&
            existing.planChangeRevision === nextRevision && existing.status === "InProgress" &&
            existing.canonicalKeyVersion === 2 &&
            canonicalTaskPlanJSON(existing.subject) === canonicalTaskPlanJSON(replacement.subject) &&
            existing.institutionId === replacement.institutionId &&
            existing.institution === replacement.institution &&
            canonicalTaskPlanJSON(existing.spawnedFrom) === canonicalTaskPlanJSON({
              kind: "conversation", id: request.taskId
            }) &&
            canonicalTaskPlanJSON(existing.dispositionContract) === canonicalTaskPlanJSON(amendmentContract);
          if (!reusable) failPrecondition("Amendment document collision");
          acceptedAmendmentDoc = existing;
        } else {
          transaction.create(amendmentRef, amendmentDoc);
        }
        const cycle = {
          ...record,
          replacementTaskId: amendmentRef.id,
          replacement: cloneFirestoreData(replacement),
          amendmentBaselineFingerprint: documentFingerprint(acceptedAmendmentDoc)
        };
        transaction.update(taskRef, {
          status: "matching_in_progress",
          dispositionContract: originalContract,
          planChangeRevision: nextRevision,
          planChangeState: "pending_amendment",
          planChangeHistory: appendHistory(task, cycle),
          pendingAmendmentTaskId: amendmentRef.id,
          confirmationUndoUsed: false,
          firstConfirmationUndoUntil: deleteValue()
        });
        response = {
          taskId: request.taskId,
          status: "matching_in_progress",
          replacementTaskId: amendmentRef.id,
          lifecycleState: "pending_amendment",
          revision: nextRevision,
          replayed: false
        };
      }
    } else if (request.action === "confirmAmendment") {
      if (!["pending_amendment", "pending_confirmation"].includes(state) || !amendmentSnapshot?.exists) {
        failPrecondition("Task has no confirmable amendment");
      }
      const amendment = amendmentSnapshot.data() || {};
      const cycle = cycleRecord(task);
      if (!cycle || amendment.supersedes !== request.taskId || amendment.planChangeRevision !== revision) {
        failPrecondition("Amendment provenance is invalid");
      }
      const originalContract = buildTerminalContract(
        { ...(task.dispositionContract || {}), superseded_by: amendmentRef.id },
        "superseded",
        `Replaced — ${now.toISOString().slice(0, 10)}`
      );
      const completedContract = buildCompletedContract(
        amendment.dispositionContract || {},
        `Amendment submitted to ${cycle.replacement.institution}`
      );
      const firstDeadline = dateFromValue(task.firstConfirmationUndoUntil) ||
        new Date(now.getTime() + 5 * 60 * 1000);
      const confirmationRecord = {
        action: state === "pending_confirmation" ? "reconfirm" : "confirm",
        reason: request.reason,
        at,
        revision,
        replacementTaskId: amendmentRef.id
      };
      const confirmationHistory = appendHistory(task, confirmationRecord);
      const originalNext = {
        ...task,
        status: "Dismissed",
        dispositionContract: originalContract,
        planChangeState: "confirmed",
        planChangeHistory: confirmationHistory,
        firstConfirmationUndoUntil: firstDeadline
      };
      const amendmentNext = {
        ...amendment,
        status: "Completed",
        dispositionContract: completedContract
      };
      transaction.update(taskRef, {
        status: "Dismissed",
        dispositionContract: originalContract,
        planChangeState: "confirmed",
        planChangeHistory: confirmationHistory,
        firstConfirmationUndoUntil: firstDeadline,
        confirmationOriginalFingerprint: documentFingerprint(originalNext, [
          "confirmationOriginalFingerprint", "confirmationAmendmentFingerprint"
        ]),
        confirmationAmendmentFingerprint: documentFingerprint(amendmentNext)
      });
      transaction.update(amendmentRef, {
        status: "Completed",
        dispositionContract: completedContract
      });
      response = {
        taskId: request.taskId,
        status: "Dismissed",
        replacementTaskId: amendmentRef.id,
        lifecycleState: "confirmed",
        revision,
        replayed: false
      };
    } else if (request.action === "undoConfirmation") {
      if (state !== "confirmed" || !amendmentSnapshot?.exists || task.confirmationUndoUsed === true) {
        failPrecondition("Confirmation cannot be undone");
      }
      const deadline = dateFromValue(task.firstConfirmationUndoUntil);
      if (!deadline || now.getTime() > deadline.getTime()) failPrecondition("Confirmation undo window expired");
      const amendment = amendmentSnapshot.data() || {};
      if (task.confirmationOriginalFingerprint !== documentFingerprint(task, [
        "confirmationOriginalFingerprint", "confirmationAmendmentFingerprint"
      ]) || task.confirmationAmendmentFingerprint !== documentFingerprint(amendment)) {
        failPrecondition("Task changed after confirmation");
      }
      const cycle = cycleRecord(task);
      if (!cycle) failPrecondition("Plan-change cycle is missing");
      const originalContract = waitingContract(
        task.dispositionContract,
        cycle.replacement.institution,
        cycle.replacement.verification,
        now,
        true
      );
      const amendmentContract = verificationActionContract(
        uid,
        cycle.replacement.institution,
        cycle.replacement.verification,
        now
      );
      transaction.update(taskRef, {
        status: "matching_in_progress",
        dispositionContract: originalContract,
        planChangeState: "pending_confirmation",
        planChangeHistory: appendHistory(task, {
          action: "undo_confirmation",
          reason: request.reason,
          at,
          revision,
          replacementTaskId: amendmentRef.id
        }),
        confirmationUndoUsed: true,
        confirmationOriginalFingerprint: deleteValue(),
        confirmationAmendmentFingerprint: deleteValue()
      });
      transaction.update(amendmentRef, {
        status: "InProgress",
        dispositionContract: amendmentContract
      });
      response = {
        taskId: request.taskId,
        status: "matching_in_progress",
        replacementTaskId: amendmentRef.id,
        lifecycleState: "pending_confirmation",
        revision,
        replayed: false
      };
    } else if (request.action === "reopen") {
      if (!["retired", "pending_amendment"].includes(state)) {
        failPrecondition("Task cannot be reopened from its current state");
      }
      const cycle = cycleRecord(task);
      if (!cycle) failPrecondition("Plan-change cycle is missing");
      if (cycle.priorDispositionContract !== undefined) {
        validateDispositionContract(
          cycle.priorStatus,
          cycle.priorDispositionContract,
          now
        );
      }
      if (state === "pending_amendment") {
        if (!amendmentSnapshot?.exists ||
            documentFingerprint(amendmentSnapshot.data() || {}) !== cycle.amendmentBaselineFingerprint) {
          failPrecondition("Amendment has progressed and cannot be cancelled");
        }
      }
      const originalUpdate = {
        status: cycle.priorStatus,
        dispositionContract: cycle.priorDispositionContract === undefined
          ? deleteValue()
          : cloneFirestoreData(cycle.priorDispositionContract),
        planChangeState: "reopened",
        planChangeHistory: appendHistory(task, {
          action: "reopen",
          reason: request.reason,
          at,
          revision,
          replacementTaskId: cycle.replacementTaskId
        }),
        pendingAmendmentTaskId: deleteValue()
      };
      transaction.update(taskRef, originalUpdate);
      if (state === "pending_amendment") {
        const cancelled = buildTerminalContract(
          amendmentSnapshot.data()?.dispositionContract || {},
          "retired",
          "Amendment cancelled"
        );
        transaction.update(amendmentRef, {
          status: "Dismissed",
          dispositionContract: cancelled
        });
      }
      response = {
        taskId: request.taskId,
        status: cycle.priorStatus,
        replacementTaskId: null,
        lifecycleState: "reopened",
        revision,
        replayed: false
      };
    } else {
      failPrecondition("Unsupported transition");
    }

    transaction.create(opRef, {
      kind: "operation",
      fingerprint,
      response,
      at
    });
    return response;
  });
}

function leaseExpiry(value) {
  return dateFromValue(value)?.getTime() || 0;
}

async function listTaskRefs(db, userRef, transaction = null) {
  if (typeof db.__phase1ListTaskRefs === "function") {
    return db.__phase1ListTaskRefs(userRef, PAGE_SIZE, transaction);
  }
  const query = userRef.collection("tasks")
    .orderBy(admin.firestore.FieldPath.documentId())
    .limit(PAGE_SIZE);
  const snapshot = transaction ? await transaction.get(query) : await query.get();
  return snapshot.docs.map((doc) => doc.ref);
}

async function initializeOrReplayReset(db, uid, request, now) {
  const userRef = db.collection("users").doc(uid);
  const opRef = operationRef(userRef, request.operationId);
  const fingerprint = resetFingerprint(request);
  return db.runTransaction(async (transaction) => {
    const opSnapshot = await transaction.get(opRef);
    const rootSnapshot = await transaction.get(userRef);
    const root = rootSnapshot.data() || {};
    if (opSnapshot.exists) {
      const op = opSnapshot.data() || {};
      if (op.kind !== "reset" || op.fingerprint !== fingerprint) {
        failPrecondition("Operation ID was already used for a different request");
      }
      if (op.finalized) return { done: true, response: responseReplay(op.finalized) };
      if (op.tasks_deleted) return { done: true, response: responseReplay(op.tasks_deleted) };
      if (root.taskReset?.operationId !== request.operationId) {
        failPrecondition("Reset marker does not match operation");
      }
      return { done: false, userRef, opRef, fingerprint };
    }
    if (root.taskReset) failPrecondition("Another task reset is active");
    const marker = {
      operationId: request.operationId,
      state: "deleting",
      deletedCount: 0,
      workerLease: null,
      startedAt: now
    };
    transaction.set(userRef, { taskReset: marker }, { merge: true });
    transaction.create(opRef, {
      kind: "reset",
      fingerprint,
      deletedCount: 0,
      state: "deleting",
      at: now
    });
    return { done: false, userRef, opRef, fingerprint };
  });
}

async function acquireResetLease(db, userRef, opRef, operationId, workerId, now) {
  return db.runTransaction(async (transaction) => {
    const rootSnapshot = await transaction.get(userRef);
    const opSnapshot = await transaction.get(opRef);
    const marker = rootSnapshot.data()?.taskReset;
    if (!marker || marker.operationId !== operationId || marker.state !== "deleting" || !opSnapshot.exists) {
      failPrecondition("Reset is not in deleting phase");
    }
    const lease = marker.workerLease;
    if (lease?.workerId && lease.workerId !== workerId && leaseExpiry(lease.expiresAt) > now.getTime()) {
      throw new HttpsError("unavailable", "Another reset worker owns the live lease");
    }
    const nextLease = { workerId, expiresAt: new Date(now.getTime() + LEASE_MS) };
    transaction.update(userRef, { "taskReset.workerLease": nextLease });
    return nextLease;
  });
}

async function deleteResetPage(db, userRef, opRef, operationId, workerId, refs, now) {
  return db.runTransaction(async (transaction) => {
    const rootSnapshot = await transaction.get(userRef);
    const opSnapshot = await transaction.get(opRef);
    const marker = rootSnapshot.data()?.taskReset;
    const op = opSnapshot.data() || {};
    if (!marker || marker.operationId !== operationId || marker.state !== "deleting" ||
        marker.workerLease?.workerId !== workerId ||
        leaseExpiry(marker.workerLease?.expiresAt) <= now.getTime()) {
      failPrecondition("Reset worker no longer owns the lease");
    }
    const snapshots = [];
    for (const ref of refs) snapshots.push(await transaction.get(ref));
    let count = 0;
    for (const [index, ref] of refs.entries()) {
      if (snapshots[index].exists) {
        transaction.delete(ref);
        count += 1;
      }
    }
    const cumulative = Number(marker.deletedCount || 0) + count;
    const nextLease = { workerId, expiresAt: new Date(now.getTime() + LEASE_MS) };
    transaction.update(userRef, {
      "taskReset.deletedCount": cumulative,
      "taskReset.workerLease": nextLease
    });
    transaction.update(opRef, { deletedCount: cumulative });
    return cumulative;
  });
}

async function finishResetDeletion(db, userRef, opRef, operationId, workerId, now) {
  return db.runTransaction(async (transaction) => {
    const rootSnapshot = await transaction.get(userRef);
    const opSnapshot = await transaction.get(opRef);
    const marker = rootSnapshot.data()?.taskReset;
    if (!marker || marker.operationId !== operationId || marker.state !== "deleting" ||
        marker.workerLease?.workerId !== workerId ||
        leaseExpiry(marker.workerLease?.expiresAt) <= now.getTime() || !opSnapshot.exists) {
      failPrecondition("Reset worker no longer owns the phase transition");
    }
    const remaining = await listTaskRefs(db, userRef, transaction);
    if (remaining.length !== 0) failPrecondition("Task reset still has rows to delete");
    const response = {
      reset: true,
      deletedCount: Number(marker.deletedCount || 0),
      replayed: false
    };
    transaction.update(userRef, {
      "taskReset.state": "awaiting_local_reset",
      "taskReset.workerLease": null,
      "taskReset.deletedCount": response.deletedCount
    });
    transaction.update(opRef, {
      state: "tasks_deleted",
      tasks_deleted: response,
      deletedCount: response.deletedCount
    });
    return response;
  });
}

async function executeResetAllTasks(db, uid, request, now) {
  const initialized = await initializeOrReplayReset(db, uid, request, now);
  if (initialized.done) return initialized.response;
  const { userRef, opRef } = initialized;
  const workerId = randomUUID();
  await acquireResetLease(db, userRef, opRef, request.operationId, workerId, now);
  let pageNow = now;
  while (true) {
    const refs = await listTaskRefs(db, userRef);
    if (refs.length === 0) break;
    await deleteResetPage(db, userRef, opRef, request.operationId, workerId, refs, pageNow);
    pageNow = new Date(pageNow.getTime() + 1);
  }
  return finishResetDeletion(db, userRef, opRef, request.operationId, workerId, pageNow);
}

async function executeFinalizeReset(db, uid, request, now) {
  const userRef = db.collection("users").doc(uid);
  const opRef = operationRef(userRef, request.operationId);
  const fingerprint = resetFingerprint(request);
  return db.runTransaction(async (transaction) => {
    const opSnapshot = await transaction.get(opRef);
    if (!opSnapshot.exists) failPrecondition("Reset operation was not found");
    const op = opSnapshot.data() || {};
    if (op.kind !== "reset" || op.fingerprint !== fingerprint) {
      failPrecondition("Operation ID was already used for a different request");
    }
    if (op.finalized) return responseReplay(op.finalized);
    const rootSnapshot = await transaction.get(userRef);
    const marker = rootSnapshot.data()?.taskReset;
    if (!op.tasks_deleted || !marker || marker.operationId !== request.operationId ||
        marker.state !== "awaiting_local_reset") {
      failPrecondition("Local reset cannot be finalized yet");
    }
    const response = {
      reset: true,
      deletedCount: Number(op.deletedCount || marker.deletedCount || 0),
      replayed: false
    };
    transaction.update(userRef, { taskReset: deleteValue() });
    transaction.update(opRef, { state: "finalized", finalized: response, finalizedAt: now });
    return response;
  });
}

async function handleTaskPlanRequest(request, dbFactory = () => admin.firestore(), now = new Date()) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in before changing a task plan");
  let cleaned;
  try {
    cleaned = validateTaskPlanRequest(request.data, now);
  } catch (error) {
    if (error instanceof TaskPlanValidationError) {
      throw new HttpsError("invalid-argument", error.message);
    }
    throw error;
  }
  const db = dbFactory();
  if (cleaned.action === "resetAllTasks") return executeResetAllTasks(db, uid, cleaned, now);
  if (cleaned.action === "finalizeTaskReset") return executeFinalizeReset(db, uid, cleaned, now);
  return executeLifecycle(db, uid, cleaned, now);
}

const changeTaskPlan = onCall(
  { region: "us-central1", timeoutSeconds: 540, memory: "512MiB" },
  (request) => handleTaskPlanRequest(request)
);

module.exports = {
  TaskPlanValidationError,
  acquireResetLease,
  canonicalTaskPlanJSON,
  canonicalAmendmentId,
  changeTaskPlan,
  cleanReplacement,
  deleteResetPage,
  executeFinalizeReset,
  executeLifecycle,
  executeResetAllTasks,
  finishResetDeletion,
  handleTaskPlanRequest,
  normalizeFingerprintValue,
  operationFingerprint,
  resetFingerprint,
  validateTaskPlanRequest
};
