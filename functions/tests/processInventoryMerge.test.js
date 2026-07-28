"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const { mergeExactInventoryItems } = require("../processInventory");

function item(overrides = {}) {
  return {
    id: "session-item-0",
    name: "End Table",
    category: "furniture",
    tier: "furniture",
    quantity: 1,
    cubicFeet: 6,
    confidence: 0.91,
    frameIndex: 0,
    boundingBox: { x: 0.1, y: 0.2, width: 0.3, height: 0.4 },
    ...overrides
  };
}

test("exact normalized name and category merge by summing quantity", () => {
  const first = item();
  const duplicate = item({
    id: "session-item-1",
    name: "  END-table  ",
    quantity: 2,
    confidence: 0.45,
    frameIndex: 3
  });
  const compatibilityDuplicate = item({
    id: "session-item-2",
    name: "ＥＮＤ　ＴＡＢＬＥ",
    quantity: 3
  });

  assert.deepEqual(mergeExactInventoryItems([
    first,
    duplicate,
    compatibilityDuplicate
  ]), [{
    ...first,
    quantity: 6
  }]);
});

test("different normalized names or exact categories never merge", () => {
  const source = [
    item(),
    item({ id: "session-item-1", name: "Side Table" }),
    item({ id: "session-item-2", category: "decor" }),
    item({ id: "session-item-3", name: "Sofa" }),
    item({ id: "session-item-4", name: "Couch" })
  ];

  assert.deepEqual(mergeExactInventoryItems(source), source);
});

test("merge preserves first-occurrence order and fields without mutating input", () => {
  const source = [
    item({ id: "a", name: "Lamp", category: "decor", tier: "boxable" }),
    item({ id: "b", name: "Chair" }),
    item({ id: "c", name: "lamp", category: "decor", tier: "boxable", quantity: 3 })
  ];
  const before = structuredClone(source);
  const result = mergeExactInventoryItems(source);

  assert.deepEqual(source, before);
  assert.deepEqual(result.map(({ id, quantity }) => ({ id, quantity })), [
    { id: "a", quantity: 4 },
    { id: "b", quantity: 1 }
  ]);
  assert.equal(result[0].name, "Lamp");
  assert.equal(result[0].confidence, source[0].confidence);
  assert.equal(result[0].frameIndex, source[0].frameIndex);
});

test("empty input is stable and production persists the merged array", () => {
  assert.deepEqual(mergeExactInventoryItems([]), []);
  assert.throws(() => mergeExactInventoryItems(null), /items must be an array/);

  const source = fs.readFileSync(path.resolve(__dirname, "../processInventory.js"), "utf8");
  assert.match(source, /const items = mergeExactInventoryItems\(normalizedItems\);/);
  assert.match(source, /sessionRef\.update\(\{\s*status: 'complete',\s*items: items,/s);
});
