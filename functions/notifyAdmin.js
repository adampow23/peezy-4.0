/**
 * notifyAdmin — Central admin notification module
 *
 * Sends an SMS to Adam via Twilio AND writes to adminNotifications (backup).
 * SMS is fire-and-forget — never blocks user flow.
 * adminNotifications is the safety net — always written first.
 */

const admin = require('firebase-admin');
const twilio = require('twilio');

/**
 * Send an SMS to Adam and log to adminNotifications collection.
 *
 * @param {Object} params
 * @param {string} params.type - Event type: concierge_request | vendor_workflow | task_flow | support_message | inventory_submitted
 * @param {string} params.userId - Firebase user ID
 * @param {string} params.title - Human-readable title
 * @param {string} params.summary - 2-3 line summary of what needs to be done
 * @param {Object} [params.details] - Full details stored in Firestore (not sent via SMS)
 * @param {string} [params.urgency='normal'] - 'high' for support messages, 'normal' for everything else
 */
async function notifyAdmin({ type, userId, title, summary, details, urgency = 'normal' }) {
  const db = admin.firestore();

  // 1. Look up user profile for context
  let userName = '';
  let currentAddress = '';
  let newAddress = '';
  let moveDate = '';

  try {
    const userDoc = await db.collection('users').doc(userId).get();
    if (userDoc.exists) {
      const data = userDoc.data();
      userName = data.name || data.displayName || '';

      const origin = [data.originCity, data.originState].filter(Boolean).join(', ');
      const dest = [data.destinationCity, data.destinationState].filter(Boolean).join(', ');
      currentAddress = data.currentAddress || origin || '';
      newAddress = data.newAddress || dest || '';

      if (data.moveDate) {
        const d = data.moveDate.toDate ? data.moveDate.toDate() : new Date(data.moveDate);
        moveDate = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
      }
    }
  } catch (err) {
    console.error('[notifyAdmin] Failed to lookup user:', err.message);
  }

  // 2. Write to adminNotifications (BACKUP — always written before SMS attempt)
  const notificationRef = db.collection('adminNotifications').doc();
  const notification = {
    id: notificationRef.id,
    type,
    userId,
    userName,
    title,
    summary,
    details: details || {},
    currentAddress,
    newAddress,
    moveDate,
    urgency,
    status: 'pending',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    smsDelivered: false,
    readAt: null,
    completedAt: null
  };

  try {
    await notificationRef.set(notification);
  } catch (err) {
    console.error('[notifyAdmin] CRITICAL — Failed to write adminNotification:', err.message);
    // Non-fatal: continue to SMS attempt even if Firestore write failed
  }

  // 3. Send SMS via Twilio (fire and forget)
  try {
    const accountSid = process.env.TWILIO_ACCOUNT_SID;
    const authToken = process.env.TWILIO_AUTH_TOKEN;
    const fromNumber = process.env.TWILIO_FROM_NUMBER;
    const adminPhone = process.env.ADMIN_PHONE_NUMBER;

    if (!accountSid || !authToken || !fromNumber || !adminPhone ||
        accountSid === 'placeholder_will_set_later') {
      console.warn('[notifyAdmin] Twilio not configured — SMS skipped');
      return;
    }

    const client = twilio(accountSid, authToken);

    const emoji = {
      concierge_request: '🏠',
      vendor_workflow: '🚛',
      task_flow: '📋',
      support_message: '💬',
      inventory_submitted: '📦'
    }[type] || '📌';

    let smsBody = `${emoji} ${title}`;
    if (userName) smsBody += `\n👤 ${userName}`;
    if (currentAddress && newAddress) smsBody += `\n📍 ${currentAddress} → ${newAddress}`;
    else if (newAddress) smsBody += `\n📍 ${newAddress}`;
    if (moveDate) smsBody += `\n📅 ${moveDate}`;
    smsBody += `\n\n${summary}`;

    if (smsBody.length > 1500) {
      smsBody = smsBody.substring(0, 1497) + '...';
    }

    await client.messages.create({
      body: smsBody,
      from: fromNumber,
      to: adminPhone
    });

    await notificationRef.update({ smsDelivered: true });

  } catch (err) {
    console.error('[notifyAdmin] SMS failed:', err.message);
    // Non-fatal — notification is still in Firestore
  }
}

module.exports = { notifyAdmin };
