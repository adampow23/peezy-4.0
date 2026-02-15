/**
 * Peezy Brain - Response Parser
 * Parses and validates LLM responses
 */

/**
 * Parse raw LLM response into structured format
 */
function parseResponse(rawResponse, context) {
  // Handle string response from Anthropic
  const text = typeof rawResponse === 'string' 
    ? rawResponse 
    : rawResponse?.content?.[0]?.text || rawResponse?.text || '';
  
  // Initialize response object
  const response = {
    text: cleanResponseText(text),
    suggestedActions: [],
    stateUpdates: {},
    internalNotes: {
      workflowUsed: context?.currentTask || null,
      vendorsSurfaced: [],
      contextFactorsApplied: []
    }
  };
  
  // Detect vendor mentions
  response.internalNotes.vendorsSurfaced = detectVendorMentions(response.text);
  
  // Detect if accountability pitch was given
  if (shouldUpdateAccountabilityPitch(response.text, context)) {
    response.stateUpdates.heardAccountabilityPitch = true;
  }
  
  // Detect vendor interactions
  const vendorUpdates = detectVendorInteractions(response.text, context);
  if (Object.keys(vendorUpdates).length > 0) {
    response.stateUpdates.vendorInteractions = vendorUpdates;
  }
  
  // Detect task completions from conversation
  const taskCompletions = detectTaskCompletions(response.text, context);
  if (taskCompletions.length > 0) {
    response.stateUpdates.completedTasks = taskCompletions;
  }
  
  // Extract suggested actions
  response.suggestedActions = extractSuggestedActions(response.text, context);
  
  // Track context factors used
  response.internalNotes.contextFactorsApplied = detectContextUsage(response.text, context);
  
  return response;
}

/**
 * Clean up response text
 */
function cleanResponseText(text) {
  if (!text) return '';
  
  let cleaned = text
    .trim()
    // Remove any XML-like tags that might slip through
    .replace(/<\/?[a-z]+>/gi, '')
    // Normalize whitespace
    .replace(/[^\S\n]+/g, ' ')
    // Clean up multiple periods
    .replace(/\.{2,}/g, '.')
    // Clean up excessive newlines
    .replace(/\n{3,}/g, '\n\n');
  
  return cleaned;
}

/**
 * Detect vendor mentions in response text
 */
function detectVendorMentions(text) {
  const vendorPatterns = {
    movers: /\b(movers?|moving company|moving companies)\b/i,
    internet: /\b(internet|wifi|cable|fiber|broadband)\b/i,
    cleaning: /\b(clean(ers?|ing)?|maid service)\b/i,
    storage: /\b(storage|store your stuff)\b/i,
    junk_removal: /\b(junk removal|haul away|get rid of)\b/i,
    pet_transport: /\b(pet transport|ship.*pet|pet.*service)\b/i,
    auto_transport: /\b(car shipping|auto transport|vehicle transport)\b/i,
    packing_services: /\b(packers?|packing service)\b/i,
    locksmith: /\b(locksmith|change.*locks?|new locks?)\b/i,
    plumber: /\b(plumb(er|ing))\b/i,
    electrician: /\b(electric(ian|al))\b/i,
    handyman: /\b(handyman|handy.*service)\b/i,
    piano_moving: /\b(piano.*mov(e|ing)|mov(e|ing).*piano)\b/i
  };
  
  const mentioned = [];
  
  for (const [vendor, pattern] of Object.entries(vendorPatterns)) {
    if (pattern.test(text)) {
      mentioned.push(vendor);
    }
  }
  
  return mentioned;
}

/**
 * Determine if accountability pitch was given
 */
function shouldUpdateAccountabilityPitch(text, context) {
  // Don't update if already heard
  if (context?.heardAccountabilityPitch) return false;
  
  // Look for key pitch indicators
  const pitchIndicators = [
    /vendors?\s+know\s+they\s+need\s+to\s+(deliver|perform)/i,
    /lose\s+access\s+to\s+(peezy|our)\s+users?/i,
    /accountability/i,
    /consequences\s+if\s+they\s+(mess|screw)\s+up/i,
    /same\s+services?.*but\s+with\s+(real\s+)?accountability/i,
    /motivated\s+to\s+(perform|deliver|show\s+up)/i
  ];
  
  let matchCount = 0;
  for (const pattern of pitchIndicators) {
    if (pattern.test(text)) matchCount++;
  }
  
  // Need at least 2 indicators to count as full pitch
  return matchCount >= 2;
}

/**
 * Detect vendor interactions from response
 */
function detectVendorInteractions(text, context) {
  const updates = {};
  
  // Check for booking offers
  const bookingPatterns = [
    { pattern: /get\s+(some\s+)?quotes?\s+(for\s+)?movers?/i, vendor: 'movers' },
    { pattern: /set\s+up\s+(your\s+)?internet/i, vendor: 'internet' },
    { pattern: /book\s+(the\s+)?clean(ers?|ing)/i, vendor: 'cleaning' },
    { pattern: /get\s+a\s+storage\s+unit/i, vendor: 'storage' },
    { pattern: /schedule\s+junk\s+removal/i, vendor: 'junk_removal' }
  ];
  
  for (const { pattern, vendor } of bookingPatterns) {
    if (pattern.test(text)) {
      updates[vendor] = {
        ...context?.vendorInteractions?.[vendor],
        mentioned: true
      };
    }
  }
  
  return updates;
}

/**
 * Detect task completions from conversation
 */
function detectTaskCompletions(text, context) {
  const completions = [];
  const userMessage = context?.message?.toLowerCase() || '';
  
  // Common completion phrases
  const completionPatterns = [
    { pattern: /movers?\s+(are\s+)?booked/i, task: 'book_movers' },
    { pattern: /internet\s+is\s+set\s+up/i, task: 'internet_setup' },
    { pattern: /forwarding\s+mail/i, task: 'mail_forwarding' },
    { pattern: /gave\s+notice/i, task: 'landlord_notice' },
    { pattern: /registered\s+to\s+vote/i, task: 'voter_registration' }
  ];
  
  for (const { pattern, task } of completionPatterns) {
    if (pattern.test(userMessage) && !context?.completedTasks?.includes(task)) {
      completions.push(task);
    }
  }
  
  return completions;
}

/**
 * Extract suggested actions from response
 */
function extractSuggestedActions(text, context) {
  const actions = [];
  
  // Booking suggestions
  if (/want\s+(me\s+to\s+)?(get\s+)?quotes?/i.test(text)) {
    actions.push({
      type: 'book_vendor',
      vendorCategory: detectPrimaryVendor(text),
      metadata: { suggested: true }
    });
  }
  
  // Task suggestions
  if (/want\s+to\s+(start|tackle|work\s+on)/i.test(text)) {
    const taskMatch = text.match(/start\s+with\s+(the\s+)?(\w+)/i);
    if (taskMatch) {
      actions.push({
        type: 'show_info',
        taskId: taskMatch[2],
        metadata: { suggested: true }
      });
    }
  }
  
  // Questions
  if (text.includes('?')) {
    actions.push({
      type: 'ask_question',
      metadata: { hasQuestion: true }
    });
  }
  
  return actions;
}

/**
 * Detect primary vendor being discussed
 */
function detectPrimaryVendor(text) {
  const vendorPriority = [
    { pattern: /mover/i, vendor: 'movers' },
    { pattern: /internet|wifi/i, vendor: 'internet' },
    { pattern: /clean/i, vendor: 'cleaning' },
    { pattern: /storage/i, vendor: 'storage' },
    { pattern: /junk/i, vendor: 'junk_removal' },
    { pattern: /piano/i, vendor: 'piano_moving' }
  ];
  
  for (const { pattern, vendor } of vendorPriority) {
    if (pattern.test(text)) return vendor;
  }
  
  return null;
}

/**
 * Detect which context factors were used in response
 */
function detectContextUsage(text, context) {
  const factors = [];
  const textLower = text.toLowerCase();
  
  // Name usage
  if (context?.userName && textLower.includes(context.userName.toLowerCase())) {
    factors.push('userName');
  }
  
  // City reference
  if (context?.originCity && textLower.includes(context.originCity.toLowerCase())) {
    factors.push('originCity');
  }
  if (context?.destinationCity && textLower.includes(context.destinationCity.toLowerCase())) {
    factors.push('destinationCity');
  }
  
  // Timeline reference
  if (/\d+\s+(day|week|month)/i.test(text)) {
    factors.push('timeline');
  }
  
  // Distance reference
  if (/local|cross[- ]?(state|country)|long[- ]?distance/i.test(text)) {
    factors.push('moveDistance');
  }
  
  // Budget reference
  if (/budget|cost|price|cheap|affordable|expensive/i.test(text)) {
    factors.push('budget');
  }
  
  // Kids reference
  if (/kid|child|school/i.test(text) && context?.hasKids) {
    factors.push('hasKids');
  }
  
  // Pet reference
  if (/pet|dog|cat|animal/i.test(text) && context?.hasPets) {
    factors.push('hasPets');
  }
  
  // Bedroom reference
  if (/bedroom|\d-?bed|\d\s?br/i.test(text)) {
    factors.push('bedrooms');
  }
  
  return factors;
}

/**
 * Validate response meets quality criteria
 */
function validateResponse(response) {
  const issues = [];
  
  // Check for robotic patterns
  const roboticPatterns = [
    /how can I help/i,
    /what would you like/i,
    /let me know if you have questions/i,
    /I am here to assist/i,
    /Great question!/i,
    /I hope this helps/i
  ];
  
  for (const pattern of roboticPatterns) {
    if (pattern.test(response.text)) {
      issues.push(`Robotic pattern detected: ${pattern}`);
    }
  }
  
  // Check for proactive content
  const hasQuestion = response.text.includes('?');
  const hasAction = /want|let's|should|how about|next|first|start/i.test(response.text);
  if (!hasQuestion && !hasAction) {
    issues.push('Response lacks proactive content (no question or action)');
  }
  
  // Check length
  if (response.text.length < 20) {
    issues.push('Response too short');
  }
  if (response.text.length > 2000) {
    issues.push('Response too long');
  }
  
  return {
    valid: issues.length === 0,
    issues
  };
}

// Export
module.exports = {
  parseResponse,
  cleanResponseText,
  detectVendorMentions,
  shouldUpdateAccountabilityPitch,
  detectVendorInteractions,
  detectTaskCompletions,
  extractSuggestedActions,
  detectContextUsage,
  validateResponse
};
