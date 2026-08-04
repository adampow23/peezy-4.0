const admin = require("firebase-admin");
const { HttpsError } = require("firebase-functions/v2/https");

const AI_CONFIG_PATH = "appConfig/ai";
const CACHE_TTL_MS = 5 * 60 * 1000;
const EXPECTED_KEYS = [
  "researchModel",
  "chatModel",
  "inventoryModel",
  "maxSearchesPerBrief",
  "briefMaxTokens"
];
const MISSING_CONFIG_MESSAGE = "AI config missing — seed appConfig/ai";

let cachedConfig = null;
let cacheExpiresAt = 0;

function missingConfigError() {
  return new HttpsError("failed-precondition", MISSING_CONFIG_MESSAGE);
}

function requireKey(config, key) {
  if (
    !Object.prototype.hasOwnProperty.call(config, key) ||
    config[key] === null ||
    config[key] === undefined
  ) {
    throw missingConfigError();
  }
}

async function readAIConfig() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }

  const snapshot = await admin.firestore().doc(AI_CONFIG_PATH).get();
  if (!snapshot.exists) {
    throw missingConfigError();
  }

  const config = snapshot.data() || {};
  EXPECTED_KEYS.forEach((key) => requireKey(config, key));
  return config;
}

/**
 * Reads the backend-owned AI configuration, cached for five minutes per
 * function instance. Pass a key to receive only that configured value.
 */
async function getAIConfig(requestedKey) {
  const now = Date.now();
  let config = cachedConfig;

  if (!config || now >= cacheExpiresAt) {
    config = await readAIConfig();
    cachedConfig = config;
    cacheExpiresAt = now + CACHE_TTL_MS;
  }

  if (requestedKey === undefined) {
    return config;
  }

  requireKey(config, requestedKey);
  return config[requestedKey];
}

module.exports = { getAIConfig };
