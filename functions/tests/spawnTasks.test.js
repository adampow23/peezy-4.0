"use strict";

const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const test = require("node:test");

const {
  SpawnValidationError,
  validateRequest,
  resolveDueDate,
  spawnTitle,
  buildTaskDoc,
  executeSpawn,
  canonicalJSON,
  requestFingerprint,
  deterministicTaskId,
  handleSpawnRequest
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

function alreadyExists(path) {
  const error = new Error(`Document already exists: ${path}`);
  error.code = 6;
  return error;
}

// In-memory Firestore fake with atomic batch create preconditions.
function fakeDb({
  tokenDoc = null,
  catalog = {},
  identity = {},
  assessments = [],
  documents = {},
  barrierCommits = 0,
  beforeCommit = null
} = {}) {
  const docs = new Map(Object.entries(documents));
  for (const [id, data] of Object.entries(catalog)) {
    docs.set(`taskCatalog/${id}`, data);
  }
  docs.set("users/u1/identity/identity", identity);
  if (tokenDoc !== null) {
    docs.set("users/u1/spawnTokens/task-1-spawn", tokenDoc);
  }

  let barrierArrivals = 0;
  let releaseBarrier;
  const barrier = new Promise((resolve) => {
    releaseBarrier = resolve;
  });
  let commitHookCalls = 0;
  const writes = [];
  const state = {
    reads: [],
    commitAttempts: 0,
    commits: 0,
    failedCommits: 0,
    autoId: 0,
    documents: docs
  };

  function docSnapshot(data) {
    return {
      exists: data !== undefined,
      data: () => data,
      get: (field) => (data === undefined ? undefined : data[field])
    };
  }

  async function getForPath(path) {
    const data = docs.get(path);
    state.reads.push({ path, exists: data !== undefined });
    return docSnapshot(data);
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
          get: () => getForPath(docPath)
        };
      },
      limit() {
        assert.equal(path.split("/")[2], "user_assessments");
        return {
          async get() {
            state.reads.push({ path: `${path}?limit=1`, exists: assessments.length > 0 });
            return {
              empty: assessments.length === 0,
              docs: assessments.map((data) => ({ data: () => data }))
            };
          }
        };
      }
    };
  }

  function applyAtomically(ops) {
    const createdPaths = new Set();
    for (const op of ops) {
      if (op.type === "create" && (docs.has(op.path) || createdPaths.has(op.path))) {
        throw alreadyExists(op.path);
      }
      if (op.type === "create") createdPaths.add(op.path);
    }

    const nextDocs = new Map(docs);
    for (const op of ops) {
      if (op.type === "set" && op.options?.merge === true) {
        nextDocs.set(op.path, { ...(nextDocs.get(op.path) || {}), ...op.data });
      } else {
        nextDocs.set(op.path, op.data);
      }
    }
    docs.clear();
    for (const [path, data] of nextDocs) docs.set(path, data);
    writes.push(...ops);
    state.commits += 1;
  }

  const db = {
    writes,
    state,
    collection: (name) => makeCollection(name),
    batch() {
      const ops = [];
      return {
        create(ref, data) {
          ops.push({ type: "create", path: ref.path, data });
        },
        set(ref, data, options) {
          ops.push({ type: "set", path: ref.path, data, options });
        },
        async commit() {
          state.commitAttempts += 1;
          if (barrierCommits > 0) {
            barrierArrivals += 1;
            if (barrierArrivals === barrierCommits) releaseBarrier();
            await barrier;
          }
          if (beforeCommit) {
            commitHookCalls += 1;
            await beforeCommit({ docs, ops, call: commitHookCalls });
          }
          try {
            applyAtomically(ops);
          } catch (error) {
            state.failedCommits += 1;
            throw error;
          }
        }
      };
    }
  };
  return db;
}

function expectedTaskDocId(token, ordinal) {
  const digest = createHash("sha256").update(`${token}|${ordinal}`).digest("hex");
  return `t1_${digest.slice(0, 40)}`;
}

function request(overrides = {}) {
  return validateRequest({
    token: "task-1-spawn",
    source: { kind: "conversation", id: "MONEY_ACCOUNTS" },
    spawns: [{ taskId: "FORWARD_MAIL" }],
    ...overrides
  });
}

function rawRequest(overrides = {}) {
  return {
    token: "task-1-spawn",
    source: { kind: "conversation", id: "MONEY_ACCOUNTS" },
    spawns: [{ taskId: "FORWARD_MAIL" }],
    ...overrides
  };
}

async function assertCallableRejectsBeforeDb(data, code, userId = "u1") {
  const db = fakeDb({ catalog: { FORWARD_MAIL: catalogRow() } });
  let dbFactoryCalls = 0;
  await assert.rejects(
    () => handleSpawnRequest(
      { auth: { uid: userId }, data },
      () => {
        dbFactoryCalls += 1;
        return db;
      },
      NOW
    ),
    (error) => error.code === code
  );
  assert.equal(dbFactoryCalls, 0);
  assert.equal(db.state.reads.length, 0);
  assert.equal(db.state.commitAttempts, 0);
  assert.equal(db.writes.length, 0);
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


test("spawn anchor: due = spawn instant + offsetDays x 24h, no midnight normalization", () => {
  // Non-midnight `now` — the instant is preserved exactly (movers chain).
  const nonMidnight = new Date("2026-08-14T21:37:12.000Z");
  const compare = catalogRow({ dateRule: { anchor: "spawn", offsetDays: 3 } });
  assert.equal(
    resolveDueDate(compare, MOVE_DATE, nonMidnight).toISOString(),
    "2026-08-17T21:37:12.000Z"
  );

  const book = catalogRow({ dateRule: { anchor: "spawn", offsetDays: 1 } });
  assert.equal(
    resolveDueDate(book, MOVE_DATE, nonMidnight).toISOString(),
    "2026-08-15T21:37:12.000Z"
  );
});

test("spawn anchor needs no moveDate and is DST-immune (UTC arithmetic)", () => {
  const row = catalogRow({ dateRule: { anchor: "spawn", offsetDays: 3 } });
  // Missing move date: spawn anchor still resolves (moveDate anchors cannot).
  assert.equal(
    resolveDueDate(row, null, NOW).toISOString(),
    "2026-08-11T15:00:00.000Z"
  );
  // US DST fall-back boundary (2026-11-01): +3 UTC days is exactly 72h —
  // wall-clock shifts do not change the stored instant.
  const acrossDst = new Date("2026-10-31T18:30:00.000Z");
  assert.equal(
    resolveDueDate(row, MOVE_DATE, acrossDst).toISOString(),
    "2026-11-03T18:30:00.000Z"
  );
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

test("legacy token without fingerprint returns stored result and writes nothing", async () => {
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

  const cleaned = request({
    spawns: [
      { taskId: "FORWARD_MAIL" },
      { taskId: "UPDATE_BANK", titleParams: { institution: "Chase" } }
    ],
    answers: { banks: "Chase" }
  });
  const result = await executeSpawn(db, "u1", cleaned, NOW);

  assert.equal(db.state.commits, 1);
  assert.equal(db.writes.length, 4);

  const [first, second, answersWrite, tokenWrite] = db.writes;
  assert.equal(first.type, "create");
  assert.equal(first.path, `users/u1/tasks/${expectedTaskDocId(cleaned.token, 0)}`);
  assert.equal(first.data.status, "Upcoming");
  assert.equal(first.data.id, expectedTaskDocId(cleaned.token, 0));
  assert.equal(second.type, "create");
  assert.equal(second.path, `users/u1/tasks/${expectedTaskDocId(cleaned.token, 1)}`);
  assert.equal(second.data.title, "Update Chase address");
  assert.equal(second.data.dueDate.toISOString(), "2026-08-17T00:00:00.000Z");

  assert.equal(answersWrite.path, "users/u1/moveAnswers/answers");
  assert.deepEqual(answersWrite.data, { banks: "Chase" });
  assert.deepEqual(answersWrite.options, { merge: true });

  assert.equal(tokenWrite.path, "users/u1/spawnTokens/task-1-spawn");
  assert.equal(tokenWrite.type, "create");
  assert.deepEqual(tokenWrite.data.result, result);
  assert.equal(tokenWrite.data.fingerprint, requestFingerprint(cleaned));

  assert.deepEqual(result, {
    created: [
      { id: expectedTaskDocId(cleaned.token, 0), taskId: "FORWARD_MAIL", title: "Forward your mail", dueDateISO: "2026-08-10T00:00:00.000Z" },
      { id: expectedTaskDocId(cleaned.token, 1), taskId: "UPDATE_BANK", title: "Update Chase address", dueDateISO: "2026-08-17T00:00:00.000Z" }
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

// ── Atomic idempotency ──

test("concurrent same-token calls atomically create one request and replay the winner", async () => {
  const db = fakeDb({
    catalog: {
      FORWARD_MAIL: catalogRow({ dateRule: { anchor: "spawn", offsetDays: 1 } }),
      UPDATE_BANK: catalogRow({ taskId: "UPDATE_BANK", title: "Update {institution}" })
    },
    identity: { moveDate: MOVE_DATE.toISOString() },
    barrierCommits: 2
  });
  const cleaned = request({
    spawns: [
      { taskId: "FORWARD_MAIL" },
      { taskId: "UPDATE_BANK", titleParams: { institution: "Chase" } }
    ],
    answers: { banks: "Chase" }
  });

  const [first, second] = await Promise.all([
    executeSpawn(db, "u1", cleaned, NOW),
    executeSpawn(db, "u1", cleaned, new Date("2026-08-08T15:00:01Z"))
  ]);

  assert.deepEqual(first, second);
  assert.deepEqual(
    first,
    db.state.documents.get("users/u1/spawnTokens/task-1-spawn").result
  );
  assert.equal(db.state.commitAttempts, 2);
  assert.equal(db.state.commits, 1);
  assert.equal(db.state.failedCommits, 1);
  const tokenReads = db.state.reads.filter(({ path }) => path === "users/u1/spawnTokens/task-1-spawn");
  assert.deepEqual(tokenReads.map(({ exists }) => exists), [false, false, true]);
  const taskPaths = [...db.state.documents.keys()].filter((path) => path.startsWith("users/u1/tasks/"));
  const tokenPaths = [...db.state.documents.keys()].filter((path) => path.startsWith("users/u1/spawnTokens/"));
  assert.deepEqual(taskPaths.sort(), [
    `users/u1/tasks/${expectedTaskDocId(cleaned.token, 0)}`,
    `users/u1/tasks/${expectedTaskDocId(cleaned.token, 1)}`
  ].sort());
  assert.deepEqual(tokenPaths, ["users/u1/spawnTokens/task-1-spawn"]);
});

test("ALREADY_EXISTS without a token after reread propagates the original error", async () => {
  const cleaned = request({ answers: { newAnswer: true } });
  const collisionPath = `users/u1/tasks/${expectedTaskDocId(cleaned.token, 0)}`;
  const existingTask = { id: "pre-existing" };
  const db = fakeDb({
    catalog: { FORWARD_MAIL: catalogRow() },
    documents: { [collisionPath]: existingTask }
  });

  let caught;
  try {
    await executeSpawn(db, "u1", cleaned, NOW);
  } catch (error) {
    caught = error;
  }

  assert.equal(caught?.code, 6);
  assert.match(caught?.message || "", /already exists/i);
  assert.equal(db.state.commitAttempts, 1);
  assert.equal(db.state.commits, 0);
  assert.equal(db.state.documents.get(collisionPath), existingTask);
  assert.equal(db.state.documents.has("users/u1/spawnTokens/task-1-spawn"), false);
  assert.equal(db.state.documents.has("users/u1/moveAnswers/answers"), false);
  assert.equal(db.writes.length, 0);
});

test("matching fingerprint fast-path replay returns stored result with zero writes", async () => {
  const db = fakeDb({ catalog: { FORWARD_MAIL: catalogRow() } });
  const cleaned = request();
  const first = await executeSpawn(db, "u1", cleaned, NOW);
  const before = {
    attempts: db.state.commitAttempts,
    commits: db.state.commits,
    writes: db.writes.length,
    reads: db.state.reads.length
  };

  const replay = await executeSpawn(db, "u1", cleaned, new Date("2026-08-09T15:00:00Z"));

  assert.deepEqual(replay, first);
  assert.equal(db.state.commitAttempts, before.attempts);
  assert.equal(db.state.commits, before.commits);
  assert.equal(db.writes.length, before.writes);
  assert.equal(db.state.reads.length, before.reads + 1);
});

test("same token with a different payload fails on the fast path with zero writes", async () => {
  const db = fakeDb({ catalog: { FORWARD_MAIL: catalogRow() } });
  const winner = request({ answers: { choice: "winner" } });
  const loser = request({ answers: { choice: "loser" } });
  await executeSpawn(db, "u1", winner, NOW);
  const before = {
    attempts: db.state.commitAttempts,
    commits: db.state.commits,
    writes: db.writes.length
  };

  await assert.rejects(
    executeSpawn(db, "u1", loser, NOW),
    (error) => error.code === "failed-precondition"
  );
  assert.equal(db.state.commitAttempts, before.attempts);
  assert.equal(db.state.commits, before.commits);
  assert.equal(db.writes.length, before.writes);
});

test("commit-time token collision with a different fingerprint fails with zero candidate writes", async () => {
  const stored = { created: [{ id: "winner", taskId: "FORWARD_MAIL" }] };
  const winner = request({ answers: { choice: "winner" } });
  const loser = request({ answers: { choice: "loser" } });
  const tokenPath = "users/u1/spawnTokens/task-1-spawn";
  const db = fakeDb({
    catalog: { FORWARD_MAIL: catalogRow() },
    beforeCommit: async ({ docs, call }) => {
      if (call === 1) {
        docs.set(tokenPath, { result: stored, fingerprint: requestFingerprint(winner), at: "winner" });
      }
    }
  });

  await assert.rejects(
    executeSpawn(db, "u1", loser, NOW),
    (error) => error.code === "failed-precondition"
  );
  assert.equal(db.state.commitAttempts, 1);
  assert.equal(db.state.commits, 0);
  assert.equal(db.writes.length, 0);
  assert.deepEqual(db.state.documents.get(tokenPath).result, stored);
  assert.equal([...db.state.documents.keys()].some((path) => path.startsWith("users/u1/tasks/")), false);
  assert.equal(db.state.documents.has("users/u1/moveAnswers/answers"), false);
});

test("concurrent different payloads keep only winner tasks and answers", async () => {
  const db = fakeDb({
    catalog: {
      UPDATE_BANK: catalogRow({ taskId: "UPDATE_BANK", title: "Update {institution}" })
    },
    barrierCommits: 2
  });
  const candidates = [
    request({
      spawns: [{ taskId: "UPDATE_BANK", titleParams: { institution: "Chase" } }],
      answers: { bank: "Chase" }
    }),
    request({
      spawns: [{ taskId: "UPDATE_BANK", titleParams: { institution: "Ally" } }],
      answers: { bank: "Ally" }
    })
  ];

  const settled = await Promise.allSettled(candidates.map((candidate) =>
    executeSpawn(db, "u1", candidate, NOW)
  ));
  const winnerIndex = settled.findIndex(({ status }) => status === "fulfilled");
  const loserIndex = winnerIndex === 0 ? 1 : 0;

  assert.notEqual(winnerIndex, -1);
  assert.equal(settled[loserIndex].status, "rejected");
  assert.equal(settled[loserIndex].reason.code, "failed-precondition");
  assert.equal(db.state.commitAttempts, 2);
  assert.equal(db.state.commits, 1);
  assert.equal(db.state.failedCommits, 1);
  const expectedInstitution = candidates[winnerIndex].spawns[0].titleParams.institution;
  const taskPath = `users/u1/tasks/${expectedTaskDocId(candidates[winnerIndex].token, 0)}`;
  assert.equal(db.state.documents.get(taskPath).title, `Update ${expectedInstitution}`);
  assert.deepEqual(db.state.documents.get("users/u1/moveAnswers/answers"), { bank: expectedInstitution });
  assert.equal(
    db.state.documents.get("users/u1/spawnTokens/task-1-spawn").fingerprint,
    requestFingerprint(candidates[winnerIndex])
  );
});

test("pre-existing moveAnswers document is merged in the atomic batch", async () => {
  const answersPath = "users/u1/moveAnswers/answers";
  const db = fakeDb({
    catalog: { FORWARD_MAIL: catalogRow() },
    documents: { [answersPath]: { retained: "yes", replaced: "old" } }
  });

  await executeSpawn(db, "u1", request({
    answers: { replaced: "new", added: true }
  }), NOW);

  assert.deepEqual(db.state.documents.get(answersPath), {
    retained: "yes",
    replaced: "new",
    added: true
  });
  const answersWrite = db.writes.find(({ path }) => path === answersPath);
  assert.equal(answersWrite.type, "set");
  assert.deepEqual(answersWrite.options, { merge: true });
});

test("task document ID collision fails the whole batch without partial writes", async () => {
  const cleaned = request({ answers: { shouldNotWrite: true } });
  const taskPath = `users/u1/tasks/${expectedTaskDocId(cleaned.token, 0)}`;
  const original = { id: "original", untouched: true };
  const db = fakeDb({
    catalog: { FORWARD_MAIL: catalogRow() },
    documents: { [taskPath]: original }
  });

  await assert.rejects(
    executeSpawn(db, "u1", cleaned, NOW),
    (error) => error.code === 6
  );
  assert.equal(db.state.commits, 0);
  assert.equal(db.writes.length, 0);
  assert.equal(db.state.documents.get(taskPath), original);
  assert.equal(db.state.documents.has("users/u1/moveAnswers/answers"), false);
  assert.equal(db.state.documents.has("users/u1/spawnTokens/task-1-spawn"), false);
});

test("same catalog task across different tokens creates distinct deterministic documents", async () => {
  const db = fakeDb({ catalog: { FORWARD_MAIL: catalogRow() } });
  const first = request({ token: "request-a" });
  const second = request({ token: "request-b" });

  const firstResult = await executeSpawn(db, "u1", first, NOW);
  const secondResult = await executeSpawn(db, "u1", second, NOW);

  assert.equal(firstResult.created[0].id, expectedTaskDocId("request-a", 0));
  assert.equal(secondResult.created[0].id, expectedTaskDocId("request-b", 0));
  assert.notEqual(firstResult.created[0].id, secondResult.created[0].id);
  assert.equal(db.state.commits, 2);
});

// ── Validation boundaries + callable ordering ──

test("boundary validation rejects invalid requests before database access", async (t) => {
  const cases = [
    ["21 spawns", rawRequest({ spawns: Array.from({ length: 21 }, () => ({ taskId: "FORWARD_MAIL" })) })],
    ["201 answer keys", rawRequest({ answers: Object.fromEntries(Array.from({ length: 201 }, (_, index) => [`k${index}`, index])) })],
    ["answers deeper than four containers", rawRequest({ answers: { a: { b: { c: { d: { e: true } } } } } })],
    ["token containing slash", rawRequest({ token: "bad/token" })],
    ["257-byte token", rawRequest({ token: "t".repeat(257) })],
    ["dot token", rawRequest({ token: "." })],
    ["dot-dot token", rawRequest({ token: ".." })],
    ["reserved token", rawRequest({ token: "__x__" })],
    ["invalid catalog taskId", rawRequest({ spawns: [{ taskId: "BAD/ID" }] })],
    ["257-byte source id", rawRequest({ source: { kind: "conversation", id: "s".repeat(257) } })],
    ["513-byte institution", rawRequest({ spawns: [{ taskId: "FORWARD_MAIL", titleParams: { institution: "i".repeat(513) } }] })],
    ["canonical request larger than 48KB", rawRequest({ answers: { blob: "x".repeat(49 * 1024) } })]
  ];

  for (const [name, data] of cases) {
    await t.test(name, () => assertCallableRejectsBeforeDb(data, "invalid-argument"));
  }
});

test("UTF-8 byte boundaries are enforced for request strings", async () => {
  const valid = validateRequest(rawRequest({
    token: "é".repeat(128),
    source: { kind: "conversation", id: "é".repeat(128) },
    spawns: [{ taskId: "FORWARD_MAIL", titleParams: { institution: "é".repeat(256) } }]
  }));
  assert.equal(Buffer.byteLength(valid.token, "utf8"), 256);
  assert.equal(Buffer.byteLength(valid.source.id, "utf8"), 256);
  assert.equal(Buffer.byteLength(valid.spawns[0].titleParams.institution, "utf8"), 512);

  await assertCallableRejectsBeforeDb(rawRequest({ token: "é".repeat(129) }), "invalid-argument");
  await assertCallableRejectsBeforeDb(rawRequest({
    source: { kind: "conversation", id: "é".repeat(129) }
  }), "invalid-argument");
  await assertCallableRejectsBeforeDb(rawRequest({
    spawns: [{ taskId: "FORWARD_MAIL", titleParams: { institution: "é".repeat(257) } }]
  }), "invalid-argument");
});

test("expectedUserId mismatch fails before database access", async () => {
  await assertCallableRejectsBeforeDb(
    rawRequest({ expectedUserId: "somebody-else" }),
    "failed-precondition"
  );
});

test("omitted and matching expectedUserId execute normally", async () => {
  for (const data of [rawRequest(), rawRequest({ token: "matching-token", expectedUserId: "u1" })]) {
    const db = fakeDb({ catalog: { FORWARD_MAIL: catalogRow() } });
    let dbFactoryCalls = 0;
    const result = await handleSpawnRequest(
      { auth: { uid: "u1" }, data },
      () => {
        dbFactoryCalls += 1;
        return db;
      },
      NOW
    );
    assert.equal(dbFactoryCalls, 1);
    assert.equal(result.created.length, 1);
    assert.equal(db.state.commits, 1);
  }
});

test("expectedUserId is excluded from the request fingerprint and replay intent", async () => {
  const withoutExpected = request({ answers: { nested: { b: 2, a: 1 } } });
  const withExpected = validateRequest(rawRequest({
    expectedUserId: "u1",
    answers: { nested: { a: 1, b: 2 } }
  }));
  assert.equal(requestFingerprint(withoutExpected), requestFingerprint(withExpected));

  const stored = { created: [{ id: "stored" }] };
  const db = fakeDb({
    tokenDoc: { result: stored, fingerprint: requestFingerprint(withoutExpected), at: "earlier" }
  });
  const replay = await executeSpawn(db, "u1", withExpected, NOW);
  assert.deepEqual(replay, stored);
  assert.equal(db.state.commitAttempts, 0);
  assert.equal(db.writes.length, 0);
});

test("expectedUserId type and UTF-8 limits validate before database access", async () => {
  await assertCallableRejectsBeforeDb(rawRequest({ expectedUserId: 123 }), "invalid-argument");
  await assertCallableRejectsBeforeDb(rawRequest({ expectedUserId: "u".repeat(129) }), "invalid-argument");
  await assertCallableRejectsBeforeDb(rawRequest({ expectedUserId: "é".repeat(65) }), "invalid-argument");

  const exactBoundary = "é".repeat(64);
  const db = fakeDb({ catalog: { FORWARD_MAIL: catalogRow() } });
  const result = await handleSpawnRequest(
    { auth: { uid: exactBoundary }, data: rawRequest({ token: "multibyte-user", expectedUserId: exactBoundary }) },
    () => db,
    NOW
  );
  assert.equal(result.created.length, 1);
});

// ── Canonicalization ──

test("request fingerprint recursively canonicalizes answer keys", () => {
  const first = validateRequest(rawRequest({
    answers: { z: 3, nested: { second: 2, first: 1 }, list: [{ b: 2, a: 1 }] }
  }));
  const reordered = validateRequest(rawRequest({
    answers: { list: [{ a: 1, b: 2 }], nested: { first: 1, second: 2 }, z: 3 }
  }));
  const changed = validateRequest(rawRequest({
    answers: { z: 4, nested: { second: 2, first: 1 }, list: [{ b: 2, a: 1 }] }
  }));

  assert.equal(
    canonicalJSON({ b: 2, a: { d: 4, c: 3 } }),
    '{"a":{"c":3,"d":4},"b":2}'
  );
  assert.match(requestFingerprint(first), /^f1_[0-9a-f]{64}$/);
  assert.equal(requestFingerprint(first), requestFingerprint(reordered));
  assert.notEqual(requestFingerprint(first), requestFingerprint(changed));
});

test("deterministic task IDs use the token and zero-based ordinal", () => {
  assert.equal(deterministicTaskId("task-1-spawn", 0), expectedTaskDocId("task-1-spawn", 0));
  assert.equal(deterministicTaskId("task-1-spawn", 1), expectedTaskDocId("task-1-spawn", 1));
  assert.match(deterministicTaskId("task-1-spawn", 0), /^t1_[0-9a-f]{40}$/);
});
