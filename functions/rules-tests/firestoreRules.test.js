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
const storageRules = fs.readFileSync(path.resolve(__dirname, "../../storage.rules"), "utf8");

let environment;

test.before(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || "", /^(127\.0\.0\.1|localhost):\d+$/);
  environment = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules },
    storage: { rules: storageRules }
  });
});

test.after(async () => {
  await environment?.cleanup();
});

test.beforeEach(async () => {
  await environment.clearFirestore();
  await environment.clearStorage();
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

test("C9.3.13 notification intents deny every client operation: owner, other, and anonymous get, list, create, update, delete", async () => {
  const { getDocs: listDocs, collection: collectionOf } = require("firebase/firestore");
  const documentPath = `users/${OWNER}/notificationIntents/ni1_${"a".repeat(40)}`;
  await seed({ [documentPath]: { schema_version: 1, state: "pending" } });
  for (const client of [dbFor(OWNER), dbFor(OTHER), anonymousDb()]) {
    await assertFails(getDoc(doc(client, documentPath)));
    await assertFails(listDocs(collectionOf(client, `users/${OWNER}/notificationIntents`)));
    await assertFails(setDoc(doc(client, `users/${OWNER}/notificationIntents/ni1_${"b".repeat(40)}`), { schema_version: 1 }));
    await assertFails(updateDoc(doc(client, documentPath), { state: "consumed" }));
    await assertFails(deleteDoc(doc(client, documentPath)));
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
  // S3 (briefs/S3_BRIEF.md, C6.8): fcmTokens carries its own create/update grammar below.
  const collections = [
    "user_assessments", "packingPlan", "readiness",
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

// ---------------------------------------------------------------------------
// S3 (briefs/S3_BRIEF.md; PHASE2_CONTRACT.md C3, C5, C6.1, C6.8): account-deletion
// boundaries, the fcmTokens grammar, server-only collections, and late Storage.
// The §5 cleanup predicates, the historical-migration candidates collection, and the
// access-budget rows wait for Reconciled 12.
// ---------------------------------------------------------------------------

const { serverTimestamp, getDocs, collection } = require("firebase/firestore");

const CAPS = [{ operationId: "adel1_00000000-0000-4000-8000-000000000001", proofSHA256: "a".repeat(64) }];
const at = (iso) => new Date(iso);
const MARKERS = {
  DELETING_SWEEPING: { schemaVersion: 1, state: "DELETING", capabilities: CAPS, startedAt: at("2026-09-01T00:00:00.000Z"), storageGuardAfter: at("2026-09-08T00:00:00.000Z") },
  DELETING_GUARDING: { schemaVersion: 1, state: "DELETING", capabilities: CAPS, startedAt: at("2026-09-01T00:00:00.000Z"), storageGuardAfter: at("2026-09-08T00:00:00.000Z"), firestoreCleanupAt: at("2026-09-01T01:00:00.000Z") },
  DATA_DELETED: { schemaVersion: 1, state: "DATA_DELETED", capabilities: CAPS, startedAt: at("2026-09-01T00:00:00.000Z"), storageGuardAfter: at("2026-09-08T00:00:00.000Z"), firestoreCleanupAt: at("2026-09-01T01:00:00.000Z"), storageGuardCompletedAt: at("2026-09-08T00:05:00.000Z"), firestoreVersionGuardCompletedAt: at("2026-09-01T02:00:00.000Z"), dataDeletedAt: at("2026-09-08T00:10:00.000Z") },
  AUTH_GUARDING: { schemaVersion: 1, state: "AUTH_GUARDING", capabilities: CAPS, startedAt: at("2026-09-01T00:00:00.000Z"), storageGuardAfter: at("2026-09-08T00:00:00.000Z"), firestoreCleanupAt: at("2026-09-01T01:00:00.000Z"), storageGuardCompletedAt: at("2026-09-08T00:05:00.000Z"), firestoreVersionGuardCompletedAt: at("2026-09-01T02:00:00.000Z"), dataDeletedAt: at("2026-09-08T00:10:00.000Z"), authAbsenceObservedAt: at("2026-09-08T00:11:00.000Z"), authGuardAfter: at("2026-09-09T00:11:00.000Z") },
  ACCOUNT_DELETED: { schemaVersion: 1, state: "ACCOUNT_DELETED", capabilities: CAPS, startedAt: at("2026-09-01T00:00:00.000Z"), storageGuardAfter: at("2026-09-08T00:00:00.000Z"), firestoreCleanupAt: at("2026-09-01T01:00:00.000Z"), storageGuardCompletedAt: at("2026-09-08T00:05:00.000Z"), firestoreVersionGuardCompletedAt: at("2026-09-01T02:00:00.000Z"), dataDeletedAt: at("2026-09-08T00:10:00.000Z"), authAbsenceObservedAt: at("2026-09-08T00:11:00.000Z"), authGuardAfter: at("2026-09-09T00:11:00.000Z"), authGuardCompletedAt: at("2026-09-09T00:12:00.000Z"), accountDeletedAt: at("2026-09-09T00:12:00.000Z") },
  malformed: { state: "junk" }
};

function storageFor(uid) {
  return environment.authenticatedContext(uid).storage();
}

function storageUpload(uid, objectPath) {
  return storageFor(uid).ref(objectPath).put(new Uint8Array([1, 2, 3]));
}

test("owner is denied every read and write across user paths while the accountDeletion marker exists in any of its four states or malformed", async () => {
  for (const [name, marker] of Object.entries(MARKERS)) {
    await environment.clearFirestore();
    await seed({
      [`users/${OWNER}`]: { name: "Owner", accountDeletion: marker },
      [`users/${OWNER}/tasks/T1`]: { status: "Upcoming" },
      [`users/${OWNER}/user_assessments/a1`]: { task_generation_epoch: 0 },
      [`users/${OWNER}/inventory/room-1`]: { name: "Kitchen" },
      [`users/${OWNER}/supportChat/reply`]: { sender: "support", read: false },
      [`userKnowledge/${OWNER}`]: { task_generation_epoch: 0 }
    });
    const owner = dbFor(OWNER);
    await assertFails(getDoc(doc(owner, `users/${OWNER}`)), name);
    await assertFails(updateDoc(doc(owner, `users/${OWNER}`), { name: "late" }));
    await assertFails(getDoc(doc(owner, `users/${OWNER}/tasks/T1`)));
    await assertFails(setDoc(doc(owner, `users/${OWNER}/tasks/T2`), { status: "Upcoming" }));
    await assertFails(updateDoc(doc(owner, `users/${OWNER}/tasks/T1`), { status: "Completed" }));
    await assertFails(deleteDoc(doc(owner, `users/${OWNER}/tasks/T1`)));
    await assertFails(deleteDoc(doc(owner, `users/${OWNER}/user_assessments/a1`)));
    await assertFails(setDoc(doc(owner, `users/${OWNER}/inventory/room-2`), { name: "Bath" }));
    await assertFails(getDoc(doc(owner, `users/${OWNER}/inventory/room-1`)));
    await assertFails(updateDoc(doc(owner, `users/${OWNER}/supportChat/reply`), { read: true }));
    await assertFails(setDoc(doc(owner, `users/${OWNER}/supportChat/late`), { sender: "user", text: "late" }));
    await assertFails(setDoc(doc(owner, `users/${OWNER}/fcmTokens/tok`), { createdAt: serverTimestamp(), platform: "ios" }));
    await assertFails(getDoc(doc(owner, `userKnowledge/${OWNER}`)));
    await assertFails(setDoc(doc(owner, `userKnowledge/${OWNER}`), { task_generation_epoch: 0 }, { merge: true }));
    await assertFails(deleteDoc(doc(owner, `userKnowledge/${OWNER}`)));
  }
});

test("descendant and userKnowledge writes require marker absence: a fresh owner without a root document still writes, and the root create/update can never carry accountDeletion", async () => {
  const fresh = "fresh-owner-2";
  const db = environment.authenticatedContext(fresh).firestore();
  await assertSucceeds(getDoc(doc(db, `users/${fresh}`))); // D15 point-path read of an absent root
  await assertSucceeds(setDoc(doc(db, `users/${fresh}/fcmTokens/tok`), { createdAt: serverTimestamp(), platform: "ios" }));
  await assertSucceeds(setDoc(doc(db, `users/${fresh}/inventory/room-1`), { name: "Kitchen" }));
  await assertFails(setDoc(doc(db, `users/${fresh}`), { name: "Fresh", accountDeletion: MARKERS.DELETING_SWEEPING }));
  await assertSucceeds(setDoc(doc(db, `users/${fresh}`), { name: "Fresh" }));
  await assertFails(updateDoc(doc(db, `users/${fresh}`), { accountDeletion: MARKERS.DELETING_SWEEPING }));
  await assertSucceeds(setDoc(doc(db, `users/${fresh}/tasks/T1`), { status: "Upcoming" }));
});

test("fcmTokens: create and update accept exactly {createdAt: server time, platform: 'ios'}, delete stays owner-only, and read/list are denied even to the owner", async () => {
  const owner = dbFor(OWNER);
  const tok = doc(owner, `users/${OWNER}/fcmTokens/token-1`);
  await assertSucceeds(setDoc(tok, { createdAt: serverTimestamp(), platform: "ios" }));
  await assertSucceeds(setDoc(tok, { createdAt: serverTimestamp(), platform: "ios" }));
  await assertFails(setDoc(doc(owner, `users/${OWNER}/fcmTokens/t2`), { platform: "ios" }));
  await assertFails(setDoc(doc(owner, `users/${OWNER}/fcmTokens/t3`), { createdAt: serverTimestamp() }));
  await assertFails(setDoc(doc(owner, `users/${OWNER}/fcmTokens/t4`), { createdAt: serverTimestamp(), platform: "android" }));
  await assertFails(setDoc(doc(owner, `users/${OWNER}/fcmTokens/t5`), { createdAt: serverTimestamp(), platform: "ios", extra: 1 }));
  await assertFails(setDoc(doc(owner, `users/${OWNER}/fcmTokens/t6`), { createdAt: new Date("2020-01-01T00:00:00Z"), platform: "ios" }));
  await assertFails(updateDoc(tok, { platform: "android" }));
  await assertFails(getDoc(tok));
  await assertFails(getDocs(collection(owner, `users/${OWNER}/fcmTokens`)));
  await assertFails(getDoc(doc(dbFor(OTHER), `users/${OWNER}/fcmTokens/token-1`)));
  await assertFails(deleteDoc(doc(dbFor(OTHER), `users/${OWNER}/fcmTokens/token-1`)));
  await assertSucceeds(deleteDoc(tok));
});

test("phase2System documents, both work-row collections, outboundLeases, legacyResetMigrations, quarantine rows, archive chunks, and refusal rows are denied to owner, other, and anonymous clients", async () => {
  const paths = [
    "phase2System/accountDeletionStorageReconcilerV1",
    "accountDeletionStorageWork/adsw1_x",
    "accountDeletionAuthWork/adaw1_x",
    `users/${OWNER}/outboundLeases/uol1_00000000-0000-4000-8000-000000000001`,
    `users/${OWNER}/legacyResetMigrations/rlm1_x`,
    "phase1System/dispositionTriggerState/quarantinedEvents/q1",
    "eventArchiveChunks/c1",
    `users/${OWNER}/eventArchiveChunks/c1`,
    "schedulerRefusals/r1",
    `users/${OWNER}/schedulerRefusals/r1`
  ];
  await seed(Object.fromEntries(paths.map((documentPath) => [documentPath, { value: 1 }])));
  for (const db of [dbFor(OWNER), dbFor(OTHER), anonymousDb()]) {
    for (const documentPath of paths) {
      const ref = doc(db, documentPath);
      await assertFails(getDoc(ref), documentPath);
      await assertFails(setDoc(ref, { value: 2 }), documentPath);
      await assertFails(updateDoc(ref, { value: 3 }), documentPath);
      await assertFails(deleteDoc(ref), documentPath);
    }
  }
});

test("Storage: inventory uploads require the owner, an existing root, and no marker; late uploads after the marker are denied; other users are denied", async () => {
  const objectPath = `inventory/${OWNER}/session-1/frame_0.jpg`;
  await environment.clearFirestore(); // no root document
  await assertFails(storageUpload(OWNER, objectPath));
  await seed({ [`users/${OWNER}`]: { name: "Owner" } });
  await assertSucceeds(storageUpload(OWNER, objectPath));
  await assertSucceeds(storageFor(OWNER).ref(objectPath).getDownloadURL());
  await assertFails(storageUpload(OTHER, objectPath));
  await assertFails(storageFor(OTHER).ref(objectPath).getDownloadURL());
  for (const [name, marker] of Object.entries(MARKERS)) {
    await seed({ [`users/${OWNER}`]: { name: "Owner", accountDeletion: marker } });
    await assertFails(storageUpload(OWNER, `inventory/${OWNER}/session-1/frame_1.jpg`), name);
    await assertFails(storageUpload(OWNER, objectPath), name);
  }
  await seed({ [`users/${OWNER}`]: { name: "Owner" } });
  await assertSucceeds(storageFor(OWNER).ref(objectPath).delete());
});
