import Foundation

// ============================================================================
// FILE: TaskCatalogSchema.swift
// PURPOSE: Source of truth for task catalog data structures
// STATUS: READ-ONLY reference - Firestore must match this format
// LAST SYNCED: 2026-01-24
//
// This file documents the EXACT format of conditions in Firestore.
// The TaskConditionParser MUST handle all formats documented here.
// Tests MUST verify against these real formats.
// ============================================================================

// MARK: - Condition Format Documentation
/*
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ FIRESTORE CONDITION FORMAT                                                  │
 │                                                                             │
 │ Conditions are stored as DICTIONARIES (objects), not arrays of strings.    │
 │                                                                             │
 │ Format: [String: [String]]                                                  │
 │   - Key: Assessment field name (matches AssessmentDataManager keys)         │
 │   - Value: Array of acceptable values (OR logic within array)               │
 │   - Multiple keys = AND logic (all must match)                              │
 │                                                                             │
 │ Examples from real Firestore data:                                          │
 │   {AnyPets: ["Yes"]}                                                        │
 │   {WhosMoving: ["Family"]}                                                  │
 │   {MoveDistance: ["Long Distance", "Cross-Country"]}                        │
 │   {newDwellingType: ["Apartment", "Condo"]}                                 │
 │   {currentRentOrOwn: ["Rent"], newRentOrOwn: ["Own"]}                       │
 │   {MoveDistance: ["Long Distance", "Cross-Country"], SchoolAgeChildren: [">=1"]} │
 └─────────────────────────────────────────────────────────────────────────────┘

 EVALUATION LOGIC:
 1. For each key in conditions:
    - Get user's value for that assessment field
    - Check if user's value is IN the array of acceptable values
    - If user's value is NOT in array → condition FAILS
 2. ALL conditions must pass (AND logic between keys)
 3. Empty conditions {} or missing conditions → auto-PASS (task for everyone)

 SPECIAL VALUES:
 - ">=1" → Numeric comparison (user value >= 1)
 - "true" / "false" → String booleans (not Bool type)
*/

struct TaskCatalogSchema {

    // MARK: - Condition Field Definitions

    /// All valid condition field names and their possible values
    /// These MUST match the keys used in AssessmentDataManager
    static let conditionFields: [String: ConditionFieldInfo] = [

        // === MOVING BASICS ===
        "MoveDistance": ConditionFieldInfo(
            description: "How far the user is moving",
            possibleValues: ["Local", "Long Distance", "Cross-Country"],
            assessmentQuestion: "How far are you moving?"
        ),

        // === DWELLING TYPES ===
        "currentDwellingType": ConditionFieldInfo(
            description: "Type of current home",
            possibleValues: ["House", "Apartment", "Condo", "Townhouse", "Other"],
            assessmentQuestion: "What type of home are you moving FROM?"
        ),
        "newDwellingType": ConditionFieldInfo(
            description: "Type of new home",
            possibleValues: ["House", "Apartment", "Condo", "Townhouse", "Other"],
            assessmentQuestion: "What type of home are you moving TO?"
        ),

        // === OWNERSHIP ===
        "currentRentOrOwn": ConditionFieldInfo(
            description: "Rent or own current home",
            possibleValues: ["Rent", "Own"],
            assessmentQuestion: "Do you rent or own your current home?"
        ),
        "newRentOrOwn": ConditionFieldInfo(
            description: "Rent or own new home",
            possibleValues: ["Rent", "Own"],
            assessmentQuestion: "Will you rent or own your new home?"
        ),

        // === HOUSEHOLD ===
        "WhosMoving": ConditionFieldInfo(
            description: "Who is included in the move",
            possibleValues: ["Just Me", "Me and Partner", "Family", "Roommates"],
            assessmentQuestion: "Who's moving with you?"
        ),
        "AnyPets": ConditionFieldInfo(
            description: "Whether user has pets",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have any pets?"
        ),

        // === SERVICES ===
        "HireMovers": ConditionFieldInfo(
            description: "Moving method",
            possibleValues: ["Hire Movers", "Move Myself"],
            assessmentQuestion: "How do you plan to move your belongings?"
        ),
        "HirePackers": ConditionFieldInfo(
            description: "Packing method",
            possibleValues: ["Hire packers", "Pack myself"],
            assessmentQuestion: "How do you plan to pack?"
        ),
        "HireCleaners": ConditionFieldInfo(
            description: "Cleaning method",
            possibleValues: ["Hire Cleaners", "Clean myself"],
            assessmentQuestion: "How do you plan to handle move-out cleaning?"
        ),

        // === CHILDREN (from mini-assessment) ===
        "SchoolAgeChildren": ConditionFieldInfo(
            description: "Number of school-age children",
            possibleValues: ["0", ">=1", "1", "2", "3+"],
            assessmentQuestion: "How many school-age children (K-12)?"
        ),
        "ChildrenUnder5": ConditionFieldInfo(
            description: "Number of children under 5",
            possibleValues: ["0", ">=1", ">=2", "1", "2", "3+"],
            assessmentQuestion: "How many children under 5?"
        ),

        // === FITNESS & LIFESTYLE (from mini-assessments) ===
        "Gym": ConditionFieldInfo(
            description: "Has gym membership",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a gym membership?"
        ),
        "GymMembership": ConditionFieldInfo(
            description: "Has gym membership (alternate key)",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a gym membership?"
        ),
        "Crossfit": ConditionFieldInfo(
            description: "Has CrossFit membership",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a CrossFit membership?"
        ),
        "Yoga": ConditionFieldInfo(
            description: "Has yoga studio membership",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a yoga membership?"
        ),
        "Pilates": ConditionFieldInfo(
            description: "Has Pilates membership",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a Pilates membership?"
        ),
        "SpinCycling": ConditionFieldInfo(
            description: "Has spin/cycling membership",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a spin studio membership?"
        ),
        "Golf": ConditionFieldInfo(
            description: "Has golf membership",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a golf membership?"
        ),
        "Massage": ConditionFieldInfo(
            description: "Has massage membership",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a massage membership?"
        ),
        "Spa": ConditionFieldInfo(
            description: "Has spa membership",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a spa membership?"
        ),
        "OtherFitness": ConditionFieldInfo(
            description: "Has other fitness membership",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Other fitness memberships?"
        ),
        "CountryClub": ConditionFieldInfo(
            description: "Has country club membership",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a country club membership?"
        ),

        // === FINANCE (from mini-assessment) ===
        "BankAccount": ConditionFieldInfo(
            description: "Has bank account",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a bank account?"
        ),
        "CreditUnion": ConditionFieldInfo(
            description: "Has credit union account",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a credit union account?"
        ),
        "CreditCard": ConditionFieldInfo(
            description: "Has credit card",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have credit cards?"
        ),
        "InvestmentAccounts": ConditionFieldInfo(
            description: "Has investment accounts",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have investment accounts?"
        ),
        "RetirementAccounts": ConditionFieldInfo(
            description: "Has retirement accounts",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have retirement accounts (401k, IRA)?"
        ),
        "StudentLoans": ConditionFieldInfo(
            description: "Has student loans",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have student loans?"
        ),

        // === HEALTH (from mini-assessment) ===
        "Doctor": ConditionFieldInfo(
            description: "Has primary care doctor",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a primary care doctor?"
        ),
        "Dentist": ConditionFieldInfo(
            description: "Has dentist",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a dentist?"
        ),
        "Pharmacy": ConditionFieldInfo(
            description: "Uses a pharmacy",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you use a pharmacy?"
        ),
        "Specialists": ConditionFieldInfo(
            description: "Sees medical specialists",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you see any specialists?"
        ),
        "Therapy": ConditionFieldInfo(
            description: "Has therapist",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you see a therapist?"
        ),

        // === INSURANCE (from mini-assessment) ===
        "HealthInsurance": ConditionFieldInfo(
            description: "Has health insurance",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have health insurance?"
        ),
        "DentalInsurance": ConditionFieldInfo(
            description: "Has dental insurance",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have dental insurance?"
        ),
        "VisionInsurance": ConditionFieldInfo(
            description: "Has vision insurance",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have vision insurance?"
        ),
        "HealthSavingsAccount": ConditionFieldInfo(
            description: "Has HSA",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have an HSA?"
        ),
        "SupplementalInsurance": ConditionFieldInfo(
            description: "Has supplemental insurance",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have supplemental insurance?"
        ),
        "LifeInsurance": ConditionFieldInfo(
            description: "Has life insurance",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have life insurance?"
        ),
        "PetInsurance": ConditionFieldInfo(
            description: "Has pet insurance",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have pet insurance?"
        ),

        // === TECH & DELIVERY (from mini-assessments) ===
        "Amazon": ConditionFieldInfo(
            description: "Uses Amazon",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you use Amazon?"
        ),
        "DoorDash": ConditionFieldInfo(
            description: "Uses DoorDash",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you use DoorDash?"
        ),
        "Instacart": ConditionFieldInfo(
            description: "Uses Instacart",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you use Instacart?"
        ),
        "UberOne": ConditionFieldInfo(
            description: "Has Uber One",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have Uber One?"
        ),
        "Walmart": ConditionFieldInfo(
            description: "Uses Walmart delivery",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you use Walmart delivery?"
        ),
        "OtherDelivery": ConditionFieldInfo(
            description: "Uses other delivery services",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Other delivery services?"
        ),

        // === STREAMING (from mini-assessment) ===
        "Netflix": ConditionFieldInfo(
            description: "Has Netflix",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have Netflix?"
        ),
        "Hulu": ConditionFieldInfo(
            description: "Has Hulu",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have Hulu?"
        ),
        "Disney": ConditionFieldInfo(
            description: "Has Disney+",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have Disney+?"
        ),
        "HBOMax": ConditionFieldInfo(
            description: "Has HBO Max",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have HBO Max?"
        ),
        "Peacock": ConditionFieldInfo(
            description: "Has Peacock",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have Peacock?"
        ),
        "Paramount": ConditionFieldInfo(
            description: "Has Paramount+",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have Paramount+?"
        ),
        "YoutubeTV": ConditionFieldInfo(
            description: "Has YouTube TV",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have YouTube TV?"
        ),
        "OtherStreaming": ConditionFieldInfo(
            description: "Has other streaming",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Other streaming services?"
        ),

        // === OTHER TECH ===
        "AppleAccount": ConditionFieldInfo(
            description: "Has Apple account",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have an Apple account?"
        ),
        "UberAccount": ConditionFieldInfo(
            description: "Has Uber account",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you use Uber?"
        ),
        "LyftAccount": ConditionFieldInfo(
            description: "Has Lyft account",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you use Lyft?"
        ),
        "PaypalAccount": ConditionFieldInfo(
            description: "Has PayPal account",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have PayPal?"
        ),
        "VenmoAccount": ConditionFieldInfo(
            description: "Has Venmo account",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have Venmo?"
        ),
        "CashAppAccount": ConditionFieldInfo(
            description: "Has Cash App account",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have Cash App?"
        ),

        // === MEMBERSHIPS ===
        "CostcoMembership": ConditionFieldInfo(
            description: "Has Costco membership",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a Costco membership?"
        ),
        "SamsMembership": ConditionFieldInfo(
            description: "Has Sam's Club membership",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a Sam's Club membership?"
        ),

        // === VEHICLE & ADMIN ===
        "TollPass": ConditionFieldInfo(
            description: "Has toll pass",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a toll pass (EZPass, etc.)?"
        ),
        "ParkingPass": ConditionFieldInfo(
            description: "Has parking permit",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Do you have a parking permit?"
        ),
        "PetRegistration": ConditionFieldInfo(
            description: "Has pet registration",
            possibleValues: ["Yes", "No"],
            assessmentQuestion: "Is your pet registered with the city?"
        ),

        // === SYSTEM FLAGS ===
        "selectedMoveDate": ConditionFieldInfo(
            description: "User has selected a move date",
            possibleValues: ["true", "false"],
            assessmentQuestion: "(System) Has user completed date selection?"
        ),
        "PREP": ConditionFieldInfo(
            description: "User has prep tasks enabled",
            possibleValues: ["true", "false"],
            assessmentQuestion: "(System) Prep tasks enabled?"
        )
    ]

    // MARK: - Sample Tasks (for testing)

    /// Real tasks from Firestore with their exact condition formats
    static let sampleTasks: [SampleTask] = [
        // Tasks with no conditions (everyone gets these)
        SampleTask(
            id: "BOOK_MOVERS",
            title: "Book Professional Movers",
            conditions: ["HireMovers": ["Hire Movers"]],
            urgencyPercentage: 94
        ),

        // Pet-conditional task
        SampleTask(
            id: "PET_OPTIONS",
            title: "Pet Mini-Assessment",
            conditions: ["AnyPets": ["Yes"]],
            urgencyPercentage: 98
        ),

        // Children-conditional task
        SampleTask(
            id: "CHILDREN_OPTIONS",
            title: "Children Mini-Assessment",
            conditions: ["WhosMoving": ["Family"]],
            urgencyPercentage: 99
        ),

        // School task with multiple conditions
        SampleTask(
            id: "BEGIN_SCHOOL_TRANSFER",
            title: "Notify Current School to Begin Transfer",
            conditions: ["MoveDistance": ["Long Distance", "Cross-Country"], "SchoolAgeChildren": [">=1"]],
            urgencyPercentage: 82
        ),

        // Dwelling type condition
        SampleTask(
            id: "RESERVE_ELEVATORS_OLD",
            title: "Reserve Elevator at Old Home",
            conditions: ["currentDwellingType": ["Apartment"]],
            urgencyPercentage: 71
        ),

        // Ownership condition
        SampleTask(
            id: "PHOTOGRAPH_RENTAL_CONDITION",
            title: "Photograph Empty Rental Condition",
            conditions: ["CurrentRentOrOwn": ["Rent"]],
            urgencyPercentage: 4
        ),

        // Service hire condition
        SampleTask(
            id: "BUY_PACKING_SUPPLIES",
            title: "Buy Packing Supplies",
            conditions: ["HirePackers": ["Pack myself"]],
            urgencyPercentage: 85
        ),

        // Multiple ownership conditions
        SampleTask(
            id: "CANCEL_RENTERS_INSURANCE",
            title: "Cancel or Update Renter's Insurance",
            conditions: ["currentRentOrOwn": ["Rent"], "newRentOrown": ["Own"]],
            urgencyPercentage: 77
        ),

        // Long distance only
        SampleTask(
            id: "NEW_DRIVERS_LICENSE",
            title: "Get New Driver's License",
            conditions: ["MoveDistance": ["Long Distance", "Cross-Country"]],
            urgencyPercentage: 84
        ),

        // System flag condition
        SampleTask(
            id: "FORWARD_MAIL_USPS",
            title: "Submit USPS Mail Forwarding",
            conditions: ["selectedMoveDate": ["true"]],
            urgencyPercentage: 79
        ),

        // Mini-assessment subtask
        SampleTask(
            id: "SETUP_VET",
            title: "Set Up New Veterinarian",
            conditions: ["AnyPets": ["Yes"], "MoveDistance": ["Long Distance", "Cross-Country"]],
            urgencyPercentage: 61
        ),

        // Fitness condition
        SampleTask(
            id: "CANCEL_YOGA",
            title: "Cancel Yoga Studio Membership",
            conditions: ["MoveDistance": ["Long Distance", "Cross-Country"], "Yoga": ["Yes"]],
            urgencyPercentage: 87
        )
    ]
}

// MARK: - Supporting Types

struct ConditionFieldInfo {
    let description: String
    let possibleValues: [String]
    let assessmentQuestion: String
}

struct SampleTask {
    let id: String
    let title: String
    let conditions: [String: [String]]
    let urgencyPercentage: Int
}
