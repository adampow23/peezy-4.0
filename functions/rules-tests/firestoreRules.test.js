"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment
} = require("@firebase/rules-unit-testing");
const {
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  setDoc,
  updateDoc
} = require("firebase/firestore");

const PROJECT_ID = "demo-peezy-phase1";
const OWNER = "owner-uid";
const OTHER = "other-uid";
const rules = fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8");

let environment;

test.before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || "", /^(127\.0\.0\.1|localhost):\d+$/);
  environment = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules }
  });
});

test.after(async () => {
  await environment?.cleanup();
});

test.beforeEach(async () => {
  await environment.clearFirestore();
  await seed({
    [`users/${OWNER}`]: { name: "Owner" },
    [`users/${OTHER}`]: { name: "Other" }
  });
});

function dbFor(uid) {
  return environment.authenticatedContext(uid).firestore();
}

function anonymousDb() {
  return environment.unauthenticatedContext().firestore();
}

async function seed(documents) {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [documentPath, data] of Object.entries(documents)) {
      await setDoc(doc(db, documentPath), data);
    }
  });
}

async function assertOwnerOnlyRead(documentPath) {
  await assertSucceeds(getDoc(doc(dbFor(OWNER), documentPath)));
  await assertFails(getDoc(doc(dbFor(OTHER), documentPath)));
  await assertFails(getDoc(doc(anonymousDb(), documentPath)));
}

async function assertClientWriteDenied(documentPath, createData = { value: 1 }) {
  const owner = dbFor(OWNER);
  await assertFails(setDoc(doc(owner, documentPath), createData));
  await seed({ [documentPath]: createData });
  await assertFails(updateDoc(doc(owner, documentPath), { value: 2 }));
  await assertFails(deleteDoc(doc(owner, documentPath)));
}

test("ordinary audit-free contractless tasks retain owner lifecycle writes", async () => {
  const owner = dbFor(OWNER);
  const task = doc(owner, `users/${OWNER}/tasks/TASK_1`);
  await assertSucceeds(setDoc(task, {
    id: "TASK_1",
    userId: OWNER,
    taskId: "TASK_1",
    status: "Upcoming",
    flowRows: [{ id: "row-1", subjectId: "subject-1" }]
  }));
  await assertSucceeds(updateDoc(task, { status: "InProgress" }));
  await assertSucceeds(updateDoc(task, {
    flowAnswers: { provider: ["Provider"] },
    flowAnswerIdentities: { provider: { id: "provider-1", label: "Provider", source: "manual" } }
  }));
  await assertFails(updateDoc(task, { flowRows: [{ id: "changed" }] }));
  await assertSucceeds(deleteDoc(task));
});

test("reserved creates and server-authored create fields are denied", async () => {
  const owner = dbFor(OWNER);
  for (const taskId of ["t1_claim", "t2_claim", "a2_claim"]) {
    await assertFails(setDoc(doc(owner, `users/${OWNER}/tasks/${taskId}`), {
      id: taskId,
      userId: OWNER,
      taskId: "TASK_1",
      status: "Upcoming"
    }));
  }
  for (const [field, value] of Object.entries({
    spawnedFrom: "token",
    subject: { kind: "service", id: "s1" },
    institutionId: "i1",
    institution: "Provider",
    canonicalKeyVersion: 2,
    supersedes: "old",
    planChangeRevision: 1,
    planChangeState: "retired",
    planChangeHistory: [],
    pendingAmendmentTaskId: "a2_x",
    confirmationOriginalFingerprint: "fingerprint",
    dispositionContract: { disposition: "COMPLETED" }
  })) {
    await assertFails(setDoc(doc(owner, `users/${OWNER}/tasks/NORMAL_${field}`), {
      id: `NORMAL_${field}`,
      userId: OWNER,
      taskId: "TASK_1",
      status: "Upcoming",
      [field]: value
    }));
  }
});

test("contracted task is wholly client immutable", async () => {
  const documentPath = `users/${OWNER}/tasks/CONTRACTED`;
  await seed({
    [documentPath]: {
      id: "CONTRACTED",
      userId: OWNER,
      taskId: "CONTRACTED",
      status: "Snoozed",
      snoozedUntil: new Date("2026-09-01T00:00:00Z"),
      dispositionContract: {
        disposition: "DEFERRED",
        owner: `user:${OWNER}`,
        next_action: "Continue",
        next_trigger: { kind: "date", at: new Date("2026-09-01T00:00:00Z") },
        resume_destination: "flow",
        visible_status_copy: "Deferred"
      }
    }
  });
  const ref = doc(dbFor(OWNER), documentPath);
  for (const mutation of [
    { status: "Completed" },
    { status: "Upcoming" },
    { snoozedUntil: new Date("2026-09-02T00:00:00Z") },
    { dispositionContract: { disposition: "COMPLETED" } },
    { planChangeHistory: [] },
    { subject: { kind: "service", id: "other" } },
    { canonicalKeyVersion: 2 },
    { supersedes: "old" },
    { spawnedFrom: "token" },
    { flowAnswers: { provider: ["Changed"] } }
  ]) {
    await assertFails(updateDoc(ref, mutation));
  }
  await assertFails(deleteDoc(ref));
});

test("retained audit state prevents ordinary and reserved task deletion", async () => {
  const documents = {
    [`users/${OWNER}/tasks/REOPENED`]: {
      id: "REOPENED", userId: OWNER, taskId: "REOPENED", status: "Upcoming",
      planChangeRevision: 1, planChangeState: "reopened", planChangeHistory: [{ action: "reopen" }]
    },
    [`users/${OWNER}/tasks/t2_reopened`]: {
      id: "t2_reopened", userId: OWNER, taskId: "REOPENED", status: "Upcoming",
      spawnedFrom: "token", subject: { kind: "service", id: "s1" },
      institutionId: "i1", institution: "Provider", canonicalKeyVersion: 2,
      planChangeRevision: 1, planChangeState: "reopened", planChangeHistory: [{ action: "reopen" }]
    }
  };
  await seed(documents);
  for (const documentPath of Object.keys(documents)) {
    const ref = doc(dbFor(OWNER), documentPath);
    await assertFails(updateDoc(ref, { status: "InProgress" }));
    await assertFails(deleteDoc(ref));
  }
});

test("untouched server-created t1 and t2 keep only frozen-provenance legacy lifecycle", async () => {
  const documents = {
    [`users/${OWNER}/tasks/t1_existing`]: {
      id: "t1_existing", userId: OWNER, taskId: "TASK_1", spawnedFrom: "token", status: "Upcoming"
    },
    [`users/${OWNER}/tasks/t2_existing`]: {
      id: "t2_existing", userId: OWNER, taskId: "TASK_1", spawnedFrom: "token", status: "Upcoming",
      subject: { kind: "service", id: "s1" }, institutionId: "i1",
      institution: "Provider", canonicalKeyVersion: 2
    }
  };
  await seed(documents);
  for (const documentPath of Object.keys(documents)) {
    const ref = doc(dbFor(OWNER), documentPath);
    await assertSucceeds(updateDoc(ref, { status: "Snoozed", snoozedUntil: new Date("2026-09-01T00:00:00Z") }));
    await assertFails(updateDoc(ref, { taskId: "OTHER" }));
    await assertFails(updateDoc(ref, { spawnedFrom: "different" }));
    await assertSucceeds(deleteDoc(ref));
  }
});

test("a2 task IDs are unconditionally client immutable even if malformed and contractless", async () => {
  const documentPath = `users/${OWNER}/tasks/a2_malformed`;
  await seed({
    [documentPath]: {
      id: "a2_malformed",
      userId: OWNER,
      taskId: "AMENDMENT",
      status: "Upcoming"
    }
  });
  const ref = doc(dbFor(OWNER), documentPath);
  await assertFails(updateDoc(ref, { status: "Completed" }));
  await assertFails(updateDoc(ref, { snoozedUntil: new Date("2026-09-01T00:00:00Z") }));
  await assertFails(deleteDoc(ref));
});

test("active reset blocks every client task create update and delete", async () => {
  for (const state of ["deleting", "awaiting_local_reset"]) {
    await environment.clearFirestore();
    await seed({
      [`users/${OWNER}`]: { name: "Owner", taskReset: { state, operationId: "op-1" } },
      [`users/${OWNER}/tasks/EXISTING`]: { id: "EXISTING", userId: OWNER, taskId: "EXISTING", status: "Upcoming" }
    });
    const owner = dbFor(OWNER);
    await assertFails(setDoc(doc(owner, `users/${OWNER}/tasks/NEW`), { status: "Upcoming" }));
    await assertFails(updateDoc(doc(owner, `users/${OWNER}/tasks/EXISTING`), { status: "Completed" }));
    await assertFails(deleteDoc(doc(owner, `users/${OWNER}/tasks/EXISTING`)));
  }
});

test("server-owned per-user lifecycle collections are owner-readable and client-write-false", async () => {
  const paths = [
    `users/${OWNER}/spawnTokens/token-1`,
    `users/${OWNER}/events/event-1`,
    `users/${OWNER}/eventState/state-1`,
    `users/${OWNER}/taskPlanOperations/op-1`
  ];
  for (const documentPath of paths) {
    await assertClientWriteDenied(documentPath);
    await assertOwnerOnlyRead(documentPath);
  }
});

test("phase1 system state is inaccessible to all client contexts", async () => {
  await seed({ "phase1System/dispositionTriggerState": { eventTaskAfterPath: "x" } });
  for (const db of [dbFor(OWNER), dbFor(OTHER), anonymousDb()]) {
    const ref = doc(db, "phase1System/dispositionTriggerState");
    await assertFails(getDoc(ref));
    await assertFails(setDoc(ref, { changed: true }));
    await assertFails(deleteDoc(ref));
  }
});

test("root profile stays writable while subscription and taskReset are server-owned", async () => {
  const owner = dbFor(OWNER);
  const root = doc(owner, `users/${OWNER}`);
  await assertSucceeds(updateDoc(root, { name: "Updated" }));
  await assertFails(updateDoc(root, { subscription: { active: true } }));
  await assertFails(updateDoc(root, { taskReset: { state: "deleting" } }));

  await seed({ [`users/${OWNER}`]: { name: "Owner", subscription: { active: true }, taskReset: { state: "deleting" } } });
  await assertFails(updateDoc(root, { subscription: deleteField() }));
  await assertFails(updateDoc(root, { taskReset: deleteField() }));

  const fresh = doc(environment.authenticatedContext("fresh-owner").firestore(), "users/fresh-owner");
  await assertSucceeds(setDoc(fresh, { name: "Fresh" }));
  await assertFails(setDoc(doc(environment.authenticatedContext("fresh-sub").firestore(), "users/fresh-sub"), {
    subscription: { active: true }
  }));
  await assertFails(setDoc(doc(environment.authenticatedContext("fresh-reset").firestore(), "users/fresh-reset"), {
    taskReset: { state: "deleting" }
  }));
});

test("inventoried client-write collections retain owner CRUD", async () => {
  const collections = [
    "user_assessments", "fcmTokens", "packingPlan", "readiness",
    "inventorySessions", "inventory", "identity"
  ];
  for (const collection of collections) {
    const ref = doc(dbFor(OWNER), `users/${OWNER}/${collection}/row-1`);
    // S1: user_assessments creates carry the effective root epoch stamp (0 here).
    const create = collection === "user_assessments" ? { value: 1, task_generation_epoch: 0 } : { value: 1 };
    await assertSucceeds(setDoc(ref, create));
    await assertSucceeds(updateDoc(ref, { value: 2 }));
    await assertSucceeds(deleteDoc(ref));
  }
  const knowledge = doc(dbFor(OWNER), `userKnowledge/${OWNER}`);
  await assertSucceeds(setDoc(knowledge, { moveDate: "2026-10-01", task_generation_epoch: 0 }));
  await assertSucceeds(updateDoc(knowledge, { moveDate: "2026-10-02" }));
  await assertFails(getDoc(doc(dbFor(OTHER), `userKnowledge/${OWNER}`)));
  await assertFails(getDoc(doc(anonymousDb(), `userKnowledge/${OWNER}`)));
  await assertSucceeds(deleteDoc(knowledge));
});

test("support chat and move answers retain narrow current semantics", async () => {
  const owner = dbFor(OWNER);
  const userMessage = doc(owner, `users/${OWNER}/supportChat/user-message`);
  await assertSucceeds(setDoc(userMessage, { sender: "user", text: "Help" }));
  await assertFails(updateDoc(userMessage, { text: "Changed" }));
  await assertFails(deleteDoc(userMessage));

  await seed({
    [`users/${OWNER}/supportChat/support-message`]: { sender: "support", text: "Reply", read: false },
    [`users/${OWNER}/supportChat/_meta`]: { unread: 1 },
    [`users/${OWNER}/moveAnswers/answers`]: { provider: "Provider" }
  });
  const reply = doc(owner, `users/${OWNER}/supportChat/support-message`);
  await assertSucceeds(getDoc(reply));
  await assertSucceeds(updateDoc(reply, { read: true }));
  await assertFails(updateDoc(reply, { text: "Changed" }));
  await assertFails(setDoc(doc(owner, `users/${OWNER}/supportChat/_meta`), { unread: 0 }));
  await assertOwnerOnlyRead(`users/${OWNER}/moveAnswers/answers`);
  await assertFails(updateDoc(doc(owner, `users/${OWNER}/moveAnswers/answers`), { provider: "Other" }));
});

test("server-owned result surfaces remain owner-readable and client-write-false", async () => {
  const paths = [
    `users/${OWNER}/packingAggregate/current`,
    `users/${OWNER}/research/result-1`,
    `users/${OWNER}/workflowResponses/workflow-1`,
    `users/${OWNER}/chats/chat-1/messages/message-1`
  ];
  for (const documentPath of paths) {
    await assertClientWriteDenied(documentPath);
    await assertOwnerOnlyRead(documentPath);
  }
});

test("other users and unauthenticated clients are denied across user paths", async () => {
  const paths = [
    `users/${OWNER}`,
    `users/${OWNER}/tasks/TASK_1`,
    `users/${OWNER}/fcmTokens/token-1`,
    `users/${OWNER}/inventory/item-1`,
    `users/${OWNER}/supportChat/message-1`,
    `users/${OWNER}/spawnTokens/token-1`
  ];
  await seed(Object.fromEntries(paths.map((documentPath) => [documentPath, { sender: "support", value: 1 }])));
  for (const db of [dbFor(OTHER), anonymousDb()]) {
    for (const documentPath of paths) {
      const ref = doc(db, documentPath);
      await assertFails(getDoc(ref));
      await assertFails(setDoc(ref, { sender: "user", value: 2 }));
      await assertFails(deleteDoc(ref));
    }
  }
  assert.ok(true);
});

// ---------------------------------------------------------------------------
// S1 first pass (briefs/S1_BRIEF.md; manifest §5:540-546, 549-551): epoch stamps
// on user_assessments, userKnowledge, and root dailyDose (create/update only).
// Cleanup and deletion semantics belong to S3, which also integrates the
// account-deletion/system/query boundaries and performs the final full-file review.
// ---------------------------------------------------------------------------

test("assessment creates must carry the effective root epoch stamp", async () => {
  const owner = dbFor(OWNER);
  await assertSucceeds(setDoc(doc(owner, `users/${OWNER}/user_assessments/a1`), { task_generation_epoch: 0, name: "x" }));
  await assertFails(setDoc(doc(owner, `users/${OWNER}/user_assessments/a2`), { name: "x" }));
  await assertFails(setDoc(doc(owner, `users/${OWNER}/user_assessments/a3`), { task_generation_epoch: 1, name: "x" }));
  await assertFails(setDoc(doc(owner, `users/${OWNER}/user_assessments/a4`), { task_generation_epoch: "0", name: "x" }));
  await seed({ [`users/${OWNER}`]: { name: "Owner", taskGenerationEpoch: 2 } });
  await assertSucceeds(setDoc(doc(owner, `users/${OWNER}/user_assessments/a5`), { task_generation_epoch: 2, name: "x" }));
  await assertFails(setDoc(doc(owner, `users/${OWNER}/user_assessments/a6`), { task_generation_epoch: 1, name: "x" }));
  await seed({ [`users/${OWNER}`]: { name: "Owner", taskGenerationEpoch: 2, taskReset: { state: "deleting" } } });
  await assertFails(setDoc(doc(owner, `users/${OWNER}/user_assessments/a7`), { task_generation_epoch: 2, name: "x" }));
});

test("assessment updates never change or remove the stamp and unstamped rows update only at root epoch 0", async () => {
  const owner = dbFor(OWNER);
  await seed({
    [`users/${OWNER}/user_assessments/stamped`]: { task_generation_epoch: 0, name: "s" },
    [`users/${OWNER}/user_assessments/unstamped`]: { name: "u" }
  });
  await assertSucceeds(updateDoc(doc(owner, `users/${OWNER}/user_assessments/stamped`), { name: "s2" }));
  await assertFails(updateDoc(doc(owner, `users/${OWNER}/user_assessments/stamped`), { task_generation_epoch: 1 }));
  await assertFails(updateDoc(doc(owner, `users/${OWNER}/user_assessments/stamped`), { task_generation_epoch: deleteField() }));
  await assertSucceeds(updateDoc(doc(owner, `users/${OWNER}/user_assessments/unstamped`), { name: "u2" }));
  await assertFails(updateDoc(doc(owner, `users/${OWNER}/user_assessments/unstamped`), { task_generation_epoch: 0 }));
  await seed({ [`users/${OWNER}`]: { name: "Owner", taskGenerationEpoch: 1 } });
  await assertFails(updateDoc(doc(owner, `users/${OWNER}/user_assessments/unstamped`), { name: "u3" }));
  await assertFails(updateDoc(doc(owner, `users/${OWNER}/user_assessments/stamped`), { name: "s3" }));
});

test("userKnowledge stamps mirror assessments and permit only the epoch-zero upgrade", async () => {
  const owner = dbFor(OWNER);
  const ref = doc(owner, `userKnowledge/${OWNER}`);
  await assertFails(setDoc(ref, { entries: {} }));
  await assertSucceeds(setDoc(ref, { entries: {}, task_generation_epoch: 0 }));
  await assertSucceeds(setDoc(ref, { entries: { a: 1 }, task_generation_epoch: 0 }, { merge: true }));
  await assertFails(setDoc(ref, { entries: { a: 1 }, task_generation_epoch: 1 }, { merge: true }));
  await assertFails(updateDoc(ref, { task_generation_epoch: deleteField() }));
  await seed({ [`userKnowledge/${OWNER}`]: { entries: { legacy: 1 } } });
  await assertSucceeds(setDoc(ref, { entries: { b: 2 }, task_generation_epoch: 0 }, { merge: true }));
  await seed({ [`userKnowledge/${OWNER}`]: { entries: { legacy: 1 } }, [`users/${OWNER}`]: { name: "Owner", taskGenerationEpoch: 2 } });
  await assertFails(setDoc(ref, { entries: { b: 2 } }, { merge: true }));
  await assertFails(setDoc(ref, { entries: { b: 2 }, task_generation_epoch: 2 }, { merge: true }));
  await assertFails(setDoc(ref, { entries: { b: 2 }, task_generation_epoch: 0 }, { merge: true }));
});

test("root dailyDose writes carry the exact stamped map and the epoch field is server-owned", async () => {
  const owner = dbFor(OWNER);
  const root = doc(owner, `users/${OWNER}`);
  await assertSucceeds(updateDoc(root, { dailyDose: { schema_version: 1, task_generation_epoch: 0, date: "2026-09-03", taskIds: ["t1"] } }));
  await assertFails(updateDoc(root, { dailyDose: { date: "2026-09-03", taskIds: [] } }));
  await assertFails(updateDoc(root, { dailyDose: { schema_version: 1, task_generation_epoch: 1, date: "2026-09-03", taskIds: [] } }));
  await assertFails(updateDoc(root, { dailyDose: { schema_version: 1, task_generation_epoch: 0, date: "2026-09-03", taskIds: [], extra: true } }));
  await assertFails(updateDoc(root, { taskGenerationEpoch: 5 }));
  await assertSucceeds(updateDoc(root, { name: "still writable" }));
  await seed({ [`users/${OWNER}`]: { name: "Owner", taskGenerationEpoch: 3 } });
  await assertSucceeds(updateDoc(root, { dailyDose: { schema_version: 1, task_generation_epoch: 3, date: "2026-09-03", taskIds: [] } }));
  await assertFails(updateDoc(root, { dailyDose: { schema_version: 1, task_generation_epoch: 2, date: "2026-09-03", taskIds: [] } }));
});
