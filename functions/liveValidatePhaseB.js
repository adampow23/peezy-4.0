const assert = require("assert/strict");
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const PROJECT_ID = "peezy-1ecrdl";
const REGION = "us-central1";
const TEST_EMAIL = "peezy-test-bot@test.peezyapp.com";
const CALLABLE_URL = `https://${REGION}-${PROJECT_ID}.cloudfunctions.net/resolveProvider`;
const FIRESTORE_ROOT = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

function normalize(value) {
  return String(value || "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "");
}

function readWebAPIKey() {
  const plistPath = path.join(__dirname, "..", "Peezy 4.0", "Documents", "GoogleService-Info.plist");
  const plist = fs.readFileSync(plistPath, "utf8");
  const match = plist.match(/<key>API_KEY<\/key>\s*<string>([^<]+)<\/string>/);
  assert.ok(match, "GoogleService-Info.plist must contain API_KEY");
  return match[1];
}

async function readJSON(response) {
  const text = await response.text();
  try {
    return text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`Expected JSON from ${response.url}; received HTTP ${response.status}`);
  }
}

async function createIDToken() {
  const user = await admin.auth().getUserByEmail(TEST_EMAIL);
  const customToken = await admin.auth().createCustomToken(user.uid);
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${encodeURIComponent(readWebAPIKey())}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token: customToken, returnSecureToken: true })
    }
  );
  const body = await readJSON(response);
  assert.equal(response.status, 200, "Test-bot token exchange must succeed");
  assert.ok(body.idToken, "Token exchange must return an ID token");
  return body.idToken;
}

async function callResolver(data, idToken) {
  const headers = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(CALLABLE_URL, {
    method: "POST",
    headers,
    body: JSON.stringify({ data }),
    signal: AbortSignal.timeout(35000)
  });
  return { status: response.status, body: await readJSON(response) };
}

function assertCitationSafe(payload, label) {
  assert.ok(payload && typeof payload === "object", `${label} must return a payload`);
  if (Object.hasOwn(payload, "url")) {
    assert.match(payload.url, /^https:\/\//, `${label} URL must use HTTPS`);
    assert.ok(
      Array.isArray(payload.citations) && payload.citations.some((citation) => citation.url === payload.url),
      `${label} URL must exactly match a returned citation`
    );
  }
}

async function assertRules(idToken) {
  const authenticatedHeaders = { Authorization: `Bearer ${idToken}` };
  const [providerRead, ispRead, unauthProviderRead, unauthISPRead] = await Promise.all([
    fetch(`${FIRESTORE_ROOT}/providerDirectory?pageSize=1`, { headers: authenticatedHeaders }),
    fetch(`${FIRESTORE_ROOT}/ispPlans?pageSize=1`, { headers: authenticatedHeaders }),
    fetch(`${FIRESTORE_ROOT}/providerDirectory?pageSize=1`),
    fetch(`${FIRESTORE_ROOT}/ispPlans?pageSize=1`)
  ]);
  assert.equal(providerRead.status, 200, "Authenticated providerDirectory read must succeed");
  assert.equal(ispRead.status, 200, "Authenticated ispPlans read must succeed even before its seed");
  assert.equal(unauthProviderRead.status, 403, "Unauthenticated providerDirectory read must be denied");
  assert.equal(unauthISPRead.status, 403, "Unauthenticated ispPlans read must be denied");

  const deniedWrite = await fetch(`${FIRESTORE_ROOT}/providerDirectory/__spec07_client_write_denied`, {
    method: "PATCH",
    headers: { ...authenticatedHeaders, "Content-Type": "application/json" },
    body: JSON.stringify({ fields: { shouldNeverWrite: { booleanValue: true } } })
  });
  assert.equal(deniedWrite.status, 403, "Authenticated client providerDirectory write must be denied");
  console.log("✅ Rules: authenticated reads allowed; unauthenticated reads and client writes denied");
}

async function run() {
  const serviceAccount = require("./serviceAccountKey.json");
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount), projectId: PROJECT_ID });
  const idToken = await createIDToken();

  await assertRules(idToken);

  const unauthenticated = await callResolver({ name: "Wells Fargo", category: "financial" });
  assert.equal(unauthenticated.status, 401, "Unauthenticated resolver calls must be denied");

  const seededResponse = await callResolver({ name: "Wells Fargo", category: "financial" }, idToken);
  assert.equal(seededResponse.status, 200);
  const seeded = seededResponse.body.result;
  assert.equal(seeded.method, "link");
  assertCitationSafe(seeded, "Seeded provider");
  console.log(`✅ Seeded provider: cited ${seeded.method} result (${seeded.name})`);

  const realResponse = await callResolver({ name: "Regions Bank", category: "financial" }, idToken);
  assert.equal(realResponse.status, 200);
  const real = realResponse.body.result;
  assertCitationSafe(real, "Unseeded real provider");
  assert.notEqual(real.method, "concierge", "Unseeded real provider must resolve at high confidence");
  assert.equal(real.confidence, "high");

  const cachedID = `resolved_${normalize(real.name).slice(0, 80)}`;
  const cached = await admin.firestore().collection("providerDirectory").doc(cachedID).get();
  assert.ok(cached.exists, "High-confidence resolution must be cached");
  assert.equal(cached.get("source"), "resolved");
  assert.equal(cached.get("verified"), false);
  assert.ok(cached.get("resolvedAt"), "Cached resolution must include resolvedAt");
  console.log(`✅ Unseeded provider: cited ${real.method} result cached as source=resolved, verified=false (${real.name})`);

  const [gibberishResponse, fakeResponse] = await Promise.all([
    callResolver({ name: "Qzxqv Move Account 92741", category: "financial" }, idToken),
    callResolver({ name: "Moonbeam Account Services 9QZ", category: "financial" }, idToken)
  ]);
  for (const [label, response] of [["Gibberish", gibberishResponse], ["Fake brand", fakeResponse]]) {
    assert.equal(response.status, 200);
    const payload = response.body.result;
    assertCitationSafe(payload, label);
    assert.equal(payload.method, "concierge", `${label} must fall back to concierge`);
    assert.ok(!Object.hasOwn(payload, "url"), `${label} must not return a URL`);
  }
  console.log("✅ Negative inputs: gibberish and fake brand returned concierge with no URL");
  console.log("✅ Phase B live acceptance matrix passed");
}

run()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(`❌ Phase B live validation failed: ${error.message}`);
    process.exit(1);
  });
