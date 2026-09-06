const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { deletionError } = require("./accountDeletionFence");
const admin = require("firebase-admin");
const { createHash } = require("node:crypto");

if (!admin.apps.length) {
  admin.initializeApp();
}

const MILLISECONDS_PER_DAY = 24 * 60 * 60 * 1000;
const SOURCE_KINDS = ["conversation", "nudge", "onComplete"];
const SUBJECT_KINDS = new Set(["person", "pet", "vehicle", "property", "service", "child"]);
const MAX_REQUEST_BYTES = 48 * 1024;

class SpawnValidationError extends Error {}

function canonicalJSON(value) {
  const ancestors = new Set();

  function encode(current) {
    if (current === null) return "null";
    if (typeof current === "string" || typeof current === "boolean") {
      return JSON.stringify(current);
    }
    if (typeof current === "number") {
      return Number.isFinite(current) ? JSON.stringify(current) : "null";
    }
    if (typeof current === "undefined" || typeof current === "function" ||
        typeof current === "symbol") {
      return undefined;
    }
    if (typeof current === "bigint") {
      throw new TypeError("BigInt is not JSON serializable");
    }
    if (typeof current.toJSON === "function") {
      return encode(current.toJSON());
    }
    if (ancestors.has(current)) {
      throw new TypeError("Circular value is not JSON serializable");
    }

    ancestors.add(current);
    let encoded;
    if (Array.isArray(current)) {
      encoded = `[${current.map((item) => encode(item) ?? "null").join(",")}]`;
    } else {
      const entries = [];
      for (const key of Object.keys(current).sort()) {
        const item = encode(current[key]);
        if (item !== undefined) entries.push(`${JSON.stringify(key)}:${item}`);
      }
      encoded = `{${entries.join(",")}}`;
    }
    ancestors.delete(current);
    return encoded;
  }

  return encode(value);
}

function sha256Hex(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function requestFingerprint(request) {
  return `f1_${sha256Hex(canonicalJSON({
    source: request.source,
    spawns: request.spawns,
    answers: request.answers
  }))}`;
}

function deterministicTaskId(token, ordinal) {
  return `t1_${sha256Hex(`${token}|${ordinal}`).slice(0, 40)}`;
}

function isSubjectAwareSpawn(spawn) {
  return Boolean(spawn?.subject && spawn?.institutionId && spawn?.institution);
}

function canonicalTaskIdV2(userId, spawn) {
  const tuple = {
    householdUid: userId,
    subject: { kind: spawn.subject.kind, id: spawn.subject.id },
    institutionId: spawn.institutionId,
    taskId: spawn.taskId
  };
  return `t2_${sha256Hex(canonicalJSON(tuple)).slice(0, 40)}`;
}

function isValidDocumentId(value) {
  return Buffer.byteLength(value, "utf8") <= 256 &&
    !value.includes("/") &&
    value !== "." &&
    value !== ".." &&
    !(value.startsWith("__") && value.endsWith("__"));
}

function validateAnswersDepth(value, depth = 1, ancestors = new Set()) {
  if (value === null || typeof value !== "object") return;
  if (depth > 4) {
    throw new SpawnValidationError("answers nesting depth must not exceed 4");
  }
  if (ancestors.has(value)) {
    throw new SpawnValidationError("answers must be JSON serializable");
  }
  ancestors.add(value);
  for (const item of Array.isArray(value) ? value : Object.values(value)) {
    validateAnswersDepth(item, depth + 1, ancestors);
  }
  ancestors.delete(value);
}

// Request: { token, source:{kind:"conversation"|"nudge"|"onComplete", id},
//            spawns:[{taskId, titleParams?:{institution}}], answers?:{k:v}, expectedUserId? }
function validateRequest(data) {
  const requestData = data || {};
  let serialized;
  try {
    serialized = canonicalJSON(requestData);
  } catch (error) {
    throw new SpawnValidationError("request must be JSON serializable");
  }
  if (serialized !== undefined && Buffer.byteLength(serialized, "utf8") > MAX_REQUEST_BYTES) {
    throw new SpawnValidationError("request must not exceed 48KB");
  }

  const { token, source, spawns, answers } = requestData;

  if (typeof token !== "string" || token.trim().length === 0) {
    throw new SpawnValidationError("A non-empty idempotency token is required");
  }
  const cleanedToken = token.trim();
  if (!isValidDocumentId(cleanedToken)) {
    throw new SpawnValidationError("token must be a valid Firestore document ID of at most 256 bytes");
  }
  if (!source || typeof source !== "object" ||
      !SOURCE_KINDS.includes(source.kind) ||
      typeof source.id !== "string" || source.id.length === 0) {
    throw new SpawnValidationError("source requires kind (conversation|nudge|onComplete) and id");
  }
  if (Buffer.byteLength(source.id, "utf8") > 256) {
    throw new SpawnValidationError("source.id must not exceed 256 bytes");
  }
  if (!Array.isArray(spawns) || spawns.length === 0) {
    throw new SpawnValidationError("spawns must be a non-empty array");
  }
  if (spawns.length > 20) {
    throw new SpawnValidationError("spawns must not contain more than 20 items");
  }

  const cleanedSpawns = spawns.map((spawn) => {
    if (!spawn || typeof spawn !== "object" ||
        typeof spawn.taskId !== "string" || spawn.taskId.trim().length === 0) {
      throw new SpawnValidationError("Every spawn requires a non-empty taskId");
    }
    const taskId = spawn.taskId.trim();
    if (!isValidDocumentId(taskId)) {
      throw new SpawnValidationError("Every taskId must be a valid Firestore document ID of at most 256 bytes");
    }
    const cleaned = { taskId };
    const titleInstitution = spawn.titleParams?.institution;
    if (typeof titleInstitution === "string" && Buffer.byteLength(titleInstitution, "utf8") > 512) {
      throw new SpawnValidationError("titleParams.institution must not exceed 512 bytes");
    }
    if (typeof titleInstitution === "string" && titleInstitution.length > 0) {
      cleaned.titleParams = { institution: titleInstitution };
    }

    const identityFields = ["subject", "institutionId", "institution"];
    const identityPresence = identityFields.map((field) =>
      Object.prototype.hasOwnProperty.call(spawn, field)
    );
    if (identityPresence.some(Boolean) && !identityPresence.every(Boolean)) {
      throw new SpawnValidationError("subject, institutionId, and institution must appear together");
    }
    if (identityPresence.every(Boolean)) {
      if (!spawn.subject || typeof spawn.subject !== "object" || Array.isArray(spawn.subject) ||
          !SUBJECT_KINDS.has(spawn.subject.kind) || typeof spawn.subject.id !== "string") {
        throw new SpawnValidationError("subject requires an approved kind and string id");
      }
      const subjectId = spawn.subject.id.trim();
      const institutionId = typeof spawn.institutionId === "string" ? spawn.institutionId.trim() : "";
      const institution = typeof spawn.institution === "string" ? spawn.institution.trim() : "";
      if (!subjectId || Buffer.byteLength(subjectId, "utf8") > 256) {
        throw new SpawnValidationError("subject.id must be nonempty and at most 256 bytes");
      }
      if (!institutionId || Buffer.byteLength(institutionId, "utf8") > 256) {
        throw new SpawnValidationError("institutionId must be nonempty and at most 256 bytes");
      }
      if (!institution || Buffer.byteLength(institution, "utf8") > 512) {
        throw new SpawnValidationError("institution must be nonempty and at most 512 bytes");
      }
      if (cleaned.titleParams && cleaned.titleParams.institution.trim() !== institution) {
        throw new SpawnValidationError("titleParams.institution must match institution");
      }
      cleaned.subject = { kind: spawn.subject.kind, id: subjectId };
      cleaned.institutionId = institutionId;
      cleaned.institution = institution;
      if (cleaned.titleParams) cleaned.titleParams = { institution };
    }
    return cleaned;
  });

  const identityModes = new Set(cleanedSpawns.map(isSubjectAwareSpawn));
  if (identityModes.size > 1) {
    throw new SpawnValidationError("A request may not mix legacy and subject-aware spawns");
  }

  let cleanedAnswers = null;
  if (answers !== undefined && answers !== null) {
    if (typeof answers !== "object" || Array.isArray(answers)) {
      throw new SpawnValidationError("answers must be a map of key/value pairs");
    }
    if (Object.keys(answers).length > 200) {
      throw new SpawnValidationError("answers must not contain more than 200 keys");
    }
    validateAnswersDepth(answers);
    cleanedAnswers = answers;
  }

  const cleaned = {
    token: cleanedToken,
    source: { kind: source.kind, id: source.id },
    spawns: cleanedSpawns,
    answers: cleanedAnswers
  };
  if (Object.prototype.hasOwnProperty.call(requestData, "expectedUserId")) {
    if (typeof requestData.expectedUserId !== "string" ||
        Buffer.byteLength(requestData.expectedUserId, "utf8") > 128) {
      throw new SpawnValidationError("expectedUserId must be a string of at most 128 bytes");
    }
    cleaned.expectedUserId = requestData.expectedUserId;
  }
  return cleaned;
}

// Same tolerance as peezyChat's dateFromValue: Timestamp.toDate / string / number.
function dateFromValue(value) {
  if (!value) return null;
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value;
  if (typeof value?.toDate === "function") {
    const date = value.toDate();
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (typeof value === "string" || typeof value === "number") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function startOfDayUTC(date) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

// dateRule override, else the urgency-timeline math from
// TaskGenerationService.calculateDueDate reimplemented exactly:
// daysFromNow = totalDays * (1 - urgencyPercentage/100), clamped to today.
function resolveDueDate(row, moveDate, now = new Date()) {
  const today = startOfDayUTC(now);
  const rule = row.dateRule;
  // "spawn" anchor (movers chain): due = the spawn instant + whole-day offsets.
  // Plain UTC millisecond arithmetic — no midnight normalization, which could
  // display as the prior local date — and no moveDate requirement.
  if (rule && rule.anchor === "spawn" && Number.isInteger(rule.offsetDays)) {
    return new Date(now.getTime() + rule.offsetDays * MILLISECONDS_PER_DAY);
  }
  if (rule && rule.anchor === "moveDate" && Number.isInteger(rule.offsetDays) && moveDate) {
    return new Date(startOfDayUTC(moveDate).getTime() + rule.offsetDays * MILLISECONDS_PER_DAY);
  }

  if (!moveDate) return today;
  const moveDateStart = startOfDayUTC(moveDate);
  const totalDays = Math.round((moveDateStart.getTime() - today.getTime()) / MILLISECONDS_PER_DAY);
  if (totalDays <= 0) return today;

  const urgencyRaw = Number(row.urgencyPercentage);
  const urgencyPercentage = Number.isFinite(urgencyRaw) ? urgencyRaw : 50;
  const daysFromNow = Math.trunc(totalDays * (1 - urgencyPercentage / 100));
  const dueDate = new Date(today.getTime() + daysFromNow * MILLISECONDS_PER_DAY);
  return dueDate < today ? today : dueDate;
}

function spawnTitle(row, titleParams) {
  const title = typeof row.title === "string" ? row.title : "";
  if (titleParams && typeof titleParams.institution === "string") {
    return title.split("{institution}").join(titleParams.institution);
  }
  return title;
}

// Mirrors the generation doc shape (TaskGenerationService.swift:93-112) with
// status "Upcoming" — NOT "pending" (terminal legacy human-handoff state).
// JS Dates are stored as Firestore Timestamps by the Admin SDK.
function buildTaskDoc({ row, docId, userId, title, dueDate, source, now, spawn = null }) {
  const urgencyRaw = Number(row.urgencyPercentage);
  const doc = {
    id: docId,
    taskId: row.taskId,
    title,
    desc: typeof row.desc === "string" ? row.desc : "",
    category: row.category || "custom",
    actionCategory: row.actionCategory || "",
    actionType: row.actionType || "off-app",
    taskType: typeof row.taskType === "string" ? row.taskType : "provide_info",
    urgencyPercentage: Number.isFinite(urgencyRaw) ? urgencyRaw : 50,
    estHours: row.estHours ?? 0,
    tips: row.tips || "",
    whyNeeded: row.whyNeeded || "",
    conditions: row.conditions || {},
    dueDate,
    status: "Upcoming",
    userId,
    createdAt: now,
    tier: "task",
    spawnedFrom: { kind: source.kind, id: source.id }
  };
  if (row.notesEnabled !== undefined) doc.notesEnabled = row.notesEnabled;
  if (row.quoteTracker !== undefined) doc.quoteTracker = row.quoteTracker;
  if (row.onCompleteSpawns !== undefined) doc.onCompleteSpawns = row.onCompleteSpawns;
  if (row.workflowId) doc.workflowId = row.workflowId;
  if (spawn && isSubjectAwareSpawn(spawn)) {
    doc.subject = spawn.subject;
    doc.institutionId = spawn.institutionId;
    doc.institution = spawn.institution;
    doc.canonicalKeyVersion = 2;
  }
  return doc;
}

// Canonical move-date read (mirrors peezyChat.loadUserContext):
// users/{uid}/identity/identity first, then user_assessments limit(1).
async function readMoveDate(db, userId) {
  const userRef = db.collection("users").doc(userId);
  const [identitySnapshot, assessmentSnapshot] = await Promise.all([
    userRef.collection("identity").doc("identity").get(),
    userRef.collection("user_assessments").limit(1).get()
  ]);
  const identity = identitySnapshot.data() || {};
  const assessment = assessmentSnapshot.empty ? {} : assessmentSnapshot.docs[0].data();
  return dateFromValue(identity.moveDate) || dateFromValue(assessment.moveDate);
}

function replayToken(snapshot, fingerprint) {
  const storedFingerprint = snapshot.get("fingerprint");
  if (storedFingerprint === undefined || storedFingerprint === fingerprint) {
    return snapshot.get("result");
  }
  throw new HttpsError(
    "failed-precondition",
    "This idempotency token was already used for a different spawn request"
  );
}

function isAlreadyExists(error) {
  return error?.code === 6 || error?.code === "6" ||
    error?.code === "already-exists" || error?.code === "ALREADY_EXISTS" ||
    error?.code === "already_exists";
}

async function executeSpawn(db, userId, request, now = new Date()) {
  const fingerprint = requestFingerprint(request);
  const tokenRef = db.collection("users").doc(userId)
    .collection("spawnTokens").doc(request.token);
  const existingToken = await tokenRef.get();
  if (existingToken.exists) {
    return replayToken(existingToken, fingerprint);
  }

  // All catalog reads before any write — an unknown id rejects with nothing written.
  const resolvedSpawns = [];
  for (const spawn of request.spawns) {
    const snapshot = await db.collection("taskCatalog").doc(spawn.taskId).get();
    if (!snapshot.exists) {
      throw new HttpsError("not-found", `Unknown catalog task: ${spawn.taskId}`);
    }
    resolvedSpawns.push({ spawn, row: snapshot.data() });
  }

  const moveDate = await readMoveDate(db, userId);

  const tasksCollection = db.collection("users").doc(userId).collection("tasks");
  const subjectAware = isSubjectAwareSpawn(request.spawns[0]);
  const seenTaskIds = new Set();
  const created = [];
  for (const [ordinal, { spawn, row }] of resolvedSpawns.entries()) {
    const docId = subjectAware
      ? canonicalTaskIdV2(userId, spawn)
      : deterministicTaskId(request.token, ordinal);
    if (seenTaskIds.has(docId)) {
      throw new HttpsError("invalid-argument", "Duplicate canonical task identity in one request");
    }
    seenTaskIds.add(docId);
    const docRef = tasksCollection.doc(docId);
    const dueDate = resolveDueDate(row, moveDate, now);
    const title = spawnTitle(row, spawn.titleParams ||
      (subjectAware ? { institution: spawn.institution } : undefined));
    created.push({ id: docRef.id, taskId: row.taskId, title, dueDateISO: dueDate.toISOString() });
  }

  const userRef = db.collection("users").doc(userId);
  const transactionResult = await db.runTransaction(async (transaction) => {
    const rootSnapshot = await transaction.get(userRef);
    const resetState = rootSnapshot.get("taskReset")?.state;
    if (resetState === "deleting" || resetState === "awaiting_local_reset") {
      throw new HttpsError("failed-precondition", "Task reset is active");
    }
    const tokenSnapshot = await transaction.get(tokenRef);
    if (tokenSnapshot.exists) return replayToken(tokenSnapshot, fingerprint);
    // C6.1 root fence: every committing branch requires accountDeletion absent on the owner root.
    if (rootSnapshot.exists && rootSnapshot.data()?.accountDeletion !== undefined) throw deletionError("ACCOUNT_DELETION_FENCED");

    const taskRows = resolvedSpawns.map(({ spawn, row }, ordinal) => {
      const id = subjectAware
        ? canonicalTaskIdV2(userId, spawn)
        : deterministicTaskId(request.token, ordinal);
      return { spawn, row, ref: tasksCollection.doc(id), result: created[ordinal] };
    });
    const taskSnapshots = [];
    for (const item of taskRows) taskSnapshots.push(await transaction.get(item.ref));
    const committedCreated = [];

    for (const [index, item] of taskRows.entries()) {
      const existing = taskSnapshots[index];
      if (!subjectAware) {
        if (existing.exists) {
          const collision = new Error(`Document already exists: ${item.ref.path}`);
          collision.code = 6;
          throw collision;
        }
        transaction.create(item.ref, buildTaskDoc({
          row: item.row, docId: item.ref.id, userId, title: item.result.title,
          dueDate: new Date(item.result.dueDateISO), source: request.source, now,
          spawn: item.spawn
        }));
        committedCreated.push(item.result);
        continue;
      }

      if (existing.exists) {
        const data = existing.data() || {};
        const sameProvenance = data.id === item.ref.id && data.userId === userId &&
          data.taskId === item.spawn.taskId && data.canonicalKeyVersion === 2 &&
          canonicalJSON(data.subject) === canonicalJSON(item.spawn.subject) &&
          data.institutionId === item.spawn.institutionId &&
          canonicalJSON(data.spawnedFrom) === canonicalJSON(request.source);
        if (!sameProvenance) {
          throw new HttpsError("failed-precondition", `Canonical task ${item.ref.id} has invalid provenance`);
        }
        const enrichment = {};
        if (data.institution !== item.spawn.institution) enrichment.institution = item.spawn.institution;
        if (data.title !== item.result.title) enrichment.title = item.result.title;
        if (Object.keys(enrichment).length) transaction.set(item.ref, enrichment, { merge: true });
        const persistedDueDate = dateFromValue(data.dueDate);
        if (!persistedDueDate) {
          throw new HttpsError("failed-precondition", `Canonical task ${item.ref.id} has invalid due date`);
        }
        committedCreated.push({
          id: item.ref.id,
          taskId: data.taskId,
          title: enrichment.title ?? data.title,
          dueDateISO: persistedDueDate.toISOString()
        });
      } else {
        transaction.create(item.ref, buildTaskDoc({
          row: item.row, docId: item.ref.id, userId, title: item.result.title,
          dueDate: new Date(item.result.dueDateISO), source: request.source, now,
          spawn: item.spawn
        }));
        committedCreated.push(item.result);
      }
    }

    if (request.answers && Object.keys(request.answers).length > 0) {
      transaction.set(userRef.collection("moveAnswers").doc("answers"), request.answers, { merge: true });
    }
    const result = { created: committedCreated };
    transaction.create(tokenRef, {
      result,
      fingerprint,
      at: admin.firestore.FieldValue.serverTimestamp()
    });
    return result;
  });
  return transactionResult;
}

async function executeSubjectAwareSpawn(db, userId, request, now = new Date()) {
  if (!request.spawns.length || !request.spawns.every(isSubjectAwareSpawn)) {
    throw new HttpsError("invalid-argument", "Subject-aware execution requires t2 identity");
  }
  return executeSpawn(db, userId, request, now);
}

async function handleSpawnRequest(
  request,
  dbFactory = () => admin.firestore(),
  now = undefined
) {
  const userId = request.auth?.uid;
  if (!userId) {
    throw new HttpsError("unauthenticated", "Sign in before spawning tasks");
  }

  let cleaned;
  try {
    cleaned = validateRequest(request.data);
  } catch (error) {
    if (error instanceof SpawnValidationError) {
      throw new HttpsError("invalid-argument", error.message);
    }
    throw error;
  }

  if (Object.prototype.hasOwnProperty.call(cleaned, "expectedUserId") &&
      cleaned.expectedUserId !== userId) {
    throw new HttpsError(
      "failed-precondition",
      "expectedUserId does not match the authenticated user"
    );
  }

  if (cleaned.spawns.every(isSubjectAwareSpawn)) {
    const identities = cleaned.spawns.map((spawn) => canonicalTaskIdV2(userId, spawn));
    if (new Set(identities).size !== identities.length) {
      throw new HttpsError("invalid-argument", "Duplicate canonical task identity in one request");
    }
  }

  return executeSpawn(dbFactory(), userId, cleaned, now);
}

const spawnTasks = onCall(
  { region: "us-central1", timeoutSeconds: 15, memory: "256MiB" },
  (request) => handleSpawnRequest(request)
);

module.exports = {
  spawnTasks,
  SpawnValidationError,
  validateRequest,
  dateFromValue,
  resolveDueDate,
  spawnTitle,
  buildTaskDoc,
  executeSpawn,
  canonicalJSON,
  requestFingerprint,
  deterministicTaskId,
  isValidDocumentId,
  canonicalTaskIdV2,
  isSubjectAwareSpawn,
  executeSubjectAwareSpawn,
  handleSpawnRequest
};
