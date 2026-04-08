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
      title: "Let's find you the right movers",
      subtitle: "A few quick questions so we can get you quotes from the top companies."
    },
    questions: [
      {
        id: "heavy_items",
        question: "Any really heavy items?",
        subtitle: "These need special equipment.",
        type: "multi_select",
        options: [
          { id: "piano", label: "Piano / Organ", icon: "pianokeys" },
          { id: "safe", label: "Gun Safe / Safe", icon: "lock.shield" },
          { id: "hot_tub", label: "Hot Tub / Spa", icon: "drop.fill" },
          { id: "pool_table", label: "Pool Table", icon: "circle.grid.3x3" }
        ]
      },
      {
        id: "specialty_items",
        question: "Any delicate or high-value items?",
        subtitle: "These need extra care during transport.",
        type: "multi_select",
        options: [
          { id: "art", label: "Art / Antiques", icon: "photo.artframe" },
          { id: "glass", label: "Large Mirrors / Glass", icon: "rectangle" },
          { id: "wine", label: "Wine Collection", icon: "wineglass" },
          { id: "instruments", label: "Musical Instruments", icon: "guitars" }
        ]
      },
      {
        id: "packing_help",
        question: "Need help with packing?",
        type: "single_select",
        options: [
          { id: "full", label: "Full service — pack everything", icon: "shippingbox.fill" },
          { id: "partial", label: "Just fragile / kitchen items", icon: "wineglass" },
          { id: "none", label: "No — I'll pack myself", icon: "hand.raised" }
        ]
      },
      {
        id: "storage_needed",
        question: "Need storage?",
        type: "single_select",
        options: [
          { id: "yes", label: "Yes", icon: "archivebox" },
          { id: "no", label: "No", icon: "xmark.circle" }
        ]
      },
      {
        id: "storage_details",
        question: "Tell us about your storage needs",
        type: "single_select",
        options: [
          { id: "5x5_partial", label: "Small (5×5) — partially full", icon: "square.grid.2x2" },
          { id: "5x5_full", label: "Small (5×5) — full", icon: "square.grid.2x2.fill" },
          { id: "10x10_partial", label: "Medium (10×10) — partially full", icon: "square.grid.3x3" },
          { id: "10x10_full", label: "Medium (10×10) — full", icon: "square.grid.3x3.fill" },
          { id: "10x20_partial", label: "Large (10×20) — partially full", icon: "rectangle.grid.2x2" },
          { id: "10x20_full", label: "Large (10×20) — full", icon: "rectangle.grid.2x2.fill" }
        ]
      },
      {
        id: "insurance_context",
        question: "You're going to want to read this.",
        subtitle: "Industry standard moving coverage is only $0.60 per pound. That means a 50lb TV worth $800 would only be covered for $30. Full-value protection covers the actual replacement cost.",
        type: "single_select",
        options: []
      },
      {
        id: "insurance_preference",
        question: "What level of coverage?",
        type: "single_select",
        options: [
          { id: "full_value", label: "Full coverage — actual replacement value", icon: "shield.checkered" },
          { id: "basic", label: "Basic — standard $0.60/lb", icon: "shield" },
          { id: "none", label: "No insurance", icon: "xmark.shield" }
        ]
      }
    ],
    questionCount: 7,
    recap: {
      title: "Here's what we've got",
      closing: "Based on your answers, we'll find the top 3 companies and get you quotes from each. We'll reach out as soon as we have them.",
      button: "Request Quotes"
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
  // BOOK CLEANERS
  // ============================================
  "book_cleaners": {
    workflowId: "book_cleaners",
    intro: {
      title: "Let's find you the right cleaners",
      subtitle: "A couple quick questions to match you with the right service."
    },
    questions: [
      {
        id: "which_place",
        question: "Which place needs cleaning?",
        type: "single_select",
        options: [
          { id: "move_out", label: "Old place — move-out clean", icon: "door.left.hand.open" },
          { id: "move_in", label: "New place — move-in clean", icon: "door.right.hand.open" },
          { id: "both", label: "Both places", icon: "arrow.left.arrow.right" }
        ]
      },
      {
        id: "services",
        question: "What services do you need?",
        subtitle: "Select all that apply.",
        type: "multi_select",
        options: [
          { id: "standard", label: "Standard clean", icon: "sparkles" },
          { id: "deep", label: "Deep clean (baseboards, inside appliances)", icon: "bubbles.and.sparkles" },
          { id: "carpet", label: "Carpet cleaning", icon: "square.grid.3x3.topleft.filled" },
          { id: "windows", label: "Window cleaning", icon: "window.horizontal" }
        ]
      },
      {
        id: "move_out_timing",
        question: "When do you need the move-out clean?",
        subtitle: "Rough time preference.",
        type: "single_select",
        options: [
          { id: "morning", label: "Morning", icon: "sunrise" },
          { id: "afternoon", label: "Afternoon", icon: "sun.max" },
          { id: "evening", label: "Evening", icon: "sunset" },
          { id: "flexible", label: "Flexible", icon: "clock" }
        ]
      },
      {
        id: "move_in_timing",
        question: "When do you need the move-in clean?",
        subtitle: "Rough time preference.",
        type: "single_select",
        options: [
          { id: "morning", label: "Morning", icon: "sunrise" },
          { id: "afternoon", label: "Afternoon", icon: "sun.max" },
          { id: "evening", label: "Evening", icon: "sunset" },
          { id: "flexible", label: "Flexible", icon: "clock" }
        ]
      }
    ],
    questionCount: 4,
    recap: {
      title: "Here's what we've got",
      closing: "We'll find cleaners who can handle everything you selected and get you quotes.",
      button: "Request Quotes"
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
      title: "Let's get you connected",
      subtitle: "A few questions to find the best internet options at your new place."
    },
    questions: [
      {
        id: "usage",
        question: "Who's using the internet?",
        subtitle: "Select all that apply.",
        type: "multi_select",
        options: [
          { id: "work_from_home", label: "Work from home", icon: "laptopcomputer" },
          { id: "streaming", label: "Streaming (Netflix, YouTube)", icon: "play.tv.fill" },
          { id: "gaming", label: "Gaming", icon: "gamecontroller.fill" },
          { id: "smart_home", label: "Smart home devices", icon: "homekit" },
          { id: "basic", label: "Just browsing and email", icon: "globe" }
        ]
      },
      {
        id: "people_count",
        question: "How many people in the household?",
        type: "single_select",
        options: [
          { id: "1_2", label: "1–2", icon: "person" },
          { id: "3_5", label: "3–5", icon: "person.2" },
          { id: "6_plus", label: "6+", icon: "person.3" }
        ]
      },
      {
        id: "contract_preference",
        question: "Contract preference?",
        type: "single_select",
        options: [
          { id: "month_to_month", label: "Month-to-month", icon: "calendar" },
          { id: "1_year", label: "1 year", icon: "calendar.badge.clock" },
          { id: "2_year", label: "2 year", icon: "calendar.badge.checkmark" },
          { id: "no_preference", label: "No preference", icon: "hand.thumbsup" }
        ]
      }
    ],
    questionCount: 3,
    recap: {
      title: "Here's what we've got",
      closing: "We'll match you with providers in your area and get you options. We'll reach out as soon as we have them.",
      button: "Request Quotes"
    }
  },

  // ============================================
  // RENT TRUCK
  // ============================================
  "rent_truck": {
    workflowId: "rent_truck",
    intro: {
      title: "Let's get you a truck",
      subtitle: "We'll use the details from your inventory to find the right size and best price."
    },
    questions: [
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
      }
    ],
    questionCount: 1,
    recap: {
      title: "Here's what we've got",
      closing: "We'll compare options from the major rental companies and get you the best deal. We'll reach out as soon as we have quotes.",
      button: "Request Quotes"
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
    intro: {
      title: "Let's handle your credit cards",
      subtitle: null
    },
    questions: [
      {
        id: "action",
        question: "What would you like to do with your credit card addresses?",
        type: "single_select",
        options: [
          { id: "update_address", label: "Update my addresses", icon: "pencil.line", subtitle: "We'll walk you through each card" },
          { id: "help_me", label: "Help me update them", icon: "hands.sparkles.fill", subtitle: "We'll handle the research" },
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
  // UPDATE INVESTMENT ACCOUNTS
  // ============================================
  "update_investment": {
    workflowId: "update_investment",
    intro: {
      title: "Let's handle your investment accounts",
      subtitle: null
    },
    questions: [
      {
        id: "action",
        question: "What would you like to do with your investment accounts?",
        type: "single_select",
        options: [
          { id: "update_address", label: "Update my address", icon: "pencil.line", subtitle: "Keep current accounts, update contact info" },
          { id: "help_transfer", label: "Help me transfer or consolidate", icon: "arrow.triangle.swap", subtitle: "We'll research options for you" },
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
  // UPDATE STUDENT LOANS
  // ============================================
  "update_student_loans": {
    workflowId: "update_student_loans",
    intro: {
      title: "Let's handle your student loans",
      subtitle: null
    },
    questions: [
      {
        id: "action",
        question: "What would you like to do with your student loans?",
        type: "single_select",
        options: [
          { id: "update_address", label: "Update my address", icon: "pencil.line", subtitle: "Update with servicer and StudentAid.gov" },
          { id: "help_me", label: "Help me figure out what to do", icon: "questionmark.circle", subtitle: "We'll walk you through it" },
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
  // TRANSFER PHARMACY RECORDS
  // ============================================
  "transfer_pharmacy_records": {
    workflowId: "transfer_pharmacy_records",
    intro: {
      title: "Let's handle your pharmacy records",
      subtitle: null
    },
    questions: [
      {
        id: "action",
        question: "What would you like to do?",
        type: "single_select",
        options: [
          { id: "transfer_records", label: "Transfer to a pharmacy near new home", icon: "doc.arrow.forward", subtitle: "We'll help coordinate the transfer" },
          { id: "update_address", label: "Update address with current pharmacy", icon: "pencil.line", subtitle: "Keep your current pharmacy" },
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
  // TRANSFER SPECIALISTS RECORDS
  // ============================================
  "transfer_specialists_records": {
    workflowId: "transfer_specialists_records",
    intro: {
      title: "Let's handle your specialist records",
      subtitle: null
    },
    questions: [
      {
        id: "action",
        question: "What would you like to do?",
        type: "single_select",
        options: [
          { id: "transfer_records", label: "Transfer records to new specialist", icon: "doc.arrow.forward", subtitle: "We'll help coordinate the transfer" },
          { id: "update_address", label: "Update address with current specialist", icon: "pencil.line", subtitle: "Keep your current specialist" },
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
  // UPDATE AUTO INSURANCE
  // ============================================
  "update_auto_insurance": {
    workflowId: "update_auto_insurance",
    intro: {
      title: "Update your auto insurance",
      subtitle: "Your garaging address affects your rates — let's get this updated."
    },
    questions: [
      {
        id: "help_preference",
        question: "Would you like help with this?",
        type: "single_select",
        options: [
          { id: "help_me", label: "Yes, help me update it", icon: "hands.sparkles.fill" },
          { id: "self", label: "I'll handle it myself", icon: "person.fill" }
        ]
      },
      {
        id: "current_provider",
        question: "Who is your current provider?",
        subtitle: "So we know who to contact.",
        type: "single_select",
        options: [
          { id: "state_farm", label: "State Farm", icon: "shield.fill" },
          { id: "geico", label: "GEICO", icon: "shield.fill" },
          { id: "progressive", label: "Progressive", icon: "shield.fill" },
          { id: "allstate", label: "Allstate", icon: "shield.fill" },
          { id: "other", label: "Other", icon: "ellipsis.circle" }
        ]
      }
    ],
    questionCount: 2,
    recap: {
      title: "We're on it",
      closing: "We'll reach out and get this updated for you.",
      button: "Submit"
    }
  },

  // ============================================
  // CANCEL RENTERS INSURANCE
  // ============================================
  "cancel_renters_insurance": {
    workflowId: "cancel_renters_insurance",
    intro: {
      title: "Cancel your renters insurance",
      subtitle: "We'll make sure you're covered through your last day."
    },
    questions: [
      {
        id: "help_preference",
        question: "Would you like help canceling?",
        type: "single_select",
        options: [
          { id: "help_me", label: "Yes, help me cancel", icon: "hands.sparkles.fill" },
          { id: "self", label: "I'll handle it myself", icon: "person.fill" }
        ]
      },
      {
        id: "current_provider",
        question: "Who is your current provider?",
        subtitle: "So we know who to contact.",
        type: "single_select",
        options: [
          { id: "state_farm", label: "State Farm", icon: "shield.fill" },
          { id: "lemonade", label: "Lemonade", icon: "shield.fill" },
          { id: "progressive", label: "Progressive", icon: "shield.fill" },
          { id: "allstate", label: "Allstate", icon: "shield.fill" },
          { id: "other", label: "Other", icon: "ellipsis.circle" }
        ]
      }
    ],
    questionCount: 2,
    recap: {
      title: "We're on it",
      closing: "We'll reach out and get this canceled effective your move date.",
      button: "Submit"
    }
  },

  // ============================================
  // SETUP RENTERS INSURANCE
  // ============================================
  "setup_renters_insurance": {
    workflowId: "setup_renters_insurance",
    intro: {
      title: "Set up renters insurance at your new place",
      subtitle: "Most leases require it, and it protects your stuff."
    },
    questions: [
      {
        id: "help_preference",
        question: "Would you like help finding a policy?",
        type: "single_select",
        options: [
          { id: "help_me", label: "Yes, find me options", icon: "hands.sparkles.fill" },
          { id: "self", label: "I'll handle it myself", icon: "person.fill" }
        ]
      }
    ],
    questionCount: 1,
    recap: {
      title: "We're on it",
      closing: "We'll find you the best options and get you set up before move day.",
      button: "Submit"
    }
  },

  // ============================================
  // TRANSFER RENTERS INSURANCE
  // ============================================
  "transfer_renters_insurance": {
    workflowId: "transfer_renters_insurance",
    intro: {
      title: "Transfer your renters insurance",
      subtitle: "Update your existing policy to cover your new address."
    },
    questions: [
      {
        id: "help_preference",
        question: "Would you like help with this?",
        type: "single_select",
        options: [
          { id: "help_me", label: "Yes, help me transfer it", icon: "hands.sparkles.fill" },
          { id: "self", label: "I'll handle it myself", icon: "person.fill" }
        ]
      },
      {
        id: "current_provider",
        question: "Who is your current provider?",
        subtitle: "So we know who to contact.",
        type: "single_select",
        options: [
          { id: "state_farm", label: "State Farm", icon: "shield.fill" },
          { id: "lemonade", label: "Lemonade", icon: "shield.fill" },
          { id: "progressive", label: "Progressive", icon: "shield.fill" },
          { id: "allstate", label: "Allstate", icon: "shield.fill" },
          { id: "other", label: "Other", icon: "ellipsis.circle" }
        ]
      }
    ],
    questionCount: 2,
    recap: {
      title: "We're on it",
      closing: "We'll reach out and get your policy transferred to the new address.",
      button: "Submit"
    }
  },

  // ============================================
  // CANCEL CONDO INSURANCE
  // ============================================
  "cancel_condo_insurance": {
    workflowId: "cancel_condo_insurance",
    intro: {
      title: "Cancel your condo insurance",
      subtitle: "Cancel effective your closing date, not your move-out date."
    },
    questions: [
      { id: "help_preference", question: "Would you like help canceling?", type: "single_select", options: [
          { id: "help_me", label: "Yes, help me cancel", icon: "hands.sparkles.fill" },
          { id: "self", label: "I'll handle it myself", icon: "person.fill" }
      ]},
      { id: "current_provider", question: "Who is your current provider?", subtitle: "So we know who to contact.", type: "single_select", options: [
          { id: "state_farm", label: "State Farm", icon: "shield.fill" },
          { id: "nationwide", label: "Nationwide", icon: "shield.fill" },
          { id: "liberty_mutual", label: "Liberty Mutual", icon: "shield.fill" },
          { id: "other", label: "Other", icon: "ellipsis.circle" }
      ]}
    ],
    questionCount: 2,
    recap: { title: "We're on it", closing: "We'll reach out and get this canceled effective your closing date.", button: "Submit" }
  },

  // ============================================
  // SETUP CONDO INSURANCE
  // ============================================
  "setup_condo_insurance": {
    workflowId: "setup_condo_insurance",
    intro: {
      title: "Set up condo insurance at your new place",
      subtitle: "Your HOA's master policy doesn't cover your unit's interior."
    },
    questions: [
      { id: "help_preference", question: "Would you like help finding a policy?", type: "single_select", options: [
          { id: "help_me", label: "Yes, find me options", icon: "hands.sparkles.fill" },
          { id: "self", label: "I'll handle it myself", icon: "person.fill" }
      ]}
    ],
    questionCount: 1,
    recap: { title: "We're on it", closing: "We'll find you the best options before closing.", button: "Submit" }
  },

  // ============================================
  // TRANSFER CONDO INSURANCE
  // ============================================
  "transfer_condo_insurance": {
    workflowId: "transfer_condo_insurance",
    intro: {
      title: "Transfer your condo insurance",
      subtitle: "Move your policy from your old condo to the new one."
    },
    questions: [
      { id: "help_preference", question: "Would you like help with this?", type: "single_select", options: [
          { id: "help_me", label: "Yes, help me transfer it", icon: "hands.sparkles.fill" },
          { id: "self", label: "I'll handle it myself", icon: "person.fill" }
      ]},
      { id: "current_provider", question: "Who is your current provider?", subtitle: "So we know who to contact.", type: "single_select", options: [
          { id: "state_farm", label: "State Farm", icon: "shield.fill" },
          { id: "nationwide", label: "Nationwide", icon: "shield.fill" },
          { id: "liberty_mutual", label: "Liberty Mutual", icon: "shield.fill" },
          { id: "other", label: "Other", icon: "ellipsis.circle" }
      ]}
    ],
    questionCount: 2,
    recap: { title: "We're on it", closing: "We'll reach out and get your policy transferred.", button: "Submit" }
  },

  // ============================================
  // CANCEL HOMEOWNERS INSURANCE
  // ============================================
  "cancel_homeowners_insurance": {
    workflowId: "cancel_homeowners_insurance",
    intro: {
      title: "Cancel your homeowners insurance",
      subtitle: "Do not cancel before closing — you're liable until the deed transfers."
    },
    questions: [
      { id: "help_preference", question: "Would you like help canceling?", type: "single_select", options: [
          { id: "help_me", label: "Yes, help me cancel", icon: "hands.sparkles.fill" },
          { id: "self", label: "I'll handle it myself", icon: "person.fill" }
      ]},
      { id: "current_provider", question: "Who is your current provider?", subtitle: "So we know who to contact.", type: "single_select", options: [
          { id: "state_farm", label: "State Farm", icon: "shield.fill" },
          { id: "nationwide", label: "Nationwide", icon: "shield.fill" },
          { id: "liberty_mutual", label: "Liberty Mutual", icon: "shield.fill" },
          { id: "usaa", label: "USAA", icon: "shield.fill" },
          { id: "other", label: "Other", icon: "ellipsis.circle" }
      ]}
    ],
    questionCount: 2,
    recap: { title: "We're on it", closing: "We'll reach out and get this canceled effective your closing date.", button: "Submit" }
  },

  // ============================================
  // SETUP HOMEOWNERS INSURANCE
  // ============================================
  "setup_homeowners_insurance": {
    workflowId: "setup_homeowners_insurance",
    intro: {
      title: "Set up homeowners insurance",
      subtitle: "Your lender requires this before closing."
    },
    questions: [
      { id: "help_preference", question: "Would you like help finding a policy?", type: "single_select", options: [
          { id: "help_me", label: "Yes, find me options", icon: "hands.sparkles.fill" },
          { id: "self", label: "I'll handle it myself", icon: "person.fill" }
      ]}
    ],
    questionCount: 1,
    recap: { title: "We're on it", closing: "We'll find you the best options. Need this bound at least 1 week before closing.", button: "Submit" }
  },

  // ============================================
  // TRANSFER HOMEOWNERS INSURANCE
  // ============================================
  "transfer_homeowners_insurance": {
    workflowId: "transfer_homeowners_insurance",
    intro: {
      title: "Transfer your homeowners insurance",
      subtitle: "Move your coverage from your current home to the new one."
    },
    questions: [
      { id: "help_preference", question: "Would you like help with this?", type: "single_select", options: [
          { id: "help_me", label: "Yes, help me transfer it", icon: "hands.sparkles.fill" },
          { id: "self", label: "I'll handle it myself", icon: "person.fill" }
      ]},
      { id: "current_provider", question: "Who is your current provider?", subtitle: "So we know who to contact.", type: "single_select", options: [
          { id: "state_farm", label: "State Farm", icon: "shield.fill" },
          { id: "nationwide", label: "Nationwide", icon: "shield.fill" },
          { id: "liberty_mutual", label: "Liberty Mutual", icon: "shield.fill" },
          { id: "usaa", label: "USAA", icon: "shield.fill" },
          { id: "other", label: "Other", icon: "ellipsis.circle" }
      ]}
    ],
    questionCount: 2,
    recap: { title: "We're on it", closing: "We'll reach out and get your policy transferred.", button: "Submit" }
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