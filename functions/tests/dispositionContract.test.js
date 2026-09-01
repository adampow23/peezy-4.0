"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  buildCompletedContract,
  buildDeferredContract,
  buildSupportActiveContract,
  buildTerminalContract,
  buildUpcomingContract,
  buildUserActionContract,
  buildWaitingOnExternalContract,
  validateDispositionContract
} = require("../dispositionContract");
const { __private: { shouldWakeDateTask } } = require("../dispositionTriggers");

const NOW = new Date("2026-08-27T12:00:00.000Z");

function dateTrigger(overrides = {}) {
  return {
    kind: "date",
    at: new Date("2026-09-01T12:00:00.000Z"),
    payload: {
      basis: "institution_promised_date",
      source_evidence_id: "evidence-1"
    },
    fired: false,
    ...overrides
  };
}

test("builders emit complete coherent maps and clear stale lifecycle fields", () => {
  const base = {
    profile_version: 7,
    disposition: "DEFERRED",
    owner: "old",
    next_action: "old",
    next_trigger: dateTrigger(),
    resume_destination: "old",
    visible_status_copy: "old",
    superseded_by: "old-task"
  };
  const user = buildUserActionContract(base, {
    owner: "user:u1",
    nextAction: "Upload the amendment",
    nextTrigger: dateTrigger(),
    resumeDestination: "amendment/upload",
    visibleStatusCopy: "Amendment ready"
  }, NOW);
  assert.deepEqual(user, {
    profile_version: 7,
    disposition: "USER_ACTION_TRACKED",
    owner: "user:u1",
    next_action: "Upload the amendment",
    next_trigger: dateTrigger(),
    resume_destination: "amendment/upload",
    visible_status_copy: "Amendment ready"
  });
  assert.equal(validateDispositionContract("InProgress", user, NOW), true);

  const waiting = buildWaitingOnExternalContract(base, {
    owner: "Chase",
    nextAction: "Confirm receipt",
    nextTrigger: dateTrigger(),
    resumeDestination: "verification/chase",
    visibleStatusCopy: "Waiting on Chase",
    externalSubmission: true
  }, NOW);
  assert.equal(waiting.external_submission, true);
  assert.equal(validateDispositionContract("matching_in_progress", waiting, NOW), true);

  assert.deepEqual(buildCompletedContract(base, "Finished"), {
    profile_version: 7,
    disposition: "COMPLETED",
    visible_status_copy: "Finished"
  });
  assert.deepEqual(buildTerminalContract(base, "retired", "Retired"), {
    profile_version: 7,
    terminal_kind: "retired",
    visible_status_copy: "Retired"
  });
  assert.deepEqual(buildUpcomingContract(base, "Ready to continue"), {
    profile_version: 7,
    visible_status_copy: "Ready to continue"
  });
});

test("full validator rejects partial, generic, stale, and backdated contracts", () => {
  const valid = buildUserActionContract({}, {
    owner: "user:u1",
    nextAction: "Continue",
    nextTrigger: dateTrigger(),
    resumeDestination: "flow/continue",
    visibleStatusCopy: "Ready"
  }, NOW);
  for (const key of ["owner", "next_action", "next_trigger", "resume_destination", "visible_status_copy"]) {
    const malformed = { ...valid };
    delete malformed[key];
    assert.throws(() => validateDispositionContract("InProgress", malformed, NOW), /required/i);
  }
  assert.throws(() => validateDispositionContract("InProgress", {
    ...valid,
    next_trigger: dateTrigger({ payload: { basis: "two_days" } })
  }, NOW), /basis/i);
  assert.throws(() => validateDispositionContract("InProgress", {
    ...valid,
    next_trigger: dateTrigger({ at: new Date("2026-08-26T12:00:00.000Z") })
  }, NOW), /future/i);
  assert.throws(() => validateDispositionContract("Completed", {
    ...buildCompletedContract({}, "Done"),
    owner: "stale"
  }, NOW), /stale/i);
});

test("date/event evidence and every approved status pair are table-driven", () => {
  const common = {
    owner: "user:u1",
    nextAction: "Continue",
    resumeDestination: "flow/continue",
    visibleStatusCopy: "Continue"
  };
  const eventTrigger = {
    kind: "event",
    event_name: "recipient_accepted",
    canonical_key: "institution:bank",
    after_source_version: 4,
    payload: { source_evidence_id: "event-evidence", nested: [true, null, 3] },
    fired: false
  };
  const deferred = buildDeferredContract({}, { ...common, nextTrigger: dateTrigger() }, NOW);
  const support = buildSupportActiveContract({}, { ...common, nextTrigger: eventTrigger }, NOW);
  assert.equal(validateDispositionContract("Snoozed", deferred, NOW), true);
  assert.equal(validateDispositionContract("pending", support, NOW), true);
  assert.equal(validateDispositionContract("Upcoming", buildUpcomingContract({}, "Ready"), NOW), true);
  assert.equal(validateDispositionContract("Completed", buildCompletedContract({}, "Done"), NOW), true);
  assert.equal(validateDispositionContract("Dismissed", buildTerminalContract({}, "not_applicable", "Not needed"), NOW), true);
  assert.equal(validateDispositionContract("Dismissed", buildTerminalContract({}, "retired", "Retired"), NOW), true);
  assert.equal(validateDispositionContract("Dismissed", buildTerminalContract(
    { superseded_by: "replacement" }, "superseded", "Replaced"
  ), NOW), true);

  assert.throws(() => buildDeferredContract({}, {
    ...common,
    nextTrigger: dateTrigger({
      payload: { basis: "safe_threshold", protected_outcome: "avoid_lapse" }
    })
  }, NOW), /source and bound/i);
  const derived = buildDeferredContract({}, {
    ...common,
    nextTrigger: dateTrigger({
      payload: {
        basis: "safe_threshold",
        protected_outcome: "avoid_lapse",
        source: "policy",
        bound: 10
      }
    })
  }, NOW);
  assert.equal(validateDispositionContract("Snoozed", derived, NOW), true);
});

test("date builders normalize callable ISO and numeric times to native Date for scheduler queries", () => {
  const common = {
    owner: "user:u1",
    nextAction: "Continue",
    resumeDestination: "flow/continue",
    visibleStatusCopy: "Continue"
  };
  for (const at of ["2026-09-01T12:00:00.000Z", Date.parse("2026-09-01T12:00:00.000Z")]) {
    const contract = buildDeferredContract({}, {
      ...common,
      nextTrigger: dateTrigger({ at })
    }, NOW);
    assert.equal(contract.next_trigger.at instanceof Date, true);
    assert.equal(contract.next_trigger.at.toISOString(), "2026-09-01T12:00:00.000Z");
    assert.equal(shouldWakeDateTask({
      status: "Snoozed",
      dispositionContract: contract
    }, new Date("2026-09-02T00:00:00.000Z")), true);
  }
});

test("builders reject raw cross-kind fields and non-boolean fired before normalization", () => {
  const input = {
    owner: "user:u1",
    nextAction: "Continue",
    resumeDestination: "flow/continue",
    visibleStatusCopy: "Continue"
  };
  const cases = [
    dateTrigger({ event_name: "must-not-survive" }),
    dateTrigger({ canonical_key: "must-not-survive" }),
    dateTrigger({ after_source_version: 1 }),
    dateTrigger({ fired: "false" }),
    {
      kind: "event",
      at: new Date("2026-09-01T12:00:00.000Z"),
      event_name: "accepted",
      canonical_key: "institution:1",
      after_source_version: 0,
      payload: { source_evidence_id: "evidence" },
      fired: false
    }
  ];
  for (const nextTrigger of cases) {
    assert.throws(
      () => buildDeferredContract({}, { ...input, nextTrigger }, NOW),
      /stale|boolean/i
    );
  }
});

test("derived date evidence rejects null, nonfinite, empty, boolean, and container bounds", () => {
  const input = {
    owner: "user:u1",
    nextAction: "Continue",
    resumeDestination: "flow/continue",
    visibleStatusCopy: "Continue"
  };
  const invalidBounds = [null, Number.NaN, Number.POSITIVE_INFINITY, "", "   ", true, {}, []];
  for (const bound of invalidBounds) {
    assert.throws(() => buildDeferredContract({}, {
      ...input,
      nextTrigger: dateTrigger({
        payload: {
          basis: "safe_threshold",
          protected_outcome: "avoid_lapse",
          source: "policy",
          bound
        }
      })
    }, NOW), /bound/i);
  }
  for (const key of ["threshold", "adjustable_bound"]) {
    assert.throws(() => buildDeferredContract({}, {
      ...input,
      nextTrigger: dateTrigger({
        payload: {
          basis: "risk_based_estimate",
          protected_outcome: "avoid_lapse",
          source: "policy",
          [key]: null
        }
      })
    }, NOW), /bound/i);
  }
  for (const bound of [0, 12.5, "policy maximum"]) {
    const contract = buildDeferredContract({}, {
      ...input,
      nextTrigger: dateTrigger({
        payload: {
          basis: "safe_threshold",
          protected_outcome: "avoid_lapse",
          source: "policy",
          bound
        }
      })
    }, NOW);
    assert.equal(contract.next_trigger.payload.bound, bound);
  }
});
