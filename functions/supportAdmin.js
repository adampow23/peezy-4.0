/**
 * Admin-only callables for support thread management.
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const { Timestamp } = require('firebase-admin/firestore');
const { withOutboundLease, assertDeletionAbsent, withFixedErrorBoundary } = require('./accountDeletionFence');

// C6.8 — the sole FCM surface. Payload is content-free; the reply text never leaves Firestore.
const FCM_DESTINATION_CAPACITY = 501;
const SUPPORT_REPLY_NOTIFICATION = Object.freeze({ title: 'Peezy', body: 'You have a new support reply.' });
/** Frozen from Firebase Admin 13.6.0 `MessagingClientErrorCode` (19 codes). */
const FCM_ACCEPTED_FAILURE_CODES_V1 = Object.freeze([
  'messaging/authentication-error', 'messaging/device-message-rate-exceeded', 'messaging/internal-error', 'messaging/invalid-argument',
  'messaging/invalid-data-payload-key', 'messaging/invalid-options', 'messaging/invalid-package-name', 'messaging/invalid-payload',
  'messaging/invalid-recipient', 'messaging/invalid-registration-token', 'messaging/message-rate-exceeded', 'messaging/mismatched-credential',
  'messaging/payload-size-limit-exceeded', 'messaging/registration-token-not-registered', 'messaging/server-unavailable',
  'messaging/third-party-auth-error', 'messaging/too-many-topics', 'messaging/topics-message-rate-exceeded', 'messaging/unknown-error'
]);
const FCM_TOKEN_DELETION_CODES_V1 = Object.freeze(['messaging/invalid-registration-token', 'messaging/registration-token-not-registered']);

function fixedLog(code, counts) {
  logger.info(code, counts || {});
}

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

function timestampToMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  if (typeof value._seconds === 'number') {
    return (value._seconds * 1000) + Math.floor((value._nanoseconds || 0) / 1000000);
  }
  return null;
}

function serializeTaskContext(value) {
  if (!value || typeof value !== 'object') return null;

  const taskContext = {
    userTaskId: typeof value.userTaskId === 'string' ? value.userTaskId : '',
    catalogTaskId: typeof value.catalogTaskId === 'string' ? value.catalogTaskId : '',
    title: typeof value.title === 'string' ? value.title : ''
  };
  return Object.values(taskContext).some(Boolean) ? taskContext : null;
}

function parseCityState(address) {
  if (typeof address !== 'string' || !address.trim()) {
    return { city: '', state: '' };
  }

  const parts = address.split(',').map(part => part.trim());
  for (let index = parts.length - 1; index >= 0; index -= 1) {
    const tokens = parts[index].split(/\s+/).filter(Boolean);
    const state = tokens[0] || '';
    const remainingTokensArePostalCode = tokens.slice(1)
      .every(token => /^[0-9-]+$/.test(token));
    if (/^[A-Z]{2}$/.test(state) && remainingTokensArePostalCode) {
      return {
        city: index > 0 ? parts[index - 1] : '',
        state
      };
    }
  }

  return { city: '', state: '' };
}

function threadFromDocument(document) {
  const data = document.data();
  const unread = Number(data.unreadForAdmin);
  return {
    uid: typeof data.uid === 'string' && data.uid ? data.uid : document.id,
    userName: typeof data.userName === 'string' ? data.userName : '',
    lastMessageText: typeof data.lastMessageText === 'string' ? data.lastMessageText : '',
    lastMessageAt: timestampToMillis(data.lastMessageAt),
    lastSender: typeof data.lastSender === 'string' ? data.lastSender : '',
    unreadForAdmin: Number.isFinite(unread) ? Math.max(0, unread) : 0,
    status: data.status === 'resolved' ? 'resolved' : 'open',
    taskContext: serializeTaskContext(data.taskContext)
  };
}

/**
 * Support-reply multicast under the outbound lease (C6.2/C6.8): `limit(501)` on
 * `users/{uid}/fcmTokens`, exact content-free payload, token deletion only for the two
 * accepted codes, fixed event codes with bounded counts. Never throws to the caller.
 */
async function sendSupportReplyPush(uid, deps = {}) {
  const db = deps.db || admin.firestore();
  const messaging = deps.messaging || admin.messaging();
  const now = deps.now || (() => Timestamp.fromMillis(Date.now()));
  const log = deps.log || fixedLog;
  const tokenSnapshot = await db.collection(`users/${uid}/fcmTokens`).orderBy(admin.firestore.FieldPath.documentId()).limit(FCM_DESTINATION_CAPACITY).get();
  if (tokenSnapshot.empty) return;
  if (tokenSnapshot.size >= FCM_DESTINATION_CAPACITY) {
    log('FCM_DESTINATION_CAPACITY', { count: tokenSnapshot.size });
    return;
  }
  const tokenDocuments = tokenSnapshot.docs;
  let result;
  try {
    result = await withOutboundLease({ db, now }, { uid, channel: 'fcm' }, () => messaging.sendEachForMulticast({
      tokens: tokenDocuments.map(document => document.id),
      notification: { title: SUPPORT_REPLY_NOTIFICATION.title, body: SUPPORT_REPLY_NOTIFICATION.body },
      data: { thread: 'support' },
      android: { ttl: 0 },
      apns: { headers: { 'apns-expiration': '0' }, payload: { aps: { sound: 'default', badge: 1, category: 'PEEZY_SUPPORT_REPLY_V1' } } }
    }));
  } catch (error) {
    log(error && error.details && error.details.reason === 'ACCOUNT_DELETION_FENCED' ? 'FCM_SEND_FENCED' : (error && typeof error.code === 'string' && error.code.startsWith('OUTBOUND_LEASE') ? error.code : 'FCM_SEND_FAILED'), { tokens: tokenDocuments.length });
    return;
  }
  let unknownCodes = 0;
  const invalidTokenRefs = [];
  (result.responses || []).forEach((response, index) => {
    if (response.success) return;
    const code = response.error && typeof response.error.code === 'string' ? response.error.code : '';
    if (!FCM_ACCEPTED_FAILURE_CODES_V1.includes(code)) { unknownCodes += 1; return; }
    if (FCM_TOKEN_DELETION_CODES_V1.includes(code)) invalidTokenRefs.push(tokenDocuments[index].ref);
  });
  if (unknownCodes > 0) log('FCM_UNKNOWN_FAILURE_CODE', { count: unknownCodes });
  if (result.failureCount > 0) log('FCM_DELIVERY_FAILURES', { failures: result.failureCount, deleted: invalidTokenRefs.length });
  // support invalid-token deletion is an explicit C6.1 exclusion (deletion-only)
  for (const ref of invalidTokenRefs) await ref.delete();
}

const adminListThreads = onCall(CALLABLE_OPTIONS, withFixedErrorBoundary('SUPPORT_ADMIN_INTERNAL_FAILURE', async (request) => {
  requireSupportAdmin(request);

  const rawStatusFilter = request.data?.statusFilter;
  const statusFilter = rawStatusFilter === undefined || rawStatusFilter === null || rawStatusFilter === ''
    ? null
    : rawStatusFilter;
  if (statusFilter !== null && statusFilter !== 'open' && statusFilter !== 'resolved') {
    throw new HttpsError('invalid-argument', 'Status filter must be open or resolved.');
  }

  const snapshot = await admin.firestore().collection('supportThreads').get();
  const threads = snapshot.docs
    .map(threadFromDocument)
    .filter(thread => statusFilter === null || thread.status === statusFilter)
    .sort((left, right) => {
      const timeDifference = (right.lastMessageAt || 0) - (left.lastMessageAt || 0);
      return timeDifference || left.uid.localeCompare(right.uid);
    });

  return { threads };
}, fixedLog));

const adminGetThread = onCall(CALLABLE_OPTIONS, withFixedErrorBoundary('SUPPORT_ADMIN_INTERNAL_FAILURE', async (request) => {
  requireSupportAdmin(request);

  const uid = requireUid(request.data);
  const db = admin.firestore();
  const userRef = db.collection('users').doc(uid);
  const supportChatRef = userRef.collection('supportChat');
  const threadRef = db.collection('supportThreads').doc(uid);

  const [messagesSnapshot, assessmentSnapshot, threadSnapshot] = await Promise.all([
    supportChatRef.get(),
    userRef.collection('user_assessments').limit(1).get(),
    threadRef.get()
  ]);

  const messages = messagesSnapshot.docs
    .filter(document => document.id !== '_meta')
    .map(document => {
      const data = document.data();
      return {
        id: document.id,
        text: typeof data.text === 'string' ? data.text : '',
        sender: typeof data.sender === 'string' ? data.sender : '',
        timestamp: timestampToMillis(data.timestamp),
        read: data.read === true,
        isAutoResponse: data.isAutoResponse === true,
        taskContext: serializeTaskContext(data.taskContext)
      };
    })
    .sort((left, right) => {
      const timeDifference = (left.timestamp || 0) - (right.timestamp || 0);
      return timeDifference || left.id.localeCompare(right.id);
    });

  const assessment = assessmentSnapshot.empty
    ? {}
    : assessmentSnapshot.docs[0].data();
  const moveDate = timestampToMillis(assessment.moveDate);
  const currentLocation = parseCityState(assessment.currentAddress);
  const destinationLocation = parseCityState(assessment.newAddress);
  const name = typeof assessment.userName === 'string'
    ? assessment.userName.trim()
    : '';
  const daysUntilMove = moveDate === null
    ? null
    : Math.ceil((moveDate - Date.now()) / (24 * 60 * 60 * 1000));

  const thread = threadSnapshot.exists ? threadFromDocument(threadSnapshot) : null;
  const now = admin.firestore.FieldValue.serverTimestamp();
  await db.runTransaction(async (transaction) => {
    await assertDeletionAbsent(transaction, db, [uid]);
    transaction.set(supportChatRef.doc('_meta'), { adminSeenAt: now }, { merge: true });
    transaction.set(threadRef, { uid, unreadForAdmin: 0 }, { merge: true });
  });

  return {
    uid,
    messages,
    userContext: {
      name,
      moveDate,
      daysUntilMove,
      currentCity: currentLocation.city,
      currentState: currentLocation.state,
      destinationCity: destinationLocation.city,
      destinationState: destinationLocation.state
    },
    status: thread?.status || 'open',
    taskContext: thread?.taskContext || null
  };
}, fixedLog));

const adminReplySupport = onCall(CALLABLE_OPTIONS, withFixedErrorBoundary('SUPPORT_ADMIN_INTERNAL_FAILURE', async (request) => {
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
  await db.runTransaction(async (transaction) => {
    await assertDeletionAbsent(transaction, db, [uid]);
    transaction.set(messageRef, {
      text,
      sender: 'support',
      timestamp: now,
      read: false
    });
    transaction.set(threadRef, {
      uid,
      lastMessageText: text,
      lastMessageAt: now,
      lastSender: 'support',
      unreadForAdmin: 0
    }, { merge: true });
    transaction.set(supportChatRef.doc('_meta'), {
      adminSeenAt: now
    }, { merge: true });
  });
  await sendSupportReplyPush(uid, { db }).catch(() => fixedLog('FCM_SEND_FAILED', {}));
  return { success: true, messageId: messageRef.id };
}, fixedLog));

const adminMarkSeen = onCall(CALLABLE_OPTIONS, withFixedErrorBoundary('SUPPORT_ADMIN_INTERNAL_FAILURE', async (request) => {
  requireSupportAdmin(request);

  const uid = requireUid(request.data);
  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  await db.runTransaction(async (transaction) => {
    await assertDeletionAbsent(transaction, db, [uid]);
    transaction.set(
      db.collection('users').doc(uid).collection('supportChat').doc('_meta'),
      { adminSeenAt: now },
      { merge: true }
    );
    transaction.set(
      db.collection('supportThreads').doc(uid),
      { unreadForAdmin: 0 },
      { merge: true }
    );
  });
  return { success: true };
}, fixedLog));

const adminSetThreadStatus = onCall(CALLABLE_OPTIONS, withFixedErrorBoundary('SUPPORT_ADMIN_INTERNAL_FAILURE', async (request) => {
  requireSupportAdmin(request);

  const uid = requireUid(request.data);
  const status = request.data?.status;
  if (status !== 'open' && status !== 'resolved') {
    throw new HttpsError('invalid-argument', 'Status must be open or resolved.');
  }

  const db = admin.firestore();
  await db.runTransaction(async (transaction) => {
    await assertDeletionAbsent(transaction, db, [uid]);
    transaction.update(db.collection('supportThreads').doc(uid), { status });
  });
  return { success: true };
}, fixedLog));

module.exports = {
  adminListThreads,
  adminGetThread,
  adminReplySupport,
  adminMarkSeen,
  adminSetThreadStatus,
  _test: {
    sendSupportReplyPush,
    FCM_ACCEPTED_FAILURE_CODES_V1,
    FCM_TOKEN_DELETION_CODES_V1,
    FCM_DESTINATION_CAPACITY,
    SUPPORT_REPLY_NOTIFICATION
  }
};
