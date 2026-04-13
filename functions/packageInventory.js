/**
 * packageInventory - Cloud Function
 * Called after user saves their inventory scan.
 * Pulls assessment data + inventory + user info,
 * packages into a formatted email, sends to admin,
 * and stores in an admin Firestore collection.
 *
 * SETUP REQUIRED:
 * 1. npm install nodemailer (in functions directory)
 * 2. Set environment variables in Firebase:
 *    firebase functions:secrets:set GMAIL_APP_PASSWORD
 *    (Generate an App Password in Google Workspace: Security > 2-Step Verification > App Passwords)
 * 3. The sending address is adam@peezymove.com via Google Workspace SMTP
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const { notifyAdmin } = require('./notifyAdmin');

const ADMIN_EMAIL = 'adam@peezymove.com';

// Lazy-init transporter
let transporter = null;

function getTransporter() {
  if (!transporter) {
    const appPassword = process.env.GMAIL_APP_PASSWORD;
    if (!appPassword) {
      throw new Error('GMAIL_APP_PASSWORD environment variable is required');
    }
    transporter = nodemailer.createTransport({
      host: 'smtp.gmail.com',
      port: 465,
      secure: true,
      auth: {
        user: ADMIN_EMAIL,
        pass: appPassword
      }
    });
  }
  return transporter;
}

exports.packageInventory = onCall(
  {
    timeoutSeconds: 60,
    memory: '512MiB',
    cors: true,
    enforceAppCheck: false,
    secrets: ['GMAIL_APP_PASSWORD']
  },
  async (request) => {
    // 1. Validate auth
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be authenticated');
    }

    const userId = request.auth.uid;
    const db = admin.firestore();

    try {
      // 2. Get user auth record (email)
      const userRecord = await admin.auth().getUser(userId);
      const userEmail = userRecord.email || 'No email on file';

      // 3. Get assessment data
      const assessmentSnap = await db.collection('users').doc(userId)
        .collection('user_assessments')
        .limit(1)
        .get();

      let assessment = {};
      if (!assessmentSnap.empty) {
        assessment = assessmentSnap.docs[0].data();
      }

      // 4. Get inventory data (all rooms)
      const inventorySnap = await db.collection('users').doc(userId)
        .collection('inventory')
        .get();

      const rooms = [];
      let allFurniture = [];
      let allBoxable = [];
      let totalItemCount = 0;

      inventorySnap.forEach(doc => {
        const roomData = doc.data();
        const items = roomData.items || [];
        const furniture = items.filter(i => i.tier === 'furniture' && i.shouldMove !== false);
        const boxable = items.filter(i => i.tier === 'boxable' && i.shouldMove !== false);

        rooms.push({
          name: roomData.name || 'Unknown Room',
          furnitureCount: furniture.length,
          boxableCount: boxable.length,
          furniture: furniture,
          boxable: boxable
        });

        allFurniture = allFurniture.concat(furniture);
        allBoxable = allBoxable.concat(boxable);
        totalItemCount += items.filter(i => i.shouldMove !== false).length;
      });

      // 5. Calculate box estimate
      const boxableCF = allBoxable.reduce((total, item) => {
        const cf = item.cubicFeet > 0 ? item.cubicFeet : 3.0;
        return total + (cf * (item.quantity || 1));
      }, 0);
      const midpointBoxes = boxableCF / 3.0;
      const boxLow = Math.max(3, Math.round(midpointBoxes * 0.85));
      const boxHigh = Math.max(3, Math.ceil(midpointBoxes * 1.15));

      const packLow = (boxLow / 6.0).toFixed(1);
      const packHigh = (boxHigh / 4.0).toFixed(1);

      // 6. Format move date
      let moveDateStr = 'Not specified';
      if (assessment.moveDate) {
        const moveDate = assessment.moveDate.toDate ? assessment.moveDate.toDate() : new Date(assessment.moveDate);
        moveDateStr = moveDate.toLocaleDateString('en-US', {
          weekday: 'long',
          year: 'numeric',
          month: 'long',
          day: 'numeric'
        });
        if (assessment.moveDateType) {
          moveDateStr += ` (${assessment.moveDateType})`;
        }
      }

      // 7. Build email HTML
      const html = buildEmailHTML({
        userName: assessment.userName || 'Unknown',
        userEmail: userEmail,
        moveDateStr: moveDateStr,
        currentAddress: assessment.currentAddress || 'Not provided',
        currentDwellingType: assessment.currentDwellingType || '',
        currentBedrooms: assessment.currentBedrooms || '',
        currentRentOrOwn: assessment.currentRentOrOwn || '',
        currentFloorAccess: assessment.currentFloorAccess || '',
        newAddress: assessment.newAddress || 'Not provided',
        newDwellingType: assessment.newDwellingType || '',
        newBedrooms: assessment.newBedrooms || '',
        newRentOrOwn: assessment.newRentOrOwn || '',
        newFloorAccess: assessment.newFloorAccess || '',
        hasStorage: assessment.hasStorage || 'No',
        storageSize: assessment.storageSize || '',
        storageFullness: assessment.storageFullness || '',
        moveDistance: assessment.moveDistance || '',
        isInterstate: assessment.isInterstate || '',
        hireMovers: assessment.hireMovers || '',
        hirePackers: assessment.hirePackers || '',
        rooms: rooms,
        allFurniture: allFurniture,
        totalItemCount: totalItemCount,
        boxLow: boxLow,
        boxHigh: boxHigh,
        packLow: packLow,
        packHigh: packHigh,
        fragileCount: allFurniture.filter(i => i.isFragile).length + allBoxable.filter(i => i.isFragile).length,
        highValueCount: allFurniture.filter(i => i.isHighValue).length + allBoxable.filter(i => i.isHighValue).length
      });

      // 8. Send email
      const mailer = getTransporter();
      await mailer.sendMail({
        from: `"Peezy Move" <${ADMIN_EMAIL}>`,
        to: ADMIN_EMAIL,
        subject: `New Inventory: ${assessment.userName || 'Unknown'} — ${assessment.currentAddress || 'No address'} → ${assessment.newAddress || 'No address'}`,
        html: html
      });

      // 9. Store in admin collection
      const packageData = {
        userId: userId,
        userEmail: userEmail,
        userName: assessment.userName || 'Unknown',
        currentAddress: assessment.currentAddress || '',
        newAddress: assessment.newAddress || '',
        moveDate: assessment.moveDate || null,
        moveDateType: assessment.moveDateType || '',
        currentDwellingType: assessment.currentDwellingType || '',
        newDwellingType: assessment.newDwellingType || '',
        totalItemCount: totalItemCount,
        furnitureCount: allFurniture.length,
        boxEstimateLow: boxLow,
        boxEstimateHigh: boxHigh,
        roomCount: rooms.length,
        fragileCount: allFurniture.filter(i => i.isFragile).length + allBoxable.filter(i => i.isFragile).length,
        highValueCount: allFurniture.filter(i => i.isHighValue).length + allBoxable.filter(i => i.isHighValue).length,
        rooms: rooms.map(r => ({
          name: r.name,
          furnitureCount: r.furnitureCount,
          boxableCount: r.boxableCount
        })),
        isNew: true,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      };

      await db.collection('admin').doc('inventoryPackages')
        .collection('packages').add(packageData);

      // Notify admin via SMS + backup log
      notifyAdmin({
        type: 'inventory_submitted',
        userId,
        title: 'Inventory submitted for review',
        summary: 'User submitted their room inventory. Check dashboard for full item list.',
        details: {}
      }).catch(err => console.error('notifyAdmin failed:', err.message));

      console.log(`packageInventory: sent package for user ${userId} (${assessment.userName})`);
      return { success: true };

    } catch (error) {
      console.error('packageInventory error:', error);
      throw new HttpsError('internal', error.message || 'Failed to package inventory');
    }
  }
);

// ─────────────────────────────────────────────
// Email HTML Builder
// ─────────────────────────────────────────────

function buildEmailHTML(data) {
  const furnitureRows = data.allFurniture.map(item => {
    const flags = [];
    if (item.isFragile) flags.push('⚠️ Fragile');
    if (item.isHighValue) flags.push('🛡️ High Value');
    return `
      <tr>
        <td style="padding: 8px 12px; border-bottom: 1px solid #eee;">${item.name}</td>
        <td style="padding: 8px 12px; border-bottom: 1px solid #eee; text-align: center;">${item.quantity || 1}</td>
        <td style="padding: 8px 12px; border-bottom: 1px solid #eee;">${item.roomName || ''}</td>
        <td style="padding: 8px 12px; border-bottom: 1px solid #eee;">${flags.join(', ') || '—'}</td>
      </tr>`;
  }).join('');

  const roomSummaryRows = data.rooms.map(room => `
    <tr>
      <td style="padding: 6px 12px; border-bottom: 1px solid #eee;">${room.name}</td>
      <td style="padding: 6px 12px; border-bottom: 1px solid #eee; text-align: center;">${room.furnitureCount}</td>
      <td style="padding: 6px 12px; border-bottom: 1px solid #eee; text-align: center;">${room.boxableCount}</td>
    </tr>`).join('');

  return `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 700px; margin: 0 auto; padding: 20px; color: #1a1a1a;">

  <div style="background: #FFC233; padding: 24px; border-radius: 12px; margin-bottom: 24px;">
    <h1 style="margin: 0; font-size: 22px; color: #1a1a1a;">New Peezy Inventory Package</h1>
    <p style="margin: 8px 0 0; color: #1a1a1a; opacity: 0.7;">Ready to send to moving companies</p>
  </div>

  <!-- Customer Info -->
  <div style="background: #f8f8f8; padding: 20px; border-radius: 10px; margin-bottom: 20px;">
    <h2 style="margin: 0 0 12px; font-size: 16px; color: #666;">Customer</h2>
    <table style="width: 100%;">
      <tr><td style="padding: 4px 0; font-weight: 600; width: 120px;">Name</td><td>${data.userName}</td></tr>
      <tr><td style="padding: 4px 0; font-weight: 600;">Email</td><td>${data.userEmail}</td></tr>
      <tr><td style="padding: 4px 0; font-weight: 600;">Move Date</td><td>${data.moveDateStr}</td></tr>
      <tr><td style="padding: 4px 0; font-weight: 600;">Distance</td><td>${data.moveDistance}${data.isInterstate === 'Yes' ? ' (Interstate)' : ''}</td></tr>
      <tr><td style="padding: 4px 0; font-weight: 600;">Wants Movers</td><td>${data.hireMovers}</td></tr>
      <tr><td style="padding: 4px 0; font-weight: 600;">Wants Packers</td><td>${data.hirePackers}</td></tr>
    </table>
  </div>

  <!-- Addresses -->
  <div style="display: flex; gap: 16px; margin-bottom: 20px;">
    <div style="flex: 1; background: #f0f7ff; padding: 16px; border-radius: 10px;">
      <h3 style="margin: 0 0 8px; font-size: 14px; color: #3b82f6;">Moving From</h3>
      <p style="margin: 0; font-weight: 600;">${data.currentAddress}</p>
      <p style="margin: 4px 0 0; color: #666; font-size: 13px;">
        ${data.currentDwellingType}${data.currentBedrooms ? ' • ' + data.currentBedrooms + ' BR' : ''}${data.currentRentOrOwn ? ' • ' + data.currentRentOrOwn : ''}
        ${data.currentFloorAccess ? '<br>Access: ' + data.currentFloorAccess : ''}
      </p>
    </div>
    <div style="flex: 1; background: #f0fdf4; padding: 16px; border-radius: 10px;">
      <h3 style="margin: 0 0 8px; font-size: 14px; color: #22c55e;">Moving To</h3>
      <p style="margin: 0; font-weight: 600;">${data.newAddress}</p>
      <p style="margin: 4px 0 0; color: #666; font-size: 13px;">
        ${data.newDwellingType}${data.newBedrooms ? ' • ' + data.newBedrooms + ' BR' : ''}${data.newRentOrOwn ? ' • ' + data.newRentOrOwn : ''}
        ${data.newFloorAccess ? '<br>Access: ' + data.newFloorAccess : ''}
      </p>
    </div>
  </div>

  <!-- Storage -->
  ${data.hasStorage === 'Yes' ? `
  <div style="background: #fefce8; padding: 12px 16px; border-radius: 8px; margin-bottom: 20px; font-size: 14px;">
    📦 <strong>Has Storage Unit</strong>${data.storageSize ? ' — ' + data.storageSize : ''}${data.storageFullness ? ' (' + data.storageFullness + ' full)' : ''}
  </div>` : ''}

  <!-- Packing Estimate -->
  <div style="background: #fff7ed; padding: 20px; border-radius: 10px; margin-bottom: 20px; text-align: center;">
    <h2 style="margin: 0 0 16px; font-size: 16px; color: #ea580c;">Packing Estimate</h2>
    <div style="display: flex; justify-content: center; gap: 40px;">
      <div>
        <div style="font-size: 28px; font-weight: 700; color: #1a1a1a;">${data.boxLow}–${data.boxHigh}</div>
        <div style="font-size: 13px; color: #666;">boxes</div>
      </div>
      <div style="width: 1px; background: #e5e5e5;"></div>
      <div>
        <div style="font-size: 28px; font-weight: 700; color: #1a1a1a;">${data.packLow}–${data.packHigh}</div>
        <div style="font-size: 13px; color: #666;">hours to pack</div>
      </div>
    </div>
    ${data.fragileCount > 0 ? `<p style="margin: 12px 0 0; font-size: 13px; color: #ea580c;">⚠️ ${data.fragileCount} fragile item${data.fragileCount === 1 ? '' : 's'}</p>` : ''}
    ${data.highValueCount > 0 ? `<p style="margin: 4px 0 0; font-size: 13px; color: #7c3aed;">🛡️ ${data.highValueCount} high-value item${data.highValueCount === 1 ? '' : 's'}</p>` : ''}
  </div>

  <!-- Room Summary -->
  <div style="margin-bottom: 20px;">
    <h2 style="font-size: 16px; color: #666; margin: 0 0 12px;">Rooms Scanned (${data.rooms.length})</h2>
    <table style="width: 100%; border-collapse: collapse; font-size: 14px;">
      <thead>
        <tr style="background: #f3f4f6;">
          <th style="padding: 8px 12px; text-align: left;">Room</th>
          <th style="padding: 8px 12px; text-align: center;">Furniture</th>
          <th style="padding: 8px 12px; text-align: center;">Boxable Items</th>
        </tr>
      </thead>
      <tbody>${roomSummaryRows}</tbody>
    </table>
  </div>

  <!-- Furniture Detail -->
  ${data.allFurniture.length > 0 ? `
  <div style="margin-bottom: 20px;">
    <h2 style="font-size: 16px; color: #666; margin: 0 0 12px;">Furniture & Large Items (${data.allFurniture.length})</h2>
    <table style="width: 100%; border-collapse: collapse; font-size: 14px;">
      <thead>
        <tr style="background: #f3f4f6;">
          <th style="padding: 8px 12px; text-align: left;">Item</th>
          <th style="padding: 8px 12px; text-align: center;">Qty</th>
          <th style="padding: 8px 12px; text-align: left;">Room</th>
          <th style="padding: 8px 12px; text-align: left;">Flags</th>
        </tr>
      </thead>
      <tbody>${furnitureRows}</tbody>
    </table>
  </div>` : ''}

  <!-- Total -->
  <div style="background: #1a1a1a; color: white; padding: 16px 20px; border-radius: 10px; text-align: center;">
    <strong>${data.totalItemCount} total items</strong> across ${data.rooms.length} room${data.rooms.length === 1 ? '' : 's'}
  </div>

</body>
</html>`;
}
