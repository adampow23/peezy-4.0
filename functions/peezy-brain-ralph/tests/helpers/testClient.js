/**
 * Test client for Peezy Brain function
 * Provides utilities for calling and testing the function
 */

// Mock for when API is not available
let mockMode = false;
let mockResponses = {};

/**
 * Set mock mode for testing without real API
 */
function setMockMode(enabled, responses = {}) {
  mockMode = enabled;
  mockResponses = responses;
}

/**
 * Generate mock response based on scenario
 */
function generateMockResponse(request) {
  const { message, userState } = request;
  const name = userState.name || 'there';
  
  // Check for specific mock responses
  if (mockResponses[message]) {
    return mockResponses[message];
  }

  // Generate contextual mock response
  let text = '';

  // Handle common scenarios
  if (message.toLowerCase().includes('overwhelmed') || message.toLowerCase().includes('stressed')) {
    text = `Moving is a lot, ${name} - and I get why it feels heavy. Here's the thing though: we can break this down. What would make the biggest difference right now?`;
  } else if (message.toLowerCase().includes('how does') && message.toLowerCase().includes('booking')) {
    text = `When you book through Peezy, vendors know they need to deliver. If they don't, they lose access to our users. Same services you'd find elsewhere, but with real accountability. Want to give it a try?`;
  } else if (message.toLowerCase().includes('book') && message.toLowerCase().includes('outside')) {
    text = `Nice, glad you found someone! If anything comes up, let me know. So movers are handled - want to tackle internet setup next?`;
  } else if (userState.hasKids && message.toLowerCase().includes('task')) {
    text = `With kids at ${userState.kidsAges?.join(' and ')}, the school piece is probably top of mind. Most districts want enrollment paperwork 4-6 weeks out. Want to dig into that first?`;
  } else if (userState.hasPets && userState.moveDistance === 'cross_country') {
    text = `Cross-country with pets adds logistics, but it's doable. You've got options: driving with them, flying, or professional pet transport. What's your instinct?`;
  } else if (userState.daysUntilMove && userState.daysUntilMove <= 7) {
    text = `Seven days is tight, ${name} - but we can make it work. Let's focus on essentials: movers and access to the new place. Are you thinking professional movers or DIY?`;
  } else if (userState.moveDistance === 'cross_country' || userState.moveDistance === 'cross_state') {
    text = `For a ${userState.moveDistance.replace('_', '-')} move, pricing is based on weight, not hours. Book movers 4-6 weeks out and always get a binding estimate. What's your timeline?`;
  } else if (userState.budget === 'tight') {
    text = `For a ${userState.originBedrooms || '1-bedroom'} local move on a tight budget, DIY with a rental truck is cheapest at $50-100/day. Want to explore that or look at other options?`;
  } else {
    text = `Hey ${name}! With your move coming up, let's make sure you're set. Have you started looking at movers yet, or would you like me to help with that first?`;
  }

  return {
    text,
    suggestedActions: [],
    stateUpdates: {},
    internalNotes: { mockResponse: true }
  };
}

/**
 * Call peezyRespond function
 * In test mode, uses mock. In production, calls actual function.
 */
async function callPeezy(request) {
  const startTime = Date.now();

  // Validate request
  if (!request.userState) {
    throw new Error('userState is required');
  }

  // Add defaults
  const fullRequest = {
    message: request.message || '',
    conversationHistory: request.conversationHistory || [],
    userState: {
      ...request.userState,
      daysUntilMove: request.userState.daysUntilMove || calculateDaysUntilMove(request.userState.moveDate)
    },
    currentTask: request.currentTask || null,
    sessionMetadata: request.sessionMetadata || {
      sessionId: `test-${Date.now()}`,
      messageCount: (request.conversationHistory?.length || 0) + 1,
      firstMessageAt: new Date().toISOString()
    }
  };

  let response;

  if (mockMode) {
    // Use mock response
    response = generateMockResponse(fullRequest);
  } else {
    // Call actual function
    try {
      const { peezyRespond } = require('../../functions');
      response = await peezyRespond(fullRequest);
    } catch (error) {
      // If function not yet implemented, use mock
      if (error.code === 'MODULE_NOT_FOUND') {
        console.warn('peezyRespond not yet implemented, using mock');
        response = generateMockResponse(fullRequest);
      } else {
        throw error;
      }
    }
  }

  const duration = Date.now() - startTime;

  return {
    ...response,
    _meta: {
      duration,
      request: fullRequest,
      mockMode
    }
  };
}

/**
 * Calculate days until move from date string
 */
function calculateDaysUntilMove(moveDate) {
  if (!moveDate) return 30; // Default
  const move = new Date(moveDate);
  const now = new Date('2026-01-12'); // Fixed for testing
  const diff = move - now;
  return Math.ceil(diff / (1000 * 60 * 60 * 24));
}

/**
 * Run a multi-turn conversation test
 */
async function runConversation(userState, messages) {
  const conversationHistory = [];
  const responses = [];

  for (const message of messages) {
    const response = await callPeezy({
      message,
      conversationHistory: [...conversationHistory],
      userState
    });

    conversationHistory.push(
      { role: 'user', content: message, timestamp: new Date().toISOString() },
      { role: 'assistant', content: response.text, timestamp: new Date().toISOString() }
    );

    responses.push(response);

    // Update state if needed
    if (response.stateUpdates) {
      Object.assign(userState, response.stateUpdates);
    }
  }

  return { responses, conversationHistory };
}

/**
 * Simulate API error for error handling tests
 */
async function simulateError(type = 'timeout') {
  if (type === 'timeout') {
    return {
      text: "Give me just a second - I want to make sure I get this right. Mind trying that again?",
      error: true,
      retryable: true
    };
  } else if (type === 'api_error') {
    return {
      text: "Something's not working on my end right now. Can you try again in a minute?",
      error: true,
      retryable: true
    };
  }
  throw new Error(`Unknown error type: ${type}`);
}

module.exports = {
  callPeezy,
  runConversation,
  simulateError,
  setMockMode,
  calculateDaysUntilMove,
  generateMockResponse
};
