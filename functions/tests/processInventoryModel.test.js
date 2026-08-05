"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const { normalizePackingSignals } = require("../processInventory");

const processInventoryPath = path.resolve(__dirname, "../processInventory.js");

const packingSignalFixtures = [
  {
    name: "Sealed moving box",
    input: { packingState: "alreadyPackedSealed", restrictedCandidate: false },
    expected: { packingState: "alreadyPackedSealed", restrictedCandidate: false }
  },
  {
    name: "Closed dresser",
    input: { packingState: "closedContentsUnknown", restrictedCandidate: false },
    expected: { packingState: "closedContentsUnknown", restrictedCandidate: false }
  },
  {
    name: "Paint can",
    input: { packingState: "loose", restrictedCandidate: true },
    expected: { packingState: "loose", restrictedCandidate: true }
  }
];

test("processInventory reads its Anthropic model from AI config", () => {
  const source = fs.readFileSync(processInventoryPath, "utf8");

  assert.match(source, /const \{ getAIConfig \} = require\(['"]\.\/aiConfig['"]\);/);
  assert.match(source, /const inventoryModel = await getAIConfig\(['"]inventoryModel['"]\);/);
  assert.match(source, /model:\s*inventoryModel/);
  assert.doesNotMatch(source, /model:\s*['"]claude-/);
});

test("prompt adds packing state and restricted candidate without replacing cube fields", () => {
  const source = fs.readFileSync(processInventoryPath, "utf8");

  assert.match(source, /"type": "exact injected cube-sheet key\|unknown"/);
  assert.match(source, /"cubicFeet": 0\.0/);
  assert.match(source, /"packingState": "loose\|alreadyPackedSealed\|alreadyPackedOpen\|emptyContainer\|visibleContentsStayInside\|closedContentsUnknown\|builtInOrStays"/);
  assert.match(source, /"restrictedCandidate": false/);
});

for (const fixture of packingSignalFixtures) {
  test(`packing signal fixture: ${fixture.name}`, () => {
    assert.deepEqual(normalizePackingSignals(fixture.input), fixture.expected);
  });
}

test("legacy or malformed packing signals use tolerant defaults", () => {
  assert.deepEqual(normalizePackingSignals({}), {
    packingState: "loose",
    restrictedCandidate: false
  });
  assert.deepEqual(normalizePackingSignals({
    packingState: "sealed",
    restrictedCandidate: "true"
  }), {
    packingState: "loose",
    restrictedCandidate: false
  });
});
