/**
 * Peezy Firebase Cloud Functions
 */

const { onRequest, onCall, HttpsError } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const admin = require('firebase-admin');
const { peezyChat } = require('./peezyChat');
const { getWorkflowQualifying, submitWorkflowAnswers } = require('./getWorkflowQualifying');
const { processInventory } = require('./processInventory');
const { packageInventory } = require('./packageInventory');
const { validateSubscription } = require('./validateSubscription');
const { resolveProvider } = require('./resolveProvider');
const { researchTask } = require('./researchTask');
const { submitCheckIn } = require('./submitCheckIn');

// Set global options
setGlobalOptions({ maxInstances: 10 });

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp();
}

const FIRST_SUPPORT_AUTO_ACK_ID = 'first-message-auto-acknowledgment';
const FIRST_SUPPORT_AUTO_ACK_TEXT = 'Thanks for reaching out. Peezy can help with moving questions here. For account or billing issues, email support@peezymove.com.';
/**
 * Request concierge handling for a task ("Peezy, handle this")
 */
exports.requestConcierge = onCall(
  { region: 'us-central1', timeoutSeconds: 10, memory: '256MiB' },
  async (request) => {
    const { taskId, taskTitle, taskCategory, userId, userName, currentAddress, newAddress, moveDate, moveDistance } = request.data;

    const db = admin.firestore();
    await db.collection('conciergeRequests').add({
      taskId: taskId || '',
      taskTitle: taskTitle || '',
      taskCategory: taskCategory || '',
      userId: userId || '',
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
    const { userId, userName, taskId, taskTitle, taskType, confirmedFields, transferChoice } = request.data;

    const db = admin.firestore();
    await db.collection('taskFlowSubmissions').add({
      userId: userId || '',
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
  { region: 'us-central1', timeoutSeconds: 10, memory: '256MiB' },
  async (request) => {
    const { userId } = request.data;
    const resolvedUserId = request.auth?.uid || userId;

    if (resolvedUserId) {
      try {
        const db = admin.firestore();
        const supportChatRef = db.collection('users').doc(resolvedUserId).collection('supportChat');
        const userMessagesSnapshot = await supportChatRef
          .where('sender', '==', 'user')
          .get();

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
              throw error;
            }
          }
        }
      } catch (error) {
        console.error('Support auto-acknowledgment failed:', error.message);
      }
    } else {
      console.warn('Support auto-acknowledgment skipped: missing userId');
    }

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
exports.packageInventory = packageInventory;
exports.resolveProvider = resolveProvider;
exports.researchTask = researchTask;
exports.peezyChat = peezyChat;
exports.submitCheckIn = submitCheckIn;
