"use strict";

/**
 * PHASE2_CONTRACT.md C9.4.3 — purgeLegacyResolvedProviders.js (S2/S3 shared; import-side-effect-free).
 *
 * The pure core `auditAndPurgeLegacyResolvedProviders({ db, apply, emit })` receives an injected Firestore adapter
 * and holds no project, environment, exit, or argv authority. Only exact complete `source:"seeded"` rows survive;
 * every non-seeded row (absent source, malformed, resolved) is deleted after a bounded transactional reread.
 * Termination requires two fresh complete passes that observe zero non-seeded rows.
 *
 * The CLI (`require.main === module` only) runs every production guard before the core: the literal arming set,
 * public-v1 client identity, and the emulator variable; the default mode is a read-only audit.
 */

const { createHash } = require("node:crypto");
const { FieldPath } = require("firebase-admin/firestore");

const COLLECTION = "providerDirectory";
const PAGE_SIZE = 100;
const PRODUCTION_PROJECT = "peezy-1ecrdl";
const PRODUCTION_DATABASE = "(default)";
/** The pinned public-v1 Commit timeout; a write issued at timeout-minus-epsilon settles within this window after the last old execution ends. */
const SETTLE_WINDOW_MS = 60000;
const HEX64_RE = /^[0-9a-f]{64}$/;
const ARMING_FLAGS = Object.freeze(["--apply", "--project-id", "--confirm-project", "--drain-evidence-sha256"]);

class ProviderPurgeInvariant extends Error {
  constructor(code, detail) { super(detail ? `${code}: ${detail}` : code); this.code = code; this.detail = detail; }
}

function sha256Hex(text) { return createHash("sha256").update(text).digest("hex"); }
function pathDigest(path) { return sha256Hex(path); }

/** Byte-identical to resolveProvider.js's `isSeededDirectoryRow` (that file is S2-owned and exports no predicate). */
function isSeededDirectoryRow(row) {
  return row !== null && typeof row === "object" && !Array.isArray(row) && row.source === "seeded" &&
    typeof row.providerId === "string" && row.providerId.length > 0 && typeof row.name === "string" && row.name.length > 0;
}

function classifyRow(data) {
  if (isSeededDirectoryRow(data)) return "seeded";
  if (data === null || typeof data !== "object" || Array.isArray(data)) return "malformed";
  if (data.source === "resolved") return "resolved";
  if (data.source === undefined) return "absent";
  return "malformed";
}

/** One complete pass: limit(100) pages over a run-local full-document-path cursor, one resident page; returns per-class counts and digests. */
async function runPass(db, apply, emit) {
  const counts = { seeded: 0, resolved: 0, malformed: 0, absent: 0, deleted: 0, preserved: 0 };
  let deletedDigests = [];
  let cursor = null;
  for (;;) {
    let query = db.collection(COLLECTION).orderBy(FieldPath.documentId(), "asc");
    if (cursor !== null) query = query.startAfter(db.doc(cursor));
    const page = await query.limit(PAGE_SIZE).get();
    if (page.empty) break;
    for (const row of page.docs) {
      const klass = classifyRow(row.data());
      counts[klass] += 1;
      if (klass === "seeded") continue;
      if (!apply) continue;
      // pre-delete: a bounded transaction rereads the row; a seeded row is preserved byte-for-byte; anything else is deleted
      const outcome = await db.runTransaction(async (transaction) => {
        const fresh = await transaction.get(row.ref);
        if (!fresh.exists) return "gone";
        if (isSeededDirectoryRow(fresh.data())) return "preserved";
        transaction.delete(row.ref);
        return "deleted";
      });
      if (outcome === "deleted") { counts.deleted += 1; deletedDigests = [...deletedDigests, pathDigest(row.ref.path)]; }
      else if (outcome === "preserved") counts.preserved += 1;
    }
    if (page.docs.length < PAGE_SIZE) break;
    cursor = page.docs[page.docs.length - 1].ref.path;
  }
  if (typeof emit === "function") emit("PROVIDER_PURGE_PASS", { seeded: counts.seeded, resolved: counts.resolved, malformed: counts.malformed, absent: counts.absent, deleted: counts.deleted });
  return { counts, deletedDigests, nonSeeded: counts.resolved + counts.malformed + counts.absent };
}

/**
 * The pure core. Audit: one complete pass, zero writes. Apply: passes until two fresh consecutive complete passes
 * observe zero non-seeded rows (bounded by `maxPasses`, then `PROVIDER_PURGE_UNSETTLED`).
 */
async function auditAndPurgeLegacyResolvedProviders({ db, apply = false, emit, maxPasses = 8 } = {}) {
  if (!db || typeof db.collection !== "function") throw new ProviderPurgeInvariant("PROVIDER_PURGE_ADAPTER_INVALID");
  const passes = [];
  if (!apply) {
    const pass = await runPass(db, false, emit);
    passes[passes.length] = pass;
    return { mode: "audit", passes, nonSeededObserved: pass.nonSeeded, twoPass: false };
  }
  let zeroPasses = 0;
  for (let i = 0; i < maxPasses; i += 1) {
    const pass = await runPass(db, true, emit);
    passes[passes.length] = pass;
    if (pass.nonSeeded === 0) { zeroPasses += 1; if (zeroPasses === 2) return { mode: "apply", passes, nonSeededObserved: 0, twoPass: true }; }
    else zeroPasses = 0;
  }
  throw new ProviderPurgeInvariant("PROVIDER_PURGE_UNSETTLED", String(maxPasses));
}

// ---------------------------------------------------------------------------
// CLI guards (every guard precedes the core; no delete precedes all guards)
// ---------------------------------------------------------------------------

function parseArguments(argv) {
  const parsed = { apply: false, projectId: null, confirmProject: null, drainEvidenceSha256: null, unknown: [], duplicate: [] };
  const seen = new Set();
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!ARMING_FLAGS.includes(arg)) { parsed.unknown = [...parsed.unknown, arg]; continue; }
    if (seen.has(arg)) parsed.duplicate = [...parsed.duplicate, arg];
    seen.add(arg);
    if (arg === "--apply") { parsed.apply = true; continue; }
    const value = argv[i + 1];
    if (typeof value !== "string" || value.startsWith("--")) { parsed.unknown = [...parsed.unknown, arg]; continue; }
    i += 1;
    if (arg === "--project-id") parsed.projectId = value;
    else if (arg === "--confirm-project") parsed.confirmProject = value;
    else parsed.drainEvidenceSha256 = value;
  }
  return parsed;
}

/** Returns the first refusal token, or null when the arming set is complete and exact. */
function armingRefusal(parsed, env, resolved) {
  if (parsed.unknown.length > 0) return "UNKNOWN_ARGUMENT";
  if (parsed.duplicate.length > 0) return "DUPLICATE_ARGUMENT";
  if (env.FIRESTORE_EMULATOR_HOST !== undefined) return "EMULATOR_HOST_PRESENT";
  if (!parsed.apply) return null;
  if (parsed.projectId !== PRODUCTION_PROJECT) return "PROJECT_ID_MISMATCH";
  if (parsed.confirmProject !== PRODUCTION_PROJECT) return "CONFIRM_PROJECT_MISMATCH";
  if (typeof parsed.drainEvidenceSha256 !== "string" || !HEX64_RE.test(parsed.drainEvidenceSha256)) return "DRAIN_EVIDENCE_INVALID";
  if (!resolved || resolved.projectId !== PRODUCTION_PROJECT || resolved.databaseId !== PRODUCTION_DATABASE) return "RESOLVED_TARGET_MISMATCH";
  return null;
}

function reportOf(parsed, resolved, refusal, result) {
  return {
    schemaVersion: 1, kind: "PROVIDER_PURGE_RUN_REPORT", mode: parsed.apply ? "apply" : "audit",
    command: ["purgeLegacyResolvedProviders", ...(parsed.apply ? ["--apply"] : []), ...(parsed.projectId ? ["--project-id", parsed.projectId] : [])].join(" "),
    resolvedProject: resolved ? resolved.projectId : null, resolvedDatabase: resolved ? resolved.databaseId : null,
    drainEvidenceSha256: parsed.drainEvidenceSha256, refusal,
    result: result ? { twoPass: result.twoPass, nonSeededObserved: result.nonSeededObserved, passes: result.passes.map((p) => ({ counts: p.counts, deletedDigests: p.deletedDigests })) } : null
  };
}

function defaultDependencies() {
  const admin = require("firebase-admin");
  return {
    env: process.env,
    emit: (code, counts) => process.stderr.write(`${code} ${JSON.stringify(counts || {})}\n`),
    resolveTarget: async () => {
      const { v1 } = require("@google-cloud/firestore");
      const client = new v1.FirestoreClient({});
      const projectId = await client.getProjectId();
      await client.close();
      return { projectId, databaseId: PRODUCTION_DATABASE };
    },
    createDb: () => { if (!admin.apps.length) admin.initializeApp(); return admin.firestore(); }
  };
}

/** Guards first, then the pure core; any guard, read, transaction, or delete failure exits nonzero. */
async function run(argv, overrides = {}) {
  const deps = { ...defaultDependencies(), ...overrides };
  const parsed = parseArguments(argv);
  let refusal = armingRefusal(parsed, deps.env, null);
  if (refusal !== null && refusal !== "RESOLVED_TARGET_MISMATCH") return { exitCode: 2, report: reportOf(parsed, null, refusal, null) };
  const resolved = await deps.resolveTarget();
  refusal = armingRefusal(parsed, deps.env, resolved);
  if (refusal !== null) return { exitCode: 3, report: reportOf(parsed, resolved, refusal, null) };
  if (!parsed.apply && resolved.databaseId !== PRODUCTION_DATABASE) return { exitCode: 3, report: reportOf(parsed, resolved, "RESOLVED_TARGET_MISMATCH", null) };
  const db = deps.createDb();
  try {
    const result = await auditAndPurgeLegacyResolvedProviders({ db, apply: parsed.apply, emit: deps.emit });
    return { exitCode: parsed.apply && !result.twoPass ? 1 : 0, report: reportOf(parsed, resolved, null, result) };
  } catch (error) {
    return { exitCode: 1, report: reportOf(parsed, resolved, error && error.code ? error.code : "PROVIDER_PURGE_FAILED", null) };
  }
}

async function main() {
  const { exitCode, report } = await run(process.argv.slice(2));
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  process.exitCode = exitCode;
}

if (require.main === module) main().catch((error) => { process.stderr.write(`${error && error.code ? error.code : "PROVIDER_PURGE_FAILED"}\n`); process.exitCode = 1; });

module.exports = { COLLECTION, PAGE_SIZE, SETTLE_WINDOW_MS, ARMING_FLAGS, ProviderPurgeInvariant, isSeededDirectoryRow, classifyRow, runPass, auditAndPurgeLegacyResolvedProviders, parseArguments, armingRefusal, reportOf, run };
