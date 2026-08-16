"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

test("Move Pass denial includes the stable machine-readable reason", () => {
  const source = fs.readFileSync(path.join(__dirname, "..", "entitlement.js"), "utf8");

  assert.match(
    source,
    /new HttpsError\(\s*['"]permission-denied['"]\s*,\s*['"]Move Pass required['"]\s*,\s*\{\s*reason:\s*['"]move-pass-required['"]\s*\}\s*\)/
  );
});
