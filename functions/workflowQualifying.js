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
        id: "heavy_items",
        question: "Do you have any really heavy items?",
        subtitle: "These require special equipment and crew.",
        type: "multi_select",
        options: [
          { id: "piano", label: "Piano / Organ", icon: "pianokeys" },
          { id: "safe", label: "Gun Safe / Safe", icon: "lock.shield" },
          { id: "hot_tub", label: "Hot Tub / Spa", icon: "drop.fill" },
          { id: "none", label: "Nothing heavy", icon: "checkmark.circle.fill", exclusive: true }
        ]
      },
      {
        id: "fragile_items",
        question: "Any delicate or high-value items?",
        subtitle: "These need extra care during transport.",
        type: "multi_select",
        options: [
          { id: "pool_table", label: "Pool Table", icon: "circle.grid.3x3" },
          { id: "art", label: "Art / Antiques", icon: "photo.artframe" },
          { id: "glass", label: "Large Mirrors / Glass", icon: "rectangle" },
          { id: "none", label: "Nothing fragile", icon: "checkmark.circle.fill", exclusive: true }
        ]
      },
      {
        id: "insurance_context",
        question: "A quick note on moving insurance",
        subtitle: "Industry standard coverage is only $0.60 per pound. That means a 50lb TV worth $800 would only be covered for $30.",
        type: "single_select",
        options: []
      },
      {
        id: "insurance_preference",
        question: "Want full-value moving insurance?",
        subtitle: "Standard coverage is only $0.60/lb — a $800 TV would be covered for just $30.",
        type: "single_select",
        options: [
          { id: "full_value", label: "Yes, full coverage", icon: "shield.checkered" },
          { id: "standard", label: "No, standard is fine", icon: "shield" }
        ]
      }
    ],
    questionCount: 5,
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
        id: "heavy_items",
        question: "Any oversized or heavy items?",
        type: "multi_select",
        options: [
          { id: "piano", label: "Piano", icon: "pianokeys" },
          { id: "vehicle", label: "Vehicle to Ship", icon: "car.fill" },
          { id: "none", label: "Standard items", icon: "checkmark.circle.fill", exclusive: true }
        ]
      },
      {
        id: "fragile_items",
        question: "Any high-value or fragile items?",
        type: "multi_select",
        options: [
          { id: "art", label: "Fine Art", icon: "photo.artframe" },
          { id: "antiques", label: "Antiques", icon: "clock.fill" },
          { id: "none", label: "Standard items", icon: "checkmark.circle.fill", exclusive: true }
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
        id: "focus_rooms",
        question: "Any rooms need extra attention?",
        type: "multi_select",
        options: [
          { id: "kitchen", label: "Kitchen", subtitle: "Appliances, grease", icon: "refrigerator.fill" },
          { id: "bathrooms", label: "Bathrooms", subtitle: "Tile, grout, fixtures", icon: "shower.fill" },
          { id: "none", label: "Even attention", icon: "checkmark.circle.fill", exclusive: true }
        ]
      },
      {
        id: "focus_extras",
        question: "Any add-on services?",
        type: "multi_select",
        options: [
          { id: "windows", label: "Windows", subtitle: "Inside and out", icon: "window.horizontal" },
          { id: "carpet", label: "Carpet Cleaning", subtitle: "Steam cleaning", icon: "square.fill" },
          { id: "none", label: "No extras", icon: "checkmark.circle.fill", exclusive: true }
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
        subtitle: "Select all that apply.",
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
          { id: "mattresses", label: "Mattresses", icon: "bed.double" },
          { id: "household", label: "Household / clothing", icon: "house" },
          { id: "outdoor", label: "Outdoor / debris", icon: "leaf" }
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
        id: "trip_type_context",
        question: "One-way vs. round-trip",
        type: "single_select",
        options: []
      },
      {
        id: "trip_type",
        question: "One-way or round-trip?",
        subtitle: "One-way = drop off at destination. Round-trip = return to pickup location.",
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
    questionCount: 5,
    recap: {
      title: "Perfect — I'll find your truck",
      closing: "I'll compare options from the major rental companies and get you the best deal.",
      button: "Find my truck"
    }
  },

  // ============================================
  // MANAGE BANK
  // ============================================
  "manage_bank": {
    workflowId: "manage_bank",
    intro: {
      title: "Let's figure out what you need for your bank account.",
      subtitle: null
    },
    questions: [
      {
        id: "action",
        question: "What would you like to do with your bank account?",
        type: "single_select",
        options: [
          { id: "update_address", label: "Update my address", icon: "pencil.line", subtitle: "Keep your current account, just update the address on file" },
          { id: "close_open_new", label: "Close & open new account", icon: "arrow.triangle.swap", subtitle: "Close this account and set up a new one near your new home" },
          { id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this", alreadyHandled: true }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "We're on it",
      closing: "We'll take it from here.",
      button: "Submit"
    },
    alreadyHandledRecap: {
      title: "All set",
      closing: "Got it — we'll mark this as complete.",
      button: "Done"
    }
  },

  // ============================================
  // MANAGE DOCTOR
  // ============================================
  "manage_doctor": {
    workflowId: "manage_doctor",
    intro: {
      title: "Let's figure out what you need for your primary care doctor.",
      subtitle: null
    },
    questions: [
      {
        id: "action",
        question: "What would you like to do?",
        type: "single_select",
        options: [
          { id: "transfer_records", label: "Transfer records to new doctor", icon: "doc.arrow.forward", subtitle: "Request records be sent to a new provider near your new home" },
          { id: "update_address", label: "Update address with current doctor", icon: "pencil.line", subtitle: "Keep your current doctor, just update your contact info" },
          { id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this", alreadyHandled: true }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "We're on it",
      closing: "We'll take it from here.",
      button: "Submit"
    },
    alreadyHandledRecap: {
      title: "All set",
      closing: "Got it — we'll mark this as complete.",
      button: "Done"
    }
  },

  // ============================================
  // MANAGE DENTIST
  // ============================================
  "manage_dentist": {
    workflowId: "manage_dentist",
    intro: {
      title: "Let's figure out what you need for your dentist.",
      subtitle: null
    },
    questions: [
      {
        id: "action",
        question: "What would you like to do?",
        type: "single_select",
        options: [
          { id: "transfer_records", label: "Transfer records to new dentist", icon: "doc.arrow.forward", subtitle: "Request records and X-rays be sent to a new dentist" },
          { id: "update_address", label: "Update address with current dentist", icon: "pencil.line", subtitle: "Keep your current dentist, just update your contact info" },
          { id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this", alreadyHandled: true }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "We're on it",
      closing: "We'll take it from here.",
      button: "Submit"
    },
    alreadyHandledRecap: {
      title: "All set",
      closing: "Got it — we'll mark this as complete.",
      button: "Done"
    }
  },

  // ============================================
  // MANAGE VET
  // ============================================
  "manage_vet": {
    workflowId: "manage_vet",
    intro: {
      title: "Let's figure out what you need for your pet's vet care.",
      subtitle: null
    },
    questions: [
      {
        id: "action",
        question: "What would you like to do?",
        type: "single_select",
        options: [
          { id: "transfer_records", label: "Find new vet & transfer records", icon: "doc.arrow.forward", subtitle: "We'll help find a vet near your new home and transfer records" },
          { id: "update_address", label: "Update address with current vet", icon: "pencil.line", subtitle: "Keep your current vet, just update your contact info" },
          { id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this", alreadyHandled: true }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "We're on it",
      closing: "We'll take it from here.",
      button: "Submit"
    },
    alreadyHandledRecap: {
      title: "All set",
      closing: "Got it — we'll mark this as complete.",
      button: "Done"
    }
  },

  // ============================================
  // MANAGE GYM
  // ============================================
  "manage_gym": {
    workflowId: "manage_gym",
    intro: {
      title: "Let's figure out what you need for your gym membership.",
      subtitle: null
    },
    questions: [
      {
        id: "action",
        question: "What would you like to do with your membership?",
        type: "single_select",
        options: [
          { id: "transfer", label: "Transfer to new location", icon: "arrow.triangle.swap", subtitle: "Move your membership to a location near your new home" },
          { id: "cancel", label: "Cancel membership", icon: "xmark.circle", subtitle: "End your current membership" },
          { id: "update_address", label: "Update my address", icon: "pencil.line", subtitle: "Keep your membership as-is, just update your address" },
          { id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this", alreadyHandled: true }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "We're on it",
      closing: "We'll take it from here.",
      button: "Submit"
    },
    alreadyHandledRecap: {
      title: "All set",
      closing: "Got it — we'll mark this as complete.",
      button: "Done"
    }
  },

  // ============================================
  // MANAGE YOGA
  // ============================================
  "manage_yoga": {
    workflowId: "manage_yoga",
    intro: {
      title: "Let's figure out what you need for your yoga or pilates membership.",
      subtitle: null
    },
    questions: [
      {
        id: "action",
        question: "What would you like to do with your membership?",
        type: "single_select",
        options: [
          { id: "transfer", label: "Transfer to new location", icon: "arrow.triangle.swap", subtitle: "Move your membership to a location near your new home" },
          { id: "cancel", label: "Cancel membership", icon: "xmark.circle", subtitle: "End your current membership" },
          { id: "update_address", label: "Update my address", icon: "pencil.line", subtitle: "Keep your membership as-is, just update your address" },
          { id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this", alreadyHandled: true }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "We're on it",
      closing: "We'll take it from here.",
      button: "Submit"
    },
    alreadyHandledRecap: {
      title: "All set",
      closing: "Got it — we'll mark this as complete.",
      button: "Done"
    }
  },

  // ============================================
  // MANAGE SPIN
  // ============================================
  "manage_spin": {
    workflowId: "manage_spin",
    intro: {
      title: "Let's figure out what you need for your spin or cycling membership.",
      subtitle: null
    },
    questions: [
      {
        id: "action",
        question: "What would you like to do with your membership?",
        type: "single_select",
        options: [
          { id: "transfer", label: "Transfer to new location", icon: "arrow.triangle.swap", subtitle: "Move your membership to a location near your new home" },
          { id: "cancel", label: "Cancel membership", icon: "xmark.circle", subtitle: "End your current membership" },
          { id: "update_address", label: "Update my address", icon: "pencil.line", subtitle: "Keep your membership as-is, just update your address" },
          { id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this", alreadyHandled: true }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "We're on it",
      closing: "We'll take it from here.",
      button: "Submit"
    },
    alreadyHandledRecap: {
      title: "All set",
      closing: "Got it — we'll mark this as complete.",
      button: "Done"
    }
  },

  // ============================================
  // MANAGE MASSAGE
  // ============================================
  "manage_massage": {
    workflowId: "manage_massage",
    intro: {
      title: "Let's figure out what you need for your massage or spa membership.",
      subtitle: null
    },
    questions: [
      {
        id: "action",
        question: "What would you like to do with your membership?",
        type: "single_select",
        options: [
          { id: "transfer", label: "Transfer to new location", icon: "arrow.triangle.swap", subtitle: "Move your membership to a location near your new home" },
          { id: "cancel", label: "Cancel membership", icon: "xmark.circle", subtitle: "End your current membership" },
          { id: "update_address", label: "Update my address", icon: "pencil.line", subtitle: "Keep your membership as-is, just update your address" },
          { id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this", alreadyHandled: true }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "We're on it",
      closing: "We'll take it from here.",
      button: "Submit"
    },
    alreadyHandledRecap: {
      title: "All set",
      closing: "Got it — we'll mark this as complete.",
      button: "Done"
    }
  },

  // ============================================
  // MANAGE GOLF
  // ============================================
  "manage_golf": {
    workflowId: "manage_golf",
    intro: {
      title: "Let's figure out what you need for your golf or country club membership.",
      subtitle: null
    },
    questions: [
      {
        id: "action",
        question: "What would you like to do with your membership?",
        type: "single_select",
        options: [
          { id: "transfer", label: "Transfer to new location", icon: "arrow.triangle.swap", subtitle: "Move your membership to a location near your new home" },
          { id: "cancel", label: "Cancel membership", icon: "xmark.circle", subtitle: "End your current membership" },
          { id: "update_address", label: "Update my address", icon: "pencil.line", subtitle: "Keep your membership as-is, just update your address" },
          { id: "already_handled", label: "Already handled", icon: "checkmark.circle", subtitle: "I've already taken care of this", alreadyHandled: true }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "We're on it",
      closing: "We'll take it from here.",
      button: "Submit"
    },
    alreadyHandledRecap: {
      title: "All set",
      closing: "Got it — we'll mark this as complete.",
      button: "Done"
    }
  },

  // ============================================
  // PARKING — NEW ADDRESS
  // ============================================
  "arrange_parking_new": {
    workflowId: "arrange_parking_new",
    workflowType: "guidance",
    intro: {
      title: "Let's sort out parking for move-in day",
      subtitle: "We need to make sure the moving truck has a place to park at your new home."
    },
    questions: [
      {
        id: "has_driveway",
        question: "Does your new place have a driveway or loading area?",
        type: "single_select",
        options: [
          { id: "yes", label: "Yes, driveway or loading dock", icon: "car.fill", subtitle: "Truck can pull right up" },
          { id: "no", label: "No, street parking only", icon: "road.lanes", subtitle: "May need a permit" },
          { id: "not_sure", label: "Not sure", icon: "questionmark.circle", subtitle: "We'll plan for street parking" }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "Got your parking plan",
      closing: "We'll walk you through the next steps.",
      button: "Got it"
    }
  },

  // ============================================
  // PARKING — OLD ADDRESS
  // ============================================
  "arrange_parking_old": {
    workflowId: "arrange_parking_old",
    workflowType: "guidance",
    intro: {
      title: "Let's sort out parking for move-out day",
      subtitle: "We need to make sure the moving truck has a place to park at your current building."
    },
    questions: [
      {
        id: "has_driveway",
        question: "Does your current place have a driveway or loading area?",
        type: "single_select",
        options: [
          { id: "yes", label: "Yes, driveway or loading dock", icon: "car.fill", subtitle: "Truck can pull right up" },
          { id: "no", label: "No, street parking only", icon: "road.lanes", subtitle: "May need a permit" },
          { id: "not_sure", label: "Not sure", icon: "questionmark.circle", subtitle: "We'll plan for street parking" }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "Got your parking plan",
      closing: "We'll walk you through the next steps.",
      button: "Got it"
    }
  },

  // ============================================
  // ELEVATOR — NEW ADDRESS
  // ============================================
  "reserve_elevators_new": {
    workflowId: "reserve_elevators_new",
    workflowType: "guidance",
    intro: {
      title: "Let's reserve the elevator for move-in",
      subtitle: "We'll figure out when you need it and for how long based on your inventory."
    },
    questions: [
      {
        id: "move_start_time",
        question: "What time are you planning to start your move?",
        subtitle: "This helps us calculate when you'll arrive at the new place.",
        type: "single_select",
        options: [
          { id: "morning", label: "Morning", icon: "sunrise.fill", subtitle: "Before 10am" },
          { id: "midday", label: "Midday", icon: "sun.max.fill", subtitle: "10am – 1pm" },
          { id: "afternoon", label: "Afternoon", icon: "sunset.fill", subtitle: "After 1pm" }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "Elevator reservation plan ready",
      closing: "We'll calculate the time window you need based on your inventory.",
      button: "Got it"
    }
  },

  // ============================================
  // ELEVATOR — OLD ADDRESS
  // ============================================
  "reserve_elevators_old": {
    workflowId: "reserve_elevators_old",
    workflowType: "guidance",
    intro: {
      title: "Let's reserve the elevator for move-out",
      subtitle: "We'll figure out how long you need it based on your inventory."
    },
    questions: [
      {
        id: "move_start_time",
        question: "What time are you planning to start your move?",
        subtitle: "This helps us calculate how long you'll need the elevator.",
        type: "single_select",
        options: [
          { id: "morning", label: "Morning", icon: "sunrise.fill", subtitle: "Before 10am" },
          { id: "midday", label: "Midday", icon: "sun.max.fill", subtitle: "10am – 1pm" },
          { id: "afternoon", label: "Afternoon", icon: "sunset.fill", subtitle: "After 1pm" }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "Elevator reservation plan ready",
      closing: "We'll calculate the time window you need based on your inventory.",
      button: "Got it"
    }
  },

  // ============================================
  // CANCEL UTILITIES
  // ============================================
  "cancel_utilities": {
    workflowId: "cancel_utilities",
    workflowType: "guidance",
    intro: {
      title: "Time to cancel utilities at your current place",
      subtitle: "We'll tell you exactly which providers to contact and when."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Here's your utility cancellation plan",
      closing: "Schedule disconnection for the day after your move so you have service through your last day. Most providers need 3-5 business days notice.",
      button: "Got it"
    }
  },

  // ============================================
  // SETUP UTILITIES
  // ============================================
  "setup_utilities": {
    workflowId: "setup_utilities",
    workflowType: "guidance",
    intro: {
      title: "Let's get utilities set up at your new place",
      subtitle: "We'll make sure everything is on when you arrive."
    },
    questions: [
      {
        id: "internet_chosen",
        question: "Have you already chosen an internet provider?",
        type: "single_select",
        options: [
          { id: "yes", label: "Yes, I know which one", icon: "checkmark.circle.fill", subtitle: "Just need setup steps" },
          { id: "no", label: "No, I need to pick one", icon: "magnifyingglass", subtitle: "Show me what's available" },
          { id: "building_provided", label: "My building has one option", icon: "building.2.fill", subtitle: "No choice to make" }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "Your utility setup plan",
      closing: "Priority order: Electric and gas first (1-3 day lead time), then internet (7-14 days for installation).",
      button: "Got it"
    }
  },

  // ============================================
  // TRANSFER UTILITIES
  // ============================================
  "transfer_utilities": {
    workflowId: "transfer_utilities",
    workflowType: "guidance",
    intro: {
      title: "Let's transfer your utilities",
      subtitle: "We'll check which providers serve both addresses so you can transfer instead of cancel and re-setup."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Your utility transfer plan",
      closing: "Do transfers 5-7 business days before your move date to avoid any gap in service.",
      button: "Got it"
    }
  },

  // ============================================
  // FORWARD MAIL
  // ============================================
  "forward_mail_usps": {
    workflowId: "forward_mail_usps",
    workflowType: "guidance",
    intro: {
      title: "Let's set up mail forwarding",
      subtitle: "This takes about 2 minutes and makes sure your mail follows you."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Here's how to forward your mail",
      closing: "Do this 1-2 weeks before your move. USPS needs 7-10 business days to fully activate forwarding. Forwarding lasts 12 months for first-class mail.",
      button: "Got it"
    }
  },

  // ============================================
  // BEGIN SCHOOL TRANSFER
  // ============================================
  "begin_school_transfer": {
    workflowId: "begin_school_transfer",
    workflowType: "guidance",
    intro: {
      title: "Let's start the school transfer",
      subtitle: "A couple quick questions so we can give you the right checklist."
    },
    questions: [
      {
        id: "num_children",
        question: "How many children are transferring?",
        type: "single_select",
        options: [
          { id: "1", label: "1 child", icon: "person.fill" },
          { id: "2", label: "2 children", icon: "person.2.fill" },
          { id: "3_plus", label: "3 or more", icon: "person.3.fill", subtitle: "We'll help you coordinate" }
        ]
      },
      {
        id: "grade_levels",
        question: "What grade level(s)?",
        subtitle: "Select all that apply",
        type: "multi_select",
        options: [
          { id: "elementary", label: "Elementary (K-5)", icon: "book.fill", subtitle: "Report cards, immunizations" },
          { id: "middle", label: "Middle (6-8)", icon: "books.vertical.fill", subtitle: "Course placement records" },
          { id: "high", label: "High School (9-12)", icon: "graduationcap.fill", subtitle: "Transcripts, credits, AP records" }
        ]
      }
    ],
    questionCount: 2,
    recap: {
      title: "Your school transfer checklist is ready",
      closing: "Start this process 2-3 weeks before your move. Schools typically take 5-10 business days to process records.",
      button: "Got it"
    }
  },

  // ============================================
  // NEW SCHOOL ENROLLMENT
  // ============================================
  "new_school_enrollment": {
    workflowId: "new_school_enrollment",
    workflowType: "guidance",
    intro: {
      title: "Let's enroll at the new school",
      subtitle: "We'll tell you which school you're zoned for and what you need to bring."
    },
    questions: [
      {
        id: "num_children",
        question: "How many children are enrolling?",
        type: "single_select",
        options: [
          { id: "1", label: "1 child", icon: "person.fill" },
          { id: "2", label: "2 children", icon: "person.2.fill", subtitle: "May be different schools" },
          { id: "3_plus", label: "3 or more", icon: "person.3.fill", subtitle: "We'll help coordinate" }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "Your enrollment plan is ready",
      closing: "Enroll as soon as you have proof of residency at the new address. Don't wait until move day.",
      button: "Got it"
    }
  },

  // ============================================
  // CHANGE OF ADDRESS — SCHOOLS
  // ============================================
  "coa_schools": {
    workflowId: "coa_schools",
    workflowType: "guidance",
    intro: {
      title: "Update your address with the school",
      subtitle: "Since you're staying in the same district, this is a quick update."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Here's what to do",
      closing: "Contact the registrar with your new address and proof of residency. Also update emergency contacts, bus routes, and after-school programs.",
      button: "Got it"
    }
  },

  // ============================================
  // SETUP DAYCARE
  // ============================================
  "setup_daycare": {
    workflowId: "setup_daycare",
    workflowType: "guidance",
    intro: {
      title: "Let's find daycare near your new home",
      subtitle: "A couple questions so we can point you to the right options."
    },
    questions: [
      {
        id: "child_age",
        question: "How old is your child?",
        subtitle: "Availability and waitlists vary significantly by age.",
        type: "single_select",
        options: [
          { id: "infant", label: "Infant (0-12 mo)", icon: "figure.and.child.holdinghands", subtitle: "Longest waitlists" },
          { id: "toddler", label: "Toddler (1-3 yrs)", icon: "figure.child", subtitle: "Competitive but more options" },
          { id: "prek", label: "Pre-K (3-5 yrs)", icon: "book.and.wrench.fill", subtitle: "Check for free public pre-K" }
        ]
      },
      {
        id: "care_type",
        question: "What type of care are you looking for?",
        type: "single_select",
        options: [
          { id: "center", label: "Daycare center", icon: "building.2.fill", subtitle: "Licensed facility" },
          { id: "in_home", label: "In-home daycare", icon: "house.fill", subtitle: "Family daycare provider" },
          { id: "part_time", label: "Part-time or drop-in", icon: "clock.fill", subtitle: "Flexible schedule" }
        ]
      }
    ],
    questionCount: 2,
    recap: {
      title: "Your daycare search plan",
      closing: "Contact 3-5 providers and get on waitlists now — it costs nothing and can take months. Start tours before or right after your move.",
      button: "Got it"
    }
  },

  // ============================================
  // TRANSFER DAYCARE
  // ============================================
  "transfer_daycare": {
    workflowId: "transfer_daycare",
    workflowType: "guidance",
    intro: {
      title: "Let's handle the daycare transition",
      subtitle: "We'll make sure there's no gap in care."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Your daycare transition plan",
      closing: "Give written notice to your current daycare ASAP — most require 2-4 weeks. Ask about prorated refunds and request immunization records and developmental assessments.",
      button: "Got it"
    }
  },

  // ============================================
  // UPDATE CREDIT CARDS
  // ============================================
  "update_credit_card": {
    workflowId: "update_credit_card",
    workflowType: "guidance",
    intro: {
      title: "Update your credit card addresses",
      subtitle: "A billing address mismatch can cause declined payments on autopay."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Here's your checklist",
      closing: "Update on or right after move day. Don't forget store cards, debit cards, and digital wallets. Set a reminder to check for any missed cards 30 days later.",
      button: "Got it"
    }
  },

  // ============================================
  // UPDATE INVESTMENT ACCOUNTS
  // ============================================
  "update_investment": {
    workflowId: "update_investment",
    workflowType: "guidance",
    intro: {
      title: "Update your investment account addresses",
      subtitle: "This matters for tax document delivery and state tax compliance."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Here's what to update",
      closing: "Update within the first week after your move. Critical deadline: before year-end so 1099s and other tax documents are mailed to the right address.",
      button: "Got it"
    }
  },

  // ============================================
  // UPDATE STUDENT LOANS
  // ============================================
  "update_student_loans": {
    workflowId: "update_student_loans",
    workflowType: "guidance",
    intro: {
      title: "Update your student loan address",
      subtitle: "Missing correspondence from your servicer can mean missed payments or lost IDR deadlines."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Here's what to update",
      closing: "Update StudentAid.gov and each loan servicer separately. If you're on an Income-Driven Repayment plan, make sure recertification paperwork goes to the right address.",
      button: "Got it"
    }
  },

  // ============================================
  // TRANSFER PHARMACY RECORDS
  // ============================================
  "transfer_pharmacy_records": {
    workflowId: "transfer_pharmacy_records",
    workflowType: "guidance",
    intro: {
      title: "Let's make sure your prescriptions follow you",
      subtitle: "One question to figure out if you need to do anything."
    },
    questions: [
      {
        id: "ongoing_prescriptions",
        question: "Do you have ongoing prescriptions you fill regularly?",
        type: "single_select",
        options: [
          { id: "yes", label: "Yes, regular prescriptions", icon: "pills.fill", subtitle: "Need seamless transfer" },
          { id: "no", label: "No, just occasional", icon: "checkmark.circle.fill", subtitle: "No proactive transfer needed" }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "Your pharmacy transfer plan",
      closing: "If you have prescriptions due within 2 weeks of your move, fill them now at your current pharmacy for a buffer.",
      button: "Got it"
    }
  },

  // ============================================
  // TRANSFER SPECIALISTS RECORDS
  // ============================================
  "transfer_specialists_records": {
    workflowId: "transfer_specialists_records",
    workflowType: "guidance",
    intro: {
      title: "Transfer your specialist medical records",
      subtitle: "Let's make sure there's no gap in your care."
    },
    questions: [
      {
        id: "sees_specialists",
        question: "Do you or your family see any specialists regularly?",
        type: "single_select",
        options: [
          { id: "yes", label: "Yes, we see specialists", icon: "stethoscope", subtitle: "Need records transferred" },
          { id: "no", label: "No specialists", icon: "checkmark.circle.fill", subtitle: "Nothing to transfer" }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "Your medical records plan",
      closing: "Request records 2-3 weeks before your move. Under HIPAA they must provide them, but it can take up to 30 days. Ask for digital copies when available.",
      button: "Got it"
    }
  },

  // ============================================
  // UPDATE AUTO INSURANCE
  // ============================================
  "update_auto_insurance": {
    workflowId: "update_auto_insurance",
    workflowType: "guidance",
    intro: {
      title: "Update your auto insurance",
      subtitle: "Your garaging address affects your rates — this needs to be updated."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Here's your plan",
      closing: "Update within 30 days of your move. If moving to a different state, you'll also need to update your vehicle registration and driver's license within 30-90 days.",
      button: "Got it"
    }
  },

  // ============================================
  // CANCEL RENTERS INSURANCE
  // ============================================
  "cancel_renters_insurance": {
    workflowId: "cancel_renters_insurance",
    workflowType: "guidance",
    intro: {
      title: "Cancel your renters insurance",
      subtitle: "We'll make sure you're covered through your last day."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Here's what to do",
      closing: "Cancel effective your move date — not earlier. Your policy covers your belongings until everything is out. If you're setting up a new policy, ask about transferring to keep your loyalty discount.",
      button: "Got it"
    }
  },

  // ============================================
  // SETUP RENTERS INSURANCE
  // ============================================
  "setup_renters_insurance": {
    workflowId: "setup_renters_insurance",
    workflowType: "guidance",
    intro: {
      title: "Set up renters insurance at your new place",
      subtitle: "Most leases require it, and it protects your stuff."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Here's your plan",
      closing: "Set this up 1-2 days before move day. Get quotes from your auto insurer first (bundle discount). Typical cost is $15-30/month. Check if your lease specifies a minimum coverage amount.",
      button: "Got it"
    }
  },

  // ============================================
  // TRANSFER RENTERS INSURANCE
  // ============================================
  "transfer_renters_insurance": {
    workflowId: "transfer_renters_insurance",
    workflowType: "guidance",
    intro: {
      title: "Transfer your renters insurance",
      subtitle: "Update your existing policy to cover your new address."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Here's what to do",
      closing: "Update 1-2 days before move day so you're covered at both locations during the transition. Your rate may change based on the new location. Confirm your policy covers belongings in transit.",
      button: "Got it"
    }
  },

  // ============================================
  // CANCEL CONDO INSURANCE
  // ============================================
  "cancel_condo_insurance": {
    workflowId: "cancel_condo_insurance",
    workflowType: "guidance",
    intro: {
      title: "Cancel your condo insurance",
      subtitle: "Important: cancel effective your closing date, not your move-out date."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Here's what to do",
      closing: "Cancel effective closing date — you're liable until the deed transfers. Ask about prorated refund and notify your lender if mortgage escrow pays the premium. Request a cancellation confirmation letter.",
      button: "Got it"
    }
  },

  // ============================================
  // SETUP CONDO INSURANCE
  // ============================================
  "setup_condo_insurance": {
    workflowId: "setup_condo_insurance",
    workflowType: "guidance",
    intro: {
      title: "Set up condo insurance at your new place",
      subtitle: "Your HOA's master policy doesn't cover your unit's interior or your belongings."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Here's your plan",
      closing: "Get your HOA's master policy declaration page first — it tells you where their coverage ends. Get quotes 2-3 weeks before closing. Your lender will require proof of insurance before closing.",
      button: "Got it"
    }
  },

  // ============================================
  // TRANSFER CONDO INSURANCE
  // ============================================
  "transfer_condo_insurance": {
    workflowId: "transfer_condo_insurance",
    workflowType: "guidance",
    intro: {
      title: "Transfer your condo insurance",
      subtitle: "Move your policy from your old condo to the new one."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Here's what to do",
      closing: "Call your insurer with both closing dates. You need coverage at both locations during any overlap. Provide the new HOA's master policy so they can adjust your HO-6 coverage.",
      button: "Got it"
    }
  },

  // ============================================
  // CANCEL HOMEOWNERS INSURANCE
  // ============================================
  "cancel_homeowners_insurance": {
    workflowId: "cancel_homeowners_insurance",
    workflowType: "guidance",
    intro: {
      title: "Cancel your homeowners insurance",
      subtitle: "Critical: do not cancel before closing."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Here's what to do",
      closing: "Cancel effective your closing date — not your move-out date. Contact your insurer 1-2 weeks before closing but make cancellation contingent on the sale actually closing. If escrow pays the premium, notify your lender.",
      button: "Got it"
    }
  },

  // ============================================
  // SETUP HOMEOWNERS INSURANCE
  // ============================================
  "setup_homeowners_insurance": {
    workflowId: "setup_homeowners_insurance",
    workflowType: "guidance",
    intro: {
      title: "Set up homeowners insurance",
      subtitle: "Your lender requires this before closing — non-negotiable."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Here's your plan",
      closing: "Start getting quotes 3-4 weeks before closing. Check with your auto insurer first for a bundle discount. Bind at least 1 week before closing and send the declarations page to your lender.",
      button: "Got it"
    }
  },

  // ============================================
  // TRANSFER HOMEOWNERS INSURANCE
  // ============================================
  "transfer_homeowners_insurance": {
    workflowId: "transfer_homeowners_insurance",
    workflowType: "guidance",
    intro: {
      title: "Transfer your homeowners insurance",
      subtitle: "Move your coverage from your current home to the new one."
    },
    questions: [],
    questionCount: 0,
    recap: {
      title: "Here's what to do",
      closing: "Call your insurer 3-4 weeks before closing. You need coverage at both homes during any overlap. Dwelling coverage will be recalculated for the new property. Send the new declarations page to your lender.",
      button: "Got it"
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