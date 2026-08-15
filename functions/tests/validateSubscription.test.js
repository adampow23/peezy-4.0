"use strict";

const assert = require("node:assert/strict");
const Module = require("node:module");
const test = require("node:test");

const {
  SERVER_TIMESTAMP,
  decide,
  parseInput
} = require("../subscriptionDecision");

// Loading the wrapper must not initialize Firebase or discover credentials.
// Stub only the two Firebase module boundaries, then exercise all wrapper I/O
// through createValidationHandler's injected Firestore/Auth dependencies.
const originalModuleLoad = Module._load;
Module._load = function loadWithFirebaseStubs(request, parent, isMain) {
  if (request === "firebase-functions/v2/https") {
    return { onRequest: (_options, handler) => handler };
  }
  if (request === "firebase-admin") {
    return {
      auth: () => { throw new Error("Firebase Auth was not injected"); },
      firestore: () => { throw new Error("Firestore was not injected"); }
    };
  }
  return originalModuleLoad.call(this, request, parent, isMain);
};
const { createValidationHandler } = require("../validateSubscription");
Module._load = originalModuleLoad;

const NOW = new Date("2026-08-15T12:00:00.000Z");

function requestBody(overrides = {}) {
  return {
    userId: "user_123",
    productId: "peezy.plus.move",
    originalTransactionId: "original.123",
    transactionId: "transaction.123",
    purchaseDate: "2026-08-15T11:00:00.000Z",
    expirationDate: "2099-01-01T00:00:00.000Z",
    environment: "Sandbox",
    isUpgraded: false,
    ...overrides
  };
}

function parsedInput(overrides = {}, now = NOW) {
  const parsed = parseInput(requestBody(overrides), now);
  assert.equal(parsed.ok, true, JSON.stringify(parsed.decision));
  return parsed.input;
}

function decideRequest(overrides = {}, state = {}, now = NOW) {
  const parsed = parseInput(requestBody(overrides), now);
  if (!parsed.ok) {
    return parsed.decision;
  }
  return decide(parsed.input, {
    now,
    binding: null,
    userSubscription: null,
    bindingCount: 0,
    boundOwnerExists: null,
    verifiedDeletedOwnerUid: null,
    ...state
  });
}

function binding(overrides = {}) {
  return {
    userId: "user_123",
    productId: "peezy.plus.move",
    originalTransactionId: "original.123",
    transactionId: "transaction.123",
    purchaseDate: "2026-08-15T11:00:00.000Z",
    expirationDate: "2027-02-15T11:00:00.000Z",
    environment: "Sandbox",
    isUpgraded: false,
    status: "active",
    ...overrides
  };
}

function writeFor(decision, target) {
  return decision.writes.find((write) => write.target === target);
}

function authError(code) {
  return Object.assign(new Error(code), { code });
}

function fakeAuth(behaviors = {}) {
  const calls = [];
  return {
    calls,
    async getUser(uid) {
      calls.push(uid);
      const behavior = behaviors[uid];
      if (behavior instanceof Error) {
        throw behavior;
      }
      return behavior ?? { uid };
    }
  };
}

function fakeDb({
  bindingDoc = null,
  userSubscription = null,
  bindingCount = 0,
  attempts = 1,
  beforeAttempt = null
} = {}) {
  const transactions = [];

  function snapshot(data) {
    return {
      exists: data != null,
      data: () => data
    };
  }

  function collection(name) {
    return {
      doc(id) {
        return { kind: "doc", path: `${name}/${id}` };
      },
      where(field, operator, value) {
        assert.equal(name, "subscriptions");
        assert.equal(field, "userId");
        assert.equal(operator, "==");
        return {
          count() {
            return { kind: "count", value };
          }
        };
      }
    };
  }

  return {
    transactions,
    collection,
    async runTransaction(callback) {
      let result;
      for (let index = 0; index < attempts; index += 1) {
        if (beforeAttempt) {
          beforeAttempt(index);
        }
        const writes = [];
        const reads = [];
        const attemptNumber = transactions.length;
        const transaction = {
          writes,
          reads,
          async get(reference) {
            reads.push(reference);
            if (reference.kind === "count") {
              return { data: () => ({ count: bindingCount }) };
            }
            if (reference.path.startsWith("subscriptions/")) {
              return snapshot(typeof bindingDoc === "function"
                ? bindingDoc(attemptNumber)
                : bindingDoc);
            }
            if (reference.path.startsWith("users/")) {
              return snapshot(userSubscription == null
                ? null
                : { subscription: userSubscription });
            }
            throw new Error(`Unexpected read: ${reference.path}`);
          },
          set(reference, data, options) {
            writes.push({ type: "set", path: reference.path, data, options });
          }
        };
        transactions.push(transaction);
        result = await callback(transaction);
      }
      return result;
    }
  };
}

function fakeResponse() {
  return {
    statusCode: null,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    }
  };
}

async function invoke({
  body = requestBody(),
  method = "POST",
  db = fakeDb(),
  auth = fakeAuth(),
  logger = () => {}
} = {}) {
  const handler = createValidationHandler({
    auth,
    db,
    now: () => new Date(NOW),
    serverTimestamp: () => "SERVER_TIMESTAMP",
    logger
  });
  const response = fakeResponse();
  await handler({ method, body }, response);
  return { response, db, auth };
}

test("1. non-allowlisted productId rejects with zero writes", () => {
  const decision = decideRequest({ productId: "peezy.plus.fake" });
  assert.equal(decision.statusCode, 400);
  assert.equal(decision.reason, "invalid_product");
  assert.deepEqual(decision.writes, []);
});

test("2. unparseable and more-than-five-minutes-future purchase dates reject", () => {
  const invalid = decideRequest({ purchaseDate: "August-ish" });
  assert.equal(invalid.statusCode, 400);
  assert.equal(invalid.reason, "invalid_purchase_date");
  assert.deepEqual(invalid.writes, []);

  const boundary = decideRequest({ purchaseDate: "2026-08-15T12:05:00.000Z" });
  assert.equal(boundary.statusCode, 200);

  const future = decideRequest({ purchaseDate: "2026-08-15T12:05:00.001Z" });
  assert.equal(future.statusCode, 400);
  assert.equal(future.reason, "future_purchase_date");
  assert.deepEqual(future.writes, []);
});

test("3. months-old first sync is accepted with calendar expiry and current activity", () => {
  const decision = decideRequest({
    productId: "peezy.plus.annual",
    purchaseDate: "2026-02-01T09:30:00.000Z"
  });
  assert.equal(decision.statusCode, 200);
  assert.equal(decision.reason, "created");
  assert.equal(decision.body.subscription.expirationDate, "2027-02-01T09:30:00.000Z");
  assert.equal(decision.body.subscription.isActive, true);
});

test("4. a binding held by a different existing uid rejects with zero writes", () => {
  const decision = decideRequest({}, {
    binding: binding({ userId: "other_user" }),
    boundOwnerExists: true
  });
  assert.equal(decision.statusCode, 403);
  assert.equal(decision.reason, "binding_conflict");
  assert.deepEqual(decision.writes, []);
});

test("5. a binding held by a verified-deleted uid rebinds to the requester", () => {
  const decision = decideRequest({}, {
    binding: binding({ userId: "deleted_user" }),
    boundOwnerExists: false,
    verifiedDeletedOwnerUid: "deleted_user"
  });
  assert.equal(decision.statusCode, 200);
  assert.equal(decision.reason, "rebound_after_deletion");
  assert.equal(writeFor(decision, "binding").data.userId, "user_123");
  assert.ok(writeFor(decision, "user"));
});

test("6. changed owner during deleted-owner rebind fails closed", () => {
  const decision = decideRequest({}, {
    binding: binding({ userId: "changed_owner" }),
    boundOwnerExists: false,
    verifiedDeletedOwnerUid: "deleted_user"
  });
  assert.equal(decision.statusCode, 500);
  assert.equal(decision.reason, "auth_error");
  assert.deepEqual(decision.writes, []);
});

test("7. a new binding writes both docs and computes all three product periods", () => {
  const cases = [
    {
      productId: "peezy.plus.move",
      purchaseDate: "2025-08-31T10:15:00.000Z",
      expected: "2026-02-28T10:15:00.000Z"
    },
    {
      productId: "peezy.plus.weekly",
      purchaseDate: "2026-08-10T10:15:00.000Z",
      expected: "2026-08-17T10:15:00.000Z"
    },
    {
      productId: "peezy.plus.annual",
      purchaseDate: "2024-02-29T10:15:00.000Z",
      expected: "2025-02-28T10:15:00.000Z"
    }
  ];

  for (const item of cases) {
    const decision = decideRequest(item);
    assert.equal(decision.statusCode, 200);
    assert.equal(decision.writes.length, 2);
    assert.equal(writeFor(decision, "binding").data.expirationDate, item.expected);
    assert.equal(writeFor(decision, "binding").data.createdAt, SERVER_TIMESTAMP);
    assert.equal(writeFor(decision, "user").data.subscription.expirationDate, item.expected);
  }
});

test("8. the 100-binding threshold alerts but does not block writes", () => {
  const decision = decideRequest({}, { bindingCount: 100 });
  assert.equal(decision.statusCode, 200);
  assert.equal(decision.writes.length, 2);
  assert.deepEqual(decision.flags, ["binding_cap_alert"]);
});

test("9. same transaction refresh uses the immutable stored tuple", () => {
  const decision = decideRequest({
    productId: "peezy.plus.annual",
    purchaseDate: "2026-08-15T11:59:00.000Z"
  }, {
    binding: binding({
      productId: "peezy.plus.weekly",
      purchaseDate: "2026-08-01T08:00:00.000Z"
    })
  });
  assert.equal(decision.reason, "refreshed");
  assert.deepEqual(decision.flags, ["product_mismatch"]);
  assert.equal(writeFor(decision, "binding").data.productId, "peezy.plus.weekly");
  assert.equal(writeFor(decision, "binding").data.purchaseDate, "2026-08-01T08:00:00.000Z");
  assert.equal(decision.body.subscription.expirationDate, "2026-08-08T08:00:00.000Z");
});

test("10. a newer transaction advances a same-user binding", () => {
  const decision = decideRequest({
    transactionId: "transaction.renewal",
    productId: "peezy.plus.annual",
    purchaseDate: "2026-08-15T11:30:00.000Z"
  }, {
    binding: binding({ purchaseDate: "2026-08-01T08:00:00.000Z" })
  });
  assert.equal(decision.reason, "renewed");
  assert.equal(writeFor(decision, "binding").data.transactionId, "transaction.renewal");
  assert.equal(writeFor(decision, "binding").data.productId, "peezy.plus.annual");
  assert.equal(decision.body.subscription.expirationDate, "2027-08-15T11:30:00.000Z");
});

test("11. a renewal synced 30 days late still advances", () => {
  const decision = decideRequest({
    transactionId: "transaction.late",
    productId: "peezy.plus.annual",
    purchaseDate: "2026-07-16T12:00:00.000Z"
  }, {
    binding: binding({ purchaseDate: "2025-07-16T12:00:00.000Z" })
  });
  assert.equal(decision.statusCode, 200);
  assert.equal(decision.reason, "renewed");
  assert.equal(decision.body.subscription.expirationDate, "2027-07-16T12:00:00.000Z");
});

test("12. an out-of-order new transaction is a no-op replay", () => {
  const decision = decideRequest({
    transactionId: "transaction.old",
    purchaseDate: "2026-08-01T08:00:00.000Z"
  }, {
    binding: binding({ purchaseDate: "2026-08-02T08:00:00.000Z" })
  });
  assert.equal(decision.statusCode, 200);
  assert.equal(decision.outcome, "noop");
  assert.equal(decision.reason, "replayed_transaction");
  assert.deepEqual(decision.writes, []);
});

test("13. gift identity is preserved, extended only when needed, and revived after expiry", () => {
  const laterGift = {
    source: "giftCode",
    productId: "peezy.plus.move",
    expirationDate: "2027-12-01T00:00:00.000Z",
    code: "PEEZY-AAAA-BBBB",
    campaign: "launch",
    updatedAt: "old-update"
  };
  const preserved = decideRequest({}, { userSubscription: laterGift });
  assert.equal(preserved.reason, "gift_preserved");
  assert.equal(writeFor(preserved, "user"), undefined);
  assert.deepEqual(preserved.flags, []);
  assert.deepEqual(laterGift, {
    source: "giftCode",
    productId: "peezy.plus.move",
    expirationDate: "2027-12-01T00:00:00.000Z",
    code: "PEEZY-AAAA-BBBB",
    campaign: "launch",
    updatedAt: "old-update"
  });

  const shorterGift = { ...laterGift, expirationDate: "2026-09-01T00:00:00.000Z" };
  const extended = decideRequest({}, { userSubscription: shorterGift });
  const extendedSubscription = writeFor(extended, "user").data.subscription;
  assert.equal(extended.reason, "gift_preserved");
  assert.deepEqual(extended.flags, ["gift_extended"]);
  assert.deepEqual(extendedSubscription, {
    ...shorterGift,
    expirationDate: "2027-02-15T11:00:00.000Z",
    updatedAt: SERVER_TIMESTAMP
  });

  const expiredGift = { ...laterGift, expirationDate: "2026-07-01T00:00:00.000Z" };
  const revived = decideRequest({}, { userSubscription: expiredGift });
  assert.ok(new Date(revived.body.subscription.expirationDate) > NOW);
  assert.equal(revived.body.subscription.isActive, true);
});

test("14. gift preservation outranks product mismatch while retaining its flag", () => {
  const decision = decideRequest({ productId: "peezy.plus.annual" }, {
    binding: binding({ productId: "peezy.plus.weekly" }),
    userSubscription: {
      source: "giftCode",
      productId: "peezy.plus.move",
      expirationDate: "2028-01-01T00:00:00.000Z",
      code: "PEEZY-AAAA-BBBB"
    }
  });
  assert.equal(decision.reason, "gift_preserved");
  assert.deepEqual(decision.flags, ["product_mismatch"]);
});

test("15. a later non-gift entitlement is not downgraded", () => {
  const existing = {
    source: "appStore",
    productId: "peezy.plus.annual",
    expirationDate: "2028-01-01T00:00:00.000Z",
    note: "preserve"
  };
  const decision = decideRequest({}, { userSubscription: existing });
  assert.equal(decision.reason, "skipped_downgrade");
  assert.ok(writeFor(decision, "binding"));
  assert.equal(writeFor(decision, "user"), undefined);
  assert.deepEqual(decision.body.subscription, {
    productId: "peezy.plus.annual",
    expirationDate: "2028-01-01T00:00:00.000Z",
    isActive: true
  });
});

test("16. an expired purchase re-syncs with isActive false", () => {
  const decision = decideRequest({
    productId: "peezy.plus.weekly",
    purchaseDate: "2026-01-01T00:00:00.000Z"
  });
  assert.equal(decision.statusCode, 200);
  assert.equal(decision.body.subscription.expirationDate, "2026-01-08T00:00:00.000Z");
  assert.equal(decision.body.subscription.isActive, false);
});

test("17. a legacy bad stored purchase date repairs from valid input or rejects bad input", () => {
  const legacy = binding({ purchaseDate: "not-a-date" });
  const repaired = decideRequest({}, { binding: legacy });
  assert.equal(repaired.statusCode, 200);
  assert.ok(repaired.flags.includes("legacy_repaired"));
  assert.equal(writeFor(repaired, "binding").data.purchaseDate, "2026-08-15T11:00:00.000Z");

  const invalidIncoming = {
    ...parsedInput(),
    purchaseDate: null,
    purchaseDateDate: null
  };
  const rejected = decide(invalidIncoming, {
    now: NOW,
    binding: legacy,
    userSubscription: null,
    bindingCount: 0,
    boundOwnerExists: null,
    verifiedDeletedOwnerUid: null
  });
  assert.equal(rejected.statusCode, 400);
  assert.equal(rejected.reason, "legacy_repair_failed");
  assert.deepEqual(rejected.writes, []);
});

test("18. success and error response JSON contain exactly the legacy keys", () => {
  const success = decideRequest();
  assert.deepEqual(Object.keys(success.body).sort(), ["subscription", "success"]);
  assert.deepEqual(Object.keys(success.body.subscription).sort(), [
    "expirationDate",
    "isActive",
    "productId"
  ]);

  for (const failure of [
    decideRequest({ productId: "bad" }),
    decideRequest({ purchaseDate: "bad" }),
    decideRequest({}, { binding: binding({ userId: "other" }), boundOwnerExists: true })
  ]) {
    assert.deepEqual(Object.keys(failure.body), ["error"]);
  }
});

test("19. wrapper rejection paths never issue Firestore writes", async () => {
  const cases = [
    { body: requestBody({ userId: "path/separator" }) },
    { body: requestBody({ productId: "bad" }) },
    { body: requestBody({ purchaseDate: "bad" }) },
    { body: requestBody({ purchaseDate: "2026-08-15T12:05:00.001Z" }) },
    {
      db: fakeDb({ bindingDoc: binding({ userId: "other_user" }) }),
      auth: fakeAuth({ other_user: { uid: "other_user" } })
    },
    { auth: fakeAuth({ user_123: authError("auth/user-not-found") }) },
    { auth: fakeAuth({ user_123: authError("auth/quota-exceeded") }) },
    {
      db: fakeDb({ bindingDoc: binding({ userId: "other_user" }) }),
      auth: fakeAuth({ other_user: authError("auth/quota-exceeded") })
    },
    {
      db: fakeDb({ bindingDoc: binding({ productId: "legacy.bad.product" }) })
    },
    {
      db: fakeDb({
        bindingDoc: (attempt) => binding({
          userId: attempt === 0 ? "deleted_user" : "changed_owner"
        })
      }),
      auth: fakeAuth({ deleted_user: authError("auth/user-not-found") })
    }
  ];

  for (const item of cases) {
    const result = await invoke(item);
    assert.equal(
      result.db.transactions.flatMap((transaction) => transaction.writes).length,
      0
    );
  }
});

test("20. new-binding writes share one Firestore transaction object", async () => {
  const db = fakeDb();
  const { response } = await invoke({ db });
  assert.equal(response.statusCode, 200);
  assert.equal(db.transactions.length, 1);
  assert.deepEqual(db.transactions[0].writes.map((write) => write.path).sort(), [
    "subscriptions/original.123",
    "users/user_123"
  ]);
  assert.ok(db.transactions[0].writes.every((write) => write.type === "set"));
});

test("21. target-user Auth not-found maps to 404 and quota maps to generic 500", async () => {
  const missing = await invoke({
    auth: fakeAuth({ user_123: authError("auth/user-not-found") })
  });
  assert.equal(missing.response.statusCode, 404);
  assert.deepEqual(missing.response.body, { error: "Unknown user" });

  const quota = await invoke({
    auth: fakeAuth({ user_123: authError("auth/quota-exceeded") })
  });
  assert.equal(quota.response.statusCode, 500);
  assert.deepEqual(quota.response.body, { error: "Sync failed" });
});

test("22. transient Auth failure checking a bound owner is auth_error with zero writes", async () => {
  const logs = [];
  const db = fakeDb({ bindingDoc: binding({ userId: "other_user" }) });
  const result = await invoke({
    db,
    auth: fakeAuth({ other_user: authError("auth/internal-error") }),
    logger: (entry) => logs.push(entry)
  });
  assert.equal(result.response.statusCode, 500);
  assert.deepEqual(result.response.body, { error: "Sync failed" });
  assert.equal(logs[0].reason, "auth_error");
  assert.equal(db.transactions.flatMap((transaction) => transaction.writes).length, 0);
});

test("23. non-POST is 405 and a non-object body is 400", async () => {
  const wrongMethod = await invoke({ method: "GET" });
  assert.equal(wrongMethod.response.statusCode, 405);
  assert.deepEqual(wrongMethod.response.body, { error: "Method not allowed" });

  for (const body of [null, [], "body"]) {
    const invalid = await invoke({ body });
    assert.equal(invalid.response.statusCode, 400);
    assert.deepEqual(invalid.response.body, { error: "Invalid input" });
  }
});

test("24. a retried transaction emits exactly one structured log line", async () => {
  const logs = [];
  const db = fakeDb({ attempts: 2 });
  const result = await invoke({ db, logger: (entry) => logs.push(entry) });
  assert.equal(result.response.statusCode, 200);
  assert.equal(db.transactions.length, 2);
  assert.equal(logs.length, 1);
  assert.deepEqual(logs[0], {
    event: "validateSubscription",
    outcome: "synced",
    reason: "created",
    uid: "user_123",
    otxHash: logs[0].otxHash,
    productId: "peezy.plus.move"
  });
  assert.match(logs[0].otxHash, /^[a-f0-9]{8}$/);
});
