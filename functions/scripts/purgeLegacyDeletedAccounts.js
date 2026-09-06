"use strict";

/**
 * PHASE2_CONTRACT.md C9.4.1 — purgeLegacyDeletedAccounts.js (S2/S3 shared; import-side-effect-free pure core, CLI only
 * under `require.main === module`).
 *
 * Audit is read-only and streams one bounded page from source 0. Apply drives the checkpoint state machine
 * discovering -> reducing -> waiting_guards -> confirming under the literal arming set, the environment guards, the
 * pre-source-0 gate, and the creation barrier; every nomination, adoption, waiting-guard mutation, and confirmation-page
 * commit re-reads the barrier first and is a zero-write invariant on drift. Output carries fixed codes, bounded counts,
 * source ordinals, and digests only.
 */

const fs = require("node:fs");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { FieldPath, FieldValue } = require("firebase-admin/firestore");
const fence = require("../accountDeletionFence");
const sealer = require("./sealAccountDeletionProviderEvidence");

const PRODUCTION_PROJECT = "peezy-1ecrdl";
const PRODUCTION_DATABASE = "(default)";
const PRODUCTION_BUCKET = "peezy-1ecrdl.firebasestorage.app";
const DOCUMENTS_PARENT = `projects/${PRODUCTION_PROJECT}/databases/${PRODUCTION_DATABASE}/documents`;
const CHECKPOINT_PATH = "phase2System/accountDeletionLegacyMigrationV1";
const CANDIDATES = "accountDeletionLegacyCandidates";
const CHECKPOINT_CAP_BYTES = 8192;
const CANDIDATE_CAP_BYTES = 2048;
const PAGE_SIZE = 100;
const PAGE_TOKEN_MAX_BYTES = 4096;
const CLEANUP_PAGE = 100;
const HEX64_RE = /^[0-9a-f]{64}$/;
const LOWERCASE_UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const CURSOR_KEYS = Object.freeze(["event_envelope_prepass", "date_snoozed_deferred", "date_inprogress_user_action", "date_matching_waiting", "event_snoozed_deferred", "event_inprogress_user_action", "event_matching_waiting"]);
const QUARANTINE_ID_FAMILIES = Object.freeze(["qev1_", "qevu1_", "qev2_"]);

/** ACCOUNT_DELETION_LEGACY_SOURCES_V1 (23 rows; displayed order = execution order). */
const ACCOUNT_DELETION_LEGACY_SOURCES_V1 = Object.freeze([
  { id: "users_missing_roots", kind: "firestore_raw", parent: DOCUMENTS_PARENT, collection_id: "users", show_missing: true, extract: "document_id" },
  { id: "user_knowledge", kind: "firestore_raw", parent: DOCUMENTS_PARENT, collection_id: "userKnowledge", show_missing: false, extract: "document_id" },
  { id: "support_threads", kind: "firestore_raw", parent: DOCUMENTS_PARENT, collection_id: "supportThreads", show_missing: false, extract: "document_id" },
  { id: "concierge_requests_user", kind: "firestore_raw", parent: DOCUMENTS_PARENT, collection_id: "conciergeRequests", show_missing: false, extract: "optional_string_field:userId" },
  { id: "task_flow_submissions_user", kind: "firestore_raw", parent: DOCUMENTS_PARENT, collection_id: "taskFlowSubmissions", show_missing: false, extract: "optional_string_field:userId" },
  { id: "inventory_sessions_user", kind: "firestore_raw", parent: DOCUMENTS_PARENT, collection_id: "inventorySessions", show_missing: false, extract: "optional_string_field:userId" },
  { id: "workflow_submissions_user", kind: "firestore_raw", parent: DOCUMENTS_PARENT, collection_id: "workflowSubmissions", show_missing: false, extract: "optional_string_field:userId" },
  { id: "workflow_submissions_owner", kind: "firestore_raw", parent: DOCUMENTS_PARENT, collection_id: "workflowSubmissions", show_missing: false, extract: "optional_string_field:owner" },
  { id: "subscriptions_user", kind: "firestore_raw", parent: DOCUMENTS_PARENT, collection_id: "subscriptions", show_missing: false, extract: "optional_string_field:userId" },
  { id: "vendor_reviews_user", kind: "firestore_raw", parent: DOCUMENTS_PARENT, collection_id: "vendorReviews", show_missing: false, extract: "optional_string_field:userId" },
  { id: "estimate_calibration_user", kind: "firestore_raw", parent: DOCUMENTS_PARENT, collection_id: "estimateCalibration", show_missing: false, extract: "optional_string_field:userId" },
  { id: "inventory_packages_user", kind: "firestore_raw", parent: `${DOCUMENTS_PARENT}/admin/inventoryPackages`, collection_id: "packages", show_missing: false, extract: "optional_string_field:userId" },
  { id: "admin_notifications_user", kind: "firestore_raw", parent: DOCUMENTS_PARENT, collection_id: "adminNotifications", show_missing: false, extract: "optional_string_field:userId" },
  { id: "gift_codes_redeemer", kind: "firestore_raw", parent: DOCUMENTS_PARENT, collection_id: "giftCodes", show_missing: false, extract: "optional_string_field:redeemedBy" },
  { id: "event_quarantine_source", kind: "firestore_raw", parent: `${DOCUMENTS_PARENT}/phase1System/dispositionTriggerState`, collection_id: "quarantinedEvents", show_missing: false, extract: "event_source_path_uid" },
  { id: "disposition_trigger_state", kind: "singleton", path: "phase1System/dispositionTriggerState", extract: "trigger_state_path_uids" },
  { id: "oldest_due_alert", kind: "singleton", path: "phase1System/dispositionTriggerState/phase2bAlerts/p2b1_oldest_due_over_900_seconds", extract: "optional_candidate_path_uid" },
  { id: "deletion_storage_work", kind: "firestore_raw", parent: DOCUMENTS_PARENT, collection_id: "accountDeletionStorageWork", show_missing: false, extract: "exact_storage_work_account_uid" },
  { id: "deletion_auth_work", kind: "firestore_raw", parent: DOCUMENTS_PARENT, collection_id: "accountDeletionAuthWork", show_missing: false, extract: "exact_auth_work_account_uid" },
  { id: "inventory_storage_versions", kind: "storage", prefix: "inventory/", mode: "versions" },
  { id: "inventory_storage_soft_deleted", kind: "storage", prefix: "inventory/", mode: "soft_deleted" },
  { id: "users_storage_versions", kind: "storage", prefix: "users/", mode: "versions" },
  { id: "users_storage_soft_deleted", kind: "storage", prefix: "users/", mode: "soft_deleted" }
].map((row) => Object.freeze(row)));

const SOURCE_REGISTRY_SHA256 = fence.sha256Hex(fence.TaskCanonicalV1({ domain: "account_deletion_legacy_sources.v1", rows: ACCOUNT_DELETION_LEGACY_SOURCES_V1.map((r) => ({ ...r })) }));
const STATUSES = Object.freeze(["discovering", "reducing", "waiting_guards", "confirming"]);
const CHECKPOINT_KEYS = Object.freeze([
  "schema_version", "kind", "generation_id", "project_id", "database_id", "bucket_name", "status",
  "pass_ordinal", "source_ordinal", "source_cursor", "pass_candidate_count", "reduction_round", "reduction_cursor_id", "reduction_deferred_count", "confirmation_zero_passes",
  "authority_generation_id", "authority_sha256", "implementation_sha256", "source_registry_sha256", "package_lock_sha256", "script_sha256",
  "drain_evidence_sha256", "auth_freeze_evidence_sha256", "auth_blocker_config_sha256", "auth_blocker_prior_config_sha256", "created_at", "updated_at"
]);
const CANDIDATE_COMMON = Object.freeze(["schema_version", "kind", "candidate_id", "account_uid", "first_pass_ordinal", "created_at", "updated_at"]);

class MigrationInvariant extends Error {
  constructor(code, detail) { super(detail ? `${code}: ${detail}` : code); this.code = code; this.detail = detail; }
}

function invariant(code, detail) { return new MigrationInvariant(code, detail); }
function digestOf(text) { return createHash("sha256").update(text).digest("hex"); }
function isPlainMap(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function isSafeCount(value) { return Number.isSafeInteger(value) && value >= 0; }
function isTimestampLike(value) { return value !== null && typeof value === "object" && typeof value.toMillis === "function"; }
function canonicalBytes(map) { return Buffer.byteLength(fence.TaskCanonicalV1(map), "utf8"); }

function candidateId(uid) { return `adlc1_${fence.first40(fence.sha256Hex(fence.TaskCanonicalV1({ account_uid: uid })))}`; }

/** Canonical UID: nonblank string without a slash, valid as a one-segment document ID. */
function isCanonicalUid(value) {
  return typeof value === "string" && value.length > 0 && value.trim() === value && !value.includes("/") && fence.isUID(value);
}

// ---------------------------------------------------------------------------
// Grammar: checkpoint and candidates
// ---------------------------------------------------------------------------

function validateCursor(cursor) {
  if (!isPlainMap(cursor)) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "cursor");
  const keys = Object.keys(cursor).sort().join(",");
  if (cursor.kind === "start" && keys === "kind") return cursor;
  if ((cursor.kind === "firestore_raw" || cursor.kind === "storage") && keys === "kind,page_token") {
    const token = cursor.page_token;
    if (typeof token !== "string" || token.length === 0 || Buffer.byteLength(token, "utf8") > PAGE_TOKEN_MAX_BYTES || Buffer.from(token, "utf8").toString("utf8") !== token) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "page_token");
    return cursor;
  }
  if (cursor.kind === "singleton" && keys === "done,kind" && cursor.done === true) return cursor;
  throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "cursor kind");
}

function validateCheckpoint(map) {
  if (!isPlainMap(map)) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "checkpoint map");
  const keys = Object.keys(map).sort();
  const expected = [...CHECKPOINT_KEYS].sort();
  if (keys.length !== expected.length || keys.some((k, i) => k !== expected[i])) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "checkpoint members");
  if (map.schema_version !== 1 || map.kind !== "ACCOUNT_DELETION_LEGACY_MIGRATION") throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "kind");
  if (typeof map.generation_id !== "string" || !LOWERCASE_UUID_RE.test(map.generation_id)) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "generation_id");
  if (map.project_id !== PRODUCTION_PROJECT || map.database_id !== PRODUCTION_DATABASE || map.bucket_name !== PRODUCTION_BUCKET) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "identity");
  if (!STATUSES.includes(map.status)) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "status");
  for (const k of ["pass_ordinal", "source_ordinal", "pass_candidate_count", "reduction_round", "reduction_deferred_count"]) if (!isSafeCount(map[k])) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", k);
  validateCursor(map.source_cursor);
  // status-dependent grammar: 0...22 with a cursor matching the current row while discovering/confirming; exactly 23 with {kind:"start"} while reducing/waiting_guards
  if (map.status === "reducing" || map.status === "waiting_guards") {
    if (map.source_ordinal !== ACCOUNT_DELETION_LEGACY_SOURCES_V1.length || map.source_cursor.kind !== "start") throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "source_ordinal");
  } else {
    if (map.source_ordinal >= ACCOUNT_DELETION_LEGACY_SOURCES_V1.length) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "source_ordinal");
    if (map.source_cursor.kind !== "start" && map.source_cursor.kind !== ACCOUNT_DELETION_LEGACY_SOURCES_V1[map.source_ordinal].kind) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "source_cursor kind");
  }
  if (map.reduction_cursor_id !== "" && !/^adlc1_[0-9a-f]{40}$/.test(map.reduction_cursor_id)) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "reduction_cursor_id");
  if (![0, 1, 2].includes(map.confirmation_zero_passes)) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "confirmation_zero_passes");
  for (const k of ["authority_sha256", "implementation_sha256", "source_registry_sha256", "package_lock_sha256", "script_sha256", "drain_evidence_sha256", "auth_freeze_evidence_sha256", "auth_blocker_config_sha256", "auth_blocker_prior_config_sha256"]) if (!HEX64_RE.test(String(map[k]))) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", k);
  if (typeof map.authority_generation_id !== "string" || !LOWERCASE_UUID_RE.test(map.authority_generation_id)) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "authority_generation_id");
  if (!isTimestampLike(map.created_at) || !isTimestampLike(map.updated_at) || map.created_at.toMillis() > map.updated_at.toMillis()) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "times");
  if (canonicalBytes({ ...map, created_at: map.created_at.toMillis(), updated_at: map.updated_at.toMillis() }) > CHECKPOINT_CAP_BYTES) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "checkpoint bytes");
  return map;
}

function validateCandidate(row, id) {
  const bad = (detail) => invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", `candidate ${detail}`);
  if (!isPlainMap(row)) throw bad("map");
  const keys = Object.keys(row).sort();
  const common = [...CANDIDATE_COMMON];
  let extra;
  if (row.disposition === "pending") extra = ["disposition", "last_check_result", "last_checked_at"];
  else if (row.disposition === "excluded_live") extra = ["disposition", "exclusion_reason", "last_checked_at"];
  else if (row.disposition === "adopted") extra = ["disposition", "last_checked_at", "operation_id", "proof_sha256", "marker_started_at"];
  else throw bad("disposition");
  const expected = [...common, ...extra].sort();
  if (keys.length !== expected.length || keys.some((k, i) => k !== expected[i])) throw bad("members");
  if (row.schema_version !== 1 || row.kind !== "ACCOUNT_DELETION_LEGACY_CANDIDATE") throw bad("kind");
  if (!isCanonicalUid(row.account_uid) || row.candidate_id !== candidateId(row.account_uid) || (id !== undefined && id !== row.candidate_id)) throw bad("identity");
  if (!isSafeCount(row.first_pass_ordinal)) throw bad("first_pass_ordinal");
  if (!isTimestampLike(row.created_at) || !isTimestampLike(row.updated_at) || row.created_at.toMillis() > row.updated_at.toMillis()) throw bad("times");
  if (row.disposition === "pending") {
    if (row.last_check_result === "unexamined") { if (row.last_checked_at !== null) throw bad("unexamined time"); }
    else if (row.last_check_result === "ambiguous") { if (!isTimestampLike(row.last_checked_at)) throw bad("ambiguous time"); }
    else throw bad("last_check_result");
  } else {
    if (!isTimestampLike(row.last_checked_at)) throw bad("last_checked_at");
    if (row.disposition === "excluded_live" && !["AUTH_PRESENT", "ROOT_PRESENT"].includes(row.exclusion_reason)) throw bad("exclusion_reason");
    if (row.disposition === "adopted" && (!fence.isOperationId(row.operation_id) || !HEX64_RE.test(String(row.proof_sha256)) || !isTimestampLike(row.marker_started_at))) throw bad("adopted members");
  }
  const projected = {};
  for (const key of Object.keys(row)) {
    const value = row[key];
    projected[key] = value === null ? null : isTimestampLike(value) ? value.toMillis() : value;
  }
  if (canonicalBytes(projected) > CANDIDATE_CAP_BYTES) throw bad("bytes");
  return row;
}

// ---------------------------------------------------------------------------
// Sources and extractors (pinned public-v1 listDocuments, Storage listings, singletons)
// ---------------------------------------------------------------------------

function rawString(value) { return value && typeof value === "object" && (value.valueType === "stringValue" || Object.keys(value).join(",") === "stringValue") ? value.stringValue : undefined; }
function rawMapFields(value) { return value && typeof value === "object" && value.mapValue ? (value.mapValue.fields || {}) : undefined; }

function uidFromEventsPath(sourcePath) {
  if (typeof sourcePath !== "string") return null;
  const parts = sourcePath.split("/");
  if (parts.length !== 4 || parts[0] !== "users" || parts[2] !== "events" || parts[1].length === 0 || parts[3].length === 0 || !isCanonicalUid(parts[1])) return null;
  return parts[1];
}

function documentPathUid(pathValue) {
  if (typeof pathValue !== "string") return null;
  const parts = pathValue.split("/");
  if (parts.length < 4 || parts[0] !== "users" || parts[1].length === 0 || !isCanonicalUid(parts[1]) || parts.length % 2 !== 0) return null;
  return parts[1];
}

/** Extracts the UID set for one raw document under the source's extractor; blocks on any non-canonical presence. */
function extractUids(source, document) {
  const name = document.name;
  const docId = name.slice(name.lastIndexOf("/") + 1);
  const fields = document.fields || {};
  const extract = source.extract;
  if (extract === "document_id") {
    if (!docId || docId.includes("/") || !isCanonicalUid(docId)) throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", `${source.id} document_id`);
    return [docId];
  }
  if (extract.startsWith("optional_string_field:")) {
    const field = extract.slice("optional_string_field:".length);
    if (fields[field] === undefined) return [];
    const value = rawString(fields[field]);
    if (!isCanonicalUid(value)) throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", `${source.id} ${field}`);
    return [value];
  }
  if (extract === "event_source_path_uid") {
    if (!QUARANTINE_ID_FAMILIES.some((prefix) => docId.startsWith(prefix))) throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", "quarantine id family");
    const uid = uidFromEventsPath(rawString(fields.sourcePath));
    if (uid === null) throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", "quarantine sourcePath");
    return [uid];
  }
  if (extract === "exact_storage_work_account_uid" || extract === "exact_auth_work_account_uid") {
    const row = jsonOf(fields);
    const uid = row.account_uid;
    if (!isCanonicalUid(uid)) throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", `${source.id} account_uid`);
    if (extract === "exact_storage_work_account_uid") { fence.validateStorageWork(row, { uid }); if (docId !== fence.storageWorkId(uid)) throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", "storage work id"); }
    else { fence.validateAuthWork(row, { uid }); if (docId !== fence.authWorkId(uid)) throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", "auth work id"); }
    return [uid];
  }
  throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", `extract ${extract}`);
}

/** Raw Value tree -> plain JS for the work-row validators (timestamps become fence-compatible Timestamps). */
function jsonOf(fields) {
  const { Timestamp } = require("firebase-admin/firestore");
  const convert = (value) => {
    if (!value || typeof value !== "object") throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", "value");
    const kind = value.valueType || Object.keys(value)[0];
    switch (kind) {
      case "nullValue": return null;
      case "booleanValue": return value.booleanValue;
      case "integerValue": return Number(value.integerValue);
      case "doubleValue": return value.doubleValue;
      case "stringValue": return value.stringValue;
      case "timestampValue": { const t = value.timestampValue; return typeof t === "string" ? Timestamp.fromDate(new Date(t)) : new Timestamp(Number(t.seconds), Number(t.nanos ?? 0)); }
      case "mapValue": return Object.fromEntries(Object.entries(value.mapValue.fields || {}).map(([k, v]) => [k, convert(v)]));
      case "arrayValue": return ((value.arrayValue && value.arrayValue.values) || []).map(convert);
      default: throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", `oneof ${kind}`);
    }
  };
  return Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, convert(v)]));
}

/** Singleton extractors over the Admin-decoded document. */
function singletonUids(source, data) {
  if (source.extract === "trigger_state_path_uids") {
    if (data === undefined) return [];
    const uids = new Set();
    for (const key of CURSOR_KEYS) {
      const cursor = data[key];
      if (cursor === undefined) continue;
      if (!isPlainMap(cursor) || typeof cursor.path !== "string") throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", `cursor ${key}`);
      const uid = documentPathUid(cursor.path);
      if (uid === null) throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", `cursor path ${key}`);
      uids.add(uid);
    }
    const observation = data.schedulerHealth && data.schedulerHealth.dueObservation;
    if (observation && observation.oldestCandidatePath !== undefined) {
      const uid = documentPathUid(observation.oldestCandidatePath);
      if (uid === null) throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", "dueObservation path");
      uids.add(uid);
    }
    return [...uids].sort(fence.compareUTF8);
  }
  if (source.extract === "optional_candidate_path_uid") {
    if (data === undefined || data.candidatePath === undefined) return [];
    const uid = documentPathUid(data.candidatePath);
    if (uid === null) throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", "candidatePath");
    return [uid];
  }
  throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", source.extract);
}

/** One pinned listDocuments page; validates the three-tuple agreement and direct-child names. */
async function listPage(deps, source, pageSize, pageToken) {
  const request = { parent: source.parent, collectionId: source.collection_id, pageSize, showMissing: source.show_missing };
  if (pageToken !== undefined) request.pageToken = pageToken;
  let tuple;
  try { tuple = await deps.firestore.client.listDocuments(request, { autoPaginate: false }); } catch (error) { throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", `${source.id} call`); }
  const bad = (detail) => invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", `${source.id} ${detail}`);
  if (!Array.isArray(tuple) || tuple.length !== 3) throw bad("tuple");
  const [documents, nextRequest, raw] = tuple;
  if (!Array.isArray(documents) || documents.length > pageSize || !isPlainMap(raw)) throw bad("shape");
  const rawDocuments = raw.documents || [];
  if (!Array.isArray(rawDocuments) || rawDocuments.length !== documents.length) throw bad("count");
  const prefix = `${source.parent}/${source.collection_id}/`;
  let previous = null;
  for (let i = 0; i < documents.length; i += 1) {
    const name = documents[i] && documents[i].name;
    if (typeof name !== "string" || !name.startsWith(prefix) || name.slice(prefix.length).length === 0 || name.slice(prefix.length).includes("/")) throw bad("name");
    if (!rawDocuments[i] || rawDocuments[i].name !== name) throw bad("raw name");
    if (previous !== null && Buffer.compare(Buffer.from(previous), Buffer.from(name)) >= 0) throw bad("order");
    previous = name;
  }
  const token = raw.nextPageToken === undefined ? "" : raw.nextPageToken;
  if (typeof token !== "string" || Buffer.byteLength(token, "utf8") > PAGE_TOKEN_MAX_BYTES) throw bad("token");
  if (token === "") { if (nextRequest !== null && nextRequest !== undefined) throw bad("nextRequest"); }
  else if (!isPlainMap(nextRequest) || nextRequest.parent !== request.parent || nextRequest.collectionId !== request.collectionId || nextRequest.pageSize !== pageSize || nextRequest.showMissing !== request.showMissing || nextRequest.pageToken !== token) throw bad("nextRequest identity");
  return { documents, token };
}

/** One Storage listing page under the fence's tuple discipline; returns UIDs from `<prefix><uid>/<tail>` names. */
async function storagePage(deps, source, pageSize, pageToken) {
  const query = { prefix: source.prefix, maxResults: pageSize, autoPaginate: false };
  if (source.mode === "versions") query.versions = true; else query.softDeleted = true;
  if (pageToken !== undefined) query.pageToken = pageToken;
  let tuple;
  try { tuple = await deps.bucket.getFiles(query); } catch (error) { throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", `${source.id} call`); }
  const { files, terminal } = fence.validateFilesTuple(tuple, { prefix: source.prefix, limit: pageSize, mode: source.mode === "versions" ? "versions" : "softDeleted" });
  const uids = [];
  for (const file of files) {
    const rest = file.name.slice(source.prefix.length);
    const slash = rest.indexOf("/");
    if (slash <= 0 || slash === rest.length - 1) throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", `${source.id} object name`);
    const uid = rest.slice(0, slash);
    if (!isCanonicalUid(uid)) throw invariant("ACCOUNT_DELETION_LEGACY_SOURCE_INVARIANT", `${source.id} uid`);
    uids[uids.length] = uid;
  }
  const token = terminal ? "" : tuple[2].nextPageToken;
  return { uids, token };
}

/** Streams one page of the source at `cursor`; returns { uids, next } where next is the following cursor (start of the next source at terminal). */
async function sourcePage(deps, ordinal, cursor, pageSize) {
  const source = ACCOUNT_DELETION_LEGACY_SOURCES_V1[ordinal];
  const nextStart = { kind: "start" };
  if (source.kind === "singleton") {
    if (cursor.kind !== "start") throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "singleton cursor");
    const snapshot = await deps.db.doc(source.path).get();
    const uids = singletonUids(source, snapshot.exists ? snapshot.data() : undefined);
    return { uids, next: nextStart, done: true };
  }
  const token = cursor.kind === "start" ? undefined : cursor.page_token;
  if (source.kind === "storage") {
    if (cursor.kind !== "start" && cursor.kind !== "storage") throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "storage cursor");
    const page = await storagePage(deps, source, pageSize, token);
    return { uids: page.uids, next: page.token === "" ? nextStart : { kind: "storage", page_token: page.token }, done: page.token === "" };
  }
  if (cursor.kind !== "start" && cursor.kind !== "firestore_raw") throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "firestore cursor");
  const page = await listPage(deps, source, pageSize, token);
  let uids = [];
  for (const document of page.documents) uids = [...uids, ...extractUids(source, document)];
  return { uids, next: page.token === "" ? nextStart : { kind: "firestore_raw", page_token: page.token }, done: page.token === "" };
}

// ---------------------------------------------------------------------------
// Guards: arguments, environment, barrier, pre-source-0 gate
// ---------------------------------------------------------------------------

const APPLY_FLAGS = Object.freeze(["--apply", "--project-id", "--confirm-project", "--database", "--bucket", "--drain-evidence-sha256", "--bucket-config-sha256", "--firestore-config-sha256", "--auth-freeze-evidence-sha256"]);
const AUDIT_FLAGS = Object.freeze(["--project-id", "--confirm-project", "--database", "--bucket", "--page-size"]);

function parseArguments(argv) {
  const parsed = { apply: false, values: {}, unknown: [], duplicate: [], missingValue: [] };
  const seen = new Set();
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--apply") { if (seen.has(arg)) parsed.duplicate = [...parsed.duplicate, arg]; seen.add(arg); parsed.apply = true; continue; }
    if (!APPLY_FLAGS.includes(arg) && !AUDIT_FLAGS.includes(arg)) { parsed.unknown = [...parsed.unknown, arg]; continue; }
    if (seen.has(arg)) parsed.duplicate = [...parsed.duplicate, arg];
    seen.add(arg);
    const value = argv[i + 1];
    if (typeof value !== "string" || value.startsWith("--")) { parsed.missingValue = [...parsed.missingValue, arg]; continue; }
    i += 1;
    parsed.values[arg] = value;
  }
  return parsed;
}

/** Returns the first refusal token before any read; null when the argument set is exact for its mode. */
function argumentRefusal(parsed) {
  if (parsed.unknown.length > 0) return "UNKNOWN_ARGUMENT";
  if (parsed.duplicate.length > 0) return "DUPLICATE_ARGUMENT";
  if (parsed.missingValue.length > 0) return "MALFORMED_ARGUMENT";
  const v = parsed.values;
  if (parsed.apply) {
    if (v["--page-size"] !== undefined) return "UNKNOWN_ARGUMENT";
    for (const flag of APPLY_FLAGS.slice(1)) if (v[flag] === undefined) return "MISSING_ARGUMENT";
    if (v["--project-id"] !== PRODUCTION_PROJECT || v["--confirm-project"] !== PRODUCTION_PROJECT) return "PROJECT_MISMATCH";
    if (v["--database"] !== PRODUCTION_DATABASE || v["--bucket"] !== PRODUCTION_BUCKET) return "TARGET_MISMATCH";
    for (const flag of ["--drain-evidence-sha256", "--bucket-config-sha256", "--firestore-config-sha256", "--auth-freeze-evidence-sha256"]) if (!HEX64_RE.test(v[flag])) return "MALFORMED_ARGUMENT";
    return null;
  }
  for (const flag of Object.keys(v)) if (!AUDIT_FLAGS.includes(flag)) return "UNKNOWN_ARGUMENT";
  if (v["--page-size"] !== undefined) { const n = Number(v["--page-size"]); if (!/^\d+$/.test(v["--page-size"]) || n < 1 || n > 100) return "MALFORMED_ARGUMENT"; }
  return null;
}

async function environmentRefusal(parsed, deps) {
  if (deps.env.FIRESTORE_EMULATOR_HOST !== undefined || deps.env.FIREBASE_STORAGE_EMULATOR_HOST !== undefined || deps.env.FIREBASE_AUTH_EMULATOR_HOST !== undefined) return "EMULATOR_HOST_PRESENT";
  const resolved = await deps.resolveTarget();
  if (resolved.projectId !== PRODUCTION_PROJECT) return "CREDENTIAL_PROJECT_MISMATCH";
  if (resolved.databaseId !== PRODUCTION_DATABASE || resolved.bucketName !== PRODUCTION_BUCKET) return "TARGET_MISMATCH";
  if (!parsed.apply) return null;
  const v = parsed.values;
  const bucketConfig = await deps.observeBucketConfig();
  if (fence.sha256Hex(fence.TaskCanonicalV1(bucketConfig)) !== v["--bucket-config-sha256"]) return "BUCKET_CONFIG_DRIFT";
  const firestoreConfig = await deps.observeFirestoreConfig();
  if (fence.sha256Hex(fence.TaskCanonicalV1(firestoreConfig)) !== v["--firestore-config-sha256"]) return "FIRESTORE_CONFIG_DRIFT";
  if (fence.sha256Hex(deps.readFile(path.join(deps.repositoryRoot, "functions/package-lock.json"))) !== deps.acceptedPackageLockSha256()) return "PACKAGE_LOCK_DRIFT";
  return null;
}

/** The barrier: active blocker config etag plus the Admin freeze policy digest, re-read before every mutation. */
async function requireBarrier(deps, checkpoint) {
  const observed = await deps.observeBarrier();
  if (!isPlainMap(observed) || !HEX64_RE.test(String(observed.activeConfigSha256)) || !HEX64_RE.test(String(observed.priorConfigSha256)) || typeof observed.etag !== "string" || !observed.etag) throw invariant("ACCOUNT_DELETION_LEGACY_BARRIER_DRIFT", "observation");
  if (checkpoint && (observed.activeConfigSha256 !== checkpoint.auth_blocker_config_sha256 || observed.priorConfigSha256 !== checkpoint.auth_blocker_prior_config_sha256)) throw invariant("ACCOUNT_DELETION_LEGACY_BARRIER_DRIFT", "config");
  return observed;
}

/** Pre-source-0 and pre-confirmation gate: the accepted destination arrays' horizons and the post-cutoff global zero match. */
async function requireGate(deps) {
  const evidence = deps.evidence();
  if (!evidence || evidence.ok !== true) throw invariant("PROVIDER_EVIDENCE_NOT_ACTIVATED");
  const gate = await deps.observeGate();
  if (!isPlainMap(gate) || gate.postCutoffMatchCount !== 0 || !Number.isFinite(gate.horizonSeconds) || gate.horizonSeconds < 0 || gate.unboundedDestinations !== 0) throw invariant("ACCOUNT_DELETION_LEGACY_GATE_FAILED");
  return evidence.authority;
}

// ---------------------------------------------------------------------------
// Audit
// ---------------------------------------------------------------------------

async function runAudit(deps, pageSize) {
  const page = await sourcePage(deps, 0, { kind: "start" }, pageSize);
  return { sourceOrdinal: 0, pageSize, count: page.uids.length, uidDigests: page.uids.map((uid) => digestOf(uid)), terminal: page.done, registrySha256: SOURCE_REGISTRY_SHA256 };
}

// ---------------------------------------------------------------------------
// Apply: checkpoint state machine
// ---------------------------------------------------------------------------

function checkpointRef(deps) { return deps.db.doc(CHECKPOINT_PATH); }
function candidateRef(deps, uid) { return deps.db.doc(`${CANDIDATES}/${candidateId(uid)}`); }

async function readCheckpoint(transaction, deps) {
  const snapshot = await transaction.get(checkpointRef(deps));
  return snapshot.exists ? validateCheckpoint(snapshot.data()) : null;
}

function updatedCheckpoint(current, patch, readTime) {
  const next = { ...current, ...patch, updated_at: readTime };
  validateCheckpoint(next);
  return next;
}

/** A checkpoint CAS: rereads, requires byte equality with the expected checkpoint, applies `mutate`, writes. */
async function checkpointTransaction(deps, expected, mutate) {
  return deps.db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(checkpointRef(deps));
    if (!snapshot.exists) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "checkpoint absent");
    const current = validateCheckpoint(snapshot.data());
    if (fence.TaskCanonicalV1(stripTimes(current)) !== fence.TaskCanonicalV1(stripTimes(expected)) || current.updated_at.toMillis() !== expected.updated_at.toMillis()) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "checkpoint drift");
    const readTime = fence.readTimeOf(snapshot, deps);
    const patch = await mutate(transaction, current, readTime);
    if (patch === null) return current;
    if (patch === "delete") { transaction.delete(checkpointRef(deps)); return null; }
    const next = updatedCheckpoint(current, patch, readTime);
    transaction.update(checkpointRef(deps), next);
    return next;
  });
}

function stripTimes(map) { const copy = { ...map }; delete copy.created_at; delete copy.updated_at; return copy; }

async function createCheckpoint(deps, parsed, authority, barrier) {
  const v = parsed.values;
  const readFile = deps.readFile;
  const implementation = sealer.implementationDigest(readFile, deps.repositoryRoot);
  const scriptSha = fence.sha256Hex(readFile(path.join(deps.repositoryRoot, "functions/scripts/purgeLegacyDeletedAccounts.js")));
  return deps.db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(checkpointRef(deps));
    if (snapshot.exists) return validateCheckpoint(snapshot.data());
    const readTime = fence.readTimeOf(snapshot, deps);
    const checkpoint = {
      schema_version: 1, kind: "ACCOUNT_DELETION_LEGACY_MIGRATION", generation_id: deps.generationId(), project_id: PRODUCTION_PROJECT, database_id: PRODUCTION_DATABASE, bucket_name: PRODUCTION_BUCKET,
      status: "discovering", pass_ordinal: 0, source_ordinal: 0, source_cursor: { kind: "start" }, pass_candidate_count: 0, reduction_round: 0, reduction_cursor_id: "", reduction_deferred_count: 0, confirmation_zero_passes: 0,
      authority_generation_id: authority.generationId, authority_sha256: authority.authoritySHA256, implementation_sha256: implementation, source_registry_sha256: SOURCE_REGISTRY_SHA256,
      package_lock_sha256: fence.sha256Hex(readFile(path.join(deps.repositoryRoot, "functions/package-lock.json"))), script_sha256: scriptSha,
      drain_evidence_sha256: v["--drain-evidence-sha256"], auth_freeze_evidence_sha256: v["--auth-freeze-evidence-sha256"], auth_blocker_config_sha256: barrier.activeConfigSha256, auth_blocker_prior_config_sha256: barrier.priorConfigSha256,
      created_at: readTime, updated_at: readTime
    };
    validateCheckpoint(checkpoint);
    transaction.create(checkpointRef(deps), checkpoint);
    return checkpoint;
  });
}

/** Restart binding: every identity/evidence/implementation/registry/package digest must agree with the checkpoint. */
function requireCheckpointBinding(checkpoint, deps, parsed, authority) {
  const v = parsed.values;
  const bad = (detail) => invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", `binding ${detail}`);
  if (checkpoint.authority_generation_id !== authority.generationId || checkpoint.authority_sha256 !== authority.authoritySHA256) throw bad("authority");
  if (checkpoint.implementation_sha256 !== sealer.implementationDigest(deps.readFile, deps.repositoryRoot)) throw bad("implementation");
  if (checkpoint.source_registry_sha256 !== SOURCE_REGISTRY_SHA256) throw bad("registry");
  if (checkpoint.package_lock_sha256 !== fence.sha256Hex(deps.readFile(path.join(deps.repositoryRoot, "functions/package-lock.json")))) throw bad("package-lock");
  if (checkpoint.script_sha256 !== fence.sha256Hex(deps.readFile(path.join(deps.repositoryRoot, "functions/scripts/purgeLegacyDeletedAccounts.js")))) throw bad("script");
  if (checkpoint.drain_evidence_sha256 !== v["--drain-evidence-sha256"] || checkpoint.auth_freeze_evidence_sha256 !== v["--auth-freeze-evidence-sha256"]) throw bad("evidence");
}

/** Discovering: one settled page per commit (candidate upserts + cursor) after a fresh barrier read. */
async function discoverStep(deps, checkpoint) {
  const ordinal = checkpoint.source_ordinal;
  await requireBarrier(deps, checkpoint);
  const page = await sourcePage(deps, ordinal, checkpoint.source_cursor, PAGE_SIZE);
  const uids = [...new Set(page.uids)];
  return checkpointTransaction(deps, checkpoint, async (transaction, current, readTime) => {
    let created = 0;
    const refs = uids.map((uid) => candidateRef(deps, uid));
    const snapshots = await Promise.all(refs.map((ref) => transaction.get(ref)));
    snapshots.forEach((snapshot, i) => {
      if (snapshot.exists) { validateCandidate(snapshot.data(), refs[i].id); return; }
      const row = { schema_version: 1, kind: "ACCOUNT_DELETION_LEGACY_CANDIDATE", candidate_id: refs[i].id, account_uid: uids[i], first_pass_ordinal: current.pass_ordinal, created_at: readTime, updated_at: readTime, disposition: "pending", last_check_result: "unexamined", last_checked_at: null };
      validateCandidate(row, refs[i].id);
      transaction.create(refs[i], row);
      created += 1;
    });
    const lastRow = ordinal === ACCOUNT_DELETION_LEGACY_SOURCES_V1.length - 1;
    const advance = page.done
      ? (lastRow ? { status: "reducing", reduction_cursor_id: "", source_ordinal: ordinal + 1, source_cursor: { kind: "start" } } : { source_ordinal: ordinal + 1, source_cursor: { kind: "start" } })
      : { source_ordinal: ordinal, source_cursor: page.next };
    return { ...advance, pass_candidate_count: current.pass_candidate_count + created };
  });
}

function candidatesQuery(deps, afterId) {
  const ordered = deps.db.collection(CANDIDATES).orderBy(FieldPath.documentId(), "asc");
  return (afterId === "" ? ordered : ordered.startAfter(deps.db.doc(`${CANDIDATES}/${afterId}`))).limit(1);
}

async function authCheck(deps, uid) {
  try {
    await fence.withDeadline(deps.auth.getUser(uid), deps.timeouts.getUserMs, "ACCOUNT_DELETION_AUTH_TIMEOUT");
    return "present";
  } catch (error) {
    if (fence.isUserNotFound(error)) return "absent";
    return "ambiguous";
  }
}

async function rootState(deps, uid) {
  const snapshot = await deps.db.doc(`users/${uid}`).get();
  if (!snapshot.exists) return { kind: "absent" };
  const data = snapshot.data();
  if (data && data.accountDeletion !== undefined) {
    try { return { kind: "marker", ...fence.validateAccountDeletionMarker(data.accountDeletion) }; } catch (error) { return { kind: "malformed_marker" }; }
  }
  return { kind: "present" };
}

async function writeCandidate(deps, uid, mutate) {
  const ref = candidateRef(deps, uid);
  return deps.db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "candidate absent");
    const current = validateCandidate(snapshot.data(), ref.id);
    const readTime = fence.readTimeOf(snapshot, deps);
    const next = mutate(current, readTime);
    if (next === "delete") { transaction.delete(ref); return null; }
    validateCandidate(next, ref.id);
    transaction.set(ref, next);
    return next;
  });
}

const exclusion = (reason) => (current, readTime) => {
  const base = { schema_version: 1, kind: current.kind, candidate_id: current.candidate_id, account_uid: current.account_uid, first_pass_ordinal: current.first_pass_ordinal, created_at: current.created_at, updated_at: readTime };
  return { ...base, disposition: "excluded_live", exclusion_reason: reason, last_checked_at: readTime };
};

/** Drives an adopted candidate's marker through the cleanup core; DATA_DELETED enters AUTH_GUARDING on a fresh user-not-found. */
async function driveAdopted(deps, candidate) {
  const uid = candidate.account_uid;
  const root = await rootState(deps, uid);
  if (root.kind !== "marker") throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "adopted without marker");
  const capability = root.marker.capabilities.find((c) => c.operationId === candidate.operation_id);
  if (!capability || capability.proofSHA256 !== candidate.proof_sha256 || root.marker.startedAt.toMillis() !== candidate.marker_started_at.toMillis() || root.marker.capabilities.length !== 1) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "adopted marker disagreement");
  if (root.phase === "DELETING_SWEEPING") {
    const ctx = { uid, operationId: candidate.operation_id, rootRef: deps.db.doc(`users/${uid}`), startedMs: Date.now() };
    await fence.runSweepingReducer(deps.fenceDeps, ctx);
    return (await rootState(deps, uid)).phase;
  }
  if (root.phase === "DATA_DELETED") { await fence.enterHistoricalGuarding(deps.fenceDeps, { uid }); return "AUTH_GUARDING"; }
  return root.phase;
}

/** Reducing: one candidate per step with the advance-before-await cursor rule. */
async function reduceStep(deps, checkpoint, sweep) {
  const page = await candidatesQuery(deps, checkpoint.reduction_cursor_id).get();
  if (page.empty) {
    // end of a sweep (empty-after-nonempty wraps; empty-at-empty is trivially complete): the state condition decides
    const complete = await sweepComplete(deps);
    if (complete) return { checkpoint: await checkpointTransaction(deps, checkpoint, async () => ({ status: "waiting_guards", reduction_cursor_id: "" })), done: true };
    sweep.sawAny = false;
    return { checkpoint: await checkpointTransaction(deps, checkpoint, async () => ({ reduction_cursor_id: "", reduction_round: checkpoint.reduction_round + 1 })), done: false };
  }
  sweep.sawAny = true;
  const row = page.docs[0];
  let candidate = validateCandidate(row.data(), row.id);
  // advance the cursor to this ID before any Auth/provider/cleanup await
  const advanced = await checkpointTransaction(deps, checkpoint, async (transaction) => {
    const fresh = await transaction.get(row.ref);
    if (!fresh.exists) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "candidate vanished");
    candidate = validateCandidate(fresh.data(), row.id);
    return { reduction_cursor_id: row.id };
  });
  await requireBarrier(deps, advanced);
  const uid = candidate.account_uid;
  if (candidate.disposition === "adopted") {
    const phase = await driveAdopted(deps, candidate);
    return { checkpoint: advanced, done: false, outcome: `ADOPTED_${phase}` };
  }
  const auth1 = await authCheck(deps, uid);
  const root = await rootState(deps, uid);
  const ambiguous = (current, readTime) => ({ schema_version: 1, kind: current.kind, candidate_id: current.candidate_id, account_uid: current.account_uid, first_pass_ordinal: current.first_pass_ordinal, created_at: current.created_at, updated_at: readTime, disposition: "pending", last_check_result: "ambiguous", last_checked_at: readTime });
  if (auth1 === "ambiguous") {
    await writeCandidate(deps, uid, ambiguous);
    const deferred = await checkpointTransaction(deps, advanced, async () => ({ reduction_deferred_count: advanced.reduction_deferred_count + 1 }));
    return { checkpoint: deferred, done: false, outcome: "AMBIGUOUS" };
  }
  if (auth1 === "present") { await writeCandidate(deps, uid, exclusion("AUTH_PRESENT")); return { checkpoint: advanced, done: false, outcome: "AUTH_PRESENT" }; }
  if (root.kind === "present") { await writeCandidate(deps, uid, exclusion("ROOT_PRESENT")); return { checkpoint: advanced, done: false, outcome: "ROOT_PRESENT" }; }
  if (root.kind === "marker" && root.phase === "ACCOUNT_DELETED" && root.marker.capabilities.length === 1) {
    // an existing tombstone replays the same residual proof: adopt it under its own capability and let the waiting guard prove it
    const cap = root.marker.capabilities[0];
    await writeCandidate(deps, uid, (current, readTime) => ({ schema_version: 1, kind: current.kind, candidate_id: current.candidate_id, account_uid: uid, first_pass_ordinal: current.first_pass_ordinal, created_at: current.created_at, updated_at: readTime, disposition: "adopted", last_checked_at: readTime, operation_id: cap.operationId, proof_sha256: cap.proofSHA256, marker_started_at: root.marker.startedAt }));
    return { checkpoint: advanced, done: false, outcome: "TOMBSTONE_ADOPTED" };
  }
  if (root.kind === "marker" || root.kind === "malformed_marker") throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "pending with marker");
  const auth2 = await authCheck(deps, uid);
  if (auth2 !== "absent") {
    await writeCandidate(deps, uid, ambiguous);
    const deferred = await checkpointTransaction(deps, advanced, async () => ({ reduction_deferred_count: advanced.reduction_deferred_count + 1 }));
    return { checkpoint: deferred, done: false, outcome: "AMBIGUOUS" };
  }
  await requireBarrier(deps, advanced);
  // adoption: recheck root absence, then the fence creates the DELETING-sweeping marker and its work row
  const rootAgain = await rootState(deps, uid);
  if (rootAgain.kind !== "absent") throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "root race");
  const created = await fence.createMigrationMarker(deps.fenceDeps, { uid });
  const marker = await rootState(deps, uid);
  await writeCandidate(deps, uid, (current, readTime) => ({ schema_version: 1, kind: current.kind, candidate_id: current.candidate_id, account_uid: uid, first_pass_ordinal: current.first_pass_ordinal, created_at: current.created_at, updated_at: readTime, disposition: "adopted", last_checked_at: readTime, operation_id: created.operationId, proof_sha256: created.proofSHA256, marker_started_at: marker.marker.startedAt }));
  const auth3 = await authCheck(deps, uid);
  if (auth3 !== "absent") throw invariant("LEGACY_ACCOUNT_AUTH_RACE", uid.length > 0 ? digestOf(uid) : "");
  const adopted = validateCandidate((await candidateRef(deps, uid).get()).data(), candidateId(uid));
  const phase = await driveAdopted(deps, adopted);
  return { checkpoint: advanced, done: false, outcome: `ADOPTED_${phase}` };
}

/** One bounded page of candidate rows in document-ID order, after `after` (a snapshot) when given. */
function candidatePage(deps, after, size) {
  const ordered = deps.db.collection(CANDIDATES).orderBy(FieldPath.documentId(), "asc");
  return (after === null ? ordered : ordered.startAfter(after)).limit(size).get();
}

/** Bounded walk over the candidate rows (100 per page, one resident page): returns the first row for which `test` is true, else null. */
async function findCandidate(deps, test) {
  let after = null;
  for (;;) {
    const page = await candidatePage(deps, after, CLEANUP_PAGE);
    for (const row of page.docs) {
      const candidate = validateCandidate(row.data(), row.id);
      if (await test(candidate)) return candidate;
    }
    if (page.docs.length < CLEANUP_PAGE) return null;
    after = page.docs[page.docs.length - 1];
  }
}

/** A complete sweep: zero pending/ambiguous and every adopted candidate's marker carries firestoreCleanupAt. */
async function sweepComplete(deps) {
  const blocking = await findCandidate(deps, async (candidate) => {
    if (candidate.disposition === "pending") return true;
    if (candidate.disposition !== "adopted") return false;
    const root = await rootState(deps, candidate.account_uid);
    return root.kind !== "marker" || !["DELETING_GUARDING", "DATA_DELETED", "AUTH_GUARDING", "ACCOUNT_DELETED"].includes(root.phase);
  });
  return blocking === null;
}

/** UID-specific residue proof over all 23 adapters plus the injected global destination-zero proof. */
async function residueProof(deps, uid) {
  let residue = 0;
  for (const source of ACCOUNT_DELETION_LEGACY_SOURCES_V1) {
    if (source.kind === "firestore_raw") {
      const collectionPath = `${source.parent.slice(DOCUMENTS_PARENT.length + 1)}${source.parent === DOCUMENTS_PARENT ? "" : "/"}${source.collection_id}`;
      if (source.extract === "document_id") {
        const snapshot = await deps.db.doc(`${collectionPath}/${uid}`).get();
        if (snapshot.exists && !(source.id === "users_missing_roots" && snapshot.data().accountDeletion !== undefined && Object.keys(snapshot.data()).length === 1)) residue += 1;
        if (source.id === "users_missing_roots") { const children = await deps.db.doc(`users/${uid}`).listCollections(); if (children.length > 0) residue += children.length; }
      } else if (source.extract.startsWith("optional_string_field:")) {
        const field = source.extract.slice("optional_string_field:".length);
        const hits = await deps.db.collection(collectionPath).where(field, "==", uid).limit(1).get();
        if (!hits.empty) residue += 1;
      } else if (source.extract === "event_source_path_uid") {
        const hits = await deps.db.collection(collectionPath).where("sourcePath", ">=", `users/${uid}/events/`).where("sourcePath", "<", `users/${uid}/events0`).limit(1).get();
        if (!hits.empty) residue += 1;
      } else {
        const id = source.extract === "exact_storage_work_account_uid" ? fence.storageWorkId(uid) : fence.authWorkId(uid);
        const snapshot = await deps.db.doc(`${collectionPath}/${id}`).get();
        if (snapshot.exists) residue += 1;
      }
    } else if (source.kind === "singleton") {
      const snapshot = await deps.db.doc(source.path).get();
      if (singletonUids(source, snapshot.exists ? snapshot.data() : undefined).includes(uid)) residue += 1;
    } else {
      const page = await storagePage(deps, { ...source, prefix: `${source.prefix}${uid}/` }, 1, undefined);
      if (page.uids.length > 0) residue += 1;
    }
  }
  const global = await deps.globalZeroProof(uid);
  if (!isPlainMap(global) || global.matchCount !== 0) residue += 1;
  return residue;
}

/** Waiting guards: adopted candidates with the exact ACCOUNT_DELETED tombstone are proved residue-free and deleted. */
async function waitingStep(deps, checkpoint, sweep) {
  const page = await candidatesQuery(deps, checkpoint.reduction_cursor_id).get();
  if (page.empty) {
    const blocking = (await findCandidate(deps, async (candidate) => candidate.disposition !== "excluded_live")) !== null;
    if (!blocking) return { checkpoint: await checkpointTransaction(deps, checkpoint, async () => ({ status: "confirming", reduction_cursor_id: "", source_ordinal: 0, source_cursor: { kind: "start" }, confirmation_zero_passes: 0 })), done: true };
    sweep.sawAny = false;
    return { checkpoint: await checkpointTransaction(deps, checkpoint, async () => ({ reduction_cursor_id: "", reduction_round: checkpoint.reduction_round + 1 })), done: false };
  }
  sweep.sawAny = true;
  const row = page.docs[0];
  let candidate = validateCandidate(row.data(), row.id);
  const advanced = await checkpointTransaction(deps, checkpoint, async (transaction) => { const fresh = await transaction.get(row.ref); if (!fresh.exists) throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "candidate vanished"); candidate = validateCandidate(fresh.data(), row.id); return { reduction_cursor_id: row.id }; });
  if (candidate.disposition !== "adopted") return { checkpoint: advanced, done: false, outcome: "RETAINED" };
  const root = await rootState(deps, candidate.account_uid);
  if (root.kind !== "marker" || root.phase !== "ACCOUNT_DELETED") return { checkpoint: advanced, done: false, outcome: "RETAINED" };
  await requireBarrier(deps, advanced);
  const residue = await residueProof(deps, candidate.account_uid);
  if (residue !== 0) return { checkpoint: advanced, done: false, outcome: "RESIDUE" };
  await writeCandidate(deps, candidate.account_uid, () => "delete");
  return { checkpoint: advanced, done: false, outcome: "DELETED" };
}

/** The failure transition out of confirming: reducing at ordinal 23, both cursors reset, count 0. */
function confirmationFailure() {
  return { status: "reducing", reduction_cursor_id: "", source_ordinal: ACCOUNT_DELETION_LEGACY_SOURCES_V1.length, source_cursor: { kind: "start" }, confirmation_zero_passes: 0 };
}

/** Bounded walk over every candidate row (100 per page): a non-excluded row or a stale exclusion fails the pass. */
async function excludedRowsStillTrue(deps) {
  let after = null;
  for (;;) {
    const page = await candidatePage(deps, after, CLEANUP_PAGE);
    for (const row of page.docs) {
      const candidate = validateCandidate(row.data(), row.id);
      if (candidate.disposition !== "excluded_live") return "NON_EXCLUDED_CANDIDATE";
      const auth = await authCheck(deps, candidate.account_uid);
      const root = await rootState(deps, candidate.account_uid);
      const stillTrue = candidate.exclusion_reason === "AUTH_PRESENT" ? auth === "present" : root.kind === "present";
      if (!stillTrue) return "EXCLUSION_DRIFT";
    }
    if (page.docs.length < CLEANUP_PAGE) return null;
    after = page.docs[page.docs.length - 1];
  }
}

/**
 * Confirming: one source page per step from row 0 `{kind:"start"}`, the checkpoint's source position advancing under
 * the confirming grammar; every UID on the page is a still-true excluded-live candidate or a residue-free ACCOUNT_DELETED
 * tombstone, anything else fails the pass; the barrier is re-read before every confirmation-page commit; the last page of
 * row 22 walks the candidate rows in bounded pages, counts the zero pass, and restarts at row 0 (two passes, then cleanup).
 */
async function confirmationPage(deps, checkpoint) {
  await requireGate(deps);
  const ordinal = checkpoint.source_ordinal;
  const page = await sourcePage(deps, ordinal, checkpoint.source_cursor, PAGE_SIZE);
  for (const uid of [...new Set(page.uids)]) {
    const snapshot = await candidateRef(deps, uid).get();
    if (snapshot.exists) {
      const candidate = validateCandidate(snapshot.data(), snapshot.id);
      if (candidate.disposition !== "excluded_live") return { ok: false, reason: "NON_EXCLUDED_CANDIDATE" };
      const auth = await authCheck(deps, uid);
      const root = await rootState(deps, uid);
      const stillTrue = candidate.exclusion_reason === "AUTH_PRESENT" ? auth === "present" : root.kind === "present";
      if (!stillTrue) return { ok: false, reason: "EXCLUSION_DRIFT" };
      continue;
    }
    // a permanent ACCOUNT_DELETED tombstone is the migration's own terminal residue: acceptable only with a zero residue proof
    const root = await rootState(deps, uid);
    if (root.kind === "marker" && root.phase === "ACCOUNT_DELETED" && (await residueProof(deps, uid)) === 0) continue;
    return { ok: false, reason: "NEW_UID" };
  }
  const lastRow = ordinal === ACCOUNT_DELETION_LEGACY_SOURCES_V1.length - 1;
  if (!(page.done && lastRow)) return { ok: true, complete: false, advance: page.done ? { source_ordinal: ordinal + 1, source_cursor: { kind: "start" } } : { source_ordinal: ordinal, source_cursor: page.next } };
  const rows = await excludedRowsStillTrue(deps);
  if (rows !== null) return { ok: false, reason: rows };
  return { ok: true, complete: true };
}

/** Excluded-live cleanup: <= 100 rows per transaction rereading each row and its exclusion authority; drift returns to reducing. */
async function cleanupExcluded(deps, checkpoint) {
  let current = checkpoint;
  for (;;) {
    const page = await deps.db.collection(CANDIDATES).orderBy(FieldPath.documentId(), "asc").limit(CLEANUP_PAGE).get();
    if (page.empty) break;
    const authorities = new Map();
    for (const row of page.docs) {
      const candidate = validateCandidate(row.data(), row.id);
      authorities.set(row.id, { auth: await authCheck(deps, candidate.account_uid), root: await rootState(deps, candidate.account_uid) });
    }
    await requireBarrier(deps, current);
    let drifted = false;
    current = await checkpointTransaction(deps, current, async (transaction) => {
      const fresh = await Promise.all(page.docs.map((row) => transaction.get(row.ref)));
      fresh.forEach((snapshot, i) => {
        if (!snapshot.exists) return;
        const candidate = validateCandidate(snapshot.data(), page.docs[i].id);
        const before = fence.TaskCanonicalV1({ ...page.docs[i].data(), created_at: null, updated_at: null, last_checked_at: null });
        const after = fence.TaskCanonicalV1({ ...snapshot.data(), created_at: null, updated_at: null, last_checked_at: null });
        const authority = authorities.get(page.docs[i].id);
        const stillTrue = candidate.disposition === "excluded_live" && (candidate.exclusion_reason === "AUTH_PRESENT" ? authority.auth === "present" : authority.root.kind === "present");
        if (before !== after || !stillTrue) { drifted = true; return; }
        transaction.delete(page.docs[i].ref);
      });
      return drifted ? { status: "reducing", reduction_cursor_id: "", source_ordinal: ACCOUNT_DELETION_LEGACY_SOURCES_V1.length, source_cursor: { kind: "start" }, confirmation_zero_passes: 0 } : {};
    });
    if (drifted) return { checkpoint: current, drifted: true };
    if (page.docs.length < CLEANUP_PAGE) break;
  }
  const probe = await deps.db.collection(CANDIDATES).orderBy(FieldPath.documentId(), "asc").limit(1).get();
  if (!probe.empty) return { checkpoint: current, drifted: false, remaining: true };
  const deleted = await checkpointTransaction(deps, current, async () => "delete");
  return { checkpoint: deleted, drifted: false, remaining: false, completed: true };
}

async function confirmStep(deps, checkpoint) {
  const page = await confirmationPage(deps, checkpoint);
  await requireBarrier(deps, checkpoint); // re-read before every confirmation-page commit (failure, advance, or count)
  if (!page.ok) return { checkpoint: await checkpointTransaction(deps, checkpoint, async () => confirmationFailure()), done: false, outcome: page.reason };
  if (!page.complete) return { checkpoint: await checkpointTransaction(deps, checkpoint, async () => page.advance), done: false, outcome: "PAGE" };
  const counted = await checkpointTransaction(deps, checkpoint, async () => ({ source_ordinal: 0, source_cursor: { kind: "start" }, confirmation_zero_passes: checkpoint.confirmation_zero_passes + 1 }));
  if (counted.confirmation_zero_passes < 2) return { checkpoint: counted, done: false, outcome: "ZERO_PASS" };
  const cleanup = await cleanupExcluded(deps, counted);
  if (cleanup.drifted) return { checkpoint: cleanup.checkpoint, done: false, outcome: "CLEANUP_DRIFT" };
  if (cleanup.remaining) return { checkpoint: cleanup.checkpoint, done: false, outcome: "CLEANUP_REMAINING" };
  return { checkpoint: null, done: true, outcome: "COMPLETED" };
}

/** Drives the checkpoint until completion or the step budget; every step is resumable from the durable checkpoint. */
async function runApply(deps, parsed, { maxSteps = 10000 } = {}) {
  const authority = await requireGate(deps);
  const barrier = await requireBarrier(deps, null);
  let checkpoint = await createCheckpoint(deps, parsed, authority, barrier);
  requireCheckpointBinding(checkpoint, deps, parsed, authority);
  await requireBarrier(deps, checkpoint);
  const outcomes = { discovered: 0, reduced: {}, waited: {}, confirmed: [] };
  const sweep = { sawAny: false };
  for (let step = 0; step < maxSteps && checkpoint !== null; step += 1) {
    if (checkpoint.status === "discovering") { checkpoint = await discoverStep(deps, checkpoint); outcomes.discovered += 1; continue; }
    if (checkpoint.status === "reducing") { const r = await reduceStep(deps, checkpoint, sweep); checkpoint = r.checkpoint; if (r.outcome) outcomes.reduced[r.outcome] = (outcomes.reduced[r.outcome] || 0) + 1; continue; }
    if (checkpoint.status === "waiting_guards") { const r = await waitingStep(deps, checkpoint, sweep); checkpoint = r.checkpoint; if (r.outcome) outcomes.waited[r.outcome] = (outcomes.waited[r.outcome] || 0) + 1; continue; }
    if (checkpoint.status === "confirming") { const r = await confirmStep(deps, checkpoint); checkpoint = r.checkpoint; outcomes.confirmed = [...outcomes.confirmed, r.outcome]; continue; }
    throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "status");
  }
  return { completed: checkpoint === null, status: checkpoint ? checkpoint.status : "completed", outcomes };
}

// ---------------------------------------------------------------------------
// Report and entry point
// ---------------------------------------------------------------------------

function reportOf(parsed, refusal, result) {
  return { schemaVersion: 1, kind: "ACCOUNT_DELETION_LEGACY_MIGRATION_REPORT", mode: parsed.apply ? "apply" : "audit", refusal, registrySha256: SOURCE_REGISTRY_SHA256, result: result || null };
}

function defaultDependencies() {
  const admin = require("firebase-admin");
  return {
    env: process.env,
    readFile: (file) => fs.readFileSync(file),
    repositoryRoot: path.resolve(__dirname, "../.."),
    generationId: () => require("node:crypto").randomUUID().toLowerCase(),
    acceptedPackageLockSha256: () => fence.sha256Hex(fs.readFileSync(path.resolve(__dirname, "../package-lock.json"))),
    resolveTarget: async () => { const { v1 } = require("@google-cloud/firestore"); const client = new v1.FirestoreClient({}); const projectId = await client.getProjectId(); await client.close(); return { projectId, databaseId: PRODUCTION_DATABASE, bucketName: PRODUCTION_BUCKET }; },
    observeBucketConfig: async () => fence.projectBucketDeletionConfig((await admin.storage().bucket(PRODUCTION_BUCKET).getMetadata())[0]),
    observeFirestoreConfig: async () => { throw invariant("ACCOUNT_DELETION_LEGACY_MIGRATION_INVARIANT", "firestore config observer not wired"); },
    observeBarrier: async () => { throw invariant("ACCOUNT_DELETION_LEGACY_BARRIER_DRIFT", "barrier observer not wired"); },
    observeGate: async () => { throw invariant("ACCOUNT_DELETION_LEGACY_GATE_FAILED", "gate observer not wired"); },
    globalZeroProof: async () => ({ matchCount: 1 }),
    timeouts: { getUserMs: 3000 }
  };
}

async function run(argv, overrides = {}) {
  const deps = { ...defaultDependencies(), ...overrides };
  const parsed = parseArguments(argv);
  const refusal = argumentRefusal(parsed);
  if (refusal !== null) return { exitCode: 2, report: reportOf(parsed, refusal, null) };
  let environment;
  try { environment = await environmentRefusal(parsed, deps); } catch (error) { return { exitCode: 3, report: reportOf(parsed, error && error.code ? error.code : "ENVIRONMENT_FAILURE", null) }; }
  if (environment !== null) return { exitCode: 3, report: reportOf(parsed, environment, null) };
  try {
    if (!parsed.apply) {
      const pageSize = parsed.values["--page-size"] !== undefined ? Number(parsed.values["--page-size"]) : PAGE_SIZE;
      return { exitCode: 0, report: reportOf(parsed, null, await runAudit(deps, pageSize)) };
    }
    const result = await runApply(deps, parsed);
    return { exitCode: result.completed ? 0 : 1, report: reportOf(parsed, null, result) };
  } catch (error) {
    return { exitCode: 1, report: reportOf(parsed, error && error.code ? error.code : "ACCOUNT_DELETION_LEGACY_MIGRATION_FAILED", null) };
  }
}

async function main() {
  const { exitCode, report } = await run(process.argv.slice(2));
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  process.exitCode = exitCode;
}

if (require.main === module) main().catch((error) => { process.stderr.write(`${error && error.code ? error.code : "ACCOUNT_DELETION_LEGACY_MIGRATION_FAILED"}\n`); process.exitCode = 1; });

module.exports = {
  ACCOUNT_DELETION_LEGACY_SOURCES_V1, SOURCE_REGISTRY_SHA256, CHECKPOINT_PATH, CANDIDATES, CHECKPOINT_KEYS, PAGE_SIZE, MigrationInvariant,
  candidateId, isCanonicalUid, validateCursor, validateCheckpoint, validateCandidate, extractUids, singletonUids, listPage, storagePage, sourcePage,
  parseArguments, argumentRefusal, environmentRefusal, requireBarrier, requireGate, runAudit, createCheckpoint, requireCheckpointBinding,
  discoverStep, reduceStep, waitingStep, confirmationPage, excludedRowsStillTrue, cleanupExcluded, confirmStep, residueProof, runApply, reportOf, run
};
