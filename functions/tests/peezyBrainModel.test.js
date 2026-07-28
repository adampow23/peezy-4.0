"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const modulePath = path.resolve(__dirname, "../peezyBrain.js");

function loadDefaultConfig(modelOverride) {
  const previous = process.env.ANTHROPIC_MODEL;
  if (modelOverride === undefined) {
    delete process.env.ANTHROPIC_MODEL;
  } else {
    process.env.ANTHROPIC_MODEL = modelOverride;
  }
  delete require.cache[require.resolve(modulePath)];
  const config = require(modulePath).DEFAULT_CONFIG;
  if (previous === undefined) {
    delete process.env.ANTHROPIC_MODEL;
  } else {
    process.env.ANTHROPIC_MODEL = previous;
  }
  return config;
}

test("peezyBrain defaults to the available Anthropic model", () => {
  assert.equal(loadDefaultConfig(undefined).model, "claude-sonnet-4-6");
});

test("peezyBrain preserves an explicit Anthropic model override", () => {
  assert.equal(loadDefaultConfig("explicit-test-model").model, "explicit-test-model");
});

test("environment example documents the available default model", () => {
  const example = fs.readFileSync(path.resolve(__dirname, "../.env.example"), "utf8");
  assert.match(example, /^# Optional: Model override \(defaults to claude-sonnet-4-6\)$/m);
  assert.match(example, /^ANTHROPIC_MODEL=claude-sonnet-4-6$/m);
  assert.doesNotMatch(example, /claude-sonnet-4-20250514/);
});
