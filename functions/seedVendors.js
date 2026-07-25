/**
 * Seeds the backend-owned `vendors` collection from vendorsData.json.
 *
 * Usage: cd functions && node seedVendors.js
 *
 * The file contains the complete placeholder rate-card schema. This script
 * upserts only the listed ids, so console-created vendor documents are never
 * deleted by a reseed.
 */

const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

const serviceAccount = require("./serviceAccountKey.json");
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

const db = admin.firestore();
const collection = db.collection("vendors");
const dataPath = path.join(__dirname, "vendorsData.json");

function loadVendors() {
  const source = JSON.parse(fs.readFileSync(dataPath, "utf8"));
  if (!Array.isArray(source.vendors) || source.vendors.length === 0) {
    throw new Error("vendorsData.json must contain a non-empty vendors array");
  }

  const ids = new Set();
  for (const vendor of source.vendors) {
    const required = ["vendorId", "name", "vertical", "serviceRadius", "rateCard", "accountability", "active"];
    const missing = required.filter((key) => vendor[key] === undefined);
    if (missing.length > 0) {
      throw new Error(`${vendor.vendorId || "(unknown vendor)"} is missing: ${missing.join(", ")}`);
    }
    if (vendor.vertical !== "movers") {
      throw new Error(`${vendor.vendorId} must use the movers vertical in this seed`);
    }
    if (ids.has(vendor.vendorId)) {
      throw new Error(`Duplicate vendorId: ${vendor.vendorId}`);
    }
    ids.add(vendor.vendorId);
  }

  return source.vendors;
}

async function writeInBatches(vendors) {
  const batchSize = 500;
  for (let index = 0; index < vendors.length; index += batchSize) {
    const batch = db.batch();
    const chunk = vendors.slice(index, index + batchSize);
    for (const vendor of chunk) {
      batch.set(collection.doc(vendor.vendorId), vendor);
    }
    await batch.commit();
  }
}

async function verifyRoundTrip(vendors) {
  const snapshots = await Promise.all(
    vendors.map((vendor) => collection.doc(vendor.vendorId).get())
  );

  for (let index = 0; index < snapshots.length; index += 1) {
    const snapshot = snapshots[index];
    const expected = vendors[index];
    if (!snapshot.exists) {
      throw new Error(`Round-trip failed: ${expected.vendorId} was not written`);
    }
    const stored = snapshot.data();
    if (
      stored.vendorId !== expected.vendorId ||
      stored.active !== expected.active ||
      stored.rateCard?.hourlyByCrew?.["3"] !== expected.rateCard.hourlyByCrew["3"]
    ) {
      throw new Error(`Round-trip failed: ${expected.vendorId} did not preserve its rate card`);
    }
  }
}

async function main() {
  const vendors = loadVendors();
  console.log(`Seeding ${vendors.length} vendor rate cards into vendors...`);
  await writeInBatches(vendors);
  await verifyRoundTrip(vendors);
  console.log(`✅ Seeded and read back ${vendors.length} vendors: ${vendors.map((vendor) => vendor.vendorId).join(", ")}`);
}

main().catch((error) => {
  console.error(`❌ Vendor seed failed: ${error.message}`);
  process.exit(1);
});
