/**
 * Peezy Brain - Context Builder
 * Builds LLM context from user state and conversation
 * 
 * UPDATED: Now fetches user data from Firestore to ensure
 * assessment data is always available to the LLM
 */

const admin = require('firebase-admin');
const { WORKFLOWS, getWorkflow } = require('./workflows');
const { VENDORS, getVendorsForContext, matchVendorByTrigger } = require('./vendorCatalog');

/**
 * Fetch user knowledge from Firestore
 * This ensures we always have the latest assessment data
 */
async function fetchUserKnowledge(userId) {
  if (!userId) return null;
  
  try {
    const db = admin.firestore();
    const doc = await db.collection('userKnowledge').doc(userId).get();
    
    if (!doc.exists) {
      console.log(`No userKnowledge found for user: ${userId}`);
      return null;
    }
    
    const data = doc.data();
    console.log(`✅ Fetched userKnowledge for user: ${userId}`);
    return data;
  } catch (error) {
    console.error(`Error fetching userKnowledge: ${error.message}`);
    return null;
  }
}

/**
 * Convert userKnowledge entries to flat userState format
 * userKnowledge stores: { entries: { field_name: { value, source, confidence, ... } } }
 * We need: { fieldName: value }
 */
function flattenUserKnowledge(userKnowledge) {
  if (!userKnowledge || !userKnowledge.entries) return {};
  
  const flattened = {};
  const entries = userKnowledge.entries;
  
  // Map userKnowledge keys to context keys
  const keyMapping = {
    'user_name': 'name',
    'move_date': 'moveDate',
    'move_experience': 'moveExperience',
    'biggest_concern': 'biggestConcern',
    'move_distance': 'moveDistance',
    'current_home_type': 'originPropertyType',
    'destination_home_type': 'destinationPropertyType',
    'household_size': 'householdSize',
    'has_pets': 'hasPets',
    'moving_help': 'movingHelp',
    'packing_help': 'packingHelp',
    'cleaning_help': 'cleaningHelp',
    // Add more mappings as needed
  };
  
  for (const [key, entry] of Object.entries(entries)) {
    if (entry && entry.value !== undefined) {
      const mappedKey = keyMapping[key] || toCamelCase(key);
      flattened[mappedKey] = entry.value;
    }
  }
  
  return flattened;
}

/**
 * Convert snake_case to camelCase
 */
function toCamelCase(str) {
  return str.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase());
}

/**
 * Merge client userState with Firestore userKnowledge
 * Firestore is the source of truth, but client may have newer session data
 */
function mergeUserState(clientState, firestoreData) {
  // Start with Firestore data (source of truth for assessment)
  const merged = { ...firestoreData };
  
  // Overlay client state (may have session-specific data like currentTask)
  // But don't let client override assessment data with empty values
  for (const [key, value] of Object.entries(clientState || {})) {
    if (value !== undefined && value !== null && value !== '') {
      // Client session data takes precedence for these fields
      const sessionFields = [
        'currentTask',
        'heardAccountabilityPitch',
        'vendorInteractions',
        'completedTasks',
        'pendingTasks',
        'skippedTasks',
        'lastInteractionAt'
      ];
      
      if (sessionFields.includes(key) || !merged[key]) {
        merged[key] = value;
      }
    }
  }
  
  return merged;
}

/**
 * Build complete context object for the LLM
 * NOW ASYNC - fetches from Firestore first
 */
async function buildContext(request) {
  const { userState, message, conversationHistory, currentTask, sessionMetadata } = request;
  
  // Get user ID
  const userId = userState?.userId;
  
  // Fetch user knowledge from Firestore (source of truth)
  let firestoreData = {};
  if (userId) {
    const userKnowledge = await fetchUserKnowledge(userId);
    if (userKnowledge) {
      firestoreData = flattenUserKnowledge(userKnowledge);
    }
  }
  
  // Merge with client state
  const mergedState = mergeUserState(userState, firestoreData);
  
  // Compute derived values
  const daysUntilMove = computeDaysUntilMove(mergedState.moveDate);
  const urgencyLevel = determineUrgencyLevel(daysUntilMove);
  const dateGap = computeDateGap(mergedState.leaseEndDate, mergedState.moveInDate);
  
  // Build base context
  const context = {
    // User identity
    userName: mergedState.name || 'there',
    userId: mergedState.userId,
    
    // Move basics
    moveDate: mergedState.moveDate,
    daysUntilMove,
    urgencyLevel,
    moveDistance: mergedState.moveDistance || 'local',
    
    // Origin
    originCity: mergedState.originCity,
    originState: mergedState.originState,
    originPropertyType: mergedState.originPropertyType,
    originOwnership: mergedState.originOwnership,
    originBedrooms: mergedState.originBedrooms,
    leaseEndDate: mergedState.leaseEndDate,
    
    // Destination
    destinationCity: mergedState.destinationCity,
    destinationState: mergedState.destinationState,
    destinationPropertyType: mergedState.destinationPropertyType,
    destinationOwnership: mergedState.destinationOwnership,
    destinationYearBuilt: mergedState.destinationYearBuilt,
    destinationNotes: mergedState.destinationNotes,
    moveInDate: mergedState.moveInDate,
    
    // Household
    householdSize: mergedState.householdSize,
    hasKids: mergedState.hasKids,
    kidsAges: mergedState.kidsAges,
    hasPets: mergedState.hasPets,
    petTypes: mergedState.petTypes,
    
    // Inventory
    largeItems: mergedState.largeItems || [],
    specialItems: mergedState.specialItems || [],
    
    // Preferences
    budget: mergedState.budget,
    servicePreference: mergedState.servicePreference,
    movingHelp: mergedState.movingHelp,
    packingHelp: mergedState.packingHelp,
    cleaningHelp: mergedState.cleaningHelp,
    
    // Progress
    completedTasks: mergedState.completedTasks || [],
    pendingTasks: mergedState.pendingTasks || [],
    skippedTasks: mergedState.skippedTasks || [],
    
    // Conversation state
    heardAccountabilityPitch: mergedState.heardAccountabilityPitch || false,
    vendorInteractions: mergedState.vendorInteractions || {},
    
    // Current focus
    currentTask,
    
    // Computed values
    dateGap,
    needsStorage: dateGap > 0,
    
    // Session info
    messageCount: sessionMetadata?.messageCount || 1,
    isFirstMessage: (sessionMetadata?.messageCount || 1) === 1,
    
    // Debug: track data source
    _dataSource: {
      hadFirestoreData: Object.keys(firestoreData).length > 0,
      hadClientState: Object.keys(userState || {}).length > 0
    }
  };
  
  // Add relevant vendors for context
  context.relevantVendors = identifyRelevantVendors(context, message);
  
  // Add workflow context if on a task
  if (currentTask) {
    context.currentWorkflow = getWorkflow(currentTask);
  }
  
  // Add detected vendor triggers from message
  context.vendorTriggers = matchVendorByTrigger(message, mergedState);
  
  return context;
}

/**
 * Compute days until move from date string
 */
function computeDaysUntilMove(moveDate) {
  if (!moveDate) return null;
  
  try {
    const move = new Date(moveDate);
    const now = new Date();
    // Reset to start of day for accurate day count
    move.setHours(0, 0, 0, 0);
    now.setHours(0, 0, 0, 0);
    
    const diffMs = move - now;
    const diffDays = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
    
    return diffDays;
  } catch (e) {
    return null;
  }
}

/**
 * Determine urgency level based on days until move
 */
function determineUrgencyLevel(daysUntilMove) {
  if (daysUntilMove === null) return 'unknown';
  if (daysUntilMove <= 0) return 'today';
  if (daysUntilMove <= 3) return 'critical';
  if (daysUntilMove <= 7) return 'urgent';
  if (daysUntilMove <= 14) return 'tight';
  if (daysUntilMove <= 30) return 'normal';
  if (daysUntilMove <= 60) return 'planning';
  return 'early';
}

/**
 * Compute gap between lease end and move-in
 */
function computeDateGap(leaseEndDate, moveInDate) {
  if (!leaseEndDate || !moveInDate) return 0;
  
  try {
    const leaseEnd = new Date(leaseEndDate);
    const moveIn = new Date(moveInDate);
    
    const diffMs = moveIn - leaseEnd;
    const diffDays = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
    
    return diffDays > 0 ? diffDays : 0;
  } catch (e) {
    return 0;
  }
}

/**
 * Identify vendors relevant to user's context
 */
function identifyRelevantVendors(context, message) {
  const relevant = [];
  
  // Core vendors everyone needs
  if (!context.vendorInteractions?.movers?.booked) {
    relevant.push({
      vendor: 'movers',
      reason: 'not_booked',
      priority: context.daysUntilMove <= 14 ? 'high' : 'normal'
    });
  }
  
  // Internet is always relevant
  if (!context.vendorInteractions?.internet?.booked) {
    relevant.push({
      vendor: 'internet',
      reason: 'not_booked',
      priority: 'normal'
    });
  }
  
  // Cleaning for renters
  if (context.originOwnership === 'rent' && !context.vendorInteractions?.cleaning?.booked) {
    relevant.push({
      vendor: 'cleaning',
      reason: 'renter_deposit',
      priority: 'normal'
    });
  }
  
  // Storage if there's a date gap
  if (context.dateGap > 0 && !context.vendorInteractions?.storage?.booked) {
    relevant.push({
      vendor: 'storage',
      reason: 'date_gap',
      priority: 'high'
    });
  }
  
  // Pet transport for long-distance with pets
  if (context.hasPets && ['cross_state', 'cross_country'].includes(context.moveDistance)) {
    if (!context.vendorInteractions?.pet_transport?.mentioned) {
      relevant.push({
        vendor: 'pet_transport',
        reason: 'long_distance_pets',
        priority: 'normal',
        surfacingStyle: 'inform'
      });
    }
  }
  
  // Auto transport for cross-country
  if (context.moveDistance === 'cross_country') {
    if (!context.vendorInteractions?.auto_transport?.mentioned) {
      relevant.push({
        vendor: 'auto_transport',
        reason: 'cross_country',
        priority: 'low',
        surfacingStyle: 'inform'
      });
    }
  }
  
  // Special items
  if (context.largeItems?.includes('piano')) {
    relevant.push({
      vendor: 'piano_moving',
      reason: 'has_piano',
      priority: 'high'
    });
  }
  if (context.largeItems?.includes('safe')) {
    relevant.push({
      vendor: 'gun_safe_moving',
      reason: 'has_safe',
      priority: 'high'
    });
  }
  if (context.largeItems?.includes('pool_table')) {
    relevant.push({
      vendor: 'pool_table_moving',
      reason: 'has_pool_table',
      priority: 'high'
    });
  }
  
  // School transfer for kids
  if (context.hasKids && !context.completedTasks?.includes('school_transfer')) {
    relevant.push({
      vendor: null,
      task: 'school_transfer',
      reason: 'has_kids',
      priority: 'normal'
    });
  }
  
  // Locksmith for homeowners
  if (context.destinationOwnership === 'own') {
    if (!context.vendorInteractions?.locksmith?.mentioned) {
      relevant.push({
        vendor: 'locksmith',
        reason: 'new_homeowner',
        priority: 'normal',
        surfacingStyle: 'direct'
      });
    }
  }
  
  // Old house contractors
  if (context.destinationYearBuilt && context.destinationYearBuilt < 1970) {
    if (!context.vendorInteractions?.plumber?.mentioned) {
      relevant.push({
        vendor: 'plumber',
        reason: 'old_house',
        priority: 'low',
        surfacingStyle: 'plant_seed'
      });
    }
    if (!context.vendorInteractions?.electrician?.mentioned) {
      relevant.push({
        vendor: 'electrician',
        reason: 'old_house',
        priority: 'low',
        surfacingStyle: 'plant_seed'
      });
    }
  }
  
  return relevant;
}

/**
 * Build conversation history for LLM
 */
function buildConversationHistory(history, maxMessages = 10) {
  if (!history || !Array.isArray(history)) return [];
  
  // Filter valid messages
  const valid = history.filter(msg => 
    msg && 
    typeof msg === 'object' &&
    ['user', 'assistant'].includes(msg.role) &&
    typeof msg.content === 'string'
  );
  
  // Take most recent messages
  const recent = valid.slice(-maxMessages);
  
  return recent.map(msg => ({
    role: msg.role,
    content: msg.content
  }));
}

/**
 * Sanitize user input
 */
function sanitizeInput(input) {
  if (!input) return '';
  if (typeof input !== 'string') return String(input);
  
  // Remove potential injection attempts
  let sanitized = input
    .replace(/<[^>]*>/g, '') // Remove HTML tags
    .replace(/\\/g, '') // Remove backslashes
    .trim();
  
  // Truncate very long messages
  if (sanitized.length > 2000) {
    sanitized = sanitized.substring(0, 2000) + '...';
  }
  
  return sanitized;
}

/**
 * Validate request structure
 */
function validateRequest(request) {
  const errors = [];
  
  if (!request) {
    errors.push('Request is required');
    return { valid: false, errors };
  }
  
  if (!request.userState) {
    errors.push('userState is required');
  } else {
    if (!request.userState.userId && !request.userState.name) {
      errors.push('userState must have userId or name');
    }
  }
  
  return {
    valid: errors.length === 0,
    errors
  };
}

// Export
module.exports = {
  buildContext,
  fetchUserKnowledge,
  flattenUserKnowledge,
  mergeUserState,
  computeDaysUntilMove,
  determineUrgencyLevel,
  computeDateGap,
  identifyRelevantVendors,
  buildConversationHistory,
  sanitizeInput,
  validateRequest
};