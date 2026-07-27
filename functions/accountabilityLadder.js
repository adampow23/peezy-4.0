const STRIKE_STATUS = Object.freeze({
  pendingReview: "pendingReview",
  confirmed: "confirmed",
  dismissed: "dismissed"
});

const STRIKE_SEVERITY = Object.freeze({
  high: "high",
  dayOfPriceChange: "dayOfPriceChange"
});

const AUTO_STRIKE_FLAGS = new Set([
  "charged_more_than_quoted",
  "damage"
]);

function normalizeStrikes(rawStrikes) {
  if (Array.isArray(rawStrikes)) {
    return rawStrikes.filter((strike) => strike && typeof strike === "object");
  }

  const legacyCount = Number.isInteger(rawStrikes) ? Math.max(0, rawStrikes) : 0;
  return Array.from({ length: legacyCount }, (_, index) => ({
    date: new Date(0),
    source: `legacy-${index + 1}`,
    severity: STRIKE_SEVERITY.high,
    status: STRIKE_STATUS.confirmed,
    note: "Migrated from legacy strike count"
  }));
}

function ladderState(rawStrikes) {
  const confirmed = normalizeStrikes(rawStrikes)
    .filter((strike) => strike.status === STRIKE_STATUS.confirmed);

  if (confirmed.some((strike) => strike.severity === STRIKE_SEVERITY.dayOfPriceChange)) {
    return "removed";
  }
  if (confirmed.length >= 3) return "removed";
  if (confirmed.length === 2) return "warning";
  if (confirmed.length === 1) return "conversation";
  return "ok";
}

function accountabilityTransition(rawStrikes, active = true) {
  const strikes = normalizeStrikes(rawStrikes);
  const state = ladderState(strikes);
  return {
    strikes,
    state,
    active: state === "removed" ? false : active
  };
}

function pendingStrikesForFlags(flags, reviewId, date = new Date()) {
  return flags
    .filter((flag) => AUTO_STRIKE_FLAGS.has(flag))
    .map((flag) => ({
      date,
      source: reviewId,
      severity: STRIKE_SEVERITY.high,
      status: STRIKE_STATUS.pendingReview,
      note: flag
    }));
}

module.exports = {
  accountabilityTransition,
  ladderState,
  normalizeStrikes,
  pendingStrikesForFlags,
  STRIKE_SEVERITY,
  STRIKE_STATUS
};
