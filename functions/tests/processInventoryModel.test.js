"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const processInventoryPath = path.resolve(__dirname, "../processInventory.js");

test("processInventory reads its Anthropic model from AI config", () => {
  const source = fs.readFileSync(processInventoryPath, "utf8");

  assert.match(source, /const \{ getAIConfig \} = require\(['"]\.\/aiConfig['"]\);/);
  assert.match(source, /const inventoryModel = await getAIConfig\(['"]inventoryModel['"]\);/);
  assert.match(source, /model:\s*inventoryModel/);
  assert.doesNotMatch(source, /model:\s*['"]claude-/);
});
