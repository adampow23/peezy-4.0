/**
 * Seeds the backend-owned `providerDirectory` collection.
 *
 * Usage:
 *   cd functions && node seedProviderDirectory.js --validate-only
 *   cd functions && node seedProviderDirectory.js
 *
 * The deploy path upserts only the listed ids. It never deletes resolved
 * providers that were written through by resolveProvider.
 */

const fs = require("fs");
const path = require("path");

const dataPath = path.join(__dirname, "providerDirectoryData.json");
const validMethods = new Set(["link", "call", "concierge"]);

function normalize(value) {
  return String(value || "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "");
}

function actionURL(provider) {
  return provider.addressChangeURL || provider.cancellationURL || null;
}

function loadProviders() {
  const source = JSON.parse(fs.readFileSync(dataPath, "utf8"));
  if (!Array.isArray(source.providers)) {
    throw new Error("providerDirectoryData.json must contain a providers array");
  }
  validateProviders(source.providers);
  return source.providers;
}

function validateProviders(providers) {
  if (providers.length < 35 || providers.length > 50) {
    throw new Error(`Expected roughly 40 providers; found ${providers.length}`);
  }

  const ids = new Set();
  const lookupKeys = new Map();

  for (const provider of providers) {
    const required = ["providerId", "name", "aliases", "category", "method", "verified", "source"];
    const missing = required.filter((key) => provider[key] === undefined);
    if (missing.length > 0) {
      throw new Error(`${provider.providerId || "(unknown provider)"} is missing: ${missing.join(", ")}`);
    }
    if (!/^[a-z0-9_]+$/.test(provider.providerId)) {
      throw new Error(`Invalid providerId: ${provider.providerId}`);
    }
    if (ids.has(provider.providerId)) {
      throw new Error(`Duplicate providerId: ${provider.providerId}`);
    }
    ids.add(provider.providerId);

    if (!Array.isArray(provider.aliases) || provider.aliases.some((alias) => typeof alias !== "string" || !alias.trim())) {
      throw new Error(`${provider.providerId} has invalid aliases`);
    }
    if (!validMethods.has(provider.method)) {
      throw new Error(`${provider.providerId} has invalid method: ${provider.method}`);
    }
    if (typeof provider.verified !== "boolean" || provider.source !== "seeded") {
      throw new Error(`${provider.providerId} has invalid verified/source fields`);
    }
    if (!Array.isArray(provider.citations)) {
      throw new Error(`${provider.providerId} must include a citations array`);
    }

    const url = actionURL(provider);
    if (provider.addressChangeURL && provider.cancellationURL) {
      throw new Error(`${provider.providerId} cannot define two action URLs`);
    }
    if (provider.method === "link") {
      if (!provider.verified || !url || !URL.canParse(url) || new URL(url).protocol !== "https:") {
        throw new Error(`${provider.providerId} link must be verified with an HTTPS action URL`);
      }
      if (!provider.citations.some((citation) => citation?.url === url && citation?.title)) {
        throw new Error(`${provider.providerId} action URL must have an exact citation`);
      }
    } else if (url) {
      throw new Error(`${provider.providerId} may not retain a URL when method is ${provider.method}`);
    }
    if (provider.verified && provider.method !== "link") {
      throw new Error(`${provider.providerId} verified:true is reserved for confirmed link rows`);
    }
    if (provider.method === "call" && !provider.phone) {
      throw new Error(`${provider.providerId} call method requires a phone number`);
    }

    for (const candidate of [provider.name, ...provider.aliases]) {
      const key = normalize(candidate);
      if (!key) {
        throw new Error(`${provider.providerId} contains an empty lookup key`);
      }
      const prior = lookupKeys.get(key);
      if (prior && prior !== provider.providerId) {
        throw new Error(`Lookup key ${candidate} is shared by ${prior} and ${provider.providerId}`);
      }
      lookupKeys.set(key, provider.providerId);
    }
  }
}

async function seedProviders(providers) {
  const admin = require("firebase-admin");
  const serviceAccount = require("./serviceAccountKey.json");
  if (!admin.apps.length) {
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  }
  const collection = admin.firestore().collection("providerDirectory");
  const batch = admin.firestore().batch();
  for (const provider of providers) {
    batch.set(collection.doc(provider.providerId), provider);
  }
  await batch.commit();

  const snapshots = await Promise.all(
    providers.map((provider) => collection.doc(provider.providerId).get())
  );
  snapshots.forEach((snapshot, index) => {
    const expected = providers[index];
    const stored = snapshot.data();
    if (!snapshot.exists || stored?.providerId !== expected.providerId || stored?.method !== expected.method) {
      throw new Error(`Round-trip failed for ${expected.providerId}`);
    }
    const url = actionURL(stored || {});
    if (url && !(stored.citations || []).some((citation) => citation.url === url)) {
      throw new Error(`Round-trip produced an uncited URL for ${expected.providerId}`);
    }
  });
}

async function main() {
  const providers = loadProviders();
  if (process.argv.includes("--validate-only")) {
    const linkCount = providers.filter((provider) => provider.method === "link").length;
    const callCount = providers.filter((provider) => provider.method === "call").length;
    console.log(`✅ Validated ${providers.length} providers (${linkCount} link, ${callCount} call)`);
    return;
  }

  console.log(`Seeding ${providers.length} providers into providerDirectory...`);
  await seedProviders(providers);
  console.log(`✅ Seeded and read back ${providers.length} providers`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`❌ Provider seed failed: ${error.message}`);
    process.exit(1);
  });
}

module.exports = { actionURL, loadProviders, normalize, validateProviders };
