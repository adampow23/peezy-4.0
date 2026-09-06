"use strict";

const { randomUUID, createHash } = require("node:crypto");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { Timestamp } = require("firebase-admin/firestore");
const fence = require("./accountDeletionFence");
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

class TaskPlanValidationError extends Error {
  constructor(message, details) {
    super(message);
    this.details = details;
  }
}

function failRequestInvalid(field) {
  throw new TaskPlanValidationError(`${field} is invalid`, { schemaVersion: 1, reason: "REQUEST_INVALID", field });
}

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

const PHASE2_RESET_REQUEST_KEYS = ["action", "operationId", "reason", "expectedTaskGenerationEpoch"];

function validatePhase2ResetRequest(input) {
  if (Object.keys(input).some((key) => !PHASE2_RESET_REQUEST_KEYS.includes(key))) failRequestInvalid("request");
  if (typeof input.operationId !== "string" || !RESET_ALIAS_RE.test(input.operationId)) failRequestInvalid("operationId");
  if (input.reason !== RESET_REASON) failRequestInvalid("reason");
  const e = input.expectedTaskGenerationEpoch;
  if (!Number.isSafeInteger(e) || e < 0 || !Number.isSafeInteger(e + 1)) failRequestInvalid("expectedTaskGenerationEpoch");
  return { action: input.action, operationId: input.operationId, reason: input.reason, expectedTaskGenerationEpoch: e };
}

function validateTaskPlanRequest(data, now = new Date()) {
  const input = data || {};
  if (!ACTIONS.has(input.action)) failValidation("action is not supported");
  const reset = input.action === "resetAllTasks" || input.action === "finalizeTaskReset";
  if (reset && input.expectedTaskGenerationEpoch !== undefined) return validatePhase2ResetRequest(input);
  const operationId = cleanDocId(input.operationId, "operationId");
  // Reserved Phase 2 namespaces are rejected on every client ID surface after normalization (v9 §6.2:622, spec v5 §693).
  if (RESERVED_ID_RE.test(operationId)) failRequestInvalid("operationId");
  const reason = cleanReason(input.reason);
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
    assertRootNotFenced(rootSnapshot);
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

async function initializeOrReplayReset(db, uid, request, now, mode = "compat") {
  const userRef = db.collection("users").doc(uid);
  const opRef = operationRef(userRef, request.operationId);
  const fingerprint = resetFingerprint(request);
  return db.runTransaction(async (transaction) => {
    const opSnapshot = await transaction.get(opRef);
    const rootSnapshot = await transaction.get(userRef);
    assertRootNotFenced(rootSnapshot);
    const root = rootSnapshot.data() || {};
    if (!opSnapshot.exists && mode === "phase2_required") {
      throw failedPrecondition("CLIENT_UPGRADE_REQUIRED", { requiredProtocol: "phase2" });
    }
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
    assertRootNotFenced(rootSnapshot);
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
    assertRootNotFenced(rootSnapshot);
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
    assertRootNotFenced(rootSnapshot);
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

async function executeResetAllTasks(db, uid, request, now, mode = "compat") {
  const initialized = await initializeOrReplayReset(db, uid, request, now, mode);
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
    const rootSnapshot = await transaction.get(userRef);
    assertRootNotFenced(rootSnapshot);
    const opSnapshot = await transaction.get(opRef);
    if (!opSnapshot.exists) failPrecondition("Reset operation was not found");
    const op = opSnapshot.data() || {};
    if (op.kind !== "reset" || op.fingerprint !== fingerprint) {
      failPrecondition("Operation ID was already used for a different request");
    }
    if (op.finalized) return responseReplay(op.finalized);
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

// ---------------------------------------------------------------------------
// Phase 2 reset protocol (PHASE2_CONTRACT.md C2.8; Reconciled 9): deterministic
// per-epoch rso1_ record, Reconciled 9 marker projection, receipts, four-target
// leased reducer, digest-bound tombstone. The raw legacy path above is byte-preserved
// under PHASE2_RESET_PROTOCOL_MODE=compat.
// ---------------------------------------------------------------------------

const RESET_PROTOCOL_MODES = Object.freeze(["compat", "phase2_required"]);

function readResetProtocolMode() {
  const value = process.env.PHASE2_RESET_PROTOCOL_MODE;
  if (value === undefined) return undefined;
  if (!RESET_PROTOCOL_MODES.includes(value)) {
    throw new Error(`PHASE2_RESET_PROTOCOL_MODE must be one of ${RESET_PROTOCOL_MODES.join("|")}; got ${JSON.stringify(value)}`);
  }
  return value;
}

// Fails module initialization on an unknown value (v9 §6.4:697); absence refuses every reset handler.
const ENV_RESET_PROTOCOL_MODE = readResetProtocolMode();

const RESET_ALIAS_RE = /^rsa1_[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const RESERVED_ID_RE = /^(rsa1_|rso1_|rlm1_)/;
const RESET_ALIAS_CAP = 16;
const RESET_TARGETS = Object.freeze([
  { key: "tasks", collection: "tasks" },
  { key: "notification_intents", collection: "notificationIntents" },
  { key: "task_deadline_evidence", collection: "taskDeadlineEvidence" },
  { key: "confirmation_snapshots", collection: "taskPlanOperations", kind: "CONFIRMATION_SNAPSHOT" }
]);
const COUNT_KEYS = Object.freeze({ tasks: "tasks", notification_intents: "notificationIntents", task_deadline_evidence: "taskDeadlineEvidence", confirmation_snapshots: "confirmationSnapshots" });
const ACTIVE_RECORD_KEYS = ["schema_version", "kind", "state", "account_uid", "operation_id", "aliases", "reason", "request_fingerprint", "expected_task_generation_epoch", "task_generation_epoch", "active_move_event_id", "target_index", "deleted_counts", "deleted_count", "created_at", "updated_at"];
const ACTIVE_OPTIONAL_KEYS = ["page_after_path", "lease", "awaiting_local_reset_at"];
const TOMBSTONE_KEYS = ["schema_version", "kind", "state", "account_uid", "operation_id", "aliases", "reason", "request_fingerprint", "expected_task_generation_epoch", "task_generation_epoch", "active_move_event_id", "deleted_counts", "deleted_count", "final_receipt_digest", "created_at", "finalized_at"];

function failedPrecondition(reason, extra) {
  return new HttpsError("failed-precondition", reason, { schemaVersion: 1, reason, ...(extra || {}) });
}

function resetCanonicalId(uid, r) {
  return `rso1_${fence.first40(fence.sha256Hex(fence.TaskCanonicalV1({ account_uid: uid, task_generation_epoch: r })))}`;
}

function resetRequestFingerprint(e) {
  return `reset1_${fence.sha256Hex(fence.TaskCanonicalV1({ kind: "reset", reason: RESET_REASON, expected_task_generation_epoch: e }))}`;
}

function activeMoveEventIdFor(uid, r, canonicalId) {
  return `me1_${fence.first40(fence.sha256Hex(fence.TaskCanonicalV1({ uid, new_task_generation_epoch: r, reset_operation_id: canonicalId })))}`;
}

function isSafeCount(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

/** Reconciled 9 marker: the total equality projection of the active record (spec v5 §697). */
function projectResetMarker(record) {
  const marker = {
    schemaVersion: 1,
    kind: "reset",
    operationId: record.operation_id,
    requestFingerprint: record.request_fingerprint,
    state: record.state,
    expectedTaskGenerationEpoch: record.expected_task_generation_epoch,
    taskGenerationEpoch: record.task_generation_epoch,
    activeMoveEventId: record.active_move_event_id,
    targetIndex: record.target_index
  };
  if (record.page_after_path !== undefined) marker.pageAfterPath = record.page_after_path;
  marker.deletedCounts = {
    tasks: record.deleted_counts.tasks,
    notificationIntents: record.deleted_counts.notification_intents,
    taskDeadlineEvidence: record.deleted_counts.task_deadline_evidence,
    confirmationSnapshots: record.deleted_counts.confirmation_snapshots
  };
  marker.deletedCount = record.deleted_count;
  if (record.lease !== undefined) marker.lease = { ownerToken: record.lease.owner_token, expiresAt: record.lease.expires_at };
  marker.createdAt = record.created_at;
  marker.updatedAt = record.updated_at;
  if (record.awaiting_local_reset_at !== undefined) marker.awaitingLocalResetAt = record.awaiting_local_reset_at;
  return marker;
}

function isLegacyResetMarker(marker) {
  return fence.isUID(String(marker?.operationId ?? "")) && ["deleting", "awaiting_local_reset"].includes(marker?.state) &&
    marker.kind === undefined && "workerLease" in (marker || {}) && "startedAt" in marker;
}

function isPhase2ResetMarker(marker) {
  return marker !== null && typeof marker === "object" && marker.schemaVersion === 1 && marker.kind === "reset";
}

function countsValid(counts) {
  return counts !== null && typeof counts === "object" &&
    Object.keys(counts).sort().join(",") === "confirmation_snapshots,notification_intents,task_deadline_evidence,tasks" &&
    Object.values(counts).every(isSafeCount);
}

/** Validates the deterministic-path record; every defect fails closed as OPERATION_REUSED naming the canonical ID. */
function validateResetRecord(record, { uid, canonicalId, fingerprint }) {
  const reject = () => failedPrecondition("OPERATION_REUSED", { operationId: canonicalId });
  if (record === null || typeof record !== "object" || Array.isArray(record)) throw reject();
  const finalized = record.state === "finalized";
  const keys = Object.keys(record);
  const required = finalized ? TOMBSTONE_KEYS : ACTIVE_RECORD_KEYS;
  const allowed = new Set(finalized ? TOMBSTONE_KEYS : [...ACTIVE_RECORD_KEYS, ...ACTIVE_OPTIONAL_KEYS]);
  if (keys.some((key) => !allowed.has(key)) || required.some((key) => !(key in record))) throw reject();
  if (record.schema_version !== 1 || record.kind !== "RESET_OPERATION" || record.account_uid !== uid ||
      record.operation_id !== canonicalId || record.reason !== RESET_REASON || record.request_fingerprint !== fingerprint) throw reject();
  if (!finalized && record.state !== "deleting" && record.state !== "awaiting_local_reset") throw reject();
  if (!Array.isArray(record.aliases) || record.aliases.length < 1 || record.aliases.length > RESET_ALIAS_CAP ||
      record.aliases.some((item) => !RESET_ALIAS_RE.test(item)) || new Set(record.aliases).size !== record.aliases.length) throw reject();
  if (!Number.isSafeInteger(record.expected_task_generation_epoch) || record.task_generation_epoch !== record.expected_task_generation_epoch + 1 ||
      !Number.isSafeInteger(record.task_generation_epoch)) throw reject();
  if (record.active_move_event_id !== activeMoveEventIdFor(uid, record.task_generation_epoch, canonicalId)) throw reject();
  if (!countsValid(record.deleted_counts) || !isSafeCount(record.deleted_count) ||
      Object.values(record.deleted_counts).reduce((sum, value) => sum + value, 0) !== record.deleted_count) throw reject();
  if (!fence.isMillisecondTimestamp(record.created_at)) throw reject();
  if (finalized) {
    if (!fence.isMillisecondTimestamp(record.finalized_at) || fence.millis(record.finalized_at) < fence.millis(record.created_at)) throw reject();
    if (typeof record.final_receipt_digest !== "string" || !/^[0-9a-f]{64}$/.test(record.final_receipt_digest)) throw reject();
    return record;
  }
  if (!fence.isMillisecondTimestamp(record.updated_at) || fence.millis(record.updated_at) < fence.millis(record.created_at)) throw reject();
  if (record.state === "deleting") {
    if (!Number.isInteger(record.target_index) || record.target_index < 0 || record.target_index > 3) throw reject();
    if (record.awaiting_local_reset_at !== undefined) throw reject();
    if (record.page_after_path !== undefined && (typeof record.page_after_path !== "string" || !record.page_after_path.startsWith(`users/${uid}/${RESET_TARGETS[record.target_index].collection}/`))) throw reject();
    if (record.lease !== undefined) {
      if (record.lease === null || typeof record.lease !== "object" || Object.keys(record.lease).sort().join(",") !== "expires_at,owner_token" ||
          typeof record.lease.owner_token !== "string" || !/^[0-9a-f-]{36}$/.test(record.lease.owner_token) || !fence.isMillisecondTimestamp(record.lease.expires_at)) throw reject();
    }
  } else {
    if (record.target_index !== 4 || record.page_after_path !== undefined || record.lease !== undefined) throw reject();
    if (!fence.isMillisecondTimestamp(record.awaiting_local_reset_at) || fence.millis(record.awaiting_local_reset_at) < fence.millis(record.created_at) ||
        fence.millis(record.updated_at) < fence.millis(record.awaiting_local_reset_at)) throw reject();
  }
  return record;
}

function requireMarkerEqualsRecord(marker, record, canonicalId) {
  if (marker === undefined || fence.TaskCanonicalV1(marker) !== fence.TaskCanonicalV1(projectResetMarker(record))) {
    throw failedPrecondition("OPERATION_REUSED", { operationId: canonicalId });
  }
}

function progressReceipt(record, replayed) {
  return {
    schemaVersion: 1,
    kind: "reset_progress",
    operationId: record.operation_id,
    replayed,
    accountUid: record.account_uid,
    expectedTaskGenerationEpoch: record.expected_task_generation_epoch,
    taskGenerationEpoch: record.task_generation_epoch,
    activeMoveEventId: record.active_move_event_id,
    deletedCount: record.deleted_count,
    deletedCounts: projectResetMarker(record).deletedCounts,
    state: record.state
  };
}

function finalReceiptOf(record) {
  return {
    schemaVersion: 1,
    kind: "reset_final",
    operationId: record.operation_id,
    replayed: false,
    accountUid: record.account_uid,
    expectedTaskGenerationEpoch: record.expected_task_generation_epoch,
    taskGenerationEpoch: record.task_generation_epoch,
    activeMoveEventId: record.active_move_event_id,
    deletedCount: record.deleted_count,
    deletedCounts: projectResetMarker({ ...record, deleted_counts: record.deleted_counts }).deletedCounts,
    state: "finalized"
  };
}

/** Recomputes and verifies the tombstone's receipt digest; mismatch fails closed. */
function reconstructFinalReceipt(tombstone) {
  const receipt = finalReceiptOf(tombstone);
  if (fence.sha256Hex(fence.TaskCanonicalV1(receipt)) !== tombstone.final_receipt_digest) {
    throw failedPrecondition("OPERATION_REUSED", { operationId: tombstone.operation_id });
  }
  return receipt;
}

function effectiveRootEpoch(root) {
  const value = root.taskGenerationEpoch;
  if (value === undefined) return 0;
  if (!Number.isSafeInteger(value) || value < 0) return null;
  return value;
}

function assertRootNotFenced(rootSnapshot) {
  const root = rootSnapshot && rootSnapshot.exists ? rootSnapshot.data() : undefined;
  if (root && root.accountDeletion !== undefined) throw fence.deletionError("ACCOUNT_DELETION_FENCED");
}

function timestampNow(now) {
  return Timestamp.fromMillis(now.getTime());
}

function writeRecordAndMarker(transaction, recordRef, userRef, record, { create = false } = {}) {
  if (create) transaction.create(recordRef, record);
  else transaction.set(recordRef, record);
  transaction.set(userRef, { taskReset: projectResetMarker(record) }, { merge: true });
}

/** Appends a caller alias (first-seen, unique, cap 16); a later alias past capacity resolves without persisting. */
async function adoptAlias(transaction, userRef, recordRef, record, alias, active) {
  if (record.aliases.includes(alias)) return record;
  const aliasSnapshot = await transaction.get(operationRef(userRef, alias));
  if (aliasSnapshot.exists) throw failedPrecondition("OPERATION_REUSED", { operationId: alias });
  if (record.aliases.length >= RESET_ALIAS_CAP) return record;
  const next = { ...record, aliases: [...record.aliases, alias] };
  if (active) writeRecordAndMarker(transaction, recordRef, userRef, next);
  else transaction.set(recordRef, next);
  return next;
}

async function classifyPhase2Reset(db, uid, request, now, { finalize }) {
  const e = request.expectedTaskGenerationEpoch;
  const r = e + 1;
  const canonicalId = resetCanonicalId(uid, r);
  const fingerprint = resetRequestFingerprint(e);
  const userRef = db.collection("users").doc(uid);
  const recordRef = operationRef(userRef, canonicalId);
  const nowTs = timestampNow(now);
  return db.runTransaction(async (transaction) => {
    const recordSnapshot = await transaction.get(recordRef);
    const rootSnapshot = await transaction.get(userRef);
    assertRootNotFenced(rootSnapshot);
    const root = rootSnapshot.exists ? rootSnapshot.data() : {};
    if (recordSnapshot.exists) {
      const record = validateResetRecord(recordSnapshot.data(), { uid, canonicalId, fingerprint });
      if (record.state === "finalized") {
        if (root.taskReset !== undefined) throw failedPrecondition("OPERATION_REUSED", { operationId: canonicalId });
        const receipt = reconstructFinalReceipt(record);
        await adoptAlias(transaction, userRef, recordRef, record, request.operationId, false);
        return { kind: "final", receipt: { ...receipt, replayed: true } };
      }
      requireMarkerEqualsRecord(root.taskReset, record, canonicalId);
      if (finalize && record.state !== "awaiting_local_reset") throw failedPrecondition("STALE_STATE");
      const adopted = await adoptAlias(transaction, userRef, recordRef, record, request.operationId, true);
      return { kind: "active", record: adopted, created: false, userRef, recordRef, canonicalId, fingerprint };
    }
    if (finalize) throw failedPrecondition("STALE_STATE");
    const marker = root.taskReset;
    if (marker !== undefined) {
      if (isLegacyResetMarker(marker)) throw failedPrecondition("LEGACY_RESET_MIGRATION_REQUIRED", { legacyOperationId: marker.operationId });
      if (isPhase2ResetMarker(marker) && Number.isSafeInteger(marker.expectedTaskGenerationEpoch) && typeof marker.operationId === "string") {
        throw failedPrecondition("RESET_ACTIVE", { operationId: marker.operationId, expectedTaskGenerationEpoch: marker.expectedTaskGenerationEpoch });
      }
      throw failedPrecondition("OPERATION_REUSED", { operationId: canonicalId });
    }
    const rootEpoch = effectiveRootEpoch(root);
    if (rootEpoch !== e) throw failedPrecondition("STALE_STATE");
    const aliasSnapshot = await transaction.get(operationRef(userRef, request.operationId));
    if (aliasSnapshot.exists) throw failedPrecondition("OPERATION_REUSED", { operationId: request.operationId });
    const record = {
      schema_version: 1,
      kind: "RESET_OPERATION",
      state: "deleting",
      account_uid: uid,
      operation_id: canonicalId,
      aliases: [request.operationId],
      reason: RESET_REASON,
      request_fingerprint: fingerprint,
      expected_task_generation_epoch: e,
      task_generation_epoch: r,
      active_move_event_id: activeMoveEventIdFor(uid, r, canonicalId),
      target_index: 0,
      deleted_counts: { tasks: 0, notification_intents: 0, task_deadline_evidence: 0, confirmation_snapshots: 0 },
      deleted_count: 0,
      created_at: nowTs,
      updated_at: nowTs
    };
    transaction.create(recordRef, record);
    transaction.set(userRef, { taskReset: projectResetMarker(record), taskGenerationEpoch: r, activeMoveEventId: record.active_move_event_id }, { merge: true });
    return { kind: "active", record, created: true, userRef, recordRef, canonicalId, fingerprint };
  });
}

function requireOwnedLease(record, ownerToken, now) {
  const lease = record.lease;
  if (!lease || lease.owner_token !== ownerToken || fence.millis(lease.expires_at) <= now.getTime()) {
    throw new HttpsError("unavailable", "Reset worker no longer owns the lease");
  }
}

async function leasedResetTransaction(db, ctx, ownerToken, now, body) {
  return db.runTransaction(async (transaction) => {
    const recordSnapshot = await transaction.get(ctx.recordRef);
    const rootSnapshot = await transaction.get(ctx.userRef);
    assertRootNotFenced(rootSnapshot);
    if (!recordSnapshot.exists) throw failedPrecondition("STALE_STATE");
    const record = validateResetRecord(recordSnapshot.data(), ctx);
    if (record.state !== "deleting") throw failedPrecondition("STALE_STATE");
    requireMarkerEqualsRecord(rootSnapshot.data()?.taskReset, record, ctx.canonicalId);
    if (ownerToken !== null) requireOwnedLease(record, ownerToken, now);
    return body(transaction, record);
  });
}

async function acquirePhase2Lease(db, ctx, ownerToken, now) {
  return leasedResetTransaction(db, ctx, null, now, async (transaction, record) => {
    const lease = record.lease;
    if (lease && lease.owner_token !== ownerToken && fence.millis(lease.expires_at) > now.getTime()) {
      throw new HttpsError("unavailable", "Another reset worker owns the live lease");
    }
    const next = { ...record, lease: { owner_token: ownerToken, expires_at: Timestamp.fromMillis(now.getTime() + LEASE_MS) }, updated_at: timestampNow(now) };
    writeRecordAndMarker(transaction, ctx.recordRef, ctx.userRef, next);
    return next;
  });
}

async function phase2TargetStep(db, ctx, ownerToken, now) {
  return leasedResetTransaction(db, ctx, ownerToken, now, async (transaction, record) => {
    const target = RESET_TARGETS[record.target_index];
    let base = ctx.userRef.collection(target.collection);
    if (target.kind) base = base.where("kind", "==", target.kind);
    base = base.orderBy(admin.firestore.FieldPath.documentId());
    let snapshot;
    if (record.page_after_path !== undefined) {
      snapshot = await transaction.get(base.startAfter(record.page_after_path.split("/").at(-1)).limit(1));
      if (snapshot.empty) snapshot = await transaction.get(base.limit(1));
    } else {
      snapshot = await transaction.get(base.limit(1));
    }
    const nowTs = timestampNow(now);
    if (snapshot.empty) {
      const next = { ...record, target_index: record.target_index + 1, updated_at: nowTs };
      delete next.page_after_path;
      if (next.target_index === RESET_TARGETS.length) {
        next.state = "awaiting_local_reset";
        next.awaiting_local_reset_at = nowTs;
        delete next.lease;
      }
      writeRecordAndMarker(transaction, ctx.recordRef, ctx.userRef, next);
      return { record: next, deleted: false };
    }
    const doc = snapshot.docs[0];
    transaction.delete(doc.ref);
    const next = {
      ...record,
      page_after_path: doc.ref.path,
      deleted_counts: { ...record.deleted_counts, [target.key]: record.deleted_counts[target.key] + 1 },
      deleted_count: record.deleted_count + 1,
      lease: { owner_token: ownerToken, expires_at: Timestamp.fromMillis(now.getTime() + LEASE_MS) },
      updated_at: nowTs
    };
    writeRecordAndMarker(transaction, ctx.recordRef, ctx.userRef, next);
    return { record: next, deleted: true };
  });
}

async function executePhase2Reset(db, uid, request, now, options = {}) {
  const outcome = await classifyPhase2Reset(db, uid, request, now, { finalize: false });
  if (outcome.kind === "final") return outcome.receipt;
  let record = outcome.record;
  if (record.state === "awaiting_local_reset") return progressReceipt(record, !outcome.created);
  const ctx = { uid, userRef: outcome.userRef, recordRef: outcome.recordRef, canonicalId: outcome.canonicalId, fingerprint: outcome.fingerprint };
  const ownerToken = randomUUID();
  record = await acquirePhase2Lease(db, ctx, ownerToken, now);
  let budget = Number.isSafeInteger(options.resetDocumentBudget) ? options.resetDocumentBudget : Number.POSITIVE_INFINITY;
  while (record.state === "deleting") {
    const step = await phase2TargetStep(db, ctx, ownerToken, now);
    record = step.record;
    if (step.deleted) {
      budget -= 1;
      if (budget <= 0 && record.state === "deleting") throw new HttpsError("unavailable", "Reset document budget exhausted");
    }
  }
  return progressReceipt(record, false);
}

async function executePhase2Finalize(db, uid, request, now) {
  const outcome = await classifyPhase2Reset(db, uid, request, now, { finalize: true });
  if (outcome.kind === "final") return outcome.receipt;
  const ctx = { uid, userRef: outcome.userRef, recordRef: outcome.recordRef, canonicalId: outcome.canonicalId, fingerprint: outcome.fingerprint };
  return db.runTransaction(async (transaction) => {
    const recordSnapshot = await transaction.get(ctx.recordRef);
    const rootSnapshot = await transaction.get(ctx.userRef);
    assertRootNotFenced(rootSnapshot);
    if (!recordSnapshot.exists) throw failedPrecondition("STALE_STATE");
    const record = validateResetRecord(recordSnapshot.data(), ctx);
    if (record.state === "finalized") return { ...reconstructFinalReceipt(record), replayed: true };
    if (record.state !== "awaiting_local_reset") throw failedPrecondition("STALE_STATE");
    requireMarkerEqualsRecord(rootSnapshot.data()?.taskReset, record, ctx.canonicalId);
    const receipt = finalReceiptOf(record);
    const tombstone = {
      schema_version: 1,
      kind: "RESET_OPERATION",
      state: "finalized",
      account_uid: record.account_uid,
      operation_id: record.operation_id,
      aliases: record.aliases,
      reason: record.reason,
      request_fingerprint: record.request_fingerprint,
      expected_task_generation_epoch: record.expected_task_generation_epoch,
      task_generation_epoch: record.task_generation_epoch,
      active_move_event_id: record.active_move_event_id,
      deleted_counts: record.deleted_counts,
      deleted_count: record.deleted_count,
      final_receipt_digest: fence.sha256Hex(fence.TaskCanonicalV1(receipt)),
      created_at: record.created_at,
      finalized_at: timestampNow(now)
    };
    transaction.set(ctx.recordRef, tombstone);
    transaction.update(ctx.userRef, { taskReset: deleteValue() });
    return receipt;
  });
}

async function handleTaskPlanRequest(request, dbFactory = () => admin.firestore(), now = new Date(), options = {}) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in before changing a task plan");
  let cleaned;
  try {
    cleaned = validateTaskPlanRequest(request.data, now);
  } catch (error) {
    if (error instanceof TaskPlanValidationError) {
      throw new HttpsError("invalid-argument", error.message, error.details);
    }
    throw error;
  }
  const reset = cleaned.action === "resetAllTasks" || cleaned.action === "finalizeTaskReset";
  const mode = Object.prototype.hasOwnProperty.call(options, "resetProtocolMode") ? options.resetProtocolMode : ENV_RESET_PROTOCOL_MODE;
  if (reset && mode === undefined) throw new HttpsError("unavailable", "Reset protocol mode is not configured");
  const db = dbFactory();
  if (reset && cleaned.expectedTaskGenerationEpoch !== undefined) {
    return cleaned.action === "resetAllTasks"
      ? executePhase2Reset(db, uid, cleaned, now, options)
      : executePhase2Finalize(db, uid, cleaned, now);
  }
  if (cleaned.action === "resetAllTasks") return executeResetAllTasks(db, uid, cleaned, now, mode);
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
  validateTaskPlanRequest,
  // Phase 2 reset protocol (C2.8)
  RESET_PROTOCOL_MODES,
  resetCanonicalId,
  resetRequestFingerprint,
  activeMoveEventIdFor,
  projectResetMarker,
  validateResetRecord,
  reconstructFinalReceipt,
  executePhase2Reset,
  executePhase2Finalize
};
