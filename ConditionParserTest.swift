#!/usr/bin/env swift
// ConditionParserTest.swift
// Standalone test to verify TaskConditionParser behavior
// AND the fix for array-formatted conditions from Firestore

import Foundation

// =============================================
// COPY OF TaskConditionParser for testing
// =============================================

class TaskConditionParser {

    /// Evaluates whether a task's conditions match the user's assessment
    static func evaluateConditions(_ conditions: String?, against userAssessment: [String: Any]) -> Bool {
        // If no conditions, always generate task
        guard let conditions = conditions, !conditions.isEmpty else {
            print("    📝 No conditions - auto-pass")
            return true
        }

        // Parse conditions into field groups
        let conditionMap = parseConditions(conditions)
        print("    📝 Parsed conditions: \(conditionMap)")

        // Check each field condition (AND logic between fields)
        for (fieldName, acceptableValues) in conditionMap {
            let userValue = userAssessment[fieldName]
            print("    📝 Checking field '\(fieldName)': user has '\(String(describing: userValue))', need one of \(acceptableValues)")

            // Check if user's value matches any acceptable value (OR logic within field)
            var fieldMatches = false
            for acceptableValue in acceptableValues {
                let matches = checkValueMatch(userValue: userValue, acceptableValue: acceptableValue)
                print("       🔸 '\(String(describing: userValue))' vs '\(acceptableValue)' → \(matches ? "MATCH" : "no match")")
                if matches {
                    fieldMatches = true
                    break
                }
            }

            // If any field doesn't match, return false
            if !fieldMatches {
                print("    ❌ Field '\(fieldName)' did NOT match - returning false")
                return false
            }
        }

        // All conditions met
        print("    ✅ All conditions met - returning true")
        return true
    }

    // MARK: - Private Helpers

    private static func parseConditions(_ conditions: String) -> [String: [String]] {
        var conditionMap: [String: [String]] = [:]

        let fieldConditions = conditions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        for condition in fieldConditions {
            guard condition.contains(":") else { continue }

            let parts = condition.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let fieldName = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let fieldValue = String(parts[1]).trimmingCharacters(in: .whitespaces)

            // Convert to camelCase
            let assessmentFieldName = fieldName.prefix(1).lowercased() + fieldName.dropFirst()

            if conditionMap[assessmentFieldName] == nil {
                conditionMap[assessmentFieldName] = []
            }
            conditionMap[assessmentFieldName]?.append(fieldValue)
        }

        return conditionMap
    }

    private static func checkValueMatch(userValue: Any?, acceptableValue: String) -> Bool {
        guard let userValue = userValue else {
            return false
        }

        // Handle numeric comparisons
        if acceptableValue.hasPrefix(">=") {
            guard let threshold = extractNumber(from: acceptableValue, offset: 2),
                  let userNum = toNumber(userValue) else { return false }
            return userNum >= threshold
        }

        if acceptableValue.hasPrefix("<=") {
            guard let threshold = extractNumber(from: acceptableValue, offset: 2),
                  let userNum = toNumber(userValue) else { return false }
            return userNum <= threshold
        }

        if acceptableValue.hasPrefix(">") && !acceptableValue.hasPrefix(">=") {
            guard let threshold = extractNumber(from: acceptableValue, offset: 1),
                  let userNum = toNumber(userValue) else { return false }
            return userNum > threshold
        }

        if acceptableValue.hasPrefix("<") && !acceptableValue.hasPrefix("<=") {
            guard let threshold = extractNumber(from: acceptableValue, offset: 1),
                  let userNum = toNumber(userValue) else { return false }
            return userNum < threshold
        }

        // Handle boolean comparisons
        if acceptableValue.lowercased() == "true" {
            if let boolValue = userValue as? Bool {
                return boolValue
            }
            if let stringValue = userValue as? String {
                return stringValue.lowercased() == "true"
            }
            return false
        }

        if acceptableValue.lowercased() == "false" {
            if let boolValue = userValue as? Bool {
                return !boolValue
            }
            if let stringValue = userValue as? String {
                return stringValue.lowercased() == "false"
            }
            return false
        }

        // Handle string comparisons (case-insensitive)
        let userString = String(describing: userValue).lowercased()
        let acceptableString = acceptableValue.lowercased()

        return userString == acceptableString
    }

    private static func extractNumber(from string: String, offset: Int) -> Double? {
        let numString = String(string.dropFirst(offset)).trimmingCharacters(in: .whitespaces)
        return Double(numString)
    }

    private static func toNumber(_ value: Any) -> Double? {
        if let num = value as? Double { return num }
        if let num = value as? Int { return Double(num) }
        if let num = value as? Float { return Double(num) }
        if let string = value as? String, let num = Double(string) { return num }
        return nil
    }
}

// =============================================
// SIMULATED FIRESTORE DATA RETRIEVAL (THE FIX)
// This simulates how TaskGenerationService handles conditions
// =============================================

/// Simulates getting conditions from Firestore taskData
/// This is the FIX - handles both String and Array formats
func getConditionsFromFirestore(_ taskData: [String: Any]) -> String? {
    if let conditionString = taskData["conditions"] as? String {
        return conditionString
    } else if let conditionArray = taskData["conditions"] as? [String] {
        // Convert array to comma-separated string
        return conditionArray.joined(separator: ", ")
    } else {
        return nil
    }
}

// =============================================
// TEST CASES
// =============================================

struct TestCase {
    let name: String
    let firestoreData: [String: Any]  // Simulates taskData from Firestore
    let assessment: [String: Any]
    let expected: Bool
}

let testCases: [TestCase] = [
    // =============================================
    // CRITICAL: ARRAY FORMAT FROM FIRESTORE (THE BUG)
    // =============================================
    TestCase(
        name: "🔥 ARRAY FORMAT: hasKids FALSE should FAIL ['hasKids: true'] condition",
        firestoreData: ["conditions": ["hasKids: true"], "title": "Child Task"],
        assessment: ["hasKids": false],
        expected: false
    ),
    TestCase(
        name: "🔥 ARRAY FORMAT: hasKids TRUE should PASS ['hasKids: true'] condition",
        firestoreData: ["conditions": ["hasKids: true"], "title": "Child Task"],
        assessment: ["hasKids": true],
        expected: true
    ),
    TestCase(
        name: "🔥 ARRAY FORMAT: Multiple conditions - one fails should FAIL",
        firestoreData: ["conditions": ["hasKids: true", "hasPets: true"], "title": "Family Task"],
        assessment: ["hasKids": false, "hasPets": true],
        expected: false
    ),
    TestCase(
        name: "🔥 ARRAY FORMAT: Multiple conditions - all match should PASS",
        firestoreData: ["conditions": ["hasKids: true", "hasPets: true"], "title": "Family Task"],
        assessment: ["hasKids": true, "hasPets": true],
        expected: true
    ),
    TestCase(
        name: "🔥 ARRAY FORMAT: Empty array should PASS (no conditions)",
        firestoreData: ["conditions": [], "title": "Generic Task"],
        assessment: ["hasKids": false],
        expected: true
    ),

    // =============================================
    // STRING FORMAT (Original format)
    // =============================================
    TestCase(
        name: "STRING FORMAT: hasKids FALSE should FAIL 'hasKids: true' condition",
        firestoreData: ["conditions": "hasKids: true", "title": "Child Task"],
        assessment: ["hasKids": false],
        expected: false
    ),
    TestCase(
        name: "STRING FORMAT: hasKids TRUE should PASS 'hasKids: true' condition",
        firestoreData: ["conditions": "hasKids: true", "title": "Child Task"],
        assessment: ["hasKids": true],
        expected: true
    ),

    // =============================================
    // NIL/MISSING CONDITIONS (should pass)
    // =============================================
    TestCase(
        name: "NIL CONDITIONS: Missing conditions field should PASS",
        firestoreData: ["title": "Generic Task"],
        assessment: ["hasKids": false],
        expected: true
    ),
    TestCase(
        name: "EMPTY STRING: Empty string conditions should PASS",
        firestoreData: ["conditions": "", "title": "Generic Task"],
        assessment: ["hasKids": false],
        expected: true
    ),

    // =============================================
    // OTHER CONDITIONS
    // =============================================
    TestCase(
        name: "hasPets FALSE should FAIL ['hasPets: true'] condition",
        firestoreData: ["conditions": ["hasPets: true"], "title": "Pet Task"],
        assessment: ["hasPets": false],
        expected: false
    ),
    TestCase(
        name: "moveDistance 'cross_country' should FAIL ['moveDistance: local'] condition",
        firestoreData: ["conditions": ["moveDistance: local"], "title": "Local Task"],
        assessment: ["moveDistance": "cross_country"],
        expected: false
    ),
    TestCase(
        name: "moveDistance 'local' should PASS ['moveDistance: local'] condition",
        firestoreData: ["conditions": ["moveDistance: local"], "title": "Local Task"],
        assessment: ["moveDistance": "local"],
        expected: true
    ),
]

// =============================================
// RUN TESTS
// =============================================

print("=" * 70)
print("TASK CONDITION PARSER TEST SUITE")
print("Testing ARRAY format from Firestore (THE BUG FIX)")
print("=" * 70)
print("")

var passed = 0
var failed = 0

for (index, test) in testCases.enumerated() {
    print("Test \(index + 1): \(test.name)")
    print("-" * 60)

    // Simulate getting conditions from Firestore (with the fix)
    let conditions = getConditionsFromFirestore(test.firestoreData)
    print("   Firestore raw: \(test.firestoreData["conditions"] ?? "nil")")
    print("   Converted to string: '\(conditions ?? "nil")'")

    let result = TaskConditionParser.evaluateConditions(conditions, against: test.assessment)

    if result == test.expected {
        print("✅ PASS")
        passed += 1
    } else {
        print("❌ FAIL")
        print("   Firestore data: \(test.firestoreData)")
        print("   Assessment: \(test.assessment)")
        print("   Expected: \(test.expected), Got: \(result)")
        failed += 1
    }
    print("")
}

print("=" * 70)
print("RESULTS")
print("=" * 70)
print("Passed: \(passed)/\(testCases.count)")
print("Failed: \(failed)/\(testCases.count)")

if failed > 0 {
    print("")
    print("🚨 TESTS FAILED - Bug still exists!")
    exit(1)
} else {
    print("")
    print("✅ ALL TESTS PASSED - Bug is fixed!")
    print("")
    print("SUMMARY OF FIX:")
    print("- The bug was in TaskGenerationService.swift line 51")
    print("- Original: let conditions = taskData[\"conditions\"] as? String")
    print("- Firestore stores conditions as ARRAY: [\"hasKids: true\"]")
    print("- Casting array to String returns nil, causing auto-pass!")
    print("- Fix: Check for both String AND Array formats")
    exit(0)
}

// Helper for string repeat
extension String {
    static func * (string: String, count: Int) -> String {
        return String(repeating: string, count: count)
    }
}
