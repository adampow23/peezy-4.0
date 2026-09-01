"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  executeWorkflowAnswers,
  workflowSubmissionFingerprint,
  workflowSubmissionId
} = require("../getWorkflowQualifying");
const { buildUserActionContract, validateDispositionContract } = require("../dispositionContract");

const NOW = new Date("2026-08-27T12:00:00.000Z");
const STAMP = { __serverTimestamp: true };

function trigger() {
  return {
    kind: "date",
    at: new Date("2026-09-10T12:00:00.000Z"),
    payload: { basis: "institution_promised_date", source_evidence_id: "evidence-1" },
    fired: false
  };
}

function fakeDb(initial = {}, { commitBarrierCount = 0 } = {}) {
  const docs = new Map(Object.entries(initial));
  const writes = [];
  let auto = 0;
  let barrierArrivals = 0;
  let releaseBarrier;
  const commitBarrier = commitBarrierCount > 0
    ? new Promise((resolve) => { releaseBarrier = resolve; })
    : null;
  const snapshot = (path) => {
    const data = docs.get(path);
    return {
      exists: data !== undefined,
      data: () => data,
      get: (field) => data?.[field]
    };
  };
  const collection = (path) => ({
    doc(...args) {
      if (args.length === 1 && args[0] === undefined) {
        throw new TypeError("Admin SDK doc() rejects an explicit undefined path");
      }
      const docId = args.length === 0 ? `auto-${++auto}` : args[0];
      const docPath = `${path}/${docId}`;
      return {
        id: docId,
        path: docPath,
        collection: (name) => collection(`${docPath}/${name}`)
      };
    }
  });
  return {
    docs,
    writes,
    collection,
    async runTransaction(callback) {
      async function attempt(number) {
        const ops = [];
        const transaction = {
          get: async (ref) => snapshot(ref.path),
          create: (ref, data) => ops.push({ type: "create", path: ref.path, data }),
          set: (ref, data, options) => ops.push({ type: "set", path: ref.path, data, options }),
          update: (ref, data) => ops.push({ type: "update", path: ref.path, data })
        };
        const result = await callback(transaction);
        if (commitBarrier && number === 0) {
          barrierArrivals += 1;
          if (barrierArrivals === commitBarrierCount) releaseBarrier();
          await commitBarrier;
        }
        try {
          for (const op of ops) {
            if (op.type === "create" && docs.has(op.path)) {
              const error = new Error("already exists");
              error.code = 6;
              throw error;
            }
            if (op.type === "update" && !docs.has(op.path)) throw new Error("not found");
          }
        } catch (error) {
          if (error.code === 6 && number === 0) return attempt(1);
          throw error;
        }
        for (const op of ops) {
          const prior = docs.get(op.path) || {};
          docs.set(op.path, op.type === "update" || op.options?.merge
            ? { ...prior, ...op.data }
            : op.data);
        }
        writes.push(...ops);
        return result;
      }
      return attempt(0);
    }
  };
}

test("workflow task mutations use the exported reset-aware transaction seam", async () => {
  assert.equal(typeof executeWorkflowAnswers, "function");
});

test("contractless guidance preserves the legacy response and task bytes", async () => {
  const db = fakeDb({
    "users/u1/tasks/cancel_utilities": { id: "cancel_utilities", status: "Upcoming", keep: true }
  });
  const result = await executeWorkflowAnswers(
    db, "u1", "cancel_utilities", {}, NOW, () => STAMP
  );
  assert.deepEqual(result, { success: true, status: "completed" });
  assert.deepEqual(db.docs.get("users/u1/workflowResponses/cancel_utilities"), {
    workflowId: "cancel_utilities",
    answers: {},
    workflowType: "guidance",
    completedAt: STAMP
  });
  assert.deepEqual(db.docs.get("users/u1/tasks/cancel_utilities"), {
    id: "cancel_utilities",
    status: "Completed",
    keep: true,
    completedAt: STAMP,
    qualifyingAnswers: {}
  });
});

test("contracted guidance completes coherently and removes stale nonterminal keys", async () => {
  const contract = buildUserActionContract({}, {
    owner: "user:u1",
    nextAction: "Review guidance",
    nextTrigger: trigger(),
    resumeDestination: "guidance/cancel_utilities",
    visibleStatusCopy: "Review guidance"
  }, NOW);
  const db = fakeDb({
    "users/u1/tasks/cancel_utilities": { status: "InProgress", dispositionContract: contract }
  });
  await executeWorkflowAnswers(db, "u1", "cancel_utilities", {}, NOW, () => STAMP);
  const task = db.docs.get("users/u1/tasks/cancel_utilities");
  assert.equal(task.status, "Completed");
  assert.deepEqual(task.dispositionContract, {
    disposition: "COMPLETED",
    visible_status_copy: "Guidance complete"
  });
  assert.equal(validateDispositionContract(task.status, task.dispositionContract, NOW), true);
});

test("active reset and contracted mini-assessment collision fail with zero writes", async () => {
  const resetDb = fakeDb({ "users/u1": { taskReset: { state: "deleting" } } });
  await assert.rejects(
    executeWorkflowAnswers(resetDb, "u1", "cancel_utilities", {}, NOW, () => STAMP),
    (error) => error.code === "failed-precondition"
  );
  assert.equal(resetDb.writes.length, 0);

  const taskPath = "users/u1/tasks/address_change_financial_bank";
  const collisionDb = fakeDb({
    [taskPath]: {
      status: "InProgress",
      dispositionContract: buildUserActionContract({}, {
        owner: "user:u1",
        nextAction: "Keep",
        nextTrigger: trigger(),
        resumeDestination: "keep",
        visibleStatusCopy: "Keep"
      }, NOW)
    }
  });
  await assert.rejects(
    executeWorkflowAnswers(collisionDb, "u1", "address_change_financial", [
      { id: "bank", displayName: "Bank" }
    ], NOW, () => STAMP),
    (error) => error.code === "failed-precondition"
  );
  assert.equal(collisionDb.writes.length, 0);
});

test("contracted vendor requires explicit future evidence and emits full waiting map", async () => {
  const db = fakeDb({
    "users/u1/tasks/book_movers": {
      status: "InProgress",
      dispositionContract: buildUserActionContract({}, {
        owner: "user:u1",
        nextAction: "Choose mover",
        nextTrigger: trigger(),
        resumeDestination: "movers/choose",
        visibleStatusCopy: "Choose mover",
        externalSubmission: true
      }, NOW)
    }
  });
  await assert.rejects(
    executeWorkflowAnswers(db, "u1", "book_movers", { quote: ["a"] }, NOW, () => STAMP),
    (error) => error.code === "failed-precondition"
  );
  assert.equal(db.writes.length, 0);

  const answers = {
    quote: ["a"],
    waiting_owner: "Mover Co",
    waiting_next_action: "Wait for quote",
    waiting_resume_destination: "movers/quote",
    waiting_next_trigger: trigger()
  };
  const result = await executeWorkflowAnswers(db, "u1", "book_movers", answers, NOW, () => STAMP);
  assert.deepEqual(result, { success: true, status: "matching_in_progress" });
  const task = db.docs.get("users/u1/tasks/book_movers");
  assert.equal(task.status, "matching_in_progress");
  assert.equal(task.dispositionContract.owner, "Mover Co");
  assert.equal(task.dispositionContract.external_submission, true);
  assert.equal(validateDispositionContract(task.status, task.dispositionContract, NOW), true);
});

test("contracted vendor rejects raw cross-kind trigger fields before any write", async () => {
  const db = fakeDb({
    "users/u1/tasks/book_movers": {
      status: "InProgress",
      dispositionContract: buildUserActionContract({}, {
        owner: "user:u1",
        nextAction: "Choose mover",
        nextTrigger: trigger(),
        resumeDestination: "movers/choose",
        visibleStatusCopy: "Choose mover"
      }, NOW)
    }
  });
  await assert.rejects(
    executeWorkflowAnswers(db, "u1", "book_movers", {
      waiting_owner: "Mover Co",
      waiting_next_action: "Wait for quote",
      waiting_resume_destination: "movers/quote",
      waiting_next_trigger: {
        ...trigger(),
        event_name: "wrong-kind",
        fired: "false"
      }
    }, NOW, () => STAMP),
    (error) => error.code === "failed-precondition" && /stale|boolean/i.test(error.message)
  );
  assert.equal(db.writes.length, 0);
});

test("legacy vendor omission uses the zero-argument random document API", async () => {
  const db = fakeDb();
  const result = await executeWorkflowAnswers(
    db, "u1", "book_movers", { priority: ["low_cost"] }, NOW, () => STAMP
  );

  assert.deepEqual(result, { success: true, status: "matching_in_progress" });
  assert.equal(db.docs.has("workflowSubmissions/auto-1"), true);
  assert.equal(
    [...db.docs.keys()].filter((path) => path.startsWith("workflowSubmissions/")).length,
    1
  );
});

test("vendor submission token replays the exact stored result without duplicate writes", async () => {
  const db = fakeDb();
  const answers = { priority: ["high_quality"], details: { b: 2, a: 1 } };
  const token = "stable-view-submission";
  const first = await executeWorkflowAnswers(
    db, "u1", "book_movers", answers, NOW, () => STAMP, token
  );
  const writesAfterFirst = db.writes.length;
  const second = await executeWorkflowAnswers(
    db, "u1", "book_movers", answers, NOW, () => ({ later: true }), token
  );

  assert.deepEqual(second, first);
  assert.equal(db.writes.length, writesAfterFirst);
  const submissionPath = `workflowSubmissions/${workflowSubmissionId("u1", token)}`;
  assert.deepEqual(db.docs.get(submissionPath), {
    workflowId: "book_movers",
    userId: "u1",
    owner: "u1",
    submissionToken: token,
    answers,
    submittedAt: STAMP,
    status: "pending_matching",
    fingerprint: workflowSubmissionFingerprint("book_movers", answers),
    result: first
  });
  assert.equal(
    db.writes.filter((write) => write.path === submissionPath).length,
    1
  );
});

test("stable token survives a recreated caller with canonically equivalent answers", async () => {
  const db = fakeDb();
  const token = "recreated-flow-token";
  const first = await executeWorkflowAnswers(
    db,
    "u1",
    "book_movers",
    { details: { one: 1, two: 2 }, priority: ["low_cost"] },
    NOW,
    () => STAMP,
    token
  );
  const writesAfterFirst = db.writes.length;

  // A newly-created view/caller rebuilds its dictionaries but retains its token.
  const recreatedResult = await executeWorkflowAnswers(
    db,
    "u1",
    "book_movers",
    { priority: ["low_cost"], details: { two: 2, one: 1 } },
    new Date("2026-08-28T12:00:00.000Z"),
    () => ({ recreated: true }),
    token
  );

  assert.deepEqual(recreatedResult, first);
  assert.equal(db.writes.length, writesAfterFirst);
});

test("concurrent vendor submissions converge through the deterministic token document", async () => {
  const db = fakeDb({}, { commitBarrierCount: 2 });
  const token = "concurrent-submission";
  const answers = { priority: ["fast_timeline"] };
  const [first, second] = await Promise.all([
    executeWorkflowAnswers(db, "u1", "book_movers", answers, NOW, () => STAMP, token),
    executeWorkflowAnswers(db, "u1", "book_movers", answers, NOW, () => STAMP, token)
  ]);
  const submissionPath = `workflowSubmissions/${workflowSubmissionId("u1", token)}`;

  assert.deepEqual(second, first);
  assert.deepEqual(db.docs.get(submissionPath).result, first);
  assert.equal(
    db.writes.filter((write) => write.path === submissionPath).length,
    1
  );
  assert.equal(
    db.writes.filter((write) => write.path === "users/u1/workflowResponses/book_movers").length,
    1
  );
});

test("reusing a vendor submission token for payload drift fails with zero writes", async () => {
  const db = fakeDb();
  const token = "drift-protected-token";
  await executeWorkflowAnswers(
    db, "u1", "book_movers", { priority: ["low_cost"] }, NOW, () => STAMP, token
  );
  const writesAfterFirst = db.writes.length;

  await assert.rejects(
    executeWorkflowAnswers(
      db, "u1", "book_movers", { priority: ["high_quality"] }, NOW, () => STAMP, token
    ),
    (error) => error.code === "failed-precondition"
  );
  assert.equal(db.writes.length, writesAfterFirst);
});
