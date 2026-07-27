/**
 * seedTaskCatalog.js
 *
 * One-time script to wipe and reseed the `taskCatalog` collection in Firestore.
 * Uses Firebase Admin SDK — run from your `functions/` directory or anywhere
 * you have a service account key.
 *
 * Usage:
 *   1. Place this file and taskCatalogData.json in your functions/ directory
 *   2. Make sure you have firebase-admin installed: npm install firebase-admin
 *   3. Run: node seedTaskCatalog.js
 *
 * The script will:
 *   - Delete ALL existing documents in `taskCatalog`
 *   - Write each task from taskCatalogData.json as a new document
 *   - Use taskId as the Firestore document ID (e.g., "BOOK_MOVERS")
 *   - Store conditions as a map/object for clean condition evaluation
 *
 * Conditions format in Firestore:
 *   {
 *     "hireMovers": ["Hire Movers"],           // single acceptable value
 *     "moveDistance": ["Long Distance", "Cross-Country"]  // OR — match any
 *   }
 *   Logic: AND between keys, OR within each key's array.
 *   Empty object {} = no conditions = always generated for every user.
 */

const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");
const { isDeepStrictEqual } = require("util");

// ── Initialize Firebase Admin ──
// Option A: If running from functions/ directory with default credentials
// admin.initializeApp();

// Option B: If you have a service account key file
const serviceAccount = require("./serviceAccountKey.json");
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

// Option C: Using project ID (works if you're authenticated via `firebase login`)
// admin.initializeApp({ projectId: "peezy-1ecrdl" });

const db = admin.firestore();
const COLLECTION = "taskCatalog";

async function deleteCollection() {
  console.log(`\n🗑️  Deleting all documents in '${COLLECTION}'...`);

  const snapshot = await db.collection(COLLECTION).get();

  if (snapshot.empty) {
    console.log("   Collection is already empty.");
    return 0;
  }

  // Firestore batch limit is 500 — chunk if needed
  const batchSize = 500;
  const docs = snapshot.docs;
  let deleted = 0;

  for (let i = 0; i < docs.length; i += batchSize) {
    const batch = db.batch();
    const chunk = docs.slice(i, i + batchSize);

    chunk.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    deleted += chunk.length;
  }

  console.log(`   Deleted ${deleted} documents.`);
  return deleted;
}

async function seedCollection() {
  // Load task data
  const dataPath = path.join(__dirname, "taskCatalogData.json");

  if (!fs.existsSync(dataPath)) {
    console.error(`\n❌ taskCatalogData.json not found at ${dataPath}`);
    console.error("   Make sure the JSON file is in the same directory as this script.");
    process.exit(1);
  }

  const tasks = JSON.parse(fs.readFileSync(dataPath, "utf8"));
  console.log(`\n📦 Seeding ${tasks.length} tasks into '${COLLECTION}'...`);

  // Firestore batch limit is 500 — chunk if needed
  const batchSize = 500;
  let written = 0;

  for (let i = 0; i < tasks.length; i += batchSize) {
    const batch = db.batch();
    const chunk = tasks.slice(i, i + batchSize);

    for (const task of chunk) {
      const docId = task.taskId;
      const docRef = db.collection(COLLECTION).doc(docId);

      // Build the Firestore document
      const doc = {
        taskId: task.taskId,
        title: task.title,
        actionCategory: task.actionCategory,
        category: task.category,
        actionType: task.actionType,
      taskType: task.taskType || "provide_info",
        conditions: task.conditions, // stored as map: { key: [values] }
        desc: task.desc,
        estHours: task.estHours,
        estPeezy: task.estPeezy,
        tips: task.tips,
        urgencyPercentage: task.urgencyPercentage,
        whyNeeded: task.whyNeeded,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Only include workflowId if present (workflow tasks only)
      if (task.workflowId) {
        doc.workflowId = task.workflowId;
      }

      // Include selfServiceOnly flag (defaults to false if absent)
      doc.selfServiceOnly = task.selfServiceOnly || false;

      // Row-generation config (Spec 04 catalog v2) — consumed by the client's
      // TaskGenerationService to stamp per-user flowRows on task docs
      if (task.rowGeneration) {
        doc.rowGeneration = task.rowGeneration;
      }
      if (Number.isInteger(task.surfaceAfterDaysPastMove)) {
        doc.surfaceAfterDaysPastMove = task.surfaceAfterDaysPastMove;
      }

      batch.set(docRef, doc);
    }

    await batch.commit();
    written += chunk.length;
    console.log(`   Wrote ${written}/${tasks.length}...`);
  }

  console.log(`   ✅ Seeded ${written} tasks.`);
  return written;
}

async function verifySeed() {
  console.log(`\n🔍 Verifying seed...`);

  const snapshot = await db.collection(COLLECTION).get();
  console.log(`   Documents in collection: ${snapshot.size}`);

  // Ghost-task check: every doc in the collection must exist in the JSON
  const tasks = JSON.parse(fs.readFileSync(path.join(__dirname, "taskCatalogData.json"), "utf8"));
  const jsonIds = new Set(tasks.map((t) => t.taskId));
  const ghosts = snapshot.docs.filter((d) => !jsonIds.has(d.id)).map((d) => d.id);
  if (ghosts.length > 0) {
    console.log(`   ✗ GHOST TASKS (in Firestore, not in JSON): ${ghosts.join(", ")}`);
  } else {
    console.log(`   ✓ No ghost tasks — collection matches taskCatalogData.json exactly`);
  }

  const documentsById = new Map(snapshot.docs.map((document) => [document.id, document.data()]));
  const roundTripFailures = [];
  for (const task of tasks) {
    const stored = documentsById.get(task.taskId);
    if (!stored) {
      roundTripFailures.push(`${task.taskId}: missing document`);
      continue;
    }
    const mismatchedFields = Object.entries(task)
      .filter(([key, value]) => !isDeepStrictEqual(stored[key], value))
      .map(([key]) => key);
    if (mismatchedFields.length > 0) {
      roundTripFailures.push(`${task.taskId}: ${mismatchedFields.join(", ")}`);
    }
  }
  if (roundTripFailures.length > 0) {
    throw new Error(`Catalog round-trip failed — ${roundTripFailures.join("; ")}`);
  }
  console.log("   ✓ Every JSON-declared catalog field round-tripped exactly");

  // Spot-check a few documents (catalog v2 ids)
  const spotChecks = [
    "BOOK_MOVERS", "SETUP_INTERNET", "MEMBERSHIPS", "FINANCIAL_ACCOUNTS",
    "STORAGE_UNIT", "MOVE_CHECKIN", "BOX_RETURN"
  ];
  for (const id of spotChecks) {
    const doc = await db.collection(COLLECTION).doc(id).get();
    if (doc.exists) {
      const data = doc.data();
      const condKeys = Object.keys(data.conditions || {});
      console.log(
        `   ✓ ${id}: "${data.title}" | urgency: ${data.urgencyPercentage} | conditions: ${condKeys.length > 0 ? condKeys.join(", ") : "(none — always generated)"}`
      );
    } else {
      console.log(`   ✗ ${id}: NOT FOUND`);
    }
  }
}

// ── Flow definitions (Spec 04) ──
// Seeds the `flowDefinitions` collection from flowDefinitionsData.json.
// Doc id = workflowId. Served to the client through getWorkflowQualifying
// (deployed rules have no direct client read on this collection).

const FLOW_COLLECTION = "flowDefinitions";

async function seedFlowDefinitions() {
  const dataPath = path.join(__dirname, "flowDefinitionsData.json");
  if (!fs.existsSync(dataPath)) {
    console.error(`\n❌ flowDefinitionsData.json not found at ${dataPath}`);
    process.exit(1);
  }

  const definitions = JSON.parse(fs.readFileSync(dataPath, "utf8"));
  console.log(`\n📦 Seeding ${definitions.length} flow definitions into '${FLOW_COLLECTION}'...`);

  // Wipe (definitions retired by catalog v2 must not linger)
  const existing = await db.collection(FLOW_COLLECTION).get();
  if (!existing.empty) {
    const batch = db.batch();
    existing.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    console.log(`   Deleted ${existing.size} existing definitions.`);
  }

  const batch = db.batch();
  for (const definition of definitions) {
    batch.set(db.collection(FLOW_COLLECTION).doc(definition.workflowId), definition);
  }
  await batch.commit();
  console.log(`   ✅ Seeded ${definitions.length} flow definitions.`);

  // Cross-check: every catalog workflowId that the engine routes must have a
  // definition. The Swift-custom flows keep their screens this spec.
  const SWIFT_CUSTOM = new Set([
    "book_movers", "book_cleaners", "setup_internet", "sell_items", "remove_items",
    "rent_truck", "handle_auto_insurance", "update_auto_insurance", "handle_home_insurance",
    "cancel_renters_insurance", "setup_renters_insurance", "transfer_renters_insurance",
    "cancel_condo_insurance", "setup_condo_insurance", "transfer_condo_insurance",
    "cancel_homeowners_insurance", "setup_homeowners_insurance", "transfer_homeowners_insurance",
    "scan_inventory",
  ]);
  const tasks = JSON.parse(fs.readFileSync(path.join(__dirname, "taskCatalogData.json"), "utf8"));
  const definitionIds = new Set(definitions.map((d) => d.workflowId));
  const missing = [];
  for (const task of tasks) {
    const flowId = task.workflowId || task.taskId.toLowerCase();
    if (task.actionType === "in-app" || task.actionType === "in-app-inventory") continue;
    if (SWIFT_CUSTOM.has(flowId)) continue;
    if (!definitionIds.has(flowId)) missing.push(`${task.taskId} → ${flowId}`);
  }
  if (missing.length > 0) {
    console.log(`   ✗ CATALOG TASKS WITHOUT DEFINITIONS: ${missing.join(", ")}`);
  } else {
    console.log(`   ✓ Every engine-routed catalog task has a flow definition`);
  }
}

async function main() {
  console.log("═══════════════════════════════════════════");
  console.log("  Peezy Task Catalog Seeder");
  console.log("  Project: peezy-1ecrdl");
  console.log("═══════════════════════════════════════════");

  try {
    const deleted = await deleteCollection();
    const written = await seedCollection();
    await verifySeed();
    await seedFlowDefinitions();

    console.log("\n═══════════════════════════════════════════");
    console.log(`  Done! Deleted ${deleted}, wrote ${written}.`);
    console.log("═══════════════════════════════════════════\n");
  } catch (error) {
    console.error("\n❌ Error:", error.message);

    if (error.code === "app/no-app") {
      console.error("   Firebase not initialized. Uncomment one of the init options in the script.");
    } else if (error.message.includes("Could not load the default credentials")) {
      console.error("   Run `firebase login` first, or use a service account key.");
    }

    process.exit(1);
  }

  process.exit(0);
}

main();
