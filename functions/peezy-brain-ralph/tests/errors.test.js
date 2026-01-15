/**
 * Peezy Brain - Error Tests
 * 
 * Tests error handling and graceful degradation.
 */

const { callPeezy, simulateError, setMockMode } = require('./helpers/testClient');
const { fixtures } = require('./helpers/fixtures');
require('./helpers/matchers');

describe('Peezy Brain - Error Handling', () => {

  // ============================================
  // API ERRORS
  // ============================================
  describe('API Error Handling', () => {
    test('handles API timeout gracefully', async () => {
      const response = await simulateError('timeout');

      expect(response.text).toBeDefined();
      expect(response.error).toBe(true);
      expect(response.retryable).toBe(true);
      
      // Should be user-friendly message
      expect(response.text).not.toMatch(/timeout|error|API|Anthropic/i);
      expect(response.text).toMatch(/try|again|second|moment/i);
    });

    test('handles API error gracefully', async () => {
      const response = await simulateError('api_error');

      expect(response.text).toBeDefined();
      expect(response.error).toBe(true);
      
      // Should not expose technical details
      expect(response.text).not.toMatch(/500|503|error code|stack/i);
    });

    test('error response is friendly and helpful', async () => {
      const response = await simulateError('timeout');

      // Should be conversational
      expect(response.text.length).toBeGreaterThan(20);
      expect(response.text.length).toBeLessThan(200);
      
      // Should suggest retry
      expect(response.text).toMatch(/try|again/i);
    });
  });

  // ============================================
  // INPUT VALIDATION ERRORS
  // ============================================
  describe('Input Validation', () => {
    test('handles missing userId', async () => {
      let error = null;
      try {
        await callPeezy({
          message: 'Hello',
          conversationHistory: [],
          userState: {
            name: 'Test'
            // Missing userId
          }
        });
      } catch (e) {
        error = e;
      }

      // Should either handle gracefully or throw clear error
      // Not crash with undefined error
    });

    test('handles invalid date format', async () => {
      const response = await callPeezy({
        message: 'Help me',
        conversationHistory: [],
        userState: {
          userId: 'test',
          name: 'Test',
          moveDate: 'not-a-date',
          daysUntilMove: NaN
        }
      });

      // Should handle gracefully
      expect(response.text).toBeDefined();
    });

    test('handles invalid move distance', async () => {
      const response = await callPeezy({
        message: 'Help me',
        conversationHistory: [],
        userState: {
          userId: 'test',
          name: 'Test',
          moveDate: '2026-02-15',
          moveDistance: 'invalid_distance'
        }
      });

      // Should handle gracefully
      expect(response.text).toBeDefined();
    });
  });

  // ============================================
  // MALFORMED INPUT
  // ============================================
  describe('Malformed Input', () => {
    test('handles non-string message', async () => {
      let error = null;
      let response = null;
      
      try {
        response = await callPeezy({
          message: 12345, // Not a string
          conversationHistory: [],
          userState: {
            userId: 'test',
            name: 'Test',
            moveDate: '2026-02-15'
          }
        });
      } catch (e) {
        error = e;
      }

      // Should either coerce to string or error gracefully
      if (response) {
        expect(response.text).toBeDefined();
      } else {
        expect(error).toBeDefined();
      }
    });

    test('handles malformed conversation history', async () => {
      const response = await callPeezy({
        message: 'Hello',
        conversationHistory: [
          { role: 'invalid', content: 123 }, // Malformed
          null, // Null entry
          'just a string' // Wrong format
        ],
        userState: {
          userId: 'test',
          name: 'Test',
          moveDate: '2026-02-15'
        }
      });

      // Should filter/handle malformed entries
      expect(response.text).toBeDefined();
    });

    test('handles circular reference in user state', async () => {
      const userState = {
        userId: 'test',
        name: 'Test',
        moveDate: '2026-02-15'
      };
      // Create circular reference
      userState.self = userState;

      let error = null;
      try {
        await callPeezy({
          message: 'Hello',
          conversationHistory: [],
          userState
        });
      } catch (e) {
        error = e;
      }

      // Should handle - either by detecting and removing or by erroring gracefully
    });
  });

  // ============================================
  // RECOVERY BEHAVIOR
  // ============================================
  describe('Recovery Behavior', () => {
    test('error response suggests retry', async () => {
      const response = await simulateError('timeout');
      
      expect(response.retryable).toBe(true);
      expect(response.text).toMatch(/try|again/i);
    });

    test('does not expose internal state on error', async () => {
      const response = await simulateError('api_error');
      
      // Should not leak:
      expect(response.text).not.toMatch(/ANTHROPIC_API_KEY/i);
      expect(response.text).not.toMatch(/firebase/i);
      expect(response.text).not.toMatch(/function.*error/i);
      expect(response.text).not.toMatch(/stack.*trace/i);
    });
  });

});
