/**
 * Peezy Brain - Firebase Cloud Function
 * Main entry point for the Peezy conversational AI
 */

const { onRequest } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const admin = require('firebase-admin');
const { generateResponse, validateContentLoaded } = require('./peezyBrain');
const { getWorkflowQualifying, submitWorkflowAnswers } = require('./getWorkflowQualifying');
const { validateSubscription } = require('./validateSubscription');

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
 * Main peezyRespond Cloud Function
 *
 * Expected input (POST body):
 * {
 *   message: string,
 *   conversationHistory: Message[],
 *   userState: UserState,
 *   currentTaskId?: string,
 *   requestType?: "chat" | "card_action" | "initial_load"
 * }
 *
 * Returns:
 * {
 *   text: string,
 *   suggestedActions?: Action[],
 *   stateUpdates?: Partial<UserState>,
 *   internalNotes?: object,
 *   cards?: CardData[]
 * }
 */
exports.peezyRespond = onRequest(
  {
    timeoutSeconds: 30,
    memory: '512MiB',
    cors: true  // Enable CORS for all origins (adjust in production if needed)
  },
  async (req, res) => {
    const startTime = Date.now();

    // Only accept POST requests
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const data = req.body;

    try {
      // Log request (sanitized)
      console.log('peezyRespond called:', sanitizeForLogging(data));

      // Validate content is loaded
      const contentCheck = validateContentLoaded();
      if (!contentCheck.valid) {
        console.error('Content not properly loaded:', contentCheck.checks);
        res.status(500).json({
          text: "I'm having trouble loading my knowledge base. Try again in a moment.",
          error: true,
          retryable: true
        });
        return;
      }

      // Get user ID for rate limiting
      const userId = data.userState?.userId || 'anonymous';

      // Check rate limit
      if (!checkRateLimit(userId)) {
        console.warn('Rate limit exceeded for user:', userId);
        res.status(429).json({
          text: "You're moving fast! Give me a moment to catch up. Try again in a few seconds.",
          error: true,
          retryable: true,
          _meta: { rateLimited: true }
        });
        return;
      }

      // Handle different request types
      const requestType = data.requestType || 'chat';
      let response;

      if (requestType === 'initial_load') {
        // Initial load - generate briefing and cards based on user state
        response = await generateInitialLoadResponse(data);
      } else {
        // Regular chat or card action
        response = await generateResponse({
          message: data.message || '',
          conversationHistory: data.conversationHistory || [],
          userState: data.userState || {},
          currentTask: data.currentTaskId,
          sessionMetadata: data.sessionMetadata || {
            sessionId: `session-${Date.now()}`,
            messageCount: (data.conversationHistory?.length || 0) + 1,
            firstMessageAt: new Date().toISOString()
          }
        });
      }

      // Log response stats (no content)
      const duration = Date.now() - startTime;
      console.log('peezyRespond completed:', {
        userId,
        requestType,
        duration,
        responseLength: response.text?.length,
        cardsReturned: response.cards?.length || 0,
        hasStateUpdates: !!response.stateUpdates && Object.keys(response.stateUpdates).length > 0,
        vendorsSurfaced: response.internalNotes?.vendorsSurfaced?.length || 0,
        error: response.error || false
      });

      // Add metadata
      response._meta = {
        duration,
        timestamp: new Date().toISOString()
      };

      res.status(200).json(response);

    } catch (error) {
      const duration = Date.now() - startTime;

      console.error('peezyRespond error:', {
        message: error.message,
        stack: error.stack,
        duration
      });

      // Return graceful error
      res.status(500).json({
        text: "Something went sideways on my end. Mind trying that again?",
        error: true,
        retryable: true,
        _meta: {
          duration,
          errorType: 'unhandled'
        }
      });
    }
  }
);

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
      
      // First try: query tasks with active status values
      // iOS writes "Upcoming", workflows use "pending" variants
      // Include "Snoozed" to match TimelineService - iOS will filter based on snoozedUntil
      let tasksSnapshot = await db
        .collection('users')
        .doc(userId)
        .collection('tasks')
        .where('status', 'in', ['Upcoming', 'InProgress', 'pending', 'pending_matching', 'matching_in_progress', 'Snoozed'])
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
    return "All clear! I'll let you know when something comes up.";
  } else if (taskCount === 1) {
    return "Just one thing today - need your input so I can take care of it for you.";
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
