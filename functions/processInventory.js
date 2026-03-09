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
      const imageContent = frames.map(frame => ({
        type: 'image',
        source: {
          type: 'base64',
          media_type: 'image/jpeg',
          data: frame.base64
        }
      }));

      const prompt = `You are analyzing photos of a room in someone's home to create a moving inventory.
These ${frameCount} images show the same room (${roomName}) from different angles during a slow pan.

INSTRUCTIONS:
1. Identify every distinct piece of furniture, appliance, and significant item visible.
2. Do NOT double-count items visible from multiple angles — deduplicate carefully.
3. For each item, estimate: category, quantity, size, whether it's fragile, whether it's high-value.
4. When uncertain, INCLUDE the item with a lower confidence score. The user will review.
5. Ignore: walls, floors, ceilings, built-in fixtures, small items under 1 cubic foot.

Return ONLY a valid JSON array. No markdown, no explanation, no preamble, no backticks. Example:
[{"name":"Sectional Sofa","category":"furniture","quantity":1,"sizeEstimate":"oversized","isFragile":false,"isHighValue":true,"confidence":0.95}]

Valid categories: furniture, electronics, boxes, appliance, decor, other
Valid sizes: small, medium, large, oversized
Confidence: 0.0 to 1.0`;

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

      const items = rawItems.map((item, idx) => ({
        id: `${sessionId}-item-${idx}`,
        name: String(item.name || 'Unknown Item'),
        category: validCategories.includes(item.category) ? item.category : 'other',
        quantity: Math.max(1, Math.round(Number(item.quantity) || 1)),
        sizeEstimate: validSizes.includes(item.sizeEstimate) ? item.sizeEstimate : 'medium',
        isFragile: Boolean(item.isFragile),
        isHighValue: Boolean(item.isHighValue),
        confidence: Math.min(1, Math.max(0, Number(item.confidence) || 0.5)),
        roomName: roomName,
        shouldMove: true,
        notes: ''
      }));

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
