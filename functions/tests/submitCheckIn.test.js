const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildFlags,
  calibrationRecord,
  cleanAnswers,
  flagMessage,
  parsedBookingContext,
  parsedVendor,
  writeReviewAndAccountability,
  FLAG_LABELS
} = require("../submitCheckInCore");

function storedBookingAnswers(overrides = {}) {
  const vendor = {
    vendorId: "test_mover_a",
    name: "Test Mover A"
  };
  const estimate = {
    low: 1200,
    high: 1600,
    typicalHours: 5.5,
    crew: 4
  };
  const scope = {
    cubicFeet: 980,
    driveMinutes: 45,
    packedStatus: "mostlyPacked"
  };
  return {
    workflowId: "book_movers",
    answers: {
      chosen_vendor: [JSON.stringify(vendor)],
      estimate: [JSON.stringify(estimate)],
      scope: [JSON.stringify(scope)],
      quoteRequest: ["false"],
      ...overrides
    }
  };
}

test("adverse outcomes map to stable factual flags", () => {
  const flags = buildFlags({
    arrivedInWindow: false,
    crewWorkedSteadily: false,
    costMoreThanQuoted: true,
    damaged: true
  });

  assert.deepEqual(flags, [
    "late_arrival",
    "unsteady_crew",
    "charged_more_than_quoted",
    "damage"
  ]);
  assert.equal(FLAG_LABELS.charged_more_than_quoted, "charged more than quoted");
  assert.equal(
    flagMessage("Test Mover A", "charged_more_than_quoted"),
    "PEEZY FLAG: Test Mover A — charged more than quoted."
  );
});

test("good outcomes produce no flags", () => {
  assert.deepEqual(buildFlags({
    arrivedInWindow: true,
    crewWorkedSteadily: true,
    costMoreThanQuoted: false,
    damaged: false
  }), []);
});

test("booked vendor parser handles the persisted WorkflowAnswers envelope", () => {
  const vendor = parsedVendor({
    workflowId: "book_movers",
    answers: {
      chosen_vendor: [JSON.stringify({
        vendorId: "test_mover_a",
        name: "Test Mover A"
      })]
    }
  });

  assert.deepEqual(vendor, {
    vendorId: "test_mover_a",
    name: "Test Mover A"
  });
  assert.equal(parsedVendor({ answers: { chosen_vendor: ["{}"] } }), null);
});

test("booked move context comes only from the persisted booking envelope", () => {
  const context = parsedBookingContext(storedBookingAnswers());

  assert.deepEqual(context, {
    vendor: {
      vendorId: "test_mover_a",
      name: "Test Mover A"
    },
    estimatedRange: {
      low: 1200,
      high: 1600
    },
    scopeSnapshot: {
      cubicFeet: 980,
      driveMinutes: 45,
      packedStatus: "mostlyPacked"
    }
  });
  assert.equal(parsedBookingContext(storedBookingAnswers({ quoteRequest: ["true"] })), null);
  assert.equal(parsedBookingContext(storedBookingAnswers({ estimate: ["{}"] })), null);
  assert.equal(parsedBookingContext(storedBookingAnswers({ scope: ["{}"] })), null);
});

test("final bill is optional, positive, finite, and client calibration context is discarded", () => {
  const withoutBill = cleanAnswers({
    arrivedInWindow: true,
    crewWorkedSteadily: true,
    costMoreThanQuoted: false,
    damaged: false,
    vendorId: "client-forgery",
    estimatedRange: { low: 1, high: 2 },
    scopeSnapshot: { cubicFeet: 1 }
  });
  assert.deepEqual(withoutBill, {
    arrivedInWindow: true,
    crewWorkedSteadily: true,
    costMoreThanQuoted: false,
    damaged: false,
    note: ""
  });

  const withBill = cleanAnswers({
    arrivedInWindow: true,
    crewWorkedSteadily: true,
    costMoreThanQuoted: false,
    damaged: false,
    note: "  all good  ",
    finalBill: 1432.18
  });
  assert.equal(withBill.finalBill, 1432.18);
  assert.equal(withBill.note, "all good");

  for (const invalid of [0, -1, Number.NaN, Number.POSITIVE_INFINITY, "1432.18"]) {
    assert.throws(() => cleanAnswers({
      arrivedInWindow: true,
      crewWorkedSteadily: true,
      costMoreThanQuoted: false,
      damaged: false,
      finalBill: invalid
    }));
  }
});

test("calibration record is conditional and links persisted context to its review", () => {
  const context = parsedBookingContext(storedBookingAnswers());
  const submittedAt = { sentinel: "server-time" };
  const record = calibrationRecord({
    reviewId: "review-123",
    userId: "user-123",
    bookingContext: context,
    answers: { finalBill: 1432.18 },
    submittedAt
  });

  assert.deepEqual(record, {
    reviewId: "review-123",
    userId: "user-123",
    vendorId: "test_mover_a",
    estimatedRange: { low: 1200, high: 1600 },
    finalBill: 1432.18,
    scopeSnapshot: {
      cubicFeet: 980,
      driveMinutes: 45,
      packedStatus: "mostlyPacked"
    },
    submittedAt
  });
  assert.equal(calibrationRecord({
    reviewId: "review-123",
    userId: "user-123",
    bookingContext: context,
    answers: {},
    submittedAt
  }), null);
  assert.equal(calibrationRecord({
    reviewId: "review-123",
    userId: "user-123",
    bookingContext: null,
    answers: { finalBill: 1432.18 },
    submittedAt
  }), null);
});

function transactionHarness(vendorData) {
  const writes = { sets: [], vendorUpdates: [] };
  const db = {
    collection(name) {
      return {
        doc(id) {
          return { id, path: `${name}/${id}` };
        }
      };
    },
    async runTransaction(operation) {
      return operation({
        async get() {
          return {
            exists: true,
            data: () => vendorData
          };
        },
        set(reference, data) {
          writes.sets.push({ reference, data });
        },
        update(reference, data) {
          writes.vendorUpdates.push({ reference, data });
        }
      });
    }
  };
  return { db, writes };
}

test("review transaction appends pending high strikes for price and damage", async () => {
  const { db, writes } = transactionHarness({
    active: true,
    accountability: { standardsVersion: "v1", strikes: 0 }
  });
  const reviewRef = { id: "review-123", path: "vendorReviews/review-123" };
  const review = {
    vendorId: "test_mover_a",
    userId: "user-123",
    answers: {},
    flags: ["late_arrival", "charged_more_than_quoted", "damage"],
    submittedAt: "server-time"
  };

  await writeReviewAndAccountability(
    db,
    reviewRef,
    null,
    { vendorId: "test_mover_a", name: "Test Mover A" },
    review,
    null
  );

  assert.equal(writes.sets.length, 1);
  assert.deepEqual(writes.sets[0].data, review);
  assert.equal(writes.vendorUpdates.length, 1);
  assert.equal(writes.vendorUpdates[0].data.active, true);
  assert.deepEqual(
    writes.vendorUpdates[0].data["accountability.strikes"].map((strike) => ({
      source: strike.source,
      severity: strike.severity,
      status: strike.status,
      note: strike.note
    })),
    [
      {
        source: "review-123",
        severity: "high",
        status: "pendingReview",
        note: "charged_more_than_quoted"
      },
      {
        source: "review-123",
        severity: "high",
        status: "pendingReview",
        note: "damage"
      }
    ]
  );
});

test("review transaction reconciles a confirmed removal state to inactive", async () => {
  const confirmed = [1, 2, 3].map((number) => ({
    date: new Date(0),
    source: `review-${number}`,
    severity: "high",
    status: "confirmed",
    note: "confirmed"
  }));
  const { db, writes } = transactionHarness({
    active: true,
    accountability: { standardsVersion: "v1", strikes: confirmed }
  });

  await writeReviewAndAccountability(
    db,
    { id: "review-4", path: "vendorReviews/review-4" },
    null,
    { vendorId: "test_mover_a", name: "Test Mover A" },
    {
      vendorId: "test_mover_a",
      userId: "user-123",
      answers: {},
      flags: ["late_arrival"],
      submittedAt: "server-time"
    },
    null
  );

  assert.equal(writes.vendorUpdates.length, 1);
  assert.equal(writes.vendorUpdates[0].data.active, false);
  assert.equal(writes.vendorUpdates[0].data["accountability.strikes"].length, 3);
});

test("review and estimate calibration are written in the same transaction", async () => {
  const { db, writes } = transactionHarness({
    active: true,
    accountability: { standardsVersion: "v1", strikes: [] }
  });
  const reviewRef = { id: "review-123", path: "vendorReviews/review-123" };
  const calibrationRef = {
    id: "calibration-456",
    path: "estimateCalibration/calibration-456"
  };
  const vendor = { vendorId: "test_mover_a", name: "Test Mover A" };
  const review = {
    vendorId: vendor.vendorId,
    userId: "user-123",
    answers: { finalBill: 1432.18 },
    flags: [],
    submittedAt: "server-time"
  };
  const calibration = {
    reviewId: reviewRef.id,
    userId: "user-123",
    vendorId: vendor.vendorId,
    estimatedRange: { low: 1200, high: 1600 },
    finalBill: 1432.18,
    scopeSnapshot: { cubicFeet: 980 },
    submittedAt: "server-time"
  };

  await writeReviewAndAccountability(
    db,
    reviewRef,
    calibrationRef,
    vendor,
    review,
    calibration
  );

  assert.deepEqual(
    writes.sets.map(({ reference, data }) => ({ path: reference.path, data })),
    [
      { path: reviewRef.path, data: review },
      { path: calibrationRef.path, data: calibration }
    ]
  );
});
