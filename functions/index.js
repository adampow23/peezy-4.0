/**
 * Peezy Brain - Firebase Cloud Function
 * Main entry point for the Peezy conversational AI
 */

const { onRequest, onCall, HttpsError } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const admin = require('firebase-admin');
const { generateResponse, validateContentLoaded } = require('./peezyBrain');
const { getWorkflowQualifying, submitWorkflowAnswers } = require('./getWorkflowQualifying');
const { processInventory } = require('./processInventory');
const { packageInventory } = require('./packageInventory');
const { validateSubscription } = require('./validateSubscription');
const { resolveProvider } = require('./resolveProvider');
const { submitCheckIn } = require('./submitCheckIn');

// Set global options
setGlobalOptions({ maxInstances: 10 });

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp();
}

// Rate limiting map (in-memory, resets on cold start)
const rateLimitMap = new Map();
const RATE_LIMIT_WINDOW = 60000; // 1 minute
const RATE_LIMIT_MAX = 10; // 10 requests per minute
const FIRST_SUPPORT_AUTO_ACK_ID = 'first-message-auto-acknowledgment';
const FIRST_SUPPORT_AUTO_ACK_TEXT = 'Thanks for reaching out — Peezy will answer here. For account or billing issues, email support@peezymove.com.';

/**
 * Check rate limit for a user
 */
function checkRateLimit(userId) {
  const now = Date.now();
  const userLimit = rateLimitMap.get(userId);

  if (!userLimit || now - userLimit.windowStart > RATE_LIMIT_WINDOW) {
    // New window
    rateLimitMap.set(userId, { windowStart: now, count: 1 });
    return true;
  }

  if (userLimit.count >= RATE_LIMIT_MAX) {
    return false;
  }

  userLimit.count++;
  return true;
}

/**
 * Sanitize data for logging (no PII)
 */
function sanitizeForLogging(data) {
  return {
    userId: data.userState?.userId,
    messageLength: data.message?.length,
    historyLength: data.conversationHistory?.length,
    hasCurrentTask: !!data.currentTask,
    requestType: data.requestType,
    moveDistance: data.userState?.moveDistance,
    daysUntilMove: data.userState?.daysUntilMove
  };
}

/**
 * Generate response for initial_load request type
 * Returns personalized briefing and task cards based on user state
 */
async function generateInitialLoadResponse(data) {
  const userState = data.userState || {};
  const userId = userState.userId;
  
  // Fetch user's tasks from Firestore
  let userTasks = [];
  if (userId) {
    try {
      const db = admin.firestore();
      
      // First try: query tasks with active status values.
      // Statuses actually written to task docs (Spec 04 Phase C audit):
      // iOS writes Upcoming/InProgress/UserInProgress/Snoozed; index.js task
      // creation writes 'pending'; submitWorkflowAnswers writes
      // 'matching_in_progress' (getWorkflowQualifying.js). 'pending_matching'
      // exists only on workflowSubmissions docs — it never lands on a task
      // doc, so it was dead weight in this filter and is removed.
      let tasksSnapshot = await db
        .collection('users')
        .doc(userId)
        .collection('tasks')
        .where('status', 'in', ['Upcoming', 'InProgress', 'pending', 'matching_in_progress', 'Snoozed'])
        .get();

      // Fallback: if no results, get all tasks and filter out completed
      if (tasksSnapshot.empty) {
        console.log('No pending tasks found, fetching all tasks...');
        tasksSnapshot = await db
          .collection('users')
          .doc(userId)
          .collection('tasks')
          .get();

        userTasks = tasksSnapshot.docs
          .map(doc => ({ id: doc.id, ...doc.data() }))
          .filter(task => !['Completed', 'completed', 'Skipped', 'skipped'].includes(task.status));
      } else {
        userTasks = tasksSnapshot.docs.map(doc => ({
          id: doc.id,
          ...doc.data()
        }));
      }
      
      // Sort by priority (higher priority first)
      userTasks.sort((a, b) => (b.priority || 1) - (a.priority || 1));
      
      console.log(`Fetched ${userTasks.length} tasks for user ${userId}:`, 
        userTasks.map(t => ({ id: t.id, title: t.title, status: t.status })));
    } catch (error) {
      console.error('Error fetching user tasks:', error);
      // Continue without tasks - will use fallback
    }
  }

  // Build cards from tasks
  const cards = [];

  // Add ALL task cards (removed artificial limit of 5)
  // iOS will handle sorting by dueDate for proper display order
  for (const task of userTasks) {
    cards.push({
      type: 'task',
      title: task.title || 'Task',
      subtitle: task.subtitle || '',
      taskId: task.id,
      workflowId: task.id,  // Use task id as workflow id
      priority: task.priority || 1,
      colorName: 'white',
      category: task.category,
      subcategory: task.subcategory,
      status: task.status,
      dueDate: task.dueDate?.toDate ? task.dueDate.toDate().toISOString() : null,
      snoozedUntil: task.snoozedUntil?.toDate ? task.snoozedUntil.toDate().toISOString() : null
    });
  }

  // Generate personalized briefing using AI
  const briefingPrompt = buildBriefingPrompt(userState, userTasks);
  
  let briefingText;
  try {
    const briefingResponse = await generateResponse({
      message: briefingPrompt,
      conversationHistory: [],
      userState: userState,
      currentTask: null,
      sessionMetadata: {
        sessionId: `briefing-${Date.now()}`,
        messageCount: 1,
        firstMessageAt: new Date().toISOString()
      }
    });
    briefingText = briefingResponse.text;
  } catch (error) {
    console.error('Error generating briefing:', error);
    // Fallback briefing
    briefingText = generateFallbackBriefing(userState, userTasks.length);
  }

  // Add intro card with briefing
  cards.push({
    type: 'intro',
    title: getGreeting(),
    subtitle: userState.name || '',
    briefingMessage: briefingText,
    priority: 0
  });

  return {
    text: briefingText,
    cards: cards,
    stateUpdates: null,
    internalNotes: {
      requestType: 'initial_load',
      tasksFound: userTasks.length,
      cardsGenerated: cards.length
    }
  };
}

/**
 * Build a prompt for generating the briefing message
 */
function buildBriefingPrompt(userState, tasks) {
  const name = userState.name || 'there';
  const daysUntil = userState.daysUntilMove;
  const taskCount = tasks.length;
  
  let context = `Generate a brief, warm greeting for ${name} who is opening the Peezy moving app. `;
  
  if (daysUntil !== undefined && daysUntil !== null) {
    if (daysUntil <= 3) {
      context += `Their move is in ${daysUntil} days - it's crunch time! `;
    } else if (daysUntil <= 7) {
      context += `Their move is in ${daysUntil} days - getting close! `;
    } else if (daysUntil <= 14) {
      context += `Their move is in ${daysUntil} days. `;
    } else {
      context += `Their move is in ${daysUntil} days - good amount of time. `;
    }
  }
  
  if (taskCount === 0) {
    context += `They have no pending tasks right now. Let them know they're all caught up. `;
  } else if (taskCount === 1) {
    context += `They have 1 task to look at. `;
  } else {
    context += `They have ${taskCount} tasks to look at. `;
  }
  
  context += `Keep it to 1-2 short sentences. Be warm and helpful, not robotic. Don't use their name in the greeting (it's shown separately). Example tone: "Got a couple things for you today - shouldn't take long!"`;
  
  return context;
}

/**
 * Generate fallback briefing when AI call fails
 */
function generateFallbackBriefing(userState, taskCount) {
  if (taskCount === 0) {
    return "All clear! We'll let you know when something comes up.";
  } else if (taskCount === 1) {
    return "Just one thing today — open it for the details and your next step.";
  } else if (taskCount === 2) {
    return "Couple things for you today - shouldn't take long!";
  } else {
    return "Got a few things ready for you.";
  }
}

/**
 * Get time-appropriate greeting
 */
function getGreeting() {
  const hour = new Date().getHours();
  if (hour < 12) return "Good morning";
  if (hour < 17) return "Good afternoon";
  return "Good evening";
}


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
  const contentCheck = validateContentLoaded();

  res.json({
    status: contentCheck.valid ? 'healthy' : 'degraded',
    timestamp: new Date().toISOString(),
    content: contentCheck.checks
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
exports.submitCheckIn = submitCheckIn;
