"use strict";

// Static contract test for the movers three-task spawn chain catalog rows
// (Spec: movers spawn chain v7, plan A4). Asserts the exact taskIds, exact
// user-visible titles (including the BOOK_MOVERS retitle), spawnedOnly flags,
// workflow routing ids, exact date rules, and presence of every field the
// seeder projection reads unconditionally.

const assert = require("node:assert/strict");
const test = require("node:test");

const rows = require("../taskCatalogData.json");
const byId = new Map(rows.map((row) => [row.taskId, row]));

// Every field seedTaskCatalog.js writes unconditionally must exist on a row.
const SEEDER_REQUIRED_FIELDS = [
  "taskId", "title", "actionCategory", "category", "actionType", "taskType",
  "researchScope", "conditions", "desc", "estHours", "estPeezy", "tips",
  "urgencyPercentage", "whyNeeded"
];

test("catalog taskIds are unique", () => {
  assert.equal(byId.size, rows.length);
});

test("BOOK_MOVERS is retitled to Get Moving Quotes", () => {
  const row = byId.get("BOOK_MOVERS");
  assert.ok(row, "BOOK_MOVERS row missing");
  assert.equal(row.title, "Get Moving Quotes");
  assert.equal(row.workflowId, "book_movers");
  assert.notEqual(row.spawnedOnly, true, "BOOK_MOVERS must stay generation-eligible");
});

test("COMPARE_MOVING_QUOTES contract", () => {
  const row = byId.get("COMPARE_MOVING_QUOTES");
  assert.ok(row, "COMPARE_MOVING_QUOTES row missing");
  assert.equal(row.title, "Compare your moving quotes");
  assert.equal(row.spawnedOnly, true);
  assert.equal(row.workflowId, "compare_moving_quotes");
  assert.equal(row.workflowId, row.taskId.toLowerCase());
  assert.deepEqual(row.dateRule, { anchor: "spawn", offsetDays: 3 });
  assert.deepEqual(row.conditions, {});
  for (const field of SEEDER_REQUIRED_FIELDS) {
    assert.ok(field in row, `COMPARE_MOVING_QUOTES missing seeder field: ${field}`);
  }
});

test("BOOK_YOUR_MOVERS contract", () => {
  const row = byId.get("BOOK_YOUR_MOVERS");
  assert.ok(row, "BOOK_YOUR_MOVERS row missing");
  assert.equal(row.title, "Book your movers");
  assert.equal(row.spawnedOnly, true);
  assert.equal(row.workflowId, "book_your_movers");
  assert.equal(row.workflowId, row.taskId.toLowerCase());
  assert.deepEqual(row.dateRule, { anchor: "spawn", offsetDays: 1 });
  assert.deepEqual(row.conditions, {});
  for (const field of SEEDER_REQUIRED_FIELDS) {
    assert.ok(field in row, `BOOK_YOUR_MOVERS missing seeder field: ${field}`);
  }
});
