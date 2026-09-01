"use strict";

const { HttpsError } = require("firebase-functions/v2/https");

const DATE_BASES = new Set([
  "institution_promised_date",
  "recipient_acceptance_date",
  "safe_threshold",
  "user_adjustable_bounded",
  "risk_based_estimate"
]);
const EVIDENCE_DATE_BASES = new Set([
  "institution_promised_date",
  "recipient_acceptance_date"
]);
const NONTERMINAL_FIELDS = [
  "owner", "next_action", "next_trigger", "resume_destination"
];
const LIFECYCLE_FIELDS = new Set([
  "disposition", "terminal_kind", "owner", "next_action", "next_trigger",
  "resume_destination", "visible_status_copy", "external_submission",
  "superseded_by"
]);

function fail(message) {
  throw new HttpsError("failed-precondition", message);
}

function trimmed(value) {
  return typeof value === "string" ? value.trim() : "";
}

function dateFromValue(value) {
  if (value instanceof Date && Number.isFinite(value.getTime())) return value;
  if (value && typeof value.toDate === "function") {
    const result = value.toDate();
    return result instanceof Date && Number.isFinite(result.getTime()) ? result : null;
  }
  if (typeof value === "string" || typeof value === "number") {
    const result = new Date(value);
    return Number.isFinite(result.getTime()) ? result : null;
  }
  return null;
}

function cloneFirestoreValue(value) {
  if (value === null || typeof value !== "object") return value;
  const date = dateFromValue(value);
  if (date) return new Date(date.getTime());
  if (Array.isArray(value)) return value.map(cloneFirestoreValue);
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, cloneFirestoreValue(item)]));
}

function normalizeTrigger(trigger) {
  if (!trigger || typeof trigger !== "object" || Array.isArray(trigger)) return trigger;
  const normalized = { kind: trigger.kind };
  if (trigger.kind === "date") {
    const at = dateFromValue(trigger.at);
    if (at) normalized.at = new Date(at.getTime());
  } else if (trigger.kind === "event") {
    if (trigger.event_name !== undefined) normalized.event_name = trigger.event_name;
    if (trigger.canonical_key !== undefined) normalized.canonical_key = trigger.canonical_key;
    if (trigger.after_source_version !== undefined) {
      normalized.after_source_version = trigger.after_source_version;
    }
  }
  if (trigger.payload !== undefined) normalized.payload = cloneFirestoreValue(trigger.payload);
  normalized.fired = trigger.fired === true;
  return normalized;
}

function isFirestoreSafe(value, seen = new Set()) {
  if (value === null || typeof value === "string" || typeof value === "boolean") return true;
  if (typeof value === "number") return Number.isFinite(value);
  if (value instanceof Date) return Number.isFinite(value.getTime());
  if (value && typeof value.toDate === "function") return dateFromValue(value) !== null;
  if (!value || typeof value !== "object" || seen.has(value)) return false;
  seen.add(value);
  const result = Array.isArray(value)
    ? value.every((item) => isFirestoreSafe(item, seen))
    : Object.entries(value).every(([key, item]) => trimmed(key) && isFirestoreSafe(item, seen));
  seen.delete(value);
  return result;
}

function profileMetadata(base) {
  const metadata = {};
  if (base && Number.isSafeInteger(base.profile_version)) {
    metadata.profile_version = base.profile_version;
  }
  return metadata;
}

function validateTrigger(trigger, now = new Date()) {
  if (!trigger || typeof trigger !== "object" || Array.isArray(trigger)) {
    fail("A complete next_trigger is required");
  }
  if (trigger.kind === "date") {
    if (trigger.event_name !== undefined || trigger.canonical_key !== undefined ||
        trigger.after_source_version !== undefined) {
      fail("Date trigger contains stale event fields");
    }
    const at = dateFromValue(trigger.at);
    if (!at || at.getTime() <= now.getTime()) fail("Date trigger must be in the future");
    if (!trigger.payload || typeof trigger.payload !== "object" ||
        Array.isArray(trigger.payload)) {
      fail("Date trigger requires an evidence payload map");
    }
    const basis = trimmed(trigger.payload.basis);
    if (!DATE_BASES.has(basis)) fail("Date trigger basis is not approved");
    if (EVIDENCE_DATE_BASES.has(basis)) {
      if (!trimmed(trigger.payload.source_evidence_id)) {
        fail("Promised or acceptance dates require source_evidence_id");
      }
    } else {
      if (!trimmed(trigger.payload.protected_outcome)) {
        fail("Derived dates require protected_outcome");
      }
      const hasSource = trimmed(trigger.payload.source_evidence_id) ||
        trimmed(trigger.payload.source) || trimmed(trigger.payload.derivation_source);
      const boundKeys = ["bound", "threshold", "adjustable_bound"].filter((key) =>
        Object.prototype.hasOwnProperty.call(trigger.payload, key)
      );
      const meaningfulBound = (value) =>
        (typeof value === "number" && Number.isFinite(value)) ||
        (typeof value === "string" && value.trim().length > 0);
      if (!hasSource || boundKeys.length === 0 ||
          boundKeys.some((key) => !meaningfulBound(trigger.payload[key]))) {
        fail("Derived dates require meaningful source and bound evidence");
      }
    }
    if (!isFirestoreSafe(trigger.payload)) {
      fail("Date trigger requires a Firestore-safe evidence payload");
    }
  } else if (trigger.kind === "event") {
    if (trigger.at !== undefined) fail("Event trigger contains a stale date");
    if (!trimmed(trigger.event_name) || !trimmed(trigger.canonical_key)) {
      fail("Event trigger requires event_name and canonical_key");
    }
    if (!Number.isSafeInteger(trigger.after_source_version) || trigger.after_source_version < -1) {
      fail("Event trigger requires a safe after_source_version");
    }
    if (!trigger.payload || !isFirestoreSafe(trigger.payload) ||
        !trimmed(trigger.payload.source_evidence_id)) {
      fail("Event trigger requires Firestore-safe source evidence");
    }
  } else {
    fail("next_trigger.kind must be date or event");
  }
  if (trigger.fired !== undefined && typeof trigger.fired !== "boolean") {
    fail("next_trigger.fired must be boolean");
  }
  return true;
}

function assertNoFields(contract, fields, context) {
  for (const field of fields) {
    if (contract[field] !== undefined) fail(`${context} contains stale ${field}`);
  }
}

function validateDispositionContract(status, contract, now = new Date()) {
  if (!contract || typeof contract !== "object" || Array.isArray(contract)) {
    fail("dispositionContract must be a map");
  }
  if (contract.profile_version !== undefined && !Number.isSafeInteger(contract.profile_version)) {
    fail("profile_version must be a safe integer");
  }
  const copy = trimmed(contract.visible_status_copy);
  if (!copy) fail("visible_status_copy is required");
  if (contract.external_submission !== undefined && typeof contract.external_submission !== "boolean") {
    fail("external_submission must be boolean");
  }
  if (contract.superseded_by !== undefined && !trimmed(contract.superseded_by)) {
    fail("superseded_by must be a nonempty string");
  }

  const expected = {
    InProgress: "USER_ACTION_TRACKED",
    matching_in_progress: "WAITING_ON_EXTERNAL",
    Snoozed: "DEFERRED",
    pending: "SUPPORT_ACTIVE"
  }[status];
  if (expected) {
    if (contract.disposition !== expected || contract.terminal_kind !== undefined) {
      fail(`Status ${status} requires disposition ${expected} without terminal_kind`);
    }
    for (const field of NONTERMINAL_FIELDS) {
      if (!trimmed(contract[field]) && field !== "next_trigger") {
        fail(`${field} is required for a noncomplete disposition`);
      }
      if (field === "next_trigger") validateTrigger(contract.next_trigger, now);
    }
    if (contract.superseded_by !== undefined) fail("Nonterminal contract contains stale superseded_by");
    return true;
  }

  if (status === "Completed") {
    if (contract.disposition !== "COMPLETED" || contract.terminal_kind !== undefined) {
      fail("Completed requires COMPLETED without terminal_kind");
    }
    assertNoFields(contract, [...NONTERMINAL_FIELDS, "external_submission", "superseded_by"], "Completed contract");
    return true;
  }

  if (status === "Dismissed") {
    const notApplicable = contract.disposition === "NOT_APPLICABLE" &&
      contract.terminal_kind === "not_applicable";
    const graphTerminal = contract.disposition === undefined &&
      ["retired", "superseded"].includes(contract.terminal_kind);
    if (!notApplicable && !graphTerminal) fail("Dismissed requires an approved terminal pair");
    assertNoFields(contract, [...NONTERMINAL_FIELDS, "external_submission"], "Terminal contract");
    if (contract.terminal_kind !== "superseded" && contract.superseded_by !== undefined) {
      fail("Only a superseded terminal may name superseded_by");
    }
    return true;
  }

  if (status === "Upcoming") {
    assertNoFields(contract, [
      "disposition", "terminal_kind", ...NONTERMINAL_FIELDS,
      "external_submission", "superseded_by"
    ], "Upcoming contract");
    return true;
  }

  fail(`Unsupported status/contract pair: ${status}`);
}

function buildNonterminal(disposition, base, input, now) {
  validateTrigger(input?.nextTrigger, now);
  const contract = {
    ...profileMetadata(base),
    disposition,
    owner: trimmed(input?.owner),
    next_action: trimmed(input?.nextAction),
    next_trigger: normalizeTrigger(input?.nextTrigger),
    resume_destination: trimmed(input?.resumeDestination),
    visible_status_copy: trimmed(input?.visibleStatusCopy)
  };
  if (input?.externalSubmission === true) contract.external_submission = true;
  const status = {
    USER_ACTION_TRACKED: "InProgress",
    WAITING_ON_EXTERNAL: "matching_in_progress",
    DEFERRED: "Snoozed",
    SUPPORT_ACTIVE: "pending"
  }[disposition];
  validateDispositionContract(status, contract, now);
  return contract;
}

function buildUserActionContract(base, input, now = new Date()) {
  return buildNonterminal("USER_ACTION_TRACKED", base, input, now);
}

function buildWaitingOnExternalContract(base, input, now = new Date()) {
  return buildNonterminal("WAITING_ON_EXTERNAL", base, input, now);
}

function buildDeferredContract(base, input, now = new Date()) {
  return buildNonterminal("DEFERRED", base, input, now);
}

function buildSupportActiveContract(base, input, now = new Date()) {
  return buildNonterminal("SUPPORT_ACTIVE", base, input, now);
}

function buildCompletedContract(base, copy) {
  const contract = {
    ...profileMetadata(base),
    disposition: "COMPLETED",
    visible_status_copy: trimmed(copy)
  };
  validateDispositionContract("Completed", contract);
  return contract;
}

function buildTerminalContract(base, terminalKind, copy) {
  const contract = {
    ...profileMetadata(base),
    terminal_kind: terminalKind,
    visible_status_copy: trimmed(copy)
  };
  if (terminalKind === "not_applicable") contract.disposition = "NOT_APPLICABLE";
  if (terminalKind === "superseded" && trimmed(base?.superseded_by)) {
    contract.superseded_by = trimmed(base.superseded_by);
  }
  validateDispositionContract("Dismissed", contract);
  return contract;
}

function buildUpcomingContract(base, copy) {
  const contract = {
    ...profileMetadata(base),
    visible_status_copy: trimmed(copy)
  };
  validateDispositionContract("Upcoming", contract);
  return contract;
}

module.exports = {
  buildCompletedContract,
  buildDeferredContract,
  buildSupportActiveContract,
  buildTerminalContract,
  buildUpcomingContract,
  buildUserActionContract,
  buildWaitingOnExternalContract,
  cloneFirestoreValue,
  dateFromValue,
  isFirestoreSafe,
  normalizeTrigger,
  validateDispositionContract,
  validateTrigger
};
