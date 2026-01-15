/**
 * Custom Jest matchers for Peezy Brain tests
 */

// Patterns that indicate robotic/bad responses
const ROBOTIC_PATTERNS = [
  /how can I help/i,
  /what would you like to do/i,
  /let me know if you have questions/i,
  /is there anything else/i,
  /I am here to assist/i,
  /I am an AI/i,
  /I am programmed/i,
  /Great question!/i,
  /I hope this helps/i,
  /As an AI/i,
  /I don't have access to/i,
  /I cannot access/i,
  /I'm just an AI/i,
  /I'm a language model/i
];

// Passive-aggressive patterns (for books outside scenario)
const PASSIVE_AGGRESSIVE_PATTERNS = [
  /too bad/i,
  /wish you had/i,
  /should have/i,
  /could have/i,
  /if only you/i,
  /next time/i,
  /unfortunately you/i
];

// Accountability pitch patterns
const ACCOUNTABILITY_PATTERNS = [
  /account/i,
  /perform/i,
  /lose access/i,
  /platform/i,
  /deliver/i,
  /consequences/i,
  /vetted/i
];

// Proactive patterns - responses should have action orientation
const PROACTIVE_PATTERNS = [
  /\?$/, // Ends with question mark
  /want to/i,
  /let's/i,
  /should we/i,
  /how about/i,
  /what about/i,
  /next/i,
  /first/i,
  /start with/i,
  /I can/i,
  /I'll/i
];

const customMatchers = {
  /**
   * Assert response is not robotic
   */
  toNotBeRobotic(received) {
    const text = typeof received === 'string' ? received : received.text;
    const matchedPatterns = [];

    for (const pattern of ROBOTIC_PATTERNS) {
      if (pattern.test(text)) {
        matchedPatterns.push(pattern.toString());
      }
    }

    const pass = matchedPatterns.length === 0;

    return {
      pass,
      message: () =>
        pass
          ? `Expected response to be robotic but it wasn't`
          : `Expected response to not be robotic but found patterns: ${matchedPatterns.join(', ')}\n\nResponse: "${text.substring(0, 200)}..."`
    };
  },

  /**
   * Assert response is proactive (includes action or question)
   */
  toBeProactive(received) {
    const text = typeof received === 'string' ? received : received.text;
    
    const hasQuestion = text.includes('?');
    const hasActionWord = PROACTIVE_PATTERNS.some(p => p.test(text));
    const pass = hasQuestion || hasActionWord;

    return {
      pass,
      message: () =>
        pass
          ? `Expected response to not be proactive but it was`
          : `Expected response to be proactive (include question or action) but it didn't.\n\nResponse: "${text.substring(0, 200)}..."`
    };
  },

  /**
   * Assert response uses context from user state
   */
  toUseContext(received, userState) {
    const text = typeof received === 'string' ? received : received.text;
    const textLower = text.toLowerCase();

    const contextUsed = [];
    const contextMissed = [];

    // Check name usage (optional, so just track if used)
    if (userState.name && textLower.includes(userState.name.toLowerCase())) {
      contextUsed.push('name');
    }

    // Check city reference
    if (userState.destinationCity && textLower.includes(userState.destinationCity.toLowerCase())) {
      contextUsed.push('destinationCity');
    }
    if (userState.originCity && textLower.includes(userState.originCity.toLowerCase())) {
      contextUsed.push('originCity');
    }

    // Check time reference
    if (/\d+ (days?|weeks?|month)/i.test(text)) {
      contextUsed.push('timeReference');
    }

    // Check move distance reference
    if (userState.moveDistance) {
      const distancePatterns = {
        'local': /local/i,
        'cross_state': /cross[- ]?state|interstate/i,
        'cross_country': /cross[- ]?country|long[- ]?distance|coast/i
      };
      if (distancePatterns[userState.moveDistance]?.test(text)) {
        contextUsed.push('moveDistance');
      }
    }

    // Check bedroom reference
    if (userState.originBedrooms && text.toLowerCase().includes('bedroom')) {
      contextUsed.push('bedrooms');
    }

    // At least one piece of context should be used
    const pass = contextUsed.length > 0;

    return {
      pass,
      message: () =>
        pass
          ? `Expected response to not use context but it used: ${contextUsed.join(', ')}`
          : `Expected response to use context from user state but found no context usage.\n\nAvailable context: name=${userState.name}, city=${userState.destinationCity || userState.originCity}, distance=${userState.moveDistance}\n\nResponse: "${text.substring(0, 200)}..."`
    };
  },

  /**
   * Assert response is not passive aggressive
   */
  toNotBePassiveAggressive(received) {
    const text = typeof received === 'string' ? received : received.text;
    const matchedPatterns = [];

    for (const pattern of PASSIVE_AGGRESSIVE_PATTERNS) {
      if (pattern.test(text)) {
        matchedPatterns.push(pattern.toString());
      }
    }

    const pass = matchedPatterns.length === 0;

    return {
      pass,
      message: () =>
        pass
          ? `Expected response to be passive aggressive but it wasn't`
          : `Expected response to not be passive aggressive but found: ${matchedPatterns.join(', ')}\n\nResponse: "${text.substring(0, 200)}..."`
    };
  },

  /**
   * Assert response includes accountability pitch
   */
  toIncludeAccountabilityPitch(received) {
    const text = typeof received === 'string' ? received : received.text;
    
    const matchedPatterns = ACCOUNTABILITY_PATTERNS.filter(p => p.test(text));
    const pass = matchedPatterns.length >= 2; // Need at least 2 indicators

    return {
      pass,
      message: () =>
        pass
          ? `Expected response to not include accountability pitch but it did`
          : `Expected response to include accountability pitch (need 2+ indicators) but found only: ${matchedPatterns.length}\n\nResponse: "${text.substring(0, 200)}..."`
    };
  },

  /**
   * Assert response does NOT include full accountability pitch (for repeat avoidance)
   */
  toNotRepeatAccountabilityPitch(received) {
    const text = typeof received === 'string' ? received : received.text;
    
    // Check for the full pitch - multiple accountability concepts together
    const matchedPatterns = ACCOUNTABILITY_PATTERNS.filter(p => p.test(text));
    
    // If 3+ indicators, it's probably repeating the pitch
    const pass = matchedPatterns.length < 3;

    return {
      pass,
      message: () =>
        pass
          ? `Expected response to repeat accountability pitch but it didn't`
          : `Expected response to NOT repeat full accountability pitch but found ${matchedPatterns.length} indicators\n\nResponse: "${text.substring(0, 200)}..."`
    };
  },

  /**
   * Assert response has reasonable length
   */
  toHaveReasonableLength(received, { min = 50, max = 2000 } = {}) {
    const text = typeof received === 'string' ? received : received.text;
    const length = text.length;
    const pass = length >= min && length <= max;

    return {
      pass,
      message: () =>
        pass
          ? `Expected response length to be outside ${min}-${max} but was ${length}`
          : `Expected response length to be between ${min}-${max} but was ${length}\n\nResponse: "${text.substring(0, 100)}..."`
    };
  },

  /**
   * Assert response acknowledges emotion (for stressed user)
   */
  toAcknowledgeEmotion(received) {
    const text = typeof received === 'string' ? received : received.text;
    
    const emotionPatterns = [
      /overwhelm/i,
      /stress/i,
      /lot/i,
      /understand/i,
      /get it/i,
      /makes sense/i,
      /heavy/i,
      /tough/i,
      /hard/i,
      /I hear you/i,
      /feel/i
    ];

    const matched = emotionPatterns.some(p => p.test(text));

    return {
      pass: matched,
      message: () =>
        matched
          ? `Expected response to not acknowledge emotion but it did`
          : `Expected response to acknowledge emotion but it didn't\n\nResponse: "${text.substring(0, 200)}..."`
    };
  },

  /**
   * Assert response mentions specific topic
   */
  toMention(received, topic) {
    const text = typeof received === 'string' ? received : received.text;
    const pattern = new RegExp(topic, 'i');
    const pass = pattern.test(text);

    return {
      pass,
      message: () =>
        pass
          ? `Expected response to not mention "${topic}" but it did`
          : `Expected response to mention "${topic}" but it didn't\n\nResponse: "${text.substring(0, 200)}..."`
    };
  },

  /**
   * Assert response does NOT mention specific topic
   */
  toNotMention(received, topic) {
    const text = typeof received === 'string' ? received : received.text;
    const pattern = new RegExp(topic, 'i');
    const pass = !pattern.test(text);

    return {
      pass,
      message: () =>
        pass
          ? `Expected response to mention "${topic}" but it didn't`
          : `Expected response to NOT mention "${topic}" but it did\n\nResponse: "${text.substring(0, 200)}..."`
    };
  }
};

// Extend Jest with custom matchers
expect.extend(customMatchers);

module.exports = { customMatchers, ROBOTIC_PATTERNS, ACCOUNTABILITY_PATTERNS, PROACTIVE_PATTERNS };
