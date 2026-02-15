#!/usr/bin/env swift
import Foundation

// ============================================================================
// TEST: Condition Parser V2 (Dictionary Format)
// Tests the new parser against real Firestore condition formats
// ============================================================================

// Copy of the new parser logic for standalone testing
class TaskConditionParser {

    static func evaluateConditions(_ conditions: [String: Any]?, against userAssessment: [String: Any]) -> Bool {
        guard let conditions = conditions, !conditions.isEmpty else {
            return true  // No conditions = auto-pass
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
        case let double as Double:
            return String(Int(double))
        default:
            return String(describing: value)
        }
    }

    private static func matchesValue(userString: String, acceptable: String) -> Bool {
        if acceptable.hasPrefix(">=") {
            return handleNumericComparison(userString: userString, comparison: acceptable, op: ">=")
        }
        if acceptable.hasPrefix("<=") {
            return handleNumericComparison(userString: userString, comparison: acceptable, op: "<=")
        }
        if acceptable.hasPrefix(">") && !acceptable.hasPrefix(">=") {
            return handleNumericComparison(userString: userString, comparison: acceptable, op: ">")
        }
        if acceptable.hasPrefix("<") && !acceptable.hasPrefix("<=") {
            return handleNumericComparison(userString: userString, comparison: acceptable, op: "<")
        }
        return userString.lowercased() == acceptable.lowercased()
    }

    private static func handleNumericComparison(userString: String, comparison: String, op: String) -> Bool {
        let offset = op.count
        let numberStr = String(comparison.dropFirst(offset))
        guard let threshold = Int(numberStr), let userNumber = Int(userString) else {
            return false
        }
        switch op {
        case ">=": return userNumber >= threshold
        case "<=": return userNumber <= threshold
        case ">":  return userNumber > threshold
        case "<":  return userNumber < threshold
        default:   return false
        }
    }
}

// ============================================================================
// TEST CASES (from real Firestore data via TaskCatalogSchema)
// ============================================================================

struct TestCase {
    let name: String
    let conditions: [String: Any]?
    let assessment: [String: Any]
    let expected: Bool
}

let testCases: [TestCase] = [
    // === NO CONDITIONS (auto-pass) ===
    TestCase(
        name: "Nil conditions - auto-pass",
        conditions: nil,
        assessment: ["AnyPets": "No"],
        expected: true
    ),
    TestCase(
        name: "Empty conditions - auto-pass",
        conditions: [:],
        assessment: ["AnyPets": "No"],
        expected: true
    ),

    // === SIMPLE SINGLE CONDITIONS ===
    TestCase(
        name: "AnyPets: Yes with user Yes - PASS",
        conditions: ["AnyPets": ["Yes"]],
        assessment: ["AnyPets": "Yes"],
        expected: true
    ),
    TestCase(
        name: "AnyPets: Yes with user No - FAIL",
        conditions: ["AnyPets": ["Yes"]],
        assessment: ["AnyPets": "No"],
        expected: false
    ),
    TestCase(
        name: "WhosMoving: Family with user Family - PASS",
        conditions: ["WhosMoving": ["Family"]],
        assessment: ["WhosMoving": "Family"],
        expected: true
    ),
    TestCase(
        name: "WhosMoving: Family with user Just Me - FAIL",
        conditions: ["WhosMoving": ["Family"]],
        assessment: ["WhosMoving": "Just Me"],
        expected: false
    ),

    // === OR LOGIC (multiple values in array) ===
    TestCase(
        name: "MoveDistance: [Long Distance, Cross-Country] with Long Distance - PASS",
        conditions: ["MoveDistance": ["Long Distance", "Cross-Country"]],
        assessment: ["MoveDistance": "Long Distance"],
        expected: true
    ),
    TestCase(
        name: "MoveDistance: [Long Distance, Cross-Country] with Cross-Country - PASS",
        conditions: ["MoveDistance": ["Long Distance", "Cross-Country"]],
        assessment: ["MoveDistance": "Cross-Country"],
        expected: true
    ),
    TestCase(
        name: "MoveDistance: [Long Distance, Cross-Country] with Local - FAIL",
        conditions: ["MoveDistance": ["Long Distance", "Cross-Country"]],
        assessment: ["MoveDistance": "Local"],
        expected: false
    ),

    // === AND LOGIC (multiple keys) ===
    TestCase(
        name: "AnyPets: Yes AND MoveDistance: Long Distance - both match - PASS",
        conditions: ["AnyPets": ["Yes"], "MoveDistance": ["Long Distance", "Cross-Country"]],
        assessment: ["AnyPets": "Yes", "MoveDistance": "Long Distance"],
        expected: true
    ),
    TestCase(
        name: "AnyPets: Yes AND MoveDistance: Long Distance - pets fail - FAIL",
        conditions: ["AnyPets": ["Yes"], "MoveDistance": ["Long Distance", "Cross-Country"]],
        assessment: ["AnyPets": "No", "MoveDistance": "Long Distance"],
        expected: false
    ),
    TestCase(
        name: "AnyPets: Yes AND MoveDistance: Long Distance - distance fail - FAIL",
        conditions: ["AnyPets": ["Yes"], "MoveDistance": ["Long Distance", "Cross-Country"]],
        assessment: ["AnyPets": "Yes", "MoveDistance": "Local"],
        expected: false
    ),

    // === NUMERIC COMPARISONS ===
    TestCase(
        name: "SchoolAgeChildren: >=1 with 2 children - PASS",
        conditions: ["SchoolAgeChildren": [">=1"]],
        assessment: ["SchoolAgeChildren": "2"],
        expected: true
    ),
    TestCase(
        name: "SchoolAgeChildren: >=1 with 0 children - FAIL",
        conditions: ["SchoolAgeChildren": [">=1"]],
        assessment: ["SchoolAgeChildren": "0"],
        expected: false
    ),
    TestCase(
        name: "ChildrenUnder5: >=2 with 3 children - PASS",
        conditions: ["ChildrenUnder5": [">=2"]],
        assessment: ["ChildrenUnder5": "3"],
        expected: true
    ),
    TestCase(
        name: "ChildrenUnder5: >=2 with 1 child - FAIL",
        conditions: ["ChildrenUnder5": [">=2"]],
        assessment: ["ChildrenUnder5": "1"],
        expected: false
    ),
    TestCase(
        name: "Numeric >0 with 1 - PASS",
        conditions: ["Count": [">0"]],
        assessment: ["Count": "1"],
        expected: true
    ),
    TestCase(
        name: "Numeric >0 with 0 - FAIL",
        conditions: ["Count": [">0"]],
        assessment: ["Count": "0"],
        expected: false
    ),
    TestCase(
        name: "Numeric <=5 with 3 - PASS",
        conditions: ["Count": ["<=5"]],
        assessment: ["Count": "3"],
        expected: true
    ),
    TestCase(
        name: "Numeric <=5 with 6 - FAIL",
        conditions: ["Count": ["<=5"]],
        assessment: ["Count": "6"],
        expected: false
    ),
    TestCase(
        name: "Numeric <10 with 9 - PASS",
        conditions: ["Count": ["<10"]],
        assessment: ["Count": "9"],
        expected: true
    ),
    TestCase(
        name: "Numeric <10 with 10 - FAIL",
        conditions: ["Count": ["<10"]],
        assessment: ["Count": "10"],
        expected: false
    ),

    // === CASE INSENSITIVITY ===
    TestCase(
        name: "Case insensitive: YES vs Yes - PASS",
        conditions: ["AnyPets": ["YES"]],
        assessment: ["AnyPets": "Yes"],
        expected: true
    ),
    TestCase(
        name: "Case insensitive: yes vs YES - PASS",
        conditions: ["AnyPets": ["yes"]],
        assessment: ["AnyPets": "YES"],
        expected: true
    ),

    // === DWELLING TYPES ===
    TestCase(
        name: "currentDwellingType: Apartment - PASS",
        conditions: ["currentDwellingType": ["Apartment"]],
        assessment: ["currentDwellingType": "Apartment"],
        expected: true
    ),
    TestCase(
        name: "currentDwellingType: [Apartment, Condo] with House - FAIL",
        conditions: ["currentDwellingType": ["Apartment", "Condo"]],
        assessment: ["currentDwellingType": "House"],
        expected: false
    ),

    // === OWNERSHIP ===
    TestCase(
        name: "currentRentOrOwn: Rent - PASS",
        conditions: ["currentRentOrOwn": ["Rent"]],
        assessment: ["currentRentOrOwn": "Rent"],
        expected: true
    ),
    TestCase(
        name: "currentRentOrOwn: Rent with Own - FAIL",
        conditions: ["currentRentOrOwn": ["Rent"]],
        assessment: ["currentRentOrOwn": "Own"],
        expected: false
    ),

    // === SERVICE SELECTIONS ===
    TestCase(
        name: "HireMovers: Hire Movers - PASS",
        conditions: ["HireMovers": ["Hire Movers"]],
        assessment: ["HireMovers": "Hire Movers"],
        expected: true
    ),
    TestCase(
        name: "HirePackers: Pack myself - PASS",
        conditions: ["HirePackers": ["Pack myself"]],
        assessment: ["HirePackers": "Pack myself"],
        expected: true
    ),

    // === BOOLEAN CONVERSION ===
    TestCase(
        name: "Bool true converts to Yes - PASS",
        conditions: ["AnyPets": ["Yes"]],
        assessment: ["AnyPets": true],
        expected: true
    ),
    TestCase(
        name: "Bool false converts to No - PASS",
        conditions: ["AnyPets": ["No"]],
        assessment: ["AnyPets": false],
        expected: true
    ),
    TestCase(
        name: "Bool true with No condition - FAIL",
        conditions: ["AnyPets": ["No"]],
        assessment: ["AnyPets": true],
        expected: false
    ),

    // === MISSING FIELD ===
    TestCase(
        name: "Field missing from assessment - FAIL",
        conditions: ["Yoga": ["Yes"]],
        assessment: ["AnyPets": "Yes"],  // No Yoga field
        expected: false
    ),

    // === SYSTEM FLAGS ===
    TestCase(
        name: "selectedMoveDate: true (string) - PASS",
        conditions: ["selectedMoveDate": ["true"]],
        assessment: ["selectedMoveDate": "true"],
        expected: true
    ),
    TestCase(
        name: "selectedMoveDate: false (string) - FAIL",
        conditions: ["selectedMoveDate": ["true"]],
        assessment: ["selectedMoveDate": "false"],
        expected: false
    ),

    // === INTEGER USER VALUES ===
    TestCase(
        name: "Integer user value 2 with >=1 - PASS",
        conditions: ["SchoolAgeChildren": [">=1"]],
        assessment: ["SchoolAgeChildren": 2],
        expected: true
    ),
    TestCase(
        name: "Integer user value 0 with >=1 - FAIL",
        conditions: ["SchoolAgeChildren": [">=1"]],
        assessment: ["SchoolAgeChildren": 0],
        expected: false
    ),

    // === COMPLEX MULTI-CONDITION ===
    TestCase(
        name: "Complex: Long distance + school age children + pets - all match - PASS",
        conditions: ["MoveDistance": ["Long Distance", "Cross-Country"], "SchoolAgeChildren": [">=1"], "AnyPets": ["Yes"]],
        assessment: ["MoveDistance": "Cross-Country", "SchoolAgeChildren": "2", "AnyPets": "Yes"],
        expected: true
    ),
    TestCase(
        name: "Complex: Long distance + school age children + pets - one fails - FAIL",
        conditions: ["MoveDistance": ["Long Distance", "Cross-Country"], "SchoolAgeChildren": [">=1"], "AnyPets": ["Yes"]],
        assessment: ["MoveDistance": "Cross-Country", "SchoolAgeChildren": "0", "AnyPets": "Yes"],
        expected: false
    ),

    // === MULTIPLE VALUES IN SINGLE FIELD ===
    TestCase(
        name: "Multiple acceptable values: [House, Apartment, Condo] with Condo - PASS",
        conditions: ["currentDwellingType": ["House", "Apartment", "Condo"]],
        assessment: ["currentDwellingType": "Condo"],
        expected: true
    ),
    TestCase(
        name: "Multiple acceptable values: [House, Apartment, Condo] with Townhouse - FAIL",
        conditions: ["currentDwellingType": ["House", "Apartment", "Condo"]],
        assessment: ["currentDwellingType": "Townhouse"],
        expected: false
    )
]

// ============================================================================
// RUN TESTS
// ============================================================================

var passed = 0
var failed = 0

func repeatString(_ str: String, _ count: Int) -> String {
    return String(repeating: str, count: count)
}

print(repeatString("=", 60))
print("CONDITION PARSER V2 TEST SUITE")
print("Testing [String: [String]] dictionary format")
print(repeatString("=", 60))
print("")

for test in testCases {
    let result = TaskConditionParser.evaluateConditions(test.conditions, against: test.assessment)

    if result == test.expected {
        print("✅ PASS: \(test.name)")
        passed += 1
    } else {
        print("❌ FAIL: \(test.name)")
        print("   Conditions: \(test.conditions ?? [:])")
        print("   Assessment: \(test.assessment)")
        print("   Expected: \(test.expected), Got: \(result)")
        failed += 1
    }
}

print("")
print(repeatString("=", 60))
print("RESULTS: \(passed)/\(passed + failed) passed")
if failed > 0 {
    print("🚨 \(failed) TESTS FAILED")
    exit(1)
} else {
    print("✅ ALL TESTS PASSED")
    exit(0)
}
