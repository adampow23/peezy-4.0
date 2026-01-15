/**
 * Mini-Assessment Workflows
 * 
 * These are "list builder" workflows that help users identify
 * all the places they need to update their address.
 * 
 * Same flow as vendor qualifying workflows, but with:
 * - Text entry after "yes" swipes
 * - Review/edit card at the end
 */

const MINI_ASSESSMENT_WORKFLOWS = {
  
  // ============================================
  // FINANCIAL INSTITUTIONS
  // ============================================
  
  "address_change_financial": {
    id: "address_change_financial",
    title: "Financial Institutions",
    taskTitle: "Create financial address change list",
    category: "address_change",
    
    intro: {
      title: "Financial Institutions",
      subtitle: "Let's make sure all your financial accounts get your new address.",
      instruction: "Swipe right if you have an account, left if you don't. We'll ask for names after."
    },
    
    questions: [
      {
        id: "bank",
        question: "Do you have a bank or credit union account?",
        icon: "building.columns.fill",
        textEntryPrompt: "Which bank/credit union?",
        textEntryPlaceholder: "Chase, Wells Fargo, etc.",
        allowMultiple: true
      },
      {
        id: "credit_cards",
        question: "Do you have any credit cards?",
        icon: "creditcard.fill",
        textEntryPrompt: "Which credit cards?",
        textEntryPlaceholder: "Amex, Discover, Capital One, etc.",
        allowMultiple: true
      },
      {
        id: "investments",
        question: "Do you have investment or brokerage accounts?",
        icon: "chart.line.uptrend.xyaxis",
        textEntryPrompt: "Which brokerages?",
        textEntryPlaceholder: "Fidelity, Schwab, Robinhood, etc.",
        allowMultiple: true
      },
      {
        id: "retirement",
        question: "Do you have a 401k or IRA?",
        icon: "banknote.fill",
        textEntryPrompt: "Which provider?",
        textEntryPlaceholder: "Fidelity, Vanguard, etc."
      },
      {
        id: "loans",
        question: "Do you have any loans (auto, student, personal)?",
        icon: "signature",
        textEntryPrompt: "Which lenders?",
        textEntryPlaceholder: "SoFi, Navient, etc.",
        allowMultiple: true
      },
      {
        id: "mortgage",
        question: "Do you have a mortgage?",
        icon: "house.fill",
        textEntryPrompt: "Which lender?",
        textEntryPlaceholder: "Rocket Mortgage, Chase, etc."
      },
      {
        id: "hsa_fsa",
        question: "Do you have an HSA or FSA account?",
        icon: "cross.case.fill",
        textEntryPrompt: "Which provider?",
        textEntryPlaceholder: "HealthEquity, Optum, etc."
      }
    ],
    
    review: {
      title: "Financial Accounts",
      subtitle: "Here's what we found:",
      confirmText: "Swipe right to add these tasks",
      editText: "Swipe left to make changes"
    },
    
    taskTemplate: {
      titlePrefix: "Update address:",
      category: "address_change",
      subcategory: "financial",
      priority: 1
    }
  },
  
  // ============================================
  // HEALTHCARE
  // ============================================
  
  "address_change_health": {
    id: "address_change_health",
    title: "Healthcare",
    taskTitle: "Create healthcare address change list",
    category: "address_change",
    
    intro: {
      title: "Healthcare Providers",
      subtitle: "Let's update your healthcare providers with your new address.",
      instruction: "Swipe right if you have this, left if you don't."
    },
    
    questions: [
      {
        id: "primary_doctor",
        question: "Do you have a primary care doctor?",
        icon: "stethoscope",
        textEntryPrompt: "Doctor's name or practice?",
        textEntryPlaceholder: "Dr. Smith, One Medical, etc."
      },
      {
        id: "dentist",
        question: "Do you have a dentist?",
        icon: "mouth.fill",
        textEntryPrompt: "Dentist's name or practice?",
        textEntryPlaceholder: "Dr. Jones, Aspen Dental, etc."
      },
      {
        id: "health_insurance",
        question: "Do you have health insurance?",
        icon: "heart.text.square.fill",
        textEntryPrompt: "Which provider?",
        textEntryPlaceholder: "Blue Cross, Aetna, Kaiser, etc."
      },
      {
        id: "dental_insurance",
        question: "Do you have dental insurance?",
        icon: "face.smiling.fill",
        textEntryPrompt: "Which provider?",
        textEntryPlaceholder: "Delta Dental, MetLife, etc."
      },
      {
        id: "vision",
        question: "Do you have vision insurance or an eye doctor?",
        icon: "eye.fill",
        textEntryPrompt: "Provider or doctor?",
        textEntryPlaceholder: "VSP, LensCrafters, etc."
      },
      {
        id: "therapist",
        question: "Do you see a therapist or counselor?",
        icon: "brain.head.profile",
        textEntryPrompt: "Therapist's name?",
        textEntryPlaceholder: "Name or practice"
      },
      {
        id: "specialists",
        question: "Do you see any specialists?",
        icon: "person.badge.plus",
        textEntryPrompt: "Which specialists?",
        textEntryPlaceholder: "Dermatologist, cardiologist, etc.",
        allowMultiple: true
      },
      {
        id: "pharmacy",
        question: "Do you have a regular pharmacy?",
        icon: "pills.fill",
        textEntryPrompt: "Which pharmacy?",
        textEntryPlaceholder: "CVS, Walgreens, etc."
      }
    ],
    
    review: {
      title: "Healthcare Providers",
      subtitle: "Here's what we found:",
      confirmText: "Swipe right to add these tasks",
      editText: "Swipe left to make changes"
    },
    
    taskTemplate: {
      titlePrefix: "Update address:",
      category: "address_change",
      subcategory: "health",
      priority: 1
    }
  },
  
  // ============================================
  // INSURANCE
  // ============================================
  
  "address_change_insurance": {
    id: "address_change_insurance",
    title: "Insurance",
    taskTitle: "Create insurance address change list",
    category: "address_change",
    
    intro: {
      title: "Insurance Policies",
      subtitle: "Insurance companies need your new address - rates can change by location!",
      instruction: "Swipe right if you have this coverage, left if you don't."
    },
    
    questions: [
      {
        id: "auto_insurance",
        question: "Do you have auto insurance?",
        icon: "car.fill",
        textEntryPrompt: "Which company?",
        textEntryPlaceholder: "State Farm, Geico, Progressive, etc."
      },
      {
        id: "renters_insurance",
        question: "Do you have renters insurance?",
        icon: "house.fill",
        textEntryPrompt: "Which company?",
        textEntryPlaceholder: "Lemonade, State Farm, etc."
      },
      {
        id: "homeowners_insurance",
        question: "Do you have homeowners insurance?",
        icon: "house.lodge.fill",
        textEntryPrompt: "Which company?",
        textEntryPlaceholder: "Allstate, Liberty Mutual, etc."
      },
      {
        id: "life_insurance",
        question: "Do you have life insurance?",
        icon: "heart.circle.fill",
        textEntryPrompt: "Which company?",
        textEntryPlaceholder: "Northwestern, MetLife, etc."
      },
      {
        id: "umbrella_insurance",
        question: "Do you have umbrella insurance?",
        icon: "umbrella.fill",
        textEntryPrompt: "Which company?",
        textEntryPlaceholder: "Usually same as auto/home"
      }
    ],
    
    review: {
      title: "Insurance Policies",
      subtitle: "Here's what we found:",
      confirmText: "Swipe right to add these tasks",
      editText: "Swipe left to make changes"
    },
    
    taskTemplate: {
      titlePrefix: "Update address:",
      category: "address_change",
      subcategory: "insurance",
      priority: 2  // Higher priority - rates change!
    }
  },
  
  // ============================================
  // FITNESS & WELLNESS
  // ============================================
  
  "address_change_fitness": {
    id: "address_change_fitness",
    title: "Fitness & Wellness",
    taskTitle: "Create fitness membership list",
    category: "address_change",
    
    intro: {
      title: "Fitness & Wellness",
      subtitle: "Let's identify memberships that need to be transferred or canceled.",
      instruction: "Swipe right if you have this membership, left if you don't."
    },
    
    questions: [
      {
        id: "gym",
        question: "Do you have a gym membership?",
        icon: "figure.strengthtraining.traditional",
        textEntryPrompt: "Which gym?",
        textEntryPlaceholder: "LA Fitness, Planet Fitness, Equinox, etc."
      },
      {
        id: "crossfit",
        question: "Are you a CrossFit member?",
        icon: "figure.cross.training",
        textEntryPrompt: "Which box?",
        textEntryPlaceholder: "CrossFit [Name]"
      },
      {
        id: "yoga",
        question: "Do you have a yoga studio membership?",
        icon: "figure.yoga",
        textEntryPrompt: "Which studio?",
        textEntryPlaceholder: "CorePower, YogaWorks, etc."
      },
      {
        id: "pilates",
        question: "Do you have a Pilates membership?",
        icon: "figure.pilates",
        textEntryPrompt: "Which studio?",
        textEntryPlaceholder: "Club Pilates, etc."
      },
      {
        id: "spin",
        question: "Do you do spin or cycling classes?",
        icon: "bicycle",
        textEntryPrompt: "Which studio?",
        textEntryPlaceholder: "SoulCycle, Peloton studio, etc."
      },
      {
        id: "pool",
        question: "Do you have a pool or swim club membership?",
        icon: "figure.pool.swim",
        textEntryPrompt: "Which pool/club?",
        textEntryPlaceholder: "YMCA, local pool, etc."
      },
      {
        id: "country_club",
        question: "Are you a country club member?",
        icon: "flag.fill",
        textEntryPrompt: "Which club?",
        textEntryPlaceholder: "Club name"
      },
      {
        id: "spa",
        question: "Do you have a spa or massage membership?",
        icon: "sparkles",
        textEntryPrompt: "Which spa?",
        textEntryPlaceholder: "Massage Envy, Hand & Stone, etc."
      }
    ],
    
    review: {
      title: "Fitness Memberships",
      subtitle: "Here's what we found:",
      confirmText: "Swipe right to add these tasks",
      editText: "Swipe left to make changes"
    },
    
    taskTemplate: {
      titlePrefix: "Cancel/transfer:",
      category: "address_change",
      subcategory: "fitness",
      priority: 1
    }
  },
  
  // ============================================
  // MEMBERSHIPS
  // ============================================
  
  "address_change_memberships": {
    id: "address_change_memberships",
    title: "Memberships",
    taskTitle: "Create membership address change list",
    category: "address_change",
    
    intro: {
      title: "Memberships",
      subtitle: "Let's catch any memberships that need your new address.",
      instruction: "Swipe right if you have this, left if you don't."
    },
    
    questions: [
      {
        id: "costco",
        question: "Do you have a Costco membership?",
        icon: "cart.fill",
        textEntryPrompt: null  // No text entry needed
      },
      {
        id: "sams",
        question: "Do you have a Sam's Club membership?",
        icon: "cart.fill",
        textEntryPrompt: null
      },
      {
        id: "bjs",
        question: "Do you have a BJ's membership?",
        icon: "cart.fill",
        textEntryPrompt: null
      },
      {
        id: "aaa",
        question: "Do you have AAA?",
        icon: "car.circle.fill",
        textEntryPrompt: null
      },
      {
        id: "amazon_prime",
        question: "Do you have Amazon Prime?",
        icon: "shippingbox.fill",
        textEntryPrompt: null
      },
      {
        id: "library",
        question: "Do you have a library card?",
        icon: "books.vertical.fill",
        textEntryPrompt: null
      },
      {
        id: "museums",
        question: "Do you have any museum memberships?",
        icon: "building.columns.fill",
        textEntryPrompt: "Which museums?",
        textEntryPlaceholder: "Science museum, art museum, etc.",
        allowMultiple: true
      },
      {
        id: "other_memberships",
        question: "Any other memberships?",
        icon: "person.crop.circle.badge.plus",
        textEntryPrompt: "What memberships?",
        textEntryPlaceholder: "Professional orgs, clubs, etc.",
        allowMultiple: true
      }
    ],
    
    review: {
      title: "Memberships",
      subtitle: "Here's what we found:",
      confirmText: "Swipe right to add these tasks",
      editText: "Swipe left to make changes"
    },
    
    taskTemplate: {
      titlePrefix: "Update address:",
      category: "address_change",
      subcategory: "memberships",
      priority: 1
    }
  },
  
  // ============================================
  // SUBSCRIPTIONS & DELIVERY
  // ============================================
  
  "address_change_subscriptions": {
    id: "address_change_subscriptions",
    title: "Subscriptions",
    taskTitle: "Create subscription address change list",
    category: "address_change",
    
    intro: {
      title: "Subscriptions & Delivery",
      subtitle: "Let's make sure nothing gets delivered to your old address!",
      instruction: "Swipe right if you subscribe to this, left if you don't."
    },
    
    questions: [
      {
        id: "meal_kit",
        question: "Do you get meal kits delivered?",
        icon: "fork.knife",
        textEntryPrompt: "Which service?",
        textEntryPlaceholder: "HelloFresh, Blue Apron, etc."
      },
      {
        id: "pet_food",
        question: "Do you get pet food or supplies delivered?",
        icon: "pawprint.fill",
        textEntryPrompt: "Which service?",
        textEntryPlaceholder: "Chewy, BarkBox, etc."
      },
      {
        id: "vitamins",
        question: "Do you subscribe to vitamins or supplements?",
        icon: "pill.fill",
        textEntryPrompt: "Which service?",
        textEntryPlaceholder: "Ritual, Care/of, etc."
      },
      {
        id: "coffee",
        question: "Do you get coffee delivered?",
        icon: "cup.and.saucer.fill",
        textEntryPrompt: "Which service?",
        textEntryPlaceholder: "Trade, Atlas, etc."
      },
      {
        id: "wine",
        question: "Are you in a wine club?",
        icon: "wineglass.fill",
        textEntryPrompt: "Which club?",
        textEntryPlaceholder: "Winc, local winery, etc."
      },
      {
        id: "beauty",
        question: "Do you get beauty products delivered?",
        icon: "sparkles",
        textEntryPrompt: "Which service?",
        textEntryPlaceholder: "Ipsy, Birchbox, etc."
      },
      {
        id: "clothing",
        question: "Do you have a clothing subscription?",
        icon: "tshirt.fill",
        textEntryPrompt: "Which service?",
        textEntryPlaceholder: "Stitch Fix, Rent the Runway, etc."
      },
      {
        id: "other_subscriptions",
        question: "Any other subscription deliveries?",
        icon: "shippingbox.fill",
        textEntryPrompt: "What subscriptions?",
        textEntryPlaceholder: "Describe your subscriptions",
        allowMultiple: true
      }
    ],
    
    review: {
      title: "Subscriptions",
      subtitle: "Here's what we found:",
      confirmText: "Swipe right to add these tasks",
      editText: "Swipe left to make changes"
    },
    
    taskTemplate: {
      titlePrefix: "Update address:",
      category: "address_change",
      subcategory: "subscriptions",
      priority: 2  // Higher priority - stuff will go to wrong address!
    }
  }
};

/**
 * Get mini-assessment workflow by ID
 */
function getMiniAssessmentWorkflow(workflowId) {
  return MINI_ASSESSMENT_WORKFLOWS[workflowId] || null;
}

/**
 * Get all mini-assessment workflow IDs
 */
function getAllMiniAssessmentIds() {
  return Object.keys(MINI_ASSESSMENT_WORKFLOWS);
}

/**
 * Check if a workflow ID is a mini-assessment
 */
function isMiniAssessment(workflowId) {
  return workflowId && workflowId.startsWith('address_change_');
}

module.exports = {
  MINI_ASSESSMENT_WORKFLOWS,
  getMiniAssessmentWorkflow,
  getAllMiniAssessmentIds,
  isMiniAssessment
};
