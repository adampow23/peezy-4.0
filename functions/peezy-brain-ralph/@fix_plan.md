# PEEZY BRAIN BUILD ORDER

Prioritized task list for Ralph loop. Complete in order.

---

## PHASE 1: PROJECT SETUP

- [ ] 1.1 Create functions/package.json with dependencies:
  - firebase-functions
  - firebase-admin  
  - @anthropic-ai/sdk
  - dotenv (dev)

- [ ] 1.2 Create tests/jest.config.js

- [ ] 1.3 Create tests/helpers/fixtures.js with user state fixtures for all scenarios

- [ ] 1.4 Create tests/helpers/matchers.js with custom Jest matchers:
  - toBeProactive()
  - toNotBeRobotic()
  - toUseContext()
  - toFollowWorkflow()

- [ ] 1.5 Create tests/helpers/testClient.js with mock harness for testing

- [ ] 1.6 Create functions/.env.example with required vars

---

## PHASE 2: CONTENT FILES

- [ ] 2.1 Create functions/workflows.js with all 40 workflows:
  - LOGISTICS (8): book_movers, book_long_distance_movers, schedule_move_date, truck_rental, coordinate_timing, moving_day_prep, post_move_checklist, handle_moving_issues
  - SERVICES (12): junk_removal, cleaning_service, pet_transport, storage_unit, internet_setup, utility_transfer, home_security, auto_transport, packing_services, handyman_services, appliance_services, furniture_assembly
  - ADMIN (8): change_address, mail_forwarding, school_transfer, update_insurance, dmv_tasks, voter_registration, medical_records, subscription_updates
  - HOUSING (6): landlord_notice, security_deposit, home_inspection, closing_prep, walkthrough, new_home_setup
  - PACKING (6): packing_supplies, declutter, start_packing, pack_fragile, essentials_box, labeling_system

- [ ] 2.2 Create tests/workflows.test.js - verify all 40 workflows exist and have required fields

- [ ] 2.3 Run workflow tests - all must pass

- [ ] 2.4 Create functions/vendorCatalog.js with 50+ vendor categories:
  - Core: movers, long_distance_movers, internet, junk_removal, cleaning, truck_rental
  - Situational: storage, pet_transport, auto_transport, packing_services
  - Property: plumber, hvac, roofing, electrician, home_security, home_warranty, solar, locksmith
  - Specialty: piano_moving, pool_table_moving, hot_tub_moving, art_moving, gun_safe_moving
  - Home Services: home_inspection, pest_control, landscaping, handyman, furniture_assembly, appliance_install
  - Insurance: renters_insurance, homeowners_insurance, auto_insurance
  - Plus 15+ more to reach 50

- [ ] 2.5 Create tests/vendors.test.js - verify all vendors exist and have required fields

- [ ] 2.6 Run vendor tests - all must pass

- [ ] 2.7 Create functions/knowledgeBase.js with:
  - timeline (8 weeks to post-move)
  - costs (by home size and distance)
  - commonMistakes (planning, packing, logistics, move day)
  - conversationTips (overwhelmed, budget, first-timer, experienced, special items, problems)

---

## PHASE 3: SYSTEM PROMPT

- [ ] 3.1 Create functions/systemPrompt.js (~400 lines) with:
  - Complete personality definition
  - Proactive engagement rules
  - Vendor surfacing guidelines (direct, inform, plant_seed)
  - Accountability model messaging
  - Tone and voice (what to say, what not to say)
  - Context usage instructions
  - Response format requirements
  - Edge case handling

- [ ] 3.2 Create tests/behaviors.test.js:
  - Test: never says "how can I help"
  - Test: always includes action or question
  - Test: uses user name appropriately
  - Test: references context
  - Test: follows workflows

---

## PHASE 4: CORE LOGIC

- [ ] 4.1 Create functions/contextBuilder.js:
  - Build context object from userState
  - Compute daysUntilMove
  - Determine urgency level
  - Identify relevant vendors to surface
  - Identify relevant workflow if on task

- [ ] 4.2 Create functions/responseParser.js:
  - Parse LLM response text
  - Extract suggested actions
  - Extract state updates
  - Validate response format

- [ ] 4.3 Create functions/peezyBrain.js:
  - Import systemPrompt, workflows, vendors, knowledge
  - Build full prompt with context
  - Call Anthropic API
  - Parse and validate response
  - Handle errors gracefully

- [ ] 4.4 Create functions/index.js:
  - Export peezyRespond Cloud Function
  - Input validation
  - Rate limiting
  - Error handling wrapper
  - Logging (no PII)

---

## PHASE 5: CORE TESTS

- [ ] 5.1 Create tests/scenarios.test.js with all 20 scenarios from @scenarios.md

- [ ] 5.2 Run scenario tests - fix any failures

- [ ] 5.3 Create tests/edgeCases.test.js:
  - Empty message
  - Very long message (>2000 chars)
  - Missing userState fields
  - Null/undefined values
  - Unicode/emoji in messages
  - Special characters

- [ ] 5.4 Run edge case tests - fix any failures

- [ ] 5.5 Create tests/errors.test.js:
  - API timeout simulation
  - API error simulation
  - Invalid input handling
  - Malformed userState

- [ ] 5.6 Run error tests - fix any failures

---

## PHASE 6: INTEGRATION & PERFORMANCE

- [ ] 6.1 Create tests/integration.test.js:
  - 5+ turn conversation flow
  - State updates persist across turns
  - Context maintained
  - Workflow progression works

- [ ] 6.2 Run integration tests - fix any failures

- [ ] 6.3 Create tests/performance.test.js:
  - Response time < 3 seconds
  - Token count < 2000 average
  - No memory leaks

- [ ] 6.4 Run performance tests - fix any failures

---

## PHASE 7: FINAL VALIDATION

- [ ] 7.1 Run full test suite: npm test
- [ ] 7.2 Verify 100% pass rate
- [ ] 7.3 Check for console errors/warnings
- [ ] 7.4 Verify all files exist per PROMPT.md architecture
- [ ] 7.5 Verify systemPrompt.js is ~400 lines
- [ ] 7.6 Verify workflows.js has 40 workflows
- [ ] 7.7 Verify vendorCatalog.js has 50+ vendors

---

## COMPLETION

When ALL tasks complete and ALL tests pass:

Output: `<promise>BRAIN_COMPLETE</promise>`

---

## STUCK HANDLING

If after 30 iterations tests still fail:
1. Document which tests are failing
2. Document what was attempted
3. List specific blockers
4. Suggest alternative approaches

Do NOT output completion promise if any tests fail.

---

## NOTES

- Run tests frequently (after each file creation)
- Fix failures before moving to next task
- Tests are the source of truth
- Reference @scenarios.md for exact test expectations
- Reference PROMPT.md for specifications
