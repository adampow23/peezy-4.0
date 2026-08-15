"use strict";

/**
 * validateSubscription Cloud Function
 *
 * Thin Firebase I/O wrapper around the pure subscription decision core.
 */

const crypto = require("node:crypto");
const { onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {
  PRODUCT_PERIODS,
  SERVER_TIMESTAMP,
  decide,
  parseInput,
  reject
} = require("./subscriptionDecision");

const LOG_IDENTIFIER_PATTERN = /^[A-Za-z0-9._-]{1,128}$/;

function isAuthUserNotFound(error) {
  return error?.code === "auth/user-not-found";
}

function replaceServerTimestamps(value, serverTimestamp) {
  if (value === SERVER_TIMESTAMP) {
    return serverTimestamp;
  }
  if (Array.isArray(value)) {
    return value.map((item) => replaceServerTimestamps(item, serverTimestamp));
  }
  if (
    value &&
    typeof value === "object" &&
    Object.getPrototypeOf(value) === Object.prototype
  ) {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [
      key,
      replaceServerTimestamps(item, serverTimestamp)
    ]));
  }
  return value;
}

function logFields(decision, body, input) {
  const rawOriginalTransactionId = input?.originalTransactionId ?? body?.originalTransactionId;
  const originalTransactionId = (
    typeof rawOriginalTransactionId === "string" &&
    LOG_IDENTIFIER_PATTERN.test(rawOriginalTransactionId)
  )
    ? rawOriginalTransactionId
    : null;
  const rawUid = input?.userId ?? body?.userId;
  const rawProductId = input?.productId ?? body?.productId;
  const entry = {
    event: "validateSubscription",
    outcome: decision.outcome,
    reason: decision.reason,
    uid: typeof rawUid === "string" && LOG_IDENTIFIER_PATTERN.test(rawUid)
      ? rawUid
      : null,
    otxHash: originalTransactionId == null
      ? null
      : crypto.createHash("sha256").update(originalTransactionId).digest("hex").slice(0, 8),
    productId: typeof rawProductId === "string" && Object.hasOwn(PRODUCT_PERIODS, rawProductId)
      ? rawProductId
      : null
  };
  if (decision.flags?.length) {
    entry.flags = decision.flags.slice(0, 4);
  }
  return entry;
}

function createValidationHandler(dependencies = {}) {
  const nowProvider = dependencies.now || (() => new Date());
  const serverTimestampProvider = dependencies.serverTimestamp || (
    () => admin.firestore.FieldValue.serverTimestamp()
  );
  const logger = dependencies.logger || ((entry) => console.log(JSON.stringify(entry)));

  async function runDecisionTransaction(input, now, verifiedDeletedOwnerUid = null) {
    const db = dependencies.db || admin.firestore();
    const bindingRef = db.collection("subscriptions").doc(input.originalTransactionId);
    const userRef = db.collection("users").doc(input.userId);

    return db.runTransaction(async (transaction) => {
      const [bindingSnapshot, userSnapshot] = await Promise.all([
        transaction.get(bindingRef),
        transaction.get(userRef)
      ]);
      const binding = bindingSnapshot.exists ? bindingSnapshot.data() : null;
      const userSubscription = userSnapshot.exists
        ? userSnapshot.data()?.subscription || null
        : null;

      let bindingCount = 0;
      if (!binding && !verifiedDeletedOwnerUid) {
        const countQuery = db.collection("subscriptions")
          .where("userId", "==", input.userId)
          .count();
        const countSnapshot = await transaction.get(countQuery);
        bindingCount = Number(countSnapshot.data().count || 0);
      }

      const decision = decide(input, {
        now,
        binding,
        userSubscription,
        bindingCount,
        boundOwnerExists: verifiedDeletedOwnerUid ? false : null,
        verifiedDeletedOwnerUid
      });

      const timestamp = decision.writes.length > 0
        ? serverTimestampProvider()
        : null;
      for (const write of decision.writes) {
        const reference = write.target === "binding" ? bindingRef : userRef;
        transaction.set(
          reference,
          replaceServerTimestamps(write.data, timestamp),
          write.options
        );
      }
      return decision;
    });
  }

  return async (req, res) => {
    const rawBody = req.body;
    let input = null;

    function finish(decision) {
      logger(logFields(decision, rawBody, input));
      res.status(decision.statusCode).json(decision.body);
    }

    if (req.method !== "POST") {
      finish({
        ...reject(400, "invalid_input"),
        statusCode: 405,
        body: { error: "Method not allowed" }
      });
      return;
    }

    const now = nowProvider();
    const parsed = parseInput(rawBody, now);
    if (!parsed.ok) {
      finish(parsed.decision);
      return;
    }
    input = parsed.input;
    const auth = dependencies.auth || admin.auth();

    try {
      await auth.getUser(input.userId);
    } catch (error) {
      finish(isAuthUserNotFound(error)
        ? reject(404, "unknown_user")
        : reject(500, "auth_error"));
      return;
    }

    let decision;
    try {
      decision = await runDecisionTransaction(input, now);
      if (decision.ownerCheckUid) {
        try {
          await auth.getUser(decision.ownerCheckUid);
        } catch (error) {
          if (!isAuthUserNotFound(error)) {
            finish(reject(500, "auth_error"));
            return;
          }
          decision = await runDecisionTransaction(input, now, decision.ownerCheckUid);
        }
      }
    } catch (_error) {
      finish(reject(500, "auth_error"));
      return;
    }

    finish(decision);
  };
}

const validateSubscription = onRequest(
  {
    timeoutSeconds: 15,
    memory: "256MiB",
    cors: true
  },
  createValidationHandler()
);

module.exports = {
  createValidationHandler,
  validateSubscription
};
