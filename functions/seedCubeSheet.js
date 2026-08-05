/**
 * Seeds the inventory anchors, cube sheet, and truck configuration.
 *
 * Usage:
 *   cd functions && node seedCubeSheet.js
 */

const admin = require("firebase-admin");
const { createHash } = require("node:crypto");
const { isDeepStrictEqual } = require("node:util");

const CONFIG_PATHS = {
  anchors: "appConfig/anchors",
  cubeSheet: "appConfig/cubeSheet",
  trucks: "appConfig/trucks",
  supplyRates: "appConfig/supplyRates",
  packing: "appConfig/packing",
  packingSim: "appConfig/packingSim"
};

const anchors = {
  anchors: [
    { name: "Interior door", standardDimension: "80\" tall (6'8\"), 30-32\" wide" },
    { name: "Electrical outlet / switch plate", standardDimension: "4.5\" tall, mounted ~12-48\" from floor" },
    { name: "Kitchen countertop", standardDimension: "36\" from floor, 25\" deep" },
    { name: "Refrigerator (standard)", standardDimension: "36\" wide, ~70\" tall" },
    { name: "Dishwasher / washer / dryer", standardDimension: "24-27\" wide (built to fit standard openings)" },
    { name: "Queen mattress", standardDimension: "60\" x 80\"" },
    { name: "King mattress", standardDimension: "76\" x 80\"" },
    { name: "Twin mattress", standardDimension: "38\" x 75\"" },
    { name: "Ceiling height (most rooms)", standardDimension: "96\" (8')" },
    { name: "Standard bath tub", standardDimension: "60\" long" },
    { name: "Toilet", standardDimension: "~28-30\" tall at tank" }
  ]
};

function packingUnit(behavior, maxChunkQty) {
  return maxChunkQty === undefined
    ? { behavior }
    : { behavior, maxChunkQty };
}

function range(category, key, low, typical, high, options = {}) {
  const row = {
    key,
    category,
    low,
    typical,
    high,
    packingUnit: options.packingUnit || packingUnit("indivisible")
  };
  if (options.packProfile) {
    row.packProfile = options.packProfile;
  }
  return row;
}

function fixed(category, key, cubicFeet, options = {}) {
  return range(category, key, cubicFeet, cubicFeet, cubicFeet, options);
}

function boxableProfile({
  lane,
  densityClass,
  minBox,
  maxBox,
  itemTags = [],
  incompatibleTags = [],
  protectionFactor,
  compressionFactor,
  specialtyRoute,
  transportPolicy,
  availabilityFlag
}) {
  return {
    lane,
    densityClass,
    minBox,
    maxBox,
    itemTags,
    incompatibleTags,
    protectionFactor,
    compressionFactor,
    boxable: true,
    boxabilityPrecedence: "row",
    ...(specialtyRoute ? { specialtyRoute } : {}),
    ...(transportPolicy ? { transportPolicy } : {}),
    ...(availabilityFlag ? { availabilityFlag } : {})
  };
}

function specialtyProfile({
  lane,
  densityClass,
  minBox,
  maxBox,
  itemTags = [],
  incompatibleTags = [],
  protectionFactor,
  compressionFactor,
  specialtyRoute,
  availabilityFlag
}) {
  return {
    lane,
    densityClass,
    minBox,
    maxBox,
    itemTags,
    incompatibleTags,
    protectionFactor,
    compressionFactor,
    notBoxable: true,
    specialtyRoute,
    ...(availabilityFlag ? { availabilityFlag } : {})
  };
}

const LIVING_ROOM = "Living Room";
const BEDROOM = "Bedroom";
const DINING_KITCHEN = "Dining Room / Kitchen";
const APPLIANCES = "Appliances";
const OFFICE = "Office";
const EXERCISE_GARAGE_OUTDOOR = "Exercise / Garage / Outdoor";
const BOXES = "Boxes (standard — used by packing plan + supplies kit, same sheet)";
const SPECIALTY = "Specialty (flat-fee items in the pricing engine — cube still counts)";

const cubeSheet = {
  rows: [
    range(LIVING_ROOM, "Sofa, 4-seat", 55, 65, 75),
    range(LIVING_ROOM, "Sofa, 3-seat", 40, 50, 60),
    range(LIVING_ROOM, "Loveseat", 28, 35, 42),
    range(LIVING_ROOM, "Sleeper sofa", 50, 60, 75),
    range(LIVING_ROOM, "Sectional, 4-piece", 120, 150, 175),
    range(LIVING_ROOM, "Sectional, 5-piece", 155, 185, 215),
    range(LIVING_ROOM, "Futon", 40, 50, 65),
    range(LIVING_ROOM, "Recliner", 15, 25, 35),
    range(LIVING_ROOM, "Armchair / club chair", 10, 15, 20),
    range(LIVING_ROOM, "Overstuffed chair", 20, 25, 30),
    range(LIVING_ROOM, "Rocker / glider", 15, 20, 30),
    range(LIVING_ROOM, "Chaise lounge", 35, 45, 55),
    range(LIVING_ROOM, "Ottoman", 4, 6, 10),
    range(LIVING_ROOM, "Coffee table", 15, 22, 28),
    range(LIVING_ROOM, "End / side table", 4, 5, 8),
    range(LIVING_ROOM, "Console / sofa table", 12, 18, 25),
    range(LIVING_ROOM, "TV, 55-65\"", 12, 15, 18, {
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "medium", minBox: "medium", maxBox: "xl",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.35, compressionFactor: 1,
        specialtyRoute: "tvKit", availabilityFlag: "packLast"
      })
    }),
    range(LIVING_ROOM, "TV, under 50\"", 5, 10, 13, {
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "medium", minBox: "medium", maxBox: "large",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.3, compressionFactor: 1,
        specialtyRoute: "tvKit", availabilityFlag: "packLast"
      })
    }),
    range(LIVING_ROOM, "TV, over 65\"", 15, 20, 30, {
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "medium", minBox: "large", maxBox: "xl",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.4, compressionFactor: 1,
        specialtyRoute: "tvKit", availabilityFlag: "packLast"
      })
    }),
    range(LIVING_ROOM, "Small electronics (each)", 0.25, 0.5, 1, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "medium", minBox: "small", maxBox: "medium",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.3, compressionFactor: 1
      })
    }),
    range(LIVING_ROOM, "TV stand", 8, 10, 15),
    range(LIVING_ROOM, "Entertainment center", 20, 40, 60),
    range(LIVING_ROOM, "Wall unit (per piece)", 30, 40, 55, {
      packingUnit: packingUnit("countable")
    }),
    range(LIVING_ROOM, "Bookcase / bookshelf", 10, 20, 35),
    range(LIVING_ROOM, "Books (each)", 0.025, 0.04, 0.06, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "dense", densityClass: "heavy", minBox: "small", maxBox: "small",
        itemTags: ["heavy-on-fragile"], incompatibleTags: ["liquid", "dirty"],
        protectionFactor: 1.05, compressionFactor: 1
      })
    }),
    range(LIVING_ROOM, "Media, CDs/DVDs/games (each)", 0.02, 0.03, 0.05, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "dense", densityClass: "medium", minBox: "small", maxBox: "small",
        itemTags: ["heavy-on-fragile"], incompatibleTags: ["liquid", "dirty"],
        protectionFactor: 1.1, compressionFactor: 1
      })
    }),
    range(LIVING_ROOM, "Vinyl records (each)", 0.025, 0.035, 0.05, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "dense", densityClass: "heavy", minBox: "small", maxBox: "small",
        itemTags: ["heavy-on-fragile"], incompatibleTags: ["liquid", "dirty"],
        protectionFactor: 1.15, compressionFactor: 1
      })
    }),
    range(LIVING_ROOM, "Shelving unit", 10, 25, 50),
    range(LIVING_ROOM, "Curio / display cabinet", 15, 22, 30),
    range(LIVING_ROOM, "Floor lamp", 8, 10, 12, {
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "light", minBox: "large", maxBox: "large",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.25, compressionFactor: 1, availabilityFlag: "packLast"
      })
    }),
    range(LIVING_ROOM, "Table lamp", 3, 5, 8, {
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "light", minBox: "medium", maxBox: "large",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.25, compressionFactor: 1, availabilityFlag: "packLast"
      })
    }),
    range(LIVING_ROOM, "Area rug, large (8x10+)", 12, 18, 22),
    range(LIVING_ROOM, "Area rug, small", 4, 6, 10),
    range(LIVING_ROOM, "Mirror / large picture", 5, 7, 12, {
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "medium", minBox: "medium", maxBox: "large",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.45, compressionFactor: 1,
        specialtyRoute: "pictureCarton", availabilityFlag: "packLast"
      })
    }),
    range(LIVING_ROOM, "Framed art / photos, small (each)", 0.25, 0.5, 0.8, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "light", minBox: "small", maxBox: "medium",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.35, compressionFactor: 1,
        specialtyRoute: "pictureCarton", availabilityFlag: "packLast"
      })
    }),
    range(LIVING_ROOM, "Framed art, medium / large (each)", 1, 2, 3, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "medium", minBox: "medium", maxBox: "large",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.4, compressionFactor: 1,
        specialtyRoute: "pictureCarton", availabilityFlag: "packLast"
      })
    }),
    range(LIVING_ROOM, "Grandfather clock", 18, 22, 28),
    range(LIVING_ROOM, "Piano, upright", 50, 60, 70),
    range(LIVING_ROOM, "Piano, baby grand", 60, 70, 80),
    range(LIVING_ROOM, "Piano, grand", 75, 85, 100),
    range(LIVING_ROOM, "Large plant", 5, 10, 15),

    range(BEDROOM, "Bed, king (frame + mattress)", 105, 125, 140),
    range(BEDROOM, "Bed, queen (frame + mattress)", 80, 95, 110),
    range(BEDROOM, "Bed, full (frame + mattress)", 65, 80, 90),
    range(BEDROOM, "Bed, twin (frame + mattress)", 50, 60, 70),
    range(BEDROOM, "Bed, bunk", 55, 70, 85),
    range(BEDROOM, "Bed, toddler / crib", 15, 20, 45),
    range(BEDROOM, "Mattress only, king", 35, 40, 45, {
      packProfile: specialtyProfile({
        lane: "generalSoft", densityClass: "medium", minBox: "xl", maxBox: "xl",
        incompatibleTags: ["liquid", "sharp", "dirty"],
        protectionFactor: 1.05, compressionFactor: 1,
        specialtyRoute: "mattressBag"
      })
    }),
    range(BEDROOM, "Mattress only, queen/full", 25, 30, 35, {
      packProfile: specialtyProfile({
        lane: "generalSoft", densityClass: "medium", minBox: "xl", maxBox: "xl",
        incompatibleTags: ["liquid", "sharp", "dirty"],
        protectionFactor: 1.05, compressionFactor: 1,
        specialtyRoute: "mattressBag"
      })
    }),
    range(BEDROOM, "Mattress only, twin", 15, 20, 25, {
      packProfile: specialtyProfile({
        lane: "generalSoft", densityClass: "medium", minBox: "large", maxBox: "xl",
        incompatibleTags: ["liquid", "sharp", "dirty"],
        protectionFactor: 1.05, compressionFactor: 1,
        specialtyRoute: "mattressBag"
      })
    }),
    range(BEDROOM, "Headboard", 10, 18, 25),
    range(BEDROOM, "Dresser, triple", 45, 50, 60),
    range(BEDROOM, "Dresser, double", 32, 40, 48),
    range(BEDROOM, "Dresser, single / chest", 20, 25, 32),
    range(BEDROOM, "Chest of drawers, small", 12, 18, 25),
    range(BEDROOM, "Armoire / wardrobe", 30, 50, 65),
    range(BEDROOM, "Nightstand", 4, 5, 8),
    range(BEDROOM, "Vanity table", 15, 20, 28),
    range(BEDROOM, "Cedar / storage chest", 10, 15, 20),
    range(BEDROOM, "Toy chest", 8, 10, 15),
    range(BEDROOM, "Changing table", 18, 22, 28),
    range(BEDROOM, "Full-length standing mirror", 15, 22, 28, {
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "medium", minBox: "large", maxBox: "xl",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.45, compressionFactor: 1,
        specialtyRoute: "pictureCarton", availabilityFlag: "packLast"
      })
    }),
    range(BEDROOM, "Folded linens (piece)", 0.25, 0.5, 0.8, {
      packingUnit: packingUnit("bulkDivisible", 8),
      packProfile: boxableProfile({
        lane: "generalSoft", densityClass: "light", minBox: "medium", maxBox: "xl",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty"],
        protectionFactor: 1, compressionFactor: 0.65
      })
    }),
    range(BEDROOM, "Bedding / pillows (bundle)", 1.5, 2.5, 4, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "generalSoft", densityClass: "light", minBox: "medium", maxBox: "xl",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty"],
        protectionFactor: 1, compressionFactor: 0.55
      })
    }),
    range(BEDROOM, "Hanging clothes (garment)", 0.15, 0.25, 0.4, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "generalSoft", densityClass: "light", minBox: "medium", maxBox: "xl",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty"],
        protectionFactor: 1, compressionFactor: 0.8,
        specialtyRoute: "wardrobe", availabilityFlag: "openFirst"
      })
    }),
    range(BEDROOM, "Medications (item)", 0.01, 0.03, 0.08, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "generalSoft", densityClass: "light", minBox: "small", maxBox: "small",
        itemTags: [], incompatibleTags: ["liquid", "dirty"],
        protectionFactor: 1.1, compressionFactor: 1,
        transportPolicy: "carrySeparately", availabilityFlag: "carrySeparately"
      })
    }),
    range(BEDROOM, "Important documents (file)", 0.01, 0.03, 0.08, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "dense", densityClass: "medium", minBox: "small", maxBox: "small",
        itemTags: [], incompatibleTags: ["liquid", "dirty"],
        protectionFactor: 1.1, compressionFactor: 1,
        transportPolicy: "carrySeparately", availabilityFlag: "carrySeparately"
      })
    }),
    range(BEDROOM, "Valuables (item)", 0.01, 0.05, 0.2, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "light", minBox: "small", maxBox: "small",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.2, compressionFactor: 1,
        transportPolicy: "carrySeparately", availabilityFlag: "carrySeparately"
      })
    }),

    range(DINING_KITCHEN, "Dining table", 28, 35, 48),
    range(DINING_KITCHEN, "Kitchen table", 15, 20, 25),
    range(DINING_KITCHEN, "Bistro / pub table", 10, 20, 26),
    range(DINING_KITCHEN, "Dining/kitchen chair (each)", 4, 5, 7, {
      packingUnit: packingUnit("countable")
    }),
    range(DINING_KITCHEN, "Bar stool (each)", 5, 7, 9, {
      packingUnit: packingUnit("countable")
    }),
    range(DINING_KITCHEN, "China cabinet / hutch", 40, 50, 60),
    range(DINING_KITCHEN, "Buffet / sideboard", 35, 45, 58),
    range(DINING_KITCHEN, "Credenza", 30, 40, 50),
    range(DINING_KITCHEN, "Baker's rack", 18, 25, 30),
    range(DINING_KITCHEN, "Kitchen island, freestanding", 30, 45, 55),
    range(DINING_KITCHEN, "Wine rack", 8, 15, 25),
    range(DINING_KITCHEN, "Microwave", 4, 7, 10),
    range(DINING_KITCHEN, "Microwave cart", 8, 10, 14),
    range(DINING_KITCHEN, "High chair", 7, 10, 12),
    range(DINING_KITCHEN, "Kitchen small appliance (each)", 1, 2, 3, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "medium", minBox: "small", maxBox: "medium",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.25, compressionFactor: 1, availabilityFlag: "openFirst"
      })
    }),
    range(DINING_KITCHEN, "Dishware bundle (place setting)", 0.15, 0.25, 0.35, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "medium", minBox: "small", maxBox: "medium",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.35, compressionFactor: 1, specialtyRoute: "dishPack"
      })
    }),
    range(DINING_KITCHEN, "Glassware (each)", 0.04, 0.08, 0.12, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "light", minBox: "small", maxBox: "medium",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.5, compressionFactor: 1, specialtyRoute: "dishPack"
      })
    }),
    range(DINING_KITCHEN, "Stemware (each)", 0.05, 0.1, 0.15, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "light", minBox: "small", maxBox: "medium",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.6, compressionFactor: 1, specialtyRoute: "dishPack"
      })
    }),
    range(DINING_KITCHEN, "Canned goods (each)", 0.04, 0.06, 0.08, {
      packingUnit: packingUnit("bulkDivisible", 12),
      packProfile: boxableProfile({
        lane: "dense", densityClass: "heavy", minBox: "small", maxBox: "small",
        itemTags: ["heavy-on-fragile"], incompatibleTags: ["liquid", "dirty"],
        protectionFactor: 1.05, compressionFactor: 1
      })
    }),
    range(DINING_KITCHEN, "Pantry dry goods (item)", 0.05, 0.12, 0.25, {
      packingUnit: packingUnit("bulkDivisible", 10),
      packProfile: boxableProfile({
        lane: "dense", densityClass: "medium", minBox: "small", maxBox: "medium",
        itemTags: [], incompatibleTags: ["liquid", "dirty"],
        protectionFactor: 1.05, compressionFactor: 1
      })
    }),
    range(DINING_KITCHEN, "Household liquids (container)", 0.08, 0.15, 0.3, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "generalSoft", densityClass: "medium", minBox: "small", maxBox: "small",
        itemTags: ["liquid"], incompatibleTags: ["sharp", "dirty"],
        protectionFactor: 1.15, compressionFactor: 1,
        transportPolicy: "carrierRestricted"
      })
    }),

    range(APPLIANCES, "Refrigerator, side-by-side / French door", 50, 60, 70),
    range(APPLIANCES, "Refrigerator, standard top-freezer", 32, 40, 48),
    range(APPLIANCES, "Refrigerator, mini", 6, 10, 14),
    range(APPLIANCES, "Freezer, chest", 25, 35, 45),
    range(APPLIANCES, "Freezer, upright", 35, 45, 60),
    range(APPLIANCES, "Range / stove", 20, 25, 30),
    range(APPLIANCES, "Washer", 22, 25, 28),
    range(APPLIANCES, "Dryer", 22, 25, 28),
    range(APPLIANCES, "Washer/dryer stacked combo", 42, 50, 55),
    range(APPLIANCES, "Dishwasher (portable)", 16, 20, 24),
    range(APPLIANCES, "Window A/C unit", 4, 7, 12),

    range(OFFICE, "Desk, standard", 18, 22, 30),
    range(OFFICE, "Desk, executive / L-shaped", 40, 48, 58),
    range(OFFICE, "Desk, computer / small", 12, 15, 20),
    range(OFFICE, "Office chair", 6, 9, 13),
    range(OFFICE, "File cabinet, 2-drawer", 8, 10, 15),
    range(OFFICE, "File cabinet, 4-5 drawer", 18, 25, 50),
    range(OFFICE, "Bookcase, tall (7-8 ft)", 25, 30, 38),
    range(OFFICE, "Computer / monitor setup", 8, 12, 18, {
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "medium", minBox: "medium", maxBox: "xl",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.35, compressionFactor: 1, availabilityFlag: "packLast"
      })
    }),
    range(OFFICE, "Printer, home", 3, 5, 8, {
      packProfile: boxableProfile({
        lane: "fragileClean", densityClass: "medium", minBox: "medium", maxBox: "large",
        itemTags: [], incompatibleTags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
        protectionFactor: 1.2, compressionFactor: 1
      })
    }),
    range(OFFICE, "Safe, small", 10, 15, 22),
    range(OFFICE, "Safe, large / gun safe", 30, 45, 60),

    range(EXERCISE_GARAGE_OUTDOOR, "Treadmill", 40, 45, 60),
    range(EXERCISE_GARAGE_OUTDOOR, "Elliptical", 25, 40, 50),
    range(EXERCISE_GARAGE_OUTDOOR, "Exercise bike", 12, 15, 20),
    range(EXERCISE_GARAGE_OUTDOOR, "Weight bench + weights", 15, 25, 40),
    range(EXERCISE_GARAGE_OUTDOOR, "Bicycle, adult", 8, 10, 13),
    range(EXERCISE_GARAGE_OUTDOOR, "Bicycle, child", 4, 5, 7),
    range(EXERCISE_GARAGE_OUTDOOR, "Kayak / canoe", 40, 50, 60),
    range(EXERCISE_GARAGE_OUTDOOR, "Workbench", 15, 22, 30),
    range(EXERCISE_GARAGE_OUTDOOR, "Tool chest, mechanic", 25, 32, 50),
    range(EXERCISE_GARAGE_OUTDOOR, "Toolbox, hand-carry", 3, 5, 8, {
      packProfile: boxableProfile({
        lane: "dense", densityClass: "heavy", minBox: "small", maxBox: "small",
        itemTags: ["sharp", "dirty", "heavy-on-fragile"], incompatibleTags: ["liquid"],
        protectionFactor: 1.05, compressionFactor: 1
      })
    }),
    range(EXERCISE_GARAGE_OUTDOOR, "Power tools (each)", 0.5, 1, 2, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "dense", densityClass: "heavy", minBox: "small", maxBox: "small",
        itemTags: ["sharp", "dirty", "heavy-on-fragile"], incompatibleTags: ["liquid"],
        protectionFactor: 1.15, compressionFactor: 1
      })
    }),
    range(EXERCISE_GARAGE_OUTDOOR, "Paint / household chemicals (container)", 0.08, 0.2, 0.5, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "generalSoft", densityClass: "medium", minBox: "small", maxBox: "small",
        itemTags: ["liquid", "dirty"], incompatibleTags: ["sharp", "heavy-on-fragile"],
        protectionFactor: 1.1, compressionFactor: 1,
        transportPolicy: "carrierRestricted"
      })
    }),
    range(EXERCISE_GARAGE_OUTDOOR, "Fuel / gasoline (container)", 0.1, 0.3, 0.8, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "generalSoft", densityClass: "medium", minBox: "small", maxBox: "small",
        itemTags: ["liquid", "dirty"], incompatibleTags: ["sharp", "heavy-on-fragile"],
        protectionFactor: 1.1, compressionFactor: 1,
        transportPolicy: "carrierRestricted"
      })
    }),
    range(EXERCISE_GARAGE_OUTDOOR, "Compressed gas cylinder (each)", 0.5, 1, 2, {
      packingUnit: packingUnit("countable"),
      packProfile: boxableProfile({
        lane: "generalSoft", densityClass: "heavy", minBox: "small", maxBox: "small",
        itemTags: ["dirty", "heavy-on-fragile"], incompatibleTags: ["liquid", "sharp"],
        protectionFactor: 1.1, compressionFactor: 1,
        transportPolicy: "carrierRestricted"
      })
    }),
    range(EXERCISE_GARAGE_OUTDOOR, "Lawnmower, push", 20, 28, 35),
    range(EXERCISE_GARAGE_OUTDOOR, "Lawnmower, riding", 85, 100, 120),
    range(EXERCISE_GARAGE_OUTDOOR, "Snow blower / leaf blower", 10, 15, 20),
    range(EXERCISE_GARAGE_OUTDOOR, "Ladder", 5, 12, 45),
    range(EXERCISE_GARAGE_OUTDOOR, "Grill, small", 12, 17, 25),
    range(EXERCISE_GARAGE_OUTDOOR, "Grill, large / 4-burner", 35, 45, 58),
    range(EXERCISE_GARAGE_OUTDOOR, "Patio table", 18, 25, 32),
    range(EXERCISE_GARAGE_OUTDOOR, "Patio chair (each)", 5, 8, 12, {
      packingUnit: packingUnit("countable")
    }),
    range(EXERCISE_GARAGE_OUTDOOR, "Patio set, 5-piece", 55, 70, 85),
    range(EXERCISE_GARAGE_OUTDOOR, "Outdoor chaise / swing", 40, 55, 65),
    range(EXERCISE_GARAGE_OUTDOOR, "Fire pit", 18, 25, 32),
    range(EXERCISE_GARAGE_OUTDOOR, "Trampoline", 20, 25, 35),
    range(EXERCISE_GARAGE_OUTDOOR, "Garbage can, large", 10, 15, 20),
    range(EXERCISE_GARAGE_OUTDOOR, "Storage tote / bin (each)", 3, 5, 8, {
      packingUnit: packingUnit("countable")
    }),
    range(EXERCISE_GARAGE_OUTDOOR, "Pool table", 280, 350, 400),
    range(EXERCISE_GARAGE_OUTDOOR, "Air hockey / foosball table", 40, 50, 60),

    fixed(BOXES, "Small box (1.5 cf)", 1.5, { packingUnit: packingUnit("countable") }),
    fixed(BOXES, "Medium box (3.0 cf)", 3, { packingUnit: packingUnit("countable") }),
    fixed(BOXES, "Large box (4.5 cf)", 4.5, { packingUnit: packingUnit("countable") }),
    fixed(BOXES, "Extra-large box (6.0 cf)", 6, { packingUnit: packingUnit("countable") }),
    fixed(BOXES, "Dish pack / china box", 6, { packingUnit: packingUnit("countable") }),
    fixed(BOXES, "Wardrobe box", 13, { packingUnit: packingUnit("countable") }),
    fixed(BOXES, "Picture/mirror carton", 3, { packingUnit: packingUnit("countable") }),

    range(SPECIALTY, "Piano (any)", "see Living Room", "—", "—"),
    range(SPECIALTY, "Gun safe / large safe", 30, 45, 60),
    range(SPECIALTY, "Pool table", 280, 350, 400),
    range(SPECIALTY, "Aquarium + stand", 10, 25, 65),
    range(SPECIALTY, "Hot tub (rare, flag for review)", 300, 375, 450)
  ],
  unknownSizeTypical: {
    small: 5,
    medium: 15,
    large: 30,
    oversized: 50
  }
};

const trucks = {
  capacities: [
    { key: "Pickup", cubicFeet: 75, fitsUpTo: { tier1: 65, tier2: 55, tier3: 50 } },
    { key: "Cargo van", cubicFeet: 245, fitsUpTo: { tier1: 210, tier2: 185, tier3: 170 } },
    { key: "10' truck", cubicFeet: 400, fitsUpTo: { tier1: 345, tier2: 305, tier3: 275 } },
    { key: "15' truck", cubicFeet: 760, fitsUpTo: { tier1: 660, tier2: 585, tier3: 520 } },
    { key: "20' truck", cubicFeet: 1015, fitsUpTo: { tier1: 880, tier2: 780, tier3: 700 } },
    { key: "26' truck", cubicFeet: 1680, fitsUpTo: { tier1: 1460, tier2: 1290, tier3: 1155 } }
  ],
  tiers: [
    {
      key: "tier1",
      label: "Packed tight",
      multiplier: 1.15,
      description: "floor-to-ceiling, tiered like a pro load"
    },
    {
      key: "tier2",
      label: "Pretty good",
      multiplier: 1.30,
      description: "solid load to about three-quarter height"
    },
    {
      key: "tier3",
      label: "Just get it in",
      multiplier: 1.45,
      description: "flat-loaded to roughly head height"
    }
  ],
  comfortableChoiceLabel: "the comfortable choice",
  above26: {
    message: "This won't fit in one 26' truck.",
    distanceThresholdMiles: 120,
    driveTimeDescription: "about two hours' drive",
    userChooses: true,
    underThresholdRecommendation: "secondTrip",
    overThresholdRecommendation: "secondTruck",
    options: [
      { key: "secondTrip", label: "Second trip", tradeoff: "time and fuel" },
      { key: "secondTruck", label: "Second truck", tradeoff: "rental cost" }
    ]
  }
};

const supplyRates = {
  smallBox: 1.75,
  mediumBox: 2.20,
  largeBox: 2.75,
  xlBox: 3.60,
  dishPack: 9.50,
  wardrobe: 14.00,
  pictureCarton: 8.00,
  packingPaper10lb: 14.00,
  bubbleRoll: 22.00,
  tapeRoll: 4.00,
  mattressBag: 10.00,
  stretchWrap: 16.00,
  marker: 2.00
};

const packing = {
  targetSessionMinutes: 40,
  minimumSessionMinutes: 20,
  cubicFeetPerHour: 45,
  boxEquivalentCubicFeet: 3,
  moveDayBufferDays: 1,
  suppliesDeliveryBufferDays: 2,
  behindPaceSessionsPerDay: 1.5,
  minimumRoomMinutesByType: {
    kitchen: 150,
    garage: 120,
    bedroom: 60,
    bathroom: 30
  },
  sequencingWeights: {
    storageSeasonal: 0,
    decorBooks: 1,
    guestSpare: 2,
    garage: 3,
    secondaryBedroom: 4,
    kitchenNonEssentials: 5,
    primaryBedroom: 6,
    bathrooms: 7,
    kitchenEssentials: 8
  }
};

function categoryDefault({ lane, densityClass, minBox, maxBox, specialtyRoute }) {
  return {
    lane,
    densityClass,
    minBox,
    maxBox,
    itemTags: [],
    incompatibleTags: [],
    protectionFactor: 1,
    compressionFactor: 1,
    notBoxable: true,
    ...(specialtyRoute ? { specialtyRoute } : {})
  };
}

const packingSim = {
  engineVersion: "sim-v2",
  routingPrecedence: [
    "transportPolicy",
    "packingState",
    "rowSpecialtyRoute",
    "rowNotBoxable",
    "categoryFallback",
    "laneSimulation"
  ],
  packingStates: [
    "loose",
    "alreadyPackedSealed",
    "alreadyPackedOpen",
    "emptyContainer",
    "visibleContentsStayInside",
    "closedContentsUnknown",
    "builtInOrStays"
  ],
  packingUnitBehaviors: ["indivisible", "countable", "bulkDivisible"],
  boxSizeOrder: ["small", "medium", "large", "xl"],
  lanes: {
    dense: { fillEfficiency: 0.82 },
    fragileClean: { fillEfficiency: 0.68 },
    generalSoft: { fillEfficiency: 0.8 }
  },
  densityClasses: {
    light: { lbPerCuFt: 6 },
    medium: { lbPerCuFt: 12 },
    heavy: { lbPerCuFt: 25 }
  },
  boxes: {
    small: {
      internalDimensionsIn: { length: 18, width: 12, height: 12 },
      usableCube: 1.5,
      maxGrossWeightLb: 50,
      permittedLanes: ["dense", "fragileClean", "generalSoft"]
    },
    medium: {
      internalDimensionsIn: { length: 18, width: 18, height: 16 },
      usableCube: 3,
      maxGrossWeightLb: 65,
      permittedLanes: ["dense", "fragileClean", "generalSoft"]
    },
    large: {
      internalDimensionsIn: { length: 18, width: 18, height: 24 },
      usableCube: 4.5,
      maxGrossWeightLb: 65,
      permittedLanes: ["fragileClean", "generalSoft"]
    },
    xl: {
      internalDimensionsIn: { length: 24, width: 18, height: 24 },
      usableCube: 6,
      maxGrossWeightLb: 70,
      permittedLanes: ["fragileClean", "generalSoft"]
    }
  },
  tags: ["liquid", "sharp", "dirty", "heavy-on-fragile"],
  specialtyContainerTypes: [
    "dishPack",
    "wardrobe",
    "pictureCarton",
    "mattressBag",
    "tvKit",
    "existingContainer",
    "handlingOnly"
  ],
  specialtyRoutes: {
    mattressBag: {
      containerType: "mattressBag",
      bagByCubeRowKey: {
        "Mattress only, king": "king",
        "Mattress only, queen/full": "queenFull",
        "Mattress only, twin": "twin"
      }
    },
    tvKit: {
      containerType: "tvKit",
      kitByCubeRowKey: {
        "TV, under 50\"": "under50",
        "TV, 55-65\"": "55to65",
        "TV, over 65\"": "over65"
      }
    },
    wardrobe: { containerType: "wardrobe", itemsPerWardrobe: 18 },
    pictureCarton: {
      containerType: "pictureCarton",
      itemsPerCartonBySizeBand: { small: 4, medium: 2, large: 1 },
      sizeBandByCubeRowKey: {
        "Framed art / photos, small (each)": "small",
        "Framed art, medium / large (each)": "medium",
        "Mirror / large picture": "large",
        "Full-length standing mirror": "large"
      }
    },
    dishPack: { containerType: "dishPack", bundlesPerPack: 8 },
    existingContainer: { containerType: "existingContainer" },
    handlingOnly: { containerType: "handlingOnly" }
  },
  transportPolicies: {
    carrierRestricted: {
      userFacingCopy: "Set this aside before packing. It may be restricted by a mover or carrier — rules vary by provider."
    },
    carrySeparately: {
      userFacingCopy: "Set this aside before packing. It may be restricted by a mover or carrier — rules vary by provider."
    }
  },
  transportKeywordRules: [
    {
      policy: "carrierRestricted",
      keywords: [
        "fuel", "gasoline", "propane", "compressed cylinder", "paint",
        "chemical", "bleach", "aerosol", "perishable", "loose battery"
      ]
    },
    {
      policy: "carrySeparately",
      keywords: ["medication", "prescription", "passport", "document", "valuable", "jewelry"]
    }
  ],
  availabilityFlags: ["packLast", "openFirst", "carrySeparately"],
  categoryDefaults: {
    [LIVING_ROOM]: categoryDefault({
      lane: "generalSoft", densityClass: "medium", minBox: "small", maxBox: "xl"
    }),
    [BEDROOM]: categoryDefault({
      lane: "generalSoft", densityClass: "medium", minBox: "small", maxBox: "xl"
    }),
    [DINING_KITCHEN]: categoryDefault({
      lane: "fragileClean", densityClass: "medium", minBox: "small", maxBox: "xl"
    }),
    [APPLIANCES]: categoryDefault({
      lane: "dense", densityClass: "heavy", minBox: "small", maxBox: "xl"
    }),
    [OFFICE]: categoryDefault({
      lane: "generalSoft", densityClass: "medium", minBox: "small", maxBox: "xl"
    }),
    [EXERCISE_GARAGE_OUTDOOR]: categoryDefault({
      lane: "dense", densityClass: "heavy", minBox: "small", maxBox: "xl"
    }),
    [BOXES]: categoryDefault({
      lane: "generalSoft", densityClass: "light", minBox: "small", maxBox: "xl",
      specialtyRoute: "existingContainer"
    }),
    [SPECIALTY]: categoryDefault({
      lane: "dense", densityClass: "heavy", minBox: "small", maxBox: "xl",
      specialtyRoute: "handlingOnly"
    })
  },
  stress: {
    ambiguousCubeBand: "high",
    uncertainFragileFillEfficiency: 0.55,
    coverageDebtAllowances: {
      closedDresser: {
        reason: "Closed dresser contents could not be verified.",
        reserveByContainerType: { medium: 2 }
      },
      closedCabinet: {
        reason: "Closed cabinet contents could not be verified.",
        reserveByContainerType: { small: 1, medium: 2 }
      },
      opaqueBin: {
        reason: "Opaque bin contents could not be verified.",
        reserveByContainerType: { medium: 1 }
      },
      closedCloset: {
        reason: "Closed closet contents could not be verified.",
        reserveByContainerType: { medium: 4, wardrobe: 1 }
      },
      closedContentsUnknown: {
        reason: "Closed storage contents could not be verified.",
        reserveByContainerType: { medium: 1 }
      }
    }
  },
  specialtyEstimator: {
    mattressBagsPerMattress: 1,
    tvKitsPerTelevision: 1
  },
  timeEstimation: {
    baseMinutesByBoxSize: { small: 5, medium: 8, large: 12, xl: 15 },
    minutesPerPackedUnit: 0.75,
    minimumMinutesPerBox: 5,
    rangeLowerFactor: 0.8,
    rangeUpperFactor: 1.25,
    rangeRoundingMinutes: 5
  },
  evidence: {
    coverageGrades: ["High", "Medium", "Limited"],
    mostUncertainItemLimit: 5,
    basedOnCopy: "Based on items visible in your walkthrough and the inventory you confirmed.",
    notIncludedCopy: "Items that were not visible or confirmed are not included."
  }
};

const positiveNumberSchema = { type: "number", exclusiveMinimum: 0 };
const positiveIntegerSchema = { type: "integer", minimum: 1 };
const nonNegativeNumberSchema = { type: "number", minimum: 0 };
const nonEmptyStringSchema = { type: "string", minLength: 1 };
const stringMapSchema = { type: "object", additionalProperties: nonEmptyStringSchema };

const packingUnitSchema = {
  type: "object",
  required: ["behavior"],
  properties: {
    behavior: { type: "string", enum: ["indivisible", "countable", "bulkDivisible"] },
    maxChunkQty: positiveIntegerSchema
  },
  additionalProperties: false
};

const packProfileSchema = {
  type: "object",
  required: [
    "lane",
    "densityClass",
    "minBox",
    "maxBox",
    "itemTags",
    "incompatibleTags",
    "protectionFactor",
    "compressionFactor"
  ],
  properties: {
    lane: nonEmptyStringSchema,
    densityClass: nonEmptyStringSchema,
    minBox: nonEmptyStringSchema,
    maxBox: nonEmptyStringSchema,
    itemTags: { type: "array", items: nonEmptyStringSchema },
    incompatibleTags: { type: "array", items: nonEmptyStringSchema },
    protectionFactor: positiveNumberSchema,
    compressionFactor: positiveNumberSchema,
    boxable: { type: "boolean" },
    notBoxable: { type: "boolean" },
    boxabilityPrecedence: {
      type: "string",
      enum: ["row", "boxable", "notBoxable"]
    },
    specialtyRoute: nonEmptyStringSchema,
    transportPolicy: nonEmptyStringSchema,
    availabilityFlag: nonEmptyStringSchema
  },
  additionalProperties: false
};

const cubeRowSchema = {
  type: "object",
  required: ["key", "category", "low", "typical", "high", "packingUnit"],
  properties: {
    key: nonEmptyStringSchema,
    category: nonEmptyStringSchema,
    low: { anyOf: [positiveNumberSchema, nonEmptyStringSchema] },
    typical: { anyOf: [positiveNumberSchema, nonEmptyStringSchema] },
    high: { anyOf: [positiveNumberSchema, nonEmptyStringSchema] },
    packingUnit: packingUnitSchema,
    packProfile: packProfileSchema
  },
  additionalProperties: false
};

const boxSchema = {
  type: "object",
  required: ["internalDimensionsIn", "usableCube", "maxGrossWeightLb", "permittedLanes"],
  properties: {
    internalDimensionsIn: {
      type: "object",
      required: ["length", "width", "height"],
      properties: {
        length: positiveNumberSchema,
        width: positiveNumberSchema,
        height: positiveNumberSchema
      },
      additionalProperties: false
    },
    usableCube: positiveNumberSchema,
    maxGrossWeightLb: positiveNumberSchema,
    permittedLanes: {
      type: "array",
      minItems: 1,
      items: nonEmptyStringSchema
    }
  },
  additionalProperties: false
};

const CONFIG_SCHEMAS = {
  [CONFIG_PATHS.anchors]: {
    type: "object",
    required: ["anchors"],
    properties: {
      anchors: {
        type: "array",
        minItems: 1,
        items: {
          type: "object",
          required: ["name", "standardDimension"],
          properties: { name: nonEmptyStringSchema, standardDimension: nonEmptyStringSchema },
          additionalProperties: false
        }
      }
    },
    additionalProperties: false
  },
  [CONFIG_PATHS.cubeSheet]: {
    type: "object",
    required: ["rows", "unknownSizeTypical", "configVersion"],
    properties: {
      rows: { type: "array", minItems: 1, items: cubeRowSchema },
      unknownSizeTypical: {
        type: "object",
        required: ["small", "medium", "large", "oversized"],
        properties: {
          small: positiveNumberSchema,
          medium: positiveNumberSchema,
          large: positiveNumberSchema,
          oversized: positiveNumberSchema
        },
        additionalProperties: false
      },
      configVersion: { type: "string", pattern: "^[a-f0-9]{64}$" }
    },
    additionalProperties: false
  },
  [CONFIG_PATHS.trucks]: {
    type: "object",
    required: ["capacities", "tiers", "comfortableChoiceLabel", "above26"],
    properties: {
      capacities: { type: "array", minItems: 1 },
      tiers: { type: "array", minItems: 1 },
      comfortableChoiceLabel: nonEmptyStringSchema,
      above26: { type: "object" }
    }
  },
  [CONFIG_PATHS.supplyRates]: {
    type: "object",
    required: [
      "smallBox", "mediumBox", "largeBox", "xlBox", "dishPack", "wardrobe",
      "pictureCarton", "packingPaper10lb", "bubbleRoll", "tapeRoll",
      "mattressBag", "stretchWrap", "marker"
    ],
    additionalProperties: positiveNumberSchema
  },
  [CONFIG_PATHS.packing]: {
    type: "object",
    required: [
      "targetSessionMinutes",
      "minimumSessionMinutes",
      "cubicFeetPerHour",
      "boxEquivalentCubicFeet",
      "moveDayBufferDays",
      "suppliesDeliveryBufferDays",
      "behindPaceSessionsPerDay",
      "minimumRoomMinutesByType",
      "sequencingWeights"
    ],
    properties: {
      targetSessionMinutes: positiveNumberSchema,
      minimumSessionMinutes: positiveNumberSchema,
      cubicFeetPerHour: positiveNumberSchema,
      boxEquivalentCubicFeet: positiveNumberSchema,
      moveDayBufferDays: positiveNumberSchema,
      suppliesDeliveryBufferDays: positiveNumberSchema,
      behindPaceSessionsPerDay: positiveNumberSchema,
      minimumRoomMinutesByType: { type: "object", additionalProperties: positiveNumberSchema },
      sequencingWeights: { type: "object", additionalProperties: nonNegativeNumberSchema }
    },
    additionalProperties: false
  },
  [CONFIG_PATHS.packingSim]: {
    type: "object",
    required: [
      "engineVersion",
      "routingPrecedence",
      "packingStates",
      "packingUnitBehaviors",
      "boxSizeOrder",
      "lanes",
      "densityClasses",
      "boxes",
      "tags",
      "specialtyContainerTypes",
      "specialtyRoutes",
      "transportPolicies",
      "transportKeywordRules",
      "availabilityFlags",
      "categoryDefaults",
      "stress",
      "specialtyEstimator",
      "timeEstimation",
      "evidence",
      "configVersion"
    ],
    properties: {
      engineVersion: { const: "sim-v2" },
      routingPrecedence: { type: "array", minItems: 1, items: nonEmptyStringSchema },
      packingStates: { type: "array", minItems: 1, items: nonEmptyStringSchema },
      packingUnitBehaviors: { type: "array", minItems: 1, items: nonEmptyStringSchema },
      boxSizeOrder: { type: "array", minItems: 1, items: nonEmptyStringSchema },
      lanes: {
        type: "object",
        required: ["dense", "fragileClean", "generalSoft"],
        properties: {
          dense: {
            type: "object",
            required: ["fillEfficiency"],
            properties: { fillEfficiency: positiveNumberSchema },
            additionalProperties: false
          },
          fragileClean: {
            type: "object",
            required: ["fillEfficiency"],
            properties: { fillEfficiency: positiveNumberSchema },
            additionalProperties: false
          },
          generalSoft: {
            type: "object",
            required: ["fillEfficiency"],
            properties: { fillEfficiency: positiveNumberSchema },
            additionalProperties: false
          }
        },
        additionalProperties: false
      },
      densityClasses: {
        type: "object",
        required: ["light", "medium", "heavy"],
        properties: {
          light: {
            type: "object",
            required: ["lbPerCuFt"],
            properties: { lbPerCuFt: positiveNumberSchema },
            additionalProperties: false
          },
          medium: {
            type: "object",
            required: ["lbPerCuFt"],
            properties: { lbPerCuFt: positiveNumberSchema },
            additionalProperties: false
          },
          heavy: {
            type: "object",
            required: ["lbPerCuFt"],
            properties: { lbPerCuFt: positiveNumberSchema },
            additionalProperties: false
          }
        },
        additionalProperties: false
      },
      boxes: {
        type: "object",
        required: ["small", "medium", "large", "xl"],
        properties: {
          small: boxSchema,
          medium: boxSchema,
          large: boxSchema,
          xl: boxSchema
        },
        additionalProperties: false
      },
      tags: { type: "array", minItems: 1, items: nonEmptyStringSchema },
      specialtyContainerTypes: { type: "array", minItems: 1, items: nonEmptyStringSchema },
      specialtyRoutes: {
        type: "object",
        required: [
          "mattressBag", "tvKit", "wardrobe", "pictureCarton", "dishPack",
          "existingContainer", "handlingOnly"
        ],
        properties: {
          mattressBag: {
            type: "object",
            required: ["containerType", "bagByCubeRowKey"],
            properties: { containerType: nonEmptyStringSchema, bagByCubeRowKey: stringMapSchema },
            additionalProperties: false
          },
          tvKit: {
            type: "object",
            required: ["containerType", "kitByCubeRowKey"],
            properties: { containerType: nonEmptyStringSchema, kitByCubeRowKey: stringMapSchema },
            additionalProperties: false
          },
          wardrobe: {
            type: "object",
            required: ["containerType", "itemsPerWardrobe"],
            properties: { containerType: nonEmptyStringSchema, itemsPerWardrobe: positiveIntegerSchema },
            additionalProperties: false
          },
          pictureCarton: {
            type: "object",
            required: ["containerType", "itemsPerCartonBySizeBand", "sizeBandByCubeRowKey"],
            properties: {
              containerType: nonEmptyStringSchema,
              itemsPerCartonBySizeBand: {
                type: "object",
                required: ["small", "medium", "large"],
                properties: {
                  small: positiveIntegerSchema,
                  medium: positiveIntegerSchema,
                  large: positiveIntegerSchema
                },
                additionalProperties: false
              },
              sizeBandByCubeRowKey: stringMapSchema
            },
            additionalProperties: false
          },
          dishPack: {
            type: "object",
            required: ["containerType", "bundlesPerPack"],
            properties: { containerType: nonEmptyStringSchema, bundlesPerPack: positiveIntegerSchema },
            additionalProperties: false
          },
          existingContainer: {
            type: "object",
            required: ["containerType"],
            properties: { containerType: nonEmptyStringSchema },
            additionalProperties: false
          },
          handlingOnly: {
            type: "object",
            required: ["containerType"],
            properties: { containerType: nonEmptyStringSchema },
            additionalProperties: false
          }
        },
        additionalProperties: false
      },
      transportPolicies: {
        type: "object",
        required: ["carrierRestricted", "carrySeparately"],
        properties: {
          carrierRestricted: {
            type: "object",
            required: ["userFacingCopy"],
            properties: { userFacingCopy: nonEmptyStringSchema },
            additionalProperties: false
          },
          carrySeparately: {
            type: "object",
            required: ["userFacingCopy"],
            properties: { userFacingCopy: nonEmptyStringSchema },
            additionalProperties: false
          }
        },
        additionalProperties: false
      },
      transportKeywordRules: {
        type: "array",
        items: {
          type: "object",
          required: ["policy", "keywords"],
          properties: {
            policy: nonEmptyStringSchema,
            keywords: { type: "array", minItems: 1, items: nonEmptyStringSchema }
          },
          additionalProperties: false
        }
      },
      availabilityFlags: { type: "array", minItems: 1, items: nonEmptyStringSchema },
      categoryDefaults: { type: "object", additionalProperties: packProfileSchema },
      stress: {
        type: "object",
        required: ["ambiguousCubeBand", "uncertainFragileFillEfficiency", "coverageDebtAllowances"],
        properties: {
          ambiguousCubeBand: { const: "high" },
          uncertainFragileFillEfficiency: positiveNumberSchema,
          coverageDebtAllowances: {
            type: "object",
            additionalProperties: {
              type: "object",
              required: ["reason", "reserveByContainerType"],
              properties: {
                reason: nonEmptyStringSchema,
                reserveByContainerType: {
                  type: "object",
                  additionalProperties: positiveIntegerSchema
                }
              },
              additionalProperties: false
            }
          }
        },
        additionalProperties: false
      },
      specialtyEstimator: {
        type: "object",
        required: ["mattressBagsPerMattress", "tvKitsPerTelevision"],
        properties: {
          mattressBagsPerMattress: positiveIntegerSchema,
          tvKitsPerTelevision: positiveIntegerSchema
        },
        additionalProperties: false
      },
      timeEstimation: {
        type: "object",
        required: [
          "baseMinutesByBoxSize",
          "minutesPerPackedUnit",
          "minimumMinutesPerBox",
          "rangeLowerFactor",
          "rangeUpperFactor",
          "rangeRoundingMinutes"
        ],
        properties: {
          baseMinutesByBoxSize: {
            type: "object",
            required: ["small", "medium", "large", "xl"],
            properties: {
              small: positiveNumberSchema,
              medium: positiveNumberSchema,
              large: positiveNumberSchema,
              xl: positiveNumberSchema
            },
            additionalProperties: false
          },
          minutesPerPackedUnit: positiveNumberSchema,
          minimumMinutesPerBox: positiveNumberSchema,
          rangeLowerFactor: positiveNumberSchema,
          rangeUpperFactor: positiveNumberSchema,
          rangeRoundingMinutes: positiveNumberSchema
        },
        additionalProperties: false
      },
      evidence: {
        type: "object",
        required: ["coverageGrades", "mostUncertainItemLimit", "basedOnCopy", "notIncludedCopy"],
        properties: {
          coverageGrades: { type: "array", minItems: 1, items: nonEmptyStringSchema },
          mostUncertainItemLimit: positiveIntegerSchema,
          basedOnCopy: nonEmptyStringSchema,
          notIncludedCopy: nonEmptyStringSchema
        },
        additionalProperties: false
      },
      configVersion: { type: "string", pattern: "^[a-f0-9]{64}$" }
    },
    additionalProperties: false
  }
};

function schemaError(path, message) {
  throw new Error(`Schema validation failed at ${path}: ${message}`);
}

function matchesType(value, type) {
  if (type === "array") return Array.isArray(value);
  if (type === "object") return value !== null && typeof value === "object" && !Array.isArray(value);
  if (type === "integer") return Number.isInteger(value);
  if (type === "number") return typeof value === "number" && Number.isFinite(value);
  return typeof value === type;
}

function assertJsonSchema(value, schema, path) {
  if (schema.anyOf) {
    const matched = schema.anyOf.some((candidate) => {
      try {
        assertJsonSchema(value, candidate, path);
        return true;
      } catch (_) {
        return false;
      }
    });
    if (!matched) schemaError(path, "does not match any allowed shape");
    return;
  }

  if (schema.const !== undefined && !isDeepStrictEqual(value, schema.const)) {
    schemaError(path, `must equal ${JSON.stringify(schema.const)}`);
  }
  if (schema.type && !matchesType(value, schema.type)) {
    schemaError(path, `must be ${schema.type}`);
  }
  if (schema.enum && !schema.enum.includes(value)) {
    schemaError(path, `must be one of ${schema.enum.join(", ")}`);
  }
  if (typeof value === "string" && schema.minLength && value.length < schema.minLength) {
    schemaError(path, `must contain at least ${schema.minLength} characters`);
  }
  if (typeof value === "string" && schema.pattern && !(new RegExp(schema.pattern)).test(value)) {
    schemaError(path, `must match ${schema.pattern}`);
  }
  if (typeof value === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) {
      schemaError(path, `must be at least ${schema.minimum}`);
    }
    if (schema.exclusiveMinimum !== undefined && value <= schema.exclusiveMinimum) {
      schemaError(path, `must be greater than ${schema.exclusiveMinimum}`);
    }
    if (schema.maximum !== undefined && value > schema.maximum) {
      schemaError(path, `must be at most ${schema.maximum}`);
    }
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) {
      schemaError(path, `must contain at least ${schema.minItems} item(s)`);
    }
    if (schema.items) {
      value.forEach((item, index) => assertJsonSchema(item, schema.items, `${path}[${index}]`));
    }
  }
  if (matchesType(value, "object")) {
    (schema.required || []).forEach((key) => {
      if (!Object.prototype.hasOwnProperty.call(value, key)) {
        schemaError(path, `is missing required field ${key}`);
      }
    });
    const properties = schema.properties || {};
    Object.entries(value).forEach(([key, child]) => {
      if (properties[key]) {
        assertJsonSchema(child, properties[key], `${path}.${key}`);
      } else if (schema.additionalProperties === false) {
        schemaError(path, `contains unsupported field ${key}`);
      } else if (schema.additionalProperties && typeof schema.additionalProperties === "object") {
        assertJsonSchema(child, schema.additionalProperties, `${path}.${key}`);
      }
    });
  }
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value !== null && typeof value === "object") {
    return Object.keys(value).sort().reduce((result, key) => {
      result[key] = canonicalize(value[key]);
      return result;
    }, {});
  }
  return value;
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function withoutConfigVersion(value) {
  const result = clone(value);
  delete result.configVersion;
  return result;
}

function calculateConfigVersion(cubeSheetData, packingSimData) {
  const content = canonicalize({
    cubeSheet: withoutConfigVersion(cubeSheetData),
    packingSim: withoutConfigVersion(packingSimData)
  });
  return createHash("sha256").update(JSON.stringify(content)).digest("hex");
}

function buildConfigDocuments({
  cubeSheetData = cubeSheet,
  packingSimData = packingSim
} = {}) {
  const version = calculateConfigVersion(cubeSheetData, packingSimData);
  return [
    { path: CONFIG_PATHS.anchors, data: clone(anchors) },
    { path: CONFIG_PATHS.cubeSheet, data: { ...clone(cubeSheetData), configVersion: version } },
    { path: CONFIG_PATHS.trucks, data: clone(trucks) },
    { path: CONFIG_PATHS.supplyRates, data: clone(supplyRates) },
    { path: CONFIG_PATHS.packing, data: clone(packing) },
    { path: CONFIG_PATHS.packingSim, data: { ...clone(packingSimData), configVersion: version } }
  ];
}

function assertUnique(values, path) {
  if (new Set(values).size !== values.length) {
    throw new Error(`Conflict validation failed at ${path}: values must be unique`);
  }
}

function assertResolved(value, allowedValues, path) {
  if (!allowedValues.has(value)) {
    throw new Error(`Cross-reference validation failed at ${path}: ${value} does not resolve`);
  }
}

function assertFactorRanges(profile, path) {
  if (profile.protectionFactor < 1) {
    throw new Error(`Range validation failed at ${path}.protectionFactor: must be at least 1`);
  }
  if (profile.compressionFactor <= 0 || profile.compressionFactor > 1) {
    throw new Error(`Range validation failed at ${path}.compressionFactor: must be greater than 0 and at most 1`);
  }
}

function validatePackingReferencesAndRanges(cubeSheetData, packingSimData) {
  const expectedPrecedence = [
    "transportPolicy",
    "packingState",
    "rowSpecialtyRoute",
    "rowNotBoxable",
    "categoryFallback",
    "laneSimulation"
  ];
  if (!isDeepStrictEqual(packingSimData.routingPrecedence, expectedPrecedence)) {
    throw new Error("Conflict validation failed: routingPrecedence must preserve the locked order");
  }
  const expectedPackingStates = [
    "loose",
    "alreadyPackedSealed",
    "alreadyPackedOpen",
    "emptyContainer",
    "visibleContentsStayInside",
    "closedContentsUnknown",
    "builtInOrStays"
  ];
  if (!isDeepStrictEqual(packingSimData.packingStates, expectedPackingStates)) {
    throw new Error("Conflict validation failed: packingStates must preserve the locked states and order");
  }
  if (!isDeepStrictEqual(packingSimData.boxSizeOrder, ["small", "medium", "large", "xl"])) {
    throw new Error("Conflict validation failed: boxSizeOrder must be small, medium, large, xl");
  }
  if (!isDeepStrictEqual(
    packingSimData.packingUnitBehaviors,
    ["indivisible", "countable", "bulkDivisible"]
  )) {
    throw new Error("Conflict validation failed: packingUnitBehaviors must preserve all three behaviors");
  }

  const laneKeys = new Set(Object.keys(packingSimData.lanes));
  const densityKeys = new Set(Object.keys(packingSimData.densityClasses));
  const boxKeys = new Set(Object.keys(packingSimData.boxes));
  const routeKeys = new Set(Object.keys(packingSimData.specialtyRoutes));
  const tagKeys = new Set(packingSimData.tags);
  const policyKeys = new Set(Object.keys(packingSimData.transportPolicies));
  const availabilityKeys = new Set(packingSimData.availabilityFlags);
  const packingBehaviors = new Set(packingSimData.packingUnitBehaviors);
  const specialtyContainers = new Set(packingSimData.specialtyContainerTypes);
  const allContainerTypes = new Set([...boxKeys, ...specialtyContainers]);
  const rowKeys = new Set(cubeSheetData.rows.map((row) => row.key));
  const boxIndex = new Map(packingSimData.boxSizeOrder.map((key, index) => [key, index]));

  assertUnique([...laneKeys], "packingSim.lanes");
  assertUnique([...densityKeys], "packingSim.densityClasses");
  assertUnique(packingSimData.boxSizeOrder, "packingSim.boxSizeOrder");
  assertUnique(packingSimData.tags, "packingSim.tags");
  assertUnique(packingSimData.availabilityFlags, "packingSim.availabilityFlags");

  const unknownBands = cubeSheetData.unknownSizeTypical;
  if (!(unknownBands.small <= unknownBands.medium &&
        unknownBands.medium <= unknownBands.large &&
        unknownBands.large <= unknownBands.oversized)) {
    throw new Error("Range validation failed at cubeSheet.unknownSizeTypical: size bands must be ascending");
  }

  packingSimData.boxSizeOrder.forEach((boxKey, index) => {
    assertResolved(boxKey, boxKeys, `packingSim.boxSizeOrder[${index}]`);
  });
  if (packingSimData.boxSizeOrder.length !== boxKeys.size) {
    throw new Error("Cross-reference validation failed: boxSizeOrder must name every box exactly once");
  }

  Object.entries(packingSimData.lanes).forEach(([lane, config]) => {
    if (config.fillEfficiency <= 0 || config.fillEfficiency > 1) {
      throw new Error(`Range validation failed at packingSim.lanes.${lane}.fillEfficiency: must be greater than 0 and at most 1`);
    }
  });
  Object.entries(packingSimData.densityClasses).forEach(([density, config]) => {
    if (config.lbPerCuFt <= 0) {
      throw new Error(`Range validation failed at packingSim.densityClasses.${density}.lbPerCuFt: must be positive`);
    }
  });
  Object.entries(packingSimData.boxes).forEach(([boxKey, box]) => {
    if (box.usableCube <= 0 || box.maxGrossWeightLb <= 0) {
      throw new Error(`Range validation failed at packingSim.boxes.${boxKey}: cube and weight must be positive`);
    }
    Object.entries(box.internalDimensionsIn).forEach(([dimension, value]) => {
      if (value <= 0) {
        throw new Error(`Range validation failed at packingSim.boxes.${boxKey}.internalDimensionsIn.${dimension}: must be positive`);
      }
    });
    assertUnique(box.permittedLanes, `packingSim.boxes.${boxKey}.permittedLanes`);
    box.permittedLanes.forEach((lane, index) => {
      assertResolved(lane, laneKeys, `packingSim.boxes.${boxKey}.permittedLanes[${index}]`);
    });
  });

  Object.entries(packingSimData.specialtyRoutes).forEach(([route, routeConfig]) => {
    assertResolved(
      routeConfig.containerType,
      specialtyContainers,
      `packingSim.specialtyRoutes.${route}.containerType`
    );
    ["bagByCubeRowKey", "kitByCubeRowKey", "sizeBandByCubeRowKey"].forEach((mapName) => {
      Object.keys(routeConfig[mapName] || {}).forEach((rowKey) => {
        assertResolved(rowKey, rowKeys, `packingSim.specialtyRoutes.${route}.${mapName}`);
      });
    });
  });
  packingSimData.transportKeywordRules.forEach((rule, index) => {
    assertResolved(rule.policy, policyKeys, `packingSim.transportKeywordRules[${index}].policy`);
  });

  function validateProfile(profile, path) {
    assertResolved(profile.lane, laneKeys, `${path}.lane`);
    assertResolved(profile.densityClass, densityKeys, `${path}.densityClass`);
    assertResolved(profile.minBox, boxKeys, `${path}.minBox`);
    assertResolved(profile.maxBox, boxKeys, `${path}.maxBox`);
    [...profile.itemTags, ...profile.incompatibleTags].forEach((tag, index) => {
      assertResolved(tag, tagKeys, `${path}.tags[${index}]`);
    });
    if (profile.specialtyRoute) {
      assertResolved(profile.specialtyRoute, routeKeys, `${path}.specialtyRoute`);
    }
    if (profile.transportPolicy) {
      assertResolved(profile.transportPolicy, policyKeys, `${path}.transportPolicy`);
    }
    if (profile.availabilityFlag) {
      assertResolved(profile.availabilityFlag, availabilityKeys, `${path}.availabilityFlag`);
    }
    if (boxIndex.get(profile.minBox) > boxIndex.get(profile.maxBox)) {
      throw new Error(`Range validation failed at ${path}: minBox must not exceed maxBox`);
    }
    const permittedBoxExists = packingSimData.boxSizeOrder
      .slice(boxIndex.get(profile.minBox), boxIndex.get(profile.maxBox) + 1)
      .some((boxKey) => packingSimData.boxes[boxKey].permittedLanes.includes(profile.lane));
    if (!permittedBoxExists && !profile.specialtyRoute && !profile.transportPolicy && !profile.notBoxable) {
      throw new Error(`Cross-reference validation failed at ${path}: no permitted box resolves for lane ${profile.lane}`);
    }
    assertFactorRanges(profile, path);
    if (profile.boxable === true && profile.notBoxable === true &&
        !["boxable", "notBoxable"].includes(profile.boxabilityPrecedence)) {
      throw new Error(`Conflict validation failed at ${path}: boxable vs notBoxable needs explicit precedence`);
    }
  }

  Object.entries(packingSimData.categoryDefaults).forEach(([category, profile]) => {
    validateProfile(profile, `packingSim.categoryDefaults.${category}`);
  });

  cubeSheetData.rows.forEach((row, index) => {
    const rowPath = `cubeSheet.rows[${index}]`;
    const categoryProfile = packingSimData.categoryDefaults[row.category];
    if (!categoryProfile) {
      throw new Error(`Cross-reference validation failed at ${rowPath}.category: ${row.category} has no fallback`);
    }
    assertResolved(row.packingUnit.behavior, packingBehaviors, `${rowPath}.packingUnit.behavior`);
    if (row.packingUnit.behavior === "bulkDivisible") {
      if (!Number.isInteger(row.packingUnit.maxChunkQty) || row.packingUnit.maxChunkQty <= 0) {
        throw new Error(`Range validation failed at ${rowPath}.packingUnit.maxChunkQty: must be a positive integer`);
      }
    } else if (row.packingUnit.maxChunkQty !== undefined) {
      throw new Error(`Conflict validation failed at ${rowPath}.packingUnit: maxChunkQty is only valid for bulkDivisible`);
    }
    if ([row.low, row.typical, row.high].every((value) => typeof value === "number") &&
        !(row.low <= row.typical && row.typical <= row.high)) {
      throw new Error(`Range validation failed at ${rowPath}: cube values must satisfy low <= typical <= high`);
    }
    if (row.packProfile) {
      validateProfile(row.packProfile, `${rowPath}.packProfile`);
      const rowBoxableBeatsCategory = row.packProfile.boxable === true && categoryProfile.notBoxable === true;
      const rowNotBoxableBeatsCategory = row.packProfile.notBoxable === true && categoryProfile.boxable === true;
      if ((rowBoxableBeatsCategory || rowNotBoxableBeatsCategory) &&
          row.packProfile.boxabilityPrecedence !== "row") {
        throw new Error(`Conflict validation failed at ${rowPath}.packProfile: row/category boxability needs row precedence`);
      }
    }
  });

  const stressFill = packingSimData.stress.uncertainFragileFillEfficiency;
  if (stressFill <= 0 || stressFill > 1 || stressFill >= packingSimData.lanes.fragileClean.fillEfficiency) {
    throw new Error("Range validation failed at packingSim.stress.uncertainFragileFillEfficiency: must be positive and lower than fragileClean fillEfficiency");
  }
  Object.entries(packingSimData.stress.coverageDebtAllowances).forEach(([debtType, allowance]) => {
    if (!allowance.reason || !allowance.reserveByContainerType) {
      throw new Error(`Schema validation failed at packingSim.stress.coverageDebtAllowances.${debtType}: reason and reserveByContainerType are required`);
    }
    Object.entries(allowance.reserveByContainerType).forEach(([containerType, count]) => {
      assertResolved(
        containerType,
        allContainerTypes,
        `packingSim.stress.coverageDebtAllowances.${debtType}.reserveByContainerType`
      );
      if (!Number.isInteger(count) || count <= 0) {
        throw new Error(`Range validation failed at packingSim.stress.coverageDebtAllowances.${debtType}.${containerType}: count must be a positive integer`);
      }
    });
  });

  const time = packingSimData.timeEstimation;
  if (time.rangeLowerFactor >= 1 || time.rangeUpperFactor <= 1) {
    throw new Error("Range validation failed at packingSim.timeEstimation: the configured range must spread below and above the central estimate");
  }
}

function validateConfigDocuments(documents) {
  const byPath = new Map(documents.map(({ path, data }) => [path, data]));
  if (byPath.size !== documents.length) {
    throw new Error("Conflict validation failed: config document paths must be unique");
  }
  Object.entries(CONFIG_SCHEMAS).forEach(([path, schema]) => {
    if (!byPath.has(path)) schemaError(path, "document is missing");
    assertJsonSchema(byPath.get(path), schema, path);
  });

  const cubeSheetData = byPath.get(CONFIG_PATHS.cubeSheet);
  const packingSimData = byPath.get(CONFIG_PATHS.packingSim);
  const expectedVersion = calculateConfigVersion(cubeSheetData, packingSimData);
  if (cubeSheetData.configVersion !== expectedVersion || packingSimData.configVersion !== expectedVersion) {
    throw new Error("Conflict validation failed: configVersion does not match the seeded content hash");
  }
  validatePackingReferencesAndRanges(cubeSheetData, packingSimData);
}

const configDocuments = buildConfigDocuments();

async function seedCubeSheet({ adminClient = admin, documents = buildConfigDocuments() } = {}) {
  validateConfigDocuments(documents);

  if (!adminClient.apps.length) {
    const serviceAccount = require("./serviceAccountKey.json");
    adminClient.initializeApp({ credential: adminClient.credential.cert(serviceAccount) });
  }

  const db = adminClient.firestore();
  const batch = db.batch();
  documents.forEach(({ path, data }) => {
    batch.set(db.doc(path), data, { merge: true });
  });
  await batch.commit();

  const snapshots = await Promise.all(documents.map(({ path }) => db.doc(path).get()));
  snapshots.forEach((snapshot, index) => {
    const { path, data } = documents[index];
    const stored = snapshot.data() || {};
    const matches = snapshot.exists && Object.entries(data).every(
      ([key, value]) => isDeepStrictEqual(stored[key], value)
    );
    if (!matches) {
      throw new Error(`Round-trip failed for ${path}`);
    }
  });
  return documents;
}

async function main() {
  console.log("Seeding inventory configuration...");
  const seededDocuments = await seedCubeSheet();
  seededDocuments.forEach(({ path }) => console.log(`✅ Seeded and read back ${path}`));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`❌ Inventory config seed failed: ${error.message}`);
    process.exit(1);
  });
}

module.exports = {
  anchors,
  cubeSheet,
  trucks,
  supplyRates,
  packing,
  packingSim,
  buildConfigDocuments,
  calculateConfigVersion,
  validateConfigDocuments,
  seedCubeSheet
};
