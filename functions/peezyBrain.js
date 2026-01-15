/**
 * Peezy Brain - Core Logic
 * Main response generation using Anthropic Claude
 */

const Anthropic = require('@anthropic-ai/sdk');
const { buildSystemPrompt } = require('./systemPrompt');
const { buildContext, buildConversationHistory, sanitizeInput, validateRequest } = require('./contextBuilder');
const { parseResponse, validateResponse } = require('./responseParser');
const { WORKFLOWS } = require('./workflows');
const { VENDORS } = require('./vendorCatalog');
const { KNOWLEDGE } = require('./knowledgeBase');

// Initialize Anthropic client
let anthropic = null;

function getAnthropicClient() {
  if (!anthropic) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      throw new Error('ANTHROPIC_API_KEY environment variable is required');
    }
    anthropic = new Anthropic({ apiKey });
  }
  return anthropic;
}

// Default configuration
const DEFAULT_CONFIG = {
  model: process.env.ANTHROPIC_MODEL || 'claude-sonnet-4-20250514',
  maxTokens: parseInt(process.env.MAX_TOKENS) || 1024,
  temperature: 0.7,
  timeout: parseInt(process.env.REQUEST_TIMEOUT) || 25000
};

/**
 * Main function to generate Peezy response
 */
async function generateResponse(request) {
  // Validate request
  const validation = validateRequest(request);
  if (!validation.valid) {
    throw new Error(`Invalid request: ${validation.errors.join(', ')}`);
  }
  
  // Handle empty message
  const message = sanitizeInput(request.message);
  if (!message || message.trim().length === 0) {
    return {
      text: "What's on your mind about the move?",
      suggestedActions: [],
      stateUpdates: {},
      internalNotes: { emptyMessage: true }
    };
  }
  
  // Build context (NOW ASYNC - fetches from Firestore)
  const context = await buildContext({
    ...request,
    message
  });
  
  // Log data source for debugging
  if (context._dataSource) {
    console.log('Context data sources:', context._dataSource);
  }
  
  // Build system prompt
  const systemPrompt = buildSystemPrompt(context);
  
  // Build conversation messages
  const conversationHistory = buildConversationHistory(request.conversationHistory);
  const messages = [
    ...conversationHistory.map(msg => ({
      role: msg.role,
      content: msg.content
    })),
    {
      role: 'user',
      content: message
    }
  ];
  
  // Call Anthropic API
  try {
    const client = getAnthropicClient();
    
    const response = await client.messages.create({
      model: DEFAULT_CONFIG.model,
      max_tokens: DEFAULT_CONFIG.maxTokens,
      system: systemPrompt,
      messages
    });
    
    // Parse response
    const parsedResponse = parseResponse(response, context);
    
    // Validate response quality
    const responseValidation = validateResponse(parsedResponse);
    if (!responseValidation.valid && process.env.DEBUG_MODE === 'true') {
      console.warn('Response quality issues:', responseValidation.issues);
    }
    
    return parsedResponse;
    
  } catch (error) {
    return handleError(error, context);
  }
}

/**
 * Handle errors gracefully
 */
function handleError(error, context) {
  console.error('Peezy Brain error:', error.message);
  
  // Rate limit error
  if (error.status === 429) {
    return {
      text: "I'm getting a lot of requests right now. Give me a sec and try again?",
      error: true,
      retryable: true,
      internalNotes: { errorType: 'rate_limit' }
    };
  }
  
  // Timeout error
  if (error.code === 'ETIMEDOUT' || error.message?.includes('timeout')) {
    return {
      text: "Give me just a second - I want to make sure I get this right. Mind trying that again?",
      error: true,
      retryable: true,
      internalNotes: { errorType: 'timeout' }
    };
  }
  
  // API error
  if (error.status >= 500) {
    return {
      text: "Something's not working on my end right now. Can you try again in a minute?",
      error: true,
      retryable: true,
      internalNotes: { errorType: 'api_error' }
    };
  }
  
  // Authentication error
  if (error.status === 401) {
    console.error('API key issue - check ANTHROPIC_API_KEY');
    return {
      text: "Having a technical issue on my end. The team's been notified.",
      error: true,
      retryable: false,
      internalNotes: { errorType: 'auth_error' }
    };
  }
  
  // Generic error
  return {
    text: "Something went sideways. Try sending that again?",
    error: true,
    retryable: true,
    internalNotes: { errorType: 'unknown', message: error.message }
  };
}

/**
 * Get workflow by ID (exposed for testing)
 */
function getWorkflow(id) {
  return WORKFLOWS[id] || null;
}

/**
 * Get vendor by ID (exposed for testing)
 */
function getVendor(id) {
  return VENDORS[id] || null;
}

/**
 * Get knowledge section (exposed for testing)
 */
function getKnowledge(section) {
  return KNOWLEDGE[section] || null;
}

/**
 * Check if all content is loaded (for testing)
 */
function validateContentLoaded() {
  const checks = {
    workflowCount: Object.keys(WORKFLOWS).length,
    vendorCount: Object.keys(VENDORS).length,
    hasTimeline: !!KNOWLEDGE.timeline,
    hasCosts: !!KNOWLEDGE.costs,
    hasCommonMistakes: !!KNOWLEDGE.commonMistakes,
    hasConversationTips: !!KNOWLEDGE.conversationTips
  };
  
  return {
    valid: checks.workflowCount >= 40 && 
           checks.vendorCount >= 50 && 
           checks.hasTimeline && 
           checks.hasCosts &&
           checks.hasCommonMistakes &&
           checks.hasConversationTips,
    checks
  };
}

// Export
module.exports = {
  generateResponse,
  handleError,
  getWorkflow,
  getVendor,
  getKnowledge,
  validateContentLoaded,
  DEFAULT_CONFIG
};