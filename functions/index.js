/**
 * Peezy Firebase Cloud Functions
 */

const { onRequest, onCall, HttpsError } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const admin = require('firebase-admin');
const { peezyChat } = require('./peezyChat');
const { getWorkflowQualifying, submitWorkflowAnswers } = require('./getWorkflowQualifying');
const { processInventory, onInventoryRoomWritten } = require('./processInventory');
const { packageInventory } = require('./packageInventory');
const { validateSubscription } = require('./validateSubscription');
const { resolveProvider } = require('./resolveProvider');
const { researchTask } = require('./researchTask');
const { submitCheckIn } = require('./submitCheckIn');
const { redeemGiftCode } = require('./entitlement');
const { spawnTasks } = require('./spawnTasks');
const { notifySupport } = require('./notifySupport');
const {
  adminListThreads,
  adminGetThread,
  adminReplySupport,
  adminMarkSeen,
  adminSetThreadStatus
} = require('./supportAdmin');

// Set global options
setGlobalOptions({ maxInstances: 10 });

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp();
}

const FIRST_SUPPORT_AUTO_ACK_ID = 'first-message-auto-acknowledgment';
const FIRST_SUPPORT_AUTO_ACK_TEXT = "Thanks — a real person on the Peezy team reads every message. We'll get back to you within 8 hours, usually much faster.";
/**
 * Request concierge handling for a task ("Peezy, handle this")
 */
exports.requestConcierge = onCall(
  { region: 'us-central1', timeoutSeconds: 10, memory: '256MiB' },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError('unauthenticated', 'Must be signed in to request concierge help.');
    }

    const { taskId, taskTitle, taskCategory, userName, currentAddress, newAddress, moveDate, moveDistance } = request.data || {};

    const db = admin.firestore();
    await db.collection('conciergeRequests').add({
      taskId: taskId || '',
      taskTitle: taskTitle || '',
      taskCategory: taskCategory || '',
      userId,
      userName: userName || '',
      currentAddress: currentAddress || '',
      newAddress: newAddress || '',
      moveDate: moveDate || '',
      moveDistance: moveDistance || '',
      requestedAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'pending'
    });

    return { success: true };
  }
);

/**
 * Submit task flow — user confirmed details for a research/transfer/cancel task
 * Called from the iOS TaskFlowView after user taps "Looks Good — Go Ahead"
 */
exports.submitTaskFlow = onCall(
  { region: 'us-central1', timeoutSeconds: 10, memory: '256MiB' },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError('unauthenticated', 'Must be signed in to submit a task flow.');
    }

    const { userName, taskId, taskTitle, taskType, confirmedFields, transferChoice } = request.data || {};

    const db = admin.firestore();
    await db.collection('taskFlowSubmissions').add({
      userId,
      userName: userName || '',
      taskId: taskId || '',
      taskTitle: taskTitle || '',
      taskType: taskType || '',
      confirmedFields: confirmedFields || {},
      transferChoice: transferChoice || null,
      submittedAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'pending'
    });

    return { success: true };
  }
);

/**
 * Submit support chat message — notifies team when user sends a message
 */
exports.submitSupportMessage = onCall(
  {
    region: 'us-central1',
    timeoutSeconds: 10,
    memory: '256MiB',
    secrets: ['GMAIL_APP_PASSWORD']
  },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError('unauthenticated', 'Must be signed in to contact support.');
    }

    const text = typeof request.data?.text === 'string'
      ? request.data.text.trim()
      : '';
    if (!text) {
      throw new HttpsError('invalid-argument', 'Support message text is required.');
    }

    const rawTaskContext = request.data?.taskContext;
    const taskContext = rawTaskContext &&
      typeof rawTaskContext.userTaskId === 'string' &&
      typeof rawTaskContext.catalogTaskId === 'string' &&
      typeof rawTaskContext.title === 'string'
      ? {
          userTaskId: rawTaskContext.userTaskId,
          catalogTaskId: rawTaskContext.catalogTaskId,
          title: rawTaskContext.title
        }
      : null;

    const db = admin.firestore();
    const userRef = db.collection('users').doc(userId);
    const supportChatRef = userRef.collection('supportChat');

    const [userMessagesResult, assessmentResult] = await Promise.allSettled([
      supportChatRef.where('sender', '==', 'user').get(),
      userRef.collection('user_assessments').limit(1).get()
    ]);

    if (userMessagesResult.status === 'fulfilled') {
      const userMessagesSnapshot = userMessagesResult.value;
      if (userMessagesSnapshot.size === 1) {
        try {
          await supportChatRef.doc(FIRST_SUPPORT_AUTO_ACK_ID).create({
            text: FIRST_SUPPORT_AUTO_ACK_TEXT,
            sender: 'support',
            isAutoResponse: true,
            read: false,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
          });
        } catch (error) {
          if (error.code !== 6 && error.code !== 'already-exists') {
            console.error('Support auto-acknowledgment failed:', error.message);
          }
        }
      }
    } else {
      console.error('Support auto-acknowledgment lookup failed:', userMessagesResult.reason.message);
    }

    let userName = '';
    if (assessmentResult.status === 'fulfilled') {
      const assessmentSnapshot = assessmentResult.value;
      const assessment = assessmentSnapshot.empty
        ? {}
        : assessmentSnapshot.docs[0].data();
      if (typeof assessment.userName === 'string') {
        userName = assessment.userName.trim();
      }
    } else {
      console.error('Support user name lookup failed:', assessmentResult.reason.message);
    }

    const threadData = {
      uid: userId,
      lastMessageText: text,
      lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
      lastSender: 'user',
      unreadForAdmin: admin.firestore.FieldValue.increment(1),
      status: 'open'
    };
    if (taskContext) {
      threadData.taskContext = taskContext;
    }
    if (userName) {
      threadData.userName = userName;
    }

    void notifySupport({
      uid: userId,
      textPreview: text.slice(0, 500),
      taskTitle: taskContext?.title || ''
    }).catch(error => {
      console.error('[notifySupport] Unexpected failure:', error.message);
    });

    await db.collection('supportThreads').doc(userId).set(threadData, { merge: true });

    return { success: true };
  }
);

/**
 * Delete user account: all Firestore data + Firebase Auth user.
 * Runs as admin — can delete anything under users/{uid}/.
 * Called ONLY from the iOS app's "Delete Account" flow in Settings.
 */
exports.deleteAccount = onCall(
  { region: 'us-central1', timeoutSeconds: 60, memory: '512MiB' },
  async (request) => {
    const userId = request.auth?.uid;

    if (!userId) {
      throw new HttpsError('unauthenticated', 'Must be signed in to delete account.');
    }

    const db = admin.firestore();
    const auth = admin.auth();

    try {
      // 1. Recursively delete all user data under users/{uid}.
      // This uses Firebase's built-in recursive delete helper.
      const userDocRef = db.collection('users').doc(userId);
      await db.recursiveDelete(userDocRef);

      // 2. Delete top-level user data documents and collections that reference this user.
      await db.collection('userKnowledge').doc(userId).delete();

      const collectionsToScan = [
        'conciergeRequests',
        'taskFlowSubmissions',
        'inventorySessions'
      ];

      for (const collectionName of collectionsToScan) {
        const snapshot = await db.collection(collectionName)
          .where('userId', '==', userId)
          .get();

        const batch = db.batch();
        snapshot.forEach(doc => batch.delete(doc.ref));
        if (snapshot.size > 0) {
          await batch.commit();
        }
      }

      // 3. Delete Firebase Storage files for this user.
      // Inventory scan frames and future user-owned files should live under this prefix.
      const bucket = admin.storage().bucket();
      const [files] = await bucket.getFiles({ prefix: `users/${userId}/` });
      await Promise.all(files.map(file => file.delete().catch(() => {})));

      // 4. LAST: delete Firebase Auth user.
      // Only runs if everything above succeeded.
      await auth.deleteUser(userId);

      return { success: true };
    } catch (error) {
      console.error('Account deletion failed for user', userId, error);
      throw new HttpsError('internal', 'Account deletion failed. Please try again or contact support.');
    }
  }
);

/**
 * Health check endpoint
 */
exports.healthCheck = onRequest((req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString()
  });
});

/**
 * Workflow qualifying functions
 */
exports.getWorkflowQualifying = getWorkflowQualifying;
exports.submitWorkflowAnswers = submitWorkflowAnswers;
exports.validateSubscription = validateSubscription;
exports.processInventory = processInventory;
exports.onInventoryRoomWritten = onInventoryRoomWritten;
exports.packageInventory = packageInventory;
exports.resolveProvider = resolveProvider;
exports.researchTask = researchTask;
exports.peezyChat = peezyChat;
exports.submitCheckIn = submitCheckIn;
exports.redeemGiftCode = redeemGiftCode;
exports.spawnTasks = spawnTasks;
exports.adminListThreads = adminListThreads;
exports.adminGetThread = adminGetThread;
exports.adminReplySupport = adminReplySupport;
exports.adminMarkSeen = adminMarkSeen;
exports.adminSetThreadStatus = adminSetThreadStatus;
