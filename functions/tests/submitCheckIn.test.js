const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildFlags,
  flagMessage,
  parsedVendor,
  writeReviewAndAccountability,
  FLAG_LABELS
} = require("../submitCheckIn");

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

function transactionHarness(vendorData) {
  const writes = { reviews: [], vendorUpdates: [] };
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
          writes.reviews.push({ reference, data });
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
    { vendorId: "test_mover_a", name: "Test Mover A" },
    review
  );

  assert.equal(writes.reviews.length, 1);
  assert.deepEqual(writes.reviews[0].data, review);
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
    { vendorId: "test_mover_a", name: "Test Mover A" },
    {
      vendorId: "test_mover_a",
      userId: "user-123",
      answers: {},
      flags: ["late_arrival"],
      submittedAt: "server-time"
    }
  );

  assert.equal(writes.vendorUpdates.length, 1);
  assert.equal(writes.vendorUpdates[0].data.active, false);
  assert.equal(writes.vendorUpdates[0].data["accountability.strikes"].length, 3);
});
