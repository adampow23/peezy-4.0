/**
 * seedTestUser.js
 *
 * Creates a complete test user for E2E testing.
 *
 * Usage:
 *   cd functions && node testProfile/seedTestUser.js
 *
 * What it does:
 *   1. Creates (or reuses) Firebase Auth user: peezy-test-bot@test.peezyapp.com
 *   2. Writes assessment data to users/{uid}/user_assessments and userKnowledge/{uid}
 *   3. Generates tasks by evaluating taskCatalog conditions (mirrors TaskConditionParser.swift)
 *   4. Applies test state modifications to first 4 tasks
 *   5. Seeds 2 support chat messages (one unread, triggers badge)
 *   6. Writes user profile doc
 */

const admin = require("firebase-admin");

const serviceAccount = require("../serviceAccountKey.json");
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

const db = admin.firestore();
const auth = admin.auth();

const TEST_EMAIL = "peezy-test-bot@test.peezyapp.com";
const TEST_PASSWORD = "PeezyTest2026!";
const TEST_NAME = "Peezy Tester";

const ASSESSMENT_DATA = {
    userName: "Peezy Tester",
    moveDate: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)),
    moveDateType: "Exact",
    moveConcerns: ["Forgetting something", "Cost"],
    currentRentOrOwn: "Rent",
    currentDwellingType: "Apartment",
    currentAddress: "100 E 14th St, Kansas City, MO 64106",
    currentUnitNumber: "4B",
    currentFloorAccess: "Elevator",
    currentBedrooms: "2",
    currentSquareFootage: "950",
    currentFinishedSqFt: "",
    newRentOrOwn: "Rent",
    newDwellingType: "House",
    newAddress: "3600 Broadway Blvd, Kansas City, MO 64111",
    newUnitNumber: "",
    newFloorAccess: "",
    newBedrooms: "3",
    newSquareFootage: "",
    newFinishedSqFt: "1400",
    anyKids: "Yes",
    childrenInSchool: "Yes",
    childrenInDaycare: "No",
    hasVet: "Yes",
    hasVehiclesDetail: "Yes",
    hasVehicles: "Yes",
    hasStorage: "No",
    storageSize: "",
    storageFullness: "",
    hireMovers: "Yes",
    hireMoversDetail: "Yes",
    hirePackers: "No",
    hireCleaners: "Yes",
    hireCleanersDetail: "Yes",
    wantsTruckRental: "No",
    hasDeclutter: "Yes",
    wantToSell: "No",
    financialInstitutions: ["Bank Account", "Credit Card"],
    healthcareProviders: ["Primary Care Doctor", "Dentist", "Health Insurance"],
    fitnessWellness: ["Gym"],
    financialDetails: { "Bank Account": "Chase", "Credit Card": "Amex" },
    healthcareDetails: { "Primary Care Doctor": "Dr. Smith", "Dentist": "Aspen Dental" },
    fitnessDetails: { "Gym": "Planet Fitness" },
    financialCounts: { "Bank Account": 1, "Credit Card": 1 },
    healthcareCounts: { "Primary Care Doctor": 1, "Dentist": 1, "Health Insurance": 1 },
    fitnessCounts: { "Gym": 1 },
    howHeard: "Friend",
    referralCode: "",
    promoCode: "",
    moveDistance: "Local",
    isInterstate: "No",
    autoRoomList: ["Living Room", "Kitchen", "Bedroom 1", "Bedroom 2", "Bathroom", "Garage"],
};

// ── Condition Evaluation (mirrors TaskConditionParser.swift) ──

function evaluateConditions(conditions, assessment) {
    if (!conditions || Object.keys(conditions).length === 0) {
        return true; // no conditions = task for everyone
    }

    for (const [fieldName, acceptableValues] of Object.entries(conditions)) {
        if (!Array.isArray(acceptableValues) || acceptableValues.length === 0) {
            return false; // invalid format — fail safely (mirrors Swift behavior)
        }

        // Case-insensitive key lookup
        const userEntry = Object.entries(assessment).find(
            ([k]) => k.toLowerCase() === fieldName.toLowerCase()
        );
        const userValue = userEntry ? userEntry[1] : undefined;

        if (!checkValueMatches(userValue, acceptableValues)) {
            return false;
        }
    }

    return true;
}

function checkValueMatches(userValue, acceptableValues) {
    if (userValue === undefined || userValue === null) {
        return acceptableValues.some(v => v === "" || v.toLowerCase() === "nil");
    }

    // Multi-select array matching (fitnessWellness, healthcareProviders, financialInstitutions)
    if (Array.isArray(userValue)) {
        return userValue.some(item =>
            acceptableValues.some(acceptable =>
                String(item).toLowerCase() === acceptable.toLowerCase()
            )
        );
    }

    // Single value matching
    const userStr = String(userValue);
    return acceptableValues.some(acceptable => matchesValue(userStr, acceptable));
}

function matchesValue(userStr, acceptable) {
    if (/^(>=|<=|>|<)/.test(acceptable)) {
        return handleNumericComparison(userStr, acceptable);
    }
    return userStr.toLowerCase() === acceptable.toLowerCase();
}

function handleNumericComparison(userStr, comparison) {
    let op, numStr;
    if (comparison.startsWith(">="))      { op = ">="; numStr = comparison.slice(2); }
    else if (comparison.startsWith("<=")) { op = "<="; numStr = comparison.slice(2); }
    else if (comparison.startsWith(">"))  { op = ">";  numStr = comparison.slice(1); }
    else if (comparison.startsWith("<"))  { op = "<";  numStr = comparison.slice(1); }
    else return false;

    const threshold = parseInt(numStr, 10);
    const userNum = parseInt(userStr, 10);
    if (isNaN(threshold) || isNaN(userNum)) return false;

    switch (op) {
        case ">=": return userNum >= threshold;
        case "<=": return userNum <= threshold;
        case ">":  return userNum > threshold;
        case "<":  return userNum < threshold;
        default:   return false;
    }
}

// Due date = today + totalDays * (1 - urgency/100)
// Mirrors TaskGenerationService.calculateDueDate()
function calculateDueDate(moveDate, urgencyPercentage) {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const moveDay = new Date(moveDate.toDate());
    moveDay.setHours(0, 0, 0, 0);

    const totalDays = Math.floor((moveDay - today) / (1000 * 60 * 60 * 24));
    if (totalDays <= 0) return today;

    const daysFromNow = Math.floor(totalDays * (1 - urgencyPercentage / 100));
    const dueDate = new Date(today);
    dueDate.setDate(dueDate.getDate() + daysFromNow);

    return dueDate < today ? today : dueDate;
}

// Delete all docs in a subcollection (batched)
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
    console.log("  Peezy E2E Test User Seeder");
    console.log("  Project: peezy-1ecrdl");
    console.log("═══════════════════════════════════════════");

    // ── Step 1: Get or create Firebase Auth user ──
    let uid;
    try {
        const existing = await auth.getUserByEmail(TEST_EMAIL);
        uid = existing.uid;
        console.log(`\n♻️  Found existing auth user: ${uid}`);
        console.log("   Cleaning old data...");
        const subs = ["tasks", "user_assessments", "supportChat", "miniAssessments", "workflowResponses", "inventory"];
        for (const sub of subs) {
            const count = await clearSubcollection(uid, sub);
            if (count > 0) console.log(`   Cleared ${count} docs from ${sub}`);
        }
        await db.collection("users").doc(uid).delete().catch(() => {});
        await db.collection("userKnowledge").doc(uid).delete().catch(() => {});
    } catch (e) {
        if (e.code === "auth/user-not-found") {
            const newUser = await auth.createUser({
                email: TEST_EMAIL,
                password: TEST_PASSWORD,
                displayName: TEST_NAME,
                emailVerified: true,
            });
            uid = newUser.uid;
            console.log(`\n✅ Created new auth user: ${uid}`);
        } else {
            throw e;
        }
    }

    // ── Step 2: Write assessment data ──
    const assessmentRef = await db
        .collection("users").doc(uid)
        .collection("user_assessments")
        .add(ASSESSMENT_DATA);
    console.log(`\n📝 Assessment → users/${uid}/user_assessments/${assessmentRef.id}`);

    await db.collection("userKnowledge").doc(uid).set(ASSESSMENT_DATA, { merge: true });
    console.log(`📝 Assessment → userKnowledge/${uid}`);

    // ── Step 3: Generate tasks from taskCatalog ──
    console.log("\n🔍 Reading task catalog...");
    const catalogSnap = await db.collection("taskCatalog").get();
    console.log(`   ${catalogSnap.size} tasks in catalog`);

    const matchedTasks = [];
    for (const doc of catalogSnap.docs) {
        const taskData = doc.data();
        if (evaluateConditions(taskData.conditions, ASSESSMENT_DATA)) {
            const urgency = typeof taskData.urgencyPercentage === "number"
                ? taskData.urgencyPercentage
                : 50;
            const dueDate = calculateDueDate(ASSESSMENT_DATA.moveDate, urgency);

            const userTask = {
                id: doc.id,
                taskId: taskData.taskId || doc.id,
                title: taskData.title || "",
                desc: taskData.desc || "",
                category: taskData.category || "custom",
                actionCategory: taskData.actionCategory || "",
                actionType: taskData.actionType || "off-app",
                taskType: taskData.taskType || "provide_info",
                urgencyPercentage: urgency,
                estHours: taskData.estHours || 0,
                tips: taskData.tips || "",
                whyNeeded: taskData.whyNeeded || "",
                conditions: taskData.conditions || {},
                dueDate: admin.firestore.Timestamp.fromDate(dueDate),
                status: "Upcoming",
                userId: uid,
                createdAt: admin.firestore.Timestamp.now(),
                selfServiceOnly: taskData.selfServiceOnly || false,
            };
            if (taskData.workflowId) userTask.workflowId = taskData.workflowId;

            matchedTasks.push(userTask);
        }
    }

    // Batch write (500/batch limit)
    const batchSize = 500;
    for (let i = 0; i < matchedTasks.length; i += batchSize) {
        const batch = db.batch();
        matchedTasks.slice(i, i + batchSize).forEach(task => {
            const ref = db.collection("users").doc(uid).collection("tasks").doc(task.id);
            batch.set(ref, task);
        });
        await batch.commit();
    }
    console.log(`\n✅ Generated ${matchedTasks.length} tasks`);

    // ── Step 4: Test state modifications ──
    if (matchedTasks.length >= 4) {
        const now = admin.firestore.Timestamp.now();
        const yesterday = new Date();
        yesterday.setDate(yesterday.getDate() - 1);
        const threeDaysAgo = new Date();
        threeDaysAgo.setDate(threeDaysAgo.getDate() - 3);

        const tasksRef = db.collection("users").doc(uid).collection("tasks");

        // Task 0: Completed (for Done tab)
        await tasksRef.doc(matchedTasks[0].id).update({
            status: "Completed",
            completedAt: now,
        });

        // Task 1: In Progress (for In Progress tab)
        await tasksRef.doc(matchedTasks[1].id).update({
            status: "In Progress",
        });

        // Task 2: Snoozed until yesterday (appears in Later tab, snooze has expired)
        await tasksRef.doc(matchedTasks[2].id).update({
            snoozedUntil: admin.firestore.Timestamp.fromDate(yesterday),
            lastSnoozedAt: admin.firestore.Timestamp.fromDate(threeDaysAgo),
        });

        // Task 3: User In Progress (for In Progress sub-section)
        await tasksRef.doc(matchedTasks[3].id).update({
            status: "User In Progress",
            userInProgressDate: now,
        });

        console.log("✅ Test state modifications applied to tasks 0–3:");
        console.log(`   [0] ${matchedTasks[0].id} → Completed`);
        console.log(`   [1] ${matchedTasks[1].id} → In Progress`);
        console.log(`   [2] ${matchedTasks[2].id} → Snoozed (yesterday)`);
        console.log(`   [3] ${matchedTasks[3].id} → User In Progress`);
    } else {
        console.log(`⚠️  Only ${matchedTasks.length} tasks generated — need 4+ for state modifications`);
    }

    // ── Step 5: Support chat messages ──
    const twoHoursAgo = new Date(Date.now() - 2 * 60 * 60 * 1000);
    const oneAndHalfHoursAgo = new Date(Date.now() - 1.5 * 60 * 60 * 1000);
    const chatRef = db.collection("users").doc(uid).collection("supportChat");

    await chatRef.add({
        content: "Hey, I have a question about my move date.",
        role: "user",
        createdAt: admin.firestore.Timestamp.fromDate(twoHoursAgo),
        read: true,
    });

    await chatRef.add({
        content: "Of course! What's going on with your move date?",
        role: "support",
        createdAt: admin.firestore.Timestamp.fromDate(oneAndHalfHoursAgo),
        read: false,
    });

    console.log("✅ Support chat messages written (1 unread → triggers badge)");

    // ── Step 6: User profile doc ──
    await db.collection("users").doc(uid).set({
        name: TEST_NAME,
        email: TEST_EMAIL,
        assessmentCompleted: true,
        moveDate: ASSESSMENT_DATA.moveDate,
        currentAddress: ASSESSMENT_DATA.currentAddress,
        newAddress: ASSESSMENT_DATA.newAddress,
        moveDistance: ASSESSMENT_DATA.moveDistance,
        isInterstate: ASSESSMENT_DATA.isInterstate,
        createdAt: admin.firestore.Timestamp.now(),
    });
    console.log("✅ User profile doc written");

    // ── Step 7: Summary ──
    console.log("\n═══════════════════════════════════════════");
    console.log("  ✅ Test User Ready!");
    console.log(`  UID:      ${uid}`);
    console.log(`  Email:    ${TEST_EMAIL}`);
    console.log(`  Password: ${TEST_PASSWORD}`);
    console.log(`  Tasks:    ${matchedTasks.length}`);
    console.log("═══════════════════════════════════════════\n");

    process.exit(0);
}

main().catch(err => {
    console.error("\n❌ Error:", err.message);
    process.exit(1);
});
