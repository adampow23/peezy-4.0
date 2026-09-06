const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const twilio = require("twilio");
const logger = require('firebase-functions/logger');
const { Timestamp } = require("firebase-admin/firestore");
const { withOutboundLease } = require("./accountDeletionFence");
const {
  buildFlags,
  calibrationRecord,
  CheckInValidationError,
  cleanAnswers,
  flagMessage,
  parsedBookingContext,
  writeReviewAndAccountability
} = require("./submitCheckInCore");

if (!admin.apps.length) {
  admin.initializeApp();
}

async function bookedMoveContext(db, userId) {
  const snapshot = await db.collection("users").doc(userId)
    .collection("workflowResponses").doc("book_movers")
    .get();
  return snapshot.exists ? parsedBookingContext(snapshot.get("answers")) : null;
}

async function notifyFlags(db, userId, vendorName, flags) {
  if (flags.length === 0) return;

  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const authToken = process.env.TWILIO_AUTH_TOKEN;
  const fromNumber = process.env.TWILIO_FROM_NUMBER;
  const notifyNumber = process.env.ADAM_NOTIFY_NUMBER;

  if (!accountSid || !authToken || !fromNumber || !notifyNumber ||
      accountSid === "placeholder_will_set_later") {
    logger.warn("CHECKIN_SMS_NOT_CONFIGURED");
    return;
  }

  try {
    const client = twilio(accountSid, authToken);
    const leaseDeps = { db, now: () => Timestamp.fromMillis(Date.now()) };
    for (const flag of flags) {
      // C6.2: one check-in SMS per flag, each under its own checkin_sms outbound lease.
      await withOutboundLease(leaseDeps, { uid: userId, channel: "checkin_sms" }, () => client.messages.create({
        body: flagMessage(vendorName, flag),
        from: fromNumber,
        to: notifyNumber
      }));
    }
    logger.info("CHECKIN_SMS_SENT", { count: flags.length });
  } catch (error) {
    logger.warn("CHECKIN_SMS_FAILED");
  }
}

const submitCheckIn = onCall(
  { region: "us-central1", timeoutSeconds: 15, memory: "256MiB" },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "Sign in before submitting a check-in");
    }

    let answers;
    try {
      answers = cleanAnswers(request.data?.answers);
    } catch (error) {
      if (error instanceof CheckInValidationError) {
        throw new HttpsError("invalid-argument", error.message);
      }
      throw error;
    }

    const db = admin.firestore();
    const bookingContext = await bookedMoveContext(db, userId);
    const vendor = bookingContext?.vendor ?? null;
    if (!bookingContext) delete answers.finalBill;

    const flags = buildFlags(answers);
    const reviewRef = db.collection("vendorReviews").doc();
    const submittedAt = admin.firestore.FieldValue.serverTimestamp();
    const review = {
      vendorId: vendor?.vendorId ?? null,
      userId,
      answers,
      flags,
      submittedAt
    };
    const calibration = calibrationRecord({
      reviewId: reviewRef.id,
      userId,
      bookingContext,
      answers,
      submittedAt
    });
    const calibrationRef = calibration
      ? db.collection("estimateCalibration").doc()
      : null;

    await writeReviewAndAccountability(
      db,
      reviewRef,
      calibrationRef,
      vendor,
      review,
      calibration,
      admin.firestore.Timestamp.now()
    );

    await notifyFlags(db, userId, vendor?.name ?? "General move", flags);

    return {
      success: true,
      reviewId: reviewRef.id,
      calibrationId: calibrationRef?.id ?? null,
      vendorId: vendor?.vendorId ?? null,
      flags
    };
  }
);

module.exports = {
  submitCheckIn,
  bookedMoveContext
};
