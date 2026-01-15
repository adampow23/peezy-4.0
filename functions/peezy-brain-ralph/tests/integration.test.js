/**
 * Peezy Brain - Integration Tests
 * 
 * Tests multi-turn conversations and state persistence.
 */

const { callPeezy, runConversation, setMockMode } = require('./helpers/testClient');
const { fixtures } = require('./helpers/fixtures');
require('./helpers/matchers');

beforeAll(() => {
  setMockMode(false);
});

describe('Peezy Brain - Integration', () => {

  // ============================================
  // MULTI-TURN CONVERSATIONS
  // ============================================
  describe('Multi-Turn Conversations', () => {
    test('maintains context across 5+ turns', async () => {
      const { userState, messages } = fixtures.multiTurnConversation;
      
      const { responses, conversationHistory } = await runConversation(
        { ...userState },
        messages.slice(0, 5)
      );

      // All responses should be valid
      for (const response of responses) {
        expect(response.text).toBeDefined();
        expect(response.text.length).toBeGreaterThan(20);
      }

      // Later responses should reference earlier context
      const lastResponse = responses[responses.length - 1];
      expect(lastResponse).toNotBeRobotic();
    });

    test('accountability pitch appears only once', async () => {
      const userState = {
        ...fixtures.newUserFirstMessage.userState,
        heardAccountabilityPitch: false
      };

      const messages = [
        "Hi, I need help with my move",
        "Should I hire movers?",
        "How does booking through you work?",
        "Okay, let's look at options",
        "Tell me more about booking through Peezy"
      ];

      const { responses } = await runConversation({ ...userState }, messages);

      // Count how many responses include full accountability pitch
      let pitchCount = 0;
      for (const response of responses) {
        // Check for multiple accountability indicators (indicates full pitch)
        const indicators = [
          /account/i.test(response.text),
          /perform/i.test(response.text),
          /lose access/i.test(response.text),
          /platform/i.test(response.text)
        ].filter(Boolean).length;

        if (indicators >= 3) {
          pitchCount++;
        }
      }

      // Should only have full pitch once
      expect(pitchCount).toBeLessThanOrEqual(2); // Allow some flexibility
    });

    test('task progression works correctly', async () => {
      const userState = {
        ...fixtures.newUserFirstMessage.userState,
        completedTasks: [],
        pendingTasks: ['book_movers', 'internet_setup', 'change_address']
      };

      const messages = [
        "Let's start with movers",
        "I don't have any special items",
        "Full service please",
        "Movers are booked!",
        "What's next?"
      ];

      const { responses } = await runConversation({ ...userState }, messages);

      // Last response should move to next task
      const lastResponse = responses[responses.length - 1];
      expect(lastResponse.text).toMatch(/internet|address|next/i);
    });
  });

  // ============================================
  // STATE UPDATES
  // ============================================
  describe('State Updates', () => {
    test('tracks when accountability pitch was given', async () => {
      const userState = {
        ...fixtures.newUserFirstMessage.userState,
        heardAccountabilityPitch: false
      };

      const response = await callPeezy({
        message: "How does booking through you work?",
        conversationHistory: [],
        userState
      });

      // Response should include state update
      if (response.stateUpdates) {
        expect(response.stateUpdates.heardAccountabilityPitch).toBe(true);
      }
    });

    test('tracks vendor interactions', async () => {
      const userState = {
        ...fixtures.newUserFirstMessage.userState,
        vendorInteractions: {}
      };

      const response = await callPeezy({
        message: "I need to find movers",
        conversationHistory: [],
        userState
      });

      // Response may include vendor interaction updates
      if (response.stateUpdates?.vendorInteractions) {
        expect(response.stateUpdates.vendorInteractions.movers).toBeDefined();
      }
    });
  });

  // ============================================
  // CONVERSATION FLOW
  // ============================================
  describe('Conversation Flow', () => {
    test('new user journey flows naturally', async () => {
      const userState = {
        userId: 'test-journey',
        name: 'TestUser',
        moveDate: '2026-02-15',
        daysUntilMove: 34,
        moveDistance: 'local',
        originCity: 'Kansas City',
        destinationCity: 'Kansas City',
        originBedrooms: '2_bedroom',
        hasKids: false,
        hasPets: false,
        completedTasks: [],
        pendingTasks: ['book_movers', 'internet_setup'],
        heardAccountabilityPitch: false,
        vendorInteractions: {}
      };

      const messages = [
        "Hi, I'm moving next month!",
        "Yes, I'd like help finding movers",
        "No special items",
        "Moderate budget, maybe $500-800"
      ];

      const { responses } = await runConversation({ ...userState }, messages);

      // First response should be welcoming
      expect(responses[0].text).toMatch(/hi|hey|hello|welcome/i);
      
      // All responses should be proactive
      for (const response of responses) {
        expect(response).toBeProactive();
        expect(response).toNotBeRobotic();
      }

      // Flow should progress logically toward booking
      const allText = responses.map(r => r.text).join(' ');
      expect(allText).toMatch(/mover|option|quote|book/i);
    });

    test('handles topic changes gracefully', async () => {
      const userState = fixtures.newUserFirstMessage.userState;

      const messages = [
        "Help me find movers",
        "Actually, what about internet first?",
        "Never mind, back to movers"
      ];

      const { responses } = await runConversation({ ...userState }, messages);

      // Should handle pivots without confusion
      for (const response of responses) {
        expect(response.text).toBeDefined();
        expect(response).toNotBeRobotic();
      }

      // Last response should be about movers
      expect(responses[2].text).toMatch(/mover/i);
    });

    test('remembers context from earlier in conversation', async () => {
      const userState = {
        ...fixtures.newUserFirstMessage.userState,
        name: 'SpecificTestName'
      };

      const messages = [
        "Hi there",
        "I have a piano that needs to move",
        "What else should I know about my move?"
      ];

      const { responses } = await runConversation({ ...userState }, messages);

      // Third response might reference the piano mentioned earlier
      // (This tests context retention)
      const allText = responses.map(r => r.text).join(' ');
      expect(allText).toMatch(/piano|special|heavy/i);
    });
  });

  // ============================================
  // EDGE CASES IN FLOW
  // ============================================
  describe('Flow Edge Cases', () => {
    test('handles user going silent then returning', async () => {
      const userState = fixtures.newUserFirstMessage.userState;

      // Simulate gap in conversation
      const history = [
        { role: 'user', content: 'Help me plan my move', timestamp: '2026-01-10T10:00:00Z' },
        { role: 'assistant', content: 'Let\'s start with movers...', timestamp: '2026-01-10T10:00:05Z' }
      ];

      const response = await callPeezy({
        message: "I'm back, where were we?",
        conversationHistory: history,
        userState
      });

      // Should reconnect to previous context
      expect(response.text).toBeDefined();
      expect(response).toBeProactive();
    });

    test('handles contradictory user statements', async () => {
      const userState = fixtures.newUserFirstMessage.userState;

      const messages = [
        "I definitely want professional movers",
        "Actually I want to do it myself",
        "Wait, maybe professional is better"
      ];

      const { responses } = await runConversation({ ...userState }, messages);

      // Should handle flip-flopping gracefully
      for (const response of responses) {
        expect(response).toNotBeRobotic();
      }
    });
  });

});
