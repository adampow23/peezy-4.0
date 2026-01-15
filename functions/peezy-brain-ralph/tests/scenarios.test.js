/**
 * Peezy Brain - Core Scenarios Tests
 * 
 * Tests all 20 core scenarios from the master plan.
 * Each test verifies specific behaviors that must pass for production readiness.
 */

const { callPeezy, setMockMode } = require('./helpers/testClient');
const { fixtures } = require('./helpers/fixtures');
require('./helpers/matchers');

// Use real API for tests (set to true for mock mode during development)
beforeAll(() => {
  setMockMode(false);
});

describe('Peezy Brain - Core Scenarios', () => {

  // ============================================
  // SCENARIO 1: New User First Message
  // ============================================
  describe('Scenario 1: New User First Message', () => {
    test('responds proactively to new user', async () => {
      const { userState, message, conversationHistory } = fixtures.newUserFirstMessage;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Must NOT be robotic
      expect(response).toNotBeRobotic();

      // Must be proactive (include action or question)
      expect(response).toBeProactive();

      // Must use context (reference their move details)
      expect(response).toUseContext(userState);

      // Must have reasonable length
      expect(response).toHaveReasonableLength({ min: 100, max: 500 });
    });
  });

  // ============================================
  // SCENARIO 2: Stressed User
  // ============================================
  describe('Scenario 2: Stressed User', () => {
    test('acknowledges stress before jumping to tasks', async () => {
      const { userState, message, conversationHistory } = fixtures.stressedUser;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Must acknowledge the emotion FIRST
      expect(response).toAcknowledgeEmotion();

      // Must NOT pile on with a huge list (count bullets/numbers)
      const bulletCount = (response.text.match(/^[\s]*[-•*\d+\.]/gm) || []).length;
      expect(bulletCount).toBeLessThan(4);

      // Must offer ONE clear next step
      expect(response).toBeProactive();

      // Must NOT be robotic
      expect(response).toNotBeRobotic();
    });
  });

  // ============================================
  // SCENARIO 3: Task Guidance (Book Movers)
  // ============================================
  describe('Scenario 3: Task Guidance', () => {
    test('guides through mover booking workflow', async () => {
      const { userState, message, conversationHistory, currentTask } = fixtures.taskGuidanceMovers;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState,
        currentTask
      });

      // Should ask clarifying questions OR provide guided options
      expect(response).toBeProactive();

      // Should reference their context (local, 2-bedroom)
      expect(response).toUseContext(userState);

      // Should NOT just dump a list
      expect(response).toNotBeRobotic();

      // Should mention something workflow-relevant
      expect(response.text).toMatch(/special items|full service|budget|service level|piano|safe/i);
    });
  });

  // ============================================
  // SCENARIO 4: Vendor Surfacing (Explicit)
  // ============================================
  describe('Scenario 4: Vendor Surfacing - Explicit', () => {
    test('handles explicit mover request with accountability pitch', async () => {
      const { userState, message, conversationHistory } = fixtures.vendorSurfacingExplicit;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Should present the case for hiring movers
      expect(response).toMention('mover');

      // Should include accountability pitch (first time)
      expect(response).toIncludeAccountabilityPitch();

      // Should be proactive
      expect(response).toBeProactive();
    });
  });

  // ============================================
  // SCENARIO 5: Vendor Surfacing (Implicit - Old House)
  // ============================================
  describe('Scenario 5: Vendor Surfacing - Implicit', () => {
    test('naturally surfaces plumber for old house', async () => {
      const { userState, message, conversationHistory } = fixtures.vendorSurfacingImplicit;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Should celebrate the milestone
      expect(response.text).toMatch(/congrat|exciting|huge|great|keys/i);

      // Should plant seed about older home (plumbing/electrical)
      expect(response.text).toMatch(/plumb|electric|older|1960s|house.*age|era/i);

      // Should NOT be a hard sell
      expect(response).toNotBeRobotic();

      // Should move conversation forward
      expect(response).toBeProactive();
    });
  });

  // ============================================
  // SCENARIO 6: Accountability Moment
  // ============================================
  describe('Scenario 6: Accountability Moment', () => {
    test('explains accountability when asked about booking', async () => {
      const { userState, message, conversationHistory, currentTask } = fixtures.accountabilityMoment;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState,
        currentTask
      });

      // Should explain accountability model
      expect(response).toIncludeAccountabilityPitch();

      // Should make value prop clear
      expect(response.text.length).toBeGreaterThan(150);

      // Should NOT be vague
      expect(response.text).toMatch(/vendor|book|lose|perform|deliver|account/i);

      // Should end with next step
      expect(response).toBeProactive();
    });
  });

  // ============================================
  // SCENARIO 7: User Books Outside Peezy
  // ============================================
  describe('Scenario 7: User Books Outside', () => {
    test('gracefully handles booking outside platform', async () => {
      const { userState, message, conversationHistory, currentTask } = fixtures.booksOutside;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState,
        currentTask
      });

      // Should acknowledge positively
      expect(response.text).toMatch(/great|good|glad|nice|awesome/i);

      // Should NOT be passive aggressive
      expect(response).toNotBePassiveAggressive();

      // Should move to next task
      expect(response.text).toMatch(/next|else|what about|internet|address/i);

      // Should be proactive
      expect(response).toBeProactive();
    });
  });

  // ============================================
  // SCENARIO 8: Context Reasoning (Date Gap)
  // ============================================
  describe('Scenario 8: Context Reasoning - Date Gap', () => {
    test('proactively surfaces storage for date gap', async () => {
      const { userState, message, conversationHistory } = fixtures.contextReasoningDateGap;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Should notice and address the gap
      expect(response.text).toMatch(/gap|two weeks|storage|between|february|lease|move-in/i);

      // Should be proactive about addressing it
      expect(response).toBeProactive();
    });
  });

  // ============================================
  // SCENARIO 9: Long-Distance Specific
  // ============================================
  describe('Scenario 9: Long-Distance Specific', () => {
    test('gives long-distance specific guidance', async () => {
      const { userState, message, conversationHistory } = fixtures.longDistanceSpecific;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Should include long-distance specific info
      expect(response.text).toMatch(/weight|weeks? (ahead|out)|binding|cross[- ]?country|long[- ]?distance/i);

      // Should NOT give local move advice (hourly rate)
      expect(response).toNotMention('hourly');

      // Should reference their specific route
      expect(response.text).toMatch(/kansas|seattle|1,?800|miles/i);
    });
  });

  // ============================================
  // SCENARIO 10: Kids Context
  // ============================================
  describe('Scenario 10: Kids Context', () => {
    test('surfaces school transfer for family with kids', async () => {
      const { userState, message, conversationHistory } = fixtures.kidsContext;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Should include school-related task
      expect(response.text).toMatch(/school|enroll|transfer|kids|children|8|12/i);

      // Should be proactive
      expect(response).toBeProactive();
    });
  });

  // ============================================
  // SCENARIO 11: Pets Context + Long Distance
  // ============================================
  describe('Scenario 11: Pets + Long Distance', () => {
    test('surfaces pet transport for pets + long distance', async () => {
      const { userState, message, conversationHistory } = fixtures.petsLongDistance;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Should address pet transport
      expect(response.text).toMatch(/pet|dog|cat|transport|travel|fly|drive/i);

      // Should present options
      expect(response).toBeProactive();
    });
  });

  // ============================================
  // SCENARIO 12: Budget-Conscious User
  // ============================================
  describe('Scenario 12: Budget-Conscious', () => {
    test('respects budget constraints', async () => {
      const { userState, message, conversationHistory } = fixtures.budgetConscious;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Should include budget-friendly options
      expect(response.text).toMatch(/budget|cost|save|affordable|DIY|truck rental|cheap/i);

      // Should NOT push premium services first
      expect(response).toNotMention('full[- ]service.*recommend');
      expect(response).toNotMention('premium.*best');
    });
  });

  // ============================================
  // SCENARIO 13: Task Completion
  // ============================================
  describe('Scenario 13: Task Completion', () => {
    test('transitions smoothly after task completion', async () => {
      const { userState, message, conversationHistory } = fixtures.taskCompletion;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Should celebrate/acknowledge
      expect(response.text).toMatch(/great|awesome|nice|done|checked|one less/i);

      // Should transition to next priority
      expect(response.text).toMatch(/next|now|also|what about|internet/i);

      // Should be proactive
      expect(response).toBeProactive();
    });
  });

  // ============================================
  // SCENARIO 14: Off-Topic Redirect
  // ============================================
  describe('Scenario 14: Off-Topic Redirect', () => {
    test('gently redirects off-topic questions', async () => {
      const { userState, message, conversationHistory } = fixtures.offTopicRedirect;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Should redirect to move topics
      expect(response.text).toMatch(/move|focus|help with|packing|task|mover/i);

      // Should be gentle, not dismissive
      expect(response).toNotBeRobotic();

      // Should be proactive
      expect(response).toBeProactive();
    });
  });

  // ============================================
  // SCENARIO 15: Multiple Tasks Mentioned
  // ============================================
  describe('Scenario 15: Multiple Tasks', () => {
    test('prioritizes when multiple tasks mentioned', async () => {
      const { userState, message, conversationHistory } = fixtures.multipleTasks;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Should prioritize
      expect(response.text).toMatch(/first|start|priority|most important|order/i);

      // Should acknowledge others exist
      expect(response.text).toMatch(/then|after|also|get to|other/i);

      // Should be proactive
      expect(response).toBeProactive();
    });
  });

  // ============================================
  // SCENARIO 16: Urgent Timing
  // ============================================
  describe('Scenario 16: Urgent Timing', () => {
    test('shows appropriate urgency for tight timeline', async () => {
      const { userState, message, conversationHistory } = fixtures.urgentTiming;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Should acknowledge urgency
      expect(response.text).toMatch(/week|7 days|soon|tight|quick|urgent/i);

      // Should focus on critical items
      expect(response.text).toMatch(/essential|critical|must|priority|mover|access/i);

      // Should be proactive
      expect(response).toBeProactive();
    });
  });

  // ============================================
  // SCENARIO 17: Question About Peezy
  // ============================================
  describe('Scenario 17: Question About Peezy', () => {
    test('explains Peezy model clearly', async () => {
      const { userState, message, conversationHistory } = fixtures.questionAboutPeezy;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Should explain accountability model
      expect(response).toIncludeAccountabilityPitch();

      // Should NOT be vague
      expect(response.text.length).toBeGreaterThan(150);

      // Should be clear
      expect(response.text).toMatch(/vendor|book|lose|perform|deliver/i);
    });
  });

  // ============================================
  // SCENARIO 18: Repeat Pitch Avoidance
  // ============================================
  describe('Scenario 18: Repeat Pitch Avoidance', () => {
    test('does not repeat accountability pitch', async () => {
      const { userState, message, conversationHistory } = fixtures.repeatPitchAvoidance;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Should NOT repeat the full pitch
      expect(response).toNotRepeatAccountabilityPitch();

      // Should just proceed
      expect(response.text).toMatch(/great|let's|option|which|what|details/i);

      // Should be proactive
      expect(response).toBeProactive();
    });
  });

  // ============================================
  // SCENARIO 19: Error Recovery
  // (Tested in errors.test.js)
  // ============================================

  // ============================================
  // SCENARIO 20: Natural Conversation
  // ============================================
  describe('Scenario 20: Natural Conversation', () => {
    test('maintains natural conversational tone', async () => {
      const { userState, message, conversationHistory } = fixtures.naturalConversation;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Should NOT sound robotic
      expect(response).toNotBeRobotic();

      // Should feel human and warm
      expect(response.text).toMatch(/first|exciting|big deal|you|we|I'll/i);

      // Should acknowledge the milestone/feeling
      expect(response.text).toMatch(/first|solo|own|milestone|exciting/i);

      // Should be proactive
      expect(response).toBeProactive();
    });
  });

});
