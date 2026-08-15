"use strict";

const IDENTIFIER_PATTERN = /^[A-Za-z0-9._-]{1,128}$/;
const ISO_8601_PATTERN = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/;
const FIVE_MINUTES_MS = 5 * 60 * 1000;
const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const PRODUCT_PERIODS = Object.freeze({
  "peezy.plus.move": { months: 6 },
  "peezy.plus.weekly": { milliseconds: WEEK_MS },
  "peezy.plus.annual": { months: 12 }
});
const FLAG_ORDER = Object.freeze([
  "product_mismatch",
  "binding_cap_alert",
  "legacy_repaired",
  "gift_extended"
]);
const REASON_ORDER = Object.freeze([
  "rebound_after_deletion",
  "gift_preserved",
  "skipped_downgrade",
  "replayed_transaction",
  "renewed",
  "created",
  "refreshed"
]);
const SERVER_TIMESTAMP = Object.freeze({ __peezyServerTimestamp: true });

function parseIso8601(value) {
  if (typeof value !== "string") {
    return null;
  }
  const match = ISO_8601_PATTERN.exec(value);
  if (!match) {
    return null;
  }

  const [, yearText, monthText, dayText, hourText, minuteText, secondText] = match;
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  const hour = Number(hourText);
  const minute = Number(minuteText);
  const second = Number(secondText);
  if (month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) {
    return null;
  }
  const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
  if (day < 1 || day > lastDay) {
    return null;
  }

  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function parseStoredDate(value) {
  let parsed;
  if (value instanceof Date) {
    parsed = new Date(value.getTime());
  } else if (value && typeof value.toDate === "function") {
    parsed = value.toDate();
  } else if (typeof value === "string" || typeof value === "number") {
    parsed = new Date(value);
  } else {
    return null;
  }
  return parsed instanceof Date && !Number.isNaN(parsed.getTime()) ? parsed : null;
}

function addCalendarMonths(date, monthCount) {
  const result = new Date(date.getTime());
  const originalDay = result.getUTCDate();
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() + monthCount);

  const lastDayOfTargetMonth = new Date(Date.UTC(
    result.getUTCFullYear(),
    result.getUTCMonth() + 1,
    0
  )).getUTCDate();
  result.setUTCDate(Math.min(originalDay, lastDayOfTargetMonth));
  return result;
}

function computeExpiration(productId, purchaseDate) {
  const period = PRODUCT_PERIODS[productId];
  if (!period || !(purchaseDate instanceof Date) || Number.isNaN(purchaseDate.getTime())) {
    return null;
  }
  if (period.months) {
    return addCalendarMonths(purchaseDate, period.months);
  }
  return new Date(purchaseDate.getTime() + period.milliseconds);
}

function errorMessage(reason) {
  switch (reason) {
    case "invalid_input":
      return "Invalid input";
    case "invalid_product":
      return "Invalid product";
    case "invalid_purchase_date":
    case "future_purchase_date":
    case "legacy_repair_failed":
      return "Invalid purchase date";
    case "binding_conflict":
      return "Transaction belongs to another user";
    case "unknown_user":
      return "Unknown user";
    default:
      return "Sync failed";
  }
}

function reject(statusCode, reason, extra = {}) {
  return {
    statusCode,
    outcome: "rejected",
    reason,
    flags: [],
    writes: [],
    body: { error: errorMessage(reason) },
    ...extra
  };
}

function parseInput(body, now) {
  const fixedNow = now instanceof Date ? now : new Date(now);
  if (
    body == null ||
    typeof body !== "object" ||
    Array.isArray(body) ||
    Number.isNaN(fixedNow.getTime())
  ) {
    return { ok: false, decision: reject(400, "invalid_input") };
  }

  for (const field of ["userId", "originalTransactionId", "transactionId"]) {
    if (typeof body[field] !== "string" || !IDENTIFIER_PATTERN.test(body[field])) {
      return { ok: false, decision: reject(400, "invalid_input") };
    }
  }
  if (!Object.hasOwn(PRODUCT_PERIODS, body.productId)) {
    return { ok: false, decision: reject(400, "invalid_product") };
  }

  const purchaseDateDate = parseIso8601(body.purchaseDate);
  if (!purchaseDateDate) {
    return { ok: false, decision: reject(400, "invalid_purchase_date") };
  }
  if (purchaseDateDate.getTime() > fixedNow.getTime() + FIVE_MINUTES_MS) {
    return { ok: false, decision: reject(400, "future_purchase_date") };
  }

  return {
    ok: true,
    input: {
      userId: body.userId,
      productId: body.productId,
      originalTransactionId: body.originalTransactionId,
      transactionId: body.transactionId,
      purchaseDate: purchaseDateDate.toISOString(),
      purchaseDateDate,
      environment: typeof body.environment === "string"
        ? body.environment.slice(0, 32)
        : "",
      isUpgraded: Boolean(body.isUpgraded)
    }
  };
}

function boundedFlags(observations) {
  return FLAG_ORDER.filter((flag) => observations.has(flag)).slice(0, 4);
}

function primaryReason(observations) {
  return REASON_ORDER.find((reason) => observations.has(reason)) || "refreshed";
}

function success({ writes, observations, responseProductId, responseExpiration, now }) {
  const flags = boundedFlags(observations);
  return {
    statusCode: 200,
    outcome: writes.length === 0 ? "noop" : "synced",
    reason: primaryReason(observations),
    flags,
    writes,
    body: {
      success: true,
      subscription: {
        productId: responseProductId,
        expirationDate: responseExpiration.toISOString(),
        isActive: responseExpiration.getTime() > now.getTime()
      }
    }
  };
}

function bindingData(input, productId, purchaseDate, expirationDate, isNew, now) {
  const data = {
    userId: input.userId,
    productId,
    originalTransactionId: input.originalTransactionId,
    transactionId: input.transactionId,
    purchaseDate: purchaseDate.toISOString(),
    expirationDate: expirationDate.toISOString(),
    environment: input.environment,
    isUpgraded: input.isUpgraded,
    status: expirationDate.getTime() > now.getTime() ? "active" : "expired",
    updatedAt: SERVER_TIMESTAMP
  };
  if (isNew) {
    data.createdAt = SERVER_TIMESTAMP;
  }
  return data;
}

function userSubscriptionData(input, productId, purchaseDate, expirationDate, now) {
  return {
    productId,
    originalTransactionId: input.originalTransactionId,
    transactionId: input.transactionId,
    purchaseDate: purchaseDate.toISOString(),
    expirationDate: expirationDate.toISOString(),
    environment: input.environment,
    isUpgraded: input.isUpgraded,
    isActive: expirationDate.getTime() > now.getTime(),
    updatedAt: SERVER_TIMESTAMP
  };
}

function addEntitlementWrite({
  writes,
  observations,
  userSubscription,
  input,
  productId,
  purchaseDate,
  expirationDate,
  now
}) {
  const existingExpiration = parseStoredDate(userSubscription?.expirationDate);

  if (userSubscription?.source === "giftCode") {
    observations.add("gift_preserved");
    if (!existingExpiration || expirationDate.getTime() > existingExpiration.getTime()) {
      observations.add("gift_extended");
      writes.push({
        target: "user",
        type: "set",
        data: {
          subscription: {
            ...userSubscription,
            expirationDate: expirationDate.toISOString(),
            updatedAt: SERVER_TIMESTAMP
          }
        },
        options: { merge: true }
      });
      return {
        productId: userSubscription.productId || productId,
        expirationDate
      };
    }
    return {
      productId: userSubscription.productId || productId,
      expirationDate: existingExpiration
    };
  }

  if (existingExpiration && existingExpiration.getTime() > expirationDate.getTime()) {
    observations.add("skipped_downgrade");
    return {
      productId: userSubscription.productId || productId,
      expirationDate: existingExpiration
    };
  }

  writes.push({
    target: "user",
    type: "set",
    data: {
      subscription: userSubscriptionData(
        input,
        productId,
        purchaseDate,
        expirationDate,
        now
      )
    },
    options: { merge: true }
  });
  return { productId, expirationDate };
}

function decide(input, ctx) {
  const now = ctx?.now instanceof Date ? ctx.now : new Date(ctx?.now);
  const binding = ctx?.binding || null;
  const userSubscription = ctx?.userSubscription || null;
  const verifiedDeletedOwnerUid = ctx?.verifiedDeletedOwnerUid || null;

  if (Number.isNaN(now.getTime())) {
    return reject(500, "auth_error");
  }

  if (verifiedDeletedOwnerUid && binding?.userId !== verifiedDeletedOwnerUid) {
    return reject(500, "auth_error");
  }

  const incomingPurchaseDate = input?.purchaseDateDate instanceof Date
    ? new Date(input.purchaseDateDate.getTime())
    : parseIso8601(input?.purchaseDate);

  if (binding && binding.userId !== input.userId) {
    if (
      ctx.boundOwnerExists === false &&
      verifiedDeletedOwnerUid === binding.userId
    ) {
      if (!incomingPurchaseDate) {
        return reject(400, "invalid_purchase_date");
      }
      const expirationDate = computeExpiration(input.productId, incomingPurchaseDate);
      const observations = new Set(["rebound_after_deletion"]);
      const writes = [{
        target: "binding",
        type: "set",
        data: bindingData(input, input.productId, incomingPurchaseDate, expirationDate, false, now),
        options: { merge: true }
      }];
      const effective = addEntitlementWrite({
        writes,
        observations,
        userSubscription,
        input,
        productId: input.productId,
        purchaseDate: incomingPurchaseDate,
        expirationDate,
        now
      });
      return success({
        writes,
        observations,
        responseProductId: effective.productId,
        responseExpiration: effective.expirationDate,
        now
      });
    }
    return reject(403, "binding_conflict", {
      ownerCheckUid: ctx.boundOwnerExists == null ? binding.userId : undefined
    });
  }

  const observations = new Set();
  const writes = [];
  let productId = input.productId;
  let purchaseDate = incomingPurchaseDate;
  const isNewBinding = binding == null;

  if (isNewBinding) {
    if (!purchaseDate) {
      return reject(400, "invalid_purchase_date");
    }
    observations.add("created");
    if (Number(ctx?.bindingCount || 0) >= 100) {
      observations.add("binding_cap_alert");
    }
  } else {
    const storedPurchaseDate = parseStoredDate(binding.purchaseDate);
    const storedProductAllowed = Object.hasOwn(PRODUCT_PERIODS, binding.productId);
    const sameTransaction = binding.transactionId === input.transactionId;

    if (!storedPurchaseDate) {
      if (!purchaseDate) {
        return reject(400, "legacy_repair_failed");
      }
      observations.add("legacy_repaired");
      if (sameTransaction) {
        productId = storedProductAllowed ? binding.productId : input.productId;
        observations.add("refreshed");
        if (storedProductAllowed && input.productId !== binding.productId) {
          observations.add("product_mismatch");
        }
      } else {
        observations.add("renewed");
      }
    } else if (sameTransaction) {
      if (!storedProductAllowed) {
        return reject(400, "legacy_repair_failed");
      }
      productId = binding.productId;
      purchaseDate = storedPurchaseDate;
      observations.add("refreshed");
      if (input.productId !== binding.productId) {
        observations.add("product_mismatch");
      }
    } else if (!purchaseDate) {
      return reject(400, "invalid_purchase_date");
    } else if (purchaseDate.getTime() <= storedPurchaseDate.getTime()) {
      productId = storedProductAllowed ? binding.productId : input.productId;
      purchaseDate = storedPurchaseDate;
      const expirationDate = computeExpiration(productId, purchaseDate);
      if (!expirationDate) {
        return reject(400, "legacy_repair_failed");
      }
      observations.add("replayed_transaction");

      let responseProductId = productId;
      let responseExpiration = expirationDate;
      const existingExpiration = parseStoredDate(userSubscription?.expirationDate);
      if (userSubscription?.source === "giftCode") {
        observations.add("gift_preserved");
        responseProductId = userSubscription.productId || productId;
        if (!existingExpiration || expirationDate.getTime() > existingExpiration.getTime()) {
          observations.add("gift_extended");
          writes.push({
            target: "user",
            type: "set",
            data: {
              subscription: {
                ...userSubscription,
                expirationDate: expirationDate.toISOString(),
                updatedAt: SERVER_TIMESTAMP
              }
            },
            options: { merge: true }
          });
        } else {
          responseExpiration = existingExpiration;
        }
      } else if (existingExpiration && existingExpiration.getTime() > expirationDate.getTime()) {
        observations.add("skipped_downgrade");
        responseProductId = userSubscription.productId || productId;
        responseExpiration = existingExpiration;
      }

      return success({
        writes,
        observations,
        responseProductId,
        responseExpiration,
        now
      });
    } else {
      observations.add("renewed");
    }
  }

  const expirationDate = computeExpiration(productId, purchaseDate);
  if (!expirationDate) {
    return reject(400, "legacy_repair_failed");
  }

  const bindingWrite = bindingData(input, productId, purchaseDate, expirationDate, isNewBinding, now);
  if (!isNewBinding && observations.has("refreshed")) {
    bindingWrite.transactionId = binding.transactionId;
  }
  writes.push({
    target: "binding",
    type: "set",
    data: bindingWrite,
    options: { merge: true }
  });

  const effective = addEntitlementWrite({
    writes,
    observations,
    userSubscription,
    input,
    productId,
    purchaseDate,
    expirationDate,
    now
  });

  return success({
    writes,
    observations,
    responseProductId: effective.productId,
    responseExpiration: effective.expirationDate,
    now
  });
}

module.exports = {
  PRODUCT_PERIODS,
  SERVER_TIMESTAMP,
  addCalendarMonths,
  computeExpiration,
  decide,
  parseInput,
  parseStoredDate,
  reject
};
