const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildFlags,
  flagMessage,
  parsedVendor,
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
