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

const adminListThreads = onCall(CALLABLE_OPTIONS, async (request) => {
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
});

const adminGetThread = onCall(CALLABLE_OPTIONS, async (request) => {
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
  const batch = db.batch();
  batch.set(supportChatRef.doc('_meta'), { adminSeenAt: now }, { merge: true });
  batch.set(threadRef, { uid, unreadForAdmin: 0 }, { merge: true });
  await batch.commit();

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
});

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
  adminListThreads,
  adminGetThread,
  adminReplySupport,
  adminMarkSeen,
  adminSetThreadStatus
};
