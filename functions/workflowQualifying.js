// workflowQualifying.js
// Qualifying questions for vendor matching workflows
// Add to your Firebase functions folder

const WORKFLOW_QUALIFYING = {

  // ============================================
  // BOOK MOVERS
  // ============================================
  "book_movers": {
    workflowId: "book_movers",
    intro: {
      title: "Let's find the right movers",
      subtitle: "A few quick questions so we can match you with companies that fit your move."
    },
    // SET FROM ASSESSMENT (not asked, passed to matching):
    // - Service area (current + new addresses)
    // - Interstate flag
    // - Packing preference (full/kitchen/both/none)
    // - Home size (bedrooms + sqft)
    questions: [
      {
        id: "locally_owned",
        question: "Do you prefer working with a locally owned company?",
        type: "single_select",
        options: [
          { id: "yes", label: "Yes, prefer local", icon: "building.2" },
          { id: "no_preference", label: "No preference", icon: "hand.thumbsup" }
        ]
      },
      {
        id: "special_items",
        question: "Do you have any of these items that need special handling?",
        subtitle: "These require specific equipment and expertise. Select all that apply.",
        type: "multi_select",
        options: [
          { id: "piano", label: "Piano or organ", icon: "pianokeys" },
          { id: "safe", label: "Gun safe or large safe", icon: "lock.shield" },
          { id: "hot_tub", label: "Hot tub or spa", icon: "drop.fill" },
          { id: "pool_table", label: "Pool table", icon: "circle.grid.3x3" },
          { id: "art", label: "Large art or antiques", icon: "photo.artframe" },
          { id: "none", label: "None of these", icon: "xmark.circle" }
        ]
      },
      {
        id: "insurance_preference",
        question: "Industry standard coverage is just $0.60 per pound — a 50lb TV worth $800 would only be covered for $30. Want to see movers who offer full-value protection?",
        type: "single_select",
        options: [
          { id: "full_value", label: "Yes, I want full-value coverage", icon: "shield.checkered" },
          { id: "standard", label: "No, standard is fine", icon: "shield" }
        ]
      }
    ],
    questionCount: 3,
    recap: {
      title: "Got it — here's what I'm looking for",
      closing: "I'll match you with movers who fit your specific needs and get you quotes.",
      button: "Find my movers"
    }
  },

  // ============================================
  // BOOK LONG-DISTANCE MOVERS
  // ============================================
  "book_long_distance_movers": {
    intro: {
      title: "Long-distance moves need the right team",
      subtitle: "Let me match you with movers who specialize in cross-country relocations. This takes about a minute."
    },
    questions: [
      {
        id: "priority",
        question: "What's most important?",
        type: "single_select",
        options: [
          { id: "price", label: "Best Price", subtitle: "Budget is tight", icon: "dollarsign.circle.fill" },
          { id: "speed", label: "Fastest Delivery", subtitle: "Need it ASAP", icon: "clock.fill" },
          { id: "care", label: "White Glove Care", subtitle: "Handle with care", icon: "hands.sparkles.fill" },
          { id: "tracking", label: "Real-Time Tracking", subtitle: "Know where it is", icon: "location.fill" }
        ]
      },
      {
        id: "estimate_type",
        question: "How should pricing work?",
        type: "single_select",
        subtitle: "This affects your final bill",
        options: [
          { id: "binding", label: "Binding Estimate", subtitle: "Locked price, no surprises", icon: "lock.fill" },
          { id: "not_binding", label: "Non-Binding", subtitle: "May change based on actual weight", icon: "scale.3d" },
          { id: "not_sure", label: "Not Sure", subtitle: "Help me decide", icon: "questionmark.circle.fill" }
        ]
      },
      {
        id: "special_items",
        question: "Any specialty items?",
        type: "multi_select",
        options: [
          { id: "piano", label: "Piano", icon: "pianokeys" },
          { id: "vehicle", label: "Vehicle to Ship", icon: "car.fill" },
          { id: "art", label: "Fine Art", icon: "photo.artframe" },
          { id: "antiques", label: "Antiques", icon: "clock.fill" },
          { id: "none", label: "Standard Household", icon: "checkmark.circle.fill", exclusive: true }
        ]
      },
      {
        id: "packing_service",
        question: "Packing services?",
        type: "single_select",
        options: [
          { id: "full", label: "Full Pack & Unpack", subtitle: "Complete service", icon: "shippingbox.fill" },
          { id: "pack_only", label: "Packing Only", subtitle: "I'll unpack myself", icon: "shippingbox" },
          { id: "fragile", label: "Fragile Items Only", icon: "wineglass" },
          { id: "none", label: "No Packing Needed", icon: "xmark.circle.fill" }
        ]
      },
      {
        id: "timeline_flexibility",
        question: "How flexible is your timeline?",
        type: "single_select",
        subtitle: "Flexibility can mean better prices",
        options: [
          { id: "exact", label: "Exact Date", subtitle: "Must be this day", icon: "calendar.badge.exclamationmark" },
          { id: "window_3", label: "3-Day Window", subtitle: "Some flexibility", icon: "calendar" },
          { id: "window_7", label: "Week Window", subtitle: "Very flexible", icon: "calendar.badge.plus" }
        ]
      }
    ],
    recap: {
      title: "Perfect. Here's your move profile:",
      closing: "I'm contacting licensed long-distance carriers now. Expect detailed quotes within 48 hours.",
      button: "Get My Quotes"
    },
    matching: {
      priorityWeight: 0.35,
      estimateTypeWeight: 0.25,
      specialItemsWeight: 0.2,
      packingWeight: 0.1,
      flexibilityWeight: 0.1
    }
  },

  // ============================================
  // CLEANING SERVICE
  // ============================================
  "cleaning_service": {
    intro: {
      title: "Let's get you a sparkling clean",
      subtitle: "Quick questions to find cleaners who match your needs."
    },
    questions: [
      {
        id: "which_place",
        question: "Which place needs cleaning?",
        type: "single_select",
        options: [
          { id: "old", label: "Old Place", subtitle: "Move-out clean", icon: "door.left.hand.open" },
          { id: "new", label: "New Place", subtitle: "Before unpacking", icon: "door.right.hand.open" },
          { id: "both", label: "Both Places", subtitle: "Full service", icon: "arrow.left.arrow.right" }
        ]
      },
      {
        id: "clean_level",
        question: "What level of clean?",
        type: "single_select",
        options: [
          { id: "standard", label: "Standard Clean", subtitle: "Surface cleaning, vacuum, mop", icon: "sparkles" },
          { id: "deep", label: "Deep Clean", subtitle: "Inside cabinets, appliances, baseboards", icon: "bubbles.and.sparkles.fill" },
          { id: "move_out", label: "Move-Out Special", subtitle: "Get your deposit back", icon: "dollarsign.circle.fill" }
        ]
      },
      {
        id: "focus_areas",
        question: "Any areas need extra attention?",
        type: "multi_select",
        options: [
          { id: "kitchen", label: "Kitchen", subtitle: "Appliances, grease", icon: "refrigerator.fill" },
          { id: "bathrooms", label: "Bathrooms", subtitle: "Tile, grout, fixtures", icon: "shower.fill" },
          { id: "windows", label: "Windows", subtitle: "Inside and out", icon: "window.horizontal" },
          { id: "carpet", label: "Carpet", subtitle: "Steam cleaning", icon: "square.fill" },
          { id: "none", label: "Even Attention", icon: "checkmark.circle.fill", exclusive: true }
        ]
      },
      {
        id: "timing",
        question: "When do you need it?",
        type: "single_select",
        options: [
          { id: "asap", label: "ASAP", subtitle: "Within 48 hours", icon: "bolt.fill" },
          { id: "this_week", label: "This Week", icon: "calendar" },
          { id: "scheduled", label: "Specific Date", subtitle: "Tied to move date", icon: "calendar.badge.clock" }
        ]
      }
    ],
    recap: {
      title: "Here's your cleaning request:",
      closing: "I'll have quotes from top-rated cleaners within 24 hours.",
      button: "Get Quotes"
    },
    matching: {
      placeWeight: 0.2,
      levelWeight: 0.35,
      focusWeight: 0.25,
      timingWeight: 0.2
    }
  },

  // ============================================
  // JUNK REMOVAL
  // ============================================
  "junk_removal": {
    intro: {
      title: "Let's get rid of the stuff you don't need",
      subtitle: "A few questions to get you an accurate quote."
    },
    questions: [
      {
        id: "volume",
        question: "How much stuff?",
        type: "single_select",
        options: [
          { id: "few_items", label: "A Few Items", subtitle: "Fits in a car", icon: "archivebox" },
          { id: "partial", label: "Partial Truck", subtitle: "Couch, mattress, some boxes", icon: "box.truck" },
          { id: "full", label: "Full Truck", subtitle: "Garage cleanout, lots of stuff", icon: "box.truck.fill" },
          { id: "not_sure", label: "Not Sure", subtitle: "Need an estimate", icon: "questionmark.circle.fill" }
        ]
      },
      {
        id: "item_types",
        question: "What kinds of items?",
        type: "multi_select",
        options: [
          { id: "furniture", label: "Furniture", icon: "sofa.fill" },
          { id: "appliances", label: "Appliances", icon: "refrigerator.fill" },
          { id: "mattress", label: "Mattress/Box Spring", icon: "bed.double.fill" },
          { id: "electronics", label: "Electronics", icon: "tv.fill" },
          { id: "yard", label: "Yard Waste", icon: "leaf.fill" },
          { id: "general", label: "General Junk", icon: "trash.fill" }
        ]
      },
      {
        id: "location",
        question: "Where is everything?",
        type: "single_select",
        options: [
          { id: "curb", label: "At the Curb", subtitle: "Easy access", icon: "road.lanes" },
          { id: "garage", label: "Garage/Driveway", icon: "car.garage.fill" },
          { id: "inside", label: "Inside the Home", subtitle: "They'll haul it out", icon: "house.fill" },
          { id: "multiple", label: "Multiple Spots", icon: "arrow.triangle.branch" }
        ]
      },
      {
        id: "timing",
        question: "When do you need pickup?",
        type: "single_select",
        options: [
          { id: "asap", label: "ASAP", subtitle: "Within 48 hours", icon: "bolt.fill" },
          { id: "before_move", label: "Before Move Day", subtitle: "Coordinate with timeline", icon: "calendar" },
          { id: "flexible", label: "Flexible", subtitle: "Best price wins", icon: "clock.fill" }
        ]
      }
    ],
    recap: {
      title: "Here's what we're removing:",
      closing: "I'll get you quotes from haulers who can handle this. Usually within a few hours.",
      button: "Get Quotes"
    },
    matching: {
      volumeWeight: 0.4,
      itemTypesWeight: 0.25,
      locationWeight: 0.15,
      timingWeight: 0.2
    }
  },

  // ============================================
  // INTERNET SETUP
  // ============================================
  "internet_setup": {
    intro: {
      title: "Let's get you connected",
      subtitle: "I'll find the best internet options at your new address."
    },
    questions: [
      {
        id: "usage",
        question: "What's your internet mainly for?",
        type: "single_select",
        options: [
          { id: "work", label: "Work From Home", subtitle: "Video calls, uploads", icon: "laptopcomputer" },
          { id: "streaming", label: "Streaming", subtitle: "Netflix, gaming", icon: "play.tv.fill" },
          { id: "basic", label: "Basic Use", subtitle: "Email, browsing", icon: "globe" },
          { id: "heavy", label: "Heavy Everything", subtitle: "Multiple users, all the above", icon: "wifi" }
        ]
      },
      {
        id: "priority",
        question: "What matters most?",
        type: "single_select",
        options: [
          { id: "speed", label: "Fastest Speed", subtitle: "Pay more, get more", icon: "bolt.fill" },
          { id: "price", label: "Best Price", subtitle: "Budget-friendly", icon: "dollarsign.circle.fill" },
          { id: "reliability", label: "Most Reliable", subtitle: "No dropouts", icon: "checkmark.shield.fill" },
          { id: "no_contract", label: "No Contract", subtitle: "Flexibility", icon: "xmark.circle.fill" }
        ]
      },
      {
        id: "current_provider",
        question: "Current internet provider?",
        type: "single_select",
        subtitle: "Sometimes we can transfer or get switch deals",
        options: [
          { id: "xfinity", label: "Xfinity/Comcast", icon: "dot.radiowaves.left.and.right" },
          { id: "att", label: "AT&T", icon: "antenna.radiowaves.left.and.right" },
          { id: "verizon", label: "Verizon Fios", icon: "fibrechannel" },
          { id: "spectrum", label: "Spectrum", icon: "wifi" },
          { id: "other", label: "Other / None", icon: "questionmark.circle.fill" }
        ]
      },
      {
        id: "extras",
        question: "Need any extras?",
        type: "multi_select",
        options: [
          { id: "tv", label: "TV Package", icon: "tv.fill" },
          { id: "phone", label: "Home Phone", icon: "phone.fill" },
          { id: "mesh", label: "Whole-Home WiFi", subtitle: "Mesh system", icon: "wifi.circle.fill" },
          { id: "none", label: "Just Internet", icon: "checkmark.circle.fill", exclusive: true }
        ]
      }
    ],
    recap: {
      title: "Here's what you need:",
      closing: "I'll check availability at your new address and set up the best option. Usually ready for move-in day.",
      button: "Find My Options"
    },
    matching: {
      usageWeight: 0.35,
      priorityWeight: 0.35,
      currentProviderWeight: 0.1,
      extrasWeight: 0.2
    }
  },

  // ============================================
  // BOOK CLEANERS
  // ============================================
  "book_cleaners": {
    workflowId: "book_cleaners",
    intro: {
      title: "Let's find the right cleaners",
      subtitle: "Just a couple questions to match you with the right service."
    },
    // SET FROM ASSESSMENT:
    // - Service area (current address)
    // - Home size (bedrooms + sqft)
    questions: [
      {
        id: "locally_owned",
        question: "Do you prefer working with a locally owned company?",
        type: "single_select",
        options: [
          { id: "yes", label: "Yes, prefer local", icon: "building.2" },
          { id: "no_preference", label: "No preference", icon: "hand.thumbsup" }
        ]
      },
      {
        id: "service_level",
        question: "What level of cleaning do you need?",
        subtitle: "Select all that apply — some companies offer package deals.",
        type: "multi_select",
        options: [
          { id: "standard", label: "Standard move-out clean", icon: "sparkles" },
          { id: "deep", label: "Deep clean (baseboards, inside appliances, windows)", icon: "bubbles.and.sparkles" },
          { id: "carpet", label: "Carpet cleaning", icon: "square.grid.3x3.topleft.filled" },
          { id: "move_in", label: "Move-in clean at new place", icon: "house" }
        ]
      }
    ],
    questionCount: 2,
    recap: {
      title: "Perfect — I know what you need",
      closing: "I'll find cleaners who can handle everything you selected.",
      button: "Find my cleaners"
    }
  },

  // ============================================
  // REMOVE ITEMS (donation + junk removal routing)
  // ============================================
  "remove_items": {
    workflowId: "remove_items",
    intro: {
      title: "Let's figure out the best way to get rid of these items",
      subtitle: "A few questions to find the right option for you."
    },
    // SET FROM ASSESSMENT:
    // - Service area (current address)
    questions: [
      {
        id: "removal_route",
        question: "What are you looking to do with these items?",
        type: "single_select",
        options: [
          { id: "donate", label: "Donate them", icon: "heart" },
          { id: "haul_away", label: "Have them hauled away", icon: "truck.box" },
          { id: "not_sure", label: "Not sure — help me decide", icon: "questionmark.circle" }
        ]
      },
      {
        id: "item_categories",
        question: "What types of items are we talking about?",
        subtitle: "Select all that apply.",
        type: "multi_select",
        options: [
          { id: "furniture", label: "Furniture", icon: "sofa" },
          { id: "appliances", label: "Appliances", icon: "refrigerator" },
          { id: "electronics", label: "Electronics", icon: "desktopcomputer" },
          { id: "clothing", label: "Clothing", icon: "tshirt" },
          { id: "mattresses", label: "Mattresses", icon: "bed.double" },
          { id: "household", label: "Household items", icon: "house" },
          { id: "yard_waste", label: "Yard waste", icon: "leaf" },
          { id: "debris", label: "Construction debris", icon: "hammer" },
          { id: "other", label: "Other / mixed", icon: "shippingbox" }
        ]
      },
      {
        id: "item_condition",
        question: "What condition are most of the items in?",
        type: "single_select",
        options: [
          { id: "like_new", label: "Like new", icon: "star.fill" },
          { id: "gently_used", label: "Gently used", icon: "star.leadinghalf.filled" },
          { id: "worn", label: "Worn but functional", icon: "star" },
          { id: "needs_repair", label: "Needs repair", icon: "wrench" }
        ]
      },
      {
        id: "quantity",
        question: "How much stuff are we talking about?",
        type: "single_select",
        options: [
          { id: "few_small", label: "A few small items", icon: "bag" },
          { id: "several_large", label: "Several large items", icon: "shippingbox" },
          { id: "full_room", label: "A full room's worth", icon: "sofa.fill" },
          { id: "multiple_rooms", label: "Multiple rooms", icon: "building.2" }
        ]
      },
      {
        id: "item_location",
        question: "Where are the items right now?",
        type: "single_select",
        options: [
          { id: "ground_floor", label: "Inside home — ground floor", icon: "house" },
          { id: "upstairs", label: "Inside home — upstairs, basement, or attic", icon: "stairs" },
          { id: "garage", label: "Garage", icon: "car.garage" },
          { id: "curbside", label: "Curbside or driveway", icon: "road.lanes" }
        ]
      },
      {
        id: "pickup_preference",
        question: "Can you drop items off, or do you need them picked up?",
        type: "single_select",
        options: [
          { id: "need_pickup", label: "I need pickup", icon: "truck.box" },
          { id: "can_dropoff", label: "I can drop off", icon: "arrow.down.to.line" },
          { id: "either", label: "Either works", icon: "arrow.left.arrow.right" }
        ]
      }
    ],
    questionCount: 6,
    recap: {
      title: "Got it — I'll find the best option",
      closing: "Based on your answers, I'll match you with the right service to get these items taken care of.",
      button: "Find my options"
    }
  },

  // ============================================
  // SELL ITEMS
  // ============================================
  "sell_items": {
    workflowId: "sell_items",
    intro: {
      title: "Let's help you sell these items",
      subtitle: "A few questions so we can point you in the right direction."
    },
    questions: [
      {
        id: "item_categories",
        question: "What are you looking to sell?",
        subtitle: "Select all that apply.",
        type: "multi_select",
        options: [
          { id: "furniture", label: "Furniture", icon: "sofa" },
          { id: "electronics", label: "Electronics", icon: "desktopcomputer" },
          { id: "clothing", label: "Clothing", icon: "tshirt" },
          { id: "appliances", label: "Appliances", icon: "refrigerator" },
          { id: "collectibles", label: "Collectibles or valuables", icon: "tag" },
          { id: "other", label: "Other", icon: "shippingbox" }
        ]
      },
      {
        id: "estimated_value",
        question: "Roughly, what do you think everything is worth?",
        type: "single_select",
        options: [
          { id: "under_500", label: "Under $500", icon: "dollarsign.circle" },
          { id: "500_2000", label: "$500 – $2,000", icon: "dollarsign.circle.fill" },
          { id: "2000_5000", label: "$2,000 – $5,000", icon: "banknote" },
          { id: "over_5000", label: "$5,000+", icon: "banknote.fill" }
        ]
      },
      {
        id: "platforms",
        question: "Which platforms are you open to?",
        subtitle: "Select all you'd be willing to use.",
        type: "multi_select",
        options: [
          { id: "fb_marketplace", label: "Facebook Marketplace", icon: "storefront" },
          { id: "offerup", label: "OfferUp", icon: "tag" },
          { id: "craigslist", label: "Craigslist", icon: "list.bullet" },
          { id: "consignment", label: "Consignment store", icon: "building.columns" },
          { id: "any", label: "Any of them", icon: "checkmark.circle" }
        ]
      }
    ],
    questionCount: 3,
    recap: {
      title: "Nice — let's get these sold",
      closing: "I'll put together a game plan based on what you're selling and where.",
      button: "Get my selling plan"
    }
  },

  // ============================================
  // SETUP INTERNET
  // ============================================
  "setup_internet": {
    workflowId: "setup_internet",
    intro: {
      title: "Let's get your internet sorted",
      subtitle: "A few questions to find the best provider and plan for your new place."
    },
    // SET FROM ASSESSMENT:
    // - Service area (new address)
    questions: [
      {
        id: "usage",
        question: "How would you describe your internet usage?",
        type: "single_select",
        options: [
          { id: "light", label: "Light — email and browsing", icon: "envelope" },
          { id: "moderate", label: "Moderate — streaming and video calls", icon: "play.tv" },
          { id: "heavy", label: "Heavy — gaming, large downloads, multiple streamers", icon: "gamecontroller" },
          { id: "home_office", label: "Home office — need rock-solid reliability", icon: "desktopcomputer" }
        ]
      },
      {
        id: "people_devices",
        question: "How many people and devices will be on the network?",
        type: "single_select",
        options: [
          { id: "1_2", label: "1–2", icon: "person" },
          { id: "3_5", label: "3–5", icon: "person.2" },
          { id: "6_plus", label: "6+", icon: "person.3" }
        ]
      },
      {
        id: "contract_preference",
        question: "How do you feel about contracts?",
        type: "single_select",
        options: [
          { id: "month_to_month", label: "Month-to-month only", icon: "calendar" },
          { id: "1_year", label: "1 year is fine", icon: "calendar.badge.clock" },
          { id: "2_year", label: "2 years is fine", icon: "calendar.badge.checkmark" },
          { id: "no_preference", label: "No preference", icon: "hand.thumbsup" }
        ]
      }
    ],
    questionCount: 3,
    recap: {
      title: "Got it — let me check what's available",
      closing: "I'll find the best internet options at your new address based on your needs.",
      button: "Find my internet"
    }
  },

  // ============================================
  // RENT TRUCK
  // ============================================
  "rent_truck": {
    workflowId: "rent_truck",
    intro: {
      title: "Let's find the right truck",
      subtitle: "A few details to get you the best rental options."
    },
    // SET FROM ASSESSMENT:
    // - Service area (current + new addresses)
    // - Home size (sqft → truck size estimate)
    // - Move distance (determines one-way default for >100mi or round-trip for <50mi)
    // - Has storage (determines if storage question shows)
    questions: [
      {
        id: "storage_same_trip",
        question: "Are you picking up items from a storage unit on the same trip?",
        subtitle: "This affects the truck size and route.",
        type: "single_select",
        options: [
          { id: "yes", label: "Yes, same trip", icon: "archivebox" },
          { id: "no", label: "No", icon: "xmark.circle" }
        ]
      },
      {
        id: "trip_type",
        question: "One-way or round-trip?",
        subtitle: "One-way means you drop the truck off at your destination. Round-trip means you return it to the pickup location.",
        type: "single_select",
        options: [
          { id: "one_way", label: "One-way", icon: "arrow.right" },
          { id: "round_trip", label: "Round-trip", icon: "arrow.triangle.2.circlepath" },
          { id: "not_sure", label: "Not sure", icon: "questionmark.circle" }
        ]
      },
      {
        id: "towing_vehicle",
        question: "Will you need to tow a vehicle behind the truck?",
        type: "single_select",
        options: [
          { id: "yes", label: "Yes", icon: "car" },
          { id: "no", label: "No", icon: "xmark.circle" }
        ]
      },
      {
        id: "days_needed",
        question: "How many days do you need the truck?",
        type: "single_select",
        options: [
          { id: "moving_day", label: "Just moving day", icon: "sun.max" },
          { id: "2_3_days", label: "2–3 days", icon: "calendar.badge.plus" },
          { id: "full_week", label: "Full week", icon: "calendar" },
          { id: "not_sure", label: "Not sure yet", icon: "questionmark.circle" }
        ]
      }
    ],
    questionCount: 4,
    recap: {
      title: "Perfect — I'll find your truck",
      closing: "I'll compare options from the major rental companies and get you the best deal.",
      button: "Find my truck"
    }
  }

};

// Helper function to get qualifying data for a workflow
function getWorkflowQualifying(workflowId) {
  return WORKFLOW_QUALIFYING[workflowId] || null;
}

// Export for Firebase functions
module.exports = {
  WORKFLOW_QUALIFYING,
  getWorkflowQualifying
};
