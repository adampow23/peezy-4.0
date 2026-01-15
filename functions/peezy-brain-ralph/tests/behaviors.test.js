/**
 * Peezy Brain - Behavior Tests
 * 
 * Tests core behavioral requirements that apply across all interactions.
 */

const { callPeezy, setMockMode } = require('./helpers/testClient');
const { fixtures } = require('./helpers/fixtures');
require('./helpers/matchers');

beforeAll(() => {
  setMockMode(false);
});

describe('Peezy Brain - Core Behaviors', () => {

  // ============================================
  // PROACTIVE ENGAGEMENT
  // ============================================
  describe('Proactive Engagement', () => {
    test('never says "how can I help"', async () => {
      const responses = await Promise.all([
        callPeezy(fixtures.newUserFirstMessage),
        callPeezy(fixtures.taskGuidanceMovers),
        callPeezy(fixtures.naturalConversation)
      ]);

      for (const response of responses) {
        expect(response.text).not.toMatch(/how can I help/i);
        expect(response.text).not.toMatch(/what would you like/i);
        expect(response.text).not.toMatch(/what can I do for you/i);
      }
    });

    test('always includes action item or question', async () => {
      const responses = await Promise.all([
        callPeezy(fixtures.newUserFirstMessage),
        callPeezy(fixtures.stressedUser),
        callPeezy(fixtures.taskCompletion),
        callPeezy(fixtures.offTopicRedirect)
      ]);

      for (const response of responses) {
        expect(response).toBeProactive();
      }
    });

    test('never ends passively', async () => {
      const responses = await Promise.all([
        callPeezy(fixtures.newUserFirstMessage),
        callPeezy(fixtures.taskGuidanceMovers),
        callPeezy(fixtures.vendorSurfacingExplicit)
      ]);

      for (const response of responses) {
        // Should not end with passive statements
        expect(response.text).not.toMatch(/let me know if you have questions\.?\s*$/i);
        expect(response.text).not.toMatch(/I hope this helps\.?\s*$/i);
        expect(response.text).not.toMatch(/feel free to ask\.?\s*$/i);
      }
    });
  });

  // ============================================
  // CONTEXT USAGE
  // ============================================
  describe('Context Usage', () => {
    test('uses user name appropriately', async () => {
      // Name should be used but not excessively
      const response = await callPeezy(fixtures.newUserFirstMessage);
      
      const nameCount = (response.text.match(new RegExp(fixtures.newUserFirstMessage.userState.name, 'gi')) || []).length;
      
      // Should use name 0-2 times per response
      expect(nameCount).toBeLessThanOrEqual(2);
    });

    test('references move timeline', async () => {
      const responses = await Promise.all([
        callPeezy(fixtures.urgentTiming),
        callPeezy(fixtures.longDistanceSpecific)
      ]);

      // Urgent timeline should mention days/weeks
      expect(responses[0].text).toMatch(/\d+ (day|week)/i);
      
      // Long distance should reference timeline for booking
      expect(responses[1].text).toMatch(/week|month|time|soon|early/i);
    });

    test('adapts to budget constraints', async () => {
      const budgetResponse = await callPeezy(fixtures.budgetConscious);
      const normalResponse = await callPeezy(fixtures.taskGuidanceMovers);

      // Budget response should mention cost-saving options
      expect(budgetResponse.text).toMatch(/budget|cost|save|DIY|cheap|affordable/i);

      // Normal response should not overly focus on budget
      // (It's okay to mention, but shouldn't be the focus)
    });

    test('adjusts for move distance', async () => {
      const longDistance = await callPeezy(fixtures.longDistanceSpecific);
      const local = await callPeezy(fixtures.taskGuidanceMovers);

      // Long distance should have different advice
      expect(longDistance.text).toMatch(/weight|binding|4-6 weeks/i);
      
      // Local should not mention weight-based pricing
      expect(local.text).not.toMatch(/weight.based/i);
    });
  });

  // ============================================
  // TONE AND PERSONALITY
  // ============================================
  describe('Tone and Personality', () => {
    test('never sounds robotic', async () => {
      const responses = await Promise.all([
        callPeezy(fixtures.newUserFirstMessage),
        callPeezy(fixtures.stressedUser),
        callPeezy(fixtures.naturalConversation),
        callPeezy(fixtures.booksOutside)
      ]);

      for (const response of responses) {
        expect(response).toNotBeRobotic();
      }
    });

    test('uses contractions naturally', async () => {
      const responses = await Promise.all([
        callPeezy(fixtures.newUserFirstMessage),
        callPeezy(fixtures.taskGuidanceMovers)
      ]);

      // Should use at least some contractions
      const allText = responses.map(r => r.text).join(' ');
      expect(allText).toMatch(/(you're|I'll|that's|it's|don't|won't|can't|we'll|they're|what's)/i);
    });

    test('acknowledges emotions when present', async () => {
      const stressedResponse = await callPeezy(fixtures.stressedUser);
      const excitedResponse = await callPeezy(fixtures.vendorSurfacingImplicit); // Got keys

      expect(stressedResponse).toAcknowledgeEmotion();
      
      // Excited response should celebrate
      expect(excitedResponse.text).toMatch(/congrat|exciting|huge|great|awesome/i);
    });

    test('avoids excessive exclamation points', async () => {
      const responses = await Promise.all([
        callPeezy(fixtures.newUserFirstMessage),
        callPeezy(fixtures.taskCompletion),
        callPeezy(fixtures.vendorSurfacingImplicit)
      ]);

      for (const response of responses) {
        const exclamationCount = (response.text.match(/!/g) || []).length;
        expect(exclamationCount).toBeLessThanOrEqual(3);
      }
    });

    test('avoids bullet points in conversational responses', async () => {
      const responses = await Promise.all([
        callPeezy(fixtures.newUserFirstMessage),
        callPeezy(fixtures.stressedUser),
        callPeezy(fixtures.naturalConversation)
      ]);

      for (const response of responses) {
        const bulletCount = (response.text.match(/^[\s]*[-•*]\s/gm) || []).length;
        expect(bulletCount).toBeLessThanOrEqual(3); // Allow a few, but not lists
      }
    });
  });

  // ============================================
  // WORKFLOW ADHERENCE
  // ============================================
  describe('Workflow Adherence', () => {
    test('follows mover booking workflow', async () => {
      const response = await callPeezy(fixtures.taskGuidanceMovers);

      // Should ask about workflow-relevant things
      expect(response.text).toMatch(/(special items|piano|safe|full service|budget|how much|service level)/i);
    });

    test('gathers information before making recommendations', async () => {
      const response = await callPeezy(fixtures.taskGuidanceMovers);

      // Should ask questions, not just recommend
      expect(response.text).toMatch(/\?/);
    });
  });

  // ============================================
  // RESPONSE FORMAT
  // ============================================
  describe('Response Format', () => {
    test('returns valid response structure', async () => {
      const response = await callPeezy(fixtures.newUserFirstMessage);

      expect(response).toHaveProperty('text');
      expect(typeof response.text).toBe('string');
      expect(response.text.length).toBeGreaterThan(0);
    });

    test('response length is reasonable', async () => {
      const responses = await Promise.all([
        callPeezy(fixtures.newUserFirstMessage),
        callPeezy(fixtures.stressedUser),
        callPeezy(fixtures.taskGuidanceMovers),
        callPeezy(fixtures.questionAboutPeezy)
      ]);

      for (const response of responses) {
        expect(response).toHaveReasonableLength({ min: 50, max: 1500 });
      }
    });
  });

});
