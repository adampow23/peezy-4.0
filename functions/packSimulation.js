"use strict";

const STRESS_RUNTIME_KEY = "__packingSimulationStress";
const LOOSE_STATE = "loose";

function stressConfigTransform(config) {
  if (!config || typeof config !== "object") {
    throw new TypeError("packing config must be an object");
  }

  const packingSim = config.packingSim || config;
  if (!packingSim.stress || typeof packingSim.stress !== "object") {
    throw new Error("packing config is missing stress settings");
  }

  const transformedPackingSim = {
    ...packingSim,
    [STRESS_RUNTIME_KEY]: {
      cubeBand: packingSim.stress.ambiguousCubeBand,
      uncertainFragileFillEfficiency:
        packingSim.stress.uncertainFragileFillEfficiency
    }
  };

  return config.packingSim
    ? { ...config, packingSim: transformedPackingSim }
    : transformedPackingSim;
}

function normalizeConfig(config) {
  if (!config || typeof config !== "object") {
    throw new TypeError("packing config must be an object");
  }

  const packingSim = config.packingSim || config;
  const cubeRows = config.cubeSheet?.rows || config.cubeRows || config.rows;
  if (!Array.isArray(cubeRows)) {
    throw new Error("packing config is missing cube-sheet rows");
  }
  if (!Array.isArray(packingSim.boxSizeOrder) || !packingSim.boxes ||
      !packingSim.lanes || !packingSim.densityClasses) {
    throw new Error("packing config is missing lane or box settings");
  }

  const rowByKey = new Map();
  for (const row of cubeRows) {
    if (row && typeof row.key === "string" && !rowByKey.has(row.key)) {
      rowByKey.set(row.key, row);
    }
  }

  return {
    packingSim,
    rowByKey,
    stressRuntime: packingSim[STRESS_RUNTIME_KEY] || null
  };
}

function finiteFrameValues(item) {
  const values = [];
  if (Array.isArray(item.frameIndices)) {
    for (const value of item.frameIndices) {
      const number = Number(value);
      if (Number.isFinite(number)) values.push(number);
    }
  }
  if (item.frameIndex != null) {
    const frameIndex = Number(item.frameIndex);
    if (Number.isFinite(frameIndex)) values.push(frameIndex);
  }
  return values;
}

function firstSeenFrame(item) {
  const values = finiteFrameValues(item);
  return values.length > 0 ? Math.min(...values) : Number.POSITIVE_INFINITY;
}

function inventoryItemId(item, originalIndex) {
  const candidate = item.inventoryItemId ?? item.id ?? item.documentId ?? item.docId;
  return candidate == null || String(candidate).length === 0
    ? `input-${originalIndex}`
    : String(candidate);
}

function roomDocumentId(item) {
  const candidate = item.roomDocumentId ?? item.roomDocId ?? item.roomId ?? item.roomName;
  return candidate == null || String(candidate).length === 0
    ? "single-room"
    : String(candidate);
}

function orderedInventoryItems(items) {
  const indexed = items.map((item, originalIndex) => ({
    item,
    originalIndex,
    inventoryItemId: inventoryItemId(item, originalIndex),
    roomDocumentId: roomDocumentId(item),
    firstSeenFrame: firstSeenFrame(item)
  }));

  const roomFirstSeen = new Map();
  for (const entry of indexed) {
    const previous = roomFirstSeen.get(entry.roomDocumentId);
    if (previous === undefined || entry.firstSeenFrame < previous) {
      roomFirstSeen.set(entry.roomDocumentId, entry.firstSeenFrame);
    }
  }

  return indexed.sort((left, right) => {
    const leftRoomFrame = roomFirstSeen.get(left.roomDocumentId);
    const rightRoomFrame = roomFirstSeen.get(right.roomDocumentId);
    if (leftRoomFrame < rightRoomFrame) return -1;
    if (leftRoomFrame > rightRoomFrame) return 1;

    const roomIdDifference = left.roomDocumentId.localeCompare(right.roomDocumentId);
    if (roomIdDifference !== 0) return roomIdDifference;

    if (left.firstSeenFrame < right.firstSeenFrame) return -1;
    if (left.firstSeenFrame > right.firstSeenFrame) return 1;

    const itemIdDifference = left.inventoryItemId.localeCompare(right.inventoryItemId);
    if (itemIdDifference !== 0) return itemIdDifference;
    return left.originalIndex - right.originalIndex;
  });
}

function evidenceFrames(item) {
  if (Array.isArray(item.evidenceFrames)) {
    return [...item.evidenceFrames];
  }

  const values = finiteFrameValues(item);
  return [...new Set(values)].sort((left, right) => left - right);
}

function isAmbiguous(item) {
  return item.uncertain === true || item.ambiguous === true || item.cubeBand === "high";
}

function itemCube(item, row, stressRuntime) {
  if (stressRuntime && isAmbiguous(item) && stressRuntime.cubeBand === "high") {
    const high = Number(row?.high);
    if (Number.isFinite(high) && high > 0) return high;
  }

  const cube = Number(item.cubicFeet);
  if (Number.isFinite(cube) && cube > 0) return cube;

  const typical = Number(row?.typical);
  return Number.isFinite(typical) && typical > 0 ? typical : null;
}

function categoryProfile(item, row, packingSim) {
  const categoryKey = row?.category ?? item.cubeCategory ?? item.category;
  return packingSim.categoryDefaults?.[categoryKey] || null;
}

function preferredProfile(item, row, packingSim) {
  return row?.packProfile || categoryProfile(item, row, packingSim);
}

function unitQuantityGroups(quantity, packingUnit) {
  const behavior = packingUnit?.behavior || "indivisible";
  if (behavior === "indivisible") return [quantity];
  if (behavior === "countable") return Array.from({ length: quantity }, () => 1);
  if (behavior !== "bulkDivisible") {
    throw new Error(`Unsupported packing unit behavior: ${behavior}`);
  }

  const maxChunkQty = Number(packingUnit.maxChunkQty);
  if (!Number.isInteger(maxChunkQty) || maxChunkQty <= 0) {
    throw new Error("bulkDivisible packing units require a positive maxChunkQty");
  }

  const groups = [];
  let remaining = quantity;
  while (remaining > 0) {
    const chunk = Math.min(maxChunkQty, remaining);
    groups.push(chunk);
    remaining -= chunk;
  }
  return groups;
}

function unitizeEntry(entry, normalizedConfig, nextOrder) {
  const { item } = entry;
  const quantity = Number(item.quantity ?? 1);
  if (!Number.isInteger(quantity) || quantity <= 0) {
    throw new Error(`Inventory item ${entry.inventoryItemId} has an invalid quantity`);
  }

  const rowKey = String(item.cubeRowId ?? item.type ?? "");
  const row = normalizedConfig.rowByKey.get(rowKey) || null;
  const profile = preferredProfile(item, row, normalizedConfig.packingSim);
  const perItemCube = itemCube(item, row, normalizedConfig.stressRuntime);
  const groups = unitQuantityGroups(quantity, row?.packingUnit || item.packingUnit);

  return groups.map((qty) => {
    const cube = perItemCube == null ? null : perItemCube * qty;
    const protectionFactor = Number(profile?.protectionFactor);
    const compressionFactor = Number(profile?.compressionFactor);
    const density = Number(
      normalizedConfig.packingSim.densityClasses?.[profile?.densityClass]?.lbPerCuFt
    );

    return {
      order: nextOrder(),
      item,
      roomDocumentId: entry.roomDocumentId,
      inventoryItemId: entry.inventoryItemId,
      cubeRowId: row?.id ? String(row.id) : rowKey,
      row,
      rowProfile: row?.packProfile || null,
      categoryProfile: categoryProfile(item, row, normalizedConfig.packingSim),
      profile,
      name: String(item.name || rowKey || "Unknown item"),
      qty,
      cube,
      effectiveCube: cube == null || !Number.isFinite(protectionFactor) ||
          !Number.isFinite(compressionFactor)
        ? null
        : cube * protectionFactor * compressionFactor,
      estWeightLb: cube == null || !Number.isFinite(density)
        ? null
        : cube * density,
      evidenceFrames: evidenceFrames(item),
      ambiguous: isAmbiguous(item)
    };
  });
}

function normalizedPackingState(unit, packingSim) {
  if (unit.item.shouldMove === false) return "builtInOrStays";
  const state = String(unit.item.packingState || LOOSE_STATE);
  return packingSim.packingStates?.includes(state) ? state : LOOSE_STATE;
}

function keywordTransportPolicy(unit, packingSim) {
  const normalizedName = unit.name.normalize("NFKC").toLowerCase();
  for (const rule of packingSim.transportKeywordRules || []) {
    if ((rule.keywords || []).some((keyword) =>
      normalizedName.includes(String(keyword).normalize("NFKC").toLowerCase()))) {
      return rule.policy;
    }
  }
  return null;
}

function transportPolicyFor(unit, packingSim) {
  if (unit.rowProfile?.transportPolicy) return unit.rowProfile.transportPolicy;
  if (unit.item.transportPolicy && packingSim.transportPolicies?.[unit.item.transportPolicy]) {
    return unit.item.transportPolicy;
  }
  const keywordPolicy = keywordTransportPolicy(unit, packingSim);
  if (keywordPolicy) return keywordPolicy;
  return unit.item.restrictedCandidate === true ? "carrierRestricted" : null;
}

function addAdjacent(records, record, identityFields, numericFields) {
  const previous = records.at(-1);
  const matches = previous && identityFields.every((field) => previous[field] === record[field]);
  if (!matches) {
    records.push({ ...record });
    return;
  }
  for (const field of numericFields) previous[field] += record[field];
}

function addOpenFirst(context, unit) {
  const previous = context.openFirst.at(-1);
  if (previous?.inventoryItemId === unit.inventoryItemId && previous.name === unit.name) {
    previous.qty += unit.qty;
  } else {
    context.openFirst.push({
      inventoryItemId: unit.inventoryItemId,
      name: unit.name,
      qty: unit.qty
    });
  }
}

function handlingNoteFor(reason) {
  const notes = {
    notBoxable: "Keep this item out of standard boxes and plan to move it separately.",
    handlingOnly: "Keep this item out of standard boxes and plan to move it separately.",
    volume: "This item does not fit the configured box volume; plan to handle it separately.",
    weight: "This item exceeds the configured box weight limit; plan to handle it separately.",
    maxBox: "This item does not fit an allowed box size; plan to handle it separately.",
    incompat: "This item needs separate packing because of its compatibility tags."
  };
  return notes[reason] || notes.notBoxable;
}

function addLeftover(context, unit, reason) {
  addAdjacent(context.leftovers, {
    inventoryItemId: unit.inventoryItemId,
    cubeRowId: unit.cubeRowId,
    name: unit.name,
    qty: unit.qty,
    handlingNote: handlingNoteFor(reason),
    reason
  }, ["inventoryItemId", "cubeRowId", "name", "handlingNote", "reason"], ["qty"]);
}

function addAssumption(context, unit, code, message) {
  addAdjacent(context.assumptions, {
    inventoryItemId: unit.inventoryItemId,
    name: unit.name,
    qty: unit.qty,
    code,
    message
  }, ["inventoryItemId", "name", "code", "message"], ["qty"]);
}

function coverageDebtType(unit, packingSim) {
  const explicit = unit.item.coverageDebtType;
  if (explicit && packingSim.stress?.coverageDebtAllowances?.[explicit]) return explicit;

  const text = `${unit.name} ${unit.cubeRowId}`.normalize("NFKC").toLowerCase();
  if (text.includes("dresser") || text.includes("drawer")) return "closedDresser";
  if (text.includes("cabinet") || text.includes("hutch")) return "closedCabinet";
  if (text.includes("closet")) return "closedCloset";
  if (text.includes("opaque") || text.includes("tote") || text.includes("bin")) return "opaqueBin";
  return "closedContentsUnknown";
}

function addCoverageDebt(context, unit, packingSim) {
  const debtType = coverageDebtType(unit, packingSim);
  const allowance = packingSim.stress?.coverageDebtAllowances?.[debtType] ||
    packingSim.stress?.coverageDebtAllowances?.closedContentsUnknown;
  addAdjacent(context.coverageDebt, {
    inventoryItemId: unit.inventoryItemId,
    name: unit.name,
    qty: unit.qty,
    debtType,
    reason: allowance?.reason || "Closed contents could not be verified.",
    evidenceFrames: unit.evidenceFrames
  }, ["inventoryItemId", "name", "debtType", "reason"], ["qty"]);
}

function addSpecialtyUnit(context, unit, routeName, routeConfig, variant = null) {
  const key = JSON.stringify([
    unit.roomDocumentId,
    routeName,
    routeConfig.containerType,
    variant
  ]);
  let bucket = context.specialtyBuckets.get(key);
  if (!bucket) {
    bucket = {
      routeName,
      containerType: routeConfig.containerType,
      variant,
      routeConfig,
      units: []
    };
    context.specialtyBuckets.set(key, bucket);
  }
  bucket.units.push(unit);
}

function specialtyRoute(context, unit, routeName, packingSim) {
  const routeConfig = packingSim.specialtyRoutes?.[routeName];
  if (!routeConfig) throw new Error(`Unknown specialty route: ${routeName}`);

  if (routeConfig.containerType === "handlingOnly") {
    addLeftover(context, unit, "handlingOnly");
    return;
  }

  let variant = null;
  if (routeName === "mattressBag") {
    variant = routeConfig.bagByCubeRowKey?.[unit.row?.key];
  } else if (routeName === "tvKit") {
    variant = routeConfig.kitByCubeRowKey?.[unit.row?.key];
  } else if (routeName === "pictureCarton") {
    variant = routeConfig.sizeBandByCubeRowKey?.[unit.row?.key] ||
      unit.item.sizeBand || unit.item.sizeEstimate;
  }
  addSpecialtyUnit(context, unit, routeName, routeConfig, variant || null);
}

function stateRoute(context, unit, state, packingSim) {
  const existingRoute = packingSim.specialtyRoutes?.existingContainer;
  switch (state) {
  case "alreadyPackedSealed":
    if (!existingRoute) throw new Error("packing config is missing existingContainer route");
    addSpecialtyUnit(context, unit, "existingContainer", existingRoute, "sealed");
    addAssumption(
      context,
      unit,
      state,
      "This sealed container is already packed; its contents are not boxed again."
    );
    return true;
  case "alreadyPackedOpen":
    if (!existingRoute) throw new Error("packing config is missing existingContainer route");
    addSpecialtyUnit(context, unit, "existingContainer", existingRoute, "open");
    addAssumption(
      context,
      unit,
      state,
      "This open packed container is already on hand; its visible contents are not boxed again."
    );
    return true;
  case "emptyContainer":
    if (!existingRoute) throw new Error("packing config is missing existingContainer route");
    addSpecialtyUnit(context, unit, "existingContainer", existingRoute, "empty");
    addAssumption(
      context,
      unit,
      state,
      "This empty container is already on hand, so no additional box is included for it."
    );
    return true;
  case "visibleContentsStayInside":
    addAssumption(
      context,
      unit,
      state,
      "These visible contents stay in their current container and are not boxed again."
    );
    return true;
  case "closedContentsUnknown":
    addCoverageDebt(context, unit, packingSim);
    addLeftover(context, unit, "notBoxable");
    addAssumption(
      context,
      unit,
      state,
      "The closed contents could not be verified, so no contents were added to the plan."
    );
    return true;
  case "builtInOrStays":
    addAssumption(
      context,
      unit,
      state,
      "This item is marked as built in or staying, so it is not included."
    );
    return true;
  default:
    return false;
  }
}

function boxSizeIndex(packingSim, size) {
  return packingSim.boxSizeOrder.indexOf(size);
}

function unitFillEfficiency(unit, packingSim, stressRuntime) {
  const regular = Number(packingSim.lanes[unit.profile.lane]?.fillEfficiency);
  const uncertainFragile = stressRuntime && unit.ambiguous &&
    (unit.item.isFragile === true || unit.profile.lane === "fragileClean");
  return uncertainFragile
    ? Number(stressRuntime.uncertainFragileFillEfficiency)
    : regular;
}

function boxTags(box) {
  const itemTags = new Set();
  const incompatibleTags = new Set();
  for (const unit of box.units) {
    for (const tag of unit.profile.itemTags || []) itemTags.add(tag);
    for (const tag of unit.profile.incompatibleTags || []) incompatibleTags.add(tag);
  }
  return { itemTags, incompatibleTags };
}

function isIncompatible(box, unit) {
  const existing = boxTags(box);
  return (unit.profile.itemTags || []).some((tag) => existing.incompatibleTags.has(tag)) ||
    (unit.profile.incompatibleTags || []).some((tag) => existing.itemTags.has(tag));
}

function fitFailure(box, unit, packingSim, stressRuntime) {
  const boxConfig = packingSim.boxes[box.size];
  const fillEfficiency = Math.min(
    box.fillEfficiency,
    unitFillEfficiency(unit, packingSim, stressRuntime)
  );
  if (box.effectiveCube + unit.effectiveCube > boxConfig.usableCube * fillEfficiency) {
    return "volume";
  }
  if (box.estWeightLb + unit.estWeightLb > boxConfig.maxGrossWeightLb) {
    return "weight";
  }

  const sizeIndex = boxSizeIndex(packingSim, box.size);
  const minIndex = boxSizeIndex(packingSim, unit.profile.minBox);
  const maxIndex = boxSizeIndex(packingSim, unit.profile.maxBox);
  if (sizeIndex < minIndex || sizeIndex > maxIndex ||
      !boxConfig.permittedLanes.includes(unit.profile.lane)) {
    return "maxBox";
  }
  if (isIncompatible(box, unit)) return "incompat";
  return null;
}

function chooseBox(unit, packingSim, stressRuntime) {
  const minIndex = boxSizeIndex(packingSim, unit.profile.minBox);
  const maxIndex = boxSizeIndex(packingSim, unit.profile.maxBox);
  if (minIndex < 0 || maxIndex < minIndex) return { size: null, reason: "maxBox" };

  const fillEfficiency = unitFillEfficiency(unit, packingSim, stressRuntime);
  let sawPermittedBox = false;
  let sawVolumeFit = false;
  let sawWeightFit = false;
  for (let index = minIndex; index <= maxIndex; index += 1) {
    const size = packingSim.boxSizeOrder[index];
    const box = packingSim.boxes[size];
    if (!box || !box.permittedLanes.includes(unit.profile.lane)) continue;
    sawPermittedBox = true;
    if (unit.effectiveCube > box.usableCube * fillEfficiency) continue;
    sawVolumeFit = true;
    if (unit.estWeightLb > box.maxGrossWeightLb) continue;
    sawWeightFit = true;
    return { size, fillEfficiency, reason: null };
  }

  if (!sawPermittedBox) return { size: null, reason: "maxBox" };
  if (!sawVolumeFit) return { size: null, reason: "volume" };
  if (!sawWeightFit) return { size: null, reason: "weight" };
  return { size: null, reason: "maxBox" };
}

function layerRank(unit) {
  if (unit.profile.densityClass === "heavy" || unit.item.rigid === true ||
      (unit.profile.itemTags || []).includes("heavy-on-fragile")) return 0;
  if (unit.item.isFragile === true || unit.profile.densityClass === "light" ||
      unit.profile.lane === "fragileClean") return 2;
  return 1;
}

function layerSortedUnits(units) {
  return [...units].sort((left, right) => {
    const rankDifference = layerRank(left) - layerRank(right);
    return rankDifference !== 0 ? rankDifference : left.order - right.order;
  });
}

function aggregateUnits(units) {
  const aggregated = [];
  for (const unit of units) {
    addAdjacent(aggregated, {
      inventoryItemId: unit.inventoryItemId,
      cubeRowId: unit.cubeRowId,
      name: unit.name,
      qtyPacked: unit.qty,
      effectiveCube: unit.effectiveCube,
      estWeightLb: unit.estWeightLb,
      evidenceFrames: unit.evidenceFrames
    }, ["inventoryItemId", "cubeRowId", "name"], ["qtyPacked", "effectiveCube", "estWeightLb"]);
  }
  return aggregated;
}

function displayItems(units) {
  const items = [];
  for (const unit of units) {
    addAdjacent(items, {
      name: unit.name,
      qty: unit.qty
    }, ["name"], ["qty"]);
  }
  return items;
}

function addUnitToLane(context, unit, packingSim, stressRuntime) {
  if (!unit.profile?.lane || unit.effectiveCube == null || unit.estWeightLb == null) {
    addLeftover(context, unit, "maxBox");
    return;
  }

  const lane = unit.profile.lane;
  const current = context.openBoxes.get(lane);
  if (current) {
    const failure = fitFailure(current, unit, packingSim, stressRuntime);
    if (!failure) {
      current.units.push(unit);
      current.effectiveCube += unit.effectiveCube;
      current.estWeightLb += unit.estWeightLb;
      current.fillEfficiency = Math.min(
        current.fillEfficiency,
        unitFillEfficiency(unit, packingSim, stressRuntime)
      );
      return;
    }
    context.closures.push({ boxRef: current.boxRef, closedBy: failure });
    context.openBoxes.delete(lane);
  }

  const selection = chooseBox(unit, packingSim, stressRuntime);
  if (!selection.size) {
    addLeftover(context, unit, selection.reason);
    return;
  }

  const n = context.boxes.length + 1;
  const box = {
    boxRef: `box-${n}`,
    n,
    size: selection.size,
    lane,
    fillEfficiency: selection.fillEfficiency,
    effectiveCube: unit.effectiveCube,
    estWeightLb: unit.estWeightLb,
    units: [unit]
  };
  context.boxes.push(box);
  context.openBoxes.set(lane, box);
}

function routeUnit(context, unit, normalizedConfig) {
  const { packingSim, stressRuntime } = normalizedConfig;
  const transportPolicy = transportPolicyFor(unit, packingSim);
  if (transportPolicy) {
    const policyConfig = packingSim.transportPolicies?.[transportPolicy];
    if (!policyConfig) throw new Error(`Unknown transport policy: ${transportPolicy}`);
    addAdjacent(context.restrictedItems, {
      inventoryItemId: unit.inventoryItemId,
      cubeRowId: unit.cubeRowId,
      name: unit.name,
      qty: unit.qty,
      policy: transportPolicy,
      guidance: policyConfig.userFacingCopy,
      evidenceFrames: unit.evidenceFrames
    }, ["inventoryItemId", "cubeRowId", "name", "policy", "guidance"], ["qty"]);
    if (transportPolicy === "carrySeparately" ||
        unit.rowProfile?.availabilityFlag === "carrySeparately" ||
        unit.rowProfile?.availabilityFlag === "openFirst") {
      addOpenFirst(context, unit);
    }
    return;
  }

  const state = normalizedPackingState(unit, packingSim);
  if (state !== LOOSE_STATE && stateRoute(context, unit, state, packingSim)) return;

  if (unit.rowProfile?.specialtyRoute) {
    specialtyRoute(context, unit, unit.rowProfile.specialtyRoute, packingSim);
    if (unit.rowProfile.availabilityFlag === "openFirst") addOpenFirst(context, unit);
    return;
  }

  if (unit.rowProfile?.notBoxable === true) {
    addLeftover(context, unit, "notBoxable");
    return;
  }

  const profile = unit.rowProfile || unit.categoryProfile;
  unit.profile = profile;
  if (!profile) {
    addLeftover(context, unit, "notBoxable");
    return;
  }
  if (!unit.rowProfile && profile.specialtyRoute) {
    specialtyRoute(context, unit, profile.specialtyRoute, packingSim);
    return;
  }
  if (profile.notBoxable === true && profile.boxabilityPrecedence !== "boxable") {
    addLeftover(context, unit, "notBoxable");
    return;
  }

  if (profile.availabilityFlag === "openFirst") addOpenFirst(context, unit);
  addUnitToLane(context, unit, packingSim, stressRuntime);
}

function specialtyCapacity(bucket, packingSim) {
  if (bucket.routeName === "wardrobe") {
    return Number(bucket.routeConfig.itemsPerWardrobe);
  }
  if (bucket.routeName === "pictureCarton") {
    return Number(bucket.routeConfig.itemsPerCartonBySizeBand?.[bucket.variant]);
  }
  if (bucket.routeName === "dishPack") {
    return Number(bucket.routeConfig.bundlesPerPack);
  }
  if (bucket.routeName === "mattressBag" || bucket.routeName === "tvKit") return 1;
  if (bucket.containerType === "existingContainer") return 1;
  return null;
}

function specialtyContainersPerItem(bucket, packingSim) {
  if (bucket.routeName === "mattressBag") {
    return Number(packingSim.specialtyEstimator?.mattressBagsPerMattress);
  }
  if (bucket.routeName === "tvKit") {
    return Number(packingSim.specialtyEstimator?.tvKitsPerTelevision);
  }
  return 1;
}

function splitSpecialtyUnits(units, capacity) {
  if (!Number.isFinite(capacity) || capacity <= 0) {
    throw new Error("Specialty route has an invalid configured capacity");
  }

  const containers = [];
  let current = [];
  let remainingCapacity = capacity;
  for (const unit of units) {
    let remainingQty = unit.qty;
    while (remainingQty > 0) {
      const packedQty = Math.min(remainingQty, remainingCapacity);
      const fraction = packedQty / unit.qty;
      current.push({
        ...unit,
        qty: packedQty,
        cube: unit.cube == null ? null : unit.cube * fraction,
        effectiveCube: unit.effectiveCube == null ? null : unit.effectiveCube * fraction,
        estWeightLb: unit.estWeightLb == null ? null : unit.estWeightLb * fraction
      });
      remainingQty -= packedQty;
      remainingCapacity -= packedQty;
      if (remainingCapacity === 0) {
        containers.push(current);
        current = [];
        remainingCapacity = capacity;
      }
    }
  }
  if (current.length > 0) containers.push(current);
  return containers;
}

function materializeSpecialtyContainers(context, packingSim) {
  const containers = [];
  for (const bucket of context.specialtyBuckets.values()) {
    const capacity = specialtyCapacity(bucket, packingSim);
    const groups = splitSpecialtyUnits(bucket.units, capacity);
    const containersPerItem = specialtyContainersPerItem(bucket, packingSim);
    if (!Number.isInteger(containersPerItem) || containersPerItem <= 0) {
      throw new Error("Specialty route has an invalid configured container count");
    }
    for (const units of groups) {
      for (let copyIndex = 0; copyIndex < containersPerItem; copyIndex += 1) {
        const index = containers.length + 1;
        const containerRef = `specialty-${index}`;
        const aggregated = aggregateUnits(units);
        containers.push({
          containerRef,
          containerType: bucket.containerType,
          route: bucket.routeName,
          variant: bucket.variant,
          items: displayItems(units)
        });
        context.trace[containerRef] = aggregated;
      }
    }
  }
  return containers;
}

function formatBoxes(context) {
  return context.boxes.map((box) => {
    const layeredUnits = layerSortedUnits(box.units);
    const aggregated = aggregateUnits(layeredUnits);
    const displayed = displayItems(layeredUnits);
    context.trace[box.boxRef] = aggregated;
    return {
      boxRef: box.boxRef,
      n: box.n,
      size: box.size,
      lane: box.lane,
      items: displayed,
      layers: displayed.map((item) => item.name),
      effectiveCube: box.effectiveCube,
      estWeightLb: box.estWeightLb
    };
  });
}

function totalsBySize(boxes, packingSim) {
  return Object.fromEntries(packingSim.boxSizeOrder.map((size) => [
    size,
    boxes.filter((box) => box.size === size).length
  ]));
}

/**
 * Pure, deterministic constrained packing simulation.
 *
 * @param {Array<object>} items persisted inventory item records
 * @param {object} config cubeSheet + packingSim config, or packingSim with rows
 * @returns {{packResult: object, trace: object, closures: Array<object>}}
 */
function simulatePack(items, config) {
  if (!Array.isArray(items)) throw new TypeError("items must be an array");
  const normalizedConfig = normalizeConfig(config);
  const context = {
    boxes: [],
    openBoxes: new Map(),
    specialtyBuckets: new Map(),
    leftovers: [],
    restrictedItems: [],
    coverageDebt: [],
    assumptions: [],
    openFirst: [],
    closures: [],
    trace: {}
  };

  let unitOrder = 0;
  const nextOrder = () => unitOrder++;
  const units = orderedInventoryItems(items).flatMap((entry) =>
    unitizeEntry(entry, normalizedConfig, nextOrder));
  for (const unit of units) routeUnit(context, unit, normalizedConfig);

  const boxes = formatBoxes(context);
  const specialtyContainers = materializeSpecialtyContainers(
    context,
    normalizedConfig.packingSim
  );
  const packResult = {
    boxes,
    specialtyContainers,
    leftovers: context.leftovers,
    restrictedItems: context.restrictedItems,
    coverageDebt: context.coverageDebt,
    assumptions: context.assumptions,
    openFirst: context.openFirst,
    totalsBySize: totalsBySize(boxes, normalizedConfig.packingSim)
  };

  return {
    packResult,
    trace: context.trace,
    closures: context.closures
  };
}

function addReserveLine(lines, reserveByContainerType, containerType, count, reason) {
  if (!(count > 0)) return;
  reserveByContainerType[containerType] =
    (reserveByContainerType[containerType] || 0) + count;
  lines.push({ containerType, count, reason });
}

/**
 * Runs the literal plan and the deterministic stress transform as two separate
 * simulator calls. Specialty containers are deliberately absent from the
 * planned-versus-stress box comparison.
 */
function simulatePackWithStress(items, config) {
  const normalizedConfig = normalizeConfig(config);
  const planned = simulatePack(items, config);
  const stress = simulatePack(items, stressConfigTransform(config));
  const plannedBySize = planned.packResult.totalsBySize;
  const stressBySize = stress.packResult.totalsBySize;
  const reserveByContainerType = {};
  const reserveLines = [];

  for (const size of normalizedConfig.packingSim.boxSizeOrder) {
    const count = Math.max(0, stressBySize[size] - plannedBySize[size]);
    addReserveLine(
      reserveLines,
      reserveByContainerType,
      size,
      count,
      "Ambiguous item ranges and fragile packing uncertainty may need this reserve."
    );
  }

  const allowances = normalizedConfig.packingSim.stress.coverageDebtAllowances;
  for (const debt of planned.packResult.coverageDebt) {
    const allowance = allowances[debt.debtType] || allowances.closedContentsUnknown;
    if (!allowance) continue;
    for (const [containerType, configuredCount] of
      Object.entries(allowance.reserveByContainerType || {})) {
      addReserveLine(
        reserveLines,
        reserveByContainerType,
        containerType,
        configuredCount * debt.qty,
        allowance.reason
      );
    }
  }

  const reserveBySize = Object.fromEntries(
    normalizedConfig.packingSim.boxSizeOrder.map((size) => [
      size,
      reserveByContainerType[size] || 0
    ])
  );

  return {
    planned,
    stress,
    comparison: {
      plannedBySize,
      stressBySize,
      reserveBySize,
      reserveByContainerType,
      reserveLines
    }
  };
}

module.exports = {
  stressConfigTransform,
  simulatePack,
  simulatePackWithStress
};
