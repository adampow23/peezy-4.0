"use strict";

/**
 * PHASE2_CONTRACT.md C9.4.4 — sealAccountDeletionProviderEvidence.js (S2/S3 shared; import-safe).
 *
 * The sole producer of `functions/accountDeletionProviderEvidenceV1.json`. `prepare` assembles the authority payload
 * from the owner's sealing input and prints the exact message bytes for offline Ed25519 signing; `seal` (once-only)
 * verifies the signature against the trust anchor, writes the canonical artifact without overwrite, and read-verifies
 * it through the fence's own loader. The trust anchor is a reviewed literal in this file and in accountDeletionFence.js;
 * while it is absent (Build A) the sealer refuses before any artifact creation.
 */

const fs = require("node:fs");
const path = require("node:path");
const { createHash, createPublicKey, verify: cryptoVerify } = require("node:crypto");
const fence = require("../accountDeletionFence");

/** Reviewed literal trust anchor (C9.4.4). Absent until the owner supplies the offline Ed25519 public key and its SHA-256. */
const SEALER_TRUST_ANCHOR_V1 = Object.freeze({ publicKeyBase64URL: null, sha256: null });
const ARTIFACT_RELATIVE_PATH = "functions/accountDeletionProviderEvidenceV1.json";
const AUTHORITY_DOMAIN = "peezy.account_deletion_provider_evidence.v1\0";
const IMPLEMENTATION_DOMAIN = "account_deletion_provider_implementation.v1";
const BUNDLE_CAP_BYTES = 67108864;
const ARTIFACT_CAP_BYTES = 131072;
const ED25519_SPKI_PREFIX = Buffer.from("302a300506032b6570032100", "hex");
const HEX64_RE = /^[0-9a-f]{64}$/;
const LOWERCASE_UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const WIRE_INSTANT_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

/** The implementation path set: base 22 plus the five additions, sorted by unsigned UTF-8 path; the artifact itself is the sole exclusion. */
const IMPLEMENTATION_PATHS_V1 = Object.freeze([
  "functions/accountDeletionFence.js", "functions/dispositionTriggers.js", "functions/entitlement.js", "functions/getWorkflowQualifying.js", "functions/index.js",
  "functions/notificationIntents.js", "functions/notifySupport.js", "functions/packageInventory.js", "functions/package-lock.json", "functions/package.json",
  "functions/peezyChat.js", "functions/processInventory.js", "functions/researchTask.js", "functions/resolveProvider.js",
  "functions/scripts/sealAccountDeletionProviderEvidence.js", "functions/spawnTasks.js", "functions/submitCheckIn.js", "functions/submitCheckInCore.js",
  "functions/supportAdmin.js", "functions/taskDisposition.js", "functions/taskPlan.js", "functions/validateSubscription.js",
  "functions/scripts/purgeLegacyDeletedAccounts.js", "functions/scripts/purgeLegacyResolvedProviders.js", "firestore.indexes.json", "firestore.rules", "storage.rules"
].sort((a, b) => Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"))));

const INPUT_KEYS = Object.freeze([
  "generationId", "region", "bucketConfig", "firestoreConfig",
  "storageDestinations", "firestoreDestinations", "authDestinations", "cloudAuditDestinations", "providerCopyDestinations",
  "copyProducerDeny", "policyChecks", "authResidualRetentionSeconds", "authResidualChecks",
  "firestoreRulesetId", "firestoreReleaseId", "storageRulesetId", "storageReleaseId",
  "activatedAt", "bundlePath", "postCutoffMatchCount", "backlogCount"
]);

class SealerRefusal extends Error {
  constructor(code, detail) { super(detail ? `${code}: ${detail}` : code); this.code = code; this.detail = detail; }
}

function sha256Hex(bytes) { return createHash("sha256").update(bytes).digest("hex"); }
function isPlainMap(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function refuse(code, detail) { throw new SealerRefusal(code, detail); }

/** AcceptedArrayDigestV1 over one complete destination array. */
function arrayDigest(array, label) {
  if (!Array.isArray(array) || array.length > 4096) refuse("SEALER_INPUT_INVALID", `${label} array`);
  const canonical = fence.TaskCanonicalV1(array);
  const canonicalBytes = Buffer.byteLength(canonical, "utf8");
  if (canonicalBytes > BUNDLE_CAP_BYTES) refuse("SEALER_INPUT_INVALID", `${label} bytes`);
  return { count: array.length, canonicalBytes, sha256: sha256Hex(canonical) };
}

/** implementationSHA256 over the raw bytes of every implementation path; a missing file refuses. */
function implementationDigest(readFile, root) {
  const files = IMPLEMENTATION_PATHS_V1.map((relative) => {
    let bytes;
    try { bytes = readFile(path.join(root, relative)); } catch (error) { refuse("SEALER_IMPLEMENTATION_FILE_MISSING", relative); }
    return { path: relative, sha256: sha256Hex(bytes) };
  });
  return sha256Hex(fence.TaskCanonicalV1({ domain: IMPLEMENTATION_DOMAIN, files }));
}

function validateInput(input) {
  if (!isPlainMap(input)) refuse("SEALER_INPUT_INVALID", "map");
  const keys = Object.keys(input).sort();
  const expected = [...INPUT_KEYS].sort();
  if (keys.length !== expected.length || keys.some((k, i) => k !== expected[i])) refuse("SEALER_INPUT_INVALID", "members");
  if (typeof input.generationId !== "string" || !LOWERCASE_UUID_RE.test(input.generationId)) refuse("SEALER_INPUT_INVALID", "generationId");
  if (input.region !== "us-central1") refuse("SEALER_INPUT_INVALID", "region");
  if (!isPlainMap(input.bucketConfig) || !isPlainMap(input.firestoreConfig) || !isPlainMap(input.copyProducerDeny)) refuse("SEALER_INPUT_INVALID", "config maps");
  if (!Array.isArray(input.policyChecks) || !Array.isArray(input.authResidualChecks)) refuse("SEALER_INPUT_INVALID", "checks");
  for (const key of ["firestoreRulesetId", "firestoreReleaseId", "storageRulesetId", "storageReleaseId"]) if (typeof input[key] !== "string" || !input[key].trim()) refuse("SEALER_INPUT_INVALID", key);
  if (typeof input.activatedAt !== "string" || !WIRE_INSTANT_RE.test(input.activatedAt)) refuse("SEALER_INPUT_INVALID", "activatedAt");
  if (typeof input.bundlePath !== "string" || !input.bundlePath) refuse("SEALER_INPUT_INVALID", "bundlePath");
  // C9.4.4 refusals before any artifact creation
  if (input.postCutoffMatchCount !== 0) refuse("SEALER_POST_CUTOFF_MATCHES", String(input.postCutoffMatchCount));
  if (input.backlogCount !== 0) refuse("SEALER_BACKLOG_NONZERO", String(input.backlogCount));
  if (!Number.isFinite(input.authResidualRetentionSeconds)) refuse("SEALER_RETENTION_NONFINITE", "authResidualRetentionSeconds");
  for (const check of input.authResidualChecks) if (!isPlainMap(check) || !Number.isFinite(check.retentionSeconds)) refuse("SEALER_RETENTION_NONFINITE", "check");
  return input;
}

/** Assembles the unsigned authority (every member but the three signature members) from the sealing input and the repository. */
function assembleUnsignedAuthority(input, { readFile, root, trustAnchor }) {
  validateInput(input);
  if (!trustAnchor || typeof trustAnchor.publicKeyBase64URL !== "string" || typeof trustAnchor.sha256 !== "string") refuse("TRUST_ANCHOR_ABSENT");
  const keyBytes = Buffer.from(trustAnchor.publicKeyBase64URL, "base64url");
  if (keyBytes.length !== 32 || keyBytes.toString("base64url") !== trustAnchor.publicKeyBase64URL || sha256Hex(keyBytes) !== trustAnchor.sha256) refuse("TRUST_ANCHOR_INVALID");
  const bundle = readFile(path.isAbsolute(input.bundlePath) ? input.bundlePath : path.join(root, input.bundlePath));
  if (!Buffer.isBuffer(bundle) || bundle.length === 0 || bundle.length > BUNDLE_CAP_BYTES) refuse("SEALER_BUNDLE_INVALID", String(bundle && bundle.length));
  const raw = (relative) => readFile(path.join(root, relative));
  return {
    schemaVersion: 1, kind: "ACCOUNT_DELETION_PROVIDER_EVIDENCE",
    generationId: input.generationId, projectId: "peezy-1ecrdl", databaseId: "(default)", bucketName: "peezy-1ecrdl.firebasestorage.app", region: input.region,
    implementationSHA256: implementationDigest(readFile, root), packageLockSHA256: sha256Hex(raw("functions/package-lock.json")),
    firestoreRulesSHA256: sha256Hex(raw("firestore.rules")), storageRulesSHA256: sha256Hex(raw("storage.rules")), firestoreIndexesSHA256: sha256Hex(raw("firestore.indexes.json")),
    firestoreRulesetId: input.firestoreRulesetId, firestoreReleaseId: input.firestoreReleaseId, storageRulesetId: input.storageRulesetId, storageReleaseId: input.storageReleaseId,
    bucketConfig: input.bucketConfig, bucketConfigSHA256: sha256Hex(fence.TaskCanonicalV1(input.bucketConfig)),
    firestoreConfig: input.firestoreConfig, firestoreConfigSHA256: sha256Hex(fence.TaskCanonicalV1(input.firestoreConfig)),
    storageDestinations: arrayDigest(input.storageDestinations, "storage"), firestoreDestinations: arrayDigest(input.firestoreDestinations, "firestore"),
    authDestinations: arrayDigest(input.authDestinations, "auth"), cloudAuditDestinations: arrayDigest(input.cloudAuditDestinations, "cloudAudit"),
    providerCopyDestinations: arrayDigest(input.providerCopyDestinations, "providerCopy"),
    copyProducerDenySHA256: sha256Hex(fence.TaskCanonicalV1(input.copyProducerDeny)), policyChecks: input.policyChecks,
    authResidualRetentionSeconds: input.authResidualRetentionSeconds, authResidualChecks: input.authResidualChecks,
    signatureAlgorithm: "ed25519", externalEvidenceBundleSHA256: sha256Hex(bundle),
    externalEvidencePublicKeyBase64URL: trustAnchor.publicKeyBase64URL, externalEvidenceSigningKeySHA256: trustAnchor.sha256,
    activatedAt: input.activatedAt
  };
}

function payloadDigest(unsigned) { return sha256Hex(fence.TaskCanonicalV1(unsigned)); }

function signedMessage(unsigned) {
  const payload = payloadDigest(unsigned);
  return { payload, message: Buffer.concat([Buffer.from(AUTHORITY_DOMAIN, "ascii"), Buffer.from(payload, "hex"), Buffer.from(unsigned.externalEvidenceBundleSHA256, "hex"), Buffer.from(unsigned.implementationSHA256, "hex")]) };
}

/** `prepare`: the exact payload digest and message bytes for offline signing; writes nothing. */
function prepare(input, deps) {
  const unsigned = assembleUnsignedAuthority(input, deps);
  const { payload, message } = signedMessage(unsigned);
  return { signedAuthorityPayloadSHA256: payload, messageHex: message.toString("hex"), implementationSHA256: unsigned.implementationSHA256, externalEvidenceBundleSHA256: unsigned.externalEvidenceBundleSHA256 };
}

/** Completes the map with the signature members; the signature must verify against the trust anchor before any write. */
function completeAuthority(unsigned, signatureBase64URL, trustAnchor) {
  if (typeof signatureBase64URL !== "string" || Buffer.from(signatureBase64URL, "base64url").length !== 64 || Buffer.from(signatureBase64URL, "base64url").toString("base64url") !== signatureBase64URL) refuse("SEALER_SIGNATURE_INVALID", "encoding");
  const { payload, message } = signedMessage(unsigned);
  const publicKey = createPublicKey({ key: Buffer.concat([ED25519_SPKI_PREFIX, Buffer.from(trustAnchor.publicKeyBase64URL, "base64url")]), format: "der", type: "spki" });
  if (!cryptoVerify(null, message, publicKey, Buffer.from(signatureBase64URL, "base64url"))) refuse("SEALER_SIGNATURE_INVALID", "verify");
  const withSignature = { ...unsigned, signedAuthorityPayloadSHA256: payload, externalEvidenceSignatureBase64URL: signatureBase64URL };
  return { ...withSignature, authoritySHA256: sha256Hex(fence.TaskCanonicalV1(withSignature)) };
}

/** `seal`: once-only artifact creation without overwrite, then read-verification through the fence loader. */
function seal(input, signatureBase64URL, deps) {
  const unsigned = assembleUnsignedAuthority(input, deps);
  const authority = completeAuthority(unsigned, signatureBase64URL, deps.trustAnchor);
  const bytes = Buffer.from(fence.TaskCanonicalV1(authority), "utf8");
  if (bytes.length > ARTIFACT_CAP_BYTES) refuse("SEALER_ARTIFACT_OVER_CAP", String(bytes.length));
  const preflight = fence.loadProviderEvidenceAuthority(bytes, { trustAnchor: deps.trustAnchor });
  if (!preflight.ok) refuse("SEALER_ARTIFACT_INVALID", preflight.code);
  const artifactPath = path.join(deps.root, ARTIFACT_RELATIVE_PATH);
  try {
    deps.writeFileExclusive(artifactPath, bytes);
  } catch (error) {
    if (error && error.code === "EEXIST") refuse("SEALER_ARTIFACT_EXISTS", ARTIFACT_RELATIVE_PATH);
    throw error;
  }
  const written = deps.readFile(artifactPath);
  const verified = fence.loadProviderEvidenceAuthority(written, { trustAnchor: deps.trustAnchor });
  if (!written.equals(bytes) || !verified.ok || verified.authority.authoritySHA256 !== authority.authoritySHA256) refuse("SEALER_READ_VERIFY_FAILED");
  return { artifactPath: ARTIFACT_RELATIVE_PATH, authoritySHA256: authority.authoritySHA256, signedAuthorityPayloadSHA256: authority.signedAuthorityPayloadSHA256, bytes: bytes.length };
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function parseArguments(argv) {
  const parsed = { mode: null, input: null, signature: null, unknown: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--prepare" || arg === "--seal") { if (parsed.mode !== null) parsed.unknown = [...parsed.unknown, arg]; parsed.mode = arg.slice(2); continue; }
    if (arg === "--input" || arg === "--signature") {
      const value = argv[i + 1];
      if (typeof value !== "string" || value.startsWith("--")) { parsed.unknown = [...parsed.unknown, arg]; continue; }
      i += 1;
      if (arg === "--input") parsed.input = value; else parsed.signature = value;
      continue;
    }
    parsed.unknown = [...parsed.unknown, arg];
  }
  return parsed;
}

function defaultDependencies() {
  return {
    root: path.resolve(__dirname, "../.."),
    readFile: (file) => fs.readFileSync(file),
    writeFileExclusive: (file, bytes) => fs.writeFileSync(file, bytes, { flag: "wx" }),
    trustAnchor: SEALER_TRUST_ANCHOR_V1
  };
}

async function run(argv, overrides = {}) {
  const deps = { ...defaultDependencies(), ...overrides };
  const parsed = parseArguments(argv);
  const report = { schemaVersion: 1, kind: "PROVIDER_EVIDENCE_SEALER_REPORT", mode: parsed.mode, refusal: null, result: null };
  try {
    if (parsed.unknown.length > 0) refuse("UNKNOWN_ARGUMENT", parsed.unknown[0]);
    if (parsed.mode === null || parsed.input === null) refuse("SEALER_USAGE");
    if (parsed.mode === "seal" && parsed.signature === null) refuse("SEALER_USAGE", "signature");
    const input = fence.parseStrictJSON(deps.readFile(path.isAbsolute(parsed.input) ? parsed.input : path.join(deps.root, parsed.input)).toString("utf8"));
    report.result = parsed.mode === "prepare" ? prepare(input, deps) : seal(input, parsed.signature, deps);
    return { exitCode: 0, report };
  } catch (error) {
    report.refusal = error instanceof SealerRefusal ? error.code : "SEALER_FAILED";
    return { exitCode: 1, report };
  }
}

async function main() {
  const { exitCode, report } = await run(process.argv.slice(2));
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  process.exitCode = exitCode;
}

if (require.main === module) main().catch((error) => { process.stderr.write(`${error && error.code ? error.code : "SEALER_FAILED"}\n`); process.exitCode = 1; });

module.exports = { SEALER_TRUST_ANCHOR_V1, ARTIFACT_RELATIVE_PATH, IMPLEMENTATION_PATHS_V1, INPUT_KEYS, BUNDLE_CAP_BYTES, ARTIFACT_CAP_BYTES, SealerRefusal, arrayDigest, implementationDigest, validateInput, assembleUnsignedAuthority, payloadDigest, signedMessage, prepare, completeAuthority, seal, parseArguments, run };
