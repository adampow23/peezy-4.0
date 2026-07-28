"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const path = require("node:path");

const PROJECT_ID = "peezy-1ecrdl";
const DEFAULT_BUCKET = "peezy-1ecrdl.firebasestorage.app";
const ANTHROPIC_MODEL = "claude-sonnet-4-6";
const MODEL_MIGRATION_COMMIT = "4023ca3ecfc76a23daeb2943dcb735b789828cf6";
const CUBE_MATERIAL_CATEGORIES = new Set(["furniture", "appliance", "boxes"]);
const PROCESS_INVENTORY_ENDPOINT =
  "https://us-central1-peezy-1ecrdl.cloudfunctions.net/processInventory";

function normalizedName(value) {
  return String(value ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.keys(value).sort().map((key) => [key, stableValue(value[key])])
  );
}

function canonicalizeItems(items) {
  if (!Array.isArray(items)) throw new TypeError("items must be an array");
  return items.map((rawItem) => {
    const item = { ...rawItem };
    delete item.id;
    return stableValue(item);
  });
}

async function loadFixture(fixturePath) {
  const absolutePath = path.resolve(fixturePath);
  const fixture = JSON.parse(await fs.readFile(absolutePath, "utf8"));
  if (fixture.schemaVersion !== 1 || !fixture.id || !Array.isArray(fixture.rooms) ||
      fixture.rooms.length === 0) {
    throw new Error(`Invalid processInventory fixture: ${absolutePath}`);
  }
  Object.defineProperty(fixture, "fixturePath", {
    value: absolutePath,
    enumerable: false
  });
  return fixture;
}

function matchingTruth(itemName, groundTruth) {
  const name = normalizedName(itemName);
  const candidates = groundTruth.flatMap((truth) =>
    truth.aliases.map((alias) => ({ truth, alias: normalizedName(alias) }))
  ).filter(({ alias }) => alias && (name === alias || name.includes(alias)));
  candidates.sort((left, right) => right.alias.length - left.alias.length);
  return candidates[0]?.truth ?? null;
}

function auditControlledOutput(groundTruth, items) {
  const matches = new Map(groundTruth.map((truth) => [truth.id, []]));
  const unmatchedOutputItems = [];

  for (const item of items) {
    const truth = matchingTruth(item.name, groundTruth);
    if (truth && (!truth.expectedCategory || item.category === truth.expectedCategory)) {
      matches.get(truth.id).push(item);
    } else {
      unmatchedOutputItems.push(item.name);
    }
  }

  const duplicateIdentityGroups = [];
  const missingIdentityGroups = [];
  const identityWalk = [];
  for (const truth of groundTruth) {
    const outputItems = matches.get(truth.id);
    const rawObservedQuantity = outputItems.reduce(
      (sum, item) => sum + Math.max(1, Math.round(Number(item.quantity) || 1)),
      0
    );
    const observedQuantity = truth.quantityMode === "presence"
      ? (outputItems.length > 0 ? 1 : 0)
      : rawObservedQuantity;
    const row = {
      id: truth.id,
      label: truth.label,
      expectedQuantity: truth.expectedQuantity,
      observedQuantity,
      outputNames: outputItems.map((item) => item.name)
    };
    identityWalk.push(row);
    if (observedQuantity > truth.expectedQuantity) {
      duplicateIdentityGroups.push(row);
    } else if (observedQuantity < truth.expectedQuantity) {
      missingIdentityGroups.push(row);
    }
  }

  return {
    groundTruthIdentityGroupCount: groundTruth.length,
    groundTruthPhysicalUnitCount: groundTruth.reduce(
      (sum, truth) => sum + truth.expectedQuantity,
      0
    ),
    outputEntryCount: items.length,
    outputReportedQuantity: items.reduce(
      (sum, item) => sum + Math.max(1, Math.round(Number(item.quantity) || 1)),
      0
    ),
    duplicateIdentityGroups,
    missingIdentityGroups,
    unmatchedOutputItems,
    identityWalk
  };
}

function numericBand(values) {
  const min = Math.min(...values);
  const max = Math.max(...values);
  return { values, min, max, width: Number((max - min).toFixed(3)) };
}

function controlledRunSummary(fixture, baseline) {
  const items = baseline.rooms.flatMap((room) => room.items);
  const cubeItems = items.filter((item) => CUBE_MATERIAL_CATEGORIES.has(item.category));
  const cubeTruth = fixture.groundTruth.filter((truth) => truth.cubeMaterial === true);
  const identityCounts = cubeTruth.map((truth) => {
    const matches = items.filter((item) =>
      matchingTruth(item.name, [truth]) !== null &&
      (!truth.expectedCategory || item.category === truth.expectedCategory)
    );
    return {
      id: truth.id,
      label: truth.label,
      quantity: matches.reduce(
        (sum, item) => sum + Math.max(1, Math.round(Number(item.quantity) || 1)),
        0
      ),
      outputNames: matches.map((item) => item.name),
      categories: [...new Set(matches.map((item) => item.category))]
    };
  });
  const totalCubicFeet = cubeItems.reduce(
    (sum, item) => sum +
      (Math.max(1, Math.round(Number(item.quantity) || 1)) *
        Math.max(0, Number(item.cubicFeet) || 0)),
    0
  );
  const allItemCubicFeet = items.reduce(
    (sum, item) => sum +
      (Math.max(1, Math.round(Number(item.quantity) || 1)) *
        Math.max(0, Number(item.cubicFeet) || 0)),
    0
  );
  return {
    capturedAt: baseline.capturedAt,
    repositoryProcessInventorySha256AtCapture:
      baseline.repositoryProcessInventorySha256AtCapture,
    totalItemEntries: items.length,
    cubeMaterialEntryCount: cubeItems.length,
    cubeMaterialReportedQuantity: cubeItems.reduce(
      (sum, item) => sum + Math.max(1, Math.round(Number(item.quantity) || 1)),
      0
    ),
    totalCubicFeet: Number(totalCubicFeet.toFixed(3)),
    allItemCubicFeet: Number(allItemCubicFeet.toFixed(3)),
    identityCounts,
    unmatchedCubeMaterialItems: cubeItems
      .filter((item) => {
        const truth = matchingTruth(item.name, cubeTruth);
        return truth === null ||
          (truth.expectedCategory && item.category !== truth.expectedCategory);
      })
      .map((item) => ({
        name: item.name,
        category: item.category,
        quantity: item.quantity,
        cubicFeet: item.cubicFeet
      }))
  };
}

function analyzeControlledVariance(fixture, runs) {
  if (!Array.isArray(runs) || runs.length !== 3) {
    throw new Error("controlled variance requires exactly three runs");
  }
  const runSummaries = runs.map((run) => controlledRunSummary(fixture, run));
  const cubeTruth = fixture.groundTruth.filter((truth) => truth.cubeMaterial === true);
  const identityCountBands = cubeTruth.map((truth) => {
    const counts = runSummaries.map((summary) =>
      summary.identityCounts.find((identity) => identity.id === truth.id).quantity
    );
    const band = numericBand(counts);
    return {
      id: truth.id,
      label: truth.label,
      counts,
      min: band.min,
      max: band.max,
      width: band.width
    };
  });
  const totalCubicFeetBand = numericBand(
    runSummaries.map((summary) => summary.totalCubicFeet)
  );
  totalCubicFeetBand.percentWidthOfMin = totalCubicFeetBand.min === 0
    ? null
    : Number(((totalCubicFeetBand.width / totalCubicFeetBand.min) * 100).toFixed(3));
  return {
    cubeMaterialCategories: [...CUBE_MATERIAL_CATEGORIES],
    runSummaries,
    identityCountBands,
    maxIdentityCountWidth: Math.max(0, ...identityCountBands.map((band) => band.width)),
    cubeMaterialEntryCountBand: numericBand(
      runSummaries.map((summary) => summary.cubeMaterialEntryCount)
    ),
    cubeMaterialReportedQuantityBand: numericBand(
      runSummaries.map((summary) => summary.cubeMaterialReportedQuantity)
    ),
    totalCubicFeetBand,
    supplementalAllItemCubicFeetBand: numericBand(
      runSummaries.map((summary) => summary.allItemCubicFeet)
    )
  };
}

function buildControlledRegressionBaseline(fixture, runs) {
  const auditedRuns = runs.map((run) => ({
    ...run,
    controlledAudit: auditControlledOutput(
      fixture.groundTruth,
      run.rooms.flatMap((room) => room.items)
    )
  }));
  const firstRun = auditedRuns[0];
  return {
    schemaVersion: 1,
    baselineStatus: "NEW — no prior byte-identical processInventory baseline existed",
    fixtureId: fixture.id,
    anthropicModel: firstRun.anthropicModel,
    modelMigrationCommit: firstRun.modelMigrationCommit || MODEL_MIGRATION_COMMIT,
    visionPrompt: {
      status: "rolled back to model-migration prompt",
      sourceCommit: MODEL_MIGRATION_COMMIT,
      secondPromptAttempt: false
    },
    postProcessing: {
      strategy: "exact normalized name and exact category; sum quantities",
      deterministic: true,
      fuzzyMatching: false,
      modelInvolvement: false
    },
    rejectedApproach: {
      strategy: "vision-prompt identity-ledger strengthening",
      reason: "cube-material instability exceeded the sub-1-cu-ft decorative defect",
      evidence: "armchairs 4→5→5; credenza omitted in rejected-prompt run 3"
    },
    runCount: auditedRuns.length,
    runs: auditedRuns,
    varianceAnalysis: analyzeControlledVariance(fixture, auditedRuns)
  };
}

function comparisonFields(item) {
  const copy = { ...item };
  delete copy.name;
  delete copy.quantity;
  delete copy.confidence;
  delete copy.frameIndex;
  delete copy.boundingBox;
  return stableValue(copy);
}

function sameValue(left, right) {
  return JSON.stringify(stableValue(left)) === JSON.stringify(stableValue(right));
}

function compareDedupOnly(beforeItems, afterItems, declaredMerges = []) {
  const before = canonicalizeItems(beforeItems);
  const after = canonicalizeItems(afterItems);
  const usedBefore = new Set();
  const usedAfter = new Set();

  for (let afterIndex = 0; afterIndex < after.length; afterIndex += 1) {
    const beforeIndex = before.findIndex((item, index) =>
      !usedBefore.has(index) && sameValue(item, after[afterIndex])
    );
    if (beforeIndex >= 0) {
      usedBefore.add(beforeIndex);
      usedAfter.add(afterIndex);
    }
  }

  const allowedRemoved = new Set();
  const allowedAdded = new Set();
  for (const merge of declaredMerges) {
    const beforeNames = new Set(merge.beforeNames.map(normalizedName));
    const canonicalAfter = after.find((item) =>
      normalizedName(item.name) === normalizedName(merge.afterName)
    );
    if (!canonicalAfter) continue;

    const source = before.find((item) =>
      beforeNames.has(normalizedName(item.name)) &&
      sameValue(comparisonFields(item), comparisonFields(canonicalAfter))
    );
    if (!source) continue;

    before.forEach((item, index) => {
      if (!usedBefore.has(index) && beforeNames.has(normalizedName(item.name))) {
        allowedRemoved.add(index);
      }
    });
    after.forEach((item, index) => {
      if (!usedAfter.has(index) &&
          normalizedName(item.name) === normalizedName(merge.afterName) &&
          sameValue(comparisonFields(item), comparisonFields(source))) {
        allowedAdded.add(index);
      }
    });
  }

  const unexplainedRemoved = before
    .map((item, index) => ({ item, index }))
    .filter(({ index }) => !usedBefore.has(index) && !allowedRemoved.has(index))
    .map(({ item }) => item);
  const unexplainedAddedOrChanged = after
    .map((item, index) => ({ item, index }))
    .filter(({ index }) => !usedAfter.has(index) && !allowedAdded.has(index))
    .map(({ item }) => item);

  return {
    pass: unexplainedRemoved.length === 0 && unexplainedAddedOrChanged.length === 0,
    unexplainedRemoved,
    unexplainedAddedOrChanged
  };
}

async function firebaseIdToken(admin, userId, webApiKey) {
  const customToken = await admin.auth().createCustomToken(userId);
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${encodeURIComponent(webApiKey)}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token: customToken, returnSecureToken: true })
    }
  );
  const body = await response.json();
  if (!response.ok || typeof body.idToken !== "string") {
    throw new Error(`Could not create bounded test-bot ID token (HTTP ${response.status})`);
  }
  return body.idToken;
}

async function roomFrames({ fixture, room, bucket }) {
  if (Array.isArray(room.frames)) {
    const fixtureDirectory = path.dirname(fixture.fixturePath);
    return Promise.all(room.frames.map((frame) =>
      fs.readFile(path.resolve(fixtureDirectory, frame))
    ));
  }

  const sourceUserId = process.env[fixture.sourceUserIdEnv];
  if (!sourceUserId || !room.sourceSessionId || !Number.isInteger(room.frameCount)) {
    throw new Error(`Remote fixture source is incomplete for ${room.id}`);
  }
  return Promise.all(Array.from({ length: room.frameCount }, async (_, index) => {
    const [buffer] = await bucket.file(
      `inventory/${sourceUserId}/${room.sourceSessionId}/frame_${index}.jpg`
    ).download();
    return buffer;
  }));
}

async function callProcessInventory({ idToken, userId, sessionId, roomName, frameCount }) {
  const response = await fetch(PROCESS_INVENTORY_ENDPOINT, {
    method: "POST",
    headers: {
      authorization: `Bearer ${idToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      data: { userId, sessionId, roomName, frameCount }
    })
  });
  const text = await response.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    throw new Error(`processInventory returned non-JSON (HTTP ${response.status})`);
  }
  if (!response.ok || body.error) {
    const message = body.error?.message || `HTTP ${response.status}`;
    throw new Error(`processInventory failed: ${message}`);
  }
  const result = body.result ?? body.data;
  if (result?.success !== true) {
    throw new Error("processInventory did not return success=true");
  }
  return result;
}

async function runRoom({ admin, bucket, db, fixture, room, userId, idToken, progress }) {
  const sessionId = `phase-g-${fixture.id}-${room.id}-${crypto.randomUUID()}`;
  const prefix = `inventory/${userId}/${sessionId}/`;
  const sessionRef = db.collection("users").doc(userId)
    .collection("inventorySessions").doc(sessionId);
  let frameCount = 0;

  try {
    const frames = await roomFrames({ fixture, room, bucket });
    frameCount = frames.length;
    const inputFrameSha256 = frames.map((buffer) =>
      crypto.createHash("sha256").update(buffer).digest("hex")
    );
    progress(`uploading ${fixture.id}/${room.id}: ${frameCount} frames`);
    await sessionRef.set({
      id: sessionId,
      userId,
      roomName: room.roomName,
      status: "processing",
      frameCount,
      items: [],
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
    await Promise.all(frames.map((buffer, index) =>
      bucket.file(`${prefix}frame_${index}.jpg`).save(buffer, {
        resumable: false,
        metadata: { contentType: "image/jpeg" }
      })
    ));

    progress(`calling deployed processInventory for ${fixture.id}/${room.id}`);
    await callProcessInventory({
      idToken,
      userId,
      sessionId,
      roomName: room.roomName,
      frameCount
    });
    const snapshot = await sessionRef.get();
    const data = snapshot.data();
    if (!snapshot.exists || data?.status !== "complete" || !Array.isArray(data.items)) {
      throw new Error(`processInventory did not persist a complete result for ${room.id}`);
    }
    progress(`captured ${fixture.id}/${room.id}: ${data.items.length} item entries`);
    return {
      id: room.id,
      roomName: room.roomName,
      frameCount,
      inputFrameSha256,
      itemCount: data.items.length,
      items: canonicalizeItems(data.items)
    };
  } finally {
    await Promise.allSettled([
      bucket.deleteFiles({ prefix, force: true }),
      sessionRef.delete()
    ]);
    progress(`cleaned exact live fixture ${fixture.id}/${room.id}`);
  }
}

async function repositoryFunctionHash() {
  const source = await fs.readFile(path.resolve(__dirname, "../functions/processInventory.js"));
  return crypto.createHash("sha256").update(source).digest("hex");
}

async function runLiveFixture(
  fixture,
  {
    progress = () => {},
    promptChangedBeforeCapture = false,
    finalBaseline = false
  } = {}
) {
  const userId = process.env.PEEZY_TEST_UID;
  const webApiKey = process.env.PEEZY_FIREBASE_WEB_API_KEY;
  if (!userId || !webApiKey) {
    throw new Error("PEEZY_TEST_UID and PEEZY_FIREBASE_WEB_API_KEY are required");
  }

  const credentialPath = process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    path.resolve(__dirname, "../functions/serviceAccountKey.json");
  const admin = require(path.resolve(__dirname, "../functions/node_modules/firebase-admin"));
  const serviceAccount = require(credentialPath);
  const app = admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: PROJECT_ID,
    storageBucket: process.env.PEEZY_STORAGE_BUCKET || DEFAULT_BUCKET
  }, `phase-g-${crypto.randomUUID()}`);

  try {
    const scopedAdmin = app;
    const db = scopedAdmin.firestore();
    const bucket = scopedAdmin.storage().bucket();
    const idToken = await firebaseIdToken(scopedAdmin, userId, webApiKey);
    const rooms = [];
    for (const room of fixture.rooms) {
      rooms.push(await runRoom({
        admin,
        bucket,
        db,
        fixture,
        room,
        userId,
        idToken,
        progress
      }));
    }
    const totalItemEntries = rooms.reduce((sum, room) => sum + room.itemCount, 0);
    const combinedOutput = rooms.flatMap((room) => room.items.map((item) => ({
      fixtureRoomId: room.id,
      ...item
    })));
    const combinedReportedQuantity = combinedOutput.reduce(
      (sum, item) => sum + Math.max(1, Math.round(Number(item.quantity) || 1)),
      0
    );
    const combinedCubicFeet = combinedOutput.reduce(
      (sum, item) => sum +
        (Math.max(1, Math.round(Number(item.quantity) || 1)) *
          Math.max(0, Number(item.cubicFeet) || 0)),
      0
    );
    const baseline = {
      schemaVersion: 1,
      baselineStatus: "NEW — no prior byte-identical processInventory baseline existed",
      fixtureId: fixture.id,
      diagnosticOrder: finalBaseline
        ? "captured on rolled-back prompt with deterministic exact merge"
        : (promptChangedBeforeCapture
          ? "captured after the Phase G prompt-only deduplication change"
          : "captured before any Phase G prompt/config change"),
      promptChangedBeforeCapture: finalBaseline ? false : promptChangedBeforeCapture,
      capturedAt: new Date().toISOString(),
      anthropicModel: ANTHROPIC_MODEL,
      modelMigrationCommit: MODEL_MIGRATION_COMMIT,
      processInventoryEndpoint: PROCESS_INVENTORY_ENDPOINT,
      repositoryProcessInventorySha256AtCapture: await repositoryFunctionHash(),
      roomCount: rooms.length,
      totalItemEntries,
      rooms,
      combinedOutput,
      combinedTotals: {
        itemEntries: totalItemEntries,
        reportedQuantity: combinedReportedQuantity,
        cubicFeet: Number(combinedCubicFeet.toFixed(3))
      },
      liveFixtureCleanup: {
        sessionDocumentsDeleted: rooms.length,
        storagePrefixesDeleted: rooms.length,
        sourceSessionsMutated: false
      }
    };
    if (finalBaseline) {
      baseline.visionPrompt = {
        status: "rolled back to model-migration prompt",
        sourceCommit: MODEL_MIGRATION_COMMIT,
        secondPromptAttempt: false
      };
      baseline.postProcessing = {
        strategy: "exact normalized name and exact category; sum quantities",
        deterministic: true,
        fuzzyMatching: false,
        modelInvolvement: false
      };
    }
    if (Array.isArray(fixture.groundTruth)) {
      baseline.controlledAudit = auditControlledOutput(
        fixture.groundTruth,
        rooms.flatMap((room) => room.items)
      );
    }
    return baseline;
  } finally {
    await app.delete();
  }
}

function parseArguments(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--fixture" || argument === "--output") {
      options[argument.slice(2)] = argv[index + 1];
      index += 1;
    } else if (argument === "--live" || argument === "--post-prompt" ||
        argument === "--final-baseline") {
      options.live = true;
      if (argument === "--post-prompt") options.postPrompt = true;
      if (argument === "--final-baseline") options.finalBaseline = true;
    } else {
      throw new Error(`Unknown argument: ${argument}`);
    }
  }
  return options;
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  if (!options.live || !options.fixture || !options.output) {
    throw new Error("usage: node Tests/ProcessInventoryDiagnostic.js --live --fixture <fixture.json> --output <baseline.json>");
  }
  const fixture = await loadFixture(options.fixture);
  const baseline = await runLiveFixture(fixture, {
    progress: (message) => process.stdout.write(`${message}\n`),
    promptChangedBeforeCapture: options.postPrompt === true,
    finalBaseline: options.finalBaseline === true
  });
  const outputPath = path.resolve(options.output);
  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  await fs.writeFile(outputPath, `${JSON.stringify(baseline, null, 2)}\n`);
  process.stdout.write(`baseline written: ${outputPath}\n`);
}

if (require.main === module) {
  main().catch((error) => {
    const message = error?.stack || String(error);
    const modelUnavailable = /model|retir|unavailable|not found|unsupported/i.test(message);
    process.stderr.write(`${modelUnavailable ? "STOP: " : ""}${message}\n`);
    process.exitCode = modelUnavailable ? 2 : 1;
  });
}

module.exports = {
  analyzeControlledVariance,
  auditControlledOutput,
  buildControlledRegressionBaseline,
  canonicalizeItems,
  compareDedupOnly,
  loadFixture,
  parseArguments,
  runLiveFixture
};
