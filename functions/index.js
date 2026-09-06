/**
 * Peezy Firebase Cloud Functions
 */

const { onRequest, onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
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
const { changeTaskPlan } = require('./taskPlan');
const { handleAccountDeletionRequest, productionDependencies, runStorageReconciler, runAuthReconciler } = require('./accountDeletionFence');
const { evaluateDispositionTriggers } = require('./dispositionTriggers');
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
 * Account deletion (PHASE2_CONTRACT.md C2.3/C3): discover|begin|resume|finalize against the
 * root marker. The core lives in ./accountDeletionFence; this export binds only the pinned options.
 */
exports.deleteAccount = onCall(
  { region: 'us-central1', timeoutSeconds: 60, memory: '512MiB' },
  (request) => handleAccountDeletionRequest(request, productionDependencies())
);

/**
 * Scheduled Storage/Firestore and Auth guards (PHASE2_CONTRACT.md C3). Sole deployed export site.
 */
exports.reconcileAccountDeletionStorage = onSchedule(
  { schedule: '*/5 * * * *', timeZone: 'UTC', region: 'us-central1', timeoutSeconds: 270, memory: '512MiB', maxInstances: 1, retryCount: 0 },
  (event) => runStorageReconciler(event, productionDependencies())
);

exports.reconcileAccountDeletionAuth = onSchedule(
  { schedule: '2-57/5 * * * *', timeZone: 'UTC', region: 'us-central1', timeoutSeconds: 270, memory: '512MiB', maxInstances: 1, retryCount: 0 },
  (event) => runAuthReconciler(event, productionDependencies())
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
exports.changeTaskPlan = changeTaskPlan;
exports.evaluateDispositionTriggers = evaluateDispositionTriggers;
exports.adminListThreads = adminListThreads;
exports.adminGetThread = adminGetThread;
exports.adminReplySupport = adminReplySupport;
exports.adminMarkSeen = adminMarkSeen;
exports.adminSetThreadStatus = adminSetThreadStatus;
