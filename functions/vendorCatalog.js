/**
 * Peezy Brain - Complete Vendor Catalog
 * 50+ vendor categories with triggers and surfacing rules
 */

const VENDORS = {
  // ============================================
  // TIER 1: CORE SERVICES (Everyone needs these)
  // ============================================

  movers: {
    id: 'movers',
    displayName: 'Moving Company',
    category: 'core',
    commission: '$50-200 per booking',
    triggers: {
      explicit: ['movers', 'moving company', 'hire movers', 'moving help', 'professional movers'],
      implicit: ['how will I move', 'transport furniture', 'heavy items', 'move my stuff']
    },
    conditions: [],
    surfacingMoment: 'logistics_task',
    surfacingStyle: 'direct',
    accountabilityPitch: true,
    seedPhrase: null
  },

  long_distance_movers: {
    id: 'long_distance_movers',
    displayName: 'Long-Distance Moving Company',
    category: 'core',
    commission: '$100-400 per booking',
    triggers: {
      explicit: ['long distance movers', 'cross country move', 'interstate movers', 'out of state movers'],
      implicit: ['moving to [other state]', 'moving far', 'cross country', 'coast to coast']
    },
    conditions: ['moveDistance: cross_state', 'moveDistance: cross_country'],
    surfacingMoment: 'logistics_task',
    surfacingStyle: 'direct',
    accountabilityPitch: true,
    seedPhrase: null
  },

  internet: {
    id: 'internet',
    displayName: 'Internet Service',
    category: 'core',
    commission: '$100-135 per signup',
    triggers: {
      explicit: ['internet', 'wifi', 'cable', 'xfinity', 'at&t', 'spectrum', 'fiber'],
      implicit: ['new place', 'work from home', 'streaming', 'need connection']
    },
    conditions: [],
    surfacingMoment: 'utilities_task',
    surfacingStyle: 'direct',
    accountabilityPitch: false,
    pitch: 'I can get this set up so it\'s ready when you arrive.',
    seedPhrase: null
  },

  junk_removal: {
    id: 'junk_removal',
    displayName: 'Junk Removal',
    category: 'core',
    commission: '$30-75 per job',
    triggers: {
      explicit: ['junk removal', 'get rid of', 'haul away', 'trash removal', 'dump run'],
      implicit: ['too much stuff', 'declutter', 'don\'t want to move this', 'throw away']
    },
    conditions: [],
    surfacingMoment: 'packing_task',
    surfacingStyle: 'direct',
    accountabilityPitch: true,
    seedPhrase: null
  },

  cleaning: {
    id: 'cleaning',
    displayName: 'Cleaning Service',
    category: 'core',
    commission: '$25-75 per job',
    triggers: {
      explicit: ['cleaning', 'cleaners', 'maid service', 'deep clean', 'move out clean'],
      implicit: ['deposit', 'move-out clean', 'dirty', 'landlord inspection']
    },
    conditions: [],
    surfacingMoment: 'before_move_out',
    surfacingStyle: 'direct',
    accountabilityPitch: true,
    seedPhrase: null
  },

  truck_rental: {
    id: 'truck_rental',
    displayName: 'Truck Rental',
    category: 'core',
    commission: '4-10% of rental',
    triggers: {
      explicit: ['rent a truck', 'u-haul', 'penske', 'budget truck', 'moving truck'],
      implicit: ['DIY move', 'do it myself', 'save money moving']
    },
    conditions: [],
    surfacingMoment: 'logistics_task',
    surfacingStyle: 'direct',
    accountabilityPitch: false,
    seedPhrase: null
  },

  // ============================================
  // TIER 2: SITUATIONAL (Based on user context)
  // ============================================

  storage: {
    id: 'storage',
    displayName: 'Storage Unit',
    category: 'situational',
    commission: '$25-50 per month ongoing',
    triggers: {
      explicit: ['storage', 'storage unit', 'store my stuff', 'temporary storage'],
      implicit: ['gap between', 'nowhere to put', 'temporary', 'between places']
    },
    conditions: ['needsStorage: true', 'dateGap > 0'],
    surfacingMoment: 'when_gap_detected',
    surfacingStyle: 'direct',
    accountabilityPitch: true,
    seedPhrase: null
  },

  pet_transport: {
    id: 'pet_transport',
    displayName: 'Pet Transport Service',
    category: 'situational',
    commission: '$50-100 per booking',
    triggers: {
      explicit: ['pet transport', 'move my pet', 'ship my dog', 'pet shipping', 'animal transport'],
      implicit: ['worried about [pet]', 'long drive with pets', 'pets on plane']
    },
    conditions: ['hasPets: true', 'moveDistance: cross_state+'],
    surfacingMoment: 'logistics_task',
    surfacingStyle: 'inform',
    accountabilityPitch: true,
    seedPhrase: 'For the pets, you\'ve got options - driving with them, flying, or professional pet transport if you\'d rather not deal with the logistics.'
  },

  auto_transport: {
    id: 'auto_transport',
    displayName: 'Car Shipping',
    category: 'situational',
    commission: '$75-150 per booking',
    triggers: {
      explicit: ['ship my car', 'auto transport', 'car shipping', 'vehicle transport'],
      implicit: ['flying to new city', 'not driving', 'second car']
    },
    conditions: ['moveDistance: cross_country', 'hasVehicle: true'],
    surfacingMoment: 'logistics_task',
    surfacingStyle: 'inform',
    accountabilityPitch: true,
    seedPhrase: 'If you\'re not driving the car yourself, auto transport is an option. Usually runs $800-1500 cross-country.'
  },

  packing_services: {
    id: 'packing_services',
    displayName: 'Professional Packers',
    category: 'situational',
    commission: '$40-100 per job',
    triggers: {
      explicit: ['packers', 'packing service', 'help packing', 'professional packing'],
      implicit: ['no time to pack', 'overwhelmed', 'hate packing', 'don\'t want to pack']
    },
    conditions: [],
    surfacingMoment: 'packing_task',
    surfacingStyle: 'inform',
    accountabilityPitch: true,
    seedPhrase: 'If packing feels like too much, professional packers can do a whole house in a day. Adds cost but saves sanity.'
  },

  moving_labor: {
    id: 'moving_labor',
    displayName: 'Moving Labor Only',
    category: 'situational',
    commission: '$30-60 per job',
    triggers: {
      explicit: ['moving labor', 'loading help', 'unloading help', 'just need muscle'],
      implicit: ['have a truck', 'renting truck', 'just need help loading']
    },
    conditions: [],
    surfacingMoment: 'logistics_task',
    surfacingStyle: 'direct',
    accountabilityPitch: true,
    seedPhrase: null
  },

  portable_storage: {
    id: 'portable_storage',
    displayName: 'Portable Storage Container',
    category: 'situational',
    commission: '$50-100 per booking',
    triggers: {
      explicit: ['pods', 'portable storage', 'container', 'pack at my pace'],
      implicit: ['flexible timeline', 'load gradually']
    },
    conditions: [],
    surfacingMoment: 'logistics_task',
    surfacingStyle: 'inform',
    accountabilityPitch: true,
    seedPhrase: null
  },

  // ============================================
  // TIER 3: PROPERTY-BASED (House triggers)
  // ============================================

  plumber: {
    id: 'plumber',
    displayName: 'Plumber',
    category: 'property',
    commission: '$30-75 per job',
    triggers: {
      explicit: ['plumber', 'plumbing', 'pipes', 'leak', 'water heater', 'drain'],
      implicit: []
    },
    conditions: ['destinationYearBuilt < 1970', 'destinationNotes: fixer upper'],
    surfacingMoment: 'after_move_in',
    surfacingStyle: 'plant_seed',
    accountabilityPitch: false,
    seedPhrase: 'Houses from that era sometimes have opinions about their plumbing. If anything acts up once you\'re in, just let me know.'
  },

  hvac: {
    id: 'hvac',
    displayName: 'HVAC Service',
    category: 'property',
    commission: '$50-100 per job',
    triggers: {
      explicit: ['hvac', 'furnace', 'air conditioning', 'heating', 'ac repair', 'heat pump'],
      implicit: []
    },
    conditions: ['destinationYearBuilt < 2000', 'destinationNotes: old'],
    surfacingMoment: 'after_move_in',
    surfacingStyle: 'plant_seed',
    accountabilityPitch: false,
    seedPhrase: 'Worth having the HVAC checked after you\'re settled. Those systems don\'t last forever, and you\'ll want to know what shape it\'s in before summer or winter hits.'
  },

  roofing: {
    id: 'roofing',
    displayName: 'Roofing Company',
    category: 'property',
    commission: '$100-500 per job',
    triggers: {
      explicit: ['roof', 'roofing', 'shingles', 'roof repair', 'roof leak'],
      implicit: []
    },
    conditions: ['houseAge > 20 years', 'destinationOwnership: own'],
    surfacingMoment: 'after_move_in',
    surfacingStyle: 'plant_seed',
    accountabilityPitch: false,
    seedPhrase: 'House is from [year] - roofs usually start showing age around 20-25 years. Something to keep an eye on.'
  },

  electrician: {
    id: 'electrician',
    displayName: 'Electrician',
    category: 'property',
    commission: '$30-75 per job',
    triggers: {
      explicit: ['electrician', 'electrical', 'wiring', 'outlets', 'breaker', 'panel'],
      implicit: []
    },
    conditions: ['destinationYearBuilt < 1970', 'destinationNotes: fixer upper'],
    surfacingMoment: 'after_move_in',
    surfacingStyle: 'plant_seed',
    accountabilityPitch: false,
    seedPhrase: 'Older homes sometimes have electrical quirks. If you notice anything weird with outlets or lights flickering, I know people.'
  },

  home_security: {
    id: 'home_security',
    displayName: 'Home Security',
    category: 'property',
    commission: '$75-150 per install',
    triggers: {
      explicit: ['security', 'alarm', 'cameras', 'ring', 'adt', 'simplisafe', 'home security'],
      implicit: []
    },
    conditions: ['destinationOwnership: own', 'destinationPropertyType: house'],
    surfacingMoment: 'after_move_in',
    surfacingStyle: 'inform',
    accountabilityPitch: true,
    seedPhrase: null
  },

  home_warranty: {
    id: 'home_warranty',
    displayName: 'Home Warranty',
    category: 'property',
    commission: '$50-100 per signup',
    triggers: {
      explicit: ['home warranty', 'appliance warranty', 'systems coverage'],
      implicit: []
    },
    conditions: ['destinationOwnership: own', 'houseAge > 10 years'],
    surfacingMoment: 'after_move_in',
    surfacingStyle: 'inform',
    accountabilityPitch: false,
    seedPhrase: 'With a house this age, some people like having a home warranty for peace of mind on appliances and systems. Worth looking into if that appeals to you.'
  },

  solar: {
    id: 'solar',
    displayName: 'Solar Installation',
    category: 'property',
    commission: '$200-500 per install',
    triggers: {
      explicit: ['solar', 'solar panels', 'energy bills', 'solar power'],
      implicit: []
    },
    conditions: ['destinationOwnership: own'],
    surfacingMoment: 'after_move_in',
    surfacingStyle: 'plant_seed',
    accountabilityPitch: false,
    seedPhrase: 'Once you\'re settled, might be worth getting a solar quote just to see the numbers. Rates keep going up.'
  },

  locksmith: {
    id: 'locksmith',
    displayName: 'Locksmith',
    category: 'property',
    commission: '$25-50 per job',
    triggers: {
      explicit: ['locksmith', 'change locks', 'new locks', 'keys', 'rekey'],
      implicit: ['security', 'previous owner', 'previous tenant']
    },
    conditions: ['destinationOwnership: own'],
    surfacingMoment: 'new_home_setup',
    surfacingStyle: 'direct',
    accountabilityPitch: true,
    seedPhrase: 'First thing with a new place - change the locks. You never know who has keys. Want me to get a locksmith out there?'
  },

  garage_door: {
    id: 'garage_door',
    displayName: 'Garage Door Service',
    category: 'property',
    commission: '$40-80 per job',
    triggers: {
      explicit: ['garage door', 'garage opener', 'garage repair'],
      implicit: []
    },
    conditions: ['destinationPropertyType: house'],
    surfacingMoment: 'after_move_in',
    surfacingStyle: 'plant_seed',
    accountabilityPitch: false,
    seedPhrase: null
  },

  window_treatment: {
    id: 'window_treatment',
    displayName: 'Window Treatments',
    category: 'property',
    commission: '$50-150 per job',
    triggers: {
      explicit: ['blinds', 'curtains', 'shades', 'window treatments', 'shutters'],
      implicit: ['privacy', 'light control']
    },
    conditions: [],
    surfacingMoment: 'after_move_in',
    surfacingStyle: 'plant_seed',
    accountabilityPitch: false,
    seedPhrase: null
  },

  // ============================================
  // TIER 4: SPECIALTY SERVICES
  // ============================================

  piano_moving: {
    id: 'piano_moving',
    displayName: 'Piano Moving',
    category: 'specialty',
    commission: '$50-150 per job',
    triggers: {
      explicit: ['piano', 'grand piano', 'upright piano', 'piano movers'],
      implicit: []
    },
    conditions: ['largeItems: piano'],
    surfacingMoment: 'logistics_task',
    surfacingStyle: 'direct',
    accountabilityPitch: true,
    seedPhrase: 'Pianos need special handling - regular movers often won\'t touch them or charge a lot extra. I can get you specialists who do this all the time.'
  },

  pool_table_moving: {
    id: 'pool_table_moving',
    displayName: 'Pool Table Moving',
    category: 'specialty',
    commission: '$40-100 per job',
    triggers: {
      explicit: ['pool table', 'billiards', 'billiard table'],
      implicit: []
    },
    conditions: ['largeItems: pool_table'],
    surfacingMoment: 'logistics_task',
    surfacingStyle: 'direct',
    accountabilityPitch: true,
    seedPhrase: null
  },

  hot_tub_moving: {
    id: 'hot_tub_moving',
    displayName: 'Hot Tub Moving',
    category: 'specialty',
    commission: '$75-150 per job',
    triggers: {
      explicit: ['hot tub', 'spa', 'jacuzzi'],
      implicit: []
    },
    conditions: ['largeItems: hot_tub'],
    surfacingMoment: 'logistics_task',
    surfacingStyle: 'direct',
    accountabilityPitch: true,
    seedPhrase: null
  },

  art_moving: {
    id: 'art_moving',
    displayName: 'Art & Antique Moving',
    category: 'specialty',
    commission: '$75-200 per job',
    triggers: {
      explicit: ['art', 'antiques', 'valuables', 'fragile art', 'paintings', 'sculptures'],
      implicit: []
    },
    conditions: ['specialItems: art', 'specialItems: antiques'],
    surfacingMoment: 'logistics_task',
    surfacingStyle: 'inform',
    accountabilityPitch: true,
    seedPhrase: null
  },

  gun_safe_moving: {
    id: 'gun_safe_moving',
    displayName: 'Safe Moving',
    category: 'specialty',
    commission: '$50-150 per job',
    triggers: {
      explicit: ['safe', 'gun safe', 'heavy safe', 'fireproof safe'],
      implicit: []
    },
    conditions: ['largeItems: safe'],
    surfacingMoment: 'logistics_task',
    surfacingStyle: 'direct',
    accountabilityPitch: true,
    seedPhrase: null
  },

  wine_collection: {
    id: 'wine_collection',
    displayName: 'Wine Collection Moving',
    category: 'specialty',
    commission: '$50-100 per job',
    triggers: {
      explicit: ['wine', 'wine collection', 'wine cellar', 'wine storage'],
      implicit: []
    },
    conditions: ['specialItems: wine'],
    surfacingMoment: 'logistics_task',
    surfacingStyle: 'inform',
    accountabilityPitch: true,
    seedPhrase: null
  },

  grandfather_clock: {
    id: 'grandfather_clock',
    displayName: 'Grandfather Clock Moving',
    category: 'specialty',
    commission: '$50-100 per job',
    triggers: {
      explicit: ['grandfather clock', 'antique clock', 'clock moving'],
      implicit: []
    },
    conditions: ['largeItems: grandfather_clock'],
    surfacingMoment: 'logistics_task',
    surfacingStyle: 'inform',
    accountabilityPitch: true,
    seedPhrase: null
  },

  // ============================================
  // TIER 5: HOME SERVICES (New homeowner)
  // ============================================

  home_inspection: {
    id: 'home_inspection',
    displayName: 'Home Inspector',
    category: 'home_services',
    commission: '$40-75 per inspection',
    triggers: {
      explicit: ['inspection', 'home inspection', 'inspector', 'house inspection'],
      implicit: []
    },
    conditions: ['destinationOwnership: own'],
    surfacingMoment: 'pre_closing',
    surfacingStyle: 'direct',
    accountabilityPitch: true,
    seedPhrase: null
  },

  pest_control: {
    id: 'pest_control',
    displayName: 'Pest Control',
    category: 'home_services',
    commission: '$25-50 per service',
    triggers: {
      explicit: ['pest', 'bugs', 'mice', 'termites', 'exterminator', 'rodent'],
      implicit: []
    },
    conditions: [],
    surfacingMoment: 'after_move_in',
    surfacingStyle: 'plant_seed',
    accountabilityPitch: false,
    seedPhrase: null
  },

  landscaping: {
    id: 'landscaping',
    displayName: 'Landscaping / Lawn Care',
    category: 'home_services',
    commission: '$25-50 per signup',
    triggers: {
      explicit: ['landscaping', 'lawn', 'yard', 'mowing', 'lawn care', 'yard work'],
      implicit: []
    },
    conditions: ['destinationPropertyType: house', 'destinationOwnership: own'],
    surfacingMoment: 'after_move_in',
    surfacingStyle: 'plant_seed',
    accountabilityPitch: false,
    seedPhrase: null
  },

  handyman: {
    id: 'handyman',
    displayName: 'Handyman Services',
    category: 'home_services',
    commission: '$25-50 per job',
    triggers: {
      explicit: ['handyman', 'repairs', 'fix', 'install', 'mount tv', 'hang pictures'],
      implicit: ['need help with', 'don\'t know how to']
    },
    conditions: [],
    surfacingMoment: 'after_move_in',
    surfacingStyle: 'plant_seed',
    accountabilityPitch: true,
    seedPhrase: 'Once you\'re in, if you need anything mounted, assembled, or fixed up, just let me know. I\'ve got handyman contacts.'
  },

  furniture_assembly: {
    id: 'furniture_assembly',
    displayName: 'Furniture Assembly',
    category: 'home_services',
    commission: '$25-40 per job',
    triggers: {
      explicit: ['assemble', 'furniture assembly', 'put together', 'ikea'],
      implicit: ['new furniture', 'build']
    },
    conditions: [],
    surfacingMoment: 'after_move_in',
    surfacingStyle: 'plant_seed',
    accountabilityPitch: true,
    seedPhrase: null
  },

  appliance_install: {
    id: 'appliance_install',
    displayName: 'Appliance Installation',
    category: 'home_services',
    commission: '$30-60 per job',
    triggers: {
      explicit: ['install appliance', 'hook up washer', 'connect dryer', 'appliance hookup'],
      implicit: ['new appliances', 'washer/dryer']
    },
    conditions: [],
    surfacingMoment: 'after_move_in',
    surfacingStyle: 'inform',
    accountabilityPitch: true,
    seedPhrase: null
  },

  carpet_cleaning: {
    id: 'carpet_cleaning',
    displayName: 'Carpet Cleaning',
    category: 'home_services',
    commission: '$25-50 per job',
    triggers: {
      explicit: ['carpet cleaning', 'steam clean', 'carpet shampoo'],
      implicit: ['stains', 'pet smell']
    },
    conditions: [],
    surfacingMoment: 'before_move_in',
    surfacingStyle: 'inform',
    accountabilityPitch: true,
    seedPhrase: null
  },

  window_cleaning: {
    id: 'window_cleaning',
    displayName: 'Window Cleaning',
    category: 'home_services',
    commission: '$20-40 per job',
    triggers: {
      explicit: ['window cleaning', 'window wash', 'clean windows'],
      implicit: []
    },
    conditions: [],
    surfacingMoment: 'after_move_in',
    surfacingStyle: 'plant_seed',
    accountabilityPitch: false,
    seedPhrase: null
  },

  painting: {
    id: 'painting',
    displayName: 'Painting Service',
    category: 'home_services',
    commission: '$50-150 per job',
    triggers: {
      explicit: ['painting', 'painters', 'repaint', 'paint walls', 'interior paint'],
      implicit: ['change colors', 'freshen up']
    },
    conditions: [],
    surfacingMoment: 'before_move_in',
    surfacingStyle: 'inform',
    accountabilityPitch: true,
    seedPhrase: 'If you want to paint before moving furniture in, now\'s the time. Much easier with empty rooms.'
  },

  // ============================================
  // TIER 6: INSURANCE (Partner model)
  // ============================================

  renters_insurance: {
    id: 'renters_insurance',
    displayName: 'Renters Insurance',
    category: 'insurance',
    commission: '$15-50 per policy',
    triggers: {
      explicit: ['renters insurance', 'renter insurance', 'insurance for apartment'],
      implicit: ['protect my stuff', 'landlord requires']
    },
    conditions: ['destinationOwnership: rent'],
    surfacingMoment: 'admin_tasks',
    surfacingStyle: 'inform',
    accountabilityPitch: false,
    seedPhrase: null
  },

  homeowners_insurance: {
    id: 'homeowners_insurance',
    displayName: 'Homeowners Insurance',
    category: 'insurance',
    commission: '$50-150 per policy + renewals',
    triggers: {
      explicit: ['homeowners insurance', 'home insurance', 'house insurance'],
      implicit: ['closing', 'mortgage requires']
    },
    conditions: ['destinationOwnership: own'],
    surfacingMoment: 'pre_closing',
    surfacingStyle: 'direct',
    accountabilityPitch: false,
    seedPhrase: null
  },

  auto_insurance: {
    id: 'auto_insurance',
    displayName: 'Auto Insurance Update',
    category: 'insurance',
    commission: '$30-75 per policy',
    triggers: {
      explicit: ['auto insurance', 'car insurance', 'vehicle insurance'],
      implicit: ['new state', 'address change']
    },
    conditions: [],
    surfacingMoment: 'admin_tasks',
    surfacingStyle: 'inform',
    accountabilityPitch: false,
    seedPhrase: null
  },

  moving_insurance: {
    id: 'moving_insurance',
    displayName: 'Moving Insurance',
    category: 'insurance',
    commission: '$20-50 per policy',
    triggers: {
      explicit: ['moving insurance', 'full value protection', 'moving coverage'],
      implicit: ['valuable items', 'worried about damage']
    },
    conditions: [],
    surfacingMoment: 'before_booking_movers',
    surfacingStyle: 'inform',
    accountabilityPitch: false,
    seedPhrase: 'Basic mover coverage is minimal - just 60 cents per pound. If you have valuable items, full value protection is worth considering.'
  },

  life_insurance: {
    id: 'life_insurance',
    displayName: 'Life Insurance',
    category: 'insurance',
    commission: '$50-200 per policy',
    triggers: {
      explicit: ['life insurance'],
      implicit: []
    },
    conditions: ['hasKids: true'],
    surfacingMoment: 'admin_tasks',
    surfacingStyle: 'plant_seed',
    accountabilityPitch: false,
    seedPhrase: null
  },

  // ============================================
  // TIER 7: ADDITIONAL SERVICES
  // ============================================

  mail_scanning: {
    id: 'mail_scanning',
    displayName: 'Mail Scanning Service',
    category: 'additional',
    commission: '$15-30 per signup',
    triggers: {
      explicit: ['mail scanning', 'virtual mailbox', 'mail forwarding service'],
      implicit: ['traveling during move', 'multiple addresses']
    },
    conditions: [],
    surfacingMoment: 'admin_tasks',
    surfacingStyle: 'plant_seed',
    accountabilityPitch: false,
    seedPhrase: null
  },

  moving_supplies: {
    id: 'moving_supplies',
    displayName: 'Moving Supplies',
    category: 'additional',
    commission: '5-10% affiliate',
    triggers: {
      explicit: ['boxes', 'packing supplies', 'bubble wrap', 'tape', 'moving boxes'],
      implicit: ['need boxes', 'packing materials']
    },
    conditions: [],
    surfacingMoment: 'packing_task',
    surfacingStyle: 'inform',
    accountabilityPitch: false,
    seedPhrase: null
  },

  donation_pickup: {
    id: 'donation_pickup',
    displayName: 'Donation Pickup',
    category: 'additional',
    commission: null,
    triggers: {
      explicit: ['donate', 'donation pickup', 'goodwill', 'salvation army'],
      implicit: ['get rid of', 'give away']
    },
    conditions: [],
    surfacingMoment: 'declutter_task',
    surfacingStyle: 'inform',
    accountabilityPitch: false,
    seedPhrase: 'For things in good condition, donation pickup is free and they\'ll come to you.'
  },

  cleaning_supplies: {
    id: 'cleaning_supplies',
    displayName: 'Cleaning Supplies',
    category: 'additional',
    commission: '3-5% affiliate',
    triggers: {
      explicit: ['cleaning supplies', 'cleaners'],
      implicit: ['deep clean myself']
    },
    conditions: [],
    surfacingMoment: 'cleaning_task',
    surfacingStyle: 'plant_seed',
    accountabilityPitch: false,
    seedPhrase: null
  },

  baby_proofing: {
    id: 'baby_proofing',
    displayName: 'Baby Proofing',
    category: 'additional',
    commission: '$30-60 per job',
    triggers: {
      explicit: ['baby proofing', 'childproofing', 'baby gates'],
      implicit: []
    },
    conditions: ['hasKids: true', 'kidsAges includes infant/toddler'],
    surfacingMoment: 'after_move_in',
    surfacingStyle: 'plant_seed',
    accountabilityPitch: false,
    seedPhrase: null
  },

  pet_friendly_cleaning: {
    id: 'pet_friendly_cleaning',
    displayName: 'Pet-Friendly Cleaning',
    category: 'additional',
    commission: '$25-50 per job',
    triggers: {
      explicit: ['pet cleaning', 'pet stains', 'pet odor'],
      implicit: []
    },
    conditions: ['hasPets: true'],
    surfacingMoment: 'before_move_out',
    surfacingStyle: 'inform',
    accountabilityPitch: false,
    seedPhrase: null
  },

  senior_moving: {
    id: 'senior_moving',
    displayName: 'Senior Moving Services',
    category: 'specialty',
    commission: '$75-150 per job',
    triggers: {
      explicit: ['senior moving', 'elderly moving', 'parent moving', 'downsizing'],
      implicit: ['helping parent', 'assisted living']
    },
    conditions: [],
    surfacingMoment: 'logistics_task',
    surfacingStyle: 'inform',
    accountabilityPitch: true,
    seedPhrase: null
  },

  office_moving: {
    id: 'office_moving',
    displayName: 'Office/Commercial Moving',
    category: 'specialty',
    commission: '$100-300 per job',
    triggers: {
      explicit: ['office moving', 'commercial moving', 'business moving'],
      implicit: ['home office', 'work equipment']
    },
    conditions: [],
    surfacingMoment: 'logistics_task',
    surfacingStyle: 'inform',
    accountabilityPitch: true,
    seedPhrase: null
  }
};

// Get vendor by ID
function getVendor(id) {
  return VENDORS[id] || null;
}

// Get all vendors by category
function getVendorsByCategory(category) {
  return Object.values(VENDORS).filter(v => v.category === category);
}

// Get vendors matching conditions
function getVendorsForContext(userState) {
  return Object.values(VENDORS).filter(vendor => {
    if (!vendor.conditions || vendor.conditions.length === 0) return true;
    
    return vendor.conditions.some(condition => {
      const [field, value] = condition.split(': ');
      if (field === 'hasPets' && value === 'true') return userState.hasPets;
      if (field === 'hasKids' && value === 'true') return userState.hasKids;
      if (field === 'moveDistance') return userState.moveDistance === value || 
        (value === 'cross_state+' && ['cross_state', 'cross_country'].includes(userState.moveDistance));
      if (field === 'destinationOwnership') return userState.destinationOwnership === value;
      if (field === 'destinationPropertyType') return userState.destinationPropertyType === value;
      if (field === 'largeItems') return userState.largeItems?.includes(value);
      if (field === 'specialItems') return userState.specialItems?.includes(value);
      return false;
    });
  });
}

// Match vendor by trigger
function matchVendorByTrigger(message, userState) {
  const messageLower = message.toLowerCase();
  const matches = [];
  
  for (const vendor of Object.values(VENDORS)) {
    const explicitMatch = vendor.triggers.explicit.some(t => messageLower.includes(t.toLowerCase()));
    const implicitMatch = vendor.triggers.implicit.some(t => messageLower.includes(t.toLowerCase()));
    
    if (explicitMatch || implicitMatch) {
      matches.push({
        vendor,
        matchType: explicitMatch ? 'explicit' : 'implicit',
        trigger: explicitMatch 
          ? vendor.triggers.explicit.find(t => messageLower.includes(t.toLowerCase()))
          : vendor.triggers.implicit.find(t => messageLower.includes(t.toLowerCase()))
      });
    }
  }
  
  return matches;
}

// Export
module.exports = {
  VENDORS,
  getVendor,
  getVendorsByCategory,
  getVendorsForContext,
  matchVendorByTrigger
};
