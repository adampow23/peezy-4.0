/**
 * Test fixtures for Peezy Brain tests
 * User states for all 20 core scenarios + additional test cases
 */

const BASE_DATE = '2026-01-12'; // Current date for test calculations

function daysFromNow(days) {
  const date = new Date(BASE_DATE);
  date.setDate(date.getDate() + days);
  return date.toISOString().split('T')[0];
}

const fixtures = {
  // ============================================
  // CORE 20 SCENARIOS
  // ============================================

  // Scenario 1: New user, first message
  newUserFirstMessage: {
    userState: {
      userId: 'test-user-1',
      name: 'Sarah',
      email: 'sarah@test.com',
      moveDate: daysFromNow(34),
      daysUntilMove: 34,
      moveDistance: 'cross_state',
      originCity: 'Kansas City',
      originState: 'MO',
      originPropertyType: 'apartment',
      originOwnership: 'rent',
      originBedrooms: '2_bedroom',
      destinationCity: 'Denver',
      destinationState: 'CO',
      destinationPropertyType: 'apartment',
      destinationOwnership: 'rent',
      householdSize: 2,
      hasKids: false,
      hasPets: false,
      completedTasks: [],
      skippedTasks: [],
      pendingTasks: ['book_movers', 'internet_setup', 'change_address'],
      heardAccountabilityPitch: false,
      vendorInteractions: {},
      createdAt: BASE_DATE,
      lastActiveAt: BASE_DATE,
      assessmentCompletedAt: BASE_DATE
    },
    message: "Hi, I'm moving next month",
    conversationHistory: []
  },

  // Scenario 2: Stressed user
  stressedUser: {
    userState: {
      userId: 'test-user-2',
      name: 'Mike',
      email: 'mike@test.com',
      moveDate: daysFromNow(13),
      daysUntilMove: 13,
      moveDistance: 'local',
      originCity: 'Kansas City',
      originState: 'MO',
      destinationCity: 'Kansas City',
      destinationState: 'MO',
      originPropertyType: 'apartment',
      originOwnership: 'rent',
      originBedrooms: '2_bedroom',
      destinationPropertyType: 'apartment',
      destinationOwnership: 'rent',
      householdSize: 1,
      hasKids: false,
      hasPets: false,
      completedTasks: [],
      skippedTasks: [],
      pendingTasks: ['book_movers', 'internet_setup', 'change_address', 'packing'],
      heardAccountabilityPitch: false,
      vendorInteractions: {},
      createdAt: BASE_DATE,
      lastActiveAt: BASE_DATE,
      assessmentCompletedAt: BASE_DATE
    },
    message: "I'm so overwhelmed with this move",
    conversationHistory: []
  },

  // Scenario 3: Task guidance (book movers)
  taskGuidanceMovers: {
    userState: {
      userId: 'test-user-3',
      name: 'Lisa',
      email: 'lisa@test.com',
      moveDate: daysFromNow(48),
      daysUntilMove: 48,
      moveDistance: 'local',
      originCity: 'Kansas City',
      originState: 'MO',
      destinationCity: 'Kansas City',
      destinationState: 'MO',
      originPropertyType: 'apartment',
      originOwnership: 'rent',
      originBedrooms: '2_bedroom',
      destinationPropertyType: 'apartment',
      destinationOwnership: 'rent',
      householdSize: 2,
      hasKids: false,
      hasPets: false,
      largeItems: [],
      budget: 'moderate',
      completedTasks: [],
      pendingTasks: ['book_movers'],
      heardAccountabilityPitch: false,
      vendorInteractions: {}
    },
    currentTask: 'book_movers',
    message: "I need to find movers",
    conversationHistory: []
  },

  // Scenario 4: Vendor surfacing (explicit)
  vendorSurfacingExplicit: {
    userState: {
      userId: 'test-user-4',
      name: 'Tom',
      email: 'tom@test.com',
      moveDate: daysFromNow(39),
      daysUntilMove: 39,
      moveDistance: 'local',
      originCity: 'Kansas City',
      originState: 'MO',
      destinationCity: 'Kansas City',
      destinationState: 'MO',
      originPropertyType: 'apartment',
      originOwnership: 'rent',
      originBedrooms: '2_bedroom',
      destinationPropertyType: 'apartment',
      destinationOwnership: 'rent',
      householdSize: 1,
      hasKids: false,
      hasPets: false,
      completedTasks: [],
      pendingTasks: ['book_movers'],
      heardAccountabilityPitch: false,
      vendorInteractions: {}
    },
    message: "Should I hire movers?",
    conversationHistory: []
  },

  // Scenario 5: Vendor surfacing (implicit - old house)
  vendorSurfacingImplicit: {
    userState: {
      userId: 'test-user-5',
      name: 'Rachel',
      email: 'rachel@test.com',
      moveDate: daysFromNow(47),
      daysUntilMove: 47,
      moveDistance: 'local',
      originCity: 'Kansas City',
      originState: 'MO',
      destinationCity: 'Kansas City',
      destinationState: 'MO',
      originPropertyType: 'apartment',
      originOwnership: 'rent',
      originBedrooms: '2_bedroom',
      destinationPropertyType: 'house',
      destinationOwnership: 'own',
      destinationYearBuilt: 1965,
      destinationNotes: 'fixer upper, needs some work',
      householdSize: 2,
      hasKids: false,
      hasPets: false,
      completedTasks: [],
      pendingTasks: ['book_movers'],
      heardAccountabilityPitch: false,
      vendorInteractions: {}
    },
    message: "Just got the keys to the new place!",
    conversationHistory: []
  },

  // Scenario 6: Accountability moment
  accountabilityMoment: {
    userState: {
      userId: 'test-user-6',
      name: 'David',
      email: 'david@test.com',
      moveDate: daysFromNow(34),
      daysUntilMove: 34,
      moveDistance: 'local',
      originCity: 'Kansas City',
      destinationCity: 'Kansas City',
      originPropertyType: 'apartment',
      originBedrooms: '2_bedroom',
      householdSize: 1,
      hasKids: false,
      hasPets: false,
      completedTasks: [],
      pendingTasks: ['book_movers'],
      heardAccountabilityPitch: false,
      vendorInteractions: {}
    },
    currentTask: 'book_movers',
    message: "How do I book through you?",
    conversationHistory: []
  },

  // Scenario 7: User books outside Peezy
  booksOutside: {
    userState: {
      userId: 'test-user-7',
      name: 'Emma',
      email: 'emma@test.com',
      moveDate: daysFromNow(39),
      daysUntilMove: 39,
      moveDistance: 'local',
      originCity: 'Kansas City',
      destinationCity: 'Kansas City',
      originPropertyType: 'apartment',
      originBedrooms: '2_bedroom',
      householdSize: 1,
      hasKids: false,
      hasPets: false,
      completedTasks: [],
      pendingTasks: ['book_movers', 'internet_setup'],
      heardAccountabilityPitch: true,
      vendorInteractions: {}
    },
    currentTask: 'book_movers',
    message: "I found movers on Yelp and already booked them",
    conversationHistory: []
  },

  // Scenario 8: Context reasoning (date gap)
  contextReasoningDateGap: {
    userState: {
      userId: 'test-user-8',
      name: 'Chris',
      email: 'chris@test.com',
      moveDate: daysFromNow(34),
      daysUntilMove: 34,
      leaseEndDate: daysFromNow(20), // Feb 1
      moveDateType: 'Out Before In',
      moveDistance: 'local',
      originCity: 'Kansas City',
      destinationCity: 'Kansas City',
      originPropertyType: 'apartment',
      originOwnership: 'rent',
      originBedrooms: '2_bedroom',
      destinationPropertyType: 'apartment',
      destinationOwnership: 'rent',
      householdSize: 1,
      hasKids: false,
      hasPets: false,
      completedTasks: [],
      pendingTasks: ['book_movers', 'storage_unit'],
      heardAccountabilityPitch: false,
      vendorInteractions: { storage: { mentioned: false } }
    },
    message: "Just confirmed my move-in date",
    conversationHistory: []
  },

  // Scenario 9: Long-distance specific
  longDistanceSpecific: {
    userState: {
      userId: 'test-user-9',
      name: 'Amy',
      email: 'amy@test.com',
      moveDate: daysFromNow(48),
      daysUntilMove: 48,
      moveDistance: 'cross_country',
      originCity: 'Kansas City',
      originState: 'MO',
      destinationCity: 'Seattle',
      destinationState: 'WA',
      originPropertyType: 'apartment',
      originOwnership: 'rent',
      originBedrooms: '3_bedroom',
      destinationPropertyType: 'apartment',
      destinationOwnership: 'rent',
      householdSize: 2,
      hasKids: false,
      hasPets: false,
      completedTasks: [],
      pendingTasks: ['book_movers'],
      heardAccountabilityPitch: false,
      vendorInteractions: {}
    },
    message: "What should I know about my move?",
    conversationHistory: []
  },

  // Scenario 10: Kids context
  kidsContext: {
    userState: {
      userId: 'test-user-10',
      name: 'Jennifer',
      email: 'jennifer@test.com',
      moveDate: daysFromNow(34),
      daysUntilMove: 34,
      moveDistance: 'cross_state',
      originCity: 'Kansas City',
      originState: 'MO',
      destinationCity: 'Denver',
      destinationState: 'CO',
      originPropertyType: 'house',
      originOwnership: 'own',
      originBedrooms: '4_bedroom',
      destinationPropertyType: 'house',
      destinationOwnership: 'own',
      householdSize: 4,
      hasKids: true,
      kidsAges: ['8', '12'],
      hasPets: false,
      completedTasks: [],
      pendingTasks: ['book_movers', 'school_transfer'],
      heardAccountabilityPitch: false,
      vendorInteractions: {}
    },
    message: "What tasks should I be thinking about?",
    conversationHistory: []
  },

  // Scenario 11: Pets context + long distance
  petsLongDistance: {
    userState: {
      userId: 'test-user-11',
      name: 'Brian',
      email: 'brian@test.com',
      moveDate: daysFromNow(48),
      daysUntilMove: 48,
      moveDistance: 'cross_country',
      originCity: 'Kansas City',
      originState: 'MO',
      destinationCity: 'Portland',
      destinationState: 'OR',
      originPropertyType: 'house',
      originOwnership: 'own',
      originBedrooms: '3_bedroom',
      destinationPropertyType: 'house',
      destinationOwnership: 'rent',
      householdSize: 2,
      hasKids: false,
      hasPets: true,
      petTypes: ['dog', 'cat'],
      completedTasks: [],
      pendingTasks: ['book_movers', 'pet_transport'],
      heardAccountabilityPitch: false,
      vendorInteractions: {}
    },
    message: "I'm worried about the logistics",
    conversationHistory: []
  },

  // Scenario 12: Budget-conscious user
  budgetConscious: {
    userState: {
      userId: 'test-user-12',
      name: 'Kevin',
      email: 'kevin@test.com',
      moveDate: daysFromNow(34),
      daysUntilMove: 34,
      moveDistance: 'local',
      originCity: 'Kansas City',
      destinationCity: 'Kansas City',
      originPropertyType: 'apartment',
      originOwnership: 'rent',
      originBedrooms: '1_bedroom',
      destinationPropertyType: 'apartment',
      destinationOwnership: 'rent',
      householdSize: 1,
      hasKids: false,
      hasPets: false,
      budget: 'tight',
      budgetNotes: 'trying to keep costs minimal',
      completedTasks: [],
      pendingTasks: ['book_movers'],
      heardAccountabilityPitch: false,
      vendorInteractions: {}
    },
    message: "What are my options for moving?",
    conversationHistory: []
  },

  // Scenario 13: Task completion
  taskCompletion: {
    userState: {
      userId: 'test-user-13',
      name: 'Nicole',
      email: 'nicole@test.com',
      moveDate: daysFromNow(39),
      daysUntilMove: 39,
      moveDistance: 'local',
      originCity: 'Kansas City',
      destinationCity: 'Kansas City',
      originPropertyType: 'apartment',
      originBedrooms: '2_bedroom',
      householdSize: 1,
      hasKids: false,
      hasPets: false,
      completedTasks: ['book_movers'],
      pendingTasks: ['internet_setup', 'change_address'],
      heardAccountabilityPitch: true,
      vendorInteractions: { movers: { booked: true } }
    },
    message: "Movers are booked!",
    conversationHistory: []
  },

  // Scenario 14: Off-topic redirect
  offTopicRedirect: {
    userState: {
      userId: 'test-user-14',
      name: 'Steve',
      email: 'steve@test.com',
      moveDate: daysFromNow(34),
      daysUntilMove: 34,
      moveDistance: 'local',
      originCity: 'Kansas City',
      destinationCity: 'Kansas City',
      originPropertyType: 'apartment',
      originBedrooms: '2_bedroom',
      householdSize: 1,
      hasKids: false,
      hasPets: false,
      completedTasks: [],
      pendingTasks: ['book_movers'],
      heardAccountabilityPitch: false,
      vendorInteractions: {}
    },
    message: "What's the weather going to be like?",
    conversationHistory: []
  },

  // Scenario 15: Multiple tasks mentioned
  multipleTasks: {
    userState: {
      userId: 'test-user-15',
      name: 'Laura',
      email: 'laura@test.com',
      moveDate: daysFromNow(29),
      daysUntilMove: 29,
      moveDistance: 'local',
      originCity: 'Kansas City',
      destinationCity: 'Kansas City',
      originPropertyType: 'apartment',
      originBedrooms: '2_bedroom',
      householdSize: 1,
      hasKids: false,
      hasPets: false,
      completedTasks: [],
      pendingTasks: ['book_movers', 'cleaning_service', 'internet_setup', 'packing'],
      heardAccountabilityPitch: false,
      vendorInteractions: {}
    },
    message: "What about movers and cleaning and internet and packing?",
    conversationHistory: []
  },

  // Scenario 16: Urgent timing
  urgentTiming: {
    userState: {
      userId: 'test-user-16',
      name: 'Mark',
      email: 'mark@test.com',
      moveDate: daysFromNow(7),
      daysUntilMove: 7,
      moveDistance: 'local',
      originCity: 'Kansas City',
      destinationCity: 'Kansas City',
      originPropertyType: 'apartment',
      originBedrooms: '2_bedroom',
      householdSize: 1,
      hasKids: false,
      hasPets: false,
      completedTasks: [],
      pendingTasks: ['book_movers', 'internet_setup', 'change_address', 'packing'],
      heardAccountabilityPitch: false,
      vendorInteractions: {}
    },
    message: "I need to figure out my move",
    conversationHistory: []
  },

  // Scenario 17: Question about Peezy
  questionAboutPeezy: {
    userState: {
      userId: 'test-user-17',
      name: 'Susan',
      email: 'susan@test.com',
      moveDate: daysFromNow(34),
      daysUntilMove: 34,
      moveDistance: 'local',
      originCity: 'Kansas City',
      destinationCity: 'Kansas City',
      originPropertyType: 'apartment',
      originBedrooms: '2_bedroom',
      householdSize: 1,
      hasKids: false,
      hasPets: false,
      completedTasks: [],
      pendingTasks: ['book_movers'],
      heardAccountabilityPitch: false,
      vendorInteractions: {}
    },
    message: "How does booking through you work?",
    conversationHistory: []
  },

  // Scenario 18: Repeat pitch avoidance
  repeatPitchAvoidance: {
    userState: {
      userId: 'test-user-18',
      name: 'Paul',
      email: 'paul@test.com',
      moveDate: daysFromNow(34),
      daysUntilMove: 34,
      moveDistance: 'local',
      originCity: 'Kansas City',
      destinationCity: 'Kansas City',
      originPropertyType: 'apartment',
      originBedrooms: '2_bedroom',
      householdSize: 1,
      hasKids: false,
      hasPets: false,
      completedTasks: [],
      pendingTasks: ['book_movers'],
      heardAccountabilityPitch: true, // Already heard it
      vendorInteractions: {}
    },
    message: "Okay I want to book movers",
    conversationHistory: [
      { role: 'user', content: 'How does booking through you work?', timestamp: '2026-01-12T10:00:00Z' },
      { role: 'assistant', content: 'When you book through Peezy, vendors know they need to perform well or they lose access to our platform. It\'s the same services you\'d find anywhere, but with real accountability.', timestamp: '2026-01-12T10:00:05Z' }
    ]
  },

  // Scenario 19: Error recovery - handled in errors.test.js

  // Scenario 20: Natural conversation
  naturalConversation: {
    userState: {
      userId: 'test-user-20',
      name: 'Diana',
      email: 'diana@test.com',
      moveDate: daysFromNow(34),
      daysUntilMove: 34,
      moveDistance: 'local',
      originCity: 'Kansas City',
      destinationCity: 'Kansas City',
      originPropertyType: 'apartment',
      originOwnership: 'rent',
      originBedrooms: '1_bedroom',
      destinationPropertyType: 'apartment',
      destinationOwnership: 'rent',
      householdSize: 1,
      hasKids: false,
      hasPets: false,
      completedTasks: [],
      pendingTasks: ['book_movers'],
      heardAccountabilityPitch: false,
      vendorInteractions: {}
    },
    message: "This is my first time moving on my own",
    conversationHistory: []
  },

  // ============================================
  // EDGE CASE FIXTURES
  // ============================================

  emptyMessage: {
    userState: {
      userId: 'test-edge-1',
      name: 'Test',
      email: 'test@test.com',
      moveDate: daysFromNow(34),
      daysUntilMove: 34,
      moveDistance: 'local',
      completedTasks: [],
      heardAccountabilityPitch: false
    },
    message: "",
    conversationHistory: []
  },

  veryLongMessage: {
    userState: {
      userId: 'test-edge-2',
      name: 'Test',
      email: 'test@test.com',
      moveDate: daysFromNow(34),
      daysUntilMove: 34,
      moveDistance: 'local',
      completedTasks: [],
      heardAccountabilityPitch: false
    },
    message: "I need help with my move ".repeat(200), // ~4800 chars
    conversationHistory: []
  },

  minimalUserState: {
    userState: {
      userId: 'test-edge-3',
      name: 'Test'
      // Everything else missing
    },
    message: "Hello",
    conversationHistory: []
  },

  unicodeMessage: {
    userState: {
      userId: 'test-edge-4',
      name: 'Tëst',
      email: 'test@test.com',
      moveDate: daysFromNow(34),
      daysUntilMove: 34,
      moveDistance: 'local',
      completedTasks: [],
      heardAccountabilityPitch: false
    },
    message: "I'm moving to 日本 🏠 and need help! 🚚",
    conversationHistory: []
  },

  // ============================================
  // INTEGRATION TEST FIXTURES
  // ============================================

  multiTurnConversation: {
    userState: {
      userId: 'test-integration-1',
      name: 'Alex',
      email: 'alex@test.com',
      moveDate: daysFromNow(30),
      daysUntilMove: 30,
      moveDistance: 'local',
      originCity: 'Kansas City',
      destinationCity: 'Kansas City',
      originPropertyType: 'apartment',
      originBedrooms: '2_bedroom',
      householdSize: 1,
      hasKids: false,
      hasPets: false,
      completedTasks: [],
      pendingTasks: ['book_movers', 'internet_setup'],
      heardAccountabilityPitch: false,
      vendorInteractions: {}
    },
    messages: [
      "Hi, I need help with my move",
      "I'm not sure if I should hire movers",
      "How does booking through you work?",
      "Okay, let's look at movers",
      "I don't have any special items",
      "I think full service would be best"
    ]
  }
};

module.exports = { fixtures, daysFromNow, BASE_DATE };
