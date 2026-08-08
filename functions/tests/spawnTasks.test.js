"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  SpawnValidationError,
  validateRequest,
  resolveDueDate,
  spawnTitle,
  buildTaskDoc,
  executeSpawn
} = require("../spawnTasks");

const NOW = new Date("2026-08-08T15:00:00Z");
const MOVE_DATE = new Date("2026-09-07T00:00:00Z");

function catalogRow(overrides = {}) {
  return {
    taskId: "FORWARD_MAIL",
    title: "Forward your mail",
    actionCategory: "notify",
    category: "admin",
    actionType: "workflow",
    taskType: "survey",
    conditions: {},
    desc: "File the USPS change of address.",
    estHours: 1,
    tips: "Do it online.",
    urgencyPercentage: 90,
    whyNeeded: "Mail follows you.",
    ...overrides
  };
}

// Minimal Firestore stub: routes doc gets by path, records batch writes.
function fakeDb({ tokenDoc = null, catalog = {}, identity = {}, assessments = [] } = {}) {
  const writes = [];
  const state = { commits: 0, autoId: 0 };

  function docSnapshot(data) {
    return {
      exists: data != null,
      data: () => data,
      get: (field) => (data ? data[field] : undefined)
    };
  }

  function getForPath(path) {
    const segments = path.split("/");
    if (segments[0] === "taskCatalog") {
      return docSnapshot(catalog[segments[1]] ?? null);
    }
    if (segments[2] === "spawnTokens") {
      return docSnapshot(tokenDoc);
    }
    if (segments[2] === "identity" && segments[3] === "identity") {
      return docSnapshot(identity);
    }
    throw new Error(`Unexpected doc get: ${path}`);
  }

  function makeCollection(path) {
    return {
      path,
      doc(id) {
        const docId = id ?? `auto-${state.autoId++}`;
        const docPath = `${path}/${docId}`;
        return {
          id: docId,
          path: docPath,
          collection: (sub) => makeCollection(`${docPath}/${sub}`),
          get: async () => getForPath(docPath)
        };
      },
      limit() {
        assert.equal(path.split("/")[2], "user_assessments");
        return {
          get: async () => ({
            empty: assessments.length === 0,
            docs: assessments.map((data) => ({ data: () => data }))
          })
        };
      }
    };
  }

  return {
    writes,
    state,
    collection: (name) => makeCollection(name),
    batch() {
      return {
        set(ref, data, options) {
          writes.push({ path: ref.path, data, options });
        },
        async commit() {
          state.commits += 1;
        }
      };
    }
  };
}

function request(overrides = {}) {
  return validateRequest({
    token: "task-1-spawn",
    source: { kind: "conversation", id: "MONEY_ACCOUNTS" },
    spawns: [{ taskId: "FORWARD_MAIL" }],
    ...overrides
  });
}

// ── Validation ──

test("validateRequest rejects missing token, empty spawns, empty taskId, bad source", () => {
  const valid = {
    token: "t",
    source: { kind: "nudge", id: "N1" },
    spawns: [{ taskId: "FORWARD_MAIL" }]
  };
  assert.throws(() => validateRequest({ ...valid, token: "  " }), SpawnValidationError);
  assert.throws(() => validateRequest({ ...valid, spawns: [] }), SpawnValidationError);
  assert.throws(() => validateRequest({ ...valid, spawns: [{ taskId: "" }] }), SpawnValidationError);
  assert.throws(() => validateRequest({ ...valid, source: { kind: "other", id: "N1" } }), SpawnValidationError);
  assert.throws(() => validateRequest({ ...valid, answers: ["a"] }), SpawnValidationError);
  const cleaned = validateRequest({
    ...valid,
    spawns: [{ taskId: " FORWARD_MAIL ", titleParams: { institution: "Chase" } }]
  });
  assert.deepEqual(cleaned.spawns, [{ taskId: "FORWARD_MAIL", titleParams: { institution: "Chase" } }]);
});

// ── Date math ──

test("dateRule override anchors on moveDate plus offsetDays", () => {
  const row = catalogRow({ dateRule: { anchor: "moveDate", offsetDays: -21 } });
  const due = resolveDueDate(row, MOVE_DATE, NOW);
  assert.equal(due.toISOString(), "2026-08-17T00:00:00.000Z");
});

test("urgency math matches calculateDueDate: trunc(totalDays * (1 - urgency/100))", () => {
  // 30 days out, urgency 90 → 30 * (1 - 0.9) = 2.999…96 in IEEE-754 doubles,
  // truncated to 2 — identical to Swift's Int(daysFromNow).
  const due = resolveDueDate(catalogRow(), MOVE_DATE, NOW);
  assert.equal(due.toISOString(), "2026-08-10T00:00:00.000Z");
});

test("past or same-day move and missing moveDate both clamp to today", () => {
  const today = "2026-08-08T00:00:00.000Z";
  assert.equal(resolveDueDate(catalogRow(), new Date("2026-08-01T00:00:00Z"), NOW).toISOString(), today);
  assert.equal(resolveDueDate(catalogRow(), null, NOW).toISOString(), today);
});

// ── Title + doc shape ──

test("spawnTitle substitutes {institution} from titleParams", () => {
  const row = catalogRow({ title: "Update {institution} address" });
  assert.equal(spawnTitle(row, { institution: "Chase" }), "Update Chase address");
  assert.equal(spawnTitle(row, undefined), "Update {institution} address");
});

test("buildTaskDoc mirrors the generation shape with status Upcoming", () => {
  const row = catalogRow({
    workflowId: "forward_mail",
    notesEnabled: true,
    quoteTracker: "v1",
    onCompleteSpawns: [{ id: "RETURN_ISP_EQUIPMENT", dateRule: { anchor: "moveDate", offsetDays: 2 } }]
  });
  const due = new Date("2026-08-11T00:00:00Z");
  const doc = buildTaskDoc({
    row, docId: "auto-0", userId: "u1", title: "Forward your mail",
    dueDate: due, source: { kind: "conversation", id: "MONEY_ACCOUNTS" }, now: NOW
  });
  assert.deepEqual(doc, {
    id: "auto-0",
    taskId: "FORWARD_MAIL",
    title: "Forward your mail",
    desc: "File the USPS change of address.",
    category: "admin",
    actionCategory: "notify",
    actionType: "workflow",
    taskType: "survey",
    urgencyPercentage: 90,
    estHours: 1,
    tips: "Do it online.",
    whyNeeded: "Mail follows you.",
    conditions: {},
    dueDate: due,
    status: "Upcoming",
    userId: "u1",
    createdAt: NOW,
    tier: "task",
    spawnedFrom: { kind: "conversation", id: "MONEY_ACCOUNTS" },
    notesEnabled: true,
    quoteTracker: "v1",
    onCompleteSpawns: [{ id: "RETURN_ISP_EQUIPMENT", dateRule: { anchor: "moveDate", offsetDays: 2 } }],
    workflowId: "forward_mail"
  });
});

// ── executeSpawn behavior ──

test("duplicate token returns the stored result and writes nothing", async () => {
  const stored = { created: [{ id: "auto-9", taskId: "FORWARD_MAIL", title: "Forward your mail", dueDateISO: "2026-08-11T00:00:00.000Z" }] };
  const db = fakeDb({ tokenDoc: { result: stored, at: "earlier" } });
  const result = await executeSpawn(db, "u1", request(), NOW);
  assert.deepEqual(result, stored);
  assert.equal(db.writes.length, 0);
  assert.equal(db.state.commits, 0);
});

test("unknown taskId rejects not-found with nothing written", async () => {
  const db = fakeDb({ catalog: {} });
  await assert.rejects(
    executeSpawn(db, "u1", request(), NOW),
    (error) => error.code === "not-found"
  );
  assert.equal(db.writes.length, 0);
  assert.equal(db.state.commits, 0);
});

test("batch shape: task docs + answers merge + token in one committed batch", async () => {
  const db = fakeDb({
    catalog: {
      FORWARD_MAIL: catalogRow(),
      UPDATE_BANK: catalogRow({
        taskId: "UPDATE_BANK",
        title: "Update {institution} address",
        dateRule: { anchor: "moveDate", offsetDays: -21 }
      })
    },
    identity: { moveDate: MOVE_DATE.toISOString() }
  });

  const result = await executeSpawn(db, "u1", request({
    spawns: [
      { taskId: "FORWARD_MAIL" },
      { taskId: "UPDATE_BANK", titleParams: { institution: "Chase" } }
    ],
    answers: { banks: "Chase" }
  }), NOW);

  assert.equal(db.state.commits, 1);
  assert.equal(db.writes.length, 4);

  const [first, second, answersWrite, tokenWrite] = db.writes;
  assert.equal(first.path, "users/u1/tasks/auto-0");
  assert.equal(first.data.status, "Upcoming");
  assert.equal(first.data.id, "auto-0");
  assert.equal(second.data.title, "Update Chase address");
  assert.equal(second.data.dueDate.toISOString(), "2026-08-17T00:00:00.000Z");

  assert.equal(answersWrite.path, "users/u1/moveAnswers/answers");
  assert.deepEqual(answersWrite.data, { banks: "Chase" });
  assert.deepEqual(answersWrite.options, { merge: true });

  assert.equal(tokenWrite.path, "users/u1/spawnTokens/task-1-spawn");
  assert.deepEqual(tokenWrite.data.result, result);

  assert.deepEqual(result, {
    created: [
      { id: "auto-0", taskId: "FORWARD_MAIL", title: "Forward your mail", dueDateISO: "2026-08-10T00:00:00.000Z" },
      { id: "auto-1", taskId: "UPDATE_BANK", title: "Update Chase address", dueDateISO: "2026-08-17T00:00:00.000Z" }
    ]
  });
});

test("moveDate falls back to the assessment doc when identity has none", async () => {
  const db = fakeDb({
    catalog: { FORWARD_MAIL: catalogRow() },
    identity: {},
    assessments: [{ moveDate: MOVE_DATE.getTime() }]
  });
  const result = await executeSpawn(db, "u1", request(), NOW);
  assert.equal(result.created[0].dueDateISO, "2026-08-10T00:00:00.000Z");
});
