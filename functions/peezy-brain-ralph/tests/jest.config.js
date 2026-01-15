/**
 * Jest configuration for Peezy Brain tests
 */

module.exports = {
  // Test environment
  testEnvironment: 'node',

  // Test file patterns
  testMatch: [
    '**/tests/**/*.test.js'
  ],

  // Ignore patterns
  testPathIgnorePatterns: [
    '/node_modules/',
    '/functions/node_modules/'
  ],

  // Setup files
  setupFilesAfterEnv: [
    '<rootDir>/tests/helpers/matchers.js'
  ],

  // Coverage configuration
  collectCoverageFrom: [
    'functions/**/*.js',
    '!functions/node_modules/**'
  ],

  // Timeout for async tests (10 seconds default)
  testTimeout: 10000,

  // Verbose output
  verbose: true,

  // Force exit after tests complete
  forceExit: true,

  // Detect open handles
  detectOpenHandles: true,

  // Module paths
  moduleDirectories: [
    'node_modules',
    'functions/node_modules'
  ],

  // Transform ignore (don't transform node_modules)
  transformIgnorePatterns: [
    '/node_modules/'
  ],

  // Reporter configuration
  reporters: [
    'default',
    ['jest-summary-reporter', { failuresOnly: false }]
  ],

  // Global setup/teardown
  globalSetup: undefined,
  globalTeardown: undefined,

  // Max workers for parallel execution
  maxWorkers: '50%'
};
