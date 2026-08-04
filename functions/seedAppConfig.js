/**
 * Seeds the backend-owned AI configuration.
 *
 * Usage:
 *   cd functions && node seedAppConfig.js
 */

const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");

const AI_CONFIG_PATH = "appConfig/ai";
const aiConfig = {
  researchModel: "claude-sonnet-4-6",
  chatModel: "claude-sonnet-4-6",
  inventoryModel: "claude-sonnet-4-6",
  maxSearchesPerBrief: 5,
  briefMaxTokens: 4096
};

async function seedAppConfig() {
  if (!admin.apps.length) {
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  }

  const document = admin.firestore().doc(AI_CONFIG_PATH);
  await document.set(aiConfig);

  const snapshot = await document.get();
  const stored = snapshot.data();
  const matches = snapshot.exists && Object.entries(aiConfig).every(
    ([key, value]) => stored?.[key] === value
  );

  if (!matches) {
    throw new Error(`Round-trip failed for ${AI_CONFIG_PATH}`);
  }
}

async function main() {
  console.log(`Seeding ${AI_CONFIG_PATH}...`);
  await seedAppConfig();
  console.log(`✅ Seeded and read back ${AI_CONFIG_PATH}`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`❌ AI config seed failed: ${error.message}`);
    process.exit(1);
  });
}

module.exports = { aiConfig, seedAppConfig };
