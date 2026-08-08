const test = require("node:test");
const assert = require("node:assert/strict");

const {
  SpawnValidationError,
  validateRequest,
  resolveDueDate,
  spawnTitle,
  buildTaskDoc,
  executeSpawn
} = require("./spawnTasks");

const UID = "uid1";
const NOW = new Date("2026-08-08T12:00:00Z");

const BASE_REQUEST = {
  token: "MONEY_ACCOUNTS-spawn",
  source: { kind: "conversation", id: "MONEY_ACCOUNTS" },
  spawns: [{ taskId: "UPDATE_BANK" }]
};

const BANK_ROW = {
  taskId: "UPDATE_BANK",
  title: "Update your address with {institution}",
  actionCategory: "notify",
  category: "finance",
  actionType: "off-app",
  taskType: "provide_info",
  conditions: {},
  desc: "Update the address on file.",
  estHours: 1,
  tips: "Do it online.",
  urgencyPercentage: 60,
  whyNeeded: "Statements follow you.",
  notesEnabled: true,
  workflowId: "update_bank"
};

// Minimal in-memory Firestore stub: routes the exact doc paths executeSpawn
// touches, records batch writes only on commit.
function makeFakeDb({ catalog = {}, tokenResult = null, identityMoveDate = "2026-09-07" } = {}) {
  const writes = [];
  let autoId = 0;
  const snap = (data) => ({
    exists: data !== null,
    data: () => data ?? undefined,
    get: (field) => (data ?? {})[field]
  });

  function makeCollection(path) {
    return {
      doc(id) {
        const docId = id ?? `auto-${++autoId}`;
        const docPath = `${path}/${docId}`;
        return {
          id: docId,
          path: docPath,
          collection: (sub) => makeCollection(`${docPath}/${sub}`),
          async get() {
            if (docPath === `users/${UID}/identity/identity`) {
              return snap(identityMoveDate ? { moveDate: identityMoveDate } : null);
            }
            if (path === "taskCatalog") return snap(catalog[docId] ?? null);
            if (path === `users/${UID}/spawnTokens`) {
              return snap(tokenResult ? { result: tokenResult } : null);
            }
            return snap(null);
          }
        };
      },
      limit: () => ({ async get() { return { empty: true, docs: [] }; } })
    };
  }

  return {
    writes,
    collection: (name) => makeCollection(name),
    batch() {
      const ops = [];
      return {
        set: (ref, data, opts) => ops.push({ path: ref.path, data, opts }),
        async commit() { writes.push(...ops); }
      };
    }
  };
}

function run(db, request, now = NOW) {
  return executeSpawn(db, UID, validateRequest(request), now);
}

test("duplicate token returns the stored result and writes nothing", async () => {
  const stored = { created: [{ id: "abc", taskId: "UPDATE_BANK", title: "t", dueDateISO: "2026-08-20T00:00:00.000Z" }] };
  const db = makeFakeDb({ catalog: { UPDATE_BANK: BANK_ROW }, tokenResult: stored });

  const result = await run(db, BASE_REQUEST);

  assert.deepEqual(result, stored);
  assert.equal(db.writes.length, 0);
});

test("unknown taskId rejects not-found and writes nothing", async () => {
  const db = makeFakeDb({ catalog: { UPDATE_BANK: BANK_ROW } });
  const request = { ...BASE_REQUEST, spawns: [{ taskId: "UPDATE_BANK" }, { taskId: "NOT_A_ROW" }] };

  await assert.rejects(
    () => run(db, request),
    (error) => error.code === "not-found"
  );
  assert.equal(db.writes.length, 0);
});

test("batch holds task docs, answers merge, and token in one commit", async () => {
  const db = makeFakeDb({ catalog: { UPDATE_BANK: BANK_ROW } });
  const request = {
    token: "MONEY_ACCOUNTS-spawn",
    source: { kind: "conversation", id: "MONEY_ACCOUNTS" },
    spawns: [
      { taskId: "UPDATE_BANK", titleParams: { institution: "Chase" } },
      { taskId: "UPDATE_BANK", titleParams: { institution: "Ally" } }
    ],
    answers: { banks: "Chase, Ally" }
  };

  const result = await run(db, request);

  assert.equal(db.writes.length, 4);

  const taskWrites = db.writes.filter((write) => write.path.startsWith(`users/${UID}/tasks/`));
  assert.equal(taskWrites.length, 2);
  const [first] = taskWrites;
  assert.equal(first.data.status, "Upcoming");
  assert.equal(first.data.tier, "task");
  assert.equal(first.data.title, "Update your address with Chase");
  assert.equal(first.data.taskId, "UPDATE_BANK");
  assert.equal(first.data.id, first.path.split("/").pop());
  assert.equal(first.data.userId, UID);
  assert.equal(first.data.urgencyPercentage, 60);
  assert.equal(first.data.notesEnabled, true);
  assert.equal(first.data.workflowId, "update_bank");
  assert.deepEqual(first.data.spawnedFrom, { kind: "conversation", id: "MONEY_ACCOUNTS" });
  assert.deepEqual(
    Object.keys(first.data).sort(),
    [
      "actionCategory", "actionType", "category", "conditions", "createdAt", "desc",
      "dueDate", "estHours", "id", "notesEnabled", "spawnedFrom", "status", "taskId",
      "taskType", "tier", "tips", "title", "urgencyPercentage", "userId", "whyNeeded",
      "workflowId"
    ].sort()
  );

  const answersWrite = db.writes.find((write) => write.path === `users/${UID}/moveAnswers/answers`);
  assert.deepEqual(answersWrite.data, { banks: "Chase, Ally" });
  assert.deepEqual(answersWrite.opts, { merge: true });

  const tokenWrite = db.writes.find((write) => write.path === `users/${UID}/spawnTokens/MONEY_ACCOUNTS-spawn`);
  assert.deepEqual(tokenWrite.data.result, result);

  assert.equal(result.created.length, 2);
  assert.deepEqual(Object.keys(result.created[0]).sort(), ["dueDateISO", "id", "taskId", "title"]);
  assert.equal(result.created[1].title, "Update your address with Ally");
});

test("missing move date falls back to a today due date", async () => {
  const db = makeFakeDb({ catalog: { UPDATE_BANK: BANK_ROW }, identityMoveDate: null });

  const result = await run(db, BASE_REQUEST);

  assert.equal(result.created[0].dueDateISO, "2026-08-08T00:00:00.000Z");
});

test("validateRequest rejects empty token, bad source, empty spawns, empty taskId", () => {
  const isValidationError = (error) => error instanceof SpawnValidationError;
  assert.throws(() => validateRequest({ ...BASE_REQUEST, token: "  " }), isValidationError);
  assert.throws(() => validateRequest({ ...BASE_REQUEST, source: { kind: "other", id: "x" } }), isValidationError);
  assert.throws(() => validateRequest({ ...BASE_REQUEST, spawns: [] }), isValidationError);
  assert.throws(() => validateRequest({ ...BASE_REQUEST, spawns: [{ taskId: "  " }] }), isValidationError);
  assert.throws(() => validateRequest({ ...BASE_REQUEST, answers: ["not", "a", "map"] }), isValidationError);
});

test("resolveDueDate mirrors the urgency-timeline formula", () => {
  const moveDate = new Date("2026-09-07T00:00:00Z");

  // 30 days out, urgency 94 → trunc(30 × 0.06) = 1 day from today.
  const urgent = resolveDueDate({ urgencyPercentage: 94 }, moveDate, NOW);
  assert.equal(urgent.toISOString(), "2026-08-09T00:00:00.000Z");

  // urgency 50 → trunc(30 × 0.5) = 15 days out.
  const mid = resolveDueDate({ urgencyPercentage: 50 }, moveDate, NOW);
  assert.equal(mid.toISOString(), "2026-08-23T00:00:00.000Z");

  // Past/same-day move clamps to today.
  const clamped = resolveDueDate({ urgencyPercentage: 50 }, new Date("2026-08-01T00:00:00Z"), NOW);
  assert.equal(clamped.toISOString(), "2026-08-08T00:00:00.000Z");
});

test("resolveDueDate prefers dateRule offset over urgency math", () => {
  const moveDate = new Date("2026-09-07T00:00:00Z");

  const early = resolveDueDate(
    { urgencyPercentage: 94, dateRule: { anchor: "moveDate", offsetDays: -21 } },
    moveDate,
    NOW
  );
  assert.equal(early.toISOString(), "2026-08-17T00:00:00.000Z");

  const postMove = resolveDueDate({ dateRule: { anchor: "moveDate", offsetDays: 2 } }, moveDate, NOW);
  assert.equal(postMove.toISOString(), "2026-09-09T00:00:00.000Z");
});

test("spawnTitle substitutes {institution} only when provided", () => {
  assert.equal(spawnTitle({ title: "Update {institution}" }, { institution: "Chase" }), "Update Chase");
  assert.equal(spawnTitle({ title: "Update {institution}" }, undefined), "Update {institution}");
  assert.equal(spawnTitle({}, { institution: "Chase" }), "");
});

test("buildTaskDoc defaults mirror the generation shape", () => {
  const dueDate = new Date("2026-08-20T00:00:00Z");
  const doc = buildTaskDoc({
    row: { taskId: "BARE_ROW" },
    docId: "doc1",
    userId: UID,
    title: "",
    dueDate,
    source: { kind: "onComplete", id: "SETUP_INTERNET" },
    now: NOW
  });
  assert.equal(doc.taskId, "BARE_ROW");
  assert.equal(doc.category, "custom");
  assert.equal(doc.actionType, "off-app");
  assert.equal(doc.taskType, "provide_info");
  assert.equal(doc.urgencyPercentage, 50);
  assert.equal(doc.estHours, 0);
  assert.deepEqual(doc.conditions, {});
  assert.equal(doc.dueDate, dueDate);
  assert.equal(doc.createdAt, NOW);
  assert.equal(doc.status, "Upcoming");
  assert.equal(doc.tier, "task");
  assert.equal("notesEnabled" in doc, false);
  assert.equal("quoteTracker" in doc, false);
  assert.equal("onCompleteSpawns" in doc, false);
  assert.equal("workflowId" in doc, false);
});
