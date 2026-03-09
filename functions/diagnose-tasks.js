const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

const db = admin.firestore();

async function diagnose() {
    // 1. Check taskCatalog
    const catalog = await db.collection("taskCatalog").get();
    console.log(`\n📚 taskCatalog: ${catalog.size} documents`);

    if (catalog.size === 0) {
        console.log("❌ PROBLEM: taskCatalog is EMPTY. Run: node seedTaskCatalog.js");
        return;
    }

    // Show a few task IDs and their conditions
    let unconditional = 0;
    catalog.forEach(doc => {
        const data = doc.data();
        const conditions = data.conditions || {};
        const condKeys = Object.keys(conditions);
        if (condKeys.length === 0) unconditional++;
    });
    console.log(`   └─ ${unconditional} tasks have NO conditions (should always generate)`);

    // 2. Find most recent user assessment
    const usersSnap = await db.collection("users").get();
    console.log(`\n👤 Total users: ${usersSnap.size}`);

    for (const userDoc of usersSnap.docs) {
        const userId = userDoc.id;

        // Check for assessment
        const assessments = await db.collection("users").doc(userId)
            .collection("user_assessments").limit(1).get();

        if (assessments.empty) continue;

        const assessmentData = assessments.docs[0].data();
        console.log(`\n🔍 User: ${userId}`);
        console.log(`   Assessment exists: YES`);
        console.log(`   userName: ${assessmentData.userName || "(empty)"}`);
        console.log(`   moveDate: ${assessmentData.moveDate?._seconds ? new Date(assessmentData.moveDate._seconds * 1000).toISOString() : assessmentData.moveDate || "(missing)"}`);

        // Check for generated tasks
        const tasks = await db.collection("users").doc(userId)
            .collection("tasks").get();
        console.log(`   Tasks in tasks collection: ${tasks.size}`);

        if (tasks.size === 0) {
            console.log(`   ❌ ZERO TASKS — checking why...`);

            // Log key assessment fields that conditions check against
            const keyFields = [
                "currentRentOrOwn", "newRentOrOwn", "hasVehicles", "hasStorage",
                "hasDeclutter", "wantToSell", "moveDistance", "isInterstate",
                "hireMovers", "hireMoversDetail", "hireCleaners", "hireCleanersDetail",
                "wantsTruckRental", "packingPreference",
                "childrenInSchool", "childrenInDaycare", "hasVet",
                "financialInstitutions", "healthcareProviders", "fitnessWellness",
                "schoolAgeChildren", "childrenUnder5", "hasPets", "hasKids"
            ];

            console.log(`\n   📋 Assessment data (condition-relevant fields):`);
            for (const field of keyFields) {
                const value = assessmentData[field];
                if (value !== undefined && value !== "" && value !== null) {
                    console.log(`      ${field}: ${JSON.stringify(value)}`);
                }
            }

            // Also dump ALL keys so we can see what's actually stored
            console.log(`\n   📋 ALL assessment keys stored:`);
            const allKeys = Object.keys(assessmentData).sort();
            console.log(`      ${allKeys.join(", ")}`);
        } else {
            // Show first few task titles
            const titles = tasks.docs.slice(0, 5).map(d => d.data().title);
            console.log(`   Sample tasks: ${titles.join(", ")}`);
        }
    }
}

diagnose().then(() => {
    console.log("\n✅ Diagnostic complete");
    process.exit(0);
}).catch(err => {
    console.error("❌ Error:", err);
    process.exit(1);
});
