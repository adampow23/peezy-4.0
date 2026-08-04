/**
 * Seeds the inventory anchors, cube sheet, and truck configuration.
 *
 * Usage:
 *   cd functions && node seedCubeSheet.js
 */

const admin = require("firebase-admin");
const { isDeepStrictEqual } = require("node:util");

const CONFIG_PATHS = {
  anchors: "appConfig/anchors",
  cubeSheet: "appConfig/cubeSheet",
  trucks: "appConfig/trucks"
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

function range(category, key, low, typical, high) {
  return { key, category, low, typical, high };
}

function fixed(category, key, cubicFeet) {
  return range(category, key, cubicFeet, cubicFeet, cubicFeet);
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
    range(LIVING_ROOM, "TV, 55-65\"", 12, 15, 18),
    range(LIVING_ROOM, "TV, under 50\"", 5, 10, 13),
    range(LIVING_ROOM, "TV, over 65\"", 15, 20, 30),
    range(LIVING_ROOM, "TV stand", 8, 10, 15),
    range(LIVING_ROOM, "Entertainment center", 20, 40, 60),
    range(LIVING_ROOM, "Wall unit (per piece)", 30, 40, 55),
    range(LIVING_ROOM, "Bookcase / bookshelf", 10, 20, 35),
    range(LIVING_ROOM, "Shelving unit", 10, 25, 50),
    range(LIVING_ROOM, "Curio / display cabinet", 15, 22, 30),
    range(LIVING_ROOM, "Floor lamp", 8, 10, 12),
    range(LIVING_ROOM, "Table lamp", 3, 5, 8),
    range(LIVING_ROOM, "Area rug, large (8x10+)", 12, 18, 22),
    range(LIVING_ROOM, "Area rug, small", 4, 6, 10),
    range(LIVING_ROOM, "Mirror / large picture", 5, 7, 12),
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
    range(BEDROOM, "Mattress only, king", 35, 40, 45),
    range(BEDROOM, "Mattress only, queen/full", 25, 30, 35),
    range(BEDROOM, "Mattress only, twin", 15, 20, 25),
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
    range(BEDROOM, "Full-length standing mirror", 15, 22, 28),

    range(DINING_KITCHEN, "Dining table", 28, 35, 48),
    range(DINING_KITCHEN, "Kitchen table", 15, 20, 25),
    range(DINING_KITCHEN, "Bistro / pub table", 10, 20, 26),
    range(DINING_KITCHEN, "Dining/kitchen chair (each)", 4, 5, 7),
    range(DINING_KITCHEN, "Bar stool (each)", 5, 7, 9),
    range(DINING_KITCHEN, "China cabinet / hutch", 40, 50, 60),
    range(DINING_KITCHEN, "Buffet / sideboard", 35, 45, 58),
    range(DINING_KITCHEN, "Credenza", 30, 40, 50),
    range(DINING_KITCHEN, "Baker's rack", 18, 25, 30),
    range(DINING_KITCHEN, "Kitchen island, freestanding", 30, 45, 55),
    range(DINING_KITCHEN, "Wine rack", 8, 15, 25),
    range(DINING_KITCHEN, "Microwave", 4, 7, 10),
    range(DINING_KITCHEN, "Microwave cart", 8, 10, 14),
    range(DINING_KITCHEN, "High chair", 7, 10, 12),

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
    range(OFFICE, "Computer / monitor setup", 8, 12, 18),
    range(OFFICE, "Printer, home", 3, 5, 8),
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
    range(EXERCISE_GARAGE_OUTDOOR, "Toolbox, hand-carry", 3, 5, 8),
    range(EXERCISE_GARAGE_OUTDOOR, "Lawnmower, push", 20, 28, 35),
    range(EXERCISE_GARAGE_OUTDOOR, "Lawnmower, riding", 85, 100, 120),
    range(EXERCISE_GARAGE_OUTDOOR, "Snow blower / leaf blower", 10, 15, 20),
    range(EXERCISE_GARAGE_OUTDOOR, "Ladder", 5, 12, 45),
    range(EXERCISE_GARAGE_OUTDOOR, "Grill, small", 12, 17, 25),
    range(EXERCISE_GARAGE_OUTDOOR, "Grill, large / 4-burner", 35, 45, 58),
    range(EXERCISE_GARAGE_OUTDOOR, "Patio table", 18, 25, 32),
    range(EXERCISE_GARAGE_OUTDOOR, "Patio chair (each)", 5, 8, 12),
    range(EXERCISE_GARAGE_OUTDOOR, "Patio set, 5-piece", 55, 70, 85),
    range(EXERCISE_GARAGE_OUTDOOR, "Outdoor chaise / swing", 40, 55, 65),
    range(EXERCISE_GARAGE_OUTDOOR, "Fire pit", 18, 25, 32),
    range(EXERCISE_GARAGE_OUTDOOR, "Trampoline", 20, 25, 35),
    range(EXERCISE_GARAGE_OUTDOOR, "Garbage can, large", 10, 15, 20),
    range(EXERCISE_GARAGE_OUTDOOR, "Storage tote / bin (each)", 3, 5, 8),
    range(EXERCISE_GARAGE_OUTDOOR, "Pool table", 280, 350, 400),
    range(EXERCISE_GARAGE_OUTDOOR, "Air hockey / foosball table", 40, 50, 60),

    fixed(BOXES, "Small box (1.5 cf)", 1.5),
    fixed(BOXES, "Medium box (3.0 cf)", 3),
    fixed(BOXES, "Large box (4.5 cf)", 4.5),
    fixed(BOXES, "Extra-large box (6.0 cf)", 6),
    fixed(BOXES, "Dish pack / china box", 6),
    fixed(BOXES, "Wardrobe box", 13),
    fixed(BOXES, "Picture/mirror carton", 3),

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

const configDocuments = [
  { path: CONFIG_PATHS.anchors, data: anchors },
  { path: CONFIG_PATHS.cubeSheet, data: cubeSheet },
  { path: CONFIG_PATHS.trucks, data: trucks }
];

async function seedCubeSheet() {
  if (!admin.apps.length) {
    const serviceAccount = require("./serviceAccountKey.json");
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  }

  const db = admin.firestore();
  await Promise.all(configDocuments.map(({ path, data }) => (
    db.doc(path).set(data, { merge: true })
  )));

  const snapshots = await Promise.all(configDocuments.map(({ path }) => db.doc(path).get()));
  snapshots.forEach((snapshot, index) => {
    const { path, data } = configDocuments[index];
    const stored = snapshot.data() || {};
    const matches = snapshot.exists && Object.entries(data).every(
      ([key, value]) => isDeepStrictEqual(stored[key], value)
    );
    if (!matches) {
      throw new Error(`Round-trip failed for ${path}`);
    }
  });
}

async function main() {
  console.log("Seeding inventory configuration...");
  await seedCubeSheet();
  configDocuments.forEach(({ path }) => console.log(`✅ Seeded and read back ${path}`));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`❌ Inventory config seed failed: ${error.message}`);
    process.exit(1);
  });
}

module.exports = { anchors, cubeSheet, trucks, seedCubeSheet };
