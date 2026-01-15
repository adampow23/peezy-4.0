/**
 * Peezy Brain - Complete Workflow Definitions
 * 40 workflows covering all moving tasks
 */

const WORKFLOWS = {
  // ============================================
  // LOGISTICS (8 workflows)
  // ============================================

  book_movers: {
    id: 'book_movers',
    title: 'Book Moving Company',
    description: 'Help user find and book the right movers',
    category: 'logistics',
    steps: [
      'Confirm move date and distance (if not known)',
      'Ask about special items (piano, safe, antiques, etc.)',
      'Understand service level (full service vs. transport only)',
      'Get budget range if not established',
      'Present 2-3 options that fit their needs',
      'Help them compare (don\'t just list - guide the decision)',
      'Facilitate booking through Peezy',
      'Confirm details and set expectations for move day'
    ],
    keyInfo: {
      localMove: 'Usually charged by hour + truck fee. 2-3 movers for apt, 3-4 for house.',
      longDistance: 'Charged by weight. Book 4-6 weeks out. Get binding estimate.',
      timeline: 'Local: 1-2 weeks out OK. Long distance: 4-6 weeks minimum.',
      pricing: {
        studio: '$300-600',
        oneBed: '$400-800',
        twoBed: '$600-1200',
        threeBed: '$800-1800',
        fourBed: '$1200-2500'
      }
    },
    vendorCategory: 'movers',
    accountabilityMoment: 'before_booking',
    commonConcerns: ['cost', 'reliability', 'damage/insurance', 'timing'],
    redFlags: ['No physical address', 'Large upfront deposit', 'No written estimate', 'No DOT number for interstate']
  },

  book_long_distance_movers: {
    id: 'book_long_distance_movers',
    title: 'Book Long-Distance Movers',
    description: 'Specialized guidance for cross-country moves',
    category: 'logistics',
    steps: [
      'Confirm exact addresses (origin and destination)',
      'Get detailed inventory (affects weight-based pricing)',
      'Ask about access issues at both locations',
      'Discuss timeline flexibility (can affect price significantly)',
      'Explain binding vs. non-binding estimates',
      'Present 3 options with different service levels',
      'Verify DOT licensing and insurance',
      'Book through Peezy with confirmation'
    ],
    keyInfo: {
      pricing: 'Based on weight and distance. Average 3-bed cross-country: $4,000-8,000',
      booking: 'Book 4-6 weeks minimum, 8 weeks for peak season',
      estimates: 'Always get binding estimate to avoid surprises',
      verification: 'Check FMCSA database for complaints',
      timeline: 'Transit typically 7-21 days depending on distance'
    },
    vendorCategory: 'long_distance_movers',
    accountabilityMoment: 'before_booking',
    commonConcerns: ['delivery window', 'weight disputes', 'damage claims'],
    redFlags: ['No USDOT number', 'Demands large cash deposit', 'Won\'t do in-home estimate']
  },

  schedule_move_date: {
    id: 'schedule_move_date',
    title: 'Schedule Move Date',
    description: 'Help finalize and coordinate the move date',
    category: 'logistics',
    steps: [
      'Confirm proposed date works for all parties',
      'Check for conflicts (lease dates, closing dates)',
      'Consider day of week (weekends cost more)',
      'Consider time of month (end of month is busiest)',
      'Lock in date with booked services',
      'Create timeline for days around move'
    ],
    keyInfo: {
      bestDays: 'Mid-week (Tue-Thu) and mid-month are cheapest',
      avoid: 'Last week of month, weekends, summer peak season (May-Sept)',
      buffer: 'Build in 1-2 days buffer if possible',
      peakSeason: 'May through September - book earlier, costs 20-30% more'
    },
    vendorCategory: null,
    accountabilityMoment: null
  },

  truck_rental: {
    id: 'truck_rental',
    title: 'Rent Moving Truck',
    description: 'For DIY moves - help with truck rental',
    category: 'logistics',
    steps: [
      'Confirm they want to DIY (vs. hiring movers)',
      'Estimate truck size needed based on home size',
      'Compare one-way vs. round-trip options',
      'Discuss insurance options (worth it)',
      'Book truck through Peezy affiliate',
      'Provide loading tips and timeline'
    ],
    keyInfo: {
      sizing: 'Studio/1BR: 10-12ft. 2BR: 15ft. 3BR: 20ft. 4BR+: 26ft.',
      costs: 'Local: $30-100/day. One-way: $800-2,000+',
      gas: 'Budget for 8-12 mpg on larger trucks',
      insurance: 'Worth $15-30/day for peace of mind',
      equipment: 'Reserve dollies, furniture pads, ramp'
    },
    vendorCategory: 'truck_rental',
    accountabilityMoment: null
  },

  coordinate_timing: {
    id: 'coordinate_timing',
    title: 'Coordinate Move Timing',
    description: 'Ensure all pieces align for move day',
    category: 'logistics',
    steps: [
      'Map out full timeline (pack → load → drive → unload)',
      'Confirm utility transfer dates align',
      'Verify access to both properties on move day',
      'Plan for overlap or gap in housing',
      'Schedule key services around move day',
      'Create day-of checklist'
    ],
    keyInfo: {
      overlap: 'If possible, have 1-2 days overlap between places',
      gap: 'If lease ends before move-in, plan storage or temporary stay',
      moveDay: 'Plan for full day minimum, often extends to next day',
      accessTimes: 'Confirm elevator reservations, parking permits if needed'
    },
    vendorCategory: null,
    accountabilityMoment: null
  },

  moving_day_prep: {
    id: 'moving_day_prep',
    title: 'Prepare for Move Day',
    description: 'Final preparations before the big day',
    category: 'logistics',
    steps: [
      'Confirm all bookings (movers, truck, etc.)',
      'Prepare essentials box (don\'t pack)',
      'Plan for pets and kids on move day',
      'Confirm parking/access for moving truck',
      'Get cash for tips',
      'Charge phones, pack chargers accessible',
      'Do final walkthrough of old place'
    ],
    keyInfo: {
      essentialsBox: 'Toiletries, phone chargers, snacks, water, medications, change of clothes, important docs, toilet paper',
      tips: 'Standard: $20-40 per mover for local, $40-80 for long distance',
      parking: 'Some cities require permits for moving trucks',
      timing: 'Start early - aim for 8am start if possible'
    },
    vendorCategory: null,
    accountabilityMoment: null
  },

  post_move_checklist: {
    id: 'post_move_checklist',
    title: 'Post-Move Tasks',
    description: 'Everything to do after arriving',
    category: 'logistics',
    steps: [
      'Do walkthrough of new place (note any issues)',
      'Verify all boxes arrived',
      'Unpack essentials first',
      'Test all utilities',
      'Update address with remaining accounts',
      'Introduce yourself to neighbors',
      'Locate nearest essentials (grocery, pharmacy, hospital)'
    ],
    keyInfo: {
      priority: 'Bedroom and bathroom first, then kitchen',
      documentation: 'Photo any damage within 24 hours',
      utilities: 'Test water, electric, gas, internet immediately'
    },
    vendorCategory: null,
    accountabilityMoment: null
  },

  handle_moving_issues: {
    id: 'handle_moving_issues',
    title: 'Handle Moving Problems',
    description: 'What to do when things go wrong',
    category: 'logistics',
    steps: [
      'Document the issue immediately (photos, notes)',
      'Contact Peezy to help resolve',
      'File claim if damage occurred',
      'Follow up until resolved'
    ],
    keyInfo: {
      damage: 'Most movers have 9-month window for claims',
      documentation: 'Photos before and after are crucial',
      peezyHelp: 'We\'ll contact the vendor on your behalf',
      valuation: 'Full value protection vs. released value (60¢/lb)'
    },
    vendorCategory: null,
    accountabilityMoment: null,
    emphasizeAccountability: true
  },

  // ============================================
  // SERVICES (12 workflows)
  // ============================================

  junk_removal: {
    id: 'junk_removal',
    title: 'Schedule Junk Removal',
    description: 'Get rid of stuff before the move',
    category: 'services',
    steps: [
      'Identify what needs to go',
      'Estimate volume (helps with pricing)',
      'Decide: full service vs. dumpster rental',
      'Schedule timing (before packing ideally)',
      'Book through Peezy',
      'Prepare items for pickup'
    ],
    keyInfo: {
      timing: 'Do this early - don\'t pack what you don\'t want',
      pricing: 'Typically $150-400 for partial load, $400-800 for full truck',
      alternatives: 'Donation pickup is free but limited, dump runs are cheap but time-consuming',
      hazardous: 'Most won\'t take paint, chemicals, electronics - check special disposal'
    },
    vendorCategory: 'junk_removal',
    accountabilityMoment: 'before_booking',
    surfacingTriggers: ['declutter', 'get rid of', 'too much stuff', 'don\'t want to move this']
  },

  cleaning_service: {
    id: 'cleaning_service',
    title: 'Book Cleaning Service',
    description: 'Clean old place (for deposit) or new place (for move-in)',
    category: 'services',
    steps: [
      'Determine which place needs cleaning (or both)',
      'Assess level needed (standard vs. deep clean)',
      'Time it right (after move-out, before move-in)',
      'Get quote through Peezy',
      'Book and confirm'
    ],
    keyInfo: {
      moveOut: 'Deep clean for deposit return. Focus on kitchen, bathrooms, appliances.',
      moveIn: 'Many people prefer cleaning before unpacking',
      pricing: 'Standard clean: $150-300. Deep clean: $250-500. Depends on size.',
      timing: 'Book 1-2 weeks ahead, especially end of month'
    },
    vendorCategory: 'cleaning',
    accountabilityMoment: 'before_booking',
    surfacingTriggers: ['deposit', 'clean', 'dirty', 'landlord inspection']
  },

  pet_transport: {
    id: 'pet_transport',
    title: 'Arrange Pet Transport',
    description: 'Figure out how pets will travel',
    category: 'services',
    steps: [
      'Understand pet\'s needs (size, temperament, health)',
      'Evaluate options (car, plane, professional transport)',
      'For long distance: professional pet transport may be best',
      'Book vet checkup and get health certificate if flying',
      'Prepare pet for travel day'
    ],
    keyInfo: {
      car: 'Best for short moves. Frequent stops, never leave in hot car.',
      flying: 'Need health certificate within 10 days. Book early - limited pet spots.',
      professional: 'For long distance or anxious pets. $300-1,500 depending on distance.',
      preparation: 'Keep routine normal, familiar items in carrier'
    },
    vendorCategory: 'pet_transport',
    accountabilityMoment: 'before_booking',
    conditions: ['hasPets: true']
  },

  storage_unit: {
    id: 'storage_unit',
    title: 'Book Storage Unit',
    description: 'Find storage for items not going directly to new place',
    category: 'services',
    steps: [
      'Understand why storage is needed (gap in dates? overflow?)',
      'Estimate size needed',
      'Decide: climate controlled or standard',
      'Consider location (near old place, new place, or in between)',
      'Book through Peezy',
      'Plan what goes to storage vs. new place'
    ],
    keyInfo: {
      sizing: '5x5: few boxes. 5x10: 1BR apt. 10x10: 2BR apt. 10x20: 3-4BR house.',
      climate: 'Needed for: wood furniture, electronics, photos, anything valuable',
      pricing: '$50-100 for small, $100-200 for medium, $200-400 for large',
      access: 'Consider 24/7 access if you\'ll need things during transition'
    },
    vendorCategory: 'storage',
    accountabilityMoment: 'before_booking',
    conditions: ['needsStorage: true', 'dateGap']
  },

  internet_setup: {
    id: 'internet_setup',
    title: 'Set Up Internet Service',
    description: 'Get internet ready at new place',
    category: 'services',
    steps: [
      'Check what providers are available at new address',
      'Determine speed needs (work from home? streaming? gaming?)',
      'Compare options',
      'Schedule installation for move-in day or before',
      'Book through Peezy (we handle it)'
    ],
    keyInfo: {
      timing: 'Schedule 1-2 weeks ahead. Ask for earliest available on move-in day.',
      speeds: 'Basic: 25-50 Mbps. Work from home: 100-200 Mbps. Heavy use: 500+ Mbps.',
      equipment: 'Provider equipment or buy your own modem/router to save monthly fee',
      transfer: 'Some providers can transfer service - ask about move programs'
    },
    vendorCategory: 'internet',
    accountabilityMoment: 'before_booking',
    commission: '$100-135',
    surfacingTriggers: ['new place', 'wifi', 'internet', 'work from home']
  },

  utility_transfer: {
    id: 'utility_transfer',
    title: 'Transfer Utilities',
    description: 'Set up electric, gas, water at new place',
    category: 'services',
    steps: [
      'Identify which utilities need to be in your name',
      'Contact providers to schedule start date',
      'Schedule stop date at old address',
      'Plan for overlap (don\'t get caught without power)',
      'Note: I can help with internet (book through me), but other utilities you\'ll contact directly'
    ],
    keyInfo: {
      timing: 'Schedule 2 weeks ahead of move',
      overlap: 'Have utilities on at both places for 1-2 days if possible',
      renting: 'Some utilities may be handled by landlord - check lease',
      deposits: 'Some providers require deposit for new customers'
    },
    vendorCategory: 'internet',
    noteOnUtilities: 'Electric/gas/water are regulated - I\'ll give you the info but you contact them directly'
  },

  home_security: {
    id: 'home_security',
    title: 'Set Up Home Security',
    description: 'Protect the new place',
    category: 'services',
    steps: [
      'Assess security needs (cameras, sensors, monitoring?)',
      'Understand options (DIY vs. professional)',
      'Consider smart home integration',
      'Get quote through Peezy',
      'Schedule installation after move-in'
    ],
    keyInfo: {
      diy: 'Ring, SimpliSafe, etc. Lower cost, self-install',
      professional: 'ADT, Vivint, etc. Monthly monitoring, professional install',
      timing: 'After you\'re settled, not urgent for move day',
      basics: 'At minimum: change locks, check smoke detectors'
    },
    vendorCategory: 'home_security',
    accountabilityMoment: 'before_booking',
    conditions: ['ownership: own', 'propertyType: house/townhouse']
  },

  auto_transport: {
    id: 'auto_transport',
    title: 'Ship Your Car',
    description: 'For long-distance moves when not driving',
    category: 'services',
    steps: [
      'Confirm car transport is needed (vs. driving)',
      'Choose open vs. enclosed transport',
      'Get quotes (varies widely)',
      'Book 2-4 weeks ahead',
      'Prepare car for transport'
    ],
    keyInfo: {
      open: 'Standard, cheaper. Fine for most cars.',
      enclosed: 'For luxury/classic cars. 40-60% more expensive.',
      pricing: 'Cross-country: $800-1,500 open, $1,200-2,200 enclosed',
      timing: 'Book 2-4 weeks ahead, more for peak season',
      prep: 'Clean car, remove personal items, document condition with photos'
    },
    vendorCategory: 'auto_transport',
    accountabilityMoment: 'before_booking',
    conditions: ['moveDistance: cross_country', 'hasVehicle: true']
  },

  packing_services: {
    id: 'packing_services',
    title: 'Hire Packers',
    description: 'Professional packing service',
    category: 'services',
    steps: [
      'Understand scope (full house vs. fragile items only)',
      'Get quote based on home size',
      'Schedule 1-2 days before move day',
      'Prepare (declutter first!)',
      'Be present to answer questions'
    ],
    keyInfo: {
      pricing: 'Adds 25-50% to moving cost',
      timing: 'Usually day before move, sometimes morning of',
      whatToKeep: 'Don\'t have them pack: valuables, medications, important docs',
      efficiency: 'Pros pack 3-5x faster than DIY'
    },
    vendorCategory: 'packing_services',
    accountabilityMoment: 'before_booking'
  },

  handyman_services: {
    id: 'handyman_services',
    title: 'Handyman Help',
    description: 'For move-related repairs and installations',
    category: 'services',
    steps: [
      'Identify what needs to be done',
      'Prioritize (what\'s needed vs. nice-to-have)',
      'Get quote through Peezy',
      'Schedule around move (before or after)'
    ],
    keyInfo: {
      common: 'Mount TVs, assemble furniture, minor repairs, hang fixtures',
      timing: 'After move-in unless repairs needed before moving out',
      pricing: '$50-100/hour typically'
    },
    vendorCategory: 'handyman',
    surfacingStyle: 'plant_seed'
  },

  appliance_services: {
    id: 'appliance_services',
    title: 'Appliance Installation',
    description: 'Install or connect appliances at new place',
    category: 'services',
    steps: [
      'Identify what needs installation (washer/dryer, dishwasher, etc.)',
      'Verify hookups exist at new place',
      'Schedule installation for move day or after'
    ],
    keyInfo: {
      washerDryer: 'Verify electric vs gas dryer, water hookups',
      fridge: 'Need 24 hours for ice maker after connecting water',
      timing: 'Day of or day after move'
    },
    vendorCategory: 'appliance_install',
    accountabilityMoment: 'before_booking'
  },

  furniture_assembly: {
    id: 'furniture_assembly',
    title: 'Furniture Assembly',
    description: 'Assemble furniture at new place',
    category: 'services',
    steps: [
      'Inventory what needs assembly',
      'Schedule for day after move',
      'Have all parts and instructions ready'
    ],
    keyInfo: {
      pricing: '$50-200 depending on complexity',
      timing: 'Day after move usually best',
      tips: 'Keep hardware in labeled bags taped to furniture'
    },
    vendorCategory: 'furniture_assembly',
    accountabilityMoment: 'before_booking'
  },

  // ============================================
  // ADMIN (8 workflows)
  // ============================================

  change_address: {
    id: 'change_address',
    title: 'Update Your Address',
    description: 'Complete guide to changing address everywhere',
    category: 'admin',
    steps: [
      'Start with USPS mail forwarding (most important)',
      'Update financial accounts (banks, credit cards)',
      'Update employer/HR',
      'Update insurance (auto, health, renters/home)',
      'Update government (DMV, voter registration)',
      'Update subscriptions and deliveries',
      'Update medical providers'
    ],
    checklist: [
      'USPS mail forwarding',
      'Banks and credit cards',
      'Employer/HR for tax purposes',
      'Auto insurance',
      'Health insurance',
      'Renters/Home insurance',
      'DMV (license and registration)',
      'Voter registration',
      'Amazon, subscriptions',
      'Doctor, dentist, pharmacy',
      'Gym membership',
      'Kids\' schools (if applicable)'
    ],
    keyInfo: {
      usps: 'Forward mail at movers.usps.com. Costs $1.10 online. Lasts 12 months.',
      timing: 'Start 2 weeks before move, continue after',
      dmv: 'Usually required within 30-60 days of move'
    },
    vendorCategory: null,
    accountabilityMoment: null
  },

  mail_forwarding: {
    id: 'mail_forwarding',
    title: 'Set Up Mail Forwarding',
    description: 'Ensure mail gets to new address',
    category: 'admin',
    steps: [
      'Go to movers.usps.com',
      'Enter old and new address',
      'Choose start date (can be move date or earlier)',
      'Pay $1.10 for identity verification',
      'Note: forwarding lasts 12 months, then update senders directly'
    ],
    keyInfo: {
      timing: 'Can set up before move to start on specific date',
      limitations: 'Some mail won\'t forward (official government mail, packages)',
      reminder: 'Update important senders directly after move'
    },
    vendorCategory: null,
    accountabilityMoment: null
  },

  school_transfer: {
    id: 'school_transfer',
    title: 'Handle School Transfer',
    description: 'Transfer kids to new school',
    category: 'admin',
    steps: [
      'Research schools in new area',
      'Contact new school district about enrollment',
      'Request records transfer from current school',
      'Complete registration paperwork',
      'Schedule any required assessments',
      'Tour new school if possible'
    ],
    keyInfo: {
      timing: 'Start 4-6 weeks before move. Some districts have deadlines.',
      documents: 'Birth certificate, immunization records, proof of address, previous school records',
      tips: 'Contact new school early - some have waitlists or specific enrollment windows'
    },
    vendorCategory: null,
    accountabilityMoment: null,
    conditions: ['hasKids: true']
  },

  update_insurance: {
    id: 'update_insurance',
    title: 'Update Insurance Policies',
    description: 'Make sure you\'re covered at new address',
    category: 'admin',
    steps: [
      'Contact auto insurance - address affects rates',
      'Update or get renters/homeowners insurance',
      'Verify health insurance covers new location',
      'Update life insurance beneficiary addresses'
    ],
    keyInfo: {
      auto: 'Rates can change significantly by location. Required to update.',
      renters: 'Need new policy for new address. Easy to get same day.',
      homeowners: 'If buying, required for closing. Shop around.',
      timing: 'Auto/renters: update effective move date. Home: needed at closing.'
    },
    vendorCategory: 'insurance',
    surfacingTriggers: ['insurance', 'coverage', 'policy']
  },

  dmv_tasks: {
    id: 'dmv_tasks',
    title: 'DMV Updates',
    description: 'License and registration updates',
    category: 'admin',
    steps: [
      'Check new state\'s requirements and timeline',
      'Update driver\'s license address',
      'Update vehicle registration',
      'If new state: may need new license and registration entirely'
    ],
    keyInfo: {
      timeline: 'Most states require update within 30-60 days',
      newState: 'May need to take new driving test, get vehicle inspected',
      sameState: 'Often can update online'
    },
    vendorCategory: null,
    accountabilityMoment: null
  },

  voter_registration: {
    id: 'voter_registration',
    title: 'Update Voter Registration',
    description: 'Register to vote at new address',
    category: 'admin',
    steps: [
      'Register at vote.gov',
      'Check registration deadline if election upcoming',
      'Cancel registration at old address if required'
    ],
    keyInfo: {
      timing: 'Deadlines vary by state, usually 15-30 days before election',
      online: 'Most states allow online registration'
    },
    vendorCategory: null,
    accountabilityMoment: null
  },

  medical_records: {
    id: 'medical_records',
    title: 'Transfer Medical Records',
    description: 'Get set up with healthcare in new area',
    category: 'admin',
    steps: [
      'Find new primary care doctor',
      'Request records transfer from current providers',
      'Transfer prescriptions to new pharmacy',
      'Find new specialists if needed'
    ],
    keyInfo: {
      records: 'Request copies - some charge a fee',
      prescriptions: 'Can often transfer by phone between pharmacies',
      timing: 'Don\'t wait until you need care',
      specialists: 'Get referrals from current doctors if possible'
    },
    vendorCategory: null,
    accountabilityMoment: null
  },

  subscription_updates: {
    id: 'subscription_updates',
    title: 'Update Subscriptions',
    description: 'Update delivery addresses for regular shipments',
    category: 'admin',
    steps: [
      'List all subscriptions with physical delivery',
      'Update addresses in each account',
      'Consider timing (some ship automatically)'
    ],
    common: [
      'Amazon',
      'Meal kits',
      'Pet food/supplies',
      'Vitamins/medications',
      'Beauty boxes',
      'Magazine subscriptions'
    ],
    vendorCategory: null,
    accountabilityMoment: null
  },

  // ============================================
  // HOUSING (6 workflows)
  // ============================================

  landlord_notice: {
    id: 'landlord_notice',
    title: 'Give Landlord Notice',
    description: 'Formally notify current landlord',
    category: 'housing',
    steps: [
      'Check lease for notice requirements (usually 30-60 days)',
      'Write formal notice letter',
      'Send via method specified in lease (often certified mail)',
      'Keep copy and proof of delivery',
      'Schedule move-out inspection if required'
    ],
    template: `[Your Name]
[Your Address]
[Date]

[Landlord Name]
[Landlord Address]

Dear [Landlord Name],

This letter serves as formal notice that I will be vacating [apartment address] on [move-out date]. This provides [X] days notice as required by my lease.

Please let me know how to schedule a final walk-through and return keys.

Thank you,
[Your Name]`,
    keyInfo: {
      timing: 'Check lease! Usually 30-60 days required.',
      delivery: 'Certified mail with return receipt OR email with read receipt',
      record: 'Keep copies of everything'
    },
    vendorCategory: null,
    conditions: ['originOwnership: rent']
  },

  security_deposit: {
    id: 'security_deposit',
    title: 'Get Security Deposit Back',
    description: 'Maximize deposit return',
    category: 'housing',
    steps: [
      'Review lease for move-out requirements',
      'Document condition with photos/video before cleaning',
      'Deep clean or hire cleaners',
      'Complete any minor repairs (patch nail holes, etc.)',
      'Schedule walk-through with landlord',
      'Document everything during walk-through',
      'Know your rights (deposit return timeline varies by state)'
    ],
    keyInfo: {
      cleaning: 'Deep clean pays for itself in deposit return',
      documentation: 'Photos dated before move-out are crucial for disputes',
      timeline: 'Most states require deposit return within 14-30 days',
      disputes: 'If deductions seem unfair, you can dispute in small claims court'
    },
    vendorCategory: 'cleaning',
    surfacingTriggers: ['deposit', 'get money back', 'cleaning']
  },

  home_inspection: {
    id: 'home_inspection',
    title: 'Schedule Home Inspection',
    description: 'Get new home inspected before closing',
    category: 'housing',
    steps: [
      'Hire licensed inspector',
      'Attend inspection if possible',
      'Review report carefully',
      'Negotiate repairs or price based on findings',
      'Re-inspect if repairs were made'
    ],
    keyInfo: {
      cost: 'Typically $300-500',
      timing: 'Usually within 7-10 days of offer acceptance',
      attendance: 'Try to attend - you\'ll learn a lot about the house',
      findings: 'Basis for negotiation or walking away if major issues'
    },
    vendorCategory: 'home_inspection',
    conditions: ['destinationOwnership: own']
  },

  closing_prep: {
    id: 'closing_prep',
    title: 'Prepare for Closing',
    description: 'Get ready to close on new home',
    category: 'housing',
    steps: [
      'Review closing disclosure',
      'Prepare funds for closing (cashier\'s check or wire)',
      'Schedule final walk-through',
      'Gather required documents',
      'Confirm closing time and location'
    ],
    keyInfo: {
      funds: 'Wire fraud is common - verify wire instructions via phone',
      walkThrough: 'Usually day before or morning of closing',
      documents: 'Government ID, proof of insurance, any outstanding items requested'
    },
    vendorCategory: null,
    conditions: ['destinationOwnership: own']
  },

  walkthrough: {
    id: 'walkthrough',
    title: 'Final Walk-Through',
    description: 'Inspect property before closing/move-in',
    category: 'housing',
    steps: [
      'Check all agreed repairs were completed',
      'Test appliances, HVAC, water',
      'Check for any new damage',
      'Verify sellers have vacated and cleaned',
      'Note any issues before closing'
    ],
    keyInfo: {
      timing: 'Day before or morning of closing',
      issues: 'If issues found, can delay closing until resolved',
      documentation: 'Photos of any problems'
    },
    vendorCategory: null,
    accountabilityMoment: null
  },

  new_home_setup: {
    id: 'new_home_setup',
    title: 'Set Up New Home',
    description: 'First things to do at new place',
    category: 'housing',
    steps: [
      'Change locks (always)',
      'Deep clean before unpacking',
      'Test all utilities',
      'Check smoke/CO detectors',
      'Locate main water shutoff, electrical panel',
      'Update smart home devices'
    ],
    keyInfo: {
      locks: 'Even if new construction - multiple people had keys',
      safety: 'Smoke detectors, fire extinguisher, CO detector',
      shutoffs: 'Know where water and electrical shutoffs are'
    },
    vendorCategory: 'locksmith',
    surfacingTriggers: ['change locks', 'security']
  },

  // ============================================
  // PACKING (6 workflows)
  // ============================================

  packing_supplies: {
    id: 'packing_supplies',
    title: 'Get Packing Supplies',
    description: 'Everything needed for packing',
    category: 'packing',
    steps: [
      'Estimate how many boxes needed',
      'Get variety of sizes',
      'Don\'t forget tape, bubble wrap, markers',
      'Consider specialty boxes (wardrobe, dish pack)',
      'Can buy or get free boxes'
    ],
    supplies: {
      small: 'Books, heavy items. Get plenty of these.',
      medium: 'General items, kitchen stuff. Most used size.',
      large: 'Light bulky items (linens, pillows). Don\'t overpack with heavy stuff.',
      wardrobe: 'Keep clothes on hangers. Worth the investment.',
      dishPack: 'Extra protection for fragile kitchen items.'
    },
    estimator: {
      studio: '10-20 boxes',
      oneBed: '20-40 boxes',
      twoBed: '40-60 boxes',
      threeBed: '60-80 boxes',
      fourBed: '80-120 boxes'
    },
    freeBoxes: [
      'Liquor stores (sturdy, divided)',
      'Bookstores',
      'Facebook marketplace, Craigslist',
      'Nextdoor',
      'U-Haul box exchange'
    ],
    vendorCategory: null,
    accountabilityMoment: null
  },

  declutter: {
    id: 'declutter',
    title: 'Declutter Before Packing',
    description: 'Get rid of stuff before you pack it',
    category: 'packing',
    steps: [
      'Go room by room',
      'Use the 4-box method: keep, donate, sell, trash',
      'Be ruthless - if you haven\'t used it in a year...',
      'Start with easiest areas (garage, closets)',
      'Schedule junk removal for what\'s left'
    ],
    tips: [
      'Don\'t pay to move things you don\'t want',
      'Moving is the best time to purge',
      'Sentimental items: take photos before letting go',
      'Sell valuable items early (eBay, Facebook, consignment)'
    ],
    vendorCategory: 'junk_removal',
    surfacingTriggers: ['too much stuff', 'overwhelmed', 'where to start']
  },

  start_packing: {
    id: 'start_packing',
    title: 'Start Packing',
    description: 'Begin the packing process strategically',
    category: 'packing',
    steps: [
      'Start with rooms you use least',
      'Pack off-season items first',
      'Label every box (contents AND destination room)',
      'Keep essentials box separate',
      'Take photos of electronics setup before disconnecting'
    ],
    packingOrder: [
      '1. Storage areas, garage, attic',
      '2. Guest rooms, decor items',
      '3. Books, collections, rarely used items',
      '4. Most of each room',
      '5. Kitchen (last, but leave essentials)',
      '6. Bathroom essentials (morning of move)'
    ],
    tips: [
      'Pack heavy items in small boxes',
      'Wrap dishes individually, pack vertically',
      'Don\'t leave empty space (paper fill)',
      'Keep hardware with furniture (tape to back)'
    ],
    vendorCategory: null,
    accountabilityMoment: null
  },

  pack_fragile: {
    id: 'pack_fragile',
    title: 'Pack Fragile Items',
    description: 'Protect breakables during the move',
    category: 'packing',
    steps: [
      'Gather supplies (bubble wrap, packing paper, dish boxes)',
      'Wrap each item individually',
      'Pack tightly (no shifting)',
      'Mark boxes FRAGILE and THIS SIDE UP',
      'Consider professional packing for valuables'
    ],
    tips: {
      dishes: 'Wrap individually, pack vertically like records',
      glasses: 'Stuff inside with paper, wrap entire glass',
      mirrors: 'X tape across glass, wrap in blankets',
      electronics: 'Original boxes if you have them, otherwise lots of padding',
      artwork: 'Specialty picture boxes or custom crating for valuable pieces'
    },
    vendorCategory: 'packing_services',
    surfacingTriggers: ['fragile', 'worried about breaking', 'valuable']
  },

  essentials_box: {
    id: 'essentials_box',
    title: 'Pack Essentials Box',
    description: 'The stuff you need access to immediately',
    category: 'packing',
    steps: [
      'Pack last, unpack first',
      'Keep with you (not in moving truck)',
      'Include everything for first 24-48 hours'
    ],
    contents: [
      'Phone chargers',
      'Toiletries',
      'Medications',
      'Change of clothes',
      'Basic tools (screwdriver, scissors, box cutter)',
      'Snacks and water',
      'Important documents',
      'Laptop/tablet',
      'Pet supplies if applicable',
      'Kids\' essentials if applicable',
      'Sheets and towels for first night',
      'Toilet paper'
    ],
    vendorCategory: null,
    accountabilityMoment: null
  },

  labeling_system: {
    id: 'labeling_system',
    title: 'Box Labeling System',
    description: 'Make unpacking easier',
    category: 'packing',
    steps: [
      'Choose a system and stick to it',
      'Label all sides of boxes',
      'Include contents AND destination room',
      'Consider color coding by room'
    ],
    systems: {
      simple: 'Write room name and general contents on top and one side',
      numbered: 'Numbered boxes with master list of contents',
      colorCoded: 'Colored tape or markers by room',
      detailed: 'Itemized list on each box'
    },
    vendorCategory: null,
    accountabilityMoment: null
  }
};

// Get workflow by ID
function getWorkflow(id) {
  return WORKFLOWS[id] || null;
}

// Get all workflows by category
function getWorkflowsByCategory(category) {
  return Object.values(WORKFLOWS).filter(w => w.category === category);
}

// Get workflows with vendor connections
function getVendorWorkflows() {
  return Object.values(WORKFLOWS).filter(w => w.vendorCategory);
}

// Export
module.exports = {
  WORKFLOWS,
  getWorkflow,
  getWorkflowsByCategory,
  getVendorWorkflows
};
