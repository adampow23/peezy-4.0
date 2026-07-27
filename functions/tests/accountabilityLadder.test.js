const test = require("node:test");
const assert = require("node:assert/strict");
const {
  accountabilityTransition,
  ladderState,
  normalizeStrikes,
  pendingStrikesForFlags,
  STRIKE_SEVERITY,
  STRIKE_STATUS
} = require("../accountabilityLadder");

function strike(status, severity = STRIKE_SEVERITY.high) {
  return {
    date: new Date("2026-07-27T00:00:00Z"),
    source: "review-test",
    severity,
    status,
    note: "test"
  };
}

test("ladder ignores pending and dismissed strikes", () => {
  assert.equal(ladderState([
    strike(STRIKE_STATUS.pendingReview),
    strike(STRIKE_STATUS.dismissed)
  ]), "ok");
});

test("confirmed strike thresholds advance through conversation and warning", () => {
  assert.equal(ladderState([strike(STRIKE_STATUS.confirmed)]), "conversation");
  assert.equal(ladderState([
    strike(STRIKE_STATUS.confirmed),
    strike(STRIKE_STATUS.confirmed)
  ]), "warning");
});

test("third confirmed strike removes the vendor and flips active false", () => {
  const transition = accountabilityTransition([
    strike(STRIKE_STATUS.confirmed),
    strike(STRIKE_STATUS.confirmed),
    strike(STRIKE_STATUS.confirmed)
  ]);

  assert.equal(transition.state, "removed");
  assert.equal(transition.active, false);
});

test("confirmed day-of price change removes immediately", () => {
  const transition = accountabilityTransition([
    strike(STRIKE_STATUS.confirmed, STRIKE_SEVERITY.dayOfPriceChange)
  ]);

  assert.equal(transition.state, "removed");
  assert.equal(transition.active, false);
});

test("only price and damage flags create deterministic pending high strikes", () => {
  const when = new Date("2026-07-27T12:00:00Z");
  const strikes = pendingStrikesForFlags([
    "late_arrival",
    "charged_more_than_quoted",
    "unsteady_crew",
    "damage"
  ], "review-123", when);

  assert.deepEqual(strikes, [
    {
      date: when,
      source: "review-123",
      severity: "high",
      status: "pendingReview",
      note: "charged_more_than_quoted"
    },
    {
      date: when,
      source: "review-123",
      severity: "high",
      status: "pendingReview",
      note: "damage"
    }
  ]);
});

test("legacy numeric strikes preserve their confirmed count during migration", () => {
  const migrated = normalizeStrikes(2);

  assert.equal(migrated.length, 2);
  assert.equal(ladderState(migrated), "warning");
});
