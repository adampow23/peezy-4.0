// workflowQualifying.js
// Qualifying questions for vendor matching workflows
// Add to your Firebase functions folder

const WORKFLOW_QUALIFYING = {

  // ============================================
  // BOOK MOVERS (Local)
  // ============================================
  "book_movers": {
    intro: {
      title: "Let's find you the right movers",
      subtitle: "A few quick questions to match you with companies that fit your move. Takes about 30 seconds."
    },
    questions: [
      {
        id: "priority",
        question: "What matters most to you?",
        type: "single_select",
        options: [
          { id: "price", label: "Lowest Price", icon: "dollarsign.circle.fill" },
          { id: "reviews", label: "Best Reviews", icon: "star.fill" },
          { id: "speed", label: "Fastest Available", icon: "clock.fill" },
          { id: "full_service", label: "Full Service", icon: "hands.sparkles.fill" }
        ]
      },
      {
        id: "special_items",
        question: "Any of these items?",
        type: "multi_select",
        subtitle: "These need special handling",
        options: [
          { id: "piano", label: "Piano", icon: "pianokeys" },
          { id: "safe", label: "Heavy Safe", icon: "lock.square.fill" },
          { id: "art", label: "Art/Antiques", icon: "photo.artframe" },
          { id: "pool_table", label: "Pool Table", icon: "circle.fill" },
          { id: "none", label: "None of These", icon: "checkmark.circle.fill", exclusive: true }
        ]
      },
      {
        id: "packing_help",
        question: "Need help packing?",
        type: "single_select",
        options: [
          { id: "full", label: "Pack Everything", subtitle: "They pack, you relax", icon: "shippingbox.fill" },
          { id: "fragile", label: "Fragile Items Only", subtitle: "Dishes, mirrors, TVs", icon: "wineglass" },
          { id: "none", label: "I'll Handle It", subtitle: "Just need transport", icon: "hand.raised.fill" }
        ]
      },
      {
        id: "access_issues",
        question: "Any tricky access?",
        type: "multi_select",
        subtitle: "At either location",
        options: [
          { id: "stairs", label: "Stairs (No Elevator)", icon: "figure.stairs" },
          { id: "long_walk", label: "Long Carry", subtitle: "Parking far from door", icon: "figure.walk" },
          { id: "narrow", label: "Narrow Doorways", icon: "door.left.hand.closed" },
          { id: "none", label: "Easy Access", icon: "checkmark.circle.fill", exclusive: true }
        ]
      }
    ],
    recap: {
      title: "Got it. Here's what I heard:",
      closing: "I'm reaching out to your top 3 matches now. You'll have quotes within 24 hours.",
      button: "Sounds Good"
    },
    matching: {
      // Used by backend to weight vendor matching
      priorityWeight: 0.4,
      specialItemsWeight: 0.3,
      servicesWeight: 0.2,
      accessWeight: 0.1
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
