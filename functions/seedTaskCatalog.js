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

  // Spot-check a few documents
  const spotChecks = ["BOOK_MOVERS", "SETUP_INTERNET", "CANCEL_YOGA"];
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

async function main() {
  console.log("═══════════════════════════════════════════");
  console.log("  Peezy Task Catalog Seeder");
  console.log("  Project: peezy-1ecrdl");
  console.log("═══════════════════════════════════════════");

  try {
    const deleted = await deleteCollection();
    const written = await seedCollection();
    await verifySeed();

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
