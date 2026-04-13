/**
 * teardownTestUser.js
 *
 * Deletes all data for the E2E test user.
 *
 * Usage:
 *   cd functions && node testProfile/teardownTestUser.js
 *
 * What it deletes:
 *   - users/{uid}/tasks
 *   - users/{uid}/user_assessments
 *   - users/{uid}/supportChat
 *   - users/{uid}/miniAssessments
 *   - users/{uid}/workflowResponses
 *   - users/{uid}/inventory
 *   - users/{uid} profile doc
 *   - userKnowledge/{uid}
 *   - Firebase Auth user
 */

const admin = require("firebase-admin");

const serviceAccount = require("../serviceAccountKey.json");
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

const db = admin.firestore();
const auth = admin.auth();

const TEST_EMAIL = "peezy-test-bot@test.peezyapp.com";

async function clearSubcollection(uid, sub) {
    const snap = await db.collection("users").doc(uid).collection(sub).get();
    if (snap.empty) return 0;
    const batchSize = 500;
    for (let i = 0; i < snap.docs.length; i += batchSize) {
        const batch = db.batch();
        snap.docs.slice(i, i + batchSize).forEach(d => batch.delete(d.ref));
        await batch.commit();
    }
    return snap.size;
}

async function main() {
    console.log("═══════════════════════════════════════════");
    console.log("  Peezy E2E Test User Teardown");
    console.log("═══════════════════════════════════════════");

    // Look up user by email
    let uid;
    try {
        const user = await auth.getUserByEmail(TEST_EMAIL);
        uid = user.uid;
    } catch (e) {
        if (e.code === "auth/user-not-found") {
            console.log(`\n✅ User ${TEST_EMAIL} not found — nothing to tear down.`);
            process.exit(0);
        }
        throw e;
    }

    console.log(`\n🗑️  Tearing down test user: ${uid}`);

    // Delete subcollections
    const subcollections = [
        "tasks",
        "user_assessments",
        "supportChat",
        "miniAssessments",
        "workflowResponses",
        "inventory",
    ];

    for (const sub of subcollections) {
        const count = await clearSubcollection(uid, sub);
        console.log(`   ${count > 0 ? `Deleted ${count}` : "0"} docs from users/${uid}/${sub}`);
    }

    // Delete user profile doc
    await db.collection("users").doc(uid).delete();
    console.log(`   Deleted users/${uid}`);

    // Delete userKnowledge doc
    await db.collection("userKnowledge").doc(uid).delete().catch(() => {});
    console.log(`   Deleted userKnowledge/${uid}`);

    // Delete Firebase Auth user
    await auth.deleteUser(uid);
    console.log(`   Deleted Auth user: ${TEST_EMAIL}`);

    console.log("\n═══════════════════════════════════════════");
    console.log("  ✅ Teardown complete.");
    console.log("═══════════════════════════════════════════\n");

    process.exit(0);
}

main().catch(err => {
    console.error("\n❌ Error:", err.message);
    process.exit(1);
});
