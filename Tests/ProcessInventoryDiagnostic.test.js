"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const test = require("node:test");

const {
  analyzeControlledVariance,
  auditControlledOutput,
  buildControlledRegressionBaseline,
  canonicalizeItems,
  compareDedupOnly,
  loadFixture,
  parseArguments
} = require("./ProcessInventoryDiagnostic");

test("controlled fixture is exactly five local frames", async () => {
  const fixture = await loadFixture(path.join(
    __dirname,
    "Fixtures/ProcessInventory/controlled-single-room/fixture.json"
  ));

  assert.equal(fixture.rooms.length, 1);
  assert.equal(fixture.rooms[0].frames.length, 5);
  assert.equal(new Set(fixture.rooms[0].frames).size, 5);
  assert.ok(fixture.rooms[0].frames.every((frame) => frame.endsWith(".jpg")));
});

test("canonical output strips volatile ids but retains item-level fields", () => {
  assert.deepEqual(canonicalizeItems([{ id: "session-item-0", name: "Sofa", quantity: 1 }]), [
    { name: "Sofa", quantity: 1 }
  ]);
});

test("controlled audit distinguishes distinct repeated furniture from duplicates", () => {
  const groundTruth = [
    { id: "sofa", label: "Sofa", expectedQuantity: 1, aliases: ["sofa", "couch"] },
    { id: "armchairs", label: "Armchairs", expectedQuantity: 4, aliases: ["armchair", "armchairs"] }
  ];
  const valid = auditControlledOutput(groundTruth, [
    { name: "Sofa", quantity: 1 },
    { name: "Armchairs", quantity: 4 }
  ]);
  const duplicated = auditControlledOutput(groundTruth, [
    { name: "Sofa", quantity: 1 },
    { name: "Couch", quantity: 1 },
    { name: "Armchair", quantity: 2 },
    { name: "Armchairs", quantity: 2 }
  ]);

  assert.deepEqual(valid.duplicateIdentityGroups, []);
  assert.deepEqual(valid.missingIdentityGroups, []);
  assert.deepEqual(duplicated.duplicateIdentityGroups, [{
    id: "sofa",
    label: "Sofa",
    expectedQuantity: 1,
    observedQuantity: 2,
    outputNames: ["Sofa", "Couch"]
  }]);
  assert.deepEqual(duplicated.missingIdentityGroups, []);
});

test("item-level comparison permits only removals or quantity merges for dedup", () => {
  const before = [
    { name: "Sofa", tier: "furniture", quantity: 1, cubicFeet: 45 },
    { name: "Couch", tier: "furniture", quantity: 1, cubicFeet: 45 },
    { name: "Books", tier: "boxable", quantity: 2, cubicFeet: 1 }
  ];
  const dedupOnly = [
    { name: "Sofa", tier: "furniture", quantity: 1, cubicFeet: 45 },
    { name: "Books", tier: "boxable", quantity: 2, cubicFeet: 1 }
  ];
  const unrelated = [
    { name: "Sofa", tier: "boxable", quantity: 1, cubicFeet: 45 },
    { name: "Books", tier: "boxable", quantity: 2, cubicFeet: 1 }
  ];

  assert.equal(compareDedupOnly(before, dedupOnly, [
    { beforeNames: ["Sofa", "Couch"], afterName: "Sofa" }
  ]).pass, true);
  assert.equal(compareDedupOnly(before, unrelated, [
    { beforeNames: ["Sofa", "Couch"], afterName: "Sofa" }
  ]).pass, false);
});

test("inventory prompt is rolled back to the model-migration version", async () => {
  const source = await fs.readFile(path.join(
    __dirname,
    "../functions/processInventory.js"
  ), "utf8");

  assert.match(source, /Do NOT double-count items visible from multiple angles — deduplicate carefully\./);
  assert.doesNotMatch(source, /Build one physical-object ledger across all frames/);
});

test("final regression capture is explicit in diagnostic arguments", () => {
  assert.deepEqual(parseArguments([
    "--live",
    "--final-baseline",
    "--fixture",
    "fixture.json",
    "--output",
    "baseline.json"
  ]), {
    live: true,
    finalBaseline: true,
    fixture: "fixture.json",
    output: "baseline.json"
  });
});

test("controlled variance isolates cube-material identity/count and cube bands", () => {
  const fixture = {
    id: "controlled",
    groundTruth: [{
      id: "chairs",
      label: "Chairs",
      expectedQuantity: 2,
      cubeMaterial: true,
      aliases: ["chair", "chairs"]
    }]
  };
  const run = (quantity, cubicFeet, decorQuantity) => ({
    fixtureId: "controlled",
    anthropicModel: "claude-sonnet-4-6",
    rooms: [{
      items: [
        { name: "Chair", category: "furniture", quantity, cubicFeet },
        { name: "Vase", category: "decor", quantity: decorQuantity, cubicFeet: 1 }
      ]
    }]
  });
  const runs = [run(2, 10, 1), run(3, 10, 8), run(2, 12, 2)];

  const analysis = analyzeControlledVariance(fixture, runs);
  assert.deepEqual(analysis.identityCountBands, [{
    id: "chairs",
    label: "Chairs",
    counts: [2, 3, 2],
    min: 2,
    max: 3,
    width: 1
  }]);
  assert.deepEqual(analysis.totalCubicFeetBand, {
    values: [20, 30, 24],
    min: 20,
    max: 30,
    width: 10,
    percentWidthOfMin: 50
  });
  assert.equal(analysis.maxIdentityCountWidth, 1);

  const baseline = buildControlledRegressionBaseline(fixture, runs);
  assert.equal(baseline.runCount, 3);
  assert.deepEqual(baseline.varianceAnalysis, analysis);
  assert.equal(baseline.visionPrompt.status, "rolled back to model-migration prompt");
  assert.equal(baseline.postProcessing.fuzzyMatching, false);
});

test("controlled regression baseline contains three recomputable clean audits", async () => {
  const fixture = await loadFixture(path.join(
    __dirname,
    "Fixtures/ProcessInventory/controlled-single-room/fixture.json"
  ));
  const baseline = JSON.parse(await fs.readFile(path.join(
    __dirname,
    "Fixtures/ProcessInventory/controlled-single-room/baseline.json"
  ), "utf8"));

  assert.equal(baseline.runCount, 3);
  assert.deepEqual(
    analyzeControlledVariance(fixture, baseline.runs),
    baseline.varianceAnalysis
  );
  assert.ok(baseline.runs.every((run) =>
    run.controlledAudit.duplicateIdentityGroups.length === 0 &&
    run.controlledAudit.missingIdentityGroups.length === 0
  ));
  assert.ok(baseline.varianceAnalysis.identityCountBands.every((band) => band.width === 0));
  assert.equal(new Set(baseline.runs.map((run) =>
    run.repositoryProcessInventorySha256AtCapture
  )).size, 1);
});

test("multi-room baseline has hashed inputs, combined output, and exact-merge uniqueness", async () => {
  const baseline = JSON.parse(await fs.readFile(path.join(
    __dirname,
    "Fixtures/ProcessInventory/realistic-multi-room/baseline.json"
  ), "utf8"));
  const flattened = baseline.rooms.flatMap((room) => room.items.map((item) => ({
    fixtureRoomId: room.id,
    ...item
  })));

  assert.deepEqual(baseline.combinedOutput, flattened);
  assert.equal(baseline.combinedTotals.itemEntries, flattened.length);
  assert.ok(baseline.rooms.every((room) =>
    room.inputFrameSha256.length === room.frameCount &&
    room.inputFrameSha256.every((hash) => /^[a-f0-9]{64}$/.test(hash))
  ));
  for (const room of baseline.rooms) {
    const keys = room.items.map((item) => JSON.stringify([
      item.name.normalize("NFKC").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim(),
      item.category
    ]));
    assert.equal(new Set(keys).size, keys.length);
  }
});
