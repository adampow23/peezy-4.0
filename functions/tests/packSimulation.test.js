"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

const { cubeSheet, packingSim } = require("../seedCubeSheet");
const {
  stressConfigTransform,
  simulatePack,
  simulatePackWithStress
} = require("../packSimulation");

function config() {
  return {
    cubeSheet: structuredClone(cubeSheet),
    packingSim: structuredClone(packingSim)
  };
}

function fixtureItem(type, overrides = {}) {
  const row = cubeSheet.rows.find((candidate) => candidate.key === type);
  return {
    id: overrides.id || type,
    name: overrides.name || type,
    type,
    category: overrides.category || "other",
    tier: "boxable",
    quantity: 1,
    cubicFeet: Number(row?.typical) || 1,
    isFragile: false,
    frameIndices: [0],
    frameIndex: null,
    shouldMove: true,
    packingState: "loose",
    ...overrides
  };
}

function traceItems(result) {
  return Object.values(result.trace).flat();
}

test("golden: lamp, books, and framed photos use separate constrained routes", () => {
  const result = simulatePack([
    fixtureItem("Floor lamp", {
      id: "lamp",
      name: "Floor lamp",
      cubicFeet: 2.4,
      isFragile: true,
      frameIndices: [0, 1]
    }),
    fixtureItem("Books (each)", {
      id: "books",
      name: "Books",
      quantity: 20,
      cubicFeet: 0.04,
      frameIndices: [2]
    }),
    fixtureItem("Framed art / photos, small (each)", {
      id: "photos",
      name: "Framed photos",
      quantity: 5,
      cubicFeet: 0.5,
      isFragile: true,
      frameIndices: [3]
    })
  ], config());

  assert.deepEqual(
    result.packResult.boxes.map(({ size, lane }) => ({ size, lane })),
    [
      { size: "large", lane: "fragileClean" },
      { size: "small", lane: "dense" }
    ]
  );
  assert.equal(result.packResult.boxes[1].items[0].qty, 20);
  assert.equal(result.packResult.specialtyContainers.length, 2);
  assert.ok(result.packResult.specialtyContainers.every((container) =>
    container.containerType === "pictureCarton"));
  assert.equal(result.packResult.leftovers.length, 0);
});

test("golden: a 50-book line is unitized across small boxes under gross weight", () => {
  const result = simulatePack([
    fixtureItem("Books (each)", {
      id: "books-50",
      name: "Books",
      quantity: 50,
      cubicFeet: 0.06
    })
  ], config());

  assert.ok(result.packResult.boxes.length > 1);
  assert.ok(result.packResult.boxes.every((box) => box.size === "small"));
  assert.ok(result.packResult.boxes.every((box) =>
    box.estWeightLb <= packingSim.boxes.small.maxGrossWeightLb));
  assert.equal(
    result.packResult.boxes.reduce(
      (sum, box) => sum + box.items.reduce((boxSum, item) => boxSum + item.qty, 0),
      0
    ),
    50
  );
  assert.ok(result.closures.every((closure) => closure.closedBy === "volume"));
});

test("golden: a sealed moving box is one existing container with no double count", () => {
  const result = simulatePack([
    fixtureItem("Medium box (3.0 cf)", {
      id: "sealed-box",
      name: "Sealed moving box",
      packingState: "alreadyPackedSealed",
      cubicFeet: 3,
      frameIndices: [1]
    }),
    fixtureItem("Books (each)", {
      id: "visible-books",
      name: "Visible books in sealed box",
      quantity: 12,
      packingState: "visibleContentsStayInside",
      frameIndices: [1]
    })
  ], config());

  assert.equal(result.packResult.boxes.length, 0);
  assert.equal(result.packResult.specialtyContainers.length, 1);
  assert.equal(result.packResult.specialtyContainers[0].containerType, "existingContainer");
  assert.equal(result.packResult.specialtyContainers[0].items[0].qty, 1);
  assert.equal(result.packResult.assumptions.length, 2);
  assert.equal(traceItems(result).reduce((sum, item) => sum + item.qtyPacked, 0), 1);
});

test("golden: a closed dresser creates coverage debt without invented contents", () => {
  const item = fixtureItem("Dresser, double", {
    id: "closed-dresser",
    name: "Closed dresser",
    tier: "furniture",
    packingState: "closedContentsUnknown",
    frameIndices: [4]
  });
  const result = simulatePackWithStress([item], config());

  assert.equal(result.planned.packResult.boxes.length, 0);
  assert.equal(result.planned.packResult.coverageDebt.length, 1);
  assert.equal(result.planned.packResult.coverageDebt[0].debtType, "closedDresser");
  assert.equal(result.planned.packResult.coverageDebt[0].qty, 1);
  assert.equal(result.planned.packResult.leftovers.length, 1);
  assert.equal(result.comparison.reserveByContainerType.medium, 2);
  assert.match(result.comparison.reserveLines[0].reason, /dresser contents/i);
});

test("golden: garage paint exits first while tools use the dense lane", () => {
  const result = simulatePack([
    fixtureItem("Paint / household chemicals (container)", {
      id: "paint",
      name: "Paint cans",
      quantity: 2,
      cubicFeet: 0.2,
      frameIndices: [0]
    }),
    fixtureItem("Power tools (each)", {
      id: "tools",
      name: "Power tools",
      quantity: 3,
      cubicFeet: 0.5,
      frameIndices: [1]
    })
  ], config());

  assert.equal(result.packResult.restrictedItems.length, 1);
  assert.equal(result.packResult.restrictedItems[0].policy, "carrierRestricted");
  assert.equal(result.packResult.restrictedItems[0].qty, 2);
  assert.match(result.packResult.restrictedItems[0].guidance, /rules vary by provider/);
  assert.ok(result.packResult.boxes.length > 0);
  assert.ok(result.packResult.boxes.every((box) => box.lane === "dense"));
});

test("golden: a notBoxable-only room has handling notes and no boxes", () => {
  const result = simulatePack([
    fixtureItem("Sofa, 3-seat", {
      id: "sofa",
      name: "Sofa",
      tier: "furniture",
      frameIndices: [0]
    })
  ], config());

  assert.equal(result.packResult.boxes.length, 0);
  assert.equal(result.packResult.specialtyContainers.length, 0);
  assert.equal(result.packResult.leftovers.length, 1);
  assert.match(result.packResult.leftovers[0].handlingNote, /move it separately/i);
});

test("golden: identical inputs produce byte-identical results", () => {
  const items = [
    fixtureItem("Books (each)", {
      id: "deterministic-books",
      name: "Books",
      quantity: 50,
      cubicFeet: 0.04,
      frameIndices: [3, 1]
    }),
    fixtureItem("Glassware (each)", {
      id: "deterministic-glass",
      name: "Glassware",
      quantity: 12,
      cubicFeet: 0.08,
      isFragile: true,
      frameIndices: [2]
    })
  ];
  const packingConfig = config();

  assert.equal(
    JSON.stringify(simulatePackWithStress(items, packingConfig)),
    JSON.stringify(simulatePackWithStress(items, packingConfig))
  );
});

test("golden: visible contents in an open tote are excluded with an assumption", () => {
  const result = simulatePack([
    fixtureItem("Storage tote / bin (each)", {
      id: "open-tote",
      name: "Open tote",
      packingState: "visibleContentsStayInside",
      frameIndices: [2]
    })
  ], config());

  assert.equal(result.packResult.boxes.length, 0);
  assert.equal(result.packResult.specialtyContainers.length, 0);
  assert.equal(result.packResult.leftovers.length, 0);
  assert.equal(result.packResult.assumptions.length, 1);
  assert.equal(result.packResult.assumptions[0].code, "visibleContentsStayInside");
  assert.match(result.packResult.assumptions[0].message, /not boxed again/i);
});

test("routing precedence is transport, state, row specialty, row boxability, category", () => {
  const result = simulatePack([
    fixtureItem("Paint / household chemicals (container)", {
      id: "restricted-built-in",
      name: "Paint marked as staying",
      packingState: "builtInOrStays"
    }),
    fixtureItem("Mattress only, queen/full", {
      id: "mattress",
      name: "Queen mattress"
    }),
    fixtureItem("Books (each)", {
      id: "row-boxable-books",
      name: "Books",
      quantity: 2,
      cubicFeet: 0.04
    }),
    fixtureItem("Sofa, 4-seat", {
      id: "category-sofa",
      name: "Sofa"
    })
  ], config());

  assert.equal(result.packResult.restrictedItems[0].inventoryItemId, "restricted-built-in");
  assert.ok(result.packResult.specialtyContainers.some((container) =>
    container.containerType === "mattressBag"));
  assert.ok(result.packResult.boxes.some((box) =>
    box.items.some((item) => item.name === "Books")));
  assert.ok(result.packResult.leftovers.some((item) => item.name === "Sofa"));
});

test("protection and compression remain separate in effective cube and weight math", () => {
  const result = simulatePack([
    fixtureItem("Folded linens (piece)", {
      id: "linens",
      name: "Folded linens",
      quantity: 8,
      cubicFeet: 0.25
    })
  ], config());
  const trace = traceItems(result)[0];

  assert.equal(trace.qtyPacked, 8);
  assert.equal(trace.effectiveCube, 8 * 0.25 * 1 * 0.65);
  assert.equal(trace.estWeightLb, 8 * 0.25 * packingSim.densityClasses.light.lbPerCuFt);
});

test("walkthrough ordering uses room frame, item frame, then persisted item ID", () => {
  const result = simulatePack([
    fixtureItem("Books (each)", {
      id: "z-item",
      name: "Later-ID books",
      roomDocumentId: "room-b",
      frameIndices: [0],
      cubicFeet: 0.04
    }),
    fixtureItem("Small electronics (each)", {
      id: "b-item",
      name: "Second electronics",
      roomDocumentId: "room-a",
      frameIndices: [5],
      cubicFeet: 0.25
    }),
    fixtureItem("Small electronics (each)", {
      id: "a-item",
      name: "First electronics",
      roomDocumentId: "room-a",
      frameIndices: [5],
      cubicFeet: 0.25
    })
  ], config());

  assert.equal(result.packResult.boxes[0].lane, "dense");
  assert.deepEqual(
    result.packResult.boxes[1].items.map((item) => item.name),
    ["First electronics", "Second electronics"]
  );
  assert.deepEqual(result.trace["box-1"][0].evidenceFrames, [0]);
});

test("boxes record bottom-to-top heavy, general, then fragile/light layers", () => {
  const packingConfig = config();
  const rows = packingConfig.cubeSheet.rows;
  const rowKeys = ["Books (each)", "Pantry dry goods (item)", "Small electronics (each)"];
  for (const key of rowKeys) {
    const profile = rows.find((row) => row.key === key).packProfile;
    Object.assign(profile, {
      lane: "generalSoft",
      minBox: "small",
      maxBox: "small",
      itemTags: [],
      incompatibleTags: [],
      protectionFactor: 1,
      compressionFactor: 1
    });
  }
  rows.find((row) => row.key === "Books (each)").packProfile.densityClass = "heavy";
  rows.find((row) => row.key === "Pantry dry goods (item)").packProfile.densityClass = "medium";
  rows.find((row) => row.key === "Small electronics (each)").packProfile.densityClass = "light";

  const result = simulatePack([
    fixtureItem("Small electronics (each)", {
      id: "fragile",
      name: "Fragile item",
      cubicFeet: 0.1,
      isFragile: true,
      frameIndices: [0]
    }),
    fixtureItem("Pantry dry goods (item)", {
      id: "general",
      name: "General item",
      cubicFeet: 0.1,
      frameIndices: [1]
    }),
    fixtureItem("Books (each)", {
      id: "heavy",
      name: "Heavy item",
      cubicFeet: 0.1,
      frameIndices: [2]
    })
  ], packingConfig);

  assert.equal(result.packResult.boxes.length, 1);
  assert.deepEqual(result.packResult.boxes[0].layers, [
    "Heavy item",
    "General item",
    "Fragile item"
  ]);
});

test("stress is a separate config transform and reserves only positive box deltas", () => {
  const packingConfig = config();
  const transformed = stressConfigTransform(packingConfig);
  assert.notEqual(transformed, packingConfig);
  assert.notEqual(transformed.packingSim, packingConfig.packingSim);
  assert.equal(packingConfig.packingSim.__packingSimulationStress, undefined);

  const result = simulatePackWithStress([
    fixtureItem("Books (each)", {
      id: "ambiguous-books",
      name: "Ambiguous books",
      quantity: 50,
      cubicFeet: 0.025,
      uncertain: true
    }),
    fixtureItem("Framed art / photos, small (each)", {
      id: "ambiguous-photos",
      name: "Ambiguous photos",
      quantity: 5,
      cubicFeet: 0.25,
      uncertain: true,
      isFragile: true
    })
  ], packingConfig);

  assert.ok(result.comparison.stressBySize.small > result.comparison.plannedBySize.small);
  assert.equal(
    result.comparison.reserveBySize.small,
    result.comparison.stressBySize.small - result.comparison.plannedBySize.small
  );
  assert.equal(result.planned.packResult.specialtyContainers.length, 2);
  assert.equal(result.stress.packResult.specialtyContainers.length, 2);
  assert.ok(result.comparison.reserveLines.every((line) => line.count > 0));
});

test("incompatible tags close only that lane's open box with an explicit cause", () => {
  const packingConfig = config();
  const rows = packingConfig.cubeSheet.rows;
  const liquid = rows.find((row) => row.key === "Household liquids (container)").packProfile;
  const tools = rows.find((row) => row.key === "Power tools (each)").packProfile;
  for (const profile of [liquid, tools]) {
    Object.assign(profile, {
      lane: "generalSoft",
      densityClass: "medium",
      minBox: "small",
      maxBox: "small",
      protectionFactor: 1,
      compressionFactor: 1
    });
    delete profile.transportPolicy;
  }
  liquid.itemTags = ["liquid"];
  liquid.incompatibleTags = ["sharp"];
  tools.itemTags = ["sharp"];
  tools.incompatibleTags = ["liquid"];

  const result = simulatePack([
    fixtureItem("Household liquids (container)", {
      id: "liquid",
      name: "Liquid",
      cubicFeet: 0.1,
      frameIndices: [0]
    }),
    fixtureItem("Power tools (each)", {
      id: "sharp",
      name: "Sharp tool",
      cubicFeet: 0.1,
      frameIndices: [1]
    })
  ], packingConfig);

  assert.equal(result.packResult.boxes.length, 2);
  assert.deepEqual(result.closures, [{ boxRef: "box-1", closedBy: "incompat" }]);
});

test("all configured specialty estimators use their seeded capacities and variants", () => {
  const result = simulatePack([
    fixtureItem("Mattress only, king", {
      id: "king-mattresses",
      name: "King mattresses",
      quantity: 2,
      frameIndices: [0]
    }),
    fixtureItem("TV, 55-65\"", {
      id: "televisions",
      name: "Televisions",
      quantity: 2,
      frameIndices: [1]
    }),
    fixtureItem("Hanging clothes (garment)", {
      id: "hanging-clothes",
      name: "Hanging clothes",
      quantity: 37,
      frameIndices: [2]
    }),
    fixtureItem("Dishware bundle (place setting)", {
      id: "dishware",
      name: "Dishware bundles",
      quantity: 17,
      frameIndices: [3]
    })
  ], config());

  const containers = result.packResult.specialtyContainers;
  assert.equal(containers.filter((item) => item.containerType === "mattressBag").length, 2);
  assert.ok(containers.filter((item) => item.containerType === "mattressBag")
    .every((item) => item.variant === "king"));
  assert.equal(containers.filter((item) => item.containerType === "tvKit").length, 2);
  assert.ok(containers.filter((item) => item.containerType === "tvKit")
    .every((item) => item.variant === "55to65"));
  assert.equal(containers.filter((item) => item.containerType === "wardrobe").length, 3);
  assert.equal(containers.filter((item) => item.containerType === "dishPack").length, 3);
  assert.equal(result.packResult.openFirst[0].qty, 37);

  const rateConfig = config();
  rateConfig.packingSim.specialtyEstimator.mattressBagsPerMattress = 2;
  const configuredRateResult = simulatePack([
    fixtureItem("Mattress only, twin", {
      id: "configured-rate-mattress",
      name: "Twin mattress"
    })
  ], rateConfig);
  assert.equal(
    configuredRateResult.packResult.specialtyContainers
      .filter((item) => item.containerType === "mattressBag").length,
    2
  );
});

test("weight and size-bound failures close boxes with their named causes", () => {
  const weightConfig = config();
  const weightProfile = weightConfig.cubeSheet.rows
    .find((row) => row.key === "Books (each)").packProfile;
  Object.assign(weightProfile, {
    lane: "generalSoft",
    densityClass: "heavy",
    minBox: "large",
    maxBox: "large",
    itemTags: [],
    incompatibleTags: [],
    protectionFactor: 1,
    compressionFactor: 1
  });
  const weightResult = simulatePack([
    fixtureItem("Books (each)", {
      id: "weight-books",
      name: "Heavy units",
      quantity: 6,
      cubicFeet: 0.5
    })
  ], weightConfig);
  assert.deepEqual(weightResult.closures, [{ boxRef: "box-1", closedBy: "weight" }]);

  const sizeConfig = config();
  const lampProfile = sizeConfig.cubeSheet.rows
    .find((row) => row.key === "Table lamp").packProfile;
  const valuablesProfile = sizeConfig.cubeSheet.rows
    .find((row) => row.key === "Valuables (item)").packProfile;
  Object.assign(lampProfile, {
    minBox: "medium",
    maxBox: "medium",
    protectionFactor: 1,
    compressionFactor: 1
  });
  delete valuablesProfile.transportPolicy;
  delete valuablesProfile.availabilityFlag;
  const sizeResult = simulatePack([
    fixtureItem("Table lamp", {
      id: "medium-only",
      name: "Medium-only item",
      cubicFeet: 1,
      frameIndices: [0]
    }),
    fixtureItem("Valuables (item)", {
      id: "small-only",
      name: "Small-only item",
      cubicFeet: 0.05,
      frameIndices: [1]
    })
  ], sizeConfig);
  assert.deepEqual(sizeResult.closures, [{ boxRef: "box-1", closedBy: "maxBox" }]);
});

test("display re-aggregates adjacent same-name units while trace preserves item IDs", () => {
  const result = simulatePack([
    fixtureItem("Books (each)", {
      id: "books-a",
      name: "Books",
      quantity: 2,
      cubicFeet: 0.04,
      frameIndices: [0]
    }),
    fixtureItem("Books (each)", {
      id: "books-b",
      name: "Books",
      quantity: 3,
      cubicFeet: 0.04,
      frameIndices: [1]
    })
  ], config());

  assert.deepEqual(result.packResult.boxes[0].items, [{ name: "Books", qty: 5 }]);
  assert.deepEqual(
    result.trace["box-1"].map((item) => item.inventoryItemId),
    ["books-a", "books-b"]
  );
});
