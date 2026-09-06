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
  "resetAllTasks", "finalizeTaskReset",
  "reconcileLegacyTaskReset", "inspectCommittedOperation"
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

function validateReconciliationRequest(input) {
  if (!exactKeySet(input, ["action", "legacyOperationId", "migrationAlias"])) {
    if (input.legacyOperationId === undefined && exactKeySet(input, ["action", "migrationAlias"])) failRequestInvalid("legacyOperationId");
    failRequestInvalid("request");
  }
  const legacyOperationId = input.legacyOperationId;
  if (typeof legacyOperationId !== "string" || !isValidDocumentId(legacyOperationId) || legacyOperationId.trim() !== legacyOperationId ||
      RESERVED_ID_RE.test(legacyOperationId)) failRequestInvalid("legacyOperationId");
  if (typeof input.migrationAlias !== "string" || !MIGRATION_ALIAS_RE.test(input.migrationAlias)) failRequestInvalid("migrationAlias");
  return { action: input.action, legacyOperationId, migrationAlias: input.migrationAlias };
}

function validateTaskPlanRequest(data, now = new Date()) {
  const input = data || {};
  if (!ACTIONS.has(input.action)) failValidation("action is not supported");
  if (input.action === "inspectCommittedOperation") return validateInspectionRequest(input);
  if (input.action === "reconcileLegacyTaskReset") return validateReconciliationRequest(input);
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
    const fencedReplay = await rawLegacyFence(transaction, userRef, uid, request.operationId, opSnapshot);
    if (fencedReplay) return { done: true, response: fencedReplay };
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
    const fencedReplay = await rawLegacyFence(transaction, userRef, uid, request.operationId, opSnapshot);
    if (fencedReplay) return fencedReplay;
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

// ---------------------------------------------------------------------------
// Legacy reset authority (v9 §6.1), migration authority and action (§6.2, §6.3),
// raw fence (§6.4:699), and inspectCommittedOperation (§7) — PHASE2_CONTRACT.md C2.8.
// ---------------------------------------------------------------------------

const LEGACY_RESET_FINGERPRINT = `reset1_${sha256(canonicalTaskPlanJSON({ kind: "reset", reason: RESET_REASON }))}`;
const MIGRATION_ALIAS_RE = /^rsa1_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const MIGRATION_ID_RE = /^rlm1_[0-9a-f]{40}$/;
const CANONICAL_RESET_ID_RE = /^rso1_[0-9a-f]{40}$/;
const WORKFLOW_TOKEN_RE = /^workflow-v2-[0-9a-f]{64}$/;
const HEX64_RE = /^[0-9a-f]{64}$/;
const MIGRATION_BYTES_CAP = 16384;
const MIGRATION_BASE_KEYS = ["schema_version", "kind", "account_uid", "migration_id", "legacy_operation_id", "migration_alias", "request_fingerprint", "outcome", "created_at"];
const MIGRATION_OUTCOME_KEYS = Object.freeze({
  not_dispatched: [],
  upgraded: ["source_state", "expected_task_generation_epoch", "task_generation_epoch", "canonical_operation_id", "active_move_event_id", "progress_receipt"],
  phase2_active: ["expected_task_generation_epoch", "task_generation_epoch", "canonical_operation_id", "active_move_event_id", "progress_receipt"],
  finalized_compat: ["source_state", "legacy_final_receipt"]
});
const HANDOFF_ACTIONS = new Set(["beginHandoff", "acknowledgeHandoffOpened", "recordHandoffReturned", "continueHandoff", "resolveHandoff"]);
const INSPECTION_FAMILIES = ["ROUTE_CLAIM", "HANDOFF", "HANDOFF_CANCEL", "RESET", "LEGACY_RESET_MIGRATION", "WORKFLOW"];

function migrationIdFor(uid, legacyOperationId) {
  return `rlm1_${fence.first40(fence.sha256Hex(fence.TaskCanonicalV1({ account_uid: uid, legacy_operation_id: legacyOperationId })))}`;
}

function migrationFingerprintFor(uid, legacyOperationId) {
  return `rlmreq1_${fence.sha256Hex(fence.TaskCanonicalV1({ account_uid: uid, legacy_operation_id: legacyOperationId }))}`;
}

function migrationRef(userRef, migrationId) {
  return userRef.collection("legacyResetMigrations").doc(migrationId);
}

function timeMillis(value) {
  const date = dateFromValue(value);
  return date ? date.getTime() : null;
}

function exactKeySet(value, keys) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
  const present = Object.keys(value);
  return present.length === keys.length && keys.every((key) => key in value);
}

function legacyReceiptValid(receipt, deletedCount) {
  return exactKeySet(receipt, ["reset", "deletedCount", "replayed"]) && receipt.reset === true && receipt.deletedCount === deletedCount && receipt.replayed === false;
}

/** §6.1 accepted legacy operation maps → absent|deleting|tasks_deleted|finalized|malformed. */
function classifyLegacyOperation(op) {
  if (op === undefined) return "absent";
  if (op === null || typeof op !== "object" || op.kind !== "reset" || op.fingerprint !== LEGACY_RESET_FINGERPRINT ||
      !isSafeCount(op.deletedCount) || timeMillis(op.at) === null) return "malformed";
  if (op.state === "deleting") return exactKeySet(op, ["kind", "fingerprint", "deletedCount", "state", "at"]) ? "deleting" : "malformed";
  if (op.state === "tasks_deleted") {
    return exactKeySet(op, ["kind", "fingerprint", "deletedCount", "state", "at", "tasks_deleted"]) && legacyReceiptValid(op.tasks_deleted, op.deletedCount) ? "tasks_deleted" : "malformed";
  }
  if (op.state === "finalized") {
    return exactKeySet(op, ["kind", "fingerprint", "deletedCount", "state", "at", "tasks_deleted", "finalized", "finalizedAt"]) &&
      legacyReceiptValid(op.tasks_deleted, op.deletedCount) && legacyReceiptValid(op.finalized, op.deletedCount) &&
      timeMillis(op.finalizedAt) !== null && timeMillis(op.finalizedAt) >= timeMillis(op.at) ? "finalized" : "malformed";
  }
  return "malformed";
}

/** §6.1 accepted legacy markers → absent|deleting|awaiting_local_reset|phase2|malformed. */
function classifyLegacyMarker(marker) {
  if (marker === undefined) return "absent";
  if (isPhase2ResetMarker(marker)) return "phase2";
  if (!exactKeySet(marker, ["operationId", "state", "deletedCount", "workerLease", "startedAt"]) || typeof marker.operationId !== "string" ||
      !isValidDocumentId(marker.operationId) || !isSafeCount(marker.deletedCount) || timeMillis(marker.startedAt) === null) return "malformed";
  const lease = marker.workerLease;
  if (marker.state === "deleting") {
    if (lease === null) return "deleting";
    return exactKeySet(lease, ["workerId", "expiresAt"]) && typeof lease.workerId === "string" && /^[0-9a-f-]{36}$/.test(lease.workerId) &&
      timeMillis(lease.expiresAt) !== null && timeMillis(lease.expiresAt) > timeMillis(marker.startedAt) ? "deleting" : "malformed";
  }
  if (marker.state === "awaiting_local_reset") return lease === null ? "awaiting_local_reset" : "malformed";
  return "malformed";
}

function legacyPairMatches(op, marker, legacyOperationId) {
  return marker.operationId === legacyOperationId && marker.deletedCount === op.deletedCount && timeMillis(op.at) === timeMillis(marker.startedAt);
}

function reconciliationResponse(record, replayed) {
  const base = {
    schemaVersion: 1, kind: "legacy_reset_reconciliation", outcome: record.outcome, migrationId: record.migration_id,
    legacyOperationId: record.legacy_operation_id, migrationAlias: record.migration_alias, accountUid: record.account_uid
  };
  if (record.outcome === "not_dispatched") return { ...base, replayed };
  if (record.outcome === "upgraded") return { ...base, sourceState: record.source_state, replayed, progressReceipt: record.progress_receipt };
  if (record.outcome === "phase2_active") return { ...base, replayed, progressReceipt: record.progress_receipt };
  return { ...base, sourceState: "finalized", replayed, legacyFinalReceipt: record.legacy_final_receipt };
}

function legacyFinalReceiptFor(uid, legacyOperationId, deletedCount) {
  return { schemaVersion: 1, kind: "legacy_reset_final", operationId: legacyOperationId, replayed: false, accountUid: uid, deletedCount, state: "finalized" };
}

/** Validates the permanent migration record; every defect is OPERATION_REUSED naming the migration ID. */
function validateMigrationRecord(record, { uid, migrationId, legacyOperationId }) {
  const reject = () => failedPrecondition("OPERATION_REUSED", { operationId: migrationId });
  if (record === null || typeof record !== "object" || Array.isArray(record)) throw reject();
  const outcomeKeys = MIGRATION_OUTCOME_KEYS[record.outcome];
  if (!outcomeKeys || !exactKeySet(record, [...MIGRATION_BASE_KEYS, ...outcomeKeys])) throw reject();
  if (record.schema_version !== 1 || record.kind !== "LEGACY_RESET_MIGRATION" || record.account_uid !== uid) throw reject();
  if (typeof record.legacy_operation_id !== "string" || !isValidDocumentId(record.legacy_operation_id) || RESERVED_ID_RE.test(record.legacy_operation_id)) throw reject();
  if (legacyOperationId !== undefined && record.legacy_operation_id !== legacyOperationId) throw reject();
  if (record.migration_id !== migrationId || migrationIdFor(uid, record.legacy_operation_id) !== migrationId) throw reject();
  if (record.request_fingerprint !== migrationFingerprintFor(uid, record.legacy_operation_id)) throw reject();
  if (!MIGRATION_ALIAS_RE.test(record.migration_alias) || !fence.isMillisecondTimestamp(record.created_at)) throw reject();
  if (record.outcome === "upgraded" || record.outcome === "phase2_active") {
    const e = record.expected_task_generation_epoch;
    if (!Number.isSafeInteger(e) || e < 0 || record.task_generation_epoch !== e + 1 || !Number.isSafeInteger(e + 1)) throw reject();
    if (record.canonical_operation_id !== resetCanonicalId(uid, e + 1) || record.active_move_event_id !== activeMoveEventIdFor(uid, e + 1, record.canonical_operation_id)) throw reject();
    const receipt = record.progress_receipt;
    if (!exactKeySet(receipt, ["schemaVersion", "kind", "operationId", "replayed", "accountUid", "expectedTaskGenerationEpoch", "taskGenerationEpoch", "activeMoveEventId", "deletedCount", "deletedCounts", "state"]) ||
        receipt.schemaVersion !== 1 || receipt.kind !== "reset_progress" || receipt.operationId !== record.canonical_operation_id ||
        receipt.replayed !== (record.outcome === "phase2_active") || receipt.accountUid !== uid ||
        receipt.expectedTaskGenerationEpoch !== e || receipt.taskGenerationEpoch !== e + 1 || receipt.activeMoveEventId !== record.active_move_event_id ||
        !exactKeySet(receipt.deletedCounts, ["tasks", "notificationIntents", "taskDeadlineEvidence", "confirmationSnapshots"]) ||
        !Object.values(receipt.deletedCounts).every(isSafeCount) || !isSafeCount(receipt.deletedCount) ||
        Object.values(receipt.deletedCounts).reduce((sum, value) => sum + value, 0) !== receipt.deletedCount ||
        !["deleting", "awaiting_local_reset"].includes(receipt.state)) throw reject();
    if (record.outcome === "upgraded" && !["deleting", "tasks_deleted"].includes(record.source_state)) throw reject();
  } else if (record.outcome === "finalized_compat") {
    if (record.source_state !== "finalized") throw reject();
    const receipt = record.legacy_final_receipt;
    if (!isSafeCount(receipt?.deletedCount) || fence.TaskCanonicalV1(receipt) !== fence.TaskCanonicalV1(legacyFinalReceiptFor(uid, record.legacy_operation_id, receipt.deletedCount))) throw reject();
  }
  if (fence.canonicalByteLength(record) > MIGRATION_BYTES_CAP) throw reject();
  return record;
}

/**
 * §6.4:699 raw fence for delayed legacy reset/finalize: reads the permanent migration
 * path in the same transaction. Returns the replayed old wire for finalized_compat, or null.
 */
async function rawLegacyFence(transaction, userRef, uid, legacyOperationId, opSnapshot) {
  const migrationId = migrationIdFor(uid, legacyOperationId);
  const snapshot = await transaction.get(migrationRef(userRef, migrationId));
  if (!snapshot.exists) return null;
  const record = validateMigrationRecord(snapshot.data(), { uid, migrationId, legacyOperationId });
  if (record.outcome !== "finalized_compat") throw failedPrecondition("CLIENT_UPGRADE_REQUIRED", { requiredProtocol: "phase2" });
  const op = opSnapshot.exists ? opSnapshot.data() : undefined;
  if (classifyLegacyOperation(op) !== "finalized" || op.deletedCount !== record.legacy_final_receipt.deletedCount) {
    throw failedPrecondition("OPERATION_REUSED", { operationId: migrationId });
  }
  return { reset: true, deletedCount: op.deletedCount, replayed: true };
}

async function executeReconcileLegacyTaskReset(db, uid, request, now) {
  const legacyOperationId = request.legacyOperationId;
  const migrationId = migrationIdFor(uid, legacyOperationId);
  const userRef = db.collection("users").doc(uid);
  const migrationAt = timestampNow(now);
  return db.runTransaction(async (transaction) => {
    const rootSnapshot = await transaction.get(userRef);
    assertRootNotFenced(rootSnapshot);
    const root = rootSnapshot.exists ? rootSnapshot.data() : {};
    const migrationSnapshot = await transaction.get(migrationRef(userRef, migrationId));
    if (migrationSnapshot.exists) {
      return reconciliationResponse(validateMigrationRecord(migrationSnapshot.data(), { uid, migrationId, legacyOperationId }), true);
    }
    const opSnapshot = await transaction.get(operationRef(userRef, legacyOperationId));
    const op = opSnapshot.exists ? opSnapshot.data() : undefined;
    const marker = root.taskReset;
    const recordClass = classifyLegacyOperation(op);
    const markerClass = classifyLegacyMarker(marker);
    const corrupt = (classes) => failedPrecondition("LEGACY_RESET_CORRUPT", { context: "reconcile", legacyOperationId, recordClass, markerClass, ...classes });
    let plan;
    if (markerClass === "absent") {
      if (recordClass === "absent") plan = { outcome: "not_dispatched" };
      else if (recordClass === "finalized") plan = { outcome: "finalized_compat" };
      else throw corrupt();
    } else if (markerClass === "deleting" || markerClass === "awaiting_local_reset") {
      if (marker.operationId !== legacyOperationId) {
        if (recordClass === "absent" || recordClass === "finalized") throw failedPrecondition("LEGACY_RESET_MIGRATION_REQUIRED", { legacyOperationId: marker.operationId });
        throw corrupt();
      }
      const paired = (markerClass === "deleting" && recordClass === "deleting") || (markerClass === "awaiting_local_reset" && recordClass === "tasks_deleted");
      if (!paired || !legacyPairMatches(op, marker, legacyOperationId)) throw corrupt();
      plan = { outcome: "upgraded" };
    } else if (markerClass === "phase2") {
      const canonicalId = marker.operationId;
      const canonicalSnapshot = typeof canonicalId === "string" && CANONICAL_RESET_ID_RE.test(canonicalId) ? await transaction.get(operationRef(userRef, canonicalId)) : null;
      let current;
      try {
        if (!canonicalSnapshot || !canonicalSnapshot.exists) throw new Error("absent");
        current = validateResetRecord(canonicalSnapshot.data(), { uid, canonicalId, fingerprint: resetRequestFingerprint(marker.expectedTaskGenerationEpoch) });
        if (current.state === "finalized") throw new Error("finalized");
        requireMarkerEqualsRecord(marker, current, canonicalId);
      } catch {
        throw corrupt({ recordClass: "phase2", markerClass: "phase2" });
      }
      if (recordClass === "absent" || recordClass === "finalized" || (legacyOperationId === canonicalId)) plan = { outcome: "phase2_active", current };
      else throw corrupt({ recordClass: recordClass === "malformed" ? "malformed" : "phase2" });
    } else {
      throw corrupt();
    }
    const aliasSnapshot = await transaction.get(operationRef(userRef, request.migrationAlias));
    if (aliasSnapshot.exists) throw failedPrecondition("LEGACY_RESET_ALIAS_OCCUPIED", { legacyOperationId, migrationAlias: request.migrationAlias });
    const record = {
      schema_version: 1, kind: "LEGACY_RESET_MIGRATION", account_uid: uid, migration_id: migrationId, legacy_operation_id: legacyOperationId,
      migration_alias: request.migrationAlias, request_fingerprint: migrationFingerprintFor(uid, legacyOperationId), outcome: plan.outcome, created_at: migrationAt
    };
    if (plan.outcome === "finalized_compat") {
      record.source_state = "finalized";
      record.legacy_final_receipt = legacyFinalReceiptFor(uid, legacyOperationId, op.deletedCount);
    } else if (plan.outcome === "upgraded") {
      const e = effectiveRootEpoch(root);
      const r = e === null ? null : e + 1;
      if (r === null || !Number.isSafeInteger(r)) throw corrupt({ recordClass: "phase2" });
      const canonicalId = resetCanonicalId(uid, r);
      const canonicalSnapshot = await transaction.get(operationRef(userRef, canonicalId));
      if (canonicalSnapshot.exists) throw corrupt({ recordClass: "phase2" });
      const createdAt = Timestamp.fromMillis(timeMillis(op.at));
      const active = {
        schema_version: 1, kind: "RESET_OPERATION", state: "deleting", account_uid: uid, operation_id: canonicalId, aliases: [request.migrationAlias],
        reason: RESET_REASON, request_fingerprint: resetRequestFingerprint(e), expected_task_generation_epoch: e, task_generation_epoch: r,
        active_move_event_id: activeMoveEventIdFor(uid, r, canonicalId), target_index: 0,
        deleted_counts: { tasks: op.deletedCount, notification_intents: 0, task_deadline_evidence: 0, confirmation_snapshots: 0 },
        deleted_count: op.deletedCount, created_at: createdAt, updated_at: migrationAt
      };
      validateResetRecord(active, { uid, canonicalId, fingerprint: active.request_fingerprint });
      transaction.create(operationRef(userRef, canonicalId), active);
      transaction.set(userRef, { taskReset: projectResetMarker(active), taskGenerationEpoch: r, activeMoveEventId: active.active_move_event_id }, { merge: true });
      Object.assign(record, {
        source_state: recordClass, expected_task_generation_epoch: e, task_generation_epoch: r, canonical_operation_id: canonicalId,
        active_move_event_id: active.active_move_event_id, progress_receipt: progressReceipt(active, false)
      });
    } else if (plan.outcome === "phase2_active") {
      const current = plan.current;
      Object.assign(record, {
        expected_task_generation_epoch: current.expected_task_generation_epoch, task_generation_epoch: current.task_generation_epoch,
        canonical_operation_id: current.operation_id, active_move_event_id: current.active_move_event_id, progress_receipt: progressReceipt(current, true)
      });
    }
    validateMigrationRecord(record, { uid, migrationId, legacyOperationId });
    transaction.create(migrationRef(userRef, migrationId), record);
    return reconciliationResponse(record, false);
  });
}

// ---- inspectCommittedOperation (§7:830–843)

/** Stored-record members that reconstruct each family's private identity map (v9 §7:957). */
const INSPECTION_IDENTITY_SOURCES = Object.freeze({
  ROUTE_CLAIM: (uid, record) => ({ kind: "route", intentId: record.response?.intentId }),
  HANDOFF: (uid, record) => ({
    kind: "handoff", action: record.action, uid, installationId: record.response?.installationId, authEpochUUID: record.response?.authEpochUUID,
    taskInstanceId: record.task_identities?.[0]?.task_instance_id, sessionId: record.response?.sessionId
  }),
  HANDOFF_CANCEL: (uid, record) => ({
    kind: "handoff_cancel", uid, taskInstanceId: record.task_identities?.[0]?.task_instance_id, sessionId: record.response?.sessionId,
    reasonCode: record.response?.reasonCode, requesterInstallationId: record.response?.requesterInstallationId, requesterAuthEpochUUID: record.response?.requesterAuthEpochUUID
  }),
  WORKFLOW: (uid, record) => ({
    kind: "workflow", uid, taskDocumentId: record.task_document_id, taskInstanceId: record.task_instance_id, taskGenerationEpoch: record.task_generation_epoch,
    workflowId: record.workflow_id, flowAttemptId: record.flow_attempt_id, flowAttemptGeneration: record.flow_attempt_generation, submissionToken: record.submission_token
  })
});

function identityDigestOf(map) {
  if (Object.values(map).some((value) => value === undefined || value === null)) return null;
  try { return fence.sha256Hex(fence.TaskCanonicalV1(map)); } catch { return null; }
}

function validateInspectionRequest(input) {
  if (!exactKeySet(input, ["action", "family", "authority", "requestAuthority", "identityDigest"])) failRequestInvalid("request");
  const family = input.family;
  if (!INSPECTION_FAMILIES.includes(family)) failRequestInvalid("family");
  const authority = input.authority;
  const authorityKey = family === "LEGACY_RESET_MIGRATION" ? "migrationId" : family === "WORKFLOW" ? "submissionToken" : "operationId";
  if (!exactKeySet(authority, [authorityKey]) || typeof authority[authorityKey] !== "string") failRequestInvalid("authority");
  const value = authority[authorityKey];
  const authorityValid = family === "RESET" ? CANONICAL_RESET_ID_RE.test(value)
    : family === "LEGACY_RESET_MIGRATION" ? MIGRATION_ID_RE.test(value)
      : family === "WORKFLOW" ? WORKFLOW_TOKEN_RE.test(value)
        : isValidDocumentId(value) && value.trim() === value && !RESERVED_ID_RE.test(value);
  if (!authorityValid) failRequestInvalid("authority");
  const requestAuthority = input.requestAuthority;
  const requestKey = ["ROUTE_CLAIM", "HANDOFF", "HANDOFF_CANCEL"].includes(family) ? "requestSHA256" : "requestFingerprint";
  if (!exactKeySet(requestAuthority, [requestKey]) || typeof requestAuthority[requestKey] !== "string") failRequestInvalid("requestAuthority");
  const requestValue = requestAuthority[requestKey];
  const requestValid = requestKey === "requestSHA256" ? HEX64_RE.test(requestValue)
    : family === "RESET" ? /^reset1_[0-9a-f]{64}$/.test(requestValue)
      : family === "LEGACY_RESET_MIGRATION" ? /^rlmreq1_[0-9a-f]{64}$/.test(requestValue)
        : HEX64_RE.test(requestValue);
  if (!requestValid) failRequestInvalid("requestAuthority");
  if (typeof input.identityDigest !== "string" || !HEX64_RE.test(input.identityDigest)) failRequestInvalid("identityDigest");
  return { action: input.action, family, authority: { [authorityKey]: value }, requestAuthority: { [requestKey]: requestValue }, identityDigest: input.identityDigest };
}

function validateOrdinaryRecord(record, { uid, operationId, family, requestSHA256 }) {
  const reject = () => failedPrecondition("OPERATION_REUSED", { operationId });
  if (record === null || typeof record !== "object" || Array.isArray(record)) throw reject();
  const expectedKind = family === "ROUTE_CLAIM" ? "INTENT_CLAIM" : "TASK_OPERATION";
  if (record.schema_version !== 1 || record.kind !== expectedKind || record.state !== "COMMITTED" || record.account_uid !== uid || record.operation_id !== operationId) throw reject();
  const actionValid = family === "ROUTE_CLAIM" ? record.action === "claimTaskIntent"
    : family === "HANDOFF_CANCEL" ? record.action === "cancelHandoff" : HANDOFF_ACTIONS.has(record.action);
  if (!actionValid) throw reject();
  if (record.request_sha256 !== requestSHA256 || record.request_fingerprint !== `op1_${requestSHA256}`) throw reject();
  if (record.response === null || typeof record.response !== "object" || Array.isArray(record.response)) throw reject();
  return record;
}

async function executeInspectCommittedOperation(db, uid, request) {
  const { family, authority, requestAuthority, identityDigest } = request;
  const userRef = db.collection("users").doc(uid);
  const base = { schemaVersion: 1, kind: "committed_operation_inspection", accountUid: uid, family, authority, requestAuthority, identityDigest };
  return db.runTransaction(async (transaction) => {
    if (family === "RESET") {
      const canonicalId = authority.operationId;
      const recordSnapshot = await transaction.get(operationRef(userRef, canonicalId));
      const rootSnapshot = await transaction.get(userRef);
      if (!recordSnapshot.exists) return { ...base, outcome: "absent" };
      const record = validateResetRecord(recordSnapshot.data(), { uid, canonicalId, fingerprint: requestAuthority.requestFingerprint });
      if (identityDigestOf({ kind: "reset", uid, expectedTaskGenerationEpoch: record.expected_task_generation_epoch }) !== identityDigest) {
        throw failedPrecondition("OPERATION_REUSED", { operationId: canonicalId });
      }
      const marker = rootSnapshot.exists ? rootSnapshot.data()?.taskReset : undefined;
      if (record.state === "finalized") {
        if (marker !== undefined) throw failedPrecondition("OPERATION_REUSED", { operationId: canonicalId });
        return { ...base, outcome: "committed", receipt: { ...reconstructFinalReceipt(record), replayed: true } };
      }
      requireMarkerEqualsRecord(marker, record, canonicalId);
      return { ...base, outcome: "pending" };
    }
    if (family === "LEGACY_RESET_MIGRATION") {
      const migrationId = authority.migrationId;
      const snapshot = await transaction.get(migrationRef(userRef, migrationId));
      if (!snapshot.exists) return { ...base, outcome: "absent" };
      const record = validateMigrationRecord(snapshot.data(), { uid, migrationId });
      if (record.request_fingerprint !== requestAuthority.requestFingerprint || identityDigestOf({ kind: "legacy_reset_migration", uid }) !== identityDigest) {
        throw failedPrecondition("OPERATION_REUSED", { operationId: migrationId });
      }
      return { ...base, outcome: "committed", receipt: reconciliationResponse(record, true) };
    }
    if (family === "WORKFLOW") {
      const submissionToken = authority.submissionToken;
      const workflowSubmissionId = `ws2_${fence.first40(fence.sha256Hex(fence.TaskCanonicalV1({ owner: uid, submissionToken })))}`;
      const snapshot = await transaction.get(db.collection("workflowSubmissions").doc(workflowSubmissionId));
      const expanded = { ...base, authority: { submissionToken, workflowSubmissionId } };
      if (!snapshot.exists) return { ...expanded, outcome: "absent" };
      const record = snapshot.data();
      const reject = () => failedPrecondition("OPERATION_REUSED", { submissionToken });
      if (record === null || typeof record !== "object" || record.owner !== uid || record.submission_token !== submissionToken ||
          record.request_fingerprint !== requestAuthority.requestFingerprint || record.workflow_outcome === null || typeof record.workflow_outcome !== "object") throw reject();
      if (identityDigestOf(INSPECTION_IDENTITY_SOURCES.WORKFLOW(uid, record)) !== identityDigest) throw reject();
      return { ...expanded, outcome: "committed", receipt: { ...record.workflow_outcome, replayed: true } };
    }
    const operationId = authority.operationId;
    const snapshot = await transaction.get(operationRef(userRef, operationId));
    if (!snapshot.exists) return { ...base, outcome: "absent" };
    const record = validateOrdinaryRecord(snapshot.data(), { uid, operationId, family, requestSHA256: requestAuthority.requestSHA256 });
    if (identityDigestOf(INSPECTION_IDENTITY_SOURCES[family](uid, record)) !== identityDigest) throw failedPrecondition("OPERATION_REUSED", { operationId });
    return { ...base, outcome: "committed", receipt: { ...record.response, replayed: true } };
  });
}

async function handleTaskPlanRequest(request, dbFactory = () => admin.firestore(), now = new Date(), options = {}) {
  const uid = request.auth?.uid;
  if (!uid) {
    const action = request && request.data ? request.data.action : undefined;
    if (action === "inspectCommittedOperation" || action === "reconcileLegacyTaskReset") {
      throw new HttpsError("unauthenticated", "AUTH_REQUIRED", { schemaVersion: 1, reason: "AUTH_REQUIRED" });
    }
    throw new HttpsError("unauthenticated", "Sign in before changing a task plan");
  }
  let cleaned;
  try {
    cleaned = validateTaskPlanRequest(request.data, now);
  } catch (error) {
    if (error instanceof TaskPlanValidationError) {
      throw new HttpsError("invalid-argument", error.message, error.details);
    }
    throw error;
  }
  const reset = cleaned.action === "resetAllTasks" || cleaned.action === "finalizeTaskReset" || cleaned.action === "reconcileLegacyTaskReset";
  const mode = Object.prototype.hasOwnProperty.call(options, "resetProtocolMode") ? options.resetProtocolMode : ENV_RESET_PROTOCOL_MODE;
  if (reset && mode === undefined) throw new HttpsError("unavailable", "Reset protocol mode is not configured");
  const db = dbFactory();
  if (cleaned.action === "inspectCommittedOperation") return executeInspectCommittedOperation(db, uid, cleaned);
  if (cleaned.action === "reconcileLegacyTaskReset") return executeReconcileLegacyTaskReset(db, uid, cleaned, now);
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
  executePhase2Finalize,
  // Legacy reconciliation and inspection (C2.8)
  LEGACY_RESET_FINGERPRINT,
  migrationIdFor,
  migrationFingerprintFor,
  validateMigrationRecord,
  classifyLegacyOperation,
  classifyLegacyMarker,
  executeReconcileLegacyTaskReset,
  executeInspectCommittedOperation
};
