const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const twilio = require("twilio");

if (!admin.apps.length) {
  admin.initializeApp();
}

const FLAG_LABELS = Object.freeze({
  late_arrival: "did not arrive in the window",
  unsteady_crew: "crew did not work steadily",
  charged_more_than_quoted: "charged more than quoted",
  damage: "damage reported"
});

function buildFlags(answers) {
  const flags = [];
  if (answers.arrivedInWindow === false) flags.push("late_arrival");
  if (answers.crewWorkedSteadily === false) flags.push("unsteady_crew");
  if (answers.costMoreThanQuoted === true) flags.push("charged_more_than_quoted");
  if (answers.damaged === true) flags.push("damage");
  return flags;
}

function flagMessage(vendorName, flag) {
  return `PEEZY FLAG: ${vendorName} — ${FLAG_LABELS[flag]}.`;
}

function cleanAnswers(raw) {
  const required = [
    "arrivedInWindow",
    "crewWorkedSteadily",
    "costMoreThanQuoted",
    "damaged"
  ];
  if (!raw || typeof raw !== "object" ||
      required.some((key) => typeof raw[key] !== "boolean")) {
    throw new HttpsError("invalid-argument", "All four factual answers are required");
  }
  return {
    arrivedInWindow: raw.arrivedInWindow,
    crewWorkedSteadily: raw.crewWorkedSteadily,
    costMoreThanQuoted: raw.costMoreThanQuoted,
    damaged: raw.damaged,
    note: typeof raw.note === "string" ? raw.note.trim().slice(0, 2000) : ""
  };
}

function answerMap(storedAnswers) {
  if (storedAnswers?.answers && typeof storedAnswers.answers === "object") {
    return storedAnswers.answers;
  }
  return storedAnswers && typeof storedAnswers === "object" ? storedAnswers : {};
}

function parsedVendor(storedAnswers) {
  const encoded = answerMap(storedAnswers).chosen_vendor;
  if (!Array.isArray(encoded) || typeof encoded[0] !== "string") return null;
  try {
    const vendor = JSON.parse(encoded[0]);
    const vendorId = typeof vendor?.vendorId === "string" ? vendor.vendorId.trim() : "";
    const name = typeof vendor?.name === "string" ? vendor.name.trim() : "";
    return vendorId && name ? { vendorId, name } : null;
  } catch {
    return null;
  }
}

async function bookedVendor(db, userId) {
  const snapshot = await db.collection("users").doc(userId)
    .collection("workflowResponses").doc("book_movers")
    .get();
  return snapshot.exists ? parsedVendor(snapshot.get("answers")) : null;
}

async function notifyFlags(vendorName, flags) {
  if (flags.length === 0) return;

  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const authToken = process.env.TWILIO_AUTH_TOKEN;
  const fromNumber = process.env.TWILIO_FROM_NUMBER;
  const notifyNumber = process.env.ADAM_NOTIFY_NUMBER;

  if (!accountSid || !authToken || !fromNumber || !notifyNumber ||
      accountSid === "placeholder_will_set_later") {
    console.warn("SMS notify not configured");
    return;
  }

  try {
    const client = twilio(accountSid, authToken);
    for (const flag of flags) {
      await client.messages.create({
        body: flagMessage(vendorName, flag),
        from: fromNumber,
        to: notifyNumber
      });
    }
    console.log(`Check-in flag SMS sent (${flags.length})`);
  } catch (error) {
    console.error("SMS notify failed:", error.message);
  }
}

const submitCheckIn = onCall(
  { region: "us-central1", timeoutSeconds: 15, memory: "256MiB" },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "Sign in before submitting a check-in");
    }

    const answers = cleanAnswers(request.data?.answers);
    const db = admin.firestore();
    const vendor = await bookedVendor(db, userId);
    const flags = buildFlags(answers);
    const reviewRef = db.collection("vendorReviews").doc();

    await reviewRef.set({
      vendorId: vendor?.vendorId ?? null,
      userId,
      answers,
      flags,
      submittedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    await notifyFlags(vendor?.name ?? "General move", flags);

    return {
      success: true,
      reviewId: reviewRef.id,
      vendorId: vendor?.vendorId ?? null,
      flags
    };
  }
);

module.exports = {
  submitCheckIn,
  buildFlags,
  flagMessage,
  parsedVendor,
  FLAG_LABELS
};
