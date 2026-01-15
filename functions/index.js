/**
 * Peezy Brain - Firebase Cloud Function
 * Main entry point for the Peezy conversational AI
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onRequest } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const admin = require('firebase-admin');
const { generateResponse, validateContentLoaded } = require('./peezyBrain');
const { getWorkflowQualifying, submitWorkflowAnswers } = require('./getWorkflowQualifying');

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
    moveDistance: data.userState?.moveDistance,
    daysUntilMove: data.userState?.daysUntilMove
  };
}

/**
 * Main peezyRespond Cloud Function
 *
 * Expected input:
 * {
 *   message: string,
 *   conversationHistory: Message[],
 *   userState: UserState,
 *   currentTask?: string,
 *   sessionMetadata?: { sessionId, messageCount, firstMessageAt }
 * }
 *
 * Returns:
 * {
 *   text: string,
 *   suggestedActions?: Action[],
 *   stateUpdates?: Partial<UserState>,
 *   internalNotes?: object
 * }
 */
exports.peezyRespond = onCall(
  {
    timeoutSeconds: 30,
    memory: '512MiB'
  },
  async (request) => {
    const startTime = Date.now();
    const data = request.data;
    const context = request;

    try {
      // Log request (sanitized)
      console.log('peezyRespond called:', sanitizeForLogging(data));

      // Validate content is loaded
      const contentCheck = validateContentLoaded();
      if (!contentCheck.valid) {
        console.error('Content not properly loaded:', contentCheck.checks);
        throw new HttpsError(
          'internal',
          'Service configuration error'
        );
      }

      // Get user ID for rate limiting
      const userId = data.userState?.userId || context.auth?.uid || 'anonymous';

      // Check rate limit
      if (!checkRateLimit(userId)) {
        console.warn('Rate limit exceeded for user:', userId);
        return {
          text: "You're moving fast! Give me a moment to catch up. Try again in a few seconds.",
          error: true,
          retryable: true,
          _meta: { rateLimited: true }
        };
      }

      // Generate response
      const response = await generateResponse({
        message: data.message || '',
        conversationHistory: data.conversationHistory || [],
        userState: data.userState || {},
        currentTask: data.currentTask,
        sessionMetadata: data.sessionMetadata || {
          sessionId: `session-${Date.now()}`,
          messageCount: (data.conversationHistory?.length || 0) + 1,
          firstMessageAt: new Date().toISOString()
        }
      });

      // Log response stats (no content)
      const duration = Date.now() - startTime;
      console.log('peezyRespond completed:', {
        userId,
        duration,
        responseLength: response.text?.length,
        hasStateUpdates: !!response.stateUpdates && Object.keys(response.stateUpdates).length > 0,
        vendorsSurfaced: response.internalNotes?.vendorsSurfaced?.length || 0,
        error: response.error || false
      });

      // Add metadata
      response._meta = {
        duration,
        timestamp: new Date().toISOString()
      };

      return response;

    } catch (error) {
      const duration = Date.now() - startTime;

      console.error('peezyRespond error:', {
        message: error.message,
        code: error.code,
        duration
      });

      // Return graceful error
      if (error instanceof HttpsError) {
        throw error;
      }

      // Generic error response
      return {
        text: "Something went sideways on my end. Mind trying that again?",
        error: true,
        retryable: true,
        _meta: {
          duration,
          errorType: 'unhandled'
        }
      };
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
