# Peezy Brain - Ralph Loop Setup

This directory contains everything needed for the Ralph Wiggum autonomous loop to build Peezy's Firebase brain function.

## Quick Start

### 1. Install Dependencies
```bash
cd peezy-brain-ralph
npm install
cd functions && npm install && cd ..
```

### 2. Set Up Environment
```bash
cp functions/.env.example functions/.env
# Edit functions/.env and add your ANTHROPIC_API_KEY
```

### 3. Run Ralph Loop
```bash
# From Claude Code, run:
/ralph-wiggum:ralph-loop "Complete the Peezy brain implementation following PROMPT.md and @fix_plan.md. Run 'npm test' after each change. Fix failures until all tests pass." --max-iterations 50 --completion-promise "BRAIN_COMPLETE"
```

## Directory Structure

```
peezy-brain-ralph/
├── PROMPT.md              # Complete specification (read first!)
├── @scenarios.md          # Detailed test scenarios
├── @fix_plan.md           # Build order and checklist
├── package.json           # Root package (test scripts)
├── README.md              # This file
│
├── functions/             # Firebase Cloud Functions (TO BE BUILT)
│   ├── package.json       # Function dependencies
│   ├── .env.example       # Environment template
│   ├── index.js           # Main entry (to create)
│   ├── peezyBrain.js      # Core logic (to create)
│   ├── systemPrompt.js    # Personality (~400 lines, to create)
│   ├── workflows.js       # 40 workflows (to create)
│   ├── vendorCatalog.js   # 50+ vendors (to create)
│   ├── knowledgeBase.js   # Expertise (to create)
│   ├── contextBuilder.js  # Context assembly (to create)
│   └── responseParser.js  # Response parsing (to create)
│
└── tests/                 # Test suite (COMPLETE)
    ├── jest.config.js     # Jest configuration
    ├── scenarios.test.js  # 20 core scenarios
    ├── behaviors.test.js  # Behavioral tests
    ├── vendors.test.js    # Vendor catalog tests
    ├── workflows.test.js  # Workflow tests
    ├── edgeCases.test.js  # Edge case handling
    ├── errors.test.js     # Error handling
    ├── integration.test.js # Multi-turn tests
    ├── performance.test.js # Timing tests
    └── helpers/
        ├── fixtures.js    # User state fixtures
        ├── matchers.js    # Custom Jest matchers
        └── testClient.js  # Test harness
```

## Test Commands

```bash
# Run all tests
npm test

# Run specific test suites
npm run test:scenarios     # 20 core scenarios
npm run test:behaviors     # Behavioral tests
npm run test:vendors       # Vendor catalog
npm run test:workflows     # Workflow definitions
npm run test:edge          # Edge cases
npm run test:errors        # Error handling
npm run test:integration   # Multi-turn conversations
npm run test:performance   # Response timing

# Watch mode
npm run test:watch

# With coverage
npm run test:coverage
```

## Success Criteria

The implementation is complete when:
1. `npm test` shows 100% pass rate
2. All 20 core scenarios pass
3. All behavior tests pass
4. All vendor/workflow definitions are complete
5. Response time < 3 seconds

## Files To Build

The Ralph loop needs to create these files in `functions/`:

| File | Lines | Purpose |
|------|-------|---------|
| systemPrompt.js | ~400 | Complete Peezy personality |
| workflows.js | ~600 | 40 task workflows |
| vendorCatalog.js | ~500 | 50+ vendor categories |
| knowledgeBase.js | ~400 | Moving expertise |
| contextBuilder.js | ~150 | Build LLM context |
| responseParser.js | ~100 | Parse responses |
| peezyBrain.js | ~200 | Core logic |
| index.js | ~100 | Cloud Function export |

## Key Behaviors to Implement

1. **Proactive**: Lead conversations, never "how can I help?"
2. **Context-aware**: Use all user state in responses
3. **Vendor surfacing**: Direct, inform, or plant seed
4. **Accountability**: Pitch once, then brief references
5. **Natural tone**: Warm, concise, human

## Completion

When all tests pass, output:
```
<promise>BRAIN_COMPLETE</promise>
```

## Troubleshooting

**Tests failing on import:**
- Make sure the function files are created with proper exports
- Check `module.exports = { ... }` syntax

**API errors:**
- Verify ANTHROPIC_API_KEY in .env
- Check network connectivity

**Timeout errors:**
- Tests have 10 second timeout by default
- May need to increase for integration tests
