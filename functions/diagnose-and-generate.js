/**
 * diagnose-and-generate.js
 *
 * Reads a user's assessment from Firestore, evaluates every catalog task's
 * conditions against it, and writes matching tasks — all server-side via Admin SDK.
 *
 * This bypasses iOS code AND Firestore security rules to isolate the problem.
 *
 * Usage: node diagnose-and-generate.js
 */
const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();
// ── Condition Evaluation (mirrors TaskConditionParser.swift) ──
function evaluateConditions(conditions, userAssessment) {
    if (!conditions || Object.keys(conditions).length === 0) {
        return { pass: true, reason: "no conditions" };
    }
    for (const [fieldName, acceptableValues] of Object.entries(conditions)) {
        if (!Array.isArray(acceptableValues) || acceptableValues.length === 0) {
            return { pass: false, reason: `invalid format for '${fieldName}'` };
        }
        // Case-insensitive key lookup
        const userKey = Object.keys(userAssessment).find(k => k.toLowerCase() === fieldName.toLowerCase());
        const userValue = userKey ? userAssessment[userKey] : undefined;
        if (userValue === undefined || userValue === null || userValue === "") {
            return { pass: false, reason: `'${fieldName}' is missing/empty in assessment` };
        }
        // Multi-select array matching
        if (Array.isArray(userValue)) {
            const match = userValue.some(uv =>
                acceptableValues.some(av => String(uv).toLowerCase() === String(av).toLowerCase())
            );
            if (!match) {
                return { pass: false, reason: `'${fieldName}': user has [${userValue}] but needs one of [${acceptableValues}]` };
            }
            continue;
        }
        // Single value matching
        const userStr = typeof userValue === "boolean" ? (userValue ? "Yes" : "No") : String(userValue);
        const match = acceptableValues.some(av => userStr.toLowerCase() === String(av).toLowerCase());
        if (!match) {
            return { pass: false, reason: `'${fieldName}': user has '${userStr}' but needs one of [${acceptableValues}]` };
        }
    }
    return { pass: true, reason: "all conditions matched" };
}
async function main() {
    // 1. Find user with assessment
    console.log("🔍 Looking for users with assessments...\n");
    // Since top-level user docs may not exist, we query user_assessments via collection group
    const assessmentSnap = await db.collectionGroup("user_assessments").limit(10).get();
    if (assessmentSnap.empty) {
        console.log("❌ No assessments found anywhere in Firestore.");
        return;
    }
    console.log(`Found ${assessmentSnap.size} assessment(s).\n`);
    for (const assessDoc of assessmentSnap.docs) {
        // Extract userId from path: users/{userId}/user_assessments/{docId}
        const pathParts = assessDoc.ref.path.split("/");
        const userId = pathParts[1];
        const assessmentData = assessDoc.data();
        console.log(`═══════════════════════════════════════════`);
        console.log(`👤 User: ${userId}`);
        console.log(`   Name: ${assessmentData.userName || "(empty)"}`);
        console.log(`   Move date: ${assessmentData.moveDate ? new Date(assessmentData.moveDate._seconds * 1000).toLocaleDateString() : "(missing)"}`);
        // Check existing tasks
        const existingTasks = await db.collection("users").doc(userId).collection("tasks").get();
        console.log(`   Existing tasks: ${existingTasks.size}`);
        // 2. Read catalog
        const catalog = await db.collection("taskCatalog").get();
        console.log(`\n📚 Evaluating ${catalog.size} catalog tasks...\n`);
        let matched = [];
        let failed = [];
        for (const catDoc of catalog.docs) {
            const taskData = catDoc.data();
            const title = taskData.title || catDoc.id;
            const conditions = taskData.conditions || {};
            const result = evaluateConditions(conditions, assessmentData);
            if (result.pass) {
                matched.push({ docId: catDoc.id, title, taskData });
            } else {
                failed.push({ title, reason: result.reason });
            }
        }
        console.log(`✅ MATCHED: ${matched.length} tasks`);
        matched.forEach(m => console.log(`   ✅ ${m.title}`));
        console.log(`\n❌ FAILED: ${failed.length} tasks`);
        // Only show first 10 failures to avoid wall of text
        failed.slice(0, 10).forEach(f => console.log(`   ❌ ${f.title} — ${f.reason}`));
        if (failed.length > 10) console.log(`   ... and ${failed.length - 10} more`);
        // 3. If there are matches and no existing tasks, write them
        if (matched.length > 0 && existingTasks.size === 0) {
            console.log(`\n📝 Writing ${matched.length} tasks to users/${userId}/tasks/...`);
            const moveDate = assessmentData.moveDate
                ? new Date(assessmentData.moveDate._seconds * 1000)
                : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // default 30 days out
            const today = new Date();
            const totalDays = Math.max(1, Math.round((moveDate - today) / (1000 * 60 * 60 * 24)));
            const batch = db.batch();
            for (const m of matched) {
                const td = m.taskData;
                const urgency = td.urgencyPercentage || 50;
                const daysFromNow = Math.round(totalDays * (1.0 - urgency / 100.0));
                const dueDate = new Date(today.getTime() + daysFromNow * 24 * 60 * 60 * 1000);
                const userTask = {
                    id: m.docId,
                    taskId: td.taskId || m.docId,
                    title: td.title || "",
                    desc: td.desc || "",
                    category: td.category || "custom",
                    actionCategory: td.actionCategory || "",
                    actionType: td.actionType || "off-app",
                    urgencyPercentage: urgency,
                    estHours: td.estHours || 0,
                    tips: td.tips || "",
                    whyNeeded: td.whyNeeded || "",
                    conditions: td.conditions || {},
                    dueDate: admin.firestore.Timestamp.fromDate(dueDate),
                    status: "Upcoming",
                    userId: userId,
                    createdAt: admin.firestore.Timestamp.now(),
                };
                if (td.workflowId) {
                    userTask.workflowId = td.workflowId;
                }
                const taskRef = db.collection("users").doc(userId).collection("tasks").doc(m.docId);
                batch.set(taskRef, userTask);
            }
            try {
                await batch.commit();
                console.log(`✅ Successfully wrote ${matched.length} tasks!`);
            } catch (err) {
                console.log(`❌ Batch write FAILED: ${err.message}`);
            }
            // Verify
            const verifySnap = await db.collection("users").doc(userId).collection("tasks").get();
            console.log(`\n🔍 Verification: ${verifySnap.size} tasks now in Firestore`);
        } else if (existingTasks.size > 0) {
            console.log(`\n⏭️ Skipping write — user already has ${existingTasks.size} tasks`);
        } else {
            console.log(`\n⚠️ No tasks matched — this shouldn't happen with 6 unconditional tasks!`);
        }
    }
}
main().then(() => {
    console.log("\n✅ Done");
    process.exit(0);
}).catch(err => {
    console.error("❌ Fatal:", err);
    process.exit(1);
});
