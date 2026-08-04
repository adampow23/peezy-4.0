/**
 * processInventory - Cloud Function
 * Downloads room frames from Storage, sends to Claude vision API,
 * returns structured inventory JSON to Firestore.
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const Anthropic = require('@anthropic-ai/sdk');
const { getAIConfig } = require('./aiConfig');

const INVENTORY_CONFIG_PATHS = {
  anchors: 'appConfig/anchors',
  cubeSheet: 'appConfig/cubeSheet'
};
const VALID_CATEGORIES = ['furniture', 'electronics', 'boxes', 'appliance', 'decor', 'other'];
const VALID_SIZES = ['small', 'medium', 'large', 'oversized'];
const VALID_TIERS = ['furniture', 'boxable'];

// Lazy-init Anthropic client (same pattern as peezyBrain.js)
let anthropic = null;

function getAnthropicClient() {
  if (!anthropic) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      throw new Error('ANTHROPIC_API_KEY environment variable is required');
    }
    anthropic = new Anthropic({ apiKey });
  }
  return anthropic;
}

function logTokenUsage(response) {
  console.log(JSON.stringify({
    event: 'anthropic_usage',
    function: 'processInventory',
    inputTokens: response?.usage?.input_tokens ?? null,
    outputTokens: response?.usage?.output_tokens ?? null
  }));
}

function buildCubeRowLookup(rows) {
  if (!Array.isArray(rows) || rows.length === 0) {
    throw new Error('Cube sheet config has no rows');
  }

  const lookup = new Map();
  for (const row of rows) {
    if (!row || typeof row.key !== 'string' || typeof row.category !== 'string') {
      throw new Error('Cube sheet config contains an invalid row');
    }

    const low = Number(row.low);
    const typical = Number(row.typical);
    const high = Number(row.high);
    const numericValueCount = [low, typical, high].filter(Number.isFinite).length;

    // The source sheet contains one cross-reference row ("Piano (any)")
    // rather than a numeric range. It remains in the injected sheet as
    // guidance, while only complete numeric rows are selectable item types.
    if (numericValueCount === 0) {
      continue;
    }
    if (numericValueCount !== 3 || low > typical || typical > high) {
      throw new Error(`Cube sheet config has an invalid range for ${row.key}`);
    }

    const numericRow = { ...row, low, typical, high };
    const existing = lookup.get(row.key);
    if (
      existing &&
      (existing.low !== low || existing.typical !== typical || existing.high !== high)
    ) {
      throw new Error(`Cube sheet config has conflicting ranges for ${row.key}`);
    }
    lookup.set(row.key, numericRow);
  }

  if (lookup.size === 0) {
    throw new Error('Cube sheet config has no numeric rows');
  }
  return lookup;
}

async function readInventorySizingConfig(db) {
  const [anchorsSnapshot, cubeSheetSnapshot] = await Promise.all([
    db.doc(INVENTORY_CONFIG_PATHS.anchors).get(),
    db.doc(INVENTORY_CONFIG_PATHS.cubeSheet).get()
  ]);

  if (!anchorsSnapshot.exists || !cubeSheetSnapshot.exists) {
    throw new Error('Inventory config missing — run node seedCubeSheet.js');
  }

  const anchorRows = anchorsSnapshot.data()?.anchors;
  const cubeSheetConfig = cubeSheetSnapshot.data() || {};
  if (!Array.isArray(anchorRows) || anchorRows.length === 0) {
    throw new Error('Anchor config has no rows');
  }
  for (const anchor of anchorRows) {
    if (
      !anchor ||
      typeof anchor.name !== 'string' ||
      typeof anchor.standardDimension !== 'string'
    ) {
      throw new Error('Anchor config contains an invalid row');
    }
  }

  const unknownSizeTypical = {};
  for (const size of VALID_SIZES) {
    const value = Number(cubeSheetConfig.unknownSizeTypical?.[size]);
    if (!Number.isFinite(value) || value <= 0) {
      throw new Error(`Cube sheet config has no unknown fallback for ${size}`);
    }
    unknownSizeTypical[size] = value;
  }

  return {
    anchorRows,
    cubeRows: cubeSheetConfig.rows,
    cubeRowLookup: buildCubeRowLookup(cubeSheetConfig.rows),
    unknownSizeTypical
  };
}

function normalizedInventoryName(value) {
  return String(value ?? '')
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();
}

function mergeExactInventoryItems(items) {
  if (!Array.isArray(items)) {
    throw new TypeError('items must be an array');
  }

  const mergedItems = [];
  const indexByIdentity = new Map();
  for (const item of items) {
    const identity = JSON.stringify([
      normalizedInventoryName(item.name),
      item.category
    ]);
    const existingIndex = indexByIdentity.get(identity);
    if (existingIndex === undefined) {
      indexByIdentity.set(identity, mergedItems.length);
      mergedItems.push({ ...item });
      continue;
    }

    const firstItem = mergedItems[existingIndex];
    mergedItems[existingIndex] = {
      ...firstItem,
      quantity: firstItem.quantity + item.quantity
    };
  }
  return mergedItems;
}

exports.processInventory = onCall(
  {
    timeoutSeconds: 120,
    memory: '1GiB',
    cors: true,
    enforceAppCheck: false
  },
  async (request) => {
    console.log('processInventory: handler entered');

    // 1. Validate auth
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be authenticated');
    }
    console.log('processInventory: auth valid, uid =', request.auth.uid);

    // 2. Extract parameters
    const { userId, sessionId, roomName, frameCount } = request.data;
    console.log('processInventory: params', { userId, sessionId, roomName, frameCount });
    if (!userId || !sessionId || !roomName) {
      throw new HttpsError('invalid-argument', 'Missing required fields');
    }

    // 3. Verify requesting user matches userId (security)
    if (request.auth.uid !== userId) {
      console.error('processInventory: uid mismatch', request.auth.uid, '!==', userId);
      throw new HttpsError('permission-denied', 'Cannot process another user inventory');
    }

    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const sessionRef = db.collection('users').doc(userId)
                        .collection('inventorySessions').doc(sessionId);

    try {
      // 4. Download frames from Storage
      const framePrefix = `inventory/${userId}/${sessionId}/`;
      const [listedFiles] = await bucket.getFiles({ prefix: framePrefix });
      const frameFiles = listedFiles
        .filter((file) => file.name !== framePrefix && !file.name.endsWith('/'))
        .sort((left, right) => left.name.localeCompare(right.name));

      if (frameCount !== frameFiles.length) {
        console.warn('processInventory: frame count mismatch', {
          reportedFrameCount: frameCount ?? null,
          listedFrameCount: frameFiles.length,
          sessionId
        });
      }
      if (frameFiles.length === 0) {
        throw new Error('No uploaded frames found');
      }

      console.log('processInventory: downloading listed frames', frameFiles.map((file) => file.name));
      const frames = await Promise.all(frameFiles.map(async (file, position) => {
        const [buffer] = await file.download();
        const indexMatch = file.name.match(/frame_(\d+)\.jpg$/);
        return {
          index: indexMatch ? Number(indexMatch[1]) : position,
          name: file.name,
          base64: buffer.toString('base64')
        };
      }));
      console.log('processInventory: downloaded', frames.length, 'frames, sizes:', frames.map(f => f.base64.length));

      // 5. Build Claude API request with multi-image input
      const imageContent = frames.map((frame) => ([
        {
          type: 'text',
          text: `[Frame ${frame.index}]`
        },
        {
          type: 'image',
          source: {
            type: 'base64',
            media_type: 'image/jpeg',
            data: frame.base64
          }
        }
      ])).flat();

      const {
        anchorRows,
        cubeRows,
        cubeRowLookup,
        unknownSizeTypical
      } = await readInventorySizingConfig(db);

      const systemPrompt = `You analyze room walkthrough frames to create a moving inventory.
These ${frames.length} labeled frames are one continuous walkthrough of one room named ${JSON.stringify(roomName)}, not separate rooms or separate inventories.

PASS 1 — FIND SIZE ANCHORS
Before inventorying, identify the visible reference objects from INJECTED_ANCHORS and use their known dimensions to judge relative item size. Do not return a separate anchor payload. If a movable anchor object is present, include that physical item exactly once in Pass 2.

INJECTED_ANCHORS:
${JSON.stringify(anchorRows)}

PASS 2 — INVENTORY THE ROOM
1. Identify every physical item exactly once across all frames. Track physical identity across adjacent and non-adjacent frames so another angle of the same item never creates another entry. Record every labeled frame where each item appears in frameIndices. Identical small boxable objects may share one entry with quantity equal to the physical count.
2. Set type to an exact key from INJECTED_CUBE_SHEET_ROWS that has numeric low, typical, and high values. The nonnumeric "Piano (any)" row is cross-reference guidance; choose the matching specific piano key. If no numeric row fits, set type to "unknown" and give the item a concise free-text name.
3. Set sizeEstimate to small, medium, large, or oversized. Set cubicFeet per unit within the selected row's inclusive [low, high] range, placing it inside that range by comparing the item with the Pass 1 anchors. Fixed-cube box rows require their exact cube.
4. Classify tier as "furniture" when movers handle the item individually, including furniture, large appliances, TVs, exercise equipment, musical instruments, and large mirrors or art. Classify tier as "boxable" for items packed into boxes. Group only genuinely interchangeable small boxable objects.
5. Set category to furniture, electronics, boxes, appliance, decor, or other. Also return quantity, isFragile, isHighValue, and confidence from 0.0 to 1.0 for every entry.
6. For furniture entries, set frameIndex to the labeled frame where the item is clearest and boundingBox to normalized 0.0–1.0 coordinates in that frame. For boxable entries, set frameIndex and boundingBox to null.
7. Include uncertain items with lower confidence. Do not omit an item merely because identification is uncertain.
8. Ignore walls, floors, ceilings, doors, windows, and built-in fixtures such as cabinets, countertops, and closet shelving.

INJECTED_CUBE_SHEET_ROWS:
${JSON.stringify(cubeRows)}

Return only a valid JSON array with no markdown, explanation, preamble, or backticks. Each object must have exactly these fields:
{
  "name": "string",
  "type": "exact injected cube-sheet key|unknown",
  "category": "furniture|electronics|boxes|appliance|decor|other",
  "tier": "furniture|boxable",
  "quantity": 1,
  "sizeEstimate": "small|medium|large|oversized",
  "cubicFeet": 0.0,
  "isFragile": false,
  "isHighValue": false,
  "confidence": 0.0,
  "frameIndices": [0],
  "frameIndex": null,
  "boundingBox": null
}`;

      const client = getAnthropicClient();
      const inventoryModel = await getAIConfig('inventoryModel');
      const response = await client.messages.create({
        model: inventoryModel,
        max_tokens: 4096,
        system: systemPrompt,
        messages: [{
          role: 'user',
          content: [
            ...imageContent,
            {
              type: 'text',
              text: 'Create the inventory for the labeled walkthrough frames.'
            }
          ]
        }]
      });
      logTokenUsage(response);

      // 6. Parse response — extract JSON from text content
      const textContent = response.content.find(c => c.type === 'text');
      if (!textContent) {
        throw new Error('No text response from Claude');
      }

      let rawItems;
      try {
        // Strip any accidental markdown fencing
        let jsonStr = textContent.text.trim();
        if (jsonStr.startsWith('```')) {
          jsonStr = jsonStr.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '');
        }
        rawItems = JSON.parse(jsonStr);
      } catch (parseErr) {
        console.error('Failed to parse Claude response:', textContent.text);
        throw new Error('Claude returned invalid JSON');
      }

      if (!Array.isArray(rawItems)) {
        throw new Error('Claude response is not an array');
      }

      // 7. Validate and normalize each item
      const normalizedItems = rawItems.map((item, idx) => {
        // Normalize bounding box if present
        let boundingBox = null;
        if (item.boundingBox && typeof item.boundingBox === 'object') {
          const bb = item.boundingBox;
          boundingBox = {
            x: Math.min(1, Math.max(0, Number(bb.x) || 0)),
            y: Math.min(1, Math.max(0, Number(bb.y) || 0)),
            width: Math.min(1, Math.max(0, Number(bb.width) || 0)),
            height: Math.min(1, Math.max(0, Number(bb.height) || 0))
          };
          // Discard degenerate bounding boxes
          if (boundingBox.width < 0.01 || boundingBox.height < 0.01) {
            boundingBox = null;
          }
        }

        // Normalize frame index
        let frameIndex = null;
        if (item.frameIndex != null && !isNaN(Number(item.frameIndex))) {
          const fi = Math.round(Number(item.frameIndex));
          if (frames.some((frame) => frame.index === fi)) {
            frameIndex = fi;
          }
        }

        const frameIndices = Array.isArray(item.frameIndices)
          ? [...new Set(item.frameIndices
            .map((value) => Math.round(Number(value)))
            .filter((value) => frames.some((frame) => frame.index === value)))]
            .sort((left, right) => left - right)
          : [];
        if (frameIndex !== null && !frameIndices.includes(frameIndex)) {
          frameIndices.push(frameIndex);
          frameIndices.sort((left, right) => left - right);
        }

        const requestedType = String(item.type || '').trim();
        const cubeRow = cubeRowLookup.get(requestedType);
        const type = cubeRow ? requestedType : 'unknown';
        const sizeEstimate = VALID_SIZES.includes(item.sizeEstimate)
          ? item.sizeEstimate
          : 'medium';

        let cubicFeet;
        let adjusted = false;
        if (cubeRow) {
          const reportedCubicFeet = Number(item.cubicFeet);
          cubicFeet = Number.isFinite(reportedCubicFeet)
            ? Math.min(cubeRow.high, Math.max(cubeRow.low, reportedCubicFeet))
            : cubeRow.typical;
          adjusted = !Number.isFinite(reportedCubicFeet) || cubicFeet !== reportedCubicFeet;

          if (adjusted) {
            console.warn(JSON.stringify({
              event: 'inventory_cube_adjusted',
              function: 'processInventory',
              sessionId,
              itemIndex: idx,
              type,
              reportedCubicFeet: Number.isFinite(reportedCubicFeet)
                ? reportedCubicFeet
                : null,
              cubicFeet,
              low: cubeRow.low,
              high: cubeRow.high
            }));
          }
        } else {
          cubicFeet = unknownSizeTypical[sizeEstimate];
        }

        return {
          id: `${sessionId}-item-${idx}`,
          name: String(item.name || 'Unknown Item'),
          type,
          category: VALID_CATEGORIES.includes(item.category) ? item.category : 'other',
          tier: VALID_TIERS.includes(item.tier) ? item.tier : 'boxable',
          quantity: Math.max(1, Math.round(Number(item.quantity) || 1)),
          sizeEstimate,
          cubicFeet,
          isFragile: Boolean(item.isFragile),
          isHighValue: Boolean(item.isHighValue),
          confidence: Math.min(1, Math.max(0, Number(item.confidence) || 0.5)),
          uncertain: !cubeRow,
          adjusted,
          frameIndices,
          frameIndex,
          boundingBox,
          roomName,
          shouldMove: true,
          notes: ''
        };
      });
      const items = mergeExactInventoryItems(normalizedItems);
      items.sort((left, right) => Number(right.uncertain) - Number(left.uncertain));

      // 8. Update Firestore session document
      await sessionRef.update({
        status: 'complete',
        items: items,
        completedAt: admin.firestore.FieldValue.serverTimestamp()
      });

      console.log(`processInventory: ${items.length} items found for session ${sessionId}`);

      return { success: true, itemCount: items.length };

    } catch (error) {
      console.error('processInventory error:', error);

      // Update session with error status
      await sessionRef.update({
        status: 'error',
        errorMessage: error.message || 'Unknown processing error'
      }).catch(e => console.error('Failed to update error status:', e));

      throw new HttpsError('internal', error.message || 'Processing failed');
    }
  }
);

exports.mergeExactInventoryItems = mergeExactInventoryItems;
