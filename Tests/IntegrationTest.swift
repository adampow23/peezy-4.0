#!/usr/bin/env swift
import Foundation

// ============================================================================
// INTEGRATION TEST: Complete Pipeline Verification
//
// Simulates the full flow:
// User Assessment → getAllAssessmentData() → Condition Evaluation → Task Filtering
//
// Tests against REAL Firestore task data (from TaskCatalogSchema)
// ============================================================================

// MARK: - Copy of TaskConditionParser (for standalone testing)

class TaskConditionParser {

    static func evaluateConditions(_ conditions: [String: Any]?, against userAssessment: [String: Any]) -> Bool {
        guard let conditions = conditions, !conditions.isEmpty else {
            return true
        }

        for (fieldName, acceptableValues) in conditions {
            guard let valuesArray = acceptableValues as? [String], !valuesArray.isEmpty else {
                continue
            }

            let userValue = userAssessment[fieldName]

            if !checkValueMatches(userValue: userValue, acceptableValues: valuesArray) {
                return false
            }
        }

        return true
    }

    private static func checkValueMatches(userValue: Any?, acceptableValues: [String]) -> Bool {
        guard let userValue = userValue else {
            return acceptableValues.contains { $0.lowercased() == "nil" || $0.isEmpty }
        }

        let userValueString = stringValue(from: userValue)

        for acceptable in acceptableValues {
            if matchesValue(userString: userValueString, acceptable: acceptable) {
                return true
            }
        }

        return false
    }

    private static func stringValue(from value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "Yes" : "No"
        case let int as Int:
            return String(int)
        default:
            return String(describing: value)
        }
    }

    private static func matchesValue(userString: String, acceptable: String) -> Bool {
        if acceptable.hasPrefix(">=") {
            let numberStr = String(acceptable.dropFirst(2))
            guard let threshold = Int(numberStr), let userNumber = Int(userString) else {
                return false
            }
            return userNumber >= threshold
        }
        return userString.lowercased() == acceptable.lowercased()
    }
}

// MARK: - Simulated Assessment Data (what getAllAssessmentData() returns)

/// Simulates a user who:
/// - Has pets (AnyPets: "Yes")
/// - No kids (WhosMoving: "Just Me")
/// - Local move (MoveDistance: "Local")
/// - Renting current place (currentRentOrOwn: "Rent")
/// - Buying new place (newRentOrOwn: "Own")
/// - Current: Apartment, New: House
/// - Hiring movers, packing themselves, hiring cleaners
let userScenario1: [String: Any] = [
    "userName": "Test User",
    "MoveDistance": "Local",
    "currentRentOrOwn": "Rent",
    "currentDwellingType": "Apartment",
    "newRentOrOwn": "Own",
    "newDwellingType": "House",
    "WhosMoving": "Just Me",
    "AnyPets": "Yes",
    "HireMovers": "Hire Movers",
    "HirePackers": "Pack myself",
    "HireCleaners": "Hire Cleaners",
    "selectedMoveDate": "true"
]

/// Simulates a user who:
/// - No pets
/// - Has kids (Family)
/// - Long distance move
/// - Owns current, renting new
/// - House to Apartment
/// - Moving themselves, hiring packers
let userScenario2: [String: Any] = [
    "userName": "Family Mover",
    "MoveDistance": "Long Distance",
    "currentRentOrOwn": "Own",
    "currentDwellingType": "House",
    "newRentOrOwn": "Rent",
    "newDwellingType": "Apartment",
    "WhosMoving": "Family",
    "AnyPets": "No",
    "HireMovers": "Move Myself",
    "HirePackers": "Hire packers",
    "HireCleaners": "Clean myself",
    "selectedMoveDate": "true",
    "SchoolAgeChildren": "2"  // From children mini-assessment
]

// MARK: - Real Task Catalog Data (from Firestore export)

struct TaskData {
    let id: String
    let title: String
    let conditions: [String: [String]]
}

let realTaskCatalog: [TaskData] = [
    // Tasks with no relevant conditions (everyone or based on selectedMoveDate)
    TaskData(id: "FORWARD_MAIL_USPS", title: "Submit USPS Mail Forwarding", conditions: ["selectedMoveDate": ["true"]]),
    TaskData(id: "SCHEDULE_TIME_OFF_WORK", title: "Request Time Off for Move", conditions: ["selectedMoveDate": ["true"]]),

    // Pet tasks
    TaskData(id: "PET_OPTIONS", title: "Pet Mini-Assessment", conditions: ["AnyPets": ["Yes"]]),
    TaskData(id: "SETUP_VET", title: "Set Up New Veterinarian", conditions: ["AnyPets": ["Yes"], "MoveDistance": ["Long Distance", "Cross-Country"]]),
    TaskData(id: "TRANSFER_VET_RECORDS", title: "Transfer Vet Records", conditions: ["AnyPets": ["Yes"], "MoveDistance": ["Long Distance", "Cross-Country"]]),
    TaskData(id: "UPDATE_VET", title: "Update Existing Veterinarian", conditions: ["AnyPets": ["Yes"], "MoveDistance": ["Local"]]),

    // Children tasks
    TaskData(id: "CHILDREN_OPTIONS", title: "Children Mini-Assessment", conditions: ["WhosMoving": ["Family"]]),
    TaskData(id: "BEGIN_SCHOOL_TRANSFER", title: "Notify Current School to Begin Transfer", conditions: ["MoveDistance": ["Long Distance", "Cross-Country"], "SchoolAgeChildren": [">=1"]]),
    TaskData(id: "COA_SCHOOLS", title: "Update Address with Your Child's School", conditions: ["MoveDistance": ["Local"], "SchoolAgeChildren": [">=1"]]),
    TaskData(id: "NEW_SCHOOL_ENROLLMENT", title: "Enroll Children in New Schools", conditions: ["MoveDistance": ["Long Distance", "Cross-Country"], "SchoolAgeChildren": [">=1"]]),

    // Dwelling-based tasks
    TaskData(id: "RESERVE_ELEVATORS_OLD", title: "Reserve Elevator at Old Home", conditions: ["currentDwellingType": ["Apartment"]]),
    TaskData(id: "RESERVE_ELEVATORS_NEW", title: "Reserve Elevator at New Home", conditions: ["newDwellingType": ["Apartment"]]),
    TaskData(id: "ARRANGE_PARKING_OLD", title: "Reserve Parking at Current Home", conditions: ["currentDwellingType": ["Apartment", "Condo"]]),
    TaskData(id: "ARRANGE_PARKING_NEW", title: "Reserve Parking at New Home", conditions: ["newDwellingType": ["Apartment", "Condo"]]),

    // Ownership-based tasks
    TaskData(id: "PHOTOGRAPH_RENTAL_CONDITION", title: "Photograph Empty Rental Condition", conditions: ["currentRentOrOwn": ["Rent"]]),
    TaskData(id: "RETURN_KEY_FOBS_REMOTES", title: "Return Keys and Remotes", conditions: ["currentRentOrOwn": ["Rent"]]),
    TaskData(id: "SETUP_HOMEOWNERS_INSURANCE", title: "Set Up Homeowner's Insurance", conditions: ["newDwellingType": ["House"], "newRentOrOwn": ["Own"]]),
    TaskData(id: "CANCEL_RENTERS_INSURANCE", title: "Cancel or Update Renter's Insurance", conditions: ["currentRentOrOwn": ["Rent"], "newRentOrOwn": ["Own"]]),

    // Service-based tasks
    TaskData(id: "BOOK_MOVERS", title: "Book Professional Movers", conditions: ["HireMovers": ["Hire Movers"]]),
    TaskData(id: "RESERVE_MOVING_TRUCK", title: "Reserve DIY Moving Truck", conditions: ["HireMovers": ["Move Myself"]]),
    TaskData(id: "BUY_PACKING_SUPPLIES", title: "Buy Packing Supplies", conditions: ["HirePackers": ["Pack myself"]]),
    TaskData(id: "BOOK_PACKERS", title: "Schedule Professional Packers", conditions: ["HirePackers": ["Hire packers"]]),
    TaskData(id: "BOOK_CLEANERS", title: "Schedule Move-Out Cleaning Service", conditions: ["HireCleaners": ["Hire Cleaners"]]),
    TaskData(id: "DIY_DEEP_CLEANING", title: "Deep Clean Your Home", conditions: ["HireCleaners": ["Clean myself"]]),

    // Long distance only
    TaskData(id: "NEW_DRIVERS_LICENSE", title: "Get New Driver's License", conditions: ["MoveDistance": ["Long Distance", "Cross-Country"]]),
    TaskData(id: "REGISTER_VEHICLE", title: "Register Vehicle in New State", conditions: ["MoveDistance": ["Long Distance", "Cross-Country"]]),
    TaskData(id: "CANCEL_UTILITIES_1", title: "Cancel Utility Accounts", conditions: ["MoveDistance": ["Long Distance", "Cross-Country"]]),
    TaskData(id: "SETUP_UTILITIES", title: "Set Up New Home Utilities", conditions: ["MoveDistance": ["Long Distance", "Cross-Country"]]),

    // Local only
    TaskData(id: "TRANSFER_UTILITIES", title: "Transfer Utilities to New Home", conditions: ["MoveDistance": ["Local"]]),
    TaskData(id: "UPDATE_DRIVERS_LICENSE", title: "Update Driver's License Address", conditions: ["MoveDistance": ["Local"]])
]

// MARK: - Test Scenarios

struct IntegrationTestScenario {
    let name: String
    let userAssessment: [String: Any]
    let expectedTasks: [String]      // Task IDs that SHOULD be generated
    let forbiddenTasks: [String]     // Task IDs that should NOT be generated
}

let integrationScenarios: [IntegrationTestScenario] = [

    // SCENARIO 1: Pet owner, no kids, local move, renting→buying, apartment→house
    IntegrationTestScenario(
        name: "Local mover with pets, no kids, renting apartment → buying house",
        userAssessment: userScenario1,
        expectedTasks: [
            "FORWARD_MAIL_USPS",           // selectedMoveDate: true
            "PET_OPTIONS",                  // AnyPets: Yes
            "UPDATE_VET",                   // AnyPets: Yes + Local
            "RESERVE_ELEVATORS_OLD",        // currentDwellingType: Apartment
            "ARRANGE_PARKING_OLD",          // currentDwellingType: Apartment
            "PHOTOGRAPH_RENTAL_CONDITION",  // currentRentOrOwn: Rent
            "RETURN_KEY_FOBS_REMOTES",      // currentRentOrOwn: Rent
            "SETUP_HOMEOWNERS_INSURANCE",   // newDwellingType: House + newRentOrOwn: Own
            "CANCEL_RENTERS_INSURANCE",     // currentRentOrOwn: Rent + newRentOrOwn: Own
            "BOOK_MOVERS",                  // HireMovers: Hire Movers
            "BUY_PACKING_SUPPLIES",         // HirePackers: Pack myself
            "BOOK_CLEANERS",                // HireCleaners: Hire Cleaners
            "TRANSFER_UTILITIES",           // MoveDistance: Local
            "UPDATE_DRIVERS_LICENSE"        // MoveDistance: Local
        ],
        forbiddenTasks: [
            "CHILDREN_OPTIONS",             // WhosMoving ≠ Family
            "BEGIN_SCHOOL_TRANSFER",        // No kids
            "COA_SCHOOLS",                  // No kids
            "NEW_SCHOOL_ENROLLMENT",        // No kids
            "SETUP_VET",                    // Needs Long Distance
            "TRANSFER_VET_RECORDS",         // Needs Long Distance
            "RESERVE_ELEVATORS_NEW",        // newDwellingType ≠ Apartment
            "ARRANGE_PARKING_NEW",          // newDwellingType ≠ Apartment/Condo
            "RESERVE_MOVING_TRUCK",         // HireMovers ≠ Move Myself
            "BOOK_PACKERS",                 // HirePackers ≠ Hire packers
            "DIY_DEEP_CLEANING",            // HireCleaners ≠ Clean myself
            "NEW_DRIVERS_LICENSE",          // MoveDistance ≠ Long Distance
            "REGISTER_VEHICLE",             // MoveDistance ≠ Long Distance
            "CANCEL_UTILITIES_1",           // MoveDistance ≠ Long Distance
            "SETUP_UTILITIES"               // MoveDistance ≠ Long Distance
        ]
    ),

    // SCENARIO 2: Family with kids, no pets, long distance, owning→renting, house→apartment
    IntegrationTestScenario(
        name: "Long distance family move, no pets, owning house → renting apartment",
        userAssessment: userScenario2,
        expectedTasks: [
            "FORWARD_MAIL_USPS",           // selectedMoveDate: true
            "CHILDREN_OPTIONS",             // WhosMoving: Family
            "BEGIN_SCHOOL_TRANSFER",        // Long Distance + SchoolAgeChildren >= 1
            "NEW_SCHOOL_ENROLLMENT",        // Long Distance + SchoolAgeChildren >= 1
            "RESERVE_ELEVATORS_NEW",        // newDwellingType: Apartment
            "ARRANGE_PARKING_NEW",          // newDwellingType: Apartment
            "RESERVE_MOVING_TRUCK",         // HireMovers: Move Myself
            "BOOK_PACKERS",                 // HirePackers: Hire packers
            "DIY_DEEP_CLEANING",            // HireCleaners: Clean myself
            "NEW_DRIVERS_LICENSE",          // MoveDistance: Long Distance
            "REGISTER_VEHICLE",             // MoveDistance: Long Distance
            "CANCEL_UTILITIES_1",           // MoveDistance: Long Distance
            "SETUP_UTILITIES"               // MoveDistance: Long Distance
        ],
        forbiddenTasks: [
            "PET_OPTIONS",                  // AnyPets ≠ Yes
            "SETUP_VET",                    // AnyPets ≠ Yes
            "TRANSFER_VET_RECORDS",         // AnyPets ≠ Yes
            "UPDATE_VET",                   // AnyPets ≠ Yes
            "COA_SCHOOLS",                  // MoveDistance ≠ Local
            "RESERVE_ELEVATORS_OLD",        // currentDwellingType ≠ Apartment
            "ARRANGE_PARKING_OLD",          // currentDwellingType ≠ Apartment/Condo
            "PHOTOGRAPH_RENTAL_CONDITION",  // currentRentOrOwn ≠ Rent
            "RETURN_KEY_FOBS_REMOTES",      // currentRentOrOwn ≠ Rent
            "SETUP_HOMEOWNERS_INSURANCE",   // newRentOrOwn ≠ Own
            "CANCEL_RENTERS_INSURANCE",     // currentRentOrOwn ≠ Rent
            "BOOK_MOVERS",                  // HireMovers ≠ Hire Movers
            "BUY_PACKING_SUPPLIES",         // HirePackers ≠ Pack myself
            "BOOK_CLEANERS",                // HireCleaners ≠ Hire Cleaners
            "TRANSFER_UTILITIES",           // MoveDistance ≠ Local
            "UPDATE_DRIVERS_LICENSE"        // MoveDistance ≠ Local
        ]
    )
]

// MARK: - Run Integration Tests

func runIntegrationTests() {
    var totalPassed = 0
    var totalFailed = 0

    print(String(repeating: "=", count: 70))
    print("INTEGRATION TEST: Complete Pipeline Verification")
    print(String(repeating: "=", count: 70))
    print("")

    for scenario in integrationScenarios {
        print("📋 SCENARIO: \(scenario.name)")
        print(String(repeating: "-", count: 60))

        var scenarioPassed = 0
        var scenarioFailed = 0

        // Generate tasks based on conditions
        var generatedTaskIds: Set<String> = []

        for task in realTaskCatalog {
            let conditions: [String: Any] = task.conditions
            let shouldGenerate = TaskConditionParser.evaluateConditions(conditions, against: scenario.userAssessment)

            if shouldGenerate {
                generatedTaskIds.insert(task.id)
            }
        }

        // Check expected tasks are present
        print("\n  Expected tasks (should be generated):")
        for expectedId in scenario.expectedTasks {
            if generatedTaskIds.contains(expectedId) {
                print("    ✅ \(expectedId)")
                scenarioPassed += 1
            } else {
                print("    ❌ MISSING: \(expectedId)")
                scenarioFailed += 1
            }
        }

        // Check forbidden tasks are NOT present
        print("\n  Forbidden tasks (should NOT be generated):")
        for forbiddenId in scenario.forbiddenTasks {
            if !generatedTaskIds.contains(forbiddenId) {
                print("    ✅ Correctly excluded: \(forbiddenId)")
                scenarioPassed += 1
            } else {
                print("    ❌ WRONGLY INCLUDED: \(forbiddenId)")
                scenarioFailed += 1
            }
        }

        print("\n  Scenario result: \(scenarioPassed) passed, \(scenarioFailed) failed")
        print("")

        totalPassed += scenarioPassed
        totalFailed += scenarioFailed
    }

    print(String(repeating: "=", count: 70))
    print("FINAL RESULTS: \(totalPassed)/\(totalPassed + totalFailed) assertions passed")

    if totalFailed > 0 {
        print("🚨 \(totalFailed) ASSERTIONS FAILED")
        exit(1)
    } else {
        print("✅ ALL INTEGRATION TESTS PASSED")
        print("")
        print("Pipeline verified:")
        print("  Assessment Data → Condition Evaluation → Correct Task Filtering")
        exit(0)
    }
}

// Run tests
runIntegrationTests()
