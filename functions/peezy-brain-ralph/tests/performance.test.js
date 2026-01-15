/**
 * Peezy Brain - Performance Tests
 * 
 * Tests response time and resource usage.
 */

const { callPeezy, setMockMode } = require('./helpers/testClient');
const { fixtures } = require('./helpers/fixtures');

// Use real API for performance tests
beforeAll(() => {
  setMockMode(false);
});

describe('Peezy Brain - Performance', () => {

  // ============================================
  // RESPONSE TIME
  // ============================================
  describe('Response Time', () => {
    test('responds in under 3 seconds for simple message', async () => {
      const { userState, message, conversationHistory } = fixtures.newUserFirstMessage;
      
      const startTime = Date.now();
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });
      const duration = Date.now() - startTime;

      expect(response.text).toBeDefined();
      expect(duration).toBeLessThan(3000); // 3 seconds
    }, 10000); // 10 second timeout for test

    test('responds in under 3 seconds for complex scenario', async () => {
      const { userState, message, conversationHistory } = fixtures.longDistanceSpecific;
      
      const startTime = Date.now();
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });
      const duration = Date.now() - startTime;

      expect(response.text).toBeDefined();
      expect(duration).toBeLessThan(3000);
    }, 10000);

    test('P95 response time is under 4 seconds', async () => {
      const scenarios = [
        fixtures.newUserFirstMessage,
        fixtures.stressedUser,
        fixtures.taskGuidanceMovers,
        fixtures.vendorSurfacingExplicit,
        fixtures.longDistanceSpecific
      ];

      const durations = [];

      for (const scenario of scenarios) {
        const startTime = Date.now();
        await callPeezy({
          message: scenario.message,
          conversationHistory: scenario.conversationHistory || [],
          userState: scenario.userState
        });
        durations.push(Date.now() - startTime);
      }

      // Sort durations and get P95
      durations.sort((a, b) => a - b);
      const p95Index = Math.floor(durations.length * 0.95);
      const p95Duration = durations[p95Index] || durations[durations.length - 1];

      expect(p95Duration).toBeLessThan(4000); // 4 seconds
    }, 30000); // 30 second timeout for multiple calls
  });

  // ============================================
  // TOKEN EFFICIENCY
  // ============================================
  describe('Token Efficiency', () => {
    test('response length is reasonable', async () => {
      const { userState, message, conversationHistory } = fixtures.newUserFirstMessage;
      
      const response = await callPeezy({
        message,
        conversationHistory,
        userState
      });

      // Response should be concise
      expect(response.text.length).toBeLessThan(1500); // Characters
      expect(response.text.split(/\s+/).length).toBeLessThan(300); // Words
    });

    test('does not include verbose explanations when not needed', async () => {
      const response = await callPeezy({
        message: "Yes",
        conversationHistory: [
          { role: 'user', content: 'Should I book movers?', timestamp: '2026-01-12T10:00:00Z' },
          { role: 'assistant', content: 'For a local move, hiring movers is usually worth it. Want me to help find options?', timestamp: '2026-01-12T10:00:05Z' }
        ],
        userState: fixtures.newUserFirstMessage.userState
      });

      // Simple affirmative should get concise response
      expect(response.text.length).toBeLessThan(500);
    });

    test('average response is under 200 words', async () => {
      const scenarios = [
        fixtures.newUserFirstMessage,
        fixtures.stressedUser,
        fixtures.taskCompletion,
        fixtures.offTopicRedirect
      ];

      const wordCounts = [];

      for (const scenario of scenarios) {
        const response = await callPeezy({
          message: scenario.message,
          conversationHistory: scenario.conversationHistory || [],
          userState: scenario.userState
        });
        wordCounts.push(response.text.split(/\s+/).length);
      }

      const avgWords = wordCounts.reduce((a, b) => a + b, 0) / wordCounts.length;
      expect(avgWords).toBeLessThan(200);
    }, 20000);
  });

  // ============================================
  // CONCURRENT REQUESTS
  // ============================================
  describe('Concurrent Requests', () => {
    test('handles multiple concurrent requests', async () => {
      const scenarios = [
        fixtures.newUserFirstMessage,
        fixtures.stressedUser,
        fixtures.taskGuidanceMovers
      ];

      const promises = scenarios.map(scenario =>
        callPeezy({
          message: scenario.message,
          conversationHistory: scenario.conversationHistory || [],
          userState: scenario.userState
        })
      );

      const responses = await Promise.all(promises);

      // All should succeed
      for (const response of responses) {
        expect(response.text).toBeDefined();
        expect(response.text.length).toBeGreaterThan(20);
      }
    }, 15000);
  });

  // ============================================
  // MEMORY/RESOURCE USAGE
  // ============================================
  describe('Resource Usage', () => {
    test('no memory leak in repeated calls', async () => {
      const initialMemory = process.memoryUsage().heapUsed;

      // Make 10 calls
      for (let i = 0; i < 10; i++) {
        await callPeezy({
          message: `Test message ${i}`,
          conversationHistory: [],
          userState: fixtures.newUserFirstMessage.userState
        });
      }

      const finalMemory = process.memoryUsage().heapUsed;
      const memoryGrowth = finalMemory - initialMemory;

      // Memory growth should be reasonable (under 50MB)
      expect(memoryGrowth).toBeLessThan(50 * 1024 * 1024);
    }, 30000);
  });

});
