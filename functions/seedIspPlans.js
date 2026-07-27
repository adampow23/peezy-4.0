/**
 * Validates and seeds the backend-owned `ispPlans` collection.
 *
 * Usage:
 *   cd functions && node seedIspPlans.js --validate-only
 *   cd functions && node seedIspPlans.js
 *
 * This is upsert-only: it never deletes plans that are not in the curated file.
 */

const fs = require("fs");
const path = require("path");

const dataPath = path.join(__dirname, "ispPlansData.json");
const expectedProviders = new Set([
  "Google Fiber",
  "AT&T Fiber",
  "Xfinity",
  "Spectrum",
  "T-Mobile Home Internet"
]);

function isHTTPS(value) {
  try {
    return new URL(value).protocol === "https:";
  } catch {
    return false;
  }
}

function loadPlans() {
  const source = JSON.parse(fs.readFileSync(dataPath, "utf8"));
  if (!/^\d{4}-\d{2}-\d{2}$/.test(source.researchedAt || "")) {
    throw new Error("ispPlansData.json must include an ISO researchedAt date");
  }
  if (typeof source.curationNote !== "string" || !/not address-level/i.test(source.curationNote)) {
    throw new Error("curationNote must explicitly disclaim address-level serviceability");
  }
  if (!Array.isArray(source.plans)) {
    throw new Error("ispPlansData.json must contain a plans array");
  }
  validatePlans(source.plans, source.researchedAt, source.curationNote);
  return source.plans.map((plan) => ({
    ...plan,
    researchedAt: source.researchedAt,
    curationNote: source.curationNote
  }));
}

function validatePlans(plans, researchedAt, curationNote) {
  if (plans.length !== expectedProviders.size) {
    throw new Error(`Expected ${expectedProviders.size} representative plans; found ${plans.length}`);
  }

  const ids = new Set();
  const providers = new Set();
  const orders = new Set();
  const required = [
    "planId", "provider", "tier", "speed", "price", "promo", "contract",
    "why", "providerURL", "affiliateURL", "sourceURL", "sourceTitle", "sortOrder"
  ];

  for (const plan of plans) {
    const missing = required.filter((key) => plan[key] === undefined || plan[key] === "");
    if (missing.length > 0) {
      throw new Error(`${plan.planId || "(unknown plan)"} is missing: ${missing.join(", ")}`);
    }
    if (!/^[a-z0-9_]+$/.test(plan.planId) || ids.has(plan.planId)) {
      throw new Error(`Invalid or duplicate planId: ${plan.planId}`);
    }
    if (!expectedProviders.has(plan.provider) || providers.has(plan.provider)) {
      throw new Error(`Unexpected or duplicate provider: ${plan.provider}`);
    }
    if (!Number.isInteger(plan.sortOrder) || plan.sortOrder < 1 || orders.has(plan.sortOrder)) {
      throw new Error(`Invalid or duplicate sortOrder for ${plan.planId}`);
    }
    if (!isHTTPS(plan.providerURL) || !isHTTPS(plan.sourceURL)) {
      throw new Error(`${plan.planId} must include HTTPS provider and source URLs`);
    }
    if (plan.affiliateURL !== "#AFFILIATE_PENDING" && !isHTTPS(plan.affiliateURL)) {
      throw new Error(`${plan.planId} has an invalid affiliateURL`);
    }
    ids.add(plan.planId);
    providers.add(plan.provider);
    orders.add(plan.sortOrder);
  }

  for (const provider of expectedProviders) {
    if (!providers.has(provider)) throw new Error(`Missing provider: ${provider}`);
  }
  if (!researchedAt || !curationNote) throw new Error("Missing curation metadata");
}

async function seedPlans(plans) {
  const admin = require("firebase-admin");
  const serviceAccount = require("./serviceAccountKey.json");
  if (!admin.apps.length) {
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  }
  const collection = admin.firestore().collection("ispPlans");
  const batch = admin.firestore().batch();
  plans.forEach((plan) => batch.set(collection.doc(plan.planId), plan));
  await batch.commit();

  const snapshots = await Promise.all(plans.map((plan) => collection.doc(plan.planId).get()));
  snapshots.forEach((snapshot, index) => {
    const expected = plans[index];
    const stored = snapshot.data();
    if (
      !snapshot.exists ||
      stored?.planId !== expected.planId ||
      stored?.provider !== expected.provider ||
      stored?.providerURL !== expected.providerURL ||
      stored?.affiliateURL !== expected.affiliateURL ||
      stored?.researchedAt !== expected.researchedAt
    ) {
      throw new Error(`Round-trip failed for ${expected.planId}`);
    }
  });
}

async function main() {
  const plans = loadPlans();
  if (process.argv.includes("--validate-only")) {
    const pending = plans.filter((plan) => plan.affiliateURL === "#AFFILIATE_PENDING").length;
    console.log(`✅ Validated ${plans.length} ISP plans (${pending} affiliate links pending)`);
    return;
  }

  console.log(`Seeding ${plans.length} curated ISP plans into ispPlans...`);
  await seedPlans(plans);
  console.log(`✅ Seeded and read back ${plans.length} ISP plans`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`❌ ISP seed failed: ${error.message}`);
    process.exit(1);
  });
}

module.exports = { isHTTPS, loadPlans, validatePlans };
