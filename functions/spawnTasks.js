const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

const MILLISECONDS_PER_DAY = 24 * 60 * 60 * 1000;
const SOURCE_KINDS = ["conversation", "nudge", "onComplete"];

class SpawnValidationError extends Error {}

// Request: { token, source:{kind:"conversation"|"nudge"|"onComplete", id},
//            spawns:[{taskId, titleParams?:{institution}}], answers?:{k:v} }
function validateRequest(data) {
  const { token, source, spawns, answers } = data || {};

  if (typeof token !== "string" || token.trim().length === 0) {
    throw new SpawnValidationError("A non-empty idempotency token is required");
  }
  if (!source || typeof source !== "object" ||
      !SOURCE_KINDS.includes(source.kind) ||
      typeof source.id !== "string" || source.id.length === 0) {
    throw new SpawnValidationError("source requires kind (conversation|nudge|onComplete) and id");
  }
  if (!Array.isArray(spawns) || spawns.length === 0) {
    throw new SpawnValidationError("spawns must be a non-empty array");
  }

  const cleanedSpawns = spawns.map((spawn) => {
    if (!spawn || typeof spawn !== "object" ||
        typeof spawn.taskId !== "string" || spawn.taskId.trim().length === 0) {
      throw new SpawnValidationError("Every spawn requires a non-empty taskId");
    }
    const cleaned = { taskId: spawn.taskId.trim() };
    const institution = spawn.titleParams?.institution;
    if (typeof institution === "string" && institution.length > 0) {
      cleaned.titleParams = { institution };
    }
    return cleaned;
  });

  let cleanedAnswers = null;
  if (answers !== undefined && answers !== null) {
    if (typeof answers !== "object" || Array.isArray(answers)) {
      throw new SpawnValidationError("answers must be a map of key/value pairs");
    }
    cleanedAnswers = answers;
  }

  return {
    token: token.trim(),
    source: { kind: source.kind, id: source.id },
    spawns: cleanedSpawns,
    answers: cleanedAnswers
  };
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
function buildTaskDoc({ row, docId, userId, title, dueDate, source, now }) {
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

async function executeSpawn(db, userId, request, now = new Date()) {
  // Idempotency: a replayed token returns the stored result, writes nothing.
  const tokenRef = db.collection("users").doc(userId)
    .collection("spawnTokens").doc(request.token);
  const existingToken = await tokenRef.get();
  if (existingToken.exists) {
    return existingToken.get("result");
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

  const batch = db.batch();
  const tasksCollection = db.collection("users").doc(userId).collection("tasks");
  const created = [];
  for (const { spawn, row } of resolvedSpawns) {
    const docRef = tasksCollection.doc();
    const dueDate = resolveDueDate(row, moveDate, now);
    const title = spawnTitle(row, spawn.titleParams);
    batch.set(docRef, buildTaskDoc({
      row,
      docId: docRef.id,
      userId,
      title,
      dueDate,
      source: request.source,
      now
    }));
    created.push({ id: docRef.id, taskId: row.taskId, title, dueDateISO: dueDate.toISOString() });
  }

  if (request.answers && Object.keys(request.answers).length > 0) {
    batch.set(
      db.collection("users").doc(userId).collection("moveAnswers").doc("answers"),
      request.answers,
      { merge: true }
    );
  }

  const result = { created };
  batch.set(tokenRef, { result, at: admin.firestore.FieldValue.serverTimestamp() });
  await batch.commit();
  return result;
}

const spawnTasks = onCall(
  { region: "us-central1", timeoutSeconds: 15, memory: "256MiB" },
  async (request) => {
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

    return executeSpawn(admin.firestore(), userId, cleaned);
  }
);

module.exports = {
  spawnTasks,
  SpawnValidationError,
  validateRequest,
  dateFromValue,
  resolveDueDate,
  spawnTitle,
  buildTaskDoc,
  executeSpawn
};
