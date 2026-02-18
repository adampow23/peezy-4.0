import Foundation

// ============================================================================
// FILE: TaskCatalogSchema.swift
// PURPOSE: Source of truth for task catalog data structures
// STATUS: READ-ONLY reference - Firestore must match this format
// LAST SYNCED: 2026-02-12
//
// MAJOR UPDATE: Assessment redesigned from mini-assessment card system to
// consolidated upfront conversational assessment. Mini-assessment parent
// tasks and individual Yes/No flags are eliminated. Services, health,
// and fitness are now multi-select tiles in the main assessment.
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
 │   {anyPets: ["Yes"]}                                                        │
 │   {hireMovers: ["Yes"]}                                                     │
 │   {moveDistance: ["Long Distance"]}                                         │
 │   {newDwellingType: ["Apartment", "Condo"]}                                 │
 │   {currentRentOrOwn: ["Rent"], newRentOrOwn: ["Own"]}                       │
 │   {fitnessWellness: ["Yoga"], moveDistance: ["Long Distance"]}                    │
 │   {healthcareProviders: ["Doctor"], moveDistance: ["Long Distance"]}              │
 │   {financialInstitutions: ["Bank Account"], moveDistance: ["Local"]}              │
 │   {isInterstate: ["Yes"]}                                                        │
 │   {schoolAgeChildren: [">=1"], moveDistance: ["Long Distance"]}                   │
 └─────────────────────────────────────────────────────────────────────────────┘

 EVALUATION LOGIC:
 1. For each key in conditions:
    a. Get user's value for that assessment field
    b. If user's value is a String:
       - Check if user's value is IN the array of acceptable values
    c. If user's value is an Array (multi-select fields):
       - Check if ANY of the user's selected values appear in the acceptable values
       - e.g., user selected ["Yoga", "Gym"], condition wants ["Yoga"] → PASS
    d. If match fails → condition FAILS
 2. ALL conditions must pass (AND logic between keys)
 3. Empty conditions {} or missing conditions → auto-PASS (task for everyone)

 SPECIAL VALUES:
 - ">=1" → Numeric comparison (user value >= 1)

 MULTI-SELECT MATCHING:
 For fields like fitnessWellness, healthcareProviders, and financialInstitutions,
 the user's assessment data contains an ARRAY of selected options. The condition
 specifies which option(s) trigger this task. If ANY user selection matches ANY
 condition value, the condition passes.

 Example:
   User data:     { fitnessWellness: ["Yoga", "Gym", "Pilates"] }
   Condition:     { fitnessWellness: ["Yoga"] }
   Result:        PASS — "Yoga" is in the user's selections

 COMPUTED FIELDS:
 Some condition fields are not directly asked in the assessment but are derived
 by the backend after assessment completion:
   - moveDistance: Computed from distance between currentAddress and newAddress.
     Under 50 miles = "Local", 50+ miles = "Long Distance".
   - isInterstate: Computed by comparing state in currentAddress vs newAddress.
     Different state = "Yes", same state = "No".
   - schoolAgeChildren: Derived from childrenAges response
   - childrenUnder5: Derived from childrenAges response
*/

struct TaskCatalogSchema {

    // MARK: - Condition Field Definitions

    /// All valid condition field names and their possible values
    /// These MUST match the keys used in AssessmentDataManager
    static let conditionFields: [String: ConditionFieldInfo] = [

        // ═══════════════════════════════════════════════════
        // DIRECT ASSESSMENT FIELDS
        // Asked directly in the conversational assessment
        // ═══════════════════════════════════════════════════

        // === DWELLING TYPES ===
        "currentDwellingType": ConditionFieldInfo(
            description: "Type of current home",
            possibleValues: ["House", "Apartment", "Condo", "Townhouse"],
            assessmentSource: .direct,
            assessmentQuestion: "What type of place is it? (current)"
        ),
        "newDwellingType": ConditionFieldInfo(
            description: "Type of new home",
            possibleValues: ["House", "Apartment", "Condo", "Townhouse"],
            assessmentSource: .direct,
            assessmentQuestion: "What kind of place? (new)"
        ),

        // === OWNERSHIP ===
        "currentRentOrOwn": ConditionFieldInfo(
            description: "Rent or own current home",
            possibleValues: ["Rent", "Own"],
            assessmentSource: .direct,
            assessmentQuestion: "Are you renting or do you own?"
        ),
        "newRentOrOwn": ConditionFieldInfo(
            description: "Rent or own new home",
            possibleValues: ["Rent", "Own"],
            assessmentSource: .direct,
            assessmentQuestion: "Renting or buying?"
        ),

        // === HOUSEHOLD ===
        "anyPets": ConditionFieldInfo(
            description: "Whether user has pets",
            possibleValues: ["Yes", "No"],
            assessmentSource: .direct,
            assessmentQuestion: "Any pets coming along?"
        ),

        // === SERVICES ===
        "hireMovers": ConditionFieldInfo(
            description: "Interested in professional movers",
            possibleValues: ["Yes", "No"],
            assessmentSource: .direct,
            assessmentQuestion: "Are you interested in getting quotes from a moving company, or planning to handle moving yourself?"
        ),
        "hirePackers": ConditionFieldInfo(
            description: "Interested in professional packers",
            possibleValues: ["Yes", "No"],
            assessmentSource: .direct,
            assessmentQuestion: "Would you like help from a professional packing team, or are you planning to pack everything yourself?"
        ),
        "hireCleaners": ConditionFieldInfo(
            description: "Interested in professional cleaning",
            possibleValues: ["Yes", "No"],
            assessmentSource: .direct,
            assessmentQuestion: "Want us to help you find a professional move-out cleaning service, or are you handling that yourself?"
        ),

        // ═══════════════════════════════════════════════════
        // MULTI-SELECT ASSESSMENT FIELDS
        // User taps all that apply from a tile grid
        // Parser must check if ANY user selection matches
        // ═══════════════════════════════════════════════════

        "financialInstitutions": ConditionFieldInfo(
            description: "Financial accounts that need address updates",
            possibleValues: ["Bank Account", "Credit Union", "Credit Card"],
            assessmentSource: .multiSelect,
            assessmentQuestion: "Which financial institutions do you need to update your address with?"
        ),

        "healthcareProviders": ConditionFieldInfo(
            description: "Healthcare providers and insurance that need updates or record transfers",
            possibleValues: ["Doctor", "Dentist", "Therapist", "Pharmacy", "Specialists",
                             "Health Insurance", "Dental Insurance", "HSA"],
            assessmentSource: .multiSelect,
            assessmentQuestion: "Any doctors, dentists, or insurance providers that need your new info?"
        ),

        "fitnessWellness": ConditionFieldInfo(
            description: "Fitness and wellness memberships that need cancellation, transfer, or setup",
            possibleValues: ["Gym", "CrossFit", "Yoga", "Pilates", "Spin/Cycling",
                             "Golf", "Massage", "Spa", "Other", "Country Club"],
            assessmentSource: .multiSelect,
            assessmentQuestion: "Any gym memberships, studios, or clubs?"
        ),

        // ═══════════════════════════════════════════════════
        // COMPUTED / DERIVED FIELDS
        // Not asked directly — calculated by backend after
        // assessment completion
        // ═══════════════════════════════════════════════════

        "moveDistance": ConditionFieldInfo(
            description: "Whether the move is over or under 50 miles — determines cancel+setup vs update tasks",
            possibleValues: ["Local", "Long Distance"],
            assessmentSource: .computed,
            assessmentQuestion: "Computed from distance between currentAddress and newAddress. Under 50 miles = Local, 50+ miles = Long Distance."
        ),

        "isInterstate": ConditionFieldInfo(
            description: "Whether the user is changing states — triggers DMV, vehicle registration",
            possibleValues: ["Yes", "No"],
            assessmentSource: .computed,
            assessmentQuestion: "Computed by comparing state component of currentAddress vs newAddress. Different state = Yes."
        ),

        "schoolAgeChildren": ConditionFieldInfo(
            description: "Count of school-age children (5-18) — derived from childrenAges",
            possibleValues: ["0", ">=1", "1", "2", "3+"],
            assessmentSource: .computed,
            assessmentQuestion: "Derived from childrenAges age group breakdown"
        ),

        "childrenUnder5": ConditionFieldInfo(
            description: "Count of children under 5 — derived from childrenAges",
            possibleValues: ["0", ">=1", "1", "2", "3+"],
            assessmentSource: .computed,
            assessmentQuestion: "Derived from childrenAges age group breakdown"
        ),
    ]

    // MARK: - Assessment Field Inventory

    /// Complete list of fields collected by the conversational assessment.
    /// Not all of these are used as condition keys — some are used for
    /// personalization, copy, or backend calculations only.
    ///
    /// Fields marked with ★ are used as condition keys in the task catalog.
    /// Fields marked with ● are used to derive condition keys.
    /// Fields marked with ○ are informational only (not used in conditions).
    static let assessmentFields: [String] = [
        "userName",              // ○ Personalization
        "moveOutDate",           // ○ Timeline calculation
        "moveInDate",            // ○ Timeline calculation
        "moveFlexibility",       // ○ Planning context
        "moveConcerns",          // ○ Priority hints
        "currentRentOrOwn",      // ★ Condition key
        "currentDwellingType",   // ★ Condition key
        "currentAddress",        // ● Used to compute moveDistance
        "currentFloor",          // ○ Logistics
        "currentElevatorAccess", // ○ Logistics
        "currentBedrooms",       // ○ Estimation
        "currentSquareFootage",  // ○ Estimation
        "currentFinishedSqFt",   // ○ Estimation (house)
        "newRentOrOwn",          // ★ Condition key
        "newDwellingType",       // ★ Condition key
        "newAddress",            // ● Used to compute moveDistance
        "newFloor",              // ○ Logistics
        "newElevatorAccess",     // ○ Logistics
        "newBedrooms",           // ○ Estimation
        "newSquareFootage",      // ○ Estimation
        "newFinishedSqFt",       // ○ Estimation (house)
        "anyChildren",           // ○ Branch gate only
        "childrenAges",          // ● Used to derive schoolAgeChildren, childrenUnder5
        "anyPets",               // ★ Condition key
        "petSelection",          // ○ Pet-specific task detail
        "hireMovers",            // ★ Condition key
        "hirePackers",           // ★ Condition key
        "hireCleaners",          // ★ Condition key
        "financialInstitutions", // ★ Condition key (multi-select)
        "healthcareProviders",   // ★ Condition key (multi-select)
        "fitnessWellness",       // ★ Condition key (multi-select)
        "howHeard",              // ○ Analytics only
    ]
}

// MARK: - Supporting Types

enum AssessmentSource {
    case direct      // Asked directly in assessment
    case multiSelect // Multi-select tile grid in assessment
    case computed    // Derived by backend after assessment
}

struct ConditionFieldInfo {
    let description: String
    let possibleValues: [String]
    let assessmentSource: AssessmentSource
    let assessmentQuestion: String
}
