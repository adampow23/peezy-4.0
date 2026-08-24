"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const admin = require("firebase-admin");

const AUTH_UID = "auth-user";
const FORGED_UID = "victim-user";
const SERVER_TIMESTAMP = "SERVER_TIMESTAMP";

let activeDb;
let firestoreCalls = 0;

function firestore() {
  firestoreCalls += 1;
  return activeDb;
}
firestore.FieldValue = {
  serverTimestamp: () => SERVER_TIMESTAMP
};

// Install the in-memory Firestore boundary before loading the callable exports.
// Calling their `.run` handlers then exercises production auth/write logic without
// starting an emulator or contacting Firebase.
Object.defineProperty(admin, "firestore", {
  configurable: true,
  value: firestore
});

const {
  requestConcierge,
  submitTaskFlow,
  submitWorkflowAnswers
} = require("../index");

function makeFakeDb() {
  const writes = [];
  let autoId = 0;

  function document(path) {
    return {
      path,
      collection(name) {
        return collection(`${path}/${name}`);
      },
      async set(data, options) {
        writes.push({ operation: "set", path, data, options });
      },
      async update(data) {
        writes.push({ operation: "update", path, data });
      }
    };
  }

  function collection(path) {
    return {
      doc(id) {
        return document(`${path}/${id}`);
      },
      async add(data) {
        const reference = document(`${path}/auto-${++autoId}`);
        writes.push({ operation: "add", path: reference.path, data });
        return reference;
      }
    };
  }

  return {
    writes,
    collection,
    batch() {
      const pending = [];
      return {
        set(reference, data, options) {
          pending.push({ operation: "batch-set", path: reference.path, data, options });
        },
        async commit() {
          writes.push(...pending);
        }
      };
    }
  };
}

function useFreshDb() {
  activeDb = makeFakeDb();
  firestoreCalls = 0;
  return activeDb;
}

function authenticatedRequest(data) {
  return { auth: { uid: AUTH_UID }, data };
}

function assertAuthenticatedUserScope(writes) {
  const userPaths = writes
    .map((write) => write.path)
    .filter((path) => path.startsWith("users/"));

  assert.ok(userPaths.length > 0);
  assert.ok(userPaths.every((path) => path.startsWith(`users/${AUTH_UID}/`)));
  assert.ok(userPaths.every((path) => !path.startsWith(`users/${FORGED_UID}/`)));

  for (const write of writes.filter((candidate) => candidate.path.startsWith("workflowSubmissions/"))) {
    assert.equal(write.data.userId, AUTH_UID);
  }
}

test("all three callables reject unauthenticated requests before Firestore writes", async () => {
  const cases = [
    {
      callable: requestConcierge,
      data: { taskId: "BOX_RETURN", userId: FORGED_UID }
    },
    {
      callable: submitTaskFlow,
      data: { taskId: "COMPARE_QUOTES", confirmedFields: {}, userId: FORGED_UID }
    },
    {
      callable: submitWorkflowAnswers,
      data: { workflowId: "book_movers", answers: {}, userId: FORGED_UID }
    }
  ];

  for (const { callable, data } of cases) {
    const db = useFreshDb();
    await assert.rejects(
      () => callable.run({ data }),
      (error) => error.code === "unauthenticated"
    );
    assert.equal(firestoreCalls, 0);
    assert.deepEqual(db.writes, []);
  }
});

test("concierge and task-flow submissions store only the authenticated uid", async () => {
  let db = useFreshDb();
  await requestConcierge.run(authenticatedRequest({
    taskId: "BOX_RETURN",
    taskTitle: "Return boxes",
    userId: FORGED_UID
  }));
  assert.equal(db.writes.length, 1);
  assert.equal(db.writes[0].path, "conciergeRequests/auto-1");
  assert.equal(db.writes[0].data.userId, AUTH_UID);

  db = useFreshDb();
  await submitTaskFlow.run(authenticatedRequest({
    taskId: "COMPARE_QUOTES",
    taskTitle: "Compare quotes",
    confirmedFields: { choice: "first" },
    userId: FORGED_UID
  }));
  assert.equal(db.writes.length, 1);
  assert.equal(db.writes[0].path, "taskFlowSubmissions/auto-1");
  assert.equal(db.writes[0].data.userId, AUTH_UID);
});

test("every submitWorkflowAnswers branch scopes all writes to the authenticated uid", async () => {
  const cases = [
    {
      data: {
        workflowId: "arrange_parking_new",
        answers: {},
        userId: FORGED_UID
      },
      paths: [
        `users/${AUTH_UID}/workflowResponses/arrange_parking_new`,
        `users/${AUTH_UID}/tasks/arrange_parking_new`
      ]
    },
    {
      data: {
        workflowId: "address_change_financial",
        answers: [{ id: "bank", displayName: "Bank" }],
        userId: FORGED_UID
      },
      paths: [
        `users/${AUTH_UID}/mini_assessments/address_change_financial`,
        `users/${AUTH_UID}/tasks/address_change_financial_bank`
      ]
    },
    {
      data: {
        workflowId: "book_movers",
        answers: { priority: ["high_quality"] },
        userId: FORGED_UID
      },
      paths: [
        "workflowSubmissions/auto-1",
        `users/${AUTH_UID}/workflowResponses/book_movers`,
        `users/${AUTH_UID}/tasks/book_movers`
      ]
    }
  ];

  for (const { data, paths } of cases) {
    const db = useFreshDb();
    await submitWorkflowAnswers.run(authenticatedRequest(data));

    assert.deepEqual(
      db.writes.map((write) => write.path).sort(),
      paths.sort()
    );
    assertAuthenticatedUserScope(db.writes);
  }
});

test("submitWorkflowAnswers accepts an authenticated payload without userId", async () => {
  const db = useFreshDb();

  await submitWorkflowAnswers.run(authenticatedRequest({
    workflowId: "book_movers",
    answers: { priority: ["low_cost"] }
  }));

  assertAuthenticatedUserScope(db.writes);
  const submission = db.writes.find((write) => write.path.startsWith("workflowSubmissions/"));
  assert.equal(submission.data.userId, AUTH_UID);
});
