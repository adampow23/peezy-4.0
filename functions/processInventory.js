/**
 * processInventory - Cloud Function
 * Downloads room frames from Storage, sends to Claude vision API,
 * returns structured inventory JSON to Firestore.
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const Anthropic = require('@anthropic-ai/sdk');

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
    if (!userId || !sessionId || !roomName || frameCount == null) {
      throw new HttpsError('invalid-argument', 'Missing required fields');
    }
    if (frameCount < 1) {
      throw new HttpsError('invalid-argument', 'frameCount must be at least 1');
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
      console.log('processInventory: downloading', frameCount, 'frames');
      const framePromises = [];
      for (let i = 0; i < frameCount; i++) {
        const filePath = `inventory/${userId}/${sessionId}/frame_${i}.jpg`;
        framePromises.push(
          bucket.file(filePath).download().then(([buffer]) => ({
            index: i,
            base64: buffer.toString('base64')
          }))
        );
      }
      const frames = await Promise.all(framePromises);
      frames.sort((a, b) => a.index - b.index);
      console.log('processInventory: downloaded', frames.length, 'frames, sizes:', frames.map(f => f.base64.length));

      // 5. Build Claude API request with multi-image input
      const imageContent = frames.map((frame, idx) => ([
        {
          type: 'text',
          text: `[Frame ${idx}]`
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

      const prompt = `You are analyzing photos of a room in someone's home to create a moving inventory.
These ${frameCount} images show the same room (${roomName}) from different angles during a slow pan.
Each image is labeled [Frame 0], [Frame 1], etc.

INSTRUCTIONS:

1. Identify EVERY visible item in the room — furniture, appliances, electronics, decor, books, kitchenware, clothing, boxes, and all smaller items.

2. Classify each item into one of two tiers:
   - "furniture": Items movers handle individually. Furniture, large appliances, TVs, exercise equipment, musical instruments, large mirrors/art — anything too big for a standard moving box.
   - "boxable": Items that get packed into boxes. Books, kitchen items, small decor, toiletries, clothing, small electronics, office supplies, etc. Group similar small items together (e.g. "Books (approx 50)" not 50 separate book entries, "Kitchen plates and bowls" not individual plates).

3. Do NOT double-count items visible from multiple angles — deduplicate carefully.

4. For EVERY item, estimate its cubic footage per unit. Use these reference points:
   - Single book: 0.08 cu ft
   - Coffee maker: 0.5 cu ft
   - Kitchen pots/pans set: 2.0 cu ft
   - Set of dishes/plates: 1.5 cu ft
   - Microwave: 3.0 cu ft
   - Nightstand: 6.0 cu ft
   - Dresser: 20.0 cu ft
   - Sofa (3-seat): 45.0 cu ft
   - King bed frame + mattress: 65.0 cu ft
   Use your judgment for items not listed.

5. For "furniture" tier items ONLY: provide the frame index (0-based) where the item is most clearly visible, and a bounding box as normalized coordinates (0.0 to 1.0) marking where the item appears in that frame. Format: {"x": left, "y": top, "width": w, "height": h}.

6. For "boxable" tier items: frameIndex and boundingBox should be null.

7. When uncertain about what an item is, INCLUDE it with a lower confidence score. The user will review.

8. Ignore: walls, floors, ceilings, doors, windows, built-in fixtures (cabinets, countertops, closet shelving).

Return ONLY a valid JSON array. No markdown, no explanation, no preamble, no backticks.

Each object must have exactly these fields:
{
  "name": "string",
  "category": "furniture|electronics|boxes|appliance|decor|other",
  "tier": "furniture|boxable",
  "quantity": 1,
  "sizeEstimate": "small|medium|large|oversized",
  "cubicFeet": 0.0,
  "isFragile": false,
  "isHighValue": false,
  "confidence": 0.0-1.0,
  "frameIndex": null or 0-based integer,
  "boundingBox": null or {"x":0.0,"y":0.0,"width":0.0,"height":0.0}
}`;

      const client = getAnthropicClient();
      const response = await client.messages.create({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 4096,
        messages: [{
          role: 'user',
          content: [
            ...imageContent,
            { type: 'text', text: prompt }
          ]
        }]
      });

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
      const validCategories = ['furniture', 'electronics', 'boxes', 'appliance', 'decor', 'other'];
      const validSizes = ['small', 'medium', 'large', 'oversized'];
      const validTiers = ['furniture', 'boxable'];

      const items = rawItems.map((item, idx) => {
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
          if (fi >= 0 && fi < frameCount) {
            frameIndex = fi;
          }
        }

        return {
          id: `${sessionId}-item-${idx}`,
          name: String(item.name || 'Unknown Item'),
          category: validCategories.includes(item.category) ? item.category : 'other',
          tier: validTiers.includes(item.tier) ? item.tier : 'boxable',
          quantity: Math.max(1, Math.round(Number(item.quantity) || 1)),
          sizeEstimate: validSizes.includes(item.sizeEstimate) ? item.sizeEstimate : 'medium',
          cubicFeet: Math.max(0, Number(item.cubicFeet) || 0),
          isFragile: Boolean(item.isFragile),
          isHighValue: Boolean(item.isHighValue),
          confidence: Math.min(1, Math.max(0, Number(item.confidence) || 0.5)),
          frameIndex: frameIndex,
          boundingBox: boundingBox,
          roomName: roomName,
          shouldMove: true,
          notes: ''
        };
      });

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