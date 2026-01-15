/**
 * Peezy Brain - Edge Case Tests
 * 
 * Tests handling of unusual inputs and edge cases.
 */

const { callPeezy, setMockMode } = require('./helpers/testClient');
const { fixtures } = require('./helpers/fixtures');
require('./helpers/matchers');

beforeAll(() => {
  setMockMode(false);
});

describe('Peezy Brain - Edge Cases', () => {

  // ============================================
  // EMPTY/MINIMAL INPUT
  // ============================================
  describe('Empty and Minimal Input', () => {
    test('handles empty message gracefully', async () => {
      const { userState } = fixtures.emptyMessage;
      
      const response = await callPeezy({
        message: '',
        conversationHistory: [],
        userState
      });

      // Should not error
      expect(response.text).toBeDefined();
      
      // Should prompt user to share something
      expect(response.text).toMatch(/what|tell|share|mind|thinking/i);
    });

    test('handles whitespace-only message', async () => {
      const { userState } = fixtures.emptyMessage;
      
      const response = await callPeezy({
        message: '   \n\t  ',
        conversationHistory: [],
        userState
      });

      expect(response.text).toBeDefined();
      expect(response.text.length).toBeGreaterThan(10);
    });

    test('handles minimal user state', async () => {
      const response = await callPeezy({
        message: 'Hello',
        conversationHistory: [],
        userState: {
          userId: 'test',
          name: 'Test'
          // Everything else missing
        }
      });

      // Should not error, should provide generic helpful response
      expect(response.text).toBeDefined();
      expect(response.text.length).toBeGreaterThan(20);
    });
  });

  // ============================================
  // VERY LONG INPUT
  // ============================================
  describe('Very Long Input', () => {
    test('handles very long message', async () => {
      const { userState } = fixtures.veryLongMessage;
      const longMessage = 'I need help with my move and here is a lot of context: '.repeat(100);
      
      const response = await callPeezy({
        message: longMessage,
        conversationHistory: [],
        userState
      });

      // Should not error
      expect(response.text).toBeDefined();
      
      // Response should be reasonable length (not echo the long input)
      expect(response.text.length).toBeLessThan(2000);
    });

    test('handles long conversation history', async () => {
      const { userState } = fixtures.newUserFirstMessage;
      
      // Create 50+ turn conversation history
      const history = [];
      for (let i = 0; i < 50; i++) {
        history.push(
          { role: 'user', content: `Message ${i}`, timestamp: new Date().toISOString() },
          { role: 'assistant', content: `Response ${i}`, timestamp: new Date().toISOString() }
        );
      }
      
      const response = await callPeezy({
        message: 'What should I do next?',
        conversationHistory: history,
        userState
      });

      expect(response.text).toBeDefined();
      expect(response).toBeProactive();
    });
  });

  // ============================================
  // SPECIAL CHARACTERS
  // ============================================
  describe('Special Characters', () => {
    test('handles unicode and emoji', async () => {
      const { userState, message } = fixtures.unicodeMessage;
      
      const response = await callPeezy({
        message,
        conversationHistory: [],
        userState
      });

      expect(response.text).toBeDefined();
      expect(response).toNotBeRobotic();
    });

    test('handles special characters in name', async () => {
      const response = await callPeezy({
        message: 'Hello',
        conversationHistory: [],
        userState: {
          userId: 'test',
          name: "O'Brien-McDonald Jr.",
          moveDate: '2026-02-15'
        }
      });

      expect(response.text).toBeDefined();
    });

    test('handles HTML-like content in message', async () => {
      const response = await callPeezy({
        message: '<script>alert("test")</script> I need help moving',
        conversationHistory: [],
        userState: {
          userId: 'test',
          name: 'Test',
          moveDate: '2026-02-15'
        }
      });

      // Should sanitize and respond normally
      expect(response.text).toBeDefined();
      expect(response.text).not.toMatch(/<script>/i);
    });
  });

  // ============================================
  // NULL/UNDEFINED VALUES
  // ============================================
  describe('Null and Undefined Handling', () => {
    test('handles null values in user state', async () => {
      const response = await callPeezy({
        message: 'Hello',
        conversationHistory: [],
        userState: {
          userId: 'test',
          name: 'Test',
          moveDate: null,
          destinationCity: null,
          hasKids: null
        }
      });

      expect(response.text).toBeDefined();
    });

    test('handles undefined optional fields', async () => {
      const response = await callPeezy({
        message: 'Help me with movers',
        conversationHistory: [],
        userState: {
          userId: 'test',
          name: 'Test',
          moveDate: '2026-02-15',
          // All optional fields undefined
          largeItems: undefined,
          petTypes: undefined,
          kidsAges: undefined
        }
      });

      expect(response.text).toBeDefined();
      expect(response).toBeProactive();
    });

    test('handles empty arrays', async () => {
      const response = await callPeezy({
        message: 'What tasks do I have?',
        conversationHistory: [],
        userState: {
          userId: 'test',
          name: 'Test',
          moveDate: '2026-02-15',
          completedTasks: [],
          pendingTasks: [],
          largeItems: [],
          petTypes: []
        }
      });

      expect(response.text).toBeDefined();
    });
  });

  // ============================================
  // DATE EDGE CASES
  // ============================================
  describe('Date Edge Cases', () => {
    test('handles move date in past', async () => {
      const response = await callPeezy({
        message: 'I need help',
        conversationHistory: [],
        userState: {
          userId: 'test',
          name: 'Test',
          moveDate: '2025-01-01', // Past date
          daysUntilMove: -365
        }
      });

      // Should handle gracefully, maybe ask for updated date
      expect(response.text).toBeDefined();
    });

    test('handles move date very far in future', async () => {
      const response = await callPeezy({
        message: 'I want to start planning',
        conversationHistory: [],
        userState: {
          userId: 'test',
          name: 'Test',
          moveDate: '2027-06-01',
          daysUntilMove: 500
        }
      });

      // Should acknowledge the long timeline
      expect(response.text).toBeDefined();
    });

    test('handles move date today', async () => {
      const response = await callPeezy({
        message: 'Help!',
        conversationHistory: [],
        userState: {
          userId: 'test',
          name: 'Test',
          moveDate: '2026-01-12',
          daysUntilMove: 0
        }
      });

      // Should show extreme urgency
      expect(response.text).toBeDefined();
      expect(response.text).toMatch(/today|now|immediate/i);
    });
  });

  // ============================================
  // CONTRADICTORY STATE
  // ============================================
  describe('Contradictory State', () => {
    test('handles contradictory completed/pending tasks', async () => {
      const response = await callPeezy({
        message: 'What should I do about movers?',
        conversationHistory: [],
        userState: {
          userId: 'test',
          name: 'Test',
          moveDate: '2026-02-15',
          completedTasks: ['book_movers'],
          pendingTasks: ['book_movers'] // Contradicts completed
        }
      });

      expect(response.text).toBeDefined();
    });

    test('handles mismatched distance and cities', async () => {
      const response = await callPeezy({
        message: 'Help me plan',
        conversationHistory: [],
        userState: {
          userId: 'test',
          name: 'Test',
          moveDate: '2026-02-15',
          moveDistance: 'local',
          originCity: 'Kansas City',
          destinationCity: 'Seattle' // Not local!
        }
      });

      // Should use most specific info available
      expect(response.text).toBeDefined();
    });
  });

  // ============================================
  // REPEATED MESSAGES
  // ============================================
  describe('Repeated Messages', () => {
    test('handles repeated identical questions', async () => {
      const { userState } = fixtures.newUserFirstMessage;
      
      const history = [
        { role: 'user', content: 'Should I hire movers?', timestamp: '2026-01-12T10:00:00Z' },
        { role: 'assistant', content: 'For most moves, hiring movers is worth it...', timestamp: '2026-01-12T10:00:05Z' }
      ];
      
      const response = await callPeezy({
        message: 'Should I hire movers?', // Same question again
        conversationHistory: history,
        userState
      });

      // Should not fully repeat, should reference previous answer
      expect(response.text).toBeDefined();
      // Ideally would be shorter or reference previous answer
    });
  });

});
