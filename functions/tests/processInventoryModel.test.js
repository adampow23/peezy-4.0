"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const processInventoryPath = path.resolve(__dirname, "../processInventory.js");

test("processInventory uses the available Spec 07 Anthropic model", () => {
  const source = fs.readFileSync(processInventoryPath, "utf8");

  assert.match(source, /model:\s*['"]claude-sonnet-4-6['"]/);
  assert.doesNotMatch(source, /claude-sonnet-4-20250514/);
});
