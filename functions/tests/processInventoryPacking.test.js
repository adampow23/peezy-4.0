"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

const { buildConfigDocuments } = require("../seedCubeSheet");
const {
  buildRoomPackingArtifacts,
  cleanupSessionFrames,
  recomputeMovePackingAggregate,
  roomInventoryRevision
} = require("../processInventory");

function config() {
  const documents = buildConfigDocuments();
  return {
    cubeSheet: structuredClone(
      documents.find(({ path }) => path === "appConfig/cubeSheet").data
    ),
    packingSim: structuredClone(
      documents.find(({ path }) => path === "appConfig/packingSim").data
    )
  };
}

function item(type, overrides = {}) {
  const packingConfig = config();
  const row = packingConfig.cubeSheet.rows.find((candidate) => candidate.key === type);
  return {
    id: overrides.id || type,
    name: overrides.name || type,
    type,
    category: overrides.category || "other",
    tier: "boxable",
    quantity: 1,
    cubicFeet: Number(row?.typical) || 1,
    isFragile: false,
    confidence: 0.9,
    frameIndices: [0],
    frameIndex: null,
    shouldMove: true,
    ...overrides
  };
}

function roomDocument(id, items, artifacts) {
  return {
    id,
    data: {
      id,
      items: structuredClone(items),
      ...structuredClone(artifacts)
    }
  };
}

test("room integration persists the frozen packPlan contract from seeded tuning", () => {
  const packingConfig = config();
  const generatedAt = "2026-08-05T12:00:00.000Z";
  const items = [item("Books (each)", {
    id: "books",
    name: "Books",
    quantity: 20,
    cubicFeet: 0.04
  })];
  const artifacts = buildRoomPackingArtifacts(items, packingConfig, {
    roomId: "office",
    generatedAt
  });

  assert.equal(artifacts.packMeta.status, "complete");
  assert.equal(artifacts.packMeta.configVersion, packingConfig.packingSim.configVersion);
  assert.equal(artifacts.packMeta.inventoryRevision, roomInventoryRevision("office", items));
  assert.deepEqual(Object.keys(artifacts.packPlan), [
    "generatedAt",
    "engineVersion",
    "configVersion",
    "boxes",
    "leftovers",
    "restricted",
    "openFirst",
    "totalsBySize",
    "reservedFeedbackSchema"
  ]);
  assert.equal(artifacts.packPlan.generatedAt, generatedAt);
  assert.equal(artifacts.packPlan.engineVersion, packingConfig.packingSim.engineVersion);
  assert.ok(artifacts.packPlan.boxes.length > 0);

  const box = artifacts.packPlan.boxes[0];
  const packedUnits = box.items.reduce((sum, packedItem) => sum + packedItem.qty, 0);
  assert.equal(
    box.estMinutes,
    Math.max(
      packingConfig.packingSim.timeEstimation.minimumMinutesPerBox,
      packingConfig.packingSim.timeEstimation.baseMinutesByBoxSize[box.size] +
        (packedUnits * packingConfig.packingSim.timeEstimation.minutesPerPackedUnit)
    )
  );
  assert.deepEqual(Object.keys(box), [
    "n",
    "size",
    "lane",
    "items",
    "layers",
    "estMinutes",
    "roomId",
    "startedAt",
    "packedAt",
    "fitFeedback"
  ]);
});

test("retrying aggregation twice is byte-identical and never double-counts", () => {
  const packingConfig = config();
  const officeItems = [item("Books (each)", {
    id: "office-books",
    name: "Books",
    quantity: 50,
    cubicFeet: 0.025,
    uncertain: true
  })];
  const kitchenItems = [item("Glassware (each)", {
    id: "kitchen-glass",
    name: "Glassware",
    quantity: 12,
    cubicFeet: 0.08,
    isFragile: true
  })];
  const office = buildRoomPackingArtifacts(officeItems, packingConfig, {
    roomId: "office",
    generatedAt: "2026-08-05T12:00:00.000Z"
  });
  const kitchen = buildRoomPackingArtifacts(kitchenItems, packingConfig, {
    roomId: "kitchen",
    generatedAt: "2026-08-05T12:00:00.000Z"
  });
  const rooms = [
    roomDocument("office", officeItems, office),
    roomDocument("kitchen", kitchenItems, kitchen)
  ];

  const first = recomputeMovePackingAggregate(rooms, packingConfig.packingSim);
  const retry = recomputeMovePackingAggregate(rooms, packingConfig.packingSim);

  assert.equal(JSON.stringify(first), JSON.stringify(retry));
  assert.equal(first.status, "complete");
  assert.equal(first.clientGuardReady, true);
  assert.deepEqual(first.expectedRoomIds, ["kitchen", "office"]);
  assert.deepEqual(first.includedRoomIds, ["kitchen", "office"]);
  for (const size of packingConfig.packingSim.boxSizeOrder) {
    assert.equal(
      first.plannedBySize[size],
      office.packPlan.totalsBySize[size] + kitchen.packPlan.totalsBySize[size]
    );
    assert.equal(
      first.purchaseBySize[size],
      first.plannedBySize[size] + first.reserveBySize[size]
    );
  }
  assert.ok(first.reserveLines.length > 0);
  assert.ok(first.reserveLines.every((line) => line.reason && line.count > 0));
});

test("one failed room produces a partial aggregate and closes the client guard", () => {
  const packingConfig = config();
  const completeItems = [item("Books (each)", {
    id: "books",
    name: "Books",
    quantity: 20,
    cubicFeet: 0.04
  })];
  const failedItems = [item("Table lamp", {
    id: "lamp",
    name: "Lamp"
  })];
  const complete = buildRoomPackingArtifacts(completeItems, packingConfig, {
    roomId: "office",
    generatedAt: "2026-08-05T12:00:00.000Z"
  });
  const rooms = [
    roomDocument("office", completeItems, complete),
    {
      id: "bedroom",
      data: {
        items: failedItems,
        packMeta: {
          status: "failed",
          inventoryRevision: roomInventoryRevision("bedroom", failedItems),
          configVersion: packingConfig.packingSim.configVersion
        }
      }
    }
  ];

  const aggregate = recomputeMovePackingAggregate(rooms, packingConfig.packingSim);
  assert.equal(aggregate.status, "partial");
  assert.equal(aggregate.clientGuardReady, false);
  assert.deepEqual(aggregate.expectedRoomIds, ["bedroom", "office"]);
  assert.deepEqual(aggregate.includedRoomIds, ["office"]);
});

test("a stale room revision cannot enter a complete aggregate", () => {
  const packingConfig = config();
  const items = [item("Books (each)", {
    id: "books",
    name: "Books",
    quantity: 20,
    cubicFeet: 0.04
  })];
  const artifacts = buildRoomPackingArtifacts(items, packingConfig, {
    roomId: "office",
    generatedAt: "2026-08-05T12:00:00.000Z"
  });
  const changedItems = structuredClone(items);
  changedItems[0].quantity += 1;
  const aggregate = recomputeMovePackingAggregate([
    roomDocument("office", changedItems, artifacts)
  ], packingConfig.packingSim);

  assert.equal(aggregate.status, "building");
  assert.equal(aggregate.clientGuardReady, false);
  assert.deepEqual(aggregate.includedRoomIds, []);
});

test("frame cleanup retains trace evidence and guards each deletion independently", async () => {
  const deleted = [];
  const errors = [];
  const frames = [0, 1, 2, 3].map((index) => ({
    index,
    name: `inventory/user/session/frame_${index}.jpg`,
    storageFile: {
      async delete() {
        if (index === 1) throw new Error("fixture deletion failure");
        deleted.push(index);
      }
    }
  }));
  const trace = {
    "box-1": [{ evidenceFrames: [0, 2] }]
  };

  const result = await cleanupSessionFrames(frames, trace, {
    error(message, details) {
      errors.push({ message, details });
    }
  });

  assert.deepEqual(result.retained, [
    "inventory/user/session/frame_0.jpg",
    "inventory/user/session/frame_2.jpg"
  ]);
  assert.deepEqual(result.deleted, [
    "inventory/user/session/frame_1.jpg",
    "inventory/user/session/frame_3.jpg"
  ]);
  assert.deepEqual(deleted, [3]);
  assert.equal(errors.length, 1);
});
