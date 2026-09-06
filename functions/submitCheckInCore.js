const {
  accountabilityTransition,
  normalizeStrikes,
  pendingStrikesForFlags
} = require("./accountabilityLadder");
const { assertDeletionAbsent } = require("./accountDeletionFence");

const FLAG_LABELS = Object.freeze({
  late_arrival: "did not arrive in the window",
  unsteady_crew: "crew did not work steadily",
  charged_more_than_quoted: "charged more than quoted",
  damage: "damage reported"
});

class CheckInValidationError extends Error {}

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
    throw new CheckInValidationError("All four factual answers are required");
  }

  const answers = {
    arrivedInWindow: raw.arrivedInWindow,
    crewWorkedSteadily: raw.crewWorkedSteadily,
    costMoreThanQuoted: raw.costMoreThanQuoted,
    damaged: raw.damaged,
    note: typeof raw.note === "string" ? raw.note.trim().slice(0, 2000) : ""
  };

  if (Object.hasOwn(raw, "finalBill")) {
    if (typeof raw.finalBill !== "number" ||
        !Number.isFinite(raw.finalBill) || raw.finalBill <= 0) {
      throw new CheckInValidationError("Final bill must be a positive number");
    }
    answers.finalBill = raw.finalBill;
  }

  return answers;
}

function answerMap(storedAnswers) {
  if (storedAnswers?.answers && typeof storedAnswers.answers === "object") {
    return storedAnswers.answers;
  }
  return storedAnswers && typeof storedAnswers === "object" ? storedAnswers : {};
}

function firstAnswer(storedAnswers, key) {
  const value = answerMap(storedAnswers)[key];
  return Array.isArray(value) && typeof value[0] === "string" ? value[0] : null;
}

function parsedAnswerObject(storedAnswers, key) {
  const encoded = firstAnswer(storedAnswers, key);
  if (!encoded) return null;
  try {
    const value = JSON.parse(encoded);
    return value && typeof value === "object" && !Array.isArray(value) ? value : null;
  } catch {
    return null;
  }
}

function parsedVendor(storedAnswers) {
  const vendor = parsedAnswerObject(storedAnswers, "chosen_vendor");
  const vendorId = typeof vendor?.vendorId === "string" ? vendor.vendorId.trim() : "";
  const name = typeof vendor?.name === "string" ? vendor.name.trim() : "";
  return vendorId && name ? { vendorId, name } : null;
}

function parsedBookingContext(storedAnswers) {
  if (firstAnswer(storedAnswers, "quoteRequest") !== "false") return null;

  const vendor = parsedVendor(storedAnswers);
  const estimate = parsedAnswerObject(storedAnswers, "estimate");
  const scope = parsedAnswerObject(storedAnswers, "scope");
  const low = estimate?.low;
  const high = estimate?.high;
  const cubicFeet = scope?.cubicFeet;
  const driveMinutes = scope?.driveMinutes;

  if (!vendor ||
      typeof low !== "number" || !Number.isFinite(low) || low < 0 ||
      typeof high !== "number" || !Number.isFinite(high) || high < low ||
      !scope || Object.keys(scope).length === 0 ||
      typeof cubicFeet !== "number" || !Number.isFinite(cubicFeet) || cubicFeet < 0 ||
      typeof driveMinutes !== "number" || !Number.isFinite(driveMinutes) || driveMinutes < 0) {
    return null;
  }

  return {
    vendor,
    estimatedRange: { low, high },
    scopeSnapshot: scope
  };
}

function calibrationRecord({
  reviewId,
  userId,
  bookingContext,
  answers,
  submittedAt
}) {
  if (!bookingContext || typeof answers?.finalBill !== "number" ||
      !Number.isFinite(answers.finalBill) || answers.finalBill <= 0) {
    return null;
  }

  return {
    reviewId,
    userId,
    vendorId: bookingContext.vendor.vendorId,
    estimatedRange: bookingContext.estimatedRange,
    finalBill: answers.finalBill,
    scopeSnapshot: bookingContext.scopeSnapshot,
    submittedAt
  };
}

async function writeReviewAndAccountability(
  db,
  reviewRef,
  calibrationRef,
  vendor,
  review,
  calibration,
  strikeTimestamp = new Date()
) {
  const vendorRef = vendor
    ? db.collection("vendors").doc(vendor.vendorId)
    : null;

  await db.runTransaction(async (transaction) => {
    const vendorSnapshot = vendorRef ? await transaction.get(vendorRef) : null;
    // C6.1 root fence: the committing transaction reads the review owner's root and requires accountDeletion absent.
    await assertDeletionAbsent(transaction, db, [review.userId]);

    transaction.set(reviewRef, review);
    if (calibrationRef && calibration) {
      transaction.set(calibrationRef, calibration);
    }

    if (!vendorSnapshot?.exists) return;

    const vendorData = vendorSnapshot.data();
    const existingStrikes = vendorData.accountability?.strikes;
    const additions = pendingStrikesForFlags(
      review.flags,
      reviewRef.id,
      strikeTimestamp
    );
    const transition = accountabilityTransition(
      [...normalizeStrikes(existingStrikes), ...additions],
      vendorData.active !== false
    );

    transaction.update(vendorRef, {
      "accountability.strikes": transition.strikes,
      active: transition.active
    });
  });
}

module.exports = {
  buildFlags,
  calibrationRecord,
  CheckInValidationError,
  cleanAnswers,
  flagMessage,
  parsedBookingContext,
  parsedVendor,
  writeReviewAndAccountability,
  FLAG_LABELS
};
