/**
 * Admin-only callables for support thread management.
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const CALLABLE_OPTIONS = {
  region: 'us-central1',
  timeoutSeconds: 10,
  memory: '256MiB'
};

function requireSupportAdmin(request) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Must be signed in.');
  }

  const allowedEmails = (process.env.SUPPORT_ADMIN_EMAILS || '')
    .split(',')
    .map(email => email.trim().toLowerCase())
    .filter(Boolean);
  const email = typeof request.auth.token.email === 'string'
    ? request.auth.token.email.trim().toLowerCase()
    : '';

  if (!email || !allowedEmails.includes(email)) {
    throw new HttpsError('permission-denied', 'Not authorized for support administration.');
  }
}

function requireUid(data) {
  const uid = typeof data?.uid === 'string' ? data.uid.trim() : '';
  if (!uid || uid.includes('/')) {
    throw new HttpsError('invalid-argument', 'A valid uid is required.');
  }
  return uid;
}

const adminReplySupport = onCall(CALLABLE_OPTIONS, async (request) => {
  requireSupportAdmin(request);

  const uid = requireUid(request.data);
  const text = typeof request.data?.text === 'string'
    ? request.data.text.trim()
    : '';
  if (!text) {
    throw new HttpsError('invalid-argument', 'Reply text is required.');
  }

  const db = admin.firestore();
  const supportChatRef = db.collection('users').doc(uid).collection('supportChat');
  const messageRef = supportChatRef.doc();
  const threadRef = db.collection('supportThreads').doc(uid);
  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();

  batch.set(messageRef, {
    text,
    sender: 'support',
    timestamp: now,
    read: false
  });
  batch.set(threadRef, {
    uid,
    lastMessageText: text,
    lastMessageAt: now,
    lastSender: 'support',
    unreadForAdmin: 0
  }, { merge: true });
  batch.set(supportChatRef.doc('_meta'), {
    adminSeenAt: now
  }, { merge: true });

  await batch.commit();
  return { success: true, messageId: messageRef.id };
});

const adminMarkSeen = onCall(CALLABLE_OPTIONS, async (request) => {
  requireSupportAdmin(request);

  const uid = requireUid(request.data);
  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();

  batch.set(
    db.collection('users').doc(uid).collection('supportChat').doc('_meta'),
    { adminSeenAt: now },
    { merge: true }
  );
  batch.set(
    db.collection('supportThreads').doc(uid),
    { unreadForAdmin: 0 },
    { merge: true }
  );

  await batch.commit();
  return { success: true };
});

const adminSetThreadStatus = onCall(CALLABLE_OPTIONS, async (request) => {
  requireSupportAdmin(request);

  const uid = requireUid(request.data);
  const status = request.data?.status;
  if (status !== 'open' && status !== 'resolved') {
    throw new HttpsError('invalid-argument', 'Status must be open or resolved.');
  }

  await admin.firestore().collection('supportThreads').doc(uid).update({ status });
  return { success: true };
});

module.exports = {
  adminReplySupport,
  adminMarkSeen,
  adminSetThreadStatus
};
